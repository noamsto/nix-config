# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

## Migrating from the old Home Manager layout (pre-Apr 2026)

The old config symlinked the entire `~/.config/nvim` directory to this
`lazyVim/` folder in one shot:

```nix
xdg.configFile."nvim".source = mkOutOfStoreSymlink ".../lazyVim";
```

Recent Home Manager versions auto-generate `~/.config/nvim/init.lua` from
`programs.neovim`, which conflicts with a whole-directory symlink. The new
layout (see `home/nvim/default.nix`) symlinks each child individually
(`nvim/lua`, `nvim/lazyvim.json`, `nvim/lazy-lock.json`, `nvim/.neoconf.json`,
`nvim/stylua.toml`) and moves the LazyVim bootstrap into
`programs.neovim.extraLuaConfig`.

**`init.lua` is no longer needed in this repo** — HM writes it to
`~/.config/nvim/init.lua` itself.

### Symptom: "Too many levels of symbolic links"

After switching configs, you may see a circular symlink loop:

```
repo/home/nvim/lazyVim/lua
  → /nix/store/…-home-manager-files/.config/nvim/lua
  → /nix/store/…-hm_lua
  → repo/home/nvim/lazyVim/lua   (loop)
```

**Root cause:** the *stale* `~/.config/nvim` symlink from the old HM
generation still points into this repo directory. When the new HM
generation writes per-file symlinks at `~/.config/nvim/<file>`, it follows
that stale symlink and ends up writing the symlinks *into the repo*,
creating a cycle with `mkOutOfStoreSymlink`.

### Fix

1. Remove the stale top-level symlink and any in-repo symlinks that were
   accidentally created:

   ```fish
   gtrash put ~/.config/nvim
   cd ~/nix-config/home/nvim/lazyVim
   # Delete any files that are now symlinks into /nix/store (check with `ls -la`)
   gtrash put init.lua lua lazy-lock.json lazyvim.json .neoconf.json stylua.toml
   # Restore the originals if you had renamed them to .bak
   mv lua.bak lua
   mv lazy-lock.json.bak lazy-lock.json
   mv lazyvim.json.bak lazyvim.json
   mv .neoconf.json.bak .neoconf.json
   mv stylua.toml.bak stylua.toml
   ```

2. Rebuild:

   ```fish
   nh home switch .
   ```

After activation, `~/.config/nvim` should be a real directory containing
symlinks into `/nix/store/…-home-manager-files/.config/nvim/…`, which in
turn point back to files in this repo. No loop.
