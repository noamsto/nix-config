{
  lib,
  pkgs,
  ...
}:
# Karabiner-Elements (installed as a brew cask in the host module) provides the
# one thing nix-darwin's keyboard remap can't: tap-vs-hold on Caps Lock.
#   Caps tapped → Escape   (vim)
#   Caps held   → Hyper (⌘⌥)  — the WM-exclusive modifier AeroSpace binds to.
# Hyper includes Cmd so the combo never leaks into the terminal/tmux, and is only
# Cmd+Alt (not Ctrl/Shift) so BOTH Ctrl and Shift stay free as differentiators —
# letting AeroSpace mirror Hyprland exactly: Hyper+Ctrl = move window,
# Hyper+Shift = cycle/move-to workspace (see aerospace.nix).
#
# NOTE: the whole karabiner.json is managed declaratively here. After the first
# switch you must launch Karabiner-Elements once and grant Input Monitoring /
# Accessibility permissions; it then picks up this profile. If Karabiner ever
# fights the read-only symlink, switch this to an activation-time copy.
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  home.file.".config/karabiner/karabiner.json".text = builtins.toJSON {
    global = {
      check_for_updates_on_startup = false;
      show_in_menu_bar = false;
    };
    profiles = [
      {
        name = "Default";
        selected = true;
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        complex_modifications.rules = [
          {
            description = "Caps Lock → Escape (tap) / Hyper ⌘⌥ (hold)";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "caps_lock";
                  modifiers.optional = ["any"];
                };
                to = [
                  {
                    key_code = "left_command";
                    modifiers = ["left_option"];
                  }
                ];
                to_if_alone = [{key_code = "escape";}];
              }
            ];
          }
          {
            # Language toggle, mirroring the ThinkPad's `grp:win_space_toggle`
            # (Super+Space). Here Hyper(=⌘⌥)+Space → Ctrl+Space, macOS's built-in
            # "select previous input source" (toggles between two sources).
            # Requires a 2nd input source (e.g. Hebrew) added in System Settings.
            description = "Hyper + Space → switch input source (Ctrl+Space)";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "spacebar";
                  modifiers.mandatory = ["left_command" "left_option"];
                };
                to = [
                  {
                    key_code = "spacebar";
                    modifiers = ["left_control"];
                  }
                ];
              }
            ];
          }
          {
            # MacBook's built-in keyboard is the only one with fn (globe) in the
            # corner; the external keyboard and both ThinkPads (BIOS Fn/Ctrl swap)
            # put Ctrl there. Swap fn<->Ctrl on the built-in keyboard ONLY;
            # `is_built_in_keyboard` keeps external keyboards (already
            # Ctrl-in-corner) from having their Ctrl turned into fn.
            description = "Built-in keyboard: swap Fn (corner) and Left Control";
            manipulators = [
              {
                type = "basic";
                from = {
                  key_code = "fn";
                  modifiers.optional = ["any"];
                };
                to = [{key_code = "left_control";}];
                conditions = [
                  {
                    type = "device_if";
                    identifiers = [{is_built_in_keyboard = true;}];
                  }
                ];
              }
              {
                type = "basic";
                from = {
                  key_code = "left_control";
                  modifiers.optional = ["any"];
                };
                to = [{key_code = "fn";}];
                conditions = [
                  {
                    type = "device_if";
                    identifiers = [{is_built_in_keyboard = true;}];
                  }
                ];
              }
            ];
          }
        ];
      }
    ];
  };
}
