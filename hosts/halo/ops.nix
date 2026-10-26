{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  polkit = import ./ops-polkit.nix {inherit lib;};

  stateDir = "/var/lib/halo-ops";
  requestDir = "/run/halo-ops";

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
      config.system.build.switchAsOwner
    ];
    runtimeEnv = {
      FLAKE = config.flakePath;
      LEMOND_PORT = toString config.hardware.amd-npu.lemonade.port;
      LOCK_COMMIT_FILTER = "${self.lib.files.lock-commit-jq}";
      OPS_REQUESTS = requestDir;
      OPS_STATE = stateDir;
    };
    text = builtins.readFile ./ops.sh;
  };

  completions = pkgs.runCommand "halo-ops-completions" {} ''
    install -Dm444 ${import self.lib.files.halo-completions {
      inherit pkgs;
      command = "halo-ops";
      flake = config.flakePath;
    }} $out/share/fish/vendor_completions.d/halo-ops.fish
  '';

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
  options.haloOps = {
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = ops;
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = stateDir;
      description = "Gated update candidate; readable by the halo-ops group, writable only by the checkout owner.";
    };
    requestDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = requestDir;
      description = "Inputs for the next update-prepare, writable by the halo-ops group; the unit validates them.";
    };
  };

  config = {
    environment.systemPackages = [ops completions];

    users.groups.halo-ops = {};
    users.users.${config.username}.extraGroups = ["halo-ops"];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 ${config.username} halo-ops -"
      "d ${requestDir} 2770 ${config.username} halo-ops -"
    ];

    security.polkit.extraConfig = polkit.rule;

    systemd.services = {
      # Fast-forwards the checkout, then builds and switches via switch-as-owner.
      # What gets built is still decided by noams's checkout and git/nix config:
      # this trusts the noams uid exactly as far as nix trusted-users (@wheel)
      # already does.
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
  };
}
