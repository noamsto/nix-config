"""Telegram slash commands that print the scout's reports as money wrote them.

A plugin command answers without the LLM, so what the user reads is exactly
the file on disk. Replies are standard Markdown, which the Hermes Telegram
adapter converts. @reportDir@ is substituted at build time.
"""

import json
import os
import re
import time
from datetime import UTC, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPORT_DIR = Path("@reportDir@")
TZ = ZoneInfo("Asia/Jerusalem")
# Telegram rejects a message over 4096 characters; leave room for the notice
# and the Markdown escapes the adapter adds.
LIMIT = 3500
JOBS = {"watch": "Watch", "crowd": "Digest"}
# The path unit starts the runner within seconds, so a request this old means it failed to start.
WAITING_MIN = 10
# Two requests at 10 min each, plus the snapshot and a devshell rebuild.
STUCK_MIN = 40


def _read(name):
    try:
        return (REPORT_DIR / name).read_text()
    except FileNotFoundError:
        return None


def _status():
    raw = _read("status.json")
    return json.loads(raw) if raw else {}


def _now():
    return time.time()


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
        at = datetime.fromisoformat(done).astimezone(TZ).strftime("%H:%M") if done else "?"
        lines.append(f"✅ **{label}**: ran today at {at}")
    for p in _requests():
        if _now() - p.stat().st_mtime > WAITING_MIN * 60:
            lines.append(
                f"⚠️ **Research**: request {p.stem} waiting > {WAITING_MIN} min. The runner may have failed. "
                "On halo: `systemctl --user status money-scout-research` and "
                "`systemctl --user reset-failed money-scout-research.path money-scout-research.service`")
    # ctime, not mtime: claiming renames the file, so the age counts from the claim.
    stuck = [p.name.removesuffix(".request.json") for p in _in_flight()
             if _now() - p.stat().st_ctime > STUCK_MIN * 60]
    if stuck:
        lines.append(f"⚠️ **Research**: stuck: {', '.join(stuck)}")
    pins = json.loads(_read("research/pins.json") or "[]")
    if pins:
        lines.append("📌 **Research pins**: " + " · ".join(f"{p['ticker']} ≤${p['buyBelow']:g} until {_day(p['expires'])}" for p in pins))
    return "\n".join(lines)


TICKER = re.compile(r"^[A-Z][A-Z0-9.-]{0,9}$")
MAX_PENDING = 2
MAX_PER_DAY = 5


def _requests():
    return sorted((REPORT_DIR / "requests").glob("*.json"))


def _in_flight():
    """Claimed by the runner but with no report or error yet."""
    research = REPORT_DIR / "research"
    return [p for p in research.glob("*.request.json")
            if not (research / p.name.replace(".request.json", ".md")).exists()
            and not (research / p.name.replace(".request.json", ".error")).exists()]


def _queue(kind, ticker):
    now = datetime.now(UTC)
    stamp = now.strftime("%Y%m%dT%H%M%S")
    pending = len(_requests()) + len(_in_flight())
    if pending >= MAX_PENDING:
        return f"*{pending} research requests are already queued; try again when one lands.*"
    today = [p for p in [*_requests(), *(REPORT_DIR / "research").glob("*.request.json")] if p.name.startswith(stamp[:8])]
    if len(today) >= MAX_PER_DAY:
        return f"*{MAX_PER_DAY} research requests today already; the cap resets at midnight UTC.*"
    rid = f"{stamp}-ticker-{ticker}" if kind == "ticker" else f"{stamp}-review"
    body = json.dumps({"id": rid, "kind": kind, "ticker": ticker, "requested": now.isoformat()})
    tmp = REPORT_DIR / "requests" / f"{rid}.json.tmp"
    tmp.write_text(body)
    # Group-readable so the runner (the dir owner, in the money-scout group) can read it.
    os.chmod(tmp, 0o640)
    tmp.rename(REPORT_DIR / "requests" / f"{rid}.json")
    return None


def _research(args):
    ticker = (args or "").strip().upper()
    if not TICKER.match(ticker):
        return "Usage: `/research TICKER`, for example `/research AVGO`"
    return _queue("ticker", ticker) or f"Queued **{ticker}** research; the report lands here in about 3–5 min."


def _checkup(_args):
    return _queue("review", None) or "Queued the portfolio check-up; it lands here in about 3–5 min."


def register(ctx):
    ctx.register_command("watch", handler=_watch, description="Today's watch report")
    ctx.register_command("digest", handler=_digest, description="The latest opportunity digest")
    ctx.register_command("holdings", handler=_holdings, description="Current positions by weight")
    ctx.register_command("scoutstatus", handler=_scoutstatus, description="Did today's scout runs succeed")
    ctx.register_command("research", handler=_research, description="Research a ticker: buy, not now, or no")
    ctx.register_command("checkup", handler=_checkup, description="Portfolio check-up against the IPS")
