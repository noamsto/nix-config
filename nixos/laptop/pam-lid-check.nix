{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";

  # Skip fprintd when lid is closed (clamshell mode)
  # Avoids waiting for unreachable fingerprint sensor
  lidCheckScript = pkgs.writeShellScript "pam-lid-check" ''
    if ! ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
      exit 0  # Open or no sensor - allow fprintd
    fi
    exit 1  # Closed - skip fprintd
  '';

  lidCheckRule = {
    enable = true;
    control = "[success=ignore default=1 perm_denied=1 auth_err=1]";
    modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
    args = ["quiet" "seteuid" (toString lidCheckScript)];
    order = 11300; # Before fprintd (11400)
  };

  # Terminal emulators: Ctrl+C works to cancel
  terminalFprintdArgs = ["timeout=-1" "max-tries=-1"];

  # TTY/GUI: Ctrl+C doesn't work, need finite tries for fallback
  noCtrlCFprintdArgs = ["timeout=-1" "max-tries=3"];
in {
  config = lib.mkIf isLaptop {
    security.pam.services =
      lib.genAttrs
      ["login" "sudo" "su" "polkit-1"]
      (name: {
        rules.auth.fprintd-lid-check = lidCheckRule;
        rules.auth.fprintd.args =
          if name == "sudo" || name == "su"
          then terminalFprintdArgs # Ctrl+C works in terminal emulators
          else noCtrlCFprintdArgs; # login (TTY/noctalia) and polkit need finite tries
      });
  };
}
