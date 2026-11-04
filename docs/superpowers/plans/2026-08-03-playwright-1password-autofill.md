# Playwright MCP + 1Password Autofill Implementation Plan

> **For agentic workers:** implement task-by-task. Steps use checkbox syntax.

**Goal:** Linux Playwright MCP launches Chromium with a persistent automation profile and the 1Password extension so logins can use autofill.

**Architecture:** Replace the direct `playwright-mcp` command (Linux) with a small wrapper that prepares `~/.cache/playwright-mcp-automation` (native-messaging host + resolved extension path), writes a Playwright MCP config with `ignoreDefaultArgs` / `--load-extension`, then execs `playwright-mcp`. Darwin unchanged.

**Tech Stack:** Nix (`writeShellApplication`), Playwright MCP `--config`, Chromium launch args, 1Password BrowserSupport native messaging.

## Global Constraints

- Linux-only extension wiring; Darwin keeps stock playwright-mcp.
- Shared profile for all harnesses consuming `mcpServers.base.playwright`.
- Soft-fail if Chromium extension dir missing.
- No `--headless`; no secrets redaction; no `op` CLI.

---

### Task 1: Linux Playwright wrapper + wire into `mcp-servers.nix`

**Files:**
- Modify `home/ai/mcp-servers.nix`

- [ ] Add `writeShellApplication` wrapper that:
  - Creates `$XDG_CACHE_HOME/playwright-mcp-automation` (fallback `~/.cache/...`)
  - Writes `NativeMessagingHosts/com.1password.1password.json` → `/run/wrappers/bin/1Password-BrowserSupport`
  - Resolves latest `~/.config/chromium/Default/Extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa/*`
  - Writes MCP config with `userDataDir`, `executablePath`, `ignoreDefaultArgs: ["--disable-extensions"]`, and load-extension args when found
  - `exec`s `playwright-mcp --config <that-file>` (pass through `"$@"`)
- [ ] Point `base.playwright` + `wrappers.playwright` at the wrapper on Linux; leave Darwin as today
- [ ] `shellcheck` the generated script (or extract `.sh` and check)
- [ ] Commit

### Task 2: Activate + smoke-check

- [ ] `nh home switch` (per nix-rebuild skill)
- [ ] Confirm wrapper is what Cursor/Claude MCP configs invoke
- [ ] Manual: unlock 1Password, open a login page via Playwright, confirm extension present
- [ ] Mark design status implemented (optional follow-up commit)
