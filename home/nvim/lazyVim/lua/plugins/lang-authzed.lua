return {
  -- Language-specific configuration for Authzed
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Ensure the authzed parser is in the ensure_installed list
      -- This will be handled by our main treesitter.lua config
    end,
  },

  -- Optional: Add LSP support if you have an Authzed language server
  -- {
  --   "neovim/nvim-lspconfig",
  --   opts = {
  --     servers = {
  --       -- authzed_ls = {}, -- if you have an Authzed language server
  --     },
  --   },
  -- },

  -- Optional: Add syntax highlighting or other language features
  -- You can add more language-specific configurations here
}
