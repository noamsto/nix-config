{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (config.desktop) isEnabled;
  inherit (config.machine) isLaptop isPC;
  core-packages = with pkgs; [
    nix-output-monitor
    vim
    wget
    git
    curl
    dmidecode

    # Fetchers
    fastfetch
    cpufetch
    ramfetch
    onefetch

    # Nix/NixOS package version diff tool
    nvd

    # Home Manager CLI for standalone configurations
    home-manager

    # === ESSENTIAL CLI UTILITIES (System-wide) ===
    ripgrep # Better grep - used by system scripts and all users
    fd # Better find - useful for system administration
    jq # JSON processing - essential for modern system scripts
    bat # Better cat with syntax highlighting - useful system-wide
    eza # Better ls - fundamental file listing for all users

    # python
    (python313.withPackages (ps:
      with ps;
        [
          ipython
          catppuccin
        ]
        ++ catppuccin.optional-dependencies.pygments))
  ];
  desktop-packages = with pkgs; [
    wlr-randr
    gpu-viewer
    wluma
    brave # Uses overlay from lib/overlays.nix for Wayland flags
    brightnessctl
    ddcutil
    ddcui # GUI for ddcutil monitor control
    i2c-tools # I2C debugging utilities for ddcutil troubleshooting
    alsa-utils # provides alsamixer for audio control
  ];
  laptop-packages = with pkgs; [
    power-profiles-daemon
    rocmPackages.rocminfo
  ];
in {
  environment.systemPackages =
    core-packages
    ++ lib.optionals
    isEnabled
    desktop-packages
    ++ lib.optionals
    isLaptop
    laptop-packages;

  # Grant btop Linux capabilities for accurate hardware monitoring
  # (memory, per-process stats, network) without requiring sudo.
  # This preserves the user's theme config unlike sudo.
  security.wrappers = lib.mkIf isPC {
    btop = {
      source = "${pkgs.btop}/bin/btop";
      capabilities = "cap_dac_read_search,cap_perfmon,cap_sys_ptrace,cap_net_raw+ep";
      owner = "root";
      group = "root";
    };
  };
}
