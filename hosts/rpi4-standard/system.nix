{
  pkgs,
  lib,
  ...
}: {
  # Set hostname
  networking.hostName = "rpi4-standard";

  # Network configuration
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false;
  };
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
    extraGroups = ["wheel" "networkmanager"];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
    ];
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Essential packages for RPi4
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    libraspberrypi
    raspberrypi-eeprom
  ];

  # Console configuration (disable for headless)
  console.enable = lib.mkDefault false;

  # System configuration
  system.stateVersion = "24.11";
}
