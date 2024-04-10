return {
  "ziontee113/icon-picker.nvim",
  config = function()
    require("icon-picker").setup({
      disable_legacy_commands = true,
    })
  end,
  event = "VeryLazy",
  dependencies = { "stevearc/dressing.nvim",
    {
      "AstroNvim/astrocore",

      opts = {
        mappings = {
          n = {
            ["<Leader>i"] = { name = " Icon" },
            ["<Leader>ip"] = { "<cmd>IconPickerNormal emoji nerd_font_v3 symbols<cr>", desc = "Open Icon Picker" },
            ["<Leader>iy"] = { "<cmd>IconPickerYank emoji nerd_font_v3 symbols<cr>", desc = "Open Icon Picker (Yank)" },
          },
        },
      }
    },
  }
}
