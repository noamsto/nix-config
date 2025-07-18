# Hyprland Quickshell Bar Refactor Plan

This plan addresses the following improvements for the Quickshell bar in Hyprland:

1. **Bar on the Left (Vertical Bar)**
   - **Approach:**
     - Change `PanelWindow` anchoring from top to left, adjust `anchors` accordingly.
     - Set width (implicitWidth) for a vertical bar; fill height.
     - Refactor major `Row` layouts to `Column` to arrange sections vertically (workspaces, active window, system info).
     - Rotate or redesign icons/text as needed for vertical orientation.
   - **Key QML APIs:** `anchors`, `Column`, `Row`, layout properties.

2. **Active Window Display Logic**
   - **Approach:**
     - Reconsider how/where to display active window info (icon/title) in a vertical bar.
     - If the info is too awkward or redundant, remove or simplify (e.g., show only icon, or omit entirely).
     - Preserve logic for tracking the active window (in case other features depend on it).
   - **Key QML APIs:** conditional rendering, layout management.

3. **App Context Menu (System Tray)**
   - **Approach:**
     - Debug why tray icon right-click (`contextMenu()`) is not showing.
     - Ensure MouseArea handlers are correct and no events are blocked.
     - Test on different tray apps; check Quickshell Services API compatibility.
     - Provide fallback or error log if unsupported.
   - **Key QML APIs:** `MouseArea`, system tray model, event propagation.

4. **App Icon Focus/Activation**
   - **Approach:**
     - Confirm that clicking on workspace or tray icons triggers the correct action:
       - Workspaces: `Hyprland.dispatch()` to switch/focus workspace.
       - Tray: `modelData.activate()` for left click, `modelData.contextMenu()` for right click.
     - Fix activation if broken (may require event order or property fix).
   - **Key QML APIs:** Hyprland/Quickshell `dispatch`, item models, MouseArea.

5. **Battery Icon Dynamic with Percentage**
   - **Approach:**
     - Replace static battery rectangle with dynamic component bound to system power info.
     - Use `Quickshell.Services.Power` (or similar) to read battery level and status.
     - Show battery percentage (e.g., as overlay text or beside icon).
     - Change icon/color based on charge/discharge/thresholds.
   - **Key QML APIs:** Power service, property bindings, SVG/image icons, Text.

6. **Wifi Icon Click Opens Network Menu**
   - **Approach:**
     - On click, launch the system's network management GUI (e.g., `nm-connection-editor`).
     - Use QML's `Process` or `DBus` API (usually via Quickshell.Io or Qt.labs.platform) to run the command.
     - Provide visual feedback for launch/failure.
   - **Key QML APIs:** `Process`, MouseArea, error handling.

---

## Implementation Steps
1. Refactor bar layout for vertical orientation.
2. Redesign or remove active window section as needed.
3. Debug and fix system tray app context menu.
4. Ensure app icons (workspaces, tray) activate/focus as expected.
5. Replace static battery icon with dynamic binding including percentage.
6. Make wifi icon open network manager when clicked.
7. Test and validate on Hyprland.

---

## Notes
- Use style/colors consistent with existing theme.
- Prefer QML-native solutions before introducing shell commands.
- Document any workarounds or limitations in code comments and/or this file.

---

**End of Plan**

