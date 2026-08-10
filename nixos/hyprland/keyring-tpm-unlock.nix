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
# A user unit cannot do the unsealing itself: since systemd 261 an unprivileged
# `systemd-creds decrypt` is brokered by io.systemd.Credentials, behind a polkit
# action that is auth_admin_keep even for active sessions, so a unit with no
# polkit agent can only ever fail it.
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
  credFile = "${credDir}/${credName}.cred";

  unlockScript = pkgs.writeShellScript "gnome-keyring-tpm-unlock" ''
    set -eu
    export GNOME_KEYRING_CONTROL="/run/user/$(id -u)/keyring"
    ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock \
      < "$CREDENTIALS_DIRECTORY/${credName}"
  '';
in
  lib.mkIf (isHyprland && config.security.tpm2.enable) {
    systemd = {
      # `just keyring-seal` writes the blob here
      tmpfiles.rules = ["d ${credDir} 0755 root root -"];

      # Globbed rather than a literal uid: uids are allocated at activation time,
      # so the flake can't name one. The control socket is the trigger because it
      # only exists once the daemon is listening.
      paths.gnome-keyring-tpm-unlock = {
        description = "Watch for a GNOME keyring daemon to unlock";
        wantedBy = ["multi-user.target"];
        pathConfig.PathExistsGlob = "/run/user/*/keyring/control";
      };

      services.gnome-keyring-tpm-unlock = {
        description = "Unlock GNOME login keyring from TPM-sealed password";
        # LoadCredentialEncrypted= is fatal on a missing source file, so hosts
        # with no sealed blob need to skip the unit rather than fail it
        unitConfig.ConditionPathExists = credFile;
        serviceConfig = {
          Type = "oneshot";
          User = config.username;
          LoadCredentialEncrypted = "${credName}:${credFile}";
          ExecStart = unlockScript;
        };
      };
    };
  }
