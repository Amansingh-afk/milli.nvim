-- Classic PSX DOOM fire: bottom row is a constant heat source, heat rises
-- with lateral jitter and random cooling. 16-color fixed palette.

local common = require("milli.shaders.common")

local M = { fps = 20 }

local PALETTE = {
  [0] = nil,
  common.rgb(31, 7, 7), common.rgb(71, 15, 7), common.rgb(103, 31, 7),
  common.rgb(143, 39, 7), common.rgb(175, 63, 7), common.rgb(199, 71, 7),
  common.rgb(223, 79, 7), common.rgb(223, 105, 15), common.rgb(215, 127, 23),
  common.rgb(207, 143, 31), common.rgb(207, 159, 47), common.rgb(215, 175, 63),
  common.rgb(223, 191, 79), common.rgb(239, 219, 111), common.rgb(255, 255, 255),
}
local GLYPHS = {
  [0] = " ",
  ".", ".", ":", ":", "*", "*", "&", "&", "#", "#", "@", "@", "▓", "▓", "█",
}

function M.new(cols, rows, opts)
  local heat = {}
  for y = 1, rows do
    heat[y] = {}
    for x = 1, cols do heat[y][x] = (y == rows) and 15 or 0 end
  end
  local state = {
    cols = cols,
    rows = rows,
    heat = heat,
    rng = common.lcg((opts and opts.seed) or 1337),
  }
  for _ = 1, rows do M.step(state) end
  return state
end

function M.step(state)
  local heat, rng = state.heat, state.rng
  local cols, rows = state.cols, state.rows
  for y = 1, rows - 1 do
    for x = 1, cols do
      local sx = math.min(cols, math.max(1, x + math.floor(rng() * 3) - 1))
      local cool = (rng() < 0.4) and 1 or 0
      heat[y][x] = math.max(0, heat[y + 1][sx] - cool)
    end
  end
end

function M.frame(state, _tick)
  M.step(state)
  local cellrows = {}
  for y = 1, state.rows do
    local row = {}
    for x = 1, state.cols do
      local h = state.heat[y][x]
      row[x] = { GLYPHS[h], PALETTE[h] }
    end
    cellrows[y] = row
  end
  return common.to_frame(cellrows)
end

return M
