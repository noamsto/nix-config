{inputs, ...}: let
  host = (import ../../lib/host-configs.nix).mbp-m4-pro;
in {
  imports = [
    ../../options.nix
    inputs.determinate.darwinModules.default
    inputs.nix-homebrew.darwinModules.nix-homebrew
    inputs.home-manager.darwinModules.home-manager
  ];

  # Custom options (from options.nix)
  inherit (host) username user-full-name email hostname profile;
  desktop.mode = host.desktop.mode;
  machine.type = host.machine.type;

  # nixpkgs for this host (overlays + unfree, mirrors the Linux side)
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
    overlays = import ../../lib/overlays.nix inputs;
  };

  # Determinate owns Nix; nix-darwin's nix.* options become inert (by design).
  determinateNix.enable = true;

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
      "claude"
      "ghostty"
      "firefox"
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
