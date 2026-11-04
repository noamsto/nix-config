# sudo-shield v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An ambient top-center "shield" that appears whenever `sudo` is waiting for auth in an unfocused terminal, shows which process triggered it, and offers a one-click "focus the calling terminal" button — so Claude-Code-style background `sudo` calls are never silently blocking.

**Architecture:** A dedicated Quickshell config (`~/.config/quickshell/sudo-shield/`) run as a systemd user service draws the shield. A PAM `pam_exec` rule on `/etc/pam.d/sudo` (control `optional`, so it can never affect auth) fires a tiny script that sends a `pending` IPC message to the running Quickshell instance. Two correctness-critical pieces — walking `/proc` to identify the caller, and asking Hyprland whether the caller's window is focused — are standalone, unit-tested shell scripts; the QML is thin glue that calls them via `Quickshell.Io.Process`. **No password ever leaves the terminal; the PAM hook cannot change the auth outcome.** (In-popup password entry is v2, deliberately out of scope — see the spec's deferred section.)

**Tech Stack:** Nix (Home Manager + NixOS modules), Quickshell 0.3.0 QML (`PanelWindow`, `IpcHandler`, `Process`), `pam_exec`, `hyprctl`, `jq`, bash.

**Spec:** `docs/superpowers/specs/2026-06-09-sudo-shield-design.md`

---

## File structure

| File | Responsibility |
|---|---|
| `home/desktop/sudo-shield/default.nix` | HM module: builds the helper scripts (`sudo-shield-resolve`, stub emitter), deploys the QML config via `xdg.configFile`, defines the `sudo-shield` systemd user service. |
| `home/desktop/sudo-shield/shell.qml` | Quickshell entry: `IpcHandler` (receives `pending`), shared state, one `PanelWindow` per screen. |
| `home/desktop/sudo-shield/Shield.qml` | The visual component: passive tab → expanded card (caller line, Focus-terminal, Dismiss). |
| `home/desktop/sudo-shield/resolve-focus.sh` | **Unit-tested.** Given caller PIDs, ask `hyprctl` for the caller's window + whether it's focused. Emits JSON. |
| `home/desktop/sudo-shield/announce.sh` | **Unit-tested.** `pam_exec` script: walk `/proc` for the caller chain + tty, send `pending` IPC. |
| `home/desktop/sudo-shield/tests/` | Plain-bash test scripts for the two `.sh` units (fixtures injected via env). |
| `nixos/hyprland/sudo-shield-pam.nix` | NixOS module: the `security.pam.services.sudo.rules` `optional` announce rule. |

**Wiring (added in the relevant tasks):**
- `home/desktop/default.nix` — add `./sudo-shield` to the `desktop.mode == "hyprland"` import list (next to `./hyprland`, `./noctalia`).
- `nixos/hyprland/default.nix` — add `./sudo-shield-pam.nix` to `imports`.

**v1 scope note:** implement for **`sudo` only**. `su` is announce-only and needs `PAM_RUSER` (not `PAM_USER`) for the runtime dir; it's a trivial extension once `sudo` works and is left as a follow-on (spec risk R3). Do not copy `pam-lid-check.nix`'s `["login" "sudo" "su" "polkit-1"]` list.

**Rebuild command (this host is Linux/Hyprland):** `nh home switch` for HM-only changes, `nh os switch` after touching the NixOS PAM module. Remember the repo gotcha: `git add` new files before rebuilding (untracked files are invisible to the flake), and the first commit may need a re-run after pre-commit reformats.

---

## Phase 1 — Shield shell + IPC skeleton (no PAM yet)

### Task 1: HM module scaffold + empty Quickshell service

**Files:**
- Create: `home/desktop/sudo-shield/default.nix`
- Create: `home/desktop/sudo-shield/shell.qml`
- Modify: `home/desktop/default.nix` (import list)

- [ ] **Step 1: Write a minimal `shell.qml` that just logs on start**

