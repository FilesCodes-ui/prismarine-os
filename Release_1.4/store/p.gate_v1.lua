--[==[ Prismarine
 ____
/\ _`\ __ __
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Gate
--@prismarine-api
-- Dials an Egress gate from a computer that touches its netherite frame.
-- Pick a destination, dial it to open a one way window, then confirm to build
-- the far side. Close an open gate to dial again.
--
--   Up / Down pick destination      Enter dial, or confirm a preview
--   Tab  X and Z boxes (blank = default spot)
--   C confirm   N cancel preview   K close open gate   R rescan   Q quit
--
-- The OS asks once to allow devices.

local PERIPHERAL_TYPE = "egress_gate"
local W, H = term.getSize()

local function T(role, default)
  local api = rawget(_G, "prismarine")
  local c = api and api.theme and api.theme.colors
  local v = c and c[role]
  if type(v) == "number" then return v end
  return default
end

local gates = {}          -- peripheral names
local gi = 1              -- chosen gate
local dests = {}
local sel, top = 1, 0
local status = { state = "idle" }
local focus = "list"      -- list, x, z
local fx, fz = "", ""
local message, messageColor, messageAt = "", colors.white, 0
local scanning, crash, denied = true, nil, false
local hits = {}

local function now() return os.epoch("utc") / 1000 end
local function say(t, c) message, messageColor, messageAt = t, c or colors.white, now() end

local function fit(s, n)
  s = tostring(s)
  if n <= 0 then return "" end
  if #s > n then return s:sub(1, math.max(0, n - 1)) .. "~" end
  return s
end

local function pretty(id)
  id = tostring(id or "?"):gsub("^[^:]+:", "")
  id = id:gsub("[_/]", " ")
  return (id:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- Mini scene: rounded cards through Pixelbox when it loads, flat blocks if not.
local PB
do
  local ok, mod = pcall(require, "pixelbox_lite")
  if ok and type(mod) == "table" and mod.new then PB = mod end
end
local box, boxKey
local cv, texts, ops = nil, {}, {}
local sceneBg

local function put(x, y, s, fg, bg)
  if y < 1 or y > H or x > W or s == "" then return end
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s:sub(1, W - x + 1))
end

local function begin(bg)
  W, H = term.getSize()
  sceneBg, texts, ops, cv = bg, {}, {}, nil
  if PB then
    local key = tostring(term.current()) .. W .. "x" .. H .. "/" .. bg
    if key ~= boxKey then
      local ok, b = pcall(PB.new, term.current(), bg)
      box, boxKey = ok and b or nil, ok and key or nil
    end
    if box then
      cv = box.canvas
      for y = 1, H * 3 do local r = cv[y] for x = 1, W * 2 do r[x] = bg end end
    end
  end
  term.setBackgroundColor(bg)
  term.clear()
end

local function text(x, y, s, fg, bg) texts[#texts + 1] = { x, y, s, fg, bg or sceneBg } end

local function card(x, y, w, h, fill, square)
  if w < 1 or h < 1 then return end
  if not cv then
    ops[#ops + 1] = function() for r = 0, h - 1 do put(x, y + r, string.rep(" ", w), colors.white, fill) end end
    return
  end
  local x1, x2, y1, y2 = (x - 1) * 2 + 1, (x + w - 1) * 2, (y - 1) * 3 + 1, (y + h - 1) * 3
  for py = math.max(1, y1), math.min(H * 3, y2) do
    local r = cv[py]
    for px = math.max(1, x1), math.min(W * 2, x2) do r[px] = fill end
  end
  if not square and (w >= 2 or h >= 2) then
    cv[y1][x1], cv[y1][x2], cv[y2][x1], cv[y2][x2] = sceneBg, sceneBg, sceneBg, sceneBg
  end
end

local function rule(x, y, w, color)
  if not cv then
    ops[#ops + 1] = function() put(x, y, string.rep("-", w), color, sceneBg) end
    return
  end
  local py = (y - 1) * 3 + 2
  for px = (x - 1) * 2 + 1, (x + w - 1) * 2 do cv[py][px] = color end
end

local function pill(x, y, label, fill, fg)
  card(x, y, #label + 2, 1, fill)
  text(x + 1, y, label, fg, fill)
  return x + #label + 3
end

local function flush()
  if box and cv then box:render() end
  for _, op in ipairs(ops) do op() end
  for _, t in ipairs(texts) do put(t[1], t[2], t[3], t[4], t[5]) end
end

local function clean(why)
  why = tostring(why or ""):gsub("^.-:%d+:%s*", "")
  if why:find("Not allowed", 1, true) then
    denied = true
    return "Devices are not allowed. See Settings, App access."
  end
  if why:find("not complete", 1, true) then return "The gate frame is not closed." end
  return fit(why, W - 2)
end

local function call(method, ...)
  local name = gates[gi]
  if not name then return nil, "No gate" end
  local ok, res = pcall(peripheral.call, name, method, ...)
  if not ok then return nil, tostring(res) end
  denied = false
  return res
end

local function poll()
  local s, why = call("status")
  if type(s) == "table" then status = s else status = { state = "error", err = clean(why) } end
end

local function loadDests()
  local list = call("destinations")
  if type(list) == "table" then dests = list end
  if sel > #dests then sel = math.max(1, #dests) end
end

local function rescan()
  gates = {}
  local names = peripheral.getNames()
  table.sort(names)
  for _, n in ipairs(names) do
    local ok, t = pcall(peripheral.getType, n)
    if ok and t == PERIPHERAL_TYPE then gates[#gates + 1] = n end
  end
  if gi > #gates then gi = 1 end
  if #gates > 0 then loadDests() poll() end
end

-- ── Actions ────────────────────────────────────────────────────────────────

local function dial()
  local d = dests[sel]
  if not d then return end
  local res, why
  local x, z = tonumber(fx), tonumber(fz)
  if (fx ~= "" or fz ~= "") and not (x and z) then
    say("Type both X and Z, or leave both blank.", colors.orange)
    return
  end
  if x and z then res, why = call("dial", d, math.floor(x), math.floor(z), "surface")
  else res, why = call("dial", d) end
  if why then say(clean(why), colors.red) else say(tostring(res), colors.cyan) end
  poll()
end

local function confirm()
  local res, why = call("confirm")
  if why then say(clean(why), colors.red) else say(tostring(res), colors.lime) end
  poll()
end

local function cancel()
  local res, why = call("cancel")
  if why then say(clean(why), colors.red)
  elseif res then say("Preview closed.", colors.lightGray)
  else say("Nothing to cancel.", colors.yellow) end
  poll()
end

local function closeGate()
  local res, why = call("close")
  if why then say(clean(why), colors.red)
  elseif res then say("Gate closed. Dial again.", colors.lightGray)
  else say("The gate is not open.", colors.yellow) end
  poll()
end

local function primary()
  local st = status.state
  if st == "preview" then confirm()
  elseif st == "idle" then dial()
  elseif st == "open" then say("The gate is open. Close it first.", colors.yellow)
  else say("The far side is building.", colors.yellow) end
end

-- ── Drawing ────────────────────────────────────────────────────────────────

local function hints(y, list)
  local x = 2
  local bar = T("bar", colors.gray)
  for _, h in ipairs(list) do
    local need = #h[1] + 2 + 1 + #h[2]
    if x + need > W - 1 then break end
    card(x, y, #h[1] + 2, 1, bar)
    text(x + 1, y, h[1], T("line", colors.cyan), bar)
    text(x + #h[1] + 3, y, h[2], T("hint", colors.lightGray), sceneBg)
    x = x + need + 1
  end
end

local function btn(x, y, label, fill, id, action)
  local nx = pill(x, y, label, fill, colors.black)
  hits[#hits + 1] = { x, y, nx - 2, y, action }
  return nx
end

local function draw()
  hits = {}
  local bg = T("bg", colors.black)
  local bar = T("bar", colors.gray)
  local txt = T("barText", colors.white)
  local dim = T("hint", colors.lightGray)
  begin(bg)

  local right
  if #gates > 1 then right = "gate " .. gi .. "/" .. #gates end
  local hx = pill(2, 1, "Gate", T("barBtn", colors.blue), txt)
  text(hx + 1, 1, "Egress", T("text", colors.white), bg)
  if right then text(W - #right, 1, right, dim, bg) end

  local function note(lines, y0, col)
    local cy = 3
    card(2, cy, W - 2, math.min(H - 5, #lines + 2), bar)
    for i, l in ipairs(lines) do
      text(4, cy + i, fit(l[1], W - 6), l[2] or dim, bar)
    end
  end

  if crash then
    note({ { "Gate stopped with an error.", T("err", colors.red) }, { "" }, { crash, dim } })
    hints(H - 1, { { "Q", "quit" } })
  elseif scanning then
    note({ { "Looking for a gate...", T("warn", colors.yellow) }, { "" },
      { "If a card asks about devices, choose Allow." } })
  elseif #gates == 0 then
    local l = { { "No gate found.", T("warn", colors.yellow) }, { "" },
      { "Put this computer next to the netherite" }, { "blocks of a gate. The frame must be closed." },
      { "Works in the overworld and the Ponder World." } }
    if denied then l[#l + 1] = { "" } l[#l + 1] = { "Devices are not allowed. See Settings, App access.", T("err", colors.red) } end
    note(l)
    hints(H - 1, { { "R", "rescan" }, { "Q", "quit" } })
  else
    local lw = math.min(22, math.floor(W * 0.42))
    local ch = H - 5
    local rows = ch - 3
    if sel - 1 < top then top = sel - 1 end
    if sel > top + rows then top = sel - rows end
    if top < 0 then top = 0 end

    -- left card: destinations
    card(2, 3, lw, ch, bar)
    text(4, 3, "Destinations", dim, bar)
    rule(3, 4, lw - 2, T("hdr", colors.blue))
    for i = 1, rows do
      local idx = top + i
      local d = dests[idx]
      if d then
        local y = 4 + i
        local on = idx == sel
        if on then card(3, y, lw - 2, 1, T("sel", colors.lightBlue)) end
        text(4, y, fit(pretty(d), lw - 5), on and T("selText", colors.black) or txt, on and T("sel", colors.lightBlue) or bar)
        hits[#hits + 1] = { 3, y, lw - 1, y, function() sel = idx focus = "list" end }
      end
    end
    if #dests > rows then
      local th = math.max(1, math.floor(rows * rows / #dests + 0.5))
      local ty = math.floor((rows - th) * top / math.max(1, #dests - rows) + 0.5)
      card(lw + 1, 5, 1, rows, bg, true)
      card(lw + 1, 5 + ty, 1, th, T("line", colors.cyan), true)
    end

    -- right card: state and controls
    local rx, rw = lw + 3, W - lw - 3
    card(rx, 3, rw, ch, bar)
    local st = status.state or "idle"
    local label, fill = "IDLE", T("barBtn", colors.blue)
    if st == "preview" then label, fill = "PREVIEW", T("warn", colors.yellow)
    elseif st == "building" then label, fill = "BUILDING", T("accent", colors.orange)
    elseif st == "open" then label, fill = "OPEN", T("ok", colors.lime)
    elseif st == "error" then label, fill = "ERROR", T("err", colors.red) end
    pill(rx + 1, 3, label, fill, (st == "idle") and txt or colors.black)
    if status.width then
      local t = status.width .. " x " .. status.height
      text(rx + rw - #t - 2, 3, t, dim, bar)
    end
    rule(rx + 1, 4, rw - 2, T("hdr", colors.blue))

    local shown = status.dest or dests[sel]
    text(rx + 2, 5, status.dest and "To" or "Pick", dim, bar)
    text(rx + 8, 5, fit(pretty(shown), rw - 10), txt, bar)
    if st == "error" then text(rx + 2, 6, fit(status.err or "", rw - 4), T("err", colors.red), bar)
    else text(rx + 2, 6, "Mode", dim, bar) text(rx + 8, 6, "surface", dim, bar) end

    -- X and Z fields
    text(rx + 2, 8, "Spot", dim, bar)
    local fw = math.max(6, math.min(9, math.floor((rw - 16) / 2)))
    local function field(x, label, val, on)
      text(x, 8, label, dim, bar)
      local f = on and T("hdr", colors.blue) or bg
      card(x + 2, 8, fw, 1, f)
      text(x + 3, 8, fit(val .. (on and "_" or ""), fw - 1), txt, f)
      return x + 2 + fw + 1
    end
    local x0 = rx + 8
    local x1 = field(x0, "X", fx, focus == "x")
    field(x1, "Z", fz, focus == "z")
    hits[#hits + 1] = { x0, 8, x1 - 1, 8, function() focus = "x" end }
    hits[#hits + 1] = { x1, 8, x1 + fw + 2, 8, function() focus = "z" end }
    text(rx + 2, 9, "Blank = default spot", T("hint", colors.lightGray), bar)

    -- buttons
    local by = 3 + ch - 2
    local bx = rx + 2
    if st == "idle" then
      btn(bx, by, "Dial", T("ok", colors.lime), nil, dial)
    elseif st == "preview" then
      bx = btn(bx, by, "Confirm", T("ok", colors.lime), nil, confirm)
      btn(bx, by, "Cancel", T("accent", colors.orange), nil, cancel)
    elseif st == "open" then
      btn(bx, by, "Close gate", T("err", colors.red), nil, closeGate)
    else
      text(bx, by, "Wait for the far side", dim, bar)
    end

    if message ~= "" and now() - messageAt < 6 then
      card(2, H - 2, 1, 1, messageColor)
      text(4, H - 2, fit(message, W - 5), messageColor, bg)
    end
    hints(H - 1, { { "Enter", st == "preview" and "confirm" or (st == "idle" and "dial" or "wait") },
      { "Tab", "X Z" }, { "N", "cancel" }, { "K", "close" }, { "R", "rescan" }, { "Q", "quit" } })
  end
  flush()
end

-- ── Main loop ──────────────────────────────────────────────────────────────

draw()
rescan()
scanning = false
local tick = os.startTimer(1)

local function runLoop()
  while true do
    draw()
    local ev, a, b, c = os.pullEventRaw()
    if crash then
      if ev == "terminate" or (ev == "char" and a:lower() == "q") then break end
    elseif ev == "terminate" then break
    elseif ev == "timer" and a == tick then
      if #gates > 0 then poll() else rescan() end
      tick = os.startTimer(status.state == "building" and 0.5 or 1)
    elseif ev == "peripheral" or ev == "peripheral_detach" then
      rescan()
    elseif ev == "mouse_click" then
      for _, h in ipairs(hits) do
        if b >= h[1] and b <= h[3] and c >= h[2] and c <= h[4] then h[5]() break end
      end
    elseif ev == "mouse_scroll" then
      sel = math.max(1, math.min(#dests, sel + a))
    elseif focus ~= "list" then
      if ev == "char" then
        if a:match("[%d%-]") then
          if focus == "x" and #fx < 8 then fx = fx .. a elseif focus == "z" and #fz < 8 then fz = fz .. a end
        end
      elseif ev == "key" then
        if a == keys.backspace then
          if focus == "x" then fx = fx:sub(1, -2) else fz = fz:sub(1, -2) end
        elseif a == keys.tab then focus = (focus == "x") and "z" or "list"
        elseif a == keys.enter or a == keys.escape then focus = "list" end
      end
    elseif ev == "key" then
      if a == keys.up then sel = math.max(1, sel - 1)
      elseif a == keys.down then sel = math.min(#dests, sel + 1)
      elseif a == keys.tab then focus = "x"
      elseif a == keys.enter then primary() end
    elseif ev == "char" then
      local k = a:lower()
      if k == "q" then break
      elseif k == "c" then confirm()
      elseif k == "n" then cancel()
      elseif k == "k" then closeGate()
      elseif k == "r" then rescan() say("Scanned.", colors.cyan) end
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
