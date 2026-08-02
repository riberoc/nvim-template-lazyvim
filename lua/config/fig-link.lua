-- ~/.config/nvim/lua/fig-link.lua
--
-- fig:path/to/file.png       ->  hover link: underlined, CursorHold shows a
--                                 floating preview near the cursor, closes
--                                 when you move away.
-- fig-side:path/to/file.png  ->  pinned diagram: always rendered in a
--                                 floating panel docked to the far right
--                                 edge of the editor while its buffer/window
--                                 is active. Meant for "this diagram explains
--                                 the code in this file" references.
--
--   gf / double-click   ->  open either link type with the system viewer
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
local FIG_SIDE_PATTERN = "fig%-side:([^%s%)%]\"']+)"
local LINK_PATTERNS = { FIG_PATTERN, FIG_SIDE_PATTERN }

-- Upper bound on the hover preview size, in terminal cells.
local MAX_WIDTH = 60
local MAX_HEIGHT = 20

-- Upper bound on the pinned side-diagram panel. Wider box, since it's meant
-- to stay open and be read at a glance rather than a quick hover peek.
local SIDE_MAX_WIDTH = 50
local SIDE_MAX_HEIGHT = 40
local SIDE_MARGIN = 1 -- cells between the panel and the editor's right edge

-- Terminal character cells are taller than they are wide, so a plain
-- width==columns/height==rows mapping stretches images vertically. Most
-- monospace fonts render cells at roughly a 1:2 width:height pixel ratio;
-- this constant corrects for that when we convert an image's pixel
-- dimensions into a cell geometry. It's only used as an initial guess --
-- see Preview:load_and_render, which shrinks to image.nvim's own reported
-- geometry once it's known. Tweak it if your font is unusually wide/narrow.
local CELL_ASPECT_RATIO = 2.0

-- Border drawn around preview floats. Set to "none" to go borderless.
local BORDER_STYLE = "rounded"
local BORDER_CELLS = 2 -- border adds ~1 cell on each side, per axis

-- Debounce delay for buffer-content-triggered side-panel refreshes.
local SIDE_DEBOUNCE_MS = 150

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
-- link detection / path resolution
-- ---------------------------------------------------------------------------

-- Cursor-under-link check for a single Lua pattern. Returns the captured
-- path, or nil.
local function match_under_cursor(line, col, pattern)
  local start_idx = 1
  while true do
    local s, e, path = line:find(pattern, start_idx)
    if not s then
      return nil
    end
    if col >= s and col <= e then
      return path
    end
    start_idx = e + 1
  end
end

-- Used for gf / double-click: either link flavor counts.
local function get_link_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  for _, pattern in ipairs(LINK_PATTERNS) do
    local path = match_under_cursor(line, col, pattern)
    if path then
      return path
    end
  end
  return nil
end

-- Used for the hover preview: only plain `fig:` links trigger it. The
-- `fig-side:` diagram already has its own always-on panel, so hovering it
-- shouldn't pop up a second, redundant floating preview.
local function get_hover_fig_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  return match_under_cursor(line, col, FIG_PATTERN)
end

-- First `fig-side:` reference in the current buffer, or nil.
local function find_side_path_in_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    local _, _, path = line:find(FIG_SIDE_PATTERN)
    if path then
      return path
    end
  end
  return nil
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

-- Works out a preview window's initial content geometry (in cells) for a
-- given file and a max_cols x max_rows bound. Falls back to the bound
-- itself if the image's real dimensions can't be determined. This is only
-- a starting guess -- Preview:load_and_render shrinks to image.nvim's own
-- reported geometry once the first render completes.
local function compute_preview_geometry(full_path, max_cols, max_rows)
  local img_w, img_h = get_image_pixel_size(full_path)
  if not img_w then
    return max_cols, max_rows
  end

  local cols, rows = fit_to_cells(img_w, img_h, max_cols, max_rows)
  log(string.format("geometry %dx%d px -> %dx%d cells", img_w, img_h, cols, rows))
  return cols, rows
end

-- ---------------------------------------------------------------------------
-- scratch buffer helper
-- ---------------------------------------------------------------------------

