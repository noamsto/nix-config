return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    explorer = {
      include = { ".env*", "gen" },
    },
    picker = {
      include = { ".env*", "gen" },
      formatters = {
        file = {
          filename_first = true,
        },
      },
    },
  },
}
