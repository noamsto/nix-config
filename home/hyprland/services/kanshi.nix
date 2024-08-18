{...}: {
  services = {
    kanshi = {
      enable = true;
      systemdTarget = "hyprland-session.target";
      settings = [
        {
          output = {
            criteria = "eDP-1";
            scale = 1.40625;
          };
        }
        {
          profile.name = "undocked";
          profile.outputs = [
            {
              criteria = "eDP-1";
            }
          ];
        }
        {
          profile.name = "home-docked";
          profile.outputs = [
            {
              criteria = "Samsung Electric Company S27H85x H4ZM300138";
              mode = "2880x1800@59.95100";
              position = "0,0";
              scale = 1.25;
            }
            {
              criteria = "Dell Inc. DELL S2722QC C77WLD3";
              mode = "2880x1800@59.95100";
              position = "2048,0";
              scale = 1.25;
            }
            {
              criteria = "eDP-1";
              status = "disable";
            }
          ];
        }
      ];
    };
  };
}
