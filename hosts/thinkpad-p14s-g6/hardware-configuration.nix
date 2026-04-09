# Placeholder — regenerate on actual hardware with:
#   nixos-generate-config --show-hardware-config
#
# Disko handles disk/filesystem config, so this file only needs
# hardware-specific settings (GPU, firmware, kernel params).
{
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot = {
    # MediaTek mt7925 WiFi needs kernel 6.17+ for out-of-box support
    kernelPackages = pkgs.linuxPackages_latest;

    # Enable thinkpad_acpi fan control for thinkfan
    extraModprobeConfig = ''
      options thinkpad_acpi fan_control=1
    '';

    kernelParams = [
      "amd_pstate=active" # Redundant on 6.17+ (default) but explicit
      "amdgpu.dcdebugmask=0x10" # Fix GPU flickering / panel self-refresh lag
    ];
  };

  # GPU Acceleration — AMD Ryzen AI 300 series iGPU
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        mesa
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };
    amdgpu.initrd.enable = true;
  };

  environment.variables = {
    "VDPAU_DRIVER" = "radeonsi";
    "LIBVA_DRIVER_NAME" = "radeonsi";
  };
}
