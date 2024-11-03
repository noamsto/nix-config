-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
	"AstroNvim/astrocommunity",
	{ import = "astrocommunity.pack.lua" },
	{ import = "astrocommunity.pack.just" },
	{ import = "astrocommunity.pack.go" },
	{
		"ray-x/go.nvim",
		commit = "b779debab83eb763b3b71bb1fa31526376bfbacc"
	},
	-- import/override with your plugins folder

	{ import = "astrocommunity.colorscheme.catppuccin" },

	{ import = "astrocommunity.utility.noice-nvim" },

	-- diagnostics
	{ import = "astrocommunity.diagnostics.trouble-nvim" },
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		dependencies = {
			'nvim-telescope/telescope.nvim',
			opts = function(_, opts)
				local open_with_trouble = require("trouble.sources.telescope").open
				-- Use this to add more results without clearing the trouble list
				-- local add_to_trouble = require("trouble.sources.telescope").add
				opts.defaults.mappings["i"]["<c-t>"] = open_with_trouble
				opts.defaults.mappings["n"]["<c-t>"] = open_with_trouble
			end
		}
	},

	-- Navigation
	{ import = "astrocommunity.scrolling.nvim-scrollbar" },
	{ import = "astrocommunity.scrolling.neoscroll-nvim" },

	-- Editing support
	{ import = "astrocommunity.editing-support.todo-comments-nvim" },
	{ import = "astrocommunity.editing-support.telescope-undo-nvim" },
	{ import = "astrocommunity.editing-support.refactoring-nvim" },
	{ import = "astrocommunity.editing-support.yanky-nvim" },

	-- { import = "astrocommunity.editing-support.copilotchat-nvim" },
	{ import = "astrocommunity.completion.copilot-lua-cmp" },
	{ import = "astrocommunity.search.nvim-spectre" },

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
		"epwalsh/obsidian.nvim",
		opts = function()
			vim.api.nvim_create_autocmd("BufReadPost", {
				desc = "Execute function when file path matches regex",
				pattern = "*/obsidian-vault/**",
				callback = function()
					local wk = require("which-key")
					wk.add({
						{
							"<Leader>o",
							group = "Obsidian",
						},
						{
							"<Leader>on",
							"<cmd>ObsidianNew<cr>",
							desc = "Obsidian new",
						}
					})
				end,
			}
			)
			return
			{
				dir = vim.env.HOME .. "/Documents/obsidian-vault",
				daily_notes = {
					folder = "daily-notes",
					default_tags = { "daily-notes" },
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
		end
	},
	{ import = "astrocommunity.markdown-and-latex.markdown-preview-nvim" },
	{
		"iamcco/markdown-preview.nvim",
		build = "cd app && yarn install",
	},
	{ import = "astrocommunity.markdown-and-latex.markview-nvim" },
	{
		"OXY2DEV/markview.nvim",
		opts = {
			modes = { "n", "no", "c" }, -- Change these modes
			-- to what you need

			hybrid_modes = { "n" }, -- Uses this feature on
			-- normal mode

			-- This is nice to have
			callbacks = {
				on_enable = function(_, win)
					vim.wo[win].conceallevel = 2;
					vim.wo[win].concealcursor = "c";
				end
			}
		}
	}
}
