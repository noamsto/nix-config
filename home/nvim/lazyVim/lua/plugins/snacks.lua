return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    image = {
      enabled = true,
    },
    explorer = {
      include = { ".env*", "gen", ".github", ".claude", ".husky", ".vscode", ".devcontainer", ".cursor", ".semgrep", ".speakeasy" },
    },
    picker = {
      db = { sqlite3_path = vim.env.SQLITE3_PATH },
      include = { ".env*", "gen", ".github", ".claude", ".husky", ".vscode", ".devcontainer", ".cursor", ".semgrep", ".speakeasy" },
      formatters = {
        file = {
          filename_first = true,
        },
      },
      sources = {
        explorer = {
          -- <c-j>/<c-k> default to list_down/list_up, which shadows smart-splits;
          -- j/k already move through the list.
          actions = {
            smart_move_down = function()
              require("smart-splits").move_cursor_down()
            end,
            smart_move_up = function()
              require("smart-splits").move_cursor_up()
            end,
          },
          win = {
            list = {
              keys = {
                ["<c-j>"] = { "smart_move_down", mode = "n" },
                ["<c-k>"] = { "smart_move_up", mode = "n" },
              },
            },
          },
        },
      },
    },
  },
}
