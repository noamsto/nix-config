{
  pkgs,
  config,
  username,
  ...
}: {
  imports = [
    ./base.nix
    ../../nixos/xscript
  ];

  environment.systemPackages = with pkgs; [
    # Pi related
    # libraspberrypi
    (import ./libraspberrypi.nix {inherit pkgs;})
    raspberrypi-eeprom

    vim
    ripgrep
    git
    fd

    # python
    (python311.withPackages (
      ps:
        with ps; [ipython]
    ))
  ];

  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;
  console.enable = false;

  services.openssh.enable = true;
  networking.hostName = "naspi";
  users = {
    users.noams = {
      # password = "admin";
      isNormalUser = true;
      extraGroups = ["wheel"];
      hashedPasswordFile = config.age.secrets.noams_password.path;
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

  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  system.stateVersion = "23.11";
}
