# slack-voice Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code skill that learns Noam's Slack voice from his message history and applies it whenever a Slack message is written on his behalf.

**Architecture:** A single `SKILL.md` at `home/ai/claude-code/skills/slack-voice/`, Nix-symlinked into `~/.claude/skills`. Two modes routed by argument: `build` mines Slack history (via the Slack MCP) into a local profile at `~/.claude/slack-voice/profile.md`; the default apply mode reads that profile and produces in-voice messages. The profile is writable runtime state, never committed.

**Tech Stack:** Claude Code skill (markdown + frontmatter), Slack MCP tools (`slack_search_users`, `slack_search_public_and_private`, `slack_send_message`), Nix Home Manager (symlinks the skill), `nh home switch`.

**Deliverable note:** The skill is prose, not executable code, so there is no unit-test harness. "Verification" steps replace "failing test" steps: we confirm discovery, a successful build run producing a profile, and a successful apply run.

**Spec:** `docs/superpowers/specs/2026-06-22-slack-voice-design.md`

---

### Task 1: Write the complete `SKILL.md`

**Files:**
- Create: `home/ai/claude-code/skills/slack-voice/SKILL.md`

- [ ] **Step 1: Create the directory and write the file**

Write `home/ai/claude-code/skills/slack-voice/SKILL.md` with exactly this content:

````markdown
---
name: slack-voice
description: Use whenever a Slack message is being written on Noam's behalf — rewriting his rough draft, drafting a message from a stated intent, or polishing a message Claude composed before it goes to Slack — to make it sound like him. Run with the argument "build" to (re)generate the voice profile from Slack history. Triggers on composing, drafting, rewriting, or sending Slack messages.
---

# slack-voice

Make Slack messages sound like Noam. Two modes, routed by the argument:

- Argument is `build` → **Build mode** (regenerate the voice profile).
- Anything else, or no argument → **Apply mode** (write a message in his voice).

**Profile path (constant):** `~/.claude/slack-voice/profile.md`

---

## Apply mode (default)

1. **Load the profile.** Read `~/.claude/slack-voice/profile.md`.
   - If it does not exist, STOP. Tell Noam: "No voice profile yet — run
     `/slack-voice build` first." Do not improvise a voice.
2. **Determine the task** from context — one of:
   - *Rewrite* a rough draft he gave you.
   - *Draft* a message from a stated intent ("tell the team the deploy slipped").
   - *Polish* a message you composed on his behalf.
3. **Pick the register.** Choose tone from the profile's register map based on the
   target channel/audience (busy work channel vs. DM vs. casual). When the target
   is unknown, ask which channel/person it's for, or default to the profile's
   most common register and say which you assumed.
4. **Write it in voice** using the profile's rules and anchors.
5. **Approve in chat, then send.** Print the drafted message text in this
   conversation and ask Noam to approve or edit. Only after his go-ahead, send it
   with `slack_send_message`. **Never auto-send.** Do not rely on
   `slack_send_message_draft` — its post-vs-draft behavior is unverified.

---

## Build mode (`/slack-voice build`)

Regenerates `~/.claude/slack-voice/profile.md` from real Slack history. Token-heavy
and deliberate — only run when asked.

1. **Resolve identity.** Find Noam's Slack user and handle with
   `slack_search_users` (and `slack_read_user_profile` if needed). Slack search has
   no `@me` operator — you need the real handle for the `from:` filter.
2. **Sample messages.** Using `slack_search_public_and_private`, search
   `from:<handle>` across a spread of channel types, deliberately reaching for
   different registers (a work channel, a DM, a casual channel) wherever the
   integration's scopes allow. Track which registers you could and could not reach.
3. **Bound the sample.** Cap at ~60–100 messages total, spread across channels.
   Weight toward *substantive* messages; skip pure one-liners ("lgtm", "ty",
   ":+1:") that teach nothing about voice.
4. **Distill** the sample into the profile sections below.
5. **Write the profile.** Create `~/.claude/slack-voice/` if needed, then write
   `profile.md` using the template below. Confirm to Noam how many messages and
   which registers fed it.

### Privacy when selecting anchors

Anchor snippets are real messages stored in a local file. Prefer innocuous ones.
Scrub or skip messages carrying obvious sensitive content (deal names, customer
identifiers, secrets) when choosing anchors. The profile stays local and is never
committed.

### Profile template

Write `~/.claude/slack-voice/profile.md` with this structure (fill from the sample):

