local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out =
    vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  spec = {
    -- 1. Add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- 2. ENABLE JAVA SUPPORT HERE:
    { import = "lazyvim.plugins.extras.lang.java" }, -- Java support
    { import = "lazyvim.plugins.extras.lang.python" }, -- Python (Pyright/Ruff)
    { import = "lazyvim.plugins.extras.lang.clangd" }, -- C / C++ (using clangd)
    { import = "lazyvim.plugins.extras.lang.json" }, -- JSON support
    { import = "lazyvim.plugins.extras.editor.snacks_explorer" }, -- Snacks file explorer
    { "nvim-neo-tree/neo-tree.nvim", enabled = false },
    {
      "neovim/nvim-lspconfig",
      opts = {
        servers = {
          basedpyright = {
            settings = {
              basedpyright = {
                analysis = {
                  typeCheckingMode = "standard",
                },
              },
            },
          },
        },
      },
    },

    -- 3. import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true,
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
