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

    # XRT wrapper scripts (xrt-smi etc.) resolve "unwrapped/loader" relative to
    # their own directory.  NixOS merges flat symlinks into /run/current-system/sw/bin
    # which breaks the relative lookup for unwrapped/.  Add the store's original
    # bin/ to PATH so wrappers run from their real location and find loader.
    environment.variables = {
      "XRT_PATH" = "${pkgs.xrt}/opt/xilinx/xrt";
    };
    # Note: Add user to video and render groups in host configuration
    # users.users.<username>.extraGroups = [ "video" "render" ];

    # System packages for NPU management
    # xrt-bin-path re-links XRT binaries with the unwrapped/ subdir intact so
    # wrapper scripts (xrt-smi) can find the loader at ../unwrapped/loader.
    environment.systemPackages = let
      xrt-bin-path = pkgs.runCommand "xrt-bin-path" {} ''
        mkdir -p $out/bin
        for f in ${pkgs.xrt}/opt/xilinx/xrt/bin/*; do
          [ -f "$f" ] && ln -s "$f" $out/bin/
        done
        ln -s ${pkgs.xrt}/opt/xilinx/xrt/bin/unwrapped $out/bin/unwrapped
      '';
    in
      [
        pkgs.pciutils
        pkgs.lshw
        xrt-bin-path
        pkgs.xrt-plugin-amdxdna
      ]
      ++ lib.optionals cfg.enableFastFlowLM [
        pkgs.fastflowlm
      ];

    # Lemonade AI server service
    services.lemonade.enable = cfg.enableLemonade;
  };
}
