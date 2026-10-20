-- Prismarine Messenger. Signed, encrypted chat and file sharing.
-- Left: people. Right: the chat. Tab switches panes. F2 finds people. F3 sends a file.
local api = prismarine
local net = api.net
local W, H = term.getSize()

if not net then
  term.clear() term.setCursorPos(1, 1)
  print("The network service is not running.")
  os.pullEvent("key")
  return
end

local LW = 17
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

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function drawPeople(list)
  for y = 1, H do put(1, y, string.rep(" ", LW), colors.white, colors.gray) end
  put(1, 1, fit(" People", LW), colors.white, colors.blue)
  for i, r in ipairs(list) do
    local y = 1 + i
    if y >= H - 1 then break end
    local on = (i == sel and mode == "chat")
    local label = r.name .. ((r.unread or 0) > 0 and (" " .. r.unread) or "")
    put(1, y, " " .. fit(label, LW - 1), on and colors.white or colors.lightGray, on and colors.cyan or colors.gray)
    hit(1, y, LW, y, function() sel = i mode = "chat" scroll = 0 end)
  end
  put(1, H - 1, fit(" [F2] Find people", LW), colors.cyan, colors.gray)
  hit(1, H - 1, LW, H - 1, function() mode = "find" end)
  put(1, H, fit(" [F3] Send file", LW), colors.cyan, colors.gray)
  hit(1, H, LW, H, function() mode = "file" fileInput = "" end)
end

