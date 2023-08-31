local M = {}

M.treesitter = {
	ensure_installed = {
		"vim",
		"lua",
		"python",
		"nix",
	},
	indent = {
		enable = true,
		-- disable = {
		--   "python"
		-- },
	},
}

M.mason = {
  ensure_installed = {
    -- Since we are on NixOS we don't use Mason for installation
    -- -- lua stuff
    -- "lua-language-server",
    -- "stylua",
    --
    -- -- web dev stuff
    -- "css-lsp",
    -- "html-lsp",
    -- "typescript-language-server",
    -- "deno",
    -- "prettier",
    --
    -- -- c/cpp stuff
    -- "clangd",
    -- "clang-format",
  },
}

-- git support in nvimtree
M.nvimtree = {
	git = {
		enable = true,
	},

	renderer = {
		highlight_git = true,
		icons = {
			show = {
				git = true,
			},
		},
	},
}

return M
