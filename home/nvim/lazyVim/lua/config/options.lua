-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt
-- opt.spelllang = { "en" }
opt.spelloptions = "camel"
opt.laststatus = 3

-- Floating window borders (applies to LSP hover, signature help, diagnostics, etc.)
vim.o.winborder = "rounded"
