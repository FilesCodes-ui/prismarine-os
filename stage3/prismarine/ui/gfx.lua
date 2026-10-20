-- /prismarine/ui/gfx.lua
-- Prismarine OS v23 graphics layer. Wraps Pixelbox_lite.
--
--   * Loads Pixelbox from /prismarine/lib/pixelbox_lite.lua and checks its
--     SHA-256 first. A missing or changed file means plain text mode.
--   * Theme: /prismarine/data/theme.json. Every key is optional.
--   * Sprites: an off-screen window. Pixelbox paints the panel and outline,
--     text goes on top, then the sprite is copied to the screen with clipping.
--   * The dashboard: the v21 PRISMARINE logo with its smooth palette shades,
--     shine, water ripple and rising bubbles.
--
-- Pixelbox cannot draw letters inside pixel cells, so text always sits on
-- cells inside the outline ring.

local G = {}

local PB_PATH = "/prismarine/lib/pixelbox_lite.lua"
local PB_HASH = "e9923dc24ed6d968de668f42a3c324d0957778a709d93bc9190617c32889de99"
local SHA_PATH = "/prismarine/lib/sha256.lua"
local THEME_PATH = "/prismarine/data/theme.json"

local floor, min, max, sin, cos = math.floor, math.min, math.max, math.sin, math.cos

-- ------------------------------------------------------------------ theme

-- role = color name. Change any of these in theme.json.
local DEFAULT_COLORS = {
  bg = "black", panel = "black", hdr = "blue", text = "white", dim = "lightGray",
  line = "cyan", sel = "lightBlue", selText = "black",
  bar = "gray", barBtn = "blue", barOn = "cyan", barText = "white",
  ok = "lime", warn = "yellow", err = "red", info = "cyan", accent = "orange",
  toastBar = "gray", toastSys = "blue", hint = "lightGray",
}
local DEFAULT_OPTS = { animations = true, fps = 12, logoColor = "Blue" }

G.c = {}
G.opts = { animations = true, fps = 12, logoColor = "Blue" }
G.pb = false
G.pbError = nil

local function setDefaults()
  for k, v in pairs(DEFAULT_COLORS) do G.c[k] = colors[v] end
  G.c.white, G.c.black, G.c.gray = colors.white, colors.black, colors.gray
  G.c.lightGray, G.c.blue, G.c.lightBlue = colors.lightGray, colors.blue, colors.lightBlue
  G.c.cyan, G.c.red, G.c.yellow = colors.cyan, colors.red, colors.yellow
  G.c.orange, G.c.lime = colors.orange, colors.lime
  for k, v in pairs(DEFAULT_OPTS) do G.opts[k] = v end
end
setDefaults()

-- Colors for the lower half of the logo (from v21). Any #RRGGBB also works.
local LOGO_COLORS = {
  { name = "Blue", rgb = { 63, 85, 255 } },
  { name = "Prismarine", rgb = { 70, 214, 178 } },
  { name = "Aqua", rgb = { 0, 200, 255 } },
  { name = "Emerald", rgb = { 46, 204, 113 } },
  { name = "Lime", rgb = { 163, 230, 53 } },
  { name = "Gold", rgb = { 255, 200, 46 } },
  { name = "Orange", rgb = { 255, 138, 31 } },
  { name = "Red", rgb = { 255, 69, 77 } },
  { name = "Rose", rgb = { 255, 107, 181 } },
  { name = "Magenta", rgb = { 224, 75, 229 } },
  { name = "Violet", rgb = { 155, 92, 255 } },
  { name = "Ice", rgb = { 184, 230, 255 } },
  { name = "Rainbow", rainbow = true },
}

local function readFile(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local h = fs.open(path, "rb")
  if not h then return nil end
  local s = h.readAll()
  h.close()
  return s
end

local function parseHex(text)
  if type(text) ~= "string" then return nil end
  local h = text:match("^#?(%x%x%x%x%x%x)$")
  if not h then return nil end
  return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) }
end

local function validLogoColor(v)
  if type(v) ~= "string" then return false end
  for _, c in ipairs(LOGO_COLORS) do
    if c.name == v then return true end
  end
  return parseHex(v) ~= nil
