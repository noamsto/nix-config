# Drives the real keyring TPM unlock units in a VM against a fake keyring
# daemon, a fake notification server, and a software TPM.
{pkgs}: let
  runtime = "/run/user/1000";
  bus = "unix:path=${runtime}/bus";
  cred = "/var/lib/gnome-keyring-tpm/noams-login-keyring.cred";

  # Speaks the control protocol the unlock script uses and records each
  # password it is handed in /tmp/unlocks-N.
  fakeKeyring = pkgs.writers.writePython3 "fake-keyring" {} ''
    import os
    import socket
    import struct
    import sys
    import time

    n = sys.argv[1]
    path = "${runtime}/keyring/control"
    os.makedirs("${runtime}/keyring", mode=0o700, exist_ok=True)
    if os.path.exists(path):
        os.unlink(path)

    # A real daemon spends time initialising between creating its directory
    # and listening; binding at once races systemd arming its inotify watch.
    time.sleep(1)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(5)


    def read_exact(conn, size):
        data = b""
        while len(data) < size:
            chunk = conn.recv(size - len(data))
            if not chunk:
                raise EOFError
            data += chunk
        return data


    while True:
        conn, _ = server.accept()
        with conn:
            try:
                read_exact(conn, 1)
                _, _, pw_len = struct.unpack(">III", read_exact(conn, 12))
                password = read_exact(conn, pw_len)
            except EOFError:
                continue
            with open("/tmp/unlocks-" + n, "ab") as f:
                f.write(password + b"\n")
            conn.sendall(struct.pack(">II", 8, 0))
  '';

  fakeNotifyd =
    pkgs.writers.writePython3 "fake-notifyd" {
      libraries = [pkgs.python3Packages.jeepney];
    } ''
      from jeepney import HeaderFields, MessageType
      from jeepney.bus_messages import DBus
      from jeepney.io.blocking import open_dbus_connection
      from jeepney.wrappers import new_method_return

      conn = open_dbus_connection(bus="SESSION")
      reply = conn.send_and_get_reply(
          DBus().RequestName("org.freedesktop.Notifications")
      )
      assert reply.body[0] == 1, reply.body

      while True:
          msg = conn.receive()
          if msg.header.message_type != MessageType.method_call:
              continue
          member = msg.header.fields[HeaderFields.member]
          if member == "Notify":
              summary, body = msg.body[3], msg.body[4]
              with open("/tmp/notifications", "a") as f:
                  f.write(summary + "|" + body + "\n")
              conn.send(new_method_return(msg, "u", (1,)))
          elif member == "GetCapabilities":
              conn.send(new_method_return(msg, "as", (["body"],)))
          elif member == "GetServerInformation":
              conn.send(
                  new_method_return(
                      msg, "ssss", ("fake", "test", "1", "1.2")
                  )
              )
    '';

  pcr = "0000000000000000000000000000000000000000000000000000000000000001";
