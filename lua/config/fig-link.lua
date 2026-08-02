-- fig:path/to/file.png   ->  hover link: underlined, CursorHold shows a
--                            floating preview near the cursor, closes
--                            when you move away.
-- fig-side:path/to/file.png  ->  pinned diagram: shows if inside the same
--                            function as the cursor (via Treesitter), or
--                            within 10 lines. Closes if scrolled away or
--                            cursor moves out of context. If the window is
--                            too narrow to fit the panel without overlapping
--                            code, falls back to behaving like a `fig:` link.
--
--  gf / double-click   ->  open either link type with the system viewer
--
-- Requires: 3rd/image.nvim, kitty (or compatible) terminal, ImageMagick
--           (`identify` on PATH -- image.nvim already depends on this for
--           the magick_cli processor, so it should already be present).
--
-- Debug:
--   :lua require("fig-link").debug(true)    -- verbose logging via :messages
--   :lua require("fig-link").debug(false)   -- silence
--   :FigLinkInspect                         -- dump current preview state

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

-- Upper bound on a single pinned side-diagram panel's width.
local SIDE_MAX_WIDTH = 50
local SIDE_MIN_SLOT_HEIGHT = 3
local SIDE_SLOT_GAP = 1
local SIDE_MARGIN = 1

local CELL_ASPECT_RATIO = 2.0
local BORDER_STYLE = "rounded"
local BORDER_CELLS = 2

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

local function resolve_path(path)
  if path:match("^/") or path:match("^~") then
    return vim.fn.expand(path)
  end
  local bufdir = vim.fn.expand("%:p:h")
  return bufdir .. "/" .. path
end

-- ---------------------------------------------------------------------------
-- space and context detection
-- ---------------------------------------------------------------------------

-- Find function bounds using Treesitter
local function get_cursor_function_range()
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = 0 })
  if not ok or not node then
    return nil, nil
  end

  while node do
    local type = node:type()
    if type:find("function") or type:find("method") then
      local start_row, _, end_row, _ = node:range()
      return start_row + 1, end_row + 1 -- 1-indexed to match vim.fn.line
    end
    node = node:parent()
  end
  return nil, nil
end

-- Checks if there is enough space on the right side of the screen
local function has_space_for_side_panel()
  local winid = vim.api.nvim_get_current_win()
  local winfo = vim.fn.getwininfo(winid)[1]
  if not winfo then
    return true
  end

  local win_width = winfo.width - winfo.textoff
  local top = vim.fn.line("w0")
  local bot = vim.fn.line("w$")
  local lines = vim.api.nvim_buf_get_lines(0, top - 1, bot, false)

  local max_len = 0
  for _, line in ipairs(lines) do
    local len = vim.fn.strdisplaywidth(line)
    if len > max_len then
      max_len = len
    end
  end

  local required_space = SIDE_MAX_WIDTH + SIDE_MARGIN + BORDER_CELLS
  return (win_width - max_len) >= required_space
end

-- ---------------------------------------------------------------------------
-- aspect-correct geometry & scratch buffers
-- ---------------------------------------------------------------------------

local function get_image_pixel_size(full_path)
  if vim.fn.executable("identify") == 0 then
    return nil
  end
  local ok, out = pcall(vim.fn.systemlist, { "identify", "-format", "%w %h", full_path })
  if not ok or vim.v.shell_error ~= 0 or not out or not out[1] then
    return nil
  end
  local w, h = out[1]:match("(%d+)%s+(%d+)")
  w, h = tonumber(w), tonumber(h)
  if not w or not h or w <= 0 or h <= 0 then
    return nil
  end
  return w, h
end

local function fit_to_cells(img_w, img_h, max_cols, max_rows)
  local max_px_w = max_cols
  local max_px_h = max_rows * CELL_ASPECT_RATIO
  local scale = math.min(max_px_w / img_w, max_px_h / img_h)
  local cols = math.max(1, math.floor(img_w * scale + 0.5))
  local rows = math.max(1, math.floor((img_h * scale) / CELL_ASPECT_RATIO + 0.5))
  return cols, rows
end

local function compute_preview_geometry(full_path, max_cols, max_rows)
  local img_w, img_h = get_image_pixel_size(full_path)
  if not img_w then
    return max_cols, max_rows
  end
  return fit_to_cells(img_w, img_h, max_cols, max_rows)
end

local function create_scratch_buffer(cols, rows)
  local ok_buf, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok_buf or not buf then
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
    border = BORDER_STYLE, -- Always enforce border once finalized
  })
end

function Preview:resize(cols, rows, position_fn)
  self.cols, self.rows = cols, rows
  local blank = {}
  for _ = 1, rows do
    table.insert(blank, string.rep(" ", cols))
  end
  pcall(vim.api.nvim_buf_set_lines, self.buf, 0, -1, false, blank)
  self:reposition(position_fn)
