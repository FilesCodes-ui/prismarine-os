-- /prismarine/ui/ui.lua
-- Prismarine OS v23, stage 2: top bar, App Manager, filing-cabinet switcher,
-- crash card and slide-in toasts. No Pixelbox yet (stage 4 adds animations).
--
--   local ui = dofile("/prismarine/ui/ui.lua").create(K, {
--     apps = { { name = "Counter", path = "/x.lua" }, ... },
--     paintDashboard = function() ... end,
--   })
--   K.run(ui.hooks)
--
-- The UI draws straight onto the real screen. While a menu is open the
-- focused app's window is hidden (K.setOverlay) so the app keeps drawing into
-- its buffer without painting over the menu. Closing the menu redraws it.

local M = {}

function M.create(K, cfg)
  cfg = cfg or {}
  local apps = cfg.apps or {}
  local paintDashboard = cfg.paintDashboard or function() end
  local settingsPath = cfg.settingsPath or "/prismarine/data/ui_settings.json"

  local native = term.native()
  local W, H = native.getSize()

  local floor, min, max = math.floor, math.min, math.max

  local C = {
    white = colors.white, black = colors.black, gray = colors.gray,
    lightGray = colors.lightGray, blue = colors.blue, lightBlue = colors.lightBlue,
    cyan = colors.cyan, red = colors.red, yellow = colors.yellow,
    orange = colors.orange, lime = colors.lime,
  }

  -- ------------------------------------------------------------ settings

  local S = { toastSide = "right", dnd = false, showText = false }

  local function loadSettings()
    local ok = pcall(function()
      if not fs.exists(settingsPath) then return end
      local h = fs.open(settingsPath, "r")
      if not h then return end
      local raw = h.readAll()
      h.close()
      local t = textutils.unserialiseJSON(raw or "")
      if type(t) ~= "table" then return end
      if t.toastSide == "left" or t.toastSide == "right" then S.toastSide = t.toastSide end
      S.dnd = t.dnd == true
      S.showText = t.showText == true
    end)
    return ok
  end

  local function saveSettings()
    pcall(function()
      fs.makeDir(fs.getDir(settingsPath))
      local h = fs.open(settingsPath, "w")
      if not h then return end
      h.write(textutils.serialiseJSON(S))
      h.close()
    end)
  end

  loadSettings()

  -- -------------------------------------------------------------- drawing

  local function put(x, y, s, fg, bg)
    if y < 1 or y > H or x > W or s == "" then return end
    if x < 1 then
      s = s:sub(2 - x)
      x = 1
    end
    s = s:sub(1, W - x + 1)
    if s == "" then return end
    native.setCursorPos(x, y)
    native.setBackgroundColor(bg or C.black)
    native.setTextColor(fg or C.white)
    native.write(s)
  end

  local function pad(s, n)
    s = tostring(s)
    if #s >= n then return s:sub(1, n) end
    return s .. string.rep(" ", n - #s)
  end

  local function wrap(text, width, maxLines)
    local lines, line = {}, ""
    for w0 in tostring(text):gmatch("%S+") do
      local word = w0
      while #word > width do
        if line ~= "" then lines[#lines + 1] = line line = "" end
        lines[#lines + 1] = word:sub(1, width)
        word = word:sub(width + 1)
      end
      if line == "" then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. " " .. word
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    while #lines > maxLines do table.remove(lines) end
    return lines
  end

  -- ---------------------------------------------------------------- state

  local menu = nil        -- { kind, sel, scroll, shown, sig }
  local toast = nil       -- current toast
  local toastQ = {}
  local unread = 0
  local netText = cfg.netText or "--"

  local TW, TH = 24, 3    -- toast size
  local PW, PH = 31, 8    -- cabinet preview size

  -- ---------------------------------------------------------- base repaint

  -- Put back whatever sits under overlays: the focused app, or the dashboard.
  local function refreshBase()
    if K.getFocus() then
      if K.overlay then
        K.setOverlay(false)
        K.setOverlay(true)
      else
        K.redrawFocused()
      end
    else
      paintDashboard()
    end
  end

  -- ------------------------------------------------------------- top bar

  local function focusedInfo()
    for _, p in ipairs(K.list()) do
      if p.focused then return p end
    end
    return nil
  end

  local function drawBar()
    local f = focusedInfo()
    local name = "Home"
    if f then name = f.name .. (f.alive and "" or "!") end
    local appsOpen = menu and (menu.kind == "apps" or menu.kind == "settings" or menu.kind == "history")
    local switchOpen = menu and menu.kind == "switch"

    put(1, 1, "[= Apps]", C.white, appsOpen and C.cyan or C.blue)

    local cw = W - 8 - 12
    local label = "[v Active: " .. name .. "]"
    if #label > cw then label = label:sub(1, cw - 1) .. "]" end
    local lp = floor((cw - #label) / 2)
    put(9, 1, string.rep(" ", lp) .. label .. string.rep(" ", cw - lp - #label),
      C.white, switchOpen and C.cyan or C.gray)

    local badge = (unread > 0) and ("*" .. min(unread, 9)) or netText
    local clock = os.date("%H:%M")
    put(W - 11, 1, "[H] " .. clock .. " " .. pad(badge, 2), C.white, C.gray)
  end

  -- --------------------------------------------------------------- actions

  local function closeMenu()
    menu = nil
    K.setOverlay(false)
    if not K.getFocus() then paintDashboard() end
  end

  local function startReveal(m, total)
    m.shown = 0
    local function step()
      if menu ~= m then return end
      m.shown = m.shown + 1
      if m.shown < total then K.after(0.03, step) end
    end
    K.after(0.03, step)
  end

  local function openMenu(kind)
    local hadToast = toast ~= nil
    toast = nil
    menu = { kind = kind, sel = 1, scroll = 0, shown = 0 }
    K.setOverlay(true)
    if hadToast then refreshBase() end
    if kind == "apps" or kind == "settings" or kind == "history" then
      startReveal(menu, 20)
    else
      menu.shown = 99
      local list = K.list()
      menu.sel = 1
      for i, p in ipairs(list) do
        if p.focused then menu.sel = i end
      end
    end
    if kind == "history" then unread = 0 end
  end

  local function toggleMenu(kind)
    if menu and menu.kind == kind then
      closeMenu()
    elseif menu then
      menu = nil
      refreshBase()
      openMenu(kind)
    else
      openMenu(kind)
    end
  end

  local function goHome()
    if menu then closeMenu() end
    K.focus(nil)
    paintDashboard()
  end

  local function focusPid(pid)
    menu = nil
    K.setOverlay(false)
    K.focus(pid)
    if not pid then paintDashboard() end
  end

  local function launch(a)
    local class = a.class or "app"
    if class == "service" then
      for _, p in ipairs(K.list()) do
        if p.name == a.name then
          K.notifySystem(a.name, "Already running", "info", p.pid)
          return
        end
      end
    end
    local spec = { name = a.name, path = a.path, class = class, pinned = a.pinned, args = a.args }
    local pid, err = K.spawn(spec)
    if not pid then
      K.notifySystem("Cannot start " .. a.name, err or "unknown error", "warn")
      return
    end
    if class == "app" then focusPid(pid) end
  end

  local function stopProc(p)
    if p.alive then
      K.kill(p.pid)
    else
      K.dismiss(p.pid)
    end
  end

  -- -------------------------------------------------------------- menu rows

  local function settingsRows()
    local rows = {}
    rows[#rows + 1] = { text = "SETTINGS", hdr = true }
    rows[#rows + 1] = {
      text = "Toasts slide in: " .. S.toastSide,
      act = function()
        S.toastSide = (S.toastSide == "right") and "left" or "right"
        saveSettings()
      end,
    }
    rows[#rows + 1] = {
      text = "Do not disturb: " .. (S.dnd and "on" or "off"),
      act = function() S.dnd = not S.dnd saveSettings() end,
    }
    rows[#rows + 1] = {
      text = "Show message text: " .. (S.showText and "on" or "off"),
      act = function() S.showText = not S.showText saveSettings() end,
    }
    rows[#rows + 1] = {
      text = "Notification history (" .. #K.notifications .. ")",
      act = function() toggleMenu("history") end,
    }
    rows[#rows + 1] = { text = "< Back", act = function() toggleMenu("apps") end }
    return rows
  end

  local function historyRows()
    local rows = {}
    rows[#rows + 1] = { text = "NOTIFICATIONS", hdr = true,
      right = { text = "[Clear]", act = function()
        for i = #K.notifications, 1, -1 do K.notifications[i] = nil end
      end } }
    local list = K.notifications
    if #list == 0 then rows[#rows + 1] = { text = "  none", dim = true } end
    for i = #list, 1, -1 do
      local n = list[i]
      local mark = n.level == "error" and "!" or (n.level == "warn" and "~" or " ")
      local fg = n.level == "error" and C.red or (n.level == "warn" and C.yellow or C.white)
      local body = n.title
      if n.private and not S.showText then body = "(message)" end
      rows[#rows + 1] = {
        text = mark .. n.from .. ": " .. body, fg = fg,
        act = n.pid and function() focusPid(n.pid) end or nil,
      }
    end
    rows[#rows + 1] = { text = "< Back", act = function() toggleMenu("settings") end }
    return rows
  end

  local function appRows()
    local rows = {}
    rows[#rows + 1] = { text = "START NEW PROGRAM", hdr = true }
    local full = K.appCount() >= K.MAX_APPS
    for _, a in ipairs(apps) do
      local blocked = full and (a.class or "app") == "app"
      rows[#rows + 1] = {
        text = a.name .. (blocked and " (full)" or ""),
        dim = blocked,
        act = function() launch(a) end,
      }
    end
    rows[#rows + 1] = { text = "RUNNING (" .. K.appCount() .. "/" .. K.MAX_APPS .. ")", hdr = true }
    local list = K.list()
    if #list == 0 then rows[#rows + 1] = { text = "  none", dim = true } end
    for _, p in ipairs(list) do
      local flag = ""
      if not p.alive then flag = (p.exitKind == "crashed") and " !" or " x" end
      if p.restartIn then flag = flag .. " (" .. math.ceil(p.restartIn) .. "s)" end
      local r = {
        text = p.name .. flag,
        fg = (p.exitKind == "crashed") and C.red or nil,
        act = function() focusPid(p.pid) end,
      }
      if p.pinned then
        r.right = { text = "pinned", dim = true }
      else
        r.right = { text = p.alive and "[Stop]" or "[Close]", act = function() stopProc(p) end }
      end
      rows[#rows + 1] = r
    end
    rows[#rows + 1] = { text = "More...", act = function() toggleMenu("settings") end }
    return rows
  end

  local function buildRows(kind)
    if kind == "settings" then return settingsRows() end
    if kind == "history" then return historyRows() end
    return appRows()
  end

  local function panelRect(kind, nrows)
    local pw = (kind == "history") and 44 or (kind == "settings" and 32 or 26)
    pw = min(pw, W)
    local vis = min(nrows, H - 1)
    return 1, 2, pw, vis
  end

  local function selectable(r)
    return not r.hdr and not r.dim and r.act ~= nil
  end

  -- ---------------------------------------------------------- menu drawing

  local function drawRowsMenu()
    local rows = buildRows(menu.kind)
    menu.rows = rows
    if menu.sel > #rows then menu.sel = #rows end
    if menu.sel < 1 or not selectable(rows[menu.sel]) then
      menu.sel = 1
      for i, r in ipairs(rows) do
        if selectable(r) then menu.sel = i break end
      end
    end
    local px, py, pw, vis = panelRect(menu.kind, #rows)
    -- keep the selected row in view
    if menu.sel <= menu.scroll then menu.scroll = menu.sel - 1 end
    if menu.sel > menu.scroll + vis then menu.scroll = menu.sel - vis end
    menu.scroll = max(0, min(menu.scroll, #rows - vis))

    local sig = menu.kind .. ":" .. #rows .. ":" .. vis
    if menu.sig and menu.sig ~= sig then refreshBase() end
    menu.sig = sig

    local revealed = min(vis, menu.shown)
    for i = 1, revealed do
      local idx = menu.scroll + i
      local r = rows[idx]
      local fg, bg = r.fg or C.white, C.black
      if r.hdr then
        bg, fg = C.blue, C.white
      elseif r.dim then
        fg = C.gray
      end
      if idx == menu.sel then bg, fg = C.lightBlue, C.black end
      put(px, py + i - 1, pad(" " .. r.text, pw), fg, bg)
      if r.right then
        local rfg = r.right.dim and C.gray or fg
        if idx ~= menu.sel and not r.hdr and not r.right.dim then rfg = C.orange end
        put(px + pw - #r.right.text - 1, py + i - 1, r.right.text, rfg, bg)
      end
    end
    if revealed < vis then
      put(px, py + revealed, string.rep(" ", pw), C.white, C.cyan)
    end
  end

  -- Shrunk copy of a process's last frame for the cabinet preview.
  local function drawPreview(pid, x, y)
    local snap = K.snapshot(pid)
    if not snap then
      for j = 1, PH do put(x, y + j - 1, pad(j == 1 and " (no preview)" or "", PW), C.gray, C.black) end
      return
    end
    for j = 1, PH do
      local sy = floor((j - 1) * snap.h / PH) + 1
      local row = snap.rows[sy]
      local t, f, b = {}, {}, {}
      for i = 1, PW do
        local sx = floor((i - 1) * snap.w / PW) + 1
        t[i] = row.text:sub(sx, sx)
        f[i] = row.fg:sub(sx, sx)
        b[i] = row.bg:sub(sx, sx)
      end
      native.setCursorPos(x, y + j - 1)
      native.blit(table.concat(t), table.concat(f), table.concat(b))
    end
  end

  local function cabinetRect(n)
    local x = floor((W - PW) / 2) + 1
    return x, 2, n
  end

  local function drawCabinet()
    local list = K.list()
    local n = min(#list, 9)
    menu.list = list
    if menu.sel > n then menu.sel = n end
    if menu.sel < 1 then menu.sel = 1 end
    local sig = "switch:" .. n .. ":" .. menu.sel
    if menu.sig and menu.sig ~= sig then refreshBase() end
    menu.sig = sig
    local x, y = cabinetRect(n)
    if n == 0 then
      put(x, y, pad(" No programs running", PW), C.gray, C.black)
      return
    end
    local row = y
    for i = 1, n do
      local p = list[i]
      local flag = ""
      if not p.alive then flag = (p.exitKind == "crashed") and " !" or " x" end
      if p.pinned then flag = flag .. " (pinned)" end
      local text = " " .. i .. ": " .. p.name .. flag
      if i == menu.sel then
        put(x, row, pad(text, PW), C.black, C.lightBlue)
        drawPreview(p.pid, x, row + 1)
        row = row + 1 + PH
      else
        put(x, row, pad(text, PW), C.white, p.focused and C.blue or C.gray)
        row = row + 1
      end
    end
  end

  -- ------------------------------------------------------------- crash card

  local CW, CH = 40, 7

  local function crashedFocus()
    if menu then return nil end
    local f = focusedInfo()
    if f and not f.alive and f.exitKind == "crashed" and f.class == "app" then return f end
    return nil
  end

  local function cardRect()
    local x = floor((W - CW) / 2) + 1
    local y = floor((H - CH) / 2) + 1
    return x, y
  end

  local function drawCard(f)
    local x, y = cardRect()
    put(x, y, pad(" App crashed: " .. f.name, CW), C.white, C.red)
    local err = tostring(f.err or "unknown error"):gsub("^[^:]*:%d+: ", "")
    local lines = wrap(err, CW - 2, 3)
    for i = 1, 4 do
      put(x, y + i, pad(" " .. (lines[i] or ""), CW), C.white, C.black)
    end
    put(x, y + 5, pad("", CW), C.white, C.black)
    put(x + 2, y + 5, "[Restart]", C.black, C.lime)
    put(x + CW - 10, y + 5, "[Close]", C.white, C.orange)
    put(x, y + 6, pad(" R restarts, C closes", CW), C.lightGray, C.black)
  end

  -- ------------------------------------------------------------------ toasts

  local function toastX(off)
    if S.toastSide == "right" then return W - TW + 1 + off end
    return 1 - off
  end

  local function toastOffset()
    return floor((1 - toast.p) * TW + 0.5)
  end

  local function drawToast()
    if not toast or menu then return end
    local n = toast.n
    local x = toastX(toastOffset())
    local lvl = n.level
    local accent = (lvl == "error") and C.red or (lvl == "warn" and C.yellow or C.cyan)
    local titleBg = n.system and C.blue or C.gray
    local head = (n.system and "SYSTEM" or n.from) .. ": " .. n.title
    if toast.count > 1 then head = head .. " x" .. toast.count end
    put(x, 2, " " .. pad(head, TW - 1), C.white, titleBg)
    local body = n.text
    if n.private and not S.showText then body = "Open to read" end
    local lines = wrap(body, TW - 2, 2)
    for i = 1, 2 do
      put(x, 2 + i, " " .. pad(lines[i] or "", TW - 1), C.white, C.black)
    end
    for i = 0, TH - 1 do put(x, 2 + i, " ", C.black, accent) end
  end

  local function toastRect()
    local x = toastX(toastOffset())
    return x, 2, x + TW - 1, 2 + TH - 1
  end

  local function frame(tk)
    if toast ~= tk then return end
    local function later() K.after(0.05, function() frame(tk) end) end
    if tk.phase == "in" then
      tk.p = tk.p + 0.2
      if tk.p >= 1 then
        tk.p = 1
        tk.phase = "hold"
        K.after(tk.hold, function()
          if toast == tk and tk.phase == "hold" then
            tk.phase = "out"
            later()
          end
        end)
        return
      end
      later()
    elseif tk.phase == "out" then
      tk.p = tk.p - 0.2
      if tk.p <= 0 then
        toast = nil
        refreshBase()
        return
      end
      refreshBase()
      later()
    end
  end

  local function dismissToast()
    if toast and toast.phase ~= "out" then
      toast.phase = "out"
      local tk = toast
      K.after(0.05, function() frame(tk) end)
    end
  end

  local function pump()
    if toast or menu or #toastQ == 0 then return end
    local n = table.remove(toastQ, 1)
    local count = 1
    -- merge repeats of the same message waiting behind it
    while toastQ[1] and toastQ[1].from == n.from and toastQ[1].title == n.title do
      n = table.remove(toastQ, 1)
      count = count + 1
    end
    toast = { n = n, phase = "in", p = 0, count = count, hold = (n.level == "error") and 6 or 3.5 }
    local tk = toast
    K.after(0.05, function() frame(tk) end)
  end

  local function enqueue(n)
    unread = unread + 1
    if S.dnd then return end
    if n.pid and not n.system and n.pid == K.getFocus() then
      unread = max(0, unread - 1) -- user is already looking at the sender
      return
    end
    toastQ[#toastQ + 1] = n
    if #toastQ > 20 then table.remove(toastQ, 1) end
  end

  -- ------------------------------------------------------------ input

  local function inRect(x, y, x1, y1, x2, y2)
    return x >= x1 and x <= x2 and y >= y1 and y <= y2
  end

  local function barClick(x)
    if x <= 8 then
      toggleMenu("apps")
    elseif x >= W - 11 and x <= W - 9 then
      goHome()
    elseif x >= 9 and x <= W - 12 then
      toggleMenu("switch")
    end
  end

  local function activate(r, x, pw)
    if not r then return end
    if r.right and r.right.act and x >= pw - #r.right.text - 1 then
      r.right.act()
    elseif selectable(r) then
      r.act()
    elseif r.hdr and r.right and r.right.act and x >= pw - #r.right.text - 1 then
      r.right.act()
    end
  end

  local function menuClick(x, y)
    if menu.kind == "switch" then
      local list = menu.list or K.list()
      local n = min(#list, 9)
      local cx, cy = cabinetRect(n)
      local row = cy
      for i = 1, n do
        if i == menu.sel then
          if inRect(x, y, cx, row, cx + PW - 1, row + PH) then
            focusPid(list[i].pid)
            return
          end
          row = row + 1 + PH
        else
          if inRect(x, y, cx, row, cx + PW - 1, row) then
            menu.sel = i
            return
          end
          row = row + 1
        end
      end
      closeMenu()
      return
    end
    local rows = menu.rows or {}
    local px, py, pw, vis = panelRect(menu.kind, #rows)
    if inRect(x, y, px, py, px + pw - 1, py + min(vis, menu.shown) - 1) then
      local idx = menu.scroll + (y - py) + 1
      if rows[idx] and selectable(rows[idx]) then menu.sel = idx end
      activate(rows[idx], x - px + 1, pw)
    else
      closeMenu()
    end
  end

  local function moveSel(dir)
    if menu.kind == "switch" then
      local n = min(#(menu.list or K.list()), 9)
      if n > 0 then menu.sel = ((menu.sel - 1 + dir) % n) + 1 end
      return
    end
    local rows = menu.rows or {}
    local i = menu.sel
    for _ = 1, #rows do
      i = i + dir
      if i < 1 or i > #rows then return end
      if selectable(rows[i]) then menu.sel = i return end
    end
  end

  local function handleClick(x, y)
    if y == 1 then
      barClick(x)
      return true
    end
    if menu then
      menuClick(x, y)
      return true
    end
    local f = crashedFocus()
    if f then
      local cx, cy = cardRect()
      if inRect(x, y, cx, cy, cx + CW - 1, cy + CH - 1) then
        if y == cy + 5 then
          if x >= cx + 2 and x <= cx + 10 then
            K.restart(f.pid)
          elseif x >= cx + CW - 10 and x <= cx + CW - 4 then
            K.dismiss(f.pid)
            paintDashboard()
          end
        end
        return true
      end
    end
    if toast and toast.p > 0 then
      local x1, y1, x2, y2 = toastRect()
      if inRect(x, y, x1, y1, x2, y2) then
        local pid = toast.n.pid
        dismissToast()
        if pid then K.focus(pid) end
        return true
      end
    end
    return false
  end

  local function handleKey(k)
    if k == keys.leftAlt then toggleMenu("apps") return true end
    if k == keys.rightAlt then toggleMenu("switch") return true end
    if menu then
      if k == keys.up then moveSel(-1)
      elseif k == keys.down then moveSel(1)
      elseif k == keys.backspace then closeMenu()
      elseif k == keys.enter then
        if menu.kind == "switch" then
          local p = (menu.list or {})[menu.sel]
          if p then focusPid(p.pid) end
        else
          local r = (menu.rows or {})[menu.sel]
          if r and selectable(r) then r.act() end
        end
      end
      return true
    end
    local f = crashedFocus()
    if f then
      if k == keys.r then K.restart(f.pid) return true end
      if k == keys.c then K.dismiss(f.pid) paintDashboard() return true end
    end
    return false
  end

  -- ------------------------------------------------------------------ hooks

  local hooks = {}

  hooks.onStart = function()
    paintDashboard()
  end

  hooks.onEvent = function(ev)
    local name = ev[1]
    if name == "term_resize" then
      W, H = native.getSize()
      return false
    end
    if name == "mouse_click" then
      return handleClick(ev[3], ev[4])
    end
    if name == "mouse_up" or name == "mouse_drag" then
      return menu ~= nil or ev[4] == 1
    end
    if name == "mouse_scroll" then
      if menu and menu.kind ~= "switch" then
        menu.scroll = max(0, min(menu.scroll + ev[2], max(0, #(menu.rows or {}) - 1)))
      end
      return menu ~= nil or ev[4] == 1
    end
    if name == "key" then
      return handleKey(ev[2])
    end
    if name == "key_up" or name == "char" or name == "paste" then
      return menu ~= nil
    end
    return false
  end

  hooks.onFocus = function(pid)
    if pid == nil then paintDashboard() end
  end

  hooks.onNotify = function(n)
    enqueue(n)
  end

  hooks.onTick = function()
    pump()
    drawBar()
    if menu then
      native.setCursorBlink(false)
      if menu.kind == "switch" then drawCabinet() else drawRowsMenu() end
      return
    end
    local f = crashedFocus()
    if f then drawCard(f) end
    drawToast()
    if toast or f then
      native.setCursorBlink(false)
    else
      K.restoreCursor()
    end
  end

  return { hooks = hooks, settings = S }
end

return M
