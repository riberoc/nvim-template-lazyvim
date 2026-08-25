return {
  "folke/zen-mode.nvim",
  cmd = "ZenMode",
  opts = {
    window = {
      backdrop = 0.95,
      width = 80, -- Forces the width to 80 units
      options = {
        signcolumn = "no",
        number = false,
        relativenumber = false,
      },
    },
  },
  keys = {
    "<leader>wz",
    "<cmd>ZenMode<cr>",
    desc = "Zen Mode (80 cols)",
  },
}
