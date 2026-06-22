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
