# Raspberry Pi 4 Image Configuration

This document describes the `rpi4-image` configuration that creates a bootable SD card image for Raspberry Pi 4 with PWM fan overlay support.

## Features

- **PWM Fan Control**: Automatic temperature-based fan control using PWM overlay
- **SSH Access**: Pre-configured SSH with your public key
- **Network Manager**: Easy WiFi and network configuration
- **Essential Tools**: Includes vim, git, htop, and other useful utilities
- **Optimized for RPI4**: Hardware-specific optimizations and firmware

## Building the Image

To build the SD card image:

```bash
nix build .#rpi4-image
```

The resulting image will be available at `result/sd-image/nixos-sd-image-*.img`.

## Flashing the Image

Flash the image to an SD card:

```bash
# Find your SD card device (e.g., /dev/sdX)
lsblk

# Flash the image (replace /dev/sdX with your SD card device)
sudo dd if=result/sd-image/nixos-sd-image-*.img of=/dev/sdX bs=4M status=progress
sync
```

## PWM Fan Configuration

The image includes a PWM fan overlay that provides automatic temperature-based fan control:

### Default Configuration

- **PWM GPIO**: GPIO 18 (PWM0)
- **Temperature Trip Point**: 50°C (fan starts)
- **Temperature Hysteresis**: 5°C
- **Cooling Levels**: 0%, 50%, 75%, 100% PWM duty cycle

### Hardware Connection

Connect your PWM fan to:
- **PWM Control**: GPIO 18 (Pin 12)
- **Power**: 5V (Pin 2 or 4)
- **Ground**: GND (Pin 6, 9, 14, 20, 25, 30, 34, or 39)

### Customizing PWM Fan Settings

You can customize the PWM fan parameters by modifying `hosts/rpi4-image/configtxt.nix`:

```nix
dt-overlays = {
  pwm-fan = {
    enable = true;
    params = {
      # Custom parameters (all optional)
      # pwm-gpio = 18;        # GPIO pin for PWM control
      # temp-trip-point = 50000;  # Temperature to start fan (50°C)
      # temp-hysteresis = 5000;   # Temperature hysteresis (5°C)
      # cooling-levels = "0,50,75,100";  # PWM duty cycle levels
    };
  };
};
```

## First Boot

After flashing and booting:

1. **Login**: Use the `nixos` user (no password required)
2. **Network**: Use NetworkManager to connect to WiFi:
   ```bash
   sudo nmcli device wifi connect "YourWiFiName" password "YourPassword"
   ```
3. **SSH**: Connect remotely using your SSH key:
   ```bash
   ssh nixos@<raspberry-pi-ip>
   ```

## System Information

- **Username**: `nixos`
- **Hostname**: `rpi4-image`
- **Timezone**: Asia/Jerusalem
- **Locale**: en_US.UTF-8
- **State Version**: 24.05

## Additional Hardware Features

### Enabled Interfaces
- **I2C**: Available for sensors and displays
- **SPI**: Available for additional peripherals
- **UART**: Enabled for debugging
- **Hardware Watchdog**: Enabled for system stability

### Performance Settings
- **GPU Memory**: 64MB (optimized for headless operation)
- **HDMI**: Force hotplug enabled
- **Boot Delay**: 1 second for slow SD cards

## Customization

To customize the image for your needs:

1. **Edit Configuration**: Modify files in `hosts/rpi4-image/`
2. **Add Packages**: Update `environment.systemPackages` in `default.nix`
3. **Change Settings**: Modify hardware configuration in `configtxt.nix`
4. **Rebuild**: Run `nix build .#rpi4-image` to create updated image

## Troubleshooting

### Fan Not Working
- Check GPIO connections (GPIO 18 for PWM)
- Verify fan is PWM-compatible
- Check temperature: `cat /sys/class/thermal/thermal_zone0/temp`
- Monitor PWM output: `cat /sys/class/pwm/pwmchip0/pwm0/duty_cycle`

### Network Issues
- Use `nmcli` to manage network connections
- Check interface status: `ip addr show`
- Scan for WiFi: `sudo nmcli device wifi list`

### SSH Access
- Ensure your SSH key is correctly added to the configuration
- Check SSH service: `sudo systemctl status sshd`
- Verify firewall settings if using custom network setup

## Related Configurations

- **`naspi`**: Runtime configuration with disko partitioning
- **`naspi-installer-target`**: For deployment to installer-booted systems
- **`rpi4-installer`**: Minimal installer image

## References

- [NixOS on ARM/Raspberry Pi 4](https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_4)
- [Raspberry Pi Device Tree Overlays](https://github.com/raspberrypi/linux/blob/rpi-6.6.y/arch/arm/boot/dts/overlays/README)
- [PWM Fan Overlay Documentation](https://github.com/raspberrypi/linux/blob/rpi-6.6.y/arch/arm/boot/dts/overlays/pwm-fan-overlay.dts)
