{config, ...}: {
  system.autoUpgrade = {
    enable = true;
    flake = "${config.programs.nh.flake}#${config.networking.hostName}";
    flags = ["--print-build-logs"];
    dates = "Sun 03:00"; # Weekly on Sunday at 3 AM
    randomizedDelaySec = "45min";
    allowReboot = false; # No automatic reboots
  };
}
