# Drives greetd's IPC like noctalia-greeter 1.7.0 and checks which auth paths
# consult the fingerprint reader.
{pkgs}: let
  # VM-only test account; nothing outside the test VM accepts it, hence the
  # betterleaks:allow on the users.users line below.
  aliceLogin = "alice-pw";

  # greetd joins the session cmd with spaces into `exec <cmd>` for /bin/sh
  # without quoting, so it must be a single word.
  session = pkgs.writeShellScript "greetd-test-session" ''
    ${pkgs.coreutils}/bin/touch "$HOME"/session-ok
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  # Answers the first secret/visible prompt per mode, as the greeter does:
  # `empty` replies "" (noctalia), `omit` sends no response (other clients).
  client = pkgs.writers.writePython3Bin "greetd-client" {} ''
    import json
    import socket
    import struct
    import sys
    import time

    PROMPTS = ("secret", "visible")
    SESSION_CMD = [
        "${session}",
    ]


    def send(sock, msg):
        data = json.dumps(msg).encode()
        sock.sendall(struct.pack("=I", len(data)) + data)


    def recv_exact(sock, n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise EOFError("greetd closed the socket")
            buf += chunk
        return buf


    def recv(sock):
        (length,) = struct.unpack("=I", recv_exact(sock, 4))
        return json.loads(recv_exact(sock, length))


    def answer(mode):
        reply = {"type": "post_auth_message_response"}
        if mode == "empty":
            reply["response"] = ""
        elif mode.startswith("typed:"):
            reply["response"] = mode[len("typed:"):]
        elif mode != "omit":
            raise SystemExit("unknown mode " + mode)
        return reply


    def main():
        path, user, mode = sys.argv[1:4]
        start = sys.argv[4:] == ["start"]
        begin = time.monotonic()
        second_prompt = False
        answered = False

        sock = socket.socket(socket.AF_UNIX)
        sock.settimeout(120)
        sock.connect(path)
        send(sock, {"type": "create_session", "username": user})
        resp = recv(sock)
        while resp["type"] == "auth_message":
            if resp["auth_message_type"] not in PROMPTS:
                reply = {"type": "post_auth_message_response"}
            elif answered:
                second_prompt = True
                break
            else:
                answered = True
                reply = answer(mode)
            send(sock, reply)
            resp = recv(sock)
        elapsed = time.monotonic() - begin

        start_type = None
        if resp["type"] == "success" and start:
            send(sock, {
                "type": "start_session",
                "cmd": SESSION_CMD,
                "env": [],
            })
            start_type = recv(sock)["type"]
        else:
            # greetd keeps the pending session after an auth error too
            send(sock, {"type": "cancel_session"})
            recv(sock)

        print(json.dumps({
            "type": resp["type"],
            "error_type": resp.get("error_type"),
            "description": resp.get("description"),
            "second_prompt": second_prompt,
            "elapsed": elapsed,
            "start_type": start_type,
        }))


    main()
  '';
in
  pkgs.testers.runNixOSTest {
    name = "greetd-pam";

    nodes.machine = {...}: {
      imports = [../../options.nix ../laptop/pam-lid-check.nix ./greetd-pam.nix];

      machine.type = "laptop";

      users.users.alice = {
        isNormalUser = true;
        password = aliceLogin; # betterleaks:allow
      };

      services.fprintd.enable = true;
      services.gnome.gnome-keyring.enable = true;
      security.pam.services.login.enableGnomeKeyring = true;

      services.greetd = {
        enable = true;
        settings.default_session.command = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };

    testScript = ''
      import json


      def stashes():
          machine.succeed("journalctl --sync")
          out = machine.succeed(
              "journalctl -b -o cat | grep -c 'gkr-pam: stashed password' || true"
          )
          return int(out.strip())


      def fprintd_stamp():
          return machine.succeed(
              "systemctl show -P ActiveEnterTimestampMonotonic fprintd.service"
          ).strip()


      def attempt(mode, start=False):
          """Returns (client result, whether fprintd was started meanwhile)."""
          machine.succeed("systemctl stop fprintd.service")
          before = fprintd_stamp()
          cmd = f"runuser -u greeter -- ${client}/bin/greetd-client {sock} alice {mode}"
          out = machine.succeed(cmd + (" start" if start else ""))
          result = json.loads(out.strip().splitlines()[-1])
          return result, fprintd_stamp() != before


      machine.wait_for_unit("greetd.service")
      machine.wait_until_succeeds("loginctl list-sessions --no-legend | grep -q greeter")
      sock = machine.succeed("ls /run/greetd-*.sock").strip()

      with subtest("wrong password is rejected without the reader"):
          result, consulted = attempt("typed:wrong-pw")
          assert result["type"] == "error", result
          assert result["error_type"] == "auth_error", result
          assert not consulted, f"fprintd consulted for a typed password: {result}"
          assert not result["second_prompt"], result

      with subtest("lid open, empty submit uses the reader"):
          before = stashes()
          result, consulted = attempt("empty")
          assert result["type"] == "error", result
          assert consulted, f"fprintd not consulted for an empty submit: {result}"
          assert stashes() == before, "empty token reached the keyring"

      with subtest("lid open, omitted response uses the reader"):
          result, consulted = attempt("omit")
          assert result["type"] == "error", result
          assert consulted, f"fprintd not consulted for an omitted response: {result}"

      with subtest("lid closed, empty submit skips the reader"):
          machine.succeed("test -d /proc/acpi")
          machine.succeed("mount -t tmpfs none /proc/acpi")
          machine.succeed("mkdir -p /proc/acpi/button/lid/LID")
          machine.succeed(
              "echo 'state:      closed' > /proc/acpi/button/lid/LID/state"
          )
          lid = machine.succeed(
              "grep -o '/nix/store/[^ ]*-pam-lid-check' /etc/pam.d/login | head -n1"
          ).strip()
          machine.fail(lid)
          result, consulted = attempt("empty")
          machine.succeed("umount /proc/acpi")
          assert result["type"] == "error", result
          assert not consulted, f"fprintd consulted with the lid closed: {result}"

      with subtest("correct password logs in at once"):
          before = stashes()
          result, consulted = attempt("typed:${aliceLogin}", start=True)
          assert result["type"] == "success", result
          assert not consulted, f"fprintd consulted for a typed password: {result}"
          assert not result["second_prompt"], result
          assert result["elapsed"] < 5, result
          assert stashes() == before + 1, "password not stashed for the keyring"
          assert result["start_type"] == "success", result
          machine.wait_until_succeeds("test -e /home/alice/session-ok", timeout=60)
    '';
  }
