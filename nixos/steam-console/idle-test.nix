# Drives the real steam-console-idle watcher with logind Suspend calls.
{pkgs}: let
  inherit (pkgs) lib;

  # systemd-run units get only systemd's built-in PATH, so the fakes carry
  # coreutils themselves; the name is the process comm pgrep/pkill -x match.
  fakeReaper = pkgs.writeShellApplication {
    name = "reaper";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      while :; do sleep 1; done
    '';
  };

  fakeWebhelper = pkgs.writeShellApplication {
    name = "steamwebhelper";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      trap 'touch /tmp/term-$USER; exit 0' TERM
      while :; do sleep 1; done
    '';
  };

  # Serials are client-chosen: each forged Suspend is followed by a logind
  # call reusing its serial, whose error the watcher must not take for
  # logind's answer to the Suspend.
  forge =
    pkgs.writers.writePython3 "forge-sleep" {
      libraries = [pkgs.python3Packages.jeepney];
    } ''
      from jeepney import (
          DBusAddress,
          HeaderFields,
          MessageFlag,
          new_method_call,
      )
      from jeepney.io.blocking import open_dbus_connection

      LOGIN1 = DBusAddress(
          "/org/freedesktop/login1",
          bus_name="org.freedesktop.login1",
          interface="org.freedesktop.login1.Manager",
      )
      # hostname1.conf lets anyone call hostnamed, so the bus never refuses.
      DECOY = DBusAddress(
          "/org/freedesktop/login1",
          bus_name="org.freedesktop.hostname1",
          interface="org.freedesktop.login1.Manager",
      )

      conn = open_dbus_connection(bus="SYSTEM")


      def wait_for_reply(serial):
          while True:
              reply = conn.receive(timeout=10)
              fields = reply.header.fields
              if fields.get(HeaderFields.reply_serial) == serial:
                  return reply


      def forge_suspend(dest, serial, no_reply=False, wait=True):
          msg = new_method_call(dest, "Suspend", "b", (True,))
          if no_reply:
              msg.header.flags |= MessageFlag.no_reply_expected
          conn.send(msg, serial=serial)
          reply = wait_for_reply(serial) if wait else None

          get_session = new_method_call(LOGIN1, "GetSession", "s", ("x",))
          conn.send(get_session, serial=serial)
          wait_for_reply(serial)

          return reply


      # (a) Answered by hostnamed itself; a bus error here would leave
      # nothing forged.
      decoy_reply = forge_suspend(DECOY, 1001)
      sender = decoy_reply.header.fields.get(HeaderFields.sender)
      assert sender != "org.freedesktop.DBus", f"vacuous: from {sender}"

      # (b) No reply expected, so the bus refuses it without answering.
      forge_suspend(LOGIN1, 1002, no_reply=True, wait=False)

      # (c) Refused by the bus, with an answer.
      forge_suspend(LOGIN1, 1003)
    '';

  suspendAs = user: flags: "runuser -u ${user} -- ${pkgs.dbus}/bin/dbus-send --system ${flags} --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:true";
