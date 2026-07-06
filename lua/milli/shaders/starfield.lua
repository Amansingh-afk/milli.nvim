-- Starfield shader: stars projected toward the viewer, warp-speed feel.

local common = require("milli.shaders.common")

local M = { fps = 24 }

local GLYPHS = { "·", "•", "*", "✦", "█" }
-- 5 brightness steps, slight blue cast when far.
local COLORS = {
  common.rgb(90, 100, 140),
  common.rgb(130, 140, 180),
  common.rgb(180, 185, 215),
  common.rgb(220, 225, 240),
  common.rgb(255, 255, 255),
}

function M.new(cols, rows, opts)
  local rng = common.lcg((opts and opts.seed) or 1337)
  local n = math.floor(cols * rows / 18)
  local stars = {}
  for i = 1, n do
    stars[i] = { x = rng() * 2 - 1, y = rng() * 2 - 1, z = 0.1 + rng() * 0.9 }
  end
  return { cols = cols, rows = rows, stars = stars, rng = rng }
end

function M.frame(state, _tick)
  local cols, rows = state.cols, state.rows
  local cellrows = {}
  for y = 1, rows do
    local row = {}
    for x = 1, cols do row[x] = { " ", nil } end
    cellrows[y] = row
  end
  for _, s in ipairs(state.stars) do
    s.z = s.z - 0.012
    if s.z <= 0.05 then
      s.x, s.y, s.z = state.rng() * 2 - 1, state.rng() * 2 - 1, 1
    end
    local px = math.floor(((s.x / s.z) * 0.5 + 0.5) * (cols - 1) + 0.5) + 1
    local py = math.floor(((s.y / s.z) * 0.5 + 0.5) * (rows - 1) + 0.5) + 1
    if px >= 1 and px <= cols and py >= 1 and py <= rows then
      local near = 1 - s.z
      local i = math.min(5, math.max(1, 1 + math.floor(near * 5)))
      cellrows[py][px] = { GLYPHS[i], COLORS[i] }
    end
  end
  return common.to_frame(cellrows)
end

return M
