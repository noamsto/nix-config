# Porting Raycast Sesh Extension to Vicinae

## Table of Contents
1. [Overview](#overview)
2. [Architecture Analysis](#architecture-analysis)
3. [macOS-Specific Code Identification](#macos-specific-code-identification)
4. [Linux Adaptations Required](#linux-adaptations-required)
5. [API Compatibility](#api-compatibility)
6. [File-by-File Porting Guide](#file-by-file-porting-guide)
7. [Terminal Detection and Launching](#terminal-detection-and-launching)
8. [Testing Strategy](#testing-strategy)
9. [Effort Estimation](#effort-estimation)
10. [Implementation Checklist](#implementation-checklist)

---

## Overview

**Sesh** is a Raycast extension that provides tmux session management through a launcher interface. It integrates with the `sesh` CLI tool (which combines tmux and zoxide) to enable quick session switching and creation.

**Goal**: Port this extension to **Vicinae**, a native Linux launcher with Raycast-compatible API, enabling the same workflow on Linux systems.

**Key Benefits of Porting**:
- Native Linux support for sesh workflows
- Integration with Linux terminal emulators (kitty, alacritty, foot, wezterm, etc.)
- Maintain familiar Raycast extension patterns
- Leverage existing sesh CLI infrastructure

---

## Architecture Analysis

### Current Structure

```
extensions/sesh/
├── package.json          # Dependencies and metadata
├── src/
│   ├── app.ts           # Terminal launcher logic (macOS-specific)
│   ├── cmd-connect.tsx  # Main UI component (React)
│   ├── env.ts           # Environment PATH management
│   └── sesh.ts          # Sesh CLI wrapper functions
├── assets/              # Icons and images
└── metadata/            # Extension metadata
```

### Data Flow

```
User selects session in UI (cmd-connect.tsx)
         ↓
connectToSession() called (sesh.ts)
         ↓
Connects to tmux session via sesh CLI
         ↓
openApp() called (app.ts) ← macOS-specific!
         ↓
Launches terminal with session attached
         ↓
Closes Raycast/Vicinae UI
```

### Key Technologies

- **Raycast API**: `@raycast/api` v1.102.0+
- **Runtime**: Node.js with React SSR
- **CLI Tool**: `sesh` (must be installed separately)
- **Session Manager**: tmux
- **Directory Indexer**: zoxide

---

## macOS-Specific Code Identification

### 1. Terminal Launching (`app.ts`)

**Current Implementation (macOS)**:
```typescript
export function openApp() {
  const { openWithApp } = getPreferenceValues<Preferences.CmdConnect>();
  if (!openWithApp) {
    return Promise.reject(new Error("No app selected"));
  }
  return new Promise<void>((resolve, reject) => {
    exec(`open -a ${openWithApp.name}`, { env }, (error, _, stderr) => {
      if (error || stderr) return reject(error?.message ?? stderr);
      return resolve();
    });
  });
}
```

**Issues**:
- `open -a` is macOS-specific (uses LaunchServices)
- Relies on app bundle names (e.g., "iTerm", "Terminal.app")
- No equivalent `open` command on Linux

### 2. Preference Configuration (`package.json`)

**Current Terminal Selection**:
```json
{
  "name": "openWithApp",
  "type": "appPicker",
  "required": false,
  "title": "App",
  "description": "Which app to open?"
}
```

**Issues**:
- `appPicker` type is macOS-specific (shows installed .app bundles)
- Linux doesn't have .app bundles
- Need different selection mechanism

### 3. Path Handling

**Current**: Works universally, but defaults may differ
```typescript
// Default PATH in package.json
"default": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
```

**Linux Differences**:
- No `/opt/homebrew/bin` (Homebrew on macOS)
- Common Linux paths: `/usr/local/bin`, `/usr/bin`, `~/.local/bin`, `~/.nix-profile/bin`

---

## Linux Adaptations Required

### 1. Terminal Emulator Detection

**Strategy**: Support common Linux terminal emulators with fallback chain

**Popular Linux Terminals** (in priority order):
1. **kitty** - GPU-accelerated, feature-rich
2. **alacritty** - Fast, minimal, GPU-accelerated
3. **foot** - Wayland-native, lightweight
4. **wezterm** - Feature-rich, cross-platform
5. **gnome-terminal** - Default on GNOME
6. **konsole** - Default on KDE Plasma
7. **xterm** - Universal fallback

**Detection Methods**:
```bash
# Method 1: Environment variable (if set)
echo $TERMINAL

# Method 2: Check running processes
ps -o comm= -p $PPID

# Method 3: Check if binary exists
which kitty || which alacritty || which foot || ...
```

### 2. Terminal Launch Commands

Each terminal has different command-line syntax:

| Terminal | Launch Command | Execute Command Flag |
|----------|---------------|---------------------|
| kitty | `kitty` | `--detach -e` or `sh -c` |
| alacritty | `alacritty` | `-e` |
| foot | `foot` | `-e` |
| wezterm | `wezterm` | `start --` |
| gnome-terminal | `gnome-terminal` | `--` |
| konsole | `konsole` | `-e` |
| xterm | `xterm` | `-e` |

**Example Launch Commands**:
```bash
# Kitty
kitty --detach sh -c "sesh connect 'session-name'"

# Alacritty
alacritty -e sesh connect 'session-name'

# Foot
foot -e sesh connect 'session-name'

# WezTerm
wezterm start -- sesh connect 'session-name'

# GNOME Terminal
gnome-terminal -- sesh connect 'session-name'

# Konsole
konsole -e sesh connect 'session-name'
```

### 3. Environment Detection

**Linux-Specific Considerations**:
- Desktop environment (GNOME, KDE, Hyprland, Sway, etc.)
- Display server (X11 vs Wayland)
- Session type affects terminal availability

```bash
# Detect desktop environment
echo $XDG_CURRENT_DESKTOP  # "GNOME", "KDE", "Hyprland", etc.

# Detect display server
echo $XDG_SESSION_TYPE  # "x11" or "wayland"
```

---

## API Compatibility

### Vicinae vs Raycast API

**Good News**: Vicinae aims for API compatibility with Raycast extensions!

According to research:
> "Vicinae provides a mostly compatible extension API, allowing reuse of many existing Raycast extensions with minimal modification."

### Expected Compatible APIs

These should work without changes:
```typescript
// From @raycast/api (should work in @vicinae/api)
import {
  List,              // ✅ UI component
  Action,            // ✅ User actions
  ActionPanel,       // ✅ Action container
  showToast,         // ✅ Notifications
  Toast,             // ✅ Toast types
  closeMainWindow,   // ✅ Window control
  getPreferenceValues, // ✅ Preferences
} from "@raycast/api";
```

### Potentially Different APIs

**Preferences**:
- `appPicker` type likely unavailable on Linux
- Replace with `dropdown` or `textfield`

```typescript
// macOS (Raycast)
{
  "name": "openWithApp",
  "type": "appPicker",  // ❌ macOS-specific
  "title": "App"
}

// Linux (Vicinae)
{
  "name": "terminal",
  "type": "dropdown",   // ✅ Manual selection
  "title": "Terminal Emulator",
  "data": [
    {"value": "kitty", "title": "Kitty"},
    {"value": "alacritty", "title": "Alacritty"},
    {"value": "foot", "title": "Foot"},
    {"value": "wezterm", "title": "WezTerm"},
    {"value": "gnome-terminal", "title": "GNOME Terminal"},
    {"value": "konsole", "title": "Konsole"}
  ]
}
```

### Testing API Compatibility

**Recommended Approach**:
1. Start with `@raycast/api` imports (Vicinae claims compatibility)
2. If issues arise, switch to `@vicinae/api`
3. Document any differences encountered

---

## File-by-File Porting Guide

### 1. `package.json`

**Changes Required**: ⚠️ Medium

**Before (macOS)**:
```json
{
  "name": "sesh",
  "title": "Sesh",
  "description": "Smart session manager for the terminal",
  "icon": "command-icon.png",
  "author": "joshmedeski",
  "categories": ["Developer Tools", "Productivity"],
  "license": "MIT",
  "commands": [
    {
      "name": "cmd-connect",
      "title": "Connect to Session",
      "description": "Connect to a tmux session",
      "mode": "view",
      "preferences": [
        {
          "name": "openWithApp",
          "type": "appPicker",
          "required": false,
          "title": "App",
          "description": "Which app to open?"
        },
        {
          "name": "environmentPath",
          "type": "textfield",
          "required": false,
          "title": "Environment Path",
          "description": "Colon-separated Unix PATH",
          "default": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
      ]
    }
  ],
  "dependencies": {
    "@raycast/api": "^1.102.0"
  },
  "devDependencies": {
    "@types/node": "^20.14.0",
    "@types/react": "^18.3.3",
    "typescript": "^5.8.2",
    "eslint": "^9.22.0",
    "prettier": "^3.5.3"
  },
  "scripts": {
    "dev": "ray develop",
    "build": "ray build",
    "lint": "ray lint",
    "publish": "ray publish"
  }
}
```

**After (Linux)**:
```json
{
  "name": "sesh",
  "title": "Sesh",
  "description": "Smart session manager for the terminal (Linux)",
  "icon": "command-icon.png",
  "author": "joshmedeski",
  "contributors": ["your-name"],
  "categories": ["Developer Tools", "Productivity"],
  "license": "MIT",
  "commands": [
    {
      "name": "cmd-connect",
      "title": "Connect to Session",
      "description": "Connect to a tmux session",
      "mode": "view",
      "preferences": [
        {
          "name": "terminal",
          "type": "dropdown",
          "required": false,
          "title": "Terminal Emulator",
          "description": "Which terminal to use",
          "default": "auto",
          "data": [
            {"value": "auto", "title": "Auto-detect"},
            {"value": "kitty", "title": "Kitty"},
            {"value": "alacritty", "title": "Alacritty"},
            {"value": "foot", "title": "Foot"},
            {"value": "wezterm", "title": "WezTerm"},
            {"value": "gnome-terminal", "title": "GNOME Terminal"},
            {"value": "konsole", "title": "Konsole"},
            {"value": "xterm", "title": "XTerm"}
          ]
        },
        {
          "name": "environmentPath",
          "type": "textfield",
          "required": false,
          "title": "Environment Path",
          "description": "Colon-separated Unix PATH",
          "default": "/usr/local/bin:/usr/bin:/bin:~/.local/bin:~/.nix-profile/bin"
        }
      ]
    }
  ],
  "dependencies": {
    "@raycast/api": "^1.102.0"
  },
  "devDependencies": {
    "@types/node": "^20.14.0",
    "@types/react": "^18.3.3",
    "typescript": "^5.8.2",
    "eslint": "^9.22.0",
    "prettier": "^3.5.3"
  },
  "scripts": {
    "dev": "vicinae develop",
    "build": "vicinae build",
    "lint": "eslint .",
    "publish": "vicinae publish"
  }
}
```

**Key Changes**:
1. ✅ Replace `appPicker` with `dropdown` for terminal selection
2. ✅ Update default PATH for Linux
3. ✅ Add "Auto-detect" option
4. ✅ Update scripts (ray → vicinae, if applicable)
5. ✅ Note Linux in description

**Effort**: 30 minutes

---

### 2. `env.ts`

**Changes Required**: ✅ None (Universal)

**Current Implementation**:
```typescript
import { getPreferenceValues } from "@raycast/api";

export function getEnv() {
  const { environmentPath } = getPreferenceValues<Preferences.CmdConnect>();

  const patchedWithoutDuplicates = new Set([
    ...(process.env.PATH?.split(":") ?? []),
    ...(environmentPath?.split(":") ?? []),
  ]);

  const pathString = Array.from(patchedWithoutDuplicates).join(":");

  const env = Object.assign({}, process.env, {
    PATH: pathString,
  });

  return env;
}
```

**Analysis**:
- ✅ Works on both macOS and Linux (Unix PATH handling)
- ✅ No platform-specific code
- ✅ No changes needed

**Effort**: 0 minutes

---

### 3. `sesh.ts`

**Changes Required**: ✅ None (Universal)

**Current Implementation**:
```typescript
import { exec } from "child_process";
import { getEnv } from "./env";

const env = getEnv();

export interface Session {
  Src: string;
  Name: string;
  Path: string;
  Score: number;
  Attached: number;
  Windows: number;
}

export function getSessions() {
  return new Promise<Session[]>((resolve, reject) => {
    exec(`sesh list --json`, { env }, (error, stdout, stderr) => {
      if (error || stderr) {
        console.error("stderr ", stderr);
        console.error("error ", error);
        return reject(`Please upgrade to the latest version of the sesh CLI`);
      }
      const sessions = JSON.parse(stdout);
      return resolve(sessions ?? []);
    });
  });
}

export function connectToSession(session: string): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    exec(`sesh connect --switch "${session}"`, { env }, (error, _, stderr) => {
      if (error || stderr) {
        console.error("error ", error);
        console.error("stderr ", stderr);
        return reject(error?.message ?? stderr);
      }
      return resolve();
    });
  });
}

export function isTmuxRunning(): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    exec(`tmux ls`, { env }, (error, _, stderr) => resolve(!(error || stderr)));
  });
}
```

**Analysis**:
- ✅ Calls `sesh` CLI (cross-platform)
- ✅ Uses standard Node.js `child_process.exec`
- ✅ No platform-specific code
- ✅ No changes needed

**Effort**: 0 minutes

---

### 4. `app.ts` (Terminal Launcher)

**Changes Required**: 🔴 Major Rewrite

**Current Implementation (macOS)**:
```typescript
import { getPreferenceValues } from "@raycast/api";
import { exec } from "child_process";
import { getEnv } from "./env";

const env = getEnv();

export function openApp() {
  const { openWithApp } = getPreferenceValues<Preferences.CmdConnect>();
  if (!openWithApp) {
    return Promise.reject(new Error("No app selected"));
  }
  return new Promise<void>((resolve, reject) => {
    exec(`open -a ${openWithApp.name}`, { env }, (error, _, stderr) => {
      if (error || stderr) return reject(error?.message ?? stderr);
      return resolve();
    });
  });
}
```

**New Implementation (Linux)**:
```typescript
import { getPreferenceValues } from "@raycast/api";
import { exec } from "child_process";
import { getEnv } from "./env";

const env = getEnv();

interface TerminalConfig {
  command: string;
  launchFlags: string[];
  executeFlag: string;
}

// Terminal emulator configurations
const TERMINAL_CONFIGS: Record<string, TerminalConfig> = {
  kitty: {
    command: "kitty",
    launchFlags: ["--detach"],
    executeFlag: "sh -c",
  },
  alacritty: {
    command: "alacritty",
    launchFlags: [],
    executeFlag: "-e",
  },
  foot: {
    command: "foot",
    launchFlags: [],
    executeFlag: "-e",
  },
  wezterm: {
    command: "wezterm",
    launchFlags: ["start"],
    executeFlag: "--",
  },
  "gnome-terminal": {
    command: "gnome-terminal",
    launchFlags: [],
    executeFlag: "--",
  },
  konsole: {
    command: "konsole",
    launchFlags: [],
    executeFlag: "-e",
  },
  xterm: {
    command: "xterm",
    launchFlags: [],
    executeFlag: "-e",
  },
};

// Detection priority order
const DETECTION_ORDER = [
  "kitty",
  "alacritty",
  "foot",
  "wezterm",
  "gnome-terminal",
  "konsole",
  "xterm",
];

/**
 * Detect available terminal emulator
 */
function detectTerminal(): Promise<string | null> {
  return new Promise((resolve) => {
    // Check TERMINAL environment variable first
    const termEnv = process.env.TERMINAL;
    if (termEnv && TERMINAL_CONFIGS[termEnv]) {
      exec(`which ${termEnv}`, (error) => {
        if (!error) return resolve(termEnv);
        // Continue to auto-detection if TERMINAL is invalid
      });
    }

    // Auto-detect by trying each terminal in order
    const checkNext = (index: number) => {
      if (index >= DETECTION_ORDER.length) {
        return resolve(null); // No terminal found
      }

      const terminal = DETECTION_ORDER[index];
      exec(`which ${terminal}`, (error) => {
        if (!error) {
          return resolve(terminal);
        }
        checkNext(index + 1);
      });
    };

    checkNext(0);
  });
}

/**
 * Launch terminal with sesh session
 */
export async function openApp(): Promise<void> {
  const { terminal } = getPreferenceValues<Preferences.CmdConnect>();

  let selectedTerminal = terminal;

  // Auto-detect if needed
  if (!selectedTerminal || selectedTerminal === "auto") {
    selectedTerminal = await detectTerminal();
    if (!selectedTerminal) {
      return Promise.reject(
        new Error(
          "No terminal emulator found. Please install kitty, alacritty, foot, or another supported terminal."
        )
      );
    }
  }

  const config = TERMINAL_CONFIGS[selectedTerminal];
  if (!config) {
    return Promise.reject(
      new Error(`Unsupported terminal: ${selectedTerminal}`)
    );
  }

  // Build command based on terminal type
  const { command, launchFlags, executeFlag } = config;
  
  // Special handling for kitty with sh -c
  let fullCommand: string;
  if (selectedTerminal === "kitty") {
    fullCommand = `${command} ${launchFlags.join(" ")} ${executeFlag} "tmux attach || tmux new"`;
  } else {
    fullCommand = `${command} ${launchFlags.join(" ")} ${executeFlag} tmux attach || ${command} ${launchFlags.join(" ")} ${executeFlag} tmux new`;
  }

  return new Promise<void>((resolve, reject) => {
    exec(fullCommand, { env }, (error, _, stderr) => {
      if (error || stderr) {
        console.error("Terminal launch error:", error, stderr);
        return reject(
          new Error(`Failed to launch ${selectedTerminal}: ${error?.message ?? stderr}`)
        );
      }
      return resolve();
    });
  });
}
```

**Key Changes**:
1. ✅ Replace `open -a` with terminal-specific launch commands
2. ✅ Add terminal detection logic
3. ✅ Support multiple terminal emulators
4. ✅ Handle different command-line syntaxes
5. ✅ Add fallback chain
6. ✅ Update preference type from `openWithApp` to `terminal`

**Alternative Simpler Implementation**:
```typescript
// Simpler version without auto-detection
export function openApp(): Promise<void> {
  const { terminal } = getPreferenceValues<Preferences.CmdConnect>();
  
  if (!terminal || terminal === "auto") {
    return Promise.reject(new Error("Please select a terminal in preferences"));
  }

  // Simple command construction
  const commands: Record<string, string> = {
    kitty: `kitty --detach sh -c "tmux attach || tmux new"`,
    alacritty: `alacritty -e tmux attach || alacritty -e tmux new`,
    foot: `foot -e tmux attach || foot -e tmux new`,
    wezterm: `wezterm start -- tmux attach || wezterm start -- tmux new`,
    "gnome-terminal": `gnome-terminal -- tmux attach || gnome-terminal -- tmux new`,
    konsole: `konsole -e tmux attach || konsole -e tmux new`,
  };

  const cmd = commands[terminal];
  if (!cmd) {
    return Promise.reject(new Error(`Unknown terminal: ${terminal}`));
  }

  return new Promise<void>((resolve, reject) => {
    exec(cmd, { env: getEnv() }, (error, _, stderr) => {
      if (error || stderr) return reject(error?.message ?? stderr);
      return resolve();
    });
  });
}
```

**Effort**: 2-4 hours (depending on complexity chosen)

---

### 5. `cmd-connect.tsx` (UI Component)

**Changes Required**: ⚠️ Minor

**Current Implementation** (excerpt):
```typescript
import { List, Action, ActionPanel, showToast, Toast, Icon, Color, closeMainWindow } from "@raycast/api";
import { useEffect, useState } from "react";
import { getSessions, connectToSession, isTmuxRunning, Session } from "./sesh";
import { openApp } from "./app";

function getIcon(source: string): { source: Icon; tintColor: Color } {
  switch (source) {
    case "tmux":
      return { source: Icon.Terminal, tintColor: Color.Green };
    case "tmuxinator":
      return { source: Icon.Hammer, tintColor: Color.Blue };
    case "config":
      return { source: Icon.Gear, tintColor: Color.Orange };
    default:
      return { source: Icon.Folder, tintColor: Color.Purple };
  }
}

function formatScore(score: number): string | undefined {
  return score === 0 ? undefined : score.toString();
}

export default function ConnectCommand() {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function fetchSessions() {
      try {
        const tmuxRunning = await isTmuxRunning();
        if (!tmuxRunning) {
          await showToast({
            style: Toast.Style.Failure,
            title: "tmux is not running",
            message: "Start tmux before using sesh",
          });
          setIsLoading(false);
          return;
        }

        const sessions = await getSessions();
        setSessions(sessions);
      } catch (error) {
        await showToast({
          style: Toast.Style.Failure,
          title: "Failed to get sessions",
          message: error instanceof Error ? error.message : String(error),
        });
      } finally {
        setIsLoading(false);
      }
    }

    fetchSessions();
  }, []);

  const handleConnect = async (session: Session) => {
    try {
      await connectToSession(session.Name);
      await openApp();
      await closeMainWindow();
    } catch (error) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Failed to connect",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  };

  return (
    <List isLoading={isLoading}>
      {sessions.map((session) => {
        const icon = getIcon(session.Src);
        return (
          <List.Item
            key={session.Name}
            icon={icon}
            title={session.Name}
            subtitle={session.Path}
            accessories={[
              session.Src === "tmux" && session.Windows > 0
                ? { text: `${session.Windows} windows` }
                : {},
              { text: formatScore(session.Score) },
            ]}
            actions={
              <ActionPanel>
                <Action title="Connect" onAction={() => handleConnect(session)} />
              </ActionPanel>
            }
          />
        );
      })}
    </List>
  );
}
```

**Analysis**:
- ✅ Uses Raycast API components (should be compatible with Vicinae)
- ✅ No platform-specific UI code
- ⚠️ May need to test `closeMainWindow()` behavior
- ⚠️ Icon and Color enums should be compatible

**Potential Changes**:
```typescript
// If Raycast API doesn't work, try Vicinae-specific import
import { List, Action, ActionPanel, showToast, Toast, Icon, Color, closeMainWindow } from "@vicinae/api";
// OR
import { List, Action, ActionPanel, showToast, Toast, Icon, Color, closeMainWindow } from "@raycast/api";
```

**Testing Focus**:
1. Verify List component renders correctly
2. Test showToast() notifications
3. Confirm closeMainWindow() closes Vicinae launcher
4. Check icon rendering

**Effort**: 30 minutes (testing + potential tweaks)

---

## Terminal Detection and Launching

### Recommended Implementation Strategy

**Phase 1: Manual Selection (MVP)**
- User selects terminal from dropdown
- Simple command mapping
- No auto-detection
- Fastest to implement

**Phase 2: Auto-Detection (Enhanced)**
- Check `$TERMINAL` environment variable
- Fall back to `which` command checks
- Remember user's choice
- Better UX

**Phase 3: Advanced Features (Future)**
- Detect desktop environment
- Smart defaults (e.g., kitty on Hyprland, gnome-terminal on GNOME)
- Per-session terminal preferences
- Terminal-specific optimizations

### Reference Implementation (From nix-config)

**Existing sesh-launcher.sh** (this repository):
```bash
#!/usr/bin/env bash
# Sesh session launcher using vicinae dmenu
# Opens a terminal with the selected tmux session

set -euo pipefail

# Helper to strip ANSI codes
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# Get sessions with sesh's built-in icons
sessions=$(sesh-list-grouped 2>/dev/null)

if [[ -z $sessions ]]; then
  # No sessions available, show helpful message
  echo "No sessions available" | vicinae dmenu -p "Connect to Session" \
    --navigation-title "Tmux Sessions"
  exit 0
fi

# Show vicinae menu
choice=$(echo "$sessions" | vicinae dmenu -p "Connect to Session" \
  --navigation-title "Tmux Sessions" \
  --section-title "Available Sessions ({count})" || echo "")

# Exit if no choice made (user cancelled)
if [[ -z $choice ]]; then
  exit 0
fi

# Strip ANSI codes and extract session name (sesh format: "icon session-name")
clean_choice=$(strip_ansi <<<"$choice")

# Remove icon (first field) to get session name
session_name=$(echo "$clean_choice" | awk '{for(i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}' | xargs)

# If extraction failed, use the whole thing
if [[ -z $session_name ]]; then
  session_name=$(echo "$clean_choice" | xargs)
fi

# Open terminal and let sesh handle connection
kitty --detach sh -c "sesh connect '$session_name'"
```

**Key Insights**:
- Uses `kitty --detach sh -c` for launching
- Handles session name extraction from formatted output
- Integrates with `vicinae dmenu` for selection
- Simple, reliable approach

**Porting Lesson**: The extension can follow similar patterns!

---

## Testing Strategy

### Test Environment Setup

**Prerequisites**:
1. ✅ Linux system (Ubuntu, Arch, NixOS, etc.)
2. ✅ Vicinae launcher installed
3. ✅ `sesh` CLI installed (`brew install sesh` or build from source)
4. ✅ tmux installed
5. ✅ zoxide installed (for sesh directory tracking)
6. ✅ At least one supported terminal emulator

### Test Cases

#### 1. Basic Functionality
- [ ] Extension loads in Vicinae
- [ ] Session list displays correctly
- [ ] Icons render for different session types (tmux, config, zoxide)
- [ ] Session metadata shows (windows, score, path)
- [ ] Empty state shows helpful message

#### 2. Terminal Launching
- [ ] Kitty launches successfully
- [ ] Alacritty launches successfully
- [ ] Foot launches successfully
- [ ] WezTerm launches successfully
- [ ] GNOME Terminal launches successfully
- [ ] Konsole launches successfully
- [ ] Fallback to available terminal works

#### 3. Session Connection
- [ ] Connects to existing tmux session
- [ ] Creates new session from zoxide result
- [ ] Handles session names with spaces
- [ ] Handles special characters in session names
- [ ] Error handling for invalid sessions

#### 4. Edge Cases
- [ ] No tmux running (shows error)
- [ ] No sessions available (shows empty state)
- [ ] sesh CLI not installed (shows error)
- [ ] Selected terminal not installed (shows error)
- [ ] Auto-detection with no terminals (shows error)

#### 5. Preferences
- [ ] Terminal selection saves correctly
- [ ] PATH override works
- [ ] Auto-detection finds available terminal
- [ ] Manual selection overrides auto-detection

#### 6. Vicinae Integration
- [ ] closeMainWindow() closes launcher
- [ ] Toast notifications appear
- [ ] Keyboard navigation works
- [ ] Action panel actions work
- [ ] Extension respects theme

### Testing Commands

```bash
# Install extension for development
cd extensions/sesh
npm install
vicinae develop  # or appropriate command

# Test sesh CLI independently
sesh list --json
sesh connect test-session

# Test terminal launching manually
kitty --detach sh -c "sesh connect 'main'"
alacritty -e sesh connect 'main'
foot -e sesh connect 'main'

# Check tmux is running
tmux ls

# Verify PATH includes sesh
which sesh
```

---

## Effort Estimation

### Time Breakdown

| Task | Complexity | Estimated Time |
|------|-----------|----------------|
| **package.json** updates | Low | 30 min |
| **env.ts** review | None | 0 min |
| **sesh.ts** review | None | 0 min |
| **app.ts** rewrite | High | 2-4 hours |
| **cmd-connect.tsx** testing | Low | 30 min |
| Terminal detection logic | Medium | 1-2 hours |
| Testing across terminals | Medium | 2-3 hours |
| Documentation | Low | 1 hour |
| Bug fixes & polish | Medium | 2-3 hours |

**Total Estimated Time**: **10-15 hours**

### Phased Approach

**Phase 1: MVP (4-6 hours)**
- Update package.json with dropdown
- Rewrite app.ts with manual terminal selection
- Basic testing with one terminal (kitty)
- Verify core functionality

**Phase 2: Multi-Terminal Support (3-4 hours)**
- Add support for all common terminals
- Test across different terminals
- Improve error handling

**Phase 3: Auto-Detection (2-3 hours)**
- Implement terminal detection
- Add environment variable support
- Smart fallbacks

**Phase 4: Polish (1-2 hours)**
- Documentation
- Error messages
- Edge case handling
- User testing feedback

---

## Implementation Checklist

### Pre-Implementation

- [ ] Install Vicinae on Linux system
- [ ] Install sesh CLI (`brew install sesh` or from source)
- [ ] Install tmux and zoxide
- [ ] Test sesh CLI independently
- [ ] Install at least 2 different terminal emulators for testing
- [ ] Set up development environment

### Phase 1: Core Changes

- [ ] Fork/clone Raycast sesh extension
- [ ] Update package.json:
  - [ ] Change appPicker to dropdown
  - [ ] Add terminal options
  - [ ] Update PATH default
  - [ ] Update scripts (ray → vicinae)
- [ ] Rewrite app.ts:
  - [ ] Remove `open -a` command
  - [ ] Add terminal configurations
  - [ ] Implement basic launch logic
  - [ ] Update preference types
- [ ] Test with manual terminal selection

### Phase 2: Testing

- [ ] Test with kitty
- [ ] Test with alacritty
- [ ] Test with foot
- [ ] Test with gnome-terminal
- [ ] Test with konsole
- [ ] Verify session connection works
- [ ] Verify tmux attachment works
- [ ] Test error handling

### Phase 3: Enhanced Features

- [ ] Implement terminal auto-detection
- [ ] Add $TERMINAL environment variable support
- [ ] Add fallback chain logic
- [ ] Test auto-detection with multiple terminals
- [ ] Test with no terminal installed

### Phase 4: API Compatibility

- [ ] Verify @raycast/api works in Vicinae
- [ ] Test List component rendering
- [ ] Test Toast notifications
- [ ] Test closeMainWindow() behavior
- [ ] Test Icon and Color enums
- [ ] Switch to @vicinae/api if needed

### Phase 5: Polish

- [ ] Add helpful error messages
- [ ] Update README for Linux
- [ ] Document installation steps
- [ ] Add troubleshooting section
- [ ] Test edge cases
- [ ] Get user feedback
- [ ] Fix reported bugs

### Phase 6: Submission

- [ ] Final testing
- [ ] Update CHANGELOG
- [ ] Create screenshots (if needed)
- [ ] Submit to Vicinae extension store (if available)
- [ ] Consider PR to upstream Raycast extension for Linux support

---

## Troubleshooting

### Common Issues

#### "No terminal emulator found"
**Cause**: Auto-detection failed, no supported terminal installed
**Solution**: Install kitty, alacritty, or another supported terminal

#### "Failed to launch terminal"
**Cause**: Terminal command incorrect or binary not in PATH
**Solution**: Verify terminal is in PATH (`which kitty`), check preference setting

#### "tmux is not running"
**Cause**: tmux server not started
**Solution**: Run `tmux` in terminal first, or modify extension to auto-start

#### "sesh command not found"
**Cause**: sesh not installed or not in PATH
**Solution**: Install sesh (`brew install sesh`), add to PATH in preferences

#### Extension won't load in Vicinae
**Cause**: API incompatibility or build error
**Solution**: Check Vicinae logs, try switching to @vicinae/api

#### Sessions don't appear
**Cause**: sesh CLI failing, tmux not running, or PATH issue
**Solution**: Test `sesh list --json` in terminal, verify tmux is running

---

## Reference Links

- **Raycast Sesh Extension**: https://github.com/raycast/extensions/tree/main/extensions/sesh
- **Sesh CLI**: https://github.com/joshmedeski/sesh
- **Vicinae**: https://github.com/vicinaehq/vicinae
- **Vicinae Docs**: https://docs.vicinae.com
- **tmux**: https://github.com/tmux/tmux
- **zoxide**: https://github.com/ajeetdsouza/zoxide

---

## Appendix: Terminal Emulator Reference

### Kitty
```bash
# Launch
kitty [options] [command]

# Execute command
kitty -e command
kitty sh -c "command"

# Detach (background)
kitty --detach -e command

# With tmux
kitty --detach sh -c "sesh connect 'session-name'"
```

### Alacritty
```bash
# Launch
alacritty [options]

# Execute command
alacritty -e command

# With tmux
alacritty -e sesh connect 'session-name'
```

### Foot
```bash
# Launch
foot [options] [command]

# Execute command
foot -e command

# With tmux
foot -e sesh connect 'session-name'
```

### WezTerm
```bash
# Launch
wezterm start [options] -- [command]

# With tmux
wezterm start -- sesh connect 'session-name'
```

### GNOME Terminal
```bash
# Launch
gnome-terminal [options]

# Execute command
gnome-terminal -- command

# With tmux
gnome-terminal -- sesh connect 'session-name'
```

### Konsole
```bash
# Launch
konsole [options]

# Execute command
konsole -e command

# With tmux
konsole -e sesh connect 'session-name'
```

---

## Conclusion

Porting the Raycast sesh extension to Vicinae is **highly feasible** with moderate effort (10-15 hours). The main challenge is replacing macOS-specific terminal launching with Linux terminal detection and launching logic.

**Key Success Factors**:
1. ✅ Most code is platform-agnostic (sesh.ts, env.ts, cmd-connect.tsx)
2. ✅ Vicinae claims Raycast API compatibility
3. ✅ Sesh CLI works on Linux (already installed in this nix-config)
4. ✅ Existing bash implementation provides reference (sesh-launcher.sh)
5. ✅ Clear terminal emulator detection strategy

**Recommended Approach**:
- Start with MVP (manual terminal selection)
- Test thoroughly with one terminal
- Gradually add more terminals
- Implement auto-detection last
- Leverage existing nix-config patterns

This port will bring powerful tmux session management to Linux users via Vicinae! 🚀
