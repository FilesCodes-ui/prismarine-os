--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/sys/inputs.lua
-- Prismarine OS v24, stage 7: the shared list of redstone inputs.
-- One list for the whole computer. Apps such as Switchboard and Dash use it
-- through the "inputs" capability, so a button is set up once.
--
-- An input = a name, a source, a mode, a strength threshold, invert, debounce.
--   source  { kind = "side", side = "left" }
--           { kind = "peripheral", name = "redstone_relay_0", side = "top" }
--   mode    "button" (active while pressed), "toggle" (flips on each press),
--           "hold" (active while the signal stays on)
-- Events to apps that hold the capability and the permission:
--   pm_input, id, "press" | "release"
--   pm_input, id, "toggle", state        (toggle mode, after each press)

local I = {}
local PATH = "/prismarine/data/inputs.dat"
local MAX_INPUTS = 32
local SIDES = { "top", "bottom", "left", "right", "front", "back" }
local SIDE_OK = {}
for _, s in ipairs(SIDES) do SIDE_OK[s] = true end
local MODES = { button = true, toggle = true, hold = true }

local K
local defs = {}      -- array, in creation order
local state = {}     -- [id] = { raw = bool, t = clock, tog = bool, level = n }
local pollTimer = false

-- ------------------------------------------------------------- storage

local function save()
  pcall(function()
    fs.makeDir(fs.getDir(PATH))
    local h = fs.open(PATH, "w")
    if h then h.write(textutils.serialize(defs)) h.close() end
  end)
end

local function clean(s, max)
  return (tostring(s or ""):gsub("%c", "")):sub(1, max)
end

-- Returns a clean definition, or nil and the reason.
local function validate(d)
  if type(d) ~= "table" then return nil, "Not a table" end
  local name = clean(d.name, 24)
  if name == "" then return nil, "Give the input a name" end
  local id = clean(d.id, 24):lower():gsub("[^%w_%-]", "")
  if id == "" then
    id = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if id == "" then id = "input" end
  end
  local src = d.source
  if type(src) ~= "table" then return nil, "No source" end
  local source
  if src.kind == "side" then
    if not SIDE_OK[src.side] then return nil, "Bad side" end
    source = { kind = "side", side = src.side }
  elseif src.kind == "peripheral" then
    local pname = clean(src.name, 40)
    if pname == "" or not SIDE_OK[src.side] then return nil, "Bad peripheral source" end
    source = { kind = "peripheral", name = pname, side = src.side }
  else
    return nil, "Bad source"
  end
  local mode = d.mode or "button"
  if not MODES[mode] then return nil, "Bad mode" end
  local th = tonumber(d.threshold) or 1
  th = math.max(1, math.min(15, math.floor(th)))
  local deb = tonumber(d.debounce) or 50
  deb = math.max(0, math.min(2000, math.floor(deb)))
  return { id = id, name = name, source = source, mode = mode, threshold = th,
    invert = d.invert == true, debounce = deb }
end
I.validate = validate

local function find(id)
  for i, d in ipairs(defs) do
    if d.id == id then return d, i end
  end
  return nil
end

-- ------------------------------------------------------------- reading

local function readLevel(src)
  if src.kind == "side" then
    local ok, v = pcall(redstone.getAnalogInput, src.side)
    return ok and tonumber(v) or 0
  end
  if peripheral.isPresent(src.name) then
    local ok, v = pcall(peripheral.call, src.name, "getAnalogInput", src.side)
    return ok and tonumber(v) or 0
  end
  return 0
end

