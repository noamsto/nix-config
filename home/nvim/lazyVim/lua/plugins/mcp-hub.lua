return {
  "noamsto/mcphub.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  cmd = "MCPHub",
  config = function()
    require("mcphub").setup({
      workspace = {
        enabled = true, -- Default: true
        look_for = { ".mcphub/servers.json", ".vscode/mcp.json", ".cursor/mcp.json" },
        reload_on_dir_changed = true,
        port_range = { min = 40000, max = 41000 },
        get_port = nil, -- Optional custom port function
      },
      global_env = {
        "DBUS_SESSION_BUS_ADDRESS", -- Array-style: uses os.getenv()
      },
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
