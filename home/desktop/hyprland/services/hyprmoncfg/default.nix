{
  pkgs,
  lib,
  osConfig,
  ...
}: let
  inherit (osConfig.machine) isLaptop;
  inherit (osConfig.nix-config.desktop.monitors) internal profiles;
  postApply = import ./post-apply.nix {inherit pkgs;};

  generated = lib.optionalAttrs (isLaptop && internal != null) {
    laptop = import ./laptop-profile.nix {
      inherit lib internal;
      scale = builtins.fromJSON (osConfig.laptop-scale or "1.25");
    };
  };

  profilesDir = import ./profiles.nix {
    inherit pkgs lib;
    profiles = lib.mapAttrs (name: p:
      {
        inherit name;
        exec = lib.getExe postApply;
      }
      // p) (generated // profiles);
  };
in {
  warnings = lib.optional (isLaptop && internal == null) "nix-config.desktop.monitors.internal is unset: no `laptop` hyprmoncfg profile is generated, so the undocked layout, laptop-scale and Xft.dpi are not applied.";

  home.packages = [pkgs.hyprmoncfg];

  # Only profiles/ is a store link: hyprmoncfgd writes state into its base dir.
  xdg.configFile."hyprmoncfg/profiles".source = profilesDir;

  systemd.user.services.hyprmoncfgd = {
    Unit = {
      Description = "Hyprland monitor profile daemon (hyprmoncfgd)";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
      X-Restart-Triggers = ["${profilesDir}"];
    };
    Service = {
      ExecStart = "${pkgs.hyprmoncfg}/bin/hyprmoncfgd";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
