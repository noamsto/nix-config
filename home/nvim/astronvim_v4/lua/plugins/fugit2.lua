return {
  'SuperBo/fugit2.nvim',
  opts = {
    libgit2_path = os.getenv('LIBGIT2_PATH')
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
            ["<Leader>Ff"] = { "<cmd>Fugit2<cr>", desc = " Fugit2" },
          },
        },
      }
    },
  },
  cmd = { 'Fugit2', 'Fugit2Diff', 'Fugit2Graph' },
}
