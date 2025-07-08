return {
  "yetone/avante.nvim",

  event = "VeryLazy",
  lazy = false,
  version = false,
  build = "make",

  config = function(_, opts)
    require("avante").setup(opts)
    local wk = require("which-key")
    wk.add({ "<leader>a", group = "Avante", mode = { "v", "n" }, icon = { icon = "󰧑", color = "orange" } })
  end,

  opts = {
    provider = "claude",
    selector = {
      provider = "snacks",
      exclude_auto_select = { "NvimTree", "neo-tree" },
    },
    windows = {
      width = 35, -- Wider sidebar (default is 30)
      input = {
        height = 12, -- Larger input section
      },
      sidebar_header = {
        enabled = true,
        align = "center",
        rounded = true,
      },
    },
    system_prompt = function()
      local hub = require("mcphub").get_hub_instance()
      return hub and hub:get_active_servers_prompt() or ""
    end,
    custom_tools = function()
      return {
        require("mcphub.extensions.avante").mcp_tool(),
      }
    end,
  },

  dependencies = {
    "nvim-treesitter/nvim-treesitter",
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
    "ravitemer/mcphub.nvim",
  },
}