local function drawChat(list)
  local r = list[sel] or list[1]
  local cw = W - LW - 1
  put(LW + 1, 1, fit(" " .. (r.name == "Everyone" and "Everyone (signed, not secret)" or r.name .. "  " .. (r.fp or "")), W - LW), colors.white, colors.blue)
  local lines = {}
  for _, m in ipairs(net.history(r.key)) do
    local who = m.mine and "You" or m.who
    for i, l in ipairs(wrap(m.text, cw - #who - 2)) do
      lines[#lines + 1] = { who = (i == 1) and who or "", text = l, mine = m.mine }
    end
  end
  local area = H - 3
  local maxScroll = math.max(0, #lines - area)
  if scroll > maxScroll then scroll = maxScroll end
  local first = math.max(1, #lines - area + 1 - scroll)
  for i = 0, area - 1 do
    local l = lines[first + i]
    local y = 2 + i
    put(LW + 1, y, string.rep(" ", W - LW), colors.white, colors.black)
    if l then
      if l.who ~= "" then put(LW + 2, y, l.who .. ":", l.mine and colors.lightBlue or colors.lime) end
      put(LW + 2 + math.max(#l.who + 1, 0) + 1, y, l.text, colors.white)
    end
  end
  put(LW + 1, H - 1, string.rep("-", W - LW), colors.gray, colors.black)
  local shown = input
  if #shown > cw - 2 then shown = shown:sub(-(cw - 2)) end
  put(LW + 1, H, fit("> " .. shown, W - LW), colors.white, colors.black)
  term.setCursorPos(LW + 3 + #shown, H)
  term.setCursorBlink(true)
  if flash and os.clock() - flashAt < 4 then
    put(LW + 1, H - 1, fit(" " .. flash, W - LW), colors.orange, colors.black)
  end
  local offers = net.offers()
  if #offers > 0 then
    local o = offers[1]
    put(LW + 1, 2, fit(" " .. o.who .. " sends " .. o.name .. " (" .. o.size .. " B)  [Y]es [N]o", W - LW), colors.black, colors.yellow)
  end
  if transfer then
    local pct = math.floor((transfer.frac or 0) * 100)
    put(LW + 1, 3, fit(" " .. transfer.name .. " " .. transfer.state .. " " .. pct .. "%", W - LW), colors.black, colors.lime)
  end
end

local function drawFind()
  put(LW + 1, 1, fit(" Find people", W - LW), colors.white, colors.blue)
  for y = 2, H do put(LW + 1, y, string.rep(" ", W - LW), colors.white, colors.black) end
  local st = net.status()
  if st.enrolled then
    put(LW + 2, 3, "This computer belongs to an Archive.", colors.lightGray)
    put(LW + 2, 4, "The Archive adds your contacts.", colors.lightGray)
    put(LW + 2, 6, "[Back]", colors.cyan)
    hit(LW + 2, 6, LW + 7, 6, function() mode = "chat" end)
    return
  end
  local y = 2
  local reqs = net.pairRequests()
  for _, r in ipairs(reqs) do
    if y > H - 2 then break end
    if r.dir == "in" then
      put(LW + 2, y, fit(r.name .. " wants to pair. Code " .. r.code, W - LW - 2), colors.yellow)
      put(LW + 2, y + 1, "Same code on their screen? [Yes] [No]", colors.white)
      local id = r.id
      hit(LW + 2 + 29, y + 1, LW + 2 + 33, y + 1, function() net.acceptPair(id, true) note("Paired.") end)
      hit(LW + 2 + 35, y + 1, LW + 2 + 38, y + 1, function() net.acceptPair(id, false) end)
      y = y + 3
    elseif r.answered and r.code then
      put(LW + 2, y, fit("Pair with " .. r.name .. ". Code " .. r.code, W - LW - 2), colors.yellow)
      put(LW + 2, y + 1, "Same code on their screen? [Yes] [No]", colors.white)
      local id = r.id
      hit(LW + 2 + 29, y + 1, LW + 2 + 33, y + 1, function() net.confirmPair(id, true) note("Paired.") end)
      hit(LW + 2 + 35, y + 1, LW + 2 + 38, y + 1, function() net.confirmPair(id, false) end)
      y = y + 3
    else
      put(LW + 2, y, fit("Waiting for " .. r.name .. "...", W - LW - 2), colors.lightGray)
      y = y + 1
    end
  end
  put(LW + 2, y, "Nearby (not paired). Click to pair:", colors.lightGray)
  y = y + 1
  local peers = net.peers()
  if #peers == 0 then put(LW + 2, y, "None yet. Press [S] to scan.", colors.gray) end
  for i, p in ipairs(peers) do
    if y > H - 2 then break end
    put(LW + 2, y, fit("#" .. p.id .. "  " .. p.name, W - LW - 4), (i == findSel) and colors.black or colors.white, (i == findSel) and colors.cyan or colors.black)
    local id = p.id
    hit(LW + 2, y, W, y, function() findSel = i net.pair(id) note("Request sent. Compare the codes.") end)
    y = y + 1
  end
  put(LW + 2, H, "[S] Scan   [Esc] Back", colors.cyan)
end

local function drawFile(list)
  put(LW + 1, 1, fit(" Send a file", W - LW), colors.white, colors.blue)
  for y = 2, H do put(LW + 1, y, string.rep(" ", W - LW), colors.white, colors.black) end
  local r = list[sel]
  if not r or r.key == "all" then
    put(LW + 2, 3, "Pick a person first.", colors.orange)
    put(LW + 2, 5, "[Esc] Back", colors.cyan)
    return
  end
  put(LW + 2, 3, "To: " .. r.name, colors.white)
  put(LW + 2, 5, "File path (up to 1 MB):", colors.lightGray)
  put(LW + 2, 6, fit("> " .. fileInput, W - LW - 3), colors.white, colors.gray)
  term.setCursorPos(LW + 4 + #fileInput, 6)
  term.setCursorBlink(true)
  put(LW + 2, 8, "Enter: send   Esc: cancel", colors.cyan)
end

local function draw()
  hits = {}
  term.setBackgroundColor(colors.black)
  local list = rows()
  if sel > #list then sel = #list end
  drawPeople(list)
  term.setCursorBlink(false)
  if mode == "find" then drawFind()
  elseif mode == "file" then drawFile(list)
  else drawChat(list) end
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
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  if e == "key" then
    local k = ev[2]
    if mode == "chat" then
      if k == keys.enter then sendInput()
      elseif k == keys.backspace then input = input:sub(1, -2)
      elseif k == keys.up then sel = math.max(1, sel - 1)
      elseif k == keys.down then sel = math.min(#rows(), sel + 1)
      elseif k == keys.pageUp then scroll = scroll + 5
      elseif k == keys.pageDown then scroll = math.max(0, scroll - 5)
      elseif k == keys.f2 then mode = "find"
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
      if c == "s" or c == "S" then net.scan() note("Scanning...") end
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
    local list = rows()
    local r = list[sel]
    if mode == "chat" and r then net.markRead(r.key) end
  end
  draw()
end