in
  pkgs.testers.runNixOSTest {
    name = "keyring-tpm-unlock";

    nodes.machine = {...}: {
      imports = [../../options.nix ./keyring-tpm-unlock.nix];

      desktop.mode = "hyprland";
      username = "alice";
      users.users.alice.isNormalUser = true;

      security.tpm2.enable = true;
      virtualisation.tpm.enable = true;
      environment.systemPackages = [pkgs.tpm2-tools];
    };

    testScript = ''
      def lines(n):
          _, out = machine.execute(f"cat /tmp/unlocks-{n} 2>/dev/null")
          return len(out.splitlines())


      def manager_start():
          return machine.succeed(
              "systemctl show -P ActiveEnterTimestampMonotonic user@1000.service"
          ).strip()


      machine.wait_for_unit("multi-user.target")
      assert machine.succeed("id -u alice").strip() == "1000"

      machine.succeed(
          "printf %s hunter2 | systemd-creds encrypt --with-key=tpm2 "
          "--tpm2-device=auto --tpm2-pcrs=7 --name=noams-login-keyring "
          "- ${cred}"
      )
      machine.succeed("chmod 0400 ${cred}")

      machine.succeed("loginctl enable-linger alice")
      machine.wait_for_unit("user@1000.service")
      started = manager_start()

      # Login 1: one unlock for the first control socket.
      machine.succeed(
          "systemd-run --uid=alice --unit=fake-keyring-1 ${fakeKeyring} 1"
      )
      machine.wait_until_succeeds("grep -qx hunter2 /tmp/unlocks-1", timeout=90)
      machine.sleep(10)
      assert lines(1) == 1, lines(1)

      # Login 2: the user manager stays up, the daemon is killed and its
      # socket file is left behind; the new daemon must be unlocked once.
      machine.succeed("systemctl stop fake-keyring-1.service")
      machine.succeed(
          "systemd-run --uid=alice --unit=fake-keyring-2 ${fakeKeyring} 2"
      )
      machine.wait_until_succeeds("grep -qx hunter2 /tmp/unlocks-2", timeout=90)
      machine.sleep(10)
      assert lines(2) == 1, lines(2)
      assert lines(1) == 1, lines(1)
      assert manager_start() == started

      # Login 3 with a broken PCR 7 seal: one notification, no unlock, and
      # the path unit survives.
      machine.succeed(
          "systemd-run --uid=alice -E DBUS_SESSION_BUS_ADDRESS=${bus} "
          "--unit=fake-notifyd ${fakeNotifyd}"
      )
      machine.wait_until_succeeds(
          "runuser -u alice -- env DBUS_SESSION_BUS_ADDRESS=${bus} "
          "busctl --user status org.freedesktop.Notifications"
      )
      machine.succeed("systemctl stop fake-keyring-2.service")
      machine.succeed("tpm2_pcrextend 7:sha256=${pcr}")
      machine.succeed(
          "systemd-run --uid=alice --unit=fake-keyring-3 ${fakeKeyring} 3"
      )
      machine.wait_until_succeeds("test -s /tmp/notifications", timeout=150)
      machine.sleep(10)
      _, out = machine.execute("cat /tmp/notifications")
      assert len(out.splitlines()) == 1, out
      assert "just keyring-seal" in out, out
      machine.fail("test -e /tmp/unlocks-3")
      result = machine.succeed(
          "systemctl show -P Result gnome-keyring-tpm-unlock@1000.service"
      ).strip()
      assert result != "success", result
      machine.succeed("journalctl -b --no-pager | grep -q 'just keyring-seal'")
      state = machine.succeed(
          "systemctl is-active gnome-keyring-tpm-unlock@1000.path"
      ).strip()
      assert state == "active", state

      # Logout: the user manager must stay down once linger is off, and the
      # teardown must not re-trigger the unlock while the socket still exists.
      cursor = machine.succeed("journalctl -b -n0 --show-cursor --no-pager")
      cursor = cursor.split("-- cursor: ")[1].strip()
      machine.succeed("loginctl disable-linger alice")
      machine.succeed("systemctl stop fake-keyring-3.service fake-notifyd.service")
      machine.wait_until_succeeds("! systemctl is-active user@1000.service", timeout=60)
      machine.sleep(5)
      machine.fail("systemctl is-active user@1000.service")
      machine.fail("systemctl is-active gnome-keyring-tpm-unlock@1000.path")
      machine.fail(
          f"journalctl -b --after-cursor='{cursor}' --no-pager "
          "-u gnome-keyring-tpm-unlock@1000.service "
          "-u gnome-keyring-tpm-unlock-watch@1000.service "
          "| grep -E 'Starting|Started|unlock failed'"
      )

      # Login again: the manager's wants= re-arms the path.
      machine.succeed("loginctl enable-linger alice")
      machine.wait_for_unit("user@1000.service")
      machine.wait_until_succeeds(
          "systemctl is-active gnome-keyring-tpm-unlock@1000.path", timeout=60
      )
    '';
  }
