--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Programs. Runs the programs in /programs.
-- In Archive mode a program runs only after the Archive approves its exact hash.
-- Keys: Up/Down pick, Enter run, A ask the Archive, R refresh, q quit.
local api = prismarine
local launch, tools, net = api.launch, api.tools, api.net
local W, H = term.getSize()
local DIR = "/programs"
local sel, top = 1, 0
local flash, flashAt = nil, 0
local list = {}

local function note(t) flash, flashAt = t, os.clock() end

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function refresh()
  list = {}
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  for _, n in ipairs(fs.list(DIR)) do
    local p = fs.combine(DIR, n)
    if not fs.isDir(p) and n:match("%.lua$") then
      local h = fs.open(p, "rb")
      local data = h and h.readAll() or ""
      if h then h.close() end
      list[#list + 1] = { name = n:gsub("%.lua$", ""), path = "/" .. p, size = #data, hash = tools and tools.sha256(data) or "?", data = data }
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
end

local hits = {}
local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  hits = {}
  put(1, 1, (" Programs   (" .. DIR .. ")" .. string.rep(" ", W)):sub(1, W), colors.white, colors.gray)
  local area = H - 4
  if sel > #list then sel = #list end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + area then top = sel - area end
  for i = 1, area do
    local p = list[top + i]
    if p then
      local on = (top + i == sel)
      put(1, 1 + i, (" " .. p.name .. string.rep(" ", W)):sub(1, W), on and colors.black or colors.white, on and colors.cyan or colors.black)
      put(W - 12, 1 + i, ("%6d B"):format(p.size), on and colors.black or colors.gray, on and colors.cyan or colors.black)
      local idx = top + i
      hits[#hits + 1] = { 1, 1 + i, W, 1 + i, function() sel = idx end }
    end
  end
  if #list == 0 then put(2, 3, "No programs yet. Put .lua files in " .. DIR, colors.gray) end
  local p = list[sel]
  if p then put(1, H - 2, (" sha256 " .. p.hash:sub(1, 32)):sub(1, W), colors.gray) end
  put(1, H - 1, " Enter: run   A: ask Archive to approve   R: refresh", colors.cyan)
  if flash and os.clock() - flashAt < 5 then put(1, H, (" " .. flash .. string.rep(" ", W)):sub(1, W), colors.orange) end
end

local function run()
  local p = list[sel]
  if not p then return end
  if not launch then note("Launching is not available.") return end
  local pid, why = launch.run(p.path, p.name)
  if pid then note("Started " .. p.name) else note(why or "Blocked") end
end

local function ask()
  local p = list[sel]
  if not p then return end
  if not net then note("No network access.") return end
  local ok, why = net.requestApproval(p.name, p.data)
  note(ok and "Sent to the Archive for review." or (why or "Could not send"))
end

refresh()
draw()
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "key" then
    local k = ev[2]
    if k == keys.up then sel = sel - 1
    elseif k == keys.down then sel = sel + 1
    elseif k == keys.enter then run() end
  elseif ev[1] == "char" then
    local c = ev[2]:lower()
    if c == "q" then return
    elseif c == "r" then refresh()
    elseif c == "a" then ask() end
  elseif ev[1] == "mouse_click" then
    for _, h in ipairs(hits) do
      if ev[3] >= h[1] and ev[3] <= h[3] and ev[4] >= h[2] and ev[4] <= h[4] then h[5]() break end
    end
  end
  draw()
end
