{
  inputs,
  pkgs,
  ...
}: let
  host = (import ../../lib/host-configs.nix).mbp-m4-pro;
in {
  imports = [
    ../../options.nix
    inputs.determinate.darwinModules.default
    inputs.nix-homebrew.darwinModules.nix-homebrew
    inputs.home-manager.darwinModules.home-manager
    # Aliases nix-darwin's /Applications/Nix Apps so Spotlight/Launchpad index them.
    inputs.mac-app-util.darwinModules.default
  ];

  # Custom options (from options.nix). Mirrors the NixOS hosts: username and
  # user-full-name ride their options.nix defaults (readOnly), hostname is the
  # single allowed definition for that readOnly option.
  inherit (host) hostname email profile;
  desktop.mode = host.desktop.mode;
  machine.type = host.machine.type;

  # nixpkgs for this host (overlays + unfree, mirrors the Linux side)
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
    overlays = import ../../lib/overlays.nix inputs;
  };

  # Determinate owns Nix; nix-darwin's nix.* options become inert (by design).
  # Caches go here (not nix.settings, which is inert under Determinate). Only
  # the cross-platform caches are useful on darwin — the Linux-specific ones
  # (hyprland, noctalia, nix-amd-ai, vicinae, yazi) are omitted.
  determinateNix = {
    enable = true;
    customSettings = {
      # An untrusted daemon user has its extra substituters / public keys
      # silently ignored, so the caches below need this to apply.
      trusted-users = [
        "root"
        host.username
      ];
      # Auto-accept flake nixConfig substituters/keys without prompting
      # (mirrors nixos/core/nix.nix). Safe: user is trusted above.
      accept-flake-config = true;
      extra-substituters = [
        "https://cache.flakehub.com"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://claude-code.cachix.org"
        "https://numtide.cachix.org" # llm-agents.nix (opencode, amp, claude-code) — cross-platform
        "https://lazytmux.cachix.org" # lazytmux (worktrunk/tmux) — cross-platform
      ];
      extra-trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
        "lazytmux.cachix.org-1:8P28D3LZAKqPlkEGKzRRU9gon3rgBv4u8/4VWRn6TCg="
      ];
    };
  };

  # Fonts (mirrors nixos/core/locale.nix). NixOS installs these system-wide via
  # fonts.packages; darwin needs its own declaration or terminals can't find
  # "FiraCode Nerd Font". nix-darwin installs these into /Library/Fonts.
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    nerd-fonts.ubuntu
  ];

  # Essential CLI tools. On NixOS these come from nixos/packages.nix
  # (environment.systemPackages, "available system-wide"), which darwin doesn't
  # import — so home/packages.nix omits them and they'd otherwise be missing on
  # the Mac. Mirror the cross-platform core here. (TODO: factor into a shared
  # lib/ list imported by both, to prevent drift.)
  environment.systemPackages = with pkgs; [
    ripgrep # rg
    fd
    jq
    bat
    eza
    fastfetch
    onefetch
    nvd
    wget
    # iOS debug bridge companion daemon — drives iOS Simulator programmatically
    # (idb_companion binary + idb CLI shim). nixpkgs ships the prebuilt
    # universal binary (v1.1.8) for both x86_64-darwin and aarch64-darwin.
    # The Python gRPC client (fb-idb on PyPI) is not in nixpkgs; install it
    # imperatively: pipx install fb-idb
    idb-companion
  ];

  networking.hostName = host.hostname;
  networking.computerName = host.hostname;

  # Fish as the login shell. programs.fish.enable wires up system-wide fish
  # (completions, /etc/shells). nix-darwin only changes an existing account's
  # shell for a user in users.knownUsers with a matching uid — uid 501 matches
  # the pre-existing account, so activation just runs `dscl … UserShell` (no
  # account recreation). gid 20 = staff. shell resolves to the GC-stable
  # /run/current-system/sw/bin/fish.
  programs.fish.enable = true;
  users.knownUsers = [host.username];
  users.users.${host.username} = {
    uid = 501;
    gid = 20;
    home = "/Users/${host.username}";
    shell = pkgs.fish;
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
      "mediosz/homebrew-tap" = inputs.homebrew-mediosz;
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
    # swipe helper comes up at login and stays up.
    swipeaerospace = {
      command = "/Applications/SwipeAeroSpace.app/Contents/MacOS/SwipeAeroSpace";
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
    # instead — same `open -a` + RunAtLoad-only pattern as easy-move-resize. It
    # comes up caffeinating because ActivateOnLaunch is set below.
    keepingyouawake.serviceConfig = {
      ProgramArguments = ["/usr/bin/open" "-a" "KeepingYouAwake"];
      RunAtLoad = true;
    };
  };

  # The tailscale-app cask ships its CLI inside the bundle (capital-T binary),
  # not on PATH. Symlink it to /usr/local/bin (on macOS's default PATH via
  # /etc/paths) so the shared fish abbreviations resolve. ln -sf tolerates the
  # target not existing yet on the very first switch — it resolves once brew
  # finishes installing the .pkg.
  system.activationScripts.postActivation.text = ''
    mkdir -p /usr/local/bin
    ln -sf "/Applications/Tailscale.app/Contents/MacOS/Tailscale" /usr/local/bin/tailscale
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
        AppleInterfaceStyle = "Dark";
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
        # login-item LaunchAgent above yields an always-awake session with a
        # filled menu-bar cup — replacing a hand-run `caffeinate`. Quirk from
        # its source (NSUserDefaults+KYAKeys): the whole reverse-DNS string is
        # the *key name*, stored inside the app's own domain — hence the domain
        # prefix repeats as domain and key.
        "info.marcel-dierkes.KeepingYouAwake"."info.marcel-dierkes.KeepingYouAwake.ActivateOnLaunch" = true;
      };
    };
  };

  # System-integrated Home Manager. osConfig is auto-injected as this darwin
  # config, so the shared home/ modules read desktop.mode/profile/username
  # exactly as on NixOS.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = {inherit inputs;};
    # Aliases Home Manager Apps (YouTube Music, …) so Spotlight/Launchpad index
    # them. No help for TCC: the trampoline only launches the store binary, and
    # that's the process macOS records permissions against.
    sharedModules = [inputs.mac-app-util.homeManagerModules.default];
    users.${host.username} = ../../home/noams.nix;
  };
}
