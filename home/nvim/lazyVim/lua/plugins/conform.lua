-- Project formatting wins: when `treefmt` is executable for the buffer (a
-- treefmt-nix devShell puts a wrapper on PATH, with no treefmt.toml), every
-- filetype formats with treefmt alone, so the editor matches pre-commit. No
-- per-language formatter or LSP fallback runs. Outside treefmt projects the
-- per-language formatters apply.
local function treefmt_or(formatters)
  return function()
    if vim.fn.executable("treefmt") == 1 then
      return { "treefmt" }
    end
    return formatters
  end
end

return {
  "stevearc/conform.nvim",
  opts = function(_, opts)
    opts.formatters = vim.tbl_deep_extend("force", opts.formatters or {}, {
      treefmt = {
        cwd = require("conform.util").root_file({ "flake.nix", ".git" }),
        condition = function()
          return vim.fn.executable("treefmt") == 1
        end,
      },
      ["markdown-toc"] = {
        condition = function(_, ctx)
          for _, line in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, 0, -1, false)) do
            if line:find("<!%-%- toc %-%->") then
              return true
            end
          end
        end,
      },
    })

    local by_ft = vim.tbl_extend("force", opts.formatters_by_ft or {}, {
      nix = { "alejandra" },
      -- prettier aligns tables and normalises whitespace, but only runs in
      -- projects with a prettier config (lazyvim_prettier_needs_config);
      -- markdown-toc runs only when the buffer has a `<!-- toc -->` marker.
      markdown = { "prettier", "markdown-toc" },
      ["markdown.mdx"] = { "prettier", "markdown-toc" },
    })
    for ft, formatters in pairs(by_ft) do
      by_ft[ft] = treefmt_or(formatters)
    end
    -- "_" applies to filetypes without a per-language entry, which would
    -- otherwise fall back to LSP formatting. conform rebuilds formatters_by_ft
    -- with tbl_extend, so a metatable default would not survive.
    by_ft["_"] = treefmt_or({})
    opts.formatters_by_ft = by_ft
  end,
}