-- Creates the scratch buffer an image gets drawn into. image.nvim needs
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

-- ---------------------------------------------------------------------------
-- Preview: one floating image panel.
--
-- Both the cursor-hover preview and the pinned side-diagram panel are the
-- same kind of thing (a float showing one image, sized to its own aspect
-- ratio), just anchored differently and with different open/close rules.
-- This class holds that shared behavior once instead of duplicating it.
-- ---------------------------------------------------------------------------

local Preview = {}
Preview.__index = Preview

function Preview.new(name)
  return setmetatable({
    name = name,
    win = nil,
    buf = nil,
    image = nil,
    last_path = nil,
    cols = nil,
    rows = nil,
  }, Preview)
end

function Preview:is_open()
  return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

function Preview:close()
  if self.image then
    pcall(function()
      self.image:clear()
    end)
  end
  if self:is_open() then
    pcall(vim.api.nvim_win_close, self.win, true)
  end
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end
  self.win, self.buf, self.image, self.last_path = nil, nil, nil, nil
  self.cols, self.rows = nil, nil
end

-- Moves (and/or resizes) the float using a fresh call to position_fn(cols,
-- rows). Used both after a resize and on bare editor-resize events.
function Preview:reposition(position_fn)
  if not self:is_open() then
    return
  end
  local row_pos, col_pos = position_fn(self.cols, self.rows)
  pcall(vim.api.nvim_win_set_config, self.win, {
    relative = "editor",
    row = row_pos,
    col = col_pos,
    width = self.cols,
    height = self.rows,
  })
end

-- Resizes the buffer's blank-line canvas and the float to a new cols x
-- rows, repositioning via position_fn so the border stays on-screen. Used
-- to correct our initial size guess once image.nvim reports the geometry
-- it actually rendered at.
function Preview:resize(cols, rows, position_fn)
  self.cols, self.rows = cols, rows

  local blank = {}
  for _ = 1, rows do
    table.insert(blank, string.rep(" ", cols))
  end
  pcall(vim.api.nvim_buf_set_lines, self.buf, 0, -1, false, blank)

  self:reposition(position_fn)
  log(string.format("[%s] resized to %dx%d", self.name, cols, rows))
end

-- Loads and renders the image into self.win. Some backends need a
-- follow-up render after the float's cells are actually committed, so we
-- render synchronously and also schedule two retries. On the first
-- successful render we also shrink-to-fit against image.nvim's own
-- reported geometry (see module header comment on CELL_ASPECT_RATIO).
function Preview:load_and_render(full_path, cols, rows, position_fn)
  -- Do NOT pass `buffer` here. image.nvim treats buffer= as "inline in this
  -- text buffer" and uses extmarks/virtual padding, which fights with a
  -- dedicated float. Passing only `window` renders into the window's cell
  -- grid, which is what we want.
  local from_file_opts = {
    window = self.win,
    width = cols,
    height = rows,
    with_virtual_padding = false,
    inline = false,
  }

  local ok_img, img_or_err = pcall(image.from_file, full_path, from_file_opts)
  log(
    string.format(
      "[%s] from_file ok=%s val=%s",
      self.name,
      tostring(ok_img),
      vim.inspect(img_or_err)
    )
  )

  if not ok_img or not img_or_err or type(img_or_err) ~= "table" then
    self:close()
    vim.notify("[fig-link] failed to load image: " .. full_path, vim.log.levels.WARN)
    return
  end
  self.image = img_or_err

  local cur_cols, cur_rows = cols, rows
  local settled = false
  local preview = self

  local function do_render()
    if not preview.image or not preview:is_open() then
      return
    end

    local ok_r = pcall(function()
      preview.image:render({ x = 0, y = 0, width = cur_cols, height = cur_rows })
    end)
    if not ok_r then
      ok_r = pcall(function()
        preview.image:render()
      end)
    end

    local geo = preview.image.rendered_geometry
    log(
      string.format(
        "[%s] render ok=%s is_rendered=%s rendered_geometry=%s",
        preview.name,
        tostring(ok_r),
        tostring(preview.image.is_rendered),
        vim.inspect(geo)
      )
    )

    if ok_r and not settled and geo and geo.width and geo.height then
      settled = true
      if geo.width ~= cur_cols or geo.height ~= cur_rows then
        cur_cols, cur_rows = geo.width, geo.height
        preview:resize(cur_cols, cur_rows, position_fn)
        do_render() -- one corrective pass at the real geometry
      end
    end
  end

  do_render()
  vim.schedule(do_render)
  vim.defer_fn(do_render, 50)