```markdown
# Noam's Slack voice profile

Generated: <date> · Sampled: <N> messages
Registers reached: <e.g. public channels, 1 DM> · Not reached: <e.g. private channels>

## Rules
- Typical length: <e.g. 1–2 short sentences>
- Emoji: <habits — which, how often, where>
- Openers / closers: <patterns, or "none — dives straight in">
- Punctuation & capitalization: <quirks, e.g. lowercase starts, no trailing period>
- Recurring phrases: <list>
- Formality: <baseline>

## Register map
- Work channel: <tone notes>
- DM: <tone notes>
- Casual: <tone notes>

## Anchors
- "<short real message 1>"
- "<short real message 2>"
- ... (5–10 total)
```

---

## Known limitations

- **Apply mode triggering is not deterministic.** It fires on description match,
  not a hook, so it may miss some Slack-compose moments. A PreToolUse hook on the
  Slack send tool is a possible future upgrade.
- **Register skew.** If the integration can't read DMs/private channels, the
  profile leans formal. The provenance line in the profile makes this visible.
- **Voice drift.** The profile is a snapshot — rerun `/slack-voice build`
  periodically.
````

- [ ] **Step 2: Commit**

```bash
git -C ~/nix-config-worktrees/feat-slack-voice-skill add home/ai/claude-code/skills/slack-voice/SKILL.md
PRE_COMMIT_ALLOW_NO_CONFIG=1 git -C ~/nix-config-worktrees/feat-slack-voice-skill commit -m "feat(claude): add slack-voice skill"
```

(The worktree has no materialized `.pre-commit-config.yaml`; the env var skips the missing-config check. If direnv has since materialized it, drop the prefix and re-`git add` any files the hooks reformat, then re-run the same commit.)

---

### Task 2: Materialize the skill and verify discovery

**Files:** none changed — this builds and checks.

- [ ] **Step 1: Rebuild Home Manager**

Invoke the `nix-rebuild` skill first (per repo CLAUDE.md), then run from the worktree:

```bash
nh home switch
```

Expected: build succeeds; the activation creates the symlink
`~/.claude/skills/slack-voice` → the Nix store copy of the skill dir.

- [ ] **Step 2: Verify the symlink exists**

Run:

```bash
ls -l ~/.claude/skills/slack-voice/SKILL.md
```

Expected: a symlink resolving into `/nix/store/...`, file present.

- [ ] **Step 3: Verify the skill is discoverable**

In a Claude Code session (this one is fine after the symlink lands on next start, or a fresh session), confirm `slack-voice` appears in the available skills list and `/slack-voice` is accepted.

Expected: skill listed with its description.

---

### Task 3: Generate the profile (real build run) and verify apply

**Files:**
- Creates at runtime: `~/.claude/slack-voice/profile.md` (not committed)

- [ ] **Step 1: Run build mode**

Invoke `/slack-voice build`. Watch that it: resolves Noam's handle, samples within
the ~60–100 cap across channel types, and reports which registers it reached.

- [ ] **Step 2: Verify the profile was written**

Run:

```bash
cat ~/.claude/slack-voice/profile.md
```

Expected: a profile with a populated `Generated:` line, Rules, Register map, and
5–10 Anchors. Anchors contain no obviously sensitive content.

- [ ] **Step 3: Verify the profile is not tracked by git**

Run:

```bash
git -C ~/nix-config-worktrees/feat-slack-voice-skill status --porcelain
```

Expected: `profile.md` does NOT appear (it lives under `~/.claude`, outside the repo).

- [ ] **Step 4: Verify apply mode**

Give Claude a rough draft and ask it to send to a channel. Confirm it: reads the
profile, rewrites in-voice, prints the draft in chat for approval, and sends via
`slack_send_message` only after go-ahead.

Expected: in-voice draft shown; nothing sent without approval.

- [ ] **Step 5: Verify the missing-profile guard**

Temporarily move the profile aside and run apply mode:

```bash
mv ~/.claude/slack-voice/profile.md ~/.claude/slack-voice/profile.md.bak
```

Expected: apply mode stops and tells Noam to run `/slack-voice build` first.
Then restore:

```bash
mv ~/.claude/slack-voice/profile.md.bak ~/.claude/slack-voice/profile.md
```

---

## Self-review

- **Spec coverage:** two modes (T1), profile location/contents/template (T1), build
  flow incl. identity-resolve/sampling/cap/privacy (T1), apply flow incl.
  approval-in-chat and missing-profile guard (T1, verified T3), description-as-trigger
  (T1 frontmatter), materialization (T2), known limitations (T1). All spec sections map.
- **Placeholder scan:** the `<...>` tokens in the profile template are intentional
  fill-ins for runtime data, not plan placeholders; everything the engineer writes is
  concrete.
- **Type consistency:** profile path `~/.claude/slack-voice/profile.md`, arg keyword
  `build`, and tool names (`slack_search_users`, `slack_search_public_and_private`,
  `slack_send_message`) are used consistently across tasks.
