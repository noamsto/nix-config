-- LSP keymaps
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      typos_lsp = {
        mason = false,
        init_options = {
          diagnosticSeverity = "Warning",
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
      atlas = {
        mason = false,
      },
      qmlls = {
        mason = false,
        cmd = { "qmlls", "-E" },
      },
    },
  },
}
