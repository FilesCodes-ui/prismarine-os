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

local kit = dofile("/prismarine/ui/kit.lua")
local S = nil
local function put(x, y, str, fg, bg)
  if S and not S.done then S:text(x, y, str, fg, bg) return end
  kit.put(x, y, str, fg, bg or colors.black)
end
local function pad(str, n)
  if #str > n then return str:sub(1, n) end
  return str .. string.rep(" ", n - #str)
end
local function note(t, c)
  flash, flashColor, flashAt = t, c or colors.lightGray, os.clock()
  os.startTimer(6)
end
local function bar(text, right)
  S:header("Vault", text, right)
end
local function footer(a, b)
  if flash and os.clock() - flashAt < 6 then
    local bad = (flashColor == colors.red or flashColor == colors.orange)
    S:status(2, flash, bad and "err" or "ok")
    S:hintText(H - 2, (a or "") .. "   " .. (b or ""), 2)
  else
    S:hintText(H - 2, (a or "") .. "   " .. (b or ""), 2)
  end
end
local function clear()
  term.setCursorBlink(false)
  W, H = term.getSize()
  S = kit.scene()
  hits = {}
end
local function present()
  S:flush()
  S.done = true
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
    local gray = kit.c("bar")
    S:card(2, 3, W - 2, 12, gray)
    S:text(4, 4, "Length", kit.c("hint"), gray)
    S:meter(14, 4, W - 22, (len - 8) / 24, kit.c("line"), kit.c("bg"))
    S:text(W - 7, 4, tostring(len), kit.c("barText"), gray)
    S:text(4, 6, "Symbols", kit.c("hint"), gray)
    S:switch(14, 6, symbols)
    S:card(4, 9, W - 6, 3, kit.c("bg"))
    S:text(6, 10, kit.fit(pw, W - 10), kit.c("ok"), kit.c("bg"))
    S:text(4, 13, "Made with strong random bytes. Nothing is saved.", kit.c("hint"), gray)
    footer("R: new one   S: symbols   Left/Right: length   " .. (canUse and "Enter: use it   " or "") .. "Esc: back")
    present()
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
    local gray = kit.c("bar")
    S:card(math.floor(W / 2) - 16, 4, 34, 9, gray)
    local cx = math.floor(W / 2) - 14
    S:text(cx, 5, "Vault is locked", kit.c("barText"), gray)
    S:text(cx, 6, "Enter your password to open it.", kit.c("hint"), gray)
    S:field(cx, 8, 30, string.rep("*", #buf), true, false, "password")
    if busy then S:text(cx, 10, "Checking...", kit.c("info"), gray)
    elseif msg then S:text(cx, 10, msg, kit.c("err"), gray) end
    footer("Enter: open   Esc: close")
    present()
    term.setCursorPos(math.min(W, cx + 1 + #buf), 8)
    term.setCursorBlink(false)
    local ev = { os.pullEvent() }
    watch(ev)
    forceLock = false
    if ev[1] == "key" and ev[2] == keys.escape then return false
    elseif ev[1] == "key" and ev[2] == keys.enter then
      if #buf > 0 then
        busy = true
        clear()
        bar("Locked")
        S:text(math.floor(W / 2) - 5, 9, "Checking...", kit.c("info"), colors.black)
        present()
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
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  local narrow = W < 40
  local lw = narrow and (W - 2) or math.min(26, math.floor(W * 0.45))
  local ch = H - 5
  local rows = ch - 2
  if sel > #items then sel = #items end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + rows then top = sel - rows end
  if top < 0 then top = 0 end
  S:card(2, 3, lw, ch, gray)
  if not narrow then S:card(lw + 3, 3, W - lw - 3, ch, gray) end
  for i = 1, rows do
    local it = items[top + i]
    if it then
      local on = top + i == sel
      S:row(3, 3 + i, lw - 2, it.title, on)
      hits[#hits + 1] = { 3 + i, top + i }
    end
  end
  S:scroll(narrow and (W - 1) or (lw + 1), 4, rows, #items, top, rows)
  if #items == 0 then
    S:empty(2, 3, lw, ch, { "Nothing here", "Press A to add." })
  end
  local it = items[sel]
  local dx, dw = lw + 5, W - lw - 7
  if it and not narrow then
    S:text(dx, 4, kit.fit(it.title, dw), text, gray)
    S:rule(dx, 5, dw, kit.c("hdr"))
    S:text(dx, 6, "User", hint, gray)
    S:text(dx + 8, 6, kit.fit(it.user == "" and "-" or it.user, dw - 8), text, gray)
    S:text(dx, 7, "Secret", hint, gray)
    S:text(dx + 8, 7, it.secret == "" and "-" or string.rep("*", math.min(#it.secret, dw - 8, 12)), text, gray)
    S:text(dx, 8, "Note", hint, gray)
    S:text(dx + 8, 8, kit.fit(it.note == "" and "-" or it.note, dw - 8), text, gray)
    S:text(dx, 3 + ch - 2, "Enter opens this item", hint, gray)
  end
  if not password and not (flash and os.clock() - flashAt < 6) then
    S:status(2, "No password set. Items are hidden, not locked.", "warn")
  end
  footer("Enter open   A add   E edit   D delete   G make password   L lock   Q quit")
  present()
end

local function drawView(it)
  clear()
  bar(it.title)
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  S:card(2, 3, W - 2, H - 5, gray)
  local function field(y, label, value, color)
    S:text(4, y, label:upper(), hint, gray)
    S:text(4, y + 1, kit.fit(value == "" and "-" or value, W - 8), color or text, gray)
  end
  field(4, "User", it.user)
  local secret = it.secret
  if secret == "" then
    field(7, "Secret", "")
  elseif shown then
    field(7, "Secret", secret, kit.c("ok"))
  else
    field(7, "Secret", string.rep("*", math.min(#secret, W - 8)), text)
  end
  field(10, "Note", it.note)
  footer("S: " .. (shown and "hide" or "show") .. " secret   E: edit   Esc: back", shown and "The secret hides itself in 10 seconds" or "")
  present()
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
    local gray = kit.c("bar")
    S:card(2, 3, W - 2, H - 5, gray)
    for i, f in ipairs(FIELDS) do
      local y = 4 + (i - 1) * 3
      S:text(4, y, f[2], i == focus and kit.c("line") or kit.c("hint"), gray)
      local v = vals[i]
      local room = W - 8
      local from = 1
      if i == focus and pos[i] > room then from = pos[i] - room + 1 end
      S:field(4, y + 1, W - 6, v:sub(from, from + room - 1), i == focus, false)
      hits[#hits + 1] = { y + 1, i }
    end
    footer("Tab or Enter: next   Ctrl+S: save   Esc: cancel", flash and "" or "Title is required")
    present()
    do
      local y = 4 + (focus - 1) * 3 + 1
      local room = W - 8
      local from = (pos[focus] > room) and (pos[focus] - room + 1) or 1
      term.setCursorPos(math.min(W, 5 + pos[focus] - from), y)
      term.setCursorBlink(false)
    end
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
    kit.put(2, H - 2, pad(" " .. text, W - 2), colors.black, kit.c("warn"))
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
  S:text(2, 3, "The Vault is not available here.", kit.c("err"), colors.black)
  present()
  os.pullEvent("key")
  return
end

password = account.status().password ~= false

local function open()
  local list, why = vault.load()
  if not list then
    clear()
    S:text(2, 3, "The Vault could not be opened.", kit.c("err"), colors.black)
    S:text(2, 5, tostring(why), kit.c("hint"), colors.black)
    S:text(2, 7, "Press any key.", kit.c("hint"), colors.black)
    present()
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
