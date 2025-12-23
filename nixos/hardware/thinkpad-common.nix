{
  pkgs,
  config,
  lib,
  ...
}: let
  isThinkpad = builtins.match "thinkpad-.*" config.hostname != null;
in {
  config = lib.mkIf isThinkpad {
    # Common boot settings for all ThinkPads
    boot = {
      initrd.availableKernelModules = ["nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod"];
      initrd.kernelModules = ["dm-snapshot"];
      kernelModules = ["kvm-amd" "amdgpu"];
      extraModulePackages = [];
      kernelParams = [
        "systemd.gpt_auto=0" # Solve annoying dmesg warning
      ];
      kernel.sysctl."kernel.sysrq" = 502;
    };

    # Common filesystem options
    fileSystems."/boot".options = ["fmask=0022" "dmask=0022"];

    # Common networking
    networking.useDHCP = lib.mkDefault true;

    # Common hardware settings
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
