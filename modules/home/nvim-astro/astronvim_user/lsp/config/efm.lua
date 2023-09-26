-- lua
local stylua = require("efmls-configs.formatters.stylua")

-- python
local mypy = require("efmls-configs.linters.mypy") -- Works better with Django
local black = require("efmls-configs.formatters.black")
black.formatCommand = black.formatCommand .. " --line-length 99"
-- nix
local alejandra = require("efmls-configs.formatters.alejandra")

-- yaml (and others)
local prettier = require("efmls-configs.formatters.prettier")

local languages = {
	lua = { stylua },
	python = { mypy, black },
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
