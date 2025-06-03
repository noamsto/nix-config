# Save this as kanshi-lid-profile.nix in your NixOS configuration directory
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.kanshi-lid-profile;
  change-kanshi-profile-script = import ./change_kanshi_profile.nix {inherit pkgs;};
in {
  options.services.kanshi-lid-profile = {
    enable = mkEnableOption "Kanshi lid profile service";
  };

  config = mkIf cfg.enable {
    systemd.user.services.kanshi-lid-profile = {
      Unit = {
        Description = "Change Kanshi profile based on laptop lid status change";
        After = ["kanshi.service"];
        Requires = ["kanshi.service"];
      };
      Install = {
        WantedBy = ["kanshi.service"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${change-kanshi-profile-script}/bin/change-kanshi-profile";
        Restart = "always";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
