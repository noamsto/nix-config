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
      cursorTheme = "Bibata-Modern-Ice";
      iconTheme = "Papirus-Dark";
    };
    fonts = {
      general = {
        family = "Ubuntu";
        pointSize = 14;
      };

      windowTitle = {
        family = "Ubuntu";
        pointSize = 12;
      };
    };

    panels = [
      {
        location = "bottom";
        height = 72;
        lengthMode = "fit";
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
        hiding = "autohide";
      }
      # Global menu at the top
      {
        location = "top";
        height = 37;
        widgets = [
          {
            name = "org.kde.plasma.kickoff";
            config = {
              General.icon = "nix-snowflake-white";
            };
          }
          "org.kde.plasma.panelspacer"
          "org.kde.plasma.systemtray"
          "org.kde.plasma.marginsseparator"
          {
            digitalClock = {
              calendar.firstDayOfWeek = "sunday";
              time.format = "12h";
            };
          }
        ];
      }
    ];
  };

  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
  ];
}
