-- ~/.config/nvim/lua/fig-link.lua
--
-- fig:path/to/file.png  ->  underlined link
--   gf / double-click   ->  open with system viewer
--   CursorHold on link  ->  inline image preview in a floating window
--
-- Requires: 3rd/image.nvim, kitty (or compatible) terminal, ImageMagick
--           (`identify` on PATH -- image.nvim already depends on this for
--           the magick_cli processor, so it should already be present).
--
-- Debug:
--   :lua require("fig-link").debug(true)   -- verbose logging via :messages
--   :lua require("fig-link").debug(false)  -- silence
--   :FigLinkInspect                        -- dump current preview state

local M = {}

-- ---------------------------------------------------------------------------
-- config / constants
-- ---------------------------------------------------------------------------

local FIG_PATTERN = "fig:([^%s%)%]\"']+)"

-- Upper bound on the preview window size, in terminal cells.
local MAX_WIDTH = 60
local MAX_HEIGHT = 20

-- Terminal character cells are taller than they are wide, so a plain
-- width==columns/height==rows mapping stretches images vertically. Most
-- monospace fonts render cells at roughly a 1:2 width:height pixel ratio;
-- this constant corrects for that when we convert an image's pixel
-- dimensions into a cell geometry. Tweak it if your font is unusually
-- wide/narrow.
local CELL_ASPECT_RATIO = 2.0

-- Border drawn around the preview float. Set to "none" to go back to a
-- borderless window.
local BORDER_STYLE = "rounded"
local BORDER_CELLS = 2 -- border adds ~1 cell on each side, per axis

-- ---------------------------------------------------------------------------
-- debug logging
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- preview state
-- ---------------------------------------------------------------------------

local preview_image = nil
local preview_win = nil
local preview_buf = nil
local last_path = nil

-- ---------------------------------------------------------------------------
-- link detection / path resolution
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
  -- NormalFloat with an opaque bg would paint over the kitty graphic.
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "NormalFloat", link = false })
  if not ok or (hl and hl.bg ~= nil) then
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
  end
end

-- ---------------------------------------------------------------------------
-- aspect-correct geometry
-- ---------------------------------------------------------------------------

-- Reads an image's pixel dimensions via ImageMagick's `identify`. Returns
-- (width, height) or nil on failure (missing binary, unreadable file, etc).
local function get_image_pixel_size(full_path)
  if vim.fn.executable("identify") == 0 then
    log("identify not on PATH; falling back to fixed geometry")
    return nil
  end

  local ok, out = pcall(vim.fn.systemlist, { "identify", "-format", "%w %h", full_path })
  if not ok or vim.v.shell_error ~= 0 or not out or not out[1] then
    log("identify failed for " .. full_path)
    return nil
  end

  local w, h = out[1]:match("(%d+)%s+(%d+)")
  w, h = tonumber(w), tonumber(h)
  if not w or not h or w <= 0 or h <= 0 then
    log("identify returned unparsable size: " .. tostring(out[1]))
    return nil
  end
  return w, h
end

-- Fits an image's pixel size into a max_cols x max_rows cell box, preserving
-- the image's true aspect ratio (after correcting for non-square cells).
-- Returns integer cols, rows, each >= 1.
local function fit_to_cells(img_w, img_h, max_cols, max_rows)
  -- Treat one cell as 1 unit wide, CELL_ASPECT_RATIO units tall, then scale
  -- the image into that pixel-equivalent box and convert back to cells.
  local max_px_w = max_cols
  local max_px_h = max_rows * CELL_ASPECT_RATIO

  local scale = math.min(max_px_w / img_w, max_px_h / img_h)

  local cols = math.max(1, math.floor(img_w * scale + 0.5))
  local rows = math.max(1, math.floor((img_h * scale) / CELL_ASPECT_RATIO + 0.5))
  return cols, rows
end

-- Works out the preview window's content geometry (in cells) for a given
-- file. Falls back to the fixed MAX_WIDTH x MAX_HEIGHT box if the image's
-- real dimensions can't be determined.
local function compute_preview_geometry(full_path)
  local img_w, img_h = get_image_pixel_size(full_path)
  if not img_w then
    return MAX_WIDTH, MAX_HEIGHT
  end

  local cols, rows = fit_to_cells(img_w, img_h, MAX_WIDTH, MAX_HEIGHT)
  log(string.format("geometry %dx%d px -> %dx%d cells", img_w, img_h, cols, rows))
  return cols, rows
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

-- Creates the scratch buffer the image gets drawn into. image.nvim needs
-- real cells under the graphic or the terminal won't commit it to those
-- rows, so we fill the buffer with blank lines matching the window size.
local function create_scratch_buffer(cols, rows)
  local ok_buf, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok_buf or not buf then
    log("nvim_create_buf failed")
    return nil
  end

  local blank = {}
  for _ = 1, rows do
    table.insert(blank, string.rep(" ", cols))
  end
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, blank)

  pcall(vim.api.nvim_set_option_value, "filetype", "fig_preview", { buf = buf })
  pcall(vim.api.nvim_set_option_value, "buftype", "nofile", { buf = buf })
  pcall(vim.api.nvim_set_option_value, "bufhidden", "wipe", { buf = buf })

  return buf
end

