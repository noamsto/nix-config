{
  pkgs,
  inputs,
  ...
}: let
  hostConfig = (import ../../lib/host-configs.nix).halo;
  inherit (import ../../lib/host-configs.nix) sshPublicKeys;
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./host_secrets.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-pc
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    ../../nixos/core/lanzaboote.nix
    ../../nixos/core/iwd-known-networks.nix
  ];

  inherit (hostConfig) hostname email profile;
  desktop.mode = hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  boot = {
    # Strix Halo (gfx1151) support is still landing upstream; track the newest
    # kernel rather than the LTS default.
    kernelPackages = pkgs.linuxPackages_latest;

    # Lives here, not in hardware-configuration.nix where g5 keeps its
    # equivalent: `nixos-anywhere --generate-hardware-config` overwrites that
    # file during the install, which would silently delete this. `cryptroot`
    # is the name disko gives the LUKS device.
    initrd.luks.devices.cryptroot.crypttabExtraOpts = ["tpm2-device=auto"];

    # The GPU draws from the GTT window, not a fixed BIOS VRAM carve-out, so
    # the BIOS UMA is set to its minimum. ttm defaults pages_limit to
    # totalram/2, which would cap the GPU at 64 GiB of the 128 GiB.
    # pages = GiB * 262144.
    #
    # Deliberately no amdgpu.gttsize: ROCm#5595 warns against setting it
    # together with pages_limit, and pages_limit alone is measured sufficient
    # on a 128 GB Halo (nix-amd-ai README, "GPU memory headroom").
    extraModprobeConfig = ''
      options ttm pages_limit=25165824 page_pool_size=25165824
    '';
  };

  # Weights are large files that get partially rewritten (resumed downloads,
  # in-place quantization), which CoW shatters into thousands of extents and
  # slows every mmap load. The flag only takes on files created after it is
  # set, so it has to land before anything writes into the subvolume.
  systemd.services.models-nodatacow = {
    description = "Disable btrfs CoW on /var/lib/models";
    wantedBy = ["multi-user.target"];
    unitConfig.RequiresMountsFor = "/var/lib/models";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.e2fsprogs}/bin/chattr +C /var/lib/models";
    };
  };

  users.users.noams.openssh.authorizedKeys.keys = [
    sshPublicKeys.noams
  ];

  # Ryzen AI Max+ 395: 16 cores / 32 threads.
  nix.settings = {
    max-jobs = 8;
    cores = 4;
    max-silent-time = 14400;
    timeout = 172800;
  };
}
