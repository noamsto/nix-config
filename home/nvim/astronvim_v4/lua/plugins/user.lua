-- You can also add or configure plugins by creating files in this `plugins/` folder
-- Here are some examples:

---@type LazySpec
return {

	-- == Examples of Adding Plugins ==

	"andweeb/presence.nvim",

	-- auto toggle relative absolute number
	{ "sitiom/nvim-numbertoggle",   event = "VeryLazy" },

	{
		"utilyre/sentiment.nvim",
		version = "*",
		event = "VeryLazy", -- keep for lazy loading
		opts = {
			-- config
		},
		init = function()
			-- `matchparen.vim` needs to be disabled manually in case of lazy loading
			vim.g.loaded_matchparen = 1
		end,
	},
	{
		"leoluz/nvim-dap-go",
		ft = "go",
		dependencies = "mfussenegger/nvim-dap",
		-- config = function()
		-- 	require("dap-go").setup()
		-- end,
		opts = {
			-- code
			dap_configurations = {
				{
					type = "go",
					name = "Attach remote",
					mode = "remote",
					request = "attach",
					-- connect = {
					-- 	host = "ec2-3-74-231-178.eu-central-1.compute.amazonaws.com",
					-- 	port = "23456"
					-- }
				},
			},
			delve = {
				port = "23456",
				host = "ec2-3-74-231-178.eu-central-1.compute.amazonaws.com",
			},
		},
	},
	{
		"mfussenegger/nvim-dap-python",
		dependencies = "mfussenegger/nvim-dap",
		ft = "python", -- NOTE: ft: lazy-load on filetype
		config = function(_, opts)
			local path = "nvim-python3"
			require("dap-python").test_runner = "pytest"

			require("dap-python").setup(path, opts)

			local dap = require('dap')
			dap.defaults.fallback.external_terminal = {
				command = 'alacritty',
				args = { '-e' },
			}
			-- table.insert(require("dap").configurations.python, {
			-- 	type = "python",
			-- 	request = "launch",
			-- 	name = "Django runserver",
			-- 	program = function()
			-- 		return vim.fn.findfile("manage.py", "**")
			-- 	end,
			-- 	args = { "runserver", "--noreload" },
			-- })
		end,
	},

	{
		"rmagatti/goto-preview",
		config = function()
			require("goto-preview").setup {}
		end,
	},
	{
		"rcarriga/nvim-notify",
		opts = {
			stages = "static",
			top_down = false,
		},
	},

	{ "microsoft/python-type-stubs" },

	{
		'Joakker/lua-json5',
		build = './install.sh',
	},
	{
		"nvim-neo-tree/neo-tree.nvim",
		opts = {
			window = {
				position = "right",
			},
		}
	},
}
