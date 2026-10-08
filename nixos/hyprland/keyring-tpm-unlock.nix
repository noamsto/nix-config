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

  # gnome-keyring-daemon --unlock cannot do this: it never hands off to a running
  # daemon (discover_other_daemon is reached only on the --start/--replace paths),
  # so it becomes a daemon itself — and gkd_control_listen unlinks the existing
  # control socket before binding, destroying the session's. Speak the control
  # protocol instead, the same GKD_CONTROL_OP_UNLOCK pam_gnome_keyring sends on
  # screen unlock. This only ever connects, so it cannot take the socket over.
  unlockScript = pkgs.writeScript "gnome-keyring-tpm-unlock" ''
    #!${pkgs.python3}/bin/python3
    import os
    import socket
    import struct
    import sys
    import time

    OP_UNLOCK = 1
    RESULTS = {0: "ok", 1: "denied", 2: "failed", 3: "no daemon"}

    uid = sys.argv[1]
    # user@.service instantiates this for every session that starts, greetd's
    # greeter among them, and the sealed password only opens this user's vault
    if uid != str(os.getuid()):
        sys.exit(0)

    control = "/run/user/{}/keyring/control".format(uid)
    with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "${credName}"), "rb") as f:
        password = f.read()


    def unlock():
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(10)
            s.connect(control)
            s.sendall(b"\0")  # credentials byte; the server checks SO_PEERCRED
            s.sendall(struct.pack(">III", 12 + len(password), OP_UNLOCK, len(password)))
            s.sendall(password)
            head = b""
            while len(head) < 8:
                chunk = s.recv(8 - len(head))
                if not chunk:
                    raise EOFError("daemon closed the connection")
                head += chunk
        return struct.unpack(">II", head)[1]


    # The path unit fires on the socket, but a daemon still initialising its
    # pkcs11 layer answers denied, so a single shot races login. Retry until it
    # takes; a genuinely wrong password just burns the window and then fails.
    deadline = time.monotonic() + 60
    result = None
    while True:
        try:
            result = unlock()
            if result == 0:
                sys.exit(0)
        except (OSError, EOFError) as err:
            result = err
        if time.monotonic() >= deadline:
            sys.exit("keyring unlock failed: {}".format(RESULTS.get(result, result)))
        time.sleep(0.5)
  '';
in
  lib.mkIf (isHyprland && config.security.tpm2.enable) {
    systemd = {
      # `just keyring-seal` writes the blob here
      tmpfiles.rules = ["d ${credDir} 0755 root root -"];

      # Instantiated per uid off user@.service, whose %i is the uid, because the
      # flake can't name one: uids are allocated at activation time. The path has
      # to be literal — inotify is armed by walking the pattern's real prefix, so
      # a glob mid-path can only watch /run/user itself and never sees the socket
      # appear two levels down.
      services."user@" = {
        overrideStrategy = "asDropin";
        wants = ["gnome-keyring-tpm-unlock@%i.path"];
      };

      # The control socket is the trigger because it only exists once the daemon
      # is listening, which is the earliest an unlock can land
      paths."gnome-keyring-tpm-unlock@" = {
        description = "Watch for uid %i's GNOME keyring daemon to unlock";
        # Gated here, not on the service: a condition-skipped service never goes
        # active, so RemainAfterExit= can't hold it and PathExists= re-fires it
        # until the path trips its trigger limit. LoadCredentialEncrypted= is
        # fatal on a missing source file, so hosts with no sealed blob must not
        # arm the watch at all.
        unitConfig.ConditionPathExists = credFile;
        pathConfig = {
          PathExists = "/run/user/%i/keyring/control";
          Unit = "gnome-keyring-tpm-unlock@%i.service";
        };
      };

      services."gnome-keyring-tpm-unlock@" = {
        description = "Unlock uid %i's GNOME login keyring from TPM-sealed password";
        unitConfig = {
          # Ties the unit's lifetime to the session so RemainAfterExit= below
          # releases on logout, re-arming the path for the next login
          BindsTo = "user@%i.service";
          After = "user@%i.service";
        };
        serviceConfig = {
          Type = "oneshot";
          # PathExists= re-triggers as soon as the triggered unit goes inactive
          # and the socket is still there; without this the oneshot re-fires
          # until it trips the start rate limit, which fails the path unit too
          RemainAfterExit = true;
          User = config.username;
          LoadCredentialEncrypted = "${credName}:${credFile}";
          ExecStart = "${unlockScript} %i";
        };
      };
    };
  }
