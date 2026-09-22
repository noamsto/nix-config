# aeye's post_tool handlers (images.sh, diagrams.sh) as a hookyard manifest,
# plus the aeye tree the claude-code, codex and cursor modules load natively.
# A plain function rather than a module, so every importer gets the same
# derivation.
{
  pkgs,
  aeye,
}: let
  # The whole tree: the scripts source lib/, core/ and ../../../core
  # relatively. Every native registration reads one of these hooks.json files,
  # so dropping their post-tool rows leaves session_start native.
  tree = pkgs.runCommand "aeye-hookyard-tree" {} ''
    cp -r ${aeye} $out
    chmod -R u+w $out
    ${pkgs.jq}/bin/jq 'del(.hooks.PostToolUse)' $out/adapters/claude-code/plugin/hooks/hooks.json >$out/adapters/claude-code/plugin/hooks/hooks.json.tmp
    mv $out/adapters/claude-code/plugin/hooks/hooks.json.tmp $out/adapters/claude-code/plugin/hooks/hooks.json
    ${pkgs.jq}/bin/jq 'del(.hooks.PostToolUse)' $out/adapters/codex/plugin/hooks/hooks.json >$out/adapters/codex/plugin/hooks/hooks.json.tmp
    mv $out/adapters/codex/plugin/hooks/hooks.json.tmp $out/adapters/codex/plugin/hooks/hooks.json
    ${pkgs.jq}/bin/jq 'del(.hooks.postToolUse)' $out/adapters/cursor/hooks.json >$out/adapters/cursor/hooks.json.tmp
    mv $out/adapters/cursor/hooks.json.tmp $out/adapters/cursor/hooks.json
  '';

  # hookyard hands a handler its envelope, with the engine's payload verbatim
  # under `.native`; aeye's scripts read the native payload.
  #
  # fire_and_forget refuses `timeout_ms` and never kills its child, so
  # `timeout` stands in for the engine timeout the native hooks had (Cursor's:
  # images 15s, diagrams 60s). Stdout is discarded, so Codex and Cursor lose
  # diagrams.sh's warnings — hookyard has no post_tool advisory slot there.
  fireAndForgetShim = kind: duration: script:
    pkgs.writeShellScriptBin "${kind}.sh" ''
      set -euo pipefail
      ${pkgs.jq}/bin/jq -c .native | exec ${pkgs.coreutils}/bin/timeout -k 5 ${toString duration} ${tree}/${script}
    '';

  fireAndForgetHandler = {
    id,
    engines,
    match,
    exec,
  }: {
    inherit id exec engines match;
    events = ["post_tool"];
    lane = "fire_and_forget";
  };

  # Verdict lane: aeye registers no pi handlers, so this shim is Claude Code
  # only — diagrams.sh's compile-failure/markdown-blank warnings reach the
  # model only this way. Large graphs render for tens of seconds, past the
  # 4.3s verdict deadline, so the render runs detached and the shim forwards
  # its output only if it finishes within 3s. Each side writes its marker
  # (`done` / `abandoned`) before checking the other's, so whichever finishes
  # second cleans up.
  diagramsShimClaude = pkgs.writeShellScriptBin "diagrams.sh" ''
    set -euo pipefail
    payload=$(${pkgs.jq}/bin/jq -c .native)
    dir=$(${pkgs.coreutils}/bin/mktemp -d)
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.bash}/bin/bash -c '
      ${pkgs.coreutils}/bin/timeout -k 5 60 ${tree}/adapters/claude-code/plugin/scripts/diagrams.sh >"$1/part" 2>/dev/null || true
      ${pkgs.coreutils}/bin/mv -f "$1/part" "$1/done"
      [ -e "$1/abandoned" ] && ${pkgs.coreutils}/bin/rm -rf "$1"
    ' _ "$dir" <<<"$payload" >/dev/null 2>&1

    for _ in $(${pkgs.coreutils}/bin/seq 30); do
      if [ -e "$dir/done" ]; then
        ${pkgs.coreutils}/bin/cat "$dir/done"
        ${pkgs.coreutils}/bin/rm -rf "$dir"
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done

    : >"$dir/abandoned"
    if [ -e "$dir/done" ]; then
      ${pkgs.coreutils}/bin/cat "$dir/done"
      ${pkgs.coreutils}/bin/rm -rf "$dir"
    fi
  '';

  imagesShimClaude = fireAndForgetShim "images" 15 "adapters/claude-code/plugin/scripts/images.sh";
  imagesShimCodex = fireAndForgetShim "images" 15 "adapters/codex/plugin/scripts/images.sh";
  diagramsShimCodex = fireAndForgetShim "diagrams" 60 "adapters/codex/plugin/scripts/diagrams.sh";
  imagesShimCursor = fireAndForgetShim "images" 15 "adapters/cursor/scripts/images.sh";
  diagramsShimCursor = fireAndForgetShim "diagrams" 60 "adapters/cursor/scripts/diagrams.sh";

  manifest = pkgs.writeText "aeye-hookyard.json" (builtins.toJSON {
    handlers = [
      (fireAndForgetHandler {
        id = "aeye-images-claude-code";
        exec = "${imagesShimClaude}/bin/images.sh";
        engines = ["claude-code"];
        match = [];
      })
      {
        # Verdict lane (default — no `lane` key here): see diagramsShimClaude above.
        id = "aeye-diagrams-claude-code";
        exec = "${diagramsShimClaude}/bin/diagrams.sh";
        events = ["post_tool"];
        engines = ["claude-code"];
        match = [];
        timeout_ms = 4300;
      }
      (fireAndForgetHandler {
        id = "aeye-images-codex";
        exec = "${imagesShimCodex}/bin/images.sh";
        engines = ["codex"];
        match = ["Read" "Write" "Bash"];
      })
      (fireAndForgetHandler {
        id = "aeye-diagrams-codex";
        exec = "${diagramsShimCodex}/bin/diagrams.sh";
        engines = ["codex"];
        match = ["Write"];
      })
      (fireAndForgetHandler {
        id = "aeye-images-cursor";
        exec = "${imagesShimCursor}/bin/images.sh";
        engines = ["cursor"];
        match = ["Read" "Write" "Bash"];
      })
      (fireAndForgetHandler {
        id = "aeye-diagrams-cursor";
        exec = "${diagramsShimCursor}/bin/diagrams.sh";
        engines = ["cursor"];
        match = ["Write" "Bash"];
      })
    ];
  });
in {
  inherit tree manifest;
}
