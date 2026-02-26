# HyprQuickFrame Fork: Resizable Region Selection — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fork HyprQuickFrame to add resizable region selection with drag handles, integrated into the existing nix-config Hyprland setup.

**Architecture:** Fetch HyprQuickFrame from GitHub, overlay two modified QML files (`RegionSelector.qml` with resize handles, `shell.qml` with Enter/Escape handling and edit-mode default). Package as a local Nix derivation under `packages/hyprquickframe/`.

**Tech Stack:** QML (Qt Quick), Quickshell, Nix, grim, satty, wl-clipboard

---

### Task 1: Create package directory and modified RegionSelector.qml

**Files:**
- Create: `packages/hyprquickframe/default.nix`
- Create: `packages/hyprquickframe/RegionSelector.qml`
- Create: `packages/hyprquickframe/shell-patches.qml` (snippet for shell.qml changes)

**Step 1: Create the package directory**

```bash
mkdir -p packages/hyprquickframe
```

**Step 2: Create the modified RegionSelector.qml**

This is the core change. The file replaces the upstream `RegionSelector.qml` with a three-state version: `idle` → `drawing` → `adjusting`. In `adjusting` state, 8 resize handles appear and the selection can be moved/resized before confirming.

Write `packages/hyprquickframe/RegionSelector.qml`:

