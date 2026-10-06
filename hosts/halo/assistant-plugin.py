"""Telegram ops commands and read-only status tools for halo's assistant bot.

The commands answer without the LLM. An action starts an existing halo-* unit
through polkit (systemctl, never sudo) on a worker thread and posts the
outcome to the chat when the unit finishes. Replies are standard Markdown,
which the Hermes Telegram adapter converts; the follow-ups go straight to the
Bot API as plain text, since they arrive after the command has returned.

@haloOps@, @pendingDir@, @requestDir@ and @opsState@ are substituted at build time.
"""

import fcntl
import json
import os
import re
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

HALO_OPS = "@haloOps@"
# One file per running action. A rebuild that changes this bot restarts it
# mid-action, and a reboot kills it; the next start resumes from these.
PENDING = Path("@pendingDir@")
REQUESTS = Path("@requestDir@")
OPS_STATE = Path("@opsState@")
# Telegram rejects a message over 4096 characters; leave room for the code fence.
LIMIT = 3500
UNIT = re.compile(r"^[A-Za-z0-9@._:-]+$")
INPUT = re.compile(r"^[A-Za-z0-9_-]+$")
RESTART = {"lemond": "lemond.service", "ds4": "ds4-server.service"}
ACTIONS = ["halo-rebuild.service", "halo-update-prepare.service", "halo-update-push.service"]


def _sh(*argv, timeout=60):
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)


def _busy(unit):
    # A running oneshot is "activating"; is-active would exit non-zero for it.
    state = _sh("systemctl", "show", "-P", "ActiveState", unit).stdout.strip()
    return state in ("activating", "deactivating", "reloading")


def _clip(text):
    # The end of a journal is what explains a failure, so keep the tail.
    return text if len(text) <= LIMIT else "…\n" + text[-LIMIT:]


def _block(text):
    return f"```\n{_clip(text.strip()) or '(no output)'}\n```"


def _send(text):
    data = urllib.parse.urlencode({
        "chat_id": os.environ["TELEGRAM_HOME_CHANNEL"],
        "text": _clip(text),
        "disable_web_page_preview": "true",
    }).encode()
    url = f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}/sendMessage"
    # After a reboot the gateway can start before Wi-Fi is up.
    for _ in range(30):
        try:
            urllib.request.urlopen(url, data=data, timeout=20).close()
            return
        except OSError:
            time.sleep(10)


def _journal(unit, since, lines=15):
    return _sh("journalctl", "--no-pager", "-o", "cat", "-n", str(lines),
               "-u", unit, "--since", f"@{since}").stdout.strip()


def _duration(since):
    d = int(time.time() - since)
    return f"{d // 60}m{d % 60:02d}s"


def _boot_time():
    for line in Path("/proc/stat").read_text().splitlines():
        if line.startswith("btime "):
            return int(line.split()[1])
    return 0


def _report(job, ok):
    took = _duration(job["since"])
    if ok and job["kind"] == "prepare":
        summary = OPS_STATE / "candidate.summary"
        if not (OPS_STATE / "candidate.lock").exists():
            return f"✅ flake inputs are already up to date ({took})."
        return (f"✅ Update candidate built and gated ({took}):\n\n{summary.read_text().strip()}\n\n"
                "Send /haloupdate confirm to commit and push it.")
    if ok and job["kind"] == "restart":
        states = "\n".join(f"{u}: {_sh('systemctl', 'is-active', u).stdout.strip()}" for u in RESTART.values())
        return f"✅ {job['title']} done ({took}).\n{states}"
    head = f"✅ {job['title']} finished ({took})." if ok else f"❌ {job['title']} failed after {took}."
    return f"{head}\n\n{_journal(job['unit'], job['since'])}"


def _claim(path):
    """Lock the action's file and return its fd, or None while another thread or process holds it."""
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o660)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return None
    return fd


def _finish(fd, path, job, started):
    keep = False
    try:
        if started:
            ok = _sh("systemctl", job["verb"], "--no-ask-password", job["unit"], timeout=None).returncode == 0
            # Keep the file: the boot after this reports back.
            keep = ok and job["kind"] == "reboot"
            if keep:
                return
        elif job["kind"] == "reboot" and _boot_time() > job["since"]:
            _send(f"✅ halo is back up.\n{_sh('uptime').stdout.strip()}")
            return
        else:
            while _busy(job["unit"]):
                time.sleep(10)
            ok = _sh("systemctl", "show", "-P", "Result", job["unit"]).stdout.strip() == "success"
        _send(_report(job, ok))
    finally:
        if not keep:
            path.unlink(missing_ok=True)
        os.close(fd)


def _start(kind, verb, unit, title, before=None):
    path = PENDING / f"{unit}.json"
    fd = _claim(path)
    if fd is not None and verb == "start" and _busy(unit):
        os.close(fd)
        fd = None
    if fd is None:
        return f"*{title} is already running.*"
    if before is not None:
        before()
    job = {"kind": kind, "verb": verb, "unit": unit, "title": title, "since": int(time.time())}
    os.ftruncate(fd, 0)
    os.pwrite(fd, json.dumps(job).encode(), 0)
    threading.Thread(target=_finish, args=(fd, path, job, True), daemon=True).start()
    return f"⏳ {title} started; I'll post the result here."


