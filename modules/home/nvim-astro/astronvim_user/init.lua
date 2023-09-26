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
			-- pylsp = {
			--   cmd = { "nvim-python3", "-m", "pylsp" },
			--   settings = {
			--     pylsp = {
			--       plugins = {
			--         ruff = { enabled = false, ignore = { "E501" }, hover = false },
			--         python_lsp_black = { enabled = false, line_length = 99 },
			--         pylsp_mypy = { enabled = true, hover = false },
			--         jedi = { enabled = false },
			--         jedi_hover = { enabled = false },
			--         jedi_completion = { enabled = false },
			--         jedi_definition = { enabled = false },
			--         jedi_references = { enabled = false },
			--         jedi_symbols = { enabled = false },
			--         jedi_signature_help = { enabled = false },
			--       },
			--     },
			--   },
			-- },
			yamlls = {
				settings = {
					yaml = {
						format = {
							enable = true,
						},
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
		on_attach = function(client, buffer)
			local clients_no_hover = { "ruff_lsp" }
			for _, no_hover_client_name in pairs(clients_no_hover) do
				if client.name == no_hover_client_name then
					client.server_capibilities.hoverProvider = false
				end
			end
		end,

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
		},
		formatting = {
			disabled = {},
			format_on_save = {
				enabled = true,
				allow_filetypes = {
					"python",
					"lua",
				},
			},
		},
	},
}