```qml
/*
 * Based on HyprQuickFrame by Ronin-CK and HyprQuickshot by JamDon2.
 * Modified to add resizable region selection with drag handles.
 *
 * Original licenses: MIT (see upstream repositories)
 */

import QtQuick

Item {
    id: root

    property real dimOpacity: 0.6
    property real borderRadius: 10
    property real outlineThickness: 2
    property url fragmentShader: Qt.resolvedUrl("dimming.frag.qsb")

    property point startPos
    property real selectionX: 0
    property real selectionY: 0
    property real selectionWidth: 0
    property real selectionHeight: 0

    property real targetX: 0
    property real targetY: 0
    property real targetWidth: 0
    property real targetHeight: 0

    property real mouseX: 0
    property real mouseY: 0

    property bool canceled: false
    property bool animateSelection: true
    property bool globalAnimations: true

    property alias pressed: mouseArea.pressed

    // State machine: idle → drawing → adjusting → confirmed
    property string selectionState: "idle"

    // Handle drag state
    readonly property int handleSize: 12
    readonly property int handleHitArea: 8
    property int activeHandle: -1
    property bool isDraggingMove: false
    property point dragStartPos
    property real dragStartSelX: 0
    property real dragStartSelY: 0
    property real dragStartSelW: 0
    property real dragStartSelH: 0

    signal regionSelected(real x, real y, real width, real height)

    function clearSelection() {
        root.animateSelection = false;
        root.selectionState = "idle";
        root.activeHandle = -1;
        root.isDraggingMove = false;
        root.canceled = false;
        root.targetX = 0;
        root.targetY = 0;
        root.targetWidth = 0;
        root.targetHeight = 0;
        root.selectionX = 0;
        root.selectionY = 0;
        root.selectionWidth = 0;
        root.selectionHeight = 0;
        root.animateSelection = true;
        guides.requestPaint();
    }

    function confirmSelection() {
        if (selectionState === "adjusting" && selectionWidth > 5 && selectionHeight > 5) {
            regionSelected(
                Math.round(selectionX), Math.round(selectionY),
                Math.round(selectionWidth), Math.round(selectionHeight)
            );
        }
    }

    function hitTestHandle(mx, my) {
        var hs = handleSize + handleHitArea * 2;
        var positions = handlePositions();
        for (var i = 0; i < positions.length; i++) {
            var hx = positions[i].x - hs / 2;
            var hy = positions[i].y - hs / 2;
            if (mx >= hx && mx <= hx + hs && my >= hy && my <= hy + hs) {
                return i;
            }
        }
        return -1;
    }

    function handlePositions() {
        return [
            {x: selectionX, y: selectionY},                                                     // 0: TL
            {x: selectionX + selectionWidth / 2, y: selectionY},                                 // 1: TC
            {x: selectionX + selectionWidth, y: selectionY},                                     // 2: TR
            {x: selectionX, y: selectionY + selectionHeight / 2},                                // 3: ML
            {x: selectionX + selectionWidth, y: selectionY + selectionHeight / 2},               // 4: MR
            {x: selectionX, y: selectionY + selectionHeight},                                    // 5: BL
            {x: selectionX + selectionWidth / 2, y: selectionY + selectionHeight},               // 6: BC
            {x: selectionX + selectionWidth, y: selectionY + selectionHeight}                    // 7: BR
        ];
    }

    function isInsideSelection(mx, my) {
        return mx >= selectionX && mx <= selectionX + selectionWidth &&
               my >= selectionY && my <= selectionY + selectionHeight;
    }

    function cursorForHandle(handle) {
        switch (handle) {
            case 0: case 7: return Qt.SizeFDiagCursor;
            case 2: case 5: return Qt.SizeBDiagCursor;
            case 1: case 6: return Qt.SizeVerCursor;
            case 3: case 4: return Qt.SizeHorCursor;
            default: return Qt.CrossCursor;
        }
    }

    onSelectionXChanged: guides.requestPaint()
    onSelectionYChanged: guides.requestPaint()
    onSelectionWidthChanged: guides.requestPaint()
    onSelectionHeightChanged: guides.requestPaint()
    onMouseXChanged: guides.requestPaint()
    onMouseYChanged: guides.requestPaint()

    // Dimming shader overlay
    ShaderEffect {
        property vector4d selectionRect: Qt.vector4d(
            root.selectionX, root.selectionY,
            root.selectionWidth, root.selectionHeight
        )
        property real dimOpacity: root.dimOpacity
        property vector2d screenSize: Qt.vector2d(root.width, root.height)
        property real borderRadius: root.borderRadius
        property real outlineThickness: root.outlineThickness
        anchors.fill: parent
        z: 0
        fragmentShader: root.fragmentShader
    }

    // Alignment guides
    Canvas {
        id: guides
        anchors.fill: parent
        z: 2
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            ctx.strokeStyle = "rgba(255, 255, 255, 0.5)";
            ctx.lineWidth = 1;
            ctx.setLineDash([5, 5]);

            if (root.selectionState === "idle") {
                ctx.moveTo(root.mouseX, 0);
                ctx.lineTo(root.mouseX, root.height);
                ctx.moveTo(0, root.mouseY);
                ctx.lineTo(root.width, root.mouseY);
            } else {
                ctx.moveTo(root.selectionX, 0);
                ctx.lineTo(root.selectionX, root.height);
                ctx.moveTo(root.selectionX + root.selectionWidth, 0);
                ctx.lineTo(root.selectionX + root.selectionWidth, root.height);
                ctx.moveTo(0, root.selectionY);
                ctx.lineTo(root.width, root.selectionY);
                ctx.moveTo(0, root.selectionY + root.selectionHeight);
                ctx.lineTo(root.width, root.selectionY + root.selectionHeight);
            }
            ctx.stroke();
        }
    }

    // Main mouse interaction
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        z: 3
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        cursorShape: {
            if (root.selectionState === "adjusting") {
                var h = root.hitTestHandle(mouseX, mouseY);
                if (h >= 0) return root.cursorForHandle(h);
                if (root.isInsideSelection(mouseX, mouseY)) return Qt.SizeAllCursor;
            }
            return Qt.CrossCursor;
        }

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.canceled = true;
                root.clearSelection();
                return;
            }
            root.canceled = false;

            if (root.selectionState === "idle") {
                root.selectionState = "drawing";
                root.startPos = Qt.point(mouse.x, mouse.y);
                root.targetX = mouse.x;
                root.targetY = mouse.y;
                root.targetWidth = 0;
                root.targetHeight = 0;
            } else if (root.selectionState === "adjusting") {
                var h = root.hitTestHandle(mouse.x, mouse.y);
                if (h >= 0) {
                    root.activeHandle = h;
                    root.dragStartPos = Qt.point(mouse.x, mouse.y);
                    root.dragStartSelX = root.selectionX;
                    root.dragStartSelY = root.selectionY;
                    root.dragStartSelW = root.selectionWidth;
                    root.dragStartSelH = root.selectionHeight;
                } else if (root.isInsideSelection(mouse.x, mouse.y)) {
                    root.isDraggingMove = true;
                    root.dragStartPos = Qt.point(mouse.x, mouse.y);
                    root.dragStartSelX = root.selectionX;
                    root.dragStartSelY = root.selectionY;
                } else {
                    // Click outside: restart drawing
                    root.clearSelection();
                    root.selectionState = "drawing";
                    root.startPos = Qt.point(mouse.x, mouse.y);
                    root.targetX = mouse.x;
                    root.targetY = mouse.y;
                    root.targetWidth = 0;
                    root.targetHeight = 0;
                }
            }
        }

        onPositionChanged: (mouse) => {
            root.mouseX = mouse.x;
            root.mouseY = mouse.y;

            if (root.selectionState === "drawing" && !root.canceled && (mouse.buttons & Qt.LeftButton)) {
                root.targetX = Math.min(root.startPos.x, mouse.x);
                root.targetY = Math.min(root.startPos.y, mouse.y);
                root.targetWidth = Math.abs(mouse.x - root.startPos.x);
                root.targetHeight = Math.abs(mouse.y - root.startPos.y);
            } else if (root.selectionState === "adjusting" && (mouse.buttons & Qt.LeftButton)) {
                var dx = mouse.x - root.dragStartPos.x;
                var dy = mouse.y - root.dragStartPos.y;

                if (root.activeHandle >= 0) {
                    var newX = root.dragStartSelX;
                    var newY = root.dragStartSelY;
                    var newW = root.dragStartSelW;
                    var newH = root.dragStartSelH;
                    var h = root.activeHandle;

                    // Left handles: 0 (TL), 3 (ML), 5 (BL)
                    if (h === 0 || h === 3 || h === 5) {
                        newX += dx;
                        newW -= dx;
                    }
                    // Right handles: 2 (TR), 4 (MR), 7 (BR)
                    if (h === 2 || h === 4 || h === 7) {
                        newW += dx;
                    }
                    // Top handles: 0 (TL), 1 (TC), 2 (TR)
                    if (h === 0 || h === 1 || h === 2) {
                        newY += dy;
                        newH -= dy;
                    }
                    // Bottom handles: 5 (BL), 6 (BC), 7 (BR)
                    if (h === 5 || h === 6 || h === 7) {
                        newH += dy;
                    }

                    // Enforce minimum size
                    if (newW >= 10) {
                        root.selectionX = newX;
                        root.selectionWidth = newW;
                    }
                    if (newH >= 10) {
                        root.selectionY = newY;
                        root.selectionHeight = newH;
                    }
                } else if (root.isDraggingMove) {
                    root.selectionX = root.dragStartSelX + dx;
                    root.selectionY = root.dragStartSelY + dy;
                }
            }
        }

        onReleased: (mouse) => {
            if (mouse.button === Qt.RightButton || root.canceled) {
                if (mouse.buttons === 0) root.canceled = false;
                return;
            }

            if (root.selectionState === "drawing") {
                if (root.targetWidth < 5 && root.targetHeight < 5) {
                    // Tiny selection = full screen
                    root.regionSelected(0, 0, root.width, root.height);
                } else {
                    // Transition to adjusting state
                    root.selectionX = root.targetX;
                    root.selectionY = root.targetY;
                    root.selectionWidth = root.targetWidth;
                    root.selectionHeight = root.targetHeight;
                    root.selectionState = "adjusting";
                }
            } else if (root.selectionState === "adjusting") {
                root.activeHandle = -1;
                root.isDraggingMove = false;
            }
        }

        onDoubleClicked: (mouse) => {
            if (root.selectionState === "adjusting" && root.isInsideSelection(mouse.x, mouse.y)) {
                root.confirmSelection();
            }
        }

        // Update timer for drawing phase animation
        Timer {
            id: updateTimer
            interval: 16
            repeat: true
            running: root.selectionState === "drawing" && !root.canceled
            onTriggered: {
                root.selectionX = root.targetX;
                root.selectionY = root.targetY;
                root.selectionWidth = root.targetWidth;
                root.selectionHeight = root.targetHeight;
            }
        }
    }

    // Resize handles — visible only in adjusting state
    Repeater {
        model: root.selectionState === "adjusting" ? 8 : 0
        Rectangle {
            required property int index
            property var pos: root.handlePositions()[index]
            x: pos.x - root.handleSize / 2
            y: pos.y - root.handleSize / 2
            width: root.handleSize
            height: root.handleSize
            radius: root.handleSize / 2
            color: "white"
            border.color: Qt.rgba(0, 0, 0, 0.5)
            border.width: 1
            z: 5
        }
    }

    // Dimension label
    Rectangle {
        id: dimLabel
        visible: root.selectionState !== "idle" && !root.canceled && root.selectionWidth > 20
        z: 4
        x: root.selectionX + root.selectionWidth / 2 - width / 2
        y: root.selectionY < 40 ? root.selectionY + 10 : root.selectionY - 35
        width: labelText.implicitWidth + 16
        height: labelText.implicitHeight + 8
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.7)

        Text {
            id: labelText
            anchors.centerIn: parent
            text: {
                var dims = `${Math.round(root.selectionWidth)} × ${Math.round(root.selectionHeight)}`;
                if (root.selectionState === "adjusting")
                    return dims + "  ↵ Enter";
                return dims;
            }
            color: "white"
            font.pixelSize: 12
            font.family: "monospace"
        }
    }

    // Spring animations for drawing phase
    Behavior on selectionX {
        enabled: root.animateSelection && root.globalAnimations && root.selectionState === "drawing"
        SpringAnimation { spring: 4; damping: 0.4 }
    }
    Behavior on selectionY {
        enabled: root.animateSelection && root.globalAnimations && root.selectionState === "drawing"
        SpringAnimation { spring: 4; damping: 0.4 }
    }
    Behavior on selectionWidth {
        enabled: root.animateSelection && root.globalAnimations && root.selectionState === "drawing"
        SpringAnimation { spring: 4; damping: 0.4 }
    }
    Behavior on selectionHeight {
        enabled: root.animateSelection && root.globalAnimations && root.selectionState === "drawing"
        SpringAnimation { spring: 4; damping: 0.4 }
    }
}
```

