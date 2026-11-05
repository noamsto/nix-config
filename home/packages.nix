{inputs, ...}: {
  pkgs,
  osConfig,
  lib,
  ...
}: let
  # Electron picks its keyring backend from XDG_CURRENT_DESKTOP and doesn't
  # recognise Hyprland, so it falls back to unencrypted storage and won't keep
  # sign-in, extension secrets or env vars. The launcher maps this variable to
  # --password-store.
  claude-desktop =
    if osConfig.desktop.isHyprland
    then
      pkgs.symlinkJoin {
        name = "claude-desktop-fhs-libsecret";
        paths = [pkgs.claude-desktop-fhs];
        buildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/claude-desktop \
            --set-default CLAUDE_PASSWORD_STORE gnome-libsecret
        '';
      }
    else pkgs.claude-desktop-fhs;

  # Bambu runs under XWayland and only picks up the dark theme through
  # GTK_THEME, which Hyprland sets for apps it launches but a shell may lack or
  # hold from before a theme toggle. Set it from the color-scheme theme-toggle
  # keeps in dconf instead.
  bambu-studio = let
    launcher = pkgs.writeShellScript "bambu-studio" ''
      scheme=$(dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null)
      if [ "$scheme" = "'prefer-light'" ]; then
        export GTK_THEME=Adwaita
      else
        export GTK_THEME=Adwaita:dark
      fi
      exec ${pkgs.bambu-studio}/bin/bambu-studio "$@"
    '';
  in
    pkgs.symlinkJoin {
      name = "bambu-studio-follow-theme";
      paths = [pkgs.bambu-studio];
      postBuild = ''
        rm $out/bin/bambu-studio
        ln -s ${launcher} $out/bin/bambu-studio
      '';
    };

  desktop-packages = with pkgs; [
    # Hyprland dynamic monitor management
    inputs.hyprdynamicmonitors.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Advanced touchpad gesture support
    libinput-gestures

    # social
    ferdium
    zoom-us

    # Claude Desktop (FHS variant so MCP servers find their interpreters)
    claude-desktop

    evince # PDF Viewer

    vlc

    # 3D modeling and animation
    blender
    freecad
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

    # firefox provided by programs.firefox.enable in home/firefox/default.nix

    # Network file system support for Dolphin/file managers
    gvfs # Virtual filesystem with NFS/SMB support
  ];
  personal-packages = [
    # Steam is enabled via programs.steam.enable in nixos/desktop/default.nix
    pkgs.vinegar # Roblox Studio bootstrapper
  ];
  linux-only = with pkgs; [
    # syscall / hardware introspection — Linux kernel specific
    strace
    uftrace
    sysstat
    lm_sensors
    ethtool
    pciutils # lspci
    usbutils # lsusb
    libva-utils # vainfo — inspect VAAPI GPU codec support
    file-roller # GNOME archive manager
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
      shellcheck
      shfmt

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

      zr

      # Better system monitoring
      btop

      # === TEXT PROCESSING ===
      # bat available system-wide
      # delta conflicts with diff-so-fancy - using diff-so-fancy via programs.git
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux linux-only
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages
    # personal-packages are Linux gaming tools (Steam/vinegar) — Linux-only.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux personal-packages;
}
