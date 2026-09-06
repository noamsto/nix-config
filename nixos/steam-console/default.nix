{
  config,
  inputs,
  lib,
  ...
}: let
  cfg = config.steamConsole;
in {
  imports = [inputs.jovian.nixosModules.default];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.desktop.isEnabled;
        message = ''
          steamConsole.enable and desktop.mode != "none" both want the display, and
          Jovian's autostart path owns the display manager. Pick one.
        '';
      }
    ];

    jovian = {
      steam = {
        enable = true;
        inherit (cfg) autoStart user;
        # Required whenever autoStart is on: Jovian's autostart unit
        # interpolates this into an ExecStart unconditionally
        # (modules/steam/autostart.nix:106) and it defaults to null, so
        # evaluation dies with "cannot coerce null to a string". halo has no
        # desktop to switch to, and "gamescope-wayland" is the value Jovian's
        # own check message prescribes for exactly that case — "Switch to
        # Desktop" just relaunches Gaming Mode.
        desktopSession = lib.mkIf cfg.autoStart "gamescope-wayland";
      };
      # Gates Jovian's AMD backlight/modesetting helpers. NOT
      # jovian.devices.steamdeck, which would pull linux-neptune over the
      # linuxPackages_latest that gfx1151 needs.
      hardware.has.amd.gpu = true;
      # Off, and it has to be said explicitly: this inherits
      # `jovian.steamos.useSteamOSConfig`, which is true, so leaving it alone
      # starts `cecd` against an adapter that does not exist. amdgpu imports
      # only the CEC *notifier* (`cec_notifier_*`) and DisplayPort AUX
      # tunnelling (`drm_dp_cec_*`) — never `cec_allocate_adapter` — so it
      # registers no HDMI CEC adapter. Measured on halo with the TV live on
      # HDMI-A-1: no /dev/cec*, no /sys/class/cec. The kernel compounds it by
      # building only cec.ko core (CONFIG_MEDIA_CEC_SUPPORT unset), so there is
      # no userspace CEC API at all. Working CEC would need a DP->HDMI adapter
      # doing CEC-Tunneling-over-AUX plus a custom kernel.
      steamos.enableHdmiCecIntegration = false;
      # Off for the same inheritance reason, and this one bites hard: it
      # injects Valve's Deck cmdline (modules/steamos/boot.nix), whose
      # `amd_iommu=off` stops `amdxdna` probing — it needs IOMMU SVA and dies
      # with `aie2_init: Running without IOMMU not supported`, leaving the NPU
      # unbound and /dev/accel absent.
      #
      # Dropping the set also drops `amdgpu.dcdebugmask=0x20000`, Jovian's
      # workaround for black/white flashes when planes show/hide
      # (jupiter-hw-support 1a27763) — re-add that one alone if Gaming Mode
      # flashes. And it drops `audit=0`, so auditing comes back on.
      steamos.enableDefaultCmdlineConfig = false;
    };

    # Jovian's modules/steam/steam.nix already sets programs.steam.enable,
    # hardware.graphics and hardware.steam-hardware. remotePlay.openFirewall is
    # deliberately left off: halo keeps ports off the LAN and is reached over
    # tailscale, same posture as lemond and ds4.

    users.users.${cfg.user} = {
      isNormalUser = true;
      description = "Steam Gaming Mode session";
      # Home is the @games subvolume root, so libraries, Proton prefixes and
      # shader caches stay off @home.
      home = "/var/lib/games";
      # No wheel, no authorizedKeys: autologin must not reach sudo or SSH.
      extraGroups = ["video" "render" "input" "audio"];
    };
  };
}
