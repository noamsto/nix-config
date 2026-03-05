return {
  -- Use cmd-based lazy loading to avoid blink.cmp cpath conflict (issue #162, still open)
  -- v2 ships pre-built binaries so no build step needed (v1 required `make build_generator`)
  "mistricky/codesnap.nvim",
  cmd = { "CodeSnap", "CodeSnapSave" },
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
