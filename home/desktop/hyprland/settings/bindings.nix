{
  lib,
  pkgs,
  osConfig,
  ...
}: let
  terminal = "kitty";
  fileManager = "${lib.getExe pkgs.thunar}";
  primaryProfile =
    if osConfig.profile == "work"
    then "work"
    else "personal";
  browser = "${lib.getExe pkgs.firefox} -P ${primaryProfile}";
  youtube-music = "${lib.getExe pkgs.pear-desktop}";

  # Run a program only if it's not already running
  runOnce = program: let
    progName = baseNameOf program;
  in "pgrep -f ${progName} || ${program}";
in {
  wayland.windowManager.hyprland.extraLuaFiles."bindings".content = ''
    local mainMod = "SUPER"

    -- === APPLICATION LAUNCHERS ===
    hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("${terminal} --single-instance --instance-group=hypr"))
    hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("${fileManager}"))
    hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("${browser}"))
    hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("sesh-launcher"))
    hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("obsidian"))
    hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd("${youtube-music}"))
    hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("pavucontrol"))

    -- === WINDOW MANAGEMENT ===
    hl.bind(mainMod .. " + Q", hl.dsp.window.close())
    hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 1 }))       -- maximize (with gaps)
    hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = 0 })) -- true fullscreen
    hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
    hl.bind(mainMod .. " + R", hl.dsp.layout("togglesplit"))
    -- Smart toggle floating: tiled→float+resize+center, floating→just unfloat
    hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("toggle-floating"))
    hl.bind(mainMod .. " + SHIFT + T", hl.dsp.window.center())

    -- === CLIPBOARD / VICINAE ===
    hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("vicinae vicinae://launch/clipboard/history"))
    hl.bind("ALT + SPACE", hl.dsp.exec_cmd("vicinae vicinae://toggle"))

    -- === SYSTEM ===
    hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("aegis-lock"))
    hl.bind(mainMod .. " + ALT + T", hl.dsp.exec_cmd("theme-toggle toggle"))
    hl.bind(mainMod .. " + ALT + K", hl.dsp.exec_cmd("system-awake toggle-last"))
    -- Session/logout menu (Noctalia)
    hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("noctalia-ipc sessionMenu toggle"))

    -- === FOCUS MOVEMENT (SUPER+hjkl) ===
    hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
    hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
    hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
    hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

    -- === WORKSPACE SWITCHING (SUPER+[1-9]) ===
    hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
    hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
    hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
    hl.bind(mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
    hl.bind(mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
    hl.bind(mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
    hl.bind(mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
    hl.bind(mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
    hl.bind(mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))

    -- Quick workspace shortcuts
    hl.bind(mainMod .. " + D", hl.dsp.focus({ workspace = 1 })) -- Development (kitty)
    hl.bind(mainMod .. " + W", hl.dsp.focus({ workspace = 2 })) -- Web (browsers)

    -- Cycle through windows (Tab)
    hl.bind(mainMod .. " + Tab", hl.dsp.window.cycle_next())
    hl.bind(mainMod .. " + Tab", hl.dsp.window.bring_to_top())
    hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
    hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.window.bring_to_top())

    -- Scroll through non-empty workspaces on current monitor
    hl.bind(mainMod .. " + SHIFT + L", hl.dsp.focus({ workspace = "m+1" }))
    hl.bind(mainMod .. " + SHIFT + H", hl.dsp.focus({ workspace = "m-1" }))
    hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }))
    hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "m-1" }))

    -- Special workspace (scratchpad)
    hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
    hl.bind(mainMod .. " + M", hl.dsp.window.move({ workspace = "special:magic" }))

    -- === MOVE WINDOW TO WORKSPACE (SUPER+SHIFT+[1-9]) ===
    hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
    hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
    hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
    hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
    hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
    hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
    hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
    hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
    hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
    hl.bind(mainMod .. " + SHIFT + D", hl.dsp.window.move({ workspace = 1 }))
    hl.bind(mainMod .. " + SHIFT + W", hl.dsp.window.move({ workspace = 2 }))

    -- === WINDOW POSITION (SUPER+CTRL+hjkl) ===
    hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.move({ direction = "left" }))
    hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.move({ direction = "right" }))
    hl.bind(mainMod .. " + CTRL + K", hl.dsp.window.move({ direction = "up" }))
    hl.bind(mainMod .. " + CTRL + J", hl.dsp.window.move({ direction = "down" }))

    -- Move window between monitors
    hl.bind(mainMod .. " + CTRL + SHIFT + H", hl.dsp.window.move({ monitor = "l" }))
    hl.bind(mainMod .. " + CTRL + SHIFT + L", hl.dsp.window.move({ monitor = "r" }))

    -- === QUICK RESIZE ===
    hl.bind(mainMod .. " + equal", hl.dsp.exec_cmd("window-resize grow"))
    hl.bind(mainMod .. " + minus", hl.dsp.exec_cmd("window-resize shrink"))

    -- === SCREENSHOTS ===
    -- Print is remapped from SUPER+SHIFT+S via xremap
    hl.bind("Print", hl.dsp.exec_cmd("grimblast-satty"))
    hl.bind("ALT + SHIFT + S", hl.dsp.exec_cmd("screenshot-menu"))

    -- === ACCESSIBILITY ===
    hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("normcap"))
    hl.bind(mainMod .. " + CTRL + 0", hl.dsp.exec_cmd("zoom-step reset"))
    hl.bind(mainMod .. " + CTRL + mouse_down", hl.dsp.exec_cmd("zoom-step in"))
    hl.bind(mainMod .. " + CTRL + mouse_up", hl.dsp.exec_cmd("zoom-step out"))
    hl.bind(mainMod .. " + SHIFT + A", hl.dsp.exec_cmd("stt-stream-toggle"))
    hl.bind(mainMod .. " + ALT + A", hl.dsp.exec_cmd("hyprvoice toggle"))

    -- Media: launch YTM if not running
    hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("${runOnce youtube-music}"))

    -- === MOUSE BINDS ===
    hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
    hl.bind(mainMod .. " + ALT + mouse:272", hl.dsp.window.resize(), { mouse = true })

    -- === MEDIA / VOLUME (locked — work on lockscreen) ===
    hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
    hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
    hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("volume-control --toggle"), { locked = true })
    hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("volume-control --toggle-mic"), { locked = true })

    -- === VOLUME / BRIGHTNESS (locked + repeating) ===
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("volume-control --inc"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("volume-control --dec"), { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightness-control --inc"), { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightness-control --dec"), { locked = true, repeating = true })

    -- === WINDOW RESIZE (arrow keys, repeating) ===
    hl.bind(mainMod .. " + left", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
    hl.bind(mainMod .. " + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
    hl.bind(mainMod .. " + up", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
    hl.bind(mainMod .. " + down", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })
  '';
}
