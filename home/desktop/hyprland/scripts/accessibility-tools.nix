{pkgs, ...}: {
  home.packages = [
    # OCR tool - select area and copy text
    pkgs.normcap
  ];

  services.voxtype = {
    enable = true;
    # Vulkan accelerates the whisper engine; ONNX provides parakeet
    package = pkgs.voxtype.override {
      vulkanSupport = true;
      onnxSupport = true;
    };
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
