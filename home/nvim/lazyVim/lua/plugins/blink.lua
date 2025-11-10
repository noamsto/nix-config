return {
  "saghen/blink.cmp",
  dependencies = {
    "Kaiser-Yang/blink-cmp-avante",
    "fang2hou/blink-copilot",
  },
  build = "nix run .#build-plugin",
  opts = function(_, opts)
    opts = opts or {}
    opts.sources = opts.sources or {}

    -- Append to default sources
    opts.sources.default = vim.list_extend(opts.sources.default or {}, { "avante", "copilot" })

    -- Append to providers
    opts.sources.providers = vim.tbl_deep_extend("force", opts.sources.providers or {}, {
      avante = {
        module = "blink-cmp-avante",
        name = "Avante",
        opts = {
          -- options for blink-cmp-avante
        },
      },
      copilot = {
        name = "copilot",
        module = "blink-copilot",
        score_offset = 100,
        async = true,
        opts = {
          max_completions = 3,
          max_attempts = 4,
          debounce = 200,
          auto_refresh = {
            backward = true,
            forward = true,
          },
        },
      },
    })

    return opts
  end,
}
