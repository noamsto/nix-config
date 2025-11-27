return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  keys = {
    {
      "<C-Left>",
      function()
        require("smart-splits").resize_left()
      end,
      desc = "Resize left",
    },
    {
      "<C-Right>",
      function()
        require("smart-splits").resize_right()
      end,
      desc = "Resize right",
    },
    {
      "<C-Up>",
      function()
        require("smart-splits").resize_up()
      end,
      desc = "Resize up",
    },
    {
      "<C-Down>",
      function()
        require("smart-splits").resize_down()
      end,
      desc = "Resize down",
    },
    {
      "<C-h>",
      function()
        require("smart-splits").move_cursor_left()
      end,
      desc = "Move left",
    },
    {
      "<C-l>",
      function()
        require("smart-splits").move_cursor_right()
      end,
      desc = "Move right",
    },
    {
      "<C-k>",
      function()
        require("smart-splits").move_cursor_up()
      end,
      desc = "Move up",
    },
    {
      "<C-j>",
      function()
        require("smart-splits").move_cursor_down()
      end,
      desc = "Move down",
    },
  },
}
