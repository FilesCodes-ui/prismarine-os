--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Messenger. Signed, encrypted chat and file sharing.
-- Left: people. Right: the chat. Tab switches panes. F10 finds people. F3 sends a file.
local api = prismarine
local net = api.net
local W, H = term.getSize()

if not net then
  term.clear() term.setCursorPos(1, 1)
  print("The network service is not running.")
  os.pullEvent("key")
  return
end

local LW = 16
local sel = 1           -- selected row in the people list
local mode = "chat"     -- chat, find, file
local input = ""
local scroll = 0
local flash, flashAt = nil, 0
local transfer = nil    -- { xid, name, frac, state }
local fileInput = ""
local hits = {}
local findSel = 1

local function note(t) flash, flashAt = t, os.clock() end

-- Opening Find people starts a scan. It scans again every few seconds while
-- the page is open, so people nearby show up without pressing anything.
local lastScan = 0
local function scan(say)
  lastScan = os.clock()
  net.scan()
  if say then note("Scanning...") end
end
local function openFind()
  mode = "find"
  scan(false)
end

local function rows()
  local r = { { key = "all", name = "Everyone", unread = 0 } }
  for _, c in ipairs(net.contacts()) do r[#r + 1] = { key = c.id, name = c.name, id = c.id, unread = c.unread, fp = c.fp } end
  return r
end

local function fit(s, n)
  s = tostring(s)
  if #s > n then return s:sub(1, n) end
  return s .. string.rep(" ", n - #s)
end

local function wrap(text, width)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    while #line > width do
      local cut = line:sub(1, width):match("^.*()%s") or width
      if cut < 2 then cut = width end
      out[#out + 1] = line:sub(1, cut)
      line = line:sub(cut + 1):gsub("^%s+", "")
    end
    out[#out + 1] = line
  end
  return out
end

local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1, y1, x2, y2, fn } end

local kit = dofile("/prismarine/ui/kit.lua")
local S

-- A line of text, queued on the scene. Drawn after the cards.
local function put(x, y, str, fg, bg)
  S:text(x, y, str, fg, bg or kit.c("bg"))
end

local function drawPeople(list)
  local gray = kit.c("bar")
  S:card(2, 2, LW - 1, H - 2, gray)
  put(3, 2, "People", kit.c("barText"), gray)
  S:rule(3, 3, LW - 3, kit.c("hdr"))
  for i, r in ipairs(list) do
    local y = 3 + i
    if y >= H - 3 then break end
    local on = (i == sel and mode == "chat")
    local badge = ((r.unread or 0) > 0) and tostring(r.unread) or ""
    S:row(3, y, LW - 3, r.name, on, { right = badge ~= "" and badge or nil, rightFg = kit.c("warn") })
    hit(3, y, LW - 1, y, function() sel = i mode = "chat" scroll = 0 end)
  end
  local y1, y2 = H - 2, H - 1
  S:text(3, y1, "F10", kit.c("line"), gray)
  S:text(7, y1, "Find", kit.c("hint"), gray)
  S:text(3, y2, "F3", kit.c("line"), gray)
  S:text(7, y2, "Send file", kit.c("hint"), gray)
  hit(2, y1, LW, y1, openFind)
  hit(2, y2, LW, y2, function() mode = "file" fileInput = "" end)
end

local function drawChat(list)
  local r = list[sel] or list[1]
  local cx = LW + 2
  local cw = W - cx
  local gray = kit.c("bar")
  local x = S:pill(cx, 1, r.name, kit.c("barBtn"), kit.c("barText"))
  local sub = (r.name == "Everyone") and "signed, not secret" or ("key " .. (r.fp or ""))
  if LW == 0 then sub = sel .. "/" .. #list .. " Up/Down" end
  put(x + 1, 1, kit.fit(sub, W - x - 2), kit.c("hint"))
  -- messages as bubbles
  local maxw = math.max(8, math.floor(cw * 0.7))
  local msgs = {}
  for _, m in ipairs(net.history(r.key)) do
    local who = m.mine and "You" or m.who
    local lines = wrap(m.text, maxw - 2)
    local w = #who
    for _, l in ipairs(lines) do if #l > w then w = #l end end
    msgs[#msgs + 1] = { who = who, lines = lines, mine = m.mine, w = w + 2, h = #lines + 1 }
  end
  local top, bottom = 3, H - 4
  local area = bottom - top + 1
  -- stack from the bottom; scroll counts in messages
  local total = 0
  for _, m in ipairs(msgs) do total = total + m.h + 1 end
  local maxScroll = math.max(0, #msgs - 1)
  if scroll > maxScroll then scroll = maxScroll end
  local y = bottom + 1
  local drawn = {}
  for i = #msgs - scroll, 1, -1 do
    local m = msgs[i]
    y = y - m.h
    if y < top then break end
    drawn[#drawn + 1] = { m = m, y = y }
    y = y - 1
  end
  for _, d in ipairs(drawn) do
    local m, yy = d.m, d.y
    local bx = m.mine and (W - 1 - m.w) or cx
    local fill = m.mine and kit.c("barBtn") or gray
    S:card(bx, yy, m.w, m.h, fill)
    put(bx + 1, yy, m.who, m.mine and kit.c("info") or kit.c("ok"), fill)
    for k, l in ipairs(m.lines) do
      put(bx + 1, yy + k, l, kit.c("barText"), fill)
    end
  end
  if #msgs == 0 then
    S:card(cx + 2, 5, cw - 4, 4, gray)
    put(cx + 4, 6, "No messages yet", kit.c("barText"), gray)
    put(cx + 4, 7, "Type below and press Enter.", kit.c("hint"), gray)
  end
  -- input
  local shown = input
  if #shown > cw - 5 then shown = shown:sub(-(cw - 5)) end
  S:card(cx, H - 2, cw, 1, kit.c("bar"))
  put(cx + 1, H - 2, ">", kit.c("line"), kit.c("bar"))
  if input == "" then
    put(cx + 3, H - 2, "Type a message", kit.c("hint"), kit.c("bar"))
  else
    put(cx + 3, H - 2, shown .. "_", kit.c("barText"), kit.c("bar"))
  end
  if flash and os.clock() - flashAt < 4 then
    S:status(H - 1, flash, "warn")
  end
  local offers = net.offers()
  if #offers > 0 then
    local o = offers[1]
    S:card(cx, 2, cw, 1, kit.c("warn"))
    put(cx + 1, 2, kit.fit(o.who .. " sends " .. o.name .. " (" .. o.size .. " B)  Y yes  N no", cw - 2), colors.black, kit.c("warn"))
  end
  if transfer then
    local pct = math.floor((transfer.frac or 0) * 100)
    S:meter(cx, 2, cw, transfer.frac or 0, kit.c("ok"), kit.c("bar"))
    put(cx, 3, kit.fit(transfer.name .. " " .. transfer.state .. " " .. pct .. "%", cw), kit.c("hint"))
  end
  S.cursor = { cx + 3 + #shown, H - 2 }
end

local function boxLine(y, text, fg, gray)
  put(LW + 4, y, kit.fit(text, W - LW - 6), fg, gray)
end

local function drawFind()
  local cx = LW + 2
  local gray = kit.c("bar")
  S:pill(cx, 1, "Find people", kit.c("barBtn"), kit.c("barText"))
  S:card(cx, 3, W - cx, H - 4, gray)
  local st = net.status()
  if st.enrolled then
    boxLine(4, "This computer belongs to an Archive.", kit.c("barText"), gray)
    boxLine(5, "The Archive adds your contacts.", kit.c("hint"), gray)
    S:pill(LW + 4, 7, "Back", kit.c("hdr"), kit.c("barText"))
    hit(LW + 4, 7, LW + 11, 7, function() mode = "chat" end)
    return
  end
  if not st.modem then
    boxLine(4, "No modem found.", kit.c("warn"), gray)
    boxLine(6, "Put a modem next to this", kit.c("hint"), gray)
    boxLine(7, "computer and right click it", kit.c("hint"), gray)
    boxLine(8, "to turn it on. Both computers", kit.c("hint"), gray)
    boxLine(9, "need a modem to see each other.", kit.c("hint"), gray)
    S:hints(H - 1, { { "Esc", "back" } }, 1, LW + 2)
    return
  end
  local y = 4
  local reqs = net.pairRequests()
  for _, r in ipairs(reqs) do
    if y > H - 5 then break end
    local function yesno(id, yes, no)
      S:text(LW + 4, y + 2, "Same code on their screen?", kit.c("barText"), gray)
      local x1 = S:pill(LW + 4, y + 3, "Yes", kit.c("ok"), colors.black)
      S:pill(x1, y + 3, "No", kit.c("err"), kit.c("barText"))
      hit(LW + 4, y + 3, LW + 8, y + 3, yes)
      hit(x1, y + 3, x1 + 4, y + 3, no)
    end
    if r.dir == "in" then
      boxLine(y, r.name .. " wants to pair", kit.c("warn"), gray)
      boxLine(y + 1, "Code " .. r.code, kit.c("warn"), gray)
      local id = r.id
      yesno(id, function() net.acceptPair(id, true) note("Paired.") end, function() net.acceptPair(id, false) end)
      y = y + 5
    elseif r.answered and r.code then
      boxLine(y, "Pair with " .. r.name, kit.c("warn"), gray)
      boxLine(y + 1, "Code " .. r.code, kit.c("warn"), gray)
      local id = r.id
      yesno(id, function() net.confirmPair(id, true) note("Paired.") end, function() net.confirmPair(id, false) end)
      y = y + 5
    else
      boxLine(y, "Waiting for " .. r.name .. "...", kit.c("hint"), gray)
      y = y + 1
    end
  end
  boxLine(y, "Nearby. Click one to pair:", kit.c("hint"), gray)
  y = y + 1
  local peers = net.peers()
  if #peers == 0 then boxLine(y, "Looking... nobody found yet.", kit.c("hint"), gray) end
  for i, p in ipairs(peers) do
    if y > H - 4 then break end
    S:row(LW + 4, y, W - LW - 7, "#" .. p.id .. "  " .. p.name, i == findSel)
    local id = p.id
    hit(LW + 4, y, W - 3, y, function() findSel = i net.pair(id) note("Request sent. Compare the codes.") end)
    y = y + 1
  end
  S:hints(H - 1, { { "S", "scan now" }, { "Esc", "back" } }, 1, LW + 2)
end

local function drawFile(list)
  local cx = LW + 2
  local gray = kit.c("bar")
  S:pill(cx, 1, "Send a file", kit.c("barBtn"), kit.c("barText"))
  S:card(cx, 3, W - cx, H - 4, gray)
  local r = list[sel]
  if not r or r.key == "all" then
    boxLine(4, "Pick a person first.", kit.c("warn"), gray)
    S:hints(H - 1, { { "Esc", "back" } }, 1, LW + 2)
    return
  end
  boxLine(4, "To: " .. r.name, kit.c("barText"), gray)
  boxLine(6, "File path (up to 1 MB):", kit.c("hint"), gray)
  S:field(LW + 4, 7, W - LW - 7, fileInput, true, false)
  S.cursor = { math.min(W - 2, LW + 5 + #fileInput), 7 }
  S:hints(H - 1, { { "Enter", "send" }, { "Esc", "cancel" } }, 1, LW + 2)
end

local function draw()
  W, H = term.getSize()
  hits = {}
  local list = rows()
  if sel > #list then sel = #list end
  LW = (W < 40) and 0 or 16
  S = kit.scene()
  if LW > 0 then drawPeople(list) end
  if mode == "find" then drawFind()
  elseif mode == "file" then drawFile(list)
  else drawChat(list) end
  S:flush()
  if S.cursor then
    term.setCursorPos(S.cursor[1], S.cursor[2])
  end
  term.setCursorBlink(false)
end

local function sendInput()
  local list = rows()
  local r = list[sel]
  if not r or input == "" then return end
  local ok, why = net.send(r.key, input)
  if ok then input = "" scroll = 0 else note(why or "Could not send") end
end

local function startFile()
  local list = rows()
  local r = list[sel]
  if not r or r.key == "all" then return end
  if not fs.exists(fileInput) or fs.isDir(fileInput) then note("No such file.") mode = "chat" return end
  local h = fs.open(fileInput, "rb")
  local data = h.readAll()
  h.close()
  local xid, why = net.sendFile(r.id, fileInput, data)
  if not xid then note(why or "Could not send") else
    transfer = { xid = xid, name = fs.getName(fileInput), frac = 0, state = "waiting" }
    note("Offer sent. Waiting for them.")
  end
  mode = "chat"
end

local function saveReceived(xid, ok, nameOrWhy)
  if not ok then note(nameOrWhy or "File failed") return end
  local name, data = net.fetchFile(xid)
  if not name then return end
  if not fs.exists("/downloads") then fs.makeDir("/downloads") end
  local path = "/downloads/" .. name
  local n = 1
  while fs.exists(path) do n = n + 1 path = "/downloads/" .. n .. "_" .. name end
  local h = fs.open(path, "wb")
  if h then h.write(data) h.close() note("Saved " .. path) else note("Could not save the file.") end
end

local timer = os.startTimer(0.3)
draw()
local lastSig = ""
local function signature()
  local list = rows()
  local r = list[sel] or list[1]
  local n = 0
  for _, c in ipairs(list) do n = n + (c.unread or 0) end
  return table.concat({ tostring(#net.history(r.key)), tostring(n), tostring(#list), tostring(#net.offers()),
    tostring(#net.peers()), tostring(#net.pairRequests()), tostring(transfer and transfer.frac),
    (flash and os.clock() - flashAt < 4) and flash or "", mode }, "|")
end
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  local skip = false
  if e == "key" then
    local k = ev[2]
    if mode == "chat" then
      if k == keys.enter then sendInput()
      elseif k == keys.backspace then input = input:sub(1, -2)
      elseif k == keys.up then sel = math.max(1, sel - 1)
      elseif k == keys.down then sel = math.min(#rows(), sel + 1)
      elseif k == keys.pageUp then scroll = scroll + 5
      elseif k == keys.pageDown then scroll = math.max(0, scroll - 5)
      elseif k == keys.f10 then openFind()
      elseif k == keys.f3 then mode = "file" fileInput = ""
      end
    elseif mode == "find" then
      if k == keys.escape then mode = "chat" end
    elseif mode == "file" then
      if k == keys.escape then mode = "chat"
      elseif k == keys.backspace then fileInput = fileInput:sub(1, -2)
      elseif k == keys.enter then startFile() end
    end
  elseif e == "char" then
    local c = ev[2]
    if mode == "chat" then
      local offers = net.offers()
      if #offers > 0 and input == "" and (c == "y" or c == "Y" or c == "n" or c == "N") then
        local o = offers[1]
        net.acceptOffer(o.xid, c:lower() == "y")
        note(c:lower() == "y" and "Receiving..." or "Declined.")
      else
        input = input .. c
      end
    elseif mode == "find" then
      if c == "s" or c == "S" then scan(true) end
    elseif mode == "file" then
      fileInput = fileInput .. c
    end
  elseif e == "paste" then
    if mode == "chat" then input = input .. ev[2]:gsub("%c", "") elseif mode == "file" then fileInput = fileInput .. ev[2]:gsub("%c", "") end
  elseif e == "mouse_click" then
    for _, h in ipairs(hits) do
      if ev[3] >= h[1] and ev[3] <= h[3] and ev[4] >= h[2] and ev[4] <= h[4] then h[5]() break end
    end
  elseif e == "mouse_scroll" then
    scroll = math.max(0, scroll - ev[2])
  elseif e == "pm_net" then
    local kind = ev[2]
    if kind == "net_message" then
      local list = rows()
      local r = list[sel]
      if mode == "chat" and r and r.key == ev[3] then net.markRead(r.key) end
    elseif kind == "net_file_done" then
      saveReceived(ev[3], ev[4], ev[5])
    end
  elseif e == "timer" and ev[2] == timer then
    timer = os.startTimer(0.3)
    if transfer then
      local st, v = net.sendStep(transfer.xid)
      if st == "done" then note("Sent " .. transfer.name) transfer = nil
      elseif st == "failed" then note(v or "Transfer failed") transfer = nil
      elseif st == "sending" then transfer.state = "sending" transfer.frac = v
      end
    end
    if mode == "find" and os.clock() - lastScan >= 4 then scan(false) end
    local list = rows()
    local r = list[sel]
    if mode == "chat" and r then net.markRead(r.key) end
    local sig = signature()
    if sig == lastSig then skip = true end
    lastSig = sig
  end
  if not skip then draw() end
end
