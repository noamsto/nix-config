return {
  "stevearc/conform.nvim",
  opts = {
    formatters = {
      ["markdown-toc"] = {
        condition = function(_, ctx)
          for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
            if line:find("<!%-%- toc %-%->") then
              return true
            end
          end
        end,
      },
      ["markdownlint-cli2"] = {
        condition = function(_, ctx)
          local diag = vim.tbl_filter(function(d)
            return d.source == "markdownlint"
          end, vim.diagnostic.get(ctx.buf))
          return #diag > 0
        end,
      },
      kulala = {
        command = "kulala-fmt",
        args = { "format", "$FILENAME" },
        stdin = false,
      },
    },
    formatters_by_ft = {
      nix = { "alejandra" },
      htmldjango = { "djlint" },
      ["markdown"] = { "markdownlint-cli2", "prettierd", "markdown-toc" },
      ["markdown.mdx"] = { "markdownlint-cli2", "prettierd", "markdown-toc" },
      http = { "kulala" },
      yaml = { "prettierd" },
      go = { "goimports", "gofumpt" },
      sql = { "sqlfluff" },
    },
  },
}
