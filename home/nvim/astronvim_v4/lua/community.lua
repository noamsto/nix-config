-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
	"AstroNvim/astrocommunity",
	{ import = "astrocommunity.pack.lua" },
	{ import = "astrocommunity.pack.just" },
	{ import = "astrocommunity.pack.go" },
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

	-- debug
	{ import = "astrocommunity.debugging.nvim-dap-virtual-text" },
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
	{ import = "astrocommunity.note-taking.obsidian-nvim" },
	{
		-- dependencies = {
		-- 	{
		-- 		"AstroNvim/astrocore",
		-- 		opts = {
		-- 			mappings = {
		-- 				n = {
		-- 					["<Leader>on"] = { function() require("obsidian").new_note() end, desc = "New note" },
		-- 					["<Leader>od"] = { function() require("obsidian").new_daily_note() end, desc = "New daily note" },
		-- 				},
		-- 			},
		-- 		},
		-- 	},
		-- },
		"epwalsh/obsidian.nvim",
		opts = {
			dir = vim.env.HOME .. "/Documents/obsidian-vault",
			daily_notes = {
				folder = "daily-notes",
			},
			mappings = {
				-- Overrides the 'gf' mapping to work on markdown/wiki links within your vault.
				["gf"] = {
					action = function()
						return require("obsidian").util.gf_passthrough()
					end,
					opts = { noremap = false, expr = true, buffer = true },
				},
				-- Smart action depending on context, either follow link or toggle checkbox.
				["<cr>"] = {
					action = function()
						return require("obsidian").util.smart_action()
					end,
					opts = { buffer = true, expr = true },
				}
			},
			ui = {
				checkboxes = {
					[" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
					["x"] = { char = "", hl_group = "ObsidianDone" },
					[">"] = { char = "", hl_group = "ObsidianRightArrow" },
					["~"] = { char = "", hl_group = "ObsidianTilde" },
					["!"] = { char = "", hl_group = "ObsidianImportant" },
				}
			},
			note_id_func = function(title)
				-- Create note IDs in a Zettelkasten format with a readable date and a suffix.
				local suffix = ""
				if title ~= nil then
					-- If title is given, transform it into valid file name.
					suffix = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
				else
					-- If title is nil, just add 4 random uppercase letters to the suffix.
					for _ = 1, 4 do
						suffix = suffix .. string.char(math.random(65, 90))
					end
				end
				return tostring(os.date("%Y-%m-%d")) .. "_" .. suffix
			end,
		}
	},
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
