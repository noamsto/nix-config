{
  config,
  lib,
  pkgs,
  ...
}: let
  polkit = import ./ops-polkit.nix {inherit lib;};

  ops = pkgs.writeShellApplication {
    name = "halo-ops";
    runtimeInputs = [
      pkgs.git
      config.nix.package
      pkgs.openssh
      pkgs.coreutils
      pkgs.jq
      pkgs.curl
      pkgs.systemd
      pkgs.gnugrep
      pkgs.gawk
      pkgs.git-lfs
      pkgs.util-linux
    ];
    runtimeEnv = {
      FLAKE = config.flakePath;
      LEMOND_PORT = toString config.hardware.amd-npu.lemonade.port;
      LOCK_COMMIT_FILTER = "${../../home/terminal/fish/lock-commit.jq}";
      OPS_STATE = "/var/lib/halo-ops";
      OPS_USER = config.username;
    };
    text = builtins.readFile ./ops.sh;
  };

  # restartIfChanged = false: a switch must never kill a running action
  # (halo-rebuild is itself what performs the switch).
  oneshot = {
    restartIfChanged = false;
    serviceConfig.Type = "oneshot";
  };

  asUser = {
    User = config.username;
    Group = "users";
  };
in {
  environment.systemPackages = [ops];

  systemd.tmpfiles.rules = ["d /var/lib/halo-ops 0750 ${config.username} users -"];

  security.polkit.extraConfig = polkit.rule;

  systemd.services = {
    # Builds as the checkout owner (root can't open the noams-owned checkout:
    # libgit2 "not owned by current user"; root has no GitHub key for
    # mysecrets), then switches as root in the same process, so the store path
    # never passes through a noams-writable file. What gets built is still
    # decided by noams's checkout and git/nix config: this trusts the noams uid
    # exactly as far as nix trusted-users (@wheel) already does.
    halo-rebuild =
      oneshot
      // {
        description = "Fast-forward the flake checkout, build and switch halo";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = oneshot.serviceConfig // {ExecStart = "${ops}/bin/halo-ops _rebuild-unit";};
      };

    halo-update-prepare =
      oneshot
      // {
        description = "Update flake inputs and gate the result without committing";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig =
          oneshot.serviceConfig
          // asUser
          // {ExecStart = "${ops}/bin/halo-ops _update-prepare-unit";};
      };

    halo-update-push =
      oneshot
      // {
        description = "Commit and push the gated flake.lock candidate";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig =
          oneshot.serviceConfig
          // asUser
          // {ExecStart = "${ops}/bin/halo-ops _update-push-unit";};
      };

    halo-reboot =
      oneshot
      // {
        description = "Reboot halo";
        serviceConfig = oneshot.serviceConfig // {ExecStart = "${pkgs.systemd}/bin/systemctl reboot";};
      };
  };
}
