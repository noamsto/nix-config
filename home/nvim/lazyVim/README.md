# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## How this config is served

- `home/nvim/default.nix` links `lua/`, `lazyvim.json`, `.neoconf.json` and
  `stylua.toml` from the Nix store. It passes lazy.nvim a farm of
  `pkgs.vimPlugins` (lazy's `dev` option) plus a treesitter parser dir, so
  lazy.nvim never clones, installs or updates.
- Adding a plugin: add its spec under `lua/plugins/` and map its lazy.nvim name
  (the repo name, or the spec's `name`) to a package in the `plugins` attrset in
  `home/nvim/default.nix`. A plugin missing from nixpkgs gets a `flake = false`
  input and `buildPlugin`.
- Treesitter parsers: the `nvim-treesitter.withPlugins` list in
  `home/nvim/default.nix` must cover LazyVim's resolved `ensure_installed`.
- Extras: edit `lazyvim.json`; `:LazyExtras` can't save into the store.
- Updates: `nix flake update` (nixpkgs, or the plugin's input), not
  `:Lazy update`. There is no `lazy-lock.json`.
- One-time cleanup after the first switch to this layout:

  ```fish
  gtrash put ~/.local/share/nvim/lazy ~/.local/share/nvim/site/parser ~/.local/share/nvim/site/parser-info ~/.local/share/nvim/site/queries
  ```
