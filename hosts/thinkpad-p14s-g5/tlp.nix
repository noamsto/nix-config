{
  config,
  pkgs,
  ...
}: {
  services = {
    tlp = {
      enable = true;
      settings = {
        # Battery charge thresholds (Percentage)
        START_CHARGE_THRESH_BAT0 = 40; # Start charging when below 40%
        STOP_CHARGE_THRESH_BAT0 = 80; # Stop charging at 80%

        # CPU frequency scaling
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        # CPU energy/performance policy
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "balance-power";

        # AMD CPU boost settings
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;

        # Radeon graphics power saving
        RADEON_DPM_PERF_LEVEL_ON_AC = "high";
        RADEON_DPM_PERF_LEVEL_ON_BAT = "high";

        # PCIe ASPM power saving
        PCIE_ASPM_ON_AC = "default";
        PCIE_ASPM_ON_BAT = "default";

        # Affects devices like:
        # WiFi cards
        # NVMe drives
        # Graphics cards
        # USB controllers
        # Sound cards
        RUNTIME_PM_ON_AC = "on";
        RUNTIME_PM_ON_BAT = "on";
      };
    };
  };
  # Optional: Install power management tools
  environment.systemPackages = with pkgs; [
    powertop
    acpi
    lm_sensors
  ];
}
