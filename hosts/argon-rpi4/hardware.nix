{
  nixos-raspberrypi,
  pkgs,
  config,
  ...
}: let
  self = config.services.argonone;
  arg1pk = nixos-raspberrypi.packages.${pkgs.system}.argononed;
in {
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-4.base
    raspberry-pi-4.display-vc4
    raspberry-pi-4.case-argonone
  ];

  # Add device tree filtering to prevent overlay conflicts

  hardware.deviceTree.filter = "*rpi-4-*.dtb";

  # Enable i2c hardware - CRITICAL for Argon ONE case
  hardware.i2c.enable = true;

  hardware.raspberry-pi.config = {
    all = {
      base-dt-params = {
        i2c_arm = {
          enable = true;
          value = "on";
        };
      };
      dt-overlays = {
        i2c1 = {
          enable = true;
          params = {};
        };
        argoneone = {
          enable = true;
          params = {
          };
        };
      };
    };
  };

  hardware.enableRedistributableFirmware = true;

  # fileSystems managed by disko.nix
}
