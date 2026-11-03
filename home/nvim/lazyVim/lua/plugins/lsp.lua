-- LSP keymaps
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      nil_ls = { enabled = false },
      nixd = {
        settings = {
          nixd = {
            nixpkgs = { expr = "import <nixpkgs> { }" },
            formatting = { command = { "alejandra" } },
          },
        },
      },
      harper_ls = {
        -- Commit messages only; markdown is too noisy.
        filetypes = { "gitcommit" },
        settings = {
          ["harper-ls"] = {
            diagnostics = {
              -- Make Harper less verbose by disabling some checks
              ["spell"] = true,         -- Enable Harper's spell checking
              ["word-repetition"] = false,  -- Less aggressive on repetition
              ["sentence-length"] = false,  -- Don't enforce sentence length
              ["unclosed-quotes"] = true,   -- Keep important checks
              ["linking-verbs"] = false,    -- Less strict on style
              ["passive-voice"] = false,    -- Allow passive voice
              ["sentence-capitalization"] = true,  -- Keep basic grammar
              ["wrong-quotes"] = true,      -- Keep punctuation checks
            },
          },
        },
      },
      marksman = {},
      protols = {
        enabled = false,
      },
      atlas = {},
      gopls = {
        settings = {
          gopls = {
            buildFlags = { "-tags=integration" },
          },
        },
      },
      golangci_lint_ls = {
        init_options = {
          command = { "golangci-lint", "run", "--build-tags=integration", "--output.json.path=stdout", "--show-stats=false" },
        },
      },
    },
  },
}
