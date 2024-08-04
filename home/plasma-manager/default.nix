{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.plasma-manager.homeManagerModules.plasma-manager
  ];
  programs.plasma = {
    enable = true;

    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      cursor.theme = "Bibata-Modern-Ice";
      iconTheme = "Papirus-Dark";
    };
    fonts = {
      general = {
        family = "Ubuntu Nerd Font";
        pointSize = 14;
      };
      fixedWidth = {
        family = "FiraCode Nerd Font";
        pointSize = 12;
      };

      windowTitle = {
        family = "Ubuntu Nerd Font";
        pointSize = 12;
      };
    };

    panels = [
      {
        location = "bottom";
        height = 92;
        lengthMode = "fit";
        floating = true;
        widgets = [
          {
            name = "org.kde.plasma.icontasks";
            config = {
              General = {
                launchers = [
                  "applications:kdesystemsettings.desktop"
                  "applications:org.kde.dolphin.desktop"
                  "applications:firefox.desktop"
                  "applications:Alacritty.desktop"
                ];
                fill = "false";
              };
            };
          }
          "org.kde.plasma.marginsseparator"
          "org.kde.plasma.showdesktop"
        ];
        hiding = "dodgewindows";
      }
      # Global menu at the top
      {
        location = "top";
        floating = true;
        height = 37;
        widgets = [
          {
            name = "org.kde.plasma.kickoff";
            config = {
              General.icon = "nix-snowflake-white";
            };
          }
          "org.kde.plasma.panelspacer"
          {
            digitalClock = {
              calendar.firstDayOfWeek = "sunday";
              date.enable = false;
            };
          }
          "org.kde.plasma.panelspacer"
          "org.kde.plasma.systemtray"
        ];
      }
    ];
    configFile = {
      krunnerrc.General.FreeFloating = "true";
    };
  };

  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
  ];
}
