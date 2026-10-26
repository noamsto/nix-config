{
  config,
  inputs,
  pkgs,
  self,
  ...
}: let
  hostConfigs = import ../../lib/host-configs.nix;
  host = hostConfigs.mbp-m4-pro;

  # Homebrew 7 turned `postflight_steps` into a declarative template DSL, so the
  # bare Ruby `appdir` the upstream cask interpolates is no longer a method on
  # the block — the cask dies at *load* with "unreadable: undefined local
  # variable or method 'appdir'". That aborts `brew bundle`, so every `nh darwin
  # switch` fails even though the app is installed and fine. Upstream generates
  # the file from build-brew-cask.py and hasn't respun it (v0.3.3, latest).
  # Strip the block here; the supervisor below re-does its one job (the
  # quarantine strip). Deletion is tolerant, so this no-ops once upstream fixes
  # it — at which point drop this derivation and go back to the bare input.
  homebrew-mediosz-patched = pkgs.runCommand "homebrew-mediosz-patched" {} ''
    cp -R ${inputs.homebrew-mediosz} $out
    chmod -R u+w $out
    ${pkgs.gnused}/bin/sed -i '/^  postflight_steps do$/,/^  end$/d' \
      $out/Casks/swipeaerospace.rb
  '';

  # SwipeAeroSpace connects to AeroSpace's control socket once at startup and
  # never reconnects, so an AeroSpace restart leaves it running but deaf and
  # swipes silently do nothing. Nothing recovers it: KeepAlive sees a healthy
  # process and no gesture triggers a reconnect. Exit when the socket inode
  # changes so KeepAlive relaunches us against the new AeroSpace.
  swipeaerospaceSupervisor = pkgs.writeShellScript "swipeaerospace-supervisor" ''
    sock=/tmp/bobko.aerospace-${host.username}.sock

    # Absolute path: BSD stat takes -f as a format, GNU coreutils takes it as
    # --file-system. A coreutils stat on PATH would fail here, and an unreadable
    # inode compares unequal — restarting the helper every 5s forever.
    until [ -S "$sock" ]; do sleep 1; done
    ino=$(/usr/bin/stat -f %i "$sock")

    # Took over from the cask's postflight, dropped above. The build is ad-hoc
    # signed with no Team ID, so Gatekeeper rejects it outright and a quarantined
    # bundle simply won't launch — and a LaunchAgent start has no "Open anyway"
    # prompt to fall back on. Non-recursive, matching the postflight: the flag on
    # the top-level bundle is the one that blocks exec. Absolute path because a
    # LaunchAgent PATH is not the login shell's.
    /usr/bin/xattr -d com.apple.quarantine /Applications/SwipeAeroSpace.app 2>/dev/null || true

    /Applications/SwipeAeroSpace.app/Contents/MacOS/SwipeAeroSpace &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
      sleep 5
      # Unreadable means AeroSpace is mid-restart; wait for the rebind rather
      # than treating the gap itself as a change.
      cur=$(/usr/bin/stat -f %i "$sock" 2>/dev/null) || continue
      if [ "$cur" != "$ino" ]; then
        kill "$pid"
        break
      fi
    done
    wait "$pid"
  '';
