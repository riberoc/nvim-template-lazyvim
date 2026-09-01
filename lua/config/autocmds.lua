-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--

local tex_group = vim.api.nvim_create_augroup("TexFiletypeFix", { clear = true })

-- LazyVim restores its default clipboard setting during startup. Keep normal
-- yanks separate from the desktop clipboard unless `"+` is used explicitly.
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.opt.clipboard = ""
  end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.tex",
  group = tex_group,
  callback = function()
    vim.bo.filetype = "tex"
  end,
})

-- Automatically open PDF files in Zathura when selected/opened
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "*.pdf",
  callback = function(ev)
    -- Launch zathura in the background detached from Neovim
    vim.fn.jobstart({ "zathura", ev.file }, { detach = true })

    -- Wipe out the raw binary buffer Neovim just created
    vim.api.nvim_buf_delete(ev.buf, { force = true })
  end,
})
