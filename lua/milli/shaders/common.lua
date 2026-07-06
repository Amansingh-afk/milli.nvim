-- Shared helpers for procedural shaders. Shaders build rows of {char, fg}
-- cells; this converts them to the { lines, colors } shape the runtime
-- paints (colors = per-row byte runs {sb, eb, fg, bg}), merging adjacent
-- same-color cells into single runs.
--
-- Colors are quantized to 4 bits/channel here so a truecolor shader can't
-- blow through Neovim's highlight-group cap (same trick as baked exports).

local M = {}

local function quant(n)
  return math.floor(n / 17 + 0.5) * 17
end

function M.rgb(r, g, b)
  return string.format("#%02x%02x%02x", quant(r), quant(g), quant(b))
end

-- h in [0,1), s/v in [0,1] -> quantized "#rrggbb"
function M.hsv(h, s, v)
  h = h % 1
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  local r, g, b
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return M.rgb(r * 255, g * 255, b * 255)
end

-- Deterministic LCG so shaders don't disturb the global math.random state.
function M.lcg(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function()
    s = (s * 16807) % 2147483647
    return (s - 1) / 2147483646
  end
end

-- cellrows: array of rows; each row is array of { ch, fg } (fg = "#hex" or
-- nil for blank). Returns lines (strings) and colors (byte-offset runs).
function M.to_frame(cellrows)
  local lines, colors = {}, {}
  for ri, row in ipairs(cellrows) do
    local parts, runs = {}, {}
    local byte = 0
    local run_start, run_fg = nil, nil
    for _, cell in ipairs(row) do
      local ch = cell[1]
      local fg = cell[2]
      local nbytes = #ch
      if fg ~= run_fg then
        if run_fg ~= nil then
          runs[#runs + 1] = { run_start, byte, run_fg, "NONE" }
        end
        run_start, run_fg = (fg ~= nil) and byte or nil, fg
      end
      parts[#parts + 1] = ch
      byte = byte + nbytes
    end
    if run_fg ~= nil then
      runs[#runs + 1] = { run_start, byte, run_fg, "NONE" }
    end
    lines[ri] = table.concat(parts)
    colors[ri] = runs
  end
  return { lines = lines, colors = colors }
end

return M
