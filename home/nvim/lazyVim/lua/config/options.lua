-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.lazyvim_python_lsp = "pyrefly"
-- Prettier formats only in projects with a prettier config.
vim.g.lazyvim_prettier_needs_config = true
-- eslint's format-on-save runs before conform, so in a treefmt project it
-- would diverge from pre-commit.
vim.g.lazyvim_eslint_auto_format = vim.fn.executable("treefmt") == 0

local opt = vim.opt
-- opt.spelllang = { "en" }
opt.spelloptions = "camel"
opt.laststatus = 3

-- Floating window borders (applies to LSP hover, signature help, diagnostics, etc.)
vim.o.winborder = "rounded"

-- nvim's clipboard autodetect matches any binary named `lemonade`; on halo that
-- name belongs to AMD's Lemonade LLM server, not the SSH clipboard relay.
-- macOS never sets DISPLAY, so it keeps its native pbcopy/pbpaste provider.
-- Paste stays local: an OSC 52 read makes the terminal show a permission prompt
-- and blocks behind tmux. Tradeoff: "+p pastes the last nvim yank, not the
-- client clipboard; terminal paste still works.
if vim.fn.has("mac") == 0 and vim.env.DISPLAY == nil and vim.env.WAYLAND_DISPLAY == nil then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste_unnamed()
    return { vim.fn.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste_unnamed, ["*"] = paste_unnamed },
  }
end
