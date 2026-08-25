return {
  "folke/trouble.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {
    modes = {
      diagnostics = {
        win = {
          type = "split",
          position = "right",
          size = 0.3, -- takes 30% of the screen width
        },
      },
    },
  },
  keys = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle<cr>",
      desc = "Workspace Diagnostics (Trouble)",
    },
  },
}
