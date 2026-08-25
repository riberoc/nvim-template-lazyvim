return {
  "folke/snacks.nvim",
  opts = {
    notifier = { enabled = true },
    explorer = {
      replace_netrw = true,
    },
    picker = {
      sources = {
        explorer = {
          -- show hidden files like .env
          hidden = true,
          -- show files ignored by git like node_modules
          ignored = true,
          diagnostics = true,
          diagnostics_open = true,
          layout = { preset = "sidebar", preview = false, layout = { width = 25, min_width = 25 } },
        },
      },
    },
  },
}