-- Every side of the computer, and every redstone peripheral. For a "find the
-- side" screen: press your button and see which one lights up.
function I.sides()
  local out = { sides = {}, relays = {} }
  for _, s in ipairs(SIDES) do
    local ok, v = pcall(redstone.getAnalogInput, s)
    out.sides[s] = ok and tonumber(v) or 0
  end
  for _, n in ipairs(peripheral.getNames()) do
    local isRs = false
    for _, t in ipairs({ peripheral.getType(n) }) do
      if tostring(t):lower():find("redstone", 1, true) then isRs = true end
    end
    if isRs then
      local r = { name = n, type = tostring(peripheral.getType(n)), sides = {} }
      for _, s in ipairs(SIDES) do
        local ok, v = pcall(peripheral.call, n, "getAnalogInput", s)
        r.sides[s] = ok and tonumber(v) or 0
      end
      out.relays[#out.relays + 1] = r
    end
  end
  return out
end

local function active(d)
  local st = state[d.id]
  if not st then return false end
  if d.mode == "toggle" then return st.tog == true end
  return st.raw == true
end

function I.list()
  local out = {}
  for _, d in ipairs(defs) do
    local st = state[d.id] or {}
    out[#out + 1] = {
      id = d.id, name = d.name, mode = d.mode, threshold = d.threshold,
      invert = d.invert, debounce = d.debounce,
      source = { kind = d.source.kind, name = d.source.name, side = d.source.side },
      level = st.level or 0, active = active(d),
    }
  end
  return out
end

function I.read(id)
  local d = find(id)
  if not d then return nil, "No such input" end
  return readLevel(d.source), active(d)
end

-- ------------------------------------------------------------ evaluation

local function emit(id, what, value)
  if K and K.sendCap then K.sendCap("inputs", "pm_input", id, what, value) end
end

local function anyPeripheral()
  for _, d in ipairs(defs) do
    if d.source.kind == "peripheral" then return true end
  end
  return false
end

local poll
local function schedule(seconds)
  if pollTimer then return end
  pollTimer = true
  K.after(seconds, function()
    pollTimer = false
    poll()
  end)
end

-- Look at every input once. Called on each redstone event, and a few times a
-- second while a redstone peripheral is in the list (peripherals do not always
-- send an event).
poll = function()
  local now = os.clock()
  local retry = nil
  for _, d in ipairs(defs) do
    local st = state[d.id]
    if not st then
      st = { raw = false, t = -1000, tog = false, level = 0 }
      state[d.id] = st
    end
    local lvl = readLevel(d.source)
    st.level = lvl
    local raw = lvl >= d.threshold
    if d.invert then raw = not raw end
    if raw ~= st.raw then
      local wait = d.debounce / 1000 - (now - st.t)
      if wait <= 0 then
        st.raw, st.t = raw, now
        emit(d.id, raw and "press" or "release")
        if raw and d.mode == "toggle" then
          st.tog = not st.tog
          emit(d.id, "toggle", st.tog)
        end
      else
        retry = math.min(retry or wait, wait)
      end
    end
  end
  if retry then schedule(retry + 0.01)
  elseif anyPeripheral() then schedule(0.25) end
end
I.poll = poll

-- ----------------------------------------------------------------- edits

function I.save(d)
  local clean_, why = validate(d)
  if not clean_ then return false, why end
  local old, at = find(clean_.id)
  if old then
    defs[at] = clean_
  else
    if #defs >= MAX_INPUTS then return false, "Too many inputs (" .. MAX_INPUTS .. ")" end
    defs[#defs + 1] = clean_
  end
  state[clean_.id] = nil
  save()
  poll()
  return true, clean_.id
end

function I.remove(id)
  local d, at = find(id)
  if not d then return false, "No such input" end
  table.remove(defs, at)
  state[id] = nil
  save()
  return true
end

function I.init(kernel)
  K = kernel
  defs, state = {}, {}
  if fs.exists(PATH) then
    local h = fs.open(PATH, "r")
    if h then
      local ok, t = pcall(textutils.unserialize, h.readAll())
      h.close()
      if ok and type(t) == "table" then
        for _, d in ipairs(t) do
          local v = validate(d)
          if v and not find(v.id) and #defs < MAX_INPUTS then defs[#defs + 1] = v end
        end
      end
    end
  end
  -- Start the readings; no events for the level the signal already has.
  for _, d in ipairs(defs) do
    local lvl = readLevel(d.source)
    local raw = lvl >= d.threshold
    if d.invert then raw = not raw end
    state[d.id] = { raw = raw, t = -1000, tog = false, level = lvl }
  end
  if anyPeripheral() then schedule(0.25) end
end

I.MAX = MAX_INPUTS
I.SIDES = SIDES
return I
