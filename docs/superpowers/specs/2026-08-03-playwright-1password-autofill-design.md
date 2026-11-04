# Playwright MCP + 1Password autofill

**Status:** implemented · **Owner:** Noam · **Date:** 2026-08-03

Make Playwright MCP's Chromium launch with the 1Password browser extension so
agent-driven login pages can be filled via 1Password (desktop app unlock +
extension autofill), instead of typing passwords into the model.

Daily driver remains Firefox. Chromium is automation-only for this path.

## Goals

1. Playwright MCP Chromium starts with 1Password extension loaded and able to
   talk to `1Password-BrowserSupport` (native messaging).
2. Persistent profile so extension connection + site cookies survive across MCP
   sessions (login once per site when possible).
3. One shared automation profile for all harnesses that use the shared
   Playwright MCP definition (Cursor, Claude `claude-frontend`, Amp, OpenCode
   wrapper) — Linux only.
4. Minimal manual setup: unlock 1Password desktop app; first Playwright session
   may need a one-time extension ↔ app link prompt.

## Non-goals

- Reusing the daily Firefox profile or cookies.
- Pointing Playwright at `~/.config/chromium` (real Chromium profile).
- Darwin / nix-darwin wiring in v1 (Playwright there uses managed browsers
  today; skip 1Password args off-Linux).
- `op` CLI secret injection into the agent.
- Playwright MCP `secrets` redaction of autofilled fields.
- Per-harness separate user-data dirs (accept single-browser lock).
- Headless 1Password (headed Chromium required for unlock UI).

## Context (current state)

- Shared MCP defs live in `home/ai/mcp-servers.nix`.
- Linux Playwright MCP already passes `--executable-path` to `pkgs.chromium`.
- Profile defaults under `~/.cache/ms-playwright-mcp/` (temp/hash dirs) — no
  1Password extension, no native-messaging host.
- Firefox automation profile (`firefox-marionette`) already installs
  `pkgs.firefox-addons.onepassword-password-manager` and pins Marionette.
- System 1Password GUI + CLI enabled via `nixos/desktop/1password`.
- Native messaging host exists at
  `~/.config/chromium/NativeMessagingHosts/com.1password.1password.json`
  → `/run/wrappers/bin/1Password-BrowserSupport`.
- Unpacked Chromium extension already present under
  `~/.config/chromium/Default/Extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa/<ver>_0`.

## Design

### Profile

Fixed user-data-dir:

```
$XDG_CACHE_HOME/playwright-mcp-automation
```

(`XDG_CACHE_HOME` falls back to `~/.cache` when unset.)

Passed to Playwright MCP via config `browser.userDataDir`. Cookies, local
storage, and extension state persist. Only one Playwright MCP browser may use
this dir at a time (upstream constraint).

### Extension loading

On Linux, resolve the latest unpacked 1Password extension directory under the
user's Chromium profile:

```
~/.config/chromium/Default/Extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa/<newest>/
```

A small wrapper (or HM-generated args) passes Chromium launch flags:

- `--disable-extensions-except=<ext-dir>`
- `--load-extension=<ext-dir>`

via Playwright MCP config `browser.launchOptions.args` (preferred over stuffing
raw flags only on the CLI if both are needed for `executablePath` + args).

If the extension directory is missing (Chromium never opened / extension not
installed), MCP still starts; 1Password simply won't be present — fail soft,
don't block browser automation.

### Native messaging

Chromium looks for hosts under `<user-data-dir>/NativeMessagingHosts/` when
using a custom user-data-dir. Ensure:

```
$XDG_CACHE_HOME/playwright-mcp-automation/NativeMessagingHosts/com.1password.1password.json
```

with the same manifest content as Chromium's host (path
`/run/wrappers/bin/1Password-BrowserSupport`). The wrapper rewrites this on
every launch so a wiped cache recovers automatically.

### MCP wiring

Linux `playwright` in `home/ai/mcp-servers.nix` runs
`playwright-mcp-automation` (a `writeShellApplication` wrapper) which writes
`$XDG_CACHE_HOME/playwright-mcp-automation/mcp-config.json` and execs
`playwright-mcp --config …`. Config sets `executablePath`, `userDataDir`,
`ignoreDefaultArgs: ["--disable-extensions"]`, and load-extension args when
the Chromium extension dir exists. Darwin still calls `playwright-mcp`
directly.

All consumers of `mcpServers.base.playwright` / the PATH wrapper pick this up
automatically.

### Runtime assumptions

- `programs._1password-gui` is enabled; desktop app running and unlocked.
- Headed mode (Playwright MCP default) — do not pass `--headless`.
- User may need one interactive “connect to 1Password” / unlock in the
  Playwright window on first use.

## Alternatives considered

| Approach | Why not |
| --- | --- |
| Reuse `~/.config/chromium` | Couples automation to a secondary browser profile; lock contention; not needed since FF is daily driver |
| CDP / Playwright Chrome extension attach | Requires a long-lived manual Chromium; more moving parts |
| `op` CLI fill | Easy for agents, but dumps secrets into tool transcripts; different UX than requested |
| HM-pinned CRX copy in the store | More declarative, but CRX update / unpack pain; resolve-from-Chromium is enough for v1 |

## Test plan

1. `nh home switch` on a Linux ThinkPad.
2. Confirm 1Password desktop is unlocked.
3. Start Playwright via Cursor (or `claude-frontend`): navigate to a site with a
   saved 1Password login.
4. Confirm extension icon / autofill UI appears; complete one login.
5. Restart MCP / new session; confirm cookies or autofill still available.
6. Confirm Darwin config (if touched) still omits the Linux-only args.

## Open questions

None blocking — extension source = resolve latest under Chromium Extensions dir;
Linux-only; shared profile; no secrets redaction.
