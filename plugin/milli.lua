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
    vim.notify("milli: available splashes - " .. table.concat(list, ", "), vim.log.levels.INFO)
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

vim.api.nvim_create_user_command("MilliShader", function(params)
  local runtime = require("milli.runtime")
  local name = params.args
  if name == "" then
    vim.notify("milli: shaders - " .. table.concat(runtime.SHADERS, ", "), vim.log.levels.INFO)
    return
  end
  if not vim.tbl_contains(runtime.SHADERS, name) then
    vim.notify("milli: unknown shader: " .. name, vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "milli-shader://" .. name)
  vim.cmd("buffer! " .. buf)

  local stop = runtime.play_shader(buf, { shader = name })
  local function quit()
    stop()
    pcall(vim.cmd, "bwipeout!")
  end
  vim.keymap.set("n", "q",     quit, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", quit, { buffer = buf, nowait = true, silent = true })
end, {
  nargs = "?",
  desc = "Run a live procedural shader (plasma, rain, doomfire, starfield) in a scratch buffer",
  complete = function(arglead)
    local out = {}
    for _, name in ipairs(require("milli.runtime").SHADERS) do
      if name:sub(1, #arglead) == arglead then table.insert(out, name) end
    end
    return out
  end,
})

vim.api.nvim_create_user_command("MilliInstall", function(params)
  local name = params.args
  if name == "" then
    vim.notify("milli: usage - :MilliInstall <name> (see :MilliBrowse)", vim.log.levels.WARN)
    return
  end
  vim.notify("milli: installing " .. name .. "...", vim.log.levels.INFO)
  require("milli.registry").install(name, function(ok, msg)
    if ok then
      vim.notify("milli: installed " .. name .. " -> " .. msg .. ". Preview: :MilliPreview " .. name, vim.log.levels.INFO)
    else
      vim.notify("milli: " .. msg, vim.log.levels.ERROR)
    end
  end)
end, {
  nargs = "?",
  desc = "Install a community splash from the milli registry",
  complete = function(arglead)
    -- Cold cache kicks off a background fetch; completion fills on next tab.
    local out = {}
    for _, entry in ipairs(require("milli.registry").index_cached()) do
      local name = type(entry) == "table" and entry.name or entry
      if type(name) == "string" and name:sub(1, #arglead) == arglead then
        table.insert(out, name)
      end
    end
    return out
  end,
})

vim.api.nvim_create_user_command("MilliUninstall", function(params)
  local ok, msg = require("milli.registry").uninstall(params.args)
  vim.notify("milli: " .. (ok and ("removed " .. msg) or msg), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
end, {
  nargs = 1,
  desc = "Remove a registry-installed splash",
  complete = function(arglead)
    local out = {}
    for _, name in ipairs(require("milli.registry").installed()) do
      if name:sub(1, #arglead) == arglead then table.insert(out, name) end
    end
    return out
  end,
})

vim.api.nvim_create_user_command("MilliBrowse", function()
  require("milli.registry").index(function(idx, err)
    if not idx then
      vim.notify("milli: " .. (err or "registry unavailable"), vim.log.levels.ERROR)
      return
    end
    local lines = { "milli registry (" .. #idx .. " splashes):" }
    for _, e in ipairs(idx) do
      local name = type(e) == "table" and e.name or tostring(e)
      local desc = type(e) == "table" and (e.desc or "") or ""
      lines[#lines + 1] = ("  %-20s %s"):format(name, desc)
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, true)
end, { desc = "List community splashes available in the milli registry" })
