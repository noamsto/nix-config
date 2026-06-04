{
  inputs,
  config,
  ...
}: let
  inherit (config.machine) isPC;
in {
  imports = [
    inputs.xremap.nixosModules.default
  ];
  services.xremap = {
    # View keys scan codes here: https://github.com/emberian/evdev/blob/1d020f11b283b0648427a2844b6b980f1a268221/src/scancodes.rs#L26-L572
    enable = isPC;
    userName = config.username;
    watch = true;
    config = {
      modmap = [
        {
          # Caps tapped → Esc (vim); Caps held → Super, the Hyprland $mainMod.
          # Mirrors the Mac's Karabiner tap/hold so the same finger drives the
          # WM on both machines (see home/darwin/karabiner.nix). xremap owns
          # Caps at the evdev layer, so `caps:escape` is dropped from kb_options.
          name = "caps_escape_super";
          remap = {
            CAPSLOCK = {
              held = "KEY_LEFTMETA";
              alone = "ESC";
              alone_timeout_millis = 1000;
              hold_threshold_millis = 100;
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
