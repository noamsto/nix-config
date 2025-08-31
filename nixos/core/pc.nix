{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
  isDesktop = config.machine.type == "desktop";
  isPC = isLaptop || isDesktop;
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
      }
      // lib.optionalAttrs isLaptop {
        power-profiles-daemon.enable = true;
        upower.enable = true;
        fprintd = {
          enable = true;
          package = pkgs.fprintd;
        };
      };

    hardware = {
      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;
      logitech.wireless.enable = true; # solaar
      logitech.wireless.enableGraphical = true;
    };

    programs = {
      # Fan and thermal control
      coolercontrol.enable = true;
      adb.enable = true;
    };

    # Recommended for alsa
    security.rtkit.enable = true;

    # OBS virtual Camera
    boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';

    # # WiFi suspend/resume fix for QCNFA765 adapter
    # systemd.services.ath11k-suspend = lib.mkIf isLaptop {
    #   description = "Unload ath11k_pci before suspend";
    #   before = ["sleep.target"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     ExecStart = "${pkgs.kmod}/bin/rmmod ath11k_pci";
    #     RemainAfterExit = true;
    #   };
    #   wantedBy = ["sleep.target"];
    # };
    #
    # systemd.services.ath11k-resume = lib.mkIf isLaptop {
    #   description = "Reload ath11k_pci after resume";
    #   after = ["suspend.target" "suspend-then-hibernate.target" "hibernate.target" "hybrid-sleep.target"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     ExecStart = "${pkgs.kmod}/bin/modprobe ath11k_pci";
    #     ExecStartPost = [
    #       "${pkgs.coreutils}/bin/sleep 2"
    #       "${pkgs.systemd}/bin/systemctl restart NetworkManager"
    #     ];
    #   };
    #   wantedBy = ["suspend.target" "suspend-then-hibernate.target" "hibernate.target" "hybrid-sleep.target"];
    # };
  };
}
