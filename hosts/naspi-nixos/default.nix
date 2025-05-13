{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./boot-loader
    ./disks.nix
    ./default.nix
    ./base.nix
  ];

  boot = {
    loader = {
      grub.enable = false;
    };

    # consoleLogLevel = lib.mkDefault 7;
    kernelParams = [
      "console=tty1"
      # https://github.com/raspberrypi/firmware/issues/1539#issuecomment-784498108
      "console=serial0,115200n8"
    ];

    kernelPackages = pkgs.linuxPackagesFor pkgs.rpi-kernels.v6_12_17.bcm2711;
    # kernelPackages = pkgs.linuxPackages_rpi4;
    initrd.availableKernelModules = [
      "pcie_brcmstb" # required for the pcie bus to work
      "reset-raspberrypi" # required for vl805 firmware to load
      "usb_storage"
      "usbhid"
      "vc4"
    ];
  };

  environment = {
    etc."nixos".source = "/persistent/nixos";

    systemPackages = with pkgs; [
      nnn
      xplr
    ];
  };

  hardware.enableRedistributableFirmware = true;

  home-manager.users.pi = import ./pi.nix;

  nixpkgs = {
    hostPlatform = "aarch64-linux";
    overlays = [inputs.raspberry-pi-nix.overlays.core];
  };

  nix.settings.flake-registry = "";

  raspberry-pi = {
    loader.enable = true;
  };

  services = {
    sshd.enable = true;
    openssh.settings.PermitRootLogin = "yes";
  };

  system = {
    configFlake = inputs.self;
    dependOnConfigFlakeInputClosure = true;
    stateVersion = "24.05";
  };

  users.users = {
    pi = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      password = "nixos";
    };
  };
}
