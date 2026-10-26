{
  config,
  lib,
  inputs,
  self,
  ...
}: let
  hostConfig = (import ../../lib/host-configs.nix).tp-g6;
  inherit (import ../../lib/host-configs.nix) sshPublicKeys;
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    self.nixosModules.default
    self.nixosModules.home
    ./agenix.nix
    ./host_secrets.nix
    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen6
    inputs.nix-amd-ai.nixosModules.default
    self.nixosModules.lanzaboote
    self.nixosModules.udev-hwmon
  ];

  # Import shared configuration
  inherit (hostConfig) username user-full-name hostname email laptop-scale;
  flakePath = "/home/${hostConfig.username}/nix-config";
  nix-config = {
    ai = {
      dispatcher.localModels = import ../assets/dispatcher-local-models.nix;
      pi.modelsFile = ../assets/pi/models.json;
    };
    terminal.remoteHosts = ["mbp" "halo"];
    user.hashedPasswordFile = config.age.secrets.noams_password.path;
    shell.hostEnvFile = "/etc/agenix/host_env.env";
    nix.accessTokensFile = config.age.secrets.nixAccessTokens.path;
    desktop = {
      # G6 has no dedicated EasyEffects preset; ArchWiki recommends the G5 set for it.
      # https://wiki.archlinux.org/title/Lenovo_ThinkPad_P14s_(AMD)_Gen_6 → Audio
      easyeffects.preset = "thinkpad-p14s-g5-linux";
      avatar = ../assets/avatar.png;
      monitors.configFile = ../assets/hyprdynamicmonitors/config.toml;
    };
  };
  home-manager.users.${config.username}.imports = [../assets/ssh-fleet.nix];
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

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
    lemonade.user = config.username;
  };

  users.users.noams = {
    # Add user to video/render groups for NPU access
    extraGroups = ["video" "render"];
    # The hosts that bridge into g6 need a way in: the mac,
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

  # Adjust jobs to match actual CPU — Ryzen AI 300 series expected
  nix.settings = {
    max-jobs = 4;
    max-silent-time = 14400;
    timeout = 172800;
  };
}