**Step 3: Commit**

```bash
git add packages/hyprquickframe/RegionSelector.qml
git commit -m "feat: add hyprquickframe RegionSelector with resize handles"
```

---

### Task 2: Create the Nix package definition

**Files:**
- Create: `packages/hyprquickframe/default.nix`
- Modify: `packages/default.nix`

**Step 1: Create the package derivation**

Write `packages/hyprquickframe/default.nix`. This fetches the upstream source from GitHub, then replaces `RegionSelector.qml` with our modified version and patches `shell.qml` for Enter/Escape handling and edit-mode default.

```nix
{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  quickshell,
  grim,
  imagemagick,
  wl-clipboard,
  satty,
  libnotify,
  qt6,
}:
let
  runtimeDeps = [
    quickshell
    grim
    imagemagick
    wl-clipboard
    satty
    libnotify
  ];
in
stdenv.mkDerivation {
  pname = "hyprquickframe";
  version = "0.1.0-fork";

  src = fetchFromGitHub {
    owner = "Ronin-CK";
    repo = "HyprQuickFrame";
    # TODO: Pin to latest commit at time of implementation
    rev = "main";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [
    makeWrapper
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qt5compat
  ];

  dontBuild = true;

  postPatch = ''
    # Replace RegionSelector with our resizable version
    cp ${./RegionSelector.qml} RegionSelector.qml

    # Patch shell.qml: Enter confirms region, Escape clears adjusting state, edit mode default
    substituteInPlace shell.qml \
      --replace-fail 'property bool editActive: false' 'property bool editActive: true' \
      --replace-fail \
        'sequence: "Escape"
        onActivated: {
            cleanup();
            Qt.quit();
        }' \
        'sequence: "Escape"
        onActivated: {
            if (root.mode === "region" && regionSelector.selectionState === "adjusting") {
                regionSelector.clearSelection();
            } else {
                cleanup();
                Qt.quit();
            }
        }' \
      --replace-quiet \
        'sequence: "s"' \
        'sequence: "s"
    }
    Shortcut {
        sequence: "Return"
        onActivated: {
            if (root.mode === "region" && regionSelector.selectionState === "adjusting") {
                regionSelector.confirmSelection();
            }
        }
    }
    Shortcut {
        // this is a placeholder to close the previous block
        sequence: "PLACEHOLDER_NEVER_MATCH"'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/hyprquickframe
    cp -r . $out/share/hyprquickframe/

    mkdir -p $out/bin
    makeWrapper ${quickshell}/bin/quickshell $out/bin/hyprquickframe \
      --prefix PATH : ${lib.makeBinPath runtimeDeps} \
      --add-flags "-c $out/share/hyprquickframe -n"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Screenshot utility for Hyprland with resizable region selection";
    homepage = "https://github.com/Ronin-CK/HyprQuickFrame";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "hyprquickframe";
  };
}
```

