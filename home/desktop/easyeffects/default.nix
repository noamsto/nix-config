{
  pkgs,
  config,
  lib,
  osConfig,
  ...
}: let
  # G6 has no dedicated EasyEffects preset; ArchWiki recommends the G5 set for it.
  # https://wiki.archlinux.org/title/Lenovo_ThinkPad_P14s_(AMD)_Gen_6 → Audio
  useGen5Presets = builtins.elem osConfig.hostname [
    "thinkpad-p14s-g5"
    "thinkpad-p14s-g6"
  ];

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

  # Select preset configuration based on hardware generation
  presetConfig =
    if useGen5Presets
    then {
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
    }
    else {
      dataFiles = {
        # Gen 4 files
        "easyeffects/irs/P14s_G4_Music_Movies.irs".source = "${thinkpad-p14s-g4-linux}/easyeffects/P14s_G4_Music_Movies.irs";
        "easyeffects/output/ThinkPad P14s G4.json".source = "${thinkpad-p14s-g4-linux}/easyeffects/ThinkPad P14s G4.json";
      };
      defaultPreset = "ThinkPad P14s G4";
    };

  # EE is an all-or-nothing interceptor (it moves every output stream through its
  # sink) and its per-device autoload only fires on a route change *within* one
  # device — never when the default sink switches between separate devices. So the
  # only reliable way to keep the speaker-correction chain off Bluetooth/HDMI/USB is
  # to flip EE's global bypass to track the default sink: correction on only for the
  # built-in speaker (whose IRS the chain is voiced for), clean passthrough elsewhere.
  # The sink name is hardware-specific, so this is gen5-g5 only.
  speakerSink = "alsa_output.pci-0000_c4_00.6.HiFi__Speaker__sink";
  eeBypassBySink = pkgs.writeShellApplication {
    name = "ee-bypass-by-sink";
    runtimeInputs = [pkgs.pulseaudio pkgs.dconf];
    text = ''
      bypass_key=/com/github/wwmm/easyeffects/bypass
      apply() {
        if [ "$(pactl get-default-sink)" = "${speakerSink}" ]; then
          dconf write "$bypass_key" false
        else
          dconf write "$bypass_key" true
        fi
      }
      apply
      pactl subscribe | while read -r line; do
        case "$line" in
          *"on server"*) apply ;;
        esac
      done
    '';
  };
in {
  xdg.dataFile = presetConfig.dataFiles;

  # EE's output-device got stuck on a disconnected HDMI sink, which took EasyEffects
  # out of the speaker path entirely. Pin it to the speaker on this host (the device
  # name is hardware-specific, so this is gen5-g5 only).
  dconf.settings = lib.mkIf (osConfig.hostname == "thinkpad-p14s-g5") {
    "com/github/wwmm/easyeffects/streamoutputs".output-device = speakerSink;
  };

  # Keep EE's speaker correction off everything that isn't the built-in speaker.
  # Runs alongside EE and re-evaluates whenever the default sink changes.
  systemd.user.services.easyeffects-bypass-by-sink = lib.mkIf (osConfig.hostname == "thinkpad-p14s-g5") {
    Unit = {
      Description = "Bypass EasyEffects unless the default sink is the built-in speaker";
      After = ["easyeffects.service" "pipewire-pulse.service"];
      BindsTo = ["easyeffects.service"];
    };
    Service = {
      ExecStart = lib.getExe eeBypassBySink;
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = ["easyeffects.service"];
  };

  services.easyeffects = {
    enable = true;
    package = pkgs.stable.easyeffects;
    preset = presetConfig.defaultPreset;
  };
}
