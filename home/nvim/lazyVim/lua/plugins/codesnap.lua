return {
  -- Pinned to v1.6.3: v2 ships a Rust .so named identically to blink.cmp's fuzzy
  -- matcher, causing a dlsym collision. v1 uses a distinct "generator" symbol name
  -- so there is no conflict. Track: https://github.com/mistricky/codesnap.nvim/issues/162
  "mistricky/codesnap.nvim",
  tag = "v1.6.3",
  build = "make build_generator",
  event = "VeryLazy",
  keys = {
    { "<leader>Cc", "<cmd>CodeSnap<cr>", mode = "x", desc = "Save selected code snapshot into clipboard" },
    { "<leader>Cs", "<cmd>CodeSnapSave<cr>", mode = "x", desc = "Save selected code snapshot in ~/Pictures" },
  },
  opts = {
    save_path = "~/Pictures",
    has_breadcrumbs = true,
    bg_theme = "grape",
    has_line_number = true,
  },
  config = function(_, opts)
    require("codesnap").setup(opts)
    local wk = require("which-key")
    wk.add({ "<leader>C", group = "CodeSnap", mode = { "v" }, icon = { icon = "", color = "azure" } })
  end,
}
