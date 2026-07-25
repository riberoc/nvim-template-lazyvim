-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
-- Generate comment for current line

-- delete original mapping if needed
--
local wk = require("which-key")

wk.add({
  { "<leader>cg", "<cmd>DogeGenerate<cr>", desc = "Generate DocString", mode = "n" },
})

vim.keymap.set("n", "<leader>ll", function()
  local tex = vim.fn.expand("%:p")
  local pdf = vim.fn.expand("%:p:r") .. ".pdf"

  -- open zathura once, detached, ignore if already running
  vim.fn.jobstart({ "zathura", pdf }, { detach = true })

  -- compile loop, no viewer spawn
  vim.cmd("terminal latexmk -pdf -pvc -view=none " .. vim.fn.shellescape(tex))
end, { desc = "Build latex + preview in zathura" })
-- remove snacks terminal keymaps (LazyVim defaults)
pcall(vim.keymap.del, "n", "<leader>ft")
pcall(vim.keymap.del, "n", "<leader>fT")
pcall(vim.keymap.del, "n", "<c-/>")
pcall(vim.keymap.del, "t", "<c-/>")
