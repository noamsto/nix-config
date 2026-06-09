# sudo-shield — ambient sudo auth indicator + focus-aware GUI entry

**Status:** spec · **Owner:** Noam · **Date:** 2026-06-09

An ambient, always-on **shield indicator** pinned at the top-center edge of the
screen whenever a `sudo`/`su` authentication is pending — so when Claude Code (or
anything) runs `sudo` in an *unfocused* terminal, you see it. The shield shows
which process triggered the prompt. Behaviour then depends on focus:

- **Calling terminal focused** → shield is passive; you type / touch in the terminal exactly as today.
- **Calling terminal unfocused** → the shield expands into a popup. You either type the password into the popup (relayed to root for verification) or click "use fingerprint" and touch the sensor.

Fingerprint already works regardless of focus today (the sensor doesn't care);
the new value is the *visible indicator* and *typed-password-without-hunting-for-the-terminal*.

## Goals

1. A visible, ambient indicator (top-center edge tab) whenever `sudo`/`su` auth is pending — even when the originating terminal is unfocused/off-screen.
2. Show **who asked**: the caller chain (e.g. `claude → node → sudo nixos-rebuild`) and the tty.
3. **Unfocused → GUI password entry** without switching windows, with the password verified by **root** (`pam_unix`), never by the GUI.
4. **Focused → unchanged** terminal flow (type or touch in the terminal).
5. Fingerprint remains usable in both cases (root `fprintd`, already in the stack).
6. **Never** weaken the `sudo` privilege boundary and **never** be able to lock the user out of `sudo` (fail-open to the normal flow on any error).
7. Visually consistent with the existing Noctalia MD3 theme.

## Non-goals

- A polkit replacement. `polkit-1` keeps using `hyprpolkitagent`. (Open option to
  show the *passive* shield for polkit events later; **out of scope for v1**.)
- Capturing/handling the password anywhere other than relaying it to root for
  verification. The GUI holds **no** authentication authority.
- Cross-shell support. This is Quickshell + Hyprland specific.
- Headless / no-tty `sudo` (cron, systemd units). When no terminal window is
  identified, the hook fails open and the normal flow proceeds; no GUI is shown.
- macOS (`mbp-m4-pro`). It already has Touch ID for sudo via `pam_tid`.
- i18n. English only.

## Trust model (the crux)

A separate PAM transaction (e.g. Quickshell's `PamContext`) **cannot** satisfy the
already-running `sudo` transaction, so the bridge must live inside `sudo`'s own PAM
stack. The danger: if the in-stack module merely *trusted* the GUI saying "I
authenticated them," any process running **as the user** could impersonate the GUI
on the socket and silently escalate to root — a real privilege-escalation
regression.

**Resolution: root stays the verifier; the GUI is only a conversation surface.**

| Path (unfocused) | Verified by | How |
|---|---|---|
| **Password** | `pam_unix` (**root**, in `sudo`'s own transaction) | The shield collects the typed password and relays it over the per-user socket. The PAM module sets `PAM_AUTHTOK` and hands off to `pam_unix use_first_pass`. The password only crosses the user's own socket; **root** decides correctness. |
| **Fingerprint** | `fprintd` (**root**, already in the stack) | Works regardless of focus today. The shield only tells you to touch. No new trust path. |

The shield therefore can never *assert* success — it can only carry a password to
root for verification, or tell the user to touch the sensor.

### The socket is a phishing surface — authenticate the *prompter* as root

A per-user socket with a same-uid `SO_PEERCRED` check is **not enough**, and getting
this wrong is a credential-theft hole. The hook and any user-level malware run as the
*same* uid, so malware could connect to the shield, send a forged `pending`, and the
shield would pop a password field and hand the typed password **back over that
connection — to the malware**. Same-uid proves nothing here.

**Resolution: a prompt may only be requested by a peer with uid 0.** The bridge is a
`.so` loaded *in* sudo, whose euid is 0 during auth, so it connects to the socket
**as root without dropping privilege**. The shield checks `SO_PEERCRED` and refuses
to prompt — or to return a password — unless the peer uid is 0. Malware running as
the user cannot forge uid 0, and because the password is only ever returned over that
same root-owned connection, it can only flow back to a real sudo transaction. (Root
reaches the user-owned socket in `$XDG_RUNTIME_DIR`, mode 700, via `CAP_DAC_OVERRIDE`.)

This is the polkit invariant again: the *prompt authority* is root, not "whoever
connected." The passive announce path (focused case, no password returned) is lower
stakes — a forged `pending` there is at worst an annoying fake toast — but it uses
the same root-peer gate for consistency.

### This is the polkit trust model, minus its machinery

polkit deliberately does **not** trust its authentication agent to assert success.
`hyprpolkitagent` is only UI + a pipe; the actual credential check runs in a
**setuid-root helper** (`polkit-agent-helper-1`) that executes the PAM stack as
root, and a **cookie** issued by `polkitd` binds that check to the one outstanding
request so a stale or foreign authentication can't be replayed. Security comes from
*root doing the check*, never from the agent's word.

We get the same guarantee more cheaply because **`sudo` is itself the setuid-root
PAM application and our module runs inside its transaction**:

- Root verification = `sudo`'s own `pam_unix` (this is `polkit-agent-helper-1`'s role, for free).
- The cookie problem vanishes — there is exactly one outstanding request (this transaction), and the module relaying the password and the `pam_unix` verifying it are the *same* transaction. Nothing to bind, nothing to replay.
- The shield = the agent: UI + pipe, no authority.

Why an "agent asserts success" design (e.g. the shield running its own
`PamContext`) **cannot** be made safe even with a cookie: our module connects *out*
to the agent's socket, so malware running as the user can replace the agent,
receive whatever cookie we send, and echo it back with no real authentication →
root. A cookie only helps when validated by a *root-trusted* component (polkit's
helper); an untrusted agent holding the cookie is worthless. The credential check
must live in root's transaction — which is exactly the relay design.

## Components

1. **Shield shell** — a dedicated Quickshell config (`quickshell -c sudo-shield`),
   run as a **systemd user service** bound to `graphical-session.target` in the
   Hyprland session. Renders:
   - the passive top-center shield tab when auth is pending,
   - the expanded popup (caller line + password field + "use fingerprint" toggle + cancel) when the caller is unfocused.
   It is **pure UI + password relay** — it runs no `PamContext` and authenticates
   nothing. Styling borrows the Noctalia MD3 palette only.

   **Focus & window resolution lives here, not in the hook** — the shield runs in
   the Hyprland session and can call `hyprctl` natively, which a root PAM hook
   cannot (no session env, no access to the user's compositor socket). The hook/
   module only sends caller **PIDs** + tty; the shield maps PID → window and decides
   focused/unfocused, then replies.

2. **Announce hook** — `pam_exec.so` rule in `security.pam.services.{sudo,su}.rules`,
   control **`optional`** so it can never affect the auth outcome. Emits `pending`
   (once per sudo PID) and `finished`. Reads `/proc` to collect the caller chain.
   Connects **as root** (no `seteuid` drop) so the shield's root-peer gate trusts it.

3. **Password-bridge module** — a small **Rust PAM module** (`pam-bindings`), built
   as a derivation in `packages/`, placed in the `sudo`/`su` auth stack **before
   `lid-check`** (see ordering). Runs in-process as root (euid 0). On the unfocused
   typed-password branch it sets `PAM_AUTHTOK` and returns `success` so control falls
   to the **adjacent verifier**. FFI boundary is `catch_unwind`-wrapped — any panic
   becomes `PAM_IGNORE`; the module must never crash sudo. (A `pam_exec` script
   **cannot** set the token — see Rejected Alternatives.)

4. **Adjacent verifier** — a dedicated `pam_unix use_first_pass` line placed
   immediately after the bridge, reached *only* when the bridge succeeds. `use_first_pass`
   (not `try_first_pass`) means a wrong relayed token fails **without** a tty-prompt
   fallback (which would hang an unfocused terminal). Keeps the distro's own
   `pam_unix` untouched for the normal/focused path.

5. **Per-user socket** — `$XDG_RUNTIME_DIR/sudo-shield.sock`. The shield listens (as
   the user); the hook/module connect **as root**. The shield enforces
   `SO_PEERCRED` **uid == 0** before prompting or returning a password (see Trust
   model). Password buffers are `mlock`ed and zeroized; core dumps disabled; the
   value is never logged.

## PAM stack ordering (the brittle part)

Current `sudo`/`su` auth stack (from `pam-lid-check.nix`):

```
11300  pam_exec  lid-check        [success=ignore default=1 perm_denied=1 auth_err=1]
11400  fprintd                    timeout=-1 max-tries=-1   (BLOCKS until touch / Ctrl+C)
 ....  pam_unix                   (try_first_pass)
```

New ordering — **our pair goes at the very front, before `lid-check`:**

```
~11100 pam_exec  sudo-shield-announce   optional              (emit "pending" once; never affects auth)
~11150 sudo-shield-bridge (Rust .so)    [success=ok ignore=1 default=ignore]
            unfocused + typed password   → set PAM_AUTHTOK, return SUCCESS → fall to verifier (next line)
            focused / no-window / shield-down / timeout / panic → IGNORE → jump +1 over verifier
            unfocused + "use fingerprint"/ cancel               → IGNORE → jump +1 over verifier
~11160 pam_unix  use_first_pass         [success=done auth_err=die default=die]   (OUR verifier; reached only on bridge SUCCESS)
11300  pam_exec  lid-check              (UNCHANGED — its relative jump is undisturbed)
11400  fprintd                          (UNCHANGED — fingerprint / fall-through branch)
 ....  pam_unix  try_first_pass         (UNCHANGED — distro's, for the normal/focused path)
```

Two deliberate choices that kill the original fragility:

- **Adjacent verifier, fixed `+1` jump.** The bridge never counts over `fprintd` to
  reach the distro's `pam_unix`; on success it simply falls to the *next* line (our
  own `use_first_pass`), and on decline it jumps exactly **1** (over that verifier).
  The jump no longer depends on how many modules nixpkgs generates downstream.
- **Front placement preserves `lid-check`.** `lid-check`'s control
  `[success=ignore default=1 …]` uses a *relative* `default=1` to skip `fprintd`.
  Inserting anything *between* `lid-check` and `fprintd` would silently retarget that
  jump onto our module. Placing our pair *before* `lid-check` leaves it byte-for-byte
  unchanged.

⚠️ Still **pin the generated `/etc/pam.d/sudo` with a test** (gen4/5/6 may differ)
and prefer the NixOS `rules` ordering abstraction over hardcoded integers. The risk
is much lower than the original jump-over-`fprintd` scheme, but the verifier must
remain the *immediate* successor of the bridge for the `+1` to hold.

## Data flow — unfocused typed-password sequence

```
Claude Code (unfocused kitty) ── runs ──▶ sudo nixos-rebuild
                                              │  opens PAM "sudo" transaction
   announce hook (root)  ── emit "pending" ──▶ shield: show passive shield + caller line
                                              │
   bridge module (root):  read /proc → caller PIDs + tty; pidfd_open(self)
        ── connect as ROOT, send {caller pids, tty} + pidfd(SCM_RIGHTS) ──▶ shield
                              shield verifies peer uid==0, maps PID→window via hyprctl,
                              decides focused?  and REPLIES:
                     focused / no-window  → IGNORE (normal terminal flow; shield passive)
                     unfocused → shield expands popup; module BLOCKS on socket (≤120s)
                            ├─ password{pw}     → set PAM_AUTHTOK; SUCCESS → fall to verifier
                            ├─ use-fingerprint  → IGNORE (+1 over verifier) → fprintd → touch
                            ├─ cancel           → shield SIGINTs the sudo pidfd → sudo aborts (≡ Ctrl+C)
                            └─ timeout / error  → IGNORE → normal flow (never killed)
                                              │
   auth result ─────────────────────────────┘  → bridge emits "finished"
   shield dismiss when ANY of: "finished" received │ tracked pidfd signals exit │ timeout
```

**IPC protocol (line-delimited JSON; every connection gated on `SO_PEERCRED` uid==0):**

- hook/module → shield: `{"event":"pending","pid":<sudo>,"tty":"pts/3","caller_pids":[…],"caller":"claude → node → nixos-rebuild"}` — the **shield** (not the hook) resolves PID→window and focus, because only it can reach `hyprctl`.
- bridge module → shield: a **pidfd** for the sudo process as `SCM_RIGHTS` ancillary data on the `pending` line — used both for cancel and to learn of sudo's exit (immune to PID reuse).
- module → shield: `{"event":"retry","pid":<sudo>,"n":<attempt>,"of":<passwd_tries>}`
- hook/module → shield: `{"event":"finished","pid":<sudo>}`
- shield → module (reply): `{"action":"focused"}` (→ module returns IGNORE) | `{"action":"password","value":"…"}` | `{"action":"use-fingerprint"}` | `{"action":"cancel"}`

### Retry & wrong-password feedback

sudo retries by calling `pam_authenticate()` again (up to `passwd_tries`, default
**3**) on the same handle, and **each call re-runs the whole auth stack — so the
bridge module is re-entered on every retry.** That re-entry *is* the failure
signal: the module returns before `pam_unix` runs (it sets `PAM_AUTHTOK` and jumps),
so it never sees the verdict directly — it learns the previous password was wrong by
being invoked again.

- The module persists an attempt counter with `pam_set_data`/`pam_get_data` (lives
  across retries within one sudo invocation). No counter → fresh prompt; counter
  present → emit `retry{n}` so the popup shows "Incorrect password — try again
  (n/3)".
- The wrong-password toast therefore lands at the *start of attempt n+1*, after a
  brief pause — not at the end of attempt n. This is intentional: the module must
  never verify the password itself (root's `pam_unix` does).
- After `passwd_tries` exhausted, sudo aborts; the module emits `finished` and the
  shield dismisses.

### Cancel = real abort

Cancel actually terminates the sudo, rather than falling through to a stuck
`fprintd` wait. The shield sends `SIGINT` to the sudo process — the programmatic
equivalent of Ctrl+C: sudo's own handler cancels the PAM conversation and exits
non-zero, the caller's command never runs.

- **Permission:** sudo is setuid-root (euid 0) but keeps the **invoking user's real
  UID**; `kill(2)` permits a sender whose UID matches the target's *real* UID, so the
  user-session shield may signal its own sudo. (Verify empirically in phase 4.)
- **PID-reuse safety:** the bridge module (`.so` loaded *in* sudo) passes a **pidfd**
  of itself to the shield via `SCM_RIGHTS`; the shield uses `pidfd_send_signal`, which
  refers to the exact process and cannot misfire onto a recycled PID. Cheap fallback
  if pidfd plumbing slips: check `/proc/<pid>/comm == "sudo"` **and** a matching
  start-time before signaling.
- **Escalation:** `SIGINT`, then `SIGTERM`→`SIGKILL` if it hasn't exited within ~1s.
- **The module's socket read is EINTR-aware** so the in-process module unblocks
  cleanly as sudo tears down.

**Cancel is *not* fail-open.** It is a deliberate user action that kills sudo.
Timeout, a dead shield, or a socket/peer-check failure remain fail-open (return
`IGNORE`, normal flow) — those must never kill a sudo, since "your sudo died because
the shield was slow" is worse than falling through.

**Caller identity (split across the root/session boundary):** the root side
collects *PIDs*, the session side (shield) maps them to a *window*. The *announce
hook* is a `pam_exec` **child** of sudo (`getppid()` → sudo); the *bridge module* is
a `.so` **in** sudo (`getpid()` → sudo — what it `pidfd_open`s; `getppid()` → caller).
The root side reads `/proc/<sudo>/stat` PPID → caller, walks ancestors collecting the
command chain + terminal PID, and sends those PIDs (plus `PAM_TTY`) to the shield. The
**shield** then maps the terminal PID → window via `hyprctl clients -j` and decides
focus — because `hyprctl` needs the user's session, unreachable from a root PAM hook.

## Fail-open invariants (safety)

The bridge module returns `PAM_IGNORE` (never blocks/denies beyond normal flow) when:

- the shield replies `focused`, or no terminal window can be identified;
- the caller's **stdin is not a tty** (e.g. `echo pw | sudo -S` in a script) — never pop a GUI for non-interactive sudo;
- the socket is missing, the shield is not running, or the peer/`SO_PEERCRED` handshake fails;
- the wait exceeds the timeout (≤120s);
- **anything panics** — the FFI boundary is `catch_unwind`-wrapped and returns `PAM_IGNORE`.

(Explicit **cancel** is the one non-fail-open outcome — it deliberately `SIGINT`s the
sudo. See *Cancel = real abort*.)

**Crash-safety is the real backstop.** `default=ignore` only fails-open on *return
codes* — a `SIGSEGV` or uncaught `panic!` would crash the sudo process itself, which
no control flag can prevent. Hence: Rust, no `unwrap`/`expect`/indexing-panics on the
auth path, `catch_unwind` at every `extern "C"` entry point, and a fuzz/abort test
that asserts a deliberately-faulted module still lets `sudo true` through.

Result: a dead/absent/crashing shield or module degrades to **exactly today's
behaviour**. The feature can never lock the user out of `sudo`.

## Rollout & recovery

Touching the `sudo` PAM stack means a bad switch could deny `sudo` system-wide.

- **First switch on g6 only, with a root shell already open** (`machinectl shell`
  or a spare TTY logged in as root) so a broken stack can't strand you. Verify the
  full test matrix, *then* roll out to g5 / p14s.
- **Rollback path:** the previous NixOS generation is always bootable
  (`nixos-rebuild ... --rollback`, or pick the prior generation in the boot menu) —
  the stack reverts wholesale.
- **Independent escape hatch:** `hyprpolkitagent` + `pkexec` remain untouched, so a
  root GUI shell is reachable even if `sudo` is wedged.

## Build phases

1. **Shield shell + IPC skeleton.** Quickshell config, systemd user service, socket,
   `pending`/`finished` protocol driven by a **stub event emitter** (fake sudo
   events). Iterate the top-center visual with zero PAM risk.
2. **Announce hook.** `pam_exec` `optional` rule emitting `pending`/`finished` for
   real `sudo`/`su`. Caller `/proc` walk + `hyprctl` window resolution. Reversible;
   cannot affect auth.
3. **Focus detection + click-to-focus.** Resolve focused vs unfocused; the popup's
   button warps focus to the caller terminal (`hyprctl dispatch focuswindow
   address:…`). Makes unfocused sudo usable *before* any password bridge exists.
4. **Password bridge (security-critical).** Rust PAM module (`catch_unwind`-wrapped),
   root-peer socket gate, `PAM_AUTHTOK` relay, adjacent `use_first_pass` verifier,
   front-of-stack ordering. Gets `find-bugs` + `security-review`; must pass the
   phishing-resistance, crash-safety, lid-check-untouched, and lock-out-recovery
   gates; rolled out g6-first with a root shell open (see Rollout & recovery).

## Testing

- **Lock-out recovery (gate for phase 4):** kill the shield, delete the socket,
  SIGSTOP the shell — `sudo true` must still authenticate via the normal flow on
  gen4/gen5/gen6.
- **PAM stack pinning:** assert the generated `/etc/pam.d/sudo` matches the shape the
  jump count assumes; fail the build if it drifts.
- **Focus matrix:** focused-terminal, unfocused-terminal, no-window (cron), lid-closed
  (no sensor) — each yields the documented branch.
- **Relay correctness:** wrong password in popup → `pam_unix` denies (no tty
  fallback under `use_first_pass`); correct password → success.
- **Retry loop:** wrong password emits `retry{n}` and re-prompts up to `passwd_tries`;
  a correct entry on attempt 2/3 succeeds; exhausting tries aborts and dismisses.
- **Dismiss paths:** success, failure, cancel, timeout, and sudo killed mid-prompt all
  dismiss the shield.
- **Cancel kills sudo:** cancel terminates the sudo (non-zero exit, command not run)
  via the pidfd; a recycled PID is never signaled (kill an unrelated process after the
  tracked sudo exits → no stray signal). Timeout does **not** kill.
- **Phishing resistance (gate for phase 4):** a non-root process connecting as the
  user and sending a forged `pending` gets **no** prompt and **no** password — the
  shield rejects peer uid != 0.
- **Crash-safety (gate for phase 4):** a deliberately-faulted bridge (`panic!` /
  segfault-inducing input) still lets `sudo true` authenticate via the normal flow.
- **lid-check untouched:** with the lid closed, `fprintd` is still skipped exactly as
  before — assert `lid-check`'s generated line is byte-identical to pre-feature.
- **Non-interactive sudo:** `echo pw | sudo -S true` from an unfocused terminal does
  **not** pop a GUI (stdin-not-a-tty → fail-open).
- **Socket hardening:** the socket enforces `SO_PEERCRED` uid==0; same-user non-root
  peers are rejected.

## Risks & open questions

- **R1 — PAM ordering fragility (now low, was high).** Downgraded by the adjacent
  `+1` verifier and front-of-stack placement (no counting over `fprintd`, `lid-check`
  untouched). Residual: the verifier must stay the bridge's immediate successor —
  pinned by the generated-`/etc/pam.d/sudo` test.
- **R6 — same-uid socket check is insufficient (critical, mitigated).** A forged
  `pending` from user-level malware would phish the password. Mitigated by the
  root-peer (`uid==0`) gate. The whole feature's safety rests on this check being
  correct — top priority for `security-review`.
- **R7 — module crash crashes sudo (critical, mitigated).** Control flags can't
  fail-open a `SIGSEGV`/panic. Mitigated by Rust + `catch_unwind` + the faulted-module
  test. No `unwrap` on the auth path, ever.
- **R2 — focus decided once at auth start.** If the user focuses the caller terminal,
  then alt-tabs away mid-prompt, the branch doesn't re-evaluate. Acceptable for v1;
  could add live re-evaluation later.
- **R3 — `su` parity.** `su`'s caller/window resolution should match `sudo`; if it
  proves flaky, ship GUI for `sudo` only and keep announce-only for `su`.
- **R4 — Rust PAM module packaging** in `packages/` (cross-compile/`pam-bindings`
  availability). Validate early in phase 4; fallback is a minimal C module.
- **R5 — cancel-signal permission unverified.** The design assumes a user-session
  process may `SIGINT` its own setuid-root sudo (target keeps the user's real UID).
  Confirm empirically before relying on it; if blocked, cancel falls back to the
  fail-open path (collapse popup, normal flow) — degraded but safe.
- **R8 — `su` edge cases.** `su <user>` relays the *target* user's password (popup
  must label whose), and `su` invoked *by root* breaks the user-signals-sudo cancel
  assumption. Keep `su` GUI behind the R3 parity gate; announce-only is always safe.

## Rejected alternatives

- **`pam_exec` sets `PAM_AUTHTOK` (broken).** `pam_exec` only *exposes* the existing
  token to the script (`expose_authtok`); it cannot write a new token back into the
  PAM handle. The password bridge therefore must be a real PAM module.
- **Shield runs its own `PamContext` and asserts success (insecure).** Lets a
  user-level process impersonate the shield and escalate. Rejected in favour of
  root-verifies-everything.
- **Same-uid socket check (`SO_PEERCRED` uid == user) (insecure).** The hook and
  malware share the uid, so a forged `pending` phishes the password back to the
  attacker. Rejected in favour of the root-peer (`uid == 0`) gate.
- **`pam_unix try_first_pass` for the relayed token (hangs).** On a wrong password it
  falls back to a tty prompt that goes nowhere on an unfocused terminal. Rejected in
  favour of a dedicated `use_first_pass` verifier line.
- **Mechanism B — self-contained custom PAM module draws its own GUI.** More
  security-critical hand-written code in the auth path; rejected in favour of a thin
  bridge + separate UI process.
- **Mechanism C — pty wrapper (cockpit-style).** Scrapes the `[sudo] password:` prompt
  and feeds a pty; stays out of the PAM stack but fights `fprintd`'s own prompts and
  is brittle. Rejected.
- **`SUDO_ASKPASS`/`sudo -A`.** Only triggers with no tty or explicit `-A`; cannot be
  made focus-conditional and we don't control how Claude Code invokes `sudo`.
