{
  lib,
  internal,
  scale,
}: {
  outputs = [
    {
      key = "laptop";
      name = "eDP-1";
      inherit (internal) make model serial;
      enabled = true;
      x = 0;
      y = 0;
      # Size and refresh 0: hyprmoncfg skips mode validation for 0 and renders
      # an empty mode as `preferred`.
      width = 0;
      height = 0;
      refresh = 0;
      inherit scale;
      transform = 0;
    }
  ];
  workspaces = {
    enabled = true;
    strategy = "manual";
    rules = map (ws: {
      workspace = toString ws;
      output_key = "laptop";
      default = ws == 1;
    }) (lib.range 1 9);
  };
}
