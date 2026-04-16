{
  lib,
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
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen6
    ../../nixos/core/lanzaboote.nix
    ../../nixos/hardware/udev-hwmon.nix
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile laptop-scale;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Thinkfan configuration
  hardware.thinkpad.thinkfan = {
    enable = true;
    generation = "gen6";
  };

  # AMD XDNA NPU (Neural Processing Unit) - AI acceleration
  # Provides: LLM inference, Whisper transcription, on-device AI
  hardware.amd-npu = {
    enable = true;
    enableFastFlowLM = true;
    enableLemonade = true;
  };

  # Add user to video/render groups for NPU access
  users.users.noams.extraGroups = ["video" "render"];

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
