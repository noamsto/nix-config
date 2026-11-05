{
  pkgs,
  config,
  ...
}: let
  inherit (config.theme) palette;

  # Generate process-compose theme YAML from palette
  mkProcessComposeTheme = p: ''
    style:
      name: "${p.name}"
      body:
        fgColor: "${p.text}"
        bgColor: "${p.base}"
        secondaryTextColor: "${p.mauve}"
        tertiaryTextColor: "${p.mauve}"
        borderColor: "${p.overlay2}"
      stat_table:
        keyFgColor: "${p.mauve}"
        valueFgColor: "${p.text}"
        logoColor: "${p.mauve}"
      proc_table:
        fgColor: "${p.text}"
        fgWarning: "${p.peach}"
        fgPending: "${p.overlay2}"
        fgCompleted: "${p.green}"
        fgError: "${p.red}"
        headerFgColor: "${p.mauve}"
      help:
        fgColor: "${p.text}"
        keyColor: "${p.mauve}"
        hlColor: "${p.surface1}"
        categoryFgColor: "${p.pink}"
      dialog:
        fgColor: "${p.pink}"
        bgColor: "${p.mauve}"
        buttonFgColor: "${p.crust}"
        buttonBgColor: "${p.mauve}"
        buttonFocusFgColor: "${p.crust}"
        buttonFocusBgColor: "${p.mauve}"
        labelFgColor: "${p.rosewater}"
        fieldFgColor: "${p.text}"
        fieldBgColor: "${p.surface2}"
  '';
in {
  # Process-compose theme is set dynamically by theme-toggle script
  # NOTE: theme.yaml is NOT symlinked - it's copied directly by theme-toggle
  # from catppuccin-mocha.yaml or catppuccin-latte.yaml

  home.packages = [
    pkgs.process-compose
  ];

  # Generate theme files from palette (file names match palette.{dark,light}.name)
  xdg.configFile = {
    "process-compose/${palette.dark.name}.yaml".text = mkProcessComposeTheme palette.dark;
    "process-compose/${palette.light.name}.yaml".text = mkProcessComposeTheme palette.light;
  };
}
