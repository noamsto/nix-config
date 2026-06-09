# sudo-shield — ambient sudo auth indicator (v1) + deferred GUI entry (v2)

**Status:** spec · **Owner:** Noam · **Date:** 2026-06-09

An ambient **shield indicator** pinned at the top-center edge of the screen whenever a
`sudo`/`su` authentication is pending — so when Claude Code (or anything) runs `sudo`
in an *unfocused* terminal, you see it, you know which process triggered it, and you
can act without hunting for the window.

**Scope split (decided after two adversarial review rounds):**

- **v1 — what we build now.** The ambient shield + a PAM *announce* hook + click-to-
  focus. Unfocused auth is handled by **touching the fingerprint sensor** (already
  works regardless of focus) or **clicking the shield to focus the calling terminal**
  and typing there. **No password ever leaves the terminal; no credential surface is
  added.** This is auth-safe — the announce hook is PAM `optional` and cannot affect
  or block authentication.
- **v2 — deferred.** Typing the password *into the popup* (relayed to root for
  verification). The second review proved this needs a **root-owned rendezvous
  (polkitd-style broker)** to be safe and is a confidentiality regression even when
  correct. Recorded in full below as a future item; **not built in v1**.

## Goals (v1)

1. A visible, ambient indicator (top-center edge tab) whenever `sudo`/`su` auth is pending — even when the originating terminal is unfocused/off-screen.
2. Show **who asked**: the caller chain (e.g. `claude → node → sudo nixos-rebuild`) and the tty.
3. **Unfocused → one click to focus the calling terminal**, where you type/touch as normal.
4. Fingerprint remains usable unfocused (root `fprintd`, already in the stack) — the shield just tells you to touch.
5. **Never** affect the `sudo` auth outcome and **never** be able to lock the user out of `sudo` (the announce hook is `optional`).
6. Visually consistent with the existing Noctalia MD3 theme.

## Non-goals (v1)

- **In-popup password entry.** Deferred to v2 (see the deferred section). v1 routes you to the terminal instead.
- A polkit replacement. `polkit-1` keeps using `hyprpolkitagent`. The shield is **not** added to the `polkit-1` PAM stack.
- Headless / no-tty `sudo` (cron, systemd units): no window → the shield does nothing.
- macOS (`mbp-m4-pro`): already has Touch ID via `pam_tid`.
- Cross-shell support / i18n. Quickshell + Hyprland, English only.

## Architecture (v1)

```
sudo (unfocused kitty) ── opens PAM "sudo" transaction
        │
   announce hook (pam_exec, OPTIONAL)  ──emit pending──▶  shield (Quickshell, user service)
        │   reads /proc → caller PIDs + tty                  │ resolves PID→window via hyprctl
   (auth proceeds normally, hook result ignored)             │ decides focused?
        │                                                     ├ focused   → passive tab only
        ▼                                                     └ unfocused → expand: caller line +
   fprintd (touch works, any focus) / tty password                          [Focus terminal] [Dismiss]
        │                                                                    (+ "touch sensor" hint)
   auth result ── hook emits finished ─────────────────▶  shield dismiss
```

### Components (v1)

1. **Shield shell** — a dedicated Quickshell config (`quickshell -c sudo-shield`), a
   **systemd user service** bound to `graphical-session.target` in the Hyprland
   session. Renders the passive top-center tab, and (when unfocused) an expanded card
   with the caller line, a **Focus-terminal** button (`hyprctl dispatch focuswindow
   address:…`), a **Dismiss** button, and a "touch sensor" hint. Styling borrows the
   Noctalia MD3 palette. **Focus/window resolution lives here** — only the session
   shell can reach `hyprctl`; a root PAM hook cannot.

2. **Announce hook** — `pam_exec.so` rule in `security.pam.services.{sudo,su}.rules`
   (the `pam-lid-check.nix` pattern), control **`optional`** so it can never change
   the auth outcome. Emits `pending` (once per sudo PID) and `finished`. Reads `/proc`
   to collect the caller chain + terminal PID and the `PAM_TTY`, and sends those to
   the shield. **Restrict to `{sudo,su}` only — do NOT reuse `pam-lid-check.nix`'s
   service list, which includes `polkit-1`** (a non-goal here).

3. **Socket** — `$XDG_RUNTIME_DIR/sudo-shield.sock`, shield listens. **v1 carries no
   password**, so the squat risk (see Trust model) degrades to only fake or suppressed
   *toasts* and leaking caller PIDs/tty that same-uid malware can already read from
   `/proc` — no credential impact. (v2 cannot use this socket; see deferred section.)

### PAM ordering (v1)

