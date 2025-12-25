return {
  "saghen/blink.cmp",
  dependencies = {
    "Kaiser-Yang/blink-cmp-avante",
  },
  build = "nix run .#build-plugin",
  opts = function(_, opts)
    opts = opts or {}
    opts.sources = opts.sources or {}

    -- Append to default sources
    opts.sources.default = vim.list_extend(opts.sources.default or {}, { "avante" })

    -- Append to providers
    opts.sources.providers = vim.tbl_deep_extend("force", opts.sources.providers or {}, {
      avante = {
        module = "blink-cmp-avante",
        name = "Avante",
        opts = {
          -- options for blink-cmp-avante
        },
      },
    })

    -- Floating window borders
    opts.completion = vim.tbl_deep_extend("force", opts.completion or {}, {
      menu = { border = "rounded" },
      documentation = { window = { border = "rounded" } },
    })
    opts.signature = vim.tbl_deep_extend("force", opts.signature or {}, {
      window = { border = "rounded" },
    })

    return opts
  end,
}
