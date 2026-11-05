{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.ms-s1-max.fanCurve;

  # The board exposes no hwmon PWM or ACPI fan; the EC drives both fans from
  # two curve tables in its RAM, which it re-reads live. Map from
  # github.com/raimondomartire/ms-s1-max-fans-control (docs/EC-MAP.md),
  # confirmed against a dump on BIOS 1.11 / EC 0.17.
  tableOffsets = [
    17 # 0x11, fan 1
    49 # 0x31, fan 2
  ];

  # 7 records of [upper °C, lower °C, duty %]; lower repeats the previous
  # record's upper, as in the stock table.
  table = lib.concatLists (lib.imap0 (i: p: [
      p.temp
      (
        if i == 0
        then 0
        else (lib.elemAt cfg.points (i - 1)).temp
      )
      p.duty
    ])
    cfg.points);

  escapes = lib.concatMapStrings (b: "\\x" + lib.fixedWidthString 2 "0" (lib.toHexString b)) table;

  apply = pkgs.writeShellApplication {
    name = "ms-s1-max-fan-curve";
    runtimeInputs = [pkgs.coreutils pkgs.diffutils];
    text = ''
      io=/sys/kernel/debug/ec/ec0/io
      want=$(mktemp)
      trap 'rm -f "$want"' EXIT
      printf '${escapes}' >"$want"
      for off in ${toString tableOffsets}; do
        dd if="$want" of="$io" bs=1 seek="$off" conv=notrunc status=none
        cmp "$want" <(dd if="$io" bs=1 skip="$off" count=${toString (lib.length table)} status=none)
      done
    '';
  };
in {
  options.hardware.ms-s1-max.fanCurve = {
    enable = lib.mkEnableOption "a custom EC fan curve on the Minisforum MS-S1 MAX";

    points = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          temp = lib.mkOption {
            type = lib.types.ints.between 1 90;
            description = "Upper temperature of the band, in °C.";
          };
          duty = lib.mkOption {
            type = lib.types.ints.between 0 100;
            description = "Fan duty, in percent, from the previous point's temperature up to `temp`.";
          };
        };
      });
      # Up to 45 °C these match the stock duty.
      default = [
        {
          temp = 25;
          duty = 12;
        }
        {
          temp = 45;
          duty = 14;
        }
        {
          temp = 55;
          duty = 20;
        }
        {
          temp = 65;
          duty = 30;
        }
        {
          temp = 75;
          duty = 50;
        }
        {
          temp = 83;
          duty = 75;
        }
        {
          temp = 90;
          duty = 100;
        }
      ];
      description = "The 7 curve points written to both fan tables.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.length cfg.points == 7;
        message = "hardware.ms-s1-max.fanCurve.points must have exactly 7 points (one per EC record).";
      }
      {
        assertion = lib.all (i: (lib.elemAt cfg.points i).temp < (lib.elemAt cfg.points (i + 1)).temp) (lib.range 0 (lib.length cfg.points - 2));
        message = "hardware.ms-s1-max.fanCurve.points temperatures must be strictly increasing.";
      }
      {
        # The record after the writable table (0x26-0x28) is a fixed 90-95 °C
        # band whose duty byte the firmware rewrites; ending at 90 keeps the
        # bands contiguous with it.
        assertion = (lib.last cfg.points).temp == 90;
        message = "hardware.ms-s1-max.fanCurve.points must end at 90 °C.";
      }
    ];

    boot.kernelModules = ["ec_sys"];
    boot.extraModprobeConfig = "options ec_sys write_support=1";

    systemd.services.ms-s1-max-fan-curve = {
      description = "Write the custom fan curve into the MS-S1 MAX EC";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service" "sys-kernel-debug.mount"];
      requires = ["sys-kernel-debug.mount"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe apply;
      };
    };
  };
}
