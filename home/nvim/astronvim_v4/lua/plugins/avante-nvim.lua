return {
  "yetone/avante.nvim",
  build = ":AvanteBuild",
  cmd = {
    "AvanteAsk",
    "AvanteBuild",
    "AvanteEdit",
    "AvanteRefresh",
    "AvanteSwitchProvider",
    "AvanteChat",
    "AvanteToggle",
    "AvanteClear",
  },
  dependencies = {
    "stevearc/dressing.nvim",
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    {
      "AstroNvim/astrocore",
      opts = {

        mappings = {
          n = {
            ["<Leader>a"] = { name = "Α Avante" },
            ["<Leader>aa"] = { function() require("avante.api").ask() end, desc = "Avante ask" },
            ["<Leader>ae"] = { function() require("avante.api").edit() end, desc = "Avante edit" },
            ["co"] = { "<Plug>(AvanteConflictOurs)", desc = "Choose ours", expr = true },
            ["ct"] = { "<Plug>(AvanteConflictTheirs)", desc = "Choose theirs", expr = true },
            ["ca"] = { "<Plug>(AvanteConflictAllTheirs)", desc = "Choose all theirs", expr = true },
            ["cb"] = { "<Plug>(AvanteConflictBoth)", desc = "Choose both", expr = true },
            ["cc"] = { "<Plug>(AvanteConflictCursor)", desc = "Choose cursor", expr = true },
            ["]x"] = { "<Plug>(AvanteConflictPrevConflict)", desc = "Move to previous conflict", expr = true },
            ["[x"] = { "<Plug>(AvanteConflictNextConflict)", desc = "Move to next conflict", expr = true },
          },
          v = {
            ["<Leader>aa"] = { function() require("avante.api").ask() end, desc = "Avante ask" },
            ["<Leader>ar"] = { function() require("avante.api").refresh() end, desc = "Avante refresh" },
            ["<Leader>ae"] = { function() require("avante.api").edit() end, desc = "Avante edit" },
            ["co"] = { "<Plug>(AvanteConflictOurs)", desc = "Choose ours", expr = true },
            ["ct"] = { "<Plug>(AvanteConflictTheirs)", desc = "Choose theirs", expr = true },
            ["ca"] = { "<Plug>(AvanteConflictAllTheirs)", desc = "Choose all theirs", expr = true },
            ["cb"] = { "<Plug>(AvanteConflictBoth)", desc = "Choose both", expr = true },
            ["cc"] = { "<Plug>(AvanteConflictCursor)", desc = "Choose cursor", expr = true },
          },
        },
      },
    },
  },
  opts = {

    provider = "claude",                  -- Recommend using Claude
    auto_suggestions_provider = "claude", -- Since auto-suggestions are a high-frequency operation and therefore expensive, it is recommended to specify an inexpensive provider or even a free provider: copilot
    claude = {
      endpoint = "https://api.anthropic.com",
      model = "claude-3-5-sonnet-20241022",
      temperature = 0,
      max_tokens = 4096,
    },
    hints = { enabled = true },
  },
  specs = { -- configure optional plugins
    {
      -- make sure `Avante` is added as a filetype
      "OXY2DEV/markview.nvim",
      optional = true,
      opts = function(_, opts)
        if not opts.filetypes then opts.filetypes = { "markdown", "quarto", "rmd" } end
        opts.filetypes = require("astrocore").list_insert_unique(opts.filetypes, { "Avante" })
      end,
    },
  },
}
