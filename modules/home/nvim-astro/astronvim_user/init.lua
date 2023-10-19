return {
	colorscheme = "catppuccin",

	options = {
		opt = {
			signcolumn = "auto", -- Show sign column when used only
			spell = false, -- Spell checking
			swapfile = false, -- Swapfile
		},
	},

	-- Configure require("lazy").setup() options
	lazy = {
		defaults = { lazy = true },
		performance = {
			rtp = {
				-- customize default disabled vim plugins
				disabled_plugins = {},
			},
		},
	},

	-- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
	lsp = {
		config = {
			ruff_lsp = {
				init_options = {
					settings = {
						args = { "--ignore=E501" },
					},
				},
			},
			pyright = {
				settings = {
					python = {
						analysis = {
							autoSearchPaths = true,
							useLibraryCodeForTypes = true,
							diagnosticMode = "openFilesOnly",
							typeCheckingMode = "off",
							stubPath = vim.fn.stdpath("data") .. "/lazy/python-type-stubs",
						},
					},
				},
			},
		},

		-- enable servers that installed by home-manager instead of mason
		servers = {
			---- Configuration Language
			"marksman", -- markdown ls
			"jsonls", -- json language server
			"yamlls", -- yaml language server
			"taplo", -- toml language server
			---- Backend
			"lua_ls", -- lua
			"pyright", -- python
			"ruff_lsp", -- extremely fast Python linter and code transformation
			"nil_ls", -- nix language server
			-- "pylsp",
			"efm",
			---- Operation & Cloud Nativautoindente
			"bashls", -- bash
			"dockerls", -- dockerfile
			"terraformls", -- terraform hcl
			"graphql",
			"bufls",
			-- "docker_compose_language_service",
		},
		formatting = {
			disabled = {},
			format_on_save = {
				enabled = true,
				allow_filetypes = {
					-- "python",
					"lua",
					"nix",
				},
			},
		},
	},
	polish = function()
		local autocmd = vim.api.nvim_create_autocmd
		-- Auto resize panes when resizing nvim window
		autocmd("VimResized", {
			pattern = "*",
			command = "tabdo wincmd =",
		})
	end,
}
