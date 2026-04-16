{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.lemonade;
  lemonade = pkgs.callPackage ../../packages/lemonade.nix {};
in {
  options.services.lemonade = {
    enable = mkEnableOption "Lemonade AI server (OpenAI-compatible local inference)";

    port = mkOption {
      type = types.port;
      default = 13305;
      description = "HTTP port for the Lemonade API.";
    };

    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "Address to bind for connections.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [lemonade];

    systemd.services.lemond = {
      description = "Lemonade AI Server";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = config.username;
        ExecStart = "${lemonade}/bin/lemond --port ${toString cfg.port} --host ${cfg.host}";
        Restart = "on-failure";
        RestartSec = "5s";
        KillSignal = "SIGINT";
      };
    };
  };
}
