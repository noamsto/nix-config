# The reviewer/specialist agent tree shared by Claude Code, Cursor and Codex.
#
# Dispatcher is canonical for every reviewer nix-config does not own
# (`adapters/core/reviewers/*-reviewer.md` in the flake input), so the harness
# agents are generated from it. Claude Code auto-delegates on `description`,
# which is kept with `name`; the dispatcher-only roster-routing frontmatter
# (`globs`, `when`, `shebang`, `aliases`, `fallback`) is dropped and the harness
# pair `tools`/`model` is added. Bodies are unchanged. The hand-written agents
# in ./agents are copied alongside and win a name collision.
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

  toClaudeAgent = text: let
    inherit (splitFrontmatter text) frontmatter body;
    kept = lib.filter (l: lib.hasPrefix "name:" l || lib.hasPrefix "description:" l) frontmatter;
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
