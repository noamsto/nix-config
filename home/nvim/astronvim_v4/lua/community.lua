-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
	"AstroNvim/astrocommunity",
	{ import = "astrocommunity.pack.lua" },
	{ import = "astrocommunity.pack.just" },
	-- import/override with your plugins folder

	{ import = "astrocommunity.colorscheme.catppuccin" },

	{ import = "astrocommunity.utility.noice-nvim" },

	-- Navigation
	{ import = "astrocommunity.scrolling.nvim-scrollbar" },
	{ import = "astrocommunity.scrolling.neoscroll-nvim" },

	-- Editing support
	{ import = "astrocommunity.editing-support.todo-comments-nvim" },
	{ import = "astrocommunity.editing-support.telescope-undo-nvim" },
	{ import = "astrocommunity.editing-support.refactoring-nvim" },

	{ import = "astrocommunity.completion.copilot-lua-cmp" },
	{ import = "astrocommunity.project.nvim-spectre" },

	-- Git Version Control
	{ import = "astrocommunity.git.neogit" },
	{ import = "astrocommunity.git.diffview-nvim" },
	{ import = "astrocommunity.git.octo-nvim" },


	-- testing
	{ import = "astrocommunity.test.neotest" },
	{
		"nvim-neotest/neotest",

		dependencies = {
			{
				"AstroNvim/astrocore",
				opts = {
					mappings = {
						n = {
							["<Leader>To"] = { function() require("neotest").output.open({ enter = true }) end, desc = "Output hover" },
						},
					},
				},
			},
			"nvim-neotest/neotest-python",
		},
		opts = function()
			return {
				-- other neotest config here.
				adapters = {
					require("neotest-python")({
						dap = { justMyCode = false },
						runner = "pytest",
						pytest_discover_instances = true,
					}),
				},
			}
		end,
	},
	-- Language Support
	---- Configuration Language
	{ import = "astrocommunity.pack.json" },
	{ import = "astrocommunity.pack.yaml" },
	{ import = "astrocommunity.pack.toml" },
	---- Backend
	{ import = "astrocommunity.pack.lua" },
	---- Database
	{ import = "astrocommunity.pack.full-dadbod" },
	---- Operation & Cloud Native
	{ import = "astrocommunity.pack.terraform" },
	{ import = "astrocommunity.pack.bash" },
	{ import = "astrocommunity.pack.docker" },
	-- Motion
	{ import = "astrocommunity.motion.nvim-surround" },
	{ import = "astrocommunity.motion.flash-nvim" },
	-- Lua implementation of CamelCaseMotion, with extra consideration of punctuation.
	{ import = "astrocommunity.motion.nvim-spider" },
	{
		"chrisgrieser/nvim-spider",
		opts = {
			skipInsignificantPunctuation = false,
		},
	},

	-- Note taking
	{ import = "astrocommunity.note-taking.neorg" },
	{
		"nvim-neorg/neorg",
		opts = {
			load = {
				["core.defaults"] = {}, -- Loads default behaviour
				["core.concealer"] = {}, -- Adds pretty icons to your documents
				["core.keybinds"] = {}, -- Adds default keybindings
				["core.export"] = {}, -- Export to supported file types
				["core.completion"] = {
					config = {
						engine = "nvim-cmp",
					},
				},                 -- Enables support for completion plugins
				["core.journal"] = {}, -- Enables support for the journal module
				["core.dirman"] = { -- Manages Neorg workspaces
					config = {
						workspaces = {
							notes = "~/notes",
						},
						default_workspace = "notes",
					},
				},
			},
		},
	},
	{ import = "astrocommunity.markdown-and-latex.markdown-preview-nvim" },
}
