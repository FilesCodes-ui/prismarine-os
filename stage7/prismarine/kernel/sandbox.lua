--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/kernel/sandbox.lua
-- Prismarine OS v24, stage 7.
-- Builds the restricted environment every app runs in. WHITELIST approach:
-- an app only sees what is copied in here, never the real _G.
--
-- Every process has a policy (see M.policy):
--   protected   paths the app cannot see at all
--   readonly    paths the app can read but not change
--   writable    when set, the only paths the app may change
--   disksRO     disk drives are read only
--   rawLua      may it turn text into code (load, loadstring)
--   canRun      check(path) before it runs another file (os.run, dofile)

local M = {}
local unpack = table.unpack or unpack

-- Never visible to any app.
M.protected = {
  "startup", "startup.lua", ".settings", ".simpleos_settings",
  "prismarine/kernel", "prismarine/secure", "prismarine/sys", "prismarine/boot.lua", "prismarine/archive",
}
-- Visible but never changed by apps.
M.readonly = { "prismarine", "rom" }

-- Event names an app can never queue: real input, system and kernel events.
local SYSTEM_EVENTS = {
  key = true, key_up = true, char = true, paste = true, terminate = true,
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
  timer = true, alarm = true, modem_message = true, rednet_message = true,
  http_success = true, http_failure = true, http_check = true,
  websocket_success = true, websocket_failure = true, websocket_message = true, websocket_closed = true,
  peripheral = true, peripheral_detach = true, disk = true, disk_eject = true,
  monitor_touch = true, monitor_resize = true, term_resize = true, redstone = true,
  turtle_inventory = true, speaker_audio_empty = true, file_transfer = true, computer_command = true,
  task_complete = true,
}

local SAFE_FUNCS = {
  "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select",
  "tonumber", "tostring", "type", "unpack", "rawequal", "rawget", "rawset", "rawlen",
  "setmetatable", "print", "printError", "write", "read", "_HOST", "_CC_DEFAULT_SETTINGS",
}

