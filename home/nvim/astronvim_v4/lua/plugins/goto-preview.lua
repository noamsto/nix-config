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
            ["gpd"] = {
              function()
                require("goto-preview").goto_preview_definition()
              end,
              desc = "Goto Preview Definition",
            },
            ["gpt"] = {
              function()
                require("goto-preview").goto_preview_type_definition()
              end,
              desc = "Goto Preview Type Definition",
            },
            ["gpi"] = {
              function()
                require("goto-preview").goto_preview_implementation()
              end,
              desc = "Goto Preview Implementation",
            },
            ["gpc"] = {
              function()
                require("goto-preview").close_all_win()
              end,
              desc = "Close All Win",
            },
            ["gpr"] = {
              function()
                require("goto-preview").goto_preview_references()
              end,
              desc = "Goto Preview References",
            },
          },
        },
      },
    },
  },
}
