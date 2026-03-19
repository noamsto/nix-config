return {
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        -- nerd: nf-md-account_plus, nf-md-comment_text, nf-md-tag, nf-md-alert_circle
        -- nf-md-robot, nf-md-emoticon, nf-md-source_pull, nf-md-source_branch
        -- nf-md-merge, nf-md-eye, nf-md-link_variant
        { "<localleader>a", group = "assignee", icon = { icon = "", color = "blue" } },
        { "<localleader>c", group = "comment", icon = { icon = "", color = "cyan" } },
        { "<localleader>l", group = "label", icon = { icon = "󰓹", color = "yellow" } },
        { "<localleader>i", group = "issue", icon = { icon = "󰀨", color = "orange" } },
        { "<localleader>r", group = "react", icon = { icon = "󰞅", color = "purple" } },
        { "<localleader>p", group = "pr", icon = { icon = "󰊢", color = "green" } },
        { "<localleader>pr", group = "rebase", icon = { icon = "󰘬", color = "green" } },
        { "<localleader>ps", group = "squash", icon = { icon = "󰃸", color = "green" } },
        { "<localleader>v", group = "review", icon = { icon = "󰈈", color = "azure" } },
        { "<localleader>g", group = "goto", icon = { icon = "󰌷", color = "cyan" } },
        { "<localleader>A", group = "ai", icon = { icon = "󰚩", color = "purple" } },
      },
    },
  },
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    event = { { event = "BufReadCmd", pattern = "octo://*" } },
    dependencies = {
      {
        "nvim-treesitter/nvim-treesitter",
        opts = function(_, opts)
          vim.treesitter.language.register("markdown", "octo")
          return opts
        end,
      },
    },
    opts = function(_, opts)
      opts.enable_builtin = true
      opts.default_to_projects_v2 = true
      opts.default_merge_method = "squash"
      opts.picker = "snacks"

      -- Keep some empty windows in sessions
      vim.api.nvim_create_autocmd("ExitPre", {
        group = vim.api.nvim_create_augroup("octo_exit_pre", { clear = true }),
        callback = function(ev)
          local keep = { "octo" }
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.tbl_contains(keep, vim.bo[buf].filetype) then
              vim.bo[buf].buftype = ""
            end
          end
        end,
      })
    end,
    keys = {
      { "<leader>gi", "<cmd>Octo issue list<CR>", desc = "List Issues (Octo)" },
      { "<leader>gI", "<cmd>Octo issue search<CR>", desc = "Search Issues (Octo)" },
      { "<leader>gp", "<cmd>Octo pr list<CR>", desc = "List PRs (Octo)" },
      { "<leader>gP", "<cmd>Octo pr search<CR>", desc = "Search PRs (Octo)" },
      { "<leader>gr", "<cmd>Octo repo list<CR>", desc = "List Repos (Octo)" },
      { "<leader>gS", "<cmd>Octo search<CR>", desc = "Search (Octo)" },

      { "@", "@<C-x><C-o>", mode = "i", ft = "octo", silent = true },
      { "#", "#<C-x><C-o>", mode = "i", ft = "octo", silent = true },
    },
  },
}
