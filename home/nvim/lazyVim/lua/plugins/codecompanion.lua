return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "folke/which-key.nvim",
  },
  event = "VeryLazy",
  config = function(_, opts)
    require("codecompanion").setup(opts)

    local wk = require("which-key")
    wk.add({
      -- Create the group
      { "<leader>a", group = "󱙷 CodeCompanion" },

      -- Core commands - only two keys max after leader
      { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "Inline Assistant" },
      { "<leader>ac", "<cmd>CodeCompanionChat<cr>", desc = "Chat Buffer" },
      { "<leader>al", "<cmd>CodeCompanionCmd<cr>", desc = "Command Line" },
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "Action Palette" },
      { "<leader>at", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle Chat" },

      -- Visual mode commands
      { "<leader>av", "<cmd>CodeCompanionChat Add<cr>", desc = "Add to Chat", mode = "v" },
    })
  end,
  opts = function()
    vim.cmd([[cab cc CodeCompanion]])
    return {
      adapters = {
        anthropic = function()
          return require("codecompanion.adapters").extend("anthropic", {
            env = {
              api_key = "ANTHROPIC_API_KEY",
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
  end,
  keys = {},
}
