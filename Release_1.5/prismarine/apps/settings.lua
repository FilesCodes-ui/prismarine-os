--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Settings. Runs sandboxed and talks to the OS through prismarine.ui.
-- Mouse: click a page on the left, click a row on the right.
-- Keys:  Up/Down row, Left/Right change a value, Enter or Space toggle,
--        Tab or PageUp/PageDown change page, q quits.
local api = prismarine
local ui = api.ui
local netadmin, account = api.netadmin, api.account
local permsApi = api.perms
local bgapps = api.bgapps
local themesApi = api.themes
local permIdx = 1
local W, H = term.getSize()

local C = {
  bg = colors.black, side = colors.gray, sideText = colors.lightGray,
  sel = colors.blue, selText = colors.white, title = colors.cyan,
  text = colors.white, dim = colors.lightGray, on = colors.lime, off = colors.gray,
  line = colors.gray, hot = colors.cyan, warn = colors.orange,
}

local kit = dofile("/prismarine/ui/kit.lua")
-- The look follows the OS theme.
local function skin()
  C.bg, C.side, C.sideText = kit.c("bg"), kit.c("bar"), kit.c("hint")
  C.sel, C.selText = kit.c("sel"), kit.c("selText")
  C.title, C.hot = kit.c("line"), kit.c("line")
  C.text, C.dim, C.on, C.off, C.warn = kit.c("text"), kit.c("hint"), kit.c("ok"), kit.c("bar"), kit.c("warn")
  C.line = kit.c("bar")
end
skin()

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
local say   -- defined below; the page builders call it
local editing = nil      -- { key, buf, mask, label, then }
local LOCKS = { 0, 1, 2, 5, 10, 15, 30, 60 }
local TOASTS = { 2, 3, 4, 6, 8, 12 }
local UPDATES = { 30, 60, 300, 900, 3600, 21600, 0 }   -- seconds; 0 is never
local function everyText(v)
  if v == 0 then return "Never" end
  if v < 60 then return v .. " s" end
  if v < 3600 then return (v / 60) .. " min" end
  return (v / 3600) .. " h"
end
local hits = {}

