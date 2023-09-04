---@type MappingsTable
local M = {}

M.disabled = {
	n = {
		-- Vim movement
		["<C-h>"] = "",
		["<C-l>"] = "",
		["<C-j>"] = "",
		["<C-k>"] = "",

		-- For trouble mapping
		["<leader>q"] = "",
	},
	i = {
		-- For cmp complete
		["<C-c>"] = "",
	},
}

M.general = {
	n = {
		[";"] = { ":", "enter command mode", opts = { nowait = true } },
		["C-h"] = {
			function()
				require("vim-tmux-navigator").TmuxNavigateLeft()
			end,
			"Window left (Tmux pane if applicable)",
		},
		["C-j"] = {
			function()
				require("vim-tmux-navigator").TmuxNavigateDown()
			end,
			"Window down (Tmux pane if applicable)",
		},
		["C-k"] = {
			function()
				require("vim-tmux-navigator").TmuxNavigateUp()
			end,
			"Window up (Tmux pane if applicable)",
		},
		["C-l"] = {
			function()
				require("vim-tmux-navigator").TmuxNavigateRight()
			end,
			"Window right (Tmux pane if applicable)",
		},
	},
}

M.dap = {
	plugin = true,
	n = {
		["<leader>db"] = { "<cmd> DapToggleBreakpoint <CR>", "Toggle Breakpoint" },
	},
}

M.dap_python = {
	plugin = true,
	n = {
		["<leader>dpr"] = {
			function()
				require("dap-python").test_method()
			end,
			"Debug Run",
		},
	},
	v = {
		["<leader>ds"] = {
			function()
				require("dap-python").debug_selection()
			end,
			"Debug Selection",
		},
	},
}

M.goto_preview = {
	plugin = true,
	n = {
		["gpr"] = {
			function()
				require("goto-preview").goto_preview_references()
			end,
			"goto preview LSP reference",
		},
		["gpd"] = {
			function()
				require("goto-preview").goto_preview_defintion()
			end,
			"goto preview LSP definition",
		},
	},
}
M.telescope = {
	n = {
		["gr"] = {
			function()
				require("telescope.builtin").lsp_references()
			end,
			"Go to LSP reference",
		},
		["gd"] = {
			function()
				require("telescope.builtin").lsp_definitions()
			end,
			"Go to LSP definition",
		},
		["<leader>lci"] = {
			function()
				require("telescope.builtin").lsp_incoming_calls()
			end,
			"Lists LSP incoming calls for word under the cursor",
		},
		["<leader>lco"] = {
			function()
				require("telescope.builtin").lsp_outgoing_calls()
			end,
			"Lists LSP outgoing calls for word under the cursor",
		},
		["<M-o>"] = {
			function()
				require("telescope.builtin").lsp_document_symbols()
			end,
			"Lists LSP document symbols in the current buffer",
		},
		["gsw"] = {
			function()
				require("telescope.builtin").lsp_workspace_symbols()
			end,
			"Lists LSP document symbols in the current workspace",
		},
		["gswd"] = {
			function()
				require("telescope.builtin").lsp_dynamic_workspace_symbols()
			end,
			"Dynamically Lists LSP for all workspace symbols",
		},
	},

	plugin = true,
}
M.trouble = {
	n = {
		["<leader>q"] = {
			function()
				require("trouble").open()
			end,
		},
	},
}
-- more keybinds!

return M
