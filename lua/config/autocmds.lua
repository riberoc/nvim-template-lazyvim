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

local balance_group = vim.api.nvim_create_augroup("BalanceCodeSplits", { clear = true })
local balance_scheduled = false

local function balance_windows()
  if balance_scheduled then
    return
  end

  balance_scheduled = true
  vim.schedule(function()
    balance_scheduled = false

    local current_win = vim.api.nvim_get_current_win()
    local normal_win
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
        normal_win = normal_win or win
      end
    end

    -- Snacks popups are floating windows; balance the underlying layout instead.
    if normal_win then
      pcall(vim.api.nvim_set_current_win, normal_win)
      vim.cmd("wincmd =")
      if vim.api.nvim_win_is_valid(current_win) then
        pcall(vim.api.nvim_set_current_win, current_win)
      end
    end
  end)
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWinLeave", "WinNew", "WinClosed", "TabEnter", "VimResized" }, {
  group = balance_group,
  callback = balance_windows,
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