in
  pkgs.testers.runNixOSTest {
    name = "steam-console-idle";

    nodes.machine = {...}: {
      imports = [../../options.nix ./on-demand.nix];

      steamConsole = {
        enable = true;
        start = "controller";
      };

      users.users.steam.isNormalUser = true;
      users.users.other.isNormalUser = true;

      # Stand-in for Jovian's display manager.
      systemd.services.display-manager = {
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };

      # Masked as on halo, so logind refuses every Suspend.
      systemd.targets = {
        sleep.enable = false;
        suspend.enable = false;
      };

      # halo runs dbus-broker; dbus-monitor's BecomeMonitor differs per bus.
      services.dbus.implementation = "broker";
    };

    testScript = let
      suspend = suspendAs "steam" "--print-reply --reply-timeout=2000" + " || true";
      otherSuspendPrint = suspendAs "other" "--print-reply --reply-timeout=2000";
      otherSuspendNoReply = suspendAs "other" "";
    in ''
      suspend = "${suspend}"


      def attack():
          # The broker's refusal text; logind's own says "Permission denied".
          status, out = machine.execute("${otherSuspendPrint} 2>&1")
          assert status != 0, out
          assert "org.freedesktop.DBus.Error.AccessDenied" in out, out
          assert "Sender is not authorized to send message" in out, out

          machine.succeed("${otherSuspendNoReply}")
          machine.succeed("runuser -u other -- ${forge}")


      machine.wait_for_unit("display-manager.service")
      machine.wait_for_unit("steam-console-idle.service")

      # Game running: keep Gaming Mode, restart only the console user's UI.
      machine.succeed(
          "systemd-run --uid=steam --unit=fake-reaper ${lib.getExe fakeReaper}"
      )
      machine.succeed(
          "systemd-run --uid=steam --unit=fake-webhelper ${lib.getExe fakeWebhelper}"
      )
      machine.succeed(
          "systemd-run --uid=other --unit=other-webhelper ${lib.getExe fakeWebhelper}"
      )

      # Both fakes must be up before the first Suspend, or the watcher sees no game.
      machine.wait_until_succeeds("pgrep -u steam -x reaper")
      machine.wait_until_succeeds("pgrep -u steam -x steamwebhelper")

      # Any logind refusal counts, not just the masked target: here another
      # uid's block inhibitor makes logind refuse steam's call earlier, and
      # the UI is stranded all the same. The masked-target refusal is covered
      # below, once the inhibitor is gone.
      machine.succeed(
          "systemd-run --unit=blocker ${pkgs.systemd}/bin/systemd-inhibit "
          + "--who=blocker --what=sleep --mode=block "
          + "${pkgs.coreutils}/bin/sleep infinity"
      )
      machine.wait_until_succeeds(
          "systemd-inhibit --list --no-legend | grep -q blocker"
      )
      machine.wait_until_succeeds(f"{suspend}; test -e /tmp/term-steam", timeout=60)
      machine.sleep(5)  # let any Suspend queued by the retry loop fully drain.
      machine.succeed("systemctl stop blocker.service")

      machine.succeed("systemctl is-active display-manager.service")
      machine.fail("test -e /tmp/term-other")
      machine.succeed("systemctl is-active other-webhelper.service")
      machine.succeed(
          "journalctl -u steam-console-idle.service | grep -q 'keeping Gaming Mode'"
      )

      # Non-console callers, game running: must not restart Steam's UI.
      machine.succeed("rm -f /tmp/term-steam")
      machine.succeed(
          "systemd-run --uid=steam --unit=fake-webhelper2 ${lib.getExe fakeWebhelper}"
      )
      machine.wait_until_succeeds("pgrep -u steam -x steamwebhelper")

      _, out = machine.execute(
          "journalctl -u steam-console-idle.service | grep -c 'Steam requested sleep'"
      )
      n = int(out.strip() or "0")

      attack()
      machine.sleep(3)

      machine.fail("test -e /tmp/term-steam")
      machine.succeed("systemctl is-active fake-webhelper2.service")
      _, out = machine.execute(
          "journalctl -u steam-console-idle.service | grep -c 'Steam requested sleep'"
      )
      assert int(out.strip() or "0") == n

      machine.succeed("systemctl stop fake-webhelper2.service")
      machine.succeed("rm -f /tmp/term-steam")  # its TERM trap touches the marker.

      # No webhelper left to signal: the watcher must log it and keep running.
      machine.sleep(5)  # let queued Suspend retries drain first.
      _, out = machine.execute(
          "journalctl -u steam-console-idle.service | grep -c 'no Steam UI process to restart'"
      )
      n = int(out.strip() or "0")

      machine.succeed(suspend)

      def restart_attempted(_):
          _, out = machine.execute(
              "journalctl -u steam-console-idle.service | grep -c 'no Steam UI process to restart'"
          )
          return int(out.strip() or "0") > n

      retry(restart_attempted)

      machine.succeed("systemctl is-active steam-console-idle.service")
      restarts = machine.succeed(
          "systemctl show -p NRestarts --value steam-console-idle.service"
      )
      assert restarts.strip() == "0", f"steam-console-idle restarted: {restarts!r}"

      # Non-console callers, no game: must not stop Gaming Mode either.
      machine.succeed("systemctl stop fake-reaper.service")

      _, out = machine.execute(
          "journalctl -u steam-console-idle.service | grep -c 'Steam requested sleep'"
      )
      n = int(out.strip() or "0")

      attack()
      machine.sleep(3)

      machine.succeed("systemctl is-active display-manager.service")
      _, out = machine.execute(
          "journalctl -u steam-console-idle.service | grep -c 'Steam requested sleep'"
      )
      assert int(out.strip() or "0") == n

      # No game: Gaming Mode stops.
      machine.wait_until_fails(
          f"{suspend}; systemctl is-active display-manager.service", timeout=60
      )

      # The machine never actually suspends.
      machine.fail("systemctl is-active suspend.target")
      machine.fail("journalctl -k | grep -q 'PM: suspend entry'")
    '';
  }
