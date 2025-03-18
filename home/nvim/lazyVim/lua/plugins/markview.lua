return {
  "OXY2DEV/markview.nvim",
  enabled = true,
  lazy = false,
  ft = { "markdown", "norg", "rmd", "org", "vimwiki", "codecompanion" },
  opts = {
    preview = {
      filetypes = { "markdown", "norg", "rmd", "org", "vimwiki", "codecompanion" },
      ignore_buftypes = {},
      modes = { "n", "no", "c" },
      hybrid_modes = { "n", "no", "c", "i" },
      icon_provider = "mini",
    },
  },
  config = function(_, opts)
    require("markview").setup(opts)
    Snacks.toggle({
      name = "Markview",
      get = function()
        return require("markview").state.enable
      end,
      set = function(enabled)
        local m = require("markview")
        if enabled then
          m.commands["Enable"]()
          m.commands["Start"]()
        else
          m.commands["Disable"]()
          m.commands["Stop"]()
        end
      end,
    }):map("<leader>um")
  end,
}
