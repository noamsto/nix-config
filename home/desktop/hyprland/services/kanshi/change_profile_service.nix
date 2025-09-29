# Save this as kanshi-lid-profile.nix in your NixOS configuration directory
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.kanshi-lid-profile;
  lid-event-handler-script = import ./lid_event_handler.nix {inherit pkgs;};
in {
  options.services.kanshi-lid-profile = {
    enable = mkEnableOption "Kanshi lid profile service";
  };

  config = mkIf cfg.enable {
    systemd.user.services.kanshi-lid-profile = {
      Unit = {
        Description = "Event-based Kanshi lid profile handler";
        After = ["kanshi.service"];
        Requires = ["kanshi.service"];
      };
      Install = {
        WantedBy = ["kanshi.service"];
      };
      Service = {
        Type = "simple";
        ExecStart = "${lid-event-handler-script}/bin/lid-event-handler";
        Restart = "always";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}
