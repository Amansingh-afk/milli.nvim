-- milli.nvim screensaver: after N seconds without a typed key, cover the
-- editor with a fullscreen float running a live shader (or a looping
-- splash). Any key wakes it - the wake key is swallowed, so nothing leaks
-- into your buffer. Layout, mode and cursor are untouched: the float sits
-- on top and is simply closed on wake.

local runtime = require("milli.runtime")

local M = {}

local on_key_ns = vim.api.nvim_create_namespace("milli_screensaver")
local uv = vim.uv or vim.loop

local DEFAULTS = {
  shader = "random", -- shader name | "random" | { "rain", "doomfire" } | nil
  splash = nil,      -- splash name to loop instead of a shader
  after = 300,       -- seconds idle before it kicks in
  fps = nil,         -- shader fps override
  bg = nil,          -- "#rrggbb" float background; nil = your Normal bg
  seed = nil,
  hue = nil,
}

local cfg = nil        -- resolved config; nil = not enabled
local last_input = 0   -- uv.now() of last typed key
local poll = nil       -- uv timer
local active = nil     -- { buf, win, stop, restore_insert, augroup } while showing

local on_key -- defined below; registered while enabled or showing

local function pick(list)
  if type(list) == "string" then
    if list ~= "random" then return list end
    list = runtime.SHADERS
  end
  return runtime.pick(list)
end

-- Only wake/idle on modes where swapping the current window is safe.
local function mode_ok()
  local m = vim.fn.mode(1)
  if m:sub(1, 1) ~= "n" and m:sub(1, 1) ~= "i" then return false end
  if vim.fn.getcmdwintype() ~= "" then return false end
  if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then return false end
  return true
end

local function centered_frame0(data, w, h)
  local frame = data.frames[1]
  local cols = data.cols or 0
  if cols == 0 then
    for _, line in ipairs(frame) do
      cols = math.max(cols, vim.fn.strdisplaywidth(line))
    end
  end
  local left = math.max(0, math.floor((w - cols) / 2))
  local top = math.max(0, math.floor((h - #frame) / 2))
  local pad = string.rep(" ", left)
  local lines = {}
  for _ = 1, top do lines[#lines + 1] = "" end
  for _, line in ipairs(frame) do lines[#lines + 1] = pad .. line end
  return lines
end

function M.is_active() return active ~= nil end

function M.hide()
  local a = active
  if not a then return end
  active = nil
  if a.stop then a.stop() end
  pcall(vim.api.nvim_del_augroup_by_id, a.augroup)
  if a.win and vim.api.nvim_win_is_valid(a.win) then
    pcall(vim.api.nvim_win_close, a.win, true)
  end
  if a.buf and vim.api.nvim_buf_is_valid(a.buf) then
    pcall(vim.api.nvim_buf_delete, a.buf, { force = true })
  end
  if a.restore_insert then vim.cmd("startinsert") end
  if not cfg then pcall(vim.on_key, nil, on_key_ns) end
  last_input = uv.now()
end

-- Show now. opts override the configured ones for this showing only.
function M.show(opts)
  if active then return end
  opts = vim.tbl_extend("force", cfg or DEFAULTS, opts or {})
  if not mode_ok() then return end

  local want_splash = opts.splash
  local shader = (not want_splash) and pick(opts.shader) or nil
  if not want_splash and not shader then return end

  local data = nil
  if want_splash then
    local ok, d = pcall(runtime.load, { splash = want_splash })
    if not ok or not d or not d.frames then
      vim.notify("milli: screensaver splash not found: " .. tostring(want_splash), vim.log.levels.ERROR)
      return
    end
    data = d
  end

  local restore_insert = vim.fn.mode(1):sub(1, 1) == "i"
  if restore_insert then vim.cmd("stopinsert") end
  vim.on_key(on_key, on_key_ns) -- so a one-off :MilliScreensaver still wakes on any key

  local w, h = vim.o.columns, vim.o.lines - vim.o.cmdheight
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "milli-screensaver://" .. (want_splash or shader))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = 0, col = 0, width = w, height = h,
    style = "minimal", focusable = true, zindex = 250, noautocmd = true,
  })
  local hl = "Normal"
  if opts.bg then
    vim.api.nvim_set_hl(0, "MilliScreensaver", { bg = opts.bg })
    hl = "MilliScreensaver"
  end
  vim.wo[win].winhighlight = "Normal:" .. hl .. ",NormalFloat:" .. hl .. ",EndOfBuffer:" .. hl
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false

  local stop
  if data then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, centered_frame0(data, w, h))
    vim.bo[buf].modifiable = false
    runtime.play(buf, { data = data, loop = true })
  else
    stop = runtime.play_shader(buf, {
      shader = shader, cols = w, rows = h, fps = opts.fps, seed = opts.seed, hue = opts.hue,
    })
  end

  local augroup = vim.api.nvim_create_augroup("milli_screensaver_active", { clear = true })
  active = { buf = buf, win = win, stop = stop, restore_insert = restore_insert, augroup = augroup }

  -- Resize: rebuild at the new size. Anything else that steals the window
  -- (a plugin opening a float, :q on the float) just tears it down.
  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      local again = { shader = shader, splash = want_splash }
      vim.schedule(function()
        M.hide()
        M.show(vim.tbl_extend("force", opts, again))
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinLeave", "WinClosed", "BufWipeout" }, {
    group = augroup,
    callback = function(ev)
      if ev.event == "WinClosed" and tonumber(ev.match) ~= win then return end
      if ev.event == "BufWipeout" and ev.buf ~= buf then return end
      vim.schedule(M.hide)
    end,
  })
end

on_key = function(_, typed)
  -- typed == "" means the key came from a mapping/feedkeys, not the human.
  if typed == "" then return end
  if active then
    vim.schedule(M.hide)
    return "" -- swallow the wake key
  end
  last_input = uv.now()
end

local function tick()
  if active or not cfg then return end
  if uv.now() - last_input < cfg.after * 1000 then return end
  vim.schedule(function()
    if active or not cfg then return end
    if uv.now() - last_input < cfg.after * 1000 then return end
    M.show()
  end)
end

function M.disable()
  M.hide()
  cfg = nil
  if poll then poll:stop() poll:close() poll = nil end
  pcall(vim.on_key, nil, on_key_ns)
  pcall(vim.api.nvim_del_augroup_by_name, "milli_screensaver")
end

-- Enable the idle screensaver. See DEFAULTS for opts.
function M.enable(opts)
  M.disable()
  cfg = vim.tbl_extend("force", DEFAULTS, opts or {})
  if cfg.after <= 0 then cfg.after = DEFAULTS.after end
  last_input = uv.now()

  vim.on_key(on_key, on_key_ns)
  -- Mouse/scroll and edits made by other means still count as activity.
  local group = vim.api.nvim_create_augroup("milli_screensaver", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "ModeChanged" }, {
    group = group,
    callback = function()
      if not active then last_input = uv.now() end
    end,
  })

  poll = uv.new_timer()
  poll:start(1000, 1000, tick)
  return cfg
end

return M
