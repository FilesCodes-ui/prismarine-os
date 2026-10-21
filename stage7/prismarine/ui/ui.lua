--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/ui/ui.lua
-- Prismarine OS v23, stage 5: top bar, App Manager, program switcher, crash
-- card, slide-in toasts, notification sidebar and the lock screen. Panels, outlines and animations go through
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
  local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
  end

  local G = cfg.gfx or dofile("/prismarine/ui/gfx.lua")
  local gfxOK = G.init(cfg.themePath)
  local C = G.c

  -- ------------------------------------------------------------ settings

  local S = {
    toastSide = "right", dnd = false, showText = false, anim = true, haze = true,
    hour24 = true, seconds = true, showDate = true, showHint = true, showStatus = true,
    bubbles = true, shine = true, ripple = true, round = true, toastTime = 4, autoLock = 5,
    osName = "Prismarine", colors = {},
    live = "Off", saver = 0, saverMode = "Tide", saverColor = "Blue", saverLink = true, saverLogo = true,
  }
  local ROLE_NAMES = { "bar", "barBtn", "barOn", "barText", "line", "sel", "selText", "hdr", "panel", "text", "dim", "accent", "toastSys",
    "ok", "warn", "err", "info", "hint", "toastBar" }
  local SAVER_MODES = { "Tide", "Starfield", "Clock", "Logo drift" }
  local SAVER_AFTER = { 0, 1, 2, 5, 10, 15, 30 }

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
      if t.haze == false then S.haze = false end
      if type(t.theme) == "string" and G.setTheme(t.theme) then S.theme = t.theme end
      if type(t.fps) == "number" then S.fps = clamp(floor(t.fps), 2, 30) G.opts.fps = S.fps end
      if type(t.logoColor) == "string" and G.setLogoColor(t.logoColor) then S.logoColor = t.logoColor end
      for _, k in ipairs({ "hour24", "seconds", "showDate", "showHint", "showStatus", "bubbles", "shine", "ripple", "round" }) do
        if type(t[k]) == "boolean" then S[k] = t[k] end
      end
      G.opts.round = S.round
      if type(t.toastTime) == "number" then S.toastTime = clamp(floor(t.toastTime), 2, 15) end
      if type(t.autoLock) == "number" then S.autoLock = clamp(floor(t.autoLock), 0, 120) end
      if K.lockdown and K.lockdown() then
        local limit = (K.bunker and K.bunker()) and 5 or 15
        if S.autoLock == 0 or S.autoLock > limit then S.autoLock = limit end
      end
      if type(t.osName) == "string" and t.osName ~= "" then S.osName = t.osName:gsub("%c", ""):sub(1, 20) end
      if type(t.live) == "string" and G.setLive(t.live) then S.live = t.live end
      if type(t.saver) == "number" then
        for _, v in ipairs(SAVER_AFTER) do if v == t.saver then S.saver = v end end
      end
      if type(t.saverMode) == "string" then
        for _, v in ipairs(SAVER_MODES) do if v == t.saverMode then S.saverMode = v end end
      end
      if type(t.saverColor) == "string" and G.setSaverColor(t.saverColor) then S.saverColor = t.saverColor end
      if type(t.saverLink) == "boolean" then S.saverLink = t.saverLink end
      G.opts.saverLink = S.saverLink
      if type(t.saverLogo) == "boolean" then S.saverLogo = t.saverLogo end
      if type(t.colors) == "table" then
        for _, role in ipairs(ROLE_NAMES) do
          local v = t.colors[role]
          if type(v) == "string" and type(colors[v]) == "number" then
            S.colors[role] = v
            C[role] = colors[v]
          end
        end
      end
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

  local function clockText(long)
    local f
    if S.hour24 then f = (long and S.seconds) and "%H:%M:%S" or "%H:%M"
    else f = (long and S.seconds) and "%I:%M:%S %p" or "%I:%M %p" end
    local t = os.date(f)
    if long and S.showDate then t = t .. "   " .. os.date("%a %d %b") end
    return t
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
    bg = bg or C.bg
    fg = fg or C.text
    if s:find("%S") then fg = G.readable(fg, bg) end
    native.setBackgroundColor(bg)
    native.setTextColor(fg)
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
  local lock = nil        -- { on, input, msg, busy } while the lock screen shows
  local saver = nil       -- the screen saver, when it runs (see the saver section)
  local lastInput = os.clock()
  local lockNow           -- defined with the lock screen below
