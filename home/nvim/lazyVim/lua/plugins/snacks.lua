return {
  "folke/snacks.nvim",
  -- Disable snacks GitHub picker keys — they hijack <leader>g* used by Octo
  keys = {
    { "<leader>gh", false },
    { "<leader>gH", false },
    { "<leader>gi", false },
    { "<leader>gI", false },
    { "<leader>gp", false },
    { "<leader>gP", false },
    { "<leader>gf", false },
  },
  ---@type snacks.Config
  opts = {
    image = {
      enabled = true,
    },
    explorer = {
      include = { ".env*", "gen", ".github", ".claude", ".husky", ".vscode", ".devcontainer", ".cursor", ".semgrep", ".speakeasy" },
    },
    picker = {
      include = { ".env*", "gen", ".github", ".claude", ".husky", ".vscode", ".devcontainer", ".cursor", ".semgrep", ".speakeasy" },
      formatters = {
        file = {
          filename_first = true,
        },
      },
    },
  },
}