-- Shallow-copied so an app cannot monkeypatch the real ones.
local SAFE_LIBS = {
  "string", "table", "math", "coroutine", "textutils", "colors", "colours",
  "keys", "vector", "window", "parallel", "bit", "bit32", "http", "redstone", "utf8",
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
M.normalize = normalize

local function under(p, list)
  for _, bad in ipairs(list) do
    if p == bad or p:sub(1, #bad + 1) == bad .. "/" then return true end
  end
  return false
end

local function isDisk(p)
  local top = p:match("^([^/]+)")
  if not top then return false end
  local ok, drive = pcall(fs.getDrive, top)
  return ok and drive ~= nil and drive ~= "hdd" and drive ~= "rom" and top ~= "rom"
end

-- Default policy: everything but the system is open.
function M.policy(over)
  local p = {
    protected = M.protected, readonly = M.readonly, writable = nil,
    disksRO = false, rawLua = true, canRun = nil, homeDir = nil,
  }
  for k, v in pairs(over or {}) do p[k] = v end
  return p
end

local function makeChecks(policy)
  local C = {}
  function C.hidden(path)
    local p = normalize(path)
    if p == nil then return true end
    return under(p, policy.protected)
  end
  -- A hidden path or a parent of one. Deleting, moving or copying such a
  -- parent would destroy or leak what is inside.
  function C.containsHidden(path)
    if C.hidden(path) then return true end
    local p = normalize(path)
    if p == "" then return true end
    for _, bad in ipairs(policy.protected) do
      if bad:sub(1, #p + 1) == p .. "/" then return true end
    end
    return false
  end
  function C.canWrite(path)
    local p = normalize(path)
    if p == nil or C.hidden(path) then return false end
    if under(p, policy.readonly) then return false end
    for _, ro in ipairs(policy.readonly) do
      if ro:sub(1, #p + 1) == p .. "/" then return false end -- a parent of a read-only folder
    end
    if p == "" then return false end
    if policy.disksRO and isDisk(p) then return false end
    if policy.writable then return under(p, policy.writable) end
    return true
  end
  return C
end
M.makeChecks = makeChecks

local function deny(path)
  return "/" .. tostring(path) .. ": Access denied"
end

-- ------------------------------------------------------------------ fs

local function makeFs(proc, policy)
  local chk = makeChecks(policy)
  local F = {}
  local ask = proc and proc.checkPerm

  -- An app's own places: its appdata folder, its own file and the folder that
  -- file sits in (unless that is the root). Reading the system folders is free.
  local own = {}
  if proc and proc.home then own[#own + 1] = normalize(proc.home) end
  if proc and proc.spec and proc.spec.path then
    local f = normalize(proc.spec.path)
    if f then
      own[#own + 1] = f
      local d = fs.getDir(f)
      if d ~= "" and d ~= ".." then own[#own + 1] = normalize(d) end
    end
  end
  -- true when the app may touch the path without asking
  local function free(path, reading)
    if not ask then return true end
    local p = normalize(path)
    if p == nil then return true end
    if p ~= "" and under(p, own) then return true end
    if reading and p ~= "" and under(p, policy.readonly) then return true end
    return false
  end
  local function allowed(path, reading, verb)
    if free(path, reading) then return true end
    return ask("files", verb .. " /" .. tostring(path):gsub("^/", ""))
  end

  for _, name in ipairs({ "combine", "getName", "getDir" }) do F[name] = fs[name] end

  for _, name in ipairs({ "getFreeSpace", "getCapacity" }) do
    local real = fs[name]
    if real then
      F[name] = function(path)
        if chk.hidden(path) then error(deny(path), 2) end
        return real(path)
      end
    end
  end

  F.exists = function(path)
    if chk.hidden(path) then return false end
    return fs.exists(path)
  end
  F.isDir = function(path)
    if chk.hidden(path) then return false end
    return fs.isDir(path)
  end
  F.isReadOnly = function(path)
    if chk.hidden(path) then return true end
    return fs.isReadOnly(path) or not chk.canWrite(path)
  end
  for _, name in ipairs({ "getSize", "getDrive", "attributes" }) do
    local real = fs[name]
    if real then
      F[name] = function(path, ...)
        if chk.hidden(path) then
          if name == "getDrive" then return nil end
          error("/" .. tostring(path) .. ": No such file", 2)
        end
        local r = { real(path, ...) }
        if name == "attributes" and type(r[1]) == "table" then
          r[1] = copyTable(r[1])
          r[1].isReadOnly = r[1].isReadOnly or not chk.canWrite(path)
        end
        return unpack(r)
      end
    end
  end
  if fs.isDriveRoot then
    F.isDriveRoot = function(path)
      if chk.hidden(path) then return false end
      return fs.isDriveRoot(path)
    end
  end

  F.list = function(path)
    if chk.hidden(path) then error("/" .. tostring(path) .. ": Not a directory", 2) end
    if not allowed(path, true, "Look in") then error(deny(path), 2) end
    local out = {}
    for _, name in ipairs(fs.list(path)) do
      if not chk.hidden(fs.combine(path, name)) then out[#out + 1] = name end
    end
    return out
  end

  F.find = function(pattern)
    local out = {}
    for _, p in ipairs(fs.find(pattern)) do
      if not chk.hidden(p) and (free(p, true) or allowed(p, true, "Search")) then out[#out + 1] = p end
    end
    return out
  end

  F.makeDir = function(path)
    if not chk.canWrite(path) then error(deny(path), 2) end
    if not allowed(path, false, "Change") then error(deny(path), 2) end
    return fs.makeDir(path)
  end

  F.delete = function(path)
    if chk.containsHidden(path) or not chk.canWrite(path) then error(deny(path), 2) end
    if not allowed(path, false, "Delete") then error(deny(path), 2) end
    return fs.delete(path)
  end

  F.move = function(from, to)
    if chk.containsHidden(from) or not chk.canWrite(from) then error(deny(from), 2) end
    if not chk.canWrite(to) then error(deny(to), 2) end
    if not allowed(from, false, "Move") or not allowed(to, false, "Change") then error(deny(from), 2) end
    return fs.move(from, to)
  end

  F.copy = function(from, to)
    if chk.containsHidden(from) then error(deny(from), 2) end
    if not chk.canWrite(to) then error(deny(to), 2) end
    if not allowed(from, true, "Read") or not allowed(to, false, "Change") then error(deny(from), 2) end
    return fs.copy(from, to)
  end

  F.open = function(path, mode)
    if type(mode) ~= "string" then error("bad argument #2 (string expected)", 2) end
    if chk.hidden(path) then return nil, "/" .. tostring(path) .. ": No such file" end
    if mode:find("[wa+]") and not chk.canWrite(path) then return nil, deny(path) end
    local writing = mode:find("[wa+]") ~= nil
    if not allowed(path, not writing, writing and "Change" or "Read") then return nil, deny(path) end
    local h, err = fs.open(path, mode)
    if h and proc and proc.handles then
      proc.handles[h] = true -- weak table; the kernel closes leftovers on stop
    end
    return h, err
  end

  return F, chk
end

-- ---------------------------------------------------------- peripheral
-- Modems are kernel-only: apps never get raw network access.

local SAFE_TYPES = { speaker = true, monitor = true, printer = true, drive = true }

local function makePeripheral(proc)
  local real = peripheral
  local ask = proc and proc.checkPerm

  local function isModem(name)
    if type(name) ~= "string" or not real.isPresent(name) then return false end
    for _, t in ipairs({ real.getType(name) }) do
      if t == "modem" then return true end
    end
    return false
  end

  -- "safe" (speaker, monitor, printer, drive), "redstone" or "device"
  local function kind(name)
    local rs, safe = false, false
    for _, t in ipairs({ real.getType(name) }) do
      local tl = tostring(t):lower()
      if SAFE_TYPES[tl] then safe = true end
      if tl:find("redstone", 1, true) then rs = true end
    end
    if rs then return "redstone" end
    if safe then return "safe" end
    return "device"
  end
  -- Reading a redstone peripheral is free. Setting an output asks.
  local function mutating(m)
    m = tostring(m)
    return m:find("^set") ~= nil or m:find("^pulse") ~= nil or m:find("^toggle") ~= nil
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
  P.call = function(n, m, ...)
    if isModem(n) then error("No peripheral attached", 2) end
    if ask and real.isPresent(n) then
      local k = kind(n)
      if k == "device" and not ask("devices", tostring(n) .. ": " .. tostring(m)) then
        error("Not allowed to use " .. tostring(n), 2)
      elseif k == "redstone" and mutating(m) and not ask("redstone", tostring(n) .. ": " .. tostring(m)) then
        return nil
      end
    end
    return real.call(n, m, ...)
  end
  P.wrap = function(n)
    if isModem(n) then return nil end
    if not real.isPresent(n) then return nil end
    if not ask or kind(n) == "safe" then return real.wrap(n) end
    local proxy = {}
    for _, m in ipairs(real.getMethods(n)) do
      proxy[m] = function(...) return P.call(n, m, ...) end
    end
    return proxy
  end
  P.find = function(t, filter)
    if t == "modem" then return nil end
    local out = {}
    for _, n in ipairs(P.getNames()) do
      local match = false
      for _, ty in ipairs({ real.getType(n) }) do
        if ty == t then match = true end
      end
      if match then
        local w = P.wrap(n)
        if w and (not filter or filter(n, w)) then out[#out + 1] = w end
      end
    end
    return unpack(out)
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
    if type(target) ~= "table" then error("bad argument #1 (table expected)", 2) end
    if target == nativeTerm or target == term.native() then
      error("Cannot redirect to the system display", 2)
    end
    return term.redirect(target)
  end
  return T
end

-- ---------------------------------------------------------------- settings
-- Reads fall through to the real settings. Changes stay inside the app.

local function makeSettings()
  local real = settings
  local over, unset = {}, {}
  local S = {}
  S.get = function(name, default)
    if over[name] ~= nil then return over[name] end
    if unset[name] then return default end
    return real.get(name, default)
  end
  S.set = function(name, value) over[name], unset[name] = value, nil end
  S.unset = function(name) over[name], unset[name] = nil, true end
  S.clear = function() over, unset = {}, {} end
  S.define = function() end
  S.undefine = function() end
  S.getNames = function()
    local seen, out = {}, {}
    for _, n in ipairs(real.getNames()) do seen[n] = true end
    for n in pairs(over) do seen[n] = true end
    for n in pairs(seen) do out[#out + 1] = n end
    table.sort(out)
    return out
  end
  S.getDetails = function(name)
    local d = real.getDetails and real.getDetails(name) or {}
    d = copyTable(d)
    d.value = S.get(name)
    d.changed = d.value ~= d.default
    return d
  end
  S.load = function() return false end
  S.save = function() return false end
  return S
end

-- ------------------------------------------------------------------ os

local function makeOs(proc, env)
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
  -- An app's own events come back only to that app, through the kernel.
  o.queueEvent = function(name, ...)
    if type(name) ~= "string" then error("bad argument #1 (string expected)", 2) end
    if SYSTEM_EVENTS[name] or name:sub(1, 3) == "pm_" or name:sub(1, 7) == "kernel_" or name:sub(1, 10) == "prismarine" then
      error("Event name '" .. name .. "' is reserved", 2)
    end
    return os.queueEvent("pm_app", proc.pid, proc.gen, name, ...)
  end
  o.sleep = function(t) return env.sleep(t) end
  o.run = function(runEnv, path, ...)
    if type(runEnv) ~= "table" then error("bad argument #1 (table expected)", 2) end
    if type(path) ~= "string" then error("bad argument #2 (string expected)", 2) end
    local childEnv = setmetatable(runEnv, { __index = env })
    local fn, err = env.loadfile(path, nil, childEnv)
    if fn then
      local args = table.pack(...)
      local ok, e = pcall(function() return fn(unpack(args, 1, args.n)) end)
      if not ok then
        if e and e ~= "" then printError(e) end
        return false
      end
      return true
    end
    if err and err ~= "" then printError(err) end
    return false
  end
  o.loadAPI = function(path)
    if type(path) ~= "string" then error("bad argument #1 (string expected)", 2) end
    local name = fs.getName(path):gsub("%.lua$", "")
    local apiEnv = setmetatable({}, { __index = env })
    local fn, err = env.loadfile(path, nil, apiEnv)
    if not fn then printError(err) return false end
    local ok, e = pcall(fn)
    if not ok then printError(e) return false end
    local api = {}
    for k, v in pairs(apiEnv) do if k ~= "_ENV" then api[k] = v end end
    env[name] = api
    return true
  end
  o.unloadAPI = function(name) if type(name) == "string" and name ~= "_G" then env[name] = nil end end
  -- NOT provided: os.shutdown, os.reboot (the Power menu does that), setComputerLabel
  return o
end

-- --------------------------------------------------------------- build

-- Load a ROM API file inside the app's own environment, so its file access
-- goes through the app's sandboxed fs.
local function romApi(env, path)
  local h = fs.open(path, "r")
  if not h then return nil end
  local src = h.readAll()
  h.close()
  local apiEnv = setmetatable({}, { __index = env })
  local fn = load(src, "@/" .. path, "t", apiEnv)
  if not fn then return nil end
  local ok = pcall(fn)
  if not ok then return nil end
  local api = {}
  for k, v in pairs(apiEnv) do api[k] = v end
  return api
end

function M.build(proc, api, nativeTerm, policy)
  policy = policy or M.policy()
  local env = {}

  for _, name in ipairs(SAFE_FUNCS) do env[name] = _G[name] end
  for _, name in ipairs(SAFE_LIBS) do
    if type(_G[name]) == "table" then env[name] = copyTable(_G[name]) end
  end
  local ask = proc and proc.checkPerm
  if ask then
    -- The internet is ask-first.
    if env.http then
      for k, v in pairs(env.http) do
        if type(v) == "function" then
          env.http[k] = function(a, ...)
            local url = type(a) == "table" and a.url or a
            if not ask("web", tostring(url)) then
              if k == "request" or k == "websocketAsync" or k == "checkURLAsync" then return false, "Internet is not allowed" end
              return nil, "Internet is not allowed"
            end
            return v(a, ...)
          end
        end
      end
    end
    -- Redstone input is free. Output is ask-first.
    if env.redstone then
      for _, k in ipairs({ "setOutput", "setAnalogOutput", "setAnalogueOutput", "setBundledOutput" }) do
        local v = env.redstone[k]
        if v then
          env.redstone[k] = function(side, ...)
            if not ask("redstone", tostring(side)) then return false end
            return v(side, ...)
          end
        end
      end
    end
  end
  if env.redstone then env.rs = env.redstone end
  if env.string then env.string.dump = nil end

  env._G = env
  local sfs, chk = makeFs(proc, policy)
  env.fs = sfs
  env.os = makeOs(proc, env)
  env.term = makeTerm(proc, nativeTerm)
  env.peripheral = makePeripheral(proc)
  env.settings = makeSettings()
  env.prismarine = api
  proc.checks = chk

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

  -- Code from a file the policy allows to run.
  local function runnable(path, src)
    if policy.canRun then
      local ok, why = policy.canRun(path, src)
      if not ok then return false, why end
    end
    return true
  end

  -- load/loadstring would default to the REAL global table: force our env.
  -- Without rawLua, text cannot become code (Archive mode).
  env.load = function(chunk, name, mode, e)
    if not policy.rawLua then
      return nil, "Running new code is blocked on this computer"
    end
    if type(chunk) ~= "string" and type(chunk) ~= "function" then
      error("bad argument #1 (string expected)", 2)
    end
    return load(chunk, name, "t", e or env)
  end
  env.loadstring = function(s, name)
    if not policy.rawLua then
      return nil, "Running new code is blocked on this computer"
    end
    return load(s, name or "=(loadstring)", "t", env)
  end
  env.loadfile = function(path, mode, e)
    if type(mode) == "table" and e == nil then e = mode end
    local h = env.fs.open(path, "r")
    if not h then
      return nil, "File not found"
    end
    local src = h.readAll()
    h.close()
    local ok, why = runnable(path, src)
    if not ok then return nil, why or "Blocked" end
    return load(src or "", "@/" .. fs.combine("", path), "t", e or env)
  end
  env.dofile = function(path)
    local fn, err = env.loadfile(path)
    if not fn then error(err, 0) end
    return fn()
  end

  -- ROM APIs that touch files, loaded inside this environment.
  for _, name in ipairs({ "paintutils", "io", "help", "disk" }) do
    local a = romApi(env, "rom/apis/" .. name .. ".lua")
    if a then env[name] = a end
  end
  -- fs.complete and friends come from the ROM's fs.lua, on top of our fs.
  do
    local h = fs.open("rom/apis/fs.lua", "r")
    if h then
      local src = h.readAll()
      h.close()
      local fsEnv = setmetatable({}, { __index = env })
      local fn = load(src, "@/rom/apis/fs.lua", "t", fsEnv)
      if fn and pcall(fn) then
        for k, v in pairs(fsEnv) do
          if type(v) == "function" and env.fs[k] == nil then env.fs[k] = v end
        end
      end
    end
  end

  -- require, like the shell gives every program.
  local okR, reqMod = pcall(function()
    local h = fs.open("rom/modules/main/cc/require.lua", "r")
    local src = h.readAll()
    h.close()
    -- The module only asks the debug library for the loaded-module registry.
    local modEnv = setmetatable({ debug = { getregistry = function() return nil end } }, { __index = env })
    return load(src, "@/rom/modules/main/cc/require.lua", "t", modEnv)()
  end)
  if okR and type(reqMod) == "table" and reqMod.make then
    local dir = proc.spec and proc.spec.path and fs.getDir(proc.spec.path) or ""
    local okM, req, pkg = pcall(reqMod.make, env, dir)
    if okM then
      env.require, env.package = req, pkg
      if type(pkg.path) == "string" then pkg.path = pkg.path .. ";/prismarine/lib/?.lua" end
    end
  end

  -- Deliberately absent: getfenv, setfenv, debug, rednet, gps, shell,
  -- multishell, os.shutdown, os.reboot. getfenv/setfenv would let an app reach
  -- the kernel's real globals through any function the kernel handed it.
  return env
end

M.SYSTEM_EVENTS = SYSTEM_EVENTS
return M
