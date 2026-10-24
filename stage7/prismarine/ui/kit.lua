--[==[ Prismarine
 ____
/\ _`\ __ __
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine app kit. One look for every built-in app.
--
--   header   title chip, context, right side text
--   hints    key hints that fit the width (never cut in the middle of a word)
--   item     list row with a selection marker
--   scrollbar, empty, status, field, fit, pad
--
-- Colors come from the OS theme (prismarine.theme), so apps follow the
-- look chosen in Settings. Without a theme they use plain colors.

local K = {}

local DEFAULTS = {
  bg = colors.black, bar = colors.gray, barText = colors.white, hdr = colors.blue,
  line = colors.cyan, sel = colors.lightBlue, barBtn = colors.blue, selText = colors.black, text = colors.white,
  dim = colors.gray, hint = colors.lightGray, ok = colors.green, warn = colors.orange,
  err = colors.red, info = colors.cyan, panel = colors.black,
}

local function theme()
  local api = rawget(_G, "prismarine")
  local t = api and api.theme
  return t and t.colors
end

-- A theme color by role. Falls back to a plain color.
function K.c(role)
  local c = theme()
  local v = c and c[role]
  if type(v) == "number" then return v end
  return DEFAULTS[role] or colors.white
end

function K.size()
  return term.getSize()
end

function K.put(x, y, s, fg, bg)
  local W, H = term.getSize()
  if y < 1 or y > H or x > W or s == "" then return end
  if x < 1 then s = s:sub(2 - x) x = 1 end
  s = s:sub(1, W - x + 1)
  term.setCursorPos(x, y)
  term.setTextColor(fg or K.c("text"))
  term.setBackgroundColor(bg or K.c("bg"))
  term.write(s)
end

-- Cut to n columns. A cut text ends with "~".
function K.fit(s, n)
  s = tostring(s)
  if n <= 0 then return "" end
  if #s > n then return s:sub(1, math.max(0, n - 1)) .. "~" end
  return s
end

function K.pad(s, n)
  s = K.fit(s, n)
  return s .. string.rep(" ", n - #s)
end

-- Clear the window with the theme background.
function K.clear()
  term.setCursorBlink(false)
  term.setBackgroundColor(K.c("bg"))
  term.setTextColor(K.c("text"))
  term.clear()
end

-- Row 1. A title chip, the context after it, and text on the right.
function K.header(title, context, right)
  local W = term.getSize()
  local bar, bt = K.c("bar"), K.c("barText")
  K.put(1, 1, string.rep(" ", W), bt, bar)
  local chip = " " .. tostring(title) .. " "
  K.put(1, 1, chip, K.c("barText"), K.c("barBtn"))
  local x = #chip + 2
  if right and right ~= "" then
    right = K.fit(right, math.max(0, W - x - 2))
    K.put(W - #right, 1, right, K.c("hint"), bar)
  end
  if context and context ~= "" then
    local room = W - x - (right and (#right + 2) or 0)
    K.put(x, 1, K.fit(context, room), bt, bar)
  end
end

-- Key hints on row y. list = { { "Enter", "open" }, { "Q", "quit" } }.
-- Items that do not fit are left out from the end. With rows = 2 the rest
-- continues on row y + 1.
function K.hints(y, list, rows)
  local W = term.getSize()
  rows = rows or 1
  local row, x = 0, 2
  local bg = K.c("bg")
  K.put(1, y, string.rep(" ", W), K.c("hint"), bg)
  for i, it in ipairs(list) do
    local key, label = tostring(it[1]), tostring(it[2] or "")
    local need = #key + 1 + #label + (x > 2 and 2 or 0)
    if x + need - 1 > W then
      row = row + 1
      if row >= rows then break end
      K.put(1, y + row, string.rep(" ", W), K.c("hint"), bg)
      x = 2
      need = #key + 1 + #label
    end
    if x > 2 then x = x + 2 end
    K.put(x, y + row, key, K.c("line"), bg)
    K.put(x + #key + 1, y + row, label, K.c("hint"), bg)
    x = x + #key + 1 + #label
  end
  return math.min(rows, row + 1)
end

-- Hints from a text such as "Enter open   A add   Esc: back". Segments are
-- split at three spaces. The word before a colon (or the first word) is the key.
function K.hintText(y, text, rows)
  local list = {}
  text = tostring(text or "")
  local pos = 1
  while pos <= #text do
    local a, b = text:find("   +", pos)
    local seg
    if a then seg = text:sub(pos, a - 1) pos = b + 1 else seg = text:sub(pos) pos = #text + 1 end
    seg = seg:gsub("^%s+", ""):gsub("%s+$", "")
    if seg ~= "" then
      local key, label = seg:match("^([^:]+):%s*(.*)$")
      if not key then key, label = seg:match("^(%S+)%s*(.*)$") end
      list[#list + 1] = { key or seg, label or "" }
    end
  end
  return K.hints(y, list, rows)
end

-- One list row across the width. Returns the text width left over.
-- o.right: text on the right edge. o.fg: text color. o.dim: faded row.
-- o.marker: leading character for a plain row.
function K.item(y, text, on, o)
  o = o or {}
  local W = term.getSize()
  local last = o.last or W
  local bg = on and K.c("sel") or K.c("bg")
  local fg = on and K.c("selText") or (o.dim and K.c("dim") or (o.fg or K.c("text")))
  K.put(1, y, string.rep(" ", last), fg, bg)
  K.put(1, y, on and ">" or (o.marker or " "), on and K.c("selText") or K.c("line"), bg)
  local right = o.right and tostring(o.right) or ""
  local room = last - 3 - (right ~= "" and (#right + 2) or 0)
  K.put(3, y, K.fit(text, room), fg, bg)
  if right ~= "" then
    K.put(last - #right, y, right, on and K.c("selText") or K.c("hint"), bg)
  end
  return room
end

-- A slim scroll bar in column x from row y to y + h - 1.
function K.scrollbar(x, y, h, total, first, visible)
  if total <= visible or h < 2 then return end
  local track, thumb = K.c("bar"), K.c("line")
  local th = math.max(1, math.floor(h * visible / total + 0.5))
  local maxFirst = total - visible
  local ty = math.floor((h - th) * math.min(first, maxFirst) / math.max(1, maxFirst) + 0.5)
  for i = 0, h - 1 do
    local on = i >= ty and i < ty + th
    K.put(x, y + i, " ", track, on and thumb or track)
  end
end

-- Centered message for an empty page. lines: { title, hint, hint... }
function K.empty(y, lines)
  local W = term.getSize()
  for i, l in ipairs(lines) do
    local fg = (i == 1) and K.c("text") or K.c("hint")
    local s = K.fit(l, W - 2)
    K.put(math.floor((W - #s) / 2) + 1, y + i - 1, s, fg, K.c("bg"))
  end
end

-- A message line. level: "ok", "warn", "err" or nil for plain information.
function K.status(y, text, level)
  local W = term.getSize()
  local col = (level == "err" and K.c("err")) or (level == "warn" and K.c("warn")) or (level == "ok" and K.c("ok")) or K.c("info")
  K.put(1, y, string.rep(" ", W), col, K.c("bg"))
  K.put(2, y, "*", col, K.c("bg"))
  K.put(4, y, K.fit(text, W - 4), col, K.c("bg"))
end

-- An input box. Shows a bar caret when focused.
function K.field(x, y, w, text, focused, secret)
  local shown = secret and string.rep("*", #text) or text
  if #shown > w - 1 then shown = shown:sub(-(w - 1)) end
  local bg = focused and K.c("bar") or K.c("bg")
  K.put(x, y, string.rep(" ", w), K.c("text"), bg)
  K.put(x, y, shown, K.c("text"), bg)
  if focused then K.put(x + #shown, y, "_", K.c("line"), bg) end
end

-- A button label. on = false shows it dim.
function K.button(x, y, label, on)
  local s = " " .. label .. " "
  K.put(x, y, s, on and K.c("selText") or K.c("dim"), on and K.c("line") or K.c("bar"))
  return x + #s + 1
end

-- ---------------------------------------------------------------------------
-- Scenes. Pixel cards drawn with Pixelbox (2 x 3 sub-pixels per cell).
--
--   local s = kit.scene()          clears a canvas the size of the window
--   s:card(x, y, w, h, fill)       rounded card (cell units)
--   s:text(x, y, str, fg, bg)      text, written after the canvas
--   s:pill / s:key / s:hints / s:header / s:row / s:badge / s:meter / s:scroll
--   s:flush()                      render the canvas, then the text
--
-- Cards keep one cell of space from the window edge. The game paints the
-- margin around the screen with the edge cell colors, so a card that touched
-- the edge would show as a colored bar outside the screen.
-- Without Pixelbox every card falls back to flat colored blocks.
-- ---------------------------------------------------------------------------

local G, PB
local function loadPB()
  if PB ~= nil then return PB end
  PB = false
  local ok, g = pcall(dofile, "/prismarine/ui/gfx.lua")
  if ok and type(g) == "table" and g.loadPixelbox then
    local okp, mod = pcall(g.loadPixelbox)
    if okp and mod then PB = mod end
  end
  return PB
end

local boxCache = {}
local Scene = {}
Scene.__index = Scene

function K.scene(bg)
  local W, H = term.getSize()
  local cur = term.current()
  bg = bg or K.c("bg")
  local s = setmetatable({ W = W, H = H, bg = bg, texts = {}, ops = {} }, Scene)
  local mod = loadPB()
  if mod then
    if boxCache.term ~= cur or boxCache.W ~= W or boxCache.H ~= H or boxCache.bg ~= bg then
      local ok, box = pcall(mod.new, cur, bg)
      if ok then
        boxCache = { term = cur, W = W, H = H, bg = bg, box = box }
      else
        boxCache = {}
      end
    end
    s.box = boxCache.box
    if s.box then
      local cv = s.box.canvas
      for y = 1, H * 3 do
        local row = cv[y]
        for x = 1, W * 2 do row[x] = bg end
      end
      s.cv = cv
    end
  end
  return s
end


-- A rounded card. fill = color. line = optional outline color.
function Scene:card(x, y, w, h, fill, line, square)
  if w < 1 or h < 1 then return end
  fill = fill or K.c("bar")
  if not self.cv then
    self.ops[#self.ops + 1] = function()
      local blank = string.rep(" ", w)
      for r = 0, h - 1 do K.put(x, y + r, blank, K.c("text"), line and ((r == 0 or r == h - 1) and line or fill) or fill) end
    end
    return
  end
  local cv = self.cv
  local x1, x2 = (x - 1) * 2 + 1, (x + w - 1) * 2
  local y1, y2 = (y - 1) * 3 + 1, (y + h - 1) * 3
  for py = math.max(1, y1), math.min(self.H * 3, y2) do
    local row = cv[py]
    for px = math.max(1, x1), math.min(self.W * 2, x2) do row[px] = fill end
  end
  if line then
    for px = x1, x2 do cv[y1][px] = line cv[y2][px] = line end
    for py = y1, y2 do cv[py][x1] = line cv[py][x2] = line end
  end
  if not square and (w >= 2 or h >= 2) then
    local cut = self.bg
    cv[y1][x1], cv[y1][x2], cv[y2][x1], cv[y2][x2] = cut, cut, cut, cut
    if line then
      cv[y1 + 1][x1], cv[y1 + 1][x2], cv[y2 - 1][x1], cv[y2 - 1][x2] = line, line, line, line
      cv[y1][x1 + 1], cv[y1][x2 - 1], cv[y2][x1 + 1], cv[y2][x2 - 1] = line, line, line, line
    end
  end
end

-- A solid bar from sub-pixel fractions. frac 0..1.
function Scene:meter(x, y, w, frac, fill, track)
  frac = math.max(0, math.min(1, frac or 0))
  track = track or K.c("bar")
  if not self.cv then
    local n = math.floor(w * frac + 0.5)
    self.ops[#self.ops + 1] = function()
      K.put(x, y, string.rep(" ", w), K.c("text"), track)
      if n > 0 then K.put(x, y, string.rep(" ", n), K.c("text"), fill) end
    end
    return
  end
  local cv = self.cv
  local x1, x2 = (x - 1) * 2 + 1, (x + w - 1) * 2
  local py = (y - 1) * 3
  local cut = math.floor((x2 - x1 + 1) * frac + 0.5)
  for r = 2, 3 do
    for px = x1, x2 do cv[py + r][px] = (px - x1 < cut) and fill or track end
  end
  -- soften the ends
  cv[py + 2][x1], cv[py + 2][x2] = self.bg, self.bg
  cv[py + 3][x1], cv[py + 3][x2] = (cut > 0) and fill or track, (cut >= x2 - x1 + 1) and fill or track
end

-- A thin line across the cells x..x+w-1 in the middle of row y.
function Scene:rule(x, y, w, color)
  if not self.cv then
    self.ops[#self.ops + 1] = function() K.put(x, y, string.rep("-", w), color or K.c("dim"), self.bg) end
    return
  end
  local cv = self.cv
  local py = (y - 1) * 3 + 2
  for px = (x - 1) * 2 + 1, (x + w - 1) * 2 do cv[py][px] = color or K.c("bar") end
end

function Scene:text(x, y, str, fg, bg)
  if str == "" or y < 1 or y > self.H then return end
  self.texts[#self.texts + 1] = { x, y, str, fg, bg }
end

function Scene:flush()
  if self.box then self.box:render() end
  for _, op in ipairs(self.ops) do op() end
  for _, t in ipairs(self.texts) do
    K.put(t[1], t[2], t[3], t[4], t[5] or self.bg)
  end
  self.texts, self.ops = {}, {}
end

-- Fit text on a card. Cuts with "~".
function Scene:label(x, y, w, str, fg, bg)
  self:text(x, y, K.fit(str, w), fg, bg)
end

-- A pill: a one cell high card with text. Returns the next free x.
function Scene:pill(x, y, label, fill, fg)
  local n = #label + 2
  self:card(x, y, n, 1, fill)
  self:text(x + 1, y, label, fg or K.c("barText"), fill)
  return x + n + 1
end

-- Status badge. kind: ok warn err info dim
function Scene:badge(x, y, label, kind)
  local fill = (kind == "ok" and K.c("ok")) or (kind == "warn" and K.c("warn")) or (kind == "err" and K.c("err"))
    or (kind == "dim" and K.c("bar")) or K.c("info")
  local fg = (kind == "dim") and K.c("hint") or colors.black
  if fill == colors.black then fg = colors.white end
  return self:pill(x, y, label, fill, fg)
end

-- Page header: title pill, context, right text. Row 1.
function Scene:header(title, context, right)
  local W = self.W
  local x = self:pill(2, 1, tostring(title), K.c("barBtn"), K.c("barText"))
  if right and right ~= "" then
    right = K.fit(right, math.max(0, W - x - 2))
    self:text(W - #right, 1, right, K.c("hint"), self.bg)
  end
  if context and context ~= "" then
    local room = W - x - (right and (#right + 3) or 1)
    self:text(x + 1, 1, K.fit(context, room), K.c("text"), self.bg)
  end
end

-- Key chips on row y. list = { { "Enter", "run" }, ... }. Items that do not
-- fit move to the next row (rows) or are dropped.
function Scene:hints(y, list, rows, x0)
  local W = self.W
  rows = rows or 1
  x0 = x0 or 2
  local row, x = 0, x0
  for _, it in ipairs(list) do
    local key, label = tostring(it[1]), tostring(it[2] or "")
    local need = #key + 2 + 1 + #label + 1
    if x + need - 2 > W - 1 then
      row = row + 1
      if row >= rows then break end
      x = x0
    end
    self:card(x, y + row, #key + 2, 1, K.c("bar"))
    self:text(x + 1, y + row, key, K.c("line"), K.c("bar"))
    self:text(x + #key + 3, y + row, label, K.c("hint"), self.bg)
    x = x + #key + 2 + 1 + #label + 1
  end
  return math.min(rows, row + 1)
end

-- Hints from a text such as "Enter open   A add   Esc: back".
function Scene:hintText(y, text, rows)
  local list = {}
  text = tostring(text or "")
  local pos = 1
  while pos <= #text do
    local a, b = text:find("   +", pos)
    local seg
    if a then seg = text:sub(pos, a - 1) pos = b + 1 else seg = text:sub(pos) pos = #text + 1 end
    seg = seg:gsub("^%s+", ""):gsub("%s+$", "")
    if seg ~= "" then
      local key, label = seg:match("^([^:]+):%s*(.*)$")
      if not key then key, label = seg:match("^(%S+)%s*(.*)$") end
      list[#list + 1] = { key or seg, label or "" }
    end
  end
  return self:hints(y, list, rows)
end

-- A list row inside a card. x..x+w-1, row y. on = selected.
function Scene:row(x, y, w, label, on, o)
  o = o or {}
  local cardBg = o.bg or K.c("bar")
  local bg = cardBg
  local fg = o.fg or K.c("barText")
  if on then
    bg = K.c("sel")
    fg = K.c("selText")
    self:card(x, y, w, 1, bg)
  end
  local right = o.right and tostring(o.right) or ""
  local room = w - 2 - (right ~= "" and (#right + 1) or 0)
  local lead = o.lead and (o.lead .. " ") or ""
  self:text(x + 1, y, K.fit(lead .. label, room), (o.dim and not on) and K.c("hint") or fg, bg)
  if right ~= "" then
    self:text(x + w - 1 - #right, y, right, on and K.c("selText") or (o.rightFg or K.c("hint")), bg)
  end
end

-- A scroll thumb in column x from row y for h rows.
function Scene:scroll(x, y, h, total, first, visible)
  if total <= visible or h < 2 then return end
  local th = math.max(1, math.floor(h * visible / total + 0.5))
  th = math.max(1, math.min(th, math.floor(h / 3)))  -- never a giant block
  local maxFirst = total - visible
  local ty = math.floor((h - th) * math.min(first, maxFirst) / math.max(1, maxFirst) + 0.5)
  -- track: a dim strip with faint dots, so the bar reads as a scroll bar
  self:card(x, y, 1, h, K.c("bar"))
  for i = 0, h - 1 do self:text(x, y + i, ".", K.c("dim"), K.c("bar")) end
  -- thumb: solid, with grip lines in the middle
  self:card(x, y + ty, 1, th, K.c("line"))
  if th >= 3 then
    local mid = y + ty + math.floor(th / 2)
    self:text(x, mid, "=", K.c("bg"), K.c("line"))
    if th >= 5 then
      self:text(x, mid - 1, "-", K.c("bg"), K.c("line"))
      self:text(x, mid + 1, "-", K.c("bg"), K.c("line"))
    end
  end
end

-- A switch. Returns the width used (5).
function Scene:switch(x, y, on)
  local fill = on and K.c("ok") or K.c("dim")
  self:card(x, y, 4, 1, fill)
  self:text(x + (on and 2 or 1), y, on and "ON" or "", colors.black, fill)
  if not on then self:text(x + 2, y, "off", K.c("barText"), fill) end
  return 5
end

-- A text field pill.
function Scene:field(x, y, w, text, focused, secret, hintText)
  local fill = focused and K.c("hdr") or K.c("bar")
  if fill == K.c("bg") then fill = K.c("bar") end
  self:card(x, y, w, 1, fill)
  local shown = secret and string.rep("*", #text) or text
  local room = w - 3
  if #shown > room then shown = shown:sub(-room) end
  if shown == "" and hintText and not focused then
    self:text(x + 1, y, K.fit(hintText, room), K.c("hint"), fill)
  else
    self:text(x + 1, y, shown, K.c("barText"), fill)
  end
  if focused then self:text(x + 1 + #shown, y, "_", K.c("line"), fill) end
end

-- Centered message on a card. lines: { title, hint, ... }
function Scene:empty(x, y, w, h, lines)
  local top = y + math.floor((h - #lines) / 2)
  for i, l in ipairs(lines) do
    local str = K.fit(l, w - 2)
    local fg = (i == 1) and K.c("barText") or K.c("hint")
    self:text(x + math.floor((w - #str) / 2), top + i - 1, str, fg, K.c("bar"))
  end
end

-- Message line with a small colored mark. level: ok warn err info
function Scene:status(y, text, level)
  local col = (level == "err" and K.c("err")) or (level == "warn" and K.c("warn")) or (level == "ok" and K.c("ok")) or K.c("info")
  self:card(2, y, 1, 1, col)
  self:text(4, y, K.fit(text, self.W - 5), col, self.bg)
end

-- Tabs on row y. Returns the end x.
function Scene:tabs(x, y, list, active)
  for i, name in ipairs(list) do
    local on = (i == active)
    local fill = on and K.c("barBtn") or K.c("bar")
    local fg = on and K.c("barText") or K.c("hint")
    x = self:pill(x, y, name, fill, fg)
  end
  return x
end


return K
