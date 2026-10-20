-- Prismarine Settings. Runs sandboxed and talks to the OS through prismarine.ui.
-- Mouse: click a page on the left, click a row on the right.
-- Keys:  Up/Down row, Left/Right change a value, Enter or Space toggle,
--        Tab or PageUp/PageDown change page, q quits.
local api = prismarine
local ui = api.ui
local W, H = term.getSize()

local C = {
  bg = colors.black, side = colors.gray, sideText = colors.lightGray,
  sel = colors.blue, selText = colors.white, title = colors.cyan,
  text = colors.white, dim = colors.lightGray, on = colors.lime, off = colors.gray,
  line = colors.gray, hot = colors.cyan, warn = colors.orange,
}

if not ui then
  term.clear()
  term.setCursorPos(1, 1)
  print("The UI service is not running.")
  print("Press any key to close.")
  os.pullEvent("key")
  return
end

local FPS = { 6, 12, 20, 30 }
local page, row = 1, 1
local flash, flashUntil = nil, 0
local hits = {}

local function cycle(list, cur, step)
  local at = 1
  for i, v in ipairs(list) do if v == cur then at = i end end
  return list[(at - 1 + step) % #list + 1]
end

-- Row kinds: toggle, choice, action, info, gap.
local function pages()
  local s = ui.get()
  local up = math.floor(os.clock())
  return {
    { name = "Display", rows = {
      { kind = "choice", label = "Theme", key = "theme", value = s.theme, list = ui.themes,
        help = "Colors for bars, menus and toasts. Sets the logo color too." },
      { kind = "toggle", label = "Animations", key = "anim", value = s.anim,
        help = "Slides, fades and the moving logo." },
      { kind = "toggle", label = "Dashboard haze", key = "haze", value = s.haze,
        help = "Dark glow at the top and bottom of Home." },
      { kind = "choice", label = "Frame rate", key = "fps", value = s.fps, list = FPS, suffix = " fps",
        help = "Higher is smoother. Lower saves work." },
      { kind = "choice", label = "Logo color", key = "logoColor", value = s.logoColor, list = ui.logoColors,
        help = "Pick a preset. Rainbow cycles." },
    } },
    { name = "Alerts", rows = {
      { kind = "toggle", label = "Do not disturb", key = "dnd", value = s.dnd,
        help = "Hides toasts. The sidebar still keeps them." },
      { kind = "choice", label = "Toast side", key = "toastSide", value = s.toastSide, list = { "left", "right" },
        help = "Which edge toasts slide in from." },
      { kind = "toggle", label = "Show message text", key = "showText", value = s.showText,
        help = "Show the body in a toast, not only the title." },
      { kind = "gap" },
      { kind = "action", label = "Send test toast", id = "test",
        help = "Posts one toast so you can see your settings." },
      { kind = "action", label = "Clear notification list (" .. ui.notificationCount() .. ")", id = "clear",
        help = "Empties the sidebar history." },
    } },
    { name = "Controls", rows = {
      { kind = "info", label = "Left Alt", text = "Apps menu" },
      { kind = "info", label = "Right Alt", text = "Switch between apps" },
      { kind = "info", label = "F8", text = "Notification sidebar" },
      { kind = "info", label = "F12", text = "Quit Prismarine" },
      { kind = "gap" },
      { kind = "info", label = "[H]", text = "Top bar: go Home" },
      { kind = "info", label = "Badge", text = "Top bar: open notifications" },
      { kind = "info", label = "Menus", text = "Press, drag, release to pick" },
      { kind = "info", label = "Wheel", text = "Scroll menus and the sidebar" },
    } },
    { name = "System", rows = {
      { kind = "info", label = "Prismarine", text = api.version or "?" },
      { kind = "info", label = "Graphics", text = s.graphics and "Pixelbox" or "Plain text" },
      { kind = "info", label = "Screen", text = s.width .. " x " .. s.height .. " cells" },
      { kind = "info", label = "Computer", text = "#" .. tostring(os.getComputerID()) .. " " .. tostring(os.getComputerLabel() or "") },
      { kind = "info", label = "Uptime", text = math.floor(os.clock() / 60) .. " min" },
      { kind = "gap" },
      { kind = "action", label = "Reset all settings", id = "reset", danger = true,
        help = "Put every setting back to its default." },
    } },
  }
end

local function selectable(r) return r.kind == "toggle" or r.kind == "choice" or r.kind == "action" end

local function fixRow(p)
  local rows = p.rows
  if not selectable(rows[row] or {}) then
    for i, r in ipairs(rows) do
      if selectable(r) then row = i return end
    end
    row = 0
  end
end

local function say(msg)
  flash, flashUntil = msg, os.clock() + 2.5
end

local function change(r, step)
  if r.kind == "toggle" then
    ui.set(r.key, not r.value)
  elseif r.kind == "choice" then
    local nv = cycle(r.list, r.value, step)
    ui.set(r.key, nv)
  elseif r.kind == "action" then
    if r.id == "test" then
      api.notify("Settings", "This is a test toast.", "info")
      say("Toast sent.")
    elseif r.id == "clear" then
      ui.clearNotifications()
      say("Notification list cleared.")
    elseif r.id == "reset" then
      ui.reset()
      say("Settings reset.")
    end
  end
end

local SIDE = 13

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or C.text)
  term.setBackgroundColor(bg or C.bg)
  term.write(s)
