return {
  "mrjones2014/smart-splits.nvim",
  lazy = false,
  dependencies = {
    { "smart-splits-nvim/backend-tmux", main = "smart-splits-backend-tmux" },
  },
  opts = {
    mux = { backend = "smart-splits-backend-tmux" },
    move = {
      -- At the true outer edge (no nvim split and no tmux pane in that direction),
      -- cross to the neighbouring kitty window — e.g. the aeye carousel. Same
      -- primitive as tmux-smart-nav and the aeye viewer; uses $KITTY_LISTEN_ON
      -- from the pane env (tmux update-environment), not a hardcoded socket.
      at_edge = function(ctx)
        local dir = ({ left = "left", right = "right", up = "top", down = "bottom" })[ctx.direction]
        vim.system({ "kitty", "@", "action", "neighboring_window", dir })
      end,
    },
  },
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
