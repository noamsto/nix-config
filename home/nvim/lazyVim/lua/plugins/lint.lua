return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        python = { "mypy" },
        htmldjango = { "djlint" },
        ["yaml.github-actions"] = { "actionlint" },
        go = {}, -- Disable nvim-lint golangci, use LSP instead
      },
    },
  },
}
