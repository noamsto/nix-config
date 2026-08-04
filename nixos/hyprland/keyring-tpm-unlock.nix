# Unlock the GNOME login keyring on fingerprint logins.
#
# pam_gnome_keyring only unlocks the keyring when a password is typed; a
# fingerprint short-circuits the login PAM stack (fprintd is `sufficient`
# before it), leaving the vault locked until the first gcr prompt. A fingerprint
# can't decrypt the keyring (it's encrypted with the login password), so the
# password is sealed into the TPM instead (`just keyring-seal`, PCR 7 — same
# trust posture as the TPM2 LUKS enrollment) and unsealed here at session start.
# If unsealing fails (e.g. PCR change after a firmware update), the unit fails
# and the keyring falls back to prompting once per session, as before.
#
# The blob lives outside the flake on purpose: only the TPM that sealed it can
# unseal it, so tracking it would put a password-derived artifact in git history
# in exchange for no reproducibility.
{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (config.desktop) isHyprland;
  credName = "noams-login-keyring";
  credDir = "/var/lib/gnome-keyring-tpm";

  unlockScript = pkgs.writeShellScript "gnome-keyring-tpm-unlock" ''
    set -eu
    cred=${credDir}/${credName}.cred
    [ -r "$cred" ] || exit 0
    export GNOME_KEYRING_CONTROL="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring"
    pw=$(${pkgs.systemd}/bin/systemd-creds decrypt --name=${credName} --tpm2-device=auto "$cred" -)
    printf %s "$pw" | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock
  '';
in
  lib.mkIf (isHyprland && config.security.tpm2.enable) {
    # tss grants /dev/tpmrm0 access so the user service can unseal without root
    users.users.${config.username}.extraGroups = ["tss"];

    # `just keyring-seal` writes the blob here; hosts without one skip silently
    # (the script exits 0 on a missing file)
    systemd.tmpfiles.rules = ["d ${credDir} 0755 root root -"];

    systemd.user.services.gnome-keyring-tpm-unlock = {
      description = "Unlock GNOME login keyring from TPM-sealed password";
      wantedBy = ["graphical-session.target"];
      after = ["graphical-session-pre.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = unlockScript;
      };
    };
  }
