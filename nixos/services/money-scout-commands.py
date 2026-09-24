"""Telegram slash commands that print the scout's reports as money wrote them.

A plugin command answers without the LLM, so what the user reads is exactly
the file on disk. @reportDir@ is substituted at build time.
"""

import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPORT_DIR = Path("@reportDir@")
TZ = ZoneInfo("Asia/Jerusalem")
# Telegram rejects a message over 4096 characters; leave room for the notice.
LIMIT = 3900


def _read(name):
    try:
        return (REPORT_DIR / name).read_text()
    except FileNotFoundError:
        return None


def _status():
    raw = _read("status.json")
    return json.loads(raw) if raw else {}


def _clip(text):
    return text if len(text) <= LIMIT else text[:LIMIT] + "\n… (cut: the report is longer than one message)"


def _state(job, today):
    s = _status().get(job)
    if not s:
        return f"{job}: never run"
    if s.get("date") != today:
        return f"{job}: no run today (last run {s.get('date', '?')})"
    if s.get("running"):
        return f"{job}: still running (started {s.get('startedAt', '?')})"
    if not s.get("ok"):
        return f"{job}: failed today — {s.get('error', 'unknown error')}"
    return None


def _report(job, name, empty):
    today = datetime.now(TZ).date().isoformat()
    body = _read(name)
    if body is None:
        return f"No {job} report yet."
    problem = _state(job, today)
    text = body.strip() or empty
    return _clip(f"⚠ {problem} — showing the last report\n\n{text}" if problem else text)


def _watch(_args):
    return _report("watch", "watch.txt", "Nothing fired today.")


def _digest(_args):
    return _report("crowd", "crowd.md", "The digest is empty.")


def _holdings(_args):
    raw = _read("holdings.json")
    if raw is None:
        return "No holdings snapshot yet."
    h = json.loads(raw)
    rows = sorted(h.get("positions", []), key=lambda p: p.get("weightPct", 0), reverse=True)
    lines = [f"{p['symbol']}  {p.get('weightPct', 0):.1f}%" for p in rows]
    stale = " (stale sync)" if h.get("stale") else ""
    head = f"Holdings {h.get('date', '?')}{stale} · total ₪{h.get('totalIls', 0):,.0f}"
    return _clip("\n".join([head, *lines]))


def _scoutstatus(_args):
    today = datetime.now(TZ).date().isoformat()
    status = _status()
    lines = []
    for job in ("watch", "crowd"):
        problem = _state(job, today)
        if problem:
            lines.append(problem)
            continue
        done = status[job].get("finishedAt")
        at = datetime.fromisoformat(done.replace("Z", "+00:00")).astimezone(TZ).strftime("%H:%M") if done else "?"
        lines.append(f"{job}: ok today at {at}")
    return "\n".join(lines)


def register(ctx):
    ctx.register_command("watch", handler=_watch, description="Today's watch report")
    ctx.register_command("digest", handler=_digest, description="The latest opportunity digest")
    ctx.register_command("holdings", handler=_holdings, description="Current positions by weight")
    ctx.register_command("scoutstatus", handler=_scoutstatus, description="Did today's scout runs succeed")
