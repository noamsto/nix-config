{
  pkgs,
  osConfig,
  lib,
  inputs,
  ...
}: let
  desktop-packages = with pkgs; [
    bottles

    # social
    ferdium
    zoom-us

    evince # PDF Viewer
    spotify

    vlc

    # 3D modeling and animation
    blender
    freecad

    # Note taking
    obsidian

    youtube-tui
    pear-desktop

    sublime-merge

    dragon-drop
    stable.aider-chat-with-playwright # Uses stable for Playwright compatibility
    aichat
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.atlas-pro

    # Network file system support for Dolphin/file managers
    gvfs # Virtual filesystem with NFS/SMB support

    shellcheck
  ];
in {
  home.packages =
    (with pkgs; [
      # here is some command line tools I use frequently
      # feel free to add your own or remove some of them

      # fastfetch available system-wide

      # archives
      zip
      xz
      unzip
      p7zip

      # === CLI UTILITIES ===
      # ripgrep, fd, jq, bat, eza available system-wide
      ast-grep # Structural search tool using AST
      yq-go

      # networking tools
      mtr # A network diagnostic tool
      iperf3
      dnsutils # `dig` + `nslookup`
      ldns # replacement of `dig`, it provide the command `drill`
      aria2 # A lightweight multi-protocol & multi-source command-line download utility
      socat # replacement of openbsd-netcat
      nmap # A utility for network discovery and security auditing
      ipcalc # it is a calculator for the IPv4/v6 addresses

      # misc
      cowsay
      file
      which
      tree
      gnused
      gnutar
      gawk
      zstd
      gnupg

      # productivity
      hugo # static site generator
      glow # markdown previewer in terminal

      # media and archives - critical missing apps
      file-roller # archive manager (GNOME, lightweight)

      # system call monitoring
      strace # system call monitoring
      ltrace # library call monitoring
      lsof # list open files

      # system tools
      sysstat
      lm_sensors # for `sensors` command
      ethtool
      pciutils # lspci
      usbutils # lsusb

      lazygit

      gtrash
      ncdu
      dust
      sd
      procs
      tokei
      hyperfine

      # Wayland clipboard
      wl-clipboard

      # github
      gh

      # AI coding tools
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.claude-squad
      happy-coder

      nh

      # Hyprland dynamic monitor management
      inputs.hyprdynamicmonitors.packages.${pkgs.stdenv.hostPlatform.system}.default

      # Advanced touchpad gesture support
      libinput-gestures

      # Better system monitoring
      btop

      # === TEXT PROCESSING ===
      # bat available system-wide
      # delta conflicts with diff-so-fancy - using diff-so-fancy via programs.git
    ])
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages;
}
