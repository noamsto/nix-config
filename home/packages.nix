{
  pkgs,
  osConfig,
  lib,
  inputs,
  ...
}: let
  desktop-packages = with pkgs; [
    # Hyprland dynamic monitor management
    inputs.hyprdynamicmonitors.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Advanced touchpad gesture support
    libinput-gestures

    # social
    ferdium
    zoom-us

    # Claude Desktop (FHS variant so MCP servers find their interpreters)
    claude-desktop-fhs

    evince # PDF Viewer

    vlc

    # 3D modeling and animation
    blender
    # Unstable's freecad has no cache hit since the python 3.14 default bump —
    # its ifcopenshell dep rebuilds from source. Back to unstable once Hydra
    # catches up.
    stable.freecad
    # Native, not flatpak: GTK4 hands SVG icon decoding to glycin, which
    # re-spawns via `flatpak-spawn --sandbox`. On NixOS that nested sandbox
    # mounts the host root (no /usr/bin/prlimit), so the loader exits 1 and GTK
    # aborts before the window opens. https://github.com/flatpak/flatpak/issues/5973
    bambu-studio

    # Video editing
    kdePackages.kdenlive
    losslesscut-bin

    youtube-tui
    pear-desktop

    sublime-merge

    dragon-drop

    # firefox provided by programs.firefox.enable in home/desktop/default.nix
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.atlas-pro

    # Network file system support for Dolphin/file managers
    gvfs # Virtual filesystem with NFS/SMB support

    shellcheck
  ];
  personal-packages = [
    # Steam is enabled via programs.steam.enable in nixos/desktop/default.nix
    pkgs.vinegar # Roblox Studio bootstrapper
  ];
  linux-only = with pkgs; [
    # syscall / hardware introspection — Linux kernel specific
    strace
    ltrace
    sysstat
    lm_sensors
    ethtool
    pciutils # lspci
    usbutils # lsusb
    libva-utils # vainfo — inspect VAAPI GPU codec support
    file-roller # GNOME archive manager
    zr # custom flake input, Linux-only outputs
    (writeShellScriptBin "amdgpu_top" ''
      scheme=$(dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null)
      if [ "$scheme" = "'prefer-light'" ]; then
        flag="--light"
      else
        flag="--dark"
      fi
      exec ${amdgpu_top}/bin/amdgpu_top "$flag" "$@"
    '')
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

      # `cmd | osc copy` reaches the *client's* clipboard over ssh. wl-copy
      # can't: it needs a compositor, and the headless hosts have none. tmux
      # (set-clipboard + allow-passthrough, both already on) forwards the
      # OSC 52 write out to kitty.
      osc

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
      glow # markdown previewer in terminal

      # system call monitoring
      lsof # list open files

      lazygit

      gtrash
      ncdu
      dust
      sd
      procs
      tokei
      hyperfine

      # github
      gh
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.gh-repo-defaults

      # Linear from the CLI (branch → issue, PRs); also powers lazytmux enrich
      inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.linear-cli

      # Better system monitoring
      btop

      # === TEXT PROCESSING ===
      # bat available system-wide
      # delta conflicts with diff-so-fancy - using diff-so-fancy via programs.git
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux linux-only
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages
    # personal-packages are Linux gaming tools (Steam/vinegar) — Linux-only.
    ++ lib.optionals (osConfig.profile != "work" && pkgs.stdenv.hostPlatform.isLinux) personal-packages;
}
