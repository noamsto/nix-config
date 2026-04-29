{
  config,
  lib,
  ...
}: let
  inherit (config.machine) isLaptop;
in {
  config = lib.mkIf isLaptop {
    # systemd-backlight clamps the restored brightness up to ID_BACKLIGHT_CLAMP%
    # on boot, so rebooting at very low brightness can't leave the screen
    # unreadable through firmware/greetd.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", ENV{ID_BACKLIGHT_CLAMP}="30"
    '';
  };
}
