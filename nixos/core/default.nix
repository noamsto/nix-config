{
  pkgs,
  config,
  self,
  ...
}: {
  imports = [
    ./networking.nix
    ./nix.nix
    ./locale.nix
    ./bootloader.nix
    ./pc.nix
    ./users.nix
    ./nice-looking-console.nix
    ./auto-upgrade.nix
  ];

  users.defaultUserShell = pkgs.fish;

  programs = {
    fish.enable = true;
    dconf.enable = true;
    ssh = {
      startAgent = false; # Explicitly disable to avoid conflicts with GCR SSH agent
      systemd-ssh-proxy.enable = false; # Nix store ownership (nobody:nogroup) breaks OpenSSH strict permissions
    };
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
      flake = config.flakePath;
    };
  };

  security.polkit.enable = true;

  # NixOS creates pre-sleep.service even when powerDownCommands is empty,
  # causing "Service has no ExecStart" warnings on every suspend
  powerManagement.powerDownCommands = "true";

  # Workaround for Claude Code sandbox TMPDIR bug (#29329):
  # Sandbox sets TMPDIR=/tmp/claude but only creates /tmp/claude-{UID}.
  # Symlink bridges the gap so tools find a writable temp dir.
  systemd.tmpfiles.rules = [
    "L /tmp/claude - - - - /tmp/claude-1000"
  ];

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
      HandleSuspendKey = "ignore";
      # systemd 259: Sleep() D-Bus method defaults to suspend-then-hibernate,
      # which resolves to hybrid-sleep. Override to plain suspend to prevent
      # unexpected hibernation when anything calls Sleep() instead of Suspend().
      SleepOperation = "suspend";
    };
  };

  system = {
    activationScripts.binbash = {
      deps = ["binsh"];
      text = ''
        [ -f /bin/bash ] || ln -s /bin/sh /bin/bash
      '';
    };
    nixos.tags = [
      config.desktop.mode
      config.machine.type
      config.profile
      (self.shortRev or self.dirtyShortRev or "unknown")
    ];
    stateVersion = "23.05";
  };
}
