{
  pkgs,
  osConfig,
  lib,
  inputs,
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

    dragon-drop
    stable.aider-chat-with-playwright # Uses stable for Playwright compatibility
    aichat
    inputs.self.packages.${pkgs.system}.atlas-pro
  ];
  work-packages = with pkgs; [
    slack

    awscli2
    aws-sam-cli
    ssm-session-manager-plugin

    chromium
    claude-code
    nur.repos.charmbracelet.crush
    stable.postman # Uses stable for API testing reliability
    ngrok
    dbeaver-bin
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
      mpv # video/audio player
      kdePackages.ark # archive manager

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

      nh

      # Better system monitoring
      btop

      # === TEXT PROCESSING ===
      # bat available system-wide
      # delta conflicts with diff-so-fancy - using diff-so-fancy via programs.git

      inputs.mcp-hub.packages."${pkgs.system}".default
    ])
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages
    ++ lib.optionals (osConfig.profile == "work") work-packages;
}
