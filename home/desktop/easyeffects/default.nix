{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}: let
  inherit (osConfig.nix-config.desktop.easyeffects) preset;

  # EasyEffects 8.x reads presets from ~/.local/share/easyeffects (xdg.dataHome).
  # It migrates away from the old ~/.config location, but that migration aborts on
  # our read-only Nix-store symlinks, so we place the files in the data dir directly.
  easyeffectsDataHome = "${config.xdg.dataHome}/easyeffects/";

  thinkpad-p14s-g4-linux = import ./thinkpad-p14s-g4-linux.nix {
    inherit pkgs;
    easyeffects_config_home = easyeffectsDataHome;
  };

  thinkpad-p14s-g5-linux = import ./thinkpad-p14s-g5-linux.nix {
    inherit pkgs;
    easyeffects_config_home = easyeffectsDataHome;
  };

  # The stock Voice preset is gate -> convolver only, with no bass control, so
  # bass-heavy passages overexcurse the laptop woofers and buzz. "Voice HP" adds a
  # 90 Hz / 48 dB-oct high-pass (band0) plus a safety limiter, lifted verbatim from
  # the upstream Legacy preset's equalizer/limiter blocks; the other EQ bands are
  # flattened so only the high-pass acts. Built on Voice (not Music/Dynamic/Game/
  # Movie) because the Voice IRS is symmetric — the others' asymmetric stereo IRS
  # buzzes on its own.
  voiceHpPreset =
    pkgs.runCommand "thinkpad-p14s-g5-voice-hp.json" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      jq --slurpfile leg "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Legacy.json" '
        .output["limiter#0"] = $leg[0].output["limiter#0"]
        | .output["equalizer#0"] = (
            $leg[0].output["equalizer#0"]
            | .["split-channels"] = false
            | .left  = (.left  | to_entries | map(.value |= (.type = "Bell" | .gain = 0.0 | .mute = false)) | from_entries)
            | .right = (.right | to_entries | map(.value |= (.type = "Bell" | .gain = 0.0 | .mute = false)) | from_entries)
            | .left.band0  |= (.type = "Hi-pass" | .frequency = 90.0 | .mode = "RLC (BT)" | .slope = "x4" | .gain = 0.0 | .mute = false)
            | .right.band0 |= (.type = "Hi-pass" | .frequency = 90.0 | .mode = "RLC (BT)" | .slope = "x4" | .gain = 0.0 | .mute = false)
          )
        | .output.plugins_order = ["gate#0", "convolver#0", "equalizer#0", "limiter#0"]
      ' "${thinkpad-p14s-g5-linux}/easyeffects/ThinkPad P14s G5 - Voice.json" > $out
    '';

  presetConfigs = {
    "thinkpad-p14s-g5-linux" = {
      dataFiles = {
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
        "easyeffects/output/ThinkPad P14s G5 - Voice HP.json".source = voiceHpPreset;
      };
      defaultPreset = "ThinkPad P14s G5 - Voice HP";
    };
    "thinkpad-p14s-g4-linux" = {
      dataFiles = {
        # Gen 4 files
        "easyeffects/irs/P14s_G4_Music_Movies.irs".source = "${thinkpad-p14s-g4-linux}/easyeffects/P14s_G4_Music_Movies.irs";
        "easyeffects/output/ThinkPad P14s G4.json".source = "${thinkpad-p14s-g4-linux}/easyeffects/ThinkPad P14s G4.json";
      };
      defaultPreset = "ThinkPad P14s G4";
    };
  };
  presetConfig =
    if preset == null
    then null
    else presetConfigs.${preset};
in {
  xdg.dataFile = lib.optionalAttrs (presetConfig != null) presetConfig.dataFiles;

  services.easyeffects = {
    enable = true;
    package = pkgs.stable.easyeffects;
    preset = lib.mkIf (presetConfig != null) presetConfig.defaultPreset;
  };
}
