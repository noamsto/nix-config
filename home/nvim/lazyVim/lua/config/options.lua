-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt
-- opt.spelllang = { "en" }
opt.spelloptions = "camel"
opt.laststatus = 3

-- Floating window borders (applies to LSP hover, signature help, diagnostics, etc.)
vim.o.winborder = "rounded"

-- nvim's clipboard autodetect matches any binary named `lemonade`; on halo that
-- name belongs to AMD's Lemonade LLM server, not the SSH clipboard relay.
if vim.env.DISPLAY == nil and vim.env.WAYLAND_DISPLAY == nil then
  local osc52 = require("vim.ui.clipboard.osc52")
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
  }
end
