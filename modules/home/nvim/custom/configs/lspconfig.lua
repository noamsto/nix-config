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
				typeCheckingMode = "basic",
			},
		},
	},
})

local ruff_on_attach = function(client, bufnr)
	-- Disable hover in favor of Pyright
	client.server_capabilities.hoverProvider = false
end

lspconfig.ruff_lsp.setup({
	on_attach = ruff_on_attach,
	capabilities = capabilities,
	init_options = {
		logLevel = "debug",
		settings = {
			-- Any extra CLI arguments for `ruff` go here.
			args = {},
		},
	},
})

-- lspconfig.pyright.setup { blabla}

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
