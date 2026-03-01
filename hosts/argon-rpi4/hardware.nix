{nixos-raspberrypi, ...}: {
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-4.base
    raspberry-pi-4.display-vc4
    raspberry-pi-4.case-argonone
  ];

  hardware = {
    # Add device tree filtering to prevent overlay conflicts
    deviceTree.filter = "*rpi-4-*.dtb";

    # Enable i2c hardware - CRITICAL for Argon ONE case
    i2c.enable = true;

    raspberry-pi.config = {
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

    enableRedistributableFirmware = true;
  };

  # fileSystems managed by disko.nix
}
