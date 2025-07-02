{
  pkgs,
  config,
  ...
}: {
  # Set hostname
  networking.hostName = "naspi";

  # Network configuration
  networking.networkmanager.enable = true;
  networking.firewall.allowedTCPPorts = [22];

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # User configuration
  users.users.noams = {
    isNormalUser = true;
    extraGroups = ["wheel" "gpio"];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
    ];
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    nh
    nom
  ];

  # System configuration

  system.nixos.tags = let
    cfg = config.boot.loader.raspberryPi;
  in [
    "raspberry-pi-${cfg.variant}"
    cfg.bootloader
    config.boot.kernelPackages.kernel.version
  ];

  system.stateVersion = "24.05";
  nixpkgs.hostPlatform = "aarch64-linux";
}
