{
  pkgs,
  config,
  username,
  ...
}: {
  imports = [
    ./base.nix
    ./samba.nix
    ../../nixos/xscript
  ];

  environment.systemPackages = with pkgs; [
    # Pi related
    (import ./libraspberrypi.nix {inherit pkgs;})
    raspberrypi-eeprom

    vim
    ripgrep
    git
    fd
    usbutils

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
    users.${username} = {
      isNormalUser = true;
      extraGroups = ["wheel" "gpio" "naspi"];
      hashedPasswordFile = config.age.secrets.noams_password.path;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
      ];
    };
  };

  networking = {
    enableIPv6 = false;
    interfaces."wlan0".useDHCP = true;
    wireless = {
      interfaces = ["wlan0"];
      enable = true;
      networks = {
        "Gal&Noam".psk = "0506468531";
      };
    };
  };

  # NOTE: Make sure to add key on host sshing from (ssh-add)
  security.pam.sshAgentAuth.enable = true;
  security.pam.services.sudo.sshAgentAuth = true;
  programs.ssh.startAgent = true;

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

  users.groups = {
    # Create gpio group
    gpio = {};
    naspi = {};
  };

  # do garbage collection weekly to keep disk usage low
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than +3";
  };

  # Change permissions gpio devices
  services.udev.extraRules = ''
    SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="gpio",MODE="0660"
    SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:gpio /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
    SUBSYSTEM=="gpio", KERNEL=="gpio*", ACTION=="add",RUN+="${pkgs.bash}/bin/bash -c 'chown root:gpio /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value ; chmod 660 /sys%p/active_low /sys%p/direction /sys%p/edge /sys%p/value'"
  '';

  system.stateVersion = "23.11";
}
