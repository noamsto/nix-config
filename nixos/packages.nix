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

  # btop runs as the user (not sudo) so it keeps their theme. cap_perfmon serves
  # the Intel GPU panel; cap_sys_ptrace lets the detailed view read other users'
  # /proc/<pid>/smaps and makes btop root-equivalent, hence wheel-only.
  security.wrappers = lib.mkIf isPC {
    btop = {
      source = "${pkgs.btop}/bin/btop";
      capabilities = "cap_perfmon,cap_sys_ptrace+ep";
      owner = "root";
      group = "wheel";
      permissions = "u+rx,g+x";
    };
  };

  # CPU watts come from RAPL energy_uj, which the kernel keeps root-only
  # (side-channel mitigation). udev GROUP/MODE cannot target sysfs attributes,
  # so tmpfiles opens it to wheel; it reruns on switch. systemd-tmpfiles-setup
  # is not ordered after udev, so intel_rapl can load after it: the udev rule
  # reapplies the same rule then. The prefix must match the rule's path as
  # written, which %p (a /devices path) would not.
  systemd.tmpfiles.rules = lib.mkIf isPC [
    "z /sys/class/powercap/intel-rapl:*/energy_uj 0440 root wheel -"
  ];
  services.udev.extraRules = lib.mkIf isPC ''
    SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", ACTION=="add", RUN+="${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=/sys/class/powercap"
  '';
}
