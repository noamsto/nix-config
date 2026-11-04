return {
  "lewis6991/gitsigns.nvim",
  opts = {
    current_line_blame = false, -- Start with blame disabled
    current_line_blame_opts = {
      virt_text = true,
      virt_text_pos = "eol",
      delay = 300,
      ignore_whitespace = false,
      virt_text_priority = 100,
    },
    current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
  },
  config = function(_, opts)
    require("gitsigns").setup(opts)

    Snacks.toggle({
      name = "Git Blame",
      get = function()
        return require("gitsigns.config").config.current_line_blame
      end,
      set = function(enabled)
        require("gitsigns").toggle_current_line_blame()
      end,
    }):map("<leader>uB")
  end,
}