-- milli.nvim runtime: resolves splash data, paints frames into a buffer,
-- and runs the animation loop. Data modules are pure tables with the shape
-- { cols, rows, delays, frames, colors? } emitted by `milli export -t lua`.

local M = {}

local ns = vim.api.nvim_create_namespace("milli_splash")
local hl_cache = {}
local bg_state = {}

local function get_hl(fg_hex, bg_hex)
  local key = fg_hex .. "_" .. bg_hex
  if hl_cache[key] then return hl_cache[key] end
  local bg_suffix = bg_hex == "NONE" and "NONE" or bg_hex:sub(2)
  local name = "MilliSplash_" .. fg_hex:sub(2) .. "_" .. bg_suffix
  local spec = { fg = fg_hex }
  if bg_hex ~= "NONE" then spec.bg = bg_hex end
  vim.api.nvim_set_hl(0, name, spec)
  hl_cache[key] = name
  return name
end

local function rtrim(s) return (s:gsub("%s+$", "")) end

local function anchor_in_frame0(data)
  local first = data.frames and data.frames[1]
  if not first then return nil, nil end
  for i, line in ipairs(first) do
    if line:find("[^%s]") then return i, line end
  end
  return nil, nil
end

-- Resolve opts into a data table. Priority: data > splash > module.
function M.load(opts)
  if opts.data then return opts.data end
  if opts.splash then
    local ok, mod = pcall(require, "milli.splashes." .. opts.splash)
    if not ok then
      error("milli.nvim: bundled splash not found: " .. tostring(opts.splash))
    end
    return mod
  end
  if opts.module then
    local ok, mod = pcall(require, opts.module)
    if not ok then
      error("milli.nvim: custom splash module not found: " .. tostring(opts.module))
    end
    return mod
  end
  error("milli.nvim: opts must include one of { data, splash, module }")
end

-- List bundled splashes by scanning the plugin's splashes directory.
function M.list()
  local files = vim.api.nvim_get_runtime_file("lua/milli/splashes/*.lua", true)
  local out = {}
  local seen = {}
  for _, path in ipairs(files) do
    local name = path:match("([^/]+)%.lua$")
    if name and not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  table.sort(out)
  return out
end

