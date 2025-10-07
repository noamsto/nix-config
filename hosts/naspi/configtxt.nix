{...}: {
  # Default config.txt as provided with the official Raspberry Pi OS images
  # https://github.com/RPi-Distro/pi-gen/blob/master/stage1/00-boot-files/files/config.txt

  # More options and information: http://rptl.io/configtxt

  # Additional overlays' (base-dt-params,dt-overlays) documentation:
  # * /boot/firmware/overlays/README
  # * https://github.com/raspberrypi/linux/blob/rpi-6.6.y/arch/arm/boot/dts/overlays/README

  # IMPORTANT: USB/SSD Boot Configuration
  # This system boots from USB SSD, NOT SD card. If you see boot errors about
  # "emergency-ssh" or SD card timeouts, remove any SD card from the slot.
  #
  # To update EEPROM boot order (prioritize USB over SD):
  # 1. Boot into Raspberry Pi OS (from SD card temporarily)
  # 2. Run: sudo rpi-eeprom-config --edit
  # 3. Set: BOOT_ORDER=0xf46  (USB, NVMe, SD fallback)
  # 4. Save and reboot
  #
  # Current boot priority: USB SSD > SD card (via EEPROM)

  hardware.raspberry-pi.config = {
    all = {
      dt-overlays = {
        # PWM 2-channel overlay for Geekworm X-C1 fan control
        # Required for xscript to control fan via GPIO 18 PWM
        pwm-2chan = {
          enable = true;
          params = {};
        };

        # GPIO shutdown overlay for Geekworm X-C1 power button
        # Power button connected to GPIO 4
        # Disabled for now due to parameter configuration issues
        # gpio-shutdown = {
        #   enable = false;
        # };

        # I2C overlay for expansion board communication
        i2c1 = {
          enable = true;
          params = {};
        };
      };

      # Additional base device tree parameters
      base-dt-params = {
        # Enable I2C interface
        i2c_arm = {
          enable = true;
          value = "on";
        };

        # Set I2C baudrate
        i2c_arm_baudrate = {
          enable = true;
          value = "400000"; # 400kHz for reliable communication
        };
      };
    };
  };
}
