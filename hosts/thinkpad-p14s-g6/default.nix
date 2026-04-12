{
  lib,
  pkgs,
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
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen6
  ];

  # Secure Boot with Lanzaboote
  boot = {
    initrd.systemd.enable = true; # Required for TPM unlock
    loader.systemd-boot.enable = lib.mkForce false; # Lanzaboote replaces systemd-boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      autoGenerateKeys.enable = true;
      autoEnrollKeys.enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    sbctl
    tpm2-tools
    # AMD AI SDKs - using flakes until merged into nixpkgs
    lemonade-ai # From PR branch - OpenAI-compatible API for local LLMs on NPU/GPU
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile;
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
  # Your AMD Ryzen AI 300 NPU is now configured and ready!
  #
  # Hardware detected: AMD Strix/Krackan NPU at c5:00.1
  # Kernel driver: amdxdna (already loaded)
  #
  # --- Lemonade SDK (Installed via flake) ---
  # Lemonade provides an OpenAI-compatible API server for your NPU.
  # It wraps FastFlowLM and supports multiple backends.
  #
  # Quick Start:
  #   lemonade backends              # Check available backends (npu, rocm, vulkan, cpu)
  #   lemonade pull Gemma-4-E2B-it   # Download a model
  #   lemonade run Gemma-4-E2B-it   # Run inference on NPU
  #   lemonade launch claude        # Launch with Claude Code
  #
  # API endpoint: http://localhost:13305/v1 (OpenAI-compatible)
  #
  # --- FastFlowLM (from nix-amd-npu flake) ---
  # Lower-level NPU inference engine. Install with:
  #   nix build github:robcohen/nix-amd-npu#fastflowlm
  #
  # --- Ryzen AI SDK (Official AMD) ---
  # Proprietary SDK with hybrid execution. More complex setup.
  # See: https://ryzenai.docs.amd.com/
  #
  # --- Verifying NPU works ---
  #   xrt-smi validate          # Test NPU functionality (after installing xrt)
  #   lspci | grep NPU          # Verify hardware detection
  #   lsmod | grep amdxdna      # Verify driver loaded
  #
  # Note: FastFlowLM models need to be in .flm format for NPU execution.
  # Convert GGUF models or download pre-converted ones from Lemonade hub.
  #
  # Flakes used:
  #   - nix-amd-npu: github:robcohen/nix-amd-npu (FastFlowLM, XRT, drivers)
  #   - lemonade-nixpkgs: github:Videl/nixpkgs/pkg-lemonade-ai-from-unstable
  #     (Remove once PR #498314 is merged into nixpkgs-unstable)
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

  # Allow access to hardware monitoring for btop
  services.udev.extraRules = ''
    SUBSYSTEM=="hwmon", KERNEL=="hwmon*", MODE="0644"
    SUBSYSTEM=="power_supply", MODE="0644"
    SUBSYSTEM=="powercap", MODE="0644"
  '';
}