`home/desktop/sudo-shield/shell.qml`:
```qml
//@ pragma UseQApplication
import Quickshell
import Quickshell.Io

ShellRoot {
    Component.onCompleted: console.log("sudo-shield: started")

    IpcHandler {
        target: "shield"
        function pending(payload: string): void {
            console.log("sudo-shield: pending " + payload);
        }
    }
}
```

- [ ] **Step 2: Write the HM module that deploys the config and runs the service**

`home/desktop/sudo-shield/default.nix`:
```nix
{pkgs, ...}: {
  # Deploy the Quickshell config to ~/.config/quickshell/sudo-shield/
  xdg.configFile."quickshell/sudo-shield/shell.qml".source = ./shell.qml;

  systemd.user.services.sudo-shield = {
    Unit = {
      Description = "sudo-shield — ambient sudo auth indicator";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c sudo-shield";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
```

- [ ] **Step 3: Add the import**

In `home/desktop/default.nix`, change the hyprland optional import list:
```nix
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
      ./noctalia
      ./sudo-shield
    ];
```

- [ ] **Step 4: Stage, rebuild, verify the service is up**

```bash
git add home/desktop/sudo-shield home/desktop/default.nix
nh home switch
```
Then:
```bash
systemctl --user status sudo-shield
```
Expected: `active (running)`. And:
```bash
journalctl --user -u sudo-shield -n 20 --no-pager
```
Expected: a line containing `sudo-shield: started`.

- [ ] **Step 5: Verify IPC reachability**

