{
  config,
  lib,
  ...
}: let
  inherit (config.machine) isLaptop;
in {
  config = lib.mkIf isLaptop {
    services.tlp = {
      enable = true;
      settings = {
        # CPU driver: keep amd-pstate in active mode (epp)
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";

        # Governor: "powersave" on amd-pstate-epp is dynamic, not fixed-low
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        # EPP hints
        CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

        # Turbo boost
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;

        # Platform profile: controls BIOS-level STAPM/PPT power envelope
        PLATFORM_PROFILE_ON_AC = "performance";
        PLATFORM_PROFILE_ON_BAT = "low-power";

        # NVMe/disk power saving
        DISK_APM_LEVEL_ON_AC = "254";
        DISK_APM_LEVEL_ON_BAT = "128";

        # WiFi power save on battery
        WIFI_PWR_ON_AC = "off";
        WIFI_PWR_ON_BAT = "on";

        # USB autosuspend (Logitech handled by existing udev rule in pc.nix)
        USB_AUTOSUSPEND = 1;
        USB_EXCLUDE_BTUSB = 1;

        # Disable NMI watchdog (saves power)
        NMI_WATCHDOG = 0;

        # Battery charge thresholds — DISABLED until battery replacement
        # START_CHARGE_THRESH_BAT0 = 75;
        # STOP_CHARGE_THRESH_BAT0 = 80;
      };
    };

    # tlp-pd implements PPD's D-Bus API so Noctalia's power profile picker keeps working
    services.tlp.pd.enable = true;
  };
}
