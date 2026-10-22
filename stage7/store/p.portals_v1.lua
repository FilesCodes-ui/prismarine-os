--[==[ Prismarine
 ____
/\ _`\ __ __
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Portals
--@prismarine-api
-- Controls Egress portals from a computer that touches a portal frame block.
-- Every portal the computer can see shows in the list. Open it or seal it,
-- hold it open for a set time, name it, or open and seal all of them.
--
--   Up / Down pick        O open          C seal (close)
--   T toggle (Enter)      A open all      X seal all (press twice)
--   H hold open time      N name          R rescan          Q quit
--
-- The OS asks once to allow devices. Hold timers run only while this app is open.

local VERSION = "1"
local SETTINGS_FILE = ".prismportals_settings"
local PERIPHERAL_TYPE = "egress_portal"
local HOLDS = { 0, 10, 30, 60, 300 }

local W, H = term.getSize()
local color = term.isColor and term.isColor()

-- Colors follow the OS theme when it is there.
local function T(role, default)
  local api = rawget(_G, "prismarine")
  local c = api and api.theme and api.theme.colors
  local v = c and c[role]
  if type(v) == "number" then return v end
  return default
end

-- ── Settings ────────────────────────────────────────────────────────────────

local cfg = { hold = 1, names = {} }

local function loadCfg()
  if not fs.exists(SETTINGS_FILE) then return end
  local f = fs.open(SETTINGS_FILE, "r")
  if not f then return end
  local data = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(data) ~= "table" then return end
  if type(data.hold) == "number" and HOLDS[data.hold] then cfg.hold = data.hold end
  if type(data.names) == "table" then
    for id, n in pairs(data.names) do
      if type(id) == "string" and type(n) == "string" then cfg.names[id] = n:sub(1, 24) end
    end
  end
end

local function saveCfg()
  local f = fs.open(SETTINGS_FILE, "w")
  if f then f.write(textutils.serialize(cfg)); f.close() end
end

-- ── Names ───────────────────────────────────────────────────────────────────

local function pretty(dim)
  dim = tostring(dim or "?")
  local path = dim:match("^[^:]+:(.+)$") or dim
  path = path:gsub("[_/]", " ")
  return (path:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local function clock(sec)
  sec = math.max(0, math.floor(sec))
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function holdText(i)
  local s = HOLDS[i]
  if s == 0 then return "off" end
  if s < 60 then return s .. "s" end
  return (s / 60) .. "m"
end

-- ── Portals ─────────────────────────────────────────────────────────────────

local portals = {}      -- { name, info, gone, error, deadline }
local sel = 1
local top = 0
local message, messageColor, messageAt = "", colors.white, 0
local denied = false
local scanning = true      -- true until the first scan ends, so the screen is never blank
local crash = nil          -- text of an error, shown on screen
local confirmAll = 0
local renaming = nil    -- text buffer while naming a portal

local function now() return os.epoch("utc") / 1000 end

local function say(text, c)
  message, messageColor, messageAt = text, c or colors.white, now()
end

local function call(name, method)
  local ok, res = pcall(peripheral.call, name, method)
  if not ok then
    local why = tostring(res)
    if why:find("Not allowed", 1, true) then denied = true end
    return nil, why
  end
  denied = false
  return res
end

local function cleanError(why)
  why = tostring(why or ""):gsub("^.-:%d+:%s*", "")
  if why:find("no longer exists", 1, true) then return "That portal is gone." end
  if why:find("cannot be controlled", 1, true) or why:find("cannot control", 1, true) then
    return "This side cannot control that portal."
  end
  if why:find("Not allowed", 1, true) then return "Devices are not allowed. See Settings, App access." end
  return why:sub(1, W - 2)
end

local function find(id)
  for i, p in ipairs(portals) do
    if p.info and p.info.id == id then return i end
  end
end

local function poll()
  for _, p in ipairs(portals) do
    local info, why = call(p.name, "getInfo")
    if type(info) == "table" then
      p.info, p.gone, p.error = info, false, nil
    else
      p.error = cleanError(why)
      if tostring(why):find("no longer exists", 1, true) then p.gone = true end
    end
  end
  -- drop duplicates (one portal seen through two frame blocks) and gone portals
  local seen, keep = {}, {}
  for _, p in ipairs(portals) do
    local id = p.info and p.info.id
    if not p.gone and not (id and seen[id]) then
      if id then seen[id] = true end
      keep[#keep + 1] = p
    end
  end
  portals = keep
  if sel > #portals then sel = #portals end
  if sel < 1 then sel = 1 end
end

local function rescan()
  local keepId = portals[sel] and portals[sel].info and portals[sel].info.id
  local old = {}
  for _, p in ipairs(portals) do old[p.name] = p end
  portals = {}
  local names = peripheral.getNames()
  table.sort(names)
  for _, n in ipairs(names) do
    local okT, t = pcall(peripheral.getType, n)
    if okT and t == PERIPHERAL_TYPE then
      local p = old[n] or { name = n }
      portals[#portals + 1] = p
    end
  end
  poll()
  if keepId then
    local i = find(keepId)
    if i then sel = i end
  end
end

local function title(p)
  local id = p.info and p.info.id
  if id and cfg.names[id] then return cfg.names[id] end
  if not p.info then return p.name end
  return pretty(p.info.from) .. " > " .. pretty(p.info.to)
end

local function canControl(p)
  return p.info and p.info.canControl ~= false
end

local function isSealed(p)
  return p.info and p.info.sealed == true
end

local function setSealed(p, wantSealed, quiet)
  if not p.info then return false end
  if not canControl(p) then
    if not quiet then say("This side cannot control that portal.", colors.red) end
    return false
  end
  local _, why = call(p.name, wantSealed and "seal" or "open")
  if why then
    if not quiet then say(cleanError(why), colors.red) end
    return false
  end
  p.info.sealed = wantSealed
  if wantSealed then
    p.deadline = nil
  else
    local hold = HOLDS[cfg.hold]
    if hold > 0 then p.deadline = now() + hold else p.deadline = nil end
  end
  return true
end

local function checkHolds()
  for _, p in ipairs(portals) do
    if p.deadline and now() >= p.deadline then
      p.deadline = nil
      if not isSealed(p) then
        if setSealed(p, true, true) then say("Sealed " .. title(p) .. " after the hold time.", colors.yellow) end
      end
    end
  end
end

-- ── Drawing ─────────────────────────────────────────────────────────────────

local hits = {}

local function put(x, y, s, fg, bg)
  if y < 1 or y > H then return end
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function row(y, fg, bg)
  put(1, y, string.rep(" ", W), fg, bg)
end

local function fit(s, n)
  s = tostring(s)
  if #s > n then return s:sub(1, math.max(0, n - 1)) .. "~" end
  return s .. string.rep(" ", n - #s)
end

local function button(x, y, label, key, on, action)
  local text = " " .. key .. " " .. label .. " "
  put(x, y, text, on and colors.black or colors.gray, on and colors.cyan or colors.black)
  if on then hits[#hits + 1] = { x, y, x + #text - 1, y, action } end
  return x + #text + 1
end

local function detail(y, label, value, c)
  put(2, y, fit(label, 9), colors.lightGray, colors.black)
  put(12, y, fit(value, W - 12), c or colors.white, colors.black)
end

local function openCount()
  local o = 0
  for _, p in ipairs(portals) do if p.info and not isSealed(p) then o = o + 1 end end
  return o
end

local function hints(list)
  local x = 2
  put(1, H, string.rep(" ", W), colors.lightGray)
  for _, it in ipairs(list) do
    local need = #it[1] + 1 + #it[2] + 2
    if x + need > W then break end
    put(x, H, it[1], T("line", colors.cyan))
    put(x + #it[1] + 1, H, it[2], colors.lightGray)
    x = x + need + 1
  end
end

local function draw()
  W, H = term.getSize()
  hits = {}
  term.setBackgroundColor(colors.black)
  term.clear()

  row(1, colors.white, T("bar", colors.gray))
  put(1, 1, " Portals ", T("barText", colors.white), T("barBtn", colors.blue))
  put(11, 1, "Egress", T("line", colors.cyan), T("bar", colors.gray))
  local count = #portals .. (#portals == 1 and " portal" or " portals")
  put(W - #count, 1, count, colors.lightGray, T("bar", colors.gray))

  if crash then
    put(2, 3, "Portals stopped with an error.", colors.red)
    put(2, 5, fit(crash, W - 2), colors.lightGray)
    put(2, H, "Q quit", colors.cyan)
    return
  end

  if scanning then
    put(2, 3, "Looking for portals...", colors.yellow)
    put(2, 5, "If a card asks about devices, choose Allow.", colors.lightGray)
    return
  end

  if #portals == 0 then
    put(2, 3, "No portal found.", colors.yellow)
    put(2, 5, "Place this computer so it touches a frame", colors.lightGray)
    put(2, 6, "block of a lit portal. The computer sees an", colors.lightGray)
    put(2, 7, "egress_portal and it shows up here.", colors.lightGray)
    put(2, 9, "Not on a synced block or inside the frame.", colors.gray)
    if denied then put(2, 11, "Devices are not allowed. See Settings, App access.", colors.red) end
    hints({ { "R", "rescan" }, { "Q", "quit" } })
    return
  end

  local o = openCount()
  put(2, 2, o .. " open   " .. (#portals - o) .. " sealed", colors.lightGray)

  local listTop, listRows = 3, math.max(3, math.min(6, H - 13))
  if sel - 1 < top then top = sel - 1 end
  if sel > top + listRows then top = sel - listRows end
  if top < 0 then top = 0 end
  for i = 1, listRows do
    local idx = top + i
    local p = portals[idx]
    local y = listTop + i - 1
    if p then
      local on = (idx == sel)
      local bg = on and T("sel", colors.lightBlue) or colors.black
      row(y, colors.white, bg)
      local state, sc
      if not p.info then state, sc = "ERROR", colors.red
      elseif isSealed(p) then state, sc = "SEALED", colors.red
      elseif p.deadline then state, sc = "OPEN " .. clock(p.deadline - now()), colors.green
      else state, sc = "OPEN", colors.green end
      if on then sc = colors.black end
      put(2, y, fit(title(p), W - #state - 4), on and colors.black or colors.white, bg)
      put(W - #state, y, state, sc, bg)
      hits[#hits + 1] = { 1, y, W, y, function() sel = idx end }
    end
  end
  if top > 0 then put(W, listTop, "^", colors.gray) end
  if top + listRows < #portals then put(W, listTop + listRows - 1, "v", colors.gray) end

  local y0 = listTop + listRows
  put(1, y0, string.rep("\140", W), colors.lightGray)
  local p = portals[sel]
  if p then
    if p.info then
      local i = p.info
      detail(y0 + 1, "From", pretty(i.from))
      detail(y0 + 2, "To", pretty(i.to))
      local shape = (i.flat and "flat" or "upright")
      detail(y0 + 3, "Size", tostring(i.width) .. " x " .. tostring(i.height) .. "  " .. shape)
      detail(y0 + 4, "Synced", tostring(i.synced or 0) .. " block" .. ((i.synced or 0) == 1 and "" or "s"))
      if canControl(p) then
        detail(y0 + 5, "Control", "yes", colors.green)
      else
        detail(y0 + 5, "Control", "read only on this side", colors.yellow)
      end
      if p.deadline then
        detail(y0 + 6, "Auto seal", "in " .. clock(p.deadline - now()), colors.yellow)
      end
    else
      detail(y0 + 1, "Status", p.error or "unreadable", colors.red)
    end
  end

  -- message line
  local my = H - 2
  if renaming then
    put(2, my, "Name: ", colors.cyan)
    put(8, my, fit(renaming .. "_", W - 9), colors.white)
  elseif message ~= "" and now() - messageAt < 6 then
    put(2, my, fit(message, W - 2), messageColor)
  end

  -- buttons
  local by = H - 1
  local ctrl = p and p.info and canControl(p)
  local x = 2
  x = button(x, by, "Open", "O", ctrl and isSealed(p), function() setSealed(p, false) end)
  x = button(x, by, "Seal", "C", ctrl and not isSealed(p), function() setSealed(p, true) end)
  x = button(x, by, "Hold " .. holdText(cfg.hold), "H", true, function()
    cfg.hold = cfg.hold % #HOLDS + 1; saveCfg()
  end)
  button(x, by, "Name", "N", p and p.info ~= nil, function()
    renaming = cfg.names[p.info.id] or ""
  end)

  hints({ { "A", "open all" }, { "X", "seal all" }, { "R", "rescan" }, { "Q", "quit" } })
  if confirmAll > now() then put(1, H, fit(" Press X again to seal all portals.", W), colors.black, colors.yellow) end
end

-- ── Actions ─────────────────────────────────────────────────────────────────

local function toggle()
  local p = portals[sel]
  if not p or not p.info then return end
  if setSealed(p, not isSealed(p)) then
    say((isSealed(p) and "Sealed " or "Opened ") .. title(p) .. ".", isSealed(p) and colors.red or colors.green)
  end
end

local function allPortals(wantSealed)
  local n, ro, fail = 0, 0, 0
  for _, p in ipairs(portals) do
    if p.info and isSealed(p) ~= wantSealed then
      if not canControl(p) then ro = ro + 1
      elseif setSealed(p, wantSealed, true) then n = n + 1
      else fail = fail + 1 end
    end
  end
  local text = (wantSealed and "Sealed " or "Opened ") .. n .. " portal" .. (n == 1 and "." or "s.")
  if ro > 0 then text = text .. " " .. ro .. " read only." end
  if fail > 0 then text = text .. " " .. fail .. " failed." end
  say(text, (ro > 0 or fail > 0) and colors.yellow or (wantSealed and colors.red or colors.green))
end

local function finishRename()
  local p = portals[sel]
  if p and p.info then
    local t = renaming:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" then cfg.names[p.info.id] = nil else cfg.names[p.info.id] = t:sub(1, 24) end
    saveCfg()
    say(t == "" and "Name cleared." or "Saved.", colors.green)
  end
  renaming = nil
end

local function click(x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then h[5](); return end
  end
end

-- ── Main loop ───────────────────────────────────────────────────────────────

loadCfg()
draw()                      -- show the screen first. The first scan can wait for a permission card.
do
  local ok, err = pcall(rescan)
  if not ok then crash = tostring(err) end
  scanning = false
end
local tick = os.startTimer(1)
local scanAt = now()

local function runLoop()
while true do
  draw()
  local ev, a, b, c = os.pullEventRaw()
  if crash then
    if ev == "terminate" or (ev == "char" and a:lower() == "q") then break end
  elseif ev == "terminate" then break
  elseif ev == "timer" and a == tick then
    checkHolds()
    if now() - scanAt >= 5 then rescan(); scanAt = now() else poll() end
    tick = os.startTimer(1)
  elseif ev == "peripheral" or ev == "peripheral_detach" then
    rescan()
  elseif ev == "mouse_click" then
    if not renaming then click(b, c) end
  elseif ev == "mouse_scroll" then
    if not renaming then sel = math.max(1, math.min(#portals, sel + a)) end
  elseif renaming then
    if ev == "char" then
      if #renaming < 24 then renaming = renaming .. a end
    elseif ev == "key" then
      if a == keys.enter then finishRename()
      elseif a == keys.backspace then renaming = renaming:sub(1, -2)
      elseif a == keys.escape then renaming = nil end
    end
  elseif ev == "key" then
    if a == keys.up then sel = math.max(1, sel - 1)
    elseif a == keys.down then sel = math.min(#portals, sel + 1)
    elseif a == keys.enter then toggle() end
  elseif ev == "char" then
    local k = a:lower()
    local p = portals[sel]
    if k == "q" then break
    elseif k == "o" then
      if p and p.info and isSealed(p) and setSealed(p, false) then say("Opened " .. title(p) .. ".", colors.green) end
    elseif k == "c" then
      if p and p.info and not isSealed(p) and setSealed(p, true) then say("Sealed " .. title(p) .. ".", colors.red) end
    elseif k == "t" then toggle()
    elseif k == "a" then allPortals(false)
    elseif k == "x" then
      if confirmAll > now() then confirmAll = 0; allPortals(true) else confirmAll = now() + 3 end
    elseif k == "h" then cfg.hold = cfg.hold % #HOLDS + 1; saveCfg(); say("Hold open: " .. holdText(cfg.hold) .. ".", colors.cyan)
    elseif k == "n" then
      if p and p.info then renaming = cfg.names[p.info.id] or "" end
    elseif k == "r" then rescan(); say("Scanned.", colors.cyan) end
  end
end

end

local ok, err = pcall(runLoop)
if not ok then
  crash = tostring(err)
  while true do
    draw()
    local ev, a = os.pullEventRaw()
    if ev == "terminate" or (ev == "char" and tostring(a):lower() == "q") then break end
  end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
