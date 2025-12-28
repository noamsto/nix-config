{pkgs, ...}: {
  imports = [
    ./networking.nix
    ./nix.nix
    ./locale.nix
    ./bootloader.nix
    ./pc.nix
    ./users.nix
    ./nice-looking-console.nix
    ./aliases.nix
    ./auto-upgrade.nix
    ./clamav.nix
  ];

  users.defaultUserShell = pkgs.fish;

  programs = {
    fish.enable = true;
    dconf.enable = true;
    ssh.startAgent = false; # Explicitly disable to avoid conflicts with GCR SSH agent
    nix-ld = {
      enable = true;
      libraries = with pkgs; [libgit2 sqlite];
    };

    nh = {
      enable = true;
      # weekly cleanup
      clean = {
        enable = true;
        extraArgs = "--keep-since 14d";
      };
      flake = "/home/noams/nix-config";
    };
  };

  security.polkit.enable = true;

  # Increase inotify limits for file-watching tools (Claude Code, VS Code, etc.)
  # With 2M watches (~2GB max memory if all used), plenty of headroom
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 2097152;
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_queued_events" = 65536;
  };

  environment.shells = with pkgs; [fish];

  services = {
    dbus.implementation = "broker";

    # Firmware updates
    fwupd.enable = true;

    # Trim SSD
    fstrim.enable = true;
    fstrim.interval = "daily";

    # Disable logind lid handling - let hyprdynamicmonitors manage it
    logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };
  };

  system.activationScripts.binbash = {
    deps = ["binsh"];
    text = ''
      [ -f /bin/bash ] || ln -s /bin/sh /bin/bash
    '';
  };

  # For RaspberryPi 4 image generating
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
  system.stateVersion = "23.05";
}
