--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Pixel Dash
--@prismarine-api
-- prismarine: background touch
-- Design dashboards for a monitor, then run them. Buttons and toggles switch
-- redstone outputs when someone touches the monitor; lamps and bars show
-- redstone signals. Everything is drawn with sub-pixels (2x3 per cell).
-- Press F1 in the editor for help.

local api = rawget(_G, "prismarine") or {}
local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin

local F = {}    -- general helpers, files, monitor
local D = {}    -- drawing
local W = {}    -- widgets
local UI = {}   -- terminal screens
local R = {}    -- running a dashboard
local S = { undo = {} }   -- editor state
local CFG = { mon = nil, scale = 1 }
local DIR = api.home or "/appdata/pixeldash"

-- ── Colors ───────────────────────────────────────────────────────────────────
local ORDER = {
    colors.black, colors.gray, colors.lightGray, colors.white, colors.red, colors.orange,
    colors.yellow, colors.lime, colors.green, colors.cyan, colors.lightBlue, colors.blue,
    colors.purple, colors.magenta, colors.pink, colors.brown,
}
local CNAME = {
    "black", "gray", "light gray", "white", "red", "orange", "yellow", "lime", "green",
    "cyan", "light blue", "blue", "purple", "magenta", "pink", "brown",
}
local TONES = { 0.07, 0.3, 0.6, 0.94, 0.4, 0.72, 0.85, 0.7, 0.45, 0.55, 0.6, 0.28, 0.33, 0.55, 0.7, 0.31 }
local TONE, VALID = {}, {}
for i, c in ipairs(ORDER) do TONE[c] = TONES[i]; VALID[c] = true end
local RAINBOW = { colors.red, colors.orange, colors.yellow, colors.lime, colors.cyan, colors.blue, colors.purple, colors.magenta }