end

local function fill(x, y, w, bg)
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg)
  term.write((" "):rep(w))
end

local function draw()
  local ps = pages()
  local p = ps[page]
  fixRow(p)
  hits = {}
  term.setBackgroundColor(C.bg)
  term.clear()
  -- sidebar
  for y = 1, H do fill(1, y, SIDE, C.side) end
  put(2, 1, "SETTINGS", C.title, C.side)
  for i, pg in ipairs(ps) do
    local y = 2 + i * 2
    local active = i == page
    fill(1, y, SIDE, active and C.sel or C.side)
    put(3, y, pg.name, active and C.selText or C.sideText, active and C.sel or C.side)
    hits[#hits + 1] = { x1 = 1, x2 = SIDE, y = y, page = i }
  end
  put(2, H, "q: quit", C.dim, C.side)
  -- pane
  local px = SIDE + 2
  local pw = W - px
  put(px, 1, p.name, C.title)
  put(px, 2, ("-"):rep(pw), C.line)
  local y = 4
  for i, r in ipairs(p.rows) do
    if r.kind == "gap" then
      y = y + 1
    else
      local sel = (i == row)
      local bg = sel and C.sel or C.bg
      fill(px - 1, y, pw + 1, bg)
      if r.kind == "info" then
        put(px, y, r.label, C.dim, bg)
        put(px + 14, y, r.text, C.text, bg)
      elseif r.kind == "toggle" then
        put(px, y, r.label, sel and C.selText or C.text, bg)
        local pill = r.value and " ON  " or " OFF "
        put(W - 6, y, pill, r.value and colors.black or colors.lightGray, r.value and C.on or C.off)
        hits[#hits + 1] = { x1 = px - 1, x2 = W, y = y, row = i }
      elseif r.kind == "choice" then
        put(px, y, r.label, sel and C.selText or C.text, bg)
        local v = tostring(r.value) .. (r.suffix or "")
        local vw = #v
        local vx = W - vw - 3
        put(vx - 1, y, "<", C.hot, bg)
        put(vx + 1, y, v, C.text, bg)
        put(vx + vw + 2, y, ">", C.hot, bg)
        hits[#hits + 1] = { x1 = px - 1, x2 = vx, y = y, row = i, step = -1 }
        hits[#hits + 1] = { x1 = vx + 1, x2 = W, y = y, row = i, step = 1 }
      elseif r.kind == "action" then
        put(px, y, "[ " .. r.label .. " ]", r.danger and C.warn or (sel and C.selText or C.hot), bg)
        hits[#hits + 1] = { x1 = px - 1, x2 = W, y = y, row = i, act = true }
      end
      y = y + 1
    end
  end
  -- footer: help for the selected row, or the last confirmation
  fill(SIDE + 1, H, W - SIDE, C.bg)
  local line = nil
  if flash and os.clock() < flashUntil then
    line = flash
    put(px, H, line, C.on)
  else
    local r = p.rows[row]
    if r and r.help then put(px, H, r.help:sub(1, pw), C.dim) end
  end
  term.setCursorBlink(false)
end

local function move(dir)
  local p = pages()[page]
  local n = #p.rows
  local i = row
  for _ = 1, n do
    i = i + dir
    if i < 1 then i = n elseif i > n then i = 1 end
    if selectable(p.rows[i]) then row = i return end
  end
end

local function setPage(i)
  local np = #pages()
  page = (i - 1) % np + 1
  row = 1
end

draw()
local tick = os.startTimer(1)
while true do
  local ev, a, b, c = os.pullEvent()
  if ev == "char" then
    if a == "q" then return end
    if a == " " then
      local r = pages()[page].rows[row]
      if r then change(r, 1) end
    end
  elseif ev == "key" then
    if a == keys.up then move(-1)
    elseif a == keys.down then move(1)
    elseif a == keys.tab or a == keys.pageDown then setPage(page + 1)
    elseif a == keys.pageUp then setPage(page - 1)
    elseif a == keys.left or a == keys.right then
      local r = pages()[page].rows[row]
      if r and r.kind == "choice" then change(r, a == keys.right and 1 or -1) end
    elseif a == keys.enter then
      local r = pages()[page].rows[row]
      if r then change(r, 1) end
    end
  elseif ev == "mouse_click" then
    for _, h in ipairs(hits) do
      if c == h.y and b >= h.x1 and b <= h.x2 then
        if h.page then
          setPage(h.page)
        else
          row = h.row
          change(pages()[page].rows[row], h.step or 1)
        end
        break
      end
    end
  elseif ev == "mouse_scroll" then
    move(a)
  elseif ev == "timer" and a == tick then
    tick = os.startTimer(1)
  end
  draw()
end
