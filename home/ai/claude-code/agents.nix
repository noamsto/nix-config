# The reviewer/specialist agent tree shared by Claude Code, Cursor and Codex.
#
# Dispatcher is canonical for every reviewer nix-config does not own
# (`adapters/core/reviewers/*-reviewer.md` in the flake input), so the harness
# agents are generated from it. Claude Code auto-delegates on `description`,
# which is kept with `name`; a non-empty `when:` is folded into it as
# `Use when <when>.`, the rest of the dispatcher-only roster-routing frontmatter
# (`globs`, `shebang`, `aliases`, `fallback`) is dropped and the harness pair
# `tools`/`model` is added. Bodies are unchanged. The hand-written agents in
# ./agents are copied alongside and win a name collision.
{
  pkgs,
  lib,
  dispatcher,
}: let
  upstream = "${dispatcher}/adapters/core/reviewers";
  local = ./agents;

  indexOf = pred: list: let
    go = i: rest:
      if rest == []
      then null
      else if pred (builtins.head rest)
      then i
      else go (i + 1) (builtins.tail rest);
  in
    go 0 list;

  # The first two `---` lines delimit the frontmatter.
  splitFrontmatter = text: let
    afterFirst = lib.tail (lib.splitString "\n" text);
    end = indexOf (l: l == "---") afterFirst;
  in
    if end == null
    then throw "agents.nix: frontmatter has no closing '---'"
    else {
      frontmatter = lib.take end afterFirst;
      body = lib.concatStringsSep "\n" (lib.drop (end + 1) afterFirst);
    };

  # The scalar after `key: ` on a frontmatter line, with one layer of YAML
  # quoting stripped. A double-quoted source keeps its own escapes; a plain or
  # single-quoted source has none, so its literal backslashes are escaped for
  # the double-quoted output.
  frontmatterScalar = key: line: let
    prefix = "${key}: ";
    value = lib.removePrefix prefix line;
    n = builtins.stringLength value;
    escapeBackslash = builtins.replaceStrings ["\\"] ["\\\\"];
  in
    if !(lib.hasPrefix prefix line)
    then null
    else if lib.hasPrefix "\"" value && lib.hasSuffix "\"" value && n >= 2
    then builtins.replaceStrings ["\\\""] ["\""] (builtins.substring 1 (n - 2) value)
    else if lib.hasPrefix "'" value && lib.hasSuffix "'" value && n >= 2
    then escapeBackslash (builtins.replaceStrings ["''"] ["'"] (builtins.substring 1 (n - 2) value))
    else escapeBackslash value;

  escapeQuotes = builtins.replaceStrings ["\""] ["\\\""];

  # Claude Code auto-delegates on `description`, but the trigger lives in the
  # upstream `when:` this transform drops; fold it back in. A trigger already
  # opening with `when`/`only when` keeps its wording.
  addWhen = frontmatter: line: let
    whenLine = lib.findFirst (l: lib.hasPrefix "when:" l) null frontmatter;
    when =
      if whenLine == null
      then null
      else frontmatterScalar "when" whenLine;
    desc = frontmatterScalar "description" line;
    trigger =
      if when == null || when == ""
      then null
      else if lib.hasPrefix "when " when || lib.hasPrefix "only when " when
      then "Use ${when}"
      else "Use when ${when}";
  in
    if
      !(lib.hasPrefix "description:" line)
      || trigger == null
      || desc == null
    then line
    else let
      combined = "${desc} ${trigger}";
    in "description: \"${escapeQuotes (
      if lib.hasSuffix "." combined
      then combined
      else combined + "."
    )}\"";

  toClaudeAgent = text: let
    inherit (splitFrontmatter text) frontmatter body;
    kept = lib.map (addWhen frontmatter) (lib.filter (l: lib.hasPrefix "name:" l || lib.hasPrefix "description:" l) frontmatter);
    head =
      ["---"]
      ++ kept
      ++ [
        ''tools: ["Read", "Grep", "Glob", "Bash"]''
        "model: sonnet"
        "---"
      ];
  in
    lib.concatStringsSep "\n" head + "\n" + body;

  generated = lib.listToAttrs (map (file: {
      name = file;
      value = pkgs.writeText file (toClaudeAgent (builtins.readFile "${upstream}/${file}"));
    })
    (lib.filter (n: lib.hasSuffix "-reviewer.md" n) (builtins.attrNames (builtins.readDir upstream))));

  localAgents = lib.listToAttrs (map (file: {
      name = file;
      value = local + "/${file}";
    })
    (builtins.attrNames (builtins.readDir local)));
in
  pkgs.linkFarm "ai-agents" (lib.mapAttrsToList (name: path: {inherit name path;}) (generated // localAgents))
