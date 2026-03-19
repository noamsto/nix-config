return {
  "noamsto/octo-ai.nvim",
  dependencies = { "pwntester/octo.nvim" },
  event = { "FileType octo", "FileType markdown.gh", "BufReadCmd octo://*" },
  opts = {
    comment_refine = "auto",
    claude_args = { "--model", "sonnet" },
  },
}
