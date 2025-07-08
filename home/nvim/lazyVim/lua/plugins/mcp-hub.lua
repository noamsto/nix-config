return {
  "ravitemer/mcphub.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  cmd = "MCPHub",
  config = function()
    require("mcphub").setup({
      auto_approve = false,
      extensions = {
        avante = {
          enabled = true,
          make_slash_commands = true,
        },
      },
    })
  end,
}
