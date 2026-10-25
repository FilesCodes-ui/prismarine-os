--[==[ Prismarine
 ____
/\ _`\ __ __
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine frame buffer.
--
-- The UI draws into this object instead of the real screen. Every write goes
-- to a pending layer. flush() then compares the pending cells with what the
-- screen already shows and sends only the cells that changed, in runs.
--
-- This removes two problems:
--   * Flicker. The screen never shows a half drawn frame (panel first, text
--     second). Only the finished frame is sent.
--   * Lag. Cells that did not change cost nothing.
--
-- invalidate() forgets what the screen shows. Call it when something else
-- wrote to the real screen (an app window became visible, for example).

local M = {}

local toBlit = colors.toBlit
local concat = table.concat

function M.new(nat)
  local S = {}
  local W, H = nat.getSize()

  -- pending layer: only cells written since the last flush
  local pt, pf, pb = {}, {}, {}
  local lo, hi = {}, {}
  -- shadow layer: what the real screen shows. nil means unknown.
  local st, sf, sb = {}, {}, {}

  local cx, cy = 1, 1
  local fg, bg = "0", "f"
  local anyDirty = false

  local function reset()
    pt, pf, pb, lo, hi = {}, {}, {}, {}, {}
    st, sf, sb = {}, {}, {}
    anyDirty = false
  end

  local function fit()
    local w, h = nat.getSize()
    if w ~= W or h ~= H then
      W, H = w, h
      reset()
    end
  end

  function S.getSize()
    fit()
    return W, H
  end

  function S.invalidate()
    st, sf, sb = {}, {}, {}
  end

  function S.setCursorPos(x, y) cx, cy = x, y end
  function S.getCursorPos() return cx, cy end
  function S.setBackgroundColor(c) bg = toBlit(c) end
  function S.setTextColor(c) fg = toBlit(c) end
  S.setBackgroundColour, S.setTextColour = S.setBackgroundColor, S.setTextColor
  function S.setCursorBlink(on) nat.setCursorBlink(on) end
  function S.getCursorBlink() return nat.getCursorBlink and nat.getCursorBlink() or false end
  function S.isColor() return nat.isColor() end
  S.isColour = S.isColor
  function S.setPaletteColor(...) return nat.setPaletteColor(...) end
  function S.getPaletteColor(...) return nat.getPaletteColor(...) end
  S.setPaletteColour, S.getPaletteColour = S.setPaletteColor, S.getPaletteColor
  function S.getBackgroundColor() return colors.fromBlit(bg) end
  function S.getTextColor() return colors.fromBlit(fg) end

  local function put(x, y, ch, f, b)
    local rt = pt[y]
    if not rt then
      rt = {}
      pt[y], pf[y], pb[y] = rt, {}, {}
      lo[y], hi[y] = x, x
    end
    rt[x] = ch
    pf[y][x] = f
    pb[y][x] = b
    if x < lo[y] then lo[y] = x end
    if x > hi[y] then hi[y] = x end
    anyDirty = true
  end

  function S.write(s)
    s = tostring(s)
    local y = cy
    if y < 1 or y > H then
      cx = cx + #s
      return
    end
    local f, b = fg, bg
    for i = 1, #s do
      local x = cx + i - 1
      if x >= 1 and x <= W then put(x, y, s:sub(i, i), f, b) end
    end
    cx = cx + #s
  end

  function S.blit(t, f, b)
    local y = cy
    if y < 1 or y > H then
      cx = cx + #t
      return
    end
    for i = 1, #t do
      local x = cx + i - 1
      if x >= 1 and x <= W then put(x, y, t:sub(i, i), f:sub(i, i), b:sub(i, i)) end
    end
    cx = cx + #t
  end

  function S.clear()
    fit()
    local b = bg
    for y = 1, H do
      for x = 1, W do put(x, y, " ", fg, b) end
    end
  end

  function S.clearLine()
    if cy < 1 or cy > H then return end
    for x = 1, W do put(x, cy, " ", fg, bg) end
  end

  -- Fill a rectangle with one background color.
  function S.fill(x1, y1, x2, y2, color)
    local b = toBlit(color)
    for y = math.max(1, y1), math.min(H, y2) do
      for x = math.max(1, x1), math.min(W, x2) do put(x, y, " ", "0", b) end
    end
  end

  -- Send the changes. Returns how many cells went out.
  function S.flush()
    if not anyDirty then return 0 end
    local sent = 0
    for y, rt in pairs(pt) do
      local rf, rb = pf[y], pb[y]
      local ot, of, ob = st[y], sf[y], sb[y]
      if not ot then ot, of, ob = {}, {}, {}; st[y], sf[y], sb[y] = ot, of, ob end
      local x, last = lo[y], hi[y]
      while x <= last do
        local c = rt[x]
        if c ~= nil and (ot[x] ~= c or of[x] ~= rf[x] or ob[x] ~= rb[x]) then
          -- run starts here. Bridge gaps of up to two unchanged cells.
          local x0, x1, gap = x, x, 0
          local nx = x + 1
          while nx <= last do
            local d = rt[nx]
            if d == nil then break end
            if ot[nx] ~= d or of[nx] ~= rf[nx] or ob[nx] ~= rb[nx] then
              x1, gap = nx, 0
            else
              gap = gap + 1
              if gap > 2 then break end
            end
            nx = nx + 1
          end
          local tt, ff, bb = {}, {}, {}
          for i = x0, x1 do
            local ch, f, b = rt[i], rf[i], rb[i]
            tt[#tt + 1], ff[#ff + 1], bb[#bb + 1] = ch, f, b
            ot[i], of[i], ob[i] = ch, f, b
          end
          nat.setCursorPos(x0, y)
          nat.blit(concat(tt), concat(ff), concat(bb))
          sent = sent + (x1 - x0 + 1)
          x = x1 + 1
        else
          x = x + 1
        end
      end
    end
    pt, pf, pb, lo, hi = {}, {}, {}, {}, {}
    anyDirty = false
    return sent
  end

  -- Flush, then put the real cursor where the UI left it (the lock screen caret).
  function S.syncCursor()
    S.flush()
    nat.setCursorPos(cx, cy)
  end

  return S
end

return M
