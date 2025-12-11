{
  pkgs,
  config,
  osConfig,
  ...
}: let
  isGen5 = osConfig.hostname == "thinkpad-p14s-g5";

  thinkpad-p14s-g4-linux = import ./thinkpad-p14s-g4-linux.nix {
    inherit pkgs;
    easyeffects_config_home = "${config.xdg.configHome}/easyeffects/";
  };

  thinkpad-p14s-g5-linux = import ./thinkpad-p14s-g5-linux.nix {
    inherit pkgs;
    easyeffects_config_home = "${config.xdg.configHome}/easyeffects/";
  };

  # Select preset configuration based on hardware generation
  presetConfig =
    if isGen5
    then {
      configFiles = {
        # Gen 5 IRS convolver files
        "easyeffects/irs/P14s_G5_Dynamic.irs".source = "${thinkpad-p14s-g5-linux}/easyeffects/P14s_G5_Dynamic.irs";
        "easyeffects/irs/P14s_G5_Game.irs".source = "${thinkpad-p14s-g5-linux}/easyeffects/P14s_G5_Game.irs";
        "easyeffects/irs/P14s_G5_Movie.irs".source = "${thinkpad-p14s-g5-linux}/easyeffects/P14s_G5_Movie.irs";
        "easyeffects/irs/P14s_G5_Music.irs".source = "${thinkpad-p14s-g5-linux}/easyeffects/P14s_G5_Music.irs";
        "easyeffects/irs/P14s_G5_Voice.irs".source = "${thinkpad-p14s-g5-linux}/easyeffects/P14s_G5_Voice.irs";
        # Gen 5 JSON preset files
        "easyeffects/output/ThinkPad P14s G5 - Dynamic.json".source = "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Dynamic.json";
        "easyeffects/output/ThinkPad P14s G5 - Game.json".source = "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Game.json";
        "easyeffects/output/ThinkPad P14s G5 - Movie.json".source = "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Movie.json";
        "easyeffects/output/ThinkPad P14s G5 - Music.json".source = "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Music.json";
        "easyeffects/output/ThinkPad P14s G5 - Voice.json".source = "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Voice.json";
        "easyeffects/output/ThinkPad P14s G5 - Legacy.json".source = "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Legacy.json";
      };
      # Voice IRS is symmetric (no phase issues on laptop speakers)
      # Music/Dynamic/Game/Movie have asymmetric stereo that causes buzzing
      defaultPreset = "ThinkPad P14s G5 - Voice";
    }
    else {
      configFiles = {
        # Gen 4 files
        "easyeffects/irs/P14s_G4_Music_Movies.irs".source = "${thinkpad-p14s-g4-linux}/easyeffects/P14s_G4_Music_Movies.irs";
        "easyeffects/output/ThinkPad P14s G4.json".source = "${thinkpad-p14s-g4-linux}/easyeffects/ThinkPad P14s G4.json";
      };
      defaultPreset = "ThinkPad P14s G4";
    };
in {
  xdg.configFile = presetConfig.configFiles;

  services.easyeffects = {
    enable = true;
    package = pkgs.stable.easyeffects;
    preset = presetConfig.defaultPreset;
  };
}
