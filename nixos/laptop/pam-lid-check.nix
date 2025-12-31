{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";

  # Instant lid check for terminal services (sudo/su/polkit)
  # These block on fingerprint with no parallel password input
  # In clamshell mode, skip fprintd to avoid waiting for unreachable sensor
  lidCheckScript = pkgs.writeShellScript "pam-lid-check" ''
    # Direct read from kernel ACPI - fastest and most accurate
    if ! ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
      exit 0  # Not closed = open (or no lid sensor) - allow fprintd
    fi
    exit 1  # Closed - skip fprintd
  '';

  # PAM rule: skip fprintd when lid is closed
  # Control: success=ignore (continue to fprintd), all errors skip 1 rule (skip fprintd)
  lidCheckRule = {
    enable = true;
    control = "[success=ignore default=1 perm_denied=1 auth_err=1]";
    modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
    args = ["quiet" "seteuid" (toString lidCheckScript)];
    order = 11300; # Before fprintd (11400)
  };

  # fprintd settings for terminal services (sudo/su)
  # timeout=-1 means unlimited/infinite timeout (fprintd special value)
  # max-tries=-1 means unlimited retries - Ctrl+C cancels in terminal
  terminalFprintdArgs = ["timeout=-1" "max-tries=-1"];

  # fprintd settings for polkit (graphical dialog)
  # max-tries=3 allows fallback to password after 3 failed attempts
  # No Ctrl+C in GUI, so finite tries is the only escape hatch
  polkitFprintdArgs = ["timeout=-1" "max-tries=3"];

  # fprintd settings for lock screen
  # Unlimited because lock screen has parallel password input
  loginFprintdArgs = ["timeout=-1" "max-tries=-1"];
in {
  config = lib.mkIf isLaptop {
    security.pam.services =
      {
        # Login (used by noctalia lock screen): NO lid check needed
        # Lock screen has parallel password input - user can type password if lid is closed
        # Adding lid check would only delay fingerprint after resume with no benefit
        login.rules.auth.fprintd.args = loginFprintdArgs;

        # Polkit: graphical dialog with no Ctrl+C
        # Finite max-tries allows fallback to password after failed attempts
        polkit-1 = {
          rules.auth.fprintd-lid-check = lidCheckRule;
          rules.auth.fprintd.args = polkitFprintdArgs;
        };
      }
      // lib.genAttrs
      # Terminal services: instant lid check needed
      # These block on fingerprint with no parallel password input
      # Ctrl+C works in terminal to cancel and fall back to password
      ["sudo" "su"]
      (_: {
        rules.auth.fprintd-lid-check = lidCheckRule;
        rules.auth.fprintd.args = terminalFprintdArgs;
      });
  };
}
