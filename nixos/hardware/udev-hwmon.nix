# Allow unprivileged access to hardware monitoring interfaces
# Enables btop and other tools to read CPU temps, battery state, etc.
_: {
  services.udev.extraRules = ''
    SUBSYSTEM=="hwmon", KERNEL=="hwmon*", MODE="0644"
    SUBSYSTEM=="power_supply", MODE="0644"
  '';
}
