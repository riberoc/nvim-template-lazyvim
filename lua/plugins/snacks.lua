return {
  "folke/snacks.nvim",
  opts = {
    notifier = { enabled = true },
    explorer = {
      enabled = true,
      replace_netrw = true,
    },
    picker = {
      sources = {
        explorer = {
          hidden = true,
          ignored = true,
          diagnostics = true,
          diagnostics_open = true,
          layout = { preset = "sidebar", preview = false, layout = { width = 25, min_width = 25 } },
        },
      },
    },
  },
}
