{pkgs, ...}: let
  pre-suspend-script = pkgs.writeShellScript "enable-edp1-pre-suspend.sh" ''
    ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1, preferred,auto,auto"
    echo "Enabling eDP-1 monitor pre-suspend"
  '';
in {
  systemd.user.services.enable-edp1-pre-suspend = {
    Unit = {
      Description = "Enable eDP-1 monitor pre suspend";
      Before = ["sleep.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pre-suspend-script}";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install = {
      WantedBy = ["sleep.target"];
    };
  };
}
