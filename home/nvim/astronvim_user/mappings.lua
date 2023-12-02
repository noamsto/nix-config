-- Mapping data with "desc" stored directly by vim.keymap.set().
--
-- Please use this mappings table to set keyboard mapping since this is the
-- lower level configuration and more robust one. (which-key will
-- automatically pick-up stored data by this setting.)
--
-- Find icons here https://www.nerdfonts.com/cheat-sheet

local utils = require("astronvim.utils")

require("telescope").load_extension("refactoring")

local continue = function()
	if vim.fn.filereadable(".vscode/launch.json") then
		require("dap.ext.vscode").load_launchjs()
	end
	require("dap").continue()
end

return {
	-- normal mode
	n = {

		["<leader>dc"] = { continue, desc = "Start/Continue (F5)" },
		-- second key is the lefthand side of the map
		-- mappings seen under group name "Buffer"
		["<leader>bn"] = { "<cmd>tabnew<cr>", desc = "New tab" },
		-- quick save
		["<C-s>"] = { ":w!<cr>", desc = "Save File" }, -- change description but the same command

		-- Toggle terminal
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
		["gpd"] = {
			function()
				require("goto-preview").goto_preview_definition()
			end,
			desc = "Goto Oreview Definition",
		},
		["gpt"] = {
			function()
				require("goto-preview").goto_preview_type_definition()
			end,
			desc = "Goto Preview Type Definition",
		},
		["gpi"] = {
			function()
				require("goto-preview").goto_preview_implementation()
			end,
			desc = "Goto Preview Implementation",
		},
		["gpc"] = {
			function()
				require("goto-preview").close_all_win()
			end,
			desc = "Close All Win",
		},
		["gpr"] = {
			function()
				require("goto-preview").goto_preview_references()
			end,
			desc = "Goto Preview References",
		},

		["<leader>r"] = { name = "󰣪 Refactor" },
		["<leader>y"] = { name = " Yanky" },

		["<leader>i"] = { name = " Icon" },
		["<leader>ip"] = { "<cmd>IconPickerNormal emoji nerd_font_v3 symbols<cr>", desc = "Open Icon Picker" },
		["<leader>iy"] = { "<cmd>IconPickerYank emoji nerd_font_v3 symbols<cr>", desc = "Open Icon Picker (Yank)" },

		["<leader>tt"] = {
			function()
				utils.toggle_term_cmd("btop")
			end,
			desc = "ToggleTerm btop",
		},
	},

	-- visual mode(what's the difference Between v and x???)
	x = {
		-- refactoring
		["<leader>r"] = { name = "󰣪 Refactor" },
		["<leader>rr"] = {
			function()
				require("telescope").extensions.refactoring.refactors()
			end,
			desc = "Prompt for a refactor to apply",
		},
	},

	i = {
		["<A-i>"] = { "<cmd>IconPickerInsert emoji nerd_font_v3 symbols<cr>", desc = "Icon picker insert mode" },
		["<C-Space>"] = false,
	},
}
