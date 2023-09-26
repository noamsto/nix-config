-- local stylua = require('efmls-configs.formatters.stylua')
-- local languages = {
--   lua = { stylua },
-- }
--
--
-- local efmls_config = {
--   filetypes = vim.tbl_keys(languages),
--   settings = {
--     rootMarkers = { '.git/' },
--     languages = languages,
--   },
--   init_options = {
--     documentFormatting = true,
--     documentRangeFormatting = true,
--   },
-- }
-- local on_attach = require("astronvim.utils.lsp").on_attach
-- local capabailities = require("astronvim.utils.lsp").capabailities

return {
  'creativenull/efmls-configs-nvim',
  version = 'v1.x.x', -- version is optional, but recommended
  dependencies = { 'neovim/nvim-lspconfig' },
}
