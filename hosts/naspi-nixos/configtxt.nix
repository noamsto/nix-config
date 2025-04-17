{...}: {
  hardware.raspberry-pi.config = {
    all = {
      dt-overlays = {
        pwm-2chan = {
          enable = true;
          params = {};
        };
      };
    };
  };
}