```bash
quickshell -c sudo-shield ipc call shield pending '{"hello":"world"}'
journalctl --user -u sudo-shield -n 5 --no-pager
```
Expected: a log line `sudo-shield: pending {"hello":"world"}`. (If `ipc call` can't find the instance, confirm the service is running and `quickshell -c sudo-shield ipc show` lists the `shield` target.)

- [ ] **Step 6: Commit**

```bash
git add home/desktop/sudo-shield home/desktop/default.nix
git commit -m "feat(sudo-shield): scaffold quickshell service + IPC skeleton"
```

---

### Task 2: Passive shield tab + stub emitter

**Files:**
- Create: `home/desktop/sudo-shield/Shield.qml`
- Modify: `home/desktop/sudo-shield/shell.qml`
- Modify: `home/desktop/sudo-shield/default.nix` (add stub emitter)

- [ ] **Step 1: Write the Shield component (passive tab only for now)**

`home/desktop/sudo-shield/Shield.qml`:
```qml
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property string caller   // e.g. "claude → node → sudo nixos-rebuild"

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 32
    radius: 16
    color: "#1e1e2e"          // Noctalia MD3 surface; refined in a later task
    border.color: "#f9e2af"   // amber — "attention"
    border.width: 1

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Text {
            text: "\u{1F510}"      // 🔐
            font.pixelSize: 16
        }
        Text {
            text: "sudo · " + root.caller
            color: "#cdd6f4"
            font.pixelSize: 13
        }
    }
}
```

- [ ] **Step 2: Wire shared state + one PanelWindow per screen into `shell.qml`**

Replace `home/desktop/sudo-shield/shell.qml` with:
```qml
//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: app

    // Active request state. Empty caller == nothing pending.
    property bool active: false
    property string caller: ""
    property int sudoPid: 0

    IpcHandler {
        target: "shield"
        function pending(payload: string): void {
            const data = JSON.parse(payload);
            app.caller = data.caller || "sudo";
            app.sudoPid = data.pid || 0;
            app.active = true;
        }
        function dismiss(): void {
            app.active = false;
            app.caller = "";
            app.sudoPid = 0;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: app.active

            // Anchor top only → compositor centers horizontally.
            anchors.top: true
            margins.top: 6
            exclusiveZone: 0
            implicitWidth: shield.implicitWidth
            implicitHeight: shield.implicitHeight
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Shield {
                id: shield
                caller: app.caller
            }
        }
    }
}
```

- [ ] **Step 3: Add a stub emitter dev script to the HM module**

In `home/desktop/sudo-shield/default.nix`, add to the `let`/body — define the package and put it on PATH:
```nix
{pkgs, ...}: let
  stub-emitter = pkgs.writeShellScriptBin "sudo-shield-stub" ''
    set -euo pipefail
    ${pkgs.quickshell}/bin/quickshell -c sudo-shield ipc call shield pending \
      '{"pid":'"''${1:-99999}"',"caller":"claude → node → sudo nixos-rebuild","caller_pids":[1234],"tty":"pts/3"}'
  '';
in {
  home.packages = [stub-emitter];

  xdg.configFile."quickshell/sudo-shield/shell.qml".source = ./shell.qml;
  xdg.configFile."quickshell/sudo-shield/Shield.qml".source = ./Shield.qml;

  systemd.user.services.sudo-shield = {
    Unit = {
      Description = "sudo-shield — ambient sudo auth indicator";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c sudo-shield";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
```

- [ ] **Step 4: Rebuild and run the visual check**

```bash
git add home/desktop/sudo-shield
nh home switch
systemctl --user restart sudo-shield
sudo-shield-stub
```
Expected: a small rounded amber-bordered "🔐 sudo · claude → node → sudo nixos-rebuild" tab appears centered at the top of the screen.

- [ ] **Step 5: Screenshot to confirm placement**

```bash
grim -g "$(slurp -o)" /tmp/sudo-shield-check.png   # click the monitor with the tab
```
Open `/tmp/sudo-shield-check.png` and confirm the tab is top-center and legible. Then dismiss:
```bash
quickshell -c sudo-shield ipc call shield dismiss
```
Expected: the tab disappears.

- [ ] **Step 6: Commit**

```bash
git add home/desktop/sudo-shield
git commit -m "feat(sudo-shield): passive top-center tab + stub emitter"
```

---

### Task 3: Auto-dismiss when the sudo process exits + timeout backstop

**Files:**
- Modify: `home/desktop/sudo-shield/shell.qml`

- [ ] **Step 1: Add a PID waiter and timeout to `shell.qml`**

Inside `ShellRoot` in `shell.qml`, add (after the `IpcHandler` block):
```qml
    // Dismiss when the tracked sudo process exits (no "finished" IPC needed),
    // with a hard timeout backstop in case the pid is never seen.
    Process {
        id: pidWaiter
        running: app.active && app.sudoPid > 0
        // bash (not sh): Task 7 pins the service PATH and bash is guaranteed there.
        // `kill` is a bash builtin; `sleep` comes from coreutils on the pinned PATH.
        command: ["bash", "-c", "while kill -0 " + app.sudoPid + " 2>/dev/null; do sleep 0.3; done"]
        onExited: (code, status) => { if (app.active) shieldIpc.dismiss(); }
    }

    Timer {
        id: backstop
        interval: 120000
        running: app.active
        onTriggered: shieldIpc.dismiss()
    }
```

Add `import Quickshell.Io` is already present. Give the `IpcHandler` an `id: shieldIpc` so `dismiss()` is callable from the waiter/timer:
```qml
    IpcHandler {
        id: shieldIpc
        target: "shield"
        // ... existing pending()/dismiss() ...
    }
```

- [ ] **Step 2: Rebuild**

```bash
git add home/desktop/sudo-shield/shell.qml
nh home switch
systemctl --user restart sudo-shield
```

- [ ] **Step 3: Verify auto-dismiss on process exit**

```bash
sleep 600 &              # a fake "sudo" to track
FAKE=$!
quickshell -c sudo-shield ipc call shield pending '{"pid":'"$FAKE"',"caller":"test → sleep","caller_pids":['"$FAKE"'],"tty":"pts/9"}'
```
Expected: tab appears. Then:
```bash
kill $FAKE
```
Expected: tab disappears within ~0.5s.

- [ ] **Step 4: Commit**

```bash
git add home/desktop/sudo-shield/shell.qml
git commit -m "feat(sudo-shield): auto-dismiss on tracked pid exit + 120s backstop"
```

---

## Phase 2 — Announce hook (PAM, `optional`, cannot affect auth)

### Task 4: `announce.sh` — caller `/proc` walk (unit-tested)

**Files:**
- Create: `home/desktop/sudo-shield/announce.sh`
- Create: `home/desktop/sudo-shield/tests/test-announce.sh`

The script reads its own PPID (the `sudo` process), walks ancestors to build a caller chain string + a list of PIDs, and sends a `pending` IPC. For testability, the IPC sink is overridable: if `SUDO_SHIELD_IPC_OUT` is set, the JSON is written there instead of invoking `quickshell`.

- [ ] **Step 1: Write the failing test**

`home/desktop/sudo-shield/tests/test-announce.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../announce.sh"

out="$(mktemp)"
# Run the script as a child of a known process tree: this test shell is the
# "caller"; the script's PPID is this shell. Emit to the file sink.
SUDO_SHIELD_IPC_OUT="$out" PAM_TTY="pts/7" bash "$SCRIPT"

payload="$(cat "$out")"
echo "payload: $payload"

# Must be valid JSON with the expected keys.
echo "$payload" | jq -e '.pid | numbers' >/dev/null   || { echo "FAIL: no numeric pid"; exit 1; }
echo "$payload" | jq -e '.tty == "pts/7"' >/dev/null   || { echo "FAIL: tty wrong"; exit 1; }
echo "$payload" | jq -e '.caller | strings' >/dev/null || { echo "FAIL: no caller string"; exit 1; }
echo "$payload" | jq -e '.caller_pids | arrays | length > 0' >/dev/null || { echo "FAIL: no caller_pids"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run it, expect failure (script missing)**

```bash
bash home/desktop/sudo-shield/tests/test-announce.sh
```
Expected: fails — `announce.sh` does not exist yet.

- [ ] **Step 3: Write `announce.sh`**

`home/desktop/sudo-shield/announce.sh`:
```bash
#!/usr/bin/env bash
# pam_exec announce hook for sudo-shield. MUST be fast, non-blocking, and never
# fail the caller — it runs in sudo's auth stack as control=optional, so its exit
# code is ignored, but we still keep it cheap. It only emits a "pending" event.
set -u

# The script is a child of sudo; its parent is the sudo process.
sudo_pid="$PPID"

# Walk ancestors from sudo upward, collecting a command chain and pid list.
# Stop at pid 1 or after a sane depth cap.
chain=()
pids=()
pid="$sudo_pid"
depth=0
while [ "$pid" -gt 1 ] && [ "$depth" -lt 12 ]; do
  comm="$(cat "/proc/$pid/comm" 2>/dev/null || echo '?')"
  chain=("$comm" "${chain[@]}")
  pids+=("$pid")
  ppid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || echo 1)"
  pid="$ppid"
  depth=$((depth + 1))
