--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Pixel Dash 2
--@prismarine-api
-- prismarine: background touch
-- Design dashboards for a monitor, then run them. Buttons and toggles switch
-- redstone outputs when someone touches the monitor; lamps and bars show
-- redstone signals. Everything is drawn with sub-pixels (2x3 per cell).
-- Art pieces (ASCII and block art) are placeable and fully editable.
--   Right-click anything for its menu. Mouse wheel zooms. Drag with the
--   right or middle button to pan. Press F1 in the editor for help.

local api = rawget(_G, "prismarine") or {}
local floor, min, max, abs, sin = math.floor, math.min, math.max, math.abs, math.sin

local F = {}    -- general helpers, files, monitor
local D = {}    -- drawing
local W = {}    -- widgets and dashboards
local A = {}    -- art
local U = {}    -- utf-8
local UI = {}   -- terminal screens
local R = {}    -- running a dashboard
local S = { undo = {}, redo = {}, sel = {}, rev = 0, mod = { shift = false, ctrl = false } }
local CFG = { mon = nil, scale = 1, grid = 8, showGrid = false, snap = true }
local DIR = api.home or "/appdata/pixeldash"
local TC = {}   -- terminal colors, from the OS theme

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

local KINDS = { "panel", "text", "button", "toggle", "lamp", "bar", "clock", "line", "art" }
local KINDSET = {}
for _, k in ipairs(KINDS) do KINDSET[k] = true end
local SIDES = { "top", "bottom", "left", "right", "front", "back" }
local SIDESET = {}
for _, s in ipairs(SIDES) do SIDESET[s] = true end
local MODES = { "toggle", "pulse", "on", "off" }
local EFFECTS = { "none", "pulse", "blink", "rainbow" }
local BGFX = { "none", "stars", "grid", "dots", "lines", "gradient" }
local ALIGN = { "left", "center", "right" }
local IOS = { "in", "out" }
local ARTMODES = { "fit", "stretch", "1x", "2x", "3x" }
local FONTS = { "small", "big" }
local GRADS = { "none", "vertical" }
local CLOCKS = { "real", "game" }
local LSTYLES = { "solid", "dotted", "dashed" }
local DIRS = { "right", "up" }
local ZOOMS = { 0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16 }
local MAXW = 120

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- ── UTF-8 ────────────────────────────────────────────────────────────────────
function U.len(b)
    if b >= 240 then return 4 elseif b >= 224 then return 3 elseif b >= 192 then return 2 end
    return 1
