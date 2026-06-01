local base = require("config.catppuccin-base")

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    -- Initial load defaults to the dark (transparent) variant; auto-dark-mode
    -- re-runs setup() with the correct transparency for the current mode at
    -- startup and on every toggle.
    opts = base.opts(true),
  },
}
