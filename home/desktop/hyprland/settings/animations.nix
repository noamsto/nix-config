_: {
  wayland.windowManager.hyprland.settings = {
    # hl.curve(name, { type = "bezier", points = {...} }) — two positional args,
    # hence _args. Replaces the hyprlang `bezier = name, x1, y1, x2, y2`.
    curve = [
      {
        _args = [
          "myBezier"
          {
            type = "bezier";
            points = [
              [0.05 0.9]
              [0.1 1.05]
            ];
          }
        ];
      }
    ];

    # hl.animation({ leaf, enabled, speed, bezier, style }) — one call per leaf.
    # Replaces hyprlang `animation = leaf, onoff, speed, curve[, style]`.
    animation = [
      {
        leaf = "windows";
        enabled = true;
        speed = 7;
        bezier = "myBezier";
      }
      {
        leaf = "windowsOut";
        enabled = true;
        speed = 7;
        bezier = "default";
        style = "popin 80%";
      }
      {
        leaf = "border";
        enabled = true;
        speed = 10;
        bezier = "default";
      }
      {
        leaf = "borderangle";
        enabled = true;
        speed = 8;
        bezier = "default";
      }
      {
        leaf = "fade";
        enabled = true;
        speed = 7;
        bezier = "default";
      }
      {
        leaf = "workspaces";
        enabled = true;
        speed = 6;
        bezier = "default";
      }
    ];
  };
}
