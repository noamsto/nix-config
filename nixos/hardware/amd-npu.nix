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

  xrt-plugin-amdxdna-bin = pkgs.callPackage ../../packages/xrt-plugin-amdxdna-bin.nix {};
  xrtPrefix = "${pkgs.xrt}/opt/xilinx/xrt";

  # XRT discovers driver plugins by scanning $XILINX_XRT/lib/ for libxrt_driver_*.so.2.
  # Nix store is read-only, so merge XRT + XDNA plugin into one tree via symlinks.
  xrt-combined = pkgs.runCommand "xrt-combined" {} ''
    mkdir -p $out
    cp -rs ${xrtPrefix}/* $out/
    chmod -R u+w $out/lib
    ln -sf ${xrt-plugin-amdxdna-bin}/lib/libxrt_driver_xdna* $out/lib/
  '';
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

    environment.variables = {
      "XILINX_XRT" = "${xrt-combined}"; # XRT plugin discovery base path
      "XRT_PATH" = "${xrt-combined}"; # used by FastFlowLM and lemonade
    };

    # Note: Add user to video and render groups in host configuration
    # users.users.<username>.extraGroups = [ "video" "render" ];

    # System packages for NPU management
    environment.systemPackages =
      [
        pkgs.pciutils
        pkgs.lshw
        xrt-combined
      ]
      ++ lib.optionals cfg.enableFastFlowLM [
        pkgs.fastflowlm
      ];

    # Lemonade AI server service
    services.lemonade.enable = cfg.enableLemonade;

    # lemond runs as a systemd service with minimal PATH — inject NPU tools
    # and XRT env so it can find flm and the XDNA plugin during backend install.
    systemd.services.lemond.serviceConfig.Environment = mkIf cfg.enableLemonade [
      "XILINX_XRT=${xrt-combined}"
      "XRT_PATH=${xrt-combined}"
      "PATH=${xrt-combined}/bin:${pkgs.fastflowlm}/bin:/run/current-system/sw/bin"
    ];
  };
}
