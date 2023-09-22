local utils = require "astronvim.utils"
return {
  colorscheme = "catppuccin",

  options = {
    opt = {
      signcolumn = "auto", -- Show sign column when used only
      spell = false,       -- Spell checking
      swapfile = false,    -- Swapfile
    },
  },

  plugins = {
    "AstroNvim/astrocommunity",
    -- colorscheme - catppuccin
    { import = "astrocommunity.colorscheme.catppuccin" },
    -- Highly experimental plugin that completely replaces
    -- the UI for messages, cmdline and the popupmenu.
    {
      import = "astrocommunity.utility.noice-nvim"
    },
    {
      "folke/noice.nvim",
      opts = {
        lsp = {
          hover = {
            silent = true
          }
        },
      }
    },
    -- Navigation
    -- { import = "astrocommunity.motion.flit-nvim" },  -- f F t T leap like, didn't work so well
    { import = "astrocommunity.scrolling.nvim-scrollbar" },
    -- { import = "astrocommunity.editing-support.auto-save-nvim" },

    -- Editing support
    { import = "astrocommunity.editing-support.todo-comments-nvim" },
    { import = "astrocommunity.editing-support.telescope-undo-nvim" },
    { import = "astrocommunity.editing-support.refactoring-nvim" },
    {
      "ThePrimeagen/refactoring.nvim",
      keys = {
        {
          "<leader>rr",
          nil,
        }
      }
    },
    -- The plugin offers the abilibty to search and replace.
    { import = "astrocommunity.project.nvim-spectre" },


    -- Language Support
    ---- Configuration Language
    { import = "astrocommunity.pack.markdown" },
    { import = "astrocommunity.pack.json" },
    { import = "astrocommunity.pack.yaml" },
    { import = "astrocommunity.pack.toml" },
    ---- Backend
    { import = "astrocommunity.pack.lua" },
    { import = "astrocommunity.pack.python" },
    ---- Operation & Cloud Native
    { import = "astrocommunity.pack.terraform" },
    { import = "astrocommunity.pack.bash" },
    { import = "astrocommunity.pack.docker" },
    -- Motion
    { import = "astrocommunity.motion.nvim-surround" },
    { import = "astrocommunity.motion.flash-nvim" },
    -- Lua implementation of CamelCaseMotion, with extra consideration of punctuation.
    { import = "astrocommunity.motion.nvim-spider" },

    -- Note taking
    { import = "astrocommunity.note-taking.neorg" },

    -- markdown preview
    {
      '0x00-ketsu/markdown-preview.nvim',
      ft = { 'md', 'markdown', 'mkd', 'mkdn', 'mdwn', 'mdown', 'mdtxt', 'mdtext', 'rmd', 'wiki' },
      config = function()
        require('markdown-preview').setup {
          -- your configuration comes here
          -- or leave it empty to use the default settings
          -- refer to the setup section below
        }
      end,
    },

    -- clipboard manager
    { import = "astrocommunity.editing-support.yanky-nvim" },
    {
      "gbprod/yanky.nvim",
      opts = {
        ring = {
          storage = "shada"
        }
      }
    },
    {
      "gbprod/yanky.nvim",
      keys = {
        {
          "<leader>yh",
          function() require("telescope").extensions.yank_history.yank_history {} end,
          desc = "Open Yank History",
        },
      }
    },

    -- Enhanced matchparen.vim plugin for Neovim to highlight the outer pair.
    {
      "utilyre/sentiment.nvim",
      version = "*",
      event = "VeryLazy", -- keep for lazy loading
      opts = {
        -- config
      },
      init = function()
        -- `matchparen.vim` needs to be disabled manually in case of lazy loading
        vim.g.loaded_matchparen = 1
      end,
    },

    -- File explorer(Custom configs)
    {
      "nvim-neo-tree/neo-tree.nvim",
      opts = {
        filesystem = {
          filtered_items = {
            visible = true, -- visible by default
            hide_dotfiles = false,
            hide_gitignored = false,
          },
        },
      }
    },

    -- full signature help, docs and completion for the nvim lua API.
    { "folke/neodev.nvim",                                 opts = {} },
    { "RRethy/vim-illuminate",                             config = function() end },

    -- Language Parser for syntax highlighting / indentation / folding / Incremental selection
    {
      "nvim-treesitter/nvim-treesitter",
      opts = function(_, opts)
        local utils = require "astronvim.utils";
        opts.incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-c>",    -- Ctrl + c
            node_incremental = "<C-c>",
            scope_incremental = "<A-c>", -- Alt + c
            node_decremental = "<bs>",   -- Backspace
          },
        }
        opts.ensure_installed = utils.list_insert_unique(opts.ensure_installed, {
          -- neovim
          "vim",
          "lua",
          -- operation & cloud native
          "dockerfile",
          "hcl",
          "regex",
          "terraform",
          "nix",
        })
      end,
    },

    -- implementation/definition preview
    {
      'rmagatti/goto-preview',
      config = function()
        require('goto-preview').setup {}
      end
    },

    -- Install lsp, formmatter and others via home manager instead of Mason.nvim
    -- LSP installations
    {
      "williamboman/mason-lspconfig.nvim",
      -- overwrite ensure_installed to install lsp via home manager(except emmet_ls)
      disabled = true,
      opts = function(_, opts)
        opts.ensure_installed = nil
      end,
    },

    -- Formatters/Linter installation
    {
      "jose-elias-alvarez/null-ls.nvim",
      opts = function(_, opts)
        local null_ls = require "null-ls"
        local code_actions = null_ls.builtins.code_actions
        local diagnostics = null_ls.builtins.diagnostics
        local formatting = null_ls.builtins.formatting
        -- https://github.com/jose-elias-alvarez/null-ls.nvim/blob/main/doc/BUILTINS.md
        utils.list_insert_unique(
          opts.sources, {
            -- Common Code Actions
            code_actions.gitsigns,
            code_actions.shellcheck,
            code_actions.proselint, -- English prose linter
            code_actions.statix,    -- Lints and suggestions for Nix.

            -- backend
            diagnostics.mypy, -- Python type checker

            -- Diagnostic
            diagnostics.actionlint,                     -- GitHub Actions workflow syntax checking
            diagnostics.deadnix,                        -- Scan Nix files for deid code. Formatting
            diagnostics.hadolint,                       -- Dockerfile linter
            formatting.black,                           -- Python formatter
            formatting.shfmt,                           -- Shell formatter
            formatting.stylua,                          -- Lua formatter
            formatting.taplo,                           -- TOML formatteautoindentr
            formatting.terraform_fmt,                   -- Terraform formatter
            formatting.alejandra,                       -- Nix formatter
            formatting.sqlfluff.with({                  -- SQL formatter
              extra_args = { "--dialect", "postgres" }, -- change to your dialect
            }),
          }
        )
        return opts
      end,
    },
    {
      "jay-babu/mason-null-ls.nvim",
      -- ensure_installed nothing
      opts = function(_, opts)
        opts.ensure_installed = nil
        opts.automatic_installation = false
      end,
    },
    -- Debugger installation
    {
      "jay-babu/mason-nvim-dap.nvim",
      -- overrides `require("mason-nvim-dap").setup(...)`
      opts = function(_, opts)
        opts.ensure_installed = nil
        opts.automatic_installation = false
      end,
    },

    {
      'nvim-telescope/telescope.nvim',
      branch = '0.1.x',
      dependencies = { 'nvim-lua/plenary.nvim' },
      init = function()
        -- 1. Disable highlighting for certain filetypes
        -- 2. Ignore files larger than a certain filesize
        local previewers = require("telescope.previewers")

        local _bad = { ".*%.csv", ".*%.min.js" } -- Put all filetypes that slow you down in this array
        local filesize_threshold = 1024 * 1024   -- 300KB
        local bad_files = function(filepath)
          for _, v in ipairs(_bad) do
            if filepath:match(v) then
              return false
            end
          end
          return true
        end

        local new_maker = function(filepath, bufnr, opts)
          opts = opts or {}
          if opts.use_ft_detect == nil then opts.use_ft_detect = true end

          -- 1. Check if the file is in the bad_files array, and if so, don't highlight it
          opts.use_ft_detect = opts.use_ft_detect == false and false or bad_files(filepath)

          -- 2. Check the file size, and ignore it if it's too big(preview nothing).
          filepath = vim.fn.expand(filepath)
          vim.loop.fs_stat(filepath, function(_, stat)
            if not stat then return end
            if stat.size > filesize_threshold then
              return
            else
              previewers.buffer_previewer_maker(filepath, bufnr, opts)
            end
          end)
        end

        require("telescope").setup {
          defaults = {
            buffer_previewer_maker = new_maker,
          }
        }
      end,
    },
    { "sitiom/nvim-numbertoggle", event = "VeryLazy" },
    -- Pyright type-stubs
    {
      "microsoft/python-type-stubs",
    },
  },

  -- Configure require("lazy").setup() options
  lazy = {
    defaults = { lazy = true },
    performance = {
      rtp = {
        -- customize default disabled vim plugins
        disabled_plugins = {},
      },
    },
  },

  -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
  lsp = {
    config = {
      pylsp = {
        cmd = { "nvim-python3", "-m", "pylsp" },
        settings = {
          pylsp = {
            plugins = {
              ruff = { enabled = false, ignore = { "E501" }, hover = false },
              python_lsp_black = { enabled = false, line_length = 99 },
              pylsp_mypy = { enabled = true, hover = false },
              jedi = { enabled = false },
              jedi_hover = { enabled = false },
              jedi_completion = { enabled = false },
              jedi_definition = { enabled = false },
              jedi_references = { enabled = false },
              jedi_symbols = { enabled = false },
              jedi_signature_help = { enabled = false },
            },
          },
        },
      },
      pyright = {
        settings = {
          python = {
            analysis = {
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = "openFilesOnly",
              typeCheckingMode = "off",
              stubPath = vim.fn.stdpath("data") .. "/lazy/python-type-stubs",
            },
          },
        },
      },
    },
    on_attach = function(client, buffer)
      local clients_no_hover = { "ruff_lsp", "pylsp" }
      for _, no_hover_client_name in pairs(clients_no_hover) do
        if client.name == no_hover_client_name then
          client.server_capibilities.hoverProvider = false
          client.server_capibilities.renameProvider = false
        end
      end
    end,

    -- enable servers that installed by home-manager instead of mason
    servers = {
      ---- Configuration Language
      "marksman", -- markdown ls
      "jsonls",   -- json language server
      "yamlls",   -- yaml language server
      "taplo",    -- toml language server
      ---- Backend
      "lua_ls",   -- lua
      "pyright",  -- python
      "ruff_lsp", -- extremely fast Python linter and code transformation
      "nil_ls",   -- nix language server
      "pylsp",
      ---- Operation & Cloud Nativautoindente
      "bashls",      -- bash
      "dockerls",    -- dockerfile
      "terraformls", -- terraform hcl
    },
    formatting = {
      disabled = {},
      format_on_save = {
        enabled = true,
        allow_filetypes = {
          "python",
          "lua"
        },
      },
    },
  },


}
