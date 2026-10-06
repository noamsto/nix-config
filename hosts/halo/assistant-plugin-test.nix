# Loads the ops plugin against stub systemctl/journalctl/halo-ops and checks
# the guards: argument validation, the confirm steps, the one-action-per-unit
# lock, the update request files, and the report after a restart or reboot.
# Hermes silently skips a plugin command that clashes with a built-in, so the
# registered names are also resolved against the pinned hermes.
{
  pkgs,
  hermesVenv,
}:
pkgs.runCommand "halo-assistant-plugin-test" {nativeBuildInputs = [pkgs.python3];} ''
  set -euo pipefail
  mkdir -p bin pending requests ops stub
  for cmd in systemctl journalctl halo-ops; do
    cat > bin/$cmd <<'EOF'
  #!/bin/sh
  echo "$(basename "$0") $*" >> "$STUB/calls"
  case "$(basename "$0") $1 $2 $3" in
    "systemctl show -P ActiveState") cat "$STUB/state-$4" 2>/dev/null || echo inactive ;;
    "systemctl show -P Result") cat "$STUB/result-$4" 2>/dev/null || echo success ;;
    "systemctl is-active"*) echo active ;;
    journalctl*) echo "last journal line" ;;
    halo-ops*) echo "uptime: fine" ;;
  esac
  exit "$(cat "$STUB/rc" 2>/dev/null || echo 0)"
  EOF
    chmod +x bin/$cmd
  done
  export PATH=$PWD/bin:$PATH STUB=$PWD/stub
  sed -e "s|@haloOps@|$PWD/bin/halo-ops|" -e "s|@pendingDir@|$PWD/pending|" \
    -e "s|@requestDir@|$PWD/requests|" -e "s|@opsState@|$PWD/ops|" ${./assistant-plugin.py} > plugin.py

  python3 - <<'EOF'
  import json, os, time
  import plugin

  sent = []
  plugin._send = sent.append

  class Now:
      """Runs the worker inline so each check sees the finished action."""
      def __init__(self, target, args, daemon):
          self.target, self.args = target, args
      def start(self):
          self.target(*self.args)

  plugin.threading.Thread = Now
  calls = lambda: open("stub/calls").read() if os.path.exists("stub/calls") else ""
  reset = lambda: os.path.exists("stub/calls") and os.remove("stub/calls")

  assert "Usage" in plugin._logs(""), "no unit"
  assert "Usage" in plugin._logs("-f lemond"), "option as unit"
  assert "Usage" in plugin._logs("lemond; rm"), "shell in unit"
  assert "Usage" in plugin._logs("lemond many"), "non-numeric lines"
  assert "last journal line" in plugin._logs("lemond 999")
  assert "-n 200 -u lemond" in calls(), calls()

  assert "Usage" in plugin._halorestart("sshd")
  assert "/reboot confirm" in plugin._reboot(""), "reboot needs confirm"
  assert "start" not in calls(), calls()

  open("stub/state-halo-rebuild.service", "w").write("activating")
  assert "is running" in plugin._reboot("confirm"), "no reboot during a rebuild"
  assert "already running" in plugin._rebuild(""), "a running unit is not started twice"
  assert "systemctl start" not in calls(), calls()
  os.remove("stub/state-halo-rebuild.service")

  reset()
  assert plugin._rebuild("").startswith("⏳")
  assert "systemctl start --no-ask-password halo-rebuild.service" in calls(), calls()
  assert sent.pop().startswith("✅ Rebuild finished"), "report on success"
  assert not os.listdir("pending"), "the finished action is cleared"

  open("stub/rc", "w").write("1")
  plugin._halorestart("ds4")
  assert "systemctl restart --no-ask-password ds4-server.service" in calls(), calls()
  report = sent.pop()
  assert report.startswith("❌ Restart of ds4 failed") and "last journal line" in report, report
  os.remove("stub/rc")

  fd = plugin._claim(plugin.PENDING / "halo-rebuild.service.json")
  assert "already running" in plugin._rebuild(""), "the pending lock blocks a second start"
  os.close(fd)

  assert "Usage" in plugin._haloupdate("nixpkgs;rm"), "bad input name"
  assert "No prepared update" in plugin._haloupdate("confirm")
  reset()
  plugin._haloupdate("nixpkgs hermes-agent")
  assert open("requests/update-inputs").read() == "nixpkgs\nhermes-agent\n"
  assert open("requests/update-skips").read() == ""
  assert "already up to date" in sent.pop(), "no candidate means nothing changed"
  open("ops/candidate.lock", "w").write("{}")
  open("ops/candidate.summary", "w").write("flake.lock: update nixpkgs")
  plugin._haloupdate("")
  assert open("requests/update-inputs").read() == "", "no names updates every input"
  out = sent.pop()
  assert "flake.lock: update nixpkgs" in out and "/haloupdate confirm" in out, out
  reset()
  plugin._haloupdate("confirm")
  assert "start --no-ask-password halo-update-push.service" in calls(), calls()
  sent.pop()

  plugin._reboot("confirm")
  assert not sent, "a reboot reports after the boot, not before"
  job = json.load(open("pending/halo-reboot.service.json"))
  assert job["kind"] == "reboot"

  plugin._boot_time = lambda: job["since"] + 60
  plugin._resume()
  assert sent.pop().startswith("✅ halo is back up"), "report after the reboot"
  assert not os.listdir("pending")

  # A rebuild that restarted the bot: the new process waits it out and reports.
  json.dump({"kind": "rebuild", "verb": "start", "unit": "halo-rebuild.service", "title": "Rebuild",
             "since": int(time.time())}, open("pending/halo-rebuild.service.json", "w"))
  open("stub/result-halo-rebuild.service", "w").write("exit-code")
  plugin._resume()
  assert sent.pop().startswith("❌ Rebuild failed"), "resumed watch reports the unit's result"
  print("ok")
  EOF

  HOME=$PWD ${hermesVenv}/bin/python3 - <<'EOF'
  from hermes_cli.commands import resolve_command
  import plugin

  class Ctx:
      names = []
      def register_command(self, name, **kw):
          self.names.append(name)
      def register_tool(self, **kw):
          pass

  plugin._resume = lambda: None
  ctx = Ctx()
  plugin.register(ctx)
  clashes = [n for n in ctx.names if resolve_command(n) is not None]
  assert not clashes, f"shadowed by hermes built-ins: {clashes}"
  print("no built-in clash")
  EOF
  touch $out
''
