-- Mapping data with "desc" stored directly by vim.keymap.set().
--
-- Please use this mappings table to set keyboard mapping since this is the
-- lower level configuration and more robust one. (which-key will
-- automatically pick-up stored data by this setting.)
--
-- Find icons here https://www.nerdfonts.com/cheat-sheet

local utils = require("astronvim.utils")

require("telescope").load_extension("refactoring")

return {
	-- normal mode
	n = {
		-- second key is the lefthand side of the map
		-- mappings seen under group name "Buffer"
		["<leader>bn"] = { "<cmd>tabnew<cr>", desc = "New tab" },
		-- quick save
		["<C-s>"] = { ":w!<cr>", desc = "Save File" }, -- change description but the same command
		["<leader>tp"] = {
			function()
				utils.toggle_term_cmd("ipython")
			end,
			desc = " ToggleTerm python",
		},

		-- Cycle through buffers
		["<tab>"] = {
			function()
				require("astronvim.utils.buffer").nav(vim.v.count > 0 and vim.v.count or 1)
			end,
			desc = "Next buffer",
		},
		["<S-tab>"] = {
			function()
				require("astronvim.utils.buffer").nav(-(vim.v.count > 0 and vim.v.count or 1))
			end,
			desc = "Next buffer",
		},

		-- implementation/definition preview
		["gp"] = { name = "󱂬 Goto Preview" },
		["gpd"] = { "<cmd>lua require('goto-preview').goto_preview_definition()<CR>", desc = "goto_preview_definition" },
		["gpt"] = {
			"<cmd>lua require('goto-preview').goto_preview_type_definition()<CR>",
			desc = "goto_preview_type_definition",
		},
		["gpi"] = {
			"<cmd>lua require('goto-preview').goto_preview_implementation()<CR>",
			desc = "goto_preview_implementation",
		},
		["gpc"] = { "<cmd>lua require('goto-preview').close_all_win()<CR>", desc = "close_all_win" },
		["gpr"] = { "<cmd>lua require('goto-preview').goto_preview_references()<CR>", desc = "goto_preview_references" },
		["<leader>r"] = { name = "󰣪 Refactor" },
		["<leader>y"] = { name = "  Yanky" },
	},

	-- visual mode(what's the difference `etween v and x???)
	x = {
		-- refactoring
		["<leader>rr"] = {
			function()
				require("telescope").extensions.refactoring.refactors()
			end,
			desc = "Prompt for a refactor to apply",
		},
		["<leader>r"] = { name = "󰣪 Refactor" },
	},
}
