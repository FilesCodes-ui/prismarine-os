--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Disks and ROM. Browse the computer, the ROM and any disk drive.
-- Keys: Up/Down pick, Enter open, Backspace up, V view, C copy, X cut, P paste, D delete,
--       N new folder, R refresh, q quit. Disks are read only in Archive mode.
-- Select many: Ctrl+click toggles one, Shift+click picks a range, Space marks the row,
--       Shift+Up/Down extends, Ctrl+Up/Down moves without changing the marks,
--       Ctrl+A all, Esc clears. C, X, P and D work on every marked item.
--       Ctrl+C, Ctrl+X and Ctrl+V also work.
local W, H = term.getSize()
local cwd = nil         -- nil is the top list: computer, ROM and disks. "" is the computer root.
local items = {}
local sel, top = 1, 0
local clip = nil        -- { cut = bool, paths = { ... } }
local marks = {}        -- set of marked paths in this folder (empty = just the row under the cursor)
local anchor = nil      -- row where a Shift range starts
local down = {}         -- modifier keys held right now
local flash, flashAt = nil, 0
local viewing = nil     -- { name, lines }
local vtop = 0
local wantOpen = false  -- set by a second click on the same row; handled in the loop
local ask = nil         -- { text, fn } or { text, input, fn }

local function note(t) flash, flashAt = t, os.clock() end
local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function refresh()
  items = {}
  for p in pairs(marks) do
    if not fs.exists(p) then marks[p] = nil end
  end
  if cwd == nil then
    items[#items + 1] = { name = "Computer (/)", path = "", dir = true, tag = "" }
    items[#items + 1] = { name = "ROM (/rom)", path = "rom", dir = true, tag = "read only" }
    for _, side in ipairs(peripheral.getNames()) do
      if peripheral.getType(side) == "drive" then
        local ok, present = pcall(peripheral.call, side, "isDiskPresent")
        if ok and present then
          local mp = peripheral.call(side, "getMountPath")
          local label = peripheral.call(side, "getDiskLabel")
          if mp then items[#items + 1] = { name = "Disk " .. side .. " " .. tostring(label or ""), path = mp, dir = true, tag = "/" .. mp, side = side } end
        else
          items[#items + 1] = { name = "Drive " .. side .. " (empty)", path = nil, dir = true, tag = "" }
        end
      end
    end
  else
    local names = fs.list(cwd)
    table.sort(names, function(a, b)
      local da, db = fs.isDir(fs.combine(cwd, a)), fs.isDir(fs.combine(cwd, b))
      if da ~= db then return da end
      return a:lower() < b:lower()
    end)
    for _, n in ipairs(names) do
      local p = fs.combine(cwd, n)
      local d = fs.isDir(p)
      items[#items + 1] = { name = n, path = p, dir = d, tag = d and "" or (fs.getSize(p) .. " B") }
    end
  end
end

local function atTop() return cwd == nil end

local function ctrlHeld() return down[keys.leftCtrl] or down[keys.rightCtrl] or false end
local function shiftHeld() return down[keys.leftShift] or down[keys.rightShift] or false end

local function markCount()
  local n = 0
  for _ in pairs(marks) do n = n + 1 end
  return n
end

local function clearMarks() marks = {} end

-- The rows an action works on: every marked item, or the row under the cursor.
local function selection()
  local out = {}
  if next(marks) then
    for _, it in ipairs(items) do
      if it.path and marks[it.path] then out[#out + 1] = it end
    end
  else
    local it = items[sel]
    if it and it.path then out[1] = it end
  end
  return out
end

-- Mark rows a..b. Replaces the marks unless add is true.
local function markRange(a, b, add)
  if not add then marks = {} end
  if a > b then a, b = b, a end
  for i = math.max(1, a), math.min(#items, b) do
    if items[i].path then marks[items[i].path] = true end
  end
end

-- Toggle one row. The row under the cursor counts as picked when nothing is
-- marked, so it becomes a real mark first and the new row is added to it.
local function toggleMark(idx)
  local it = items[idx]
  if not it or not it.path then return end
  local implicit = markCount() == 0
  if implicit then
    local cur = items[sel]
    if cur and cur.path then marks[cur.path] = true end
    if idx == sel then return end
  end
  if marks[it.path] then marks[it.path] = nil else marks[it.path] = true end
end

local function resetSel()
  sel, top, anchor = 1, 0, 1
  clearMarks()
end

-- Move the cursor. Plain: one row. Shift: extend the marked range. Ctrl (or
-- keep = true, for the wheel): move only, keeping the marks.
local function moveCursor(d, keep)
  local n = #items
  if n == 0 then return end
  local new = math.max(1, math.min(n, sel + d))
  if atTop() then sel = new return end
  if shiftHeld() and not keep then
    anchor = anchor or sel
    sel = new
    markRange(anchor, sel, ctrlHeld())
  elseif ctrlHeld() or keep then
    sel, anchor = new, new
  else
    sel, anchor = new, new
    clearMarks()
  end
end

local function clickRow(idx)
  if shiftHeld() then
    markRange(anchor or sel, idx, ctrlHeld())
    sel = idx
  elseif ctrlHeld() then
    toggleMark(idx)
    sel, anchor = idx, idx
  else
    -- a second plain click on the row that is already the only pick opens it
    local only = markCount() == 0 or (markCount() == 1 and items[idx] and marks[items[idx].path])
    if sel == idx and only then wantOpen = true end
    clearMarks()
    sel, anchor = idx, idx
  end
end

local kit = dofile("/prismarine/ui/kit.lua")
local hits = {}
local function kb(n)
  if n >= 1048576 then return ("%.1f MB"):format(n / 1048576) end
  if n >= 1024 then return ("%.1f KB"):format(n / 1024) end
  return n .. " B"
end
local function space(path)
  local okc, cap = pcall(fs.getCapacity, path)
  local okf, free = pcall(fs.getFreeSpace, path)
  if okc and okf and type(cap) == "number" and cap > 0 then return cap, free end
  return nil
end

local function draw()
  W, H = term.getSize()
  hits = {}
  local s = kit.scene()
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  if viewing then
    s:header("View", viewing.name, #viewing.lines .. " lines")
    local ch = H - 4
    s:card(2, 3, W - 2, ch, gray)
    local area = ch - 2
    for i = 1, area do
      local l = viewing.lines[vtop + i]
      if l then s:text(3, 3 + i, kit.fit(l, W - 5), text, gray) end
    end
    s:scroll(W - 1, 4, area, #viewing.lines, vtop, area)
    s:hints(H - 1, { { "Up/Down", "scroll" }, { "PgUp/PgDn", "page" }, { "Esc", "back" } })
    s:flush()
    return
  end
  local mc = markCount()
  s:header("Disks", atTop() and "Computer, ROM and drives" or ("/" .. cwd),
    mc > 0 and (mc .. " selected") or (#items .. (#items == 1 and " item" or " items")))
  if sel > #items then sel = #items end
  if sel < 1 then sel = 1 end
  local ch = H - 5
  if atTop() then
    -- volume cards, 5 rows each
    local per = math.max(1, math.floor((ch + 1) / 6))
    if sel - 1 < top then top = sel - 1 end
    if sel > top + per then top = sel - per end
    if top < 0 then top = 0 end
    for i = 1, per do
      local it = items[top + i]
      if it then
        local idx = top + i
        local y = 3 + (i - 1) * 6
        local on = idx == sel
        s:card(2, y, W - 3, 5, gray, on and kit.c("line") or nil)
        local tagRoom = (it.tag ~= "") and (#it.tag + 4) or 0
        local narrow = W - 8 - tagRoom < 12
        s:text(4, y + 1, kit.fit(it.name, W - 8 - (narrow and 0 or tagRoom)), on and kit.c("line") or text, gray)
        if it.tag ~= "" and not narrow then s:badge(W - #it.tag - 5, y + 1, it.tag, it.tag == "read only" and "warn" or "info") end
        local cap, free = nil, nil
        if it.path then cap, free = space(it.path) end
        if cap then
          s:meter(4, y + 2, W - 8, (cap - free) / cap, kit.c("line"), kit.c("bg"))
          local r = kb(free) .. " free"
          if W - 8 >= #r + 14 then s:text(4, y + 3, kb(cap - free) .. " used", text, gray) end
          s:text(W - 3 - #r, y + 3, r, hint, gray)
        elseif not it.path then
          s:text(4, y + 2, "No disk inserted", hint, gray)
        else
          s:text(4, y + 2, kit.fit(narrow and it.tag or "Size not available", W - 8), hint, gray)
        end
        hits[#hits + 1] = { 2, y, W - 2, y + 4, function() if sel == idx then wantOpen = true end sel = idx end }
      end
    end
    s:scroll(W - 1, 3, ch, #items, top, per)
  else
    s:card(2, 3, W - 2, ch, gray)
    local area = ch - 2
    if sel - 1 < top then top = sel - 1 end
    if sel > top + area then top = sel - area end
    if top < 0 then top = 0 end
    local inClip = {}
    if clip then for _, cp in ipairs(clip.paths) do inClip[cp] = true end end
    for i = 1, area do
      local it = items[top + i]
      if it then
        local idx = top + i
        local marked = marks[it.path] and true or false
        local lit = marked or (idx == sel and mc == 0)          -- drawn as picked
        local cursorOnly = idx == sel and not lit               -- cursor row while others are marked
        local isCut = clip and clip.cut and inClip[it.path]
        if cursorOnly then s:card(3, 3 + i, W - 4, 1, kit.c("hdr")) end
        s:row(3, 3 + i, W - 4, (it.dir and "> " or "  ") .. it.name .. (it.dir and "/" or ""), lit,
          { right = isCut and "cut" or (it.tag ~= "" and it.tag or nil),
            fg = cursorOnly and kit.c("barText") or (it.dir and kit.c("info") or nil),
            bg = cursorOnly and kit.c("hdr") or nil, dim = isCut })
        hits[#hits + 1] = { 3, 3 + i, W - 2, 3 + i, function() clickRow(idx) end }
      end
    end
    s:scroll(W - 1, 4, area, #items, top, area)
    if #items == 0 then s:empty(2, 3, W - 2, ch, { "This folder is empty", "Press N to make a folder." }) end
  end
  if ask then
    local q = ask.text .. (ask.input and (" " .. ask.input .. "_") or "  Y yes   N no")
    s:card(2, H - 2, W - 2, 1, kit.c("warn"))
    s:text(3, H - 2, kit.fit(q, W - 4), colors.black, kit.c("warn"))
  elseif flash and os.clock() - flashAt < 5 then
    s:status(H - 2, flash, "warn")
  end
  s:hints(H - 1, atTop()
    and { { "Enter", "open" }, { "R", "refresh" }, { "Q", "close" } }
    or { { "Enter", "open" }, { "Space", "mark" }, { "C", "copy" }, { "X", "cut" }, { "P", "paste" },
         { "D", "del" }, { "Bksp", "up" }, { "N", "new" }, { "Q", "quit" } }, 2)
  s:flush()
end

local function tryfs(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then note(tostring(err):gsub("^.-:%d+: ", ""):sub(1, W - 2)) return false end
  return true
end

local function openSel()
  local it = items[sel]
  if not it then return end
  if it.dir then
    if it.path == nil then note("No disk in that drive.") return end
    cwd = it.path
    resetSel()
    refresh()
  else
    local h = fs.open(it.path, "r")
    if not h then note("Cannot read that file.") return end
    local data = h.readAll()
    h.close()
    viewing = { name = it.name, lines = {} }
    for line in ((data or "") .. "\n"):gmatch("(.-)\n") do viewing.lines[#viewing.lines + 1] = line end
    vtop = 0
  end
end

local function cleanErr(e)
  local msg = tostring(e):gsub("^.-:%d+: ", "")
  return msg
end

local function countWord(n) return n == 1 and "1 item" or (n .. " items") end

-- Copy or cut the selection onto the clipboard.
local function toClip(cut)
  if cwd == nil then return end
  local list = selection()
  if #list == 0 then return end
  local paths, locked = {}, 0
  for _, it in ipairs(list) do
    if cut and fs.isReadOnly(it.path) then locked = locked + 1 else paths[#paths + 1] = it.path end
  end
  if #paths == 0 then note("Read only. That cannot be cut.") return end
  clip = { cut = cut, paths = paths }
  local what = #paths == 1 and fs.getName(paths[1]) or countWord(#paths)
  local extra = locked > 0 and (" (" .. locked .. " read only left out)") or ""
  note((cut and "Cut " or "Copied ") .. what .. extra .. ". Open a folder, press P.")
end

-- Move that also works between drives: copy, then delete the original.
local function moveTo(src, dst)
  local ok, err = pcall(fs.move, src, dst)
  if ok then return end
  if fs.exists(dst) or not fs.exists(src) then error(err, 0) end
  local cok, cerr = pcall(fs.copy, src, dst)
  if not cok then error(cerr, 0) end
  local dok, derr = pcall(fs.delete, src)
  if not dok then
    pcall(fs.delete, dst)   -- do not leave a second copy behind
    error(derr, 0)
  end
end

local function insideSelf(src, dst)
  return dst == src or dst:sub(1, #src + 1) == src .. "/"
end

-- Paste the clipboard into the open folder. Items that cannot go are skipped
-- and counted; the rest still go.
local function pasteHere()
  if cwd == nil then return end
  if not clip or #clip.paths == 0 then note("Nothing to paste.") return end
  local done, exists, loop, missing, failed, firstErr = 0, 0, 0, 0, 0, nil
  local wasCut = clip.cut
  local left = {}
  for _, src in ipairs(clip.paths) do
    local dst = fs.combine(cwd, fs.getName(src))
    if not fs.exists(src) then
      missing = missing + 1
    elseif fs.isDir(src) and insideSelf(src, dst) then
      loop = loop + 1
      left[#left + 1] = src
    elseif dst == src or fs.exists(dst) then
      exists = exists + 1
      left[#left + 1] = src
    else
      local ok, err = pcall(wasCut and moveTo or fs.copy, src, dst)
      if ok then
        done = done + 1
      else
        failed = failed + 1
        firstErr = firstErr or cleanErr(err)
        left[#left + 1] = src
      end
    end
  end
  if wasCut then
    if #left == 0 then clip = nil else clip.paths = left end
  end
  local bits = {}
  if exists > 0 then bits[#bits + 1] = exists .. " name exists" end
  if loop > 0 then bits[#bits + 1] = loop .. " inside itself" end
  if missing > 0 then bits[#bits + 1] = missing .. " gone" end
  if failed > 0 then bits[#bits + 1] = failed .. " failed: " .. firstErr end
  local verb = wasCut and "Moved " or "Copied "
  local msg
  if done > 0 then msg = verb .. countWord(done) .. "." else msg = "Nothing pasted." end
  if #bits > 0 then msg = msg .. " " .. table.concat(bits, ", ") .. "." end
  note(msg:sub(1, W - 2))
end

local function askDelete()
  if cwd == nil then return end
  local list = selection()
  if #list == 0 then return end
  local paths = {}
  for _, it in ipairs(list) do paths[#paths + 1] = it.path end
  local what = #list == 1 and list[1].name or countWord(#list)
  ask = { text = "Delete " .. what .. "?", fn = function()
    local n, bad, firstErr = 0, 0, nil
    for _, p in ipairs(paths) do
      local ok, err = pcall(fs.delete, p)
      if ok then n = n + 1 else bad = bad + 1 firstErr = firstErr or cleanErr(err) end
    end
    clearMarks()
    local msg = "Deleted " .. countWord(n) .. "."
    if bad > 0 then msg = msg .. " " .. bad .. " failed: " .. firstErr end
    note(msg:sub(1, W - 2))
  end }
end

refresh()
draw()
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  -- Track Ctrl and Shift. Mouse clicks do not say which keys are held.
  if e == "key" then down[ev[2]] = true
  elseif e == "key_up" then down[ev[2]] = nil
  elseif e == "char" and ctrlHeld() then
    -- A letter cannot arrive while Ctrl is really held, so the release was
    -- missed (Ctrl let go in another app). Forget it.
    down[keys.leftCtrl], down[keys.rightCtrl] = nil, nil
  end
  if ask then
    if ask.input then
      if e == "char" then ask.input = ask.input .. ev[2]
      elseif e == "key" and ev[2] == keys.backspace then ask.input = ask.input:sub(1, -2)
      elseif e == "key" and ev[2] == keys.enter then local a = ask ask = nil if a.input ~= "" then a.fn(a.input) refresh() end
      elseif e == "key" and ev[2] == keys.escape then ask = nil end
    elseif e == "char" then
      local c = ev[2]:lower()
      local a = ask
      ask = nil
      if c == "y" then a.fn() refresh() end
    end
  elseif viewing then
    if e == "key" then
      if ev[2] == keys.backspace or ev[2] == keys.escape then viewing = nil
      elseif ev[2] == keys.down then vtop = math.min(math.max(0, #viewing.lines - (H - 1)), vtop + 1)
      elseif ev[2] == keys.up then vtop = math.max(0, vtop - 1)
      elseif ev[2] == keys.pageDown then vtop = math.min(math.max(0, #viewing.lines - (H - 1)), vtop + 10)
      elseif ev[2] == keys.pageUp then vtop = math.max(0, vtop - 10) end
    elseif e == "mouse_scroll" then
      vtop = math.max(0, math.min(math.max(0, #viewing.lines - (H - 1)), vtop + ev[2] * 3))
    end
  elseif e == "key" then
    local k = ev[2]
    local ctrl = ctrlHeld()
    if ctrl and cwd ~= nil and k == keys.a then
      markRange(1, #items)
    elseif ctrl and cwd ~= nil and k == keys.c then toClip(false)
    elseif ctrl and cwd ~= nil and k == keys.x then toClip(true)
    elseif ctrl and cwd ~= nil and k == keys.v then pasteHere() refresh()
    elseif k == keys.escape then clearMarks()
    elseif k == keys.up then moveCursor(-1)
    elseif k == keys.down then moveCursor(1)
    elseif k == keys.enter then openSel()
    elseif k == keys.backspace and not atTop() then
      if cwd == "" or cwd == "rom" or fs.getDir(cwd) == ".." then cwd = nil else cwd = fs.getDir(cwd) end
      resetSel()
      refresh()
    end
  elseif e == "char" then
    local c = ev[2]:lower()
    local it = items[sel]
    if c == "q" then return
    elseif c == "r" then refresh()
    elseif c == "v" and it and not it.dir then openSel()
    elseif c == "c" then toClip(false)
    elseif c == "x" then toClip(true)
    elseif c == "p" then pasteHere() refresh()
    elseif c == "d" then askDelete()
    elseif c == " " and cwd ~= nil then toggleMark(sel)
    elseif c == "n" and cwd ~= nil then
      ask = { text = "New folder:", input = "", fn = function(n) if tryfs(fs.makeDir, fs.combine(cwd, n)) then note("Created.") end end }
    end
  elseif e == "mouse_click" then
    for _, h in ipairs(hits) do
      if ev[3] >= h[1] and ev[3] <= h[3] and ev[4] >= h[2] and ev[4] <= h[4] then h[5]() break end
    end
    if wantOpen then wantOpen = false openSel() end
  elseif e == "mouse_scroll" then
    moveCursor(ev[2], true)   -- the wheel moves the cursor and keeps the marks
  end
  draw()
end
