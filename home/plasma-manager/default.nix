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

    #
    # Some high-level settings:
    #
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
      # Windows-like panel at the bottom
      {
        location = "bottom";
        height = 72;
        widgets = [
          # Adding configuration to the widgets can also for example be used to
          # pin apps to the task-manager, which this example illustrates by
          # pinning dolphin and konsole to the task-manager by default.
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
          # We can configure the widgets by adding the name and config
          # attributes. For example to add the the kickoff widget and set the
          # icon to "nix-snowflake-white" use the below configuration. This will
          # add the "icon" key to the "General" group for the widget in
          # ~/.config/plasma-org.kde.plasma.desktop-appletsrc.
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
