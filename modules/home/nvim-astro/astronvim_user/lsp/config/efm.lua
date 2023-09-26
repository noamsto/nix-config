local stylua = require("efmls-configs.formatters.stylua")
local mypy = require("efmls-configs.linters.mypy")
local alejandra = require("efmls-configs.formatters.alejandra")
local prettier = require("efmls-configs.formatters.prettier")

local languages = {
	lua = { stylua },
	python = { mypy },
	nix = { alejandra },
	yaml = { prettier },
}
local efmls_config = {
	filetypes = vim.tbl_keys(languages),
	settings = {
		rootMarkers = { ".git/" },
		languages = languages,
	},
	init_options = {
		documentFormatting = true,
		documentRangeFormatting = true,
	},
}
return efmls_config