end

-- Opens (or no-ops if already showing `path`) this preview, sized to fit
-- within max_cols x max_rows and positioned by position_fn(cols, rows) ->
-- row, col.
function Preview:show(path, position_fn, max_cols, max_rows)
  if not ok_image then
    log("image.nvim not loaded")
    return
  end
  if path == self.last_path and self:is_open() then
    log(string.format("[%s] already showing %s", self.name, path))
    return
  end

  local full = resolve_path(path)
  log(string.format("[%s] resolve %s -> %s", self.name, path, full))
  if vim.fn.filereadable(full) == 0 then
    log(string.format("[%s] not readable: %s", self.name, full))
    return
  end

  self:close()
  ensure_transparent_float_hl()

  local cols, rows = compute_preview_geometry(full, max_cols, max_rows)
  self.cols, self.rows = cols, rows

  local buf = create_scratch_buffer(cols, rows)
  if not buf then
    return
  end
  self.buf = buf

  local row_pos, col_pos = position_fn(cols, rows)
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
    log(string.format("[%s] nvim_open_win failed", self.name))
    self:close()
    return
  end
  self.win = win

  -- Transparent body so the kitty graphic shows through; a visible border
  -- so the image reads as a framed preview instead of a stray floating box.
  pcall(
    vim.api.nvim_set_option_value,
    "winhighlight",
    "Normal:NormalFloat,NormalFloat:NormalFloat,FloatBorder:FigLinkBorder",
    { win = win }
  )
  pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = win })

  self.last_path = path
  log(
    string.format(
      "[%s] float win=%d at row=%d col=%d %dx%d (+border)",
      self.name,
      win,
      row_pos,
      col_pos,
      cols,
      rows
    )
  )

  self:load_and_render(full, cols, rows, position_fn)
end

-- ---------------------------------------------------------------------------
-- the two preview instances + their positioning rules
-- ---------------------------------------------------------------------------

local hover_preview = Preview.new("hover")
local side_preview = Preview.new("side")

-- Hover preview: floats near the cursor, clamped to stay on-screen.
local function hover_position(cols, rows)
  local editor_w, editor_h = vim.o.columns, vim.o.lines
  local outer_w, outer_h = cols + BORDER_CELLS, rows + BORDER_CELLS

  local col_pos = math.max(0, math.min(editor_w - outer_w - 2, vim.fn.wincol() + 2))
  local row_pos = math.max(0, math.min(editor_h - outer_h - 2, vim.fn.winline()))
  return row_pos, col_pos
end

-- Side diagram panel: pinned to the far right edge of the editor,
-- vertically centered, independent of where the cursor happens to be.
local function side_position(cols, rows)
  local editor_w, editor_h = vim.o.columns, vim.o.lines
  local outer_w, outer_h = cols + BORDER_CELLS, rows + BORDER_CELLS

  local col_pos = math.max(0, editor_w - outer_w - SIDE_MARGIN)
  local row_pos = math.max(0, math.floor((editor_h - outer_h) / 2))
  return row_pos, col_pos
end

-- Refreshes the pinned side panel to match whatever `fig-side:` reference
-- (if any) is in the current buffer. Safe to call often -- it's a no-op if
-- the same path is already showing.
local function update_side_preview()
  local path = find_side_path_in_buffer()
  if path then
    side_preview:show(path, side_position, SIDE_MAX_WIDTH, SIDE_MAX_HEIGHT)
  else
    side_preview:close()
  end
end

