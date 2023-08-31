local overrides = require("custom.configs.overrides")

---@type NvPluginSpec[]
local plugins = {
	-- Override plugin definition options

	{
		"neovim/nvim-lspconfig",
		dependencies = {
			-- format & linting
			{
				"jose-elias-alvarez/null-ls.nvim",
				config = function()
					require("custom.configs.null-ls")
				end,
			},
		},
		config = function()
			require("plugins.configs.lspconfig")
			require("custom.configs.lspconfig")
		end,
	},

	{
		"williamboman/mason.nvim",
		opts = overrides.mason,
	},

	{
		"nvim-treesitter/nvim-treesitter",
		opts = overrides.treesitter,
	},

	{
		"nvim-tree/nvim-tree.lua",
		opts = overrides.nvimtree,
	},

	{
		"max397574/better-escape.nvim",
		event = "InsertEnter",
		config = function()
			require("better_escape").setup()
		end,
	},

	{
		"f3fora/cmp-spell",
		config = function()
			local cmp = require("cmp")
			local config = cmp.get_config()
			table.insert(config.sources, {
				name = "spell",
				option = {
					keep_all_entries = false,
					enable_in_context = function()
						return require("cmp.config.context").in_treesitter_capture("spell")
					end,
				},
				cmp.setup(config),
			})
		end,
		event = "InsertEnter",
	},

	{
		"mfussenegger/nvim-dap",
		config = function()
			require("core.utils").load_mappings("dap")
		end,
	},

	{
		"mfussenegger/nvim-dap-python",
		ft = "python",
		dependencies = {
			"mfussenegger/nvim-dap",
			"rcarriga/nvim-dap-ui",
		},
		config = function()
			require("dap-python").setup("nvim-python3")
			require("core.utils").load_mappings("dap_python")
		end,
	},

	{
		"rcarriga/nvim-dap-ui",
		dependencies = "mfussenegger/nvim-dap",
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")
			dapui.setup()
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end
		end,
	},

	{ "sitiom/nvim-numbertoggle", lazy = false },

	{
		"rmagatti/goto-preview",
		config = function()
			require("goto-preview").setup({})
			require("core.utils").load_mappings("goto_preview")
		end,
		event = "BufEnter",
	},

	{
		"nvim-neorg/neorg",
		build = ":Neorg sync-parsers",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			require("neorg").setup({
				load = {
					["core.defaults"] = {}, -- Loads default behaviour
					["core.concealer"] = {}, -- Adds pretty icons to your documents
					["core.summary"] = {},
					["core.dirman"] = { -- Manages Neorg workspaces
						config = {
							workspaces = {
								notes = "~/notes",
							},
							default_workspace = "notes",
						},
					},
				},
			})
		end,
		lazy = false,
	},

	{
		"nvim-treesitter/nvim-treesitter-context",
		config = function()
			require("treesitter-context").setup({
				multiline_threshold = 1,
			})
		end,
		event = "BufEnter *.py",
	},

	{
		"christoomey/vim-tmux-navigator",
		lazy = false,
		init = function()
			vim.g.tmux_navigator_disable_when_zoomed = 1
		end,
	},

	-- To make a plugin not be loaded
	-- {
	--   "NvChad/nvim-colorizer.lua",
	--   enabled = false
	-- },

	-- All NvChad plugins are lazy-loaded by default
	-- For a plugin to be loaded, you will need to set either `ft`, `cmd`, `keys`, `event`, or set `lazy = false`
	-- If you want a plugin to load on startup, add `lazy = false` to a plugin spec, for example
	-- {
	-- "mg979/vim-visual-multi",
	--   lazy = false,
	-- }
}

return plugins
