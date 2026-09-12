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
# `manifests` is empty because aeye, the intended first consumer, cannot move
# yet: noamsto/hookyard#27 (no advisory delivery outside `pre_tool`), #28 (no
# fire-and-forget lane, 4300ms handler cap), #29 (the read path below).
{
  config,
  lib,
  inputs,
  ...
}: let
  # From `stateDir`, not `xdg.stateHome`, so repointing the state directory
  # takes this file with it.
  unroutedClaudeSettings = "${config.programs.hookyard.stateDir}/claude-settings.unrouted.json";
in {
  imports = [inputs.hookyard.homeModules.default];

  programs.hookyard = {
    enable = true;

    # Nothing reads this file. hookyard refuses to write through a symlink,
    # and `~/.claude/settings.json` is a `mkOutOfStoreSymlink` onto this repo
    # (../claude-code) — while being Claude Code's only user-scope hook source,
    # its other two being the checkout's `settings.local.json` and the
    # `--settings` file. Pointing at it aborts activation with nothing
    # registered; the two ways to free it both fail silently instead. So a
    # claude-code handler needs #29 settled first, which the warning below
    # says at the moment it would matter.
    claudeSettings = unroutedClaudeSettings;

    # All four destinations get written whether or not the engine is installed,
    # so a personal host gains an empty `~/.codex/config.toml` and the darwin
    # host a `~/.pi/agent/settings.json`. Setting these does not cause that —
    # the defaults name the same paths.
    codexConfig = "${config.home.homeDirectory}/.codex/config.toml";
    cursorHooks = "${config.home.homeDirectory}/.cursor/hooks.json";
    piSettings = "${config.home.homeDirectory}/.pi/agent/settings.json";

    # Generate the manifest (`pkgs.writeText`) with the handler's own store
    # path: `install` stats every `exec`, and a failed stat aborts the switch.
    # Namespace handler ids — `manifest.Merge` errors on a duplicate across
    # manifests, which also aborts. And the order against ../cursor's two
    # entries on the shared `~/.cursor/hooks.json` is undeclared; inert only
    # while this list is empty.
    manifests = [];
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
      assertion =
        lib.count
        (entry: lib.hasInfix "/bin/hookyard install" entry.data)
        (lib.attrValues config.home.activation)
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

  # Not an assertion: `manifests` holds paths, and reading a generated one at
  # eval time would force it to build, so Nix cannot tell a claude-code
  # handler from a cursor-only one. Blocking every consumer over a
  # claude-code-specific problem is worse than warning.
  warnings = lib.optional (config.programs.hookyard.manifests != []) ''
    programs.hookyard: handlers are registered while `claudeSettings` is still
    the unrouted placeholder (${unroutedClaudeSettings}), which no engine
    reads. Any claude-code handler among them will never fire. Repoint
    `claudeSettings` onto Claude Code's real user-scope read path first — see
    noamsto/hookyard#29. Handlers for other engines are unaffected.
  '';
}