> **Important note for implementer:** The `substituteInPlace` approach for shell.qml patching above is fragile — whitespace and exact string matching matters. If it fails, the fallback approach is:
> 1. Copy the upstream `shell.qml` to `packages/hyprquickframe/shell.qml`
> 2. Make the 3 edits manually (editActive default, Escape handler, Enter shortcut)
> 3. Add `cp ${./shell.qml} shell.qml` to `postPatch`
>
> This fallback is the **recommended approach** since shell.qml is complex and substituteInPlace is brittle for multi-line replacements. See Task 2b below.

**Step 2: Register in packages/default.nix**

In `packages/default.nix`, add to the `packages` attrset:

```nix
hyprquickframe = pkgs.callPackage ./hyprquickframe {};
```

**Step 3: Commit**

```bash
git add packages/hyprquickframe/default.nix packages/default.nix
git commit -m "feat: add hyprquickframe nix package definition"
```

---

### Task 2b: Copy and modify shell.qml (recommended fallback)

**If `substituteInPlace` in Task 2 is too fragile for shell.qml:**

**Files:**
- Create: `packages/hyprquickframe/shell.qml`

**Step 1: Fetch and save the upstream shell.qml**

```bash
curl -sL https://raw.githubusercontent.com/Ronin-CK/HyprQuickFrame/main/shell.qml > packages/hyprquickframe/shell.qml
```

