return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        go = {}, -- golangci-lint already runs through golangci_lint_ls
      },
    },
  },
}
