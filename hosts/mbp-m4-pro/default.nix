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
      extra-substituters = [
        "https://cache.flakehub.com"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://claude-code.cachix.org"
        "https://numtide.cachix.org" # llm-agents.nix (opencode, amp, claude-code) — cross-platform
      ];
      extra-trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
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
    };
  };

  homebrew = {
    enable = true;
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
    };
    brews = [
      "fastlane"
    ];
    casks = [
      "1password"
      "1password-cli" # op; cask (not nixpkgs) so desktop-app integration works
      "blender"
      "claude"
      "ferdium"
      "firefox"
      # Tap/hold on Caps Lock (Esc on tap, Hyper ⌘⌃⌥ on hold) for the AeroSpace
      # WM modifier — see home/darwin/karabiner.nix.
      "karabiner-elements"
      "losslesscut"
      # 3-finger swipe → AeroSpace workspace (parity with Hyprland's gesture
      # swipe on the ThinkPad). From the mediosz/tap declared above.
      "mediosz/tap/swipeaerospace"
      "raycast"
      "vlc"
      # Cask, not nixpkgs: no reliable aarch64-darwin build there.
      "bambu-studio"
      # freecad: omitted — the upstream cask is malformed (two `depends_on macos`,
      # rejected by brew) and nixpkgs has no darwin build. Install the official
      # .dmg manually; re-add this cask once upstream fixes Casks/f/freecad.rb.
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

  # Firefox enters Troubleshoot Mode if Option is held at launch. The AeroSpace
  # Hyper bind (cmd-alt-b) holds Option as Firefox starts, so disable the key
  # trigger session-wide. launchctl setenv exposes it to GUI (launchd) apps.
  launchd.user.agents.firefox-disable-safe-mode-key = {
    command = "/bin/launchctl setenv MOZ_DISABLE_SAFE_MODE_KEY 1";
    serviceConfig.RunAtLoad = true;
  };

  # The SwipeAeroSpace cask registers no login item, so it never auto-starts.
  # Give it a LaunchAgent mirroring AeroSpace's own (RunAtLoad + KeepAlive) so
  # the swipe helper comes up at login and stays up.
  launchd.user.agents.swipeaerospace = {
    command = "/Applications/SwipeAeroSpace.app/Contents/MacOS/SwipeAeroSpace";
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
    };
  };

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
    # Aliases Home Manager Apps (kitty, …) so Spotlight/Launchpad index them.
    sharedModules = [inputs.mac-app-util.homeManagerModules.default];
    users.${host.username} = ../../home/noams.nix;
  };
}
