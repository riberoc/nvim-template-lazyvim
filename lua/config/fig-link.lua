-- ~/.config/nvim/lua/fig-link.lua
--
-- fig:path/to/file.png  ->  underlined link
--   gf / double-click   ->  open with system viewer
--   CursorHold on link  ->  inline image preview in a floating window
--
-- Requires: 3rd/image.nvim, kitty (or compatible) terminal.
--
-- Debug:
--   :lua require("fig-link").debug(true)   -- verbose logging via :messages
--   :lua require("fig-link").debug(false)  -- silence
--   :FigLinkInspect                        -- dump current preview state

local M = {}

-- ---------------------------------------------------------------------------
-- config / state
-- ---------------------------------------------------------------------------

local FIG_PATTERN = "fig:([^%s%)%]\"']+)"

local DEBUG = false
local function log(msg)
  if DEBUG then
    vim.schedule(function()
      vim.notify("[fig-link] " .. msg, vim.log.levels.INFO)
    end)
  end
end

function M.debug(on)
  DEBUG = on and true or false
  vim.notify("[fig-link] debug = " .. tostring(DEBUG), vim.log.levels.INFO)
end

local ok_image, image = pcall(require, "image")

local preview_image = nil
local preview_win = nil
local preview_buf = nil
local last_path = nil

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function get_fig_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local start_idx = 1
  while true do
    local s, e, path = line:find(FIG_PATTERN, start_idx)
    if not s then
      return nil
    end
    if col >= s and col <= e then
      return path
    end
    start_idx = e + 1
  end
end

local function resolve_path(path)
  if path:match("^/") or path:match("^~") then
    return vim.fn.expand(path)
  end
  local bufdir = vim.fn.expand("%:p:h")
  return bufdir .. "/" .. path
end

local function ensure_transparent_float_hl()
  -- NormalFloat with an opaque bg will paint over the kitty graphic.
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "NormalFloat", link = false })
  if not ok or (hl and hl.bg ~= nil) then
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
  end
end

-- ---------------------------------------------------------------------------
-- preview lifecycle
-- ---------------------------------------------------------------------------

local function close_preview()
  if preview_image then
    pcall(function()
      preview_image:clear()
    end)
    preview_image = nil
  end
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    pcall(vim.api.nvim_win_close, preview_win, true)
  end
  if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
    pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
  end
  preview_win = nil
  preview_buf = nil
  last_path = nil
end

local function show_preview(path)
  if not ok_image then
    log("image.nvim not loaded")
    return
  end
  if path == last_path and preview_win and vim.api.nvim_win_is_valid(preview_win) then
    log("already showing " .. path)
    return
  end

  local full = resolve_path(path)
  log("resolve " .. path .. " -> " .. full)
  if vim.fn.filereadable(full) == 0 then
    log("not readable: " .. full)
    return
  end

  close_preview()
  ensure_transparent_float_hl()

  -- ----- scratch buffer -----
  local ok_buf, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok_buf or not buf then
    log("nvim_create_buf failed")
    return
  end
  preview_buf = buf

  local width, height = 60, 20

  -- Fill buffer with blank lines. image.nvim needs real cells under the
  -- image or the terminal will not commit the graphic to those rows.
  local blank = {}
  for _ = 1, height do
    table.insert(blank, string.rep(" ", width))
  end
  pcall(vim.api.nvim_buf_set_lines, preview_buf, 0, -1, false, blank)

  -- Mark the filetype so image.nvim's overlap-clear can ignore it.
  pcall(vim.api.nvim_set_option_value, "filetype", "fig_preview", { buf = preview_buf })
  pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = preview_buf })
  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = preview_buf })

  -- ----- float window (anchored to editor, not cursor) -----
  -- editor-relative avoids cursor-position calc bugs in image.nvim popups.
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines
  local col_pos = math.max(0, math.min(editor_w - width - 2, vim.fn.wincol() + 2))
  local row_pos = math.max(0, math.min(editor_h - height - 2, vim.fn.winline()))

  local ok_win, win = pcall(vim.api.nvim_open_win, preview_buf, false, {
    relative = "editor",
    row = row_pos,
    col = col_pos,
    width = width,
    height = height,
    style = "minimal",
    focusable = false,
    zindex = 50,
    -- No border on purpose: some border configs paint cells over the graphic.
  })
  if not ok_win or not win then
    log("nvim_open_win failed")
    close_preview()
    return
  end
  preview_win = win

  -- Force transparent bg on the float; nonzero winblend forces solid black.
  pcall(
    vim.api.nvim_set_option_value,
    "winhighlight",
    "Normal:NormalFloat,NormalFloat:NormalFloat",
    { win = preview_win }
  )
  pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = preview_win })

  log(
    string.format(
      "float win=%d buf=%d at row=%d col=%d %dx%d",
      preview_win,
      preview_buf,
      row_pos,
      col_pos,
      width,
      height
    )
  )

  -- ----- create the image -----
  -- Do NOT pass `buffer` here. image.nvim treats buffer= as "inline in this
  -- text buffer" and uses extmarks/virtual padding, which fights with a
  -- dedicated float. Passing only `window` renders the image into the
  -- window's cell grid, which is what we want.
  local from_file_opts = {
    window = preview_win,
    width = width, -- cells
    height = height, -- cells
    with_virtual_padding = false,
    inline = false,
  }

  local ok_img, img_or_err = pcall(image.from_file, full, from_file_opts)

  log("from_file ok=" .. tostring(ok_img) .. " val=" .. vim.inspect(img_or_err))

  if not ok_img or not img_or_err or type(img_or_err) ~= "table" then
    close_preview()
    vim.notify("[fig-link] failed to load image: " .. full, vim.log.levels.WARN)
    return
  end
  preview_image = img_or_err
  last_path = path

  -- Render synchronously first; some backends need a follow-up render after
  -- the float's cells are committed, so also schedule one on the next tick.
  local function do_render()
    if not preview_image then
      return
    end
    if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
      return
    end
    -- Some image.nvim versions expose :render(geometry). Try that first,
    -- fall back to plain :render() on older versions.
    local ok_r, err_r = pcall(function()
      preview_image:render({ x = 0, y = 0, width = width, height = height })
    end)
    if not ok_r then
      ok_r, err_r = pcall(function()
        preview_image:render()
      end)
    end
    log(
      string.format(
        "render ok=%s is_rendered=%s rendered_geometry=%s",
        tostring(ok_r),
        tostring(preview_image.is_rendered),
        vim.inspect(preview_image.rendered_geometry)
      )
    )
  end

  do_render()
  vim.schedule(do_render)
  vim.defer_fn(do_render, 50)
