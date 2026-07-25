return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  main = "nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "latex",
      "python",
      "java",
    },
  },
}
