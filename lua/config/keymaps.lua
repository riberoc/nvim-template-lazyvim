-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local wk = require("which-key")

-- Global handle to track the Zathura job ID
local zathura_job_id = nil

pcall(vim.keymap.del, "n", "<leader>cl")
wk.add({
  { "<leader>cl", group = "LSP" },
  { "<leader>clr", "<cmd>lsp restart basedpyright<CR>", desc = "Restart LSP" },
})

wk.add({
  { "<leader>cg", "<cmd>DogeGenerate<cr>", desc = "Generate DocString", mode = "n" },
  { "<leader>l", group = "latex" },
  {
    "<leader>ll",
    function()
      if vim.bo.filetype ~= "tex" then
        vim.notify("Not a LaTeX file!", vim.log.levels.WARN)
        return
      end
      local file = vim.fn.expand("%:p")
      local pdf = vim.fn.expand("%:p:r") .. ".pdf"

      -- Save current buffer before compiling
      vim.cmd("silent write")
      local file = vim.fn.expand("%:p")
      local file_dir = vim.fn.expand("%:p:h") -- Extract directory containing the file
      local pdf = vim.fn.expand("%:p:r") .. ".pdf"

      vim.fn.jobstart({ "latexmk", "-pdf", "-interaction=nonstopmode", file }, {
        cwd = file_dir, -- Set execution context to the file's folder
        on_exit = function(_, exit_code, _)
          if exit_code == 0 then
            vim.notify("LaTeX compiled successfully!", vim.log.levels.INFO)
            if not zathura_job_id or vim.fn.jobwait({ zathura_job_id }, 0)[1] ~= -1 then
              zathura_job_id = vim.fn.jobstart({ "zathura", pdf }, { cwd = file_dir })
            end
          else
            vim.notify("LaTeX compilation failed! Check logs.", vim.log.levels.ERROR)
          end
        end,
      })
    end,
    desc = "Compile LaTeX and Open PDF",
    mode = "n",
  },
  {
    "<leader>lc",
    function()
      if vim.bo.filetype ~= "tex" then
        vim.notify("Not a LaTeX file!", vim.log.levels.WARN)
        return
      end
      local file = vim.fn.expand("%:p")
      local pdf = vim.fn.expand("%:p:r") .. ".pdf"

      -- Save current buffer before compiling
      vim.cmd("silent write")
      local file = vim.fn.expand("%:p")
      local file_dir = vim.fn.expand("%:p:h") -- Extract directory containing the file
      local pdf = vim.fn.expand("%:p:r") .. ".pdf"

      vim.fn.jobstart({ "latexmk", "-c", "-interaction=nonstopmode", file }, {
        cwd = file_dir, -- Set execution context to the file's folder
        on_exit = function(_, exit_code, _)
          if exit_code == 0 then
            vim.notify("LaTeX files cleaned successfully!", vim.log.levels.INFO)
          else
            vim.notify("LaTeX file cleaning failed! .", vim.log.levels.ERROR)
          end
        end,
      })
    end,
    desc = "Clean LaTex compilation files",
    mode = "n",
  },
})

-- -- Clean the build files and close the zathura window
-- vim.api.nvim_create_autocmd("VimLeavePre", {
--   pattern = "*.tex",
--   callback = function()
--     -- Clean up intermediate LaTeX files (keeps the PDF)
--     local file = vim.fn.expand("%:p")
--     if file ~= "" then
--       vim.fn.jobstart({ "latexmk", "-c", file })
--     end
--
--     -- Kill Zathura process if running
--     if zathura_job_id and vim.fn.jobwait({ zathura_job_id }, 0)[1] == -1 then
--       vim.fn.jobstop(zathura_job_id)
--     end
--   end,
-- })
--
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.tex",
  callback = function()
    local file = vim.fn.expand("%:p")
    local file_dir = vim.fn.expand("%:p:h") -- Extract directory containing the file
    local pdf = vim.fn.expand("%:p:r") .. ".pdf"

    vim.fn.jobstart({ "latexmk", "-pdf", "-interaction=nonstopmode", file }, {
      cwd = file_dir, -- Set execution context to the file's folder
      on_exit = function(_, exit_code, _)
        if exit_code == 0 then
          -- If Zathura isn't running yet, open it
          if not zathura_job_id or vim.fn.jobwait({ zathura_job_id }, 0)[1] ~= -1 then
            zathura_job_id = vim.fn.jobstart({ "zathura", pdf }, { cwd = file_dir })
          end
        else
          vim.notify("LaTeX compilation failed on save!", vim.log.levels.WARN)
        end
      end,
    })
  end,
})

-- Remove snacks terminal keymaps (LazyVim defaults)
pcall(vim.keymap.del, "n", "<leader>ft")
pcall(vim.keymap.del, "n", "<leader>fT")
pcall(vim.keymap.del, "n", "<c-/>")
pcall(vim.keymap.del, "t", "<c-/>")

-- Generate typed `self.arg: Type = arg` lines from __init__ definition
vim.keymap.set("n", "<leader>cI", function()
  -- Read all lines of the `def __init__` header in case it spans multiple lines
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local total_lines = vim.api.nvim_buf_line_count(0)

  local full_text = ""
  local end_row = row
  for i = row, math.min(row + 15, total_lines) do
    local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1] or ""
    full_text = full_text .. " " .. line
    if line:find("%)") then
      end_row = i
      break
    end
  end

  local params_str = full_text:match("%((.*)%)")
  if not params_str then
    print("No parameters found!")
    return
  end

  local indent = full_text:match("^%s*") .. "    "
  local lines = {}

  -- Split parameters safely while respecting nested brackets like list[GuardrailBase]
  local current_param = ""
  local depth = 0
  local params = {}

  for i = 1, #params_str do
    local char = params_str:sub(i, i)
    if char == "[" or char == "(" or char == "{" then
      depth = depth + 1
      current_param = current_param .. char
    elseif char == "]" or char == ")" or char == "}" then
      depth = depth - 1
      current_param = current_param .. char
    elseif char == "," and depth == 0 then
      table.insert(params, current_param)
      current_param = ""
    else
      current_param = current_param .. char
    end
  end
  if #current_param > 0 then
    table.insert(params, current_param)
  end

  -- Process each parameter
  for _, param in ipairs(params) do
    -- Trim whitespace
    param = param:match("^%s*(.-)%s*$")

    -- Strip default values if present (e.g., arg: int = 5 -> arg: int)
    param = param:gsub("=%s*.*", ""):match("^%s*(.-)%s*$")

    if param ~= "" and param ~= "self" and not param:match("^%*") then
      local name, type_hint = param:match("^([^:]+):%s*(.+)$")

      if name and type_hint then
        name = name:match("^%s*(.-)%s*$")
        type_hint = type_hint:match("^%s*(.-)%s*$")
        table.insert(lines, string.format("%sself.%s: %s = %s", indent, name, type_hint, name))
      else
        -- Fallback if parameter has no type hint
        table.insert(lines, string.format("%sself.%s = %s", indent, param, param))
      end
    end
  end

  if #lines > 0 then
    vim.api.nvim_buf_set_lines(0, end_row, end_row, false, lines)
  end
end, { desc = "Generate typed self assignments from __init__" })
