{
  pkgs,
  config,
  ...
}: {
  # Raspberry Pi 4: 4 cores, 8GB RAM
  nix.settings = {
    max-jobs = 2;
    cores = 2; # 2x2 = 4 threads total
    max-silent-time = 14400;
    timeout = 172800;
  };

  # Network configuration - minimal systemd-networkd for headless server
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.firewall.allowedTCPPorts = [22];

  # Configure all interfaces to use DHCP
  systemd.network = {
    enable = true;
    networks = {
      # Ethernet interface
      "10-ethernet" = {
        matchConfig.Name = "eth* en*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 100;
        dhcpV6Config.RouteMetric = 100;
      };
      # WiFi interface (if present)
      "20-wireless" = {
        matchConfig.Name = "wlan*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.RouteMetric = 200;
        dhcpV6Config.RouteMetric = 200;
      };
    };
  };

  # Enable iwd for WiFi management (lightweight, no GUI dependencies)
  networking.wireless.iwd.enable = true;

  # Enable SSH for remote access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # User configuration
  users.users = {
    # Root user - needed for emergency mode access
    # SECURITY: Change this password after first boot!
    root = {
      initialPassword = "nixos";
    };

    # Normal user
    noams = {
      isNormalUser = true;
      extraGroups = ["wheel" "gpio"];
      initialPassword = "nixos";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
      ];
    };
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Swap configuration - Using ZFS zvol (configured in disko-zfs.nix)
  # swapDevices configured in disko-zfs.nix to use /dev/zvol/rpool/swap

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
