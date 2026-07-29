# Global Claude Code Instructions

Claude-Code-specific guidance only — its settings layering, tools, skills, and
hooks. Engine-neutral conventions live in `AGENTS.shared.md`, imported below.

## Claude Code Settings Architecture

Settings are split into two layers. **Never mix them.**

| Layer | File | Owns | Writable |
|-------|------|------|----------|
| `settings.json` | `home/ai/claude-code/settings.json` (symlinked to `~/.claude/settings.json`) | permissions, plugins, theme, sandbox, mcpServers, preferences — everything that's plain JSON | Yes (third-party tools and UI can edit) |
| `--settings` overlay | Nix-generated via `nix-settings-json` in `home/ai/claude-code/default.nix` | hooks, statusLine (keys that reference `/nix/store` paths), and **profile-gated `enabledPlugins`** | No (read-only, rebuilt by Nix) |

**Rules:**
- If a setting needs a nix store path → `--settings` overlay (default.nix)
- If a setting must differ by `osConfig.profile` (work vs personal) → `--settings` overlay, gated with `lib.optionalAttrs`
- Everything else → `settings.json`
- Object-valued keys (`enabledPlugins`, `permissions`, `env`, `mcpServers`, `hooks`) **deep-merge** across the two layers, with the `--settings` overlay winning per-key. So the same top-level key CAN live in both layers — but the keys *inside* it must not overlap unless you intend the overlay to win.
  - Example: common plugins live in `settings.json` (TUI-toggleable); profile-specific plugins (`figma`/`pg`/`cc-skills-golang` → work, `swift-lsp` → personal) live in the overlay and are **profile-locked** (the `/plugin` TUI can't toggle them, same as hooks).
- Third-party tools (lazytmux, etc.) should modify `settings.json` — changes appear as git diffs
- `feedbackSurveyState` and other runtime-mutated keys live in `settings.json`; ignore the noise in diffs

## Bash Command Simplicity

**Prefer** simple, single commands that match `Bash(cmd *)` permission patterns cleanly.

- **Avoid `$()` and backticks** — use direct arguments instead (e.g., `git commit -m "message"`, not HEREDOC with `$(cat ...)`).
- **Avoid `&&` / `||` chaining** — prefer separate Bash tool calls for each command.
- **Avoid pipes `|`** — prefer dedicated tools (Grep, Glob, Read) or separate calls.

These are **not hard bans** — use compound syntax when genuinely needed (e.g., a subshell `(cd dir && build)`, or a pipe that can't be split). But default to simple commands first.

## Skill Precedence

Two superpowers skills are superseded by better ones installed via
`home/ai/agent-skills`. `enabledPlugins` is plugin-granularity — it can't
disable a single skill inside a plugin — so precedence is asserted here instead.

- **Debugging** — use `diagnosing-bugs`, not `superpowers:systematic-debugging`.
  It builds a tight, red-capable feedback loop *before* forming any hypothesis;
  no such loop, no theorising.
- **Authoring or editing a skill** — use `writing-great-skills`, not
  `superpowers:writing-skills`. It is user-invoked upstream, so type it; the
  banned alternative is the half that needs stating.

## Reading Code (skeleton-first)

For files larger than ~300 lines, **structure before content**: run `ast-grep` for signatures, invoke the `context-efficient-tools:code-structure` skill, or `Grep` for the symbol you actually care about — *before* a full `Read`. Pull in the full body of a region only once you know which region matters.

Why: loading whole files burns context and rarely helps; most edits touch one small slice. This is the Dirac CLI insight — harness behavior beats model choice on benchmarks like TerminalBench, and "skeleton-by-default reads" is the single biggest contributor.

Exceptions (whole-file work — security review, top-to-bottom audit, config where every line matters): pass an explicit `limit` to `Read` to opt in deliberately. A PreToolUse guard (`claude-read-skeleton-guard`, in the `--settings` overlay) blocks unbounded `Read`s of files >300 lines and tells you to slice; bounded reads (offset/limit) and short files pass through untouched.

## Editing Files (read-then-edit, in one beat)

Every `Edit`/`Write` requires a current read of the target. The retry tax — `File has not been read yet` / `File has been modified since read` — is pure waste, so avoid it up front:

- **Read the exact region you're about to edit immediately before editing it.** Don't carry a stale read across many turns: if a build, formatter, linter, codegen, or `git` step ran since your last read of that file, Read it again before the Edit. Skeleton-first still applies to *locating* the region; the freshness rule applies to the *slice you edit*.
- **After a successful Edit, the file state is current** (the tool says so) — don't re-Read just to confirm. Re-Read only when something external could have touched the file since.
- **Never batch dependent steps into one parallel tool block.** A single failing call cancels its siblings (`Cancelled: parallel tool call ... errored`) and forces a re-run. Parallelize only mutually independent, read-only calls (e.g. several `Read`/`Grep`); run anything that mutates state, or that a later call depends on, as its own sequential call.

## Playwright Screenshot Configuration

**CRITICAL REQUIREMENT**: When using `mcp__playwright__browser_take_screenshot`:

- Default to `type: "png"` for UI screenshots — keeps Hebrew text, thin borders,
  and progress bars crisp, which is what you almost always want when debugging
  the UI.
- Use `type: "jpeg"` only when token cost clearly dominates (very large
  screenshots, many-image batches).
- Claude Vision supports `image/jpeg`, `image/png`, `image/gif`, and
  `image/webp`. AVIF and HEIC are NOT supported.

## Shared Agent Conventions

Engine-neutral rules — worktree isolation, the `wt` vocabulary, branch naming,
issue/ticket workflow, `gtrash`, fish, shellcheck, design principles, lean-code
guidance — are imported below from `home/ai/AGENTS.shared.md`. The same file is
symlinked to `~/.codex/AGENTS.md` and `~/.cursor/rules/shared-conventions.mdc`,
so all three engines read one source.

Put a rule there, not here, unless it is genuinely about Claude Code's own
harness.

@~/.claude/AGENTS.shared.md

## Machine Profile Overlay

Profile-specific instructions (work vs personal) are imported below. Nix
symlinks the target to `CLAUDE.work.md` or `CLAUDE.personal.md` based on
`osConfig.profile`, so the import always resolves. Keep machine-bound guidance
in those files; engine-neutral rules go in `AGENTS.shared.md`.

@~/.claude/CLAUDE.profile.md
