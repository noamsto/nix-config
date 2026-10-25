# deja-vu's session-start digest, delivered through hookyard's existing advisory
# contract. This is the whole integration: one `session_start` handler that runs
# `deja hook-context`, whose stdout is already hookyard's handler wire protocol
# (`hookSpecificOutput.additionalContext`), fence included.
#
# Deliberately NOT `deja install`: that writes engine hook configs directly and
# would fight home-manager. hookyard owns the registration of every engine.
#
# Fail-open is upstream's: `deja hook-context` always exits 0, returns empty
# `additionalContext` when there is no index (triggering a detached build), and
# hookyard reads an empty stdout or a killed timeout as an abstain.
#
# Index freshness: no systemd timer / launchd agent. deja already refreshes
# lazily on the exact path that needs it — `cachedHookDigestFor` requests a
# detached warmup when the manifest is missing/stale/damaged, and a detached
# `index.Ensure` when the cached digest is older than its 60s TTL
# (cmd/deja/hook_context.go). A timer would duplicate that and burn CPU when no
# agent is running.
{
  lib,
  pkgs,
  inputs,
  ...
}: let
  deja = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.deja-vu;

  # hookyard's handler manifest has no `env` field (internal/manifest), so the
  # non-negotiable knobs travel in the handler's own exec. This is not
  # belt-and-braces: a GUI-launched agent never sources a shell profile, and
  # `DEJA_EMBED_OFF` there is the difference between a local index and an
  # embedding request. `exec` keeps hookyard's stdin (the envelope) and stdout
  # (the digest) intact.
  dejaHook = pkgs.writeShellApplication {
    name = "deja-hook-context";
    runtimeInputs = [deja];
    text = ''
      export DEJA_EMBED_OFF=1
      exec ${lib.getExe deja} hook-context
    '';
  };

  manifest = pkgs.writeText "deja-vu-hookyard.json" (builtins.toJSON {
    handlers = [
      {
        id = "deja.session-digest";
        exec = "${dejaHook}/bin/deja-hook-context";
        events = ["session_start"];
        # Cursor is registered but hookyard has no standalone `session_start`
        # advisory on it (HasAdvisorySlot(Cursor) == HasDecisionSlot == false),
        # so today the digest is delivered on Claude Code, Codex and Pi. Cursor
        # sessions are still indexed by deja's native Cursor loader and recalled
        # into the other engines. A hookyard gap, tracked as a follow-up.
        engines = ["claude-code" "codex" "cursor" "pi"];
        match = [];
        timeout_ms = 4000;
      }
    ];
  });
in {
  # ../hookyard owns `enable` and the install pass; this contributes a path and
  # nothing else.
  programs.hookyard.manifests = [manifest];

  home = {
    packages = [deja];

    # The index stays lexical: nothing is sent to an embedding endpoint.
    sessionVariables.DEJA_EMBED_OFF = "1";
  };
}
