local M = {}

-- State configuration
M.config = {
  theme = "dark", -- Options: "dark", "light"
}

-- Utility to get the corresponding PNG path
local function get_png_path(drawio_file)
  return drawio_file:gsub("%.drawio$", ".png")
end

-- Toggles theme between dark and light, then re-renders current file
function M.toggle_theme()
  M.config.theme = M.config.theme == "dark" and "light" or "dark"
  vim.notify("Draw.io theme set to: " .. M.config.theme, vim.log.levels.INFO)

  -- Force re-render with the new configuration if we are in a drawio or png file
  local current_file = vim.fn.expand("%:p")
  if current_file:match("%.drawio$") or current_file:match("%.png$") then
    M.render_and_open(current_file, true)
  end
end

-- Opens the GUI for the .drawio file
function M.open_in_gui(filepath)
  local file_to_open = filepath

  if filepath:match("%.png$") then
    local possible_drawio = filepath:gsub("%.png$", ".drawio")
    if vim.fn.filereadable(possible_drawio) == 1 then
      file_to_open = possible_drawio
    end
  end

  if not file_to_open:match("%.drawio$") then
    vim.notify("No corresponding .drawio file found", vim.log.levels.WARN)
    return
  end

  vim.fn.jobstart({ "drawio", file_to_open }, { detach = true })
  vim.notify("Opened in Draw.io GUI", vim.log.levels.INFO)
end

-- Renders .drawio to .png using current config and manages buffer switching
function M.render_and_open(filepath, force)
  local drawio_file = filepath
  local is_png = filepath:match("%.png$")

  if is_png then
    drawio_file = filepath:gsub("%.png$", ".drawio")
    if vim.fn.filereadable(drawio_file) == 0 then
      return
    end
  elseif not drawio_file:match("%.drawio$") then
    return
  end

  local png_path = get_png_path(drawio_file)
  local drawio_mtime = vim.fn.getftime(drawio_file)
  local png_mtime = vim.fn.getftime(png_path)

  if force or png_mtime == -1 or drawio_mtime > png_mtime then
    vim.notify("Rendering Draw.io to PNG (" .. M.config.theme .. ")...", vim.log.levels.INFO)

    -- Uses correct `--theme` flag based on state configuration
    vim.system({
      "drawio",
      "--export",
      "--format",
      "png",
      "--theme",
      M.config.theme,
      "--output",
      png_path,
      drawio_file,
    }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          vim.notify("Draw.io export failed:\n" .. (obj.stderr or ""), vim.log.levels.ERROR)
          return
        end

        if not is_png then
          vim.cmd("edit " .. vim.fn.fnameescape(png_path))
        else
          vim.cmd("silent! edit!")
        end

        vim.notify("Diagram updated (" .. M.config.theme .. ")!", vim.log.levels.INFO)
      end)
    end)
  else
    if not is_png then
      vim.cmd("edit " .. vim.fn.fnameescape(png_path))
    end
  end
end

return {
  "drawio-preview",
  dir = vim.fn.stdpath("config"),
  lazy = false,
  config = function()
    -- Autocmd to intercept opening .drawio or .png files
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = { "*.drawio", "*.png" },
      callback = function(args)
        M.render_and_open(args.file, false)
      end,
    })

    -- Keymaps setup
    local wk_ok, wk = pcall(require, "which-key")
    if wk_ok then
      wk.add({
        {
          "<leader>dd",
          function()
            M.open_in_gui(vim.fn.expand("%:p"))
          end,
          desc = "Open in Draw.io GUI",
          mode = "n",
        },
        {
          "<leader>dr",
          function()
            M.render_and_open(vim.fn.expand("%:p"), true)
          end,
          desc = "Render Draw.io PNG",
          mode = "n",
        },
        {
          "<leader>dcl",
          function()
            M.toggle_theme()
          end,
          desc = "Toggle Draw.io Theme (Dark/Light)",
          mode = "n",
        },
      })
    else
      vim.keymap.set("n", "<leader>dd", function()
        M.open_in_gui(vim.fn.expand("%:p"))
      end, { desc = "Open in Draw.io GUI" })

      vim.keymap.set("n", "<leader>dr", function()
        M.render_and_open(vim.fn.expand("%:p"), true)
      end, { desc = "Render Draw.io PNG" })

      vim.keymap.set("n", "<leader>dcl", function()
        M.toggle_theme()
      end, { desc = "Toggle Draw.io Theme (Dark/Light)" })
    end
  end,
}
