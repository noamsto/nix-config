return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    explorer = {
      include = { ".env.local" },
    },
    picker = {
      include = { ".env.local" },
    },
  },
}