-- Clamped editor-relative position for a cols x rows (+border) float, so it
-- never spills off-screen.
local function preview_position(cols, rows)
  local editor_w, editor_h = vim.o.columns, vim.o.lines
  local outer_w, outer_h = cols + BORDER_CELLS, rows + BORDER_CELLS

  local col_pos = math.max(0, math.min(editor_w - outer_w - 2, vim.fn.wincol() + 2))
  local row_pos = math.max(0, math.min(editor_h - outer_h - 2, vim.fn.winline()))
  return row_pos, col_pos
end

-- Opens the floating window that hosts the preview, anchored to the editor
-- (not the cursor -- avoids cursor-position calc bugs in image.nvim popups).
local function open_preview_window(buf, cols, rows)
  local row_pos, col_pos = preview_position(cols, rows)

  local ok_win, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    row = row_pos,
    col = col_pos,
    width = cols,
    height = rows,
    style = "minimal",
    focusable = false,
    zindex = 50,
    border = BORDER_STYLE,
  })
  if not ok_win or not win then
    log("nvim_open_win failed")
    return nil
  end

  -- Transparent body so the kitty graphic shows through; a visible border
  -- so the image reads as a framed preview instead of a stray floating box.
  pcall(
    vim.api.nvim_set_option_value,
    "winhighlight",
    "Normal:NormalFloat,NormalFloat:NormalFloat,FloatBorder:FigLinkBorder",
    { win = win }
  )
  pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = win })

  log(
    string.format(
      "float win=%d at row=%d col=%d %dx%d (+border)",
      win,
      row_pos,
      col_pos,
      cols,
      rows
    )
  )
  return win
end

-- Resizes the buffer's blank-line canvas and the float window itself to a
-- new cols x rows, repositioning so the border stays on-screen. Used to
-- correct our initial size guess once image.nvim reports the geometry it
-- actually rendered at.
local function resize_preview(buf, win, cols, rows)
  local blank = {}
  for _ = 1, rows do
    table.insert(blank, string.rep(" ", cols))
  end
  pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, blank)

  local row_pos, col_pos = preview_position(cols, rows)
  pcall(vim.api.nvim_win_set_config, win, {
    relative = "editor",
    row = row_pos,
    col = col_pos,
    width = cols,
    height = rows,
  })

  log(string.format("resized preview to %dx%d at row=%d col=%d", cols, rows, row_pos, col_pos))
end

-- Loads and renders the image into preview_win. Some backends need a
-- follow-up render after the float's cells are actually committed, so we
-- render synchronously and also schedule two retries.
local function load_and_render_image(full_path, cols, rows)
  -- Do NOT pass `buffer` here. image.nvim treats buffer= as "inline in this
  -- text buffer" and uses extmarks/virtual padding, which fights with a
  -- dedicated float. Passing only `window` renders into the window's cell
  -- grid, which is what we want -- and since the window is now sized to
  -- the image's own aspect ratio, filling it no longer stretches anything.
  local from_file_opts = {
    window = preview_win,
    width = cols,
    height = rows,
    with_virtual_padding = false,
    inline = false,
  }

  local ok_img, img_or_err = pcall(image.from_file, full_path, from_file_opts)
  log("from_file ok=" .. tostring(ok_img) .. " val=" .. vim.inspect(img_or_err))

  if not ok_img or not img_or_err or type(img_or_err) ~= "table" then
    close_preview()
    vim.notify("[fig-link] failed to load image: " .. full_path, vim.log.levels.WARN)
    return
  end
  preview_image = img_or_err

  -- Our upfront cols/rows are a heuristic guess (see fit_to_cells). Once
  -- image.nvim actually renders, it knows the true cell pixel size and
  -- reports the geometry it really used; we shrink the window to match
  -- that exactly, once, so the border hugs the image instead of leaving
  -- dead space when our guess was a bit off.
  local cur_cols, cur_rows = cols, rows
  local settled = false

  local function do_render()
    if not preview_image then
      return
    end
    if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then
      return
    end
    local ok_r = pcall(function()
      preview_image:render({ x = 0, y = 0, width = cur_cols, height = cur_rows })
    end)
    if not ok_r then
      ok_r = pcall(function()
        preview_image:render()
      end)
    end

    local geo = preview_image.rendered_geometry
    log(
      string.format(
        "render ok=%s is_rendered=%s rendered_geometry=%s",
        tostring(ok_r),
        tostring(preview_image.is_rendered),
        vim.inspect(geo)
      )
    )

    if ok_r and not settled and geo and geo.width and geo.height then
      settled = true
      if geo.width ~= cur_cols or geo.height ~= cur_rows then
        cur_cols, cur_rows = geo.width, geo.height
        resize_preview(preview_buf, preview_win, cur_cols, cur_rows)
        do_render() -- one corrective pass at the real geometry
      end
    end
  end

  do_render()
  vim.schedule(do_render)
  vim.defer_fn(do_render, 50)
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

  local cols, rows = compute_preview_geometry(full)

  local buf = create_scratch_buffer(cols, rows)
  if not buf then
    return
  end
  preview_buf = buf

  local win = open_preview_window(buf, cols, rows)
  if not win then
    close_preview()
    return
  end
  preview_win = win
  last_path = path

  load_and_render_image(full, cols, rows)
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
  vim.api.nvim_set_hl(0, "FigLinkBorder", { link = "FloatBorder", default = true })

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
