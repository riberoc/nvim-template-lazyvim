-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.relativenumber = false

vim.g.doge_doc_standard_python = "google"

vim.opt.wrap = false

-- Keep split panes balanced when other windows are opened or closed.
vim.opt.equalalways = true
vim.opt.eadirection = "ver"

vim.g.lazyvim_python_lsp = "ty"
vim.g.lazyvim_python_ruff = "ruff"

vim.g.maplocalleader = ","
vim.g.tex_flavor = "latex"

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})

vim.opt.colorcolumn = "80"
