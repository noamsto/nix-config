{inputs, ...}: {
  config,
  lib,
  pkgs,
  ...
}: let
  palette = config.theme.palette.dark;
  voxtype = pkgs.voxtype.override {
    onnxSupport = true;
  };
in {
  home.packages = [
    # OCR tool - select area and copy text
    # (English and Hebrew only: the default bundle ships every language, ~1 GB)
    ((pkgs.normcap.override {
        tesseract4 = pkgs.tesseract4.override {enableLanguages = ["eng" "heb"];};
      }).overrideAttrs (old: {
        # These tests OCR Chinese and Japanese, whose data is no longer built in.
        disabledTests = old.disabledTests ++ ["test_remove_spaces_in_chi"];
      }))
    # Streaming dictation, complementing voxtype's push-to-talk
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.sherpa-dictate
  ];

  services.voxtype = {
    enable = true;
    # ONNX provides parakeet
    package = voxtype;
    # Also puts wtype + wl-clipboard on the service PATH for text injection
    wayland.display = "wayland-1";
    loadModels = ["parakeet-tdt-0.6b-v3"];

    environment = {
      # The launcher searches --qml-path, then this, then XDG data dirs; the
      # QML tree ships in the source but nixpkgs installs none of it.
      VOXTYPE_OSD_QML_PATH = "${voxtype.src}/quickshell";

      # The module's own PATH covers only coreutils/which plus the wayland
      # typing tools, and systemd lets a later Environment= line win — so
      # restate it whole to add qs (which the launcher execs) and voxtype
      # itself (for the voxtype-audio-bridge sidecar the waveform reads).
      PATH = lib.makeBinPath [
        pkgs.coreutils
        pkgs.which
        pkgs.wl-clipboard
        pkgs.wtype
        pkgs.quickshell
        voxtype
      ];
    };

    settings = {
      engine = "parakeet";
      # Recording is driven by the Hyprland keybind, not voxtype's evdev listener
      hotkey.enabled = false;
      parakeet.model = "parakeet-tdt-0.6b-v3";
      whisper.model = "large-v3-turbo";

      osd = {
        frontend = "quickshell";
        layout = "compact";

        # The stock recipe frames the panel in the state colour (a hard red
        # while recording) and stacks a filled waveform over a separate
        # green-to-yellow meter — three competing hues. Drop the frame and the
        # meter, and draw discrete bars instead: the filled area reads as mush
        # at this size.
        # palette = "omarchy" would read ~/.config/omarchy/current/theme/
        # colors.toml, but voxtype 1.0.1 ships no loader for it — Theme.qml
        # marks that "Wave 2". Feed the semantic tokens directly instead.
        #
        # These are the dark values only. theme-toggle repaints the running
        # OSD for light mode by patching the same tokens in the runtime style
        # JSON; see update_voxtype in theme-toggle.sh.
        palette = "custom";

        colors = {
          accent = palette.mauve;
          background = palette.base;
          surface = palette.surface0;
          foreground = palette.text;
          muted = palette.subtext0;
          success = palette.green;
          warning = palette.yellow;
          error = palette.red;
          recording = palette.red;
          streaming = palette.blue;
          transcribing = palette.peach;
          idle = palette.overlay1;
        };

        frame = {
          border = "none";
          background = "background";
          glow = false;
        };

        visual.layers = [
          {
            type = "shadow";
            order = 0;
          }
          {
            type = "bars";
            source = "peak";
            color = "accent";
            mirror = true;
            order = 10;
          }
          {
            type = "icon";
            source = "state";
            color = "recording";
            order = 20;
          }
        ];
      };
    };
  };
}
