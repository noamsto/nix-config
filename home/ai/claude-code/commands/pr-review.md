---
description: "Review a PR with all matching reviewers, dedupe across them, post one review of mechanical findings; surface architectural decisions in chat"
argument-hint: "[PR number | URL] [--dry-run] [--yes]"
---

# PR Review: Multi-Reviewer → One Deduped Review

You take a single PR, run every reviewer that matches the diff, merge their findings so nothing is repeated, and split the result into three streams: **mechanical fixes** become one inline review on the PR; **architectural decisions** and **reader-comprehension findings** (code a human would misread — only genuinely ambiguous things) are surfaced to the user in chat for a human call before any posting. You coordinate and synthesize — the reviewer agents do the reviewing.

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
  class: <mechanical | architectural | clarity>
  what: <one sentence: what is wrong>
  fix: <one sentence: the concrete fix, or the decision to make>
```

`class: architectural` = a design/contract/layering/duplication decision that has more than one defensible answer. `class: mechanical` = a local, unambiguous fix. `class: clarity` = code that works but a human reader would misread or stumble over (see Reader Comprehension below).

Also instruct each reviewer to apply the **Reader Comprehension** lens and emit any survivors as `class: clarity` findings:

> **Reader Comprehension — raise only genuinely ambiguous things, not everything.**
>
> Default to silence. Raise a clarity finding ONLY when two competent readers *of this language* would genuinely disagree about what the code does or whether it is intentional. This is not a "could it be clearer?" sweep.
>
> **Smells to look for (only when genuinely ambiguous):** misleading names (name implies different behavior/type than reality); overloaded return/param semantics (one value meaning several things — `nil` = not-found *and* error *and* default; a bool that's really tri-state); hidden side effects (name/signature implies purity but it mutates an arg/global/disk/db); unstated invariants (correct only because of an ordering/nullness/caller contract written nowhere); surprising control flow (a buried early-return/`break`/fallthrough, or success returned from an error-shaped branch); magic values (a bare timeout/retry-cap/status-code/sentinel with no name/comment); action-at-a-distance (behavior depends on a global/env/earlier mutation with no local signal); comment ⇄ code drift (a comment asserting an invariant the code no longer backs).
>
> **The bar (gatekeeper):** a clarity finding survives only if it names the **concrete misread and its cost** — what a careful reader will wrongly conclude, and what breaks downstream. Phrase `what` as the misread, not a defect label: not "unclear name `count`" but "a reader will read `count` as the total and reuse it that way, but it's the remaining count → off-by-one." If you can only say "could be clearer" with no specific misread, it's style — drop it.
>
> **Do NOT flag:** idiomatic code that's standard for the language (even if terse); patterns consistent with the surrounding code; meaning recoverable from the immediate context; names that are merely imperfect but still clear; pure formatting. Prefer the few highest-confidence points over an exhaustive list; when unsure, drop it.
>
> **Judgment calls:** when you cannot tell whether something is a bug or deliberate, do not silently drop it and do not assert a fix — emit a `clarity` finding whose `fix` states the **open question and both readings** (e.g. "`getUser` returns `nil` on a DB timeout, same as not-found — intentional empty-state fallback, or a swallowed outage? A reader can't tell.").

---

## Step 5: Dedupe + triage

In this session, merge all reviewers' findings:

1. **Collapse overlaps** — same `file`+`line`, or the same root cause flagged by two reviewers. Keep the clearest wording; append "(also flagged by `<reviewer>`)".
2. **Filter to actionable + real** — drop nits, pure style, and "consider…" musings. A survivor must name *what's wrong* **and** *the fix/decision*. A `clarity` finding survives only if it clears the misread+cost bar (Step 4) — apply that bar strictly here too; "could be clearer" with no concrete misread is style, drop it. If `--yes`/autopilot, keep `should-fix` and `blocker`; drop `nit`.
3. **Split by class:**
   - **mechanical** → candidates for inline PR comments
   - **architectural** → decision stream (chat only, Step 6 §A)
   - **clarity** → comprehension stream (chat only, Step 6 §C) — never auto-posted; raised to the user before any posting

---

## Step 6: Report in chat + confirm

Print these sections to chat, concise — no walls of text:

**A. Architectural decisions (not posted — your call):**
For each, write a **short human-readable context** the user can decide from quickly:
> **`<file>` — <one-line title>**
> What: <the tension / why it matters, 1–2 sentences>
> Options: <the realistic choices>
> Recommendation: <your call, one line>

These are never posted to the PR. The user decides what to do with each.

**B. Mechanical findings (to be posted):**
A tight list — `path:line — what → fix`, severity-ordered. This is the tally that will become the inline review.

**C. Reader comprehension (not posted — raised for your call):**
Clarity findings that cleared the bar, each as `path:line — the misread & cost → fix or open question`. These are **raised to you here before any posting** — never auto-posted. Keep this list short; if it runs long, the bar wasn't applied strictly enough.

**Gate:**
- `--dry-run` → stop here. Nothing is posted.
- `--yes` *and* author is you → post mechanical findings (Step 7) without asking. **Clarity findings are never auto-posted** — list them in §C only.
- Otherwise (default, or any non-author PR) → ask: *"Post N mechanical findings as one review on PR #X? (M reader-comprehension findings in §C — say which, if any, to include.) [yes / dry-run / edit]"*. Wait for the answer. If the user names clarity findings to include, fold them into the posted review as `[clarity]`-tagged comments.

If **no mechanical findings survive triage** → post nothing to the PR by default; say so in chat (architectural and reader-comprehension findings, if any, are still shown in §A and §C).

---

## Step 7: Post one review

Single call — one review event, not N comment spams:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews \
  -f event=COMMENT \
  -f body='<summary>' \
  -f 'comments[][path]=...' -F 'comments[][line]=...' -f 'comments[][body]=...'   # repeat per finding
```

- `comments[]` ← line-local mechanical findings, each `path` + `line` + a short `body` (`what` + `fix`); plus any clarity findings the user opted to include (Step 6 gate), their `body` prefixed `[clarity]`.
- `body` ← a one-line tally (`N findings: …`) plus any included finding whose `line` is null (can't anchor) written as `path — what → fix`.
- `event: COMMENT` — advisory, never `REQUEST_CHANGES`.

Architectural findings — and clarity findings the user did not opt to include — are **not** in the posted review.

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
