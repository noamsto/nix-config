# pi's tool-call guards as a hookyard yard-mode manifest (noamsto/hookyard#67
# decision D2). Replaces the hand-written PI_AGENT_HOOKS transport: hookyard's
# installed bin/hookyard-bridge.ts is now the only pi guard extension, and it
# owns routing, deny-wins consolidation, the per-handler timeout and the
# ask-to-block degrade that the old bridge did by hand.
#
# A plain function rather than a module, so ./default.nix and the flake check
# in ./guards-check.nix name the same store paths.
#
# Wire contract, which is why eight of the ten handlers need no adapter:
# hookyard's normalized envelope already carries `tool_name` mapped to the
# canonical vocabulary (pi's `bash` -> `Bash`), pi's `tool_input` verbatim, and
# `cwd` — exactly the three keys ../agent-hooks' guards read. Handler stdout is
# the same `hookSpecificOutput` shape they already write. Read is the one
# mismatch: pi calls the key `path` where the guards read `file_path`, so the
# path-taking tools (Read, and Grep for secret-read) go through the adapter
# below and nothing else does.
#
# ../claude-code pipes `jq -c .native` in front of the same guard binaries; this
# does not, on purpose. Do NOT unify them onto `.native` here: pi's native
# payload spells the tools `bash`/`read`, so every `[[ $tool_name == "Bash" ]]`
# would stop matching and every Bash guard would abstain, silently.
{
  pkgs,
  dispatcher,
}: let
  guards = import ../agent-hooks {inherit pkgs;};

  # ../claude-code owns its own nix wiring for these two, so they're built
  # separately here rather than shared.
  skeleton-guard = pkgs.writeShellScriptBin "agent-read-skeleton-guard" (builtins.readFile ../claude-code/skeleton-guard.sh);
  psql-guard = pkgs.writeShellScriptBin "agent-psql-guard" (builtins.readFile ../claude-code/psql-guard.sh);

  # Envelope adapter for the path-taking tools, one instance per guard binary
  # (`mkPathAdapter`). Renames pi's `path` to the guards' `file_path` and
  # resolves it the way pi's own read tool does (resolveToCwd -> normalizePath's
  # expandTilde, on by default): `~`/`~/…` expand to the home dir before being
  # resolved against the event cwd. Plain resolution doesn't expand `~`, which
  # would hand the guard a relative-looking path it cannot stat, and a guard
  # that cannot stat abstains — silently.
  #
  # `path` is type-checked because jq's `startswith` is a hard error on a
  # non-string, which `set -e` turns into a non-zero exit — and hookyard reads
  # that as an abstain.
  #
  # jq throughout, reading the envelope on stdin: no JSON value is ever
  # interpolated into the shell. The guard is `exec`d rather than piped to, so
  # hookyard's timeout kills the guard itself instead of leaving it orphaned
  # behind a dead wrapper.
  #
  # This restates pi's resolution rather than asking pi for it: if pi ever
  # resolves `read` paths differently, the guard gets a path it cannot stat and
  # abstains silently, and ./guards-check.nix still passes — it pins this
  # adapter's semantics, not pi's.
  #
  # A leading `@` (pi's `@file` mention syntax) is stripped first, as pi does;
  # left in place, `@.env` would resolve to `<cwd>/@.env` and dodge every
  # anchored secret-path pattern.
  #
  # Grep only needs the `~` expansion plus `output_mode: "content"`: secret-read
  # treats an absent mode as Claude's default (`files_with_matches`, which never
  # prints content) and abstains, but pi's grep always prints the matching lines.
  # Any other tool passes through untouched.
  mkPathAdapter = {
    name,
    guard,
    exe,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.jq guard];
      text = ''
        payload=$(jq -c --arg home "$HOME" '
          def normalize:
            split("/")
            | reduce .[] as $seg ([];
                if $seg == "" or $seg == "." then .
                elif $seg == ".." then .[:-1]
                else . + [$seg] end)
            | "/" + join("/");

          (.tool_input.path) as $raw
          | (if ($raw | type) == "string" then $raw | ltrimstr("@") else "" end) as $path
          | (if $path == "~" then $home
             elif ($path | startswith("~/")) then $home + "/" + $path[2:]
             else $path end) as $expanded
          | if .tool_name == "Grep" then
              {
                tool_name: "Grep",
                tool_input: (.tool_input + {path: $expanded, output_mode: "content"}),
                cwd: .cwd,
              }
            elif .tool_name == "Read" then
              {
                tool_name: "Read",
                tool_input: {
                  file_path: (if ($expanded | startswith("/")) then $expanded
                              else (.cwd // "") + "/" + $expanded end | normalize),
                  offset: .tool_input.offset,
                  limit: .tool_input.limit,
                },
                cwd: .cwd,
              }
            else . end
        ')
        exec ${exe} <<<"$payload"
      '';
    };

  readAdapter = mkPathAdapter {
    name = "agent-pi-read-adapter";
    guard = skeleton-guard;
    exe = "agent-read-skeleton-guard";
  };
  secretReadAdapter = mkPathAdapter {
    name = "agent-pi-secret-read-adapter";
    guard = guards.secret-read-guard;
    exe = "agent-secret-read-guard";
  };

  # Verdict lane (no `lane` key): every one of these can block. 4000ms matches
  # ../claude-code's value for the same guard binaries, under hookyard's 4300ms
  # ceiling. Worth knowing when tuning it: a guard that overruns is recorded as
  # a timeout, which consolidates as abstain — a silent fail-open, not a loud
  # failure.
  piGuard = id: exec: match: {
    inherit id exec match;
    events = ["pre_tool"];
    engines = ["pi"];
    timeout_ms = 4000;
  };

  handlers = [
    (piGuard "guards.pi.git-default-branch" "${guards.git-default-branch-guard}/bin/agent-git-default-branch-guard" ["Bash"])
    (piGuard "guards.pi.nix-stage" "${guards.nix-stage-guard}/bin/agent-nix-stage-guard" ["Bash"])
    (piGuard "guards.pi.read-skeleton" "${readAdapter}/bin/agent-pi-read-adapter" ["Read"])
    # Bash needs no envelope change, so it runs the guard directly: a jq failure
    # in the adapter would exit non-zero, which hookyard reads as an abstain.
    (piGuard "guards.pi.secret-read" "${guards.secret-read-guard}/bin/agent-secret-read-guard" ["Bash"])
    (piGuard "guards.pi.secret-read-paths" "${secretReadAdapter}/bin/agent-pi-secret-read-adapter" ["Read" "Grep"])
    (piGuard "guards.pi.psql" "${psql-guard}/bin/agent-psql-guard" ["Bash"])
    # Advisory-only. pi's tool_call return still can't carry content on allow
    # (a pi platform limit), but hookyard's bridge now delivers the advice
    # anyway: it stashes it at tool_call and appends it onto that call's own
    # tool_result once the call resolves — after the tool's own output and
    # after any post_tool advice (noamsto/hookyard#72, resolved by #75; see
    # docs/design/hookyard.md §11.1). A denial still carries the advice only
    # in its reason, never doubled. Delivery is skipped if the call aborts
    # before it executes, if tool_result content isn't an array, or if a
    # later extension replaces rather than appends content.
    (piGuard "guards.pi.git-commit-autostage" "${guards.git-commit-autostage-guard}/bin/agent-git-commit-autostage-guard" ["Bash"])
    (piGuard "guards.pi.tmux-live-server" "${guards.tmux-live-server-guard}/bin/agent-tmux-live-server-guard" ["Bash"])
    (piGuard "guards.pi.git-identity" "${guards.git-identity-guard}/bin/agent-git-identity-guard" ["Bash"])
    (piGuard "guards.pi.pgrep-self-match" "${guards.pgrep-self-match-guard}/bin/agent-pgrep-self-match-guard" ["Bash"])
  ];

  manifest = pkgs.writeText "pi-guards-hookyard.json" (builtins.toJSON {inherit handlers;});

  # dispatcher's own pi handlers, generated from its own hookyard.json rather
  # than hand-copied (#567). dispatcher declares its pi pre_tool guards and its
  # session_shutdown notify there with exec paths relative to its tree; read
  # that locked file at eval time and render each handler through a store-path
  # wrapper, so a new dispatcher handler arrives with a plain
  # `nix flake update dispatcher` and no nix-config edit.
  dispatcherJson = builtins.fromJSON (builtins.readFile "${dispatcher}/hookyard.json");

  # dispatcher handlers nix-config already provides for pi, by dispatcher id.
  # secret-read-guard: ../agent-hooks' guard is the same family and is what pi
  # already runs (Bash via guards.pi.secret-read, Read/Grep via the path adapter
  # guards.pi.secret-read-paths); the two copies have diverged, so installing
  # dispatcher's as well would double-run two different filters.
  dispatcherExcluded = ["secret-read-guard"];

  # One shared PATH for every dispatcher handler: the union of what the four
  # scripts resolve. Supersedes both hand-written wrappers' PATHs, so no handler
  # loses a binary (notify needs ps/tmux; public-leak needs betterleaks/curl/gh;
  # secret-read needs awk; test-scope needs jq/git).
  dispatcherPath = pkgs.lib.makeBinPath (with pkgs; [
    bash
    jq
    gawk
    gnugrep
    gnused
    coreutils
    findutils
    git
    curl
    gh
    betterleaks
    procps
    tmux
  ]);

  # hookyard resolves `exec` at hook-fire time against the agent's cwd and PATH,
  # so it must be an absolute store path; the dispatcher scripts' `/usr/bin/env`
  # shebang also does not resolve in the check sandbox, hence the explicit bash.
  # `engines` is pinned to pi: claude-code gets these from the dispatcher plugin
  # already, and installing them here too would double-run them there.
  dispatcherHandler = h:
    {
      id = "dispatcher.${h.id}";
      exec = "${
        pkgs.writeShellScriptBin "hookyard-dispatcher-${h.id}" ''
          export PATH=${dispatcherPath}:$PATH
          exec ${pkgs.bash}/bin/bash ${dispatcher}/${h.exec} "$@"
        ''
      }/bin/hookyard-dispatcher-${h.id}";
      inherit (h) events;
      engines = ["pi"];
      match = h.match or [];
    }
    // pkgs.lib.optionalAttrs (h ? lane) {inherit (h) lane;}
    // pkgs.lib.optionalAttrs (h ? timeout_ms) {inherit (h) timeout_ms;};

  dispatcherHandlers =
    builtins.concatMap
    (h: pkgs.lib.optional (!builtins.elem h.id dispatcherExcluded) (dispatcherHandler h))
    (builtins.filter (h: builtins.elem "pi" (h.engines or [])) dispatcherJson.handlers);

  dispatcherManifest =
    pkgs.writeText "hookyard-dispatcher.json" (builtins.toJSON {handlers = dispatcherHandlers;});
in {
  inherit manifest handlers readAdapter dispatcherManifest dispatcherExcluded;
}
