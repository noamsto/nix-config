---
description: "Review a PR with all matching reviewers, dedupe across them, post one review of mechanical findings; surface architectural decisions in chat"
argument-hint: "[PR number | URL] [--dry-run] [--yes]"
---

# PR Review: Multi-Reviewer → One Deduped Review

You take a single PR, run every reviewer that matches the diff, merge their findings so nothing is repeated, and split the result into two streams: **mechanical fixes** become one inline review on the PR; **architectural decisions** are surfaced to the user in chat for a human call. You coordinate and synthesize — the reviewer agents do the reviewing.

The downstream consumer of the posted review is often an **agent** (e.g. `/finish-prs`), so the posted findings must be structured, line-anchored, and independently resolvable — not a wall of text.

**Argument:** `$ARGUMENTS`

Parse:

- **PR ref** (first non-flag token): a number (`1942`) or URL. If omitted, resolve the PR for the current branch: `gh pr view --json number,url,baseRefName,headRefName,author -q .`
- `--dry-run` — do everything except post; print the full report to chat and stop. Never asks.
- `--yes` — skip the confirm gate and post immediately after triage (for autopilot / agent use). Mutually exclusive with `--dry-run`.

If no PR can be resolved, abort with a friendly error.

---

## Step 1: Resolve the PR

```bash
gh pr view <PR> --json number,url,baseRefName,headRefName,author,isDraft,title -q .
gh pr diff <PR> --name-only          # changed files
gh pr diff <PR>                      # full diff (for the reviewers)
```

Record `baseRefName`, the changed-file list, and `author.login`.

**Author check:** if `author.login` is not the current user (`gh api user -q .login`), note it — this is someone else's PR and posting a review under your identity is a different act. Require an explicit confirm before posting regardless of `--yes` (mention it in the gate).

---

## Step 2: Map files → reviewers

Match changed files to reviewer agents (from `~/.claude/CLAUDE.md` / `CLAUDE.local.md`):

| Files in diff | Reviewer agent |
|---|---|
| `*.go` | `go-reviewer` |
| `*.ts` `*.tsx` `*.js` `*.jsx` `*.mjs` `*.cjs` | `typescript-reviewer` |
| `*.sql` or any path under `migrations/` | `database-reviewer` |

A reviewer runs only if the diff actually contains its file types. **Zero matches and zero gaps (Step 3)** → report "no reviewers matched this diff" and stop.

---

## Step 3: Detect reviewer gaps

Look at the changed files for any **source-code language with no matching reviewer** above that is a *meaningful chunk* of the diff — roughly **≥3 files** or a substantial line count. Ignore one-off config / lockfile / docs touches.

Examples worth flagging: a batch of `*.py`, `*.rs`, `*.tf`, Helm chart `*.yaml`, `*.proto`, shell scripts.

Hold these gaps for **Step 8** — do not interrupt the review flow.

---

## Step 4: Dispatch matched reviewers (parallel)

Dispatch one `Agent` call **per matched reviewer, directly from this session** (not via a meta-agent — meta-agents fall back to weak inline review). Send all the calls in one message so they run concurrently. Scope each reviewer to its own file subset.

Tell each reviewer to return findings as a structured list, one finding per item:

```
- file: <path>
  line: <line number in the new file, or null if not line-local>
  severity: <blocker | should-fix | nit>
  class: <mechanical | architectural>
  what: <one sentence: what is wrong>
  fix: <one sentence: the concrete fix, or the decision to make>
```

`class: architectural` = a design/contract/layering/duplication decision that has more than one defensible answer. `class: mechanical` = a local, unambiguous fix.

---

## Step 5: Dedupe + triage

In this session, merge all reviewers' findings:

1. **Collapse overlaps** — same `file`+`line`, or the same root cause flagged by two reviewers. Keep the clearest wording; append "(also flagged by `<reviewer>`)".
2. **Filter to actionable + real** — drop nits, pure style, and "consider…" musings. A survivor must name *what's wrong* **and** *the fix/decision*. If `--yes`/autopilot, keep `should-fix` and `blocker`; drop `nit`.
3. **Split by class:**
   - **mechanical** → candidates for inline PR comments
   - **architectural** → decision stream (chat only, Step 6)

---

## Step 6: Report in chat + confirm

Print two sections to chat, concise — no walls of text:

**A. Architectural decisions (not posted — your call):**
For each, write a **short human-readable context** the user can decide from quickly:
> **`<file>` — <one-line title>**
> What: <the tension / why it matters, 1–2 sentences>
> Options: <the realistic choices>
> Recommendation: <your call, one line>

These are never posted to the PR. The user decides what to do with each.

**B. Mechanical findings (to be posted):**
A tight list — `path:line — what → fix`, severity-ordered. This is the tally that will become the inline review.

**Gate:**
- `--dry-run` → stop here. Nothing is posted.
- `--yes` *and* author is you → post (Step 7) without asking.
- Otherwise (default, or any non-author PR) → ask: *"Post N mechanical findings as one review on PR #X? [yes / dry-run / edit]"*. Wait for the answer.

If **no mechanical findings survive triage** → post nothing to the PR; say so in chat (architectural decisions, if any, are still shown in section A).

---

## Step 7: Post one review

Single call — one review event, not N comment spams:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews \
  -f event=COMMENT \
  -f body='<summary>' \
  -f 'comments[][path]=...' -F 'comments[][line]=...' -f 'comments[][body]=...'   # repeat per finding
```

- `comments[]` ← line-local mechanical findings, each `path` + `line` + a short `body` (`what` + `fix`).
- `body` ← a one-line tally (`N findings: …`) plus any mechanical finding whose `line` is null (can't anchor) written as `path — what → fix`.
- `event: COMMENT` — advisory, never `REQUEST_CHANGES`.

Architectural findings are **not** included anywhere in the posted review.

Echo the posted tally + the review URL to chat.

---

## Step 8: Reviewer-gap suggestion

For each gap from Step 3, report it plainly:

> No `<x>-reviewer` for <N> changed `<lang>` files in this diff.

Then ask whether to create one. **On yes:**

1. Write `~/.claude/agents/<x>-reviewer.md`, modeled on `~/.claude/agents/go-reviewer.md`:
   - Frontmatter: `name`, a `description` ending in "Use for all `<lang>` code changes.", `tools: ["Read", "Grep", "Glob", "Bash"]`, `model: sonnet`.
   - Body: a focused `<lang>` reviewer system prompt (idioms, common bugs, the language's lint/vet tooling, the "When invoked" steps pattern).
2. Offer to run the new reviewer on **this same PR** and fold its findings back through Steps 4–7.

Never write an agent file without the user's yes.
