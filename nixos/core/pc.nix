{
  config,
  lib,
  ...
}: let
  inherit (config.machine) isLaptop serverMode;
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
          # Stream to AirPlay (RAOP) wifi speakers — they show up as normal
          # PipeWire sinks. raopOpenFirewall only opens the timing/control ports;
          # the discover module lives in the package's pipewire.conf.avail and is
          # NOT loaded unless we activate it here (env.etc drop-ins now assert-fail).
          # Discovery rides the Avahi mDNS already enabled in networking.nix.
          raopOpenFirewall = true;
          extraConfig.pipewire."50-raop" = {
            "context.modules" = [
              {
                name = "libpipewire-module-raop-discover";
                condition = [{"module.raop" = "!false";}];
              }
            ];
          };
          extraConfig.pipewire."92-webrtc-stable" = {
            "context.properties" = {
              "default.clock.min-quantum" = 512;
            };
          };
        };

        # Bridge non-AirPlay wifi speakers (Chromecast/Sonos/UPnP) into AirPlay,
        # so they join the RAOP sinks above in one PipeWire output list.
        airconnect.enable = true;

        # profile-sync-daemon: removed 2026-04-28.
        # Reasons: NVMe wear math doesn't justify it (~136 yrs to TBW exhaustion at
        # firefox's ~12 GB/day), Fedora dropped the package, mainstream Linux
        # discussion has gone quiet, and v6.50 in nixpkgs collides with HM at boot
        # by replacing ~/.config/mozilla/firefox/default with a tmpfs symlink that
        # dangles until the user session brings it up — see journal of 2026-04-28.
        # Revisit when BOTH conditions hold:
        #   1. nixpkgs ships psd v7+ (uses fuse-overlayfs, no symlink-at-rest;
        #      tracking PR https://github.com/NixOS/nixpkgs/pull/500548).
        #   2. A real benchmark surfaces showing measurable wear or perf benefit on
        #      modern NVMe — the current pro-psd argument has shifted to "NVMe APST
        #      idle states" but no one has measured it.

        # Disable USB autosuspend for Logitech receivers (Bolt/Unifying)
        # Fixes: external keyboard not waking screen from DPMS off
        udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", TEST=="power/control", ATTR{power/control}="on"
        '';
      }
      // lib.optionalAttrs isLaptop {
        upower = {
          enable = true;
          # Clean shutdown instead of HybridSleep — no hibernate needed.
          # 5% leaves enough headroom for a clean poweroff under load.
          percentageAction = 5;
          criticalPowerAction = "PowerOff";
        };
        fprintd.enable = !serverMode; # headless server: no sensor to authenticate against
      };

    hardware = {
      alsa.enablePersistence = true;
      bluetooth = {
        enable = true;
        powerOnBoot = true;
        settings = {
          General.Experimental = true; # battery reporting + newer BT features
          Policy.AutoEnable = true; # re-power adapters after suspend/resume
        };
      };
      logitech.wireless.enable = true; # solaar
    };

    programs = {
      solaar.enable = true;

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
    boot.extraModulePackages = [
      # On kernel 7.3 the build runs depmod and ships modules.* index files,
      # which collide with the kernel's own in the linux-modules buildEnv.
      (config.boot.kernelPackages.v4l2loopback.overrideAttrs (old: {
        postInstall =
          (old.postInstall or "")
          + ''
            find $out/lib/modules -maxdepth 2 -type f -name 'modules.*' -delete
          '';
      }))
    ];
    boot.extraModprobeConfig = ''
      options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
    '';
  };
}
