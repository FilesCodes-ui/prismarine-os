-- Prismarine Settings. Runs sandboxed and talks to the OS through prismarine.ui.
-- Mouse: click a page on the left, click a row on the right.
-- Keys:  Up/Down row, Left/Right change a value, Enter or Space toggle,
--        Tab or PageUp/PageDown change page, q quits.
local api = prismarine
local ui = api.ui
local netadmin, account = api.netadmin, api.account
local permsApi = api.perms
local permIdx = 1
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
local top = 1
local flash, flashUntil = nil, 0
local editing = nil      -- { key, buf, mask, label, then }
local LOCKS = { 0, 1, 2, 5, 10, 15, 30, 60 }
local TOASTS = { 2, 3, 4, 6, 8, 12 }
local hits = {}

local function cycle(list, cur, step)
  local at = 1
  for i, v in ipairs(list) do if v == cur then at = i end end
  return list[(at - 1 + step) % #list + 1]
end

-- Row kinds: toggle, choice, text, action, info, gap.

local function pages()
  local s = ui.get()
  local ns = netadmin and netadmin.status() or nil
  local up = math.floor(os.clock())
  local locked = api.lockdown and api.lockdown()
  local ast = (account and account.status and account.status()) or {}
  local ps = {
    { name = "Display", rows = {
      { kind = "choice", label = "Theme", key = "theme", value = s.theme, list = ui.themes,
        help = "Colors for bars, menus and toasts. Sets the logo color too." },
      { kind = "toggle", label = "Animations", key = "anim", value = s.anim,
        help = "Slides, fades and the moving logo." },
      { kind = "toggle", label = "Dashboard haze", key = "haze", value = s.haze,
        help = "Dark glow at the top and bottom of Home." },
      { kind = "toggle", label = "Rounded corners", key = "round", value = s.round,
        help = "Soft corners on menus, toasts, buttons and app frames." },
      { kind = "toggle", label = "Bubbles", key = "bubbles", value = s.bubbles,
        help = "Floating bubbles on Home." },
      { kind = "toggle", label = "Logo shine", key = "shine", value = s.shine,
        help = "A light band that sweeps over the gray half." },
      { kind = "toggle", label = "Logo ripple", key = "ripple", value = s.ripple,
        help = "A wave of brightness over the colored half." },
      { kind = "choice", label = "Frame rate", key = "fps", value = s.fps, list = FPS, suffix = " fps",
        help = "Higher is smoother. Lower saves work." },
      { kind = "choice", label = "Logo color", key = "logoColor", value = s.logoColor, list = ui.logoColors,
        help = "Pick a preset. Rainbow cycles." },
      { kind = "choice", label = "Live theme", key = "live", value = s.live, list = ui.liveModes,
        help = "Colors that change on their own. Home only. Off keeps them still." },
      { kind = "choice", label = "Screen saver", key = "saver", value = s.saver, list = ui.saverAfter,
        fmt = function(v) return v == 0 and "Off" or (v .. " min") end,
        help = "Starts after this idle time. Any key wakes it. It shows no messages." },
      { kind = "choice", label = "Saver style", key = "saverMode", value = s.saverMode, list = ui.saverModes,
        help = "Tide, Starfield, Clock or Logo drift." },
    } },
    { name = "Clock", rows = {
      { kind = "toggle", label = "24 hour clock", key = "hour24", value = s.hour24, help = "Off shows AM and PM." },
      { kind = "toggle", label = "Show seconds", key = "seconds", value = s.seconds, help = "Seconds on the Home clock." },
      { kind = "toggle", label = "Show date", key = "showDate", value = s.showDate, help = "The date under the Home clock." },
      { kind = "toggle", label = "Show status line", key = "showStatus", value = s.showStatus, help = "App and alert counts on Home." },
      { kind = "toggle", label = "Show hint line", key = "showHint", value = s.showHint, help = "The key help at the bottom of Home." },
      { kind = "text", label = "System name", key = "osName", value = s.osName, help = "Shown on the top bar while locked." },
    } },
    { name = "Colors", rows = (function()
      local rows = {}
      for _, role in ipairs(ui.roles) do
        rows[#rows + 1] = { kind = "choice", label = role, key = "color." .. role, value = s.colors[role] or "?",
          list = ui.colorNames, help = "Color for the '" .. role .. "' part of the interface. Theme resets it." }
      end
      return rows
    end)() },
    { name = "Alerts", rows = {
      { kind = "toggle", label = "Do not disturb", key = "dnd", value = s.dnd,
        help = "Hides toasts. The sidebar still keeps them." },
      { kind = "choice", label = "Toast side", key = "toastSide", value = s.toastSide, list = { "left", "right" },
        help = "Which edge toasts slide in from." },
      { kind = "choice", label = "Toast time", key = "toastTime", value = s.toastTime, list = TOASTS, suffix = " s",
        help = "How long a toast stays." },
      { kind = "toggle", label = "Show message text", key = "showText", value = s.showText,
        help = "Show the body in a toast, not only the title." },
      { kind = "gap" },
      { kind = "action", label = "Send test toast", id = "test",
        help = "Posts one toast so you can see your settings." },
      { kind = "action", label = "Clear notification list (" .. ui.notificationCount() .. ")", id = "clear",
        help = "Empties the sidebar history." },
    } },
    { name = "Security", rows = {
      { kind = "choice", label = "Auto-lock", key = "autoLock", value = s.autoLock, list = LOCKS, suffix = " min",
        help = ast.bunker and "Bunker: 1 to 5 minutes only." or locked and "Archive mode: 1 to 15 minutes only."
          or (ast.password == false and "Locking needs a password. Turn one on in Others.") or "Lock after this idle time. 0 turns it off." },
      { kind = "info", label = "Archive mode", text = ast.bunker and "BUNKER. Shell, Programs, Disks locked." or locked and "ON. Shell and new programs locked." or "Off" },
      { kind = "info", label = "Lock now", text = ast.password == false and "Needs a password" or "Press F9" },
      { kind = "info", label = "Password", text = ast.password == false and "Off. Turn on in Others" or "On. Manage in Others" },
      { kind = "info", label = "System files", text = "Checked at every boot" },
      { kind = "info", label = "Messages", text = "Signed and encrypted" },
    } },
  }
  if permsApi then
    local rows = {}
    local list = permsApi.list()
    if permsApi.bunker then
      rows[#rows + 1] = { kind = "info", label = "Bunker", text = "Every request is refused" }
    end
    if #list == 0 then
      rows[#rows + 1] = { kind = "info", label = "Apps", text = "None have asked yet" }
      rows[#rows + 1] = { kind = "info", label = "Safe", text = "Sound, screens, own folder" }
    else
      if permIdx > #list then permIdx = #list end
      if permIdx < 1 then permIdx = 1 end
      local a = list[permIdx]
      local names = {}
      for i, e in ipairs(list) do names[i] = i .. "/" .. #list .. " " .. e.name end
      rows[#rows + 1] = { kind = "choice", label = "App", value = names[permIdx], list = names,
        help = "Apps ask the first time. Speaker, screens, colors and their own folder never ask.",
        apply = function(nv)
          for i, n in ipairs(names) do if n == nv then permIdx = i end end
        end }
      local short = { web = "Internet", redstone = "Redstone out", devices = "Devices", files = "Other files", inputs = "Saved inputs", touch = "Monitor touch" }
      local help = {
        web = "Download or send data over the internet.",
        redstone = "Switch redstone outputs. Reading input is free.",
        devices = "Use chests, energy cells and other devices.",
        files = "Read or change files outside the app's own folder.",
        inputs = "See and change your saved redstone inputs.",
        touch = "Get touches on your monitors.",
      }
      for _, perm in ipairs(permsApi.order) do
        local cur = a.grants[perm] or "ask"
        rows[#rows + 1] = { kind = "choice", label = short[perm] or perm,
          value = cur:sub(1, 1):upper() .. cur:sub(2), list = { "Ask", "Always", "Never" },
          help = (help[perm] or "") .. " Never refuses without asking.",
          apply = function(nv)
            if not permsApi.set(a.key, perm, nv:lower()) then say("Could not change that.") end
          end }
      end
      rows[#rows + 1] = { kind = "gap" }
      rows[#rows + 1] = { kind = "action", label = "Forget this app", id = "permforget", key = a.key, danger = true,
        help = "Removes what it was given. It asks again next time." }
    end
    ps[#ps + 1] = { name = "Permissions", rows = rows }
  end
  if netadmin and ns then
    local rows = {}
    rows[#rows + 1] = { kind = "info", label = "Your key", text = tostring(ns.myFp) }
    if ns.isArchive then
      rows[#rows + 1] = { kind = "info", label = "Role", text = "This computer is the Archive" }
      rows[#rows + 1] = { kind = "info", label = "Archive key", text = tostring(ns.archiveFp) }
      rows[#rows + 1] = { kind = "info", label = "Name", text = tostring(ns.arcName) }
    elseif ns.enrolled then
      rows[#rows + 1] = { kind = "info", label = "Archive", text = tostring(ns.archive.name) }
      rows[#rows + 1] = { kind = "info", label = "Archive key", text = tostring(ns.archive.fp) }
      rows[#rows + 1] = { kind = "info", label = "Leaving", text = "Only the Archive can release you" }
    else
      local es = netadmin.enrollState()
      if es then
        rows[#rows + 1] = { kind = "info", label = "Joining", text = tostring(es.name) }
        rows[#rows + 1] = { kind = "info", label = "Your key", text = tostring(es.myFp) }
        if es.refused then
          rows[#rows + 1] = { kind = "info", label = "Result", text = "The Archive said no" }
        elseif es.answered then
          rows[#rows + 1] = { kind = "info", label = "Archive key", text = tostring(es.fp) }
          rows[#rows + 1] = { kind = "action", label = "Join (keys match)", id = "joinyes" }
          rows[#rows + 1] = { kind = "action", label = "Cancel", id = "joinno" }
        else
          rows[#rows + 1] = { kind = "info", label = "Waiting", text = "The Archive must approve you" }
        end
      else
        rows[#rows + 1] = { kind = "action", label = "Find Archives", id = "findarc", help = "Look for Archives in range." }
        for _, a in ipairs(netadmin.archives()) do
          rows[#rows + 1] = { kind = "action", label = "Join " .. a.name .. " " .. a.fp, id = "join", arc = a.id,
            help = "Ask this Archive to enroll you. Compare the key codes." }
        end
        rows[#rows + 1] = { kind = "gap" }
        rows[#rows + 1] = { kind = "action", label = "Make this computer an Archive", id = "become", danger = true,
          help = "Needs your password. The Archive reads all messages." }
      end
    end
    ps[#ps + 1] = { name = "Network", rows = rows }
  end
  ps[#ps + 1] = { name = "Controls", rows = {
      { kind = "info", label = "Left Alt", text = "Apps menu" },
      { kind = "info", label = "Right Alt", text = "Switch between apps" },
      { kind = "info", label = "F8", text = "Notification sidebar" },
      { kind = "info", label = "F9", text = "Lock the computer" },
      { kind = "gap" },
      { kind = "info", label = "[H]", text = "Top bar: go Home" },
      { kind = "info", label = "Badge", text = "Top bar: alerts" },
      { kind = "info", label = "Menus", text = "Drag, release to pick" },
      { kind = "info", label = "Wheel", text = "Scroll menus, sidebar" },
  } }
  ps[#ps + 1] = { name = "System", rows = {
      { kind = "info", label = "Prismarine", text = api.version or "?" },
      { kind = "info", label = "Graphics", text = s.graphics and "Pixelbox" or "Plain text" },
      { kind = "info", label = "Screen", text = s.width .. " x " .. s.height .. " cells" },
      { kind = "info", label = "Computer", text = "#" .. tostring(os.getComputerID()) .. " " .. tostring(os.getComputerLabel() or "") },
      { kind = "info", label = "Uptime", text = math.floor(os.clock() / 60) .. " min" },
      { kind = "gap" },
      { kind = "action", label = "Reset all settings", id = "reset", danger = true,
        help = "Put every setting back to its default." },
  } }
  return ps
end

local function selectable(r) return r.kind == "toggle" or r.kind == "choice" or r.kind == "action" or r.kind == "text" end

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
    local cur = r.value
    if r.apply then
      -- r.value may carry a suffix; cycle over the shown strings
      r.apply(cycle(r.list, cur, step))
      return
    end
    local nv = cycle(r.list, r.value, step)
    if ui.set(r.key, nv) == false then say("Blocked: Archive mode.") end
  elseif r.kind == "text" then
    editing = { key = r.key, buf = tostring(r.value), label = r.label }
  elseif r.kind == "action" then
    if r.id == "findarc" then netadmin.findArchives() say("Looking...") return end
    if r.id == "join" then
      local ok, why = netadmin.join(r.arc)
      say(ok and "Request sent. Wait for the Archive." or tostring(why)) return
    end
    if r.id == "joinyes" then netadmin.confirmJoin(true) say("Joined. Roster loading.") return end
    if r.id == "joinno" then netadmin.cancelJoin() say("Cancelled.") return end
    if r.id == "become" then
      editing = { become = true, buf = "", mask = "*", label = "Password to confirm" }
      return
    end
    if r.id == "permforget" then
      permsApi.forget(r.key)
      say("Forgotten.")
      return
    end
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
  -- keep the selected row on screen
  local fit = H - 5
  if row < top then top = row end
  while row > 0 and row - top + 1 > fit do top = top + 1 end
  if top < 1 or #p.rows <= fit then top = 1 end
  hits = {}
  term.setBackgroundColor(C.bg)
  term.clear()
  -- sidebar
  for y = 1, H do fill(1, y, SIDE, C.side) end
  put(2, 1, "SETTINGS", C.title, C.side)
  for i, pg in ipairs(ps) do
    local y = 2 + i * (#ps <= 7 and 2 or 1)
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
  for i = top, #p.rows do
    local r = p.rows[i]
    if y > H - 2 then break end
    if r.kind == "gap" then
      y = y + 1
    else
      local sel = (i == row)
      local bg = sel and C.sel or C.bg
      fill(px - 1, y, pw + 1, bg)
      if r.kind == "info" then
        put(px, y, r.label, C.dim, bg)
        put(px + 14, y, tostring(r.text):sub(1, pw - 14), C.text, bg)
      elseif r.kind == "toggle" then
        put(px, y, r.label, sel and C.selText or C.text, bg)
        local pill = r.value and " ON  " or " OFF "
        put(W - 6, y, pill, r.value and colors.black or colors.lightGray, r.value and C.on or C.off)
        hits[#hits + 1] = { x1 = px - 1, x2 = W, y = y, row = i }
      elseif r.kind == "choice" then
        put(px, y, r.label, sel and C.selText or C.text, bg)
        local v = (r.fmt and r.fmt(r.value) or tostring(r.value)) .. (r.suffix or "")
        local vw = #v
        local vx = W - vw - 3
        put(vx - 1, y, "<", C.hot, bg)
        put(vx + 1, y, v, C.text, bg)
        put(vx + vw + 2, y, ">", C.hot, bg)
        hits[#hits + 1] = { x1 = px - 1, x2 = vx, y = y, row = i, step = -1 }
        hits[#hits + 1] = { x1 = vx + 1, x2 = W, y = y, row = i, step = 1 }
      elseif r.kind == "text" then
        put(px, y, r.label, sel and C.selText or C.text, bg)
        local v = tostring(r.value)
        put(W - #v - 2, y, v, C.hot, bg)
        hits[#hits + 1] = { x1 = px - 1, x2 = W, y = y, row = i }
      elseif r.kind == "action" then
        put(px, y, "[ " .. r.label .. " ]", r.danger and C.warn or (sel and C.selText or C.hot), bg)
        hits[#hits + 1] = { x1 = px - 1, x2 = W, y = y, row = i, act = true }
      end
      y = y + 1
    end
  end
  if top > 1 then put(W, 3, "^", C.hot) end
  if #p.rows - top + 1 > fit then put(W, H - 2, "v", C.hot) end
  -- footer: help for the selected row, or the last confirmation
  fill(SIDE + 1, H - 1, W - SIDE, C.bg)
  fill(SIDE + 1, H, W - SIDE, C.bg)
  local line = nil
  if flash and os.clock() < flashUntil then
    line = flash
    put(px, H, line, C.on)
  else
    local r = p.rows[row]
    if r and r.help then
      local t = r.help
      if #t <= pw then put(px, H, t, C.dim)
      else
        local cut = t:sub(1, pw):match("^(.*) ") or t:sub(1, pw)
        put(px, H - 1, cut, C.dim)
        put(px, H, t:sub(#cut + 2, #cut + 1 + pw), C.dim)
      end
    end
  end
  term.setCursorBlink(false)
  if editing then
    fill(SIDE + 1, H - 1, W - SIDE, C.sel)
    local shown = editing.mask and ("*"):rep(#editing.buf) or editing.buf
    put(px, H - 1, (editing.label .. ": " .. shown):sub(1, pw - 1), C.selText, C.sel)
    term.setCursorPos(math.min(W, px + #editing.label + 2 + #shown), H - 1)
    term.setCursorBlink(true)
  end
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
  top = 1
end

draw()
local tick = os.startTimer(1)
while true do
  local ev, a, b, c = os.pullEvent()
  if editing then
    if ev == "char" then editing.buf = editing.buf .. a
    elseif ev == "key" and a == keys.backspace then editing.buf = editing.buf:sub(1, -2)
    elseif ev == "key" and a == keys.escape then editing = nil
    elseif ev == "key" and a == keys.enter then
      local e = editing
      editing = nil
      if e.become then
        say("Checking...")
        draw()
        local ok = account and account.check(e.buf)
        if ok then
          say("Getting the Archive app...")
          draw()
          local made, fp = netadmin.becomeArchive()
          say(made and ("This is now an Archive. Key " .. tostring(fp)) or tostring(fp))
        else
          say("Wrong password.")
        end
      else
        if not ui.set(e.key, e.buf) then say("Not allowed.") end
      end
    end
  elseif ev == "char" then
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
