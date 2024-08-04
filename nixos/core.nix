{
  config,
  pkgs,
  username,
  user_full_name,
  ...
}: {
  imports = [
    ./networking.nix
    ./nix.nix
    ./locale.nix
  ];

  users.defaultUserShell = pkgs.zsh;

  programs = {
    zsh.enable = true;
    dconf.enable = true;
    ssh.startAgent = true;
    nix-ld.enable = true;

    # Fan and thermal control
    coolercontrol.enable = true;
    nh = {
      enable = true;
      # clean.enable = true;
      # clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/noams/nix-config";
    };
  };

  # OBS virtual Camera
  boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
  '';

  security.polkit.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  hardware.alsa.enablePersistence = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  programs.adb.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${username} = {
    isNormalUser = true;
    description = user_full_name;
    extraGroups = ["adbusers" "networkmanager" "wheel" "video"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    firefox
    dmidecode
    fastfetch
    nvd

    # python
    (python312.withPackages (ps:
      with ps;
        [
          ipython
          catppuccin
        ]
        ++ catppuccin.optional-dependencies.pygments))
  ];

  environment.shells = with pkgs; [zsh];

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.logitech.wireless.enable = true; # solaar

  services = {
    dbus.implementation = "broker";

    power-profiles-daemon.enable = true;
    # Firmware updates
    fwupd.enable = true;

    # Trim SSD
    fstrim.enable = true;
    fstrim.interval = "daily";

    # Enable CUPS to print documents.
    printing.enable = true;
    # printing.drivers = with pkgs; [splix samsung-unified-linux-driver];

    # Enable flatpak
    flatpak.enable = true;
  };

  system.activationScripts.binbash = {
    deps = ["binsh"];
    text = ''
      [ -f /bin/bash ] || ln -s /bin/sh /bin/bash
    '';
  };

  # For RaspberryPi 4 image generating
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  system.stateVersion = "23.05";
}