v1 adds exactly **one** rule — the `optional` announce hook — placed before
`lid-check`. It contributes nothing to the auth decision, so no control-flow surgery,
no jumps, no interaction with `lid-check`'s relative jump.

```
~11100 pam_exec  sudo-shield-announce   optional   (emit pending/finished; result ignored)
10200  pam_rootok        (su only, unchanged)
10400  pam_faillock      (su only, unchanged)
11300  pam_exec  lid-check              (unchanged)
11400  pam_fprintd       sufficient  timeout=-1 max-tries=-1   (unchanged)
11700  pam_unix          sufficient  likeauth try_first_pass   (unchanged)
12500  pam_deny          required     (unchanged)
```

### Cancel / dismiss (v1)

- **Dismiss** hides the indicator; the underlying sudo proceeds normally (touch the
  sensor, or it sits at the tty prompt). No effect on auth.
- **Focus terminal** brings the caller window forward so you can type or Ctrl+C there.
- *Optional* **Abort sudo:** send `SIGINT` to the caller's sudo PID, guarded by a
  `/proc/<pid>/comm == "sudo"` + start-time check (no pidfd needed). This is **not a
  new capability** — same-uid malware can already signal your own sudo — so it adds no
  privilege surface. Include only if the focus-then-Ctrl+C path feels insufficient.

### Fail-safety (v1)

The announce hook is PAM `optional`: its return value is discarded, and a crash in a
`pam_exec` **child** process cannot take down sudo (unlike an in-process `.so`). A
dead/absent/squatted shield changes nothing about authentication. **v1 cannot lock
you out of sudo and cannot leak a credential.**

## Trust model — why v1 is safe and v2 is hard

