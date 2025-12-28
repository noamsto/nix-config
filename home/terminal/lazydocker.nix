{
  pkgs,
  config,
  lib,
  ...
}: let
  palette = config.theme.palette;

  # Generate lazydocker theme from palette
  # Lazydocker uses terminal color names, but we can use closest matches
  # Available colors: default, black, red, green, yellow, blue, magenta, cyan, white
  # Can also use attributes: bold, reverse, underline
  mkLazydockerTheme = p:
    if p.variant == "dark"
    then {
      # Dark theme - use bold colors for visibility on dark background
      activeBorderColor = ["blue" "bold"];
      inactiveBorderColor = ["default"];
      selectedLineBgColor = ["default"]; # Use terminal default for selection
      optionsTextColor = ["blue"];
    }
    else {
      # Light theme - more subtle colors
      activeBorderColor = ["blue" "bold"];
      inactiveBorderColor = ["black"];
      selectedLineBgColor = ["default"];
      optionsTextColor = ["blue"];
    };

  # Full config structure
  mkLazydockerConfig = p: {
    gui = {
      theme = mkLazydockerTheme p;
      showAllContainers = true;
      returnImmediately = false;
    };
    reporting = "off";
    commandTemplates = {
      # Common docker commands
      dockerCompose = "docker compose";
      restartService = "{{ .DockerCompose }} restart {{ .Service.Name }}";
      stopService = "{{ .DockerCompose }} stop {{ .Service.Name }}";
      serviceLogs = "{{ .DockerCompose }} logs --since=60m --follow {{ .Service.Name }}";
    };
  };
in {
  home.packages = [pkgs.lazydocker];

  # Generate config files for both themes
  # theme-toggle will switch between them by copying the appropriate one
  xdg.configFile = {
    # Default config (dark theme)
    "lazydocker/config.yml".text = lib.generators.toYAML {} (mkLazydockerConfig palette.dark);

    # Theme variants for theme-toggle to use
    "lazydocker/themes/${palette.dark.name}.yml".text = lib.generators.toYAML {} (mkLazydockerConfig palette.dark);
    "lazydocker/themes/${palette.light.name}.yml".text = lib.generators.toYAML {} (mkLazydockerConfig palette.light);
  };
}
