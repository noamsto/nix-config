{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";

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
  config = lib.mkIf isLaptop {
    # PAM rule to skip fprintd when lid is closed (clamshell mode)
    # Applied to common auth services where fingerprint timeout is annoying
    security.pam.services =
      lib.genAttrs
      ["sudo" "su" "polkit-1" "login" "noctalia-shell" "swaylock"]
      (_: {rules.auth.fprintd-lid-check = fprintdLidRule;});
  };
}
