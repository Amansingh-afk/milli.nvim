-- Matrix rain shader: per-column glyph streams, bright head, fading tail.

local common = require("milli.shaders.common")

local M = { fps = 20 }

local CHARS = {}
for c in ("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅZ:･.=*+-<>0123456789"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
  CHARS[#CHARS + 1] = c
end

-- Precomputed green ramp (8 steps) + white head; tiny fixed palette.
local GREENS = {}
for i = 1, 8 do
  local k = math.max(0.12, i / 8)
  GREENS[i] = common.rgb(0, 255 * k, 70 * k)
end
local HEAD = common.rgb(235, 255, 235)

function M.new(cols, rows, opts)
  local rng = common.lcg((opts and opts.seed) or 1337)
  local drops = {}
  for x = 1, cols do
    drops[x] = {
      y = -math.floor(rng() * rows * 2),
      speed = 0.3 + rng() * 0.7,
      len = 4 + math.floor(rng() * rows / 2),
    }
  end
  return { cols = cols, rows = rows, drops = drops, rng = rng }
end

function M.frame(state, tick)
  local cols, rows = state.cols, state.rows
  local crng = common.lcg(1337 + math.floor(tick / 2) * 7919)
  local cellrows = {}
  for y = 1, rows do
    local row = {}
    for x = 1, cols do row[x] = { " ", nil } end
    cellrows[y] = row
  end
  for x = 1, cols do
    local d = state.drops[x]
    d.y = d.y + d.speed
    if d.y - d.len > rows then
      d.y = -math.floor(state.rng() * rows)
      d.speed = 0.3 + state.rng() * 0.7
      d.len = 4 + math.floor(state.rng() * rows / 2)
    end
    local head = math.floor(d.y)
    for k = 0, d.len - 1 do
      local y = head - k
      if y >= 1 and y <= rows then
        local ch = CHARS[1 + math.floor(crng() * #CHARS)]
        local fg
        if k == 0 then
          fg = HEAD
        else
          fg = GREENS[math.max(1, math.ceil((1 - k / d.len) * 8))]
        end
        cellrows[y][x] = { ch, fg }
      end
    end
  end
  return common.to_frame(cellrows)
end

return M
