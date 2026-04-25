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

return M
