{
  pkgs,
  config,
  ...
}: {
  # Set hostname
  networking.hostName = "naspi-nix";

  # Raspberry Pi 4: 4 cores, 8GB RAM
  nix.settings = {
    max-jobs = 2;
    cores = 2; # 2x2 = 4 threads total
    max-silent-time = 14400;
    timeout = 172800;
  };

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

  # Swap configuration
  swapDevices = [
    {
      device = "/var/swap";
      size = 2048; # 2GB
    }
  ];

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

  system.stateVersion = "25.05";
  nixpkgs.hostPlatform = "aarch64-linux";
}
