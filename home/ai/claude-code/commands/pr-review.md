---
description: "Review a PR with all matching reviewers, dedupe across them, deslop the review comments, then auto-post one review covering all findings — mechanical, architectural, and clarity"
argument-hint: "[PR number | URL] [--dry-run] [--yes]"
---

# PR Review: Multi-Reviewer → One Deduped Review

You take a single PR, run every reviewer that matches the diff, and merge their findings so nothing is repeated. Every surviving finding — **mechanical**, **architectural**, and **reader-comprehension (clarity)** — is posted as one inline review on the PR, tagged by class. Before posting, a **deslop pass** cleans the AI-slop out of the comment prose you wrote, so each comment lands tight. On your own PR the review **auto-posts** once findings are deslopped; you still see the full tally in chat. You coordinate and synthesize — the reviewer agents do the reviewing.

The downstream consumer of the posted review is often an **agent** (e.g. `/finish-prs`), so the posted findings must be structured, line-anchored, and independently resolvable — not a wall of text.

**Argument:** `$ARGUMENTS`

Parse:

- **PR ref** (first non-flag token): a number (`1942`) or URL. If omitted, resolve the PR for the current branch: `gh pr view --json number,url,baseRefName,headRefName,author -q .`
- `--dry-run` — do everything except post; print the full report to chat and stop. Never asks.
- `--yes` — autopilot / agent flag: post without any chat interaction. Your own PR already auto-posts after the deslop pass (Step 7), so this only matters for scripted runs; it still does **not** override the non-author confirm (Step 1). Mutually exclusive with `--dry-run`.

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

Hold these gaps for **Step 10** — do not interrupt the review flow.

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
2. **Filter to actionable + real** — drop nits, pure style, and "consider…" musings. A survivor must name *what's wrong* **and** *the fix/decision*. A `clarity` finding survives only if it clears the misread+cost bar (Step 4) — apply that bar strictly here too; "could be clearer" with no concrete misread is style, drop it. An `architectural` finding survives only if it names a real decision **and** a concrete recommendation — a vague "consider refactoring" is not actionable, drop it. Always drop `nit`; keep `should-fix` and `blocker`.
3. **Tag by class — every class is posted (Step 9):**
   - **mechanical** → inline comment, no tag
   - **architectural** → inline comment, body prefixed `[arch]` (state the decision + your recommendation in one or two lines)
   - **clarity** → inline comment, body prefixed `[clarity]` (state the misread & cost, then the fix or open question)

---

## Step 6: Adversarially verify findings

Every surviving finding goes through a verification pass before it can be posted — auto-post has no human gate, so this is the backstop against hallucinations and misreads.

Dispatch **one verifier `Agent` per finding**, all in one message so they run in parallel, each scoped to the finding's file. The verifier's job is to **refute**, not to confirm:

> You are checking one code-review finding against the actual code. Read the cited file and line plus enough surrounding context. Try to prove the finding **wrong** — the bug can't occur, the API/symbol it names doesn't exist or behaves differently than claimed, the misread it describes isn't real, or its fix is already in place. Reply `real` or `refuted` with a one-sentence reason. **Default to `refuted` when you can't confirm the finding from the code in front of you.**

Drop every `refuted` finding. This is a single verifier per finding (fast, catches the common hallucinations) — it trims false positives, it does not guarantee none. If nothing survives, treat it as the empty case in Step 8.

---

## Step 7: Deslop the review comments

Before anything is posted, run a **deslop pass over the comment prose you just wrote** — the `what`/`fix` text of every surviving finding. This is *not* the standalone `deslop` skill (that targets code); it cleans the slop out of **your own review comments** so what lands on the PR is tight.

Strip from each comment body:

- **Hedging and filler** — "It seems that", "you might want to consider", "perhaps", "I think", "in order to".
- **Preamble and praise padding** — "Great work, but…", "Nice approach. One thing…".
- **Restating what the code does** at length — the reader has the code in front of them; state only what's wrong and the fix.
- **Repetition** between `what` and `fix`, or across two comments on the same root cause.

Keep each comment to a crisp `what → fix` (one or two lines), with its `[arch]`/`[clarity]` tag where applicable. If a comment says nothing concrete after deslopping, drop the finding.

---

## Step 8: Report the tally + gate

Print the deslopped findings to chat, concise — severity-ordered, grouped by class, each as `path:line — what → fix` with its `[arch]`/`[clarity]` tag. This is **exactly** what will be posted; no separate decision/comprehension streams anymore.

**Gate:**

- `--dry-run` → stop here. Nothing is posted.
- **Non-author PR** (author ≠ you, from Step 1) → ask before posting, *regardless of `--yes`*: posting a review under your identity on someone else's PR is a distinct act. *"Post N findings as one review on PR #X? [yes / dry-run]"*. Wait for the answer.
- **Your own PR** → **auto-post** (Step 9) with no confirm. The chat tally is your record.

If **no findings survive triage, verification, + deslop** → post nothing; say so in chat.

---

## Step 9: Post one review

Single call — one review event, not N comment spams:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews \
  -f event=COMMENT \
  -f body='<summary>' \
  -f 'comments[][path]=...' -F 'comments[][line]=...' -f 'comments[][body]=...'   # repeat per finding
```

- `comments[]` ← every line-local finding (all classes), each `path` + `line` + the deslopped `body` (`what` + `fix`), prefixed `[arch]`/`[clarity]` per class (mechanical untagged).
- `body` ← a one-line tally (`N findings: …`) plus any finding whose `line` is null (can't anchor — often architectural) written as `path — [tag] what → fix`.
- `event: COMMENT` — advisory, never `REQUEST_CHANGES`.

Echo the posted tally + the review URL to chat.

---

## Step 10: Reviewer-gap suggestion

For each gap from Step 3, report it plainly:

> No `<x>-reviewer` for <N> changed `<lang>` files in this diff.

Then ask whether to create one. **On yes:**

1. Write `~/.claude/agents/<x>-reviewer.md`, modeled on `~/.claude/agents/go-reviewer.md`:
   - Frontmatter: `name`, a `description` ending in "Use for all `<lang>` code changes.", `tools: ["Read", "Grep", "Glob", "Bash"]`, `model: sonnet`.
   - Body: a focused `<lang>` reviewer system prompt (idioms, common bugs, the language's lint/vet tooling, the "When invoked" steps pattern).
2. Offer to run the new reviewer on **this same PR** and fold its findings back through Steps 4–9.

Never write an agent file without the user's yes.
