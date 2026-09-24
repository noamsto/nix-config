"""Telegram slash commands that print the scout's reports as money wrote them.

A plugin command answers without the LLM, so what the user reads is exactly
the file on disk. Replies are standard Markdown, which the Hermes Telegram
adapter converts. @reportDir@ is substituted at build time.
"""

import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPORT_DIR = Path("@reportDir@")
TZ = ZoneInfo("Asia/Jerusalem")
# Telegram rejects a message over 4096 characters; leave room for the notice
# and the Markdown escapes the adapter adds.
LIMIT = 3500
JOBS = {"watch": "Watch", "crowd": "Digest"}


def _read(name):
    try:
        return (REPORT_DIR / name).read_text()
    except FileNotFoundError:
        return None


def _status():
    raw = _read("status.json")
    return json.loads(raw) if raw else {}


def _today():
    return datetime.now(TZ).date().isoformat()


def _day(iso):
    return datetime.fromisoformat(iso).strftime("%a %-d %b")


def _clip(text):
    return text if len(text) <= LIMIT else text[:LIMIT] + "\n\n*… cut: the report is longer than one message*"


def _problem(job, today):
    s = _status().get(job)
    if not s:
        return "never run"
    if s.get("date") != today:
        return f"no run today, last run {_day(s['date'])}" if s.get("date") else "no run today"
    if s.get("running"):
        return f"still running since {s.get('startedAt', '?')}"
    if not s.get("ok"):
        return f"failed today: {s.get('error', 'unknown error')}"
    return None


def _report(job, name, empty):
    body = _read(name)
    if body is None:
        return f"*No {JOBS[job].lower()} report yet.*"
    problem = _problem(job, _today())
    text = body.strip() or f"*{empty}*"
    return _clip(f"⚠️ *{JOBS[job]}: {problem}. Showing the last report.*\n\n{text}" if problem else text)


def _watch(_args):
    return _report("watch", "watch.txt", "Nothing fired today.")


def _digest(_args):
    return _report("crowd", "crowd.md", "The digest is empty.")


def _holdings(_args):
    raw = _read("holdings.json")
    if raw is None:
        return "*No holdings snapshot yet.*"
    h = json.loads(raw)
    rows = sorted(h.get("positions", []), key=lambda p: p.get("weightPct", 0), reverse=True)
    # Rich messages render this as a table; without them the adapter turns it into bullets.
    table = "\n".join(
        ["| | Position | Weight | Value |", "|---|---|---:|---:|"]
        + [f"| {'💵' if p.get('isCash') else '📈' if p.get('usListed') else '🏦'} | {p['symbol']} "
           f"| {p.get('weightPct', 0):.1f}% | ₪{p.get('valueIls', 0):,.0f} |" for p in rows])
    head = f"💼 **Holdings · {_day(h['date'])}**" if h.get("date") else "💼 **Holdings**"
    stale = "\n> ⚠️ From a stale sync; the broker data may be behind." if h.get("stale") else ""
    return _clip(f"{head}\nTotal **₪{h.get('totalIls', 0):,.0f}**{stale}\n\n{table}\n\n*📈 US stock · 🏦 fund · 💵 cash*")


def _scoutstatus(_args):
    today = _today()
    status = _status()
    lines = [f"**🩺 Scout status · {_day(today)}**"]
    for job, label in JOBS.items():
        problem = _problem(job, today)
        if problem:
            lines.append(f"⚠️ **{label}**: {problem}")
            continue
        done = status[job].get("finishedAt")
        at = datetime.fromisoformat(done.replace("Z", "+00:00")).astimezone(TZ).strftime("%H:%M") if done else "?"
        lines.append(f"✅ **{label}**: ran today at {at}")
    return "\n".join(lines)


def register(ctx):
    ctx.register_command("watch", handler=_watch, description="Today's watch report")
    ctx.register_command("digest", handler=_digest, description="The latest opportunity digest")
    ctx.register_command("holdings", handler=_holdings, description="Current positions by weight")
    ctx.register_command("scoutstatus", handler=_scoutstatus, description="Did today's scout runs succeed")
