{lib, ...}: {
  wayland.windowManager.hyprland.settings = {
    # layer rules — hl.layer_rule({ match = { namespace = ... }; <effect> = ...; })
    # One call per rule (not consolidated): rules registered later win, and
    # `vicinae` deliberately appears in both the ignore_alpha 0 and 0.5 lists.
    layer_rule = let
      mkLayerRules = effects: namespaces:
        lib.flatten (map (ns: map (e: {match = {namespace = ns;};} // e) effects) namespaces);

      lowopacity = ["bar" "calendar" "notifications" "system-menu"];
      highopacity = ["vicinae" "osd" "logout_dialog"];
      blurred = lib.concatLists [lowopacity highopacity];
      sensitive = ["gnome-keyring-prompt" "polkit" "hyprpolkitagent" "gcr-prompter"];
    in
      (mkLayerRules [{blur = true;}] blurred)
      ++ (mkLayerRules [{xray = true;}] ["bar"])
      ++ (mkLayerRules [{ignore_alpha = 0;}] ["vicinae"])
      ++ (mkLayerRules [{ignore_alpha = 0.5;}] (highopacity ++ ["music"]))
      ++ (mkLayerRules [{ignore_alpha = 0.2;}] lowopacity)
      ++ (mkLayerRules [{no_anim = true;}] ["vicinae"])
      ++ (mkLayerRules [{no_screen_share = true;}] sensitive);

    # window rules — hl.window_rule({ match = {...}; <effect> = ...; })
    # Effects sharing a match are merged into one call; ordering between
    # distinct matches is preserved (the pin -> Vicinae border_color override
    # depends on it).
    window_rule = [
      {
        match = {class = ".*";};
        suppress_event = "maximize";
      }
      {
        match = {title = "^(Vicinae Launcher)$";};
        pin = true;
        size = "900 700";
      }
      {
        match = {title = "^(Media viewer)$";};
        float = true;
        size = "900 600";
        center = true;
      }
      {
        match = {class = "^(org.gnome.Calculator)$";};
        float = true;
        size = "360 490";
      }
      {
        match = {class = "^(pavucontrol)$";};
        float = true;
      }
      {
        match = {class = "^(nm-connection-editor)$";};
        float = true;
      }
      {
        match = {class = "^(file-roller)$";};
        float = true;
        size = "700 500";
        center = true;
      }
      {
        match = {class = "^(1Password|1password|com.1password.1Password)$";};
        float = true;
        center = true;
        immediate = true;
      }
      {
        match = {
          class = "^(1Password|1password|com.1password.1Password)$";
          title = "^(Quick Access)$";
        };
        float = true;
        center = true;
        size = "400 500";
      }
      {
        match = {
          class = "^(1Password|1password|com.1password.1Password)$";
          title = ".*(Password|Lock).*";
        };
        float = true;
        center = true;
        size = "900 600";
      }
      {
        match = {
          class = "^(1Password|1password|com.1password.1Password)$";
          title = "^(1Password)$";
        };
        size = "500 600";
      }
      {
        match = {
          class = "^(1Password|1password|com.1password.1Password)$";
          title = "^$";
        };
        float = true;
        immediate = true;
        decorate = false;
        no_shadow = true;
        pin = true;
      }
      {
        match = {class = "^(pavucontrol)$";};
        size = "800 600";
      }
      {
        match = {class = "^(nm-connection-editor)$";};
        size = "600 500";
      }
      {
        match = {class = "^(ca.andyholmes.Valent)$";};
        float = true;
        center = true;
        size = "800 600";
      }
      {
        match = {title = "^(Bluetooth)$";};
        float = true;
        center = true;
        dim_around = true;
      }
      {
        match = {title = "^(.*[Bb]luetooth.*(Pairing|Authentication)).*$";};
        float = true;
        center = true;
        dim_around = true;
      }
      {
        match = {title = "^(Picture-in-Picture)$";};
        float = true;
        pin = true;
        no_initial_focus = true;
      }
      {
        match = {
          class = "^(chromium|chromium-browser)$";
          title = "^(Picture-in-Picture)$";
        };
        float = true;
        pin = true;
        no_initial_focus = true;
        size = "400 225";
        move = "100%-420 100%-245";
      }
      {
        match = {
          class = "^(chromium|chromium-browser)$";
          title = "^(.*Picture.in.Picture.*)$";
        };
        float = true;
        no_initial_focus = true;
      }
      {
        match = {
          class = "^(chromium|chromium-browser)$";
          title = "^(.*meet\\.google\\.com.*)$";
        };
        float = true;
      }
      {
        match = {title = "^(Firefox — Sharing Indicator)$";};
        workspace = "special silent";
      }
      {
        match = {title = "^(.*is sharing (your screen|a window)\\.)$";};
        workspace = "special silent";
      }
      {
        match = {title = "^(.*Sharing Indicator)$";};
        workspace = "special silent";
      }
      {
        match = {title = "^(.*is sharing (your screen|a window).*)$";};
        float = true;
      }
      {
        match = {title = "^(Volume Control)$";};
        size = "800 600";
      }
      {
        match = {class = "^(vlc)$";};
        float = true;
        idle_inhibit = "focus";
        size = "960 640";
        center = true;
      }
      {
        match = {class = "^(mpv)$";};
        float = true;
      }
      {
        match = {class = "^(mpv|.+exe|celluloid)$";};
        idle_inhibit = "focus";
      }
      {
        match = {class = "^(mpv)$";};
        size = "960 640";
        center = true;
      }
      {
        match = {class = "^(firefox)$";};
        no_close_for = 2000;
      }
      {
        # browser automation drives Chromium in the background; its focus requests would switch workspaces
        match = {class = "^(chromium|chromium-browser)$";};
        no_close_for = 2000;
        suppress_event = "maximize activate activatefocus";
      }
      {
        match = {
          class = "^(firefox)$";
          title = "^(.*YouTube.*)$";
        };
        idle_inhibit = "focus";
      }
      {
        match = {class = "^(firefox)$";};
        idle_inhibit = "fullscreen";
      }
      {
        match = {
          class = "^(chromium|chromium-browser)$";
          title = "^(.*YouTube.*)$";
        };
        idle_inhibit = "focus";
      }
      {
        match = {class = "^(chromium|chromium-browser)$";};
        idle_inhibit = "fullscreen";
      }
      {
        match = {
          class = "^(thunar|Thunar)$";
          title = "^(Progress Dialog|Copying|File Operation Progress)$";
        };
        float = true;
      }
      {
        match = {class = "^(dragon|dragon-drop)$";};
        float = true;
        pin = true;
        no_initial_focus = true;
        size = "400 300";
      }
      {
        match = {class = "^(kitty|com\\.mitchellh\\.ghostty)$";};
        workspace = "1 silent";
      }
      {
        match = {class = "^(firefox)$";};
        workspace = "2";
      }
      {
        match = {
          class = "^(chromium|chromium-browser)$";
          initial_title = ".*";
        };
        workspace = "2 silent";
      }
      {
        match = {class = "^(slack|Slack)$";};
        workspace = "5";
      }
      {
        match = {class = "^(ferdium)$";};
        workspace = "5 silent";
      }
      {
        match = {class = "^(zoom)$";};
        workspace = "5";
      }
      {
        match = {class = "^(com.github.th_ch.youtube_music|spotify)$";};
        workspace = "9 silent";
      }
      {
        match = {class = "^(zoom|Zoom)$";};
        float = true;
      }
      {
        match = {class = "^(zoom)$";};
        idle_inhibit = "focus";
      }
      {
        match = {class = "^(zoom|Zoom)$";};
        immediate = true;
      }
      {
        match = {
          class = "^(zoom)$";
          title = "^(Zoom Meeting)$";
        };
        float = true;
      }
      {
        match = {
          class = "^(zoom|Zoom)$";
          title = "^(Zoom Meeting)$";
        };
        size = "960 640";
      }
      {
        match = {
          class = "^(zoom|Zoom)$";
          title = "^(Zoom)$";
        };
        size = "500 400";
      }
      {
        match = {class = "^(zoom|Zoom)$";};
        center = true;
      }
      {
        match = {
          class = "^(zoom)$";
          title = "^$";
        };
        float = true;
        pin = true;
        decorate = false;
        no_shadow = true;
        min_size = "1 1";
        max_size = "800 600";
      }
      {
        match = {
          class = "^(zoom)$";
          xwayland = true;
        };
        rounding = 0;
      }
      {
        match = {class = "^(gcr-prompter)$";};
        dim_around = true;
      }
      {
        match = {float = true;};
        max_size = "1200 900";
      }
      {
        match = {
          float = true;
          title = "^$";
        };
        min_size = "1 1";
      }
      {
        match = {title = "^(Menu|.*menu.*|.*dropdown.*|.*popup.*)$";};
        stay_focused = true;
      }
      {
        match = {class = "^(xdg-desktop-portal-gtk)$";};
        dim_around = true;
        float = true;
        size = "900 600";
        center = true;
        immediate = true;
      }
      {
        match = {class = "^(xdg-desktop-portal-kde|xdg-desktop-portal-wlr)$";};
        dim_around = true;
        float = true;
        pin = true;
        immediate = true;
      }
      {
        match = {title = "^(Print|Print Document)$";};
        dim_around = true;
        float = true;
        pin = true;
        immediate = true;
      }
      {
        match = {class = "^(gtk3-print-backends)$";};
        dim_around = true;
        float = true;
        pin = true;
        immediate = true;
      }
      {
        match = {class = "^(polkit-gnome-authentication-agent-1|gnome-keyring-prompt|hyprpolkitagent)$";};
        dim_around = true;
        float = true;
        pin = true;
        stay_focused = true;
        immediate = true;
      }
      {
        match = {title = "^(.*(Screen|Desktop) (Share|Capture|Record)).*$";};
        dim_around = true;
        float = true;
        pin = true;
        immediate = true;
      }
      {
        match = {title = "^(Select what to share)$";};
        dim_around = true;
        float = true;
        pin = true;
        stay_focused = true;
        immediate = true;
      }
      {
        match = {title = "^(.*Permission.*)$";};
        dim_around = true;
        float = true;
        pin = true;
        immediate = true;
      }
      {
        match = {title = "^(Authentication Required)$";};
        dim_around = true;
        float = true;
        pin = true;
        stay_focused = true;
        immediate = true;
      }
      {
        match = {title = "^(Confirm)$";};
        dim_around = true;
        float = true;
        pin = true;
        immediate = true;
      }
      {
        match = {xwayland = true;};
        rounding = 0;
      }
      {
        match = {
          xwayland = true;
          float = true;
        };
        immediate = true;
      }
      {
        match = {
          class = "^(.*jetbrains.*)$";
          title = "^(Confirm Exit|Open Project|win424|win201|splash)$";
        };
        center = true;
      }
      {
        match = {
          class = "^(.*jetbrains.*)$";
          title = "^(splash)$";
        };
        size = "640 400";
      }
      {
        match = {fullscreen = true;};
        decorate = false;
        no_shadow = true;
        rounding = 0;
        opacity = "0.95";
      }
      {
        match = {class = "^(kitty|foot|com\\.mitchellh\\.ghostty)$";};
        opacity = "1.0 override 1.0 override";
      }
      {
        match = {pin = true;};
        border_color = {colors = ["rgb(f9e2af)" "rgb(f1fa8c)"];};
      }
      {
        match = {title = "^(Vicinae Launcher)$";};
        border_color = {colors = ["rgb(89b4fa)" "rgb(74c7ec)"];};
      }
    ];
  };
}
