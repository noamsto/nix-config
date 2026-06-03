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
    };
  };

  homebrew = {
    enable = true;
    # Install casks without the com.apple.quarantine flag, so Gatekeeper doesn't
    # prompt "X is from the internet, are you sure?" on first launch of each app.
    caskArgs.no_quarantine = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # Start conservative: "uninstall" removes undeclared casks but keeps
      # their data. Promote to "zap" only once the cask list is complete.
      cleanup = "uninstall";
    };
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
      "raycast"
      "vlc"
      # Cask, not nixpkgs: no reliable aarch64-darwin build there.
      "bambu-studio"
      # freecad: omitted — the upstream cask is malformed (two `depends_on macos`,
      # rejected by brew) and nixpkgs has no darwin build. Install the official
      # .dmg manually; re-add this cask once upstream fixes Casks/f/freecad.rb.
    ];
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
