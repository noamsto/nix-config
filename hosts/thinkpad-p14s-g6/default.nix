{
  lib,
  inputs,
  ...
}: let
  hostConfig = (import ../../lib/host-configs.nix).thinkpad-p14s-g6;
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    ./host_secrets.nix
    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen6
    ../../nixos/core/lanzaboote.nix
    ../../nixos/hardware/udev-hwmon.nix
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile laptop-scale;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Thinkfan configuration
  hardware.thinkpad.thinkfan = {
    enable = true;
    generation = "gen6";
  };

  # AMD XDNA NPU (Neural Processing Unit) - AI acceleration
  # Provides: LLM inference, Whisper transcription, on-device AI
  # Compatible with: FastFlowLM, Lemonade SDK
  hardware.amd-npu = {
    enable = true;
    # FastFlowLM package is available via nix-amd-npu overlay
    # Install manually: nix build .#legacyPackages.x86_64-linux.fastflowlm
  };

  # Add user to video/render groups for NPU access
  users.users.noams.extraGroups = ["video" "render"];

  # ============================================================================
  # NPU AI USAGE GUIDE
  # ============================================================================
  # Hardware: AMD Ryzen AI 300 NPU (Strix/Krackan at c5:00.1)
  # Driver: amdxdna (loaded by hardware.amd-npu module)
  #
  # --- Lemonade SDK ---
  # OpenAI-compatible API server for local LLMs on NPU/GPU
  #   lemonade backends              # Available backends (npu, rocm, vulkan, cpu)
  #   lemonade pull Gemma-4-E2B-it   # Download a model
  #   lemonade run Gemma-4-E2B-it    # Run inference on NPU
  #   lemonade server                # API at localhost:13305/v1
  #
  # --- FastFlowLM ---
  #   nix build github:robcohen/nix-amd-npu#fastflowlm
  #
  # --- Verify ---
  #   lspci | grep -i npu    # Hardware detection
  #   lsmod | grep amdxdna   # Driver loaded
  #
  # Docs: https://lemonade-server.ai/ | https://ryzenai.docs.amd.com/
  # ============================================================================

  # Btrfs swapfile for hibernate support
  # After install, run: sudo btrfs filesystem mkswapfile --size 32G /swap/swapfile
  # Then uncomment:
  # swapDevices = [{ device = "/swap/swapfile"; }];
  # boot.resumeDevice = "/dev/mapper/cryptroot";
  # boot.kernelParams = [ "resume_offset=<offset>" ];
  # Get offset with: sudo btrfs inspect-internal map-swapfile -r /swap/swapfile

  # Adjust cores/jobs to match actual CPU — Ryzen AI 300 series expected
  nix.settings = {
    max-jobs = 4;
    cores = 4;
    max-silent-time = 14400;
    timeout = 172800;
  };
}
