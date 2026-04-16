# AMD XDNA NPU (Neural Processing Unit) Support
# For Ryzen AI 300 series (Strix Point/Krackan) laptops
# Driver + udev + PAM limits for NPU access.
# Optional: FastFlowLM (NPU inference) and Lemonade (OpenAI-compatible API server).
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
      description = "Install FastFlowLM for LLM inference on AMD NPU.";
    };

    enableLemonade = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Lemonade server service for OpenAI-compatible local AI API.";
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
        pciutils
        lshw
      ]
      ++ lib.optionals cfg.enableFastFlowLM [
        pkgs.fastflowlm
      ];

    # Lemonade AI server service
    services.lemonade.enable = cfg.enableLemonade;
  };
}