in {
  imports = [
    self.darwinModules.default
    self.darwinModules.home
    inputs.nix-homebrew.darwinModules.nix-homebrew
    # Aliases nix-darwin's /Applications/Nix Apps so Spotlight/Launchpad index them.
    inputs.mac-app-util.darwinModules.default
  ];

  # Custom options (from options.nix). hostname is readOnly, so this is its
  # single definition.
  inherit (host) username user-full-name hostname email;
  flakePath = "/Users/${host.username}/nix-config";
  nix-config = {
    ai = {
      dispatcher.localModels = import ../assets/dispatcher-local-models.nix;
      pi.modelsFile = ../assets/pi/models.json;
    };
    terminal.remoteHosts = ["tp-g6" "halo"];
    shell.hostEnvFile = "/etc/agenix/host_env.env";
    git.allowedSigners = hostConfigs.allowedSigners;
  };
  desktop.mode = host.desktop.mode;
  machine.type = host.machine.type;

  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = host.hostname;
  networking.computerName = host.hostname;

  # Fish as the login shell. nix-darwin only changes an existing account's
  # shell for a user in users.knownUsers with a matching uid — uid 501 matches
  # the pre-existing account, so activation just runs `dscl … UserShell` (no
  # account recreation). gid 20 = staff. shell resolves to the GC-stable
  # /run/current-system/sw/bin/fish.
  users.knownUsers = [host.username];
  users.users.${host.username} = {
    uid = 501;
    gid = 20;
    home = "/Users/${host.username}";
    shell = pkgs.fish;
    # Allow SSH in from the ThinkPads (shared personal key) and from halo, whose
    # session picker lists mbp. nix-darwin wires this through
    # /etc/ssh/sshd_config.d, but the sshd itself is macOS's — Remote Login must
    # be toggled on once in System Settings → Sharing; it is not declarable.
    openssh.authorizedKeys.keys = [
      hostConfigs.sshPublicKeys.noams
      hostConfigs.sshPublicKeys.halo
    ];
  };

  # Declarative Homebrew via nix-homebrew (Apple Silicon prefix /opt/homebrew).
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = host.username;
    mutableTaps = false;
    # Adopt the pre-existing official-installer Homebrew + its taps, instead of
    # nix-homebrew refusing to untap homebrew/cask (it has installed casks).
    autoMigrate = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      # mediosz/tap → SwipeAerospace (swipe-to-switch-workspace for AeroSpace).
      # Patched: upstream cask is unreadable under Homebrew 7 (see above).
      "mediosz/homebrew-tap" = homebrew-mediosz-patched;
      # nikitabobko/tap → AeroSpace itself.
      "nikitabobko/homebrew-tap" = inputs.homebrew-nikitabobko;
    };
  };

  homebrew = {
    enable = true;
    # Declare the taps nix-homebrew manages so the generated Brewfile lists them
    # and `brew bundle --cleanup` doesn't try to untap them. Without these the
    # Brewfile has no `tap` lines, so cleanup flags homebrew/cask (its casks
    # aren't full-path-pinned) for untap; the deprecated `--cleanup` flag then
    # exits nonzero — failing activation even though nothing is actually removed.
    # Short brew tap form (what cleanup compares against), mirroring
    # nix-homebrew.taps above.
    taps = [
      "homebrew/core"
      "homebrew/cask"
      "mediosz/tap"
      "nikitabobko/tap"
    ];
    # NOTE: caskArgs.no_quarantine was removed — Homebrew disabled the
    # `--[no-]quarantine` switch ("There is no replacement"), so passing it
    # fails every fresh cask install. Gatekeeper will prompt once per app on
    # first launch; clear it manually if needed (xattr -d com.apple.quarantine
    # /Applications/<App>.app, or right-click → Open).
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # Start conservative: "uninstall" removes undeclared casks but keeps
      # their data. Promote to "zap" only once the cask list is complete.
      cleanup = "uninstall";
      # Homebrew 6.0 Tap Trust blocks loading casks from non-official taps
      # (here mediosz/tap → swipeaerospace) until trusted, aborting `brew
      # bundle`. Because the generated Brewfile marks every entry `trusted:
      # true`, `brew bundle` self-grants trust on each run: it *writes*
      # trust.json and acquires a `trust.json.lock` sibling (Trust.trust! →
      # with_trust_store_lock, File::CREAT) at `$XDG_CONFIG_HOME/homebrew/`.
      # That dir must therefore be WRITABLE — a read-only store path fails with
      # `Permission denied … trust.json.lock`. brew resolves the location only
      # via XDG_CONFIG_HOME (HOMEBREW_USER_CONFIG_HOME is force-set in bin/brew
      # and not user-overridable; HOMEBREW_XDG_CONFIG_HOME is ignored), and the
      # activation `brew bundle` runs as the user via `sudo --user=… --set-home
      # env`, which strips the interactive XDG_CONFIG_HOME (=~/.config) — so
      # point it back at the user's real ~/.config. brew mkpaths the dir and
      # owns trust.json there, shared with interactive `brew bundle`.
      extraEnv.XDG_CONFIG_HOME = "/Users/${host.username}/.config";
    };
    brews = [
      "fastlane"
      # Synthesizes mouse clicks for driving the iOS Simulator (toddl's
      # `just sim-*` loop / automated UI taps). Quartz-based, macOS-only, and
      # not in nixpkgs — hence brew. Needs the terminal (kitty) granted
      # Accessibility permission to actually post events.
      "cliclick"
    ];
    casks = [
      "1password"
      "1password-cli" # op; cask (not nixpkgs) so desktop-app integration works
      "blender"
      # Chromium browser for Meet, matching Linux
      "brave-browser"
      "claude"
      # Hold-Hyper (⌘⌥) + mouse drag to move/resize windows, mirroring
      # Hyprland's SUPER+drag. AeroSpace is keyboard-only; this fills the gap.
      # Modifier + auto-start wired below (CustomUserPreferences + LaunchAgent).
      "easy-move+resize"
      "ferdium"
      "firefox"
      # Tap/hold on Caps Lock (Esc on tap, Hyper ⌘⌃⌥ on hold) for the AeroSpace
      # WM modifier — see home/darwin/karabiner.nix.
      "karabiner-elements"
      # Menu-bar caffeinate wrapper: coffee-cup icon toggles sleep prevention
      # (filled = active), replacing a hand-run `caffeinate`. Option-click for
      # timed sessions. Start-at-login + activate-on-battery via its own menu.
      "keepingyouawake"
      # CANONICAL TCC RATIONALE (kitty + aerospace below): macOS identifies an
      # app by path + signing identity, and the nixpkgs bundles are ad-hoc signed
      # (no Team ID) run straight out of /nix/store — so the identity IS the
      # hashed store path, and every version bump reads as a brand-new app whose
      # permissions must be granted again. Casks are Developer ID-signed under a
      # fixed /Applications path, so grants survive upgrades. Config still comes
      # from Nix. For kitty this covers every CLI tool run inside it, since the
      # terminal is their TCC principal (Accessibility for cliclick, Automation,
      # Full Disk Access).
      "kitty"
      "losslesscut"
      # 3-finger swipe → AeroSpace workspace (parity with Hyprland's gesture
      # swipe on the ThinkPad). From the mediosz/tap declared above.
      "mediosz/tap/swipeaerospace"
      "microsoft-teams"
      # Cask for the TCC reason above; here it's the Accessibility grant, plus
      # the Automation one the float-center osascript needs. The LaunchAgent
      # below owns startup, config stays in home/darwin/aerospace.nix.
      "nikitabobko/tap/aerospace"
      "raycast"
      # Mesh VPN. GUI/menubar variant (auto-update, browser login, native
      # daemon). CLI lives inside the bundle and isn't on PATH — symlinked
      # below so the shared fish abbreviations (tss/tsp/tsw) resolve.
      "tailscale-app"
      "vlc"
      # Cask, not nixpkgs: no reliable aarch64-darwin build there.
      "bambu-studio"
      # Cask, not nixpkgs: no darwin build upstream.
      "freecad"
    ];
  };

  # Touch ID for sudo. touchIdAuth adds pam_tid; reattach adds pam_reattach
  # FIRST so it also works inside tmux/screen (otherwise pam_tid can't reach the
  # Touch ID prompt from a detached session and silently falls back to password).
  # nix-darwin manages /etc/pam.d/sudo_local and re-includes it after macOS
  # updates reset /etc/pam.d/sudo. Note: the first sudo right after a switch
  # (the switch itself) still uses a password; Touch ID kicks in afterward.
  security.pam.services.sudo_local = {
    enable = true;
    reattach = true;
    touchIdAuth = true;
  };

  launchd.user.agents = {
    # Firefox enters Troubleshoot Mode if Option is held at launch. The AeroSpace
    # Hyper bind (cmd-alt-b) holds Option as Firefox starts, so disable the key
    # trigger session-wide. launchctl setenv exposes it to GUI (launchd) apps.
    firefox-disable-safe-mode-key = {
      command = "/bin/launchctl setenv MOZ_DISABLE_SAFE_MODE_KEY 1";
      serviceConfig.RunAtLoad = true;
    };

    # Startup for the AeroSpace cask. The Home Manager module's own agent is off
    # (programs.aerospace.launchd.enable = false) because it hardcodes the
    # store-path binary; this points at the stable /Applications bundle instead.
    # The inner binary, not `open -a`: KeepAlive needs a process to supervise.
    aerospace = {
      command = "/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    # The SwipeAeroSpace cask registers no login item, so it never auto-starts.
    # Give it a LaunchAgent mirroring AeroSpace's (RunAtLoad + KeepAlive) so the
    # swipe helper comes up at login and stays up. The supervisor wrapper also
    # brings it back when AeroSpace restarts.
    swipeaerospace = {
      command = "${swipeaerospaceSupervisor}";
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = true;
      };
    };

    # Easy Move+Resize registers no login item either. `open -a` by display name
    # (not the inner binary) survives the cask's self-updates; RunAtLoad-only —
    # no KeepAlive, since `open` exits immediately once the app is launched.
    easy-move-resize.serviceConfig = {
      ProgramArguments = ["/usr/bin/open" "-a" "Easy Move+Resize"];
      RunAtLoad = true;
    };

    # KeepingYouAwake's own "Start at Login" uses SMAppService (macOS 13+), which
    # can't be set declaratively via `defaults`. Drive it from a LaunchAgent
    # instead — same `open -a` + RunAtLoad-only pattern as easy-move-resize.
    #
    # ActivateOnLaunch is passed as an `open -a --args` launch argument (NSArgumentDomain)
    # rather than written into KeepingYouAwake's persisted defaults domain: that domain is
    # sandboxed (~/Library/Containers/info.marcel-dierkes.KeepingYouAwake/), so a `defaults
    # write` against it at activation reads as cross-app container access and macOS pops
    # the "kitty would like to access data from other apps" TCC prompt on every darwin
    # switch. The argument domain overrides the same key at launch without touching the
    # container. Quirk from KeepingYouAwake's source (NSUserDefaults+KYAKeys): the whole
    # reverse-DNS string is the *key name*, hence it repeats after the app-name arg below.
    keepingyouawake.serviceConfig = {
      ProgramArguments = [
        "/usr/bin/open"
        "-a"
        "KeepingYouAwake"
        "--args"
        "-info.marcel-dierkes.KeepingYouAwake.ActivateOnLaunch"
        "YES"
      ];
      RunAtLoad = true;
    };

    # Follow macOS Light/Dark: the watched global-prefs plist is rewritten on
    # every appearance change, firing this agent. RunAtLoad themes apps at login.
    # The script self-debounces, so unrelated global-pref writes are cheap no-ops.
    theme-watch = let
      inherit (config.home-manager.users.${host.username}.home) homeDirectory;
    in {
      serviceConfig = {
        ProgramArguments = [
          "${config.home-manager.users.${host.username}.programs.theme-toggle.package}/bin/theme-apply-macos"
        ];
        WatchPaths = ["${homeDirectory}/Library/Preferences/.GlobalPreferences.plist"];
        RunAtLoad = true;
        # Not /tmp: it is world-writable, and launchd opens these without O_EXCL,
        # so a pre-created symlink there would redirect the agent's output.
        StandardErrorPath = "${homeDirectory}/Library/Logs/theme-watch.err.log";
        StandardOutPath = "${homeDirectory}/Library/Logs/theme-watch.out.log";
      };
    };
  };

  # The tailscale-app cask ships its CLI inside the bundle (capital-T binary),
  # not on PATH. Put it on /usr/local/bin (on macOS's default PATH via
  # /etc/paths) so the shared fish abbreviations resolve.
  #
  # A symlink doesn't work: the binary derives Bundle.main from the path it was
  # invoked through, so it looks for Info.plist next to /usr/local/bin/tailscale
  # and dies with "bundleIdentifier is unknown to the registry". A wrapper
  # exec'ing the real path keeps that lookup inside the bundle.
  # rm -f first: a bare `>` would follow an old symlink into the app bundle.
  system.activationScripts.postActivation.text = ''
    mkdir -p /usr/local/bin
    rm -f /usr/local/bin/tailscale
    printf '#!/bin/sh\nexec "/Applications/Tailscale.app/Contents/MacOS/Tailscale" "$@"\n' > /usr/local/bin/tailscale
    chmod +x /usr/local/bin/tailscale
  '';

  # nix-darwin system identity + starter macOS defaults.
  # NOTE: bump stateVersion to the current nix-darwin value if the changelog
  # on the Mac says otherwise; 6 is correct as of this writing.
  system = {
    stateVersion = 6;
    primaryUser = host.username;

    # Minimal starter macOS defaults — grow over time.
    defaults = {
      NSGlobalDomain = {
        KeyRepeat = 2;
        InitialKeyRepeat = 15;
        AppleShowAllExtensions = true;
      };
      dock.autohide = true;
      finder.AppleShowAllExtensions = true;

      CustomUserPreferences = {
        # System UI language = English (was Hebrew-first). en-IL keeps Israel
        # region formatting (dates/currency) with an English interface; Hebrew
        # stays available as the 2nd language + input source. No typed nix-darwin
        # option exists for these, hence CustomUserPreferences on the global
        # domain. NOTE: takes effect after a logout/login (macOS reads it at login).
        "NSGlobalDomain" = {
          AppleLanguages = ["en-IL" "he-IL"];
          AppleLocale = "en_IL";
        };

        # Free ⌘-Space for Raycast by disabling Spotlight's hotkey (id 64;
        # parameters = space char, keycode 49, ⌘ mask). Raycast then claims the
        # combo via its onboarding. Like the languages above, macOS reads symbolic
        # hotkeys at login, so this needs a logout/login to take effect.
        "com.apple.symbolichotkeys".AppleSymbolicHotKeys."64" = {
          enabled = false;
          value = {
            parameters = [32 49 1048576];
            type = "standard";
          };
        };

        # AeroSpace's experimental menu-bar workspace indicator. i3Ordered draws
        # one box per workspace in numeric order (the "1 2" boxed style). It's
        # stored in UserDefaults, not aerospace.toml, so it lives here.
        "bobko.aerospace".displayStyle = "i3Ordered";

        # SwipeAeroSpace (the swipe→workspace cask) keeps its settings in
        # UserDefaults too. skip-empty jumps over empty workspaces; threshold is
        # the swipe sensitivity; menuBarExtraIsInserted shows its menu-bar icon.
        "club.mediosz.SwipeAeroSpace" = {
          skip-empty = true;
          threshold = 1.0;
          menuBarExtraIsInserted = true;
        };

        # Easy Move+Resize reads its modifier set from this domain at launch
        # (comma-separated string). CMD,ALT = Hyper, so hold-Hyper + left-drag
        # moves a window and hold-Hyper + right-drag resizes it. Hyper here is
        # the same ⌘⌥ as the AeroSpace keyboard binds, but mouse vs key input
        # means they never collide. Mainly useful on floating windows — dragging
        # a tiled one just gets re-tiled by AeroSpace on the next layout pass.
        "org.dmarcotte.Easy-Move-Resize".ModifierFlags = "CMD,ALT";

        # KeepingYouAwake starts caffeinating as soon as it launches, so the
        # login-item LaunchAgent yields an always-awake session with a filled
        # menu-bar cup — replacing a hand-run `caffeinate`. ActivateOnLaunch is
        # passed as a launch argument on that LaunchAgent (see its comment)
        # rather than set here, since this domain is sandboxed and writing it
        # at activation triggers a TCC "access data from other apps" prompt.
      };
    };
  };

  home-manager = {
    # Aliases Home Manager Apps (YouTube Music, …) so Spotlight/Launchpad index
    # them. No help for TCC: the trampoline only launches the store binary, and
    # that's the process macOS records permissions against.
    sharedModules = [inputs.mac-app-util.homeManagerModules.default];
    users.${host.username}.imports = [../assets/ssh-fleet.nix];
  };
}
