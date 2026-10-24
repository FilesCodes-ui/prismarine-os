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
-- Keys: Up/Down pick, Enter open, Backspace up, V view, C copy, P paste, D delete,
--       N new folder, R refresh, q quit. Disks are read only in Archive mode.
local W, H = term.getSize()
local cwd = nil         -- nil is the top list: computer, ROM and disks. "" is the computer root.
local items = {}
local sel, top = 1, 0
local clip = nil
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
  s:header("Disks", atTop() and "Computer, ROM and drives" or ("/" .. cwd), #items .. (#items == 1 and " item" or " items"))
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
    for i = 1, area do
      local it = items[top + i]
      if it then
        local idx = top + i
        s:row(3, 3 + i, W - 4, (it.dir and "> " or "  ") .. it.name .. (it.dir and "/" or ""), idx == sel,
          { right = it.tag ~= "" and it.tag or nil, fg = it.dir and kit.c("info") or nil })
        hits[#hits + 1] = { 3, 3 + i, W - 2, 3 + i, function() if sel == idx then wantOpen = true end sel = idx end }
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
    or { { "Enter", "open" }, { "Bksp", "up" }, { "V", "view" }, { "C", "copy" }, { "P", "paste" }, { "D", "delete" }, { "N", "folder" }, { "Q", "close" } }, 1)
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
    sel, top = 1, 0
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

local function copyTo(src, dst)
  if fs.exists(dst) then note("That name already exists here.") return end
  if tryfs(fs.copy, src, dst) then note("Copied.") end
end

refresh()
draw()
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
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
    if k == keys.up then sel = sel - 1
    elseif k == keys.down then sel = sel + 1
    elseif k == keys.enter then openSel()
    elseif k == keys.backspace and not atTop() then
      if cwd == "" or cwd == "rom" or fs.getDir(cwd) == ".." then cwd = nil else cwd = fs.getDir(cwd) end
      sel, top = 1, 0
      refresh()
    end
  elseif e == "char" then
    local c = ev[2]:lower()
    local it = items[sel]
    if c == "q" then return
    elseif c == "r" then refresh()
    elseif c == "v" and it and not it.dir then openSel()
    elseif c == "c" and it and it.path and cwd ~= nil then clip = it.path note("Copied to clipboard: " .. it.name)
    elseif c == "p" and clip and cwd ~= nil then copyTo(clip, fs.combine(cwd, fs.getName(clip))) refresh()
    elseif c == "d" and it and it.path and cwd ~= nil then
      ask = { text = "Delete " .. it.name .. "?", fn = function() if tryfs(fs.delete, it.path) then note("Deleted.") end end }
    elseif c == "n" and cwd ~= nil then
      ask = { text = "New folder:", input = "", fn = function(n) if tryfs(fs.makeDir, fs.combine(cwd, n)) then note("Created.") end end }
    end
  elseif e == "mouse_click" then
    for _, h in ipairs(hits) do
      if ev[3] >= h[1] and ev[3] <= h[3] and ev[4] >= h[2] and ev[4] <= h[4] then h[5]() break end
    end
    if wantOpen then wantOpen = false openSel() end
  elseif e == "mouse_scroll" then
    sel = sel + ev[2]
  end
  draw()
end
