{pkgs, ...}: {
  services = {
    tlp = {
      enable = false;
      settings = {
        # Battery charge thresholds (Percentage)
        START_CHARGE_THRESH_BAT0 = 40; # Start charging when below 40%
        STOP_CHARGE_THRESH_BAT0 = 80; # Stop charging at 80%

        # AMD CPU driver operation mode (for amd-pstate-epp driver)
        # "active" mode lets the processor autonomously select frequencies
        CPU_DRIVER_OPMODE_ON_AC = "active";
        CPU_DRIVER_OPMODE_ON_BAT = "active";

        # CPU frequency scaling governors
        # For amd-pstate-epp in active mode, powersave is actually performance-oriented
        CPU_SCALING_GOVERNOR_ON_AC = "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        # CPU energy/performance policy (AMD Zen 2+ with amd-pstate-epp)
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

        # AMD CPU boost settings
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;

        # AMD GPU power management (modern AMDGPU driver settings)
        # Use AMDGPU settings instead of legacy RADEON for modern APUs
        AMDGPU_ABM_LEVEL_ON_AC = 0; # Adaptive backlight management off on AC
        AMDGPU_ABM_LEVEL_ON_BAT = 3; # Max power saving on battery

        # PCIe Active State Power Management
        PCIE_ASPM_ON_AC = "default";
        PCIE_ASPM_ON_BAT = "powersupersave";

        # Runtime Power Management for PCIe devices
        RUNTIME_PM_ON_AC = "on";
        RUNTIME_PM_ON_BAT = "auto";

        # USB power management
        USB_AUTOSUSPEND = 1;
        USB_EXCLUDE_AUDIO = 1; # Prevent audio device suspension issues
        USB_EXCLUDE_BTUSB = 1; # Prevent Bluetooth issues
        USB_EXCLUDE_PHONE = 1; # Prevent phone connection issues

        # WiFi power management
        WIFI_PWR_ON_AC = "off";
        WIFI_PWR_ON_BAT = "on";

        # Bluetooth power management
        RESTORE_DEVICE_STATE_ON_STARTUP = 1;

        # Disk power management
        DISK_IDLE_SECS_ON_AC = 0; # No disk idle timeout on AC
        DISK_IDLE_SECS_ON_BAT = 2; # 2 second timeout on battery

        # SATA link power management
        SATA_LINKPWR_ON_AC = "med_power_with_dipm";
        SATA_LINKPWR_ON_BAT = "min_power";

        # NVMe power management
        NVME_APST_ENABLE = 1; # Enable Autonomous Power State Transition
      };
    };
  };

  # Install power management and monitoring tools
  environment.systemPackages = with pkgs; [
    powertop
    acpi
    lm_sensors
  ];

  # Enable AMD microcode updates
  hardware.cpu.amd.updateMicrocode = true;
}
