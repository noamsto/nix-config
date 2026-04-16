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

  # XRT discovers driver plugins by scanning $XILINX_XRT/lib/ for libxrt_driver_*.so.2.
  # Since the Nix store is read-only, create a merged directory containing XRT's libs
  # plus the XDNA plugin so both are found in a single lookup path.
  xrt-combined = pkgs.runCommand "xrt-combined" {} ''
    mkdir -p $out/lib $out/bin

    # Symlink all XRT libs
    for f in ${pkgs.xrt}/opt/xilinx/xrt/lib/*; do
      ln -s "$f" $out/lib/
    done

    # Add the XDNA plugin alongside XRT's libs
    ln -sf ${xrt-plugin-amdxdna-bin}/lib/libxrt_driver_xdna.so.2.21.75 $out/lib/
    ln -sf libxrt_driver_xdna.so.2.21.75 $out/lib/libxrt_driver_xdna.so.2

    # Symlink XRT binaries with unwrapped/ subdir intact
    for f in ${pkgs.xrt}/opt/xilinx/xrt/bin/*; do
      [ -f "$f" ] && ln -s "$f" $out/bin/
    done
    ln -s ${pkgs.xrt}/opt/xilinx/xrt/bin/unwrapped $out/bin/unwrapped

    # Symlink other XRT dirs (include, share, firmware, etc.)
    for d in ${pkgs.xrt}/opt/xilinx/xrt/*; do
      name=$(basename "$d")
      [ "$name" = "lib" ] || [ "$name" = "bin" ] && continue
      ln -s "$d" $out/"$name"
    done
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

    # XILINX_XRT tells XRT where to find its libs and plugins.
    # xrt-combined merges XRT libs + XDNA plugin in one directory.
    environment.variables = {
      "XILINX_XRT" = "${xrt-combined}";
      "XRT_PATH" = "${xrt-combined}";
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
  };
}
