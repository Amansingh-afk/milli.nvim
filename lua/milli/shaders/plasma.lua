-- Plasma shader: layered sine fields -> flowing color blobs. Pure math,
-- no state beyond the tick counter.

local common = require("milli.shaders.common")

local M = { fps = 18 }

function M.new(cols, rows, opts)
  return {
    cols = cols,
    rows = rows,
    hue = (opts and opts.hue) or 0,
  }
end

function M.frame(state, tick)
  local t = tick / M.fps
  local cols, rows = state.cols, state.rows
  local cellrows = {}
  for y = 1, rows do
    local row = {}
    local ny = (y / rows) * 2
    for x = 1, cols do
      local nx = x / cols
      local v = math.sin(nx * 6 + t)
        + math.sin((ny + t) * 3)
        + math.sin((nx + ny + t) * 4)
        + math.sin(math.sqrt((nx - 0.5) ^ 2 + (ny - 1) ^ 2) * 10 - t * 2)
      local n = (v + 4) / 8
      -- Quantize the field so adjacent cells share highlight groups.
      n = math.floor(n * 24) / 24
      row[x] = { "█", common.hsv(state.hue + n * 0.7 + t * 0.02, 0.8, 0.45 + n * 0.55) }
    end
    cellrows[y] = row
  end
  return common.to_frame(cellrows)
end

return M
