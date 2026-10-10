{
  config,
  pkgs,
  ...
}: let
  flake = config.programs.nh.flake;

  buildHead = pkgs.writeShellApplication {
    name = "nixos-upgrade-build";
    runtimeInputs = [pkgs.gitMinimal config.nix.package];
    text = ''
      # Committed HEAD only: an unattended switch must not pick up uncommitted edits.
      rev=$(git -C ${flake} rev-parse HEAD)
      exec nix build --no-link --print-out-paths --print-build-logs \
        "git+file://${flake}?rev=$rev#nixosConfigurations.${config.networking.hostName}.config.system.build.toplevel"
    '';
  };

  switchAsOwner = pkgs.writeShellApplication {
    name = "switch-as-owner";
    runtimeInputs = [pkgs.util-linux config.nix.package];
    text = ''
      # Root can't open the owner's checkout (libgit2 "not owned by current
      # user") and has no key for private inputs, so "$@" runs as the owner and
      # only the store path it prints comes back. The lock serialises switches;
      # it is root-only and kept from the owner's build so no other uid can hold it.
      umask_was=$(umask)
      umask 077
      exec 9>>/run/switch-as-owner.lock
      umask "$umask_was"
      flock -n 9 || { echo "switch-as-owner: waiting for another switch to finish" >&2; flock 9; }
      path=$(runuser -u ${config.username} -- "$@" 9>&-)
      [[ $path =~ ^/nix/store/[^/]+$ ]] || { echo "switch-as-owner: refusing store path: $path" >&2; exit 1; }
      [[ -x $path/bin/switch-to-configuration ]] || { echo "switch-as-owner: no switch-to-configuration in $path" >&2; exit 1; }
      nix-env -p /nix/var/nix/profiles/system --set "$path"
      exec "$path/bin/switch-to-configuration" switch
    '';
  };
in {
  system.build.switchAsOwner = switchAsOwner;

  systemd.services.nixos-upgrade = {
    description = "Build the flake checkout as its owner and switch to it";
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    wants = ["network-online.target"];
    after = ["network-online.target"];
    environment = config.nix.envVars // config.networking.proxy.envVars;
    # nix shells out to git and ssh for git+ssh inputs.
    path = [pkgs.coreutils pkgs.gitMinimal config.programs.ssh.package];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${switchAsOwner}/bin/switch-as-owner ${buildHead}/bin/nixos-upgrade-build";
    };
    startAt = "Sun 03:00";
  };

  systemd.timers.nixos-upgrade.timerConfig = {
    RandomizedDelaySec = "45min";
    Persistent = true;
  };
}
