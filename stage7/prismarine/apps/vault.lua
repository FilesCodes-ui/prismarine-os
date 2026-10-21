--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Vault. A short list of secrets, locked with your password.
-- Items are sealed with a key made from the password and kept where no app
-- can read them. The Vault asks for the password each time it opens, and
-- locks itself after 90 quiet seconds.
-- Keys: Up/Down pick, Enter open, A add, E edit, D delete, G make a password,
-- L lock, Q quit.
local api = prismarine
local vault, account = api.vault, api.account
local W, H = term.getSize()
local IDLE = 90

local items = nil
local screen = "gate"
local sel, top = 1, 0
local shown, shownAt = false, 0
local flash, flashColor, flashAt = nil, colors.lightGray, 0
local lastInput = os.clock()
local password = true
local hits = {}
local timer = nil
local forceLock = false
local INPUT = { key = true, char = true, paste = true, mouse_click = true, mouse_scroll = true, mouse_drag = true }

-- Called for every event. Notes real input, and watches the quiet timer.
-- Returns true when the Vault should lock because nobody is there.
local function watch(ev)
  if INPUT[ev[1]] then lastInput = os.clock() end
  if ev[1] == "timer" and ev[2] == timer then
    timer = os.startTimer(5)
    if password and os.clock() - lastInput > IDLE then
      forceLock = true
      return true
    end
  end
  return false
