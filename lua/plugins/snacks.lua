return {
  "folke/snacks.nvim",
  opts = {
    notifier = { enabled = true },
    explorer = {
      replace_netrw = false,
      enabled = false,
      hidden = true,
      exclude = { "__pycache__", "**/__pycache__", "*.class", "*.pyc", "*.pyo" },
      ignored = true,
      diagnostics = true,
      diagnostics_open = true,
      layout = { preset = "sidebar", preview = false, layout = { width = 25, min_width = 25 } },
    },
  },
}
