# `/pr-review` Reader-Comprehension Lens — Design

## Problem

The reviewer sub-agents (`go-reviewer`, `typescript-reviewer`, `shell-reviewer`,
`database-reviewer`, `expo-mobile-reviewer`) and the `/pr-review` orchestrator are
sharply tuned for **correctness, security, performance, and idioms**, organized
by CRITICAL/HIGH/MEDIUM severity. They explicitly **drop nits and pure style**.

What's missing is a lens for **"would a human reading this be confused?"** — and
`/pr-review`'s triage (Step 5) would currently filter most such findings out as
nits. The goal is a broad human-comprehension upgrade: flag confusing code,
surface judgment calls, and word findings so a human isn't confused by the
report itself.

**Hard constraint from the user: only genuinely *ambiguous* things, not
everything.** The lens must default to silence and fire only on real
comprehension hazards — never a blanket "could this be clearer?" sweep.

## Scope

All changes land in **one file**: `home/ai/claude-code/commands/pr-review.md`.

This is deliberate. `/pr-review` already dispatches the reviewers (Step 4) and
hands them the finding schema, so the clarity rubric lives in that dispatch
prompt — one copy, no per-agent-file duplication. The language reviewer agent
files are **not** touched.

**Known limitation (accepted):** reviewers dispatched outside `/pr-review` —
`/finish-prs`, `autopilot`, or a direct `Agent` call — will not get the lens.
That follows from the "part of `/pr-review`" decision. The fallback, if ever
wanted everywhere, is a short "Reader Comprehension" section per agent file
(duplication cost); left out of this change.

## The restraint principle (most important)

Default to **silence**. Raise a comprehension finding only when **two competent
readers of this language would genuinely disagree** about what the code does or
whether it is intentional.

**When NOT to flag (drop these):**
- Idiomatic code that is standard for the language, even if terse.
- Patterns consistent with the surrounding/sibling code.
- Anything whose meaning is recoverable from the immediate context.
- Names that are merely imperfect but still clear.
- Pure formatting or aesthetic preference.

**Signal over noise:** prefer the few highest-confidence confusion points over an
exhaustive list. If unsure whether something clears the bar, drop it.

## Edits to `pr-review.md`

### 1. Dispatch prompt (Step 4) — add a "Reader Comprehension" instruction block

Every dispatched reviewer receives this alongside the existing schema. Three
parts:

**a. Confusion-smell catalog** (language-agnostic, the things to look for *only
when genuinely ambiguous*):
- Misleading names — name implies different behavior/type than reality.
- Overloaded return/param semantics — same value means different things
  (`nil` = not-found *and* error *and* default; a bool that's really tri-state).
- Hidden side effects — name/signature implies purity but it mutates an
  arg/global/disk/db.
- Unstated invariants — code is only correct due to an ordering, nullness, or
  caller contract written nowhere.
- Surprising control flow — a buried early-return/`continue`/`break`/fallthrough
  a reader won't expect; success returned from an error-shaped branch.
- Magic values — a bare timeout/retry-cap/status-code/sentinel with no
  name/comment.
- Action-at-a-distance — behavior depends on a global/env/earlier mutation with
  no local signal.
- Comment ⇄ code drift — a comment asserting an invariant the code no longer
  backs.

**b. Clarity-vs-style bar (gatekeeper):** a finding survives only if it names the
**concrete misread and its cost** — what a careful reader will wrongly conclude
and what breaks downstream. "Could be clearer" / "rename for readability" with no
specific misread = style → drop. Calibrate to a competent reader *of this
language*.

**c. Judgment-call instruction:** when the reviewer **cannot tell** whether
something is a bug or deliberate, don't silently drop it and don't assert a fix —
raise it as a question stating **both readings** (e.g. "`getUser` returns `nil`
on a DB timeout, same as not-found — a reader can't tell if the empty-state
fallback is intentional or a swallowed outage").

### 2. Finding schema (Step 4)

Extend the `class` enum from `mechanical | architectural` to
`mechanical | architectural | clarity`.

### 3. Triage (Step 5)

Clarity findings that pass the bar are **kept** (not dropped as nits) and **held
for the chat report** — they are not merged into the postable mechanical stream.

### 4. Reporting + gate (Step 6)

Add a third chat section:

> **C. Reader comprehension (not posted — raised for your call)**

Each finding rendered as `path:line — the misread & cost → fix or open question`.

These are **raised to the user before any posting** — never auto-posted. The
existing confirm gate then lets the user pull any of them into the posted review.

**Output framing (clearer wording):** phrase every finding as the *misread*, not
the defect label — not "unclear variable name" but "a reader will read `count` as
the total and reuse it as such, but it's the remaining count → off-by-one."

**`--yes` / autopilot (unattended):** clarity findings are **never auto-posted**
— the posted review stays correctness/security-only. They are logged to chat
only. This is the natural consequence of "raise to me before."

## Routing summary

| Finding shape | Stream | Destination |
|---|---|---|
| Correctness/security/perf mechanical fix | postable | inline PR comment |
| Architectural decision (>1 defensible answer) | decision | chat §A, human call |
| Clarity finding (passes ambiguity bar) | comprehension | chat §C, raised before posting |
| Fails the misread+cost / ambiguity bar | dropped | — (style) |

## Out of scope

- Touching the language reviewer agent files.
- Wiring the lens into `/finish-prs`, `autopilot`, or direct dispatch.
- Adding new reviewers or changing the file→reviewer routing table.
