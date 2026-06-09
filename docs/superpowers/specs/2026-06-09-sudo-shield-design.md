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
root for verification, or tell the user to touch the sensor. Defense-in-depth: the
socket is per-user (`$XDG_RUNTIME_DIR`, mode 700) with an `SO_PEERCRED`/uid check on
every connection.

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

2. **Announce hook** — `pam_exec.so` rule in `security.pam.services.{sudo,su}.rules`,
   `seteuid` to the calling user (same mechanism as `nixos/laptop/pam-lid-check.nix`),
   control **`optional`** so it can never affect the auth outcome. Emits `pending`
   on entry. Walks `/proc` to identify the caller and resolves the terminal window
   via `hyprctl clients -j`.

3. **Password-bridge module** — a small **Rust PAM module** (`pam-bindings`),
   built as a derivation in `packages/`, placed in the `sudo`/`su` auth stack
   *before* `fprintd`. On the unfocused typed-password branch it sets `PAM_AUTHTOK`
   and returns a PAM control jump that skips `fprintd` and lands on
   `pam_unix use_first_pass`. (A `pam_exec` script **cannot** do this — see Rejected
   Alternatives.)

4. **Per-user socket** — `$XDG_RUNTIME_DIR/sudo-shield.sock`. The shield listens
   (as the user); the hook/module connect (`seteuid` user). `SO_PEERCRED` uid check.

## PAM stack ordering (the brittle part)

Current `sudo`/`su` auth stack (from `pam-lid-check.nix`):

```
11300  pam_exec  lid-check        [success=ignore default=1 perm_denied=1 auth_err=1]
11400  fprintd                    timeout=-1 max-tries=-1   (BLOCKS until touch / Ctrl+C)
 ....  pam_unix                   (try_first_pass)
```

New ordering:

```
~11200 pam_exec  sudo-shield-announce   optional         (emit "pending"; never affects auth)
11300  pam_exec  lid-check              (unchanged)
~11350 sudo-shield-bridge (Rust .so)    [<jump-over-fprintd-on-success> default=ignore]
            focused / no window / shield down / timeout → IGNORE  (fall through, normal flow)
            unfocused + typed password  → set PAM_AUTHTOK, SUCCESS+jump → pam_unix use_first_pass
            unfocused + "use fingerprint"→ IGNORE → fprintd activates → touch
11400  fprintd                          (unchanged; reached on the fingerprint/fall-through branch)
 ....  pam_unix                         (must honor use_first_pass for the relayed token)
```

⚠️ **The jump count in the bridge module's control is the single most
security-critical, install-fragile line in the feature.** It must be derived from
the **actual generated `/etc/pam.d/sudo`** on each host (gen4/gen5/gen6 may differ),
and pinned by a test that asserts the generated file matches expectations. If the
generated stack changes shape, the jump must be re-derived. Prefer expressing the
target via the NixOS `rules` ordering abstraction over a hardcoded integer where
possible.

## Data flow — unfocused typed-password sequence

```
Claude Code (unfocused kitty) ── runs ──▶ sudo nixos-rebuild
                                              │  opens PAM "sudo" transaction
   announce hook (optional)  ── emit ──▶ shield: show pending + caller line
                                              │
   bridge module:  walk /proc (PPID→sudo→caller), resolve window via hyprctl
                   active window == caller window?
                     yes → IGNORE (normal terminal flow; shield stays passive)
                     no  → shield: expand popup; BLOCK on socket (≤120s)
                            ├─ password{pw}     → set PAM_AUTHTOK; SUCCESS+jump → pam_unix verifies
                            ├─ use-fingerprint  → IGNORE → fprintd activates → touch
                            └─ cancel / timeout → IGNORE → normal flow
                                              │
   auth result ─────────────────────────────┘  → bridge emits "finished"
   shield dismiss when ANY of: "finished" received │ tracked sudo PID exits │ timeout
```

**IPC protocol (line-delimited JSON over the socket):**

- hook → shield: `{"event":"pending","pid":<sudo>,"tty":"pts/3","caller":"claude → node → nixos-rebuild","term_pid":<pid>,"focused":bool}`
- hook → shield: `{"event":"finished","pid":<sudo>}`
- shield → hook (reply): `{"action":"password","value":"…"}` | `{"action":"use-fingerprint"}` | `{"action":"cancel"}`

**Caller identity:** the hook/module is a child of `sudo`; `getppid()` → `sudo` pid;
`/proc/<sudo>/stat` PPID → the caller. Walk ancestors to the nearest known terminal,
collect the command chain, map terminal pid → window via `hyprctl clients -j`. `tty`
comes directly from `PAM_TTY`.

## Fail-open invariants (safety)

The bridge module returns `PAM_IGNORE` (never blocks/denies beyond normal flow) when:

- the caller's window is focused, or no terminal window can be identified;
- the socket is missing, the shield is not running, or the connection/`SO_PEERCRED` check fails;
- the user cancels, or the wait exceeds the timeout (≤120s).

Result: a dead/absent shield degrades to **exactly today's behaviour**. The feature
can never lock the user out of `sudo`.

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
4. **Password bridge (security-critical).** Rust PAM module, `PAM_AUTHTOK` relay,
   the `fprintd`-skip jump, `use_first_pass`. Gets `find-bugs` + `security-review`,
   a test pinning the generated `/etc/pam.d/sudo` shape, and an explicit **lock-out
   recovery test** (sudo still works with the shield/socket killed) on each host
   generation before enabling.

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
- **Dismiss paths:** success, failure, cancel, timeout, and sudo killed mid-prompt all
  dismiss the shield.
- **Socket hardening:** a second user/process cannot drive the socket (`SO_PEERCRED`).

## Risks & open questions

- **R1 — jump-count fragility (high).** Mitigated by the pinning test + preferring the
  `rules` ordering abstraction; still the thing most likely to break on a nixpkgs PAM
  change. Revisit if the generated stack shape changes.
- **R2 — focus decided once at auth start.** If the user focuses the caller terminal,
  then alt-tabs away mid-prompt, the branch doesn't re-evaluate. Acceptable for v1;
  could add live re-evaluation later.
- **R3 — `su` parity.** `su`'s caller/window resolution should match `sudo`; if it
  proves flaky, ship GUI for `sudo` only and keep announce-only for `su`.
- **R4 — Rust PAM module packaging** in `packages/` (cross-compile/`pam-bindings`
  availability). Validate early in phase 4; fallback is a minimal C module.

## Rejected alternatives

- **`pam_exec` sets `PAM_AUTHTOK` (broken).** `pam_exec` only *exposes* the existing
  token to the script (`expose_authtok`); it cannot write a new token back into the
  PAM handle. The password bridge therefore must be a real PAM module.
- **Shield runs its own `PamContext` and asserts success (insecure).** Lets a
  user-level process impersonate the shield and escalate. Rejected in favour of
  root-verifies-everything.
- **Mechanism B — self-contained custom PAM module draws its own GUI.** More
  security-critical hand-written code in the auth path; rejected in favour of a thin
  bridge + separate UI process.
- **Mechanism C — pty wrapper (cockpit-style).** Scrapes the `[sudo] password:` prompt
  and feeds a pty; stays out of the PAM stack but fights `fprintd`'s own prompts and
  is brittle. Rejected.
- **`SUDO_ASKPASS`/`sudo -A`.** Only triggers with no tty or explicit `-A`; cannot be
  made focus-conditional and we don't control how Claude Code invokes `sudo`.