end
function U.split(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local l = U.len(s:byte(i))
        out[#out + 1] = s:sub(i, i + l - 1)
        i = i + l
    end
    return out
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


-- ── Art ──────────────────────────────────────────────────────────────────────
-- An art piece is a grid of cells. Each cell has a character, a color for the
-- character (fg) and a color behind it (bg). false means see through.
-- Every cell is drawn as 2x2 sub-pixels, so block characters keep their shape.
local HEX = "0123456789abcdef"
local BLIT = {}
for i = 0, 15 do BLIT[HEX:sub(i + 1, i + 1)] = 2 ^ i end

-- Which of the four quarters (top-left, top-right, bottom-left, bottom-right)
-- a character fills with its own color.
local P = {
    [" "] = { 0, 0, 0, 0 }, ["█"] = { 1, 1, 1, 1 }, ["▀"] = { 1, 1, 0, 0 }, ["▄"] = { 0, 0, 1, 1 },
    ["▌"] = { 1, 0, 1, 0 }, ["▐"] = { 0, 1, 0, 1 }, ["░"] = { 1, 0, 0, 0 }, ["▒"] = { 1, 0, 0, 1 },
    ["▓"] = { 0, 1, 1, 1 }, ["■"] = { 1, 1, 1, 1 }, ["▘"] = { 1, 0, 0, 0 }, ["▝"] = { 0, 1, 0, 0 },
    ["▖"] = { 0, 0, 1, 0 }, ["▗"] = { 0, 0, 0, 1 }, ["▚"] = { 1, 0, 0, 1 }, ["▞"] = { 0, 1, 1, 0 },
    ["▙"] = { 1, 0, 1, 1 }, ["▛"] = { 1, 1, 1, 0 }, ["▜"] = { 1, 1, 0, 1 }, ["▟"] = { 0, 1, 1, 1 },
}
-- Plain characters get a rough shape from how much ink they use.
local LOW = ".,"
local TOPS = "'`\"^~"
local SIDEI = "|!lIi1[](){}/\\jt"
local HEAVY = "#@%&$WMB8NH"
local BOTS = "_=-"
function A.pattern(ch)
    local p = P[ch]
    if p then return p end
    if #ch == 1 then
        if ch:find(" ", 1, true) then p = P[" "]
        elseif LOW:find(ch, 1, true) then p = { 0, 0, 1, 0 }
        elseif TOPS:find(ch, 1, true) then p = { 1, 1, 0, 0 }
        elseif BOTS:find(ch, 1, true) then p = { 0, 0, 1, 1 }
        elseif SIDEI:find(ch, 1, true) then p = { 1, 0, 1, 0 }
        elseif HEAVY:find(ch, 1, true) then p = { 1, 1, 1, 0 }
        elseif ch == ":" or ch == ";" then p = { 0, 1, 0, 1 }
        else p = { 1, 0, 0, 1 } end
    else
        p = { 1, 0, 0, 1 }
    end
    P[ch] = p
    return p
end

function A.new(cols, rows)
    local a = { cols = cols, rows = rows, ch = {}, fg = {}, bg = {}, rev = 1 }
    for y = 1, rows do
        local c, f, b = {}, {}, {}
        for x = 1, cols do c[x] = " "; f[x] = false; b[x] = false end
        a.ch[y], a.fg[y], a.bg[y] = c, f, b
    end
    return a
end
function A.copy(a)
    local o = { cols = a.cols, rows = a.rows, ch = {}, fg = {}, bg = {}, rev = 1 }
    for y = 1, a.rows do
        local c, f, b = {}, {}, {}
        for x = 1, a.cols do c[x] = a.ch[y][x]; f[x] = a.fg[y][x]; b[x] = a.bg[y][x] end
        o.ch[y], o.fg[y], o.bg[y] = c, f, b
    end
    return o
end
-- Add or drop columns and rows. Cells that are new are empty.
function A.resize(a, cols, rows)
    local o = A.new(cols, rows)
    for y = 1, min(rows, a.rows) do
        for x = 1, min(cols, a.cols) do
            o.ch[y][x], o.fg[y][x], o.bg[y][x] = a.ch[y][x], a.fg[y][x], a.bg[y][x]
        end
    end
    return o
end

-- Saved form: one string per row for characters, and one per row for each
-- color (one hex digit per cell, "-" for see through).
function A.encode(a)
    local o = { cols = a.cols, rows = a.rows, ch = {}, fg = {}, bg = {} }
    for y = 1, a.rows do
        local cs, fs, bs = {}, {}, {}
        for x = 1, a.cols do
            cs[x] = a.ch[y][x] or " "
            local f, b = a.fg[y][x], a.bg[y][x]
            fs[x] = f and colors.toBlit(f) or "-"
            bs[x] = b and colors.toBlit(b) or "-"
        end
        o.ch[y], o.fg[y], o.bg[y] = table.concat(cs), table.concat(fs), table.concat(bs)
    end
    return o
end
function A.decode(t)
    if type(t) ~= "table" or type(t.ch) ~= "table" then return nil end
    local cols, rows = F.int(t.cols, 0, 0, 400), F.int(t.rows, 0, 0, 200)
    if cols < 1 or rows < 1 then return nil end
    local a = A.new(cols, rows)
    local tf, tb = type(t.fg) == "table" and t.fg or {}, type(t.bg) == "table" and t.bg or {}
    for y = 1, rows do
        local cs = U.split(tostring(t.ch[y] or ""))
        local fs, bs = tostring(tf[y] or ""), tostring(tb[y] or "")
        for x = 1, cols do
            a.ch[y][x] = cs[x] or " "
            a.fg[y][x] = BLIT[fs:sub(x, x)] or false
            a.bg[y][x] = BLIT[bs:sub(x, x)] or false
        end
    end
    return a
end

-- Text to art. Understands ANSI color codes (ESC[0;36m) and plain text.
local ANSI = {
    [30] = colors.black, [31] = colors.red, [32] = colors.green, [33] = colors.orange,
    [34] = colors.blue, [35] = colors.purple, [36] = colors.cyan, [37] = colors.lightGray,
    [90] = colors.gray, [91] = colors.pink, [92] = colors.lime, [93] = colors.yellow,
    [94] = colors.lightBlue, [95] = colors.magenta, [96] = colors.lightBlue, [97] = colors.white,
}
function A.parse(text, defFg)
    text = tostring(text):gsub("\r", ""):gsub("\t", "    ")
    defFg = defFg or colors.white
    local ansi = text:find("\27%[") or text:find("^%[%d+;%d+m") or text:find("\n%[%d+;%d+m")
    local fg, bg = defFg, false
    local lines, cur = {}, {}
    local i, n = 1, #text
    while i <= n do
        local b = text:byte(i)
        local s, e, codes
        if ansi and (b == 27 or b == 91) then s, e, codes = text:find("^\27?%[([%d;]*)m", i) end
        if s then
            for num in (codes .. ";"):gmatch("(%d*);") do
                local v = tonumber(num) or 0
                if v == 0 or v == 39 then fg = defFg end
                if v == 0 or v == 49 then bg = false end
                if ANSI[v] and v < 50 then fg = ANSI[v] end
                if ANSI[v] and v >= 90 and v < 100 then fg = ANSI[v] end
                if v >= 40 and v <= 47 then bg = ANSI[v - 10] end
                if v >= 100 and v <= 107 then bg = ANSI[v - 10] end
            end
            i = e + 1
        elseif b == 27 then
            i = i + 1
        elseif b == 10 then
            lines[#lines + 1] = cur
            cur = {}
            i = i + 1
        else
            local l = U.len(b)
            cur[#cur + 1] = { ch = text:sub(i, i + l - 1), fg = fg, bg = bg }
            i = i + l
        end
    end
    lines[#lines + 1] = cur
    while #lines > 1 and #lines[#lines] == 0 do lines[#lines] = nil end
    local cols = 1
    for _, l in ipairs(lines) do cols = max(cols, #l) end
    cols = min(cols, 400)
    local rows = min(#lines, 200)
    local a = A.new(cols, rows)
    for y = 1, rows do
        for x = 1, min(cols, #lines[y]) do
            local c = lines[y][x]
            a.ch[y][x], a.fg[y][x], a.bg[y][x] = c.ch, c.fg, c.bg
        end
    end
    return a
end

-- Sub-pixel picture of an art piece, cached until the art changes.
local PXC = setmetatable({}, { __mode = "k" })
function A.px(a)
    local e = PXC[a]
    if e and e.rev == a.rev and e.px.pw == a.cols * 2 and e.px.ph == a.rows * 2 then return e.px end
    local sw, sh = a.cols * 2, a.rows * 2
    local px = { pw = sw, ph = sh }
    for y = 1, sh do
        local r = {}
        for x = 1, sw do r[x] = false end
        px[y] = r
    end
    for cy = 1, a.rows do
        local chr, fgr, bgr = a.ch[cy], a.fg[cy], a.bg[cy]
        local ra, rb = px[(cy - 1) * 2 + 1], px[(cy - 1) * 2 + 2]
        for cx = 1, a.cols do
            local p = A.pattern(chr[cx] or " ")
            local f, b = fgr[cx], bgr[cx]
            local x0 = (cx - 1) * 2
            ra[x0 + 1] = (p[1] == 1 and f or b) or false
            ra[x0 + 2] = (p[2] == 1 and f or b) or false
            rb[x0 + 1] = (p[3] == 1 and f or b) or false
            rb[x0 + 2] = (p[4] == 1 and f or b) or false
        end
    end
    PXC[a] = { rev = a.rev, px = px }
    return px
end
function A.touch(a) a.rev = (a.rev or 0) + 1 end

-- Colors an art piece uses, most used first.
function A.palette(a)
    local count, list = {}, {}
    for y = 1, a.rows do
        for x = 1, a.cols do
            for _, c in ipairs({ a.fg[y][x], a.bg[y][x] }) do
                if c then
                    if not count[c] then count[c] = 0; list[#list + 1] = c end
                    count[c] = count[c] + 1
                end
            end
        end
    end
    table.sort(list, function(x, y) return count[x] > count[y] end)
    return list
end

-- Swap every use of one color for another.
function A.replace(a, from, to)
    for y = 1, a.rows do
        for x = 1, a.cols do
            if a.fg[y][x] == from then a.fg[y][x] = to end
            if a.bg[y][x] == from then a.bg[y][x] = to end
        end
    end
    A.touch(a)
end
function A.flip(a, horizontal)
    local o = A.copy(a)
    local mirror = { ["▌"] = "▐", ["▐"] = "▌", ["▘"] = "▝", ["▝"] = "▘", ["▖"] = "▗", ["▗"] = "▖",
        ["▙"] = "▟", ["▟"] = "▙", ["▛"] = "▜", ["▜"] = "▛" }
    local vert = { ["▀"] = "▄", ["▄"] = "▀", ["▘"] = "▖", ["▖"] = "▘", ["▝"] = "▗", ["▗"] = "▝",
        ["▙"] = "▛", ["▛"] = "▙", ["▟"] = "▜", ["▜"] = "▟" }
    for y = 1, a.rows do
        for x = 1, a.cols do
            local sx, sy = x, y
            if horizontal then sx = a.cols - x + 1 else sy = a.rows - y + 1 end
            local ch = a.ch[sy][sx]
            ch = (horizontal and mirror[ch] or (not horizontal and vert[ch])) or ch
            o.ch[y][x], o.fg[y][x], o.bg[y][x] = ch, a.fg[sy][sx], a.bg[sy][sx]
        end
    end
    A.touch(o)
    return o
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



-- ── Fonts ────────────────────────────────────────────────────────────────────
-- "small" is the 3x5 font above. "big" is 5x7.
local GLYB = {}
do
    local src = {
        A = ".###./#...#/#...#/#####/#...#/#...#/#...#", B = "####./#...#/#...#/####./#...#/#...#/####.",
        C = ".####/#..../#..../#..../#..../#..../.####", D = "####./#...#/#...#/#...#/#...#/#...#/####.",
        E = "#####/#..../#..../####./#..../#..../#####", F = "#####/#..../#..../####./#..../#..../#....",
        G = ".####/#..../#..../#.###/#...#/#...#/.###.", H = "#...#/#...#/#...#/#####/#...#/#...#/#...#",
        I = "#####/..#../..#../..#../..#../..#../#####", J = "..###/....#/....#/....#/....#/#...#/.###.",
        K = "#...#/#..#./#.#../##.../#.#../#..#./#...#", L = "#..../#..../#..../#..../#..../#..../#####",
        M = "#...#/##.##/#.#.#/#...#/#...#/#...#/#...#", N = "#...#/##..#/#.#.#/#..##/#...#/#...#/#...#",
        O = ".###./#...#/#...#/#...#/#...#/#...#/.###.", P = "####./#...#/#...#/####./#..../#..../#....",
        Q = ".###./#...#/#...#/#...#/#.#.#/#..#./.##.#", R = "####./#...#/#...#/####./#.#../#..#./#...#",
        S = ".####/#..../#..../.###./....#/....#/####.", T = "#####/..#../..#../..#../..#../..#../..#..",
        U = "#...#/#...#/#...#/#...#/#...#/#...#/.###.", V = "#...#/#...#/#...#/#...#/#...#/.#.#./..#..",
        W = "#...#/#...#/#...#/#...#/#.#.#/##.##/#...#", X = "#...#/#...#/.#.#./..#../.#.#./#...#/#...#",
        Y = "#...#/#...#/.#.#./..#../..#../..#../..#..", Z = "#####/....#/...#./..#../.#.../#..../#####",
        ["0"] = ".###./#...#/#..##/#.#.#/##..#/#...#/.###.", ["1"] = "..#../.##../..#../..#../..#../..#../.###.",
        ["2"] = ".###./#...#/....#/...#./..#../.#.../#####", ["3"] = "####./....#/....#/.###./....#/....#/####.",
        ["4"] = "...#./..##./.#.#./#..#./#####/...#./...#.", ["5"] = "#####/#..../####./....#/....#/#...#/.###.",
        ["6"] = ".###./#..../#..../####./#...#/#...#/.###.", ["7"] = "#####/....#/...#./..#../.#.../.#.../.#...",
        ["8"] = ".###./#...#/#...#/.###./#...#/#...#/.###.", ["9"] = ".###./#...#/#...#/.####/....#/....#/.###.",
        [" "] = "...../...../...../...../...../...../.....", [":"] = "...../..#../..#../...../..#../..#../.....",
        ["."] = "...../...../...../...../...../.##../.##..", ["-"] = "...../...../...../#####/...../...../.....",
        ["!"] = "..#../..#../..#../..#../..#../...../..#..", ["?"] = ".###./#...#/....#/...#./..#../...../..#..",
        ["/"] = "....#/....#/...#./..#../.#.../#..../#....", ["%"] = "##..#/##..#/...#./..#../.#.../#..##/#..##",
        ["+"] = "...../..#../..#../#####/..#../..#../.....", ["_"] = "...../...../...../...../...../...../#####",
        [","] = "...../...../...../...../.##../..#../.#...", ["'"] = "..#../..#../.#.../...../...../...../.....",
        ["*"] = "...../#.#.#/.###./#####/.###./#.#.#/.....", ["="] = "...../...../#####/...../#####/...../.....",
    }
    for k, v in pairs(src) do
        local rows = {}
        for r in v:gmatch("[^/]+") do rows[#rows + 1] = r end
        GLYB[k] = rows
    end
end
function D.font(name)
    if name == "big" then return GLYB, 5, 7 end
    return GLY, 3, 5
end
-- Width in pixels of a line of text.
function D.textWidth(s, sc, name, sp)
    local _, gw = D.font(name)
    sp = sp or 0
    local n = #s
    if n == 0 then return 0 end
    return n * ((gw + 1) * sc + sp) - sc - sp
end
function D.text(c, s, x, y, sc, col, name, sp)
    local g, gw, gh = D.font(name)
    sp = sp or 0
    for i = 1, #s do
        local rows = g[s:sub(i, i):upper()] or g["?"]
        local gx = x + (i - 1) * ((gw + 1) * sc + sp)
        for ry = 1, gh do
            local row = rows[ry]
            for rx = 1, gw do
                if row:sub(rx, rx) == "#" then
                    D.rect(c, gx + (rx - 1) * sc, y + (ry - 1) * sc, gx + rx * sc - 1, y + ry * sc - 1, col)
                end
            end
        end
    end
end

-- ── Shapes ───────────────────────────────────────────────────────────────────
local BAY = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
function D.bay(x, y) return (BAY[(y - 1) % 4 + 1][(x - 1) % 4 + 1] + 0.5) / 16 end

local function span(y, x1, y1, x2, y2, r)
    local k = min(y - y1, y2 - y)
    local inset = (r > 0 and k < r) and (r - k) or 0
    return x1 + inset, x2 - inset
end
local function capR(x1, y1, x2, y2, r)
    return min(r or 0, floor((min(x2 - x1, y2 - y1) + 1) / 2))
end
-- Filled rectangle with cut corners. r is 0 to 3.
function D.rrect(c, x1, y1, x2, y2, col, r)
    if not col then return end
    r = capR(x1, y1, x2, y2, r)
    if r <= 0 then return D.rect(c, x1, y1, x2, y2, col) end
    for y = max(1, y1), min(c.ph, y2) do
        local xa, xb = span(y, x1, y1, x2, y2, r)
        D.rect(c, xa, y, xb, y, col)
    end
end
function D.rbox(c, x1, y1, x2, y2, col, r)
    if not col then return end
    r = capR(x1, y1, x2, y2, r)
    if r <= 0 then return D.box(c, x1, y1, x2, y2, col) end
    for y = max(1, y1), min(c.ph, y2) do
        local xa, xb = span(y, x1, y1, x2, y2, r)
        if y == y1 or y == y2 or x2 - x1 < 2 or y2 - y1 < 2 then
            D.rect(c, xa, y, xb, y, col)
        else
            local ia, ib = span(y, x1 + 1, y1 + 1, x2 - 1, y2 - 1, max(0, r - 1))
            D.rect(c, xa, y, ia - 1, y, col)
            D.rect(c, ib + 1, y, xb, y, col)
        end
    end
end
-- Fill that fades from c1 at the top to c2 at the bottom with dots.
function D.gradFill(c, x1, y1, x2, y2, c1, c2, r)
    r = capR(x1, y1, x2, y2, r)
    for y = max(1, y1), min(c.ph, y2) do
        local t = (y2 > y1) and (y - y1) / (y2 - y1) or 0
        local xa, xb = x1, x2
        if r > 0 then xa, xb = span(y, x1, y1, x2, y2, r) end
        local row = c[y]
        for x = max(1, xa), min(c.pw, xb) do row[x] = (t > D.bay(x, y)) and c2 or c1 end
    end
end

function D.layer(w, h) return D.new(max(1, w), max(1, h), false) end

-- ── Effects ──────────────────────────────────────────────────────────────────
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

function D.clock(fmt, mode)
    fmt = (fmt and fmt ~= "") and fmt or "%H:%M"
    if mode == "game" then
        local t = os.time()
        local h = floor(t)
        local m = floor((t - h) * 60)
        local h12 = h % 12
        if h12 == 0 then h12 = 12 end
        local ok, s = pcall(function()
            return (fmt:gsub("%%(%a)", function(k)
                if k == "H" then return string.format("%02d", h)
                elseif k == "M" then return string.format("%02d", m)
                elseif k == "I" then return string.format("%02d", h12)
                elseif k == "p" then return h < 12 and "AM" or "PM"
                elseif k == "d" then return tostring(os.day and os.day() or 1)
                end
                return ""
            end))
        end)
        return ok and s:sub(1, 16) or "--:--"
    end
    local ok, s = pcall(os.date, fmt)
    if ok and type(s) == "string" then return s:sub(1, 16) end
    return "--:--"
end

-- Text into a layer. The area is x, y, aw, ah. Size is picked to fit unless
-- the widget sets one. A "|" starts a new line.
function D.textBlock(L, w, s, ax, ay, aw, ah, col)
    s = tostring(s or "")
    if s == "" then return end
    local lines, longest = {}, ""
    for part in (s .. "|"):gmatch("(.-)|") do
        lines[#lines + 1] = part
        if #part > #longest then longest = part end
    end
    if #lines > 6 then for i = #lines, 7, -1 do lines[i] = nil end end
    local nl = #lines
    local g, gw, gh = D.font(w.fnt)
    local sp = w.sp or 0
    local maxw, maxh = aw - 2, ah - 2
    local function fits(k)
        return D.textWidth(longest, k, w.fnt, sp) <= maxw and nl * gh * k + (nl - 1) * k <= maxh
    end
    local sc = w.sc or 0
    if sc < 1 then
        sc = 1
        for k = 2, 10 do if fits(k) then sc = k end end
    end
    while sc > 1 and not fits(sc) do sc = sc - 1 end
    local adv = (gw + 1) * sc + sp
    local n = floor((maxw + sc + sp) / adv)
    if n < 1 then return end
    local total = nl * gh * sc + (nl - 1) * sc
    local y0 = ay + floor((ah - total) / 2)
    for i, line in ipairs(lines) do
        if #line > n then line = line:sub(1, n) end
        local tw = D.textWidth(line, sc, w.fnt, sp)
        local x
        if w.al == "left" then x = ax + 1
        elseif w.al == "right" then x = ax + aw - tw - 1
        else x = ax + floor((aw - tw) / 2) end
        D.text(L, line, x, y0 + (i - 1) * (gh + 1) * sc, sc, col, w.fnt, sp)
    end
end

-- Dither a layer from two colors, top to bottom.
function D.gradLayer(L, c1, c2)
    local h = L.ph
    for y = 1, h do
        local t = (h > 1) and (y - 1) / (h - 1) or 0
        local row = L[y]
        for x = 1, L.pw do
            if row[x] then row[x] = (t > D.bay(x, y)) and c2 or c1 end
        end
    end
end

-- Draw a layer onto the canvas with the widget's shadow and reflection.
function D.stylize(c, w, L)
    if w.gr == "vertical" then D.gradLayer(L, w.fg, w.fg2 or w.fg) end
    local out = L
    local rh = w.h - L.ph
    if w.sh or rh > 0 then
        out = D.layer(w.w, w.h)
        if w.sh then
            local o = (w.sc and w.sc >= 4) and 2 or 1
            for y = 1, L.ph do
                for x = 1, L.pw do
                    if L[y][x] and y + o <= out.ph and x + o <= out.pw then out[y + o][x + o] = w.sh end
                end
            end
        end
        for y = 1, L.ph do
            for x = 1, L.pw do
                if L[y][x] then out[y][x] = L[y][x] end
            end
        end
        for i = 1, rh do
            local sy = L.ph - i + 1
            local keep = 1 - (i - 1) / max(1, rh)
            if sy >= 1 then
                for x = 1, L.pw do
                    local v = L[sy][x]
                    if v and keep > D.bay(x, i) and not out[L.ph + i][x] then out[L.ph + i][x] = w.rc or v end
                end
            end
        end
    end
    for y = 1, out.ph do
        local cy = w.y + y - 1
        if cy >= 1 and cy <= c.ph then
            local row, crow = out[y], c[cy]
            for x = 1, out.pw do
                local v = row[x]
                local cx = w.x + x - 1
                if v and cx >= 1 and cx <= c.pw then crow[cx] = v end
            end
        end
    end
end

-- Height of the main part of a widget when it keeps room for a reflection.
function D.mainH(w)
    local rf = w.rf or 0
    if rf <= 0 then return w.h end
    local m = w.h - floor(w.h * rf / 100)
    if m < 3 then return w.h end
    return m
end

function W.label(c, w, s, col)
    local mh = D.mainH(w)
    local L = D.layer(w.w, mh)
    D.textBlock(L, w, s, 1, 1, w.w, mh, col)
    D.stylize(c, w, L)
end

-- Art into a layer. Mode decides how it fills the widget.
function A.sample(L, w, t)
    local art = w.art
    if not art or art.cols < 1 then return end
    local px = A.px(art)
    local sw, sh = px.pw, px.ph
    local aw, ah = L.pw, L.ph
    local mode = w.am or "fit"
    local dw, dh
    if mode == "stretch" then
        dw, dh = aw, ah
    elseif mode == "1x" or mode == "2x" or mode == "3x" then
        local k = tonumber(mode:sub(1, 1))
        dw, dh = sw * k, sh * k
    else
        local s = min(aw / sw, ah / sh)
        if s >= 1 then s = floor(s) end
        dw, dh = max(1, floor(sw * s)), max(1, floor(sh * s))
    end
    local ox
    if w.al == "left" then ox = 0 elseif w.al == "right" then ox = aw - dw else ox = floor((aw - dw) / 2) end
    local oy = floor((ah - dh) / 2)
    local map, fx = w.map, w.fx or "none"
    local wave = floor((t or 0) * 3)
    if fx == "blink" and floor((t or 0) * 2) % 2 == 1 then return end
    local alt = (fx == "pulse") and sin((t or 0) * 4) <= 0
    for dy = 1, dh do
        local yy = oy + dy
        if yy >= 1 and yy <= ah then
            local srow = px[floor((dy - 1) * sh / dh) + 1]
            local drow = L[yy]
            for dx = 1, dw do
                local xx = ox + dx
                if xx >= 1 and xx <= aw then
                    local v = srow[floor((dx - 1) * sw / dw) + 1]
                    if v then
                        if map and map[v] then v = map[v] end
                        if fx == "rainbow" then v = RAINBOW[(wave + floor(dx / 3)) % #RAINBOW + 1]
                        elseif alt then v = w.fxc end
                        drow[xx] = v
                    end
                end
            end
        end
    end
end

-- ── Backgrounds and widgets ──────────────────────────────────────────────────
function D.background(c, dash, t)
    D.rect(c, 1, 1, c.pw, c.ph, dash.bg)
    local fx = dash.fx
    if fx == "stars" then
        for i = 1, floor(c.pw * c.ph / 90) do
            local x = (i * 37 + (i * i) % 11) % c.pw + 1
            local y = (i * 53 + (i * 7) % 13) % c.ph + 1
            local tw = sin(t * 1.5 + i)
            c[y][x] = (tw > 0.6) and colors.white or ((tw > -0.3) and colors.lightGray or colors.gray)
        end
    elseif fx == "grid" then
        local gc = (dash.bg == colors.gray) and colors.lightGray or colors.gray
        for y = 1, c.ph, 8 do D.rect(c, 1, y, c.pw, y, gc) end
        for x = 1, c.pw, 8 do D.rect(c, x, 1, x, c.ph, gc) end
    elseif fx == "dots" then
        local gc = (dash.bg == colors.gray) and colors.lightGray or colors.gray
        for y = 1, c.ph, 6 do for x = 1, c.pw, 6 do c[y][x] = gc end end
    elseif fx == "lines" then
        local gc = (dash.bg == colors.gray) and colors.lightGray or colors.gray
        for y = 1, c.ph, 3 do D.rect(c, 1, y, c.pw, y, gc) end
    elseif fx == "gradient" then
        D.gradFill(c, 1, 1, c.pw, c.ph, dash.bg, dash.bg2 or colors.blue, 0)
    end
end

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

local function backing(c, w, col)
    local x1, y1, x2, y2 = w.x, w.y, w.x + w.w - 1, w.y + w.h - 1
    if not col then return end
    if w.gr == "vertical" and w.kind == "panel" then
        D.gradFill(c, x1, y1, x2, y2, col, w.fg2 or col, w.rd or 0)
    else
        D.rrect(c, x1, y1, x2, y2, col, w.rd or 0)
    end
end
local function edge(c, w)
    if w.bd then D.rbox(c, w.x, w.y, w.x + w.w - 1, w.y + w.h - 1, w.bd, w.rd or 0) end
end

function W.draw(c, w, ctx)
    local x1, y1 = w.x, w.y
    local x2, y2 = w.x + w.w - 1, w.y + w.h - 1
    local k, t = w.kind, ctx.t
    if w.hidden then
        if ctx.edit then
            for x = x1, x2, 2 do D.rect(c, x, y1, x, y1, colors.gray); D.rect(c, x, y2, x, y2, colors.gray) end
            for y = y1, y2, 2 do D.rect(c, x1, y, x1, y, colors.gray); D.rect(c, x2, y, x2, y, colors.gray) end
        end
        return
    end
    local fg = D.accent(w, w.fg, t)
    if k == "panel" then
        backing(c, w, w.bg)
        edge(c, w)
    elseif k == "text" or k == "clock" then
        backing(c, w, w.bg)
        edge(c, w)
        W.label(c, w, (k == "clock") and D.clock(w.tx, w.cm) or w.tx, fg)
    elseif k == "button" then
        local pressed = ctx.st[w.id] and ctx.st[w.id] > t
        local back, front = w.bg or colors.gray, fg
        if pressed then back, front = front, back end
        D.rrect(c, x1, y1, x2, y2, back, w.rd or 0)
        edge(c, w)
        W.label(c, w, w.tx, front)
    elseif k == "toggle" then
        local on = ctx.live and R.getOut(w.act.side)
        D.rrect(c, x1, y1, x2, y2, on and w.fxc or (w.bg or colors.gray), w.rd or 0)
        edge(c, w)
        W.label(c, w, w.tx, on and colors.black or fg)
    elseif k == "lamp" then
        local on = R.analog(w, ctx) > 0
        D.rrect(c, x1, y1, x2, y2, on and D.accent(w, w.fxc, t) or (w.bg or colors.gray), w.rd or 0)
        edge(c, w)
    elseif k == "bar" then
        D.rrect(c, x1, y1, x2, y2, w.bg or colors.gray, w.rd or 0)
        local v = R.analog(w, ctx) / 15
        if w.dir == "up" then
            local fill = floor((w.h - 2) * v + 0.5)
            if fill > 0 then D.rect(c, x1 + 1, y2 - fill, x2 - 1, y2 - 1, fg) end
        else
            local fill = floor((w.w - 2) * v + 0.5)
            if fill > 0 then D.rect(c, x1 + 1, y1 + 1, x1 + fill, y2 - 1, fg) end
        end
        edge(c, w)
    elseif k == "line" then
        local horiz = w.w >= w.h
        local len = horiz and w.w or w.h
        for i = 0, len - 1 do
            local on = true
            if w.ls == "dotted" then on = (i % 2 == 0)
            elseif w.ls == "dashed" then on = (floor(i / 3) % 2 == 0) end
            if on then
                if horiz then D.rect(c, x1 + i, y1, x1 + i, y2, fg) else D.rect(c, x1, y1 + i, x2, y1 + i, fg) end
            end
        end
    elseif k == "art" then
        backing(c, w, w.bg)
        edge(c, w)
        local mh = D.mainH(w)
        local L = D.layer(w.w, mh)
        A.sample(L, w, t)
        -- Art keeps its own colors: no text gradient over it.
        D.stylize(c, setmetatable({ gr = "none" }, { __index = w }), L)
    end
end

function D.dash(c, dash, ctx)
    D.background(c, dash, ctx.t)
    ctx.bg = dash.bg
    for _, w in ipairs(dash.widgets) do W.draw(c, w, ctx) end
end

-- ── Widgets: defaults, cleaning, saving ──────────────────────────────────────
local DEF = {
    panel  = { w = 34, h = 22, tx = "", bg = colors.gray, bd = colors.lightGray, fg = colors.white },
    text   = { w = 60, h = 14, tx = "HELLO", bg = false, bd = false, fg = colors.white },
    button = { w = 38, h = 15, tx = "PUSH", bg = colors.blue, bd = colors.lightBlue, fg = colors.white, rd = 1 },
    toggle = { w = 38, h = 15, tx = "LIGHT", bg = colors.gray, bd = colors.lightGray, fg = colors.white, fxc = colors.lime, rd = 1 },
    lamp   = { w = 12, h = 12, tx = "", bg = colors.gray, bd = colors.lightGray, fg = colors.white, fxc = colors.lime, rd = 3 },
    bar    = { w = 48, h = 9, tx = "", bg = colors.gray, bd = colors.lightGray, fg = colors.lime },
    clock  = { w = 56, h = 14, tx = "%H:%M", bg = false, bd = false, fg = colors.yellow },
    line   = { w = 48, h = 1, tx = "", bg = false, bd = false, fg = colors.lightGray },
    art    = { w = 48, h = 24, tx = "", bg = false, bd = false, fg = colors.white },
}
function W.minSize(kind) return (kind == "line") and 1 or 3 end
function W.label_of(w)
    if w.name and w.name ~= "" then return w.name end
    return w.kind
end

function W.new(kind, dash)
    local d = DEF[kind]
    dash.nextId = (dash.nextId or 0) + 1
    return {
        id = "w" .. dash.nextId, kind = kind, name = "", x = 1, y = 1, w = d.w, h = d.h, tx = d.tx,
        fg = d.fg, bg = d.bg, bd = d.bd, fx = "none", fxc = d.fxc or colors.yellow,
        al = "center", sc = 0, fnt = "small", sp = 0, rd = d.rd or 0,
        gr = "none", fg2 = colors.blue, sh = false, rf = 0, rc = false,
        locked = false, hidden = false, dir = "right", cm = "real", ls = "solid", am = "fit",
        act = { side = "top", mode = (kind == "button") and "pulse" or "toggle" },
        src = { side = "top", io = "in" },
    }
end

local function colorOr(v, def, allowNone)
    if allowNone and v == false then return false end
    if type(v) == "number" and VALID[v] then return v end
    return def
end
local function pick(list, v, def) return inList(list, v) and v or def end

function W.clean(t, dash)
    if type(t) ~= "table" or not KINDSET[t.kind] then return nil end
    local w = W.new(t.kind, { nextId = 0 })
    local mn = W.minSize(t.kind)
    w.id = (type(t.id) == "string" and #t.id <= 12) and t.id or ("w" .. tostring(math.random(1000, 99999)))
    w.name = (type(t.name) == "string") and t.name:sub(1, 20) or ""
    w.w = F.int(t.w, w.w, mn, dash.pw)
    w.h = F.int(t.h, w.h, mn, dash.ph)
    w.x = F.int(t.x, 1, 1, max(1, dash.pw - w.w + 1))
    w.y = F.int(t.y, 1, 1, max(1, dash.ph - w.h + 1))
    w.tx = (type(t.tx) == "string") and t.tx:sub(1, 40) or w.tx
    w.fg = colorOr(t.fg, w.fg, false)
    w.bg = colorOr(t.bg, w.bg, true)
    w.bd = colorOr(t.bd, w.bd, true)
    w.fxc = colorOr(t.fxc, w.fxc, false)
    w.fg2 = colorOr(t.fg2, w.fg2, false)
    w.sh = colorOr(t.sh, false, true)
    w.rc = colorOr(t.rc, false, true)
    w.fx = pick(EFFECTS, t.fx, "none")
    w.al = pick(ALIGN, t.al, "center")
    w.fnt = pick(FONTS, t.fnt, "small")
    w.gr = pick(GRADS, t.gr, "none")
    w.cm = pick(CLOCKS, t.cm, "real")
    w.ls = pick(LSTYLES, t.ls, "solid")
    w.dir = pick(DIRS, t.dir, "right")
    w.am = pick(ARTMODES, t.am, "fit")
    w.sc = F.int(t.sc, 0, 0, 10)
    w.sp = F.int(t.sp, 0, 0, 6)
    w.rd = F.int(t.rd, w.rd, 0, 3)
    w.rf = F.int(t.rf, 0, 0, 60)
    w.locked = t.locked == true
    w.hidden = t.hidden == true
    if type(t.act) == "table" then
        if SIDESET[t.act.side] then w.act.side = t.act.side end
        if inList(MODES, t.act.mode) then w.act.mode = t.act.mode end
    end
    if type(t.src) == "table" then
        if SIDESET[t.src.side] then w.src.side = t.src.side end
        if inList(IOS, t.src.io) then w.src.io = t.src.io end
    end
    if t.kind == "art" then
        w.art = A.decode(t.art) or A.new(8, 4)
        if type(t.map) == "table" then
            local m, n = {}, 0
            for from, to in pairs(t.map) do
                if n < 20 and VALID[from] and VALID[to] then m[from] = to; n = n + 1 end
            end
            if n > 0 then w.map = m end
        end
    end
    return w
end

function W.newDash(name, pw, ph)
    return { v = 2, name = name, pw = pw, ph = ph, bg = colors.black, bg2 = colors.blue, fx = "none", widgets = {}, nextId = 0 }
end

function W.cleanDash(t, name)
    local d = W.newDash(F.safe(name), F.int(t.pw, 72, 16, 400), F.int(t.ph, 54, 12, 300))
    if d.name == "" then d.name = "dash" end
    d.bg = colorOr(t.bg, colors.black, false)
    d.bg2 = colorOr(t.bg2, colors.blue, false)
    d.fx = pick(BGFX, t.fx, "none")
    d.nextId = F.int(t.nextId, 0, 0, 100000)
    if type(t.widgets) == "table" then
        for i = 1, min(#t.widgets, MAXW) do
            local w = W.clean(t.widgets[i], d)
            if w then d.widgets[#d.widgets + 1] = w end
        end
    end
    return d
end

-- A copy of the dashboard that is safe to write to disk.
function F.encodeDash(d)
    local o = {}
    for k, v in pairs(d) do if k ~= "widgets" then o[k] = v end end
    o.widgets = {}
    for i, w in ipairs(d.widgets) do
        local c = {}
        for k, v in pairs(w) do c[k] = v end
        if w.art then c.art = A.encode(w.art) end
        o.widgets[i] = c
    end
    return o
end

function F.loadDash(name)
    local s = F.read(F.path(name))
    if not s or #s > 900000 then return nil, "Cannot read that file" end
    local t = textutils.unserialize(s)
    if type(t) ~= "table" then return nil, "That file is damaged" end
    return W.cleanDash(t, name)
end
function F.saveDash(d)
    local name = F.safe(d.name)
    if name == "" then return false end
    d.name = name
    F.ensure(DIR .. "/dash")
    return F.write(F.path(name), textutils.serialize(F.encodeDash(d)))
end

function W.at(dash, dx, dy)
    for i = #dash.widgets, 1, -1 do
        local w = dash.widgets[i]
        if not w.hidden and dx >= w.x and dx < w.x + w.w and dy >= w.y and dy < w.y + w.h then return w, i end
    end
    return nil
end

-- ── Settings and saved art ───────────────────────────────────────────────────
function F.loadCfg()
    local s = F.read(DIR .. "/config.dat")
    local t = s and #s < 5000 and textutils.unserialize(s)
    if type(t) == "table" then
        if type(t.mon) == "string" then CFG.mon = t.mon:sub(1, 60) end
        local sc = tonumber(t.scale)
        if sc and sc >= 0.5 and sc <= 5 then CFG.scale = floor(sc * 2 + 0.5) / 2 end
        CFG.grid = F.int(t.grid, 8, 1, 64)
        CFG.showGrid = t.showGrid == true
        if t.snap == false then CFG.snap = false end
    end
end
function F.saveCfg()
    F.write(DIR .. "/config.dat", textutils.serialize({
        mon = CFG.mon, scale = CFG.scale, grid = CFG.grid, showGrid = CFG.showGrid, snap = CFG.snap }))
end

function F.apath(name) return DIR .. "/art/" .. name .. ".art" end
function F.listArt()
    local out = {}
    local dir = DIR .. "/art"
    if fs.exists(dir) and fs.isDir(dir) then
        for _, n in ipairs(fs.list(dir)) do
            local b = n:match("^(.+)%.art$")
            if b then out[#out + 1] = b end
        end
    end
    table.sort(out)
    return out
end
-- Text files the user dropped in the art folder: .txt, .ans, .asc.
function F.listArtFiles()
    local out = {}
    local dir = DIR .. "/art"
    if fs.exists(dir) and fs.isDir(dir) then
        for _, n in ipairs(fs.list(dir)) do
            if n:match("%.txt$") or n:match("%.ans$") or n:match("%.asc$") then out[#out + 1] = n end
        end
    end
    table.sort(out)
    return out
end
function F.saveArt(name, art)
    F.ensure(DIR .. "/art")
    return F.write(F.apath(name), textutils.serialize(A.encode(art)))
end
function F.loadArt(name)
    local s = F.read(F.apath(name))
    if not s or #s > 600000 then return nil end
    return A.decode(textutils.unserialize(s))
end
function F.importArt(file, defFg)
    local s = F.read(DIR .. "/art/" .. file)
    if not s or #s > 600000 then return nil end
    return A.parse(s, defFg)
end

-- ── Theme and terminal basics ────────────────────────────────────────────────
local TFALL = {
    bg = colors.black, panel = colors.gray, hdr = colors.blue, text = colors.white, dim = colors.lightGray,
    line = colors.cyan, sel = colors.lightBlue, selText = colors.black, bar = colors.gray, barBtn = colors.blue,
    barText = colors.white, ok = colors.lime, warn = colors.yellow, err = colors.red, accent = colors.orange,
    hint = colors.lightGray,
}
local function gap(a, b) return abs((TONE[a] or 0.5) - (TONE[b] or 0.5)) end
local function standout(bg, need, prefs)
    for _, c in ipairs(prefs or {}) do
        if c and gap(c, bg) >= need then return c end
    end
    local best, bestGap = colors.white, -1
    for _, c in ipairs(ORDER) do
        local g = gap(c, bg)
        if g > bestGap then best, bestGap = c, g end
    end
    return best
end
local function ensure(role, against, need, prefs)
    if gap(TC[role], TC[against]) < need then TC[role] = standout(TC[against], need, prefs) end
end
function UI.loadTheme()
    local src
    pcall(function()
        local p = rawget(_G, "prismarine")
        local t = (p and p.theme) or api.theme
        src = t and t.colors
    end)
    for role, def in pairs(TFALL) do
        local v
        if src then
            local ok, got = pcall(function() return src[role] end)
            if ok then v = got end
        end
        TC[role] = (type(v) == "number" and VALID[v]) and v or def
    end
    for i = 0, 15 do
        local slot = 2 ^ i
        local ok, r, g, b = pcall(term.getPaletteColor, slot)
        if ok and r then TONE[slot] = 0.3 * r + 0.59 * g + 0.11 * b end
    end
    for _, bgRole in ipairs({ "bg", "panel" }) do
        ensure("text", bgRole, 0.4, { TC.text, colors.white, colors.black })
        ensure("dim", bgRole, 0.25, { TC.dim, TC.text })
        ensure("line", bgRole, 0.2, { TC.line, TC.accent, TC.text })
        ensure("ok", bgRole, 0.2, { TC.ok, TC.line, TC.text })
        ensure("warn", bgRole, 0.2, { TC.warn, TC.accent, TC.text })
        ensure("err", bgRole, 0.15, { TC.err, TC.warn, TC.text })
    end
    if gap(TC.sel, TC.panel) < 0.12 then TC.sel = standout(TC.panel, 0.3, { TC.line, TC.accent, colors.lightGray }) end
    ensure("selText", "sel", 0.4, { colors.black, colors.white })
    ensure("barText", "bar", 0.4, { TC.text, colors.white, colors.black })
    ensure("barText", "barBtn", 0.3, { TC.barText, colors.white, colors.black })
    if gap(TC.barBtn, TC.bar) < 0.08 then TC.barBtn = standout(TC.bar, 0.2, { TC.line, TC.hdr, TC.sel }) end
end

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

function UI.flash(text) S.note = { text = tostring(text), t = os.clock() } end
function UI.resetMods() S.mod.shift, S.mod.ctrl = false, false end

-- A centred box with a title chip. Returns x, y, w, h.
function UI.frame(title, bw, bh)
    local w, h = term.getSize()
    bw, bh = min(bw, w - 2), min(bh, h - 2)
    local bx, by = floor((w - bw) / 2) + 1, floor((h - bh) / 2) + 1
    for y = 0, bh - 1 do UI.fill(bx, by + y, bw, TC.panel) end
    UI.fill(bx, by, bw, TC.bar)
    UI.put(bx, by, " " .. F.cut(title, bw - 2) .. " ", TC.barText, TC.barBtn)
    return bx, by, bw, bh
end

-- Pick one item. Returns its number, or nil on Esc.
function UI.pick(title, items, hint, start)
    local sel, top = start or 1, 0
    while true do
        S.under()
        local widest = #title + 4
        for _, it in ipairs(items) do widest = max(widest, #it + 4) end
        local bx, by, bw, bh = UI.frame(title, max(34, widest), #items + 4)
        local rows = bh - 3
        if sel < top + 1 then top = sel - 1 elseif sel > top + rows then top = sel - rows end
        for i = 1, rows do
            local it = items[top + i]
            if it then
                local on = (top + i == sel)
                UI.put(bx + 1, by + i, F.pad(it, bw - 2), on and TC.selText or TC.text, on and TC.sel or TC.panel)
            end
        end
        UI.put(bx + 1, by + bh - 1, F.pad(hint or "Enter: pick   Esc: back", bw - 2), TC.dim, TC.panel)
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.up then sel = max(1, sel - 1)
            elseif a == keys.down then sel = min(#items, sel + 1)
            elseif a == keys.pageUp then sel = max(1, sel - rows)
            elseif a == keys.pageDown then sel = min(#items, sel + rows)
            elseif a == keys.home then sel = 1
            elseif a == keys["end"] then sel = #items
            elseif a == keys.enter then UI.resetMods() return sel
            elseif a == keys.escape or a == keys.q then UI.resetMods() return nil end
        elseif ev == "mouse_click" then
            if b >= bx and b < bx + bw and c > by and c <= by + rows and items[top + c - by] then
                UI.resetMods()
                return top + c - by
            elseif b < bx or b >= bx + bw or c < by or c >= by + bh then
                UI.resetMods()
                return nil
            end
        elseif ev == "mouse_scroll" then
            sel = F.clamp(sel + a, 1, #items)
        end
    end
end

function UI.msg(text, title)
    local lines = {}
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    while true do
        S.under()
        local widest = 0
        for _, l in ipairs(lines) do widest = max(widest, #l) end
        local bx, by, bw, bh = UI.frame(title or "Pixel Dash", widest + 4, #lines + 4)
        for i, l in ipairs(lines) do
            if i <= bh - 3 then UI.put(bx + 1, by + i, F.cut(l, bw - 2), TC.text, TC.panel) end
        end
        UI.put(bx + 1, by + bh - 1, F.cut("Press any key", bw - 2), TC.dim, TC.panel)
        local ev = os.pullEvent()
        if ev == "key" or ev == "mouse_click" then UI.resetMods() return end
    end
end

function UI.ask(text)
    local i = UI.pick(text, { "Yes", "No" }, "Enter: pick   Esc: no")
    return i == 1
end

-- A form. fields: { id, label, t = "text"|"num"|"choice"|"color"|"bool", v, list, min, max, len, none }.
-- Returns a table of answers, or nil when cancelled.
function UI.form(title, fields)
    local n = #fields
    local val, fresh = {}, {}
    for i, f in ipairs(fields) do
        if f.t == "text" then val[i] = tostring(f.v or "")
        elseif f.t == "num" then val[i] = tostring(f.v or 0)
        elseif f.t == "bool" then val[i] = f.v and 2 or 1
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
            elseif f.t == "bool" then r[f.id] = (val[i] == 2)
            elseif f.t == "choice" then r[f.id] = f.list[val[i]]
            else r[f.id] = (val[i] == 0) and false or ORDER[val[i]] end
        end
        return r
    end
    local function step(i, d)
        local f = fields[i]
        if f.t == "choice" then
            val[i] = (val[i] - 1 + d) % #f.list + 1
        elseif f.t == "bool" then
            val[i] = (val[i] == 2) and 1 or 2
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
        local bx, by, bw, bh = UI.frame(title, 38, rows + 3)
        if focus <= top then top = focus - 1 elseif focus > top + rows then top = focus - rows end
        local lw = min(11, floor(bw / 3))
        local vx, vw = bx + 2 + lw, bw - 3 - lw
        for r = 1, rows do
            local i = top + r
            local f = fields[i]
            if f then
                local on = (i == focus)
                local y = by + r
                UI.put(bx + 1, y, F.pad(f.label, lw), on and TC.selText or TC.dim, on and TC.sel or TC.panel)
                UI.fill(vx, y, vw, TC.panel)
                if f.t == "text" or f.t == "num" then
                    local s = val[i]
                    if #s > vw - 1 then s = s:sub(#s - vw + 2) end
                    UI.put(vx, y, s .. (on and "_" or ""), TC.text, TC.panel)
                elseif f.t == "choice" then
                    UI.put(vx, y, F.cut("< " .. tostring(f.list[val[i]]) .. " >", vw), TC.text, TC.panel)
                elseif f.t == "bool" then
                    UI.put(vx, y, (val[i] == 2) and "[x] on" or "[ ] off", (val[i] == 2) and TC.ok or TC.dim, TC.panel)
                else
                    if val[i] == 0 then
                        UI.put(vx, y, "--", TC.dim, TC.panel)
                        UI.put(vx + 3, y, F.cut("none", vw - 3), TC.text, TC.panel)
                    else
                        UI.put(vx, y, "  ", TC.text, ORDER[val[i]])
                        UI.put(vx + 3, y, F.cut(CNAME[val[i]], vw - 3), TC.text, TC.panel)
                    end
                end
            end
        end
        local fy = by + bh - 1
        UI.put(bx + 1, fy, " OK ", colors.black, TC.ok)
        UI.put(bx + 6, fy, " Cancel ", colors.white, TC.err)
        UI.put(bx + 15, fy, F.cut("Tab: next", bw - 16), TC.dim, TC.panel)
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.escape then UI.resetMods() return nil
            elseif a == keys.enter then UI.resetMods() return result()
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
            elseif f.t == "bool" and a == " " then
                step(focus, 1)
            end
        elseif ev == "paste" then
            local f = fields[focus]
            if f.t == "text" then
                local s = a:gsub("[^%g ]", "")
                val[focus] = (val[focus] .. s):sub(1, f.len or 24)
            end
        elseif ev == "mouse_click" then
            if c == fy and b >= bx + 1 and b <= bx + 4 then UI.resetMods() return result()
            elseif c == fy and b >= bx + 6 and b <= bx + 13 then UI.resetMods() return nil
            elseif b >= bx and b < bx + bw and c > by and c <= by + rows then
                local i = top + c - by
                if fields[i] then
                    local ft = fields[i].t
                    if i == focus and (ft == "choice" or ft == "color" or ft == "bool") then step(i, 1)
                    else setFocus(i) end
                end
            elseif b < bx or b >= bx + bw or c < by or c >= by + bh then
                UI.resetMods()
                return nil
            end
        end
    end
end

-- One line of text. Returns the text, or nil when cancelled.
function UI.input(title, label, value, len)
    local r = UI.form(title, { { id = "v", label = label, t = "text", v = value or "", len = len or 20 } })
    return r and r.v or nil
end

-- ── Pop-up menus ─────────────────────────────────────────────────────────────
-- items: { label, key, fn, sub, off, sep }. sub is a list or a function that
-- returns one. A pop-up returns the chosen item, or nil.
function UI.popupBase(behind)
    if behind then behind() else S.under() end
end
function UI.popupPaint(items, x, y, bw, bh, iw, lw, kw, sel)
    UI.fill(x, y, bw, TC.line)
    UI.fill(x, y + bh - 1, bw, TC.line)
    for i, it in ipairs(items) do
        local ry = y + i
        UI.put(x, ry, " ", TC.text, TC.line)
        UI.put(x + bw - 1, ry, " ", TC.text, TC.line)
        if it.sep then
            UI.put(x + 1, ry, string.rep("-", iw), TC.dim, TC.panel)
        else
            local on = (i == sel)
            local fg = on and TC.selText or (it.off and TC.dim or TC.text)
            local bg = on and TC.sel or TC.panel
            local line = " " .. F.pad(it.label, lw)
            if kw > 0 then line = line .. " " .. F.pad(it.key or "", kw) end
            line = line .. " " .. (it.sub and ">" or " ")
            UI.put(x + 1, ry, F.pad(line, iw), fg, bg)
        end
    end
end

function UI.popup(items, px, py, behind)
    local sw, sh = term.getSize()
    local lw, kw = 0, 0
    for _, it in ipairs(items) do
        if not it.sep then lw = max(lw, #it.label); kw = max(kw, #(it.key or "")) end
    end
    local iw = lw + 1 + ((kw > 0) and (kw + 1) or 0) + 2
    local bw, bh = iw + 2, #items + 2
    local x = F.clamp(px, 1, max(1, sw - bw + 1))
    local y = F.clamp(py, 2, max(2, sh - bh + 1))
    local sel = 0
    local function usable(i) local it = items[i]; return it and not it.sep and not it.off end
    for i = 1, #items do if usable(i) then sel = i break end end
    local function move(d)
        local i = sel
        for _ = 1, #items do
            i = (i - 1 + d) % #items + 1
            if usable(i) then sel = i return end
        end
    end
    local function activate(i)
        local it = items[i]
        if it.sub then
            local list = (type(it.sub) == "function") and it.sub() or it.sub
            if list and #list > 0 then
                return UI.popup(list, x + bw - 1, y + i, function()
                    UI.popupBase(behind)
                    UI.popupPaint(items, x, y, bw, bh, iw, lw, kw, sel)
                end)
            end
            return nil
        end
        return it
    end
    while true do
        UI.popupBase(behind)
        UI.popupPaint(items, x, y, bw, bh, iw, lw, kw, sel)
        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.up then move(-1)
            elseif a == keys.down then move(1)
            elseif a == keys.enter or a == keys.right then
                if sel > 0 then
                    local r = activate(sel)
                    if r then return r end
                end
            elseif a == keys.left or a == keys.escape then return nil end
        elseif ev == "mouse_click" then
            if b > x and b < x + bw - 1 and c > y and c < y + bh - 1 then
                local i = c - y
                if usable(i) then
                    sel = i
                    local r = activate(i)
                    if r then return r end
                end
            elseif b < x or b >= x + bw or c < y or c >= y + bh then
                return nil
            end
        end
    end
end

-- Open a pop-up menu and run what is chosen. Returns what the action returns.
function UI.menuAt(items, x, y)
    local it = UI.popup(items, x, y)
    UI.resetMods()
    if it and it.fn then return it.fn() end
end

-- ── Editor: view ─────────────────────────────────────────────────────────────
UI.TOOLS = {
    { "Menu", "menu" }, { "Add", "addMenu" }, { "Edit", "props" }, { "Del", "del" },
    { "Dup", "dup" }, { "Undo", "undo" }, { "Redo", "redo" }, { "Run", "run" }, { "Save", "save" },
}

function UI.viewSize()
    local w, h = term.getSize()
    return w * 2, (h - 2) * 3
end
function UI.fitView()
    local vw, vh = UI.viewSize()
    local d = S.dash
    local z = min((vw - 4) / d.pw, (vh - 4) / d.ph)
    if z >= 1 then z = floor(z) end
    z = max(0.1, z)
    S.view = { z = z, ox = floor((vw - d.pw * z) / 2), oy = floor((vh - d.ph * z) / 2), fit = true }
end
function UI.clampPan()
    local v, d = S.view, S.dash
    local vw, vh = UI.viewSize()
    v.ox = F.clamp(v.ox, 8 - floor(d.pw * v.z), vw - 8)
    v.oy = F.clamp(v.oy, 8 - floor(d.ph * v.z), vh - 8)
end
function UI.zoomAt(nz, ax, ay)
    local v = S.view
    nz = F.clamp(nz, 0.1, 32)
    local px = (ax - v.ox - 1) / v.z
    local py = (ay - v.oy - 1) / v.z
    v.z = nz
    v.ox = floor(ax - 1 - px * nz + 0.5)
    v.oy = floor(ay - 1 - py * nz + 0.5)
    v.fit = false
    UI.clampPan()
end
function UI.zoomStep(dir, ax, ay)
    local vw, vh = UI.viewSize()
    ax, ay = ax or floor(vw / 2), ay or floor(vh / 2)
    local z = S.view.z
    local nz
    if dir > 0 then
        for _, q in ipairs(ZOOMS) do if q > z * 1.01 then nz = q break end end
        nz = nz or ZOOMS[#ZOOMS]
    else
        for i = #ZOOMS, 1, -1 do if ZOOMS[i] < z / 1.01 then nz = ZOOMS[i] break end end
        nz = nz or ZOOMS[1]
    end
    UI.zoomAt(nz, ax, ay)
end
function UI.zoomIn() UI.zoomStep(1) end
function UI.zoomOut() UI.zoomStep(-1) end
function UI.zoomFit() UI.fitView() end
function UI.zoomTo(z)
    local vw, vh = UI.viewSize()
    UI.zoomAt(z, floor(vw / 2), floor(vh / 2))
end
function UI.pan(dx, dy)
    S.view.ox, S.view.oy = S.view.ox + dx, S.view.oy + dy
    S.view.fit = false
    UI.clampPan()
end

function UI.toScreen(dx, dy)
    local v = S.view
    return v.ox + floor((dx - 1) * v.z) + 1, v.oy + floor((dy - 1) * v.z) + 1
end
function UI.toDash(sx, sy)
    local v = S.view
    return floor((sx - v.ox - 1) / v.z) + 1, floor((sy - v.oy - 1) / v.z) + 1
end

-- ── Editor: model changes ────────────────────────────────────────────────────
function UI.mod()
    S.dirty = true
    S.rev = S.rev + 1
end
function UI.snap()
    local u = S.undo
    u[#u + 1] = F.copy(S.dash)
    if #u > 30 then table.remove(u, 1) end
    S.redo = {}
end
function UI.selIds()
    local ids = {}
    for _, w in ipairs(S.sel) do ids[w.id] = true end
    return ids
end
function UI.restore(d, ids)
    S.dash = d
    local list = {}
    for _, w in ipairs(d.widgets) do if ids[w.id] then list[#list + 1] = w end end
    UI.setSel(list)
    UI.mod()
end
function UI.undo()
    local u = S.undo
    if #u == 0 then UI.flash("Nothing to undo") return end
    S.redo[#S.redo + 1] = F.copy(S.dash)
    UI.restore(table.remove(u), UI.selIds())
end
function UI.redo()
    local r = S.redo
    if #r == 0 then UI.flash("Nothing to redo") return end
    S.undo[#S.undo + 1] = F.copy(S.dash)
    UI.restore(table.remove(r), UI.selIds())
end

function UI.isSel(w)
    for _, x in ipairs(S.sel) do if x == w then return true end end
    return false
end
function UI.setSel(list)
    S.sel = list
    S.cur = list[#list]
end
function UI.toggleSel(w)
    local list = {}
    local was = false
    for _, x in ipairs(S.sel) do
        if x == w then was = true else list[#list + 1] = x end
    end
    if not was then list[#list + 1] = w end
    UI.setSel(list)
end
function UI.selectAll()
    local list = {}
    for _, w in ipairs(S.dash.widgets) do if not w.hidden then list[#list + 1] = w end end
    UI.setSel(list)
end
function UI.need()
    if #S.sel == 0 then UI.flash("Select a widget first") return false end
    return true
end

function UI.clampWidgets(d)
    for _, w in ipairs(d.widgets) do
        local mn = W.minSize(w.kind)
        w.w = F.clamp(w.w, mn, d.pw)
        w.h = F.clamp(w.h, mn, d.ph)
        w.x = F.clamp(w.x, 1, max(1, d.pw - w.w + 1))
        w.y = F.clamp(w.y, 1, max(1, d.ph - w.h + 1))
    end
end

-- Add a widget. art is for kind "art". ax, ay is where its middle goes.
function UI.addWidget(kind, art, name, ax, ay)
    local d = S.dash
    if #d.widgets >= MAXW then UI.flash("Too many widgets") return end
    UI.snap()
    local w = W.new(kind, d)
    if art then
        w.art = art
        local nw, nh = art.cols * 2, art.rows * 2
        local k = floor(d.pw * 0.8 / nw)
        if k >= 1 then
            k = min(k, 4)
            w.w, w.h = nw * k, nh * k
        else
            local s = (d.pw * 0.9) / nw
            w.w, w.h = max(3, floor(nw * s)), max(3, floor(nh * s))
        end
        w.name = name or ""
    end
    w.w, w.h = min(w.w, d.pw), min(w.h, d.ph)
    if kind == "line" then w.h = 1 end
    ax = ax or floor(d.pw / 2)
    ay = ay or floor(d.ph / 2)
    w.x = F.clamp(ax - floor(w.w / 2), 1, max(1, d.pw - w.w + 1))
    w.y = F.clamp(ay - floor(w.h / 2), 1, max(1, d.ph - w.h + 1))
    d.widgets[#d.widgets + 1] = w
    UI.setSel({ w })
    UI.mod()
    return w
end

function UI.del()
    if not UI.need() then return end
    UI.snap()
    local d = S.dash
    for i = #d.widgets, 1, -1 do
        if UI.isSel(d.widgets[i]) then table.remove(d.widgets, i) end
    end
    UI.setSel({})
    UI.mod()
end

function UI.dup()
    if not UI.need() then return end
    local d = S.dash
    if #d.widgets + #S.sel > MAXW then UI.flash("Too many widgets") return end
    UI.snap()
    local list = {}
    for _, w in ipairs(S.sel) do
        local c = F.copy(w)
        d.nextId = (d.nextId or 0) + 1
        c.id = "w" .. d.nextId
        c.x = F.clamp(w.x + 3, 1, max(1, d.pw - w.w + 1))
        c.y = F.clamp(w.y + 3, 1, max(1, d.ph - w.h + 1))
        d.widgets[#d.widgets + 1] = c
        list[#list + 1] = c
    end
    UI.setSel(list)
    UI.mod()
end

function UI.copy()
    if not UI.need() then return end
    S.clip = {}
    for _, w in ipairs(S.sel) do S.clip[#S.clip + 1] = F.copy(w) end
    UI.flash("Copied " .. #S.clip)
end
function UI.cut()
    if not UI.need() then return end
    UI.copy()
    UI.del()
end
function UI.paste(ax, ay)
    if not S.clip or #S.clip == 0 then UI.flash("Nothing to paste") return end
    local d = S.dash
    if #d.widgets + #S.clip > MAXW then UI.flash("Too many widgets") return end
    UI.snap()
    local x0, y0 = math.huge, math.huge
    for _, w in ipairs(S.clip) do x0, y0 = min(x0, w.x), min(y0, w.y) end
    local dx, dy = 3, 3
    if ax then dx, dy = ax - x0, ay - y0 end
    local list = {}
    for _, w in ipairs(S.clip) do
        local c = F.copy(w)
        d.nextId = (d.nextId or 0) + 1
        c.id = "w" .. d.nextId
        c.w, c.h = min(c.w, d.pw), min(c.h, d.ph)
        c.x = F.clamp(w.x + dx, 1, max(1, d.pw - c.w + 1))
        c.y = F.clamp(w.y + dy, 1, max(1, d.ph - c.h + 1))
        d.widgets[#d.widgets + 1] = c
        list[#list + 1] = c
    end
    UI.setSel(list)
    UI.mod()
end

function UI.order(mode)
    if not UI.need() then return end
    local d = S.dash
    local list = d.widgets
    UI.snap()
    if mode == "front" or mode == "back" then
        local a, b = {}, {}
        for _, w in ipairs(list) do
            if UI.isSel(w) then a[#a + 1] = w else b[#b + 1] = w end
        end
        local out = {}
        if mode == "front" then
            for _, w in ipairs(b) do out[#out + 1] = w end
            for _, w in ipairs(a) do out[#out + 1] = w end
        else
            for _, w in ipairs(a) do out[#out + 1] = w end
            for _, w in ipairs(b) do out[#out + 1] = w end
        end
        d.widgets = out
    elseif mode == "forward" then
        for i = #list - 1, 1, -1 do
            if UI.isSel(list[i]) and not UI.isSel(list[i + 1]) then list[i], list[i + 1] = list[i + 1], list[i] end
        end
    else
        for i = 2, #list do
            if UI.isSel(list[i]) and not UI.isSel(list[i - 1]) then list[i], list[i - 1] = list[i - 1], list[i] end
        end
    end
    UI.mod()
end

function UI.nudge(dx, dy)
    local d = S.dash
    if #S.sel == 0 then return end
    local ok = false
    for _, w in ipairs(S.sel) do
        if not w.locked then
            local nx = F.clamp(w.x + dx, 1, max(1, d.pw - w.w + 1))
            local ny = F.clamp(w.y + dy, 1, max(1, d.ph - w.h + 1))
            if nx ~= w.x or ny ~= w.y then ok = true end
        end
    end
    if not ok then return end
    if os.clock() - (S.nudgeAt or 0) > 1 then UI.snap() end
    S.nudgeAt = os.clock()
    for _, w in ipairs(S.sel) do
        if not w.locked then
            w.x = F.clamp(w.x + dx, 1, max(1, d.pw - w.w + 1))
            w.y = F.clamp(w.y + dy, 1, max(1, d.ph - w.h + 1))
        end
    end
    UI.mod()
end

function UI.nextWidget()
    local d = S.dash
    if #d.widgets == 0 then return end
    local cur = 0
    for i, x in ipairs(d.widgets) do if x == S.cur then cur = i end end
    for step = 1, #d.widgets do
        local w = d.widgets[(cur + step - 1) % #d.widgets + 1]
        if not w.hidden then UI.setSel({ w }) return end
    end
end

-- Set one field on every selected widget.
function UI.setAll(field, value)
    if not UI.need() then return end
    UI.snap()
    for _, w in ipairs(S.sel) do w[field] = value end
    UI.mod()
end
function UI.toggleAll(field, on, off)
    if not UI.need() then return end
    UI.setAll(field, (S.cur[field] == off) and on or off)
end

-- ── Editor: align and size ───────────────────────────────────────────────────
function UI.bounds(list)
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, w in ipairs(list) do
        x1, y1 = min(x1, w.x), min(y1, w.y)
        x2, y2 = max(x2, w.x + w.w - 1), max(y2, w.y + w.h - 1)
    end
    return x1, y1, x2, y2
end
function UI.align(mode)
    if not UI.need() then return end
    local d = S.dash
    local x1, y1, x2, y2 = 1, 1, d.pw, d.ph
    if #S.sel > 1 then x1, y1, x2, y2 = UI.bounds(S.sel) end
    UI.snap()
    for _, w in ipairs(S.sel) do
        if not w.locked then
            if mode == "left" then w.x = x1
            elseif mode == "hcenter" then w.x = x1 + floor((x2 - x1 + 1 - w.w) / 2)
            elseif mode == "right" then w.x = x2 - w.w + 1
            elseif mode == "top" then w.y = y1
            elseif mode == "vcenter" then w.y = y1 + floor((y2 - y1 + 1 - w.h) / 2)
            elseif mode == "bottom" then w.y = y2 - w.h + 1 end
        end
    end
    UI.clampWidgets(d)
    UI.mod()
end
function UI.distribute(horizontal)
    if #S.sel < 3 then UI.flash("Select three or more") return end
    local list = {}
    for _, w in ipairs(S.sel) do list[#list + 1] = w end
    local key = horizontal and "x" or "y"
    local size = horizontal and "w" or "h"
    table.sort(list, function(a, b) return a[key] < b[key] end)
    local first, last = list[1], list[#list]
    local total = (last[key] + last[size]) - first[key]
    local used = 0
    for _, w in ipairs(list) do used = used + w[size] end
    local gapv = (total - used) / (#list - 1)
    UI.snap()
    local pos = first[key]
    for i, w in ipairs(list) do
        if i > 1 and i < #list and not w.locked then w[key] = floor(pos + 0.5) end
        pos = pos + w[size] + gapv
    end
    UI.clampWidgets(S.dash)
    UI.mod()
end
function UI.fillDash(horizontal)
    if not UI.need() then return end
    local d = S.dash
    UI.snap()
    for _, w in ipairs(S.sel) do
        if not w.locked then
            if horizontal then w.x, w.w = 1, d.pw else w.y, w.h = 1, d.ph end
        end
    end
    UI.mod()
end
function UI.matchSize(horizontal)
    if not UI.need() or #S.sel < 2 then UI.flash("Select two or more") return end
    UI.snap()
    local ref = S.cur
    for _, w in ipairs(S.sel) do
        if w ~= ref and not w.locked then
            if horizontal then w.w = ref.w else w.h = ref.h end
        end
    end
    UI.clampWidgets(S.dash)
    UI.mod()
end
function UI.artRatio()
    local w = S.cur
    if not w or not w.art then UI.flash("Select an art piece") return end
    UI.snap()
    local ratio = (w.art.cols * 2) / (w.art.rows * 2)
    local nh = max(3, floor(w.w / ratio + 0.5))
    if nh > S.dash.ph then
        nh = S.dash.ph
        w.w = max(3, floor(nh * ratio + 0.5))
    end
    w.h = nh
    UI.clampWidgets(S.dash)
    UI.mod()
end

-- ── Editor: drawing ──────────────────────────────────────────────────────────
function UI.dashCanvas()
    local d = S.dash
    local c = S.dc
    if c and c.rev == S.rev and c.d == d and c.c.pw == d.pw and c.c.ph == d.ph then return c.c end
    local cv = D.new(d.pw, d.ph, d.bg)
    D.dash(cv, d, { live = false, st = {}, t = 0, edit = true })
    S.dc = { rev = S.rev, d = d, c = cv }
    return cv
end

function UI.drawEditor()
    local w, h = term.getSize()
    if not S.view then UI.fitView() end
    UI.fill(1, 1, w, TC.bar)
    S.tb = {}
    local x = 1
    for _, b in ipairs(UI.TOOLS) do
        local label = " " .. b[1] .. " "
        if x + #label - 1 <= w then
            UI.put(x, 1, label, TC.barText, TC.barBtn)
            S.tb[#S.tb + 1] = { x1 = x, x2 = x + #label - 1, fn = b[2] }
            x = x + #label + 1
        end
    end
    local d, v = S.dash, S.view
    local vw, vh = UI.viewSize()
    local V = D.new(vw, vh, colors.gray)
    F.blitScaled(UI.dashCanvas(), V, v.z, v.ox, v.oy, colors.gray)
    D.box(V, v.ox, v.oy, v.ox + floor(d.pw * v.z) + 1, v.oy + floor(d.ph * v.z) + 1, colors.lightGray)
    -- Grid dots at every grid crossing.
    local g = CFG.grid
    if CFG.showGrid and g * v.z >= 4 and (d.pw / g) * (d.ph / g) <= 6000 then
        for gy = 1, d.ph, g do
            local _, sy = UI.toScreen(1, gy)
            if sy >= 1 and sy <= vh then
                for gx = 1, d.pw, g do
                    local sx = UI.toScreen(gx, 1)
                    if sx >= 1 and sx <= vw then V[sy][sx] = colors.lightGray end
                end
            end
        end
    end
    -- Selection outlines.
    S.handle = nil
    for _, sw in ipairs(S.sel) do
        local x1, y1 = UI.toScreen(sw.x, sw.y)
        local x2, y2 = UI.toScreen(sw.x + sw.w, sw.y + sw.h)
        local col = (sw == S.cur) and colors.white or colors.lightBlue
        if sw.locked then col = colors.orange end
        D.box(V, x1 - 1, y1 - 1, x2, y2, col)
        if #S.sel == 1 and not sw.locked then
            D.rect(V, x2 - 1, y2 - 1, x2 + 1, y2 + 1, colors.yellow)
            S.handle = { x = x2, y = y2 }
        end
    end
    local dr = S.drag
    if dr and dr.mode == "marquee" then
        D.box(V, min(dr.x1, dr.x2), min(dr.y1, dr.y2), max(dr.x1, dr.x2), max(dr.y1, dr.y2), colors.white)
    end
    D.cells(V, term, 1, 2)
    -- Status line.
    UI.fill(1, h, w, TC.bg)
    local line
    if S.note and os.clock() - S.note.t < 3 then
        line = S.note.text
    elseif #S.sel == 1 then
        local sw = S.sel[1]
        line = W.label_of(sw) .. "  " .. sw.x .. "," .. sw.y .. "  " .. sw.w .. "x" .. sw.h
            .. (sw.locked and "  locked" or "")
    elseif #S.sel > 1 then
        line = #S.sel .. " selected"
    else
        line = d.name .. (S.dirty and "*" or "") .. "  " .. d.pw .. "x" .. d.ph .. "  F1 help"
    end
    UI.put(1, h, F.cut(line, max(0, w - 20)), TC.dim, TC.bg)
    S.zb = {}
    local bx = w - 12
    for _, b in ipairs({ { " - ", "zoomOut" }, { " + ", "zoomIn" }, { " Fit ", "zoomFit" } }) do
        UI.put(bx, h, b[1], TC.barText, TC.barBtn)
        S.zb[#S.zb + 1] = { x1 = bx, x2 = bx + #b[1] - 1, fn = b[2] }
        bx = bx + #b[1] + 1
    end
    UI.put(w - 18, h, F.pad(floor(v.z * 100 + 0.5) .. "%", 5), TC.dim, TC.bg)
end

-- ── Editor: mouse ────────────────────────────────────────────────────────────
function UI.snapv(v)
    if CFG.snap and not S.mod.ctrl then
        local g = CFG.grid
        return floor((v - 1) / g + 0.5) * g + 1
    end
    return v
end
local function pixelOf(x, y) return (x - 1) * 2 + 1, (y - 2) * 3 + 2 end

function UI.click(btn, x, y)
    local w, h = term.getSize()
    if y == 1 then
        if btn == 1 then
            for _, b in ipairs(S.tb or {}) do
                if x >= b.x1 and x <= b.x2 then return UI[b.fn]() end
            end
        end
        return
    end
    if y == h then
        if btn == 1 then
            for _, b in ipairs(S.zb or {}) do
                if x >= b.x1 and x <= b.x2 then return UI[b.fn]() end
            end
        end
        return
    end
    local sx, sy = pixelOf(x, y)
    if btn == 2 or btn == 3 then
        S.rc = { x = x, y = y, sx = sx, sy = sy, moved = false, ox = S.view.ox, oy = S.view.oy, btn = btn }
        return
    end
    local hd = S.handle
    if #S.sel == 1 and hd and abs(sx - hd.x) <= 3 and abs(sy - hd.y) <= 4 then
        S.drag = { mode = "size", ratio = S.cur.w / max(1, S.cur.h) }
        return
    end
    local dx, dy = UI.toDash(sx, sy)
    local hit = W.at(S.dash, dx, dy)
    if hit then
        if S.mod.shift then UI.toggleSel(hit) S.drag = nil return end
        local collapse
        if not UI.isSel(hit) then UI.setSel({ hit })
        elseif #S.sel > 1 then collapse = hit end
        S.cur = hit
        local now = os.clock()
        if S.lastHit == hit and now - (S.lastT or 0) < 0.4 then
            S.lastHit, S.drag = nil, nil
            return UI.props()
        end
        S.lastHit, S.lastT = hit, now
        local list = {}
        for _, sw in ipairs(S.sel) do
            if not sw.locked then list[#list + 1] = { w = sw, x = sw.x, y = sw.y } end
        end
        S.drag = { mode = "move", sx = dx, sy = dy, list = list, collapse = collapse }
    else
        S.lastHit = nil
        local base = {}
        if S.mod.shift then for i, sw in ipairs(S.sel) do base[i] = sw end else UI.setSel({}) end
        S.drag = { mode = "marquee", x1 = sx, y1 = sy, x2 = sx, y2 = sy, base = base }
    end
end

function UI.dragTo(btn, x, y)
    local sx, sy = pixelOf(x, y)
    local r = S.rc
    if r then
        if x ~= r.x or y ~= r.y then r.moved = true end
        if r.moved then
            S.view.ox, S.view.oy = r.ox + (sx - r.sx), r.oy + (sy - r.sy)
            S.view.fit = false
            UI.clampPan()
        end
        return
    end
    local dr, dash = S.drag, S.dash
    if not dr then return end
    local dx, dy = UI.toDash(sx, sy)
    if dr.mode == "move" then
        if #dr.list == 0 then return end
        local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
        for _, e in ipairs(dr.list) do
            x1, y1 = min(x1, e.x), min(y1, e.y)
            x2, y2 = max(x2, e.x + e.w.w - 1), max(y2, e.y + e.w.h - 1)
        end
        local mx, my = dx - dr.sx, dy - dr.sy
        mx = F.clamp(mx, 1 - x1, dash.pw - x2)
        my = F.clamp(my, 1 - y1, dash.ph - y2)
        if CFG.snap and not S.mod.ctrl then
            local ref = dr.list[1]
            for _, e in ipairs(dr.list) do if e.w == S.cur then ref = e end end
            mx = F.clamp(UI.snapv(ref.x + mx) - ref.x, 1 - x1, dash.pw - x2)
            my = F.clamp(UI.snapv(ref.y + my) - ref.y, 1 - y1, dash.ph - y2)
        end
        if mx == 0 and my == 0 and not dr.moved then return end
        if not dr.snapped then UI.snap() dr.snapped = true end
        dr.moved = true
        for _, e in ipairs(dr.list) do e.w.x, e.w.y = e.x + mx, e.y + my end
        UI.mod()
    elseif dr.mode == "size" then
        local w = S.cur
        if not w then return end
        local mn = W.minSize(w.kind)
        local nw, nh = dx - w.x + 1, dy - w.y + 1
        if CFG.snap and not S.mod.ctrl then
            nw = UI.snapv(w.x + nw) - w.x
            nh = UI.snapv(w.y + nh) - w.y
        end
        if S.mod.shift then nh = floor(nw / dr.ratio + 0.5) end
        if w.kind == "line" then
            if w.w >= w.h then nh = w.h else nw = w.w end
        end
        nw = F.clamp(nw, mn, max(mn, dash.pw - w.x + 1))
        nh = F.clamp(nh, mn, max(mn, dash.ph - w.y + 1))
        if nw ~= w.w or nh ~= w.h then
            if not dr.snapped then UI.snap() dr.snapped = true end
            w.w, w.h = nw, nh
            UI.mod()
        end
    else
        dr.x2, dr.y2 = sx, sy
        local ax, ay = UI.toDash(min(dr.x1, sx), min(dr.y1, sy))
        local bx, by = UI.toDash(max(dr.x1, sx), max(dr.y1, sy))
        local list = {}
        for _, sw in ipairs(dr.base) do list[#list + 1] = sw end
        for _, sw in ipairs(dash.widgets) do
            if not sw.hidden and sw.x <= bx and sw.x + sw.w - 1 >= ax and sw.y <= by and sw.y + sw.h - 1 >= ay then
                local have = false
                for _, o in ipairs(list) do if o == sw then have = true end end
                if not have then list[#list + 1] = sw end
            end
        end
        UI.setSel(list)
    end
end

function UI.release(btn, x, y)
    local r = S.rc
    if r and btn == r.btn then
        S.rc = nil
        if not r.moved and btn == 2 then return UI.context(r.x, r.y) end
        return
    end
    local dr = S.drag
    S.drag = nil
    if dr and dr.mode == "move" and not dr.moved and dr.collapse then UI.setSel({ dr.collapse }) end
end

function UI.wheel(dir, x, y)
    if y <= 1 or y >= select(2, term.getSize()) then return end
    local sx, sy = pixelOf(x, y)
    UI.zoomStep(-dir, sx, sy)
end

-- ── Editor: menus ────────────────────────────────────────────────────────────
local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end
local function setter(field, value, label)
    return { label = label, fn = function() UI.setAll(field, value) end }
end

function UI.addItems(ax, ay)
    local items = {}
    for _, k in ipairs({ "panel", "text", "button", "toggle", "lamp", "bar", "clock", "line" }) do
        items[#items + 1] = { label = cap(k), fn = function() UI.addWidget(k, nil, nil, ax, ay) end }
    end
    items[#items + 1] = { sep = true, label = "" }
    items[#items + 1] = { label = "Art", sub = function() return UI.artItems(ax, ay) end }
    return items
end
function UI.addMenu() return UI.menuAt(UI.addItems(), 1, 2) end

function UI.arrangeItems()
    return {
        { label = "Bring to front", fn = function() UI.order("front") end },
        { label = "Forward", key = "]", fn = function() UI.order("forward") end },
        { label = "Backward", key = "[", fn = function() UI.order("backward") end },
        { label = "Send to back", fn = function() UI.order("back") end },
    }
end
function UI.alignItems()
    local function a(m) return function() UI.align(m) end end
    return {
        { label = "Left", fn = a("left") }, { label = "Center", fn = a("hcenter") }, { label = "Right", fn = a("right") },
        { label = "Top", fn = a("top") }, { label = "Middle", fn = a("vcenter") }, { label = "Bottom", fn = a("bottom") },
        { sep = true, label = "" },
        { label = "Spread across", fn = function() UI.distribute(true) end, off = #S.sel < 3 },
        { label = "Spread down", fn = function() UI.distribute(false) end, off = #S.sel < 3 },
    }
end
function UI.sizeItems()
    local one = S.cur and S.cur.kind == "art" and #S.sel == 1
    return {
        { label = "Fill width", fn = function() UI.fillDash(true) end },
        { label = "Fill height", fn = function() UI.fillDash(false) end },
        { label = "Match width", fn = function() UI.matchSize(true) end, off = #S.sel < 2 },
        { label = "Match height", fn = function() UI.matchSize(false) end, off = #S.sel < 2 },
        { label = "Art aspect", fn = UI.artRatio, off = not one },
    }
end
function UI.styleItems()
    local function sub(field, list)
        local out = {}
        for _, e in ipairs(list) do out[#out + 1] = setter(field, e[2], e[1]) end
        return out
    end
    return {
        { label = "Corners", sub = sub("rd", { { "Square", 0 }, { "Round 1", 1 }, { "Round 2", 2 }, { "Round 3", 3 } }) },
        { label = "Shadow", fn = function()
            local on = S.cur.sh and false or (S.dash.bg == colors.black and colors.gray or colors.black)
            UI.setAll("sh", on)
        end },
        { label = "Reflection", sub = sub("rf", { { "Off", 0 }, { "Light", 25 }, { "Strong", 45 } }) },
        { label = "Gradient", fn = function() UI.toggleAll("gr", "vertical", "none") end },
        { label = "Font", sub = sub("fnt", { { "Small", "small" }, { "Big", "big" } }) },
        { label = "Text align", sub = sub("al", { { "Left", "left" }, { "Center", "center" }, { "Right", "right" } }) },
        { label = "Effect", sub = sub("fx", { { "None", "none" }, { "Pulse", "pulse" }, { "Blink", "blink" }, { "Rainbow", "rainbow" } }) },
    }
end

function UI.widgetItems()
    local cur = S.cur
    local items = {
        { label = "Edit...", key = "Enter", fn = UI.props },
        { label = "Rename...", fn = UI.rename, off = #S.sel > 1 },
        { sep = true, label = "" },
        { label = "Cut", key = "^X", fn = UI.cut },
        { label = "Copy", key = "^C", fn = UI.copy },
        { label = "Duplicate", key = "^D", fn = UI.dup },
        { label = "Delete", key = "Del", fn = UI.del },
        { sep = true, label = "" },
        { label = "Arrange", sub = UI.arrangeItems },
        { label = "Align", sub = UI.alignItems },
        { label = "Size", sub = UI.sizeItems },
        { label = "Style", sub = UI.styleItems },
        { label = cur.locked and "Unlock" or "Lock", fn = function() UI.toggleAll("locked", true, false) end },
        { label = cur.hidden and "Show" or "Hide", fn = function() UI.toggleAll("hidden", true, false) end },
    }
    if cur.kind == "art" and #S.sel == 1 then
        items[#items + 1] = { sep = true, label = "" }
        items[#items + 1] = { label = "Edit art...", fn = UI.editArt }
        items[#items + 1] = { label = "Recolor...", fn = UI.mapColor }
        items[#items + 1] = { label = "Reset recolor", fn = UI.resetMap, off = not cur.map }
        items[#items + 1] = { label = "Flip left-right", fn = function() UI.flipArt(true) end }
        items[#items + 1] = { label = "Flip up-down", fn = function() UI.flipArt(false) end }
        items[#items + 1] = { label = "Save to library...", fn = UI.saveToLibrary }
    end
    return items
end

function UI.canvasItems(dx, dy)
    return {
        { label = "Paste", key = "^V", fn = function() UI.paste(dx, dy) end, off = not S.clip or #S.clip == 0 },
        { label = "Select all", key = "^A", fn = UI.selectAll },
        { label = "Add", sub = function() return UI.addItems(dx, dy) end },
        { sep = true, label = "" },
        { label = "Zoom in", key = "+", fn = UI.zoomIn },
        { label = "Zoom out", key = "-", fn = UI.zoomOut },
        { label = "Fit view", key = "0", fn = UI.zoomFit },
        { label = "Actual size", key = "1", fn = function() UI.zoomTo(1) end },
        { label = CFG.showGrid and "Hide grid" or "Show grid", key = "G", fn = UI.toggleGrid },
        { label = CFG.snap and "Snap off" or "Snap on", fn = UI.toggleSnap },
        { sep = true, label = "" },
        { label = "Dashboard...", fn = UI.dashSettings },
        { label = "Run", key = "R", fn = UI.run },
        { label = "Save", key = "S", fn = UI.save },
    }
end

function UI.context(x, y)
    local sx, sy = pixelOf(x, y)
    local dx, dy = UI.toDash(sx, sy)
    local hit = W.at(S.dash, dx, dy)
    local items
    if hit then
        if not UI.isSel(hit) then UI.setSel({ hit }) else S.cur = hit end
        items = UI.widgetItems()
    else
        UI.setSel({})
        items = UI.canvasItems(dx, dy)
    end
    return UI.menuAt(items, x, y)
end

function UI.toggleGrid() CFG.showGrid = not CFG.showGrid; F.saveCfg() end
function UI.toggleSnap() CFG.snap = not CFG.snap; F.saveCfg(); UI.flash(CFG.snap and "Snap on" or "Snap off") end

function UI.rename()
    if not UI.need() then return end
    local v = UI.input("Rename", "Name", S.cur.name, 20)
    if v then UI.snap(); S.cur.name = v; UI.mod() end
end

-- ── Editor: properties ───────────────────────────────────────────────────────
function UI.props()
    if not UI.need() then return end
    local w, d = S.cur, S.dash
    local k = w.kind
    local multi = #S.sel > 1
    local mn = W.minSize(k)
    local texty = (k == "text" or k == "button" or k == "toggle" or k == "clock")
    local f = {}
    local function add(id, label, t, v, extra)
        local e = { id = id, label = label, t = t, v = v }
        if extra then for key, val in pairs(extra) do e[key] = val end end
        f[#f + 1] = e
    end
    if not multi then
        add("name", "Name", "text", w.name, { len = 20 })
        add("x", "X", "num", w.x, { min = 1, max = d.pw })
        add("y", "Y", "num", w.y, { min = 1, max = d.ph })
        add("w", "Width", "num", w.w, { min = mn, max = d.pw })
        add("h", "Height", "num", w.h, { min = mn, max = d.ph })
    end
    if texty and not multi then
        add("tx", (k == "clock") and "Format" or "Text", "text", w.tx, { len = 40 })
    end
    if k == "clock" and not multi then add("cm", "Time", "choice", w.cm, { list = CLOCKS }) end
    if texty then
        add("fnt", "Font", "choice", w.fnt, { list = FONTS })
        add("al", "Align", "choice", w.al, { list = ALIGN })
        add("sc", "Text size", "num", w.sc, { min = 0, max = 10 })
        add("sp", "Spacing", "num", w.sp, { min = 0, max = 6 })
    end
    if k == "art" then
        add("al", "Align", "choice", w.al, { list = ALIGN })
        add("am", "Fit", "choice", w.am, { list = ARTMODES })
    end
    if k == "line" and not multi then add("ls", "Style", "choice", w.ls, { list = LSTYLES }) end
    if k == "bar" and not multi then add("dir", "Fills", "choice", w.dir, { list = DIRS }) end
    add("fg", "Color", "color", w.fg)
    add("bg", "Back", "color", w.bg, { none = true })
    add("bd", "Border", "color", w.bd, { none = true })
    add("rd", "Corners", "num", w.rd, { min = 0, max = 3 })
    add("fx", "Effect", "choice", w.fx, { list = EFFECTS })
    add("fxc", (k == "toggle" or k == "lamp") and "On color" or "Effect clr", "color", w.fxc)
    if texty or k == "panel" then
        add("gr", "Gradient", "choice", w.gr, { list = GRADS })
        add("fg2", "Color 2", "color", w.fg2)
    end
    add("sh", "Shadow", "color", w.sh, { none = true })
    add("rf", "Reflect %", "num", w.rf, { min = 0, max = 60 })
    add("rc", "Reflect clr", "color", w.rc, { none = true })
    if not multi then
        if k == "button" or k == "toggle" then add("aside", "Output", "choice", w.act.side, { list = SIDES }) end
        if k == "button" then add("amode", "Action", "choice", w.act.mode, { list = MODES }) end
        if k == "lamp" or k == "bar" then
            add("sside", "Signal", "choice", w.src.side, { list = SIDES })
            add("sio", "Read", "choice", w.src.io, { list = IOS })
        end
    end
    add("locked", "Locked", "bool", w.locked)
    add("hidden", "Hidden", "bool", w.hidden)

    local r = UI.form(multi and ("Edit " .. #S.sel .. " widgets") or ("Edit " .. k), f)
    if not r then return end
    UI.snap()
    local skip = { x = true, y = true, w = true, h = true, aside = true, amode = true, sside = true, sio = true }
    for _, t in ipairs(multi and S.sel or { w }) do
        for key, val in pairs(r) do
            if not skip[key] then t[key] = val end
        end
    end
    if not multi then
        w.w, w.h = r.w, r.h
        w.x = F.clamp(r.x, 1, max(1, d.pw - w.w + 1))
        w.y = F.clamp(r.y, 1, max(1, d.ph - w.h + 1))
        if r.aside then w.act.side = r.aside end
        if r.amode then w.act.mode = r.amode end
        if r.sside then w.src.side = r.sside end
        if r.sio then w.src.io = r.sio end
    end
    UI.mod()
end

-- ── Editor: dashboard-level actions ──────────────────────────────────────────
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
        { id = "bg2", label = "Fade to", t = "color", v = d.bg2 or colors.blue },
    })
    if not r then return end
    UI.snap()
    d.pw, d.ph, d.bg, d.fx, d.bg2 = r.pw, r.ph, r.bg, r.fx, r.bg2
    UI.clampWidgets(d)
    UI.mod()
    UI.fitView()
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
    UI.mod()
    UI.fitView()
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

function UI.gridSettings()
    local r = UI.form("Grid and snap", {
        { id = "grid", label = "Grid size", t = "num", v = CFG.grid, min = 1, max = 64 },
        { id = "show", label = "Show grid", t = "bool", v = CFG.showGrid },
        { id = "snap", label = "Snap", t = "bool", v = CFG.snap },
    })
    if not r then return end
    CFG.grid, CFG.showGrid, CFG.snap = r.grid, r.show, r.snap
    F.saveCfg()
end

function UI.help()
    UI.msg(table.concat({
        "Click a widget to select it.",
        "Drag to move. Drag the yellow",
        "corner to resize (Shift keeps",
        "the shape). Drag empty space",
        "to select several. Shift+click",
        "adds to the selection.",
        "Double-click: edit.",
        "Right-click: menu for what is",
        "under the mouse.",
        "Wheel or + - 0 1: zoom.",
        "Right-drag or middle-drag: pan.",
        "Arrows nudge (Shift = a grid).",
        "Ctrl: C X V D A Z Y S",
        "G grid   [ ] order   F1 help",
    }, "\n"), "Help 1/3")
    UI.msg(table.concat({
        "ART",
        "Add > Art gives title text,",
        "presets, your library, and",
        "files from the art folder:",
        DIR .. "/art",
        "(.txt .ans .asc; ANSI colors",
        "are read). Right-click an art",
        "piece > Edit art to paint it.",
        "Recolor changes colors without",
        "touching the art itself.",
    }, "\n"), "Help 2/3")
    UI.msg(table.concat({
        "RUN",
        "Touch buttons and toggles on",
        "the monitor. Lamps and bars",
        "show redstone signals.",
        "Q or Stop leaves the run.",
    }, "\n"), "Help 3/3")
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
    return UI.menuAt({
        { label = "Run on monitor", key = "R", fn = UI.run },
        { label = "Save", key = "^S", fn = UI.save },
        { label = "Save as...", fn = UI.saveAs },
        { sep = true, label = "" },
        { label = "Dashboard...", fn = UI.dashSettings },
        { label = "Fit to monitor", fn = UI.fitMon },
        { label = "Monitor...", fn = UI.monSettings },
        { label = "Grid and snap...", fn = UI.gridSettings },
        { sep = true, label = "" },
        { label = "Select all", key = "^A", fn = UI.selectAll },
        { label = "Zoom to fit", key = "0", fn = UI.zoomFit },
        { sep = true, label = "" },
        { label = "Delete dashboard", fn = UI.deleteDash },
        { label = "Help", key = "F1", fn = UI.help },
        { label = "Close to home", key = "Q", fn = UI.close },
    }, 1, 2)
end

function UI.run()
    local under = S.under
    R.run(S.dash)
    S.under = under
    UI.resetMods()
end

-- ── Editor: keys and loop ────────────────────────────────────────────────────
function UI.editorKey(k)
    local m = S.mod
    if k == keys.leftShift or k == keys.rightShift then m.shift = true return end
    if k == keys.leftCtrl or k == keys.rightCtrl then m.ctrl = true return end
    if m.ctrl then
        if k == keys.c then UI.copy()
        elseif k == keys.x then UI.cut()
        elseif k == keys.v then UI.paste()
        elseif k == keys.d then UI.dup()
        elseif k == keys.a then UI.selectAll()
        elseif k == keys.z then UI.undo()
        elseif k == keys.y then UI.redo()
        elseif k == keys.s then UI.save() end
        return
    end
    local step = m.shift and CFG.grid or 1
    if k == keys.up or k == keys.down or k == keys.left or k == keys.right then
        local dx = (k == keys.left and -1 or 0) + (k == keys.right and 1 or 0)
        local dy = (k == keys.up and -1 or 0) + (k == keys.down and 1 or 0)
        if #S.sel > 0 then UI.nudge(dx * step, dy * step) else UI.pan(-dx * 6, -dy * 6) end
    elseif k == keys.delete or k == keys.backspace then UI.del()
    elseif k == keys.tab then UI.nextWidget()
    elseif k == keys.a then return UI.addMenu()
    elseif k == keys.e or k == keys.enter then UI.props()
    elseif k == keys.d then UI.dup()
    elseif k == keys.z then UI.undo()
    elseif k == keys.s then UI.save()
    elseif k == keys.r then UI.run()
    elseif k == keys.m then return UI.menu()
    elseif k == keys.g then UI.toggleGrid()
    elseif k == keys.leftBracket then UI.order("backward")
    elseif k == keys.rightBracket then UI.order("forward")
    elseif k == keys.f1 then UI.help()
    elseif k == keys.q then return UI.close()
    end
end
function UI.editorChar(c)
    if c == "+" or c == "=" then UI.zoomIn()
    elseif c == "-" then UI.zoomOut()
    elseif c == "0" then UI.zoomFit()
    elseif c == "1" then UI.zoomTo(1) end
end

function UI.editor(dash, isNew)
    S.dash, S.sel, S.cur, S.undo, S.redo, S.drag, S.rc = dash, {}, nil, {}, {}, nil, nil
    S.dirty = isNew and true or false
    S.dc, S.lastHit = nil, nil
    S.under = UI.drawEditor
    UI.resetMods()
    UI.fitView()
    while true do
        UI.drawEditor()
        local ev, a, b, c = os.pullEvent()
        local r
        if ev == "key" then r = UI.editorKey(a)
        elseif ev == "key_up" then
            if a == keys.leftShift or a == keys.rightShift then S.mod.shift = false
            elseif a == keys.leftCtrl or a == keys.rightCtrl then S.mod.ctrl = false end
        elseif ev == "char" then UI.editorChar(a)
        elseif ev == "mouse_click" then r = UI.click(a, b, c)
        elseif ev == "mouse_drag" then UI.dragTo(a, b, c)
        elseif ev == "mouse_up" then r = UI.release(a, b, c)
        elseif ev == "mouse_scroll" then UI.wheel(a, b, c)
        elseif ev == "term_resize" then if S.view.fit then UI.fitView() end
        end
        if r == "close" then break end
    end
    S.under = UI.clear
end

-- ── Art: building blocks ─────────────────────────────────────────────────────
-- Four quarters of a cell as a number: top-left 1, top-right 2, bottom-left 4, bottom-right 8.
local MASKCH = { [0] = " ", "▘", "▝", "▀", "▖", "▌", "▞", "▛", "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█" }

function A.quarters(a, cx, cy)
    local p = A.pattern(a.ch[cy][cx] or " ")
    local f, b = a.fg[cy][cx], a.bg[cy][cx]
    return {
        (p[1] == 1 and f or b) or false, (p[2] == 1 and f or b) or false,
        (p[3] == 1 and f or b) or false, (p[4] == 1 and f or b) or false,
    }
end
-- Turn four quarter colors into a character, a color for it, and a color behind it.
-- A cell can only hold two colors, so a third is moved to the nearest of the two.
function A.encodeQ(q, prefer)
    local list, count = {}, {}
    for i = 1, 4 do
        local c = q[i]
        if c then
            if not count[c] then count[c] = 0; list[#list + 1] = c end
            count[c] = count[c] + 1
        end
    end
    if #list == 0 then return " ", false, false end
    if #list > 2 then
        table.sort(list, function(x, y)
            if count[x] ~= count[y] then return count[x] > count[y] end
            if (x == prefer) ~= (y == prefer) then return x == prefer end
            return x < y
        end)
        local k1, k2 = list[1], list[2]
        for i = 1, 4 do
            local c = q[i]
            if c and c ~= k1 and c ~= k2 then
                q[i] = (abs((TONE[c] or 0) - (TONE[k1] or 0)) <= abs((TONE[c] or 0) - (TONE[k2] or 0))) and k1 or k2
            end
        end
        list = { k1, k2 }
    end
    local a, b = list[1], list[2]
    if b then
        -- Two colors and some empty quarters: the empty ones take the second color.
        for i = 1, 4 do if not q[i] then q[i] = b end end
    end
    local mask = 0
    for i = 1, 4 do if q[i] == a then mask = mask + 2 ^ (i - 1) end end
    mask = floor(mask)
    return MASKCH[mask], a, b or false
end
function A.setCell(a, cx, cy, ch, f, b)
    a.ch[cy][cx], a.fg[cy][cx], a.bg[cy][cx] = ch, f, b
end
function A.setQuarter(a, cx, cy, qi, color)
    if cx < 1 or cy < 1 or cx > a.cols or cy > a.rows then return end
    local q = A.quarters(a, cx, cy)
    q[qi] = color
    A.setCell(a, cx, cy, A.encodeQ(q, color))
    A.touch(a)
end
-- Art from a grid of pixels (pm[y][x] is a color or false).
function A.fromPixels(pm, pw, ph)
    local a = A.new(max(1, floor((pw + 1) / 2)), max(1, floor((ph + 1) / 2)))
    for cy = 1, a.rows do
        for cx = 1, a.cols do
            local r1, r2 = pm[cy * 2 - 1] or {}, pm[cy * 2] or {}
            local q = { r1[cx * 2 - 1] or false, r1[cx * 2] or false, r2[cx * 2 - 1] or false, r2[cx * 2] or false }
            A.setCell(a, cx, cy, A.encodeQ(q))
        end
    end
    return a
end
-- Styled title text. Top half is c1, bottom half is c2.
function A.fromText(text, fnt, c1, c2)
    text = tostring(text):upper():sub(1, 24)
    local g, gw, gh = D.font(fnt)
    local pw = max(1, #text * (gw + 1) - 1)
    local pm = {}
    for y = 1, gh + 1 do
        pm[y] = {}
        for x = 1, pw do pm[y][x] = false end
    end
    local half = floor((gh + 1) / 2)
    for i = 1, #text do
        local rows = g[text:sub(i, i)] or g["?"]
        for ry = 1, gh do
            for rx = 1, gw do
                if rows[ry]:sub(rx, rx) == "#" then
                    pm[ry][(i - 1) * (gw + 1) + rx] = (ry <= half) and c1 or (c2 or c1)
                end
            end
        end
    end
    return A.fromPixels(pm, pw, gh + 1)
end
-- Art from lines of text. color is one color or a list used row by row.
function A.fromLines(lines, color)
    local a = A.parse(table.concat(lines, "\n"), colors.white)
    for y = 1, a.rows do
        local c = type(color) == "table" and color[min(y, #color)] or color or colors.white
        for x = 1, a.cols do a.fg[y][x] = c end
    end
    A.touch(a)
    return a
end

A.PRESETS = {
    { "Heart", colors.red, {
        "▄███▄ ▄███▄",
        "███████████",
        "▀█████████▀",
        "  ▀█████▀  ",
        "    ▀█▀    " } },
    { "Star", colors.yellow, {
        "     ▄     ",
        "    ███    ",
        "▀▀███████▀▀",
        "  ▀█████▀  ",
        "  ▄██▀██▄  ",
        "  ▀▀   ▀▀  " } },
    { "Arrow right", colors.lime, {
        "      ▄▄    ",
        "████████▄▄  ",
        "██████████▄ ",
        "████████▀▀  ",
        "      ▀▀    " } },
    { "Arrow up", colors.cyan, {
        "    ▄▄    ",
        "   ████   ",
        "  ██████  ",
        " ▀▀████▀▀ ",
        "   ████   ",
        "   ████   " } },
    { "Smiley", colors.yellow, {
        "  ▄████▄  ",
        " ██▀██▀██ ",
        "██████████",
        "██▄████▄██",
        " ▀▄▄▄▄▄▀  " } },
    { "Warning", colors.orange, {
        "    ▄▄    ",
        "   ████   ",
        "  ██▀▀██  ",
        " ████████ ",
        "▄▄▄▄▄▄▄▄▄▄" } },
    { "Lightning", colors.yellow, {
        "    ▄███",
        "  ▄███▀ ",
        " ▀███▄  ",
        "   ▀██▄ ",
        "    ▀▀  " } },
    { "Rainbow bar", { colors.red, colors.orange, colors.yellow, colors.lime, colors.cyan, colors.blue, colors.purple }, {
        "████████████████████████",
        "████████████████████████",
        "████████████████████████",
        "████████████████████████",
        "████████████████████████",
        "████████████████████████",
        "████████████████████████" } },
    { "Frame", colors.lightGray, {
        "▄▄▄▄▄▄▄▄▄▄▄▄",
        "█          █",
        "█          █",
        "█          █",
        "▀▀▀▀▀▀▀▀▀▀▀▀" } },
}

-- ── Art: adding and managing ─────────────────────────────────────────────────
function UI.artItems(ax, ay)
    local items = {
        { label = "Title text...", fn = function() UI.newTitle(ax, ay) end },
        { label = "Blank canvas...", fn = function() UI.newBlank(ax, ay) end },
        { sep = true, label = "" },
        { label = "Presets", sub = function()
            local out = {}
            for _, p in ipairs(A.PRESETS) do
                out[#out + 1] = { label = p[1], fn = function()
                    UI.addWidget("art", A.fromLines(p[3], p[2]), p[1], ax, ay)
                end }
            end
            return out
        end },
        { label = "My library", sub = function()
            local out = {}
            for _, n in ipairs(F.listArt()) do
                out[#out + 1] = { label = n, fn = function()
                    local art = F.loadArt(n)
                    if art then UI.addWidget("art", art, n, ax, ay) else UI.flash("Cannot read " .. n) end
                end }
            end
            if #out == 0 then out[1] = { label = "(empty)", off = true } end
            return out
        end },
        { label = "Import file", sub = function()
            local out = {}
            for _, n in ipairs(F.listArtFiles()) do
                out[#out + 1] = { label = n, fn = function()
                    local art = F.importArt(n, colors.white)
                    if art then UI.addWidget("art", art, n:gsub("%.%w+$", ""), ax, ay) else UI.flash("Cannot read " .. n) end
                end }
            end
            if #out == 0 then out[1] = { label = "(none in art folder)", off = true } end
            return out
        end },
    }
    return items
end

function UI.newTitle(ax, ay)
    local r = UI.form("Title text", {
        { id = "tx", label = "Text", t = "text", v = "TITLE", len = 24 },
        { id = "fnt", label = "Font", t = "choice", list = FONTS, v = "big" },
        { id = "c1", label = "Top color", t = "color", v = colors.cyan },
        { id = "c2", label = "Bottom", t = "color", v = colors.lightBlue },
    })
    if not r or r.tx == "" then return end
    UI.addWidget("art", A.fromText(r.tx, r.fnt, r.c1, r.c2), r.tx:sub(1, 20), ax, ay)
end

function UI.newBlank(ax, ay)
    local r = UI.form("Blank art", {
        { id = "cols", label = "Columns", t = "num", v = 16, min = 1, max = 120 },
        { id = "rows", label = "Rows", t = "num", v = 8, min = 1, max = 60 },
    })
    if not r then return end
    local art = UI.artEdit(A.new(r.cols, r.rows))
    if art then UI.addWidget("art", art, "art", ax, ay) end
end

function UI.editArt()
    local w = S.cur
    if not w or w.kind ~= "art" then UI.flash("Select an art piece") return end
    local art = UI.artEdit(A.copy(w.art))
    if art then
        UI.snap()
        w.art = art
        UI.mod()
    end
end
function UI.flipArt(horizontal)
    local w = S.cur
    if not w or w.kind ~= "art" then return end
    UI.snap()
    w.art = A.flip(w.art, horizontal)
    UI.mod()
end
function UI.saveToLibrary()
    local w = S.cur
    if not w or w.kind ~= "art" then return end
    local name = UI.input("Save to library", "Name", w.name ~= "" and w.name or "art", 20)
    if not name then return end
    name = F.safe(name)
    if name == "" then UI.flash("Name is empty") return end
    if F.saveArt(name, w.art) then UI.flash("Saved " .. name) else UI.flash("Could not save") end
end
-- Recolor on the widget only: the art itself stays as it was.
function UI.mapColor()
    local w = S.cur
    if not w or w.kind ~= "art" then return end
    local pal = A.palette(w.art)
    if #pal == 0 then UI.flash("This art has no colors") return end
    local names = {}
    for i, c in ipairs(pal) do names[i] = CNAME[F.colorIndex(c)] .. ((w.map and w.map[c]) and (" -> " .. CNAME[F.colorIndex(w.map[c])]) or "") end
    local i = UI.pick("Recolor which color?", names)
    if not i then return end
    local r = UI.form("Recolor " .. CNAME[F.colorIndex(pal[i])], {
        { id = "to", label = "Show as", t = "color", v = (w.map and w.map[pal[i]]) or pal[i] },
    })
    if not r then return end
    UI.snap()
    w.map = w.map or {}
    if r.to == pal[i] then w.map[pal[i]] = nil else w.map[pal[i]] = r.to end
    if next(w.map) == nil then w.map = nil end
    UI.mod()
end
function UI.resetMap()
    if not S.cur or not S.cur.map then return end
    UI.snap()
    S.cur.map = nil
    UI.mod()
end

-- ── Art: the painter ─────────────────────────────────────────────────────────
-- Full-screen. Pen paints one quarter of a cell (the finest dot). Char paints a
-- whole cell with a character. Fill, Pick and Text do what they say.
-- Left button paints, right button erases.
local CHARS = {
    { "Full block", "█" }, { "Top half", "▀" }, { "Bottom half", "▄" }, { "Left half", "▌" },
    { "Right half", "▐" }, { "Light shade", "░" }, { "Medium shade", "▒" }, { "Dark shade", "▓" },
    { "Dot .", "." }, { "Colon :", ":" }, { "Dash -", "-" }, { "Bar |", "|" }, { "Hash #", "#" }, { "Space", " " },
}
local PTOOLS = { { "Pen", "pen" }, { "Char", "char" }, { "Fill", "fill" }, { "Pick", "pick" }, { "Text", "text" } }
local ZLIST = { 2, 3, 4, 6, 8 }

function UI.artEdit(art)
    local E = {
        art = art, tool = "pen", ch = "█", chname = "Full block", fg = colors.white, bg = false,
        z = 4, ox = 2, oy = 2, undo = {}, cx = 1, cy = 1, dirty = false,
    }
    local oldUnder = S.under
    local function snap()
        E.undo[#E.undo + 1] = A.copy(E.art)
        if #E.undo > 25 then table.remove(E.undo, 1) end
        E.dirty = true
    end
    local function compose()
        local px = A.px(E.art)
        local c = E.comp
        if c and c.rev == E.art.rev and c.art == E.art then return c.cv end
        local cv = D.new(px.pw, px.ph, colors.black)
        for y = 1, px.ph do
            local row, crow = px[y], cv[y]
            for x = 1, px.pw do
                local v = row[x]
                if v then crow[x] = v
                else crow[x] = (floor((x - 1) / 2) + floor((y - 1) / 2)) % 2 == 0 and colors.gray or colors.black end
            end
        end
        E.comp = { rev = E.art.rev, art = E.art, cv = cv }
        return cv
    end
    local function cellAt(x, y)
        local sx, sy = (x - 1) * 2 + 1, (y - 2) * 3 + 2
        local qx = floor((sx - E.ox - 1) / E.z) + 1
        local qy = floor((sy - E.oy - 1) / E.z) + 1
        local cx, cy = floor((qx - 1) / 2) + 1, floor((qy - 1) / 2) + 1
        if cx < 1 or cy < 1 or cx > E.art.cols or cy > E.art.rows then return nil end
        return cx, cy, (qy - 1) % 2 * 2 + (qx - 1) % 2 + 1, sx, sy
    end
    local function draw()
        local w, h = term.getSize()
        UI.fill(1, 1, w, TC.bar)
        E.tb = {}
        local x = 1
        local function btn(label, fn, on)
            local t = " " .. label .. " "
            if x + #t - 1 > w then return end
            UI.put(x, 1, t, on and TC.selText or TC.barText, on and TC.sel or TC.barBtn)
            E.tb[#E.tb + 1] = { x1 = x, x2 = x + #t - 1, fn = fn }
            x = x + #t + 1
        end
        btn("Done", "done")
        btn("Menu", "menu")
        for _, t in ipairs(PTOOLS) do btn(t[1], t[2], E.tool == t[2]) end
        local vw, vh = w * 2, (h - 3) * 3
        local V = D.new(vw, vh, colors.gray)
        F.blitScaled(compose(), V, E.z, E.ox, E.oy, colors.gray)
        D.box(V, E.ox, E.oy, E.ox + E.art.cols * 2 * E.z + 1, E.oy + E.art.rows * 2 * E.z + 1, colors.lightGray)
        if E.tool == "text" then
            local x1 = E.ox + (E.cx - 1) * 2 * E.z + 1
            local y1 = E.oy + (E.cy - 1) * 2 * E.z + 1
            D.box(V, x1 - 1, y1 - 1, x1 + 2 * E.z, y1 + 2 * E.z, colors.yellow)
        end
        D.cells(V, term, 1, 2)
        -- Palette.
        E.pal = {}
        for i = 1, 16 do
            local px1 = 1 + (i - 1) * 2
            UI.put(px1, h - 1, "  ", TC.text, ORDER[i])
            E.pal[i] = { x1 = px1, x2 = px1 + 1, c = ORDER[i] }
        end
        UI.put(33, h - 1, "--", TC.dim, TC.panel)
        E.pal[17] = { x1 = 33, x2 = 34, c = false }
        UI.put(36, h - 1, "F", TC.dim, TC.bg)
        UI.put(37, h - 1, "  ", TC.text, E.fg or TC.panel)
        UI.put(40, h - 1, "B", TC.dim, TC.bg)
        if E.bg then UI.put(41, h - 1, "  ", TC.text, E.bg) else UI.put(41, h - 1, "--", TC.dim, TC.panel) end
        UI.fill(1, h, w, TC.bg)
        local line
        if S.note and os.clock() - S.note.t < 3 then line = S.note.text
        else line = E.tool .. "  " .. E.chname .. "  " .. E.art.cols .. "x" .. E.art.rows .. "  zoom " .. E.z end
        UI.put(1, h, F.cut(line, w - 12), TC.dim, TC.bg)
        UI.put(w - 10, h, " - ", TC.barText, TC.barBtn)
        UI.put(w - 6, h, " + ", TC.barText, TC.barBtn)
        E.zb = { { x1 = w - 10, x2 = w - 8, d = -1 }, { x1 = w - 6, x2 = w - 4, d = 1 } }
    end
    S.under = draw

    local function zoom(d)
        local idx = 3
        for i, z in ipairs(ZLIST) do if z == E.z then idx = i end end
        E.z = ZLIST[F.clamp(idx + d, 1, #ZLIST)]
    end
    local function paint(cx, cy, qi, erase)
        local a = E.art
        if E.tool == "pen" then
            A.setQuarter(a, cx, cy, qi, (not erase) and E.fg or false)
        elseif E.tool == "char" then
            if erase then A.setCell(a, cx, cy, " ", false, false)
            else A.setCell(a, cx, cy, E.ch, E.fg, E.bg) end
            A.touch(a)
        end
    end
    local function flood(cx, cy, qi, erase)
        local px = A.px(E.art)
        local x0 = (cx - 1) * 2 + (qi - 1) % 2 + 1
        local y0 = (cy - 1) * 2 + floor((qi - 1) / 2) + 1
        local target = px[y0][x0]
        local color = (not erase) and E.fg or false
        if target == color then return end
        local seen, stack, hits = {}, { { x0, y0 } }, {}
        while #stack > 0 and #hits < 60000 do
            local p = table.remove(stack)
            local x, y = p[1], p[2]
            if x >= 1 and y >= 1 and x <= px.pw and y <= px.ph and px[y][x] == target and not seen[y * 1000 + x] then
                seen[y * 1000 + x] = true
                hits[#hits + 1] = p
                stack[#stack + 1] = { x + 1, y }; stack[#stack + 1] = { x - 1, y }
                stack[#stack + 1] = { x, y + 1 }; stack[#stack + 1] = { x, y - 1 }
            end
        end
        for _, p in ipairs(hits) do
            A.setQuarter(E.art, floor((p[1] - 1) / 2) + 1, floor((p[2] - 1) / 2) + 1, (p[2] - 1) % 2 * 2 + (p[1] - 1) % 2 + 1, color)
        end
    end
    local function pickAt(cx, cy, qi, second)
        local c = A.quarters(E.art, cx, cy)[qi]
        if second then E.bg = c else if c then E.fg = c end end
    end
    local function stroke(btn, x, y, first)
        local cx, cy, qi = cellAt(x, y)
        if not cx then return end
        local erase = (btn == 2)
        if E.tool == "pen" or E.tool == "char" then
            if first then snap() end
            paint(cx, cy, qi, erase)
        elseif first and E.tool == "fill" then
            snap()
            flood(cx, cy, qi, erase)
        elseif first and E.tool == "pick" then
            pickAt(cx, cy, qi, btn == 2)
        elseif first and E.tool == "text" then
            E.cx, E.cy = cx, cy
        end
    end
    local function write(ch)
        if E.cx > E.art.cols then return end
        snap()
        A.setCell(E.art, E.cx, E.cy, ch, E.fg, E.bg)
        A.touch(E.art)
        if E.cx < E.art.cols then E.cx = E.cx + 1 end
    end
    local function pickChar()
        local names = {}
        for i, c in ipairs(CHARS) do names[i] = c[1] end
        names[#names + 1] = "Type one..."
        local i = UI.pick("Character", names)
        if not i then return end
        if CHARS[i] then
            E.ch, E.chname = CHARS[i][2], CHARS[i][1]
        else
            local v = UI.input("Character", "Char", "", 1)
            if v and #v == 1 then E.ch, E.chname = v, "'" .. v .. "'" end
        end
        E.tool = "char"
    end
    local function resize()
        local r = UI.form("Art size", {
            { id = "cols", label = "Columns", t = "num", v = E.art.cols, min = 1, max = 120 },
            { id = "rows", label = "Rows", t = "num", v = E.art.rows, min = 1, max = 60 },
        })
        if not r then return end
        snap()
        E.art = A.resize(E.art, r.cols, r.rows)
        E.cx, E.cy = 1, 1
    end
    local function recolor()
        local pal = A.palette(E.art)
        if #pal == 0 then UI.flash("No colors yet") return end
        local names = {}
        for i, c in ipairs(pal) do names[i] = CNAME[F.colorIndex(c)] end
        local i = UI.pick("Replace which color?", names)
        if not i then return end
        local r = UI.form("Replace " .. names[i], { { id = "to", label = "With", t = "color", v = pal[i] } })
        if not r then return end
        snap()
        A.replace(E.art, pal[i], r.to)
    end
    local function undo()
        if #E.undo == 0 then UI.flash("Nothing to undo") return end
        E.art = table.remove(E.undo)
    end
    local function menu()
        local result
        local it = UI.popup({
            { label = "Character...", fn = pickChar },
            { label = "Size...", fn = resize },
            { label = "Replace color...", fn = recolor },
            { label = "Flip left-right", fn = function() snap(); E.art = A.flip(E.art, true) end },
            { label = "Flip up-down", fn = function() snap(); E.art = A.flip(E.art, false) end },
            { label = "Clear all", fn = function()
                if UI.ask("Clear everything?") then snap(); E.art = A.new(E.art.cols, E.art.rows) end
            end },
            { label = "Undo", key = "^Z", fn = undo },
            { sep = true, label = "" },
            { label = "Cancel changes", fn = function()
                if not E.dirty or UI.ask("Throw away changes?") then result = "cancel" end
            end },
        }, 1, 2)
        UI.resetMods()
        if it and it.fn then it.fn() end
        return result
    end

    local drag, last
    local result
    while true do
        draw()
        local ev, a, b, c = os.pullEvent()
        local act
        if ev == "mouse_click" then
            if c == 1 then
                for _, t in ipairs(E.tb) do if b >= t.x1 and b <= t.x2 then act = t.fn end end
            elseif c == select(2, term.getSize()) then
                for _, t in ipairs(E.zb) do if b >= t.x1 and b <= t.x2 then zoom(t.d) end end
            elseif c == select(2, term.getSize()) - 1 then
                for i, p in ipairs(E.pal) do
                    if b >= p.x1 and b <= p.x2 then
                        if a == 1 then E.fg = p.c or E.fg else E.bg = p.c end
                    end
                end
            elseif a == 1 or a == 2 then
                drag = a
                stroke(a, b, c, true)
                last = { b, c }
            elseif a == 3 then
                drag = 3
                last = { b, c }
            end
        elseif ev == "mouse_drag" then
            if drag == 3 then
                E.ox = E.ox + (b - last[1]) * 2
                E.oy = E.oy + (c - last[2]) * 3
                last = { b, c }
            elseif drag and (E.tool == "pen" or E.tool == "char") then
                local steps = max(abs(b - last[1]), abs(c - last[2])) * 3
                for i = 1, max(1, steps) do
                    local t = i / max(1, steps)
                    stroke(drag, floor(last[1] + (b - last[1]) * t + 0.5), floor(last[2] + (c - last[2]) * t + 0.5), false)
                end
                last = { b, c }
            end
        elseif ev == "mouse_up" then
            drag = nil
        elseif ev == "mouse_scroll" then
            zoom(-a)
        elseif ev == "char" and E.tool == "text" then
            if a:byte() >= 32 and a:byte() < 127 then write(a) end
        elseif ev == "char" then
            if a == "+" or a == "=" then zoom(1) elseif a == "-" then zoom(-1) end
        elseif ev == "key" then
            if a == keys.leftCtrl or a == keys.rightCtrl then S.mod.ctrl = true
            elseif S.mod.ctrl then
                if a == keys.z then undo() end
            elseif a == keys.escape then act = "menu"
            elseif E.tool == "text" then
                if a == keys.left then E.cx = max(1, E.cx - 1)
                elseif a == keys.right then E.cx = min(E.art.cols, E.cx + 1)
                elseif a == keys.up then E.cy = max(1, E.cy - 1)
                elseif a == keys.down then E.cy = min(E.art.rows, E.cy + 1)
                elseif a == keys.enter then E.cy = min(E.art.rows, E.cy + 1); E.cx = 1
                elseif a == keys.backspace then
                    E.cx = max(1, E.cx - 1)
                    snap()
                    A.setCell(E.art, E.cx, E.cy, " ", false, false)
                    A.touch(E.art)
                end
            else
                if a == keys.left then E.ox = E.ox + 6 elseif a == keys.right then E.ox = E.ox - 6
                elseif a == keys.up then E.oy = E.oy + 6 elseif a == keys.down then E.oy = E.oy - 6 end
            end
        elseif ev == "key_up" then
            if a == keys.leftCtrl or a == keys.rightCtrl then S.mod.ctrl = false end
        end
        if act == "done" then result = "done"
        elseif act == "menu" then
            local r = menu()
            if r == "cancel" then result = "cancel" end
        elseif act then
            E.tool = act
        end
        if result then break end
    end
    S.under = oldUnder
    UI.resetMods()
    if result == "cancel" then return nil end
    return E.art
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
    local animated = dash.fx == "stars"
    local hasClock = false
    for _, w in ipairs(dash.widgets) do
        if w.fx ~= "none" then animated = true end
        if w.kind == "clock" then hasClock = true end
    end

    local function header()
        local tw, th = term.getSize()
        UI.clear()
        UI.fill(1, 1, tw, TC.bar)
        UI.put(2, 1, F.cut("Running " .. dash.name .. (mon and (" on " .. mname) or " (preview)"), tw - 9), TC.barText, TC.bar)
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
    UI.fill(1, 1, w, TC.bar)
    UI.put(2, 1, "Pixel Dash", TC.barText, TC.bar)
    local title = "PIXEL DASH"
    local vw, vh = w * 2, 12
    local sc = 2
    if D.textWidth(title, sc, "small", 0) > vw - 4 then sc = 1 end
    local tw = D.textWidth(title, sc, "small", 0)
    local V = D.new(vw, vh, TC.bg)
    local L = D.layer(vw, vh)
    D.text(L, title, floor((vw - tw) / 2) + 1, 2, sc, colors.white, "small", 0)
    D.gradLayer(L, TC.line, TC.accent)
    for y = 1, vh do
        for x = 1, vw do if L[y][x] then V[y][x] = L[y][x] end end
    end
    D.cells(V, term, 1, 3)
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
    t.tx, t.fg, t.fnt = "PIXEL DASH", colors.cyan, "big"
    t.w = min(pw - 4, 80)
    t.h = min(14, ph - 2)
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
    F.ensure(DIR .. "/art")
    F.loadCfg()
    UI.loadTheme()
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

if rawget(_G, "__PD_TEST") then
    return { F = F, D = D, W = W, A = A, U = U, UI = UI, R = R, S = S, CFG = CFG, TC = TC, main = main }
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
