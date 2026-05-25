# Nvim Trim Plan

Goal: shrink LazyVim down to a fast editor for targeted edits. CC handles navigation, refactors, multi-file work, AI. Stay on LazyVim framework — just disable extras and prune plugin files.

Paths are relative to `home/nvim/lazyVim/`.

## Definitely cut — dead code, zero functional change

- [ ] `lua/plugins/example.lua` — LazyVim template, returns `{}` immediately
- [ ] `lua/plugins/lang-authzed.lua` — all commented-out placeholders
- [ ] `lua/plugins/vectorcode.lua` — entirely commented out

## AI plugins — CC replaces all of these

- [ ] `lua/plugins/avante.lua` (116 lines)
- [ ] `lua/plugins/codecompanion.lua` (146 lines)
- [ ] `lua/plugins/sidekick.lua`
- [ ] `lua/plugins/octo-ai.lua` — own plugin, but AI-on-PRs is `gh` + CC territory
- [ ] Remove `lazyvim.plugins.extras.ai.sidekick` from `lazyvim.json`

## IDE bloat — matches "barely use nvim now" framing

- [ ] `lua/plugins/coverage.lua` — test coverage gutter
- [ ] `lua/plugins/dbee.lua` — in-editor DB client (dbeaver covers this)
- [ ] `lua/plugins/codesnap.lua` — code screenshots, rare
- [ ] `lua/plugins/lensline.lua` — inline code-lens noise
- [ ] `lua/plugins/nvim-store.lua` — plugin browser, one-shot tool
- [ ] Remove from `lazyvim.json`:
  - [ ] `lazyvim.plugins.extras.dap.core` — debugger
  - [ ] `lazyvim.plugins.extras.test.core` — neotest
  - [ ] `lazyvim.plugins.extras.util.rest` — **redundant with kulala**
  - [ ] `lazyvim.plugins.extras.editor.dial`
  - [ ] `lazyvim.plugins.extras.editor.inc-rename`
  - [ ] `lazyvim.plugins.extras.util.dot`
  - [ ] `lazyvim.plugins.extras.coding.yanky`

## Decisions needed

### Language extras (`lazyvim.json`)

Current set: `docker`, `go`, `json`, `nix`, `python`, `toml`, `typescript`, `yaml`.

Guess: keep `nix` + `go` + `typescript`, cut the rest (treesitter alone handles syntax fine; CC writes the boilerplate).

- [ ] Keep `lang.nix`
- [ ] Keep `lang.go`
- [ ] Keep `lang.typescript`
- [ ] Cut `lang.python`
- [ ] Cut `lang.docker`
- [ ] Cut `lang.json`
- [ ] Cut `lang.yaml`
- [ ] Cut `lang.toml`

### Individual plugins

- [ ] `lua/plugins/octo.lua` — full GitHub PR review in nvim. Cut if living in `gh`/web.
- [ ] `lua/plugins/lint.lua` — only configures `mypy`, `djlint`, `actionlint`. Cut if not using those.

## Keep (uncontroversial)

User keep-list: snacks, markview, kulala, LSP/TS, which-key (LazyVim default), some LazyVim UI tweaks.

Supporting cast that stays:

- `snacks.lua`, `markview.lua`, `kulala.lua`
- `lsp.lua`, `treesitter.lua`, `mason.lua`, `blink.lua`, `conform.lua`
- `lazyvim.lua` (colorscheme), `catppuccin.lua`, `auto-dark-mode.lua`
- `lualine.lua` (snacks doesn't replace statusline)
- `better-escape.lua`, `smart-splits.lua`, `spider.lua`
- `gitisings.lua` (gitsigns)
- `obsidian.lua`, `resolved.lua` (own plugin), `stubs.lua`
- `lazyvim.plugins.extras.ui.treesitter-context`, `util.mini-hipatterns`

## After the cut

- [ ] `nvim --startuptime /tmp/before.log nvim` before, again after, diff totals
- [ ] `:Lazy profile` to confirm load order
- [ ] Open a normal working session, then `:Lazy` — anything still "not loaded" is another deletion candidate

## Open question: framework itself

Trimmed LazyVim is fine for now. If config still feels heavy after this pass, consider hand-rolled `lazy.nvim` setup (~50 lines `init.lua` + plugin specs). Not worth migrating preemptively.
