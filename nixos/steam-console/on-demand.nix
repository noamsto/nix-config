{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.steamConsole;
  systemctl = "${pkgs.systemd}/bin/systemctl";

  # The single "never stop mid-game" check, shared by the stop paths and the
  # idle keep branch below. Steam runs every game (and non-Steam shortcut) as
  # a child of its own `reaper` process, which exits with the game — nothing
  # else needs checking, and in particular no stop path reads the controller,
  # so a flat pad battery can never end a session.
  gameRunning = pkgs.writeShellApplication {
    name = "steam-console-game-running";
    runtimeInputs = [pkgs.procps];
    text = "pgrep -u ${cfg.user} -x reaper >/dev/null";
  };

  stop = pkgs.writeShellApplication {
    name = "steam-console-stop";
    runtimeInputs = [pkgs.systemd];
    text = ''
      reason="$1"

      if ${lib.getExe gameRunning}; then
        echo "$reason, but a game is running — keeping Gaming Mode"
        exit 0
      fi

      echo "$reason — stopping Gaming Mode"
      # --no-block: steam-console-idle is PartOf the DM it's stopping here, so
      # a blocking call would deadlock waiting on its own unit's stop job.
      # Residual race: a game launched between the reaper check above and
      # this queued stop landing is not protected.
      systemctl stop --no-block display-manager.service
    '';
  };

  # Watcher for one joystick device node, run per-device by the
  # steam-console-wake@ template below. flake8 runs over this at build time,
  # so the interpolated store path is wrapped to stay inside its line limit.
  wake =
    pkgs.writers.writePython3 "steam-console-wake" {
      libraries = [pkgs.python3Packages.evdev];
    } ''
      import subprocess
      import sys

      import evdev

      SYSTEMCTL = (
          "${systemctl}"
      )

      # No EVIOCGRAB: reads without exclusive access, so Steam's own input
      # handling of this device is left untouched. A start while the display
      # manager is already active is a systemd no-op.
      dev = evdev.InputDevice(sys.argv[1])
      for event in dev.read_loop():
          is_home_press = (
              event.type == evdev.ecodes.EV_KEY
              and event.code == evdev.ecodes.BTN_MODE
              and event.value == 1
          )
          if is_home_press:
              subprocess.run(
                  [SYSTEMCTL, "start", "--no-block",
                   "display-manager.service"],
                  check=False,
              )
    '';

  # Steam's idle sleep is a dbus-send Suspend call to logind, made from
  # inside the console user's session (#219: the actual suspend targets
  # stay masked, so logind refuses it — this only reacts to the request,
  # either stopping Gaming Mode or, mid-game, restarting Steam's UI).
  # *WithFlags members cover recent systemd's `systemctl suspend`, in case
  # anything besides Steam ever issues one on halo.
  sleepMembers = [
    "Suspend"
    "Hibernate"
    "HybridSleep"
    "SuspendThenHibernate"
    "Sleep"
    "SuspendWithFlags"
    "HibernateWithFlags"
    "HybridSleepWithFlags"
    "SuspendThenHibernateWithFlags"
  ];
  dbusMatchArgs = lib.escapeShellArgs (map (
      member: "type='method_call',interface='org.freedesktop.login1.Manager',member='${member}'"
    )
    sleepMembers);

  idle = pkgs.writeShellApplication {
    name = "steam-console-idle";
    runtimeInputs = [pkgs.dbus pkgs.procps pkgs.coreutils stop];
    text = ''
      dbus-monitor --system ${dbusMatchArgs} | while read -r line; do
        case "$line" in
        "method call "*)
          if ${lib.getExe gameRunning}; then
            echo "Steam requested sleep (idle), but a game is running — keeping Gaming Mode, restarting Steam's UI"
            sleep 1
            # The refused sleep means Steam's resume never comes, so a fresh UI
            # is the only way out — Steam relaunches its webhelper, as Decky does.
            pkill -TERM -u ${cfg.user} -x steamwebhelper || echo "no Steam UI process to restart"
          else
            steam-console-stop "Steam requested sleep (idle)"
          fi
          ;;
        esac
      done
    '';
  };

  tvOff = pkgs.writeShellApplication {
    name = "steam-console-tv-off";
    runtimeInputs = [pkgs.coreutils pkgs.systemd stop];
    text = ''
      systemctl is-active --quiet display-manager.service || exit 0

      # Debounce: mode-set/link-training flaps and TV input switches that
      # come straight back shouldn't stop Gaming Mode.
      sleep 60

      for f in /sys/class/drm/card*-*/status; do
        read -r status <"$f"
        # Writeback pseudo-connectors report "unknown", never "connected" —
        # match the literal value so those never count as still connected.
        if [ "$status" = "connected" ]; then
          exit 0
        fi
      done

      steam-console-stop "no display connected (TV off)"
    '';
  };

  # display-manager.service Conflicts=autovt@tty1.service, so starting
  # Gaming Mode kills getty@tty1 and nothing ever brings it back on stop —
  # a headless TV just holds the last frame with no local console left.
  # ExecStopPost runs before systemd decides whether to restart the unit, so
  # SERVICE_RESULT can't distinguish a clean stop from a restart (or a crash
  # that Restart=always is about to revive) — the only reliable signal is
  # whether the DM is still down a few seconds later. Waiting here also keeps
  # the getty start from racing a pending DM restart.
  vtRestore = pkgs.writeShellApplication {
    name = "steam-console-vt-restore";
    runtimeInputs = [pkgs.kbd pkgs.systemd];
    text = ''
      sleep 3
      systemctl is-active --quiet display-manager.service && exit 0

      chvt 1 || true
      systemctl start --no-block autovt@tty1.service
    '';
  };
