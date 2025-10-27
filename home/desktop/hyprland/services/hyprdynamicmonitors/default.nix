{
  inputs,
  config,
  pkgs,
  ...
}: let
  # Get the absolute path to the scripts directory
  scriptsPath = "${config.xdg.configHome}/hyprdynamicmonitors/scripts";

  # Generate config.toml with substituted script paths
  configFile = pkgs.substitute {
    src = ./config.toml;
    substitutions = [
      "--replace"
      "@SCRIPTS_PATH@"
      scriptsPath
    ];
  };
in {
  imports = [inputs.hyprdynamicmonitors.homeManagerModules.default];

  # Configure hyprdynamicmonitors with systemd integration
  home.hyprdynamicmonitors = {
    inherit configFile;
    enable = true;
    extraFlags = ["--enable-lid-events"];
  };

  # Deploy profiles and scripts using xdg.configFile
  xdg.configFile = {
    "hyprdynamicmonitors/profiles".source = ./profiles;
    "hyprdynamicmonitors/scripts".source = ./scripts;
  };
}