-- Debounced wrapper for high-frequency triggers (typing).
local side_update_scheduled = false
local function schedule_side_update()
  if side_update_scheduled then
    return
  end
  side_update_scheduled = true
  vim.defer_fn(function()
    side_update_scheduled = false
    update_side_preview()
  end, SIDE_DEBOUNCE_MS)
end

-- Forces a full reload (not just a reposition) next time the side panel
-- updates -- used on editor resize, where the max-size bounds may now fit
-- differently.
local function force_side_reload()
  side_preview.last_path = nil
  update_side_preview()
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
  local path = get_link_under_cursor()
  if not path then
    vim.notify("[fig-link] no fig: / fig-side: reference under cursor", vim.log.levels.INFO)
    return
  end
  open_with_system(path)
end

-- ---------------------------------------------------------------------------
-- inspection command
-- ---------------------------------------------------------------------------

local function preview_snapshot(preview)
  return {
    win = preview.win,
    win_valid = preview:is_open(),
    buf = preview.buf,
    buf_valid = preview.buf and vim.api.nvim_buf_is_valid(preview.buf),
    last_path = preview.last_path,
    cols = preview.cols,
    rows = preview.rows,
    image = preview.image and "<image handle>" or nil,
  }
end

function M.inspect_state()
  local info = {
    ok_image = ok_image,
    hover = preview_snapshot(hover_preview),
    side = preview_snapshot(side_preview),
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
  if opts.side_max_width then
    SIDE_MAX_WIDTH = opts.side_max_width
  end
  if opts.side_max_height then
    SIDE_MAX_HEIGHT = opts.side_max_height
  end

  if not ok_image then
    vim.notify("[fig-link] image.nvim not found; preview disabled", vim.log.levels.WARN)
  end

  vim.keymap.set(
    "n",
    keymap,
    M.open_fig,
    { desc = "Open fig: / fig-side: reference (system viewer)" }
  )
  vim.keymap.set(
    "n",
    "<2-LeftMouse>",
    M.open_fig,
    { desc = "Open fig: / fig-side: reference (system viewer)" }
  )

  vim.api.nvim_set_hl(0, "FigLink", { link = "Underlined", default = true })
  vim.api.nvim_set_hl(0, "FigLinkSide", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "FigLinkBorder", { link = "FloatBorder", default = true })

  vim.api.nvim_create_user_command("FigLinkInspect", function()
    M.inspect_state()
  end, {})
  vim.api.nvim_create_user_command("FigLinkDebug", function(a)
    M.debug(a.args ~= "off")
  end, { nargs = "?" })

  local group = vim.api.nvim_create_augroup("FigLink", { clear = true })

  -- ---- link highlighting ----
  local fig_match_id, side_match_id
  local function apply_match()
    if fig_match_id then
      pcall(vim.fn.matchdelete, fig_match_id)
      fig_match_id = nil
    end
    if side_match_id then
      pcall(vim.fn.matchdelete, side_match_id)
      side_match_id = nil
    end
    local ok1, id1 = pcall(vim.fn.matchadd, "FigLink", [[fig:\S\+]])
    if ok1 then
      fig_match_id = id1
    end
    local ok2, id2 = pcall(vim.fn.matchadd, "FigLinkSide", [[fig-side:\S\+]])
    if ok2 then
      side_match_id = id2
    end
  end

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "ColorScheme" }, {
    group = group,
    callback = apply_match,
  })
  apply_match()

  -- ---- hover preview (fig:) ----
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == hover_preview.win then
        return -- never trigger from inside our own float
      end
      local path = get_hover_fig_under_cursor()
      if path then
        hover_preview:show(path, hover_position, MAX_WIDTH, MAX_HEIGHT)
      else
        hover_preview:close()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinLeave" }, {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == hover_preview.win then
        return -- ignore movement inside our own preview window
      end
      hover_preview:close()
    end,
  })

  -- ---- pinned side diagram (fig-side:) ----
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == side_preview.win then
        return
      end
      update_side_preview()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = schedule_side_update,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = force_side_reload,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == side_preview.win then
        return
      end
      side_preview:close()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      hover_preview:close()
      side_preview:close()
    end,
  })
end

return M
