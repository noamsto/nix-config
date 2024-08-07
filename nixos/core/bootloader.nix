{...}: {
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 12;
      consoleMode = "auto";
    };
    efi.canTouchEfiVariables = true;
  };
}
