{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    vim
    git
    libraspberrypi
    raspberrypi-eeprom
  ];
  services.openssh.enable = true;
  networking.hostName = "naspi";
  users = {
    users.noams = {
      password = "admin";
      isNormalUser = true;
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
      ];
    };
  };
  networking = {
    interfaces."wlan0".useDHCP = true;
    wireless = {
      interfaces = ["wlan0"];
      enable = true;
      networks = {
        "Gal&Noam".psk = "0506468531";
      };
    };
  };

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
  disabledModules = ["profiles/base.nix"];
  system.stateVersion = "23.11";
}
