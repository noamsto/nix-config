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
    provider = "claude",
    file_selector = {
      provider = "snacks",
      provider_opts = {},
    },
  },
  -- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
  build = "make",
  file_selector = {
    provider = "snakcs",
  },
  keys = {
    { "<Leader>a", name = "Avante" },
  },

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
          -- required for Windows users
          use_absolute_path = true,
        },
      },
    },
    {
      -- Make sure to set this up properly if you have lazy=true
      "OXY2DEV/markview.nvim",
      opts = {
        preview = {
          filetypes = { "markdown", "norg", "rmd", "org", "vimwiki", "Avante" },
        },
        buf_ignore = {},
        max_length = 99999,
      },
      ft = { "markdown", "Avante" },
    },
  },
}
