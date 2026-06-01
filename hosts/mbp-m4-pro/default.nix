{inputs, ...}: let
  host = (import ../../lib/host-configs.nix).mbp-m4-pro;
in {
  imports = [
    ../../options.nix
    inputs.determinate.darwinModules.default
    inputs.nix-homebrew.darwinModules.nix-homebrew
    inputs.home-manager.darwinModules.home-manager
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
      extra-substituters = [
        "https://cache.flakehub.com"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://claude-code.cachix.org"
      ];
      extra-trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
    };
  };

  networking.hostName = host.hostname;
  networking.computerName = host.hostname;

  users.users.${host.username}.home = "/Users/${host.username}";

  # Declarative Homebrew via nix-homebrew (Apple Silicon prefix /opt/homebrew).
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = host.username;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # Start conservative: "uninstall" removes undeclared casks but keeps
      # their data. Promote to "zap" only once the cask list is complete.
      cleanup = "uninstall";
    };
    casks = [
      "1password"
      "blender"
      "claude"
      "ferdium"
      "firefox"
      "ghostty"
      "losslesscut"
      "raycast"
      "vlc"
      # Casks, not nixpkgs: neither has a reliable aarch64-darwin build.
      "bambu-studio"
      "freecad"
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
    users.${host.username} = ../../home/noams.nix;
  };
}
