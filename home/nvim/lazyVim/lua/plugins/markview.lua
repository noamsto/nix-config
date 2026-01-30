return {
  "OXY2DEV/markview.nvim",
  dependencies = {
    "nvim-mini/mini.icons",
  },
  enabled = true,
  event = "InsertEnter",
  ft = { "markdown", "norg", "rmd", "org", "vimwiki", "codecompanion", "Avante" },
  opts = {
    preview = {
      filetypes = { "markdown", "norg", "rmd", "org", "vimwiki", "codecompanion", "Avante" },
      ignore_buftypes = {},
      modes = { "n", "no", "c", "i" },
      hybrid_modes = { "n", "no", "c", "i" },
      icon_provider = "mini",
    },
  },
  config = function(_, opts)
    require("markview").setup(opts)
    Snacks.toggle({
      name = "Markview",
      get = function()
        local markview = require("markview")
        local buf = vim.api.nvim_get_current_buf()
        -- State is now per-buffer
        return markview.state and markview.state[buf] and markview.state[buf].enable or false
      end,
      set = function(enabled)
        local commands = require("markview.commands")
        if enabled then
          commands.enable()
        else
          commands.disable()
        end
      end,
    }):map("<leader>um")
  end,
}
