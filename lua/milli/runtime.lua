-- milli.nvim runtime: resolves splash data, paints frames into a buffer,
-- and runs the animation loop. Data modules are pure tables with the shape
-- { cols, rows, delays, frames, colors? } emitted by `milli export -t lua`.

local M = {}

local ns = vim.api.nvim_create_namespace("milli_splash")
local hl_cache = {}

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

-- Pick one entry of a list. Uses the clock instead of math.random so we
-- never touch the user's global RNG state.
function M.pick(list)
  if type(list) ~= "table" or #list == 0 then return nil end
  local t = (vim.uv or vim.loop).hrtime()
  return list[math.floor(t / 1000) % #list + 1]
end

-- `splash = "random"` (any bundled/user/installed splash) or a list of
-- names to choose from. The choice is made once per Neovim session so the
-- dashboard header seeded via load() and the preset that animates it agree.
local random_picks = {}
function M.resolve_name(splash)
  local pool, key
  if splash == "random" then
    pool, key = M.list(), "*"
  elseif type(splash) == "table" then
    pool, key = splash, table.concat(splash, ",")
  else
    return splash
  end
  if not random_picks[key] then
    random_picks[key] = M.pick(pool)
    if not random_picks[key] then
      error("milli.nvim: splash = " .. (key == "*" and '"random"' or "{...}") .. " but no splashes found")
    end
  end
  return random_picks[key]
end

-- Resolve opts into a data table. Priority: data > splash > module.
-- Splash lookup order: bundled/user-runtimepath, then registry-installed
-- (stdpath("data")/milli/splashes via :MilliInstall).
function M.load(opts)
  if type(opts) == "string" then opts = { splash = opts } end
  if opts.data then return opts.data end
  if opts.splash then
    opts = vim.tbl_extend("force", opts, { splash = M.resolve_name(opts.splash) })
    local ok, mod = pcall(require, "milli.splashes." .. opts.splash)
    if ok then return mod end
    local installed = require("milli.registry").load_installed(opts.splash)
    if installed then return installed end
    error("milli.nvim: splash not found: " .. tostring(opts.splash)
      .. " (not bundled, not installed - try :MilliInstall " .. tostring(opts.splash) .. ")")
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

-- List splashes: bundled (runtimepath) + registry-installed.
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
  for _, name in ipairs(require("milli.registry").installed()) do
    if not seen[name] then
      seen[name] = true
      table.insert(out, name)
    end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------- shaders

M.SHADERS = { "doomfire", "plasma", "rain", "starfield" }

local shader_timers = {} -- buf -> generation counter, bumped to cancel loops

-- Run a procedural shader live into a buffer. No baked frames: each tick the
-- shader module computes { lines, colors } and we repaint. opts:
--   shader = "plasma" | "rain" | "doomfire" | "starfield"  (required)
--   cols/rows = grid size (default: current window size)
--   fps = frame rate override (default: shader's own)
--   seed, hue = passed through to the shader
-- Returns a stop() function.
function M.play_shader(buf, opts)
  opts = type(opts) == "string" and { shader = opts } or (opts or {})
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return function() end end
  local ok, shader = pcall(require, "milli.shaders." .. tostring(opts.shader))
  if not ok then
    error("milli.nvim: unknown shader: " .. tostring(opts.shader)
      .. " (want one of: " .. table.concat(M.SHADERS, ", ") .. ")")
  end

  local win = vim.fn.bufwinid(buf)
  local cols = opts.cols or (win ~= -1 and vim.api.nvim_win_get_width(win) or 80)
  local rows = opts.rows or (win ~= -1 and vim.api.nvim_win_get_height(win) or 24)
  local fps = opts.fps or shader.fps or 20
  local delay = math.max(15, math.floor(1000 / fps))

  shader_timers[buf] = (shader_timers[buf] or 0) + 1
  local gen = shader_timers[buf]
  local state = shader.new(cols, rows, opts)
  local tick = 0

  local function paint()
    if not vim.api.nvim_buf_is_valid(buf) or shader_timers[buf] ~= gen then return end
    local frame = shader.frame(state, tick)
    tick = tick + 1

    vim.bo[buf].modifiable = true
    pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, frame.lines)
    vim.bo[buf].modified = false
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for row_i, runs in ipairs(frame.colors) do
      for _, run in ipairs(runs) do
        local hl = get_hl(run[3], run[4])
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row_i - 1, run[1], {
          end_col = run[2],
          hl_group = hl,
          priority = 200,
        })
      end
    end
    vim.defer_fn(paint, delay)
  end

  paint()
  return function()
    shader_timers[buf] = (shader_timers[buf] or 0) + 1
  end
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
    local last_painted = nil -- lines we last wrote, to detect a dashboard re-render
    local misses = 0

    -- Dashboards (snacks, alpha, dashboard-nvim) re-render the whole buffer
    -- on VimResized, re-centering the header seeded from frame 0. If the
    -- region we painted no longer holds what we wrote, the layout moved:
    -- find frame 0's anchor again and follow it. Returns false when the
    -- anchor is missing (mid-redraw) so the caller can retry next tick.
    local function relocate_if_moved()
      if not last_painted then return true end
      local cur = vim.api.nvim_buf_get_lines(buf, start_row, start_row + #last_painted, false)
      local moved = #cur ~= #last_painted
      if not moved then
        for i = 1, #cur do
          if cur[i] ~= last_painted[i] then moved = true break end
        end
      end
      if not moved then return true end
      local row, p = locate()
      if not row then return false end
      start_row, pad, pad_bytes = row, p, #p
      return true
    end

    local function paint(idx)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local frame = data.frames[idx + 1]
      local colors = data.colors and data.colors[idx + 1]
      if not frame then return end
      if not relocate_if_moved() then return false end

      local padded = {}
      for i, line in ipairs(frame) do padded[i] = pad .. line end

      vim.bo[buf].modifiable = true
      pcall(vim.api.nvim_buf_set_lines, buf, start_row, start_row + #padded, false, padded)
      vim.bo[buf].modified = false
      vim.bo[buf].modifiable = false
      last_painted = padded

      vim.api.nvim_buf_clear_namespace(buf, ns, start_row, start_row + #padded)
      if not colors then return true end
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
      return true
    end

    paint(0)
    local idx = 1
    local function step()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if idx >= #data.frames and not loop then return end
      local fi = idx % #data.frames
      if paint(fi) == false then
        -- Anchor gone (header replaced or dashboard mid-redraw). Hold this
        -- frame and retry; give up after ~100 ticks so a buffer that no
        -- longer contains the splash doesn't keep a timer alive forever.
        misses = misses + 1
        if misses > 100 then return end
      else
        misses = 0
        idx = idx + 1
      end
      local delay = data.delays[fi + 1] or 100
      vim.defer_fn(step, delay)
    end
    vim.defer_fn(step, data.delays[1] or 100)
  end

  start(0)
end

return M
