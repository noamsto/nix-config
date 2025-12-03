return {
  "noamsto/resolved.nvim",
  -- dir = "~/Data/git/resolved.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {},
  config = function(_, opts)
    require("resolved").setup(opts)
    Snacks.toggle
      .new({
        name = "Resolved",
        get = function()
          return require("resolved").is_enabled()
        end,
        set = function(state)
          if state then
            require("resolved").enable()
          else
            require("resolved").disable()
          end
        end,
      })
      :map("<leader>uR")
  end,
  event = "VeryLazy",
}
