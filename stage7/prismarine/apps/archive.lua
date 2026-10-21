--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Archive. The record keeper and the root of trust for a network.
-- Tabs: Feed, Days, Find, People, Apps, Disks, Info.
-- Keys: Left/Right tab, Up/Down row, Enter act, Backspace back, q quit.
local draw
local api = prismarine
local A = api.archive
local W, H = term.getSize()

if not A then
  term.clear() term.setCursorPos(1, 1)
  print("This computer is not an Archive.")
  print("Make it one in Settings > Network.")
  os.pullEvent("key")
  return
end

local TABS = { "Feed", "Days", "Find", "People", "Apps", "Disks", "Info" }
local KINDS = { "all", "private", "public", "file", "audit", "approval", "enroll", "marked" }
local KIND_LABEL = { all = "All", private = "Private", public = "Public", file = "Files", audit = "Audit", approval = "Programs", enroll = "Joins", marked = "Marked" }
local STORAGE = { "computer", "overflow", "disks", "mirror" }
local STORAGE_HELP = {
  computer = "Logs stay on this computer.",
  overflow = "Computer first. Disks when space runs low.",
  disks = "New logs go to disks. Computer if none.",
  mirror = "Every log lands on computer and disks.",
}
local RESERVES = { 10000, 20000, 50000, 100000, 1000000, 5000000, 10000000 }
local function sizeText(n)
  if n >= 1000000 then return (n / 1000000) .. " MB" end
  return n .. " B"
end

local tab, row, top = 1, 1, 0
local feed = {}
local view = nil        -- { day, recs, find, review }
local flash, flashAt = nil, 0
local items = {}
local marks = A.marks()
local prompt = nil      -- { label, buf, act }
local dest = "computer"
local q = { text = "", kind = 1, results = nil, busy = false, info = "" }

local function note(t) flash, flashAt = t, os.clock() end

local function stamp(ms)
  if not ms then return "--:--" end
  return os.date("!%H:%M", math.floor(ms / 1000))
end

local function recKey(day, r)
  return (day or "?") .. ":" .. tostring(r.t or 0) .. ":" .. tostring(r.sender or 0) .. ":" .. tostring(r.kind or "?"):sub(1, 12)
end

local function recLine(r, day)
  local m = (day and marks[recKey(day, r)]) and "* " or "  "
  return m .. stamp(r.t) .. " " .. tostring(r.text or r.kind or "?"):gsub("%c", " ")
end

local function kindOf(r)
  local k = tostring(r.kind or "")
  if k == "private" or k == "public" or k == "approval" or k == "enroll" then return k end
  if k == "file" or k == "file_data" then return "file" end
  if k:sub(1, 6) == "audit_" then return "audit" end
  return "other"
end

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function dayView(d)
  view = { day = d, recs = A.day(d) }
  row, top = 1, 0
end

