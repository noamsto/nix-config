{
  pkgs,
  config,
  ...
}: {
  # Set hostname
  networking.hostName = "argon-rpi4";

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

  # Swap configuration (8GB RAM system)
  # With 8GB RAM, swap is optional but can help with:
  # - Memory-intensive Nix builds
  # - Emergency OOM situations
  # - Background processes
  # Uncomment if you want swap (will be created on @swap subvolume):
  # swapDevices = [{
  #   device = "/swap/swapfile";
  #   size = 2048; # 2GB - conservative for SSD longevity
  # }];

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    nh
    nom
  ];

  # Memory optimizations for 8GB RAM system
  # More aggressive caching since we have plenty of RAM
  boot.kernel.sysctl = {
    # Use more RAM for file system cache
    "vm.vfs_cache_pressure" = 50; # Default is 100
    "vm.dirty_ratio" = 15; # Default is 20
    "vm.dirty_background_ratio" = 5; # Default is 10

    # Network optimizations with more RAM available
    "net.core.rmem_max" = 134217728; # 128MB
    "net.core.wmem_max" = 134217728; # 128MB
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";

    # Better memory management
    "vm.swappiness" = 10; # Prefer RAM over swap
  };

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
