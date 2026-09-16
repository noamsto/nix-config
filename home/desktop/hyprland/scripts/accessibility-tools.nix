{
  inputs,
  pkgs,
  ...
}: {
  home.packages = [
    # OCR tool - select area and copy text
    pkgs.normcap
    # Streaming dictation, complementing voxtype's push-to-talk
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.sherpa-dictate
  ];

  services.voxtype = {
    enable = true;
    # Vulkan accelerates the whisper engine; ONNX provides parakeet
    package =
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
        cargoBuildFeatures = old.cargoBuildFeatures ++ ["osd-gtk4"];
        cargoCheckFeatures = old.cargoCheckFeatures ++ ["osd-gtk4"];
        buildInputs = old.buildInputs ++ [pkgs.gtk4 pkgs.gtk4-layer-shell];
        nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.wrapGAppsHook4];
      });
    # Also puts wtype + wl-clipboard on the service PATH for text injection
    wayland.display = "wayland-1";
    loadModels = ["parakeet-tdt-0.6b-v3"];
    settings = {
      engine = "parakeet";
      # Recording is driven by the Hyprland keybind, not voxtype's evdev listener
      hotkey.enabled = false;
      parakeet.model = "parakeet-tdt-0.6b-v3";
      whisper.model = "large-v3-turbo";
    };
  };
}
