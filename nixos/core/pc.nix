{
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
  isDesktop = config.machine.type == "desktop";
  isPC = isLaptop || isDesktop;
in {
  config = lib.mkIf isPC {
    services = {
      power-profiles-daemon.enable = isLaptop;
      # Enable CUPS to print documents.
      printing.enable = true;
      # printing.drivers = with pkgs; [splix samsung-unified-linux-driver];
    };

    hardware = {
      bluetooth.enable = true;
      logitech.wireless.enable = true; # solaar
    };
    services.fprintd.enable = isLaptop; # TODO: Move to laptop nix file?

    programs = {
      # Fan and thermal control
      coolercontrol.enable = true;
      adb.enable = true;
    };

    # Enable sound with pipewire.
    hardware.alsa.enablePersistence = true;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # OBS virtual Camera
    boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
  };
}
