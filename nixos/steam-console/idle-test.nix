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
      suspend = ''runuser -u steam -- ${pkgs.dbus}/bin/dbus-send --system --print-reply --reply-timeout=2000 --dest=org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager.Suspend boolean:true || true'';
    in ''
      suspend = "${suspend}"

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

      machine.wait_until_succeeds(f"{suspend}; test -e /tmp/term-steam", timeout=60)
      machine.sleep(3)  # DM stop, if any, is --no-block.

      machine.succeed("systemctl is-active display-manager.service")
      machine.fail("test -e /tmp/term-other")
      machine.succeed("systemctl is-active other-webhelper.service")
      machine.succeed(
          "journalctl -u steam-console-idle.service | grep -q 'keeping Gaming Mode'"
      )

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

      # No game: Gaming Mode stops.
      machine.succeed("systemctl stop fake-reaper.service")
      machine.wait_until_fails(
          f"{suspend}; systemctl is-active display-manager.service", timeout=60
      )

      # The machine never actually suspends.
      machine.fail("systemctl is-active suspend.target")
      machine.fail("journalctl -k | grep -q 'PM: suspend entry'")
    '';
  }
