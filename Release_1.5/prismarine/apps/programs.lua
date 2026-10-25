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

local kit = dofile("/prismarine/ui/kit.lua")
local run, ask
local hits = {}
local function hit(x, y, w, fn) hits[#hits + 1] = { x, y, x + w - 1, y, fn } end

local function draw()
  W, H = term.getSize()
  hits = {}
  local s = kit.scene()
  s:header("Programs", DIR, #list .. (#list == 1 and " program" or " programs"))
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  local narrow = W < 40
  local lw = narrow and (W - 2) or math.min(26, math.floor(W * 0.42))
  local ch = H - 5
  local area = ch - 2
  if sel > #list then sel = #list end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + area then top = sel - area end
  if top < 0 then top = 0 end
  s:card(2, 3, lw, ch, gray)
  if not narrow then s:card(lw + 3, 3, W - lw - 3, ch, gray) end
  if #list == 0 then
    s:empty(2, 3, lw, ch, { "No programs yet", "Put .lua files", "in " .. DIR, "then press R." })
  end
  for i = 1, area do
    local p = list[top + i]
    if p then
      local idx = top + i
      s:row(3, 3 + i, lw - 2, p.name, idx == sel, { right = ("%.1f KB"):format(p.size / 1024) })
      hit(3, 3 + i, lw - 2, function() sel = idx end)
    end
  end
  s:scroll(narrow and (W - 1) or (lw + 1), 4, area, #list, top, area)
  local p = list[sel]
  local dx, dw = lw + 5, W - lw - 7
  if narrow then
    -- list only on a small screen
  elseif p then
    s:text(dx, 4, kit.fit(p.name, dw), text, gray)
    s:text(dx, 5, ("%d bytes"):format(p.size), hint, gray)
    s:rule(dx, 6, dw, kit.c("hdr"))
    s:text(dx, 7, "File", hint, gray)
    s:text(dx + 6, 7, kit.fit(p.path, dw - 6), text, gray)
    s:text(dx, 8, "Hash", hint, gray)
    s:text(dx + 6, 8, kit.fit(p.hash:sub(1, 16), dw - 6), text, gray)
    s:text(dx + 6, 9, kit.fit(p.hash:sub(17, 32), dw - 6), text, gray)
    local by = 3 + ch - 2
    local nx = s:pill(dx, by, "Run", kit.c("ok"), colors.black)
    hit(dx, by, 5, run)
    local ax, ay = nx, by
    if dw < 19 then ax, ay = dx, by - 1 end
    s:pill(ax, ay, "Ask Archive", kit.c("hdr"), kit.c("barText"))
    hit(ax, ay, 13, ask)
  else
    s:empty(lw + 3, 3, W - lw - 3, ch, { "Nothing selected" })
  end
  if flash and os.clock() - flashAt < 5 then
    s:status(2, flash, "warn")
  end
  s:hints(H - 1, { { "Enter", "run" }, { "A", "ask Archive" }, { "R", "refresh" }, { "Q", "quit" } })
  s:flush()
end

function run()
  local p = list[sel]
  if not p then return end
  if not launch then note("Launching is not available.") return end
  local pid, why, existed = launch.run(p.path, p.name)
  if existed then note(p.name .. " is already open.")
  elseif pid then note("Started " .. p.name)
  else note(why or "Blocked") end
end

function ask()
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
