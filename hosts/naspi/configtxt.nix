{...}: {
  # Default config.txt as provided with the official Raspberry Pi OS images
  # https://github.com/RPi-Distro/pi-gen/blob/master/stage1/00-boot-files/files/config.txt

  # More options and information: http://rptl.io/configtxt

  # Additional overlays' (base-dt-params,dt-overlays) documentation:
  # * /boot/firmware/overlays/README
  # * https://github.com/raspberrypi/linux/blob/rpi-6.6.y/arch/arm/boot/dts/overlays/README

  hardware.raspberry-pi.config = {
    all = {
      dt-overlays = {
        pwm-fan = {
          enable = true;
          params = {};
        };
      };
    };
  };
}
