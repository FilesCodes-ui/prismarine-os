--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/sys/perms.lua
-- Prismarine OS: remembered app permissions.
-- One entry per app file: its hash and what it may always (or never) do.
-- A changed app file loses its entry, so an update asks again.

local P = {}
local PATH = "/prismarine/secure/perms.dat"
local MAX = 100
local VALID_PERM = { web = true, redstone = true, devices = true, files = true, background = true }

local K, C
local db = {}
-- Background choices, one per program file: "keep" (never freeze it) or
-- "freeze" (always freeze it). No entry means Auto: the app may ask.
local BGPATH = "/prismarine/secure/background.dat"
local bg = {}

local function load()
  db = {}
  if not fs.exists(PATH) then return end
  local h = fs.open(PATH, "r")
  if not h then return end
  local ok, t = pcall(textutils.unserialize, h.readAll())
  h.close()
  if not ok or type(t) ~= "table" then return end
  for key, e in pairs(t) do
    if type(key) == "string" and type(e) == "table" and type(e.hash) == "string" then
      local g = {}
      if type(e.grants) == "table" then
        for perm, v in pairs(e.grants) do
          if VALID_PERM[perm] and (v == "always" or v == "never") then g[perm] = v end
        end
      end
      db[key] = { name = tostring(e.name or key):sub(1, 30), hash = e.hash, grants = g }
    end
  end
end

local function save()
  pcall(function()
    fs.makeDir(fs.getDir(PATH))
    local h = fs.open(PATH, "w")
    if h then h.write(textutils.serialize(db)) h.close() end
  end)
end

local function bgKey(path)
  local ok, r = pcall(fs.combine, "", tostring(path or ""))
  return (ok and r or tostring(path)):lower()
end

local function loadBg()
  bg = {}
  if not fs.exists(BGPATH) then return end
  local h = fs.open(BGPATH, "r")
  if not h then return end
  local ok, t = pcall(textutils.unserialize, h.readAll())
  h.close()
  if not ok or type(t) ~= "table" then return end
  local n = 0
  for key, v in pairs(t) do
    if type(key) == "string" and #key < 120 and (v == "keep" or v == "freeze") and n < 200 then
      bg[key] = v
      n = n + 1
    end
  end
end

local function saveBg()
  pcall(function()
    fs.makeDir(fs.getDir(BGPATH))
    local h = fs.open(BGPATH, "w")
    if h then h.write(textutils.serialize(bg)) h.close() end
  end)
end

function P.init(kernel, crypto)
  K, C = kernel, crypto
  load()
  loadBg()
end

-- "keep" | "freeze" | nil for a program path.
function P.bgGet(path) return bg[bgKey(path)] end

-- mode: "auto" | "keep" | "freeze". The key is a path as bgKey shows it.
function P.bgSet(path, mode)
  local key = bgKey(path)
  if mode == "auto" then
    bg[key] = nil
  elseif mode == "keep" or mode == "freeze" then
    local n = 0
    for _ in pairs(bg) do n = n + 1 end
    if bg[key] == nil and n >= 200 then return false end
    bg[key] = mode
  else
    return false
  end
  saveBg()
  return true
end
P.bgKey = bgKey

local function keyOf(p) return tostring(p.spec.path):lower() end

local function hashOf(p)
  if p.hashV == nil then
    local h = C.hashFile(p.spec.path)
    p.hashV = h or false
  end
  return p.hashV
end

local function count()
  local n = 0
  for _ in pairs(db) do n = n + 1 end
  return n
end

-- "always" | "never" | nil. A changed file forgets everything it was given.
function P.stored(p, perm)
  local e = db[keyOf(p)]
  if not e then return nil end
  local h = hashOf(p)
  if not h or e.hash ~= h then
    db[keyOf(p)] = nil
    save()
    return nil
  end
  return e.grants[perm]
end

-- Remember that an app asked, so Settings can list it even before an answer.
function P.seen(p, perm)
  local key = keyOf(p)
  local h = hashOf(p)
  if not h then return end
  local e = db[key]
  if e and e.hash ~= h then db[key] = nil e = nil end
  if not e then
    if count() >= MAX then return end
    db[key] = { name = tostring(p.name):sub(1, 30), hash = h, grants = {} }
    save()
  end
end

function P.save(p, perm, value)
  if not VALID_PERM[perm] or (value ~= "always" and value ~= "never") then return end
  P.seen(p, perm)
  local e = db[keyOf(p)]
  if e then
    e.grants[perm] = value
    save()
  end
end

-- For Settings: { { key, name, grants = {web="always"} }, ... } sorted by name.
function P.list()
  local out = {}
  for key, e in pairs(db) do
    local g = {}
    for perm, v in pairs(e.grants) do g[perm] = v end
    out[#out + 1] = { key = key, name = e.name, grants = g }
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- value: "ask" | "always" | "never"
function P.set(key, perm, value)
  local e = db[key]
  if not e or not VALID_PERM[perm] then return false end
  if value == "ask" then
    e.grants[perm] = nil
  elseif value == "always" or value == "never" then
    e.grants[perm] = value
  else
    return false
  end
  save()
  return true
end

function P.forget(key)
  if not db[key] then return false end
  db[key] = nil
  save()
  return true
end

return P
