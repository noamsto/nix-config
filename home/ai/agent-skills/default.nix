# Third-party Agent Skills, installed into every harness that reads the
# SKILL.md standard (Claude Code, Codex, Cursor) from one pinned catalog.
#
# Locally-authored skills stay where they are: home/ai/claude-code/skills, which
# out-of-store-symlinks them so they're editable without a rebuild. This module
# is only for upstream skills we consume read-only.
{
  osConfig,
  inputs,
  ...
}: {
  imports = [inputs.agent-skills-nix.homeManagerModules.default];

  programs.agent-skills = {
    enable = true;

    # One source per bucket folder rather than one at the repo root. Skill IDs
    # are the path relative to `subdir`, and mkBundle lays the bundle out by ID —
    # a root-level source would yield ~/.claude/skills/engineering/<skill>/, and
    # every harness on disk (and upstream's own installer) keeps skill dirs flat.
    # maxDepth pins that flatness so an upstream reorganisation surfaces as a
    # build failure instead of a silently nested path.
    sources = {
      mattpocock-eng = {
        input = "mattpocock-skills";
        subdir = "skills/engineering";
        filter.maxDepth = 1;
      };
      mattpocock-prod = {
        input = "mattpocock-skills";
        subdir = "skills/productivity";
        filter.maxDepth = 1;
      };
    };

    skills.enable = [
      # Supersedes superpowers:systematic-debugging — organises the whole
      # process around "build a red-capable feedback loop before theorising".
      # Precedence is asserted in CLAUDE.global.md; both are model-invoked and
      # enabledPlugins can't disable a single skill inside a plugin.
      "diagnosing-bugs"
      # Throwaway prototypes: ?variant= UI switcher, or a TUI over a pure
      # reducer for state-model questions.
      "prototype"
      # Deep-module vocabulary (module/interface/depth/seam/adapter) plus the
      # design-it-twice parallel-subagent pattern.
      "codebase-design"
      "grilling"
      # User-invoked upstream (disable-model-invocation), so it can't shadow
      # superpowers:writing-skills by precedence — CLAUDE.global.md bans that
      # one instead, and this is reached by typing it.
      "writing-great-skills"
    ];

    # `link` is load-bearing: it renders as per-file home.file symlinks, while
    # the default `symlink-tree`/`copy-tree` structures rsync --delete the
    # destination — which would wipe the locally-authored skills that
    # claude-code/default.nix symlinks into ~/.claude/skills.
    #
    # dest is spelled out per target because `link` can't expand shell
    # variables: it recovers a `${VAR:-$HOME/x}` fallback by regex and throws
    # outright on the bare `$HOME/...` form that the cursor default uses.
    targets = {
      claude = {
        enable = true;
        structure = "link";
        dest = ".claude/skills";
      };
      cursor = {
        enable = true;
        structure = "link";
        dest = ".cursor/skills";
      };
      # Matches home/ai/default.nix, which only imports ./codex on work.
      codex = {
        enable = osConfig.profile == "work";
        structure = "link";
        dest = ".codex/skills";
      };
    };
  };
}
