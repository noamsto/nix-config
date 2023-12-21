-- lua
local stylua = require("efmls-configs.formatters.stylua")

-- python
local mypy = require("efmls-configs.linters.mypy") -- Works better with Django

-- nix
local alejandra = require("efmls-configs.formatters.alejandra")

-- yaml (and others)
local prettier = require("efmls-configs.formatters.prettier")

-- protobuf
local buf_fmt = require("efmls-configs.formatters.buf")
local buf_lint = require("efmls-configs.linters.buf")

-- bash
local shfmt = require("efmls-configs.formatters.shfmt")

local languages = {
	lua = { stylua },
	python = { mypy },
	nix = { alejandra },
	yaml = { prettier },
	html = { prettier },
	css = { prettier },
	proto = { buf_fmt, buf_lint },
	sh = { shfmt },
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
