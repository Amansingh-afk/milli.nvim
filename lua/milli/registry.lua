-- Community splash registry. Splashes are plain frames.lua data files hosted
-- in a GitHub repo; :MilliInstall downloads one into stdpath("data") where
-- runtime.load/list pick it up like any bundled splash.
--
-- Registry layout (override base with vim.g.milli_registry):
--   <base>/index.json            -- [{ "name": ..., "desc": ..., "author": ... }, ...]
--   <base>/splashes/<name>.lua   -- milli export -t lua output

local M = {}

local function base_url()
  return vim.g.milli_registry
    or "https://raw.githubusercontent.com/amansingh-afk/milli-splashes/main"
end

function M.install_dir()
  return vim.fn.stdpath("data") .. "/milli/splashes"
end

local index_cache = nil

local function fetch(url, cb)
  if vim.fn.executable("curl") ~= 1 then
    cb(nil, "curl not found on PATH (required for :MilliInstall)")
    return
  end
  vim.system({ "curl", "-fsSL", "--max-time", "15", url }, { text = true }, function(out)
    if out.code ~= 0 then
      cb(nil, "download failed (" .. url .. "): " .. (out.stderr or ("exit " .. out.code)))
    else
      cb(out.stdout)
    end
  end)
end

-- Validate that downloaded content is a milli data module, not arbitrary
-- code: load it with an EMPTY environment (exports are pure table literals
-- and need no globals) and check the shape.
local function validate(content)
  local chunk, err = load(content, "milli-splash", "t", {})
  if not chunk then return nil, "not valid Lua: " .. tostring(err) end
  local ok, data = pcall(chunk)
  if not ok then return nil, "failed to evaluate: " .. tostring(data) end
  if type(data) ~= "table" or type(data.frames) ~= "table" or #data.frames == 0 then
    return nil, "not a milli splash module (no frames table)"
  end
  return data
end

function M.index(cb, force)
  if index_cache and not force then
    cb(index_cache)
    return
  end
  fetch(base_url() .. "/index.json", function(body, err)
    if not body then
      vim.schedule(function() cb(nil, err) end)
      return
    end
    local ok, parsed = pcall(vim.json.decode, body)
    if not ok or type(parsed) ~= "table" then
      vim.schedule(function() cb(nil, "bad index.json from registry") end)
      return
    end
    index_cache = parsed
    vim.schedule(function() cb(parsed) end)
  end)
end

-- Synchronous view of the index for tab-completion: returns the cache if
-- warm and kicks off a background refresh otherwise.
function M.index_cached()
  if not index_cache then
    M.index(function() end)
  end
  return index_cache or {}
end

function M.installed()
  local out = {}
  for _, path in ipairs(vim.fn.glob(M.install_dir() .. "/*.lua", false, true)) do
    out[#out + 1] = vim.fn.fnamemodify(path, ":t:r")
  end
  table.sort(out)
  return out
end

function M.install(name, cb)
  cb = cb or function() end
  if not name:match("^[%w_%-]+$") then
    cb(false, "bad splash name: " .. name)
    return
  end
  fetch(base_url() .. "/splashes/" .. name .. ".lua", function(body, err)
    vim.schedule(function()
      if not body then
        cb(false, err)
        return
      end
      local data, verr = validate(body)
      if not data then
        cb(false, "registry file rejected: " .. verr)
        return
      end
      vim.fn.mkdir(M.install_dir(), "p")
      local path = M.install_dir() .. "/" .. name .. ".lua"
      local f = io.open(path, "w")
      if not f then
        cb(false, "cannot write " .. path)
        return
      end
      f:write(body)
      f:close()
      cb(true, path .. " (" .. #data.frames .. " frames)")
    end)
  end)
end

function M.uninstall(name)
  local path = M.install_dir() .. "/" .. name .. ".lua"
  if vim.fn.filereadable(path) ~= 1 then
    return false, "not installed: " .. name
  end
  vim.fn.delete(path)
  package.loaded["milli.splashes." .. name] = nil
  return true, path
end

-- Load an installed splash by name; nil if absent.
function M.load_installed(name)
  local path = M.install_dir() .. "/" .. name .. ".lua"
  if vim.fn.filereadable(path) ~= 1 then return nil end
  local chunk = loadfile(path)
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  if not ok then return nil end
  return data
end

return M