done

# Build "a → b → c" and a JSON array of pids.
caller="$(printf '%s → ' "${chain[@]}")"
caller="${caller% → }"
pids_json="$(printf '%s,' "${pids[@]}")"
pids_json="[${pids_json%,}]"

tty="${PAM_TTY:-?}"

payload="$(jq -nc \
  --argjson pid "$sudo_pid" \
  --arg caller "$caller" \
  --argjson caller_pids "$pids_json" \
  --arg tty "$tty" \
  '{pid:$pid, caller:$caller, caller_pids:$caller_pids, tty:$tty}')"

if [ -n "${SUDO_SHIELD_IPC_OUT:-}" ]; then
  printf '%s' "$payload" > "$SUDO_SHIELD_IPC_OUT"
  exit 0
fi

# Real path: send to the running shield, time-bounded, never blocking sudo.
timeout 1 quickshell -c sudo-shield ipc call shield pending "$payload" 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Run the test, expect PASS**

```bash
bash home/desktop/sudo-shield/tests/test-announce.sh
```
Expected: `PASS`.

- [ ] **Step 5: shellcheck**

```bash
shellcheck home/desktop/sudo-shield/announce.sh home/desktop/sudo-shield/tests/test-announce.sh
```
Expected: no warnings/errors. (Fix any before continuing — required by repo policy.)

- [ ] **Step 6: Commit**

