-- milli.nvim: animated ASCII splash screens for neovim.
-- See README for install + usage. Bundled splashes live in lua/milli/splashes/.
-- Generate your own via the `milli` CLI (`milli export -t lua --no-helper ...`)
-- and drop the emitted `frames.lua` into that directory (rename to <name>.lua).

local runtime = require("milli.runtime")

local M = {}

M.play = runtime.play
M.list = runtime.list
M.load = runtime.load

-- A string opts value is sugar for `{ splash = "<name>" }`.
local function resolve(opts)
  if type(opts) == "string" then return { splash = opts } end
  return opts or {}
end

-- Preset: dashboard-nvim. Attach to its FileType event.
-- The user is still responsible for setting `header = require("milli").load(opts).frames[1]`
-- in their dashboard config so the anchor has something to match.
function M.dashboard(opts)
  opts = resolve(opts)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "dashboard",
    callback = function(args) runtime.play(args.buf, opts) end,
  })
end

-- Preset: alpha-nvim.
function M.alpha(opts)
  opts = resolve(opts)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "alpha",
    callback = function(args) runtime.play(args.buf, opts) end,
  })
end

-- Preset: mini.starter. Uses its MiniStarterOpened user event.
function M.starter(opts)
  opts = resolve(opts)
  vim.api.nvim_create_autocmd("User", {
    pattern = "MiniStarterOpened",
    callback = function(args) runtime.play(args.buf, opts) end,
  })
end

-- Preset: snacks.nvim dashboard. Listens for the SnacksDashboardOpened
-- user event (fires after the initial render finishes, so the
-- anchor-search can locate frame 0 reliably). Re-attaches on
-- SnacksDashboardUpdatePost so window resizes don't kill the animation.
-- User still seeds the header via `preset.header` - see README.
function M.snacks(opts)
  opts = resolve(opts)
  local function attach()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype == "snacks_dashboard" then
      runtime.play(buf, opts)
    end
  end
  vim.api.nvim_create_autocmd("User", {
    pattern = { "SnacksDashboardOpened", "SnacksDashboardUpdatePost" },
    callback = function() vim.schedule(attach) end,
  })
end

-- Preset: raw VimEnter (no dashboard plugin). Seeds the current empty
-- buffer with frame 0 so the anchor-search finds itself, then plays.
function M.vimenter(opts)
  opts = resolve(opts)
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      if vim.fn.argc() > 0 then return end
      local ok, data = pcall(runtime.load, opts)
      if not ok or not data or not data.frames then return end
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.frames[1])
      vim.bo[buf].modifiable = false
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      runtime.play(buf, opts)
    end,
  })
end

-- Reserved for future global config. No-op today.
function M.setup(_opts) end

return M
