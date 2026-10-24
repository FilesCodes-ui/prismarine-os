--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/ui/login.lua
-- Prismarine OS v23: the screens that run before the desktop starts:
-- first-time setup, login, "system files changed", and reset.
-- They draw over the animated logo, like the boot screen.

local L = {}

local native = term.native()
local G = nil
local spr = nil
local t0 = os.clock()

local function W() local w = native.getSize() return w end
local function H() local _, h = native.getSize() return h end

local function put(x, y, s, fg, bg)
  native.setCursorPos(x, y)
  native.setTextColor(fg or colors.white)
  native.setBackgroundColor(bg or colors.black)
  native.write(s)
end

local function pad(s, n)
  s = tostring(s)
  if #s >= n then return s:sub(1, n) end
  return s .. string.rep(" ", n - #s)
end

local function center(y, s, fg, bg)
  s = tostring(s):sub(1, W())
  put(math.floor((W() - #s) / 2) + 1, y, s, fg, bg)
end

function L.init(gfx)
  G = gfx
  if G and G.pb then
    spr = G.sprite(W(), H() - 1)
    G.applyScene(os.clock())
  end
end

-- The logo background plus a title bar.
local function background(title, right)
  if spr then
    spr:dash({ t = os.clock() - t0, haze = true, status = nil, clock = "", hint = "" })
    spr:present(1, 2)
  else
    native.setBackgroundColor(colors.black)
    native.clear()
    center(4, "P R I S M A R I N E", colors.cyan)
  end
  local w = W()
  local r = right or ""
  put(1, 1, pad(" " .. (title or "Prismarine"), w - #r) .. r, colors.white, colors.gray)
end

-- Rows below the logo: up to 3 lines of text.
local function bottom(lines, colorsFor)
  local h = H()
  for i = 1, 3 do
    local y = h - 3 + i - 1
    put(1, y, string.rep(" ", W()), colors.black, colors.black)
    local l = lines[i]
    if l and l ~= "" then center(y, l, (colorsFor and colorsFor[i]) or colors.lightGray) end
  end
end

-- A text box under the logo. Returns the text, or nil on Escape (when allowed)
-- or "\0forgot" when the [Forgot password?] link is clicked.
-- opts: title, label, mask, default, hint, forgot, allowCancel, err
function L.prompt(opts)
  local text = opts.default or ""
  local msg = opts.err or opts.hint or ""
  local msgColor = opts.err and colors.orange or colors.lightGray
  local link = opts.forgot and "[Forgot password?] " or nil
  local timer = os.startTimer(0.1)
  while true do
    background(opts.title, link)
    local h, w = H(), W()
    local fw = math.min(28, w - 2)
    local fx = math.floor((w - fw) / 2) + 1
    local shown = opts.mask and string.rep(opts.mask, #text) or text
    if #shown > fw - 2 then shown = shown:sub(-(fw - 2)) end
    bottom({ opts.label or "", "", msg }, { colors.white, colors.white, msgColor })
    -- The box sits on the blank row between the label and the message, so it
    -- never covers the hint or an error.
    put(fx, h - 2, " " .. pad(shown, fw - 1), colors.white, colors.gray)
    native.setCursorPos(fx + 1 + #shown, h - 2)
    native.setTextColor(colors.white)
    native.setCursorBlink(true)
    local ev = table.pack(os.pullEventRaw())
    local name = ev[1]
    if name == "timer" and ev[2] == timer then
      timer = os.startTimer(0.1)
    elseif name == "char" then
      if #text < 64 then text = text .. ev[2] end
    elseif name == "paste" then
      text = (text .. tostring(ev[2]):gsub("%c", "")):sub(1, 64)
    elseif name == "key" then
      if ev[2] == keys.enter or ev[2] == keys.numPadEnter then
        native.setCursorBlink(false)
        return text
      elseif ev[2] == keys.backspace then
        text = text:sub(1, -2)
      elseif opts.allowCancel and ev[2] == keys.tab then
        native.setCursorBlink(false)
        return nil
      end
    elseif name == "mouse_click" and link and ev[4] == 1 and ev[3] >= w - #link then
      native.setCursorBlink(false)
      return "\0forgot"
    end
  end
end

-- Shows lines and waits for Enter (or a choice key). choices: { y = "label", ... }
function L.message(title, lines, color, choices)
  local timer = os.startTimer(0.1)
  while true do
    background(title)
    local l = { lines[1] or "", lines[2] or "", lines[3] or "" }
    bottom(l, { color or colors.white, colors.lightGray, colors.lightGray })
    native.setCursorBlink(false)
    local ev = table.pack(os.pullEventRaw())
    if ev[1] == "timer" and ev[2] == timer then
      timer = os.startTimer(0.1)
    elseif ev[1] == "key" then
      if not choices and (ev[2] == keys.enter or ev[2] == keys.numPadEnter) then return true end
      if choices then
        local name = keys.getName(ev[2])
        if name and choices[name] then return name end
      end
    elseif ev[1] == "mouse_click" and not choices then
      return true
    end
  end
end

-- A busy line under the logo. Returns a function to update the text.
function L.busy(title, text)
  -- The logo behind the bar moves only a few times a second. Most calls just
  -- redraw the bar, which is cheap, so the work finishes sooner.
  local lastBar, lastBg = 0, nil
  local function show(t, frac)
    local now = os.epoch("utc")
    if now - lastBar < 60 and frac ~= 1 then return end
    lastBar = now
    if not lastBg or now - lastBg > 250 then
      background(title)
      lastBg = now
    end
    local bar = ""
    if frac then
      local n = math.floor(20 * math.max(0, math.min(1, frac)) + 0.5)
      bar = "[" .. string.rep("=", n) .. string.rep(" ", 20 - n) .. "]"
    end
    bottom({ t or text, bar, "" }, { colors.white, colors.cyan })
  end
  show(text)
  return show
end

-- A scrollable list of lines with a question. Returns the key name chosen.
function L.list(title, header, items, question, choices)
  local top = 1
  while true do
    native.setBackgroundColor(colors.black)
    native.clear()
    local w, h = W(), H()
    put(1, 1, pad(" " .. title, w), colors.white, colors.red)
    put(2, 3, header:sub(1, w - 2), colors.white)
    local rows = h - 7
    for i = 1, rows do
      local it = items[top + i - 1]
      if it then put(3, 4 + i, it:sub(1, w - 4), colors.lightGray) end
    end
    if #items > rows then put(w - 10, 4, ("%d-%d of %d"):format(top, math.min(#items, top + rows - 1), #items), colors.gray) end
    put(2, h - 1, question:sub(1, w - 2), colors.yellow)
    native.setCursorBlink(false)
    local ev = table.pack(os.pullEventRaw())
    if ev[1] == "key" then
      local name = keys.getName(ev[2])
      if name == "up" then top = math.max(1, top - 1)
      elseif name == "down" then top = math.min(math.max(1, #items - rows + 1), top + 1)
      elseif name and choices[name] then return name end
    elseif ev[1] == "mouse_scroll" then
      top = math.max(1, math.min(math.max(1, #items - rows + 1), top + ev[2]))
    end
  end
end

return L
