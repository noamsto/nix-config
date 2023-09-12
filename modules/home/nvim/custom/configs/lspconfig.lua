local config = require("plugins.configs.lspconfig")
local on_attach = config.on_attach
local capabilities = config.capabilities

local lspconfig = require("lspconfig")

-- if you just want default config for the servers then put them in a table
-- local servers = { "pyright" }
--
-- for _, lsp in ipairs(servers) do
-- 	lspconfig[lsp].setup({
-- 		on_attach = on_attach,
-- 		capabilities = capabilities,
-- 	})
-- end

lspconfig.pyright.setup({
	on_attach = on_attach,
	capabilities = capabilities,
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
})

local on_attach_no_hover = function(client, bufnr)
	-- Disable hover in favor of Pyright
	client.server_capabilities.hoverProvider = false
end

lspconfig.ruff_lsp.setup({
	on_attach = on_attach_no_hover,
	capabilities = capabilities,
	init_options = {
		-- logLevel = "debug",
		settings = {
			-- Any extra CLI arguments for `ruff` go here.
			args = { "--ignore=E501" },
		},
	},
})

lspconfig.pylsp.setup({
	on_attach = on_attach_no_hover,
	capabilities = capabilities,
	cmd = { "nvim-python3", "-m", "pylsp" },
	settings = {
		pylsp = {
			plugins = {
				ruff = { enabled = false, ignore = { "E501" }, hover = false },
				python_lsp_black = { enabled = true, line_length = 99 },
				pylsp_mypy = { enabled = true, hover = false },
				jedi = { enabled = false },
				jedi_hover = { enabled = false },
				jedi_completion = { enabled = false },
				jedi_definition = { enabled = false },
				jedi_references = { enabled = false },
				jedi_symbols = { enabled = false },
			},
		},
	},
})

-- local lsp = require('lsp-zero').preset({})
--
-- lsp.on_attach(function(client, bufnr)
--   -- see :help lsp-zero-keybindings
--   -- to learn the available actions
--   lsp.default_keymaps({buffer = bufnr})
-- end)
--
-- -- When you don't have mason.nvim installed
-- -- You'll need to list the servers installed in your system
-- lsp.setup_servers({'pyright', 'ruff-lsp'})
--
-- -- (Optional) Configure lua language server for neovim
-- require('lspconfig').lua_ls.setup(lsp.nvim_lua_ls())
--
-- lsp.setup()