**Step 2: Apply the 3 modifications to `packages/hyprquickframe/shell.qml`**

**Change 1** — Default edit mode to on (line ~13):
```
// BEFORE:
property bool editActive: false

// AFTER:
property bool editActive: true
```

**Change 2** — Escape shortcut handles adjusting state:
```qml
// BEFORE:
    Shortcut {
        sequence: "Escape"
        onActivated: {
            cleanup();
            Qt.quit();
        }
    }

// AFTER:
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.mode === "region" && regionSelector.selectionState === "adjusting") {
                regionSelector.clearSelection();
            } else {
                cleanup();
                Qt.quit();
            }
        }
    }
```

**Change 3** — Add Enter shortcut (after the Escape shortcut):
```qml
    Shortcut {
        sequence: "Return"
        onActivated: {
            if (root.mode === "region" && regionSelector.selectionState === "adjusting") {
                regionSelector.confirmSelection();
            }
        }
    }
```

**Step 3: Update default.nix postPatch**

Replace the `substituteInPlace` block with:

```nix
postPatch = ''
  cp ${./RegionSelector.qml} RegionSelector.qml
  cp ${./shell.qml} shell.qml
'';
```

**Step 4: Commit**

```bash
git add packages/hyprquickframe/shell.qml packages/hyprquickframe/default.nix
git commit -m "feat: add modified shell.qml with enter/escape handling"
```

---

### Task 3: Build and fix the package hash

**Step 1: Stage all new files**

```bash
git add packages/hyprquickframe/
```