def _resume():
    for path in PENDING.glob("*.json"):
        fd = _claim(path)
        if fd is None:
            continue
        try:
            job = json.loads(os.pread(fd, 65536, 0))
        except ValueError:
            path.unlink(missing_ok=True)
            os.close(fd)
            continue
        threading.Thread(target=_finish, args=(fd, path, job, False), daemon=True).start()


def _write_request(name, lines):
    # The halo-ops CLI may own the current file; replace it rather than write through it.
    tmp = REQUESTS / f"{name}.{os.getpid()}.tmp"
    tmp.write_text("".join(f"{line}\n" for line in lines))
    tmp.replace(REQUESTS / name)


def _halostatus(_args):
    r = _sh(HALO_OPS, "status")
    return _block(r.stdout + r.stderr)


def _logs(args):
    words = (args or "").split()
    if not words or not UNIT.match(words[0]) or words[0].startswith("-") or len(words) > 2 \
            or (len(words) == 2 and not words[1].isdigit()):
        return "Usage: `/logs <unit> [lines]`, for example `/logs lemond 50`"
    lines = min(int(words[1]) if len(words) == 2 else 30, 200)
    return _block(_sh("journalctl", "--no-pager", "-n", str(lines), "-u", words[0]).stdout)


def _rebuild(_args):
    return _start("rebuild", "start", "halo-rebuild.service", "Rebuild")


def _haloupdate(args):
    words = (args or "").split()
    if words == ["confirm"]:
        if not (OPS_STATE / "candidate.lock").exists():
            return "*No prepared update; run /haloupdate first.*"
        return _start("push", "start", "halo-update-push.service", "Update push")
    if not all(INPUT.match(w) for w in words):
        return "Usage: `/haloupdate [input...]` to prepare, then `/haloupdate confirm` to push"

    def request():
        _write_request("update-inputs", words)
        _write_request("update-skips", [])

    return _start("prepare", "start", "halo-update-prepare.service",
                  f"Update of {', '.join(words)}" if words else "Update of all inputs", before=request)


def _reboot(args):
    if (args or "").strip() != "confirm":
        return "⚠️ This reboots halo. Send `/reboot confirm` to go ahead."
    running = [u for u in ACTIONS if _busy(u)]
    if running:
        return f"*{', '.join(running)} is running; reboot when it ends.*"
    return _start("reboot", "start", "halo-reboot.service", "Reboot")


def _halorestart(args):
    name = (args or "").strip()
    if name not in RESTART:
        return "Usage: `/halorestart lemond` or `/halorestart ds4` (starting one stops the other)"
    return _start("restart", "restart", RESTART[name], f"Restart of {name}")


def _tool_status(_params, **_kwargs):
    r = _sh(HALO_OPS, "status")
    return json.dumps({"status": r.stdout, "errors": r.stderr})


def _tool_logs(params, **_kwargs):
    unit = str(params.get("unit", ""))
    if not UNIT.match(unit) or unit.startswith("-"):
        return json.dumps({"error": f"invalid unit name: {unit!r}"})
    lines = min(int(params.get("lines", 50)), 200)
    return json.dumps({"unit": unit, "journal": _sh("journalctl", "--no-pager", "-n", str(lines), "-u", unit).stdout})


STATUS_SCHEMA = {
    "name": "halo_status",
    "description": "Current state of halo: uptime and load, the system generation and whether it is "
                   "the running one, failed units, the inference servers (lemond, ds4-server) and "
                   "the models lemond has loaded, and available memory.",
    "parameters": {"type": "object", "properties": {}},
}

LOGS_SCHEMA = {
    "name": "halo_logs",
    "description": "The most recent journal lines of one systemd unit on halo, e.g. lemond, "
                   "ds4-server, halo-rebuild, halo-update-prepare, hermes-assistant.",
    "parameters": {
        "type": "object",
        "properties": {
            "unit": {"type": "string", "description": "Unit name; .service may be omitted"},
            "lines": {"type": "integer", "description": "How many lines, at most 200 (default 50)"},
        },
        "required": ["unit"],
    },
}


def register(ctx):
    ctx.register_command("halostatus", handler=_halostatus, description="Uptime, generation, failed units, models")
    ctx.register_command("logs", handler=_logs, description="Recent journal of a unit", args_hint="<unit> [lines]")
    ctx.register_command("rebuild", handler=_rebuild, description="Pull main, build and switch halo")
    ctx.register_command("haloupdate", handler=_haloupdate, description="Update flake inputs; confirm to push",
                         args_hint="[input...|confirm]")
    ctx.register_command("reboot", handler=_reboot, description="Reboot halo (needs confirm)", args_hint="confirm")
    ctx.register_command("halorestart", handler=_halorestart, description="Restart lemond or ds4",
                         args_hint="<lemond|ds4>")
    ctx.register_tool(name="halo_status", toolset="halo", schema=STATUS_SCHEMA, handler=_tool_status)
    ctx.register_tool(name="halo_logs", toolset="halo", schema=LOGS_SCHEMA, handler=_tool_logs)
    PENDING.mkdir(parents=True, exist_ok=True)
    _resume()
