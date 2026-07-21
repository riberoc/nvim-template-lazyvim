return {
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "VeryLazy",
    priority = 1000,
    opts = {
      options = {
        break_line = { enabled = true, after = 30 },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = { virtual_text = false },
    },
  },
}
