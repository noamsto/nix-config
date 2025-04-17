return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      -- Configure linters for specific filetypes
      -- Event to trigger linters
      linters_by_ft = {
        python = { "mypy" },
        htmldjango = { "djlint" },
        ["*"] = { "codespell" },
      },
      -- Configure linter settings
    },
  },
}