function M.play(buf, opts)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  opts = opts or {}
  local data = M.load(opts)
  local loop = opts.loop == true

  local anchor_idx, anchor_line = anchor_in_frame0(data)
  if not anchor_idx then return end
  local anchor_trim = rtrim(anchor_line)

  local function locate()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, l in ipairs(lines) do
      local pos = l:find(anchor_trim, 1, true)
      if pos then return i - anchor_idx, l:sub(1, pos - 1) end
    end
    return nil, nil
  end

  local function start(attempt)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local start_row, pad = locate()
    if not start_row then
      if attempt < 20 then
        vim.defer_fn(function() start(attempt + 1) end, 25)
      end
      return
    end
    local pad_bytes = #pad

    local function paint(idx)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local frame = data.frames[idx + 1]
      local colors = data.colors and data.colors[idx + 1]
      if not frame then return end

      local padded = {}
      for i, line in ipairs(frame) do padded[i] = pad .. line end

      vim.bo[buf].modifiable = true
      pcall(vim.api.nvim_buf_set_lines, buf, start_row, start_row + #padded, false, padded)
      vim.bo[buf].modified = false
      vim.bo[buf].modifiable = false

      vim.api.nvim_buf_clear_namespace(buf, ns, start_row, start_row + #padded)
      if not colors then return end
      for row_i, row_runs in ipairs(colors) do
        local buf_row = start_row + row_i - 1
        for _, run in ipairs(row_runs) do
          local sb, eb, fg, bg = run[1], run[2], run[3], run[4]
          local hl = get_hl(fg, bg)
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, buf_row, pad_bytes + sb, {
            end_col = pad_bytes + eb,
            hl_group = hl,
            priority = 200,
          })
        end
      end
    end

    paint(0)
    local idx = 1
    local function step()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if idx >= #data.frames and not loop then return end
      local fi = idx % #data.frames
      paint(fi)
      idx = idx + 1
      local delay = data.delays[fi + 1] or 100
      vim.defer_fn(step, delay)
    end
    vim.defer_fn(step, data.delays[1] or 100)
  end

  start(0)
end

local function centered_frame(frame, width, height)
  local rows = #frame
  local cols = 0
  for _, line in ipairs(frame) do
    local w = vim.fn.strdisplaywidth(line)
    if w > cols then cols = w end
  end

  local top_pad = math.max(0, math.floor((height - rows) / 2))
  local left_pad = math.max(0, math.floor((width - cols) / 2))
  local out = {}
  local blank = string.rep(" ", width)
  local pad = string.rep(" ", left_pad)

  for _ = 1, top_pad do
    table.insert(out, blank)
  end
  for _, line in ipairs(frame) do
    local rendered = pad .. line
    local rw = vim.fn.strdisplaywidth(rendered)
    if rw < width then
      rendered = rendered .. string.rep(" ", width - rw)
    end
    table.insert(out, rendered)
  end
  while #out < height do
    table.insert(out, blank)
  end
  return out, top_pad, left_pad
end

local function stretched_frame(frame, width, height)
  local src_h = #frame
  local src_w = 0
  for _, line in ipairs(frame) do
    if #line > src_w then src_w = #line end
  end
  if src_h == 0 or src_w == 0 then
    local out = {}
    local blank = string.rep(" ", width)
    for _ = 1, height do
      out[#out + 1] = blank
    end
    return out
  end

  local out = {}
  for y = 1, height do
    local sy = math.floor(((y - 1) * src_h) / height) + 1
    local src = frame[sy] or ""
    local row = {}
    for x = 1, width do
      local sx = math.floor(((x - 1) * src_w) / width) + 1
      row[x] = sx <= #src and src:sub(sx, sx) or " "
    end
    out[y] = table.concat(row)
  end
  return out
end

local function stop_background_for_win(win)
  local state = bg_state[win]
  if not state then return end
  state.active = false
  if state.float and vim.api.nvim_win_is_valid(state.float) then
    pcall(vim.api.nvim_win_close, state.float, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  bg_state[win] = nil
end

-- Render full-screen frames in a dedicated floating window.
-- Intended for "background" mode integrations.
function M.play_background(win, opts)
  opts = opts or {}
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local ok, data = pcall(M.load, opts)
  if not ok or not data or not data.frames or #data.frames == 0 then return end

  stop_background_for_win(win)

  local host_buf = vim.api.nvim_win_get_buf(win)
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[float_buf].buftype = "nofile"
  vim.bo[float_buf].bufhidden = "wipe"
  vim.bo[float_buf].swapfile = false

  local state = { active = true, buf = float_buf, float = nil }
  bg_state[win] = state

  local function ensure_float()
    if not state.active then return false end
    if not vim.api.nvim_win_is_valid(win) then
      stop_background_for_win(win)
      return false
    end
    if not state.float or not vim.api.nvim_win_is_valid(state.float) then
      local width = vim.api.nvim_win_get_width(win)
      local height = vim.api.nvim_win_get_height(win)
      local cfg = {
        relative = "win",
        win = win,
        row = 0,
        col = 0,
        width = width,
        height = height,
        style = "minimal",
        focusable = false,
        noautocmd = true,
      }
      state.float = vim.api.nvim_open_win(float_buf, false, cfg)
      vim.wo[state.float].winblend = opts.winblend or 35
      vim.wo[state.float].wrap = false
      vim.wo[state.float].cursorline = false
      vim.wo[state.float].number = false
      vim.wo[state.float].relativenumber = false
      vim.wo[state.float].signcolumn = "no"
      vim.wo[state.float].foldcolumn = "0"
      vim.wo[state.float].winfixbuf = true
      vim.wo[state.float].winhl = "Normal:Normal,NormalNC:Normal"
    else
      local width = vim.api.nvim_win_get_width(win)
      local height = vim.api.nvim_win_get_height(win)
      pcall(vim.api.nvim_win_set_config, state.float, {
        relative = "win",
        win = win,
        row = 0,
        col = 0,
        width = width,
        height = height,
      })
    end
    return true
  end

  local function paint(fi)
    if not ensure_float() then return end
    if vim.api.nvim_win_get_buf(win) ~= host_buf then
      stop_background_for_win(win)
      return
    end
    local width = vim.api.nvim_win_get_width(win)
    local height = vim.api.nvim_win_get_height(win)
    local frame = data.frames[fi + 1]
    if not frame then return end
    local fit = opts.background_fit or "contain"
    local lines, top_pad, left_pad
    if fit == "stretch" then
      lines = stretched_frame(frame, width, height)
      top_pad, left_pad = 0, 0
    else
      lines, top_pad, left_pad = centered_frame(frame, width, height)
    end
    vim.bo[float_buf].modifiable = true
    pcall(vim.api.nvim_buf_set_lines, float_buf, 0, -1, false, lines)
    vim.bo[float_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(float_buf, ns, 0, -1)

    local colors = data.colors and data.colors[fi + 1]
    if not colors or fit == "stretch" then return end
    for row_i, row_runs in ipairs(colors) do
      local buf_row = top_pad + row_i - 1
      if buf_row >= 0 and buf_row < height then
        for _, run in ipairs(row_runs) do
          local sb, eb, fg, bg = run[1], run[2], run[3], run[4]
          local start_col = left_pad + sb
          local end_col = left_pad + eb
          if end_col > 0 and start_col < width then
            start_col = math.max(0, start_col)
            end_col = math.min(width, end_col)
            if end_col > start_col then
              local hl = get_hl(fg, bg)
              pcall(vim.api.nvim_buf_set_extmark, float_buf, ns, buf_row, start_col, {
                end_col = end_col,
                hl_group = hl,
                priority = 200,
              })
            end
          end
        end
      end
    end
  end

  local loop = opts.loop == true
  local idx = 0
  local function step()
    if not state.active then return end
    paint(idx % #data.frames)
    if not loop and idx >= #data.frames - 1 then return end
    local di = (idx % #data.frames) + 1
    idx = idx + 1
    vim.defer_fn(step, data.delays[di] or 100)
  end

  vim.api.nvim_create_autocmd({ "WinClosed", "BufWipeout", "BufLeave" }, {
    callback = function(ev)
      if ev.match == tostring(win) or ev.buf == host_buf then
        stop_background_for_win(win)
      end
    end,
    once = true,
  })

  step()
end

return M