```bash
git add home/desktop/sudo-shield/announce.sh home/desktop/sudo-shield/tests/test-announce.sh
git commit -m "feat(sudo-shield): announce.sh /proc caller walk (unit-tested)"
```

---

### Task 5: Wire `announce.sh` as a PAM `optional` rule on `sudo`

**Files:**
- Create: `nixos/hyprland/sudo-shield-pam.nix`
- Modify: `nixos/hyprland/default.nix` (import)

The script needs `jq` + `quickshell` on its PATH and `XDG_RUNTIME_DIR` set so `quickshell ipc` finds the user instance. It runs `seteuid` to the invoking user (PAM_USER for `sudo`) — like `pam-lid-check.nix`.

- [ ] **Step 1: Write the NixOS module**

`nixos/hyprland/sudo-shield-pam.nix`:
```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  inherit (config.desktop) isHyprland;

  # Single source of truth: reuse the unit-tested announce.sh from the HM tree.
  # Path literal resolves relative to this file's directory.
  announceSrc = ../../home/desktop/sudo-shield/announce.sh;

  announceScript = pkgs.writeShellScript "sudo-shield-announce" ''
    export PATH="${lib.makeBinPath [pkgs.jq pkgs.quickshell pkgs.coreutils pkgs.gawk]}:$PATH"
    # quickshell ipc discovers the instance via XDG_RUNTIME_DIR; PAM env lacks it.
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    # Run via bash explicitly — the store copy of announce.sh is not +x.
    exec ${pkgs.bash}/bin/bash ${announceSrc}
  '';
in {
  config = lib.mkIf isHyprland {
    security.pam.services.sudo.rules.auth.sudo-shield-announce = {
      enable = true;
      control = "optional";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      # seteuid → run as the invoking user so quickshell ipc reaches their instance.
      args = ["quiet" "seteuid" (toString announceScript)];
      order = 11100; # before lid-check (11300); optional, so order is non-critical
    };
  };
}
```

> Note: referencing the HM script from a NixOS module via a relative path couples the two trees. If that coupling is undesirable, copy `announce.sh` into `nixos/hyprland/` instead. Keep one source of truth; do not let the two drift.

- [ ] **Step 2: Add the import**

In `nixos/hyprland/default.nix`:
```nix
  imports = [./gnome-services.nix ./sudo-shield-pam.nix];
```

- [ ] **Step 3: Stage and rebuild the system**

```bash
git add nixos/hyprland/sudo-shield-pam.nix nixos/hyprland/default.nix home/desktop/sudo-shield/announce.sh
nh os switch
```

- [ ] **Step 4: SAFETY CHECK — sudo still works**

Before anything else, in a **focused** terminal:
```bash
sudo true && echo "SUDO OK"
```
Expected: authenticates and prints `SUDO OK`. (The rule is `optional`; if sudo is in any way impaired, STOP — but `optional` + `pam_exec` child cannot deny auth.) Confirm the generated stack:
```bash
grep -n sudo-shield /etc/pam.d/sudo
```
Expected: one `auth optional pam_exec.so ... sudo-shield-announce` line, before the `lid-check` line.

- [ ] **Step 5: Verify a real unfocused sudo raises the shield**

In a terminal, run a sudo that will wait, then click away to unfocus it within the prompt window — or simpler, run from a script that backgrounds:
```bash
# From a focused terminal, then immediately focus another window:
sudo -k        # clear cached creds so it actually prompts
sudo true
```
Expected: the 🔐 shield appears top-center showing a caller chain ending in `sudo`. Authenticate (touch sensor or type), and the shield auto-dismisses when sudo exits.

- [ ] **Step 6: Confirm scope — NOT on polkit**

```bash
grep -c sudo-shield /etc/pam.d/polkit-1 || true
```
Expected: `0` (no match). The hook is `sudo`-only.

- [ ] **Step 7: Commit**

```bash
git add nixos/hyprland/sudo-shield-pam.nix nixos/hyprland/default.nix
git commit -m "feat(sudo-shield): fire announce IPC from sudo PAM stack (optional rule)"
```

