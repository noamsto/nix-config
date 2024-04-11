-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
	"AstroNvim/astrocommunity",
	{ import = "astrocommunity.pack.lua" },
	-- import/override with your plugins folder

	{ import = "astrocommunity.colorscheme.catppuccin" },

	{ import = "astrocommunity.utility.noice-nvim" },

	-- Navigation
	{ import = "astrocommunity.scrolling.nvim-scrollbar" },

	-- Editing support
	{ import = "astrocommunity.editing-support.todo-comments-nvim" },
	{ import = "astrocommunity.editing-support.telescope-undo-nvim" },

	-- Git Version Control
	{ import = "astrocommunity.git.neogit" },
	{ import = "astrocommunity.git.diffview-nvim" },

	-- Language Support
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

	{ import = "astrocommunity.markdown-and-latex.markdown-preview-nvim" },
}
