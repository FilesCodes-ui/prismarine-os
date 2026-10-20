-- /prismarine/ui/ui.lua
-- Prismarine OS v23, stage 3: top bar, App Manager, program switcher, crash
-- card and slide-in toasts. Panels, outlines and animations go through
-- gfx.lua (Pixelbox). If Pixelbox is missing the same layout draws with plain
-- cells and the old text dashboard.
--
--   local ui = dofile("/prismarine/ui/ui.lua").create(K, {
--     apps = { { name = "Counter", path = "/x.lua" }, ... },
--     paintDashboard = function() ... end,   -- used only without Pixelbox
--     dashHint = "text under the logo",
--   })
--   K.run(ui.hooks)
--
-- While a menu is open the focused app's window is hidden (K.setOverlay) so the
-- app keeps drawing into its buffer without painting over the menu.

local M = {}

function M.create(K, cfg)
  cfg = cfg or {}
  local apps = cfg.apps or {}
  local paintDashboard = cfg.paintDashboard or function() end
  local settingsPath = cfg.settingsPath or "/prismarine/data/ui_settings.json"
  local dashHint = cfg.dashHint or "Left Alt: Apps   Right Alt: Switch"

  local native = term.native()
  local W, H = native.getSize()

  local floor, min, max = math.floor, math.min, math.max

  local G = cfg.gfx or dofile("/prismarine/ui/gfx.lua")
  local gfxOK = G.init(cfg.themePath)
  local C = G.c

  -- ------------------------------------------------------------ settings

  local S = { toastSide = "right", dnd = false, showText = false, anim = true }

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
      if t.anim == false then S.anim = false end
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

  local function animOn()
    return G.opts.animations and S.anim
  end

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
    native.setBackgroundColor(bg or C.bg)
    native.setTextColor(fg or C.text)
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

  local menu = nil        -- { kind, sel, scroll, slide, sig, spr, sprSig }
  local toast = nil       -- current toast
  local toastQ = {}
  local unread = 0
  local netText = cfg.netText or "--"
  local card = nil        -- { pid, slide, spr, sig }

  local TW, TH = 24, 3    -- toast inner size
  local TWo, THo = TW + 2, TH + 2
  local PW = 31           -- switcher inner width

  -- ------------------------------------------------------------ dashboard

  local dash = { spr = nil, last = 0, visible = false }

  local function dashRender()
    if not gfxOK then return end
    if not dash.spr or dash.spr.w ~= W or dash.spr.h ~= H - 1 then
      dash.spr = G.sprite(W, H - 1)
    end
    local t = os.clock()
    if G.isRainbow() or not G.sceneOn then G.applyScene(t) end
    dash.spr:dash(animOn() and t or 0, dashHint)
    dash.last = t
  end

  local function dashPaintAll()
    if not gfxOK then
      paintDashboard()
      return
    end
    if not G.sceneOn then G.applyScene(os.clock()) end
    if not dash.spr then dashRender() end
    dash.spr:present(1, 2)
  end

  local function showDash()
    dash.visible = true
    dashPaintAll()
  end

  -- Keeps the logo moving: shine, ripple and bubbles.
  local function dashTick()
    if not gfxOK or K.getFocus() then return end
    if not animOn() then
      if not dash.spr then
        dashRender()
        dash.spr:present(1, 2)
      end
      return
    end
    local now = os.clock()
    if dash.spr and now - dash.last < 1 / G.opts.fps then return end
    dashRender()
    dash.spr:present(1, 2)
  end

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
      showDash()
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

    put(1, 1, "[= Apps]", C.barText, appsOpen and C.barOn or C.barBtn)

    local cw = W - 8 - 12
    local label = "[v Active: " .. name .. "]"
    if #label > cw then label = label:sub(1, cw - 1) .. "]" end
    local lp = floor((cw - #label) / 2)
    put(9, 1, string.rep(" ", lp) .. label .. string.rep(" ", cw - lp - #label),
      C.barText, switchOpen and C.barOn or C.bar)

    local badge = (unread > 0) and ("*" .. min(unread, 9)) or netText
    local clock = os.date("%H:%M")
    put(W - 11, 1, "[H] " .. clock .. " " .. pad(badge, 2), C.barText, C.bar)
  end

  -- --------------------------------------------------------------- actions

  local function closeMenu()
    menu = nil
    K.setOverlay(false)
    if not K.getFocus() then showDash() end
  end

  -- Menus slide in: apps from the left, the switcher from under the bar.
  local function startSlide(m, instant)
    if instant or not animOn() then
      m.slide = 1
      return
    end
    m.slide = 0
    local function step()
      if menu ~= m then return end
      m.slide = min(1, m.slide + 0.25)
      if m.slide < 1 then K.after(0.03, step) end
    end
    K.after(0.03, step)
  end

  local function openMenu(kind, instant)
    local hadToast = toast ~= nil
    toast = nil
    menu = { kind = kind, sel = 1, scroll = 0, slide = 0 }
    K.setOverlay(true)
    if hadToast then refreshBase() end
    startSlide(menu, instant)
    if kind == "switch" then
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
      local instant = menu.kind ~= "switch" and kind ~= "switch"
      menu = nil
      refreshBase()
      openMenu(kind, instant)
    else
      openMenu(kind)
    end
  end

  local function goHome()
    if menu then closeMenu() end
    K.focus(nil)
    showDash()
  end

  local function focusPid(pid)
    menu = nil
    K.setOverlay(false)
    K.focus(pid)
    if not pid then showDash() end
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
      text = "Animations: " .. (S.anim and "on" or "off"),
      act = function() S.anim = not S.anim saveSettings() end,
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
      local fg = n.level == "error" and C.err or (n.level == "warn" and C.warn or C.text)
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
        fg = (p.exitKind == "crashed") and C.err or nil,
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

  -- Inner area of the panel: x, y of the first text cell, text width, rows.
  -- The outline ring is one cell wider on every side.
  local function panelRect(kind, nrows)
    local pw = (kind == "history") and 44 or (kind == "settings" and 32 or 26)
    pw = min(pw, W - 2)
    local vis = min(nrows, H - 4)
    return 2, 3, pw, vis
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
    local ix, iy, pw, vis = panelRect(menu.kind, #rows)
    -- keep the selected row in view
    if menu.sel <= menu.scroll then menu.scroll = menu.sel - 1 end
    if menu.sel > menu.scroll + vis then menu.scroll = menu.sel - vis end
    menu.scroll = max(0, min(menu.scroll, #rows - vis))

    local sig = menu.kind .. ":" .. #rows .. ":" .. vis
    if menu.sig and menu.sig ~= sig then refreshBase() end
    menu.sig = sig

    local ow, oh = pw + 2, vis + 2
    local parts = { menu.sel, menu.scroll, pw, vis }
    for i = 1, vis do
      local r = rows[menu.scroll + i]
      parts[#parts + 1] = r.text .. "|" .. tostring(r.fg) .. (r.hdr and "h" or "")
        .. (r.dim and "d" or "") .. (r.right and r.right.text or "")
    end
    local fullsig = table.concat(parts, "\n")
    if not menu.spr or menu.spr.w ~= ow or menu.spr.h ~= oh or menu.sprSig ~= fullsig then
      if not menu.spr or menu.spr.w ~= ow or menu.spr.h ~= oh then
        menu.spr = G.sprite(ow, oh)
      end
      local spr = menu.spr
      spr:panel(C.panel, C.line)
      for i = 1, vis do
        local idx = menu.scroll + i
        local r = rows[idx]
        local fg, bg = r.fg or C.text, C.panel
        if r.hdr then
          bg, fg = C.hdr, C.text
        elseif r.dim then
          fg = C.dim
        end
        if idx == menu.sel then bg, fg = C.sel, C.selText end
        spr:text(2, i + 1, pad(" " .. r.text, pw), fg, bg)
        if r.right then
          local rfg = r.right.dim and C.dim or fg
          if idx ~= menu.sel and not r.hdr and not r.right.dim then rfg = C.accent end
          spr:text(2 + pw - #r.right.text - 1, i + 1, r.right.text, rfg, bg)
        end
      end
      menu.sprSig = fullsig
    end
    local e = 1 - (1 - menu.slide) ^ 3
    menu.spr:present(1 - floor((1 - e) * ow + 0.5), 2)
  end

  local function cabinetRect(n)
    local ow = PW + 2
    local x = floor((W - ow) / 2) + 1
    return x, 2, max(n, 1)
  end

  local function drawCabinet()
    local list = K.list()
    local n = min(#list, 9)
    menu.list = list
    if menu.sel > n then menu.sel = n end
    if menu.sel < 1 then menu.sel = 1 end
    local sig = "switch:" .. n
    if menu.sig and menu.sig ~= sig then refreshBase() end
    menu.sig = sig

    local ox, oy, nrows = cabinetRect(n)
    local ow, oh = PW + 2, nrows + 2
    local parts = { menu.sel, n }
    for i = 1, n do
      local p = list[i]
      parts[#parts + 1] = p.name .. tostring(p.alive) .. tostring(p.exitKind) .. tostring(p.focused)
    end
    local fullsig = table.concat(parts, "\n")
    if not menu.spr or menu.spr.w ~= ow or menu.spr.h ~= oh or menu.sprSig ~= fullsig then
      if not menu.spr or menu.spr.w ~= ow or menu.spr.h ~= oh then
        menu.spr = G.sprite(ow, oh)
      end
      local spr = menu.spr
      spr:panel(C.panel, C.line)
      if n == 0 then
        spr:text(2, 2, pad(" No programs running", PW), C.dim, C.panel)
      end
      for i = 1, n do
        local p = list[i]
        local flag = ""
        if not p.alive then flag = (p.exitKind == "crashed") and " !" or " x" end
        if p.pinned or p.class == "service" then flag = flag .. " (service)" end
        local text = " " .. i .. ": " .. p.name .. flag
        if i == menu.sel then
          spr:text(2, i + 1, pad(text, PW), C.selText, C.sel)
        else
          spr:text(2, i + 1, pad(text, PW), C.text, p.focused and C.hdr or C.bar)
        end
      end
      menu.sprSig = fullsig
    end
    local e = 1 - (1 - menu.slide) ^ 3
    menu.spr:present(ox, oy - floor((1 - e) * oh + 0.5), nil, nil, 2)
  end

  -- ------------------------------------------------------------- crash card

  local CW, CH = 40, 7   -- inner size

  local function crashedFocus()
    if menu then return nil end
    local f = focusedInfo()
    if f and not f.alive and f.exitKind == "crashed" and f.class == "app" then return f end
    return nil
  end

  -- First text cell of the card (the outline ring sits one cell outside).
  local function cardRect()
    local x = floor((W - (CW + 2)) / 2) + 2
    local y = floor((H - (CH + 2)) / 2) + 2
    return x, y
  end

  local function drawCard(f)
    if not card or card.pid ~= f.pid then
      card = { pid = f.pid, slide = animOn() and 0 or 1 }
      if card.slide < 1 then
        local c = card
        local function step()
          if card ~= c then return end
          c.slide = min(1, c.slide + 0.25)
          refreshBase()
          if c.slide < 1 then K.after(0.03, step) end
        end
        K.after(0.03, step)
      end
    end
    local x, y = cardRect()
    local err = tostring(f.err or "unknown error"):gsub("^[^:]*:%d+: ", "")
    local sig = f.name .. "|" .. err
    if not card.spr or card.sig ~= sig then
      local spr = G.sprite(CW + 2, CH + 2)
      spr:panel(C.panel, C.err)
      spr:text(2, 2, pad(" App crashed: " .. f.name, CW), C.text, C.err)
      local lines = wrap(err, CW - 2, 3)
      for i = 1, 4 do
        spr:text(2, 2 + i, pad(" " .. (lines[i] or ""), CW), C.text, C.panel)
      end
      spr:text(2, 7, pad("", CW), C.text, C.panel)
      spr:text(4, 7, "[Restart]", C.bg, C.ok)
      spr:text(2 + CW - 10, 7, "[Close]", C.text, C.accent)
      spr:text(2, 8, pad(" R restarts, C closes", CW), C.hint, C.panel)
      card.spr = spr
      card.sig = sig
    end
    local e = 1 - (1 - card.slide) ^ 3
    card.spr:present(x - 1, (y - 1) - floor((1 - e) * (CH + 2 + y) + 0.5), nil, nil, 2)
  end

  -- ------------------------------------------------------------------ toasts

  local function toastX(off)
    if S.toastSide == "right" then return W - TWo + 1 + off end
    return 1 - off
  end

  local function toastOffset()
    return floor((1 - toast.p) * TWo + 0.5)
  end

  local function buildToast(tk)
    local n = tk.n
    local lvl = n.level
    local accent = (lvl == "error") and C.err or (lvl == "warn" and C.warn or C.info)
    local titleBg = n.system and C.toastSys or C.toastBar
    local head = (n.system and "SYSTEM" or n.from) .. ": " .. n.title
    if tk.count > 1 then head = head .. " x" .. tk.count end
    local spr = G.sprite(TWo, THo)
    spr:panel(C.panel, accent)
    spr:text(2, 2, " " .. pad(head, TW - 1), C.text, titleBg)
    local body = n.text
    if n.private and not S.showText then body = "Open to read" end
    local lines = wrap(body, TW - 2, 2)
    for i = 1, 2 do
      spr:text(2, 2 + i, " " .. pad(lines[i] or "", TW - 1), C.text, C.panel)
    end
    tk.spr = spr
  end

  local function drawToast()
    if not toast or menu then return end
    toast.spr:present(toastX(toastOffset()), 2)
  end

  local function toastRect()
    local x = toastX(toastOffset())
    return x, 2, x + TWo - 1, 2 + THo - 1
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
    buildToast(toast)
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
    if menu.slide < 1 then return end
    if menu.kind == "switch" then
      local list = menu.list or K.list()
      local n = min(#list, 9)
      local ox, oy, nrows = cabinetRect(n)
      local oh = nrows + 2
      if not inRect(x, y, ox, oy, ox + PW + 1, oy + oh - 1) then
        closeMenu()
        return
      end
      if n > 0 and inRect(x, y, ox + 1, oy + 1, ox + PW, oy + n) then
        focusPid(list[y - oy].pid)
      end
      return
    end
    local rows = menu.rows or {}
    local ix, iy, pw, vis = panelRect(menu.kind, #rows)
    local oh = vis + 2
    if not inRect(x, y, ix - 1, iy - 1, ix + pw, iy + vis) then
      closeMenu()
      return
    end
    if inRect(x, y, ix, iy, ix + pw - 1, iy + vis - 1) then
      local idx = menu.scroll + (y - iy) + 1
      if rows[idx] and selectable(rows[idx]) then menu.sel = idx end
      activate(rows[idx], x - ix + 1, pw)
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
      if inRect(x, y, cx - 1, cy - 1, cx + CW, cy + CH) then
        if y == cy + 5 then
          if x >= cx + 2 and x <= cx + 10 then
            K.restart(f.pid)
          elseif x >= cx + CW - 10 and x <= cx + CW - 4 then
            K.dismiss(f.pid)
            showDash()
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
      if k == keys.c then K.dismiss(f.pid) showDash() return true end
    end
    return false
  end

  -- ------------------------------------------------------------------ hooks

  local hooks = {}

  hooks.onStart = function()
    native.setBackgroundColor(colors.black)
    native.clear()
    showDash()
    -- keep the dashboard moving: one tick per frame
    local function beat()
      K.after(1 / G.opts.fps, beat)
    end
    beat()
  end

  hooks.onEvent = function(ev)
    local name = ev[1]
    if name == "term_resize" then
      W, H = native.getSize()
      dash.spr = nil
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
    if pid == nil then
      showDash()
    else
      dash.visible = false
      if gfxOK and G.sceneOn then G.restorePalette() end
    end
  end

  hooks.onNotify = function(n)
    enqueue(n)
  end

  hooks.onTick = function()
    pump()
    drawBar()
    dashTick()
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

  return {
    hooks = hooks, settings = S, graphics = gfxOK, gfx = G,
    -- call after K.run returns: puts the normal colors back
    restore = function() if gfxOK then G.restorePalette() end end,
  }
end

return M
