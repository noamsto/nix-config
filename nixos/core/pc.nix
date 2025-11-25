{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
  isDesktop = config.machine.type == "desktop";
  isPC = isLaptop || isDesktop;

  # Script to check lid state for PAM - exits 0 if open, 1 if closed
  # Uses full paths since PAM context has minimal environment
  lidCheckScript = pkgs.writeShellScript "pam-lid-check" ''
    if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
      exit 1
    fi
    exit 0
  '';

  # PAM rule to skip fprintd when lid is closed
  # Control: success=ignore (continue to fprintd), all errors skip 1 rule (skip fprintd)
  # pam_exec returns various error codes on script failure, so we handle them all
  fprintdLidRule = {
    enable = true;
    control = "[success=ignore default=1 perm_denied=1 auth_err=1]";
    modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
    args = ["quiet" "seteuid" (toString lidCheckScript)];
    order = 11300; # Before fprintd (11400)
  };
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
      alsa.enablePersistence = true;
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

    # PAM rule to skip fprintd when lid is closed (clamshell mode)
    # Applied to common auth services where fingerprint timeout is annoying
    security.pam.services = lib.mkIf isLaptop (
      lib.genAttrs ["sudo" "su" "polkit-1" "login" "hyprlock" "swaylock"] (
        _: {rules.auth.fprintd-lid-check = fprintdLidRule;}
      )
    );

    # OBS virtual Camera
    boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';

    # Restart hyprdynamicmonitors after resume to fix phantom monitor detection
    # When laptop is undocked while asleep, Hyprland keeps phantom monitors
    # Restarting HDM forces fresh monitor detection
    systemd.services.hyprdynamicmonitors-resume = lib.mkIf isLaptop {
      description = "Clear phantom monitors and restart hyprdynamicmonitors after system resume";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        # Clear phantom monitors by checking DRM status and disabling disconnected ones in Hyprland
        ExecStart = pkgs.writeShellScript "hdm-resume" ''
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)

          # Disable monitors that DRM reports as disconnected (these are phantoms in Hyprland)
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")

              # If DRM says disconnected, disable in Hyprland to clear phantom
              if [ "$status" = "disconnected" ] && [ "$connector_name" != "Writeback-1" ]; then
                ${pkgs.hyprland}/bin/hyprctl keyword monitor "$connector_name,disable" 2>/dev/null || true
              fi
            fi
          done

          sleep 1

          # Now restart HDM to re-detect actual monitors
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host restart hyprdynamicmonitors.service
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };

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