in {
  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.start != "boot") {
      # Run as its own unit, not inline in ExecStopPost, so the DM's stop job
      # isn't held open for the 3s wait above and the wait runs in its own
      # cgroup.
      systemd.services.display-manager.serviceConfig.ExecStopPost = "-${systemctl} start --no-block steam-console-vt-restore.service";

      systemd.services.steam-console-vt-restore = {
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe vtRestore;
          NoNewPrivileges = true;
          ProtectHome = true;
        };
      };
    })
    (lib.mkIf (cfg.enable && cfg.start == "controller") {
      # Why match the joystick property, not VID/PID or an event number: the
      # dongle enumerates persistently and pad power on/off emits no udev
      # event at all (only its own key presses do), so presence-based rules
      # would never fire — the input has to be watched instead. Steam's own
      # uinput virtual pads match this rule too; harmless, since starting an
      # already-running display manager is a no-op.
      services.udev.extraRules = ''
        ACTION!="remove", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", TAG+="systemd"
        ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", ENV{SYSTEMD_WANTS}+="steam-console-wake@%k.service"
        ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", RUN+="${systemctl} start --no-block steam-console-tv-off.service"
      '';

      # Shared budget for every per-device watcher below.
      systemd.slices.steam-console-wake = {
        sliceConfig = {
          TasksMax = 32;
          MemoryMax = "512M";
        };
      };

      systemd.services = {
        "steam-console-wake@" = {
          description = "Watch %i for a controller Home-button press";
          bindsTo = ["dev-input-%i.device"];
          after = ["dev-input-%i.device"];
          serviceConfig = {
            ExecStart = "${wake} /dev/input/%I";
            # A crashed watcher shouldn't leave the Home button dead until
            # reboot; BindsTo above still stops it when the device is removed.
            Restart = "on-failure";
            RestartSec = 1;
            NoNewPrivileges = true;
            ProtectHome = true;
            PrivateNetwork = true;
            # Any joystick spawns a root watcher — including uinput pads the
            # console user can create, since it gets uaccess on /dev/uinput —
            # so cap the total rather than trust the device.
            Slice = "steam-console-wake.slice";
          };
        };

        steam-console-idle = {
          wantedBy = ["display-manager.service"];
          partOf = ["display-manager.service"];
          after = ["display-manager.service"];
          serviceConfig = {
            ExecStart = lib.getExe idle;
            NoNewPrivileges = true;
            ProtectHome = true;
            # Losing the bus exits the pipeline, which would leave idle-stop
            # dead for the rest of the session. PartOf teardown is a
            # systemd-initiated stop, so it never restarts through that path.
            Restart = "on-failure";
            RestartSec = 1;
          };
        };

        steam-console-tv-off = {
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe tvOff;
            NoNewPrivileges = true;
            ProtectHome = true;
          };
        };
      };
    })
  ];
}
