{pkgs, ...}: {
  # Create nwg-dock-hyprland configuration files
  xdg.configFile."nwg-dock-hyprland/style.css".text = ''
    /* Catppuccin Mocha colors */
    @define-color rosewater #f5e0dc;
    @define-color flamingo #f2cdcd;
    @define-color pink #f5c2e7;
    @define-color mauve #cba6f7;
    @define-color red #f38ba8;
    @define-color maroon #eba0ac;
    @define-color peach #fab387;
    @define-color yellow #f9e2af;
    @define-color green #a6e3a1;
    @define-color teal #94e2d5;
    @define-color sky #89dceb;
    @define-color sapphire #74c7ec;
    @define-color blue #89b4fa;
    @define-color lavender #b4befe;
    @define-color text #cdd6f4;
    @define-color subtext1 #bac2de;
    @define-color subtext0 #a6adc8;
    @define-color overlay2 #9399b2;
    @define-color overlay1 #7f849c;
    @define-color overlay0 #6c7086;
    @define-color surface2 #585b70;
    @define-color surface1 #45475a;
    @define-color surface0 #313244;
    @define-color base #1e1e2e;
    @define-color mantle #181825;
    @define-color crust #11111b;

    @define-color background @base;
    @define-color surface @surface0;
    @define-color primary @mauve;
    @define-color on-primary @crust;
    @define-color secondary @overlay0;
    @define-color on-secondary @text;

    window {
      background: alpha(@surface, 0.7);
      border-radius: 12px;
      padding: 3px;
      margin: 2px;
      border: 1px solid alpha(@overlay0, 0.3);
    }

    button {
      background-color: transparent;
      border: none;
      border-radius: 8px;
      padding: 4px;
      margin: 1px;
      transition: all 200ms ease-in-out;
    }

    button:hover {
      background-color: alpha(@primary, 0.2);
      color: @text;
      border: 1px solid alpha(@primary, 0.4);
    }

    button:focus {
      box-shadow: none;
      outline: none;
    }

    button:active {
      background-color: alpha(@primary, 0.3);
    }

    image {
      padding: 2px;
      margin: 2px;
      opacity: 0.9;
    }

    button:hover image {
      opacity: 1.0;
    }

    /* Hotspot optimization for better dock activation - based on GitHub issue #65 */
    #hotspot {
      min-height: 3px;
      background-color: transparent;
    }

    /* Ensure dock stays at screen edge when autohidden */
    #dock {
      margin-bottom: 0px;
    }

    /* Improve activation area visibility during development/debugging */
    #hotspot:hover {
      background-color: alpha(@primary, 0.1);
    }
  '';

  # Create launch script for nwg-dock-hyprland
  home.packages = [
    (pkgs.writeShellScriptBin "launch-dock" ''
      # Check if dock is disabled
      if [ -f "$HOME/.cache/dock-disabled" ]; then
          echo ":: Dock disabled"
          exit 0
      fi

      # Kill existing dock processes
      ${pkgs.procps}/bin/pkill -f nwg-dock-hyprland 2>/dev/null || true

      # Wait a moment for processes to terminate
      ${pkgs.coreutils}/bin/sleep 0.5

      # Launch nwg-dock-hyprland with optimized parameters
      # Optimizations based on GitHub issue #65:
      # - Removed -mb (bottom margin) to fix hotspot activation issues
      # - Added -hd 0 to set hide delay to 0ms for instant hiding
      # - Removed -x to allow dock to overlay without pushing windows up
      exec ${pkgs.nwg-dock-hyprland}/bin/nwg-dock-hyprland \
        -i 48 \
        -d \
        -nolauncher \
        -p bottom \
        -a center \
        -hd 0 \
        > /tmp/nwg-dock.log 2>&1
    '')
  ];
}