local KINDS = { "panel", "text", "button", "toggle", "lamp", "bar", "clock" }
local KINDSET = {}
for _, k in ipairs(KINDS) do KINDSET[k] = true end
local SIDES = { "top", "bottom", "left", "right", "front", "back" }
local SIDESET = {}
for _, s in ipairs(SIDES) do SIDESET[s] = true end
local MODES = { "toggle", "pulse", "on", "off" }
local EFFECTS = { "none", "pulse", "blink", "rainbow" }
local BGFX = { "none", "stars", "grid" }
local ALIGN = { "left", "center", "right" }
local IOS = { "in", "out" }

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- ── Helpers ──────────────────────────────────────────────────────────────────
function F.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end
function F.int(v, def, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then v = def end
    return F.clamp(floor(v + 0.5), lo, hi)
end
function F.copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = F.copy(x) end
    return o
end
function F.cut(s, n)
    s = tostring(s)
    if n <= 0 then return "" end
    if #s > n then return s:sub(1, n) end
    return s
end
function F.pad(s, n)
    s = F.cut(s, n)
    return s .. string.rep(" ", n - #s)
end
function F.colorIndex(c)
    for i, x in ipairs(ORDER) do if x == c then return i end end
    return 1
end
function F.safe(s)
    local r = tostring(s or ""):lower():gsub("[^%w_%-]", "_")
    return r:sub(1, 20)
end

-- ── Files ────────────────────────────────────────────────────────────────────
function F.ensure(p)
    if not fs.exists(p) then pcall(fs.makeDir, p) end
end
function F.read(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local s = h.readAll()
    h.close()
    return s
end
function F.write(path, s)
    local h = fs.open(path, "w")
    if not h then return false end
    h.write(s)
    h.close()
    return true
end
function F.path(name) return DIR .. "/dash/" .. name .. ".dash" end
function F.listDash()
    local out = {}
    local dir = DIR .. "/dash"
    if fs.exists(dir) and fs.isDir(dir) then
        for _, n in ipairs(fs.list(dir)) do
            local b = n:match("^(.+)%.dash$")
            if b then out[#out + 1] = b end
        end
    end
    table.sort(out)
    return out
end
function F.loadCfg()
    local s = F.read(DIR .. "/config.dat")
    local t = s and #s < 5000 and textutils.unserialize(s)
    if type(t) == "table" then
        if type(t.mon) == "string" then CFG.mon = t.mon:sub(1, 60) end
        local sc = tonumber(t.scale)
        if sc and sc >= 0.5 and sc <= 5 then CFG.scale = floor(sc * 2 + 0.5) / 2 end
    end
end
function F.saveCfg()
    F.write(DIR .. "/config.dat", textutils.serialize({ mon = CFG.mon, scale = CFG.scale }))
end

-- ── Monitor ──────────────────────────────────────────────────────────────────
function F.monitors()
    local out = {}
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "monitor" then out[#out + 1] = n end
    end
    return out
end
function F.openMon()
    local name = CFG.mon
    if not name or not peripheral.isPresent(name) or peripheral.getType(name) ~= "monitor" then
        name = F.monitors()[1]
    end
    if not name then return nil end
    local m = peripheral.wrap(name)
    if not m then return nil end
    pcall(m.setTextScale, CFG.scale or 1)
    pcall(m.setBackgroundColor, colors.black)
    pcall(m.clear)
    return m, name
end

-- ── Canvas and drawing ───────────────────────────────────────────────────────
function D.new(pw, ph, col)
    local c = { pw = pw, ph = ph }
    for y = 1, ph do
        local row = {}
        for x = 1, pw do row[x] = col end
        c[y] = row
    end
    return c
end
function D.rect(c, x1, y1, x2, y2, col)
    x1, y1 = max(1, x1), max(1, y1)
    x2, y2 = min(c.pw, x2), min(c.ph, y2)
    for y = y1, y2 do
        local row = c[y]
        for x = x1, x2 do row[x] = col end
    end
end
function D.box(c, x1, y1, x2, y2, col)
    D.rect(c, x1, y1, x2, y1, col)
    D.rect(c, x1, y2, x2, y2, col)
    D.rect(c, x1, y1, x1, y2, col)
    D.rect(c, x2, y1, x2, y2, col)
end

-- 3x5 pixel font.
local GLY = {}
do
    local src = {
        { "A", ".#./#.#/###/#.#/#.#" }, { "B", "##./#.#/##./#.#/##." }, { "C", ".##/#../#../#../.##" },
        { "D", "##./#.#/#.#/#.#/##." }, { "E", "###/#../##./#../###" }, { "F", "###/#../##./#../#.." },
        { "G", ".##/#../#.#/#.#/.##" }, { "H", "#.#/#.#/###/#.#/#.#" }, { "I", "###/.#./.#./.#./###" },
        { "J", "..#/..#/..#/#.#/.#." }, { "K", "#.#/#.#/##./#.#/#.#" }, { "L", "#../#../#../#../###" },
        { "M", "#.#/###/###/#.#/#.#" }, { "N", "##./#.#/#.#/#.#/#.#" }, { "O", ".#./#.#/#.#/#.#/.#." },
        { "P", "##./#.#/##./#../#.." }, { "Q", ".#./#.#/#.#/##./.##" }, { "R", "##./#.#/##./#.#/#.#" },
        { "S", ".##/#../.#./..#/##." }, { "T", "###/.#./.#./.#./.#." }, { "U", "#.#/#.#/#.#/#.#/###" },
        { "V", "#.#/#.#/#.#/#.#/.#." }, { "W", "#.#/#.#/###/###/#.#" }, { "X", "#.#/#.#/.#./#.#/#.#" },
        { "Y", "#.#/#.#/.#./.#./.#." }, { "Z", "###/..#/.#./#../###" },
        { "0", "###/#.#/#.#/#.#/###" }, { "1", ".#./##./.#./.#./###" }, { "2", "##./..#/.#./#../###" },
        { "3", "##./..#/.#./..#/##." }, { "4", "#.#/#.#/###/..#/..#" }, { "5", "###/#../##./..#/##." },
        { "6", ".##/#../###/#.#/###" }, { "7", "###/..#/.#./.#./.#." }, { "8", "###/#.#/###/#.#/###" },
        { "9", "###/#.#/###/..#/##." },
        { " ", ".../.../.../.../..." }, { ":", ".../.#./.../.#./..." }, { ".", ".../.../.../.../.#." },
        { "-", ".../.../###/.../..." }, { "%", "#.#/..#/.#./#../#.#" }, { "!", ".#./.#./.#./.../.#." },
        { "?", "##./..#/.#./.../.#." }, { "/", "..#/..#/.#./#../#.." }, { "+", ".../.#./###/.#./..." },
        { "_", ".../.../.../.../###" }, { "*", "#.#/.#./###/.#./#.#" }, { "'", ".#./.#./.../.../..." },
    }
    for _, e in ipairs(src) do
        local rows = {}
        for r in e[2]:gmatch("[^/]+") do rows[#rows + 1] = r end
        GLY[e[1]] = rows
    end
end
function D.textWidth(s, sc) return #s * 4 * sc - sc end
function D.text(c, s, x, y, sc, col)
    for i = 1, #s do
        local g = GLY[s:sub(i, i):upper()] or GLY["?"]
        local gx = x + (i - 1) * 4 * sc
        for ry = 1, 5 do
            local row = g[ry]
            for rx = 1, 3 do
                if row:sub(rx, rx) == "#" then
                    D.rect(c, gx + (rx - 1) * sc, y + (ry - 1) * sc, gx + rx * sc - 1, y + ry * sc - 1, col)
                end
            end
        end
    end
end

-- A color that changes with the widget's effect.
function D.accent(w, base, t)
    local f = w.fx
    if f == "pulse" then
        return (sin(t * 4) > 0) and base or w.fxc
    elseif f == "blink" then
        return (floor(t * 2) % 2 == 0) and base or (w.bg or colors.black)
    elseif f == "rainbow" then
        return RAINBOW[floor(t * 4) % #RAINBOW + 1]
    end
    return base
end

function D.clock(fmt)
    local ok, s = pcall(os.date, (fmt and fmt ~= "") and fmt or "%H:%M")
    if ok and type(s) == "string" then return s:sub(1, 12) end
    return "--:--"
end

-- Text inside a widget: size picked to fit unless the widget sets one.
function D.label(c, w, s, col)
    s = tostring(s or "")
    if s == "" then return end
    local x1, y1 = w.x, w.y
    local x2, y2 = w.x + w.w - 1, w.y + w.h - 1
    local sc = w.sc or 0
    local maxw, maxh = w.w - 2, w.h - 2
    if sc < 1 then
        sc = 1
        for k = 2, 6 do
            if D.textWidth(s, k) <= maxw and 5 * k <= maxh then sc = k end
        end
    end
    while sc > 1 and (D.textWidth(s, sc) > maxw or 5 * sc > maxh) do sc = sc - 1 end
    local n = floor((maxw + sc) / (4 * sc))
    if n < 1 then return end
    if #s > n then s = s:sub(1, n) end
    local tw = D.textWidth(s, sc)
    local x
    if w.al == "left" then x = x1 + 2
    elseif w.al == "right" then x = x2 - tw - 1
    else x = x1 + floor((w.w - tw) / 2) end
    local y = y1 + floor((w.h - 5 * sc) / 2)
    D.text(c, s, x, y, sc, col)
end

-- Redstone readings. In the editor (not live) they show a sample value.
function R.analog(w, ctx)
    if not ctx.live then return 10 end
    local s = w.src
    local ok, v = pcall(function()
        if s.io == "out" then return redstone.getAnalogOutput(s.side) end
        return redstone.getAnalogInput(s.side)
    end)
    if ok and type(v) == "number" then return v end
    return 0
end
function R.getOut(side)
    local ok, v = pcall(redstone.getOutput, side)
    return ok and v == true
end

function W.draw(c, w, ctx)
    local x1, y1 = w.x, w.y
    local x2, y2 = w.x + w.w - 1, w.y + w.h - 1
    local k, t = w.kind, ctx.t
    local fg = D.accent(w, w.fg, t)
    if k == "panel" then
        if w.bg then D.rect(c, x1, y1, x2, y2, w.bg) end
        if w.bd then D.box(c, x1, y1, x2, y2, w.bd) end
    elseif k == "text" or k == "clock" then
        if w.bg then D.rect(c, x1, y1, x2, y2, w.bg) end
        if w.bd then D.box(c, x1, y1, x2, y2, w.bd) end
        D.label(c, w, (k == "clock") and D.clock(w.tx) or w.tx, fg)
    elseif k == "button" then
        local pressed = ctx.st[w.id] and ctx.st[w.id] > t
        local back, front = w.bg or colors.gray, fg
        if pressed then back, front = front, back end
        D.rect(c, x1, y1, x2, y2, back)
        if w.bd then D.box(c, x1, y1, x2, y2, w.bd) end
        D.label(c, w, w.tx, front)
    elseif k == "toggle" then
        local on = ctx.live and R.getOut(w.act.side)
        D.rect(c, x1, y1, x2, y2, on and w.fxc or (w.bg or colors.gray))
        if w.bd then D.box(c, x1, y1, x2, y2, w.bd) end
        D.label(c, w, w.tx, on and colors.black or fg)
    elseif k == "lamp" then
        local on = R.analog(w, ctx) > 0
        D.rect(c, x1, y1, x2, y2, on and D.accent(w, w.fxc, t) or (w.bg or colors.gray))
        if w.bd then D.box(c, x1, y1, x2, y2, w.bd) end
        local bgc = ctx.bg or colors.black
        D.rect(c, x1, y1, x1, y1, bgc)
        D.rect(c, x2, y1, x2, y1, bgc)
        D.rect(c, x1, y2, x1, y2, bgc)
        D.rect(c, x2, y2, x2, y2, bgc)
    elseif k == "bar" then
        D.rect(c, x1, y1, x2, y2, w.bg or colors.gray)
        local inner = w.w - 2
        local fill = floor(inner * R.analog(w, ctx) / 15 + 0.5)
        if fill > 0 then D.rect(c, x1 + 1, y1 + 1, x1 + fill, y2 - 1, fg) end
        if w.bd then D.box(c, x1, y1, x2, y2, w.bd) end
    end
end

function D.background(c, dash, t)
    D.rect(c, 1, 1, c.pw, c.ph, dash.bg)
    if dash.fx == "stars" then
        for i = 1, floor(c.pw * c.ph / 90) do
            local x = (i * 37 + (i * i) % 11) % c.pw + 1
            local y = (i * 53 + (i * 7) % 13) % c.ph + 1
            local tw = sin(t * 1.5 + i)
            local col = (tw > 0.6) and colors.white or ((tw > -0.3) and colors.lightGray or colors.gray)
            c[y][x] = col
        end
    elseif dash.fx == "grid" then
        local gc = (dash.bg == colors.gray) and colors.lightGray or colors.gray
        for y = 1, c.ph, 8 do D.rect(c, 1, y, c.pw, y, gc) end
        for x = 1, c.pw, 8 do D.rect(c, x, 1, x, c.ph, gc) end
    end
end

function D.dash(c, dash, ctx)
    D.background(c, dash, ctx.t)
    ctx.bg = dash.bg
    for _, w in ipairs(dash.widgets) do W.draw(c, w, ctx) end
end

-- Canvas to terminal cells (works on the term or on a monitor).
function D.cells(c, t, x0, y0)
    local blit = colors.toBlit
    local cw, ch = floor(c.pw / 2), floor(c.ph / 3)
    for cy = 1, ch do
        local chars, fgs, bgs = {}, {}, {}
        local py = (cy - 1) * 3
        local r1, r2, r3 = c[py + 1], c[py + 2], c[py + 3]
        for cx = 1, cw do
            local px = (cx - 1) * 2
            local p = { r1[px + 1], r1[px + 2], r2[px + 1], r2[px + 2], r3[px + 1], r3[px + 2] }
            local counts, order = {}, {}
            for i = 1, 6 do
                local k = p[i]
                if not counts[k] then counts[k] = 0; order[#order + 1] = k end
                counts[k] = counts[k] + 1
            end
            local ch2, fg, back
            if #order == 1 then
                ch2, fg, back = " ", order[1], order[1]
            else
                if #order > 2 then
                    table.sort(order, function(x, y)
                        if counts[x] ~= counts[y] then return counts[x] > counts[y] end
                        return x < y
                    end)
                end
                local a, b = order[1], order[2]
                local bits, last = 0, false
                for i = 1, 6 do
                    local k = p[i]
                    local isB
                    if k == b then isB = true
                    elseif k == a then isB = false
                    else isB = abs((TONE[k] or 0) - (TONE[b] or 0)) < abs((TONE[k] or 0) - (TONE[a] or 0)) end
                    if i == 6 then last = isB
                    elseif isB then bits = bits + 2 ^ (i - 1) end
                end
                bits = floor(bits)
                if last then ch2, fg, back = string.char(128 + (31 - bits)), a, b
                else ch2, fg, back = string.char(128 + bits), b, a end
            end
            chars[cx], fgs[cx], bgs[cx] = ch2, blit(fg), blit(back)
        end
        t.setCursorPos(x0, y0 + cy - 1)
        t.blit(table.concat(chars), table.concat(fgs), table.concat(bgs))
    end
end

-- Fit a pw x ph picture into vw x vh pixels. Returns scale and offsets.
function F.fit(pw, ph, vw, vh)
    local s = min(vw / pw, vh / ph)
    if s >= 1 then s = floor(s) end
    local ox = floor((vw - pw * s) / 2)
    local oy = floor((vh - ph * s) / 2)
    return s, ox, oy
end
function F.blitScaled(src, dst, s, ox, oy, fill)
    D.rect(dst, 1, 1, dst.pw, dst.ph, fill)
    local xmap = {}
    for sx = 1, dst.pw do
        local dx = floor((sx - ox - 1) / s) + 1
        if dx >= 1 and dx <= src.pw then xmap[sx] = dx end
    end
    for sy = 1, dst.ph do
        local dy = floor((sy - oy - 1) / s) + 1
        if dy >= 1 and dy <= src.ph then
            local srow, drow = src[dy], dst[sy]
            for sx = 1, dst.pw do
                local dx = xmap[sx]
                if dx then drow[sx] = srow[dx] end
            end
        end
    end
end

-- ── Widgets: defaults, cleaning, saving ──────────────────────────────────────
local DEF = {
    panel  = { w = 34, h = 22, tx = "", bg = colors.gray, bd = colors.lightGray, fg = colors.white },
    text   = { w = 44, h = 11, tx = "HELLO", bg = false, bd = false, fg = colors.white },
    button = { w = 38, h = 15, tx = "PUSH", bg = colors.blue, bd = colors.lightBlue, fg = colors.white },
    toggle = { w = 38, h = 15, tx = "LIGHT", bg = colors.gray, bd = colors.lightGray, fg = colors.white, fxc = colors.lime },
    lamp   = { w = 12, h = 12, tx = "", bg = colors.gray, bd = colors.lightGray, fg = colors.white, fxc = colors.lime },
    bar    = { w = 48, h = 9, tx = "", bg = colors.gray, bd = colors.lightGray, fg = colors.lime },
    clock  = { w = 48, h = 11, tx = "%H:%M", bg = false, bd = false, fg = colors.yellow },
}

function W.new(kind, dash)
    local d = DEF[kind]
    dash.nextId = (dash.nextId or 0) + 1
    local w = {
        id = "w" .. dash.nextId, kind = kind, x = 1, y = 1, w = d.w, h = d.h, tx = d.tx,
        fg = d.fg, bg = d.bg, bd = d.bd, fx = "none", fxc = d.fxc or colors.yellow,
        al = "center", sc = 0,
        act = { side = "top", mode = (kind == "button") and "pulse" or "toggle" },
        src = { side = "top", io = "in" },
    }
    return w
end

local function colorOr(v, def, allowNone)
    if allowNone and v == false then return false end
    if type(v) == "number" and VALID[v] then return v end
    return def
end

function W.clean(t, dash)
    if type(t) ~= "table" or not KINDSET[t.kind] then return nil end
    local w = W.new(t.kind, { nextId = 0 })
    w.id = (type(t.id) == "string" and #t.id <= 12) and t.id or ("w" .. tostring(math.random(1000, 99999)))
    w.w = F.int(t.w, w.w, 3, dash.pw)
    w.h = F.int(t.h, w.h, 3, dash.ph)
    w.x = F.int(t.x, 1, 1, max(1, dash.pw - w.w + 1))
    w.y = F.int(t.y, 1, 1, max(1, dash.ph - w.h + 1))
    w.tx = (type(t.tx) == "string") and t.tx:sub(1, 24) or w.tx
    w.fg = colorOr(t.fg, w.fg, false)
    w.bg = colorOr(t.bg, w.bg, true)
    w.bd = colorOr(t.bd, w.bd, true)
    w.fxc = colorOr(t.fxc, w.fxc, false)
    w.fx = inList(EFFECTS, t.fx) and t.fx or "none"
    w.al = inList(ALIGN, t.al) and t.al or "center"
    w.sc = F.int(t.sc, 0, 0, 6)
    if type(t.act) == "table" then
        if SIDESET[t.act.side] then w.act.side = t.act.side end
        if inList(MODES, t.act.mode) then w.act.mode = t.act.mode end
    end
    if type(t.src) == "table" then
        if SIDESET[t.src.side] then w.src.side = t.src.side end
        if inList(IOS, t.src.io) then w.src.io = t.src.io end
    end
    return w
end

function W.newDash(name, pw, ph)
    return { v = 1, name = name, pw = pw, ph = ph, bg = colors.black, fx = "none", widgets = {}, nextId = 0 }
end

function W.cleanDash(t, name)
    local d = W.newDash(F.safe(name), F.int(t.pw, 72, 16, 400), F.int(t.ph, 54, 12, 300))
    if d.name == "" then d.name = "dash" end
    d.bg = colorOr(t.bg, colors.black, false)
    d.fx = inList(BGFX, t.fx) and t.fx or "none"
    d.nextId = F.int(t.nextId, 0, 0, 100000)
    if type(t.widgets) == "table" then
        for i = 1, min(#t.widgets, 100) do
            local w = W.clean(t.widgets[i], d)
            if w then d.widgets[#d.widgets + 1] = w end
        end
    end
    return d
end

function F.loadDash(name)
    local s = F.read(F.path(name))
    if not s or #s > 300000 then return nil, "Cannot read that file" end
    local t = textutils.unserialize(s)
    if type(t) ~= "table" then return nil, "That file is damaged" end
    return W.cleanDash(t, name)
end
function F.saveDash(d)
    local name = F.safe(d.name)
    if name == "" then return false end
    d.name = name
    F.ensure(DIR .. "/dash")
    return F.write(F.path(name), textutils.serialize(d))
end

function W.at(dash, dx, dy)
    for i = #dash.widgets, 1, -1 do
        local w = dash.widgets[i]
        if dx >= w.x and dx < w.x + w.w and dy >= w.y and dy < w.y + w.h then return w, i end
    end
    return nil
end

-- ── Terminal basics ──────────────────────────────────────────────────────────
local TC = {
    bg = colors.black, text = colors.white, dim = colors.lightGray, hdr = colors.blue,
    sel = colors.lightBlue, selText = colors.black, ok = colors.green, err = colors.red,
    warn = colors.yellow, box = colors.gray,
}
function UI.put(x, y, s, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(s)
end
function UI.fill(x, y, w, bg)
    if w > 0 then UI.put(x, y, string.rep(" ", w), TC.text, bg or TC.bg) end
end
function UI.clear()
    term.setBackgroundColor(TC.bg)
    term.setTextColor(TC.text)
    term.clear()
end
S.under = UI.clear

function UI.flash(text)
    S.note = { text = tostring(text), t = os.clock() }
end

-- A centred box. Returns x, y, w, h.
function UI.frame(title, bw, bh)
    local w, h = term.getSize()
    bw, bh = min(bw, w - 2), min(bh, h - 2)
    local bx, by = floor((w - bw) / 2) + 1, floor((h - bh) / 2) + 1
    for y = 0, bh - 1 do UI.fill(bx, by + y, bw, TC.box) end
    UI.fill(bx, by, bw, TC.hdr)
    UI.put(bx + 1, by, F.cut(title, bw - 2), TC.text, TC.hdr)
    return bx, by, bw, bh
end

-- Pick one item. Returns its number, or nil on Esc.
function UI.pick(title, items, hint, start)
    local sel, top = start or 1, 0
    while true do
        S.under()
        local bx, by, bw, bh = UI.frame(title, 34, #items + 4)
        local rows = bh - 3
        if sel < top + 1 then top = sel - 1 elseif sel > top + rows then top = sel - rows end
        for i = 1, rows do
            local it = items[top + i]
            if it then
                local on = (top + i == sel)
                UI.put(bx + 1, by + i, F.pad(it, bw - 2), on and TC.selText or TC.text, on and TC.sel or TC.box)
            end
        end
        UI.put(bx + 1, by + bh - 1, F.pad(hint or "Enter: pick   Esc: back", bw - 2), TC.dim, TC.box)
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.up then sel = max(1, sel - 1)
            elseif a == keys.down then sel = min(#items, sel + 1)
            elseif a == keys.pageUp then sel = max(1, sel - rows)
            elseif a == keys.pageDown then sel = min(#items, sel + rows)
            elseif a == keys.home then sel = 1
            elseif a == keys["end"] then sel = #items
            elseif a == keys.enter then return sel
            elseif a == keys.escape or a == keys.q then return nil end
        elseif ev == "mouse_click" then
            if b >= bx and b < bx + bw and c > by and c <= by + rows and items[top + c - by] then
                return top + c - by
            elseif b < bx or b >= bx + bw or c < by or c >= by + bh then
                return nil
            end
        elseif ev == "mouse_scroll" then
            sel = F.clamp(sel + a, 1, #items)
        end
    end
end

-- Show a message. Any key or click closes it.
function UI.msg(text, title)
    local lines = {}
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    while true do
        S.under()
        local widest = 0
        for _, l in ipairs(lines) do widest = max(widest, #l) end
        local bx, by, bw, bh = UI.frame(title or "Pixel Dash", widest + 4, #lines + 4)
        for i, l in ipairs(lines) do
            if i <= bh - 3 then UI.put(bx + 1, by + i, F.cut(l, bw - 2), TC.text, TC.box) end
        end
        UI.put(bx + 1, by + bh - 1, F.cut("Press any key", bw - 2), TC.dim, TC.box)
        local ev = os.pullEvent()
        if ev == "key" or ev == "mouse_click" then return end
    end
end

-- Yes / No. Enter or Y is yes.
function UI.ask(text)
    local i = UI.pick(text, { "Yes", "No" }, "Enter: pick   Esc: no")
    return i == 1
end

-- A form. fields: { id, label, t = "text"|"num"|"choice"|"color", v, list, min, max, len, none }.
-- Returns a table of answers, or nil when cancelled.
function UI.form(title, fields)
    local n = #fields
    local val, fresh = {}, {}
    for i, f in ipairs(fields) do
        if f.t == "text" then val[i] = tostring(f.v or "")
        elseif f.t == "num" then val[i] = tostring(f.v or 0)
        elseif f.t == "choice" then
            val[i] = 1
            for j, o in ipairs(f.list) do if o == f.v then val[i] = j end end
        else
            val[i] = (f.v == false and f.none) and 0 or F.colorIndex(f.v)
        end
    end
    local focus, top = 1, 0
    fresh[1] = true
    local function result()
        local r = {}
        for i, f in ipairs(fields) do
            if f.t == "text" then r[f.id] = val[i]
            elseif f.t == "num" then
                r[f.id] = F.int(tonumber(val[i]), tonumber(f.v) or 0, f.min or 0, f.max or 9999)
            elseif f.t == "choice" then r[f.id] = f.list[val[i]]
            else r[f.id] = (val[i] == 0) and false or ORDER[val[i]] end
        end
        return r
    end
    local function step(i, d)
        local f = fields[i]
        if f.t == "choice" then
            val[i] = (val[i] - 1 + d) % #f.list + 1
        elseif f.t == "color" then
            local lo = f.none and 0 or 1
            local v = val[i] + d
            if v > 16 then v = lo elseif v < lo then v = 16 end
            val[i] = v
        elseif f.t == "num" then
            val[i] = tostring(F.int(tonumber(val[i]), 0, f.min or 0, f.max or 9999) + d)
        end
    end
    local function setFocus(i)
        focus = F.clamp(i, 1, n)
        fresh = {}
        fresh[focus] = true
    end
    while true do
        S.under()
        local w, h = term.getSize()
        local rows = min(n, h - 6)
        local bx, by, bw, bh = UI.frame(title, 36, rows + 3)
        if focus <= top then top = focus - 1 elseif focus > top + rows then top = focus - rows end
        local lw = min(10, floor(bw / 3))
        local vx, vw = bx + 2 + lw, bw - 3 - lw
        for r = 1, rows do
            local i = top + r
            local f = fields[i]
            if f then
                local on = (i == focus)
                local y = by + r
                UI.put(bx + 1, y, F.pad(f.label, lw), on and TC.selText or TC.dim, on and TC.sel or TC.box)
                UI.fill(vx, y, vw, TC.box)
                if f.t == "text" or f.t == "num" then
                    local s = val[i]
                    if #s > vw - 1 then s = s:sub(#s - vw + 2) end
                    UI.put(vx, y, s .. (on and "_" or ""), TC.text, TC.box)
                elseif f.t == "choice" then
                    UI.put(vx, y, F.cut("< " .. tostring(f.list[val[i]]) .. " >", vw), TC.text, TC.box)
                else
                    if val[i] == 0 then
                        UI.put(vx, y, "--", TC.dim, TC.box)
                        UI.put(vx + 3, y, F.cut("none", vw - 3), TC.text, TC.box)
                    else
                        UI.put(vx, y, "  ", TC.text, ORDER[val[i]])
                        UI.put(vx + 3, y, F.cut(CNAME[val[i]], vw - 3), TC.text, TC.box)
                    end
                end
            end
        end
        local fy = by + bh - 1
        UI.put(bx + 1, fy, " OK ", colors.black, TC.ok)
        UI.put(bx + 6, fy, " Cancel ", colors.white, TC.err)
        UI.put(bx + 15, fy, F.cut("Tab: next", bw - 16), TC.dim, TC.box)
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.escape then return nil
            elseif a == keys.enter then return result()
            elseif a == keys.down or a == keys.tab then setFocus(focus % n + 1)
            elseif a == keys.up then setFocus((focus - 2) % n + 1)
            elseif a == keys.left then step(focus, -1)
            elseif a == keys.right then step(focus, 1)
            elseif a == keys.backspace then
                local f = fields[focus]
                if f.t == "text" or f.t == "num" then val[focus] = val[focus]:sub(1, -2); fresh[focus] = nil end
            end
        elseif ev == "char" then
            local f = fields[focus]
            if f.t == "text" then
                if #val[focus] < (f.len or 24) and a:byte() >= 32 and a:byte() < 127 then
                    val[focus] = val[focus] .. a
                end
            elseif f.t == "num" then
                if a:match("^[%d%-]$") then
                    if fresh[focus] then val[focus] = "" fresh[focus] = nil end
                    if #val[focus] < 5 then val[focus] = val[focus] .. a end
                end
            end
        elseif ev == "paste" then
            local f = fields[focus]
            if f.t == "text" then
                local s = a:gsub("[^%g ]", "")
                val[focus] = (val[focus] .. s):sub(1, f.len or 24)
            end
        elseif ev == "mouse_click" then
            if c == fy and b >= bx + 1 and b <= bx + 4 then return result()
            elseif c == fy and b >= bx + 6 and b <= bx + 13 then return nil
            elseif b >= bx and b < bx + bw and c > by and c <= by + rows then
                local i = top + c - by
                if fields[i] then
                    if i == focus and (fields[i].t == "choice" or fields[i].t == "color") then step(i, 1)
                    else setFocus(i) end
                end
            elseif b < bx or b >= bx + bw or c < by or c >= by + bh then
                return nil
            end
        end
    end
end

-- ── Editor ───────────────────────────────────────────────────────────────────
UI.TOOLS = {
    { "Menu", "menu" }, { "Add", "add" }, { "Edit", "props" }, { "Del", "del" },
    { "Run", "run" }, { "Save", "save" }, { "Dup", "dup" }, { "Undo", "undo" },
}

function UI.toScreen(dx, dy)
    local v = S.view
    return v.ox + floor((dx - 1) * v.s) + 1, v.oy + floor((dy - 1) * v.s) + 1
end
function UI.toDash(sx, sy)
    local v = S.view
    return floor((sx - v.ox - 1) / v.s) + 1, floor((sy - v.oy - 1) / v.s) + 1
end

function UI.drawEditor()
    local w, h = term.getSize()
    local dash = S.dash
    UI.fill(1, 1, w, TC.hdr)
    S.tb = {}
    local x = 1
    for _, b in ipairs(UI.TOOLS) do
        local label = " " .. b[1] .. " "
        if x + #label - 1 <= w then
            UI.put(x, 1, label, TC.selText, TC.sel)
            S.tb[#S.tb + 1] = { x1 = x, x2 = x + #label - 1, fn = b[2] }
            x = x + #label + 1
        end
    end
    local vw, vh = w * 2, (h - 2) * 3
    local V = D.new(vw, vh, colors.gray)
    local DC = D.new(dash.pw, dash.ph, dash.bg)
    D.dash(DC, dash, { live = false, st = {}, t = os.clock() })
    local s, ox, oy = F.fit(dash.pw, dash.ph, vw - 2, vh - 2)
    ox, oy = ox + 1, oy + 1
    F.blitScaled(DC, V, s, ox, oy, colors.gray)
    D.box(V, ox, oy, ox + floor(dash.pw * s) + 1, oy + floor(dash.ph * s) + 1, colors.lightGray)
    S.view = { s = s, ox = ox, oy = oy }
    local sw = S.sel
    if sw then
        local x1, y1 = UI.toScreen(sw.x, sw.y)
        local x2, y2 = UI.toScreen(sw.x + sw.w, sw.y + sw.h)
        D.box(V, x1 - 1, y1 - 1, x2, y2, colors.white)
        D.rect(V, x2 - 1, y2 - 1, x2 + 1, y2 + 1, colors.yellow)
        S.handle = { x = x2, y = y2 }
    else
        S.handle = nil
    end
    D.cells(V, term, 1, 2)
    UI.fill(1, h, w, TC.bg)
    local line
    if S.note and os.clock() - S.note.t < 3 then
        line = S.note.text
    elseif sw then
        line = sw.kind .. "  " .. sw.x .. "," .. sw.y .. "  " .. sw.w .. "x" .. sw.h
    else
        line = dash.name .. (S.dirty and "*" or "") .. "  " .. dash.pw .. "x" .. dash.ph .. "  F1 help"
    end
    UI.put(1, h, F.cut(line, w), TC.dim, TC.bg)
end

function UI.snap()
    local u = S.undo
    u[#u + 1] = F.copy(S.dash)
    if #u > 30 then table.remove(u, 1) end
end
function UI.undo()
    local u = S.undo
    if #u == 0 then UI.flash("Nothing to undo") return end
    S.dash = table.remove(u)
    S.sel = nil
    S.dirty = true
end

function UI.clampWidgets(d)
    for _, w in ipairs(d.widgets) do
        w.w = F.clamp(w.w, 3, d.pw)
        w.h = F.clamp(w.h, 3, d.ph)
        w.x = F.clamp(w.x, 1, max(1, d.pw - w.w + 1))
        w.y = F.clamp(w.y, 1, max(1, d.ph - w.h + 1))
    end
end

function UI.add()
    local labels = {}
    for i, k in ipairs(KINDS) do labels[i] = k:sub(1, 1):upper() .. k:sub(2) end
    local i = UI.pick("Add widget", labels)
    if not i then return end
    local d = S.dash
    if #d.widgets >= 100 then UI.flash("Too many widgets") return end
    UI.snap()
    local w = W.new(KINDS[i], d)
    w.w, w.h = min(w.w, d.pw), min(w.h, d.ph)
    w.x = max(1, floor((d.pw - w.w) / 2) + 1)
    w.y = max(1, floor((d.ph - w.h) / 2) + 1)
    d.widgets[#d.widgets + 1] = w
    S.sel = w
    S.dirty = true
end

function UI.del()
    local w, d = S.sel, S.dash
    if not w then UI.flash("Tap a widget first") return end
    UI.snap()
    for i, x in ipairs(d.widgets) do
        if x == w then table.remove(d.widgets, i) break end
    end
    S.sel = nil
    S.dirty = true
end

function UI.dup()
    local w, d = S.sel, S.dash
    if not w then UI.flash("Tap a widget first") return end
    if #d.widgets >= 100 then UI.flash("Too many widgets") return end
    UI.snap()
    local c = F.copy(w)
    d.nextId = (d.nextId or 0) + 1
    c.id = "w" .. d.nextId
    c.x = F.clamp(w.x + 3, 1, max(1, d.pw - w.w + 1))
    c.y = F.clamp(w.y + 3, 1, max(1, d.ph - w.h + 1))
    d.widgets[#d.widgets + 1] = c
    S.sel = c
    S.dirty = true
end

function UI.reorder(dir)
    local w, d = S.sel, S.dash
    if not w then UI.flash("Tap a widget first") return end
    for i, x in ipairs(d.widgets) do
        if x == w then
            local j = i + dir
            if j >= 1 and j <= #d.widgets then
                UI.snap()
                d.widgets[i], d.widgets[j] = d.widgets[j], d.widgets[i]
                S.dirty = true
            end
            return
        end
    end
end
function UI.forward() UI.reorder(1) end
function UI.back() UI.reorder(-1) end

function UI.props()
    local w, d = S.sel, S.dash
    if not w then UI.flash("Tap a widget first") return end
    local k = w.kind
    local f = {
        { id = "x", label = "X", t = "num", v = w.x, min = 1, max = d.pw },
        { id = "y", label = "Y", t = "num", v = w.y, min = 1, max = d.ph },
        { id = "w", label = "Width", t = "num", v = w.w, min = 3, max = d.pw },
        { id = "h", label = "Height", t = "num", v = w.h, min = 3, max = d.ph },
    }
    local texty = (k == "text" or k == "button" or k == "toggle" or k == "clock")
    if texty then
        f[#f + 1] = { id = "tx", label = (k == "clock") and "Format" or "Text", t = "text", v = w.tx, len = 20 }
        f[#f + 1] = { id = "al", label = "Align", t = "choice", list = ALIGN, v = w.al }
        f[#f + 1] = { id = "sc", label = "Text size", t = "num", v = w.sc, min = 0, max = 6 }
    end
    f[#f + 1] = { id = "fg", label = "Color", t = "color", v = w.fg }
    f[#f + 1] = { id = "bg", label = "Back", t = "color", v = w.bg, none = true }
    f[#f + 1] = { id = "bd", label = "Border", t = "color", v = w.bd, none = true }
    f[#f + 1] = { id = "fx", label = "Effect", t = "choice", list = EFFECTS, v = w.fx }
    f[#f + 1] = { id = "fxc", label = (k == "toggle" or k == "lamp") and "On color" or "Effect clr", t = "color", v = w.fxc }
    if k == "button" or k == "toggle" then
        f[#f + 1] = { id = "aside", label = "Output", t = "choice", list = SIDES, v = w.act.side }
    end
    if k == "button" then
        f[#f + 1] = { id = "amode", label = "Action", t = "choice", list = MODES, v = w.act.mode }
    end
    if k == "lamp" or k == "bar" then
        f[#f + 1] = { id = "sside", label = "Signal", t = "choice", list = SIDES, v = w.src.side }
        f[#f + 1] = { id = "sio", label = "Read", t = "choice", list = IOS, v = w.src.io }
    end
    local r = UI.form("Edit " .. k, f)
    if not r then return end
    UI.snap()
    w.w, w.h = r.w, r.h
    w.x = F.clamp(r.x, 1, max(1, d.pw - w.w + 1))
    w.y = F.clamp(r.y, 1, max(1, d.ph - w.h + 1))
    if r.tx then w.tx = r.tx end
    if r.al then w.al = r.al end
    if r.sc then w.sc = r.sc end
    w.fg, w.bg, w.bd, w.fx, w.fxc = r.fg, r.bg, r.bd, r.fx, r.fxc
    if r.aside then w.act.side = r.aside end
    if r.amode then w.act.mode = r.amode end
    if r.sside then w.src.side = r.sside end
    if r.sio then w.src.io = r.sio end
    S.dirty = true
end

function UI.save()
    if F.saveDash(S.dash) then
        S.dirty = false
        UI.flash("Saved " .. S.dash.name)
    else
        UI.flash("Could not save")
    end
end

function UI.saveAs()
    local r = UI.form("Save as", { { id = "name", label = "Name", t = "text", v = S.dash.name, len = 20 } })
    if not r then return end
    local name = F.safe(r.name)
    if name == "" then UI.flash("Name is empty") return end
    if name ~= S.dash.name and fs.exists(F.path(name)) and not UI.ask("Replace " .. name .. "?") then return end
    S.dash.name = name
    UI.save()
end

function UI.dashSettings()
    local d = S.dash
    local r = UI.form("Dashboard", {
        { id = "pw", label = "Width px", t = "num", v = d.pw, min = 16, max = 400 },
        { id = "ph", label = "Height px", t = "num", v = d.ph, min = 12, max = 300 },
        { id = "bg", label = "Background", t = "color", v = d.bg },
        { id = "fx", label = "Backdrop", t = "choice", list = BGFX, v = d.fx },
    })
    if not r then return end
    UI.snap()
    d.pw, d.ph, d.bg, d.fx = r.pw, r.ph, r.bg, r.fx
    UI.clampWidgets(d)
    S.dirty = true
end

function UI.fitMon()
    local m = F.openMon()
    if not m then
        UI.msg("No monitor found.\nPlace one next to this\ncomputer, then try again.")
        return
    end
    local cw, ch = m.getSize()
    UI.snap()
    S.dash.pw = F.clamp(cw * 2, 16, 400)
    S.dash.ph = F.clamp(ch * 3, 12, 300)
    UI.clampWidgets(S.dash)
    S.dirty = true
    pcall(m.clear)
    UI.flash("Size is " .. S.dash.pw .. "x" .. S.dash.ph)
end

function UI.monSettings()
    local list = F.monitors()
    local items = { "Automatic (first one)" }
    for _, n in ipairs(list) do items[#items + 1] = n end
    local i = UI.pick("Monitor", items)
    if not i then return end
    CFG.mon = (i > 1) and list[i - 1] or nil
    local scales = { "0.5", "1", "1.5", "2", "3", "4", "5" }
    local j = UI.pick("Text scale (small = sharp)", scales)
    if j then CFG.scale = tonumber(scales[j]) end
    F.saveCfg()
    UI.flash("Monitor saved")
end

function UI.help()
    UI.msg(table.concat({
        "EDITOR",
        "Tap a widget, drag to move.",
        "Drag the yellow corner to",
        "resize. Arrows nudge.",
        "A add   E edit   D copy",
        "Del remove   Z undo",
        "S save   R run   Q close",
        "[ ] send back / forward",
        "Tab: next widget",
        "",
        "RUN",
        "Touch buttons and toggles",
        "on the monitor. The first",
        "redstone use asks first.",
    }, "\n"), "Help")
end

function UI.deleteDash()
    if not UI.ask("Delete " .. S.dash.name .. "?") then return end
    pcall(fs.delete, F.path(S.dash.name))
    S.dirty = false
    return "close"
end

function UI.close()
    if S.dirty then
        local i = UI.pick("Unsaved changes", { "Save and close", "Close without saving", "Keep editing" })
        if i == 1 then UI.save() return "close"
        elseif i == 2 then return "close" end
        return nil
    end
    return "close"
end

function UI.menu()
    local items = {
        "Run on monitor", "Save", "Save as...", "Dashboard settings", "Fit size to monitor",
        "Monitor settings", "Duplicate widget", "Bring forward", "Send back", "Undo",
        "Delete dashboard", "Help", "Close to home",
    }
    local fns = {
        UI.run, UI.save, UI.saveAs, UI.dashSettings, UI.fitMon, UI.monSettings, UI.dup,
        UI.forward, UI.back, UI.undo, UI.deleteDash, UI.help, UI.close,
    }
    local i = UI.pick("Menu", items)
    if i then return fns[i]() end
end

function UI.run()
    local under = S.under
    R.run(S.dash)
    S.under = under
end

function UI.nudge(dx, dy)
    local w, d = S.sel, S.dash
    if not w then return end
    local nx = F.clamp(w.x + dx, 1, max(1, d.pw - w.w + 1))
    local ny = F.clamp(w.y + dy, 1, max(1, d.ph - w.h + 1))
    if nx == w.x and ny == w.y then return end
    if os.clock() - (S.nudgeAt or 0) > 1 then UI.snap() end
    S.nudgeAt = os.clock()
    w.x, w.y = nx, ny
    S.dirty = true
end

function UI.nextWidget()
    local d = S.dash
    if #d.widgets == 0 then return end
    local cur = 0
    for i, x in ipairs(d.widgets) do if x == S.sel then cur = i end end
    S.sel = d.widgets[cur % #d.widgets + 1]
end

function UI.editorKey(k)
    if k == keys.up then UI.nudge(0, -1)
    elseif k == keys.down then UI.nudge(0, 1)
    elseif k == keys.left then UI.nudge(-1, 0)
    elseif k == keys.right then UI.nudge(1, 0)
    elseif k == keys.delete or k == keys.backspace then UI.del()
    elseif k == keys.tab then UI.nextWidget()
    elseif k == keys.a then UI.add()
    elseif k == keys.e or k == keys.enter then UI.props()
    elseif k == keys.d then UI.dup()
    elseif k == keys.z then UI.undo()
    elseif k == keys.s then UI.save()
    elseif k == keys.r then UI.run()
    elseif k == keys.m then return UI.menu()
    elseif k == keys.leftBracket then UI.back()
    elseif k == keys.rightBracket then UI.forward()
    elseif k == keys.f1 then UI.help()
    elseif k == keys.q then return UI.close()
    end
end

function UI.click(button, x, y)
    local w, h = term.getSize()
    if y == 1 then
        for _, b in ipairs(S.tb or {}) do
            if x >= b.x1 and x <= b.x2 then return UI[b.fn]() end
        end
        return
    end
    if y < 2 or y > h - 1 or not S.view then return end
    local sx, sy = (x - 1) * 2 + 1, (y - 2) * 3 + 2
    local dash = S.dash
    local hd = S.handle
    if S.sel and hd and abs(sx - hd.x) <= 3 and abs(sy - hd.y) <= 4 then
        S.drag = { mode = "size" }
        return
    end
    local dx, dy = UI.toDash(sx, sy)
    local hit = W.at(dash, dx, dy)
    S.sel = hit
    if hit then S.drag = { mode = "move", ox = dx - hit.x, oy = dy - hit.y } else S.drag = nil end
end

function UI.drag(x, y)
    local d, w, dash = S.drag, S.sel, S.dash
    if not d or not w or not S.view then return end
    local sx, sy = (x - 1) * 2 + 1, (y - 2) * 3 + 2
    local dx, dy = UI.toDash(sx, sy)
    local nx, ny, nw, nh = w.x, w.y, w.w, w.h
    if d.mode == "move" then
        nx = F.clamp(dx - d.ox, 1, max(1, dash.pw - w.w + 1))
        ny = F.clamp(dy - d.oy, 1, max(1, dash.ph - w.h + 1))
    else
        nw = F.clamp(dx - w.x + 1, 3, max(3, dash.pw - w.x + 1))
        nh = F.clamp(dy - w.y + 1, 3, max(3, dash.ph - w.y + 1))
    end
    if nx ~= w.x or ny ~= w.y or nw ~= w.w or nh ~= w.h then
        if not d.snapped then UI.snap() d.snapped = true end
        w.x, w.y, w.w, w.h = nx, ny, nw, nh
        S.dirty = true
    end
end

function UI.editor(dash, isNew)
    S.dash, S.sel, S.undo, S.drag = dash, nil, {}, nil
    S.dirty = isNew and true or false
    S.under = UI.drawEditor
    local tmr, tmrAt = os.startTimer(0.5), os.clock()
    while true do
        UI.drawEditor()
        local ev, a, b, c = os.pullEvent()
        local r
        if ev == "timer" then
            if a == tmr then tmr, tmrAt = os.startTimer(0.5), os.clock() end
        elseif ev == "key" then r = UI.editorKey(a)
        elseif ev == "mouse_click" then r = UI.click(a, b, c)
        elseif ev == "mouse_drag" then UI.drag(b, c)
        elseif ev == "mouse_up" then S.drag = nil
        end
        if r == "close" then break end
        if os.clock() - tmrAt > 1 then tmr, tmrAt = os.startTimer(0.5), os.clock() end
    end
    S.under = UI.clear
end

-- ── Running a dashboard ──────────────────────────────────────────────────────
function R.run(dash)
    local mon, mname = F.openMon()
    if mon and api.touch and api.touch.enable then pcall(api.touch.enable) end
    if api.background and api.background.request then pcall(api.background.request) end
    local st, pending = {}, {}
    local ctx = { live = true, st = st, t = 0 }
    local DC = D.new(dash.pw, dash.ph, dash.bg)
    local MC = nil
    local view = { s = 1, ox = 0, oy = 0 }
    local animated = dash.fx ~= "none"
    local hasClock = false
    for _, w in ipairs(dash.widgets) do
        if w.fx ~= "none" then animated = true end
        if w.kind == "clock" then hasClock = true end
    end

    local function header()
        local tw, th = term.getSize()
        UI.clear()
        UI.fill(1, 1, tw, TC.hdr)
        UI.put(2, 1, F.cut("Running " .. dash.name .. (mon and (" on " .. mname) or " (preview)"), tw - 9), TC.text, TC.hdr)
        UI.put(max(1, tw - 5), 1, " Stop ", colors.white, TC.err)
        UI.put(1, th, F.cut(mon and "Touch the monitor. Q stops." or "No monitor: preview. Q stops.", tw), TC.dim, TC.bg)
    end

    local function present()
        ctx.t = os.clock()
        D.dash(DC, dash, ctx)
        if mon then
            local cw, ch = mon.getSize()
            if not MC or MC.pw ~= cw * 2 or MC.ph ~= ch * 3 then MC = D.new(cw * 2, ch * 3, colors.black) end
            local s, ox, oy = F.fit(dash.pw, dash.ph, MC.pw, MC.ph)
            view.s, view.ox, view.oy = s, ox, oy
            F.blitScaled(DC, MC, s, ox, oy, colors.black)
            D.cells(MC, mon, 1, 1)
        else
            local tw, th = term.getSize()
            local V = D.new(tw * 2, (th - 2) * 3, colors.black)
            local s, ox, oy = F.fit(dash.pw, dash.ph, V.pw, V.ph)
            view.s, view.ox, view.oy = s, ox, oy
            F.blitScaled(DC, V, s, ox, oy, colors.black)
            D.cells(V, term, 1, 2)
        end
    end

    local function signature()
        local parts = {}
        local now = os.clock()
        for _, w in ipairs(dash.widgets) do
            if w.kind == "lamp" or w.kind == "bar" then parts[#parts + 1] = R.analog(w, ctx)
            elseif w.kind == "toggle" then parts[#parts + 1] = R.getOut(w.act.side) and 1 or 0 end
            if st[w.id] and st[w.id] > now then parts[#parts + 1] = "p" end
        end
        if animated then parts[#parts + 1] = floor(now * 4) end
        if hasClock then parts[#parts + 1] = os.date("%S") end
        return table.concat(parts, ",")
    end

    local function act(w)
        local a = w.act
        pcall(function()
            if a.mode == "toggle" then redstone.setOutput(a.side, not redstone.getOutput(a.side))
            elseif a.mode == "on" then redstone.setOutput(a.side, true)
            elseif a.mode == "off" then redstone.setOutput(a.side, false)
            elseif a.mode == "pulse" then
                redstone.setOutput(a.side, true)
                pending[#pending + 1] = { at = os.clock() + 0.5, side = a.side }
            end
        end)
        st[w.id] = os.clock() + 0.25
    end

    local function touch(sx, sy)
        local dx = floor((sx - view.ox - 1) / view.s) + 1
        local dy = floor((sy - view.oy - 1) / view.s) + 1
        local w = W.at(dash, dx, dy)
        if w and (w.kind == "button" or w.kind == "toggle") then act(w) end
    end

    local function body()
        header()
        present()
        local last = signature()
        local tmr = os.startTimer(0.2)
        while true do
            local ev, a, b, c = os.pullEvent()
            if ev == "timer" and a == tmr then
                local now = os.clock()
                for i = #pending, 1, -1 do
                    if now >= pending[i].at then
                        pcall(redstone.setOutput, pending[i].side, false)
                        table.remove(pending, i)
                    end
                end
                local sg = signature()
                if sg ~= last then
                    last = sg
                    present()
                end
                tmr = os.startTimer(0.2)
            elseif ev == "monitor_touch" then
                if mon and a == mname then
                    touch((b - 1) * 2 + 1, (c - 1) * 3 + 2)
                    present()
                    last = signature()
                end
            elseif ev == "mouse_click" then
                local tw, th = term.getSize()
                if c == 1 and b >= tw - 5 then return end
                if not mon and c >= 2 and c <= th - 1 then
                    touch((b - 1) * 2 + 1, (c - 2) * 3 + 2)
                    present()
                    last = signature()
                end
            elseif ev == "key" then
                if a == keys.q or a == keys.escape then return end
            elseif ev == "term_resize" then
                header()
                present()
            elseif ev == "monitor_resize" or ev == "peripheral" or ev == "peripheral_detach" then
                mon, mname = F.openMon()
                MC = nil
                header()
                present()
            end
        end
    end

    local ok, err = pcall(body)
    for _, p in ipairs(pending) do pcall(redstone.setOutput, p.side, false) end
    if mon then
        pcall(mon.setBackgroundColor, colors.black)
        pcall(mon.clear)
    end
    if not ok then error(err, 0) end
end

-- ── Home ─────────────────────────────────────────────────────────────────────
function UI.homeBg()
    UI.clear()
    local w = term.getSize()
    UI.fill(1, 1, w, TC.hdr)
    UI.put(2, 1, "Pixel Dash", TC.text, TC.hdr)
end

function UI.newDash()
    local r = UI.form("New dashboard", {
        { id = "name", label = "Name", t = "text", v = "", len = 20 },
        { id = "size", label = "Size", t = "choice", v = "Match monitor",
          list = { "Match monitor", "Small 48x36", "Medium 96x72", "Large 144x108" } },
    })
    if not r then return end
    local name = F.safe(r.name)
    if name == "" then UI.msg("Please give it a name.") return end
    if fs.exists(F.path(name)) then UI.msg("That name is taken.") return end
    local pw, ph = 96, 72
    if r.size == "Match monitor" then
        local m = F.openMon()
        if m then
            local cw, ch = m.getSize()
            pw, ph = F.clamp(cw * 2, 16, 400), F.clamp(ch * 3, 12, 300)
            pcall(m.clear)
        end
    elseif r.size:find("Small") then pw, ph = 48, 36
    elseif r.size:find("Large") then pw, ph = 144, 108 end
    local d = W.newDash(name, pw, ph)
    local t = W.new("text", d)
    t.tx, t.fg = "PIXEL DASH", colors.cyan
    t.w = min(pw - 4, 80)
    t.h = min(11, ph - 2)
    t.x = floor((pw - t.w) / 2) + 1
    t.y = 3
    d.widgets[1] = t
    UI.editor(d, true)
end

local function main()
    if not term.isColour() then
        print("Pixel Dash needs an advanced computer (colour).")
        return
    end
    F.ensure(DIR)
    F.ensure(DIR .. "/dash")
    F.loadCfg()
    S.under = UI.homeBg
    while true do
        S.under = UI.homeBg
        local names = F.listDash()
        local items = {}
        for _, n in ipairs(names) do items[#items + 1] = n end
        local count = #items
        items[#items + 1] = "+ New dashboard"
        items[#items + 1] = "Monitor settings"
        items[#items + 1] = "Delete a dashboard"
        items[#items + 1] = "Help"
        items[#items + 1] = "Quit"
        local i = UI.pick("Your dashboards", items, "Enter: open   Esc: quit")
        if not i or i == count + 5 then
            break
        elseif i <= count then
            local d, err = F.loadDash(names[i])
            if d then UI.editor(d, false) else UI.msg(err) end
        elseif i == count + 1 then
            UI.newDash()
        elseif i == count + 2 then
            UI.monSettings()
        elseif i == count + 3 then
            if count == 0 then
                UI.msg("Nothing to delete.")
            else
                local j = UI.pick("Delete which one?", names)
                if j and UI.ask("Delete " .. names[j] .. "?") then pcall(fs.delete, F.path(names[j])) end
            end
        elseif i == count + 4 then
            UI.help()
        end
    end
end

local ok, err = pcall(main)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and not tostring(err):find("Terminated") then
    print("Pixel Dash stopped: " .. tostring(err))
    print("Press any key.")
    os.pullEvent("key")
end
