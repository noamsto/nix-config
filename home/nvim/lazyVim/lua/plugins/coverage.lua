return {
  "andythigpen/nvim-coverage",
  event = "VeryLazy",
  version = "*",
  config = function()
    require("coverage").setup({
      auto_reload = true,
    })
  end,
}
