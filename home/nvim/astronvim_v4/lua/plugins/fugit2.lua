return {
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = os.getenv('LIBGIT2_PATH'),
    external_diffview = true,
  },
  dependencies = {
    'MunifTanjim/nui.nvim',
    'nvim-tree/nvim-web-devicons',
    'nvim-lua/plenary.nvim',
    {
      'chrisgrieser/nvim-tinygit', -- optional: for Github PR view
      dependencies = { 'stevearc/dressing.nvim' }
    },
    {
      "AstroNvim/astrocore",

      opts = {
        mappings = {
          n = {
            ["<Leader>F"] = { name = "  Fugit2" },
            ["<Leader>Ff"] = { "<cmd>Fugit2<cr>", desc = "Open Fugit2" },
            ["<Leader>Fd"] = { "<cmd>Fugit2Diff<cr>", desc = "Open Diff view" },
            ["<Leader>Fg"] = { "<cmd>Fugit2Graph<cr>", desc = "Open Git Graph" },
            ["<Leader>Fb"] = { "<cmd>Fugit2Blame<cr>", desc = "Open Git Blame" },
          },
        },
      }
    },
  },
  cmd = { 'Fugit2', 'Fugit2Diff', 'Fugit2Graph', 'Fugit2Blame' },
}