The defining constraint: a separate PAM transaction (e.g. Quickshell's `PamContext`)
cannot satisfy the already-running `sudo`, so any *password* path must live inside
sudo's stack and be verified by **root** (`pam_unix`), never asserted by a user-
session agent. This is the polkit model: the agent is UI + a pipe; a setuid-root
helper does the PAM check; a cookie binds it to the request.

**v1 sidesteps this entirely** by never relaying a password — it routes you to the
terminal, where root's existing `pam_unix`/`fprintd` do exactly what they do today.

**v2 cannot.** The adversarial review found the naive relay over a per-user socket is
a **critical credential-theft hole (socket squatting):**

> The shield *listens* in `$XDG_RUNTIME_DIR` (`0700 noams:users` — the user owns it);
> the root module *connects in*. A `SO_PEERCRED` uid==0 gate proves the *connector* is
> root **to the shield** — but **nothing proves the listener is the real shield to
> root**. User-level malware can `unlink`+`bind` the socket path first; the root
> module then connects into the attacker, hands over caller PIDs **and a pidfd of the
> root sudo**, and blocks for a reply. The attacker pops its own pixel-perfect popup,
> the victim types the real password into it. Game over.

This is the exact failure the spec's own polkit analysis warns about — security must
come from a **root-owned rendezvous**, not a user-writable socket path. That is why
`polkitd` exists as a persistent root daemon the session agent *registers with*.

## Build phases (v1)

1. **Shield shell + IPC skeleton.** Quickshell config, systemd user service, socket,
   `pending`/`finished` protocol driven by a **stub emitter** (fake events). Iterate
   the top-center visual with zero PAM involvement.
2. **Announce hook.** `pam_exec` `optional` rule emitting `pending`/`finished` for
   real `sudo`/`su`; caller `/proc` collection. Reversible; cannot affect auth.
3. **Focus detection + click-to-focus.** Shield maps PID→window, decides focus, and
   the button warps focus to the caller terminal. This completes v1.

## Testing (v1)

- **Auth-untouched (gate):** `sudo true` / fingerprint / tty password behave
  identically with the announce hook present, absent, shield dead, or socket squatted
  — on gen4/gen5/gen6.
- **lid-check untouched:** lid-closed still skips `fprintd` exactly as before.
- **`{sudo,su}` only:** the announce rule is NOT present in `/etc/pam.d/polkit-1`.
- **Focus matrix:** focused → passive tab; unfocused → expanded card with working
  Focus-terminal; no-window (cron) → nothing.
- **Dismiss / finished / sudo-exits-mid-prompt** all dismiss the shield.

## Risks (v1)

- **R1 — squatted announce socket** yields only fake/suppressed toasts + PID/tty
  leakage already available to same-uid malware. No credential or auth impact. Accept.
- **R2 — focus decided once** at auth start; alt-tabbing mid-prompt won't re-evaluate.
  Acceptable; live re-eval is a later nicety.
- **R3 — `su` window resolution** may differ from `sudo`; if flaky, keep `su`
  announce-only (it already is in v1).

## Rejected alternatives

- **In-popup password entry over a per-user socket (v2 naive form) — insecure.**
  Socket-squattable; root never authenticates the listener. Requires a root-owned
  rendezvous (see deferred section).
- **Shield asserts success via its own `PamContext` — insecure.** A user process can
  impersonate the agent; the credential check must be root's.
- **`pam_exec` sets `PAM_AUTHTOK` — impossible.** `pam_exec` only *exposes* the token
  to its child; it cannot write one back. (v2 needs a real PAM module.)
- **pty wrapper (cockpit-style)** — scrapes the prompt, fights `fprintd`. Rejected.
- **`SUDO_ASKPASS`/`sudo -A`** — only fires with no tty/`-A`; not focus-conditional.

---

# Deferred: v2 — GUI password entry (requires a root broker)

Recorded so this doesn't get re-derived. **Do not build without the root-owned
rendezvous.** Everything below is verified against the live stack (`sudo 1.9.17p2`,
`linux-pam 1.7.1`) where noted.

## v2 mechanism (corrected)

A small **Rust PAM module** (`catch_unwind`-wrapped — a panic/segfault in an in-process
`.so` crashes sudo, which no control flag can prevent) in the `{sudo,su}` auth stack,
in-process as root. On the unfocused branch it relays the typed password to root's
verifier:

- **Adjacent verifier, fixed `+1` jump.** A dedicated `pam_unix use_first_pass`
  line placed *immediately after* the bridge. Verified: `use_first_pass` never prompts
  the tty on a wrong token (so no unfocused hang); the distro line is the looser
  `sufficient likeauth try_first_pass`, left untouched for the normal path.
- **Bridge control:** `[success=ok ignore=1 default=1]` — `success=ok` falls to the
  verifier; `ignore=1`/`default=1` jump +1 *over* the verifier on decline/error.
  ⚠️ The review found `default=ignore` is **wrong** here (it falls *into* the verifier
  on an error return); use `default=1`, or contract the module to return only
  SUCCESS/IGNORE.
- **Placement:** before `lid-check` (preserves its relative jump) but **after `su`'s
  `pam_faillock` (order 10400)** — faillock ahead of the bridge otherwise poisons the
  stack state. Express orders as offsets from `lidCheckRule.order`, never bare
  constants; **pin the generated `/etc/pam.d/sudo` with a test** (verifier must remain
  the bridge's immediate successor).
- **Retry:** sudo re-runs the full stack up to `passwd_tries` (verified default 3), so
  the module is re-entered each attempt; it persists an attempt counter via
  `pam_set_data` and emits `retry{n}` → popup shows "Incorrect password (n/3)". The
  wrong-password signal is the *re-entry*, since the module returns before `pam_unix`
  verifies.
- **Cancel = in-module `PAM_ABORT`.** The module is in sudo; on a `cancel` message it
  returns `PAM_ABORT` and sudo aborts cleanly. **No pidfd is passed out** — passing a
  root sudo's pidfd to a user process is a SIGKILL-capability leak (review CRITICAL).
  This also dissolves the `kill(2)`-permission and `su`-by-root edge cases.

## v2 trust model — the root-owned rendezvous

The relay is safe **only** if root authenticates the *prompter*. Options:

- **Socket-activated root daemon (`sudo-shieldd`)** owning a root-created socket in
  `/run` (not `$XDG_RUNTIME_DIR`); it authenticates the user shield via `SO_PEERCRED ==
  session uid` and brokers module ↔ shield. Squat-proof (root owns the path).
- **System D-Bus registration**, exactly as `hyprpolkitagent` registers with
  `polkitd` — the bus is the root-mediated, non-squattable rendezvous.

Both add a persistent root component to audit. `SO_PEERCRED` is a connect-time
snapshot — gate per-transaction, one connection per PAM transaction, never reuse a
connection across a privilege change.

## v2 irreducible cost

Even built perfectly, the cleartext password **transits a user-session process** (the
shield) — a confidentiality surface that does not exist when typing into the terminal
(where only sudo's tty + root's `pam_unix` see it). Mitigate (`mlock`, zeroize, no
core dumps, never log) but cannot eliminate against a same-uid attacker who can
`ptrace`/read the shield or *is* the shield. This is a deliberate trade-off to weigh
against the convenience — and the reason v1 deliberately avoids it.

## v2 rollout (if ever built)

First switch on **g6 only with a root shell already open** (`machinectl shell` / spare
root TTY); the previous NixOS generation is the rollback; `hyprpolkitagent`+`pkexec`
remain an independent root escape hatch. Must pass: phishing-resistance (squat yields
no password), crash-safety (faulted module still lets `sudo true` through),
lid-check-untouched, and lock-out-recovery gates before enabling.