---

## Phase 3 — Focus detection + click-to-focus

### Task 6: `resolve-focus.sh` — is the caller's window focused? (unit-tested)

**Files:**
- Create: `home/desktop/sudo-shield/resolve-focus.sh`
- Create: `home/desktop/sudo-shield/tests/test-resolve-focus.sh`

Given a comma-separated list of caller PIDs, find the Hyprland client whose `.pid` is in that set (the terminal window), and report whether it is the active window. Fixtures injected via `SUDO_SHIELD_CLIENTS_JSON` / `SUDO_SHIELD_ACTIVE_JSON`.

- [ ] **Step 1: Write the failing test**

`home/desktop/sudo-shield/tests/test-resolve-focus.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../resolve-focus.sh"

clients='[{"address":"0xAAA","pid":1234,"class":"kitty"},{"address":"0xBBB","pid":5678,"class":"firefox"}]'

# Case 1: caller pid 1234 is the terminal, and it is NOT the active window.
active='{"address":"0xBBB","pid":5678}'
res="$(SUDO_SHIELD_CLIENTS_JSON="$clients" SUDO_SHIELD_ACTIVE_JSON="$active" bash "$SCRIPT" "9999,1234")"
echo "case1: $res"
echo "$res" | jq -e '.found == true and .focused == false and .address == "0xAAA"' >/dev/null \
  || { echo "FAIL case1"; exit 1; }

# Case 2: the terminal IS the active window.
active='{"address":"0xAAA","pid":1234}'
res="$(SUDO_SHIELD_CLIENTS_JSON="$clients" SUDO_SHIELD_ACTIVE_JSON="$active" bash "$SCRIPT" "1234")"
echo "case2: $res"
echo "$res" | jq -e '.found == true and .focused == true' >/dev/null || { echo "FAIL case2"; exit 1; }

# Case 3: no caller pid matches any window (headless/cron).
res="$(SUDO_SHIELD_CLIENTS_JSON="$clients" SUDO_SHIELD_ACTIVE_JSON="$active" bash "$SCRIPT" "4242")"
echo "case3: $res"
echo "$res" | jq -e '.found == false' >/dev/null || { echo "FAIL case3"; exit 1; }

echo "PASS"
```

- [ ] **Step 2: Run it, expect failure**

```bash
bash home/desktop/sudo-shield/tests/test-resolve-focus.sh
```
Expected: fails — script missing.

- [ ] **Step 3: Write `resolve-focus.sh`**

`home/desktop/sudo-shield/resolve-focus.sh`:
```bash
#!/usr/bin/env bash
# Resolve whether the caller's terminal window is the focused one.
# Arg 1: comma-separated caller pids (from announce.sh).
# Output: JSON {found:bool, focused:bool, address:string}.
set -euo pipefail

pids_csv="${1:-}"

clients="${SUDO_SHIELD_CLIENTS_JSON:-$(hyprctl clients -j)}"
active="${SUDO_SHIELD_ACTIVE_JSON:-$(hyprctl activewindow -j)}"

# jq: turn "9999,1234" into an array, find the first client whose pid is in it.
result="$(jq -nc \
  --argjson clients "$clients" \
  --argjson active "$active" \
  --arg pids "$pids_csv" '
  ($pids | split(",") | map(tonumber)) as $callerPids
  | ($clients | map(select(.pid as $p | $callerPids | index($p))) | first) as $win
  | if $win == null
    then {found:false, focused:false, address:""}
    else {found:true, focused:($win.address == $active.address), address:$win.address}
    end
')"
printf '%s' "$result"
```

- [ ] **Step 4: Run the test, expect PASS**

```bash
bash home/desktop/sudo-shield/tests/test-resolve-focus.sh
```
Expected: `PASS`.

- [ ] **Step 5: shellcheck**

