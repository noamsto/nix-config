{inputs, ...}: {
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  palette = config.theme.palette.dark;
  voxtype = inputs.voxtype.packages.${pkgs.stdenv.hostPlatform.system}.onnx;
  gemini = osConfig.nix-config.voxtype.gemini;
  geminiActive = gemini.enable && gemini.keyFile != null;
  geminiAdapter = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.voxtype-gemini;
  # Quote the whole assignment; systemd expands \, " and % (specifiers) inside it.
  envAssign = name: value: "\"${name}=${lib.replaceStrings ["\\" "\"" "%"] ["\\\\" "\\\"" "%%"] value}\"";
in {
  home.packages =
    lib.optional geminiActive geminiAdapter
    ++ [
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

  home.sessionVariables = lib.mkIf geminiActive {
    VOXTYPE_GEMINI_KEY_FILE = gemini.keyFile;
    # voxtype-stt-compare reads these so it measures what dictation sends.
    VOXTYPE_GEMINI_VOCABULARY = lib.concatStringsSep "," gemini.vocabulary;
    VOXTYPE_GEMINI_LANGUAGE_CODES = lib.concatStringsSep "," gemini.languageCodes;
  };

  # The key stays in keyFile: the adapter reads the path at startup, so it
  # never reaches the unit, the store or the process arguments.
  systemd.user.services.voxtype-gemini-adapter = lib.mkIf geminiActive {
    Unit.Description = "Gemini Transcribe adapter for voxtype";
    Service = {
      ExecStart = "${geminiAdapter}/bin/voxtype-gemini-adapter";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        (envAssign "VOXTYPE_GEMINI_KEY_FILE" gemini.keyFile)
        (envAssign "VOXTYPE_GEMINI_PORT" (toString gemini.port))
        (envAssign "VOXTYPE_GEMINI_MODEL" gemini.model)
        (envAssign "VOXTYPE_GEMINI_VOCABULARY" (lib.concatStringsSep "," gemini.vocabulary))
        (envAssign "VOXTYPE_GEMINI_LANGUAGE_CODES" (lib.concatStringsSep "," gemini.languageCodes))
      ];
      MemoryMax = "512M";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      # AF_UNIX: name resolution may go through systemd-resolved over a unix socket
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.voxtype.Unit = lib.mkIf geminiActive {
    After = ["voxtype-gemini-adapter.service"];
    Wants = ["voxtype-gemini-adapter.service"];
  };

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
      VOXTYPE_OSD_QML_PATH = "${inputs.voxtype}/quickshell";

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
      engine =
        if geminiActive
        then "whisper"
        else "parakeet";
      # Recording is driven by the Hyprland keybind, not voxtype's evdev listener
      hotkey.enabled = false;
      parakeet.model = "parakeet-tdt-0.6b-v3";
      whisper =
        {
          model = "large-v3-turbo";
        }
        // lib.optionalAttrs geminiActive {
          mode = "remote";
          remote_endpoint = "http://127.0.0.1:${toString gemini.port}";
          remote_model = gemini.model;
          remote_timeout_secs = 30;
          language = "auto";
        };

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
