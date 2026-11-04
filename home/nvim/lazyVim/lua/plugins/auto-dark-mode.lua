local base = require("config.catppuccin-base")

-- Re-run catppuccin setup() so transparency tracks the mode (opaque in light to
-- avoid the washed-out latte look), then apply the matching flavour.
local function apply(transparent, bg, flavour)
  require("catppuccin").setup(base.opts(transparent))
  vim.api.nvim_set_option_value("background", bg, {})
  vim.cmd.colorscheme("catppuccin-" .. flavour)
end

return {
  "f-person/auto-dark-mode.nvim",
  lazy = false,
  opts = {
    update_interval = 1000,
    set_dark_mode = function()
      apply(true, "dark", "mocha")
    end,
    set_light_mode = function()
      apply(false, "light", "latte")
    end,
  },
}
