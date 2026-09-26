# hookyard renders one handler table into Claude Code's, Codex's, Cursor's and
# Pi's native hook config in a single `install` pass.
#
# This file owns `enable` and all four engine paths. A consumer contributes
# paths to `programs.hookyard.manifests` and nothing else — never its own
# hookyard input, never its own `hookyard install` entry. hookyard's strip is
# keyed on a marker that does not record which manifest produced a row, so a
# second invocation deletes the first one's rows instead of merging with them.
# The assertion below enforces that.
#
# aeye is one consumer: its `post_tool` handlers are declared in ./aeye.nix
# and contributed below via `manifests`. Its Claude Code registration reaches
# `--settings` through `claudeOverlay.merged`, wired in
# ../claude-code/default.nix, not through a file this module writes.
#
# ../pi is the other: its `pre_tool` guards are declared in ../pi/guards.nix
# and contributed from ../pi/default.nix, which is the same contract seen from
# the consumer's side — a manifest path, nothing more.
{
  config,
  lib,
  osConfig,
  pkgs,
  inputs,
  ...
}: let
  isHalo = osConfig.hostname == "halo";
  aeye = import ./aeye.nix {
    inherit pkgs;
    aeye = inputs.tmux-og.inputs.aeye;
  };
in {
  imports = [inputs.hookyard.homeModules.default];

  programs.hookyard = {
    enable = true;

    # These destinations get written whether or not the engine is installed,
    # so a personal host gains an empty `~/.codex/config.toml` and the darwin
    # host a `~/.pi/agent/settings.json`. Setting these does not cause that —
    # the defaults name the same paths, except for the second pi dir below.
    # Claude Code has no destination string here: its registration reaches it
    # via `claudeOverlay.merged`, wired as an overlay in ../claude-code, not a
    # file hookyard writes directly.
    codexConfig = "${config.home.homeDirectory}/.codex/config.toml";
    cursorHooks = "${config.home.homeDirectory}/.cursor/hooks.json";

    # Both pi settings dirs, and the second one is the security-relevant half:
    # dispatcher launches autonomous pi workers with
    # `PI_CODING_AGENT_DIR=~/.pi/dispatcher-worker` and `--no-approve`, and its
    # seeder merges into that dir's own settings.json rather than inheriting
    # anything from the ambient one. Managing only `.pi/agent` would leave
    # every dispatched worker running ../pi's guards nowhere.
    piSettings = [
      "${config.home.homeDirectory}/.pi/agent/settings.json"
      "${config.home.homeDirectory}/.pi/dispatcher-worker/settings.json"
    ];

    # Generate the manifest (`pkgs.writeText`) with the handler's own store
    # path: `install` stats every `exec`, and a failed stat aborts the switch.
    # Namespace handler ids — `manifest.Merge` errors on a duplicate across
    # manifests, which also aborts. ../cursor's two entries write the same
    # `~/.cursor/hooks.json`, but every writer strips only its own marker, so
    # the order does not matter.
    manifests = [aeye.manifest];
  };

  assertions = [
    {
      # Reading `home.activation` here is safe, for two different reasons:
      # standalone, assertions are checked outside the module fixpoint; under
      # the NixOS and darwin submodules (g6, mbp-m4-pro via ../../home) they
      # are lifted into the system's own assertions and `toplevel` depends on
      # them. If this is ever extended, the edge that would close the loop is
      # an activation entry reaching through `osConfig` into those.
      #
      # It counts one evaluation. halo has two activation paths — standalone
      # and NixOS-embedded — differing in `--router-path`, each installing the
      # binary into the profile it names.
      #
      # `trampolineApps` (mac-app-util) is excluded: reading its `.data`
      # realises an un-substitutable cl-nix-lite derivation, which fails
      # `nix flake check --no-build` on a clean store.
      assertion =
        lib.count
        (entry: lib.hasInfix "/bin/hookyard install" entry.data)
        (lib.attrValues (removeAttrs config.home.activation ["trampolineApps"]))
        == 1;
      message = ''
        programs.hookyard: expected exactly one activation entry invoking
        `hookyard install`, found a different number. A second one deletes the
        first pass's rows rather than merging with them, and those handlers
        stop firing with no error. Contribute paths to
        `programs.hookyard.manifests` instead.
      '';
    }
  ];
  # Always-on viewer for halo's localProxy. Binds 127.0.0.1:7757 only; the
  # proxy is the sole way in. Lingering for the user comes from
  # nixos/core/users.nix, so this runs without a login session.
  systemd.user.services.hookyard-serve = lib.mkIf isHalo {
    Unit.Description = "hookyard serve - hook event viewer";
    Service = {
      ExecStart = "${config.programs.hookyard.package}/bin/hookyard serve --port 7757";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["default.target"];
  };
}
