return {
  "rmagatti/goto-preview",
  event = "BufEnter",
  config = true, -- necessary as per https://github.com/rmagatti/goto-preview/issues/88

  dependencies = {
    {
      "AstroNvim/astrocore",
      opts = {
        mappings = {
          n = {
            ["<LocalLeader>p"] = { name = "󰙔 Goto Preview" },
            ["<LocalLeader>pd"] = {
              function()
                require("goto-preview").goto_preview_definition()
              end,
              desc = "Goto Preview definition",
            },
            ["<LocalLeader>pt"] = {
              function()
                require("goto-preview").goto_preview_type_definition()
              end,
              desc = "Goto Preview type definition",
            },
            ["<LocalLeader>pi"] = {
              function()
                require("goto-preview").goto_preview_implementation()
              end,
              desc = "Goto Preview implementation",
            },
            ["<LocalLeader>pc"] = {
              function()
                require("goto-preview").close_all_win()
              end,
              desc = "Close all preview windows",
            },
            ["<LocalLeader>pr"] = {
              function()
                require("goto-preview").goto_preview_references()
              end,
              desc = "Goto Preview references",
            },
          },
        },
      },
    },
  },
}
