return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
      -- The "seen" NEWS.md hash lives in the read-only lazyvim.json, so the news
      -- window would reopen on every start after an update.
      news = { lazyvim = false },
    },
  },
  { "folke/tokyonight.nvim", enabled = false },
}
