-- Customize None-ls sources

---@type LazySpec
return {
	"nvimtools/none-ls.nvim",
	opts = function(_, config)
		-- config variable is the default configuration table for the setup function call
		local null_ls = require("null-ls")
		local code_actions = null_ls.builtins.code_actions
		local diagnostics = null_ls.builtins.diagnostics
		local formatting = null_ls.builtins.formatting

		-- Check supported formatters and linters
		-- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/formatting
		-- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/diagnostics
		config.sources = {
			-- Set a formatter
			-- null_ls.builtins.formatting.stylua,
			-- null_ls.builtins.formatting.prettier,

			code_actions.gitsigns,
			code_actions.proselint, -- English prose linter
			code_actions.statix, -- Lints and suggestions for Nix.

			-- Diagnostic
			diagnostics.deadnix, -- Scan Nix files for deid code. Formatting
			diagnostics.selene, -- Dockerfile linter
			formatting.prettierd, -- Terraform formatter
			formatting.alejandra,
		}
		return config -- return final config table
	end,
}
