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

local hits = {}
local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  hits = {}
  if viewing then
    put(1, 1, (" " .. viewing.name .. "   Backspace: close" .. string.rep(" ", W)):sub(1, W), colors.white, colors.gray)
    for i = 1, H - 1 do
      local l = viewing.lines[vtop + i]
      if l then put(1, 1 + i, l:sub(1, W), colors.white) end
    end
    return
  end
  put(1, 1, (" " .. (atTop() and "Disks and ROM" or ("/" .. cwd)) .. string.rep(" ", W)):sub(1, W), colors.white, colors.gray)
  local area = H - 3
  if sel > #items then sel = #items end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + area then top = sel - area end
  for i = 1, area do
    local it = items[top + i]
    if it then
      local on = (top + i == sel)
      local bg = on and colors.cyan or colors.black
      put(1, 1 + i, string.rep(" ", W), colors.white, bg)
      put(2, 1 + i, ((it.dir and "[D] " or "    ") .. it.name):sub(1, W - 16), on and colors.black or (it.dir and colors.lightBlue or colors.white), bg)
      put(W - 13, 1 + i, (it.tag or ""):sub(1, 13), on and colors.black or colors.gray, bg)
      local idx = top + i
      hits[#hits + 1] = { 1, 1 + i, W, 1 + i, function() if sel == idx then os.queueEvent("pm_open") end sel = idx end }
    end
  end
  put(1, H - 1, " Enter open  V view  C copy  P paste  D delete  N folder", colors.cyan)
  if ask then
    put(1, H - 2, (" " .. ask.text .. (ask.input and (" " .. ask.input) or " [Y/N]") .. string.rep(" ", W)):sub(1, W), colors.black, colors.yellow)
  elseif flash and os.clock() - flashAt < 5 then
    put(1, H, (" " .. flash .. string.rep(" ", W)):sub(1, W), colors.orange)
  end
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
  elseif e == "pm_open" then openSel()
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
  elseif e == "mouse_scroll" then
    sel = sel + ev[2]
  end
  draw()
end