end

-- ---------------------------------------------------------------------------
-- gf / double-click: open with system viewer
-- ---------------------------------------------------------------------------

local function open_with_system(path)
  local full = resolve_path(path)
  if vim.fn.filereadable(full) == 0 then
    vim.notify("[fig-link] file not found: " .. full, vim.log.levels.WARN)
    return
  end
  if vim.ui.open then
    vim.ui.open(full)
    return
  end
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = { "open", full }
  elseif vim.fn.has("unix") == 1 then
    cmd = { "xdg-open", full }
  elseif vim.fn.has("win32") == 1 then
    cmd = { "cmd.exe", "/c", "start", "", full }
  end
  if not cmd then
    vim.notify("[fig-link] no opener for this OS", vim.log.levels.WARN)
    return
  end
  vim.fn.jobstart(cmd, { detach = true })
end

function M.open_fig()
  local path = get_fig_under_cursor()
  if not path then
    vim.notify("[fig-link] no fig: reference under cursor", vim.log.levels.INFO)
    return
  end
  open_with_system(path)
end

-- ---------------------------------------------------------------------------
-- inspection command
-- ---------------------------------------------------------------------------

function M.inspect_state()
  local info = {
    ok_image = ok_image,
    preview_win = preview_win,
    win_valid = preview_win and vim.api.nvim_win_is_valid(preview_win),
    preview_buf = preview_buf,
    buf_valid = preview_buf and vim.api.nvim_buf_is_valid(preview_buf),
    last_path = last_path,
    preview_image = preview_image and "<image handle>" or nil,
  }
  vim.notify("[fig-link] state = " .. vim.inspect(info), vim.log.levels.INFO)

  if ok_image then
    local ok, imgs = pcall(function()
      return image.get_images()
    end)
    if ok then
      vim.notify("[fig-link] image.get_images() = " .. vim.inspect(imgs), vim.log.levels.INFO)
    else
      vim.notify("[fig-link] image.get_images() failed: " .. tostring(imgs), vim.log.levels.WARN)
    end
  end
end

-- ---------------------------------------------------------------------------
-- setup
-- ---------------------------------------------------------------------------

local did_setup = false

function M.setup(opts)
  if did_setup then
    return
  end
  did_setup = true

  opts = opts or {}
  local keymap = opts.keymap or "gf"
  if opts.debug then
    DEBUG = true
  end

  if not ok_image then
    vim.notify("[fig-link] image.nvim not found; preview disabled", vim.log.levels.WARN)
  end

  vim.keymap.set("n", keymap, M.open_fig, { desc = "Open fig: reference (system viewer)" })
  vim.keymap.set("n", "<2-LeftMouse>", M.open_fig, { desc = "Open fig: reference (system viewer)" })

  vim.api.nvim_set_hl(0, "FigLink", { link = "Underlined", default = true })

  vim.api.nvim_create_user_command("FigLinkInspect", function()
    M.inspect_state()
  end, {})
  vim.api.nvim_create_user_command("FigLinkDebug", function(a)
    M.debug(a.args ~= "off")
  end, { nargs = "?" })

  local group = vim.api.nvim_create_augroup("FigLink", { clear = true })

  local match_id
  local function apply_match()
    if match_id then
      pcall(vim.fn.matchdelete, match_id)
      match_id = nil
    end
    local ok, id = pcall(vim.fn.matchadd, "FigLink", [[fig:\S\+]])
    if ok then
      match_id = id
    end
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "ColorScheme" }, {
    group = group,
    callback = apply_match,
  })
  apply_match()

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      -- Never trigger from inside our own float.
      if vim.api.nvim_get_current_win() == preview_win then
        return
      end
      local path = get_fig_under_cursor()
      if path then
        show_preview(path)
      else
        close_preview()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinLeave" }, {
    group = group,
    callback = function()
      -- Ignore movement inside our own preview window.
      if vim.api.nvim_get_current_win() == preview_win then
        return
      end
      close_preview()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = close_preview,
  })
end

return M
