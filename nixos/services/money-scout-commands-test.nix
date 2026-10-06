# Loads the plugin against a temp report dir and checks the research commands:
# ticker validation, the pending and daily caps, and the request file shape.
# Hermes silently skips a plugin command that clashes with a built-in, so the
# registered names are also resolved against the pinned hermes.
{
  pkgs,
  hermesVenv,
}:
pkgs.runCommand "money-scout-commands-test" {
  nativeBuildInputs = [pkgs.python3];
  TZDIR = "${pkgs.tzdata}/share/zoneinfo";
} ''
  set -euo pipefail
  mkdir -p scout/requests scout/research
  sed "s|@reportDir@|$PWD/scout|" ${./money-scout-commands.py} > plugin.py
  python3 - <<'EOF'
  import json, os, plugin

  out = plugin._research("avgo")
  assert out.startswith("Queued **AVGO**"), out
  [name] = os.listdir("scout/requests")
  req = json.load(open(f"scout/requests/{name}"))
  assert req["kind"] == "ticker" and req["ticker"] == "AVGO" and name == req["id"] + ".json", req

  assert "Usage" in plugin._research(""), "empty ticker"
  assert "Usage" in plugin._research("rm -rf /"), "bad ticker"

  out = plugin._checkup("")
  assert out.startswith("Queued the portfolio check-up"), out
  [rev] = [f for f in os.listdir("scout/requests") if f.endswith("-review.json")]
  assert json.load(open(f"scout/requests/{rev}"))["kind"] == "review", rev
  assert "already queued" in plugin._research("NVDA"), "pending cap of 2"

  for f in os.listdir("scout/requests"):
      os.rename(f"scout/requests/{f}", f"scout/research/{f[:-5]}.request.json")
      open(f"scout/research/{f[:-5]}.md", "w").write("done")
  plugin._research("MSFT"); plugin._research("NET")
  for f in os.listdir("scout/requests"):
      os.rename(f"scout/requests/{f}", f"scout/research/{f[:-5]}.request.json")
      open(f"scout/research/{f[:-5]}.md", "w").write("done")
  plugin._research("HOOD")
  assert "5 research requests today" in plugin._research("TSLA"), "daily cap of 5"
  print("ok")

  # Stalls show in /scoutstatus: an unclaimed request after 10 min, a claim with no report after 40.
  [waiting] = os.listdir("scout/requests")
  open("scout/research/20261006T000000-ticker-BRK.B.request.json", "w").write("{}")
  real = plugin._now()
  assert "waiting" not in plugin._scoutstatus("") and "stuck" not in plugin._scoutstatus(""), "fresh"
  plugin._now = lambda: real + 11 * 60
  out = plugin._scoutstatus("")
  assert f"request {waiting[:-5]} waiting > 10 min" in out and "reset-failed" in out, out
  assert "stuck" not in out, "a claim is not stuck at 11 min"
  plugin._now = lambda: real + 41 * 60
  assert "stuck: 20261006T000000-ticker-BRK.B" in plugin._scoutstatus(""), "stuck after 40 min"
  EOF
  HOME=$PWD ${hermesVenv}/bin/python3 - <<'EOF'
  from hermes_cli.commands import resolve_command
  import plugin

  class Ctx:
      names = []
      def register_command(self, name, **kw):
          self.names.append(name)

  ctx = Ctx()
  plugin.register(ctx)
  assert {"research", "checkup"} <= set(ctx.names), ctx.names
  clashes = [n for n in ctx.names if resolve_command(n) is not None]
  assert not clashes, f"shadowed by hermes built-ins: {clashes}"
  print("no built-in clash")
  EOF
  touch $out
''
