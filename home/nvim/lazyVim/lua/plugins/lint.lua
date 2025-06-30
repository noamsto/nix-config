return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      -- Configure linters for specific filetypes
      linters_by_ft = {
        python = { "mypy" },
        htmldjango = { "djlint" },
        ["yaml.github-actions"] = { "actionlint" },
        sql = { "sqlfluff" },
      },
    },
  },
}
