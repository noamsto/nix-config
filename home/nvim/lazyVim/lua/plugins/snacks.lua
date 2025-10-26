return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    image = {
      enabled = true,
    },
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
