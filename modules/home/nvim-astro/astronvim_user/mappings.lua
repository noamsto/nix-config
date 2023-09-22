-- Mapping data with "desc" stored directly by vim.keymap.set().
--
-- Please use this mappings table to set keyboard mapping since this is the
-- lower level configuration and more robust one. (which-key will
-- automatically pick-up stored data by this setting.)
local utils = require "astronvim.utils"

require("telescope").load_extension("refactoring")

return {
  -- normal mode
  n = {
    -- second key is the lefthand side of the map
    -- mappings seen under group name "Buffer"
    ["<leader>bn"] = { "<cmd>tabnew<cr>", desc = "New tab" },
    -- quick save
    ["<C-s>"] = { ":w!<cr>", desc = "Save File" }, -- change description but the same command
    ["<leader>tp"] = { function() utils.toggle_term_cmd("ipython") end, desc = "ToggleTerm python" },

    -- undo history
    ["<leader>uh"] = { "<cmd>Telescope undo<cr>", desc = "Telescope undo" },

    -- implementation/definition preview
    ["gpd"] = { "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", desc = "goto_preview_definition" },
    ["gpt"] = { "<cmd>lua require('goto-preview').goto_preview_type_definition()<CR>", desc =
    "goto_preview_type_definition" },
    ["gpi"] = { "<cmd>lua require('goto-preview').goto_preview_implementation()<CR>", desc =
    "goto_preview_implementation" },
    ["gP"] = { "<cmd>lua require('goto-preview').close_all_win()<CR>", desc = "close_all_win" },
    ["gpr"] = { "<cmd>lua require('goto-preview').goto_preview_references()<CR>", desc = "goto_preview_references" },
  },
  
  -- visual mode(what's the difference between v and x???)
  x = {
    -- refactoring
    ["<leader>rr"] = { function() require('telescope').extensions.refactoring.refactors() end, desc =
    "Prompt for a refactor to apply" },
  },
}
