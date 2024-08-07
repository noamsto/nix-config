{
  inputs,
  config,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
  isDesktop = config.machine.type == "desktop";
  isPC = isLaptop || isDesktop;
in {
  imports = [
    inputs.xremap.nixosModules.default
  ];
  services.xremap = {
    # View keys scancodes here: https://github.com/emberian/evdev/blob/1d020f11b283b0648427a2844b6b980f1a268221/src/scancodes.rs#L26-L572
    enable = isPC;
    userName = config.username;
    watch = true;
    config = {
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
