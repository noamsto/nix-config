{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.thinkpad.thinkfan;
in {
  options.hardware.thinkpad.thinkfan = {
    enable = lib.mkEnableOption "ThinkPad fan control via thinkfan";

    generation = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["gen4" "gen5" "gen6"]);
      default = null;
      example = "gen5";
      description = "ThinkPad P14s generation for sensor paths. Required when thinkfan is enabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.generation != null;
        message = "hardware.thinkpad.thinkfan.generation must be set to 'gen4' or 'gen5' when thinkfan is enabled";
      }
    ];

    # Enable thinkpad_acpi fan control
    boot.extraModprobeConfig = lib.mkDefault ''
      options thinkpad_acpi fan_control=1
    '';

    services.thinkfan = {
      enable = true;
      sensors =
        if cfg.generation == "gen6"
        then [
          # Gen6: Path-based sensor lookup (stable across reboots)
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:08.1/0000:c4:00.0/hwmon";
            indices = [1];
          }
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
            indices = [1];
          }
          {
            type = "hwmon";
            query = "/sys/devices/platform/thinkpad_hwmon/hwmon";
            indices = [1 3 6 7];
          }
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:02.1/0000:c1:00.0/nvme/nvme0";
            indices = [1];
            correction = [(-5)];
          }
          {
            type = "hwmon";
            query = "/sys/devices/virtual/thermal/thermal_zone0";
            indices = [1];
          }
        ]
        else if cfg.generation == "gen5"
        then [
          # Gen5: Path-based sensor lookup (stable across reboots)
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:08.1/0000:c4:00.0/hwmon";
            indices = [1];
          }
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
            indices = [1];
          }
          {
            type = "hwmon";
            query = "/sys/devices/platform/thinkpad_hwmon/hwmon";
            indices = [1 3 6 7];
          }
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:02.4/0000:03:00.0/nvme/nvme0";
            indices = [1];
            correction = [(-5)];
          }
          {
            type = "hwmon";
            query = "/sys/devices/virtual/thermal/thermal_zone0";
            indices = [1];
          }
        ]
        else [
          # Gen4: Name-based sensor lookup
          {
            name = "amdgpu";
            type = "hwmon";
            indices = [1];
            query = "/sys/class/hwmon";
          }
          {
            name = "k10temp";
            type = "hwmon";
            indices = [1];
            query = "/sys/class/hwmon";
          }
          {
            name = "thinkpad";
            type = "hwmon";
            indices = [1 3 6 7];
            query = "/sys/class/hwmon";
            max_errors = 10;
          }
          {
            name = "nvme";
            type = "hwmon";
            indices = [1 2 3];
            correction = [(-5) 0 0];
            query = "/sys/class/hwmon";
          }
          {
            name = "acpitz";
            type = "hwmon";
            indices = [1];
            query = "/sys/class/hwmon";
          }
        ];
      fans = [
        {
          type = "tpacpi";
          query = "/proc/acpi/ibm/fan";
        }
      ];
      # Aggressive fan curve — ramps early, wide hysteresis to prevent oscillation
      levels = [
        [0 0 50]
        [1 45 55]
        [2 50 60]
        [3 55 65]
        [4 58 70]
        [5 63 75]
        [7 68 80]
        ["level full-speed" 75 32767]
      ];
    };
  };
}