local function cycle(list, cur, step)
  local at = 1
  for i, v in ipairs(list) do if v == cur then at = i end end
  return list[(at - 1 + step) % #list + 1]
end

-- Row kinds: toggle, choice, text, action, info, gap.

local function hexOf(r, g, b) return ("#%02X%02X%02X"):format(r, g, b) end
local STEPS = {}
for v = 0, 255, 15 do STEPS[#STEPS + 1] = v end
local function snap(v) return math.max(0, math.min(255, math.floor((v or 0) / 15 + 0.5) * 15)) end

-- A color picker made of rows: presets plus Custom. Custom shows three rows
-- (Red, Green, Blue) so you mix the color by clicking, with no code to type.
local function colorRows(label, key, cur, rgb, list, help)
  local custom = type(cur) == "string" and cur:sub(1, 1) == "#"
  rgb = rgb or { 63, 85, 255 }
  local names = {}
  for _, n in ipairs(list) do names[#names + 1] = n end
  names[#names + 1] = "Custom"
  local rows = { { kind = "choice", label = label, value = custom and "Custom" or cur, list = names, help = help,
    apply = function(nv)
      if nv == "Custom" then ui.set(key, hexOf(snap(rgb[1]), snap(rgb[2]), snap(rgb[3])))
      else ui.set(key, nv) end
    end } }
  if custom then
    local parts = { "Red", "Green", "Blue" }
    for i = 1, 3 do
      rows[#rows + 1] = { kind = "choice", label = "  " .. parts[i], value = snap(rgb[i]), list = STEPS,
        help = "Mix your own color. 0 is none and 255 is full.",
        apply = function(nv)
          local c = { snap(rgb[1]), snap(rgb[2]), snap(rgb[3]) }
          c[i] = nv
          ui.set(key, hexOf(c[1], c[2], c[3]))
        end }
    end
  end
  return rows
end

local function pages()
  local s = ui.get()
  local ns = netadmin and netadmin.status() or nil
  local up = math.floor(os.clock())
  local locked = api.lockdown and api.lockdown()
  local ast = (account and account.status and account.status()) or {}
  local ps = {
    { name = "Look", intro = "Colors and motion of the whole OS.", rows = (function()
      local rows = {
        { kind = "choice", label = "Theme", key = "theme", value = s.theme, list = ui.themes,
          help = "Colors for bars, menus and toasts. It sets the logo color too." },
        { kind = "choice", label = "Live theme", key = "live", value = s.live, list = ui.liveModes,
          help = "Colors that change on their own, on Home only. Off keeps them still." },
        { kind = "toggle", label = "Animations", key = "anim", value = s.anim,
          help = "Slides and fades. Turn off on a slow computer." },
        { kind = "toggle", label = "Rounded corners", key = "round", value = s.round,
          help = "Soft corners on menus, toasts and app frames." },
        { kind = "choice", label = "Smoothness", key = "fps", value = s.fps, list = FPS, suffix = " fps",
          help = "Higher looks smoother. Lower saves work." },
      }
      return rows
    end)() },
    { name = "Home", intro = "What the Home screen shows.", rows = (function()
      local rows = {}
      for _, r in ipairs(colorRows("Logo color", "logoColor", s.logoColor, s.logoRGB, ui.logoColors,
        "Colors the Home logo only. Pick Custom to mix your own.")) do rows[#rows + 1] = r end
      local more = {
        { kind = "toggle", label = "Glow", key = "haze", value = s.haze,
          help = "A soft glow behind the logo, dark at the edges." },
        { kind = "toggle", label = "Bubbles", key = "bubbles", value = s.bubbles,
          help = "Bubbles that float up behind the logo." },
        { kind = "toggle", label = "Logo shine", key = "shine", value = s.shine,
          help = "A light band that sweeps over the gray half." },
        { kind = "toggle", label = "Logo ripple", key = "ripple", value = s.ripple,
          help = "A wave of light over the colored half." },
        { kind = "toggle", label = "Status line", key = "showStatus", value = s.showStatus,
          help = "Shows how many apps and alerts you have." },
        { kind = "toggle", label = "Key hints", key = "showHint", value = s.showHint,
          help = "The line of key help at the bottom of Home." },
      }
      for _, r in ipairs(more) do rows[#rows + 1] = r end
      return rows
    end)() },
    { name = "Saver", intro = "The picture that shows when idle.", rows = (function()
      local rows = {
        { kind = "choice", label = "Start after", key = "saver", value = s.saver, list = ui.saverAfter,
          fmt = function(v) return v == 0 and "Never" or (v .. " min") end,
          help = "Idle time before the saver starts. Any key or click ends it." },
        { kind = "choice", label = "Style", key = "saverMode", value = s.saverMode, list = ui.saverModes,
          help = "Tide has waves and the PRISMARINE name. The others are Starfield and Clock." },
        { kind = "toggle", label = "Show name", key = "saverLogo", value = s.saverLogo,
          help = "Shows PRISMARINE over the waves in Tide." },
        { kind = "toggle", label = "Follow logo color", key = "saverLink", value = s.saverLink,
          help = "On: the saver uses the Home logo color. Off: it has its own color." },
      }
      if s.saverLink then
        rows[#rows + 1] = { kind = "info", label = "Saver color", text = "Same as the logo" }
      else
        for _, r in ipairs(colorRows("Saver color", "saverColor", s.saverColor, s.saverRGB, ui.saverColors,
          "Colors the Tide saver. Pick Custom to mix your own.")) do rows[#rows + 1] = r end
      end
      rows[#rows + 1] = { kind = "gap" }
      rows[#rows + 1] = { kind = "action", label = "Preview the saver", id = "saverpreview",
        help = "Starts the saver now. Press any key to come back." }
      return rows
    end)() },
    { name = "Clock", intro = "Time, date and the Home text lines.", rows = {
      { kind = "toggle", label = "24 hour clock", key = "hour24", value = s.hour24, help = "Off shows AM and PM." },
      { kind = "toggle", label = "Show seconds", key = "seconds", value = s.seconds, help = "Seconds on the Home clock." },
      { kind = "toggle", label = "Show date", key = "showDate", value = s.showDate, help = "The date under the Home clock." },
      { kind = "text", label = "System name", key = "osName", value = s.osName,
        help = "Press Enter, type a name, press Enter. It shows on the top bar while locked." },
    } },
    { name = "Alerts", intro = "How toasts and the sidebar behave.", rows = {
      { kind = "toggle", label = "Do not disturb", key = "dnd", value = s.dnd,
        help = "Hides toasts. The sidebar still keeps every alert." },
      { kind = "choice", label = "Toast side", key = "toastSide", value = s.toastSide, list = { "left", "right" },
        help = "The edge toasts slide in from." },
      { kind = "choice", label = "Toast time", key = "toastTime", value = s.toastTime, list = TOASTS, suffix = " s",
        help = "How long a toast stays on screen." },
      { kind = "toggle", label = "Show message text", key = "showText", value = s.showText,
        help = "Show the message in a toast, not only the title." },
      { kind = "choice", label = "Check for updates", key = "updateEvery", value = s.updateEvery, list = UPDATES, fmt = everyText,
        help = "How often to look for a new version. Never turns the checks off." },
      { kind = "toggle", label = "Update toast", key = "updateToast", value = s.updateToast,
        help = "Show a toast when a new update is found." },
      { kind = "gap" },
      { kind = "action", label = "Send a test toast", id = "test",
        help = "Posts one toast so you see your settings at work." },
      { kind = "action", label = "Clear the alert list (" .. ui.notificationCount() .. ")", id = "clear",
        help = "Empties the sidebar history." },
    } },
    { name = "Security", intro = "Locking, passwords and checks.", rows = {
      { kind = "choice", label = "Auto-lock", key = "autoLock", value = s.autoLock, list = LOCKS,
        fmt = function(v) return v == 0 and "Never" or (v .. " min") end,
        help = ast.bunker and "Bunker: 1 to 5 minutes only." or locked and "Archive mode: 1 to 15 minutes only."
          or (ast.password == false and "Locking needs a password. Turn one on in Others.") or "Locks after this idle time. Never turns it off." },
      { kind = "info", label = "Lock now", text = ast.password == false and "Needs a password" or "Press F9" },
      { kind = "info", label = "Password", text = ast.password == false and "Off. Turn on in Others" or "On. Change it in Others" },
      { kind = "info", label = "Archive mode", text = ast.bunker and "BUNKER. Shell, Programs, Disks locked." or locked and "ON. Shell and new programs locked." or "Off" },
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
      local short = { web = "Internet", redstone = "Redstone out", devices = "Devices", files = "Other files", inputs = "Saved inputs", touch = "Monitor touch", background = "Background", rooms = "Rooms chat" }
      local help = {
        web = "Download or send data over the internet.",
        redstone = "Switch redstone outputs. Reading input is free.",
        devices = "Use chests, energy cells and other devices.",
        files = "Read or change files outside the app's own folder.",
        inputs = "See and change your saved redstone inputs.",
        touch = "Get touches on your monitors.",
        background = "Keep running when the app is not in front.",
        rooms = "Send and get chat messages with other players over the network.",
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
    ps[#ps + 1] = { name = "App access", intro = "What each app is allowed to use.", rows = rows }
  end
  if bgapps then
    -- Apps that are not in front freeze. Pick the ones that keep running.
    local rows = {}
    rows[#rows + 1] = { kind = "info", label = "Rule", text = "Apps freeze when not in front" }
    rows[#rows + 1] = { kind = "info", label = "Auto", text = "Frozen, unless it asks and you allow" }
    rows[#rows + 1] = { kind = "gap" }
    for _, e in ipairs(bgapps.list()) do
      local autoLabel = (e.default == "keep") and "Auto (runs)" or "Auto"
      local cur = (e.mode == "keep" and "Keep running") or (e.mode == "freeze" and "Freeze") or autoLabel
      rows[#rows + 1] = { kind = "choice", label = e.name, value = cur, list = { autoLabel, "Keep running", "Freeze" },
        help = (e.default == "keep" and "Runs in the background unless you pick Freeze. " or "")
          .. "Keep running: it never freezes, so music and timers continue. Freeze: it always freezes.",
        apply = function(nv)
          local m = (nv == "Keep running" and "keep") or (nv == "Freeze" and "freeze") or "auto"
          if not bgapps.set(e.key, m) then say("Could not change that.") end
        end }
    end
    if #rows == 3 then rows[#rows + 1] = { kind = "info", label = "Apps", text = "No apps found" } end
    ps[#ps + 1] = { name = "Background", intro = "Choose which apps keep running when not in front.", rows = rows }
  end
  if netadmin and ns then
    local rows = {}
    rows[#rows + 1] = { kind = "info", label = "Your key", text = tostring(ns.myFp) }
    if ns.isArchive then
      rows[#rows + 1] = { kind = "info", label = "Role", text = "This computer is the Archive" }
      rows[#rows + 1] = { kind = "info", label = "Archive key", text = tostring(ns.archiveFp) }
      rows[#rows + 1] = { kind = "info", label = "Name", text = tostring(ns.arcName) }
      rows[#rows + 1] = { kind = "info", label = "Token", text = "Archive app, Info tab. Write it down." }
    elseif ns.enrolled then
      rows[#rows + 1] = { kind = "info", label = "Archive", text = tostring(ns.archive.name) }
      rows[#rows + 1] = { kind = "info", label = "Archive key", text = tostring(ns.archive.fp) }
      rows[#rows + 1] = { kind = "info", label = "Leaving", text = "Only the Archive can release you" }
      local age = ns.rosterAge
      local ageText = "unknown"
      if age then
        local sec = math.floor(age / 1000)
        ageText = (sec < 90) and (sec .. " s ago") or (sec < 5400) and (math.floor(sec / 60) .. " min ago") or (math.floor(sec / 3600) .. " h ago")
      end
      rows[#rows + 1] = { kind = "info", label = "Roster", text = "Archive last heard " .. ageText .. (ns.rosterStale and ". OLD: only the Archive is trusted." or "") }
      rows[#rows + 1] = { kind = "action", label = "Leave with a dissolve token", id = "dissolve", danger = true,
        help = "For a lost Archive. Paste the token the Archive owner saved." }
    else
      local es = netadmin.enrollState()
      if es then
        rows[#rows + 1] = { kind = "info", label = "Joining", text = tostring(es.name) }
        rows[#rows + 1] = { kind = "info", label = "Your key", text = tostring(es.myFp) }
        if es.refused then
          rows[#rows + 1] = { kind = "info", label = "Result", text = "The Archive said no" }
        elseif es.answered then
          rows[#rows + 1] = { kind = "info", label = "Archive key", text = tostring(es.fp) }
          rows[#rows + 1] = { kind = "info", label = "Warning", text = "The Archive reads everything you send." }
          rows[#rows + 1] = { kind = "info", label = "", text = "It sees every program you run too." }
          rows[#rows + 1] = { kind = "action", label = "Join (type the key to confirm)", id = "joinyes",
            help = "You type the first group of the Archive key. Check it against the Archive screen first." }
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
    ps[#ps + 1] = { name = "Network", intro = "Archives and other computers.", rows = rows }
  end
  ps[#ps + 1] = { name = "Keys", intro = "Keys and mouse moves.", rows = {
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
  if themesApi then
    local rows = {
      { kind = "info", label = "How", text = "Edit colors on the Colors page, then save the look as a theme." },
      { kind = "action", label = "Save this look as a theme", id = "themesave",
        help = "Keeps the colors on screen now. Apps like Audio follow it." },
      { kind = "action", label = "Install a theme from a link", id = "themeget",
        help = "Paste an https:// link to a theme file. Themes hold colors only, never code." },
      { kind = "action", label = "Scan the themes folder", id = "themescan",
        help = "Finds theme files you copied into /prismarine/themes." },
    }
    local dl = themesApi.downloadStatus()
    if dl and dl.state ~= "idle" then
      rows[#rows + 1] = { kind = "info", label = "Download", text = tostring(dl.text) }
    end
    local list = themesApi.list()
    if #list == 0 then
      rows[#rows + 1] = { kind = "info", label = "Yours", text = "No custom themes yet." }
    end
    for _, t in ipairs(list) do
      rows[#rows + 1] = { kind = "action", label = "Delete " .. t.name .. (t.active and " (in use)" or ""), id = "themedel",
        key = t.name, danger = true, help = "Removes the theme file." .. (t.author and (" By " .. t.author .. ".") or "") }
    end
    ps[#ps + 1] = { name = "Themes", intro = "Make, install and remove your own themes.", rows = rows }
  end
  ps[#ps + 1] = { name = "Colors", intro = "Pick any color for each part.", rows = (function()
    local rows = {}
    for _, role in ipairs(ui.roles) do
      rows[#rows + 1] = { kind = "choice", label = role, key = "color." .. role, value = s.colors[role] or "?",
        list = ui.colorNames, help = "Color for the '" .. role .. "' part of the interface. A theme resets it." }
    end
    return rows
  end)() }
  ps[#ps + 1] = { name = "System", intro = "Facts about this computer.", rows = {
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

function say(msg)
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
    if r.id == "joinyes" then
      editing = { joinTyped = true, buf = "", plain = true, label = "First group of the Archive key" }
      return
    end
    if r.id == "dissolve" then
      editing = { dissolve = true, buf = "", plain = true, label = "Dissolve token" }
      return
    end
    if r.id == "joinno" then netadmin.cancelJoin() say("Cancelled.") return end
    if r.id == "become" then
      editing = { become = true, buf = "", mask = "*", label = "Password to confirm" }
      return
    end
    if r.id == "themesave" then
      editing = { themeSave = true, buf = "", label = "Theme name" }
      return
    end
    if r.id == "themeget" then
      editing = { themeGet = true, buf = "https://", label = "Theme link" }
      return
    end
    if r.id == "themescan" then
      say(themesApi.rescan() .. " custom theme(s) found.")
      return
    end
    if r.id == "themedel" then
      themesApi.delete(r.key)
      say("Deleted " .. tostring(r.key) .. ".")
      return
    end
    if r.id == "permforget" then
      permsApi.forget(r.key)
      say("Forgotten.")
      return
    end
    if r.id == "saverpreview" then
      if ui.startSaver then ui.startSaver() else say("Not available.") end
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

local SIDE = 14

local function draw()
  W, H = term.getSize()
  skin()
  local ps = pages()
  local p = ps[page]
  fixRow(p)
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  local narrow = W < 40
  local rx = narrow and 2 or (SIDE + 3)
  local rw = W - rx
  local ch = H - 4
  -- keep the selected row on screen
  local fit = ch - 2
  if row < top then top = row end
  while row > 0 and row - top + 1 > fit do top = top + 1 end
  if top < 1 or #p.rows <= fit then top = 1 end
  hits = {}
  local s = kit.scene()
  s:header("Settings", p.name .. (narrow and ("  " .. page .. "/" .. #ps .. " Tab") or ""), nil)
  -- sidebar
  if not narrow then s:card(2, 2, SIDE, ch, gray) end
  for i, pg in ipairs(ps) do
    local y = 2 + i
    if narrow or y > H - 3 then break end
    local active = i == page
    s:row(3, y, SIDE - 2, pg.name, active)
    hits[#hits + 1] = { x1 = 2, x2 = SIDE + 1, y = y, page = i }
  end
  -- pane
  s:card(rx, 2, rw, ch, gray)
  local px = rx + 2
  local y = 3
  for i = top, #p.rows do
    local r = p.rows[i]
    if y > H - 4 then break end
    if r.kind == "gap" then
      y = y + 1
    else
      local sel = (i == row)
      local bg = sel and kit.c("sel") or gray
      local fg = sel and kit.c("selText") or text
      if sel then s:card(rx + 1, y, rw - 2, 1, bg) end
      if r.kind == "info" then
        s:text(px, y, r.label, hint, gray)
        s:text(px + 14, y, kit.fit(tostring(r.text), rw - 18), text, gray)
      elseif r.kind == "toggle" then
        s:text(px, y, kit.fit(r.label, rw - 10), fg, bg)
        s:switch(rx + rw - 7, y, r.value)
        hits[#hits + 1] = { x1 = rx, x2 = W, y = y, row = i }
      elseif r.kind == "choice" then
        local v = (r.fmt and r.fmt(r.value) or tostring(r.value)) .. (r.suffix or "")
        v = kit.fit(v, narrow and 8 or 14)
        local vw = #v
        s:text(px, y, kit.fit(r.label, rw - vw - 9), fg, bg)
        local vx = rx + rw - vw - 5
        s:text(vx - 1, y, "<", sel and kit.c("selText") or kit.c("line"), bg)
        s:text(vx + 1, y, v, fg, bg)
        s:text(vx + vw + 2, y, ">", sel and kit.c("selText") or kit.c("line"), bg)
        hits[#hits + 1] = { x1 = rx, x2 = vx, y = y, row = i, step = -1 }
        hits[#hits + 1] = { x1 = vx + 1, x2 = W, y = y, row = i, step = 1 }
      elseif r.kind == "text" then
        local v = kit.fit(tostring(r.value), narrow and 8 or 16)
        s:text(px, y, kit.fit(r.label, rw - #v - 7), fg, bg)
        s:text(rx + rw - #v - 3, y, v, sel and kit.c("selText") or kit.c("line"), bg)
        hits[#hits + 1] = { x1 = rx, x2 = W, y = y, row = i }
      elseif r.kind == "action" then
        local col = r.danger and kit.c("warn") or (sel and kit.c("selText") or kit.c("line"))
        s:text(px, y, "> " .. r.label, col, bg)
        hits[#hits + 1] = { x1 = rx, x2 = W, y = y, row = i, act = true }
      end
      y = y + 1
    end
  end
  s:scroll(W - 1, 3, fit, #p.rows, top - 1, fit)
  -- footer: help for the selected row, or the last confirmation
  if flash and os.clock() < flashUntil then
    s:status(H - 1, flash, "ok")
  else
    local r = p.rows[row]
    local t = (r and r.help) or p.intro
    if t then
      local w = W - 5
      if #t <= w then s:text(3, H - 1, t, hint, kit.c("bg"))
      else
        local cut = t:sub(1, w):match("^(.*) ") or t:sub(1, w)
        s:text(3, H - 2, cut, hint, kit.c("bg"))
        s:text(3, H - 1, kit.fit(t:sub(#cut + 2), w), hint, kit.c("bg"))
      end
    end
  end
  if editing then
    local shown = editing.mask and ("*"):rep(#editing.buf) or editing.buf
    s:card(2, H - 1, W - 2, 1, kit.c("sel"))
    s:text(3, H - 1, kit.fit(editing.label .. ": " .. shown, W - 5), kit.c("selText"), kit.c("sel"))
  end
  s:flush()
  term.setCursorBlink(false)
  if editing then
    local shown = editing.mask and ("*"):rep(#editing.buf) or editing.buf
    term.setCursorPos(math.min(W - 1, 3 + #editing.label + 2 + #shown), H - 1)
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
    elseif ev == "paste" then editing.buf = (editing.buf .. tostring(a):gsub("%c", "")):sub(1, 300)
    elseif ev == "key" and a == keys.backspace then editing.buf = editing.buf:sub(1, -2)
    elseif ev == "key" and a == keys.escape then editing = nil
    elseif ev == "key" and a == keys.enter then
      local e = editing
      editing = nil
      if e.joinTyped then
        local ok, why = netadmin.confirmJoin(true, e.buf)
        if ok then say("Joined. Roster loading.")
        elseif why == "mismatch" then say("Those letters do not match the Archive key.")
        else say("Could not join.") end
      elseif e.dissolve then
        local ok, why = netadmin.dissolve(e.buf)
        say(ok and "You left the Archive network." or tostring(why))
      elseif e.themeSave then
        local ok, why = themesApi.save(e.buf)
        say(ok and ("Saved. Theme " .. tostring(why) .. " is on.") or tostring(why))
      elseif e.themeGet then
        local ok, why = themesApi.download(e.buf)
        say(ok and "Downloading. Check this page." or tostring(why))
      elseif e.become then
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
