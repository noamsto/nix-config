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

-- protobuf
local protolint_fmt = require("efmls-configs.formatters.protolint")

local fs = require("efmls-configs.fs")
local sourceText = require("efmls-configs.utils").sourceText
protolint = "protolint"
local command = string.format("%s lint -reporter unix '${INPUT}'", fs.executable(protolint))
local protolint_lint = {

	prefix = protolint,
	lintSource = sourceText(protolint),
	lintCommand = command,
	lintStdin = false,
	lintFormats = {
		"%f:%l:%c: %m",
	},
	lintSeverity = 2,
	rootMarkers = {
		".protolint.yaml",
		".protolint.yml",
	},
}

-- -- buf formatting
--
-- local formatter = "buf"
-- local command = string.format("%s format '${INPUT}'", fs.executable(formatter))
--
-- local buf = {
-- 	formatCommand = command,
-- 	formatStdin = false,
-- 	rootMarkers = {
-- 		"buf.yaml",
-- 	},
-- }
--
-- -- buf linting
--
-- local buf_linter = "buf"
-- local buf_lint_command = string.format("%s lint", fs.executable(buf_linter))
--
-- local buf_lint = {
-- 	prefix = buf_linter,
-- 	lintSource = sourceText(buf_linter),
-- 	lintCommand = buf_lint_command,
-- 	lintStdin = false,
-- 	lintFormats = {
-- 		"%f:%l:%c:%m",
-- 	},
-- 	lintSeverity = 2,
-- 	rootMarkers = {
-- 		"buf.yaml",
-- 	},
-- }

-- bash
local shfmt = require("efmls-configs.formatters.shfmt")

local languages = {
	lua = { stylua },
	python = { mypy, black },
	nix = { alejandra },
	yaml = { prettier },
	proto = { protolint_fmt, protolint_lint },
	bash = { shfmt },
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