```bash
shellcheck home/desktop/sudo-shield/resolve-focus.sh home/desktop/sudo-shield/tests/test-resolve-focus.sh
```
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add home/desktop/sudo-shield/resolve-focus.sh home/desktop/sudo-shield/tests/test-resolve-focus.sh
git commit -m "feat(sudo-shield): resolve-focus.sh window/focus detection (unit-tested)"
```

---

### Task 7: Expanded card with Focus-terminal + Dismiss; passive when focused

**Files:**
- Modify: `home/desktop/sudo-shield/default.nix` (deploy `resolve-focus.sh`, expose its path to QML)
- Modify: `home/desktop/sudo-shield/shell.qml` (call resolve on `pending`, store focus + address + term pid)
- Modify: `home/desktop/sudo-shield/Shield.qml` (expanded state + buttons)

- [ ] **Step 1: Deploy `resolve-focus.sh` and pass its path + hyprctl into the QML env**

In `home/desktop/sudo-shield/default.nix`, add a resolver package and reference it from the service env. Replace the `let`/service so the resolver is on the service PATH and its path is exported:
```nix
{pkgs, ...}: let
  resolver = pkgs.writeShellApplication {
    name = "sudo-shield-resolve";
    runtimeInputs = [pkgs.jq pkgs.hyprland];
    text = builtins.readFile ./resolve-focus.sh;
  };
  stub-emitter = pkgs.writeShellScriptBin "sudo-shield-stub" ''
    set -euo pipefail
    ${pkgs.quickshell}/bin/quickshell -c sudo-shield ipc call shield pending \
      '{"pid":'"''${1:-99999}"',"caller":"claude → node → sudo nixos-rebuild","caller_pids":[1234],"tty":"pts/3"}'
  '';
