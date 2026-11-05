---
name: claude-code-settings
description: Use when changing Claude Code configuration in nix-config - settings.json, permissions, hooks, statusLine, plugins, mcpServers, env, or the --settings overlay in home/ai/claude-code/default.nix.
---

# Claude Code settings layers

Settings live in two layers under `home/ai/claude-code/`. Do not mix them.

| Layer | File | Owns |
|---|---|---|
| `settings.json` | symlinked to `~/.claude/settings.json`, writable | permissions, plugins, theme, sandbox, mcpServers, preferences: plain JSON |
| `--settings` overlay | Nix-generated via `nix-settings-json` in `default.nix`, read-only | hooks, statusLine, anything referencing `/nix/store`, and profile-gated `enabledPlugins` |

Rules:

- A setting that needs a nix store path goes in the overlay.
- Everything else goes in `settings.json`.
- Object-valued keys (`enabledPlugins`, `permissions`, `env`, `mcpServers`, `hooks`) deep-merge across the layers and the overlay wins per key. The same top-level key can live in both, but keep the nested keys disjoint unless the overlay should win. Example: common plugins live in `settings.json` (toggleable in the `/plugin` TUI); plugins that must not be toggled off (`swift-lsp`) live in the overlay.
- Third-party tools (lazytmux, etc.) should edit `settings.json`, so their changes show up as git diffs.
- Global-config keys in `~/.claude.json` (such as `lspRecommendationDisabled`) belong to neither layer; set them from `home.activation` (model on `claudeLspRecommendationDisabled` in `home/ai/claude-code/default.nix`).
- `feedbackSurveyState` and other runtime-mutated keys live in `settings.json`; ignore that diff noise.