end

function G.loadTheme(path)
  path = path or THEME_PATH
  setDefaults()
  local raw = readFile(path)
  if not raw then
    -- write a template so the user can edit it
    pcall(function()
      fs.makeDir(fs.getDir(path))
      local t = { colors = DEFAULT_COLORS, logoColor = DEFAULT_OPTS.logoColor,
        animations = DEFAULT_OPTS.animations, fps = DEFAULT_OPTS.fps }
      local h = fs.open(path, "w")
      if h then h.write(textutils.serialiseJSON(t)) h.close() end
    end)
    return
  end
  pcall(function()
    local t = textutils.unserialiseJSON(raw)
    if type(t) ~= "table" then return end
    if type(t.colors) == "table" then
      for role in pairs(DEFAULT_COLORS) do
        local name = t.colors[role]
        if type(name) == "string" and type(colors[name]) == "number" then
          G.c[role] = colors[name]
        end
      end
    end
    if type(t.animations) == "boolean" then G.opts.animations = t.animations end
    if type(t.fps) == "number" then G.opts.fps = max(2, min(30, t.fps)) end
    if validLogoColor(t.logoColor) then G.opts.logoColor = t.logoColor end
  end)
end

-- --------------------------------------------------------------- pixelbox

function G.loadPixelbox()
  if G.pb ~= false then return G.pb end
  G.pbError = nil
  local src = readFile(PB_PATH)
  if not src then G.pbError = "pixelbox_lite.lua not found" return false end
  local shaSrc = readFile(SHA_PATH)
  if not shaSrc then G.pbError = "sha256.lua not found" return false end
  local shaFn = load(shaSrc, "=sha256", "t", _G)
  if not shaFn then G.pbError = "sha256.lua is broken" return false end
  local okS, sha = pcall(shaFn)
  if not okS or type(sha) ~= "function" then G.pbError = "sha256.lua is broken" return false end
  local okH, digest = pcall(sha, src)
  if not okH or digest ~= PB_HASH then
    G.pbError = "pixelbox_lite.lua failed its hash check"
    return false
  end
  local fn = load(src, "=pixelbox_lite", "t", _G)
  if not fn then G.pbError = "pixelbox_lite.lua is broken" return false end
  local ok, mod = pcall(fn)
  if not ok or type(mod) ~= "table" or type(mod.new) ~= "function" then
    G.pbError = "pixelbox_lite.lua did not load"
    return false
  end
  G.pb = mod
  return mod
end

function G.init(themePath)
  G.loadTheme(themePath)
  G.loadPixelbox()
  return G.pb ~= false
end

-- ---------------------------------------------------------------- palette
-- The logo uses smooth shade ramps, so the dashboard reprograms the palette
-- (like v21 did). The UI colors keep their names and still look right.
--   gray ramp:   gray, pink, lightGray, magenta, white
--   accent ramp: brown, green, blue, purple, cyan, lightBlue
-- red, yellow, lime and orange stay as they are. black is the background.

local SLOT_GR = { colors.gray, colors.pink, colors.lightGray, colors.magenta, colors.white }
local SLOT_AC = { colors.brown, colors.green, colors.blue, colors.purple, colors.cyan, colors.lightBlue }
G.slotGr, G.slotAc = SLOT_GR, SLOT_AC
G.sceneOn = false

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end
local function lerp(a, b, t) return a + (b - a) * t end
local function mix(a, b, t)
  return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end

local function hsv(h, s, v)
  h = (h % 1) * 6
  local i = floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  local r, g, b
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return { r * 255, g * 255, b * 255 }
end

local function accentAt(acc, t)
  local dark = { acc[1] * 0.10, acc[2] * 0.10, acc[3] * 0.10 }
  if t <= 0.65 then return mix(dark, acc, t / 0.65) end
  local light = mix(acc, { 255, 255, 255 }, 0.40)
  return mix(acc, light, (t - 0.65) / 0.35)
end

