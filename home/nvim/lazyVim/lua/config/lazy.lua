-- Nix serves lazy.nvim, every plugin and the treesitter parsers from the store
-- (vim.g.lazy_nix, set in home/nvim/default.nix); lazy.nvim only loads them.
local nix = vim.g.lazy_nix
vim.opt.rtp:prepend(nix.plugins .. "/lazy.nvim")

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
    -- LazyVim counts a parser as installed only under install_dir and installs the
    -- rest from the network.
    { "nvim-treesitter/nvim-treesitter", opts = { install_dir = nix.parsers } },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  -- "" matches every plugin URL, so each one loads from <plugins>/<name>; lazy never
  -- clones, builds or locks local plugins.
  dev = { path = nix.plugins, patterns = { "" }, fallback = false },
  install = { missing = false, colorscheme = { "catppuccin", "habamax" } },
  -- Written after any :Lazy task; the default would land in the HM-managed ~/.config/nvim.
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
  rocks = { enabled = false }, -- no remaining plugin needs luarocks
  checker = { enabled = false },
  change_detection = { enabled = false },
  ui = {
    border = "rounded",
  },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
