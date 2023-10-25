{
  config,
  pkgs,
  inputs,
  username,
  user_full_name,
  user_email,
  system,
  ...
}: {
  imports = [
    ./vim
  ];
  programs.thefuck.enable = true;
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  programs.dconf.enable = true;
  programs.ssh.startAgent = true;

  # boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.grub.configurationLimit = 10;
  # do garbage collection weekly to keep disk usage low
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 3d";
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

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [splix samsung-unified-linux-driver];

  networking.firewall.enable = false;
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # For discovering zero-conf network sharing
  services.avahi.enable = true;

  services.resolved.enable = true;

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

      source-sans
      source-serif

      # nerdfonts
      (nerdfonts.override {
        fonts = [
          "FiraCode"
          # "NerdFontsSymbolsOnly"
        ];
      })
    ];

    # user defined fonts
    # the reason there's Noto Color Emoji everywhere is to override DejaVu's
    # B&W emojis that would sometimes show instead of some Color emojis
    fontconfig.defaultFonts = {
      serif = ["Noto Serif" "Noto Color Emoji"];
      sansSerif = ["Noto Sans" "Noto Color Emoji"];
      monospace = ["Fira Code Nerd Font" "Noto Color Emoji"];
      emoji = ["Noto Color Emoji"];
    };
  };

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${username} = {
    isNormalUser = true;
    description = user_full_name;
    extraGroups = ["networkmanager" "wheel"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
    packages = with pkgs; [
      firefox-wayland
      kate
      #  thunderbird
    ];
  };

  nix.settings.trusted-users = [username];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    curl
    alejandra
    xclip

    # python
    (python311.withPackages (ps:
      with ps; [
        ipython
        requests
      ]))
  ];

  environment.shells = with pkgs; [zsh];

  # enable bluetooth & gui paring tools - blueman
  # or you can use cli:
  # $ bluetoothctl
  # [bluetooth] # power on
  # [bluetooth] # agent on
  # [bluetooth] # default-agent
  # [bluetooth] # scan on
  # ...put device in pairing mode and wait [hex-address] to appear here...
  # [bluetooth] # pair [hex-address]
  # [bluetooth] # connect [hex-address]
  # Bluetooth devices automatically connect with bluetoothctl as well:
  # [bluetooth] # trust [hex-address]
  hardware.bluetooth.enable = true;
  # services.blueman.enable = true;

  services.power-profiles-daemon.enable = true;

  # security with polkit
  security.polkit.enable = true;

  services = {
    dbus.packages = [pkgs.gcr];
    geoclue2.enable = true;

    udev.packages = with pkgs; [
      platformio # udev rules for platformio
      android-udev-rules
    ];
  };

  services.openssh.enable = true;

  xdg = {
    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
      ];
    };
  };

  system.stateVersion = "23.05"; # Did you read the comment?
}