**Step 2: Attempt to build the package**

```bash
nix build .#hyprquickframe 2>&1
```

This will fail with a hash mismatch. Copy the correct hash from the error output.

**Step 3: Update the hash in default.nix**

Replace `lib.fakeHash` with the correct SHA256 hash from the build output.

**Step 4: Build again to verify**

```bash
nix build .#hyprquickframe
```

Expected: Build succeeds. Check the output:

```bash
ls -la result/bin/hyprquickframe
result/bin/hyprquickframe --help 2>&1 || true
```

**Step 5: Commit**

```bash
git add packages/hyprquickframe/default.nix
git commit -m "fix: update hyprquickframe source hash"
```

---

### Task 4: Integrate into Hyprland configuration

**Files:**
- Modify: `home/desktop/hyprland/default.nix` (~line 57-66, packages section)
- Modify: `home/desktop/hyprland/settings/bindings.nix` (~line 131)

**Step 1: Add hyprquickframe to packages**

In `home/desktop/hyprland/default.nix`, add the package to `home.packages`.
After the existing screenshot tools block (~line 66), add:

```nix
# Resizable screenshot tool (fork of HyprQuickFrame)
(pkgs.callPackage ../../../../packages/hyprquickframe {})
```

Also add `imagemagick` if not already present (HyprQuickFrame depends on it):

```nix
imagemagick  # Required by hyprquickframe for image processing
```

**Step 2: Update the screenshot keybinding**

In `home/desktop/hyprland/settings/bindings.nix`, change line 131:

```nix
# BEFORE:
", Print, exec, grimblast-satty"

# AFTER:
", Print, exec, hyprquickframe"
```

Keep the `screenshot-menu` binding as-is (ALT+SHIFT+S) for the vicinae menu fallback.

**Step 3: Commit**

```bash
git add home/desktop/hyprland/default.nix home/desktop/hyprland/settings/bindings.nix
git commit -m "feat: integrate hyprquickframe into hyprland config"
```

---

### Task 5: Build, deploy, and test

**Step 1: Stage everything and validate flake**

```bash
git add -A
nix flake check 2>&1 | head -20
```

**Step 2: Build Home Manager configuration**

```bash
nh home build .
```

Expected: Build succeeds with no errors.

**Step 3: Deploy**

```bash
nh home switch .
```

**Step 4: Manual testing**

Test the following scenarios:

1. **Press Print Screen** — HyprQuickFrame overlay should appear with frozen screen
2. **Draw a region** — Drag to create selection rectangle
3. **Release mouse** — Selection should stay visible with 8 white circular handles at corners/edges
4. **Resize via handle** — Drag any handle to resize the selection. Cursor should change to resize arrows.
5. **Move selection** — Drag inside the selection to reposition it. Cursor should be move icon.
6. **Confirm with Enter** — Press Enter to capture. Satty should open with the cropped screenshot.
7. **Confirm with double-click** — Double-click inside selection to capture.
8. **Cancel with Escape** — In adjusting state, Escape clears selection (returns to crosshair). Second Escape quits.
9. **Cancel with right-click** — Right-click clears selection.
10. **Click outside** — Clicking outside the selection starts a new draw.
11. **Window mode** — Press `w` key to switch to window mode (unchanged from upstream).
12. **Full screen** — Press `s` key for full screen capture (unchanged).

**Step 5: Fix any issues and commit**

If issues are found during testing, fix and commit:

```bash
git add -A
git commit -m "fix: address issues found during testing"
```

---

### Task 6: Clean up old screenshot tools (optional)

**Only do this after Task 5 confirms everything works.**

The following are now redundant but can be kept as fallbacks:
- `grimblast-satty` script (replaced by hyprquickframe for Print key)
- `grimblast` package (still useful for screenshot-menu)
- `slurp` package (still useful for screenshot-menu and other tools)
- `hyprpicker` package (no longer needed for freeze — hyprquickframe uses ScreencopyView)

**Recommended:** Keep all existing tools for now. They serve as fallbacks via `screenshot-menu` (ALT+SHIFT+S). Prune later if hyprquickframe proves reliable.
