local failures, info = {}, {}
local function fail(msg)
  table.insert(failures, msg)
end

-- Errors only: warnings (e.g. smart-splits' tmux notice without $TMUX) are expected.
if vim.v.errmsg ~= "" then
  fail("startup error: " .. vim.v.errmsg)
end
for line in vim.fn.execute("messages"):gmatch("[^\n]+") do
  if line:find("E%d+:") or line:find("Error") then
    fail("startup message: " .. line)
  end
end

local Config = require("lazy.core.config")
local farm = vim.g.lazy_nix.plugins .. "/"
for name, p in pairs(Config.plugins) do
  if not p._.installed then
    fail("not installed: " .. name)
  end
  if not vim.startswith(p.dir, farm) then
    fail("outside the Nix farm: " .. name .. " " .. p.dir)
  end
  if name:find("dap") then
    fail("DAP plugin resolved: " .. name)
  end
end

for _, name in ipairs({ "resolved.nvim", "backend-tmux", "blink.cmp" }) do
  if not Config.plugins[name] then
    fail("not enabled: " .. name)
  end
end

-- lazy.nvim always creates this root, so no clones means empty, not absent.
local cloned = vim.fn.readdir(vim.fn.stdpath("data") .. "/lazy")
if #cloned > 0 then
  fail("lazy root not empty: " .. table.concat(cloned, ", "))
end

require("lazy").load({ plugins = { "resolved.nvim", "smart-splits.nvim", "blink.cmp", "nvim-treesitter" } })
for _, mod in ipairs({ "resolved", "smart-splits-backend-tmux", "blink.cmp.fuzzy.rust" }) do
  local ok, err = pcall(require, mod)
  if not ok then
    fail("require " .. mod .. " failed: " .. tostring(err))
  end
end

local ensure = require("lazy.core.plugin").values(Config.plugins["nvim-treesitter"], "opts", false).ensure_installed
local installed = LazyVim.treesitter.get_installed(true)
local wanted = {}
for _, lang in ipairs(ensure) do
  wanted[lang] = true
  if not installed[lang] then
    fail("parser missing: " .. lang)
  end
end
for lang in pairs(installed) do
  if not wanted[lang] then
    table.insert(info, "parser not in ensure_installed: " .. lang)
  end
end
table.sort(info)

for _, f in ipairs({ "a.lua", "a.nix" }) do
  vim.cmd.edit(f)
  local buf = vim.api.nvim_get_current_buf()
  if not vim.wait(3000, function()
    return vim.treesitter.highlighter.active[buf] ~= nil
  end) then
    fail("no treesitter highlighting: " .. f)
  end
end

if #info > 0 then
  io.stderr:write("info (not failing):\n" .. table.concat(info, "\n") .. "\n")
end
if #failures > 0 then
  io.stderr:write(table.concat(failures, "\n") .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
