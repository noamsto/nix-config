{
  config,
  pkgs,
  username,
  user_full_name,
  ...
}: {
  imports = [
    ./networking.nix
  ];

  users.defaultUserShell = pkgs.zsh;

  programs = {
    thefuck.enable = true;
    zsh.enable = true;
    dconf.enable = true;
    ssh.startAgent = true;
    nix-ld.enable = true;

    # Fan and thermal control
    coolercontrol.enable = true;
  };

  # OBS virtual Camera
  boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
  '';
  # Kernel
  boot.loader.grub.configurationLimit = 10;

  # do garbage collection weekly to keep disk usage low
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # To protect nix-shell agains GC (development env)
  nix.settings = {
    keep-outputs = true;
    keep-derivations = true;
  };

  # Manual optimise storage: nix-store --optimise
  # https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-optimise-store
  nix.settings.auto-optimise-store = true;

  nix.settings.builders-use-substitutes = true;

  # enable flakes globally
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Set your time zone.
  time.timeZone = "Asia/Jerusalem";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ADDRESS = "en_IL";
    LC_IDENTIFICATION = "en_IL";
    LC_MEASUREMENT = "en_IL";
    LC_MONETARY = "en_IL";
    LC_NAME = "en_IL";
    LC_NUMERIC = "en_IL";
    LC_PAPER = "en_IL";
    LC_TELEPHONE = "en_IL";
    LC_TIME = "en_IL";
  };

  # all fonts are linked to /nix/var/nix/profiles/system/sw/share/X11/fonts
  fonts = {
    # use fonts specified by user rather than default ones
    enableDefaultPackages = false;
    fontDir.enable = true;

    packages = with pkgs; [
      # icon fonts
      material-design-icons
      font-awesome

      noto-fonts
      noto-fonts-emoji
      noto-fonts-extra

      # Chinese
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif

      source-sans
      source-serif

      # nerdfonts
      (nerdfonts.override {
        fonts = [
          "FiraCode"
          "NerdFontsSymbolsOnly"
          "Ubuntu"
        ];
      })
    ];

    # user defined fonts
    # the reason there's Noto Color Emoji everywhere is to override DejaVu's
    # B&W emojis that would sometimes show instead of some Color emojis
    fontconfig.defaultFonts = {
      serif = ["Noto Serif" "Noto Color Emoji"];
      sansSerif = ["Noto Sans" "Noto Color Emoji"];
      monospace = ["Fira Code Nerd Font" "Symbols Nerd Font" "Noto Color Emoji"];
      emoji = ["Noto Color Emoji"];
    };
  };

  security.polkit.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  programs.adb.enable = true;

  security.tpm2 = {
    enable = true;
    abrmd.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${username} = {
    isNormalUser = true;
    description = user_full_name;
    extraGroups = ["adbusers" "networkmanager" "wheel" "video"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
  };

  nix.settings.trusted-users = [username];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    alejandra
    firefox
    dmidecode
    fastfetch
    nvd

    # python
    (python311.withPackages (ps:
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

  environment.shellAliases = {
    nix-rebuild-diff = ''
      sudo nixos-rebuild build --flake . && ${pkgs.nvd}/bin/nvd diff /run/current-system result
    '';
  };

  system.stateVersion = "23.05";
}
