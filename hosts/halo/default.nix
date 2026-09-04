{
  config,
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
    inputs.nix-amd-ai.nixosModules.default
    ../../nixos/steam-console
  ];

  inherit (hostConfig) hostname email profile;
  desktop.mode = hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;
  machine.serverMode = hostConfig.machine.serverMode;

  # Couch console on the TV. Runs as its own unprivileged user, so autologin
  # never reaches noams's SSH keys, sudo, or the agents.
  steamConsole.enable = true;

  boot = {
    # Strix Halo (gfx1151) support is still landing upstream; track the newest
    # kernel rather than the LTS default.
    kernelPackages = pkgs.linuxPackages_latest;

    # Lives here, not in hardware-configuration.nix where g5 keeps its
    # equivalent: `nixos-anywhere --generate-hardware-config` overwrites that
    # file during the install, which would silently delete this. `cryptroot`
    # is the name disko gives the LUKS device.
    initrd.luks.devices.cryptroot.crypttabExtraOpts = ["tpm2-device=auto"];
  };

  hardware.amd-npu = {
    enable = true;
    gpuTarget = "gfx1151"; # Strix Halo; the module default is gfx1150 (Strix Point)
    enableROCm = true;
    enableVulkan = true;
    enableLemonade = true;

    # On deliberately, both here and by default: halo is the only npu5 (rev 0x11)
    # host, and nix-amd-ai's Halo checklist has npu5-on-FLM-1.0.3 as an unfilled
    # cell - 0.9.43 is confirmed, 1.0.3 is not. Turning these off would skip the
    # one measurement this box exists to provide.
    enableNPU = true;
    enableFastFlowLM = true;

    # The GPU draws from the GTT window, not a fixed BIOS VRAM carve-out, so the
    # BIOS UMA is set to its minimum. ttm defaults pages_limit to totalram/2,
    # which would cap the GPU at 64 GiB of the 128 GiB.
    #
    # Deliberately no amdgpu.gttsize: ROCm#5595 warns against setting it together
    # with pages_limit, and pages_limit alone is measured sufficient on a 128 GB
    # Halo (nix-amd-ai README, "GPU memory headroom").
    #
    # 104, not the README's 96: at 96 ds4-server cannot load
    # DeepSeek-V4-Flash at all. It fills 91.2 GiB, then reports
    # `free=4.80 GiB reserve=4.80 GiB total=96.00 GiB` and dies with `ROCm
    # tensor alloc failed: out of memory` — it refuses to spend its own
    # reserve, so 96 really means 91.2 GiB usable against an 80.76 GiB model
    # plus ~10 GiB of mappings. Measured identical with lemond stopped, so this
    # is a sizing floor, not contention. 104 is sized for ds4 alone — see the
    # ds4-server override below for why the two servers never share the box.
    gpuMemory = {
      ttmSizeGiB = 104;
      pagePoolSizeGiB = 104;
    };

    lemonade = {
      user = "noams";
      # Headless: skips the Tauri shell's Rust + npm build entirely.
      desktopApp.enable = false;

      # Reachable from the ThinkPads. Safe only because the port stays out of
      # allowedTCPPorts and tailscale0 is a trusted interface
      # (nixos/services/tailscale.nix), so the tailnet reaches it and the LAN
      # does not. Binding tailscale0's address directly would instead race
      # tailscaled at boot. The endpoint is unauthenticated; lemond reads
      # LEMONADE_API_KEY if the firewall ever stops being enough.
      host = "0.0.0.0";
      # A non-loopback host with no origins makes browsers on other machines
      # get a 403, so every name the ThinkPads might use is listed.
      allowedOrigins = [
        "http://halo:13305"
        "http://halo.tail68e513.ts.net:13305"
        "http://100.92.49.55:13305"
      ];

      # Deliberately short. g6's 16-model set is entirely imperative and
      # undocumented; most of it exists because g6 is RAM-constrained, which
      # halo is not. Grow this once the pair is trusted.
      # pruneUnlistedModels already defaults false, so hand-pulled models used
      # for benchmarking survive a rebuild.
      models = [
        "Qwen3.5-4B-GGUF" # 3.58 GB, for cheap tasks
        "Qwen3-Coder-30B-A3B-Instruct-GGUF" # 18.6 GB, proven on g6
      ];
      # Without this both caches land in ~/.cache on @home, which is
      # compress=zstd and CoW - 157 GB of weights on the wrong subvolume.
      cacheDir = "/var/lib/models";

      # Games and lemond both draw from the same GTT pool. auto_evict unloads
      # idle models under memory pressure and reloads on the next request, so a
      # game does not need the endpoint stopped. Unverified whether this
      # observes a game's allocations specifically — see the plan's Task 5
      # measurement; if it does not, stop lemond before gaming, as with ds4.
      settings.auto_evict = true;
    };

    # lemond and ds4 cannot both hold weights on this box: 80.76 GiB + ~11 GiB
    # leaves nothing for page cache and both endpoints stop answering. lemond
    # wins the boot because the ThinkPads point at it all day; `systemctl start
    # ds4-server` takes the machine over and gives it back on stop.
    exclusiveInference = true;

    # A second server: ds4 is antirez's DeepSeek-V4-only engine, not a generic
    # GGUF runner, and its ROCm backend targets gfx1151 alone. A sibling of
    # lemonade rather than a child, so neither unit's failure touches the other.
    ds4 = {
      enable = true;
      autoStart = false;
      user = "noams";
      # Upstream STRIXHALO.md names this exact build. Deliberately not one of
      # unsloth's UD-* dynamic quants: the same doc warns the mixed IQ2/IQ4 and
      # IQ2/Q4 GGUFs put far more pressure on the ROCm path and can take the
      # system OOM rather than fail cleanly. 80.76 GiB, and the one measured in
      # nix-amd-ai's README on this hardware.
      model = "/var/lib/models/gguf/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix.gguf";
      # Same posture as lemond: reachable on the tailnet, dropped on the LAN
      # because 8000 stays out of allowedTCPPorts.
      host = "0.0.0.0";
      # ctx left at the engine default (32768). At 104 GiB the model loads with
      # fp16 kernels retained, so there is headroom now — but nothing has
      # measured what raising it costs, so it stays where the engine puts it.
      #
      # No --ssd-streaming either: that exists for models too large for GTT, and
      # this one fits. Adding it would trade memory bandwidth for NVMe reads to
      # solve a problem we do not have.
    };
  };

  systemd = {
    services = {
      # Weights are large files that get partially rewritten (resumed downloads,
      # in-place quantization), which CoW shatters into thousands of extents and
      # slows every mmap load. The flag only takes on files created after it is
      # set, so it has to land before anything writes into the subvolume.
      models-nodatacow = {
        description = "Disable btrfs CoW on /var/lib/models";
        wantedBy = ["multi-user.target"];
        unitConfig.RequiresMountsFor = "/var/lib/models";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.e2fsprogs}/bin/chattr +C /var/lib/models";
        };
      };

      # Same rationale as models-nodatacow: game files are partially rewritten
      # by updates, which CoW shatters into extents. Must land before Steam
      # writes anything, since the flag only affects files created after it.
      games-nodatacow = {
        description = "Disable btrfs CoW on /var/lib/games";
        wantedBy = ["multi-user.target"];
        unitConfig.RequiresMountsFor = "/var/lib/games";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.e2fsprogs}/bin/chattr +C /var/lib/games";
        };
      };
    };

    # disko creates the subvolumes as root:root. Split by consumer: lemond's two
    # caches, and the plain GGUFs ds4-server reads. They inherit the parent's
    # nodatacow flag.
    tmpfiles.rules = [
      "d /var/lib/models 0755 noams users -"
      "d /var/lib/models/hf 0755 noams users -"
      "d /var/lib/models/lemonade 0755 noams users -"
      "d /var/lib/models/gguf 0755 noams users -"
      "d /var/lib/games 0700 ${config.steamConsole.user} users -"
    ];
  };

  users.users.noams = {
    # lemond's unit sets no SupplementaryGroups, unlike ds4-server's.
    extraGroups = ["video" "render"];
    openssh.authorizedKeys.keys = [
      sshPublicKeys.noams
    ];
  };

  # Ryzen AI Max+ 395: 16 cores / 32 threads.
  nix.settings = {
    max-jobs = 8;
    cores = 4;
    max-silent-time = 14400;
    timeout = 172800;
  };
}
