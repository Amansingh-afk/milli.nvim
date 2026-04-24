-- milli.nvim command registration. Loaded automatically by Neovim on startup.

if vim.g.loaded_milli then return end
vim.g.loaded_milli = true

vim.api.nvim_create_user_command("MilliPreview", function(params)
  local name = params.args
  if name == "" then
    local list = require("milli").list()
    if #list == 0 then
      vim.notify("milli: no bundled splashes found in lua/milli/splashes/", vim.log.levels.WARN)
      return
    end
    vim.notify("milli: available splashes — " .. table.concat(list, ", "), vim.log.levels.INFO)
    return
  end

  local runtime = require("milli.runtime")
  local ok, data = pcall(runtime.load, { splash = name })
  if not ok or not data or not data.frames then
    vim.notify("milli: splash not found: " .. name, vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "milli://" .. name)

  vim.cmd("buffer! " .. buf)

  local win_w = vim.api.nvim_win_get_width(0)
  local win_h = vim.api.nvim_win_get_height(0)
  local frame = data.frames[1]
  local cols = data.cols or 0
  if cols == 0 then
    for _, line in ipairs(frame) do
      if vim.fn.strdisplaywidth(line) > cols then cols = vim.fn.strdisplaywidth(line) end
    end
  end
  local rows = #frame
  local left_pad = math.max(0, math.floor((win_w - cols) / 2))
  local top_pad  = math.max(0, math.floor((win_h - rows) / 2))
  local pad_str = string.rep(" ", left_pad)

  local lines = {}
  for _ = 1, top_pad do table.insert(lines, "") end
  for _, line in ipairs(frame) do table.insert(lines, pad_str .. line) end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.keymap.set("n", "q",     "<cmd>bwipeout<cr>", { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>bwipeout<cr>", { buffer = buf, nowait = true, silent = true })

  runtime.play(buf, { splash = name, loop = true })
end, {
  nargs = "?",
  desc = "Preview a bundled milli splash in a scratch buffer",
  complete = function(arglead)
    local list = require("milli").list()
    local out = {}
    for _, name in ipairs(list) do
      if name:sub(1, #arglead) == arglead then table.insert(out, name) end
    end
    return out
  end,
})
