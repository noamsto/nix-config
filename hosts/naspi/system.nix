{pkgs, ...}: {
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
    extraGroups = ["wheel"];
    initialPassword = "nixos";
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];

  # System configuration
  system.stateVersion = "24.05";
  nixpkgs.hostPlatform = "aarch64-linux";
}
