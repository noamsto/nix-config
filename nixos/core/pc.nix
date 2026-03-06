{
  config,
  lib,
  ...
}: let
  inherit (config.machine) isLaptop;
  inherit (config.machine) isPC;
in {
  config = lib.mkIf isPC {
    services =
      {
        # Enable CUPS to print documents.
        printing.enable = true;
        # printing.drivers = with pkgs; [splix samsung-unified-linux-driver];

        # Sound
        pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
          jack.enable = true;
        };

        # profile-sync-daemon
        psd = {
          enable = true;
          resyncTimer = "10m";
        };

        # Disable USB autosuspend for Logitech receivers (Bolt/Unifying)
        # Fixes: external keyboard not waking screen from DPMS off
        udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", TEST=="power/control", ATTR{power/control}="on"
        '';
      }
      // lib.optionalAttrs isLaptop {
        upower.enable = true;
        fprintd.enable = true;
      };

    hardware = {
      alsa.enablePersistence = true;
      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;
      logitech.wireless.enable = true; # solaar
      logitech.wireless.enableGraphical = true;
    };

    programs = {
      # Fan and thermal control
      coolercontrol.enable = true;
    };

    # Recommended for alsa
    security.rtkit.enable = true;

    # Raise memlock limit for io_uring (semgrep, modern Rust/OCaml tooling)
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "soft";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "*";
        type = "hard";
        item = "memlock";
        value = "unlimited";
      }
    ];

    # OBS virtual Camera
    boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
  };
}