local function search()
  local days = A.days()
  local want = q.text:lower()
  local kind = KINDS[q.kind]
  q.results, q.busy = {}, true
  for i = #days, 1, -1 do
    q.info = "Searching " .. (#days - i + 1) .. "/" .. #days
    draw()
    local d = days[i]
    for _, r in ipairs(A.day(d)) do
      local ok = true
      if want ~= "" then
        ok = tostring(r.text or ""):lower():find(want, 1, true) ~= nil
      end
      if ok and kind == "marked" then ok = marks[recKey(d, r)] == true
      elseif ok and kind ~= "all" then ok = (kindOf(r) == kind) end
      if ok then
        q.results[#q.results + 1] = { day = d, rec = r }
        if #q.results >= 300 then break end
      end
    end
    if #q.results >= 300 then break end
  end
  q.busy = false
  q.info = #q.results .. " found" .. (#q.results >= 300 and " (first 300)" or "")
  row, top = 1, 0
end

local function build()
  items = {}
  local function add(text, color, act, extra)
    local it = { text = text, color = color, act = act }
    if extra then for k, v in pairs(extra) do it[k] = v end end
    items[#items + 1] = it
  end
  if view then
    for _, r in ipairs(view.recs) do
      local day = (not view.review) and view.day or nil
      add(recLine(r, day), (day and marks[recKey(day, r)]) and colors.yellow or colors.white, nil, { rec = r, day = day })
    end
    if #view.recs == 0 then add("Nothing on this day.", colors.gray) end
    return
  end
  if tab == 1 then
    for i = #feed, 1, -1 do add(recLine(feed[i]), colors.white) end
    if #feed == 0 then add("Waiting for messages. New ones appear here.", colors.gray) end
  elseif tab == 2 then
    local days = A.days()
    for i = #days, 1, -1 do
      local d = days[i]
      add(d .. "   Enter: open   Del: delete", colors.white, function() dayView(d) end)
    end
    if #days == 0 then add("No saved days yet.", colors.gray) end
  elseif tab == 3 then
    add("Search: " .. q.text .. "_", colors.cyan)
    add("Show: " .. KIND_LABEL[KINDS[q.kind]] .. "   (Tab changes)   Enter: search", colors.lightGray)
    add(q.info ~= "" and q.info or "Type words. Matches any part of a message.", colors.gray)
    if q.results then
      for _, h in ipairs(q.results) do
        local d, r = h.day, h.rec
        add((marks[recKey(d, r)] and "* " or "  ") .. d:sub(6) .. " " .. stamp(r.t) .. " " .. tostring(r.text or r.kind):gsub("%c", " "),
          marks[recKey(d, r)] and colors.yellow or colors.white, function() dayView(d) end, { rec = r, day = d })
      end
    end
  elseif tab == 4 then
    local pend = A.pending()
    for _, p in ipairs(pend) do
      add("JOIN? #" .. p.id .. " " .. p.name .. "  " .. p.fp, colors.yellow, function()
        A.approve(p.id, true) note("Approved " .. p.name)
      end)
    end
    for _, m in ipairs(A.members()) do
      add((m.banned and "BANNED " or "") .. "#" .. m.id .. " " .. m.name .. "  " .. m.fp,
        m.banned and colors.red or colors.white, function()
          A.ban(m.id, not m.banned)
          note(m.banned and "Unbanned." or "Banned. Others now ignore them.")
        end)
    end
    if #items == 0 then add("No members yet.", colors.gray) end
  elseif tab == 5 then
    for _, a in ipairs(A.approvals()) do
      add("REVIEW " .. a.name .. " (" .. a.size .. " B) from #" .. tostring(a.who), colors.yellow, function()
        view = { day = "Review " .. a.name, recs = {}, review = a }
        local body = A.approvalBody(a.hash) or ""
        for line in (body .. "\n"):gmatch("(.-)\n") do view.recs[#view.recs + 1] = { text = line } end
        row, top = 1, 0
      end)
    end
    for _, a in ipairs(A.allowed()) do
      add("OK  " .. a.name .. "  " .. a.hash:sub(1, 12) .. "  Enter: revoke", colors.lime, function()
        A.revoke(a.hash) note("Revoked.")
      end)
    end
    if #items == 0 then add("No program requests.", colors.gray) end
  elseif tab == 6 then
    local st = A.storage()
    add("Storage: " .. st.storage .. "   (Enter changes)", colors.white, function()
      local i = 1
      for n, m in ipairs(STORAGE) do if m == st.storage then i = n end end
      A.setStorage("storage", STORAGE[i % #STORAGE + 1])
    end)
    add(STORAGE_HELP[st.storage] or "", colors.gray)
    add("Keep free: " .. sizeText(st.reserve) .. "   (Enter changes)", colors.white, function()
      local i = 1
      for n, v in ipairs(RESERVES) do if v == st.reserve then i = n end end
      A.setStorage("reserve", RESERVES[i % #RESERVES + 1])
    end)
    add("Used by overflow mode.", colors.gray)
    add("Disks found: " .. #st.disks, colors.white, function() A.refreshDisks() note("Looked again.") end)
    for _, d in ipairs(st.disks) do
      add("  " .. d.mount .. (d.label and (" " .. d.label) or "") .. "  " .. d.free .. " B free", colors.lightGray)
    end
    add("Copy logs to the first disk", colors.cyan, function()
      note("Copying...") draw()
      local n, why = A.copyToDisk()
      if n == false then note(tostring(why)) else note("Copied " .. tostring(n) .. " lines." .. (why and (" " .. why) or "")) end
    end)
    add("Printer: " .. (A.hasPrinter() and "found" or "none found"), colors.lightGray)
    add("Disk files stay encrypted with the Archive key.", colors.gray)
  elseif tab == 7 then
    local s = A.stats()
    add("Name: " .. tostring(A.name()), colors.white)
    add("Key code: " .. A.fingerprint(), colors.cyan)
    add("Roster version: " .. tostring(s.rosterV), colors.lightGray)
    add("Messages ok " .. s.ok .. "  bad " .. s.bad .. "  dropped " .. s.dropped, colors.lightGray)
    add("Logs are encrypted on disk with a key only this", colors.gray)
    add("Archive holds. Print and export ask your password.", colors.gray)
    add("This computer is in Bunker mode.", colors.gray)
  end
end

local hits = {}

draw = function()
  term.setBackgroundColor(colors.black)
  term.clear()
  hits = {}
  local x = 1
  put(1, 1, string.rep(" ", W), colors.white, colors.gray)
  for i, t in ipairs(TABS) do
    local on = (i == tab and not view)
    local label = " " .. t .. " "
    put(x, 1, label, on and colors.white or colors.lightGray, on and colors.blue or colors.gray)
    local x1, x2 = x, x + #label - 1
    hits[#hits + 1] = { x1, 1, x2, 1, function() tab = i view = nil row, top = 1, 0 end }
    x = x + #label + 1
  end
  build()
  if row > #items then row = #items end
  if row < 1 then row = 1 end
  local area = H - 3
  if row - 1 < top then top = row - 1 end
  if row > top + area then top = row - area end
  if view then
    local help = view.review and "Bksp back  A approve  R refuse"
      or ("Bksp back  M mark  P print  E save>" .. (dest == "disk" and "disk" or "pc") .. "  D swap")
    put(1, 2, (" " .. view.day .. "  " .. help .. string.rep(" ", W)):sub(1, W), colors.black, colors.lightGray)
  end
  for i = 1, area do
    local it = items[top + i]
    if it then
      local on = (top + i == row)
      local y = 2 + i - (view and 0 or 1)
      put(1, y, (" " .. it.text .. string.rep(" ", W)):sub(1, W), on and colors.black or it.color, on and colors.cyan or colors.black)
      local idx = top + i
      hits[#hits + 1] = { 1, y, W, y, function() row = idx if it.act then it.act() end end }
    end
  end
  if prompt then
    put(1, H, (" " .. prompt.label .. " " .. string.rep("*", #prompt.buf) .. string.rep(" ", W)):sub(1, W - 1), colors.white, colors.blue)
    term.setCursorPos(math.min(W, 3 + #prompt.label + #prompt.buf), H)
    term.setCursorBlink(true)
  else
    term.setCursorBlink(false)
    if flash and os.clock() - flashAt < 4 then put(1, H, (" " .. flash .. string.rep(" ", W)):sub(1, W - 1), colors.orange) end
  end
end

local WHY = { wrong = "Wrong password.", locked = "Too many tries. Wait." }

local function finish(res, extra, third)
  if res == false then
    note(WHY[extra] or tostring(extra or "Failed"))
  end
end

local function askPassword(label, act)
  prompt = { label = label, buf = "", act = act }
end

local function doPrint(pw)
  note("Printing...") draw()
  local pages, why, extra = A.print(view.day, pw)
  if pages == false then note(WHY[why] or tostring(why)) return end
  if pages == nil then note("Print failed.") return end
  note("Printed " .. pages .. " page" .. (pages == 1 and "" or "s") .. "." .. (why and (" " .. tostring(why)) or ""))
end

local function doExport(pw)
  note("Saving...") draw()
  local path, why = A.export(view.day, dest, pw)
  if path == false then note(WHY[why] or tostring(why)) return end
  note("Saved " .. tostring(path))
end

local function selectedRec()
  local it = items[row]
  if it and it.rec and it.day then return it.rec, it.day end
end

local timer = os.startTimer(1)
draw()
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  if prompt then
    if e == "char" then prompt.buf = prompt.buf .. ev[2]
    elseif e == "paste" then prompt.buf = prompt.buf .. tostring(ev[2]):gsub("%c", "")
    elseif e == "key" then
      if ev[2] == keys.backspace then prompt.buf = prompt.buf:sub(1, -2)
      elseif ev[2] == keys.escape then prompt = nil
      elseif ev[2] == keys.enter then
        local p2 = prompt
        prompt = nil
        p2.act(p2.buf)
      end
    end
  elseif e == "key" then
    local k = ev[2]
    local typing = (tab == 3 and not view)
    if k == keys.left and not view then tab = (tab - 2) % #TABS + 1 row, top = 1, 0
    elseif k == keys.right and not view then tab = tab % #TABS + 1 row, top = 1, 0
    elseif k == keys.up then row = row - 1
    elseif k == keys.down then row = row + 1
    elseif k == keys.pageUp then row = row - 8
    elseif k == keys.pageDown then row = row + 8
    elseif k == keys.tab and typing then q.kind = q.kind % #KINDS + 1 q.results = nil
    elseif k == keys.enter and typing and row <= 3 then search()
    elseif k == keys.enter then
      local it = items[row]
      if it and it.act then it.act() end
    elseif k == keys.backspace and typing and #q.text > 0 then q.text = q.text:sub(1, -2)
    elseif k == keys.backspace then view = nil row, top = 1, 0
    elseif k == keys.delete and tab == 2 and not view then
      local days = A.days()
      local d = days[#days - row + 1]
      if d and A.deleteDay(d) then note("Deleted " .. d) end
    end
  elseif e == "char" then
    local c = ev[2]
    if view and view.review then
      if c == "a" then A.allow(view.review.hash, true) note("Approved.") view = nil
      elseif c == "r" then A.allow(view.review.hash, false) note("Refused.") view = nil end
    elseif view then
      if c == "q" then return
      elseif c == "m" or c == "M" then
        local r, d = selectedRec()
        if r then
          local key = recKey(d, r)
          local on = not marks[key]
          if A.setMark(key, on) then marks[key] = on or nil note(on and "Marked." or "Unmarked.")
          else note("Too many marks.") end
        end
      elseif c == "d" or c == "D" then dest = (dest == "computer") and "disk" or "computer"
      elseif c == "p" or c == "P" then
        if not A.hasPrinter() then note("No printer found.")
        else askPassword("Password to print:", doPrint) end
      elseif c == "e" or c == "E" then askPassword("Password to save plain text:", doExport)
      end
    elseif tab == 3 then
      if #q.text < 40 then q.text = q.text .. c end
    elseif c == "q" then return
    elseif tab == 2 and (c == "m" or c == "M") then
    end
  elseif e == "paste" and tab == 3 and not view then
    q.text = (q.text .. tostring(ev[2]):gsub("%c", "")):sub(1, 40)
  elseif e == "mouse_click" then
    for _, h in ipairs(hits) do
      if ev[3] >= h[1] and ev[3] <= h[3] and ev[4] >= h[2] and ev[4] <= h[4] then h[5]() break end
    end
  elseif e == "mouse_scroll" then
    row = row + ev[2] * 3
  elseif e == "pm_arc" then
    feed[#feed + 1] = ev[2]
    if #feed > 200 then table.remove(feed, 1) end
  elseif e == "timer" and ev[2] == timer then
    timer = os.startTimer(1)
  end
  draw()
end
