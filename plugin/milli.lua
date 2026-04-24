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

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, data.frames[1])
  vim.bo[buf].modifiable = false

  vim.api.nvim_set_current_buf(buf)

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