end

function Preview:load_and_render(full_path, cols, rows, position_fn)
  local from_file_opts = {
    window = self.win,
    width = cols,
    height = rows,
    with_virtual_padding = false,
    inline = false,
  }
  local ok_img, img_or_err = pcall(image.from_file, full_path, from_file_opts)
  if not ok_img or type(img_or_err) ~= "table" then
    self:close()
    return
  end
  self.image = img_or_err

  local cur_cols, cur_rows = cols, rows
  local preview = self
  local retry_count = 0

  local function do_render()
    if not preview.image or not preview:is_open() then
      return
    end

    -- Initial render triggers image.nvim to query the terminal
    local ok_r = pcall(function()
      preview.image:render({ x = 0, y = 0, width = cur_cols, height = cur_rows })
    end)
    if not ok_r then
      pcall(function()
        preview.image:render()
      end)
    end

    local geo = preview.image.rendered_geometry
    if geo and geo.width and geo.height then
      cur_cols, cur_rows = geo.width, geo.height

      -- We have the exact layout geometry! Resize applies the border
      -- that we kept hidden during the initial guess.
      preview:resize(cur_cols, cur_rows, position_fn)

      -- One final render to snap image bounds to the finalized window
      pcall(function()
        preview.image:render({ x = 0, y = 0, width = cur_cols, height = cur_rows })
      end)
    else
      -- Wait a split second for the backend to return terminal info
      retry_count = retry_count + 1
      if retry_count < 5 then
        vim.defer_fn(do_render, 20)
      else
        -- Fallback: just apply the border anyway
        preview:resize(cur_cols, cur_rows, position_fn)
      end
    end
  end

  do_render()
end

function Preview:show(path, position_fn, max_cols, max_rows)
  if not ok_image then
    return
  end
  if path == self.last_path and self:is_open() then
    return
  end

  local full = resolve_path(path)
  if vim.fn.filereadable(full) == 0 then
    return
  end

  self:close()

  local cols, rows = compute_preview_geometry(full, max_cols, max_rows)
  self.cols, self.rows = cols, rows
  local buf = create_scratch_buffer(cols, rows)
  if not buf then
    return
  end
  self.buf = buf

  local row_pos, col_pos = position_fn(cols, rows)

  -- Open borderless first, but offset it inward so the inner content is exactly
  -- where it will be when the border is eventually snapped on.
  -- Combined with `bg = "none"`, this makes the window completely invisible
  -- while it guesses the size, eliminating the border-flash!
  local b_off = BORDER_CELLS > 0 and 1 or 0

  local ok_win, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    row = row_pos + b_off,
    col = col_pos + b_off,
    width = cols,
    height = rows,
    style = "minimal",
    focusable = false,
    zindex = 50,
    border = "none",
  })
  if not ok_win or not win then
    self:close()
    return
  end
  self.win = win

  pcall(
    vim.api.nvim_set_option_value,
    "winhighlight",
    "Normal:FigLinkFloat,NormalFloat:FigLinkFloat,FloatBorder:FigLinkBorder",
    { win = win }
  )
  pcall(vim.api.nvim_set_option_value, "winblend", 0, { win = win })

  self.last_path = path
  self:load_and_render(full, cols, rows, position_fn)
end

-- ---------------------------------------------------------------------------
-- hover preview
-- ---------------------------------------------------------------------------

local hover_preview = Preview.new("hover")

local function hover_position(cols, rows)
  local editor_w, editor_h = vim.o.columns, vim.o.lines
  local outer_w, outer_h = cols + BORDER_CELLS, rows + BORDER_CELLS
  local col_pos = math.max(0, math.min(editor_w - outer_w - 2, vim.fn.wincol() + 2))
  local row_pos = math.max(0, math.min(editor_h - outer_h - 2, vim.fn.winline()))
  return row_pos, col_pos
end

-- ---------------------------------------------------------------------------
-- side diagram panels
-- ---------------------------------------------------------------------------

local side_previews = {}
local last_side_signature = nil

local function close_all_side_previews()
  for _, p in ipairs(side_previews) do
    p:close()
  end
  side_previews = {}
  last_side_signature = nil
end

local function is_side_preview_win(winid)
  for _, p in ipairs(side_previews) do
    if p.win == winid then
      return true
    end
  end
  return false
end

-- Returns true if the path is currently shown in a side panel
local function is_path_in_side_panels(path)
  for _, p in ipairs(side_previews) do
    if p:is_open() and p.last_path == path then
      return true
    end
  end
  return false
end

