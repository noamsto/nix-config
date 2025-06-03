{
  pkgs,
  config,
  ...
}: let
  thinkpad-p14s-g4-linux = import ./thinkpad-p14s-g4-linux.nix {
    inherit pkgs;
    easyeffects_config_home = "${config.xdg.configHome}/easyeffects/";
  };
in {
  xdg.configFile = {
    "easyeffects/irs/P14s_G4_Music_Movies.irs".source = "${thinkpad-p14s-g4-linux}/easyeffects/P14s_G4_Music_Movies.irs";
    "easyeffects/output/ThinkPad P14s G4.json".source = "${thinkpad-p14s-g4-linux}/easyeffects/ThinkPad P14s G4.json";
  };

  services.easyeffects = {
    enable = true;
    package = pkgs.easyeffects;
    preset = "Thinkpad P14s G4";
  };
}
