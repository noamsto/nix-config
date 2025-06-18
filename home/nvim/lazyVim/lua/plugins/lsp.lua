-- LSP keymaps
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      harper_ls = {
        settings = {
          ["harper-ls"] = {
            linters = { ToDoHyphen = false },
          },
        },
      },
      pyright = {
        capabilities = {
          textDocument = {
            publishDiagnostics = {
              tagSupport = {
                valueSet = { 2 },
              },
            },
          },
        },
        settings = {
          python = {
            analysis = {
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "openFilesOnly",
              typeCheckingMode = "off",
              diagnosticSeverityOverrides = {
                reportUnusedVariable = "none", -- or anything
                reportUndefinedVariable = "none",
              },
              stubPath = vim.fn.stdpath("data") .. "/lazy/python-type-stubs",
            },
          },
        },
      },
      marksman = {
        mason = false,
      },
      postgres_lsp = {
        mason = false,
      },
      protols = {
        enabled = false,
      },
    },
  },
}