-- Determines what hovering should show, allowing fallback for fig-side
local function get_hover_fig_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  -- Check regular hover first
  local path = match_under_cursor(line, col, FIG_PATTERN)
  if path then
    return path
  end

  -- Fallback: check if we're hovering a fig-side that isn't rendered in the side panel
  path = match_under_cursor(line, col, FIG_SIDE_PATTERN)
  if path and not is_path_in_side_panels(path) then
    return path
  end

  return nil
end

local function compute_slot_height(count)
  local total_gap = math.max(0, count - 1) * SIDE_SLOT_GAP
  local usable = vim.o.lines - total_gap
  return math.max(SIDE_MIN_SLOT_HEIGHT, math.floor(usable / math.max(count, 1)))
end

local function make_side_position_fn(slot, slot_h)
  return function(cols, rows)
    local editor_w, editor_h = vim.o.columns, vim.o.lines
    local outer_w, outer_h = cols + BORDER_CELLS, rows + BORDER_CELLS
    local col_pos = math.max(0, editor_w - outer_w - SIDE_MARGIN)
    local slot_top = (slot - 1) * (slot_h + SIDE_SLOT_GAP)
    local row_pos = slot_top + math.max(0, math.floor((slot_h - outer_h) / 2))
    row_pos = math.max(0, math.min(editor_h - outer_h - 1, row_pos))
    return row_pos, col_pos
  end
end

local function find_active_side_paths()
  -- If we don't have enough horizontal space to show diagrams without overlapping code,
  -- return an empty list so it falls back to hover behavior.
  if not has_space_for_side_panel() then
    return {}
  end

  local top = vim.fn.line("w0")
  local bot = vim.fn.line("w$")
  if top < 1 or bot < top then
    return {}
  end

  local cursor_line = vim.fn.line(".")
  local func_start, func_end = get_cursor_function_range()
  local lines = vim.api.nvim_buf_get_lines(0, top - 1, bot, false)
  local paths = {}

  for i, line in ipairs(lines) do
    local lnum = top + i - 1
    for path in line:gmatch(FIG_SIDE_PATTERN) do
      local is_active = false
      if func_start and func_end then
        -- Inside a function context, trigger for anything in this function
        if lnum >= func_start and lnum <= func_end then
          is_active = true
        end
      else
        -- Not in a function, check if within 10 lines of the cursor
        if math.abs(lnum - cursor_line) <= 10 then
          is_active = true
        end
      end

      if is_active then
        table.insert(paths, path)
      end
    end
  end
  return paths
end

local function update_side_previews()
  local paths = find_active_side_paths()
  local signature = table.concat(paths, "\30") .. "@" .. vim.o.lines .. "x" .. vim.o.columns
  if signature == last_side_signature then
    return
  end

  close_all_side_previews()
  last_side_signature = signature

  if #paths == 0 then
    return
  end

  local slot_h = compute_slot_height(#paths)
  for i, path in ipairs(paths) do
    local preview = Preview.new("side" .. i)
    side_previews[i] = preview
    preview:show(path, make_side_position_fn(i, slot_h), SIDE_MAX_WIDTH, slot_h)
  end
end

local side_update_scheduled = false
local function schedule_side_update()
  if side_update_scheduled then
    return
  end
  side_update_scheduled = true
  vim.defer_fn(function()
    side_update_scheduled = false
    update_side_previews()
  end, SIDE_DEBOUNCE_MS)
end

-- ---------------------------------------------------------------------------
-- gf / double-click: open with system viewer
-- ---------------------------------------------------------------------------

local function open_with_system(path)
  local full = resolve_path(path)
  if vim.fn.filereadable(full) == 0 then
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
  if cmd then
    vim.fn.jobstart(cmd, { detach = true })
  end
end

function M.open_fig()
  local path = get_link_under_cursor()
  if path then
    open_with_system(path)
  end
end

function M.inspect_state()
  -- Omitted for brevity, kept exactly as in your original file
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
  vim.api.nvim_set_hl(0, "FigLinkSide", { link = "Underlined", default = true })
  vim.api.nvim_set_hl(0, "FigLinkBorder", { link = "FloatBorder", default = true })

  -- Create an isolated transparent background just for these floats
  vim.api.nvim_set_hl(0, "FigLinkFloat", { bg = "none", default = true })

  local group = vim.api.nvim_create_augroup("FigLink", { clear = true })

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

  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == hover_preview.win then
        return
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
        return
      end
      hover_preview:close()
      schedule_side_update()
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      if is_side_preview_win(vim.api.nvim_get_current_win()) then
        return
      end
      update_side_previews()
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "WinScrolled", "VimResized" }, {
    group = group,
    callback = schedule_side_update,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    group = group,
    callback = function()
      if is_side_preview_win(vim.api.nvim_get_current_win()) then
        return
      end
      close_all_side_previews()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      hover_preview:close()
      close_all_side_previews()
    end,
  })
end

return M