end

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end
local function pad(s, n)
  if #s > n then return s:sub(1, n) end
  return s .. string.rep(" ", n - #s)
end
local function note(t, c)
  flash, flashColor, flashAt = t, c or colors.lightGray, os.clock()
  os.startTimer(6)
end
local function bar(text, right)
  put(1, 1, pad(" Vault", W), colors.cyan, colors.gray)
  put(9, 1, text or "", colors.white, colors.gray)
  if right then put(W - #right, 1, right, colors.lightGray, colors.gray) end
end
local function footer(a, b)
  put(1, H - 1, pad(" " .. (a or ""), W), colors.cyan)
  if flash and os.clock() - flashAt < 6 then
    put(1, H, pad(" " .. flash, W), flashColor)
  else
    put(1, H, pad(" " .. (b or ""), W), colors.gray)
  end
end
local function clear()
  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.clear()
  hits = {}
end

-- ------------------------------------------------------------ line editing

-- Applies one event to a text buffer. Returns the buffer and cursor.
local function editBuf(buf, pos, ev, max)
  local e = ev[1]
  if e == "char" then
    if #buf < max then buf = buf:sub(1, pos - 1) .. ev[2] .. buf:sub(pos) pos = pos + 1 end
  elseif e == "paste" then
    local t = ev[2]:gsub("[\r\n]", " ")
    t = t:sub(1, max - #buf)
    buf = buf:sub(1, pos - 1) .. t .. buf:sub(pos)
    pos = pos + #t
  elseif e == "key" then
    local k = ev[2]
    if k == keys.backspace then
      if pos > 1 then buf = buf:sub(1, pos - 2) .. buf:sub(pos) pos = pos - 1 end
    elseif k == keys.delete then buf = buf:sub(1, pos - 1) .. buf:sub(pos + 1)
    elseif k == keys.left then pos = math.max(1, pos - 1)
    elseif k == keys.right then pos = math.min(#buf + 1, pos + 1)
    elseif k == keys.home then pos = 1
    elseif k == keys["end"] then pos = #buf + 1 end
  end
  return buf, pos
end

-- ------------------------------------------------------------ password maker

local LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local SYMBOLS = "!@#$%&*?-_=+"

local function makePassword(len, symbols)
  local set = LETTERS .. (symbols and SYMBOLS or "")
  local n = #set
  local limit = math.floor(256 / n) * n
  local out = {}
  while #out < len do
    local bytes = vault.random(len * 3)
    for i = 1, #bytes do
      local b = bytes:byte(i)
      if b < limit then
        local c = b % n + 1
        out[#out + 1] = set:sub(c, c)
        if #out >= len then break end
      end
    end
  end
  return table.concat(out)
end

-- Shows a made password. Returns it when the person chooses Use, or nil.
local function generator(canUse)
  local len, symbols = 16, true
  local pw = makePassword(len, symbols)
  while true do
    clear()
    bar("Make a password")
    put(2, 3, "Length   " .. len .. "   (Left / Right to change)", colors.white)
    put(2, 4, "Symbols  " .. (symbols and "on " or "off") .. "   (S to switch)", colors.white)
    put(2, 7, pad(" " .. pw, math.min(W - 2, len + 2)), colors.white, colors.gray)
    put(2, 9, "Made with strong random bytes. Nothing is saved.", colors.gray)
    footer("R: new one   " .. (canUse and "Enter: use it   " or "") .. "Esc: back")
    local ev = { os.pullEvent() }
    if watch(ev) then return nil end
    if ev[1] == "key" then
      local k = ev[2]
      if k == keys.escape then return nil
      elseif k == keys.enter and canUse then return pw
      elseif k == keys.left and len > 8 then len = len - 1 pw = makePassword(len, symbols)
      elseif k == keys.right and len < 32 then len = len + 1 pw = makePassword(len, symbols) end
    elseif ev[1] == "char" then
      local c = ev[2]:lower()
      if c == "r" then pw = makePassword(len, symbols)
      elseif c == "s" then symbols = not symbols pw = makePassword(len, symbols) end
    end
  end
end

-- ------------------------------------------------------------ saving

local function sortItems()
  table.sort(items, function(a, b)
    local x, y = a.title:lower(), b.title:lower()
    if x == y then return a.changed < b.changed end
    return x < y
  end)
end

local function persist()
  sortItems()
  local ok, why = vault.save(items)
  if not ok then note("Could not save: " .. tostring(why), colors.red) end
  return ok
end

-- ------------------------------------------------------------ gate

local function gate()
  if not password then
    screen = "list"
    return true
  end
  local buf, pos = "", 1
  local msg, busy = nil, false
  while true do
    clear()
    bar("Locked")
    put(2, 4, "Enter your password to open the Vault.", colors.white)
    put(2, 6, "Password", colors.lightGray)
    put(2, 7, pad(string.rep("*", #buf), 30), colors.white, colors.gray)
    if busy then put(2, 9, "Checking...", colors.cyan)
    elseif msg then put(2, 9, msg, colors.red) end
    footer("Enter: open   Esc: close")
    term.setCursorPos(2 + #buf, 7)
    term.setCursorBlink(true)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.gray)
    local ev = { os.pullEvent() }
    watch(ev)
    forceLock = false
    if ev[1] == "key" and ev[2] == keys.escape then return false
    elseif ev[1] == "key" and ev[2] == keys.enter then
      if #buf > 0 then
        busy = true
        clear()
        bar("Locked")
        put(2, 9, "Checking...", colors.cyan)
        local good = account.check(buf)
        buf, pos, busy = "", 1, false
        if good then
          lastInput = os.clock()
          return true
        end
        msg = "Wrong password"
      end
    else
      buf, pos = editBuf(buf, pos, ev, 60)
      if ev[1] == "char" then msg = nil end
    end
  end
end

-- ------------------------------------------------------------ screens

local function drawList()
  clear()
  bar(("%d item%s"):format(#items, #items == 1 and "" or "s"), password and "protected" or "no password")
  local rows = H - 4
  if sel > #items then sel = #items end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + rows then top = sel - rows end
  for i = 1, rows do
    local it = items[top + i]
    if it then
      local on = top + i == sel
      local bg = on and colors.cyan or colors.black
      put(1, 1 + i, string.rep(" ", W), colors.white, bg)
      put(2, 1 + i, pad(it.title, 24), on and colors.black or colors.white, bg)
      put(27, 1 + i, pad(it.user, W - 27), on and colors.black or colors.lightGray, bg)
      local idx = top + i
      hits[#hits + 1] = { 1 + i, idx }
    end
  end
  if #items == 0 then
    put(2, 3, "Nothing here yet.", colors.white)
    put(2, 4, "Press A to add a login, key or note.", colors.lightGray)
  end
  if not password then
    put(1, H - 2, pad(" No password set. Items are hidden, not locked.", W), colors.orange)
  end
  footer("Enter open   A add   E edit   D delete", "G make password   L lock   Q quit")
end

local function drawView(it)
  clear()
  bar(it.title)
  local function field(y, label, value, color)
    put(2, y, label, colors.lightGray)
    put(2, y + 1, pad(value == "" and "-" or value, W - 2), color or colors.white)
  end
  field(3, "User", it.user)
  local secret = it.secret
  if secret == "" then
    field(6, "Secret", "")
  elseif shown then
    field(6, "Secret", secret, colors.lime)
  else
    field(6, "Secret", string.rep("*", math.min(#secret, W - 4)), colors.white)
  end
  field(9, "Note", it.note)
  footer("S: " .. (shown and "hide" or "show") .. " secret   E: edit   Esc: back", shown and "The secret hides itself in 10 seconds" or "")
end

local FIELDS = {
  { "title", "Title", 40 },
  { "user", "User or name", 60 },
  { "secret", "Secret (F2 makes one)", 120 },
  { "note", "Note", 200 },
}

-- Add or edit an item. Returns the new item, or nil if cancelled.
local function form(base)
  local vals, pos = {}, {}
  for i, f in ipairs(FIELDS) do
    vals[i] = base and base[f[1]] or ""
    pos[i] = #vals[i] + 1
  end
  local focus = 1
  local ctrl = false
  while true do
    clear()
    bar(base and "Edit item" or "New item")
    for i, f in ipairs(FIELDS) do
      local y = 2 + (i - 1) * 3
      put(2, y, f[2], i == focus and colors.cyan or colors.lightGray)
      local v = vals[i]
      local room = W - 4
      local from = 1
      if i == focus and pos[i] > room then from = pos[i] - room + 1 end
      put(2, y + 1, pad(v:sub(from, from + room - 1), room + 1), colors.white, i == focus and colors.gray or colors.black)
      if i ~= focus then hits[#hits + 1] = { y + 1, i } end
    end
    footer("Tab or Enter: next   Ctrl+S: save   Esc: cancel", flash and "" or "Title is required")
    local y = 2 + (focus - 1) * 3 + 1
    local room = W - 4
    local from = (pos[focus] > room) and (pos[focus] - room + 1) or 1
    term.setCursorPos(2 + pos[focus] - from, y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorBlink(true)
    local ev = { os.pullEvent() }
    if watch(ev) then return nil end
    local function finish()
      if vals[1] == "" then note("Give it a title first", colors.orange) focus = 1 return nil end
      local out = { changed = os.epoch("utc") }
      for i, f in ipairs(FIELDS) do out[f[1]] = vals[i] end
      return out
    end
    if ev[1] == "key" then
      local k = ev[2]
      if k == keys.escape then return nil
      elseif k == keys.tab or k == keys.down then focus = focus % #FIELDS + 1
      elseif k == keys.up then focus = (focus - 2) % #FIELDS + 1
      elseif k == keys.enter then
        if focus < #FIELDS then focus = focus + 1
        else local out = finish() if out then return out end end
      elseif k == keys.f2 then
        local made = generator(true)
        if made then vals[3] = made pos[3] = #made + 1 focus = 3 end
      elseif k == keys.leftCtrl or k == keys.rightCtrl then ctrl = true
      elseif k == keys.s and ctrl then
        local out = finish() if out then return out end
      else
        vals[focus], pos[focus] = editBuf(vals[focus], pos[focus], ev, FIELDS[focus][3])
      end
    elseif ev[1] == "key_up" then
      if ev[2] == keys.leftCtrl or ev[2] == keys.rightCtrl then ctrl = false end
    elseif ev[1] == "mouse_click" then
      for _, h in ipairs(hits) do
        if ev[4] == h[1] then focus = h[2] end
      end
    else
      if ev[1] == "char" then ctrl = false end
      vals[focus], pos[focus] = editBuf(vals[focus], pos[focus], ev, FIELDS[focus][3])
    end
  end
end

-- ------------------------------------------------------------ main

local function lock()
  items = nil
  shown = false
  screen = "gate"
end

local function ask(text)
  while true do
    put(1, H - 1, pad(" " .. text, W), colors.orange)
    local ev = { os.pullEvent() }
    if watch(ev) then return false end
    if ev[1] == "char" then
      local c = ev[2]:lower()
      if c == "y" then return true elseif c == "n" then return false end
    elseif ev[1] == "key" and ev[2] == keys.escape then
      return false
    end
  end
end

if not vault or not account then
  clear()
  put(2, 3, "The Vault is not available here.", colors.red)
  os.pullEvent("key")
  return
end

password = account.status().password ~= false

local function open()
  local list, why = vault.load()
  if not list then
    clear()
    put(2, 3, "The Vault could not be opened.", colors.red)
    put(2, 5, tostring(why), colors.lightGray)
    put(2, 7, "Press any key.", colors.gray)
    os.pullEvent("key")
    return false
  end
  items = list
  for _, it in ipairs(items) do
    it.title, it.user, it.secret, it.note = it.title or "", it.user or "", it.secret or "", it.note or ""
    it.changed = tonumber(it.changed) or 0
  end
  sortItems()
  sel, top = 1, 0
  screen = "list"
  return true
end

timer = os.startTimer(5)
local viewing = nil

while true do
  if forceLock then forceLock = false lock() end
  if screen == "gate" then
    if not gate() then return end
    if not open() then return end
  end

  if screen == "list" then
    drawList()
  elseif screen == "view" then
    if shown and os.clock() - shownAt > 10 then shown = false end
    drawView(viewing)
  end

  local ev = { os.pullEvent() }
  local e = ev[1]
  if watch(ev) then
    forceLock = false
    lock()
  elseif e == "timer" then
    -- nothing to do
  elseif screen == "list" then
    if e == "key" then
      local k = ev[2]
      if k == keys.up then sel = sel - 1
      elseif k == keys.down then sel = sel + 1
      elseif k == keys.enter and items[sel] then viewing = items[sel] shown = false screen = "view" end
    elseif e == "char" then
      local c = ev[2]:lower()
      if c == "q" then return
      elseif c == "l" then if password then lock() else note("Set a password in Others first", colors.orange) end
      elseif c == "g" then generator(false)
      elseif c == "a" then
        if #items >= 100 then note("The Vault holds 100 items", colors.orange)
        else
          local it = form(nil)
          if it then items[#items + 1] = it if persist() then note("Added " .. it.title, colors.lime) end end
        end
      elseif c == "e" and items[sel] then
        local old = items[sel]
        local it = form(old)
        if it then
          for i, v in ipairs(items) do if v == old then items[i] = it end end
          if persist() then note("Saved", colors.lime) end
        end
      elseif c == "d" and items[sel] then
        drawList()
        if ask("Delete " .. items[sel].title .. "?  Y yes   N no") then
          table.remove(items, sel)
          if persist() then note("Deleted", colors.lightGray) end
        end
      end
    elseif e == "mouse_click" then
      for _, h in ipairs(hits) do
        if ev[4] == h[1] then
          if sel == h[2] and items[sel] then viewing = items[sel] shown = false screen = "view" else sel = h[2] end
        end
      end
    elseif e == "mouse_scroll" then
      sel = sel + ev[2]
    end
  elseif screen == "view" then
    if e == "key" and ev[2] == keys.escape then screen = "list" shown = false
    elseif e == "char" then
      local c = ev[2]:lower()
      if c == "s" then shown = not shown shownAt = os.clock()
      elseif c == "e" then
        local it = form(viewing)
        if it then
          for i, v in ipairs(items) do if v == viewing then items[i] = it end end
          viewing = it
          if persist() then note("Saved", colors.lime) end
        end
      elseif c == "q" then screen = "list" shown = false end
    end
  end
end
