-- /prismarine/kernel/sandbox.lua
-- Prismarine OS v23, stage 1.
-- Builds the restricted environment every app runs in. WHITELIST approach:
-- an app only sees what is copied in here, never the real _G.

local M = {}
local unpack = table.unpack or unpack

-- Paths apps may never see or touch (lowercase, no leading slash).
-- Edit this list to match where v23 keeps its secrets.
M.protected = {
  "startup",
  "startup.lua",
  ".simpleos_settings",
  "prismarine/kernel",
  "prismarine/secure",
}

-- Event names apps may not fake with os.queueEvent.
local RESERVED = {
  timer = true, alarm = true,
  rednet_message = true, modem_message = true,
}

local SAFE_FUNCS = {
  "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
  "tonumber", "tostring", "type", "unpack", "rawequal", "rawget", "rawset",
  "setmetatable", "print", "printError", "write", "read",
}

-- Libraries are shallow-COPIED so an app cannot monkeypatch the real ones.
local SAFE_LIBS = {
  "string", "table", "math", "coroutine", "textutils", "colors", "colours",
  "keys", "vector", "window", "paintutils", "parallel", "bit", "bit32",
  "http", "redstone",
}

local function copyTable(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- ---------------------------------------------------------------- paths

local function normalize(path)
  if type(path) ~= "string" then return nil end
  local ok, p = pcall(fs.combine, "", path)
  if not ok or type(p) ~= "string" then return nil end
  p = p:lower() -- case-insensitive host file systems must not bypass the list
  if p == ".." or p:sub(1, 3) == "../" then return nil end
  return p
end

local function isProtected(path)
  local p = normalize(path)
  if p == nil then return true end -- unparseable or outside the root: deny
  for _, bad in ipairs(M.protected) do
    if p == bad or p:sub(1, #bad + 1) == bad .. "/" then return true end
  end
  return false
end

-- A protected path OR a parent of one. Deleting, moving or copying such a
-- parent would destroy or leak the protected files inside it.
local function touchesProtected(path)
  if isProtected(path) then return true end
  local p = normalize(path)
  if p == "" then return true end -- root contains everything
  for _, bad in ipairs(M.protected) do
    if bad:sub(1, #p + 1) == p .. "/" then return true end
  end
  return false
end

local function deny(path)
  return tostring(path) .. ": Access denied"
end

-- ------------------------------------------------------------------ fs

local function makeFs(proc)
  local F = {}

  for _, name in ipairs({ "combine", "getName", "getDir", "getFreeSpace", "getCapacity" }) do
    F[name] = fs[name]
  end

  -- protected paths look like they do not exist
  for _, name in ipairs({ "exists", "isDir", "isReadOnly", "getSize", "getDrive", "attributes" }) do
    local real = fs[name]
    if real then
      F[name] = function(path, ...)
        if isProtected(path) then
          if name == "exists" or name == "isDir" then return false end
          error(deny(path), 2)
        end
        return real(path, ...)
      end
    end
  end

  F.list = function(path)
    if isProtected(path) then error(deny(path), 2) end
    local out = {}
    for _, name in ipairs(fs.list(path)) do
      if not isProtected(fs.combine(path, name)) then out[#out + 1] = name end
    end
    return out
  end

  F.find = function(pattern)
    local out = {}
    for _, p in ipairs(fs.find(pattern)) do
      if not isProtected(p) then out[#out + 1] = p end
    end
    return out
  end

  F.makeDir = function(path)
    if isProtected(path) then error(deny(path), 2) end
    return fs.makeDir(path)
  end

  F.delete = function(path)
    if touchesProtected(path) then error(deny(path), 2) end
    return fs.delete(path)
  end

  F.move = function(from, to)
    if touchesProtected(from) or isProtected(to) then error(deny(from), 2) end
    return fs.move(from, to)
  end

  F.copy = function(from, to)
    if touchesProtected(from) or isProtected(to) then error(deny(from), 2) end
    return fs.copy(from, to)
  end

  F.open = function(path, mode)
    if isProtected(path) then return nil, deny(path) end
    local h, err = fs.open(path, mode)
    if h and proc and proc.handles then
      proc.handles[h] = true -- weak table; the kernel closes leftovers on stop
    end
    return h, err
  end

  return F
end

-- ---------------------------------------------------------- peripheral
-- Modems are kernel-only: apps never get raw network access.

local function makePeripheral()
  local real = peripheral

  local function isModem(name)
    if type(name) ~= "string" or not real.isPresent(name) then return false end
    for _, t in ipairs({ real.getType(name) }) do
      if t == "modem" then return true end
    end
    return false
  end

  local P = {}
  P.getName = real.getName

  P.getNames = function()
    local out = {}
    for _, n in ipairs(real.getNames()) do
      if not isModem(n) then out[#out + 1] = n end
    end
    return out
  end
  P.isPresent = function(n)
    return real.isPresent(n) and not isModem(n)
  end
  P.getType = function(n)
    if isModem(n) then return nil end
    return real.getType(n)
  end
  if real.hasType then
    P.hasType = function(n, t)
      if isModem(n) then return nil end
      return real.hasType(n, t)
    end
  end
  P.getMethods = function(n)
    if isModem(n) then return nil end
    return real.getMethods(n)
  end
  P.call = function(n, ...)
    if isModem(n) then error("No peripheral attached", 2) end
    return real.call(n, ...)
  end
  P.wrap = function(n)
    if isModem(n) then return nil end
    return real.wrap(n)
  end
  P.find = function(t, filter)
    if t == "modem" then return nil end
    return real.find(t, filter)
  end
  return P
end

-- ---------------------------------------------------------------- term
-- The real term API follows whatever the kernel redirected to (the app's own
-- window). Apps just cannot redirect to the real screen or see it.

local function makeTerm(proc, nativeTerm)
  local T = {}
  for k, v in pairs(term) do
    if type(v) == "function" then
      T[k] = function(...) return term[k](...) end
    end
  end
  T.native = function() return proc.win end
  T.redirect = function(target)
    if target == nativeTerm then
      error("Cannot redirect to the system display", 2)
    end
    return term.redirect(target)
  end
  return T
end

-- ------------------------------------------------------------------ os

local function makeOs(proc)
  local o = {}
  for _, name in ipairs({
    "pullEvent", "pullEventRaw", "clock", "time", "day", "epoch", "date",
    "getComputerID", "computerID", "getComputerLabel", "computerLabel", "version",
  }) do
    o[name] = os[name]
  end

  -- timers and alarms are tracked so the kernel can cancel them on stop
  o.startTimer = function(t)
    local id = os.startTimer(t)
    proc.timers[id] = true
    return id
  end
  o.cancelTimer = function(id)
    if proc.timers[id] then
      proc.timers[id] = nil
      os.cancelTimer(id)
    end
  end
  o.setAlarm = function(t)
    local id = os.setAlarm(t)
    proc.alarms[id] = true
    return id
  end
  o.cancelAlarm = function(id)
    if proc.alarms[id] then
      proc.alarms[id] = nil
      os.cancelAlarm(id)
    end
  end
  o.queueEvent = function(name, ...)
    if type(name) == "string" then
      if RESERVED[name] or name:sub(1, 3) == "pm_" or name:sub(1, 7) == "kernel_" then
        error("Event name '" .. name .. "' is reserved", 2)
      end
    end
    return os.queueEvent(name, ...)
  end
  -- NOT provided: os.shutdown, os.reboot, os.run, os.loadAPI (kernel service later)
  return o
end

-- --------------------------------------------------------------- build

function M.build(proc, api, nativeTerm)
  local env = {}

  for _, name in ipairs(SAFE_FUNCS) do env[name] = _G[name] end
  for _, name in ipairs(SAFE_LIBS) do
    if type(_G[name]) == "table" then env[name] = copyTable(_G[name]) end
  end
  if env.redstone then env.rs = env.redstone end

  env._G = env
  env.os = makeOs(proc)
  env.fs = makeFs(proc)
  env.term = makeTerm(proc, nativeTerm)
  env.peripheral = makePeripheral()
  env.prismarine = api

  -- sleep() must use the tracked os so frozen apps can have timers buffered
  env.sleep = function(t)
    local id = env.os.startTimer(tonumber(t) or 0)
    repeat
      local _, got = env.os.pullEvent("timer")
    until got == id
  end

  -- the string metatable points at the real string table; hand out a decoy
  env.getmetatable = function(v)
    if type(v) == "string" then
      return { __index = env.string, __metatable = false }
    end
    return getmetatable(v)
  end

  -- load/loadstring would default to the REAL global table: force our env
  env.load = function(chunk, name, mode, e)
    return load(chunk, name, "t", e or env)
  end
  env.loadstring = function(s, name)
    return load(s, name or "=(loadstring)", "t", env)
  end
  env.loadfile = function(path, mode, e)
    if type(mode) == "table" and e == nil then e = mode end
    local h = env.fs.open(path, "r")
    if not h then
      return nil, tostring(path) .. ": cannot open (missing or access denied)"
    end
    local src = h.readAll()
    h.close()
    return load(src or "", "@" .. tostring(path), "t", e or env)
  end
  env.dofile = function(path)
    local fn, err = env.loadfile(path)
    if not fn then error(err, 0) end
    return fn()
  end

  -- Deliberately absent: getfenv, setfenv, debug, rednet, gps, shell,
  -- require, os.run. getfenv/setfenv would let an app reach the kernel's
  -- real globals through any function the kernel handed it.
  return env
end

return M
