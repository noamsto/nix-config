# AMD XDNA NPU (Neural Processing Unit) Support
# For Ryzen AI 300 series (Strix Point/Krackan) laptops
# Based on: https://github.com/robcohen/nix-amd-npu
#
# This module enables AMD XDNA NPU hardware support for AI inference.
# To actually run AI workloads, you'll need additional software:
#
# 1. Lemonade SDK (recommended): OpenAI-compatible API server
#    - Website: https://lemonade-server.ai/
#    - GitHub: https://github.com/lemonade-sdk/lemonade
#    - Manual install required (not yet in nixpkgs)
#
# 2. FastFlowLM: Direct NPU inference engine
#    - Available via: nix build github:robcohen/nix-amd-npu#fastflowlm
#
# 3. Ryzen AI SDK: Official AMD SDK (proprietary, complex setup)
#    - Website: https://ryzenai.docs.amd.com/
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.hardware.amd-npu;
in {
  options.hardware.amd-npu = {
    enable = mkEnableOption "AMD XDNA NPU support for AI inference acceleration";

    enableFastFlowLM = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install FastFlowLM for LLM inference on NPU.
        Note: Package available via nix-amd-npu flake overlay.
        Run: nix build github:robcohen/nix-amd-npu#fastflowlm
      '';
    };

    enableLemonade = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install Lemonade-AI server for OpenAI-compatible API on NPU.
        Note: Not yet packaged in nixpkgs. Install manually from:
        https://github.com/lemonade-sdk/lemonade
      '';
    };
  };

  config = mkIf cfg.enable {
    # Kernel already has amdxdna driver (6.14+)
    # Just ensure we're using a recent kernel
    assertions = [
      {
        assertion = lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.14";
        message = "AMD NPU requires Linux kernel 6.14 or later. Current: ${config.boot.kernelPackages.kernel.version}";
      }
    ];

    # Required kernel parameters for NPU SVA (Shared Virtual Addressing)
    # Must use IOMMU translated mode, not passthrough
    boot.kernelParams = ["iommu.passthrough=0"];

    # Load amdxdna driver early
    boot.kernelModules = ["amdxdna"];

    # Udev rules for NPU device access
    services.udev.extraRules = ''
      # AMD XDNA NPU device permissions
      SUBSYSTEM=="accel", KERNEL=="amdxdna", MODE="0660", GROUP="video"
      SUBSYSTEM=="misc", KERNEL=="amdxdna", MODE="0660", GROUP="video"
    '';

    # PAM limits for NPU buffer allocation (required for XRT)
    security.pam.loginLimits = [
      {
        domain = "@video";
        type = "soft";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "@video";
        type = "hard";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "@render";
        type = "soft";
        item = "memlock";
        value = "unlimited";
      }
      {
        domain = "@render";
        type = "hard";
        item = "memlock";
        value = "unlimited";
      }
    ];

    # Environment variables for XRT
    environment.variables = {
      # XRT setup
      "XRT_PATH" = "/opt/xilinx/xrt";
    };

    # Note: Add user to video and render groups in host configuration
    # users.users.<username>.extraGroups = [ "video" "render" ];

    # System packages for NPU management
    environment.systemPackages = with pkgs;
      [
        # Basic tools
        pciutils
        lshw
      ]
      ++ lib.optionals cfg.enableFastFlowLM [
        # FastFlowLM will be added via overlay from nix-amd-npu
      ];

    # Note: The actual packages (xrt, fastflowlm, etc.) come from the
    # nix-amd-npu flake overlay, which should be added to nixpkgs.overlays

    # Firmware for NPU
    # hardware.firmware = with pkgs; [ amdxdna-firmware ]; # From nix-amd-npu
  };
}
