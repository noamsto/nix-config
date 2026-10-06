{
  lib,
  inputs,
  ...
}: let
  hostConfig = (import ../../lib/host-configs.nix).tp-g6;
  inherit (import ../../lib/host-configs.nix) sshPublicKeys;
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
    inputs.nix-amd-ai.nixosModules.default
    ../../nixos/core/lanzaboote.nix
    ../../nixos/hardware/udev-hwmon.nix
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile laptop-scale;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;
  machine.serverMode = hostConfig.machine.serverMode;

  # Thinkfan configuration
  hardware.thinkpad.thinkfan = {
    enable = true;
    generation = "gen6";
  };

  # AMD AI: NPU inference (FastFlowLM) + GPU inference (ROCm) via Lemonade
  hardware.amd-npu = {
    enable = true;
    enableFastFlowLM = true;
    enableLemonade = true;
    enableROCm = true; # Enable GPU/VRAM utilization
    enableVulkan = true; # Faster decode than ROCm on Strix Point 890M
    lemonade.user = "noams";
  };

  users.users.noams = {
    # Add user to video/render groups for NPU access
    extraGroups = ["video" "render"];
    # g6 runs headless, so the hosts that bridge into it need a way in: the mac,
    # and halo, whose session picker lists tp-g6.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOs/38Sx3/0eq4ZHzy8fS6wNK+NljZEhEN9jtuJ6BR02 noams@nwms-MacBook-Pro.local"
      sshPublicKeys.halo
    ];
  };

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
