{
  inputs,
  lib,
  pkgs,
  ...
}: let
  voxtype =
    (pkgs.voxtype.override {
      vulkanSupport = true;
      onnxSupport = true;
    })
    .overrideAttrs (old: {
      # nixpkgs enables no OSD feature, so the recording indicator never
      # renders. Drop once nixpkgs grows an osdSupport flag.
      #
      # buildRustPackage snapshots buildFeatures into cargo*Features at call
      # time and the cargo hooks read only those — appending to buildFeatures
      # here builds green and silently omits the binary.
      #
      # gtk4 stays built as the launcher's fallback: it substitutes
      # automatically if the quickshell frontend cannot start.
      cargoBuildFeatures = old.cargoBuildFeatures ++ ["osd-gtk4"];
      cargoCheckFeatures = old.cargoCheckFeatures ++ ["osd-gtk4"];
      buildInputs = old.buildInputs ++ [pkgs.gtk4 pkgs.gtk4-layer-shell];
      nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.wrapGAppsHook4];
    });
in {
  home.packages = [
    # OCR tool - select area and copy text
    pkgs.normcap
    # Streaming dictation, complementing voxtype's push-to-talk
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.sherpa-dictate
  ];

  services.voxtype = {
    enable = true;
    # Vulkan accelerates the whisper engine; ONNX provides parakeet
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
        # Literal Catppuccin Mocha rather than palette = "omarchy": that path
        # reads ~/.config/omarchy/current/theme/colors.toml, which this host
        # does not have. Values mirror noctalia-colors.conf ($primary/$error/
        # $surface), so the OSD matches the rest of the desktop in dark mode.
        palette = "custom";

        frame = {
          border = "none";
          background = "#1e1e2e";
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
            color = "#cba6f7";
            mirror = true;
            order = 10;
          }
          {
            type = "icon";
            source = "state";
            color = "#f38ba8";
            order = 20;
          }
        ];
      };
    };
  };
}
