return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "hrsh7th/nvim-cmp",                                                        -- Optional: For using slash commands and variables in the chat buffer
    "nvim-telescope/telescope.nvim",                                           -- Optional: For using slash commands
    { "stevearc/dressing.nvim",                    opts = {} },                -- Optional: Improves `vim.ui.select`
    { "MeanderingProgrammer/render-markdown.nvim", ft = { "codecompanion" } }, -- Optional: For prettier markdown rendering
    {
      "AstroNvim/astrocore",

      opts = {
        mappings = {
          n = {
            ["<Leader>a"] = { name = "󱙷 CodeCompanion" },
            ["<Leader>ac"] = { "<cmd>CodeCompanionChat<cr>", desc = "Open Chat" },
            ["<LocalLeader>a"] = { "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle a chat buffer" },
            ["<Leader>at"] = { "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle a chat buffer" },
            ["<Leader>aa"] = { "<cmd>CodeCompanionActions<cr>", desc = "Open the Action Palette" },
          },
          v = {
            ["<Leader>at"] = { "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle a chat buffer" },
            ["<LocalLeader>a"] = { "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle a chat buffer" },
            ["<Leader>aa"] = { "<cmd>CodeCompanionActions<cr>", desc = "Open the Action Palette" },
            ["<Leader>aA"] = { "<cmd>CodeCompanionChat Add<cr>", desc = "Add visually selected text to chat buffer" },
          },
        },
      }
    }
  },
  config = true,
  opts = function()
    vim.cmd([[cab cc CodeCompanion]])
    return {

      adapters = {
        anthropic = function()
          return require("codecompanion.adapters").extend("anthropic", {
            env = {
              api_key = "ANTHROPIC_API_KEY"
            },
          })
        end,
      },
      strategies = {
        chat = {
          adapter = "anthropic",
        },
        inline = {
          adapter = "anthropic",
        },
      },
    }
  end
}
