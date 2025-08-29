return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = true,
  keys = {
    { "<leader>ac", nil, desc = "AI/Claude Code" },
    { "<leader>acc", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
    { "<leader>acf", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
    { "<leader>acr", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
    { "<leader>acC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    { "<leader>acm", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
    { "<leader>acb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
    { "<leader>acs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
    {
      "<leader>acs",
      "<cmd>ClaudeCodeTreeAdd<cr>",
      desc = "Add file",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles" },
    },
    -- Diff management
    { "<leader>aca", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>acd", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
  },
}
