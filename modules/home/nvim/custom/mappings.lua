---@type MappingsTable
local M = {}

M.general = {
	n = {
		[";"] = { ":", "enter command mode", opts = { nowait = true } },
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

M.multi_cusrsors = {
	n = {
		["<leader>mc"] = {
			function()
				require("multicursors.nvim").MCstart()
			end,
			"Create a selection for selected text or word under the cursor",
		},
	},
	v = {
		["<leader>mc"] = {
			function()
				require("multicursors.nvim").MCstart()
			end,
			"Create a selection for selected text or word under the cursor",
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
			"goto LSP reference",
		},
	},
}
-- more keybinds!

return M
