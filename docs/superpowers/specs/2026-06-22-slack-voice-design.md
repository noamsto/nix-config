# slack-voice skill — design

**Date:** 2026-06-22
**Status:** approved (design locked)

## Purpose

A Claude Code skill that makes Slack messages sound like Noam. It learns his
voice by mining his own Slack history, distills that into a saved profile, and
applies the profile whenever a Slack message is being written — whether Claude
is rewriting his rough draft, drafting from a stated intent, or polishing a
message it composed on his behalf.

## Shape

One skill, two modes, living at
`home/ai/claude-code/skills/slack-voice/SKILL.md` (Nix-symlinked into
`~/.claude/skills/slack-voice`).

- **Build mode** — run occasionally (`/slack-voice build`). Mines Slack history,
  distills patterns, writes the voice profile. Token-heavy; deliberate, not
  automatic.
- **Apply mode** — the default. Reads the profile and produces the message in
  Noam's voice. Triggers on all three workflows below.

Mode routing: `SKILL.md` branches on its argument — `build` selects build mode;
anything else (or no arg) selects apply mode. Apply mode auto-suggests running
build when it finds no profile.

The skill's `description` is the trigger for apply mode. It is written to fire
on: rewriting a user draft, drafting a Slack message from intent, and polishing
any Slack message Claude composes. There is **no hook** — the description is the
honest mechanism. A PreToolUse hook on Slack-send is a documented future add-on
(see Known Limitations), not built now.

## Voice profile

- **Location:** `~/.claude/slack-voice/profile.md` — a writable runtime path,
  **not committed** to any repo, regenerable anytime with no Nix rebuild. (The
  skill source is read-only in `/nix/store`, so the profile cannot live beside
  it.)
- **Contents:** distilled rules + 5–10 short real anchor snippets.
  - **Rules section:** typical message length, emoji habits, openers/closers,
    punctuation and capitalization quirks, recurring phrases, formality level.
  - **Register map:** how the voice shifts by audience/channel type (busy work
    channel vs. DM vs. casual), since one flat average misrepresents real voice.
  - **Anchors section:** 5–10 short verbatim messages as grounding examples,
    chosen to be innocuous (see privacy below).
  - **Provenance line:** when it was generated and which channels/registers were
    and were **not** reachable, so the register map is honest rather than
    silently public-channel-only.

## Build mode — flow

1. **Resolve identity.** Look up Noam's Slack user/handle via
   `slack_search_users` / profile tools. Do **not** assume `@me` — Slack search
   has no such operator; it needs the real handle.
2. **Sample messages.** Search `from:<handle>` across a spread of channel types,
   deliberately reaching for different registers (work channel, DM, casual)
   where the integration's scopes allow. Record any register that could not be
   reached.
3. **Bound the sample.** Hard cap ~60–100 messages, sampled across channels and
   weighted toward *substantive* messages — skip pure one-liners ("lgtm", "ty",
   ":+1:") that teach nothing about voice.
4. **Distill.** Extract the rules + register map described above.
5. **Write the profile.** Create `~/.claude/slack-voice/` if needed and write
   `profile.md`.

## Apply mode — flow

1. Read `~/.claude/slack-voice/profile.md`. If missing, stop and tell Noam to
   run `/slack-voice build` first.
2. Determine intent from context: rewrite his draft, draft from a stated intent,
   or polish a message Claude composed.
3. Produce the message in-voice, choosing the register from the profile's
   register map based on the target channel/audience.
4. **Approval in chat, then send.** Print the drafted message text in the Claude
   conversation for Noam to approve. Only on his go-ahead send it via
   `slack_send_message`. Never auto-send. (Deliberately does not depend on
   `slack_send_message_draft`, whose post-vs-draft semantics are unverified.)

## Privacy

- The profile is local-only and never committed.
- Anchor snippets prefer innocuous messages; the build step scrubs obvious
  sensitive tokens (names tied to deals, secrets) when selecting anchors.

## Known limitations

- **Auto-polish is not deterministic.** Description-based triggering won't catch
  every Slack-compose moment. If this proves unreliable in practice, add a
  PreToolUse hook on the Slack send tool that routes through this skill. Out of
  scope for the first version.
- **Register skew.** If the Slack integration cannot read DMs/private channels,
  the profile will lean formal. The provenance line makes this visible so the
  output isn't silently miscalibrated.
- **Voice drift.** The profile is a snapshot; rerun build periodically.

## Out of scope (YAGNI)

- A hook-based always-on interceptor (future add-on only).
- Committing/syncing the profile across machines (agenix/encryption rejected as
  overkill).
- Multi-workspace support beyond the single connected Slack workspace.