local function grayAt(t)
  local v
  if t <= 0.6 then v = lerp(24, 150, t / 0.6) else v = lerp(150, 245, (t - 0.6) / 0.4) end
  return { v, v, min(255, v + 3) }
end

local function logoRGB(t)
  local name = G.opts.logoColor
  for _, c in ipairs(LOGO_COLORS) do
    if c.name == name then
      if c.rainbow then return hsv((t or 0) * 0.1, 0.72, 1) end
      return c.rgb
    end
  end
  return parseHex(name) or LOGO_COLORS[1].rgb
end

local function setPal(c, rgb)
  term.native().setPaletteColor(c, clamp(rgb[1] / 255, 0, 1), clamp(rgb[2] / 255, 0, 1),
    clamp(rgb[3] / 255, 0, 1))
end

-- Program the dashboard palette. Cheap enough to call every frame (Rainbow).
function G.applyScene(t)
  pcall(function()
    local acc = logoRGB(t)
    setPal(colors.black, { 5, 7, 12 })
    for i, c in ipairs(SLOT_GR) do setPal(c, grayAt((i - 1) / (#SLOT_GR - 1))) end
    for i, c in ipairs(SLOT_AC) do setPal(c, accentAt(acc, (i - 1) / (#SLOT_AC - 1))) end
  end)
  G.sceneOn = true
end

function G.isRainbow()
  return G.opts.logoColor == "Rainbow"
end

-- Back to the normal colors (apps expect them).
function G.restorePalette()
  pcall(function()
    local nat = term.native()
    for i = 0, 15 do
      local c = 2 ^ i
      local r, g, b = term.nativePaletteColor(c)
      nat.setPaletteColor(c, r, g, b)
    end
  end)
  G.sceneOn = false
end

-- ---------------------------------------------------------------- sprites

local Sprite = {}
Sprite.__index = Sprite

function G.sprite(w, h)
  local win = window.create(term.native(), 1, 1, w, h, false)
  local s = setmetatable({ w = w, h = h, win = win }, Sprite)
  if G.pb then s.box = G.pb.new(win, G.c.bg) end
  return s
end

-- Fill the whole sprite and draw a 1 sub-pixel outline around it.
function Sprite:panel(fill, line)
  local w, h = self.w, self.h
  if self.box then
    local cv = self.box.canvas
    local pw, ph = w * 2, h * 3
    for y = 1, ph do
      local row = cv[y]
      for x = 1, pw do row[x] = fill end
    end
    local top, bot = cv[1], cv[ph]
    for x = 1, pw do top[x] = line bot[x] = line end
    for y = 1, ph do
      local row = cv[y]
      row[1] = line
      row[pw] = line
    end
    self.box:render()
  else
    local win = self.win
    win.setBackgroundColor(fill)
    win.setTextColor(G.c.text)
    win.clear()
    win.setBackgroundColor(line)
    local bar = string.rep(" ", w)
    win.setCursorPos(1, 1) win.write(bar)
    win.setCursorPos(1, h) win.write(bar)
    for y = 2, h - 1 do
      win.setCursorPos(1, y) win.write(" ")
      win.setCursorPos(w, y) win.write(" ")
    end
  end
end

function Sprite:text(x, y, s, fg, bg)
  if y < 1 or y > self.h or x > self.w or s == "" then return end
  if x < 1 then s = s:sub(2 - x) x = 1 end
  s = s:sub(1, self.w - x + 1)
  if s == "" then return end
  local win = self.win
  win.setCursorPos(x, y)
  win.setBackgroundColor(bg or G.c.panel)
  win.setTextColor(fg or G.c.text)
  win.write(s)
end

-- Copy sprite rows r1..r2 to the real screen at (x, y). Clips to the screen.
-- Rows that would land above screen row `miny` (default 1) are skipped.
function Sprite:present(x, y, r1, r2, miny)
  local nat = term.native()
  local W, H = nat.getSize()
  r1 = r1 or 1
  r2 = r2 or self.h
  miny = miny or 1
  local c1 = 1
  if x < 1 then c1 = 2 - x end
  local c2 = min(self.w, W - x + 1)
  if c2 < c1 then return end
  local dx = max(x, 1)
  for r = r1, r2 do
    local yy = y + r - 1
    if yy >= miny and yy <= H then
      local t, f, b = self.win.getLine(r)
      nat.setCursorPos(dx, yy)
      nat.blit(t:sub(c1, c2), f:sub(c1, c2), b:sub(c1, c2))
    end
  end
end

-- ------------------------------------------------------------------- logo
-- The PRISMARINE logo from Prismarine OS v21. Digits: 0 blank, 1-4 light to
-- solid shade, 5 lower half block, 6 upper half block. The first four rows
-- are the gray half, the last four the colored half.

local LOGO_ROWS = {
  "0111150011115011051110511511150051115001111501101111505111",
  "0110110011011011011000110110110011011001101101101101101106",
  "0222260022226022062250220220220022222002222602202202202220",
  "0340000034034034000340340340340034034003403403403403403400",
  "0550000055055055000550550550550055055005505505505505505500",
  "0110000011011011000110110110110011011001101101101101101100",
  "0220000022022022000220220000220022022002202202202202202205",
  "5335000533033033033360330000330533033053303303303303306333",
}
local LOGO_W, LOGO_R, LOGO_SPLIT = 58, #LOGO_ROWS, 8
local SHADE = { [0] = 0, 0.34, 0.58, 0.80, 1.0 }
local ROWBASE = { 0.34, 0.34, 0.58, 0.85, 0.50, 0.34, 0.58, 0.85 }

local SRC
local function buildSrc()
  SRC = {}
  for r = 1, LOGO_R do
    local top, bot = {}, {}
    local row = LOGO_ROWS[r]
    for x = 1, LOGO_W do
      local ch = tonumber(row:sub(x, x))
      local tl, bl = 0, 0
      if ch >= 1 and ch <= 4 then
        tl, bl = SHADE[ch], SHADE[ch]
      elseif ch == 5 then
        bl = ROWBASE[r]
      elseif ch == 6 then
        tl = ROWBASE[r]
      end
      top[x], bot[x] = tl, bl
    end
    SRC[r * 2 - 1], SRC[r * 2] = top, bot
  end
end

local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local function thr(x, y)
  return (BAYER[(y - 1) % 4 + 1][(x - 1) % 4 + 1] + 0.5) / 16
end

-- Which of n palette shades a brightness maps to, with ordered dithering.
local function slotFor(level, n, x, y)
  local i = floor(level * (n - 1) + thr(x, y))
  if i < 0 then i = 0 elseif i > n - 1 then i = n - 1 end
  return i + 1
end

local logoCache = {}

-- The logo scaled to dw pixels wide: lv[y][x] brightness, rg[y] 1 gray, 2 color.
function G.logo(dw)
  if logoCache[dw] then return logoCache[dw] end
  if not SRC then buildSrc() end
  local SH = LOGO_R * 2
  local dh = max(4, floor(dw * (LOGO_R * 9) / (LOGO_W * 6) + 0.5))
  local lv, rg = {}, {}
  for dy = 1, dh do
    local y0, y1 = (dy - 1) * SH / dh, dy * SH / dh
    local row = {}
    for dx = 1, dw do
      local x0, x1 = (dx - 1) * LOGO_W / dw, dx * LOGO_W / dw
      local sum, wsum = 0, 0
      for sy = floor(y0) + 1, min(SH, math.ceil(y1)) do
        local wy = min(sy, y1) - max(sy - 1, y0)
        local srow = SRC[sy]
        for sx = floor(x0) + 1, min(LOGO_W, math.ceil(x1)) do
          local wx = min(sx, x1) - max(sx - 1, x0)
          sum = sum + srow[sx] * wx * wy
          wsum = wsum + wx * wy
        end
      end
      row[dx] = (wsum > 0) and sum / wsum or 0
    end
    lv[dy] = row
    rg[dy] = ((y0 + y1) / 2 <= LOGO_SPLIT) and 1 or 2
  end
  local logo = { w = dw, h = dh, lv = lv, rg = rg }
  logoCache[dw] = logo
  return logo
end

-- Layout of the dashboard scene for a sprite. none = true on a tiny screen.
local function newScene(spr, reserve)
  local pw, ph = spr.w * 2, spr.h * 3
  local ratio = LOGO_W * 6 / (LOGO_R * 9)
  local dw = min(98, pw - 4, floor((spr.h - reserve) * 3 * ratio))
  if dw < 36 then return { none = true } end
  local logo = G.logo(dw)
  local logoRows = math.ceil(logo.h / 3)
  local top = max(1, floor((spr.h - logoRows - reserve) / 2) + 1)
  local sc = {
    logo = logo, pw = pw, ph = ph,
    ox = floor((pw - dw) / 2),
    oy = (top - 1) * 3 + floor((logoRows * 3 - logo.h) / 2),
    bubbles = {}, last = nil,
  }
  for i = 1, 16 do
    sc.bubbles[i] = {
      x = math.random(2, pw - 1), y = math.random(1, ph),
      v = 4 + math.random() * 10, ph = math.random() * 6, c = math.random(2, 4),
    }
  end
  return sc
end

local function paintBubbles(sc, canvas, dt)
  for _, b in ipairs(sc.bubbles) do
    b.y = b.y - b.v * dt
    b.x = b.x + sin(b.y * 0.2 + b.ph) * dt * 4
    if b.y < 1 then
      b.y = sc.ph
      b.x = math.random(2, sc.pw - 1)
      b.v = 4 + math.random() * 10
    end
    local x, y = floor(b.x + 0.5), floor(b.y + 0.5)
    if x >= 1 and x <= sc.pw and y >= 1 and y <= sc.ph then
      canvas[y][x] = SLOT_AC[b.c]
    end
  end
end

-- The gray half shines, the colored half ripples like water.
local function paintLogo(sc, canvas, t)
  local logo = sc.logo
  local dw, dh = logo.w, logo.h
  local ngr, nac = #SLOT_GR, #SLOT_AC
  local lastGray = 0
  for dy = 1, dh do
    if logo.rg[dy] == 1 then lastGray = dy end
  end
  local shine = ((t * 0.45) % 2.4 - 0.6) * (dw + dh * 1.6)
  for dy = 1, dh do
    local lvrow = logo.lv[dy]
    local gray = logo.rg[dy] == 1
    local crow = canvas[sc.oy + dy]
    if crow then
      local r = dy - lastGray
      local off = 0
      if not gray then
        off = floor(sin(r * 0.95 - t * 4.2) * (0.6 + r * 0.05) * 1.2 + 0.5)
      end
      for dx = 1, dw do
        local l = lvrow[clamp(dx + off, 1, dw)]
        if l > 0.03 then
          if gray then
            local d = (dx + dy * 1.6) - shine
            if d > -9 and d < 9 then
              local k = 1 - math.abs(d) / 9
              l = l + k * k * 0.6
            end
            crow[sc.ox + dx] = SLOT_GR[slotFor(l, ngr, dx, dy)]
          else
            l = l * (0.86 + 0.14 * sin(dx * 0.45 + r * 0.8 - t * 3.2))
            crow[sc.ox + dx] = SLOT_AC[slotFor(l, nac, dx, dy)]
          end
        end
      end
    end
  end
end

-- Paint the dashboard frame. t is a time in seconds. The last cell row holds
-- the hint text. Needs Pixelbox and the scene palette.
function Sprite:dash(t, hint)
  local bg = colors.black
  local cv = self.box.canvas
  local pw, ph = self.w * 2, self.h * 3
  for y = 1, ph do
    local row = cv[y]
    for x = 1, pw do row[x] = bg end
  end
  if not self.scene then self.scene = newScene(self, 2) end
  local sc = self.scene
  if not sc.none then
    local dt = sc.last and clamp(t - sc.last, 0, 0.2) or 0
    sc.last = t
    paintBubbles(sc, cv, dt)
    paintLogo(sc, cv, t)
  end
  self.box:render()
  if hint and hint ~= "" then
    local s = hint:sub(1, self.w)
    local x = floor((self.w - #s) / 2) + 1
    self:text(x, self.h, s, colors.lightGray, bg)
  end
end

return G
