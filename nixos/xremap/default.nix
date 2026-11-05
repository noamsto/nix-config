{inputs, ...}: {config, ...}: let
  inherit (config.machine) isPC;
in {
  imports = [
    inputs.xremap.nixosModules.default
  ];
  services.xremap = {
    # View keys scan codes here: https://github.com/emberian/evdev/blob/1d020f11b283b0648427a2844b6b980f1a268221/src/scancodes.rs#L26-L572
    enable = isPC && config.desktop.isEnabled;
    userName = config.username;
    watch = true;
    config = {
      modmap = [
        {
          # Caps tapped → Esc (vim); Caps held → Super, the Hyprland $mainMod.
          # Mirrors the Mac's Karabiner tap/hold so the same finger drives the
          # WM on both machines (see home/darwin/karabiner.nix). xremap owns
          # Caps at the evdev layer, so `caps:escape` is dropped from kb_options.
          #
          # hold_threshold_millis = 0 starts Caps in xremap's HoldPreferred
          # state, so any chorded key resolves to Super instantly (like
          # Karabiner). A non-zero threshold would make Caps+key within that
          # window emit Esc+key instead — a lag on every WM combo. A standalone
          # tap released within alone_timeout_millis still emits Esc.
          name = "caps_escape_super";
          remap = {
            CAPSLOCK = {
              held = "KEY_LEFTMETA";
              alone = "ESC";
              alone_timeout_millis = 1000;
              hold_threshold_millis = 0;
            };
          };
        }
        {
          # Tap Right Alt to toggle streaming dictation; held it still acts as
          # Alt, so Alt+Tab and Alt+Space are untouched.
          #
          # held is LEFTALT, not RIGHTALT. Mapping the key to itself made xremap
          # pass it straight through: holding worked (Alt+Space still opened
          # vicinae) but a tap never emitted F13, because there was nothing to
          # defer. Nothing here distinguishes the two Alts — Hyprland's modmask
          # does not separate them — so this costs nothing.
          #
          # Otherwise structurally identical to caps_escape_super above, the
          # tap/hold rule known to work on this machine.
          #
          # F13 is a keycode nothing else claims; Hyprland binds it directly.
          name = "ralt_tap_dictation";
          remap = {
            RIGHTALT = {
              held = "KEY_LEFTALT";
              alone = "KEY_F13";
              alone_timeout_millis = 1000;
              hold_threshold_millis = 0;
            };
          };
        }
      ];
      keymap = [
        {
          # Fix Logitech MX keys mini print screen key
          name = "Print screen remap";
          remap = {
            "SUPER-SHIFT-S" = "KEY_PRINT";
          };
        }
        {
          name = "Media keys remap";
          remap = {
            "SUPER-SHIFT-N" = "KEY_NEXTSONG";
            "SUPER-SHIFT-P" = "KEY_PREVIOUSSONG";
          };
        }
      ];
    };
  };
}
