-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- disable diagnostics for .env files
local group = vim.api.nvim_create_augroup("__env", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = ".env*",
  group = group,
  callback = function(args)
    vim.diagnostic.enable(false, { bufnr = args.buf })
  end,
})

-- Set up custom filetypes
vim.filetype.add({
  filename = {
    [".envrc"] = "sh",
    ["atlas.hcl"] = "atlas-config",
  },
  extension = {
    ["http"] = "http",
  },
  pattern = {
    [".env.*"] = "sh",
    [".*compose.yml"] = "yaml.docker-compose",
    [".*compose.yaml"] = "yaml.docker-compose",
    [".*dockerfile"] = "dockerfile",
    [".*Dockerfile"] = "dockerfile",
    [".*Dockerfile.*"] = "dockerfile",
    [".*/%.github/workflows/.*%.ya?ml"] = "yaml.github-actions",
    [".*/*.my.hcl"] = "atlas-schema-mysql",
    [".*/*.pg.hcl"] = "atlas-schema-postgresql",
    [".*/*.lt.hcl"] = "atlas-schema-sqlite",
    [".*/*.ch.hcl"] = "atlas-schema-clickhouse",
    [".*/*.ms.hcl"] = "atlas-schema-mssql",
    [".*/*.rs.hcl"] = "atlas-schema-redshift",
    [".*/*.test.hcl"] = "atlas-test",
    [".*/*.plan.hcl"] = "atlas-plan",
  },
})

-- Set Jinja files to be highlighted as HTML
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  pattern = { "*.html.j2", "*.jinja", "*.jinja2", "*.j2" },
  command = "setlocal filetype=htmldjango",
})
