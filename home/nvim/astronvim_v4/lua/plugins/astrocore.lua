-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing


local continue = function()
  if vim.fn.filereadable(".vscode/launch.json") then
    require('dap.ext.vscode').json_decode = require 'json5'.parse
    require("dap.ext.vscode").load_launchjs()
  end
  require("dap").continue()
end

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 500, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true,                                 -- enable autopairs at start
      cmp = true,                                       -- enable completion at start
      diagnostics_mode = 3,                             -- diagnostic mode on start (0 = off, 1 = no signs/virtual text, 2 = no virtual text, 3 = on)
      highlighturl = true,                              -- highlight URLs at start
      notifications = true,                             -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- vim options can be configured here
    options = {
      opt = {                  -- vim.opt.<key>
        relativenumber = true, -- sets vim.opt.relativenumber
        number = true,         -- sets vim.opt.number
        spell = true,          -- sets vim.opt.spell
        signcolumn = "auto",   -- sets vim.opt.signcolumn to auto
        wrap = false,          -- sets vim.opt.wrap
        conceallevel = 2
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapLeader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
        sqlite_clib_path = os.getenv('SQLITE3_PATH'),
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized

    mappings = {
      -- first key is the mode
      n = {

        ["[p"] = { "<Plug>(YankyCycleForward)", desc = "Cycle forward through yank history" },
        ["]p"] = { "<Plug>(YankyCycleBackward)", desc = "Cycle backward through yank history" },
        ["<S-CR>"] = { "k" },

        ["<Leader>dc"] = { continue, desc = "Start/Continue (F5)" },

        ["<Leader>dm"] = {
          function()
            require("neotest").run.run({ strategy = "dap" })
          end,
          desc = "Test & Debug Method",
        },

        ["<Leader>df"] = {
          function()
            require("neotest").run.run({ vim.fn.expand("%"), strategy = "dap" })
          end,
          desc = "Test & Debug File",
        },

        -- mappings seen under group name "Buffer"
        ["<Leader>bn"] = { "<cmd>tabnew<cr>", desc = "New tab" },
        -- quick save
        ["<C-s>"] = { ":w!<cr>", desc = "Save File" },

        -- Toggle terminal
        ["<Leader>tp"] = {
          function()
            require("astrocore").toggle_term_cmd("ipython")
          end,
          desc = " ToggleTerm python",
        },

        -- Cycle through buffers
        ["<tab>"] = {
          function()
            require("astrocore.buffer").nav(vim.v.count > 0 and vim.v.count or 1)
          end,
          desc = "Next buffer",
        },
        ["<S-tab>"] = {
          function()
            require("astrocore.buffer").nav(-(vim.v.count > 0 and vim.v.count or 1))
          end,
          desc = "Next buffer",
        },

        -- implementation/definition preview
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

        ["<Leader>r"] = { name = "󰣪 Refactor" },
        ["<Leader>rbf"] = false,
        ["<Leader>rB"] = {
          function() require("refactoring").refactor "Extract Block To File" end,
          desc = "Extract Block To File",
        },

        ["<Leader>tt"] = {
          function()
            require("astrocore").toggle_term_cmd("btop")
          end,
          desc = "ToggleTerm btop",
        },

        -- mappings seen under group name "Buffer"
        ["<Leader>bD"] = {
          function()
            require("astroui.status.heirline").buffer_picker(function(bufnr)
              require("astrocore.buffer").close(bufnr)
            end)
          end,
          desc = "Pick to close",
        },

        --
        --   ["<leader>a"] = { name = " Copilot Chat" },
        --
        --   ["<leader>aq"] = {
        --     function()
        --       local input = vim.fn.input("Quick Chat: ")
        --       if input ~= "" then
        --         require("CopilotChat").ask(input, { selection = require("CopilotChat.select").buffer })
        --       end
        --     end,
        --     desc = "CopilotChat - Quick chat",
        --   },
        --   ["<leader>ah"] = {
        --     function()
        --       local actions = require("CopilotChat.actions")
        --       require("CopilotChat.integrations.telescope").pick(actions.help_actions())
        --     end,
        --     desc = "CopilotChat - Help actions",
        --   },
        --   -- Show prompts actions with telescope
        --
        --   ["<leader>ap"] = {
        --     function()
        --       local actions = require("CopilotChat.actions")
        --       require("CopilotChat.integrations.telescope").pick(actions.prompt_actions())
        --     end,
        --     desc = "CopilotChat - Prompt actions",
        --   },
        --
      },
      v = {
        ["<Leader>r"] = { name = "󰣪 Refactor" },
        ["<Leader>rbf"] = false,
        ["<Leader>rB"] = {
          function() require("refactoring").refactor "Extract Block To File" end,
          desc = "Extract Block To File",
        },
      },
      t = {
        -- setting a mapping to false will disable it
        -- ["<esc>"] = false,
      },
    },
  },
}