local function lockable() return cfg.lock ~= nil and (not cfg.lockOn or cfg.lockOn()) end
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

  -- ---------------------------------------------------------- settings API
  -- Apps reach this as prismarine.ui. Only these keys exist.
  local function applyLook()
    if gfxOK and G.sceneOn then G.applyScene(os.clock()) end
    dash.spr = nil
  end

  local DEFAULTS = { anim = true, haze = true, dnd = false, showText = false, toastSide = "right", fps = 12, logoColor = "Blue",
    saverColor = "Blue" }

  local BOOLS = { anim = true, haze = true, dnd = true, showText = true, hour24 = true, seconds = true,
    showDate = true, showHint = true, showStatus = true, bubbles = true, shine = true, ripple = true, round = true,
    saverLink = true, saverLogo = true }
  local colorNames = {}
  for name, v in pairs(colors) do if type(v) == "number" then colorNames[#colorNames + 1] = name end end
  table.sort(colorNames, function(a, b) return colors[a] < colors[b] end)

  K.uiApi = {
    logoColors = G.logoNames,
    saverColors = G.logoNames,
    themes = G.themes,
    roles = ROLE_NAMES,
    colorNames = colorNames,
    liveModes = G.liveModes,
    saverModes = SAVER_MODES,
    saverAfter = SAVER_AFTER,
    get = function()
      local cs = {}
      for _, r in ipairs(ROLE_NAMES) do
        for _, n in ipairs(colorNames) do if colors[n] == C[r] then cs[r] = n end end
      end
      return {
        theme = G.theme,
        anim = S.anim, haze = S.haze, dnd = S.dnd, showText = S.showText,
        toastSide = S.toastSide, fps = G.opts.fps, logoColor = G.opts.logoColor,
        graphics = gfxOK, width = W, height = H,
        hour24 = S.hour24, seconds = S.seconds, showDate = S.showDate, showHint = S.showHint,
        showStatus = S.showStatus, bubbles = S.bubbles, shine = S.shine, ripple = S.ripple, round = S.round,
        toastTime = S.toastTime, autoLock = S.autoLock, osName = S.osName, colors = cs,
        live = S.live, saver = S.saver, saverMode = S.saverMode,
        saverColor = G.opts.saverColor, saverLink = S.saverLink, saverLogo = S.saverLogo,
        logoRGB = G.colorRGB(G.opts.logoColor), saverRGB = G.colorRGB(G.opts.saverColor),
      }
    end,
    set = function(key, v)
      if BOOLS[key] then
        if type(v) ~= "boolean" then return false end
        S[key] = v
        if key == "round" then G.opts.round = v end
        if key == "saverLink" then G.opts.saverLink = v end
      elseif key == "saverColor" then
        if type(v) ~= "string" or not G.setSaverColor(v) then return false end
        S.saverColor = v
      elseif key == "toastTime" then
        if type(v) ~= "number" then return false end
        S.toastTime = clamp(floor(v), 2, 15)
      elseif key == "autoLock" then
        if type(v) ~= "number" then return false end
        local limit = (K.bunker and K.bunker()) and 5 or 15
        if K.lockdown and K.lockdown() and (v == 0 or v > limit) then return false end
        S.autoLock = clamp(floor(v), 0, 120)
      elseif key == "osName" then
        if type(v) ~= "string" or v == "" then return false end
        S.osName = v:gsub("%c", ""):sub(1, 20)
      elseif type(key) == "string" and key:sub(1, 6) == "color." then
        local role = key:sub(7)
        local ok = false
        for _, r in ipairs(ROLE_NAMES) do if r == role then ok = true end end
        if not ok or type(v) ~= "string" or type(colors[v]) ~= "number" then return false end
        S.colors[role] = v
        C[role] = colors[v]
        menu = nil
        K.setOverlay(false)
      elseif key == "toastSide" then
        if v ~= "left" and v ~= "right" then return false end
        S.toastSide = v
      elseif key == "fps" then
        if type(v) ~= "number" then return false end
        S.fps = clamp(floor(v), 2, 30)
        G.opts.fps = S.fps
      elseif key == "theme" then
        if type(v) ~= "string" or not G.setTheme(v) then return false end
        S.theme = v
        S.logoColor = G.opts.logoColor
        S.colors = {}
        dash.spr = nil
      elseif key == "logoColor" then
        if type(v) ~= "string" or not G.setLogoColor(v) then return false end
        S.logoColor = v
      elseif key == "live" then
        if type(v) ~= "string" or not G.setLive(v) then return false end
        S.live = v
      elseif key == "saver" then
        local ok = false
        for _, a in ipairs(SAVER_AFTER) do if a == v then ok = true end end
        if not ok then return false end
        S.saver = v
      elseif key == "saverMode" then
        local ok = false
        for _, m in ipairs(SAVER_MODES) do if m == v then ok = true end end
        if not ok then return false end
        S.saverMode = v
      else
        return false
      end
      saveSettings()
      if key == "logoColor" or key == "haze" or key == "anim" or key == "theme" or key == "live" then applyLook() end
      if key == "theme" or key == "logoColor" or key == "live" or key:sub(1, 6) == "color." then
        if K.themeChanged then K.themeChanged() end
      end
      return true
    end,
    reset = function()
      S.anim, S.haze, S.dnd, S.showText = DEFAULTS.anim, DEFAULTS.haze, DEFAULTS.dnd, DEFAULTS.showText
      S.hour24, S.seconds, S.showDate, S.showHint, S.showStatus = true, true, true, true, true
      S.bubbles, S.shine, S.ripple, S.toastTime, S.osName, S.colors = true, true, true, 4, "Prismarine", {}
      S.round = true
      G.opts.round = true
      if not (K.lockdown and K.lockdown()) then S.autoLock = 5 end
      S.toastSide, S.fps, S.logoColor = DEFAULTS.toastSide, DEFAULTS.fps, DEFAULTS.logoColor
      G.opts.fps = DEFAULTS.fps
      G.setTheme("Ocean")
      S.theme = "Ocean"
      G.setLogoColor(DEFAULTS.logoColor)
      G.setLive("Off")
      S.live, S.saver, S.saverMode = "Off", 0, "Tide"
      S.saverColor, S.saverLink, S.saverLogo = DEFAULTS.saverColor, true, true
      G.setSaverColor(DEFAULTS.saverColor)
      G.opts.saverLink = true
      saveSettings()
      applyLook()
      if K.themeChanged then K.themeChanged() end
      return true
    end,
    clearNotifications = function()
      for i = #K.notifications, 1, -1 do table.remove(K.notifications, i) end
      return true
    end,
    notificationCount = function() return #K.notifications end,
  }
  -- Every app may read the look; only Settings may change it (capability "settings").
  K.caps.ui = function(p)
    local t = { logoColors = G.logoNames, saverColors = G.logoNames, themes = G.themes, roles = ROLE_NAMES, colorNames = colorNames, get = K.uiApi.get,
      liveModes = G.liveModes, saverModes = SAVER_MODES, saverAfter = SAVER_AFTER,
      notificationCount = K.uiApi.notificationCount }
    for _, c in ipairs(p.spec.caps or {}) do
      if c == "settings" then
        t.set, t.reset, t.clearNotifications = K.uiApi.set, K.uiApi.reset, K.uiApi.clearNotifications
        t.startSaver = K.uiApi.startSaver
      end
    end
    return t
  end


  local function dashRender()
    if not gfxOK then return end
    if not dash.spr or dash.spr.w ~= W or dash.spr.h ~= H - 1 then
      dash.spr = G.sprite(W, H - 1)
    end
    local t = os.clock()
    G.liveAlerts = unread
    if not dash.boot and (G.isRainbow() or not G.sceneOn or G.sceneDue(t)) then G.applyScene(t) end
    local lk = lock and lock.on
    local hintText = lk and "" or (S.showHint and (lockable() and dashHint or dashHint:gsub("   F9: Lock", "")) or nil)
    if hintText and #hintText > W then
      if animOn() then
        -- the line is wider than the screen, so it scrolls
        local loop = hintText .. "     "
        local off = floor(t * 4) % #loop
        hintText = (loop .. loop):sub(off + 1, off + W)
      else
        hintText = hintText:gsub("Left Alt", "L-Alt"):gsub("Right Alt", "R-Alt")
      end
    end
    local status = S.showStatus and (K.appCount() .. " apps   " .. #K.notifications .. " alerts"
      .. (cfg.statusExtra and cfg.statusExtra() or "")) or nil
    dash.spr:dash({
      t = animOn() and t or 0,
      haze = S.haze,
      boot = dash.boot and dash.boot.prog or nil,
      status = lk and (S.osName .. " is locked") or status,
      clock = lk and "" or clockText(true),
      hint = hintText,
      bubbles = S.bubbles, shine = S.shine, ripple = S.ripple,
    })
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
    if not gfxOK or K.getFocus() or dash.boot then return end
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

  -- Boot splash: the logo fades in, a progress bar fills, then the hint shows.
  local function startBoot()
    local b = { t0 = os.clock(), prog = 0 }
    dash.boot = b
    dash.visible = true
    local function step()
      if dash.boot ~= b then return end
      local el = os.clock() - b.t0
      b.prog = clamp((el - 0.4) / 1.4, 0, 1)
      if el >= 1.9 then
        dash.boot = nil
        G.applyScene(os.clock())
        dashRender()
        dash.spr:present(1, 2)
        return
      end
      G.applyScene(os.clock(), clamp(el / 0.6, 0, 1))
      dashRender()
      dash.spr:present(1, 2)
      K.after(0.05, step)
    end
    step()
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
    if lock and lock.on then
      local text = " " .. S.osName .. " is locked"
      local clock = clockText(false) .. " "
      put(1, 1, pad(text, W - #clock) .. clock, C.barText, C.bar)
      return
    end
    local f = focusedInfo()
    local name = "Home"
    if f then name = f.name .. (f.alive and "" or "!") end
    local appsOpen = menu and (menu.kind == "apps" or menu.kind == "settings")
    local notesOpen = menu and menu.kind == "notes"
    local switchOpen = menu and menu.kind == "switch"

    if S.round then
      local bcol = appsOpen and C.barOn or C.barBtn
      -- With the menu open the tab and the menu are one shape: no dark strip.
      put(1, 1, "\149", appsOpen and bcol or C.bar, bcol)
      put(2, 1, "= Apps", C.barText, bcol)
      put(8, 1, "\149", bcol, C.bar)
    else
      put(1, 1, "[= Apps]", C.barText, appsOpen and C.barOn or C.barBtn)
    end

    local cw = W - 8 - 12
    local label = "[v Active: " .. name .. "]"
    if #label > cw then label = label:sub(1, cw - 1) .. "]" end
    local lp = floor((cw - #label) / 2)
    put(9, 1, string.rep(" ", lp) .. label .. string.rep(" ", cw - lp - #label),
      C.barText, switchOpen and C.barOn or C.bar)

    local nt = cfg.netText and cfg.netText() or netText
    local badge = (unread > 0) and ("*" .. min(unread, 9)) or nt
    local clock = os.date(S.hour24 and "%H:%M" or "%I:%M")
    put(W - 11, 1, "[H]", C.barText, C.bar)
    put(W - 8, 1, " " .. clock .. " " .. pad(badge, 2), C.barText, notesOpen and C.barOn or C.bar)
  end

  -- --------------------------------------------------------------- actions

  -- App slide: a frozen copy of the app window rises from the bottom (in) or
  -- sinks to the bottom (out) over what sits underneath.
  local trans = nil
  local holdPalette = false

  local function endTrans(t)
    if trans ~= t then return end
    trans = nil
    if gfxOK and K.getFocus() and G.sceneOn then G.restorePalette() end
    if t.kind == "in" and not menu and K.getFocus() == t.pid then K.setOverlay(false) end
    if t.kind == "out" then dashPaintAll() end
  end

  local function startTrans(kind, snap, under, pid)
    local t = { kind = kind, p = 0, snap = snap, under = under, pid = pid }
    trans = t
    local function frame()
      if trans ~= t then return end
      t.p = min(1, t.p + 0.18)
      local e = 1 - (1 - t.p) ^ 3
      local off = floor(((kind == "in") and (1 - e) or e) * (H - 1) + 0.5)
      if t.under == "dash" then dashPaintAll() else t.under:present(1, 2) end
      if t.p < 1 or kind == "in" then t.snap:present(1, 2 + off, nil, nil, 2) end
      if t.p >= 1 then
        endTrans(t)
        return
      end
      K.after(0.03, frame)
    end
    frame()
  end

  local function finishClose()
    menu = nil
    K.setOverlay(false)
    if not K.getFocus() then showDash() end
  end

  -- Slides the menu out, then closes it. instant = close at once.
  local function closeMenu(instant)
    if not menu then return end
    if instant or not animOn() or menu.slide < 1 or menu.closing then
      finishClose()
      return
    end
    local m = menu
    m.closing = true
    local function step()
      if menu ~= m then return end
      m.slide = m.slide - 0.25
      if m.slide <= 0 then
        finishClose()
        return
      end
      refreshBase()
      K.after(0.03, step)
    end
    step()
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
    if kind == "notes" then unread = 0 end
  end

  local function toggleMenu(kind)
    if menu and menu.closing then return end
    if menu and menu.kind == kind then
      closeMenu()
    elseif menu then
      local function left(k) return k == "apps" or k == "settings" end
      local instant = left(menu.kind) and left(kind)
      menu = nil
      refreshBase()
      openMenu(kind, instant)
    else
      openMenu(kind)
    end
  end

  local function focusPid(pid)
    local old = K.getFocus()
    local oldSnap = nil
    if gfxOK and animOn() and old and old ~= pid then
      oldSnap = G.snapshot(K.snapshot(old))
    end
    trans = nil
    menu = nil
    K.setOverlay(false)
    holdPalette = true
    K.focus(pid)
    holdPalette = false
    if gfxOK and animOn() and pid ~= old then
      if pid then
        local snap = G.snapshot(K.snapshot(pid))
        if snap then
          K.setOverlay(true)
          startTrans("in", snap, oldSnap or "dash", pid)
          return
        end
      elseif oldSnap then
        startTrans("out", oldSnap, "dash", nil)
        return
      end
    end
    if pid then
      if gfxOK and G.sceneOn then G.restorePalette() end
    else
      showDash()
    end
  end

  local function goHome()
    if menu then closeMenu(true) end
    focusPid(nil)
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
    local spec = { name = a.name, path = a.path, class = class, pinned = a.pinned, args = a.args,
      caps = a.caps, system = a.system, trusted = a.trusted, terminate = a.terminate, shell = a.shell }
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
    rows[#rows + 1] = { text = "QUICK SETTINGS", hdr = true }
    for _, a in ipairs(apps) do
      if a.name == "Settings" then
        rows[#rows + 1] = { text = "Open Settings app", act = function() closeMenu(true) launch(a) end }
      end
    end
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
      text = "Haze: " .. (S.haze and "on" or "off"),
      act = function() S.haze = not S.haze saveSettings() end,
    }
    rows[#rows + 1] = {
      text = "Logo color: " .. G.opts.logoColor,
      act = function()
        local names, at = G.logoNames, 1
        for i, n in ipairs(names) do
          if n == G.opts.logoColor then at = i end
        end
        local nxt = names[at % #names + 1]
        G.setLogoColor(nxt)
        S.logoColor = nxt
        saveSettings()
        if gfxOK and G.sceneOn then G.applyScene(os.clock()) end
      end,
    }
    rows[#rows + 1] = {
      text = "Notifications (" .. #K.notifications .. ")",
      act = function() toggleMenu("notes") end,
    }
    rows[#rows + 1] = { text = "< Back", act = function() toggleMenu("apps") end }
    return rows
  end

  local function appRows()
    local rows = {}
    rows[#rows + 1] = { text = "START NEW PROGRAM", hdr = true }
    local full = K.appCount() >= K.MAX_APPS
    for _, a in ipairs(apps) do
      if not a.hidden or not a.hidden() then
        local locked = a.locked and a.locked()
        local blocked = (full and (a.class or "app") == "app") or locked
        rows[#rows + 1] = {
          text = a.name .. (locked and " (locked)" or (blocked and " (full)" or "")),
          dim = blocked,
          act = function() launch(a) end,
        }
      end
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
    if cfg.power then
      rows[#rows + 1] = { text = "POWER", hdr = true }
      if lockable() then rows[#rows + 1] = { text = "Lock", act = function() closeMenu(true) lockNow() end } end
      rows[#rows + 1] = { text = "Reboot", act = function() cfg.power("reboot") end }
      rows[#rows + 1] = { text = "Shut down", act = function() cfg.power("shutdown") end }
    end
    return rows
  end

  local function buildRows(kind)
    if kind == "settings" then return settingsRows() end
    return appRows()
  end

  -- Inner area of the panel: x, y of the first text cell, text width, rows.
  -- The outline ring is one cell wider on every side.
  local function panelRect(kind, nrows)
    local pw = (kind == "settings") and 32 or 26
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
      -- The menu hangs from the Apps tab, so its top left corner stays square.
      spr:panel(C.panel, C.line, function(cv)
        if cv then cv[1][1] = C.line end
      end)
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

  -- The switcher sits right under the "[v Active: ...]" segment of the top
  -- bar: same left edge (column 9) and same width (W - 20).
  local function cabinetRect(n)
    PW = max(20, W - 22)
    return 9, 2, max(n, 1)
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
      -- The top edge joins the bar, so its corners stay square.
      spr:panel(C.panel, C.line, function(cv, pw)
        if cv then
          cv[1][1] = C.line
          cv[1][pw] = C.line
        end
      end)
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

  -- ------------------------------------------------ notifications sidebar
  -- A panel on the right edge. Content scrolls with the wheel, the arrow keys,
  -- or a draggable slider drawn in the last column.

  local NW = 36

  local function notesGeom()
    local ow = min(NW, W)
    return ow, H - 1, ow - 3, H - 4 -- outer w, outer h, text width, list rows
  end

  local function notesLines(tw)
    local lines = {}
    local list = K.notifications
    if #list == 0 then
      lines[1] = { text = "  none", fg = C.dim }
      return lines
    end
    for i = #list, 1, -1 do
      local n = list[i]
      local mark = n.level == "error" and "!" or (n.level == "warn" and "~" or " ")
      local fg = n.level == "error" and C.err or (n.level == "warn" and C.warn or C.text)
      lines[#lines + 1] = { text = mark .. n.from .. ": " .. n.title, fg = fg, bg = C.toastBar, idx = i }
      local body = n.text
      if n.private and not S.showText then body = "(message hidden)" end
      for _, l in ipairs(wrap(body, tw - 2, 3)) do
        lines[#lines + 1] = { text = "  " .. l, fg = C.dim, idx = i }
      end
      lines[#lines + 1] = { text = "" }
    end
    return lines
  end

  local function drawNotes()
    local ow, oh, tw, vr = notesGeom()
    local lines = notesLines(tw)
    menu.lines = lines
    local maxScroll = max(0, #lines - vr)
    menu.maxScroll = maxScroll
    menu.scroll = clamp(menu.scroll, 0, maxScroll)
    unread = 0
    local trackH = vr * 3
    local show = #lines > vr
    local thumbH = show and max(6, floor(trackH * vr / #lines)) or trackH
    local thumbY = (show and maxScroll > 0) and floor((trackH - thumbH) * menu.scroll / maxScroll + 0.5) or 0
    menu.sb = { show = show, trackH = trackH, thumbH = thumbH, thumbY = thumbY, vr = vr }

    local parts = { menu.scroll, #lines, thumbY, thumbH, tostring(menu.drag ~= nil), tostring(S.showText), ow, oh }
    for i = 1, vr do
      local l = lines[menu.scroll + i]
      parts[#parts + 1] = l and (l.text .. tostring(l.fg)) or ""
    end
    local sig = table.concat(parts, "\n")
    if not menu.spr or menu.spr.w ~= ow or menu.spr.h ~= oh or menu.sprSig ~= sig then
      local spr = G.sprite(ow, oh)
      menu.spr = spr
      local thumbC = menu.drag and C.sel or C.line
      spr:panel(C.panel, C.line, function(cv, pw, ph, win)
        local sc = ow - 1
        if cv then
          local px1, px2, y0 = sc * 2 - 1, sc * 2, 2 * 3 + 1
          for k = 0, trackH - 1 do cv[y0 + k][px2] = C.bar end
          if show then
            for k = 0, thumbH - 1 do
              local row = cv[y0 + thumbY + k]
              row[px1] = thumbC
              row[px2] = thumbC
            end
          end
        elseif win then
          win.setBackgroundColor(C.bar)
          for r = 1, vr do win.setCursorPos(sc, 2 + r) win.write(" ") end
          if show then
            win.setBackgroundColor(thumbC)
            for r = floor(thumbY / 3) + 1, min(vr, math.ceil((thumbY + thumbH) / 3)) do
              win.setCursorPos(sc, 2 + r)
              win.write(" ")
            end
          end
        end
      end)
      spr:text(2, 2, pad(" NOTIFICATIONS", ow - 2), C.text, C.hdr)
      spr:text(ow - 7, 2, "[Clear]", C.text, C.hdr)
      for i = 1, vr do
        local l = lines[menu.scroll + i]
        spr:text(2, 2 + i, pad(l and l.text or "", tw), l and l.fg or C.text, l and l.bg or C.panel)
      end
      menu.sprSig = sig
    end
    local e = 1 - (1 - menu.slide) ^ 3
    menu.spr:present((W - ow + 1) + floor((1 - e) * ow + 0.5), 2)
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
    local p = toast.p
    local e = (toast.phase == "out") and (p * p * (3 - 2 * p)) or (1 - (1 - p) ^ 3)
    return floor((1 - e) * TWo + 0.5)
  end

  local function buildToast(tk)
    local n = tk.n
    local lvl = n.level
    local accent = (lvl == "error") and C.err or (lvl == "warn" and C.warn or C.info)
    local titleBg = n.system and C.toastSys or C.toastBar
    local icon = (lvl == "error") and "x " or (lvl == "warn" and "! " or "i ")
    local head = icon .. (n.system and "SYSTEM" or n.from) .. ": " .. n.title
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
    toast = { n = n, phase = "in", p = 0, count = count, hold = (n.level == "error") and (S.toastTime + 2) or S.toastTime }
    buildToast(toast)
    local tk = toast
    K.after(0.05, function() frame(tk) end)
  end

  local function enqueue(n)
    unread = unread + 1
    if S.dnd then return end
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
    elseif x >= W - 8 then
      toggleMenu("notes")
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

  -- Which row sits under (x, y)? Returns index, x inside the panel, panel width.
  local function rowAt(x, y)
    if menu.slide < 1 then return nil end
    if menu.kind == "switch" then
      local list = menu.list or K.list()
      local n = min(#list, 9)
      local ox, oy = cabinetRect(n)
      if n > 0 and inRect(x, y, ox + 1, oy + 1, ox + PW, oy + n) then
        return y - oy, x - ox, PW
      end
      return nil
    end
    local rows = menu.rows or {}
    local ix, iy, pw, vis = panelRect(menu.kind, #rows)
    if inRect(x, y, ix, iy, ix + pw - 1, iy + vis - 1) then
      local idx = menu.scroll + (y - iy) + 1
      if rows[idx] then return idx, x - ix + 1, pw end
    end
    return nil
  end

  -- Press highlights the row under the pointer. Dragging moves the highlight.
  -- Letting go runs the row under the pointer.
  local function notesClick(x, y)
    local ow, oh, tw, vr = notesGeom()
    local x0 = W - ow + 1
    if not inRect(x, y, x0, 2, W, 1 + oh) then
      closeMenu()
      return
    end
    if y == 3 then
      if x >= x0 + ow - 8 and x <= x0 + ow - 2 then
        for i = #K.notifications, 1, -1 do K.notifications[i] = nil end
        menu.scroll = 0
      end
      return
    end
    if y < 4 or y > 3 + vr then return end
    local sb = menu.sb
    if x == x0 + ow - 2 then
      if not sb or not sb.show then return end
      local top = 4 + sb.thumbY / 3
      local bot = 4 + (sb.thumbY + sb.thumbH) / 3
      local py = y + 0.5
      if py >= top and py < bot then
        menu.drag = { grab = py - top }
      elseif py < top then
        menu.scroll = clamp(menu.scroll - vr, 0, menu.maxScroll or 0)
      else
        menu.scroll = clamp(menu.scroll + vr, 0, menu.maxScroll or 0)
      end
      return
    end
    local line = (menu.lines or {})[menu.scroll + (y - 3)]
    if line and line.idx then
      local n = K.notifications[line.idx]
      if n and n.pid then
        local pid = n.pid
        finishClose()
        focusPid(pid)
      end
    end
  end

  local function notesDrag(y)
    if not menu.drag or not menu.sb then return end
    local sb = menu.sb
    local span = sb.vr - sb.thumbH / 3
    if span <= 0 then return end
    local top = (y + 0.5) - menu.drag.grab
    menu.scroll = floor(clamp((top - 4) / span, 0, 1) * (menu.maxScroll or 0) + 0.5)
  end

  local function menuClick(x, y)
    if menu.slide < 1 or menu.closing then return end
    if menu.kind == "notes" then return notesClick(x, y) end
    local outer
    if menu.kind == "switch" then
      local n = min(#(menu.list or K.list()), 9)
      local ox, oy, nrows = cabinetRect(n)
      outer = { ox, oy, ox + PW + 1, oy + nrows + 1 }
    else
      local ix, iy, pw, vis = panelRect(menu.kind, #(menu.rows or {}))
      outer = { ix - 1, iy - 1, ix + pw, iy + vis }
    end
    if not inRect(x, y, outer[1], outer[2], outer[3], outer[4]) then
      closeMenu()
      return
    end
    local idx = rowAt(x, y)
    menu.press = nil
    if idx then
      if menu.kind == "switch" then
        menu.sel = idx
        menu.press = idx
      elseif selectable(menu.rows[idx]) or (menu.rows[idx].right and menu.rows[idx].right.act) then
        if selectable(menu.rows[idx]) then menu.sel = idx end
        menu.press = idx
      end
    end
  end

  local function menuDrag(x, y)
    if menu.kind == "notes" then return notesDrag(y) end
    if not menu.press then return end
    local idx = rowAt(x, y)
    if not idx then return end
    if menu.kind == "switch" then
      menu.sel = idx
    elseif selectable(menu.rows[idx]) then
      menu.sel = idx
    end
  end

  local function menuRelease(x, y)
    if menu.kind == "notes" then
      menu.drag = nil
      return
    end
    local pressed = menu.press
    menu.press = nil
    if not pressed or menu.slide < 1 then return end
    local idx, rx, pw = rowAt(x, y)
    if not idx then return end
    if menu.kind == "switch" then
      local p = (menu.list or {})[idx]
      if p then focusPid(p.pid) end
    else
      activate(menu.rows[idx], rx, pw)
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
    if keys.f8 and k == keys.f8 then toggleMenu("notes") return true end
    if menu then
      if menu.closing then return true end
      if menu.kind == "notes" then
        local ms = menu.maxScroll or 0
        local vr = menu.sb and menu.sb.vr or 10
        if k == keys.up then menu.scroll = clamp(menu.scroll - 1, 0, ms)
        elseif k == keys.down then menu.scroll = clamp(menu.scroll + 1, 0, ms)
        elseif keys.pageUp and k == keys.pageUp then menu.scroll = clamp(menu.scroll - vr, 0, ms)
        elseif keys.pageDown and k == keys.pageDown then menu.scroll = clamp(menu.scroll + vr, 0, ms)
        elseif keys.home and k == keys.home then menu.scroll = 0
        elseif keys["end"] and k == keys["end"] then menu.scroll = ms
        elseif k == keys.backspace then closeMenu() end
        return true
      end
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


  -- ------------------------------------------------------------ lock screen
  -- Covers everything. Apps keep running underneath; services keep working.
  -- The password is checked as a kernel task, so nothing else stalls.

  lockNow = function()
    if not lockable() or (lock and lock.on) then return end
    menu = nil
    toast = nil
    card = nil
    lock = { on = true, input = "", msg = "", busy = false, last = 0, frac = nil }
    K.setOverlay(true)
    if gfxOK and not saver then
      G.applyScene(os.clock())
      dash.spr = nil
    end
    if cfg.onLock then pcall(cfg.onLock) end
  end

  local function unlock()
    lock = nil
    K.setOverlay(false)
    lastInput = os.clock()
    if K.getFocus() then
      if gfxOK and G.sceneOn then G.restorePalette() end
      K.redrawFocused()
    else
      dash.spr = nil
      showDash()
    end
    if cfg.onUnlock then pcall(cfg.onUnlock) end
  end

  local function tryUnlock()
    if lock.busy or lock.input == "" then return end
    lock.busy = true
    lock.frac = 0
    lock.msg = "Checking..."
    local pw = lock.input
    lock.input = ""
    local function progress(i)
      if lock then lock.frac = math.min(1, i / 10000) end
    end
    K.task(function() return cfg.lock.check(pw, progress) end, function(ok, good, why, extra)
      if not lock then return end
      lock.busy = false
      if ok and good then
        unlock()
      elseif why == "locked" then
        lock.msg = "Too many tries. Wait " .. tostring(extra or "?") .. " s"
      else
        lock.msg = "Wrong password"
        if type(extra) == "number" and extra >= 3 then lock.msg = lock.msg .. " (" .. extra .. " tries)" end
      end
    end)
  end

  local function drawLock()
    local now = os.clock()
    if gfxOK then
      if not G.sceneOn then G.applyScene(now) end
      if lock.busy and dash.spr then
        -- keep the picture still while the password is checked, so the
        -- check gets the whole processor and the bar moves smoothly
      elseif not dash.spr or now - lock.last >= 1 / G.opts.fps then
        dashRender()
        dash.spr:present(1, 2)
        lock.last = now
      end
    else
      paintDashboard()
      put(2, H - 2, S.osName .. " is locked", C.text, C.bg)
    end
    local fw = math.min(26, W - 2)
    local fx = floor((W - fw) / 2) + 1
    local shown = string.rep("*", #lock.input)
    if #shown > fw - 2 then shown = shown:sub(-(fw - 2)) end
    put(fx, H - 1, " " .. pad(shown, fw - 1), C.barText, C.bar)
    local msg = lock.msg ~= "" and lock.msg or "Type your password, then Enter"
    if lock.busy and lock.frac then
      local n = floor(20 * lock.frac + 0.5)
      msg = "Checking [" .. string.rep("=", n) .. string.rep(" ", 20 - n) .. "]"
    end
    local mx = floor((W - #msg) / 2) + 1
    put(1, H, string.rep(" ", W), C.bg, C.bg)
    put(mx, H, msg, lock.msg ~= "" and C.warn or C.dim, C.bg)
    native.setCursorPos(fx + 1 + #shown, H - 1)
    native.setTextColor(C.barText)
    native.setCursorBlink(not lock.busy)
  end

  local function lockInput(ev)
    local name = ev[1]
    if name == "key" then
      if ev[2] == keys.enter or ev[2] == keys.numPadEnter then tryUnlock()
      elseif ev[2] == keys.backspace and not lock.busy then lock.input = lock.input:sub(1, -2) end
    elseif name == "char" and not lock.busy then
      if #lock.input < 64 then lock.input = lock.input .. ev[2] end
      if lock.msg ~= "Checking..." then lock.msg = "" end
    elseif name == "paste" and not lock.busy then
      lock.input = (lock.input .. tostring(ev[2]):gsub("%c", "")):sub(1, 64)
    end
  end

  local INPUTS_ALL = { key = true, key_up = true, char = true, paste = true, mouse_click = true,
    mouse_up = true, mouse_drag = true, mouse_scroll = true }

  -- --------------------------------------------------------- theme for apps
  -- prismarine.theme: the colors the OS uses right now, for apps that want to
  -- match. Every app gets its own read-only copy. Changes arrive as the
  -- kernel-only event "prismarine_theme" (name, version), at most once a
  -- second per app. Apps cannot queue that event name themselves.
  --   local T = prismarine and prismarine.theme or require("prismarine_theme_fallback")
  --   T.colors.hdr   a color for term.setBackgroundColor
  --   T.name, T.version, T.live, T.roles, T.apply(win), T.get()

  local THEME_ROLES = { "bg", "panel", "hdr", "text", "dim", "line", "sel", "selText", "bar", "barBtn",
    "barOn", "barText", "ok", "warn", "err", "info", "accent", "hint" }
  local THEME_VERSION = 1

  local function validColor(v)
    if type(v) ~= "number" then return false end
    for i = 0, 15 do
      if v == 2 ^ i then return true end
    end
    return false
  end

  -- A plain copy of the current look. Bad values fall back to white.
  local function themeSnapshot()
    local out = {}
    for _, r in ipairs(THEME_ROLES) do
      local v = C[r]
      out[r] = validColor(v) and v or colors.white
    end
    return out
  end

  local themeStates = {}   -- [pid] = { copy, name, live, last, pending }

  local function refreshState(st)
    st.copy = themeSnapshot()
    st.name = tostring(G.theme)
    st.live = G.live ~= "Off"
  end

  K.caps.theme = function(p)
    local st = themeStates[p.pid]
    if not st or st.gen ~= p.gen then
      st = { gen = p.gen, last = -10, pending = false }
      refreshState(st)
      themeStates[p.pid] = st
    end
    local fns = {
      version = THEME_VERSION,
      roles = (function() local r = {} for i, v in ipairs(THEME_ROLES) do r[i] = v end return r end)(),
      -- Paints the whole window with the theme's background and text color.
      apply = function(win)
        win = win or term.current()
        if type(win) ~= "table" then error("bad argument #1 (window expected)", 2) end
        win.setBackgroundColor(st.copy.bg)
        win.setTextColor(st.copy.text)
        win.clear()
        win.setCursorPos(1, 1)
      end,
      -- A fresh table: { name, version, live, colors }
      get = function()
        local c = {}
        for k, v in pairs(st.copy) do c[k] = v end
        return { name = st.name, version = THEME_VERSION, live = st.live, colors = c }
      end,
    }
    local colorView = setmetatable({}, {
      __index = function(_, k) return st.copy[k] end,
      __newindex = function() error("Theme colors are read only", 2) end,
      __metatable = false,
    })
    fns.colors = colorView
    return setmetatable({}, {
      __index = function(_, k)
        if k == "name" then return st.name end
        if k == "live" then return st.live end
        return fns[k]
      end,
      __newindex = function() error("The theme is read only", 2) end,
      __metatable = false,
    })
  end

  -- Called after any change to the look. Each app hears about it at most once
  -- a second; the last change always arrives.
  K.themeChanged = function()
    local alive = {}
    for _, info in ipairs(K.list()) do alive[info.pid] = info.alive end
    for pid, st in pairs(themeStates) do
      if not alive[pid] then
        themeStates[pid] = nil
      else
        local function fire()
          st.pending = false
          st.last = os.clock()
          refreshState(st)
          K.send(pid, "prismarine_theme", st.name, THEME_VERSION)
        end
        local wait = 1 - (os.clock() - st.last)
        if wait <= 0 then
          fire()
        elseif not st.pending then
          st.pending = true
          K.after(wait + 0.02, fire)
        end
      end
    end
  end

  -- ------------------------------------------------------------ screen saver
  -- Starts after the idle time chosen in Settings. Any key or click wakes it.
  -- It draws no message text. It covers the top bar and toasts, and stops the
  -- moment the lock screen or a permission card needs the screen.

  -- saver = { mode, t0, last, stars, ox, oy, spr }

  local function saverPalette(now)
    if not gfxOK then return end
    if S.saverMode == "Tide" then G.applySaver(now) else G.applyScene(now) end
  end

  local function saverStart()
    saver = { t0 = os.clock(), last = -10, ox = nil, oy = nil }
    menu, toast, card = nil, nil, nil
    K.setOverlay(true)
    saverPalette(os.clock())
    native.setBackgroundColor(colors.black)
    native.clear()
    native.setCursorBlink(false)
  end

  -- Any key or click ends the saver. A locked computer shows the password
  -- prompt (the password is never skipped). An unlocked one goes to Home.
  local function saverWake()
    if not saver then return end
    saver = nil
    lastInput = os.clock()
    native.setBackgroundColor(colors.black)
    native.clear()
    dash.spr = nil
    if lock and lock.on then
      if gfxOK then G.applyScene(os.clock()) end
      return
    end
    trans, menu = nil, nil
    K.setOverlay(false)
    holdPalette = true
    K.focus(nil)
    holdPalette = false
    if gfxOK then G.applyScene(os.clock()) end
    showDash()
  end

  local function saverCanvas()
    if not saver.spr or saver.spr.w ~= W or saver.spr.h ~= H then
      saver.spr = G.sprite(W, H)
    end
    return saver.spr, saver.spr.box.canvas, W * 2, H * 3
  end

  local function saverTide(now)
    local spr, cv, pw, ph = saverCanvas()
    if G.saverRainbow() then G.applySaver(now) end
    G.paintTide(cv, pw, ph, now - saver.t0)
    if S.saverLogo then G.paintSaverLogo(cv, pw, ph) end
    spr.box:render()
    spr:present(1, 1)
  end

  local function saverStars(now)
    local spr, cv, pw, ph = saverCanvas()
    if not saver.stars then
      saver.stars = {}
      for i = 1, 46 do
        saver.stars[i] = { x = (math.random() - 0.5) * 2, y = (math.random() - 0.5) * 2, z = math.random() * 0.95 + 0.05 }
      end
    end
    for y = 1, ph do
      local row = cv[y]
      for x = 1, pw do row[x] = colors.black end
    end
    local dt = now - (saver.lastStars or now)
    saver.lastStars = now
    for _, st in ipairs(saver.stars) do
      st.z = st.z - dt * 0.22
      if st.z <= 0.04 then
        st.x, st.y, st.z = (math.random() - 0.5) * 2, (math.random() - 0.5) * 2, 1
      end
      local sx = floor(pw / 2 + st.x / st.z * pw * 0.28)
      local sy = floor(ph / 2 + st.y / st.z * ph * 0.28)
      if sx >= 1 and sx <= pw and sy >= 1 and sy <= ph then
        cv[sy][sx] = st.z < 0.3 and colors.white or (st.z < 0.65 and colors.lightGray or colors.gray)
      end
    end
    spr.box:render()
    spr:present(1, 1)
  end

  local function saverClock(now)
    local x = saver.cx
    local slot = floor((now - saver.t0) / 30)
    if saver.slot ~= slot then
      saver.slot = slot
      saver.cx = math.random(2, max(2, W - 12))
      saver.cy = math.random(2, max(2, H - 2))
      native.setBackgroundColor(colors.black)
      native.clear()
    end
    native.setBackgroundColor(colors.black)
    native.setTextColor(colors.white)
    native.setCursorPos(saver.cx, saver.cy)
    native.write(os.date(S.hour24 and "%H:%M:%S" or "%I:%M:%S %p"))
    native.setTextColor(colors.lightGray)
    native.setCursorPos(saver.cx, min(H, saver.cy + 1))
    native.write(os.date("%a %d %b"))
    native.setCursorBlink(false)
  end

  local function saverLogo(now)
    local t = now - saver.t0
    local ox = floor(math.sin(t * 0.13) * 6 + 0.5)
    local oy = floor(math.sin(t * 0.09 + 1) * 3 + 0.5)
    dashRender()
    if saver.ox ~= ox or saver.oy ~= oy then
      saver.ox, saver.oy = ox, oy
      native.setBackgroundColor(colors.black)
      native.clear()
    end
    dash.spr:present(1 + ox, 1 + oy)
  end

  local function saverDraw()
    local now = os.clock()
    local gap = 1 / min(10, max(2, G.opts.fps))
    if now - saver.last < gap then return end
    saver.last = now
    if G.live ~= "Off" and G.sceneDue(now) then G.applyScene(now) end
    local mode = S.saverMode
    if not gfxOK and mode ~= "Clock" then mode = "Clock" end
    if mode == "Tide" then saverTide(now)
    elseif mode == "Starfield" then saverStars(now)
    elseif mode == "Logo drift" then saverLogo(now)
    else saverClock(now) end
  end

  -- Settings can start the saver to show it off.
  K.uiApi.startSaver = function()
    if saver or (lock and lock.on) then return false end
    saverStart()
    saverDraw()
    return true
  end

  local function saverDue()
    if saver or S.saver <= 0 or K.permQueue[1] then return false end
    return os.clock() - lastInput > S.saver * 60
  end

  -- ----------------------------------------------------- permission card
  -- An app asked for something that needs a yes. The card sits over everything
  -- (except the lock screen) and takes all input until it is answered.

  K.permUI = true
  local PWID, PROWS = 46, 7
  local PERM_DELAY = 0.7   -- clicks and keys that approve are ignored right after it appears

  local function permRect()
    return floor((W - PWID) / 2) + 1, floor((H - PROWS) / 2) + 1
  end

  local function permAnswer(choice)
    local r = K.permQueue[1]
    if not r then return end
    K.permAnswer(r, choice)
    refreshBase()
  end

  local function drawPerm()
    local r = K.permQueue[1]
    if not r then return false end
    if not r.shown then r.shown = os.clock() end
    local x, y = permRect()
    native.setCursorBlink(false)
    local function row(i, text, fg, bg)
      put(x, y + i - 1, pad(text, PWID), fg or C.text, bg or C.panel)
    end
    local more = #K.permQueue - 1
    row(1, " Permission needed" .. (more > 0 and ("  (+" .. more .. " waiting)") or ""), C.bg, C.accent)
    row(2, " " .. tostring(r.p.name):sub(1, 30) .. " wants to", C.text)
    row(3, "   " .. (K.PERM_LABEL[r.perm] or r.perm), C.accent)
    row(4, " For: " .. tostring(r.detail or ""), C.dim)
    row(5, " File: " .. tostring(r.p.spec.path), C.dim)
    row(6, "", C.text)
    local ready = os.clock() - r.shown >= PERM_DELAY
    put(x + 1, y + 5, " Allow once ", ready and C.bg or C.dim, ready and C.ok or C.line)
    put(x + 15, y + 5, " Always ", ready and C.bg or C.dim, ready and C.accent or C.line)
    put(x + 25, y + 5, " No ", C.bg, C.err)
    row(7, " 1 once   2 always   3 or N: no", C.hint)
    return true
  end

  local function permInput(ev)
    local r = K.permQueue[1]
    if not r then return false end
    local name = ev[1]
    local ready = r.shown and os.clock() - r.shown >= PERM_DELAY
    if name == "mouse_click" then
      local x, y = permRect()
      local mx, my = ev[3], ev[4]
      if my == y + 5 then
        if mx >= x + 1 and mx <= x + 12 and ready then permAnswer("once")
        elseif mx >= x + 15 and mx <= x + 22 and ready then permAnswer("always")
        elseif mx >= x + 25 and mx <= x + 28 then permAnswer("no") end
      end
      return true
    elseif name == "key" then
      local k = ev[2]
      if (k == keys.one or k == keys.numPad1) and ready then permAnswer("once")
      elseif (k == keys.two or k == keys.numPad2) and ready then permAnswer("always")
      elseif k == keys.three or k == keys.numPad3 or k == keys.n or k == keys.backspace then permAnswer("no") end
      return true
    end
    return INPUTS_ALL[name] == true
  end

  -- ------------------------------------------------------------------ hooks

  local hooks = {}

  hooks.onStart = function()
    native.setBackgroundColor(colors.black)
    native.clear()
    if gfxOK and animOn() and not cfg.noBoot then startBoot() else showDash() end
    -- keep the dashboard moving: one tick per frame
    local function beat()
      K.after(1 / G.opts.fps, beat)
    end
    beat()
  end

  local INPUTS = { key = true, key_up = true, char = true, paste = true, mouse_click = true,
    mouse_up = true, mouse_drag = true, mouse_scroll = true }

  hooks.onEvent = function(ev)
    local name = ev[1]
    if INPUTS[name] then lastInput = os.clock() end
    if saver and INPUTS[name] then
      -- the click that started a preview ends with a mouse_up: ignore the first moments
      if os.clock() - saver.t0 > 0.7 then saverWake() end
      return true
    end
    if lock and lock.on then
      if INPUTS[name] then
        lockInput(ev)
        return true
      end
      if name == "term_resize" then W, H = native.getSize() dash.spr = nil end
      return false
    end
    if K.permQueue[1] and INPUTS[name] then
      return permInput(ev)
    end
    if name == "key" and keys.f9 and ev[2] == keys.f9 and lockable() then
      lockNow()
      return true
    end
    if name == "term_resize" then
      W, H = native.getSize()
      dash.spr = nil
      return false
    end
    if name == "mouse_click" then
      return handleClick(ev[3], ev[4])
    end
    if name == "mouse_drag" then
      if menu then menuDrag(ev[3], ev[4]) end
      return menu ~= nil or ev[4] == 1
    end
    if name == "mouse_up" then
      local had = menu ~= nil
      if menu then menuRelease(ev[3], ev[4]) end
      return had or ev[4] == 1
    end
    if name == "mouse_scroll" then
      if menu and menu.kind == "notes" then
        menu.scroll = clamp(menu.scroll + ev[2] * 3, 0, menu.maxScroll or 0)
      elseif menu and menu.kind ~= "switch" then
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
      if gfxOK and G.sceneOn and not holdPalette and not trans then G.restorePalette() end
    end
  end

  hooks.onNotify = function(n)
    enqueue(n)
  end

  -- Rounded app frame: the four corner cells lose one sub-pixel to black.
  local function roundApp()
    local pid = K.getFocus()
    if not pid then return end
    local e = K.edgeRows(pid)
    if not e then return end
    local function colorAt(row, x)
      local ch = row.bg:sub(x, x)
      local idx = tonumber(ch, 16)
      return idx and (2 ^ idx) or colors.black
    end
    native.setCursorBlink(false)
    local function corner(x, y, row, ch, invert)
      if row.text:sub(x, x) ~= " " then return end -- never hide an app's text
      local c = colorAt(row, x)
      native.setCursorPos(x, y)
      if invert then
        native.setBackgroundColor(colors.black)
        native.setTextColor(c)
      else
        native.setBackgroundColor(c)
        native.setTextColor(colors.black)
      end
      native.write(ch)
    end
    corner(1, 2, e.top, "\129")
    corner(W, 2, e.top, "\130")
    corner(1, H, e.bottom, "\144")
    corner(W, H, e.bottom, "\159", true)
    K.restoreCursor()
  end

  local baseTick
  baseTick = function()
    if lock and lock.on then
      drawBar()
      drawLock()
      return
    end
    local al = S.autoLock
    if K.bunker and K.bunker() and (al == 0 or al > 5) then al = 5 end
    if lockable() and al > 0 and os.clock() - lastInput > al * 60 then
      lockNow()
      return
    end
    pump()
    drawBar()
    dashTick()
    if S.round and not menu and not trans and not toast and K.getFocus() and not K.overlay then roundApp() end
    if menu then
      native.setCursorBlink(false)
      if menu.kind == "switch" then
        drawCabinet()
      elseif menu.kind == "notes" then
        drawNotes()
      else
        drawRowsMenu()
      end
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

  local function autoLockDue()
    local al = S.autoLock
    if K.bunker and K.bunker() and (al == 0 or al > 5) then al = 5 end
    return lockable() and al > 0 and os.clock() - lastInput > al * 60
  end

  hooks.onTick = function()
    if saver then
      if K.permQueue[1] then
        saverWake()
      else
        -- the lock closes in behind the saver, so waking asks for the password
        if autoLockDue() and not (lock and lock.on) then lockNow() end
        saverDraw()
        return
      end
    elseif saverDue() then
      saverStart()
      saverDraw()
      return
    end
    baseTick()
    if not (lock and lock.on) and K.permQueue[1] then drawPerm() end
  end

  return {
    hooks = hooks, settings = S, graphics = gfxOK, gfx = G,
    lockNow = function() lockNow() end,
    locked = function() return lock ~= nil and lock.on end,
    goHome = function() goHome() end,
    focus = function(pid) focusPid(pid) end,
    -- call after K.run returns: puts the normal colors back
    restore = function() if gfxOK then G.restorePalette() end end,
  }
end

return M
