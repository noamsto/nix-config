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
{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (config.desktop) isHyprland;
  credName = "noams-login-keyring";
  hostCred = ../../hosts/${config.hostname}/${credName}.cred;

  unlockScript = pkgs.writeShellScript "gnome-keyring-tpm-unlock" ''
    set -eu
    cred=/etc/${credName}.cred
    [ -r "$cred" ] || exit 0
    export GNOME_KEYRING_CONTROL="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/keyring"
    pw=$(${pkgs.systemd}/bin/systemd-creds decrypt --name=${credName} --tpm2-device=auto "$cred" -)
    printf %s "$pw" | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock
  '';
in
  lib.mkIf (isHyprland && config.security.tpm2.enable) {
    # tss grants /dev/tpmrm0 access so the user service can unseal without root
    users.users.${config.username}.extraGroups = ["tss"];

    # Hosts without a sealed blob skip silently (script exits 0 on missing file)
    environment.etc = lib.optionalAttrs (builtins.pathExists hostCred) {
      "${credName}.cred".source = hostCred;
    };

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
