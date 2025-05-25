return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    explorer = {
      include = { ".env*", "gen" },
    },
    picker = {
      include = { ".env*", "gen" },
    },
  },
}
