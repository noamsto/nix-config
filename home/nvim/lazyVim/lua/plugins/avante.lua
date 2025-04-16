return {
  "yetone/avante.nvim",
  event = "VeryLazy",
  lazy = false,
  version = false,
  config = function(_, opts)
    require("avante").setup(opts)
    local wk = require("which-key")
    wk.add({ "<leader>a", group = "Avante", mode = { "v", "n" }, icon = { icon = "󰧑", color = "orange" } })
  end,
  opts = {
    build = "make",
    provider = "claude",
    file_selector = {
      provider = "snacks",
      provider_opts = {},
    },
    behaviour = {
      enable_claude_text_editor_tool_mode = true,
    },
    -- system_prompt = function()
    --   local hub = require("mcphub").get_hub_instance()
    --   return hub:get_active_servers_prompt()
    -- end,
    -- -- The custom_tools type supports both a list and a function that returns a list. Using a function here prevents requiring mcphub before it's loaded
    -- custom_tools = function()
    --   return {
    --     require("mcphub.extensions.avante").mcp_tool(),
    --   }
    -- end,
  },
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`

  -- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    --- The below dependencies are optional,
    "echasnovski/mini.icons",
    {
      -- support for image pasting
      "HakonHarnes/img-clip.nvim",
      event = "VeryLazy",
      opts = {
        -- recommended settings
        default = {
          embed_image_as_base64 = false,
          prompt_for_file_name = false,
          drag_and_drop = {
            insert_mode = true,
          },
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      "OXY2DEV/markview.nvim",
      opts = {
        preview = {
          filetypes = { "markdown", "norg", "rmd", "org", "vimwiki", "Avante" },
          ignore_buftypes = {},
        },
        max_length = 99999,
      },
      ft = { "markdown", "Avante" },
    },
  },
}
