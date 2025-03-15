{
  pkgs,
  osConfig,
  lib,
  ...
}: let
  desktop-packages = with pkgs; [
    # social
    ferdium
    zoom-us

    evince # PDF Viewer
    spotify

    vlc

    # Note taking
    obsidian

    youtube-tui
    youtube-music

    sublime-merge

  ];
  work-packages = with pkgs; [
    slack
    postman

    awscli2
    aws-sam-cli
    ssm-session-manager-plugin

    mongodb-compass

    chromium
  ];
in {
  home.packages =
    (with pkgs; [
      # here is some command line tools I use frequently
      # feel free to add your own or remove some of them

      fastfetch
      nnn # terminal file manager

      # archives
      zip
      xz
      unzip
      p7zip

      # utils
      ripgrep # recursively searches directories for a regex pattern
      jq # A lightweight and flexible command-line JSON processor
      yq-go # yaml processer https://github.com/mikefarah/yq
      eza # A modern replacement for ‘ls’
      fzf # A command-line fuzzy finder

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

      fd # find files
      ncdu # better du

      # Wayland clipboard
      wl-clipboard-rs

      # github
      gh

      nh
    ])
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages
    ++ lib.optionals (osConfig.profile == "work") work-packages;
}
