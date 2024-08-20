{...}: {
  services = {
    kanshi = {
      enable = true;
      systemdTarget = "hyprland-session.target";
      settings = [
        {
          output = {
            criteria = "eDP-1";
            mode = "2880x1800@90.0";
            scale = 1.40625;
          };
        }
        {
          profile.name = "undocked";
          profile.outputs = [
            {
              criteria = "eDP-1";
              position = "0,0";
            }
          ];
        }
        {
          profile.name = "home-docked-laptop-open";
          profile.outputs = [
            {
              criteria = "Samsung Electric Company S27H85x H4ZM300138";
              mode = "2560x1440@59.95100";
              position = "0,0";
              scale = 1.25;
            }
            {
              criteria = "Samsung Electric Company S27H85x H4ZKB00167";
              mode = "2560x1440@59.95100";
              position = "2048,0";
              scale = 1.25;
            }
            {
              criteria = "eDP-1";
              position = "2048,1152";
            }
          ];
        }
      ];
    };
  };
}
