-- You can also add or configure plugins by creating files in this `plugins/` folder
-- Here are some examples:

---@type LazySpec
return {


	-- auto toggle relative absolute number
	{ "sitiom/nvim-numbertoggle", event = "VeryLazy" },

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
}
