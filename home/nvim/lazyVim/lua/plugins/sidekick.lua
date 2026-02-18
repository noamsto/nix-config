return {
  "folke/sidekick.nvim",
  opts = {
    nes = {
      enabled = false, -- requires Copilot LSP
    },
    copilot = {
      status = {
        enabled = false, -- no Copilot subscription
      },
    },
    cli = {
      mux = {
        backend = "tmux",
        enabled = true,
        create = "split",
        split = {
          vertical = true, -- Vertical split (left/right)
          size = 0.35, -- 35% of the width
        },
      },
    },
  },
}