in {
  home.packages = [stub-emitter resolver];

  xdg.configFile."quickshell/sudo-shield/shell.qml".source = ./shell.qml;
  xdg.configFile."quickshell/sudo-shield/Shield.qml".source = ./Shield.qml;

  systemd.user.services.sudo-shield = {
    Unit = {
      Description = "sudo-shield — ambient sudo auth indicator";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      # Pin a complete PATH for the QML's Process calls: resolver + hyprctl
      # (focus dispatch), bash + coreutils (pid-waiter's `bash -c … sleep`).
      Environment = ["PATH=${pkgs.lib.makeBinPath [resolver pkgs.hyprland pkgs.bash pkgs.coreutils]}"];
      ExecStart = "${pkgs.quickshell}/bin/quickshell -c sudo-shield";
      Restart = "on-failure";
      RestartSec = "3s";
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
```

- [ ] **Step 2: In `shell.qml`, resolve focus on `pending` and store the result**

Update the `pending` handler and state in `shell.qml`:
```qml
    property bool active: false
    property string caller: ""
    property int sudoPid: 0
    property string callerPids: ""     // "1234,5678"
    property bool focused: true
    property bool windowFound: false

    IpcHandler {
        id: shieldIpc
        target: "shield"
        function pending(payload: string): void {
            const data = JSON.parse(payload);
            app.caller = data.caller || "sudo";
            app.sudoPid = data.pid || 0;
            app.callerPids = (data.caller_pids || []).join(",");
            app.active = true;
            resolver.running = true;     // kick off focus resolution
        }
        function dismiss(): void {
            app.active = false; app.caller = ""; app.sudoPid = 0;
            app.callerPids = ""; app.focused = true; app.windowFound = false;
        }
    }

    property string shield_targetAddress: ""

    Process {
        id: resolver
        command: ["sudo-shield-resolve", app.callerPids]
        stdout: StdioCollector {
            id: resolverOut
            onStreamFinished: {
                try {
                    const r = JSON.parse(resolverOut.text);
                    app.windowFound = r.found;
                    app.focused = r.focused;
                    app.shield_targetAddress = r.address;
                } catch (e) { /* fail-open: stay passive */ }
            }
        }
    }
```
(Keep the `pidWaiter`/`backstop` from Task 3. Ensure `import Quickshell.Io` is present for `Process`/`StdioCollector`.)

- [ ] **Step 3: Pass focus state + target into the Shield and expand when unfocused**

In `shell.qml`, update the `Shield {}` instantiation inside the `PanelWindow`:
```qml
            Shield {
                id: shield
                caller: app.caller
                expanded: app.active && app.windowFound && !app.focused
                targetAddress: app.shield_targetAddress
                onFocusRequested: focusProc.running = true
                onDismissRequested: shieldIpc.dismiss()
            }

            Process {
                id: focusProc
                command: ["hyprctl", "dispatch", "focuswindow", "address:" + app.shield_targetAddress]
            }
```

- [ ] **Step 4: Build the expanded card in `Shield.qml`**

Replace `home/desktop/sudo-shield/Shield.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: root
    required property string caller
    property bool expanded: false
    property string targetAddress: ""

    signal focusRequested()
    signal dismissRequested()

    implicitWidth: col.implicitWidth + 24
    implicitHeight: col.implicitHeight + 16
    radius: 14
    color: "#1e1e2e"
    border.color: "#f9e2af"
    border.width: 1

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 8

        RowLayout {
            spacing: 8
            Text { text: "\u{1F510}"; font.pixelSize: 16 }
            Text {
                text: "sudo · " + root.caller
                color: "#cdd6f4"; font.pixelSize: 13
            }
        }

        RowLayout {
            visible: root.expanded
            spacing: 8
            Text {
                text: "unfocused — touch sensor, or"
                color: "#a6adc8"; font.pixelSize: 11
            }
            Button {
                text: "Focus terminal"
                onClicked: root.focusRequested()
            }
            Button {
                text: "Dismiss"
                onClicked: root.dismissRequested()
            }
        }
    }
}
```

- [ ] **Step 5: Rebuild and verify the focused case stays passive**

```bash
git add home/desktop/sudo-shield
nh home switch
systemctl --user restart sudo-shield
```
In a **focused** terminal:
```bash
sudo -k; sudo true
```
Expected: the shield shows the passive tab only (no buttons), because the calling terminal is focused. Authenticate; it dismisses.

- [ ] **Step 6: Verify the unfocused case expands and Focus works**

Run a sudo, then click another window so the terminal is unfocused while it waits. Easiest repeatable form: open two terminals A and B; in A run `sudo -k; sudo true`, then immediately click B.
Expected: the shield expands with "Focus terminal" / "Dismiss". Click **Focus terminal** → terminal A comes to the front and is focused. Type the password there → shield dismisses.

- [ ] **Step 7: Screenshot the expanded card**

```bash
grim -g "$(slurp)" /tmp/sudo-shield-expanded.png
```
Confirm the expanded card renders cleanly. (Adjust colors to match the live Noctalia palette here if desired — this is the styling-polish point.)

- [ ] **Step 8: Commit**

```bash
git add home/desktop/sudo-shield
git commit -m "feat(sudo-shield): focus-aware expanded card with click-to-focus"
```

---

## Final verification (v1 acceptance)

- [ ] **Auth-safety:** with the service stopped (`systemctl --user stop sudo-shield`) and the socket gone, `sudo true` authenticates normally. PAM hook is `optional` → cannot deny.
- [ ] **lid-check untouched:** `grep -A1 -B1 lid-check /etc/pam.d/sudo` shows the `lid-check` line and its `[success=ignore default=1 ...]` control unchanged from before the feature.
- [ ] **Scope:** `grep sudo-shield /etc/pam.d/polkit-1` returns nothing.
- [ ] **Focused path:** focused-terminal sudo → passive tab only.
- [ ] **Unfocused path:** unfocused-terminal sudo → expanded card; Focus-terminal warps focus; Dismiss hides it.
- [ ] **No-window path:** `sudo true` from a non-graphical context (e.g. a systemd unit or `ssh localhost sudo true`) shows no expanded card (resolver reports `found:false` → stays passive/absent).
- [ ] **Dismiss-on-exit:** killing the tracked sudo dismisses the shield within ~0.5s.
- [ ] Both unit test scripts pass and shellcheck is clean.

When all boxes are checked, v1 is complete. v2 (in-popup password entry behind a root broker) remains deferred per the spec.
