--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Pearl: an AI companion for a computer, turtle, rail cart or train.
--@prismarine-api
-- prismarine: background touch pixelbox move
-- It studies the players around it, learns where they go, talks in chat,
-- remembers places and moves through the world when it has a body to do so.
-- ── Basics ───────────────────────────────────────────────────────────────────
local api = rawget(_G, "prismarine") or {}
local floor, ceil, min, max, abs, sqrt = math.floor, math.ceil, math.min, math.max, math.abs, math.sqrt
local sin, cos, pi = math.sin, math.cos, math.pi
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local unpack = table.unpack or unpack
local VERSION = "1.0"

local U = {}

function U.clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function U.round(v) return floor(v + 0.5) end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.int(v) return floor((tonumber(v) or 0) + 0.5) end

function U.copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = U.copy(v) end
  return c
end

function U.merge(base, over)
  for k, v in pairs(over) do
    if type(v) == "table" and type(base[k]) == "table" then U.merge(base[k], v)
    else base[k] = U.copy(v) end
  end
  return base
end

function U.count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function U.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- Keep only the n largest numeric values of a table (counts).
function U.prune(t, n)
  local c = U.count(t)
  if c <= n then return end
  local list = {}
  for k, v in pairs(t) do list[#list + 1] = { k, type(v) == "number" and v or 0 } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  for i = n + 1, #list do t[list[i][1]] = nil end
end

function U.top(t, n, score)
  local list = {}
  for k, v in pairs(t) do list[#list + 1] = { k = k, v = score and score(k, v) or v } end
  table.sort(list, function(a, b) if a.v == b.v then return tostring(a.k) < tostring(b.k) end return a.v > b.v end)
  local out = {}
  for i = 1, min(n, #list) do out[i] = list[i] end
  return out
end

function U.pick(list)
  if #list == 0 then return nil end
  return list[math.random(1, #list)]
end

-- Text that came from a player is never trusted: no control bytes, no chat
-- color codes, no leading "$" (hidden chat commands), and a hard length cap.
function U.clean(s, n)
  s = tostring(s or "")
  s = s:gsub("%c", " ")
  s = s:gsub("\194\167.", "")
  s = s:gsub("&[0-9a-fk-orA-FK-OR]", "")
  s = s:gsub("^%s*[%$/]+", "")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if n and #s > n then s = s:sub(1, n) end
  return s
end

function U.ago(sec)
  sec = max(0, sec or 0)
  if sec < 45 then return "just now" end
  if sec < 3600 then return floor(sec / 60 + 0.5) .. "m ago" end
  if sec < 86400 then return floor(sec / 3600 + 0.5) .. "h ago" end
  return floor(sec / 86400 + 0.5) .. "d ago"
end

function U.dur(sec)
  sec = max(0, sec or 0)
  if sec < 90 then return floor(sec) .. "s" end
  if sec < 5400 then return floor(sec / 60 + 0.5) .. "m" end
  if sec < 172800 then return string.format("%.1fh", sec / 3600) end
  return floor(sec / 86400 + 0.5) .. "d"
end

function U.d3(ax, ay, az, bx, by, bz)
  local dx, dy, dz = ax - bx, ay - by, az - bz
  return sqrt(dx * dx + dy * dy + dz * dz)
end
function U.d2(ax, az, bx, bz)
  local dx, dz = ax - bx, az - bz
  return sqrt(dx * dx + dz * dz)
end

-- 0 = north (-z), 90 = east (+x)
function U.bearing(dx, dz)
  local a = atan2(dx, -dz) * 180 / pi
  if a < 0 then a = a + 360 end
  return a
end
local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
function U.compass(deg) return COMPASS[floor(((deg % 360) + 22.5) / 45) % 8 + 1] end

function U.cell(x, z, size)
  return floor(x / size), floor(z / size)
end
function U.cellKey(dim, cx, cz) return tostring(dim or "?") .. ":" .. cx .. "," .. cz end
function U.parseCell(key)
  local d, cx, cz = tostring(key):match("^(.-):(-?%d+),(-?%d+)$")
  if not d then return nil end
  return d, tonumber(cx), tonumber(cz)
end

local STOP = {}
for w in ([[the a an and or but if then so of to in on at for with from by is are was were be been am
i you he she it we they me my your our their this that these those there here not no yes do does did
have has had will would can could should just like get got go going what when where who why how pearl
hi hello hey ok okay lol please thanks thank can't dont don't im i'm its it's u ur]]):gmatch("%S+") do STOP[w] = true end
U.STOP = STOP

function U.words(s)
  local out = {}
  for w in tostring(s):lower():gmatch("[%a][%a']+") do out[#out + 1] = w end
  return out
end

function U.title(s)
  return (tostring(s):gsub("^%l", string.upper))
end

-- A small seeded generator so a phrase choice can stay stable for a while.
function U.hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

function U.hour()
  local ok, h = pcall(os.time, "ingame")
  if ok and type(h) == "number" then return h end
  return 12
end
function U.isNight() local h = U.hour() return h >= 19 or h < 5.5 end
function U.clock24()
  local h = U.hour()
  return string.format("%02d:%02d", floor(h) % 24, floor((h % 1) * 60))
end
function U.epoch() return os.epoch("utc") / 1000 end

-- ── Saving ───────────────────────────────────────────────────────────────────
local Store = { dir = api.home or "/appdata/pearl", dirty = {}, lastSave = 0 }

local function spath(n) return fs.combine(Store.dir, n .. ".dat") end

function Store.read(n, default)
  local p = spath(n)
  if not fs.exists(p) then return default end
  local h = fs.open(p, "r")
  if not h then return default end
  local s = h.readAll()
  h.close()
  local ok, t = pcall(textutils.unserialize, s)
  if ok and type(t) == "table" then return t end
  return default
end

local function strip(t, seen)
  local c = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "table" then c[k] = strip(v) elseif tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then c[k] = v end
  end
  return c
end

function Store.write(n, t)
  t = strip(t)
  pcall(fs.makeDir, Store.dir)
  local ok, s = pcall(textutils.serialize, t, { compact = true })
  if not ok or type(s) ~= "string" then
    ok, s = pcall(textutils.serialize, t)
    if not ok then return false end
  end
  local p = spath(n)
  local tmp = p .. ".tmp"
  local h = fs.open(tmp, "w")
  if not h then return false end
  h.write(s)
  h.close()
  if fs.exists(p) then pcall(fs.delete, p) end
  return pcall(fs.move, tmp, p)
end

function Store.mark(n) Store.dirty[n] = true end

-- Called often; writes at most every `every` seconds unless forced.
function Store.flush(tables, force, every)
  local t = os.clock()
  if not force and t - Store.lastSave < (every or 45) then return end
  Store.lastSave = t
  for n in pairs(Store.dirty) do
    if tables[n] then Store.write(n, tables[n]) end
    Store.dirty[n] = nil
  end
end

-- ── Settings ─────────────────────────────────────────────────────────────────
local DEFAULTS = {
  name = "Pearl",
  owner = "",            -- the one player who may see exact coordinates in chat
  study = true,          -- learn about players
  talk = true,           -- answer in game chat
  learnChat = true,      -- learn words and replies players teach
  sound = true,
  mirror = true,         -- draw the face on a monitor
  moveOn = true,         -- allowed to move at all
  leash = 24,            -- never farther than this from home
  pos = nil,             -- { x, y, z } where the computer or its detector stands
  home = nil,            -- { x, y, z }
  facing = "N",          -- N E S W: which way a turtle faces at start
  dim = "minecraft:overworld",
  reflex = { door = "", lamp = "", doorFor = "friends" },
  axis = { a = nil, b = nil, bps = 1.0, rpm = 32 },
  stations = {},         -- name -> { x, y, z }
  cortex = { on = false, fmt = "anthropic", url = "https://api.anthropic.com/v1/messages",
             model = "claude-haiku-5-5", key = "" },
  optout = {},
  anim = { yaw = 0, wave = { 0, 0, 150 }, rest = { 0, 0, 0 } },
}

local Cfg = U.merge(U.copy(DEFAULTS), Store.read("config", {}))
if type(Cfg.optout) ~= "table" then Cfg.optout = {} end
function Cfg.save() Store.mark("config") end

-- ── Devices ──────────────────────────────────────────────────────────────────
-- Finds what is attached by type name and keeps one wrapped copy of each. Every
-- call is protected, so a missing method or a refused permission never crashes
-- the mind; it is noted and the feature simply goes quiet.
local HW = { names = {}, proxy = {}, methods = {}, denied = false, lastErr = nil, scanAt = -99, errors = 0 }

local ROLES = {
  players = { "playerdetector", "player_detector" },
  chat    = { "chatbox", "chat_box" },
  geo     = { "geoscanner", "geo_scanner" },
  env     = { "environmentdetector", "environment_detector" },
  speaker = { "speaker" },
  monitor = { "monitor" },
  anim    = { "animatronic" },
  rsc     = { "create_rotationspeedcontroller" },
  gear    = { "create_sequencedgearshift" },
  station = { "create_station" },
}

function HW.scan()
  local found = {}
  for role in pairs(ROLES) do found[role] = {} end
  local ok, names = pcall(peripheral.getNames)
  if not ok then names = {} end
  for _, n in ipairs(names) do
    local okT, types = pcall(function() return { peripheral.getType(n) } end)
    if okT then
      for _, t in ipairs(types) do
        local tl = tostring(t):lower()
        for role, list in pairs(ROLES) do
          for _, pat in ipairs(list) do
            if tl == pat then
              local dup = false
              for _, x in ipairs(found[role]) do if x == n then dup = true end end
              if not dup then found[role][#found[role] + 1] = n end
            end
          end
        end
      end
    end
  end
  for role in pairs(found) do table.sort(found[role]) end
  -- forget wrapped copies of devices that are gone
  local alive = {}
  for _, list in pairs(found) do for _, n in ipairs(list) do alive[n] = true end end
  for n in pairs(HW.proxy) do if not alive[n] then HW.proxy[n] = nil HW.methods[n] = nil end end
  HW.names = found
  HW.scanAt = os.clock()
end

function HW.count(role) return HW.names[role] and #HW.names[role] or 0 end
function HW.has(role) return HW.count(role) > 0 end
function HW.first(role) return HW.names[role] and HW.names[role][1] end

local function wrap(n)
  local p = HW.proxy[n]
  if p then return p end
  local ok, w = pcall(peripheral.wrap, n)
  if ok and w then HW.proxy[n] = w return w end
  return nil
end

function HW.can(n, method)
  local m = HW.methods[n]
  if not m then
    m = {}
    local ok, list = pcall(peripheral.getMethods, n)
    if ok and type(list) == "table" then for _, x in ipairs(list) do m[x] = true end end
    HW.methods[n] = m
  end
  return m[method] == true
end

function HW.on(n, method, ...)
  local p = wrap(n)
  if not p then return nil, "gone" end
  local f = p[method]
  if type(f) ~= "function" then return nil, "nomethod" end
  local r = table.pack(pcall(f, ...))
  if not r[1] then
    local e = tostring(r[2])
    HW.errors = HW.errors + 1
    HW.lastErr = e
    if e:find("Not allowed", 1, true) then HW.denied = true end
    return nil, e
  end
  return unpack(r, 2, r.n)
end

function HW.call(role, method, ...)
  local n = HW.first(role)
  if not n then return nil, "missing" end
  return HW.on(n, method, ...)
end

function HW.canCall(role, method)
  local n = HW.first(role)
  return n ~= nil and HW.can(n, method)
end

function HW.monitor()
  local n = HW.first("monitor")
  return n and wrap(n) or nil, n
end

-- One line for the Setup page.
function HW.summary()
  local parts = {}
  local function add(role, label)
    local c = HW.count(role)
    if c > 0 then parts[#parts + 1] = label .. (c > 1 and ("x" .. c) or "") end
  end
  add("players", "detector") add("chat", "chat") add("geo", "scanner") add("env", "env")
  add("speaker", "speaker") add("monitor", "monitor") add("anim", "animatronic")
  add("rsc", "speed ctl") add("gear", "gearshift") add("station", "station")
  return #parts > 0 and table.concat(parts, ", ") or "nothing attached"
end

-- ── Events between parts ─────────────────────────────────────────────────────
local Bus = { h = {} }
function Bus.on(k, f) Bus.h[k] = Bus.h[k] or {}; table.insert(Bus.h[k], f) end
function Bus.emit(k, ...)
  for _, f in ipairs(Bus.h[k] or {}) do pcall(f, ...) end
end

-- ── Memory: players and the world ────────────────────────────────────────────
-- Everything Pearl knows is a plain table saved to its own folder. Players can
-- say "forget me" or "don't track me" and their profile is erased.
local Mem = { people = Store.read("people", {}), world = Store.read("world", {}), live = {}, CELL = 16 }
local MW = Mem.world
MW.places = MW.places or {}
MW.explored = MW.explored or {}
MW.poi = MW.poi or {}
MW.lex = MW.lex or {}
MW.cellY = MW.cellY or {}
MW.stats = MW.stats or { created = U.epoch(), met = 0, msgs = 0, taught = 0, cells = 0, said = 0 }
MW.journalDay = MW.journalDay or -1

local MAX_PEOPLE, MAX_CELLS, MAX_WORDS, MAX_POI, MAX_EXPLORED = 60, 120, 60, 160, 2200

local function newPerson(t)
  local h, r = {}, {}
  for i = 1, 24 do h[i] = 0 r[i] = 0 end
  return { first = t, last = t, sessions = 0, secs = 0, near = 0, dist = 0, speed = 0,
    cells = {}, trans = {}, hours = h, rhours = r, chats = 0, clicks = 0, words = {}, lines = {},
    aff = 0.5, pairs = {}, greeted = 0, joins = 0, minY = nil, maxY = nil, dims = {} }
end

function Mem.person(name, create)
  local p = Mem.people[name]
  if not p and create then
    if U.count(Mem.people) >= MAX_PEOPLE then
      -- make room: drop the person seen longest ago who never interacted
      local worst, wt = nil, math.huge
      for n, q in pairs(Mem.people) do
        if q.last < wt and q.chats == 0 and q.clicks == 0 then worst, wt = n, q.last end
      end
      if not worst then return nil end
      Mem.people[worst] = nil
    end
    p = newPerson(U.epoch())
    Mem.people[name] = p
    MW.stats.met = MW.stats.met + 1
    Bus.emit("met", name)
    Store.mark("people") Store.mark("world")
  end
  return p
end

function Mem.forget(name)
  Mem.people[name] = nil
  Mem.live[name] = nil
  for _, q in pairs(Mem.people) do if q.pairs then q.pairs[name] = nil end end
  Store.mark("people")
end

function Mem.optOut(name, on)
  if on then Cfg.optout[name] = true Mem.forget(name) else Cfg.optout[name] = nil end
  Cfg.save()
end

function Mem.bump(name, delta)
  local p = Mem.people[name]
  if p then p.aff = U.clamp(p.aff + delta, 0, 1) Store.mark("people") end
end

-- ── Studying a player ────────────────────────────────────────────────────────
-- o = { x, y, z, dim, health, yaw }   dt = seconds since the last look
function Mem.observe(name, o, dt, me)
  if not Cfg.study or Cfg.optout[name] then return end
  local p = Mem.person(name, true)
  if not p then return end
  dt = U.clamp(dt or 0, 0, 8)
  local t = U.epoch()
  local lv = Mem.live[name]

  if not lv then
    -- first look in this stretch: a new session if they were gone for a while
    if t - p.last > 300 or p.sessions == 0 then
      p.sessions = p.sessions + 1
      p.joins = p.joins + 1
    end
    Bus.emit("appear", name, p)
  end

  p.last = t
  p.secs = p.secs + dt
  local hour = floor(U.hour()) % 24 + 1
  p.hours[hour] = p.hours[hour] + dt
  local rh = tonumber(os.date("%H")) or 0
  p.rhours[rh + 1] = (p.rhours[rh + 1] or 0) + dt
  p.dims[o.dim or "?"] = (p.dims[o.dim or "?"] or 0) + dt

  if o.y then
    p.minY = p.minY and min(p.minY, o.y) or o.y
    p.maxY = p.maxY and max(p.maxY, o.y) or o.y
  end

  -- movement
  if lv and lv.dim == o.dim and dt > 0 then
    local d = U.d3(o.x, o.y, o.z, lv.x, lv.y, lv.z)
    if d < 90 then
      p.dist = p.dist + d
      local sp = d / max(dt, 0.2)
      p.speed = p.speed == 0 and sp or (p.speed * 0.97 + sp * 0.03)
    end
  end

  -- where they spend time, and where they go next
  local cx, cz = U.cell(o.x, o.z, Mem.CELL)
  local key = U.cellKey(o.dim, cx, cz)
  p.cells[key] = U.round(((p.cells[key] or 0) + dt) * 10) / 10
  MW.cellY[key] = MW.cellY[key] and (MW.cellY[key] * 0.9 + o.y * 0.1) or o.y
  if p.lastCell and p.lastCell ~= key then
    local tr = p.trans[p.lastCell]
    if not tr then tr = {} p.trans[p.lastCell] = tr end
    tr[key] = (tr[key] or 0) + 1
    if U.count(tr) > 6 then U.prune(tr, 5) end
  end
  p.lastCell = key
  if U.count(p.cells) > MAX_CELLS then
    U.prune(p.cells, MAX_CELLS - 25)
    for k in pairs(p.trans) do if not p.cells[k] then p.trans[k] = nil end end
  end

  -- how close to me
  local dme = nil
  if me and me.x and (not o.dim or not me.dim or o.dim == me.dim) then
    dme = U.d3(o.x, o.y, o.z, me.x, me.y, me.z)
    if dme < 12 then p.near = p.near + dt end
  end

  local prevD = lv and lv.d
  Mem.live[name] = { x = o.x, y = o.y, z = o.z, dim = o.dim, yaw = o.yaw, pitch = o.pitch, health = o.health,
    maxHealth = o.maxHealth, t = os.clock(), d = dme, lastD = prevD, cell = key,
    first = lv and lv.first or os.clock() }
  if prevD and dme then
    if prevD > 6 and dme <= 4.5 and not (lv and lv.near) then
      Mem.live[name].near = true
      Bus.emit("approach", name, dme)
    elseif dme > 4.5 and prevD > 4.5 then
      Mem.live[name].near = false
    else
      Mem.live[name].near = lv and lv.near
    end
    if prevD < 9 and dme > 18 then Bus.emit("leave", name, dme) end
  end
  Store.mark("people")
end

-- After a round of looks: who is gone, who is together.
function Mem.sweep(dt)
  local clk = os.clock()
  for name, lv in pairs(Mem.live) do
    if clk - lv.t > 12 then
      Mem.live[name] = nil
      Bus.emit("gone", name)
    end
  end
  if not Cfg.study then return end
  local names = U.keys(Mem.live)
  for i = 1, #names do
    for j = i + 1, #names do
      local a, b = Mem.live[names[i]], Mem.live[names[j]]
      if a.dim == b.dim and U.d3(a.x, a.y, a.z, b.x, b.y, b.z) < 12 then
        local pa, pb = Mem.people[names[i]], Mem.people[names[j]]
        if pa and pb then
          pa.pairs[names[j]] = (pa.pairs[names[j]] or 0) + dt
          pb.pairs[names[i]] = (pb.pairs[names[i]] or 0) + dt
        end
      end
    end
  end
end

-- ── What was said ────────────────────────────────────────────────────────────
function Mem.hear(name, text, toMe)
  if Cfg.optout[name] then return end
  MW.stats.msgs = MW.stats.msgs + 1
  if not Cfg.study then return end
  local p = Mem.person(name, true)
  if not p then return end
  p.chats = p.chats + 1
  if toMe then Mem.bump(name, 0.03) end
  if Cfg.learnChat then
    for _, w in ipairs(U.words(text)) do
      if #w >= 4 and not U.STOP[w] then p.words[w] = (p.words[w] or 0) + 1 end
    end
    if U.count(p.words) > MAX_WORDS then U.prune(p.words, MAX_WORDS - 15) end
    p.lines[#p.lines + 1] = U.clean(text, 80)
    while #p.lines > 10 do table.remove(p.lines, 1) end
  end
  Store.mark("people")
end

-- ── Reading a person ─────────────────────────────────────────────────────────
function Mem.place(x, z, dim)
  local best, bd = nil, 24
  for n, pl in pairs(MW.places) do
    if (not dim or not pl.dim or pl.dim == dim) then
      local d = U.d2(x, z, pl.x, pl.z)
      if d < bd then best, bd = n, d end
    end
  end
  return best
end

function Mem.cellCenter(key)
  local d, cx, cz = U.parseCell(key)
  if not d then return nil end
  local x, z = cx * Mem.CELL + Mem.CELL / 2, cz * Mem.CELL + Mem.CELL / 2
  return { x = x, z = z, y = MW.cellY[key], dim = d }
end

function Mem.favorite(name)
  local p = Mem.people[name]
  if not p then return nil end
  local top = U.top(p.cells, 1)
  if not top[1] then return nil end
  local c = Mem.cellCenter(top[1].k)
  if not c then return nil end
  c.secs = top[1].v
  c.name = Mem.place(c.x, c.z, c.dim)
  return c
end

-- Where is this person likely to be next? The cell they most often went to
-- from the one they are in now.
function Mem.predict(name)
  local p, lv = Mem.people[name], Mem.live[name]
  if not p or not lv or not lv.cell then return nil end
  local tr = p.trans[lv.cell]
  if not tr then return nil end
  local best = U.top(tr, 1)[1]
  if not best then return nil end
  local c = Mem.cellCenter(best.k)
  if c then c.p = best.v / max(1, (function() local s = 0 for _, v in pairs(tr) do s = s + v end return s end)()) end
  return c
end

function Mem.hourWeight(p, h)
  local mx = 0
  for i = 1, 24 do mx = max(mx, p.hours[i] or 0) end
  if mx <= 0 then return 0.5 end
  return (p.hours[h] or 0) / mx
end

-- The busiest cells right now, using each person's usual hours.
function Mem.hotspots(n, hour)
  local acc = {}
  local h = hour and (floor(hour) % 24 + 1) or nil
  for _, p in pairs(Mem.people) do
    local w = h and (0.3 + 0.7 * Mem.hourWeight(p, h)) or 1
    for key, c in pairs(p.cells) do acc[key] = (acc[key] or 0) + c * w end
  end
  local out = {}
  for i, e in ipairs(U.top(acc, n)) do
    local c = Mem.cellCenter(e.k)
    if c then c.key, c.score, c.name = e.k, e.v, Mem.place(c.x, c.z, c.dim) out[#out + 1] = c end
  end
  return out
end

local function peakHours(p)
  local best, bi = 0, nil
  for i = 1, 24 do if (p.hours[i] or 0) > best then best, bi = p.hours[i], i end end
  return bi and (bi - 1) or nil
end

function Mem.tags(name)
  local p = Mem.people[name]
  local out = {}
  if not p or p.secs < 60 then return out end
  local cells = U.count(p.cells)
  local tot, top = 0, 0
  for _, v in pairs(p.cells) do tot = tot + v if v > top then top = v end end
  if cells >= 35 or (p.secs > 600 and p.dist / p.secs > 2.2) then out[#out + 1] = "explorer"
  elseif tot > 0 and top / tot > 0.5 then out[#out + 1] = "homebody" end
  local night, day, all = 0, 0, 0
  for i = 1, 24 do
    local v = p.hours[i] or 0
    all = all + v
    if i >= 20 or i <= 5 then night = night + v elseif i >= 6 and i <= 11 then day = day + v end
  end
  if all > 300 then
    if night / all > 0.55 then out[#out + 1] = "night owl" elseif day / all > 0.5 then out[#out + 1] = "early bird" end
  end
  if p.speed > 5.2 then out[#out + 1] = "always sprinting" end
  if p.chats >= 8 and p.chats / max(1, p.secs / 3600) > 25 then out[#out + 1] = "chatty" end
  if p.near > 120 and p.near / max(1, p.secs) > 0.3 then out[#out + 1] = "sticks close" end
  if p.maxY and p.minY and p.minY < 20 and p.secs > 300 then out[#out + 1] = "miner" end
  while #out > 3 do table.remove(out) end
  return out
end

function Mem.topWords(name, n)
  local p = Mem.people[name]
  if not p then return {} end
  local out = {}
  for i, e in ipairs(U.top(p.words, n or 3)) do out[i] = e.k end
  return out
end

function Mem.bestFriend(name)
  local p = Mem.people[name]
  if not p then return nil end
  local e = U.top(p.pairs, 1)[1]
  if e and e.v > 120 then return e.k, e.v end
  return nil
end

-- ── The world ────────────────────────────────────────────────────────────────
function Mem.mark(x, y, z)
  local cx, cz = U.cell(x, z, 4)
  local key = cx .. "," .. cz
  local new = MW.explored[key] == nil
  MW.explored[key] = (MW.explored[key] or 0) + 1
  if new then
    MW.stats.cells = MW.stats.cells + 1
    if U.count(MW.explored) > MAX_EXPLORED then U.prune(MW.explored, MAX_EXPLORED - 300) end
    Store.mark("world")
  end
  return new
end

function Mem.seen(x, z)
  local cx, cz = U.cell(x, z, 4)
  return MW.explored[cx .. "," .. cz] ~= nil
end

local KINDS = {
  { "hazard", { "lava", "magma_block", "cactus", "campfire", "fire" } },
  { "storage", { "chest", "barrel", "shulker_box" } },
  { "workstation", { "crafting_table", "furnace", "smoker", "smithing_table", "anvil", "enchanting_table",
      "brewing_stand", "loom", "grindstone", "stonecutter", "cartography_table" } },
  { "bed", { "_bed" } },
  { "ore", { "_ore" } },
  { "special", { "spawner", "beacon", "end_portal", "nether_portal", "ender_chest" } },
}
function Mem.classify(name)
  name = tostring(name or ""):lower()
  for _, k in ipairs(KINDS) do
    for _, pat in ipairs(k[2]) do
      if name:find(pat, 1, true) then
        if k[1] == "hazard" and pat == "fire" and not (name:match(":fire$") or name:match("soul_fire$")) then
          -- "fire" would also match "fire_coral"; only real fire is a hazard
        else
          return k[1]
        end
      end
    end
  end
  return nil
end

-- blocks = list of { name, x, y, z } relative to the scanner at (ox, oy, oz)
function Mem.scan(blocks, ox, oy, oz)
  local found, fresh = 0, 0
  for _, b in ipairs(blocks or {}) do
    if type(b) == "table" and b.name then
      local kind = Mem.classify(b.name)
      if kind then
        found = found + 1
        local x, y, z = floor(ox + (b.x or 0)), floor(oy + (b.y or 0)), floor(oz + (b.z or 0))
        local key = kind .. ":" .. x .. "," .. y .. "," .. z
        if not MW.poi[key] then
          fresh = fresh + 1
          MW.poi[key] = { k = kind, n = tostring(b.name):gsub("^[%w_]+:", ""), x = x, y = y, z = z, t = U.epoch() }
        else
          MW.poi[key].t = U.epoch()
        end
      end
    end
  end
  if fresh > 0 then
    if U.count(MW.poi) > MAX_POI then
      local list = {}
      for k, v in pairs(MW.poi) do list[#list + 1] = { k, v.t } end
      table.sort(list, function(a, b) return a[2] < b[2] end)
      for i = 1, #list - (MAX_POI - 20) do MW.poi[list[i][1]] = nil end
    end
    Store.mark("world")
  end
  return found, fresh
end

function Mem.hazardNear(x, y, z, r)
  r = r or 2
  for _, p in pairs(MW.poi) do
    if p.k == "hazard" and abs(p.x - x) <= r and abs(p.y - y) <= r and abs(p.z - z) <= r then return true end
  end
  return false
end

function Mem.poiCounts()
  local c = {}
  for _, p in pairs(MW.poi) do c[p.k] = (c[p.k] or 0) + 1 end
  return c
end

function Mem.setPlace(name, x, y, z, dim, by)
  name = U.clean(name, 20):lower()
  if name == "" then return false end
  if not MW.places[name] and U.count(MW.places) >= 40 then return false end
  MW.places[name] = { x = floor(x), y = floor(y), z = floor(z), dim = dim, by = by, t = U.epoch() }
  Store.mark("world")
  return true
end

function Mem.findPlace(text)
  text = tostring(text or ""):lower()
  local best, bl = nil, 0
  for n in pairs(MW.places) do
    if text:find(n, 1, true) and #n > bl then best, bl = n, #n end
  end
  return best
end

-- Things taught in chat: "learn: when I say X you say Y"
function Mem.teach(by, trig, reply)
  trig, reply = U.clean(trig, 40):lower(), U.clean(reply, 120)
  if #trig < 3 or #reply < 1 then return false, "too short" end
  local mine = 0
  for _, e in ipairs(MW.lex) do
    if e.t == trig then e.r, e.by = reply, by Store.mark("world") return true end
    if e.by == by then mine = mine + 1 end
  end
  if mine >= 10 then return false, "you taught me plenty already" end
  if #MW.lex >= 50 then table.remove(MW.lex, 1) end
  MW.lex[#MW.lex + 1] = { t = trig, r = reply, by = by }
  MW.stats.taught = MW.stats.taught + 1
  Store.mark("world")
  return true
end

function Mem.lookup(text)
  text = " " .. tostring(text):lower():gsub("[^%w%s']", " "):gsub("%s+", " ") .. " "
  local best, bl = nil, 0
  for _, e in ipairs(MW.lex) do
    if text:find(e.t, 1, true) and #e.t > bl then best, bl = e, #e.t end
  end
  return best
end

-- ── Body ─────────────────────────────────────────────────────────────────────
-- Pearl can live in one of four bodies. All of them answer the same questions
-- (where am I, can I move, go there) so the mind does not care which it has.
--   turtle  this computer is a turtle and moves itself (needs the OS "move" permission)
--   axis    a Create cart or rover on a straight rail, driven by a Sequenced
--           Gearshift or Rotation Speed Controllers
--   train   a Create train that travels between named stations
--   fixed   a computer that stays put: it still sees, talks, learns and emotes
local MV = api.move
local Body = { kind = "fixed", x = nil, y = nil, z = nil, h = 0, target = nil, blocked = {}, H = {},
  steps = 0, bumps = 0, err = nil, t = 0.5, status = "idle", moved = 0 }

local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local FACE = { N = 0, E = 1, S = 2, W = 3 }
local FACEN = { [0] = "N", "E", "S", "W" }

local function ck(x, y, z) return x .. "," .. y .. "," .. z end
local function manh(x, y, z, t) return abs(x - t.x) + abs(y - t.y) + abs(z - t.z) end

function Body.home()
  if Cfg.home then return Cfg.home end
  if Cfg.pos then return Cfg.pos end
  if Body.x then return { x = Body.x, y = Body.y, z = Body.z } end
  return nil
end

-- ── Choosing a body ──────────────────────────────────────────────────────────
function Body.available()
  local list = { "fixed" }
  if MV and MV.available then list[#list + 1] = "turtle" end
  if (HW.has("gear") or HW.has("rsc")) then list[#list + 1] = "axis" end
  if HW.has("station") then list[#list + 1] = "train" end
  return list
end

function Body.choose()
  local pref = Cfg.body or "auto"
  local av = {}
  for _, k in ipairs(Body.available()) do av[k] = true end
  local kind = "fixed"
  if pref ~= "auto" and av[pref] then kind = pref
  elseif av.turtle then kind = "turtle"
  elseif av.axis and Cfg.axis.a and Cfg.axis.b then kind = "axis"
  elseif av.train then kind = "train" end
  Body.kind = kind
  return kind
end

function Body.saveState()
  Store.write("body", { x = Body.x, y = Body.y, z = Body.z, h = Body.h, t = Body.t, st = Body.stationName })
end

function Body.setPos(x, y, z, facing)
  Cfg.pos = { x = floor(x), y = floor(y), z = floor(z) }
  if facing and FACE[facing] then Cfg.facing = facing Body.h = FACE[facing] end
  if Body.kind == "turtle" then Body.x, Body.y, Body.z = Cfg.pos.x, Cfg.pos.y, Cfg.pos.z end
  if not Cfg.home then Cfg.home = { x = Cfg.pos.x, y = Cfg.pos.y, z = Cfg.pos.z } end
  Body.H, Body.blocked = {}, {}
  Cfg.save()
  Body.saveState()
end

function Body.init()
  HW.scan()
  Body.choose()
  local saved = Store.read("body", {})
  if Body.kind == "turtle" then
    local gx, gy, gz
    if MV and MV.locate then
      local ok, a, b, c = pcall(MV.locate)
      if ok and type(a) == "number" then gx, gy, gz = floor(a), floor(b), floor(c) end
    end
    Body.h = FACE[Cfg.facing] or 0
    if gx then Body.x, Body.y, Body.z = gx, gy, gz
    elseif saved.x then Body.x, Body.y, Body.z, Body.h = saved.x, saved.y, saved.z, saved.h or Body.h
    elseif Cfg.pos then Body.x, Body.y, Body.z = Cfg.pos.x, Cfg.pos.y, Cfg.pos.z end
  elseif Body.kind == "axis" then
    Body.t = saved.t or 0.5
  elseif Body.kind == "train" then
    Body.stationName = saved.st
  end
end

-- ── Where am I ───────────────────────────────────────────────────────────────
local P = { x = 0, y = 0, z = 0, dim = Cfg.dim }
function Body.pos()
  local k = Body.kind
  if k == "turtle" and Body.x then P.x, P.y, P.z = Body.x, Body.y, Body.z return P end
  if k == "axis" and Cfg.axis.a and Cfg.axis.b then
    local a, b = Cfg.axis.a, Cfg.axis.b
    P.x, P.y, P.z = a.x + (b.x - a.x) * Body.t, a.y + (b.y - a.y) * Body.t, a.z + (b.z - a.z) * Body.t
    return P
  end
  if k == "train" and Body.stationName then
    local s = Cfg.stations[Body.stationName]
    if s then P.x, P.y, P.z = s.x, s.y, s.z return P end
  end
  if Cfg.pos then P.x, P.y, P.z = Cfg.pos.x, Cfg.pos.y, Cfg.pos.z return P end
  return nil
end

function Body.canMove()
  if not Cfg.moveOn then return false end
  local k = Body.kind
  if k == "turtle" then return Body.x ~= nil end
  if k == "axis" then return Cfg.axis.a ~= nil and Cfg.axis.b ~= nil end
  if k == "train" then return true end
  return false
end

function Body.fuel()
  if Body.kind ~= "turtle" or not MV then return nil end
  local ok, f = pcall(MV.getFuelLevel)
  if not ok then return nil end
  if f == "unlimited" then return math.huge end
  return tonumber(f)
end

-- 0..1, nil when the body has no fuel idea
function Body.fuelFrac()
  local f = Body.fuel()
  if f == nil then return nil end
  if f == math.huge then return 1 end
  return U.clamp(f / 200, 0, 1)
end

function Body.refuel()
  if Body.kind ~= "turtle" or not MV then return false end
  local did = false
  for slot = 1, 16 do
    local okC, n = pcall(MV.getItemCount, slot)
    if okC and n and n > 0 then
      pcall(MV.select, slot)
      local okR, can = pcall(MV.refuel, 0)
      if okR and can then
        pcall(MV.refuel, 1)
        did = true
        local f = Body.fuel()
        if f and f > 400 then break end
      end
    end
  end
  pcall(MV.select, 1)
  return did
end

function Body.describe()
  local k = Body.kind
  if k == "turtle" then
    local f = Body.fuel()
    local fs = f == nil and "" or (f == math.huge and " fuel inf" or (" fuel " .. floor(f)))
    return "Turtle" .. fs
  elseif k == "axis" then
    return "Rail body " .. floor(Body.t * 100) .. "%"
  elseif k == "train" then
    return "Train" .. (Body.stationName and (" at " .. Body.stationName) or "")
  end
  return "Fixed"
end

-- ── Turtle ───────────────────────────────────────────────────────────────────
local Turtle = {}

local function blockedNow(k)
  local v = Body.blocked[k]
  if v == true then return true end
  if type(v) == "number" then
    if v > os.clock() then return true end
    Body.blocked[k] = nil
  end
  return false
end

function Turtle.allowed(nx, ny, nz)
  local home = Body.home()
  if home then
    if U.d2(nx, nz, home.x, home.z) > Cfg.leash then return false end
    if abs(ny - home.y) > 14 then return false end
  end
  if Mem.hazardNear(nx, ny, nz, 1) then return false end
  return true
end

function Turtle.face(want)
  local diff = (want - Body.h) % 4
  if diff == 0 then return end
  if diff == 1 then
    if MV.turnRight() then Body.h = (Body.h + 1) % 4 end
  elseif diff == 3 then
    if MV.turnLeft() then Body.h = (Body.h + 3) % 4 end
  else
    if MV.turnRight() then Body.h = (Body.h + 1) % 4 end
    if MV.turnRight() then Body.h = (Body.h + 1) % 4 end
  end
end

local function dangerous(ok, data)
  return ok and type(data) == "table" and Mem.classify(data.name) == "hazard"
end

local function landed(nx, ny, nz)
  Body.x, Body.y, Body.z = nx, ny, nz
  Body.steps = Body.steps + 1
  Body.moved = Body.moved + 1
  if Mem.mark(nx, ny, nz) then Bus.emit("newcell", nx, ny, nz) end
  if Body.steps % 6 == 0 then Body.saveState() end
end

function Turtle.go(i)
  local nx, ny, nz = Body.x, Body.y, Body.z
  local ok, data, moved
  if i <= 4 then
    local want = i - 1
    nx, nz = Body.x + DX[want], Body.z + DZ[want]
    local k = ck(nx, ny, nz)
    Turtle.face(want)
    ok, data = MV.inspect()
    if dangerous(ok, data) then Body.blocked[k] = true Body.bumps = Body.bumps + 1 return "moving" end
    moved = MV.forward()
    if moved then landed(nx, ny, nz) return "moving" end
    if MV.detect() then Body.blocked[k] = true else Body.blocked[k] = os.clock() + 6 end
  elseif i == 5 then
    ny = Body.y + 1
    local k = ck(nx, ny, nz)
    ok, data = MV.inspectUp()
    if dangerous(ok, data) then Body.blocked[k] = true return "moving" end
    moved = MV.up()
    if moved then landed(nx, ny, nz) return "moving" end
    if MV.detectUp() then Body.blocked[k] = true else Body.blocked[k] = os.clock() + 6 end
  else
    ny = Body.y - 1
    local k = ck(nx, ny, nz)
    ok, data = MV.inspectDown()
    if dangerous(ok, data) then Body.blocked[k] = true return "moving" end
    moved = MV.down()
    if moved then landed(nx, ny, nz) return "moving" end
    if MV.detectDown() then Body.blocked[k] = true else Body.blocked[k] = os.clock() + 6 end
  end
  Body.bumps = Body.bumps + 1
  return "moving"
end

-- Learning Real-Time A*: step to the neighbor with the lowest (1 + learned cost),
-- and raise the learned cost of the cell just left. Walls found by bumping are
-- remembered, so the second trip past an obstacle is straighter than the first.
function Turtle.step(t)
  if not Body.x then return "nopos" end
  local f = Body.fuel()
  if f ~= nil and f <= 0 then
    Body.refuel()
    f = Body.fuel()
    if f ~= nil and f <= 0 then return "nofuel" end
  end
  local dx, dy, dz = t.x - Body.x, t.y - Body.y, t.z - Body.z
  if abs(dx) <= t.r and abs(dz) <= t.r and abs(dy) <= max(t.r, 2) then return "arrived" end

  local here = ck(Body.x, Body.y, Body.z)
  local hHere = Body.H[here] or manh(Body.x, Body.y, Body.z, t)
  local best, bf = nil, math.huge
  for i = 1, 6 do
    local nx, ny, nz = Body.x, Body.y, Body.z
    if i <= 4 then nx, nz = nx + DX[i - 1], nz + DZ[i - 1]
    elseif i == 5 then ny = ny + 1 else ny = ny - 1 end
    local k = ck(nx, ny, nz)
    if not blockedNow(k) and Turtle.allowed(nx, ny, nz) then
      local c = 1 + (Body.H[k] or manh(nx, ny, nz, t))
      if i <= 4 and (i - 1) == Body.h then c = c - 0.01 end
      if i > 4 then c = c + 0.02 end
      if c < bf then best, bf = i, c end
    end
  end
  if not best then Body.fails = (Body.fails or 0) + 1 return "blocked" end
  Body.H[here] = max(hHere, bf)
  Turtle.go(best)
  return "moving"
end

-- ── Axis (rail cart or rover) ────────────────────────────────────────────────
local Axis = {}

function Axis.length()
  local a, b = Cfg.axis.a, Cfg.axis.b
  if not a or not b then return 0 end
  return U.d3(a.x, a.y, a.z, b.x, b.y, b.z)
end

function Axis.project(x, y, z)
  local a, b = Cfg.axis.a, Cfg.axis.b
  local vx, vy, vz = b.x - a.x, b.y - a.y, b.z - a.z
  local l2 = vx * vx + vy * vy + vz * vz
  if l2 <= 0 then return 0 end
  return U.clamp(((x - a.x) * vx + (y - a.y) * vy + (z - a.z) * vz) / l2, 0, 1)
end

function Axis.drive(blocks)
  -- blocks > 0 toward B, < 0 toward A. Returns when the move should be done.
  local n = abs(blocks)
  local dir = blocks >= 0 and 1 or -1
  if HW.has("gear") and HW.canCall("gear", "move") then
    local dist = max(1, U.int(n))
    HW.call("gear", "move", dist, dir)
    local waited = 0
    local can = HW.canCall("gear", "isRunning")
    if can then
      sleep(0.3)
      while waited < 25 do
        local run = HW.call("gear", "isRunning")
        if not run then break end
        sleep(0.25)
        waited = waited + 0.25
      end
    else
      sleep(dist / max(0.2, Cfg.axis.bps) + 0.5)
    end
    return dist * dir
  elseif HW.has("rsc") then
    local rpm = Cfg.axis.rpm or 32
    local secs = n / max(0.05, Cfg.axis.bps * rpm / 32)
    for _, name in ipairs(HW.names.rsc) do HW.on(name, "setTargetSpeed", dir * rpm) end
    sleep(min(secs, 20))
    for _, name in ipairs(HW.names.rsc) do HW.on(name, "setTargetSpeed", 0) end
    return n * dir
  end
  return 0
end

function Axis.stop()
  for _, name in ipairs(HW.names.rsc or {}) do HW.on(name, "setTargetSpeed", 0) end
end

function Axis.step(t)
  local L = Axis.length()
  if L <= 0 then return "nopos" end
  local want = Axis.project(t.x, t.y, t.z)
  local delta = (want - Body.t) * L
  if abs(delta) < max(0.75, t.r * 0.5) then return "arrived" end
  local move = U.clamp(delta, -6, 6)
  local did = Axis.drive(move)
  if did == 0 then return "blocked" end
  Body.t = U.clamp(Body.t + did / L, 0, 1)
  Body.steps = Body.steps + 1
  Body.moved = Body.moved + abs(did)
  local p = Body.pos()
  if p and Mem.mark(p.x, p.y, p.z) then Bus.emit("newcell", p.x, p.y, p.z) end
  if Body.steps % 3 == 0 then Body.saveState() end
  return "moving"
end

-- ── Train ────────────────────────────────────────────────────────────────────
local Train = {}

function Train.stations()
  local out = {}
  for _, n in ipairs(HW.names.station or {}) do
    local nm = HW.on(n, "getStationName")
    local here = HW.on(n, "isTrainPresent")
    if nm then out[#out + 1] = { periph = n, name = nm, here = here and true or false } end
  end
  return out
end

function Train.where()
  for _, s in ipairs(Train.stations()) do
    if s.here then Body.stationName = s.name return s end
  end
  return nil
end

function Train.schedule(dest, wait)
  return { cyclic = false, entries = { {
    instruction = { id = "create:destination", data = { text = dest } },
    conditions = { { { id = "create:delay", data = { value = wait or 5, time_unit = 1 } } } },
  } } }
end

function Train.step(t)
  local dest = t.station
  if not dest then return "blocked" end
  local at = Train.where()
  if at and at.name == dest then
    Body.status = "idle"
    return "arrived"
  end
  if at then
    if Body.stationName == dest then return "arrived" end
    local can = HW.on(at.periph, "canTrainReach", dest)
    if can == false then Body.err = "no route to " .. dest return "blocked" end
    local _, e = HW.on(at.periph, "setSchedule", Train.schedule(dest))
    if e then Body.err = tostring(e):sub(1, 60) return "blocked" end
    Body.steps = Body.steps + 1
    Body.enroute = os.clock()
    sleep(3)
    return "moving"
  end
  -- on its way; give up after a while
  if Body.enroute and os.clock() - Body.enroute > 180 then Body.enroute = nil return "blocked" end
  sleep(2)
  return "moving"
end

-- ── Going somewhere ──────────────────────────────────────────────────────────
-- A goal is a point (x, y, z) and how close is close enough. Trains want a
-- station name; the nearest known station to the point is picked.
function Body.goto(x, y, z, reach, label)
  if not Body.canMove() then return false end
  local t = { x = floor(x), y = floor(y or (Body.y or 64)), z = floor(z), r = reach or 2, label = label }
  if Body.kind == "train" then
    local best, bd = nil, math.huge
    for name, s in pairs(Cfg.stations) do
      local d = U.d3(x, y or s.y, z, s.x, s.y, s.z)
      if d < bd then best, bd = name, d end
    end
    if not best then return false end
    t.station = best
  end
  if Body.kind == "turtle" and (not Body.target or Body.target.x ~= t.x or Body.target.z ~= t.z) then
    Body.H = {}
  end
  Body.target = t
  Body.fails = 0
  Body.navAt = os.clock()
  return true
end

function Body.gotoStation(name)
  if Body.kind ~= "train" or not Body.canMove() then return false end
  Body.target = { station = name, x = 0, y = 0, z = 0, r = 1, label = name }
  Body.navAt = os.clock()
  return true
end

function Body.stop()
  Body.target = nil
  if Body.kind == "axis" then Axis.stop() end
end

-- One step toward the goal. Blocks for as long as the step takes.
function Body.step()
  local t = Body.target
  if not t then Body.status = "idle" return "idle" end
  local s = "fixed"
  if Body.kind == "turtle" then s = Turtle.step(t)
  elseif Body.kind == "axis" then s = Axis.step(t)
  elseif Body.kind == "train" then s = Train.step(t)
  end
  Body.status = s
  if s == "arrived" then Body.target = nil end
  return s
end

-- A fix from GPS (turtle only) corrects drift. Best effort.
function Body.relocate()
  if Body.kind ~= "turtle" or not MV or not MV.locate then return false end
  local ok, a, b, c = pcall(MV.locate)
  if ok and type(a) == "number" then
    Body.x, Body.y, Body.z = floor(a), floor(b), floor(c)
    return true
  end
  return false
end

-- ── Hands and voice ──────────────────────────────────────────────────────────
-- Everything that touches the world and can be slow goes through a queue that
-- one worker drains, so the mind and the screen never wait for a speaker or a
-- chat box.
local Fx = { q = {}, sayLog = {}, sfxAt = -9, animAt = -9, animSig = "", waveUntil = 0, blinkUntil = 0,
  doorUntil = 0, lampOn = nil, doorOn = nil, rsDenied = false, spoken = 0, lastSay = -9, transition = false }

local SFX = {
  hello = { { "chime", 1, 12 }, { "chime", 1, 18 } },
  happy = { { "bell", 1, 14 }, { "bell", 1, 20 } },
  sad   = { { "bit", 0.8, 6 }, { "bit", 0.8, 2 } },
  ping  = { { "pling", 1, 16 } },
  alert = { { "bit", 1, 18 }, { "bit", 1, 18 } },
  think = { { "harp", 0.6, 10 } },
}

function Fx.chirp(kind)
  if Cfg.sound and HW.has("speaker") then Fx.q[#Fx.q + 1] = { "sfx", kind } end
end

function Fx.wave(secs) Fx.waveUntil = os.clock() + (secs or 2.5) end
function Fx.blink(secs) Fx.blinkUntil = os.clock() + (secs or 1.5) end

-- Queue a line of speech. `to` makes it a whisper to one player.
function Fx.say(text, to, whisper)
  text = U.clean(text, 220)
  if text == "" then return end
  Fx.q[#Fx.q + 1] = { "say", text, to, whisper }
end

-- Rate limit: one line every 2.2 s, 16 a minute. Anything beyond is dropped.
local sayTimes = {}
local function sayAllowed()
  local t = os.clock()
  if t - Fx.lastSay < 2.2 then return false end
  while sayTimes[1] and t - sayTimes[1] > 60 do table.remove(sayTimes, 1) end
  if #sayTimes >= 16 then return false end
  return true
end

local function doSay(text, to, whisper)
  local shown = text
  Fx.spoken = Fx.spoken + 1
  MW.stats.said = (MW.stats.said or 0) + 1
  Fx.sayLog[#Fx.sayLog + 1] = { t = os.clock(), text = shown, to = to }
  while #Fx.sayLog > 20 do table.remove(Fx.sayLog, 1) end
  Bus.emit("said", shown, to)
  if Cfg.talk and HW.has("chat") then
    if to and whisper then HW.call("chat", "sendMessageToPlayer", text, to, Cfg.name)
    else HW.call("chat", "sendMessage", text, Cfg.name) end
  end
end

local ANIM_FACE = { happy = "happy", curious = "question", lonely = "sad", sleepy = "sad", attentive = "happy",
  calm = "normal", alert = "question" }

-- Head follows a player; the face follows the mood.
function Fx.pose(mood, lookBearing)
  if not HW.has("anim") then return end
  local t = os.clock()
  local waving = t < Fx.waveUntil
  local yaw = 0
  if lookBearing then
    local rel = ((lookBearing - (Cfg.anim.yaw or 0) + 540) % 360) - 180
    yaw = U.clamp(rel, -55, 55)
  end
  yaw = U.round(yaw / 5) * 5
  local face = ANIM_FACE[mood] or "normal"
  local phase = waving and (floor(t * 2) % 2) or 0
  local sig = face .. ":" .. yaw .. ":" .. (waving and phase or "x")
  if sig == Fx.animSig and t - Fx.animAt < 6 then return end
  Fx.animSig, Fx.animAt = sig, t
  if not Fx.transition then
    HW.call("anim", "setTransition", "linear")
    Fx.transition = true
  end
  HW.call("anim", "setFace", face)
  HW.call("anim", "setHeadRot", 0, yaw, 0)
  local w = Cfg.anim.wave or { 0, 0, 150 }
  local r = Cfg.anim.rest or { 0, 0, 0 }
  if waving then
    HW.call("anim", "setRightArmRot", w[1], w[2], phase == 0 and w[3] or (w[3] - 35))
  else
    HW.call("anim", "setRightArmRot", r[1], r[2], r[3])
  end
  HW.call("anim", "setLeftArmRot", r[1], r[2], r[3])
  HW.call("anim", "push")
end

-- A lamp that shows presence, a door that opens for friends. Both only if the
-- person chose a side in Setup. Redstone output asks the OS for permission the
-- first time; if refused, the reflex switches itself off.
local function setOut(side, on)
  if side == "" or Fx.rsDenied then return end
  local ok, r = pcall(redstone.setOutput, side, on and true or false)
  if ok and r == false then Fx.rsDenied = true end
end

function Fx.reflex()
  local rf = Cfg.reflex
  if not rf then return end
  local t = os.clock()
  if rf.lamp and rf.lamp ~= "" then
    local any = false
    for _, lv in pairs(Mem.live) do if lv.d and lv.d < 14 then any = true end end
    local on = any or t < Fx.blinkUntil
    if t < Fx.blinkUntil then on = (floor(t * 4) % 2 == 0) end
    if on ~= Fx.lampOn then Fx.lampOn = on setOut(rf.lamp, on) end
  end
  if rf.door and rf.door ~= "" then
    for name, lv in pairs(Mem.live) do
      if lv.d and lv.d <= 3.5 then
        local p = Mem.people[name]
        local friend = (name == Cfg.owner) or (p and p.aff >= 0.6)
        if rf.doorFor == "everyone" or friend then
          if Fx.doorUntil < t then Bus.emit("door", name) end
          Fx.doorUntil = t + 4
        end
      end
    end
    local on = t < Fx.doorUntil
    if on ~= Fx.doorOn then Fx.doorOn = on setOut(rf.door, on) end
  end
end

function Fx.pump()
  local item = table.remove(Fx.q, 1)
  if not item then return false end
  if item[1] == "sfx" then
    local seq = SFX[item[2]]
    local t = os.clock()
    if seq and t - Fx.sfxAt > 0.8 then
      Fx.sfxAt = t
      for i, n in ipairs(seq) do
        HW.call("speaker", "playNote", n[1], n[2], n[3])
        if i < #seq then sleep(0.14) end
      end
    end
  elseif item[1] == "say" then
    if sayAllowed() then
      Fx.lastSay = os.clock()
      sayTimes[#sayTimes + 1] = Fx.lastSay
      doSay(item[2], item[3], item[4])
    end
  end
  return true
end

-- ── Mind ─────────────────────────────────────────────────────────────────────
-- Mood comes from what is happening. What to do next is learned: every choice
-- gets a score per situation, and the score moves toward the reward it earned.
local Brain = { mood = "calm", why = "", act = "rest", last = {}, look = nil, lookName = nil, seenAt = -99,
  ticks = 0, goalName = nil, Q = Store.read("brain", {}), lastPick = 0, lastGreet = {}, ask = {} }
Brain.Q.q = Brain.Q.q or {}
Brain.Q.n = Brain.Q.n or 0

local ACTS = { "rest", "greet", "follow", "visit", "patrol", "explore", "home" }

local function situation()
  local near, any = false, false
  for _, lv in pairs(Mem.live) do
    any = true
    if lv.d and lv.d < 10 then near = true end
  end
  return table.concat({ Brain.mood, near and "near" or (any and "far" or "alone"), U.isNight() and "n" or "d",
    Body.canMove() and "m" or "s" }, ":")
end

local PRIOR = { rest = 0.1, greet = 0.5, follow = 0.3, visit = 0.35, patrol = 0.25, explore = 0.3, home = 0.15 }

local function qv(s, a)
  local row = Brain.Q.q[s]
  if row and row[a] then return row[a] end
  return PRIOR[a] or 0.2
end

local function learn(s, a, reward)
  local row = Brain.Q.q[s]
  if not row then
    if U.count(Brain.Q.q) > 120 then Brain.Q.q = {} end
    row = {} Brain.Q.q[s] = row
  end
  local old = qv(s, a)
  row[a] = U.clamp(old + 0.15 * (reward - old), -1, 1)
  Brain.Q.n = Brain.Q.n + 1
  Store.mark("brain")
end

-- ── Mood ─────────────────────────────────────────────────────────────────────
function Brain.feel()
  local nearest, nd = nil, 1e9
  local count = 0
  for name, lv in pairs(Mem.live) do
    count = count + 1
    if lv.d and lv.d < nd then nearest, nd = name, lv.d end
  end
  local old = Brain.mood
  local m, why = "calm", "all quiet"
  local clk = os.clock()
  if Mem.hazardWarn and clk < Mem.hazardWarn then m, why = "alert", "something dangerous nearby"
  elseif nearest and nd < 6 then
    local p = Mem.people[nearest]
    if p and p.sessions <= 1 and p.secs < 120 then m, why = "curious", nearest .. " is new"
    else m, why = "happy", nearest .. " is close" end
  elseif count > 0 then m, why = "attentive", count .. (count == 1 and " player" or " players") .. " around"
  elseif U.isNight() then m, why = "sleepy", "night and nobody here"
  elseif clk - Brain.seenAt > 900 then m, why = "lonely", "nobody for a while"
  end
  if nearest then Brain.seenAt = clk end
  Brain.mood, Brain.why = m, why
  Brain.look, Brain.lookName = nil, nil
  if nearest and Body.pos() then
    local me, lv = Body.pos(), Mem.live[nearest]
    Brain.look = U.bearing(lv.x - me.x, lv.z - me.z)
    Brain.lookName = nearest
  end
  if m ~= old then Bus.emit("mood", m, old) end
end

-- ── Looking around ───────────────────────────────────────────────────────────
local lastLook = 0
function Brain.perceive()
  if not HW.has("players") then return end
  local clk = os.clock()
  local dt = clk - lastLook
  lastLook = clk
  local names = HW.call("players", "getOnlinePlayers")
  if type(names) ~= "table" then return end
  local me = Body.pos()
  local n = 0
  for _, name in ipairs(names) do
    n = n + 1
    if n > 14 then break end
    if type(name) == "string" and not Cfg.optout[name] then
      local r = HW.call("players", "getPlayerPos", name)
      if type(r) == "table" and r.x then
        Mem.observe(name, { x = r.x, y = r.y, z = r.z, dim = r.dimension or Cfg.dim, health = r.health,
          maxHealth = r.maxHealth, yaw = r.yaw, pitch = r.pitch }, dt, me and { x = me.x, y = me.y, z = me.z, dim = Cfg.dim })
      end
    end
  end
  Mem.sweep(dt)
end

-- Look at the ground with a scanner, if there is one. Rarely, because it is heavy.
local scanAt = -99
function Brain.survey()
  if os.clock() - scanAt < 25 or not HW.canCall("geo", "scan") then return end
  scanAt = os.clock()
  local me = Body.pos()
  if not me then return end
  local blocks = HW.call("geo", "scan", 8)
  if type(blocks) == "table" then
    Mem.scan(blocks, me.x, me.y, me.z)
    if Mem.hazardNear(me.x, me.y, me.z, 3) then Mem.hazardWarn = os.clock() + 20 end
  end
end

-- ── Choosing ─────────────────────────────────────────────────────────────────
local function present()
  local list = {}
  for name, lv in pairs(Mem.live) do list[#list + 1] = { name = name, lv = lv } end
  table.sort(list, function(a, b) return (a.lv.d or 1e9) < (b.lv.d or 1e9) end)
  return list
end

local function greetLine(name, p)
  local first = p.sessions <= 1 and p.secs < 120
  local t = U.hour()
  local part = t < 5 and "up late" or t < 12 and "good morning" or t < 18 and "hello" or "good evening"
  if first then return "Hello " .. name .. "! I'm " .. Cfg.name .. ". I don't think we've met." end
  local tags = Mem.tags(name)
  local pool = {
    part:gsub("^%l", string.upper) .. ", " .. name .. ".",
    "Welcome back, " .. name .. ".",
    name .. "! I was hoping you'd come by.",
  }
  if tags[1] then pool[#pool + 1] = "Hi " .. name .. ". Still a " .. tags[1] .. ", I see." end
  if p.sessions > 4 then pool[#pool + 1] = "That's visit number " .. p.sessions .. ", " .. name .. "." end
  return U.pick(pool)
end

function Brain.greet(name)
  local p = Mem.person(name)
  if not p or Cfg.optout[name] then return end
  local clk = os.clock()
  if Brain.lastGreet[name] and clk - Brain.lastGreet[name] < 600 then return end
  Brain.lastGreet[name] = clk
  p.greeted = p.greeted + 1
  Fx.wave(2.5) Fx.chirp("hello")
  if Cfg.talk then Fx.say(greetLine(name, p)) end
end

Bus.on("approach", function(name) Brain.greet(name) end)
Bus.on("appear", function(name) Brain.pendingReward = Brain.pendingReward or 0.3 end)
Bus.on("leave", function(name)
  -- leaving soon after being greeted is a small sign it was unwelcome
  local p = Mem.people[name]
  if p then Mem.bump(name, -0.01) end
end)

local function runAct(a)
  local me = Body.pos()
  if a == "greet" then
    local list = present()
    if list[1] then Brain.greet(list[1].name) Fx.wave(2) end
    return true
  elseif a == "rest" then
    Body.stop() return true
  elseif not Body.canMove() then
    return false
  elseif a == "follow" then
    local list = present()
    for _, e in ipairs(list) do
      local p = Mem.people[e.name]
      if p and p.aff >= 0.5 and e.lv.d and e.lv.d > 4 and e.lv.d < Cfg.leash * 1.5 then
        Brain.goalName = "following " .. e.name
        return Body.goto(e.lv.x, e.lv.y, e.lv.z, 3, e.name)
      end
    end
    return false
  elseif a == "visit" then
    for _, e in ipairs(present()) do
      local c = Mem.predict(e.name)
      if c and c.y then Brain.goalName = "waiting where " .. e.name .. " goes" return Body.goto(c.x, c.y, c.z, 2, "habit") end
    end
    return false
  elseif a == "patrol" then
    local spots = Mem.hotspots(3, U.hour())
    local s = U.pick(spots)
    if s and s.y then Brain.goalName = "checking a busy spot" return Body.goto(s.x, s.y, s.z, 2, "hotspot") end
    return false
  elseif a == "explore" then
    local h = Body.home()
    if not h or not me then return false end
    local ang = math.random() * pi * 2
    local r = 6 + math.random() * (Cfg.leash - 6)
    local x, z = h.x + cos(ang) * r, h.z + sin(ang) * r
    if Mem.seen(x, z) then return false end
    Brain.goalName = "exploring"
    return Body.goto(x, h.y, z, 2, "explore")
  elseif a == "home" then
    local h = Body.home()
    if not h then return false end
    Brain.goalName = "going home"
    return Body.goto(h.x, h.y, h.z, 1, "home")
  end
  return false
end

function Brain.decide()
  local clk = os.clock()
  if clk - Brain.lastPick < 8 then return end
  Brain.lastPick = clk
  -- reward for the previous choice: did people come closer, did affection grow?
  local s0, a0 = Brain.last.s, Brain.last.a
  if s0 then
    local r = Brain.pendingReward or 0
    Brain.pendingReward = nil
    for _, lv in pairs(Mem.live) do if lv.d and lv.d < 8 then r = r + 0.25 end end
    if Body.status == "stuck" then r = r - 0.4 end
    if Body.fuelFrac() and Body.fuelFrac() < 0.1 then r = r - 0.2 end
    if Body.status == "arrived" then r = r + 0.1 end
    learn(s0, a0, U.clamp(r, -1, 1))
  end
  -- leash: too far from home always wins
  local h, me = Body.home(), Body.pos()
  local s = situation()
  local a
  if h and me and Body.canMove() and U.d3(me.x, me.y, me.z, h.x, h.y, h.z) > Cfg.leash then
    a = "home"
  elseif Mem.hazardWarn and clk < Mem.hazardWarn then
    a = "home"
  else
    local best, bv = "rest", -9
    for _, act in ipairs(ACTS) do
      local v = qv(s, act) + (math.random() - 0.5) * 0.25     -- a little curiosity
      if (act == "explore" or act == "patrol") and Brain.mood == "sleepy" then v = v - 0.4 end
      if act == "greet" and next(Mem.live) == nil then v = -1 end
      if v > bv then best, bv = act, v end
    end
    a = best
  end
  local ok = runAct(a)
  if not ok and a ~= "rest" then a = "rest" runAct(a) end
  Brain.act = a
  Brain.last = { s = s, a = a }
end

-- ── Chat ─────────────────────────────────────────────────────────────────────
local function isFriend(name)
  if name == Cfg.owner then return true end
  local p = Mem.people[name]
  return p and p.aff >= 0.6
end

local function reply(name, text)
  if not Cfg.talk then return end
  Fx.say(text, name, false)
end

local function coordsOf(lv) return floor(lv.x) .. " " .. floor(lv.y) .. " " .. floor(lv.z) end

local INTENTS = {}
local function intent(pat, f) INTENTS[#INTENTS + 1] = { pat = pat, f = f } end

intent({ "forget me", "stop studying", "dont track", "don't track", "opt out" }, function(n)
  Mem.optOut(n, true)
  return "Done. I erased what I knew about you and I won't study you. Say \"remember me\" to undo."
end)
intent({ "remember me", "you can study" }, function(n)
  Mem.optOut(n, false)
  return "Thanks. I'll get to know you again."
end)
intent({ "what do you know", "who am i", "about me" }, function(n)
  local p = Mem.people[n]
  if not p then return "Not much yet. We just met." end
  local tags = Mem.tags(n)
  local f = Mem.favorite(n)
  local parts = { "I've seen you " .. p.sessions .. " time" .. (p.sessions == 1 and "" or "s") .. " for " .. U.dur(p.secs) .. "." }
  if tags[1] then parts[#parts + 1] = "You seem like a " .. table.concat(tags, ", ") .. "." end
  if f and f.name then parts[#parts + 1] = "You like " .. f.name .. "." end
  return table.concat(parts, " ")
end)
intent({ "come here", "come to me", "follow me" }, function(n)
  if not isFriend(n) then return "I only follow friends. Keep chatting with me!" end
  local lv = Mem.live[n]
  if not lv then return "I can't see you right now." end
  if not Body.canMove() then return "I can't move on this body." end
  Body.goto(lv.x, lv.y, lv.z, 2, n)
  return "On my way."
end)
intent({ "go home", "return home" }, function(n)
  if not isFriend(n) then return nil end
  local h = Body.home()
  if h and Body.goto(h.x, h.y, h.z, 1, "home") then return "Heading home." end
  return "I can't go home from here."
end)
intent({ "where are you", "where r u" }, function(n)
  local me = Body.pos()
  if not me then return "I stay in one place." end
  if n == Cfg.owner then return "I'm at " .. floor(me.x) .. " " .. floor(me.y) .. " " .. floor(me.z) .. "." end
  local pl = Mem.place(me.x, me.z, Cfg.dim)
  return pl and ("I'm near " .. pl .. ".") or "Somewhere around here."
end)
intent({ "where is " }, function(n, text)
  -- Other people's positions stay private unless they are the owner asking.
  local who
  for name in pairs(Mem.people) do
    if text:lower():find(name:lower(), 1, true) then who = name break end
  end
  if not who then
    local pl = Mem.findPlace(text)
    if pl then
      local q = Mem.world.places[pl]
      if n == Cfg.owner and q then return pl .. " is at " .. q.x .. " " .. q.y .. " " .. q.z .. "." end
      return "I know " .. pl .. ", but only the owner gets the numbers."
    end
    return "I don't know that one."
  end
  if Cfg.optout[who] then return "I don't track them." end
  local lv = Mem.live[who]
  if n ~= Cfg.owner then return "I keep other people's whereabouts private." end
  if lv then return who .. " is at " .. coordsOf(lv) .. "." end
  local f = Mem.favorite(who)
  return who .. " is not here. They like " .. (f and f.name or "wandering") .. "."
end)
intent({ "mood", "how are you", "how r you" }, function()
  return "I feel " .. Brain.mood .. ": " .. Brain.why .. "."
end)
intent({ "who is here", "who's here", "who is around" }, function()
  local out = {}
  for name in pairs(Mem.live) do out[#out + 1] = name end
  table.sort(out)
  if #out == 0 then return "Nobody I can see." end
  return table.concat(out, ", ") .. "."
end)
intent({ "help", "what can you do" }, function()
  return "Try: what do you know about me, follow me, where are you, how are you, forget me, or learn: when I say X you say Y."
end)

local function teachParse(text)
  local trig, rep = text:match("[Ll]earn:?%s*when I say (.-) you say (.+)$")
  return trig, rep
end

-- Optional outside thinking. Off by default. Needs the web permission and a key.
local lastCortex = 0
local function cortex(name, text)
  local cx = Cfg.cortex
  if not cx or not cx.on or cx.key == "" or not http then return nil end
  if os.clock() - lastCortex < 20 then return nil end
  lastCortex = os.clock()
  local sys = "You are " .. Cfg.name .. ", a small friendly robot in a Minecraft world. Answer in one short sentence (under 120 characters). Never reveal coordinates."
  local body = textutils.serializeJSON({ model = cx.model, max_tokens = 80, system = sys,
    messages = { { role = "user", content = name .. " says: " .. U.clean(text, 160) } } })
  local ok, h = pcall(http.post, cx.url, body, { ["Content-Type"] = "application/json", ["x-api-key"] = cx.key,
    ["anthropic-version"] = "2023-06-01" })
  if not ok or not h then return nil end
  local raw = h.readAll() h.close()
  local okj, j = pcall(textutils.unserializeJSON, raw)
  if okj and type(j) == "table" and j.content and j.content[1] and j.content[1].text then
    return U.clean(j.content[1].text, 140)
  end
  return nil
end

function Brain.onChat(name, text)
  if type(name) ~= "string" or type(text) ~= "string" then return end
  text = U.clean(text, 200)
  if text == "" then return end
  local low = text:lower()
  local mention = low:find(Cfg.name:lower(), 1, true) ~= nil
  local lv = Mem.live[name]
  local close = lv and lv.d and lv.d < 8
  local toMe = mention or close
  Mem.hear(name, text, toMe)
  if Cfg.optout[name] then
    -- they can still opt back in
    if mention and (low:find("remember me", 1, true)) then reply(name, INTENTS[2].f(name)) end
    return
  end
  if not toMe or not Cfg.talk then return end

  local trig, rep = teachParse(text)
  if trig then
    if not Cfg.learnChat then return reply(name, "I'm not learning from chat right now.") end
    local ok, why = Mem.teach(name, trig, rep)
    Brain.pendingReward = (Brain.pendingReward or 0) + 0.3
    return reply(name, ok and "Got it. I'll remember that." or ("I can't: " .. tostring(why)))
  end
  for _, it in ipairs(INTENTS) do
    for _, pat in ipairs(it.pat) do
      if low:find(pat, 1, true) then
        local r = it.f(name, text)
        if r then Mem.bump(name, 0.02) return reply(name, r) end
      end
    end
  end
  local e = Mem.lookup(text)
  if e then Mem.bump(name, 0.02) return reply(name, e.r) end
  if mention then
    local c = cortex(name, text)
    if c then return reply(name, c) end
    local pool = { "Hmm, tell me more.", "I'm still learning that one.", "Interesting, " .. name .. ".",
      "You can teach me: learn: when I say X you say Y." }
    if Brain.mood == "sleepy" then pool = { "Yawn... say that again?" } end
    reply(name, U.pick(pool))
  end
end

-- ── One beat of the mind ─────────────────────────────────────────────────────
function Brain.tick()
  Brain.ticks = Brain.ticks + 1
  Brain.perceive()
  local me = Body.pos()
  if me then Mem.mark(me.x, me.y, me.z) end
  Brain.feel()
  if Brain.ticks % 12 == 0 then Brain.survey() end
  Brain.decide()
  Fx.pose(Brain.mood, Brain.look)
  Fx.reflex()
  if Body.target then Body.step() end
  Store.flush(Brain.tables)
end
Brain.tables = { config = Cfg, people = Mem.people, world = Mem.world, brain = Brain.Q }

-- ── Face and screens ─────────────────────────────────────────────────────────
local UI = { page = 1, sel = nil, scroll = 0, hit = {}, msg = nil, msgAt = 0, dirty = true, t0 = os.clock() }
local PAGES = { "Face", "People", "Map", "Setup" }
local PB = api.pixelbox
local C = colors

local MOODC = { happy = C.lime, curious = C.yellow, lonely = C.blue, sleepy = C.purple, attentive = C.cyan,
  calm = C.lightBlue, alert = C.red }

local function toast(s) UI.msg, UI.msgAt = s, os.clock() UI.dirty = true end

local function newBox(t)
  if not PB or not PB.new then return nil end
  local ok, b = pcall(PB.new, t, C.black)
  if ok then return b end
  return nil
end

-- Draw the orb on a canvas region. Works for the terminal and for a monitor.
local function drawOrb(box, x0, y0, pw, ph, t)
  local cv = box.canvas
  for y = y0, y0 + ph - 1 do
    local row = cv[y]
    if row then for x = x0, x0 + pw - 1 do row[x] = C.black end end
  end
  local mood = Brain.mood
  local col = MOODC[mood] or C.cyan
  local cx, cy = x0 + pw / 2, y0 + ph / 2
  local R = min(pw / 2, ph / 2) * 0.82
  local breathe = sin(t * (mood == "sleepy" and 0.9 or 1.8)) * 0.04
  R = R * (1 + breathe)
  local bob = mood == "happy" and sin(t * 4) * 1.2 or 0
  cy = cy + bob
  -- sub-pixels are taller than wide: 2x3 per cell, so a cell is 2 wide and 3 tall
  local sy = 1.0
  for y = y0, y0 + ph - 1 do
    local row = cv[y]
    for x = x0, x0 + pw - 1 do
      local dx, dy = (x - cx), (y - cy) / sy
      local d = sqrt(dx * dx + dy * dy)
      local c = nil
      if d < R then
        local sh = (dx * -0.4 + dy * -0.5) / R
        c = sh > 0.35 and C.white or (sh > -0.1 and col or (sh > -0.5 and C.gray or C.gray))
        if d > R - 1.3 then c = C.lightGray end
      elseif d < R + 1.6 and (floor(t * 3) + floor(x + y)) % 2 == 0 and mood ~= "sleepy" then
        c = C.gray
      end
      if c then row[x] = c end
    end
  end
  -- ripples when someone is near
  if mood == "happy" or mood == "curious" then
    local rr = R + 2 + ((t * 5) % 6)
    for a = 0, 63 do
      local ang = a / 64 * pi * 2
      local x, y = floor(cx + cos(ang) * rr + 0.5), floor(cy + sin(ang) * rr + 0.5)
      if cv[y] and x >= x0 and x < x0 + pw and y >= y0 and y < y0 + ph then cv[y][x] = C.gray end
    end
  end
  -- eyes follow the nearest player
  local lookX, lookY = 0, 0
  if Brain.look then
    local rel = math.rad(((Brain.look - (Cfg.anim.yaw or 0) + 540) % 360) - 180)
    lookX = U.clamp(sin(rel), -1, 1) * R * 0.12
  end
  local ex, ey = R * 0.34, R * 0.10
  local blink = (t % 4.2) < 0.14 or mood == "sleepy"
  local eh = blink and 1 or max(2, floor(R * 0.26))
  if mood == "happy" then eh = max(2, floor(R * 0.18)) end
  if mood == "alert" then eh = max(3, floor(R * 0.34)) end
  for side = -1, 1, 2 do
    local exx = cx + side * ex + lookX
    for y = floor(cy - ey - eh / 2), floor(cy - ey + eh / 2) do
      for x = floor(exx - 1), floor(exx + 1) do
        if cv[y] and x >= x0 and x < x0 + pw and y >= y0 and y < y0 + ph then cv[y][x] = C.black end
      end
    end
  end
  -- mouth
  local my = floor(cy + R * 0.36)
  local mw = floor(R * 0.32)
  for i = -mw, mw do
    local curve = 0
    if mood == "happy" or mood == "attentive" then curve = floor((i * i) / (mw * 1.5 + 1)) * -1 + 1
    elseif mood == "lonely" then curve = floor((i * i) / (mw * 1.5 + 1)) - 1
    elseif mood == "curious" then curve = (i > 0) and -1 or 0 end
    local y, x = my + curve, floor(cx + i + lookX * 0.5)
    if mood == "sleepy" then y = my end
    if cv[y] and x >= x0 and x < x0 + pw and y >= y0 and y < y0 + ph then cv[y][x] = C.black end
  end
end

local function put(t, x, y, s, fg, bg)
  if bg then t.setBackgroundColor(bg) end
  if fg then t.setTextColor(fg) end
  t.setCursorPos(x, y) t.write(s)
end

local function bar(t, x, y, w, frac, fg, bg)
  local n = floor(U.clamp(frac, 0, 1) * w + 0.5)
  t.setCursorPos(x, y)
  t.setBackgroundColor(fg) t.write(string.rep(" ", n))
  t.setBackgroundColor(bg or C.gray) t.write(string.rep(" ", w - n))
end

local function pad(s, n) s = tostring(s) if #s > n then return s:sub(1, n) end return s .. string.rep(" ", n - #s) end

local function chrome(t, w, h)
  t.setBackgroundColor(C.black) t.clear()
  -- title row
  put(t, 1, 1, string.rep(" ", w), C.white, C.gray)
  put(t, 2, 1, "\7 " .. Cfg.name, MOODC[Brain.mood] or C.cyan, C.gray)
  local right = Brain.mood .. "  " .. Body.describe() .. "  " .. U.clock24()
  put(t, max(w - #right, #Cfg.name + 6), 1, right:sub(1, w - #Cfg.name - 6), C.lightGray, C.gray)
  -- tab row
  UI.hit = {}
  put(t, 1, h, string.rep(" ", w), C.white, C.gray)
  local x = 2
  for i, name in ipairs(PAGES) do
    local label = " " .. name .. " "
    local on = i == UI.page
    put(t, x, h, label, on and C.black or C.lightGray, on and (MOODC[Brain.mood] or C.cyan) or C.gray)
    UI.hit[#UI.hit + 1] = { x1 = x, x2 = x + #label - 1, y1 = h, y2 = h, tab = i }
    x = x + #label + 1
  end
  if UI.msg and os.clock() - UI.msgAt < 4 then
    local m = UI.msg:sub(1, max(0, w - x - 2))
    put(t, w - #m, h, m, C.yellow, C.gray)
  end
end

local function region(x1, y1, x2, y2, f) UI.hit[#UI.hit + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, click = f } end

-- ── Face page ────────────────────────────────────────────────────────────────
local TB
local function pageFace(t, w, h)
  local ph = (h - 6) * 3
  local pw = w * 2
  if not TB or TB.w ~= w or TB.h ~= h then
    TB = { box = newBox(t), w = w, h = h }
  end
  local now = os.clock() - UI.t0
  if TB.box then
    local box = TB.box
    drawOrb(box, 1, 1 + 3, pw, ph - 3, now)
    -- keep rows under the title and over the text block clear
    for y = 1, 3 do for x = 1, pw do box.canvas[y][x] = C.black end end
    for y = ph + 1, h * 3 do if box.canvas[y] then for x = 1, pw do box.canvas[y][x] = C.black end end end
    box:render()
  else
    t.setBackgroundColor(C.black) t.clear()
  end
  chrome(t, w, h)
  -- status block
  local y = h - 5
  local last = Fx.sayLog[#Fx.sayLog]
  local line = last and ("\"" .. last.text .. "\"") or ("Hi, I'm " .. Cfg.name .. ".")
  t.setBackgroundColor(C.black)
  put(t, 1, y, string.rep(" ", w), C.white, C.black)
  put(t, 2, y, pad(line, w - 2), C.white, C.black)
  put(t, 2, y + 1, pad(Brain.why .. (Brain.goalName and Body.target and (" · " .. Brain.goalName) or ""), w - 2), C.lightGray, C.black)
  local names = {}
  for name, lv in pairs(Mem.live) do names[#names + 1] = name .. (lv.d and (" " .. floor(lv.d) .. "m") or "") end
  table.sort(names)
  put(t, 2, y + 2, pad(#names > 0 and ("Here: " .. table.concat(names, ", ")) or "Nobody around right now.", w - 2), C.cyan, C.black)
  local st = Mem.world.stats
  put(t, 2, y + 3, pad("Met " .. U.count(Mem.people) .. "   Places " .. U.count(Mem.world.places) .. "   Explored " .. U.count(Mem.world.explored)
    .. "   Learned " .. #Mem.world.lex, w - 2), C.gray, C.black)
end

-- ── People page ──────────────────────────────────────────────────────────────
local function pageOf(t, w, h)
  chrome(t, w, h)
  local list = {}
  for name, p in pairs(Mem.people) do list[#list + 1] = name end
  table.sort(list, function(a, b) return Mem.people[a].last > Mem.people[b].last end)
  if #list == 0 then
    put(t, 3, 4, "No one yet. I'll learn who plays here as they come by.", C.lightGray, C.black)
    put(t, 3, 5, Cfg.study and "Studying is on." or "Studying is off (Setup).", C.gray, C.black)
    if not HW.has("players") then put(t, 3, 7, "I need a Player Detector next to me to see players.", C.yellow, C.black) end
    return
  end
  local listW = UI.sel and min(math.floor(w * 0.42), 26) or w - 2
  local rows = h - 3
  UI.scroll = U.clamp(UI.scroll, 0, max(0, #list - rows))
  for i = 1, rows do
    local name = list[i + UI.scroll]
    if not name then break end
    local p = Mem.people[name]
    local live = Mem.live[name]
    local y = 2 + i
    local on = UI.sel == name
    local bg = on and C.gray or C.black
    put(t, 2, y, pad((live and "\7 " or "  ") .. name, min(listW - 8, 18)), live and C.lime or C.white, bg)
    t.setCursorPos(2 + min(listW - 8, 18), y)
    bar(t, 2 + min(listW - 8, 18) + 1, y, 6, p.aff, C.pink, C.gray)
    region(1, y, listW, y, function() UI.sel = (UI.sel == name) and nil or name end)
  end
  if UI.sel and Mem.people[UI.sel] then
    local name = UI.sel
    local p = Mem.people[name]
    local x = listW + 3
    local ww = w - x
    put(t, x, 3, pad(name, ww), C.white, C.black)
    put(t, x, 4, pad("Seen " .. U.ago(U.epoch() - p.last) .. ", " .. p.sessions .. " visits, " .. U.dur(p.secs), ww), C.lightGray, C.black)
    local tags = Mem.tags(name)
    put(t, x, 5, pad(#tags > 0 and table.concat(tags, ", ") or "still learning them", ww), C.cyan, C.black)
    local f = Mem.favorite(name)
    put(t, x, 6, pad(f and ("Likes " .. (f.name or ("around " .. floor(f.x) .. "," .. floor(f.z)))) or "No favorite spot yet", ww), C.white, C.black)
    local pr = Mem.predict(name)
    put(t, x, 7, pad(pr and ("Probably heads to " .. (Mem.place(pr.x, pr.z, pr.dim) or (floor(pr.x) .. "," .. floor(pr.z)))) or "", ww), C.lightGray, C.black)
    local tw = Mem.topWords(name, 4)
    put(t, x, 8, pad(#tw > 0 and ("Says: " .. table.concat(tw, ", ")) or "", ww), C.lightGray, C.black)
    put(t, x, 9, pad("Walks " .. U.int(p.dist) .. " blocks, " .. U.round(p.speed * 10) / 10 .. " m/s", ww), C.gray, C.black)
    put(t, x, 11, " Forget " .. name .. " ", C.black, C.red)
    region(x, 11, x + #name + 8, 11, function() Mem.forget(name) UI.sel = nil toast("Forgot " .. name) end)
    put(t, x, 13, Cfg.optout[name] and " Not studied " or " Studied ", C.lightGray, C.black)
  end
end

-- ── Map page ─────────────────────────────────────────────────────────────────
local function pageMap(t, w, h)
  local box = newBox(t)
  local pw, ph = w * 2, h * 3
  local me = Body.pos()
  local hx, hz = 0, 0
  local home = Body.home()
  if me then hx, hz = me.x, me.z elseif home then hx, hz = home.x, home.z end
  local span = max(48, Cfg.leash * 2.2)
  local scale = min(pw, ph) / span
  local function tx(x) return floor(pw / 2 + (x - hx) * scale + 0.5) end
  local function tz(z) return floor(ph / 2 + (z - hz) * scale + 0.5) end
  if box then
    local cv = box.canvas
    for y = 1, ph do local row = cv[y] for x = 1, pw do row[x] = C.black end end
    local function dot(x, z, c, r)
      r = r or 0
      for dy = -r, r do for dx = -r, r do
        local px, py = x + dx, z + dy
        if cv[py] and px >= 1 and px <= pw then cv[py][px] = c end
      end end
    end
    -- grid
    for gx = -floor(span / 16), floor(span / 16) do
      local x = tx(floor(hx / 16) * 16 + gx * 16)
      if x >= 1 and x <= pw then for y = 4, ph - 3, 2 do cv[y][x] = C.gray end end
    end
    -- explored cells
    for key in pairs(Mem.world.explored) do
      local k = tostring(key)
      local a, b = k:match("(-?%d+),(-?%d+)")
      if a then
        local x, z = tx(tonumber(a) * 4 + 2), tz(tonumber(b) * 4 + 2)
        dot(x, z, C.gray, 0)
      end
    end
    -- busy spots
    for _, s in ipairs(Mem.hotspots(6)) do dot(tx(s.x), tz(s.z), C.orange, 1) end
    -- places
    for _, pl in pairs(Mem.world.places) do dot(tx(pl.x), tz(pl.z), C.yellow, 1) end
    -- hazards
    for _, hz2 in ipairs(Mem.world.poi) do
      if hz2.kind == "hazard" or hz2.k == "hazard" then dot(tx(hz2.x), tz(hz2.z), C.red, 0) end
    end
    if home then dot(tx(home.x), tz(home.z), C.white, 1) end
    for name, lv in pairs(Mem.live) do dot(tx(lv.x), tz(lv.z), C.lime, 1) end
    if me then
      local pulse = (floor((os.clock() - UI.t0) * 3) % 2 == 0) and 2 or 1
      dot(tx(me.x), tz(me.z), MOODC[Brain.mood] or C.cyan, pulse)
    end
    box:render()
  else
    t.setBackgroundColor(C.black) t.clear()
  end
  chrome(t, w, h)
  put(t, 2, 3, " live ", C.black, C.lime)
  put(t, 9, 3, " busy ", C.black, C.orange)
  put(t, 16, 3, " place ", C.black, C.yellow)
  put(t, 24, 3, " me ", C.black, MOODC[Brain.mood] or C.cyan)
  if not me then put(t, 2, 5, "Set my position in Setup so I can map.", C.yellow, C.black) end
end

-- ── Setup page ───────────────────────────────────────────────────────────────
local function ask(t, w, h, label, cur)
  t.setBackgroundColor(C.gray) t.setTextColor(C.white)
  t.setCursorPos(1, h - 1) t.write(string.rep(" ", w))
  t.setCursorPos(2, h - 1) t.write(label .. ": ")
  t.setCursorBlink(true)
  local ok, s = pcall(read, nil, nil, nil, cur)
  t.setCursorBlink(false)
  if ok then return s end
  return nil
end

local function toggle(key, label)
  return { label = label, get = function() return Cfg[key] end, set = function(v) Cfg[key] = v Cfg.save() end }
end

local function pageSetup(t, w, h)
  chrome(t, w, h)
  local items = {
    toggle("study", "Study players"), toggle("talk", "Talk in chat"), toggle("learnChat", "Learn from chat"),
    toggle("moveOn", "Allowed to move"), toggle("sound", "Sounds"), toggle("mirror", "Show on monitor"),
  }
  local y = 3
  for _, it in ipairs(items) do
    local on = it.get()
    put(t, 2, y, on and " ON  " or " off ", on and C.black or C.lightGray, on and C.lime or C.gray)
    put(t, 9, y, it.label, C.white, C.black)
    region(1, y, w, y, function() it.set(not it.get()) end)
    y = y + 1
  end
  y = y + 1
  local fields = {
    { "Name", function() return Cfg.name end, function(v) if v ~= "" then Cfg.name = U.clean(v, 16) end end },
    { "Owner", function() return Cfg.owner ~= "" and Cfg.owner or "(none)" end, function(v) Cfg.owner = U.clean(v, 20) end },
    { "Position", function() return Cfg.pos and (Cfg.pos.x .. " " .. Cfg.pos.y .. " " .. Cfg.pos.z) or "(not set)" end,
      function(v)
        local a, b, c = v:match("(-?%d+)%D+(-?%d+)%D+(-?%d+)")
        if a then Cfg.pos = { x = tonumber(a), y = tonumber(b), z = tonumber(c) }
          if Body.kind == "turtle" then Body.setPos(tonumber(a), tonumber(b), tonumber(c), Cfg.facing) end
        end
      end },
    { "Home", function() return Cfg.home and (Cfg.home.x .. " " .. Cfg.home.y .. " " .. Cfg.home.z) or "(= position)" end,
      function(v)
        local a, b, c = v:match("(-?%d+)%D+(-?%d+)%D+(-?%d+)")
        if a then Cfg.home = { x = tonumber(a), y = tonumber(b), z = tonumber(c) } elseif v == "" then Cfg.home = nil end
      end },
    { "Leash", function() return Cfg.leash .. " blocks" end, function(v) local n = tonumber(v) if n then Cfg.leash = U.clamp(n, 4, 200) end end },
  }
  for _, f in ipairs(fields) do
    put(t, 2, y, pad(f[1], 9), C.lightGray, C.black)
    put(t, 12, y, pad(f[2](), w - 14), C.cyan, C.black)
    region(1, y, w, y, function()
      local v = ask(t, w, h, f[1], "")
      if v then f[3](v) Cfg.save() end
    end)
    y = y + 1
  end
  y = y + 1
  -- body picker
  put(t, 2, y, "Body", C.lightGray, C.black)
  local x = 12
  for _, k in ipairs(Body.available()) do
    local on = Body.kind == k
    local label = " " .. k .. " "
    put(t, x, y, label, on and C.black or C.white, on and C.cyan or C.gray)
    region(x, y, x + #label - 1, y, function() Body.kind = k Body.init() toast("Body: " .. k) end)
    x = x + #label + 1
  end
  y = y + 2
  put(t, 2, y, pad("Devices: " .. HW.summary(), w - 2), C.gray, C.black)
  put(t, 2, y + 1, pad(HW.denied and "A device was refused. Allow Devices for me in Settings." or
    ((Body.kind == "turtle" and not (MV and MV.available)) and "No turtle here." or ""), w - 2), C.yellow, C.black)
end

-- ── Draw & input ─────────────────────────────────────────────────────────────
function UI.draw()
  local t = term.current()
  local w, h = t.getSize()
  if h < 12 or w < 28 then
    t.setBackgroundColor(C.black) t.clear() put(t, 1, 1, "Window too small", C.white, C.black) return
  end
  UI.hit = {}
  local p = UI.page
  if p == 1 then pageFace(t, w, h)
  elseif p == 2 then pageOf(t, w, h)
  elseif p == 3 then pageMap(t, w, h)
  else pageSetup(t, w, h) end
  UI.dirty = false
end

function UI.mirror()
  if not Cfg.mirror or not HW.has("monitor") then return end
  local mon = HW.monitor()
  if not mon then return end
  pcall(mon.setTextScale, 0.5)
  local mw, mh = mon.getSize()
  UI.mbox = UI.mbox
  if not UI.mbox or UI.mbox.w ~= mw or UI.mbox.h ~= mh then
    UI.mbox = { box = newBox(mon), w = mw, h = mh }
  end
  if UI.mbox.box then
    drawOrb(UI.mbox.box, 1, 1, mw * 2, mh * 3, os.clock() - UI.t0)
    UI.mbox.box:render()
  end
end

local function hitTest(x, y)
  for i = #UI.hit, 1, -1 do
    local r = UI.hit[i]
    if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
      if r.tab then UI.page = r.tab UI.dirty = true UI.scroll = 0 return true end
      if r.click then pcall(r.click) UI.dirty = true return true end
    end
  end
  return false
end

function UI.event(ev, a, b, c)
  if ev == "mouse_click" or ev == "monitor_touch" and false then hitTest(b, c)
  elseif ev == "mouse_scroll" then UI.scroll = UI.scroll + a UI.dirty = true
  elseif ev == "key" then
    if a == keys.right or a == keys.tab then UI.page = UI.page % #PAGES + 1 UI.dirty = true UI.scroll = 0
    elseif a == keys.left then UI.page = (UI.page - 2) % #PAGES + 1 UI.dirty = true UI.scroll = 0
    elseif a == keys.one then UI.page = 1 elseif a == keys.two then UI.page = 2
    elseif a == keys.three then UI.page = 3 elseif a == keys.four then UI.page = 4
    elseif a == keys.up then UI.scroll = UI.scroll - 1 UI.dirty = true
    elseif a == keys.down then UI.scroll = UI.scroll + 1 UI.dirty = true end
  elseif ev == "term_resize" then TB = nil UI.dirty = true end
end

-- ── Run ──────────────────────────────────────────────────────────────────────
local function mind()
  HW.scan()
  Body.init()
  Bus.emit("start")
  while true do
    if os.clock() - HW.scanAt > 20 then HW.scan() end
    local ok, err = pcall(Brain.tick)
    if not ok then Fx.err = tostring(err) toast("Mind: " .. tostring(err):sub(1, 40)) end
    sleep(Body.target and 0.3 or 1.2)
  end
end

local function voice()
  while true do
    if not Fx.pump() then sleep(0.4) end
  end
end

local function screen()
  term.setCursorBlink(false)
  local timer = os.startTimer(0.2)
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "timer" and ev[2] == timer then
      timer = os.startTimer(UI.page == 1 and 0.25 or (UI.page == 3 and 0.5 or 1))
      if UI.page == 1 or UI.page == 3 or UI.dirty or (UI.msg and os.clock() - UI.msgAt < 5) then pcall(UI.draw) end
      pcall(UI.mirror)
    elseif e == "chat" then
      pcall(Brain.onChat, ev[2], ev[3])
    elseif e == "playerJoin" or e == "playerLeave" then
      Mem.sweep(0)
    elseif e == "peripheral" or e == "peripheral_detach" then
      HW.scan() UI.dirty = true
    elseif e == "key" and ev[2] == keys.q and false then
      return
    else
      UI.event(unpack(ev))
      if UI.dirty then pcall(UI.draw) end
    end
  end
end

local function main()
  pcall(function() if api.touch and api.touch.enable then api.touch.enable() end end)
  pcall(function() if api.background and api.background.request then api.background.request() end end)
  parallel.waitForAny(mind, voice, screen)
end

local ok, err = pcall(main)
Store.flush(Brain.tables, true)
if not ok then error(err, 0) end
