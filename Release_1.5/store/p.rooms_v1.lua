--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Audio
-- Prismarine Rooms
--@prismarine-api
-- prismarine: background pixelbox rooms
-- Chat for the people on your Minecraft server. A Room lives on the computer of
-- its host. Channels, private messages, roles, reactions and files. Colors follow
-- the OS theme. Press F1 in the app for help.
-- ── Shared helpers (theme, drawing, input) ──────────────────────────────────
local floor = math.floor
local FALLBACK = {
    bg = colors.black, panel = colors.black, hdr = colors.blue, text = colors.white,
    dim = colors.lightGray, line = colors.cyan, sel = colors.lightBlue, selText = colors.black,
    bar = colors.gray, barBtn = colors.blue, barText = colors.white, ok = colors.lime,
    warn = colors.yellow, err = colors.red, accent = colors.orange, hint = colors.lightGray,
    info = colors.cyan,
}
local C = {}
local TONE = {}

local function osColors()
    local ok, c = pcall(function()
        local p = rawget(_G, "prismarine")
        local t = (p and p.theme) or (api and api.theme)
        return t and t.colors
    end)
    if ok then return c end
    return nil
end

local DEFAULT_TONE = {
    [colors.white] = 0.94, [colors.orange] = 0.72, [colors.magenta] = 0.55, [colors.lightBlue] = 0.6,
    [colors.yellow] = 0.85, [colors.lime] = 0.7, [colors.pink] = 0.7, [colors.gray] = 0.3,
    [colors.lightGray] = 0.6, [colors.cyan] = 0.55, [colors.purple] = 0.33, [colors.blue] = 0.28,
    [colors.brown] = 0.31, [colors.green] = 0.45, [colors.red] = 0.4, [colors.black] = 0.07,
}
local ALL_COLORS = {
    colors.black, colors.gray, colors.brown, colors.blue, colors.purple, colors.red, colors.green,
    colors.cyan, colors.magenta, colors.lightGray, colors.lightBlue, colors.pink, colors.lime,
    colors.orange, colors.yellow, colors.white,
}
local function tone(col) return TONE[col] or DEFAULT_TONE[col] or 0.5 end
local function gap(a, b) return math.abs(tone(a) - tone(b)) end
local function standout(bg, need, prefs)
    for _, c in ipairs(prefs or {}) do
        if c and gap(c, bg) >= need then return c end
    end
    local best, bestGap = colors.white, -1
    for _, c in ipairs(ALL_COLORS) do
        local g = gap(c, bg)
        if g > bestGap then best, bestGap = c, g end
    end
    return best
end
local function ensure(role, against, need, prefs)
    if gap(C[role], C[against]) < need then C[role] = standout(C[against], need, prefs) end
end

local function loadTheme()
    local src = osColors()
    for role, default in pairs(FALLBACK) do
        local v
        if src then
            local ok, got = pcall(function() return src[role] end)
            if ok then v = got end
        end
        C[role] = (type(v) == "number" and DEFAULT_TONE[v]) and v or default
    end
    for i = 0, 15 do
        local slot = 2 ^ i
        local ok, r, g, b = pcall(term.getPaletteColor, slot)
        if ok and r then TONE[slot] = 0.3 * r + 0.59 * g + 0.11 * b end
    end
    for _, bgRole in ipairs({ "bg", "panel" }) do
        ensure("text", bgRole, 0.4, { C.text, colors.white, colors.black })
        ensure("hint", bgRole, 0.25, { C.hint, C.dim, C.text })
        ensure("line", bgRole, 0.25, { C.line, C.accent, C.sel, C.text })
        ensure("accent", bgRole, 0.25, { C.accent, C.line, C.text })
        ensure("ok", bgRole, 0.25, { C.ok, C.line, C.text })
        ensure("warn", bgRole, 0.25, { C.warn, C.accent, C.text })
        ensure("err", bgRole, 0.2, { C.err, C.warn, C.text })
        ensure("info", bgRole, 0.25, { C.info, C.line, C.text })
    end
    if gap(C.sel, C.bg) < 0.12 or gap(C.sel, C.panel) < 0.12 then
        C.sel = standout(C.bg, 0.3, { C.line, C.accent, colors.lightGray })
    end
    ensure("selText", "sel", 0.4, { colors.black, colors.white })
    ensure("barText", "bar", 0.4, { C.text, colors.white, colors.black })
    ensure("barText", "barBtn", 0.3, { C.barText, colors.white, colors.black })
    C.guide = (gap(C.bar, C.bg) >= 0.12) and C.bar or C.hint
    -- A side rail color that stands a little apart from the main area.
    C.rail = (gap(C.panel, C.bg) >= 0.06) and C.panel or C.bar
    if gap(C.rail, C.bg) < 0.04 then C.rail = C.guide end
    -- Name colors: distinct theme colors that read on the background.
    local pool, seen = {}, {}
    for _, col in ipairs({ C.line, C.accent, C.ok, C.warn, C.info, C.sel, C.text, C.err, C.barBtn }) do
        if col and not seen[col] and gap(col, C.bg) >= 0.2 then
            seen[col] = true
            pool[#pool + 1] = col
        end
    end
    for _, col in ipairs(ALL_COLORS) do
        if #pool >= 5 then break end
        if not seen[col] and gap(col, C.bg) >= 0.3 then seen[col] = true; pool[#pool + 1] = col end
    end
    if #pool < 3 then
        local rest = {}
        for _, col in ipairs(ALL_COLORS) do if not seen[col] then rest[#rest + 1] = col end end
        table.sort(rest, function(a, b) return gap(a, C.bg) > gap(b, C.bg) end)
        for i = 1, 3 - #pool do pool[#pool + 1] = rest[i] end
    end
    C.names = pool
end
loadTheme()

local W, H = term.getSize()
local win
local hits = {}
local osApi = rawget(_G, "prismarine")

local function nowSec() return os.epoch("utc") / 1000 end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function fit(s, n)
    s = tostring(s)
    if n <= 0 then return "" end
    if #s > n then return s:sub(1, math.max(0, n - 1)) .. "~" end
    return s
end
local function pad(text, width)
    if width <= 0 then return "" end
    text = tostring(text):sub(1, width)
    return text .. string.rep(" ", width - #text)
end
local function hash(s)
    local h = 5381
    s = tostring(s)
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end
local function put(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end
local function fill(x, y, w, fg, bg)
    if w > 0 then put(x, y, string.rep(" ", w), fg or C.text, bg or C.bg) end
end
local function addHit(x1, x2, y, k, y2) hits[#hits + 1] = { x1 = x1, x2 = x2, y = y, y2 = y2 or y, k = k, i = #hits + 1 } end
local function hitAt(x, y)
    for i = #hits, 1, -1 do
        local h = hits[i]
        if x >= h.x1 and x <= h.x2 and y >= h.y and y <= h.y2 then return h end
    end
end

-- Sub-pixel canvas: 2x3 pixels per cell.
local function newCanvas(cw, ch)
    local c = { cw = cw, ch = ch, pw = cw * 2, ph = ch * 3 }
    for y = 1, c.ph do
        local row = {}
        for x = 1, c.pw do row[x] = false end
        c[y] = row
    end
    return c
end
local function rect(c, x1, y1, x2, y2, col)
    for y = math.max(1, floor(y1)), math.min(c.ph, floor(y2)) do
        local row = c[y]
        for x = math.max(1, floor(x1)), math.min(c.pw, floor(x2)) do row[x] = col end
    end
end
local function dot(c, x, y, col)
    x, y = floor(x), floor(y)
    if x >= 1 and y >= 1 and x <= c.pw and y <= c.ph then c[y][x] = col end
end

local function renderOwn(c, x0, y0, bg)
    bg = bg or C.bg
    local blit = colors.toBlit
    for cy = 1, c.ch do
        local chars, fgs, bgs = {}, {}, {}
        local py = (cy - 1) * 3
        local r1, r2, r3 = c[py + 1], c[py + 2], c[py + 3]
        for cx = 1, c.cw do
            local px = (cx - 1) * 2
            local p = {
                r1[px + 1] or bg, r1[px + 2] or bg, r2[px + 1] or bg,
                r2[px + 2] or bg, r3[px + 1] or bg, r3[px + 2] or bg,
            }
            local counts, order = {}, {}
            for i = 1, 6 do
                local k = p[i]
                if not counts[k] then counts[k] = 0; order[#order + 1] = k end
                counts[k] = counts[k] + 1
            end
            local ch, fg, back
            if #order == 1 then
                ch, fg, back = " ", order[1], order[1]
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
                    else isB = math.abs((TONE[k] or 0) - (TONE[b] or 0)) < math.abs((TONE[k] or 0) - (TONE[a] or 0)) end
                    if i == 6 then last = isB
                    elseif isB then bits = bits + 2 ^ (i - 1) end
                end
                if last then ch, fg, back = string.char(128 + (31 - bits)), a, b
                else ch, fg, back = string.char(128 + bits), b, a end
            end
            chars[cx], fgs[cx], bgs[cx] = ch, blit(fg), blit(back)
        end
        term.setCursorPos(x0, y0 + cy - 1)
        term.blit(table.concat(chars), table.concat(fgs), table.concat(bgs))
    end
end

local PBM = nil
do
    local ok, m = pcall(function() return osApi and osApi.pixelbox end)
    if ok and type(m) == "table" and type(m.new) == "function" then PBM = m end
end
local pbCache, pbCount = {}, 0
local function renderPB(c, x0, y0, bg)
    bg = bg or C.bg
    local key = c.cw .. "x" .. c.ch .. "@" .. x0 .. "," .. y0
    local e = pbCache[key]
    if not e then
        local sub = window.create(term.current(), x0, y0, c.cw, c.ch, true)
        local bx, why = PBM.new(sub, bg)
        if not bx then error(why or "no box", 0) end
        if pbCount >= 40 then pbCache, pbCount = {}, 0 end
        e = { box = bx }
        pbCache[key] = e
        pbCount = pbCount + 1
    end
    local cv = e.box.canvas
    for y = 1, c.ph do
        local src, dst = c[y], cv[y]
        for x = 1, c.pw do dst[x] = src[x] or bg end
    end
    e.box:render()
end
local function render(c, x0, y0, bg)
    if PBM then
        if pcall(renderPB, c, x0, y0, bg) then return end
        PBM = nil
    end
    renderOwn(c, x0, y0, bg)
end

local function header(title, context, right)
    put(1, 1, string.rep(" ", W), C.barText, C.bar)
    local chipText = " " .. title .. " "
    put(1, 1, chipText, C.barText, C.barBtn)
    local x = #chipText + 2
    local hasRight = right and right ~= ""
    if hasRight then
        right = fit(right, math.max(0, W - x - 2))
        put(W - #right, 1, right, C.hint, C.bar)
    end
    if context and context ~= "" then
        local room = W - x - (hasRight and (#right + 2) or 0)
        put(x, 1, fit(context, room), C.barText, C.bar)
    end
end
local function hintLine(y, list, withHits)
    put(1, y, string.rep(" ", W), C.hint, C.bg)
    local x = 2
    for _, it in ipairs(list) do
        local key, label = it[1], it[2]
        local need = #key + 1 + #label
        if x + need - 1 > W then break end
        put(x, y, key, C.line, C.bg)
        put(x + #key + 1, y, label, C.hint, C.bg)
        if withHits and it[3] then addHit(x, x + need - 1, y, it[3]) end
        x = x + need + 2
    end
end
local function box(x, y, w, h, bg)
    if w < 3 or h < 2 then return end
    for r = 0, h - 1 do
        if r == 0 or r == h - 1 then
            put(x, y + r, string.rep(" ", w), C.text, C.line)
        else
            put(x, y + r, " ", C.text, C.line)
            put(x + 1, y + r, string.rep(" ", w - 2), C.text, bg or C.panel)
            put(x + w - 1, y + r, " ", C.text, C.line)
        end
    end
end
-- A small button. Returns its width.
local function button(x, y, label, k, on)
    local t = " " .. label .. " "
    put(x, y, t, on and C.selText or C.barText, on and C.sel or C.barBtn)
    addHit(x, x + #t - 1, y, k)
    return #t
end
-- Text a person types, with a cursor. st = { text, pos }.
local function editKey(st, key)
    local t = st.text
    st.pos = clamp(st.pos or #t, 0, #t)
    if key == keys.backspace then
        if st.pos > 0 then st.text = t:sub(1, st.pos - 1) .. t:sub(st.pos + 1); st.pos = st.pos - 1 end
    elseif key == keys.delete then
        st.text = t:sub(1, st.pos) .. t:sub(st.pos + 2)
    elseif key == keys.left then st.pos = math.max(0, st.pos - 1)
    elseif key == keys.right then st.pos = math.min(#t, st.pos + 1)
    elseif key == keys.home then st.pos = 0
    elseif key == keys["end"] then st.pos = #t
    else return false end
    return true
end
local function editChar(st, ch, maxLen)
    local t = st.text
    st.pos = clamp(st.pos or #t, 0, #t)
    if #t + #ch > (maxLen or 400) then return end
    st.text = t:sub(1, st.pos) .. ch .. t:sub(st.pos + 1)
    st.pos = st.pos + #ch
end
-- Draws a one-line field. Returns nothing. The visible part follows the cursor.
local function fieldDraw(x, y, w, st, fg, bg, mask, nocursor)
    local t = st.text
    if mask then t = string.rep("*", #t) end
    local pos = clamp(st.pos or #t, 0, #t)
    local view = w - 1
    local start = math.max(0, pos - view + 1)
    local shown = t:sub(start + 1, start + view)
    put(x, y, pad(shown, w), fg, bg)
    local cx = x + (pos - start)
    if not nocursor and cx <= x + w - 1 then put(cx, y, (t:sub(pos + 1, pos + 1) ~= "" and t:sub(pos + 1, pos + 1) or " "), bg, fg) end
end
local function fmtClock(ts)
    local ok, s = pcall(os.date, "%H:%M", math.floor(ts))
    if ok and s then return s end
    return "--:--"
end
local function fmtAgo(sec)
    sec = math.max(0, sec)
    if sec < 60 then return floor(sec) .. "s" end
    if sec < 3600 then return floor(sec / 60) .. "m" end
    if sec < 86400 then return floor(sec / 3600) .. "h" end
    return floor(sec / 86400) .. "d"
end
local function fmtSize(n)
    if n < 1024 then return n .. " B" end
    if n < 1048576 then return string.format("%.1f KB", n / 1024) end
    return string.format("%.1f MB", n / 1048576)
end
local function readAll(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local f = fs.open(path, "rb")
    if not f then return nil end
    local s = f.readAll()
    f.close()
    return s
end
local function writeAll(path, data)
    local f = fs.open(path, "wb")
    if not f then return false end
    f.write(data)
    f.close()
    return true
end
local function loadTable(path)
    local s = readAll(path)
    if not s then return nil end
    local ok, t = pcall(textutils.unserialize, s)
    if ok and type(t) == "table" then return t end
    return nil
end
local function saveTable(path, t)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then pcall(fs.makeDir, dir) end
    local tmp = path .. ".tmp"
    if writeAll(tmp, textutils.serialize(t, { compact = true })) then
        pcall(fs.delete, path)
        return pcall(fs.move, tmp, path)
    end
    return false
end
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64dec = {}
for i = 1, 64 do b64dec[B64:byte(i)] = i - 1 end
local function b64enc(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2, c3, c4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end
local function b64dc(s)
    local out = {}
    for i = 1, #s, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local n = (b64dec[a] or 0) * 262144 + (b64dec[b] or 0) * 4096 + (b64dec[c] or 0) * 64 + (b64dec[d] or 0)
        out[#out + 1] = string.char(floor(n / 65536) % 256)
        if c ~= 61 then out[#out + 1] = string.char(floor(n / 256) % 256) end
        if d ~= 61 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end
local function randHex(n)
    local t = {}
    for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
    return table.concat(t)
end

-- ── Pixel font (3 or 5 wide, 5 tall) for titles ─────────────────────────────
local FONT = {
    R = { "##.", "#.#", "##.", "#.#", "#.#" }, O = { ".#.", "#.#", "#.#", "#.#", ".#." },
    M = { "#...#", "##.##", "#.#.#", "#...#", "#...#" }, S = { ".##", "#..", ".#.", "..#", "##." },
    P = { "##.", "#.#", "##.", "#..", "#.." }, I = { "###", ".#.", ".#.", ".#.", "###" },
    X = { "#.#", "#.#", ".#.", "#.#", "#.#" }, E = { "###", "#..", "##.", "#..", "###" },
    L = { "#..", "#..", "#..", "#..", "###" }, D = { "##.", "#.#", "#.#", "#.#", "##." },
    A = { ".#.", "#.#", "###", "#.#", "#.#" }, H = { "#.#", "#.#", "###", "#.#", "#.#" },
    [" "] = { "..", "..", "..", "..", ".." },
}
local function fontWidth(text, scale)
    local w = 0
    for i = 1, #text do
        local g = FONT[text:sub(i, i)]
        if g then w = w + #g[1] + 1 end
    end
    return math.max(0, w - 1) * (scale or 1)
end
-- Draws the text on a canvas. colorAt(px, py) gives each lit pixel its color.
local function fontDraw(c, text, x, y, scale, colorAt)
    scale = scale or 1
    local cx = x
    for i = 1, #text do
        local g = FONT[text:sub(i, i)]
        if g then
            for ry = 1, 5 do
                local row = g[ry]
                for rx = 1, #row do
                    if row:sub(rx, rx) == "#" then
                        for sy = 0, scale - 1 do
                            for sx = 0, scale - 1 do
                                local px, py = cx + (rx - 1) * scale + sx, y + (ry - 1) * scale + sy
                                dot(c, px, py, colorAt and colorAt(px, py) or C.text)
                            end
                        end
                    end
                end
            end
            cx = cx + (#g[1] + 1) * scale
        end
    end
end
-- A small identicon: mirrored pixels from a name. cw x ch cells.
local function identicon(x, y, cw, ch, name, bgc)
    local h = hash(name)
    local c = newCanvas(cw, ch)
    local pool = C.names
    local a = pool[(h % #pool) + 1] or C.line
    local b = pool[(floor(h / 7) % #pool) + 1] or C.accent
    if a == b then b = C.text end
    local back = bgc or a
    rect(c, 1, 1, c.pw, c.ph, back)
    local half = floor((c.pw + 1) / 2)
    local seed = h
    for py = 1, c.ph do
        for px = 1, half do
            seed = (seed * 1103515245 + 12345) % 2147483648
            if floor(seed / 65536) % 2 == 0 then
                local col = (px + py) % 3 == 0 and b or C.text
                if back == col then col = C.bg end
                c[py][px] = col
                c[py][c.pw - px + 1] = col
            end
        end
    end
    renderOwn(c, x, y, back)
end

-- ── Rooms: data, protocol, host and client logic ────────────────────────────
local DATA = "rooms_data"
local VERSION = "1"
local ROLE_NAME = { [0] = "Member", [1] = "Mod", [2] = "Admin", [3] = "Owner" }
local REACT = { "+1", "<3", "GG", "LOL", "!!", "?", "-1", "ok" }
local REACT_OK = {}
for _, e in ipairs(REACT) do REACT_OK[e] = true end
local MAXMEM, MAXTEXT, MAXHIST = 40, 600, 300
local FILE_CHUNK = 4500

local rm = osApi and osApi.rooms        -- the OS network chat capability
local R = {
    cfg = { name = nil, host = {}, joined = {}, ui = {} },
    me = nil,               -- { id, name, ipk, xpk, fp }
    loop = {},              -- packets this computer sends to itself
    dirty = false,          -- screen needs drawing
    notes = {},             -- short messages for the person
    found = {},             -- beacons heard: key -> info
    info = nil,             -- reply to a hello
    listenKey = "",
}

local function str(v, n) if type(v) == "string" and #v <= (n or 200) then return v end end
local function int(v, lo, hi)
    if type(v) == "number" and v % 1 == 0 and v >= (lo or 0) and v <= (hi or 2147483647) then return v end
end
local function cleanName(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[^%w_%-%. ]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    s = s:sub(1, 20)
    if #s < 2 then return nil end
    return s
end
local function cleanText(s, n)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:sub(1, n or MAXTEXT)
    if #s < 1 then return nil end
    return s
end
local function cleanChan(s)
    if type(s) ~= "string" then return nil end
    s = s:lower():gsub("[^a-z0-9_%-]", "-"):gsub("^%-+", ""):sub(1, 16)
    if #s < 1 then return nil end
    return s
end
local function isHex(v, n) return type(v) == "string" and #v == n and v:match("^%x+$") ~= nil end
local function safeFile(s)
    s = tostring(s or ""):gsub("[^%w%._%- ]", "_"):gsub("^[%.%s]+", ""):sub(1, 40)
    if s == "" then s = "file" end
    return s
end
local function note(text, kind)
    R.notes[#R.notes + 1] = { text = text, kind = kind or "info", t = nowSec() }
    if #R.notes > 4 then table.remove(R.notes, 1) end
    R.dirty = true
end
local function mix(s)
    local a, b = 5381, 52711
    for i = 1, #s do
        local c = s:byte(i)
        a = (a * 33 + c) % 4294967291
        b = (b * 131 + c + a) % 4294967279
    end
    return string.format("%08x%08x", a, b)
end
local function pwHash(salt, pw)
    local h = salt .. pw
    for _ = 1, 600 do h = mix(h .. salt) end
    return h
end
local function deepCopy(t, depth)
    if type(t) ~= "table" or (depth or 0) > 6 then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = deepCopy(v, (depth or 0) + 1) end
    return o
end
local function ser(t) return textutils.serialize(t, { compact = true }) end

-- ── Files on disk ────────────────────────────────────────────────────────────
local function ensureDir(p) if not fs.exists(p) then pcall(fs.makeDir, p) end end
local function hostPath(rid) return DATA .. "/host_" .. rid .. ".dat" end
local function histPath(rid, ch) return DATA .. "/hh_" .. rid .. "_" .. ch .. ".dat" end
local function clientPath() return DATA .. "/client.dat" end
local function cacheName(rid) return DATA .. "/c_" .. rid .. ".dat" end
local function filePath(rid, fid) return DATA .. "/files/" .. rid .. "_" .. fid end

-- ── Network ──────────────────────────────────────────────────────────────────
local Net = {}

function Net.refreshMe()
    if rm and rm.me then
        local ok, me = pcall(rm.me)
        if ok and type(me) == "table" then R.me = me; return me end
    end
    return R.me
end

-- tbl goes to a computer id. To this computer it goes through the loop queue.
function Net.send(toId, tbl)
    if not R.me then return false, "offline" end
    tbl.v = 1
    local body = ser(tbl)
    if #body > 8000 then return false, "too big" end
    if toId == R.me.id then
        R.loop[#R.loop + 1] = { from = R.me.id, ipk = R.me.ipk, xpk = R.me.xpk, t = textutils.unserialize(body) }
        return true
    end
    if not rm then return false, "no network" end
    local ok, a, b = pcall(rm.send, toId, body)
    if not ok then return false, tostring(a) end
    if a == false or a == nil then return false, b or "failed" end
    return true
end

-- A packet whose body is already built (a batch of events).
function Net.sendRaw(toId, body)
    if #body > 8000 then return false, "too big" end
    if toId == R.me.id then
        local t = textutils.unserialize(body)
        R.loop[#R.loop + 1] = { from = R.me.id, ipk = R.me.ipk, xpk = R.me.xpk, t = t }
        return true
    end
    if not rm then return false, "no network" end
    local ok, a, b = pcall(rm.send, toId, body)
    if not ok then return false, tostring(a) end
    if a == false or a == nil then return false, b or "failed" end
    return true
end

function Net.broadcast(tbl)
    if not rm or not R.me then return end
    tbl.v = 1
    pcall(rm.send, nil, ser(tbl))
end

-- Which sender ids the OS hands us. Joined hosts, or everyone while looking.
function Net.listen(all)
    if not rm then return end
    local ids = {}
    if not all then
        for _, c in pairs(R.rooms) do
            if c.hostId and c.hostId ~= (R.me and R.me.id) then ids[#ids + 1] = c.hostId end
        end
        for _, c in pairs(R.dmPeers or {}) do ids[#ids + 1] = c end
        table.sort(ids)
    end
    local key = all and "*" or table.concat(ids, ",")
    if key == R.listenKey then return end
    R.listenKey = key
    pcall(rm.listen, all and nil or ids)
end

-- ── Host ─────────────────────────────────────────────────────────────────────
local Host = { rooms = {}, outq = {}, nextBeacon = 0, nextSave = 0, rate = {} }
R.Host = Host

local ROLE_MOD, ROLE_ADMIN, ROLE_OWNER = 1, 2, 3

local function hostSave(room, force)
    local meta = {
        rid = room.rid, name = room.name, owner = room.owner, created = room.created, mode = room.mode,
        pw = room.pw, listed = room.listed, chans = room.chans, nextCh = room.nextCh, mem = {}, nextU = room.nextU,
        bans = room.bans, head = room.head, inbox = room.inbox, files = room.files, bytes = room.bytes,
        maxFile = room.maxFile, rv = room.rv,
    }
    for ipk, m in pairs(room.mem) do
        meta.mem[ipk] = { u = m.u, ipk = m.ipk, xpk = m.xpk, nm = m.nm, ro = m.ro, mute = m.mute, joined = m.joined }
    end
    saveTable(hostPath(room.rid), meta)
    for ch, h in pairs(room.hist) do
        if room.histDirty[ch] or force then
            saveTable(histPath(room.rid, ch), { msgs = h })
            room.histDirty[ch] = nil
        end
    end
    room.dirty = false
end

local function hostLoadOne(path)
    local meta = loadTable(path)
    if not meta or not meta.rid then return nil end
    local room = {
        rid = meta.rid, name = meta.name, owner = meta.owner, created = meta.created or 0, mode = meta.mode or "open",
        pw = meta.pw, listed = meta.listed ~= false, chans = meta.chans or {}, nextCh = meta.nextCh or 1,
        mem = {}, uidIdx = {}, nextU = meta.nextU or 1, bans = meta.bans or {}, head = meta.head or {},
        hist = {}, histDirty = {}, inbox = meta.inbox or {}, files = meta.files or {}, bytes = meta.bytes or 0,
        maxFile = meta.maxFile or 98304, rv = meta.rv or 1, pend = {}, out = {}, dirty = false,
    }
    for ipk, m in pairs(meta.mem or {}) do
        m.on = false
        m.id = nil
        m.seen = 0
        m.recent = {}
        m.cids = {}
        room.mem[ipk] = m
        room.uidIdx[m.u] = ipk
    end
    for _, c in ipairs(room.chans) do
        local h = loadTable(histPath(room.rid, c.id))
        room.hist[c.id] = (h and h.msgs) or {}
        room.head[c.id] = math.max(room.head[c.id] or 0, #room.hist[c.id] > 0 and room.hist[c.id][#room.hist[c.id]].n or 0)
    end
    return room
end

function Host.loadAll()
    ensureDir(DATA)
    for _, rid in ipairs(R.cfg.host or {}) do
        local room = hostLoadOne(hostPath(rid))
        if room then Host.rooms[rid] = room end
    end
end

local function chanById(room, id)
    for _, c in ipairs(room.chans) do if c.id == id then return c end end
end

function Host.create(name, mode, pw)
    local me = Net.refreshMe()
    if not me then return nil, "No network" end
    name = cleanName(name)
    if not name then return nil, "Name needs 2 to 20 letters or digits" end
    local rid = randHex(8)
    local room = {
        rid = rid, name = name, owner = me.ipk, created = nowSec(), mode = mode or "open", listed = true,
        chans = { { id = "c1", nm = "general", tp = "Say hello" }, { id = "c2", nm = "announcements", tp = "News from the staff", kd = "announce" },
            { id = "c3", nm = "files", tp = "Share files here" } },
        nextCh = 4, mem = {}, uidIdx = {}, nextU = 1, bans = {}, head = {}, hist = { c1 = {}, c2 = {}, c3 = {} },
        histDirty = {}, inbox = {}, files = {}, bytes = 0, maxFile = 98304, rv = 1, pend = {}, out = {}, dirty = true,
    }
    if mode == "password" then
        local salt = randHex(8)
        room.pw = { salt = salt, hash = pwHash(salt, pw or "") }
    end
    room.mem[me.ipk] = { u = 1, ipk = me.ipk, xpk = me.xpk, nm = R.cfg.name or cleanName(me.name) or "host", ro = ROLE_OWNER,
        id = me.id, seen = nowSec(), on = true, joined = nowSec(), recent = {}, cids = {} }
    room.uidIdx[1] = me.ipk
    room.nextU = 2
    Host.rooms[rid] = room
    R.cfg.host[#R.cfg.host + 1] = rid
    hostSave(room, true)
    return room
end

function Host.delete(rid)
    local room = Host.rooms[rid]
    if not room then return end
    Host.emit(room, "*", { k = "closed" })
    Host.flush(true)
    Host.rooms[rid] = nil
    for i, v in ipairs(R.cfg.host) do if v == rid then table.remove(R.cfg.host, i) break end end
    pcall(fs.delete, hostPath(rid))
    for _, c in ipairs(room.chans) do pcall(fs.delete, histPath(rid, c.id)) end
    for fid in pairs(room.files) do pcall(fs.delete, filePath(rid, fid)) end
end

local function online(m) return m.on and m.id and (nowSec() - (m.seen or 0)) < 60 end

-- Queue an event for members. who: "*" everyone online, or a member record.
function Host.emit(room, who, ev, except)
    local s = ser(ev)
    if who == "*" then
        for ipk, m in pairs(room.mem) do
            if online(m) and ipk ~= except then
                local q = room.out[ipk]
                if not q then q = {}; room.out[ipk] = q end
                q[#q + 1] = s
            end
        end
    else
        local q = room.out[who.ipk]
        if not q then q = {}; room.out[who.ipk] = q end
        q[#q + 1] = s
    end
end

-- Send what is queued. Several events share one packet.
function Host.flush(all)
    for rid, room in pairs(Host.rooms) do
        for ipk, q in pairs(room.out) do
            local m = room.mem[ipk]
            if m and m.id and #q > 0 then
                while #q > 0 do
                    local parts, size, n = {}, 0, 0
                    while q[n + 1] and size + #q[n + 1] < 7400 do
                        n = n + 1
                        parts[n] = q[n]
                        size = size + #q[n] + 1
                    end
                    if n == 0 then table.remove(q, 1); break end      -- one event too big, drop it
                    local body = '{t="b",r="' .. rid .. '",v=1,ev={' .. table.concat(parts, ",") .. "}}"
                    local ok, why = Net.sendRaw(m.id, body)
                    if not ok then
                        if why == "slow down" and not all then return end
                        if why ~= "slow down" then room.out[ipk] = {}; break end
                        return
                    end
                    for _ = 1, n do table.remove(q, 1) end
                    if not all then break end
                end
            else
                room.out[ipk] = nil
            end
        end
    end
end

function Host.pending()
    for _, room in pairs(Host.rooms) do
        for _, q in pairs(room.out) do if #q > 0 then return true end end
    end
    return false
end

local function rateOk(room, m, cost)
    local b = m.bucket
    local t = nowSec()
    if not b then b = { n = 6, t = t }; m.bucket = b end
    b.n = math.min(6, b.n + (t - b.t) * 0.6)
    b.t = t
    if b.n < cost then return false end
    b.n = b.n - cost
    return true
end

local function memEvent(m)
    return { k = "mem", u = m.u, ipk = m.ipk, xpk = m.xpk, nm = m.nm, ro = m.ro, on = online(m) and 1 or 0, mu = m.mute }
end

function Host.sendState(room, m)
    Host.emit(room, m, { k = "welcome", rid = room.rid, nm = room.name, u = m.u, ro = m.ro, rv = room.rv, md = room.mode })
    Host.emit(room, m, { k = "chans", l = room.chans, rv = room.rv })
    for _, other in pairs(room.mem) do Host.emit(room, m, memEvent(other)) end
    Host.emit(room, m, { k = "head", h = room.head, rv = room.rv })
end

function Host.sendHist(room, m, ch, since, limit)
    local h = room.hist[ch]
    if not h then return end
    local first = #h
    while first > 1 and h[first - 1].n > since and (#h - first) < (limit - 1) do first = first - 1 end
    for i = math.max(1, first), #h do
        local g = h[i]
        if g.n > since then
            Host.emit(room, m, { k = "m", ch = ch, n = g.n, ts = g.ts, u = g.u, x = g.x, re = g.re, f = g.f, rx = g.rx, ed = g.ed, sy = g.sy, old = 1 })
        end
    end
end

function Host.post(room, ch, u, text, extra, cid)
    local h = room.hist[ch]
    if not h then h = {}; room.hist[ch] = h end
    local n = (room.head[ch] or 0) + 1
    room.head[ch] = n
    local g = { n = n, ts = floor(nowSec()), u = u, x = text }
    if extra then for k, v in pairs(extra) do g[k] = v end end
    h[#h + 1] = g
    while #h > MAXHIST do
        local old = table.remove(h, 1)
        if old.f and room.files[old.f.id] then
            room.bytes = room.bytes - (room.files[old.f.id].sz or 0)
            pcall(fs.delete, filePath(room.rid, old.f.id))
            room.files[old.f.id] = nil
        end
    end
    room.histDirty[ch] = true
    room.dirty = true
    Host.emit(room, "*", { k = "m", ch = ch, n = n, ts = g.ts, u = u, x = text, re = g.re, f = g.f, sy = g.sy, c = cid })
    return g
end

local function sysPost(room, text)
    Host.post(room, room.chans[1] and room.chans[1].id or "c1", 0, text, { sy = 1 })
end

local function findMsg(room, ch, n)
    local h = room.hist[ch]
    if not h then return nil end
    for i = #h, 1, -1 do
        if h[i].n == n then return h[i], i end
        if h[i].n < n then return nil end
    end
end

local function bumpRv(room)
    room.rv = room.rv + 1
    room.dirty = true
end

local function nameFree(room, nm, ipk)
    local base, try = nm, nm
    local i = 1
    while true do
        local clash = false
        for k, m in pairs(room.mem) do
            if k ~= ipk and m.nm:lower() == try:lower() then clash = true break end
        end
        if not clash then return try end
        i = i + 1
        try = base:sub(1, 17) .. i
    end
end

local function admit(room, ipk, xpk, nm, id)
    local m = room.mem[ipk]
    if not m then
        m = { u = room.nextU, ipk = ipk, xpk = xpk, nm = nameFree(room, nm, ipk), ro = 0, joined = nowSec(), recent = {}, cids = {} }
        room.nextU = room.nextU + 1
        room.mem[ipk] = m
        room.uidIdx[m.u] = ipk
        bumpRv(room)
        sysPost(room, m.nm .. " joined the Room")
    end
    m.id, m.seen, m.on = id, nowSec(), true
    m.xpk = xpk
    return m
end

local function level(room, ipk)
    local m = room.mem[ipk]
    return m and m.ro or -1
end

local function dropMember(room, m, why)
    room.mem[m.ipk] = nil
    room.uidIdx[m.u] = nil
    room.out[m.ipk] = nil
    bumpRv(room)
    Host.emit(room, "*", { k = "gone", u = m.u })
end

-- One packet from a client.
function Host.handle(room, pk, t)
    local ipk = pk.ipk
    local ty = t.t
    if ty == "hello" then
        Net.send(pk.from, { t = "info", r = room.rid, nm = room.name, mc = (function() local n = 0 for _ in pairs(room.mem) do n = n + 1 end return n end)(),
            md = room.mode, o = (room.mem[room.owner] or {}).nm })
        return
    end
    if ty == "join" then
        if room.bans[ipk] then
            Net.send(pk.from, { t = "deny", r = room.rid, why = "You are banned from this Room" })
            return
        end
        local nm = cleanName(t.nm) or "player"
        local m = room.mem[ipk]
        if m then
            m.nm = (cleanName(t.nm) and cleanName(t.nm) ~= m.nm) and nameFree(room, cleanName(t.nm), ipk) or m.nm
            m.id, m.seen, m.on = pk.from, nowSec(), true
            m.xpk = pk.xpk
            room.out[ipk] = {}
            Host.sendState(room, m)
            Host.flushInbox(room, m)
            Host.emit(room, "*", memEvent(m), ipk)
            return
        end
        local count = 0
        for _ in pairs(room.mem) do count = count + 1 end
        if count >= MAXMEM then
            Net.send(pk.from, { t = "deny", r = room.rid, why = "This Room is full" })
            return
        end
        if room.mode == "password" then
            local pw
            if type(t.env) == "table" and rm and rm.open then
                local ok, got = pcall(rm.open, t.env)
                if ok then pw = got end
            end
            if not pw or pwHash(room.pw.salt, pw) ~= room.pw.hash then
                Net.send(pk.from, { t = "deny", r = room.rid, why = "Wrong password" })
                return
            end
        elseif room.mode == "approval" then
            if not room.pend[ipk] then
                local n = 0
                for _ in pairs(room.pend) do n = n + 1 end
                if n >= 20 then Net.send(pk.from, { t = "deny", r = room.rid, why = "Too many requests, try later" }) return end
                room.pend[ipk] = { nm = nm, xpk = pk.xpk, id = pk.from, ts = nowSec() }
                for _, other in pairs(room.mem) do
                    if other.ro >= ROLE_MOD and online(other) then
                        Host.emit(room, other, { k = "req", ipk = ipk, nm = nm })
                    end
                end
            else
                room.pend[ipk].id = pk.from
            end
            Net.send(pk.from, { t = "wait", r = room.rid })
            return
        end
        m = admit(room, ipk, pk.xpk, nm, pk.from)
        Host.sendState(room, m)
        Host.emit(room, "*", memEvent(m), ipk)
        return
    end
    local m = room.mem[ipk]
    if not m then
        Net.send(pk.from, { t = "deny", r = room.rid, why = "Not a member", gone = 1 })
        return
    end
    m.id, m.seen = pk.from, nowSec()
    if not m.on then
        m.on = true
        Host.emit(room, "*", memEvent(m), ipk)
    end
    local lv = m.ro

    if ty == "hb" then
        local h = type(t.h) == "table" and t.h or {}
        if int(t.rv, 0) ~= room.rv then
            Host.sendState(room, m)
        end
        Host.emit(room, m, { k = "head", h = room.head, rv = room.rv })
        for _, c in ipairs(room.chans) do
            local have = int(h[c.id], 0) or 0
            if have < (room.head[c.id] or 0) then Host.sendHist(room, m, c.id, have, 30) end
        end
        Host.flushInbox(room, m)
        return
    elseif ty == "sync" then
        local ch = str(t.ch, 8)
        if ch and room.hist[ch] then Host.sendHist(room, m, ch, int(t.since, 0) or 0, 40) end
        return
    elseif ty == "typ" then
        local ch = str(t.ch, 8)
        if ch and room.hist[ch] then Host.emit(room, "*", { k = "typ", ch = ch, u = m.u }, ipk) end
        return
    elseif ty == "leave" then
        sysPost(room, m.nm .. " left the Room")
        if m.ro == ROLE_OWNER then return end
        dropMember(room, m)
        return
    elseif ty == "msg" then
        local ch = str(t.ch, 8)
        local c = chanById(room, ch or "")
        local cid = int(t.c, 0)
        if not c or not cid then return end
        for _, old in ipairs(m.cids) do
            if old == cid then Host.emit(room, m, { k = "ack", c = cid }) return end
        end
        if m.mute and (m.mute == 0 or m.mute > nowSec()) then
            Host.emit(room, m, { k = "deny", c = cid, why = "You are muted" })
            return
        end
        if c.kd == "announce" and lv < ROLE_MOD then
            Host.emit(room, m, { k = "deny", c = cid, why = "Only staff post here" })
            return
        end
        if not rateOk(room, m, 1) then
            Host.emit(room, m, { k = "deny", c = cid, why = "Slow down" })
            return
        end
        local text = cleanText(t.x)
        if not text then return end
        local extra = {}
        local re = int(t.re, 1)
        if re and findMsg(room, ch, re) then extra.re = re end
        m.cids[#m.cids + 1] = cid
        if #m.cids > 24 then table.remove(m.cids, 1) end
        Host.post(room, ch, m.u, text, extra, cid)
        Host.emit(room, m, { k = "ack", c = cid })
        return
    elseif ty == "rx" then
        local ch, n, e = str(t.ch, 8), int(t.n, 1), str(t.e, 4)
        if not (ch and n and e and REACT_OK[e]) then return end
        local g = findMsg(room, ch, n)
        if not g or not rateOk(room, m, 0.5) then return end
        g.rx = g.rx or {}
        local list = g.rx[e] or {}
        local at
        for i, u in ipairs(list) do if u == m.u then at = i end end
        if at then table.remove(list, at) else list[#list + 1] = m.u end
        g.rx[e] = (#list > 0) and list or nil
        if next(g.rx) == nil then g.rx = nil end
        room.histDirty[ch] = true
        room.dirty = true
        Host.emit(room, "*", { k = "r", ch = ch, n = n, e = e, u = m.u, on = at and 0 or 1 })
        return
    elseif ty == "del" then
        local ch, n = str(t.ch, 8), int(t.n, 1)
        if not (ch and n) then return end
        local g, idx = findMsg(room, ch, n)
        if not g then return end
        local author = room.uidIdx[g.u]
        local alv = author and level(room, author) or 0
        if g.u ~= m.u and not (lv >= ROLE_MOD and lv > alv) then return end
        table.remove(room.hist[ch], idx)
        if g.f and room.files[g.f.id] then
            room.bytes = room.bytes - (room.files[g.f.id].sz or 0)
            pcall(fs.delete, filePath(room.rid, g.f.id))
            room.files[g.f.id] = nil
        end
        room.histDirty[ch] = true
        room.dirty = true
        Host.emit(room, "*", { k = "x", ch = ch, n = n })
        return
    elseif ty == "edit" then
        local ch, n = str(t.ch, 8), int(t.n, 1)
        local text = cleanText(t.x)
        if not (ch and n and text) then return end
        local g = findMsg(room, ch, n)
        if not g or g.u ~= m.u or g.sy then return end
        g.x, g.ed = text, 1
        room.histDirty[ch] = true
        room.dirty = true
        Host.emit(room, "*", { k = "e", ch = ch, n = n, x = text })
        return
    elseif ty == "dm" then
        local to = int(t.to, 1)
        local tipk = to and room.uidIdx[to]
        local tm = tipk and room.mem[tipk]
        local cid = int(t.c, 0)
        if not tm or type(t.env) ~= "table" or not cid then return end
        for _, old in ipairs(m.cids) do
            if old == cid then Host.emit(room, m, { k = "ack", c = cid }) return end
        end
        m.cids[#m.cids + 1] = cid
        if #m.cids > 24 then table.remove(m.cids, 1) end
        if type(t.env.wk) ~= "string" or type(t.env.box) ~= "string" or #t.env.wk > 600 or #t.env.box > 5200 then return end
        if m.mute and (m.mute == 0 or m.mute > nowSec()) then
            Host.emit(room, m, { k = "deny", c = cid, why = "You are muted" })
            return
        end
        if not rateOk(room, m, 1) then Host.emit(room, m, { k = "deny", c = cid, why = "Slow down" }) return end
        local ev = { k = "dm", fu = m.u, env = { wk = t.env.wk, box = t.env.box } }
        if online(tm) then
            Host.emit(room, tm, ev)
        else
            local box = room.inbox[tipk]
            if not box then box = {}; room.inbox[tipk] = box end
            box[#box + 1] = ev
            if #box > 40 then table.remove(box, 1) end
            room.dirty = true
        end
        Host.emit(room, m, { k = "ack", c = cid })
        return
    elseif ty == "bans" then
        if lv < ROLE_ADMIN then return end
        local l = {}
        for k, nm in pairs(room.bans) do l[#l + 1] = { ipk = k, nm = nm } end
        Host.emit(room, m, { k = "bans", l = l })
        Host.emit(room, m, { k = "pend", l = (function()
            local o = {}
            for k2, p in pairs(room.pend) do o[#o + 1] = { ipk = k2, nm = p.nm } end
            return o
        end)() })
        return
    elseif ty == "mod" then
        return Host.moderate(room, m, t)
    elseif ty == "fup" then
        return Host.fileUp(room, m, t)
    elseif ty == "fget" then
        return Host.fileGet(room, m, t)
    end
end

function Host.flushInbox(room, m)
    local box = room.inbox[m.ipk]
    if box and #box > 0 then
        for _, ev in ipairs(box) do Host.emit(room, m, ev) end
        room.inbox[m.ipk] = nil
        room.dirty = true
    end
end

function Host.moderate(room, m, t)
    local a = str(t.a, 12)
    local lv = m.ro
    local target = int(t.u, 1) and room.uidIdx[t.u] and room.mem[room.uidIdx[t.u]]
    local function notice(text) Host.emit(room, m, { k = "deny", why = text }) end
    if a == "kick" or a == "ban" then
        if not target or target.ipk == m.ipk then return end
        if lv < ROLE_MOD or (a == "ban" and lv < ROLE_ADMIN) or target.ro >= lv then return notice("Not allowed") end
        local tm = target
        Host.emit(room, tm, { k = (a == "ban") and "banned" or "kicked" })
        Host.flush(true)
        if a == "ban" then room.bans[tm.ipk] = tm.nm end
        sysPost(room, tm.nm .. (a == "ban" and " was banned" or " was removed") .. " by " .. m.nm)
        dropMember(room, tm)
    elseif a == "unban" then
        if lv < ROLE_ADMIN then return end
        local k = str(t.ipk, 64)
        if k and room.bans[k] then room.bans[k] = nil; room.dirty = true end
    elseif a == "mute" or a == "unmute" then
        if not target or lv < ROLE_MOD or target.ro >= lv then return notice("Not allowed") end
        if a == "mute" then
            local mins = int(t.v, 0, 10080) or 10
            target.mute = (mins == 0) and 0 or (nowSec() + mins * 60)
        else
            target.mute = nil
        end
        room.dirty = true
        bumpRv(room)
        Host.emit(room, "*", memEvent(target))
    elseif a == "role" then
        local ro = int(t.v, 0, 2)
        if not target or ro == nil or lv < ROLE_ADMIN or target.ro >= lv then return notice("Not allowed") end
        if ro >= lv then return notice("Not allowed") end
        target.ro = ro
        bumpRv(room)
        Host.emit(room, "*", memEvent(target))
        sysPost(room, target.nm .. " is now " .. ROLE_NAME[ro])
    elseif a == "approve" or a == "deny" then
        local k = str(t.ipk, 64)
        local p = k and room.pend[k]
        if not p or lv < ROLE_MOD then return end
        room.pend[k] = nil
        if a == "approve" then
            local nm = admit(room, k, p.xpk, p.nm, p.id)
            Host.sendState(room, nm)
            Host.emit(room, "*", memEvent(nm), k)
        else
            if p.id then Net.send(p.id, { t = "deny", r = room.rid, why = "Request declined" }) end
        end
    elseif a == "chadd" then
        if lv < ROLE_ADMIN then return notice("Not allowed") end
        local nm = cleanChan(t.nm)
        if not nm or #room.chans >= 12 then return notice("Cannot add that channel") end
        local id = "c" .. room.nextCh
        room.nextCh = room.nextCh + 1
        room.chans[#room.chans + 1] = { id = id, nm = nm, tp = "", kd = (t.kd == "announce") and "announce" or nil }
        room.hist[id] = {}
        room.histDirty[id] = true
        bumpRv(room)
        Host.emit(room, "*", { k = "chans", l = room.chans, rv = room.rv })
    elseif a == "chdel" then
        local id = str(t.ch, 8)
        if lv < ROLE_ADMIN or not id or #room.chans <= 1 then return notice("Not allowed") end
        for i, c in ipairs(room.chans) do
            if c.id == id then
                table.remove(room.chans, i)
                room.hist[id] = nil
                room.head[id] = nil
                pcall(fs.delete, histPath(room.rid, id))
                break
            end
        end
        bumpRv(room)
        Host.emit(room, "*", { k = "chans", l = room.chans, rv = room.rv })
    elseif a == "chedit" then
        local id = str(t.ch, 8)
        local c = id and chanById(room, id)
        if lv < ROLE_ADMIN or not c then return notice("Not allowed") end
        if t.nm then c.nm = cleanChan(t.nm) or c.nm end
        if t.tp then c.tp = (cleanText(t.tp, 60)) or "" end
        bumpRv(room)
        Host.emit(room, "*", { k = "chans", l = room.chans, rv = room.rv })
    elseif a == "setname" then
        if lv < ROLE_OWNER then return notice("Not allowed") end
        local nm = cleanName(t.v)
        if nm then room.name = nm; bumpRv(room); Host.emit(room, "*", { k = "welcome", rid = room.rid, nm = room.name, u = m.u, ro = m.ro, rv = room.rv, md = room.mode, keep = 1 }) end
    elseif a == "setmode" then
        if lv < ROLE_OWNER then return notice("Not allowed") end
        local md = str(t.v, 10)
        if md == "open" or md == "approval" then room.mode = md; room.pw = nil
        elseif md == "password" then
            local pw = str(t.pw, 40)
            if not pw or #pw < 3 then return notice("Password needs 3 characters") end
            local salt = randHex(8)
            room.pw = { salt = salt, hash = pwHash(salt, pw) }
            room.mode = md
        end
        room.dirty = true
    elseif a == "listed" then
        if lv < ROLE_OWNER then return end
        room.listed = t.v == 1
        room.dirty = true
    elseif a == "maxfile" then
        if lv < ROLE_OWNER then return end
        room.maxFile = int(t.v, 4096, 524288) or room.maxFile
        room.dirty = true
    end
end

-- Uploads arrive in order, one chunk per packet, each answered with an ack.
function Host.fileUp(room, m, t)
    local ch, fid = str(t.ch, 8), str(t.fid, 12)
    local i, n, sz = int(t.i, 1, 200), int(t.n, 1, 200), int(t.sz, 1, 524288)
    local d = str(t.d, 7000)
    if not (ch and fid and i and n and d and sz and fid:match("^%x+$") and room.hist[ch]) then return end
    local function nope(why) Host.emit(room, m, { k = "fnack", fid = fid, why = why }) end
    local c = chanById(room, ch)
    if m.mute and (m.mute == 0 or m.mute > nowSec()) then return nope("You are muted") end
    if c.kd == "announce" and m.ro < ROLE_MOD then return nope("Only staff post here") end
    if sz > room.maxFile then return nope("File over " .. fmtSize(room.maxFile)) end
    if room.bytes + sz > 4 * 1048576 then return nope("The Room storage is full") end
    local up = m.up
    if i == 1 then
        if not rateOk(room, m, 2) then return nope("Slow down") end
        up = { fid = fid, nm = safeFile(t.nm), sz = sz, n = n, got = 0, bytes = 0, ch = ch, parts = {}, re = int(t.re, 1) }
        m.up = up
    end
    if not up or up.fid ~= fid then return end
    if i == up.got then
        Host.emit(room, m, { k = "fack", fid = fid, i = i })
        return
    end
    if i ~= up.got + 1 or n ~= up.n then return end
    local raw = b64dc(d)
    up.bytes = up.bytes + #raw
    if up.bytes > up.sz + 8 or up.bytes > room.maxFile then m.up = nil return nope("File too large") end
    up.parts[#up.parts + 1] = raw
    up.got = i
    Host.emit(room, m, { k = "fack", fid = fid, i = i })
    if i == n then
        ensureDir(DATA .. "/files")
        local all = table.concat(up.parts)
        m.up = nil
        if not writeAll(filePath(room.rid, fid), all) then return nope("Cannot store the file") end
        room.files[fid] = { nm = up.nm, sz = #all, u = m.u, ts = nowSec() }
        room.bytes = room.bytes + #all
        local extra = { f = { id = fid, nm = up.nm, sz = #all } }
        if up.re and findMsg(room, up.ch, up.re) then extra.re = up.re end
        Host.post(room, up.ch, m.u, cleanText(t.x or "") or "", extra, nil)
    end
end

function Host.fileGet(room, m, t)
    local fid, i = str(t.fid, 12), int(t.i, 1, 200)
    local f = fid and room.files[fid]
    if not f or not i then Host.emit(room, m, { k = "fnack", fid = fid or "", why = "File is gone" }) return end
    if not rateOk(room, m, 0.34) then return end
    local data = readAll(filePath(room.rid, fid))
    if not data then Host.emit(room, m, { k = "fnack", fid = fid, why = "File is gone" }) return end
    local n = math.max(1, math.ceil(#data / FILE_CHUNK))
    if i > n then return end
    local part = data:sub((i - 1) * FILE_CHUNK + 1, i * FILE_CHUNK)
    Host.emit(room, m, { k = "fdat", fid = fid, i = i, n = n, sz = #data, d = b64enc(part), nm = f.nm })
end

-- Housekeeping: presence, beacons, saving.
function Host.tick()
    local t = nowSec()
    for _, room in pairs(Host.rooms) do
        for _, m in pairs(room.mem) do
            if m.on and m.ipk ~= (R.me and R.me.ipk) and (t - (m.seen or 0)) > 45 then
                m.on = false
                Host.emit(room, "*", memEvent(m), m.ipk)
            end
            if m.mute and m.mute ~= 0 and m.mute < t then
                m.mute = nil
                room.dirty = true
                Host.emit(room, "*", memEvent(m))
            end
        end
        local me = room.mem[room.owner]
        if me and R.me then me.seen, me.on, me.id = t, true, R.me.id end
        for k, p in pairs(room.pend) do if t - p.ts > 600 then room.pend[k] = nil end end
    end
    if t >= Host.nextBeacon then
        Host.nextBeacon = t + 20
        for _, room in pairs(Host.rooms) do
            if room.listed then
                local n = 0
                for _ in pairs(room.mem) do n = n + 1 end
                Net.broadcast({ t = "bc", r = room.rid, nm = room.name, mc = n, md = room.mode, o = (room.mem[room.owner] or {}).nm })
            end
        end
    end
    if t >= Host.nextSave then
        Host.nextSave = t + 6
        for _, room in pairs(Host.rooms) do
            if room.dirty or next(room.histDirty) then hostSave(room) end
        end
    end
end

function Host.saveAll()
    for _, room in pairs(Host.rooms) do hostSave(room, true) end
end

-- ── Rooms: client side ───────────────────────────────────────────────────────
R.rooms = {}            -- rid -> client room
R.dmPeers = {}
local Cl = {}
R.Cl = Cl

local function newRoom(rid, name, hostId, hostIpk, hostXpk)
    return {
        rid = rid, name = name or "Room", hostId = hostId, hostIpk = hostIpk, hostXpk = hostXpk,
        state = "joining", u = nil, ro = 0, chans = {}, mem = {}, byIpk = {}, hist = {}, seq = {}, read = {},
        ment = {}, rv = 0, pend = {}, typing = {}, dms = {}, dmRead = {}, lastHead = 0, joinTry = 0,
        nextCid = math.random(1, 100000), xfer = {}, reqs = {}, bans = {}, mode = "open", dirty = false,
        flash = {}, lastFlash = 0,
    }
end

function Cl.saveCfg()
    local out = { name = R.cfg.name, host = R.cfg.host, joined = {}, ui = R.cfg.ui }
    for rid, c in pairs(R.rooms) do
        out.joined[rid] = { name = c.name, hostId = c.hostId, hostIpk = c.hostIpk, hostXpk = c.hostXpk, read = c.read,
            dmRead = c.dmRead, u = c.u }
    end
    saveTable(clientPath(), out)
end

function Cl.saveCache(c)
    local hist = {}
    for ch, list in pairs(c.hist) do
        local from = math.max(1, #list - 119)
        local o = {}
        for i = from, #list do
            local g = list[i]
            if not g.local_ then o[#o + 1] = g end
        end
        hist[ch] = o
    end
    local dms = {}
    for k, list in pairs(c.dms) do
        local from = math.max(1, #list - 79)
        local o = {}
        for i = from, #list do o[#o + 1] = list[i] end
        dms[k] = o
    end
    saveTable(cacheName(c.rid), { hist = hist, dms = dms, seq = c.seq, chans = c.chans, mem = c.mem, rv = c.rv })
    c.dirty = false
end

function Cl.loadAll()
    ensureDir(DATA)
    local cfg = loadTable(clientPath())
    if cfg then
        R.cfg.name = cfg.name
        R.cfg.host = cfg.host or {}
        R.cfg.ui = cfg.ui or {}
        for rid, j in pairs(cfg.joined or {}) do
            local c = newRoom(rid, j.name, j.hostId, j.hostIpk, j.hostXpk)
            c.read, c.dmRead, c.u = j.read or {}, j.dmRead or {}, j.u
            local cache = loadTable(cacheName(rid))
            if cache then
                c.hist, c.dms, c.seq = cache.hist or {}, cache.dms or {}, cache.seq or {}
                c.chans, c.mem, c.rv = cache.chans or {}, cache.mem or {}, 0
                for u, m in pairs(c.mem) do if m.ipk then c.byIpk[m.ipk] = u end; m.on = false end
            end
            c.state = "offline"
            R.rooms[rid] = c
        end
    end
end

local function chanOf(c, id)
    for _, ch in ipairs(c.chans) do if ch.id == id then return ch end end
end
Cl.chanOf = chanOf

function Cl.nameOf(c, u)
    if u == 0 then return "Room" end
    local m = c.mem[u]
    return m and m.nm or ("user" .. tostring(u))
end

function Cl.send(c, tbl)
    tbl.r = c.rid
    return Net.send(c.hostId, tbl)
end

function Cl.join(c, pw)
    local t = { t = "join", nm = R.cfg.name or cleanName(R.me and R.me.name) or "player" }
    if c.mode == "password" and pw and rm and rm.seal and c.hostXpk then
        local env = rm.seal(c.hostXpk, pw)
        if env then t.env = env end
    end
    c.joinPw = pw or c.joinPw
    if not t.env and c.joinPw and rm and rm.seal and c.hostXpk then t.env = rm.seal(c.hostXpk, c.joinPw) end
    c.joinTry = nowSec()
    Cl.send(c, t)
end

-- Add a new Room to this computer (after the person confirmed the host).
function Cl.addRoom(info, pw)
    local c = R.rooms[info.rid]
    if not c then
        c = newRoom(info.rid, info.nm, info.hostId, info.hostIpk, info.hostXpk)
        R.rooms[info.rid] = c
    end
    c.mode = info.md or c.mode
    c.state = "joining"
    Net.listen(false)
    Cl.join(c, pw)
    Cl.saveCfg()
    return c
end

function Cl.leave(c)
    Cl.send(c, { t = "leave" })
    R.rooms[c.rid] = nil
    pcall(fs.delete, cacheName(c.rid))
    Net.listen(false)
    Cl.saveCfg()
end

local function insertMsg(list, g)
    -- list is sorted by n. A message with the same n replaces the old one.
    local last = list[#list]
    if not last or g.n > last.n then list[#list + 1] = g; return true end
    for i = #list, 1, -1 do
        if list[i].n == g.n then list[i] = g; return false end
        if list[i].n < g.n then table.insert(list, i + 1, g); return true end
    end
    table.insert(list, 1, g)
    return true
end

local function mentions(c, text)
    local me = c.mem[c.u]
    if not me or not text then return false end
    local low = text:lower()
    local nm = me.nm:lower()
    local s = low:find("@" .. nm:gsub("%p", "%%%0"), 1)
    if s then return true end
    return low:find("@everyone", 1, true) ~= nil
end
Cl.mentions = mentions

local function pushFlash(c, ch, n)
    c.flash[ch .. ":" .. n] = nowSec()
end

local function ev_m(c, e)
    local ch, n = str(e.ch, 8), int(e.n, 1)
    if not (ch and n) then return end
    local x = str(e.x, 2000)
    if x == nil then x = "" end
    local g = { n = n, ts = int(e.ts, 0) or floor(nowSec()), u = int(e.u, 0) or 0, x = x, re = int(e.re, 1), ed = e.ed and 1 or nil, sy = e.sy and 1 or nil }
    if type(e.f) == "table" and str(e.f.id, 12) and str(e.f.nm, 40) then
        g.f = { id = e.f.id, nm = e.f.nm, sz = int(e.f.sz, 0) or 0 }
    end
    if type(e.rx) == "table" then
        g.rx = {}
        for k, list in pairs(e.rx) do
            if REACT_OK[k] and type(list) == "table" then
                local o = {}
                for _, u in ipairs(list) do if int(u, 0) then o[#o + 1] = u end end
                if #o > 0 then g.rx[k] = o end
            end
        end
    end
    local list = c.hist[ch]
    if not list then list = {}; c.hist[ch] = list end
    -- our own message: replace the sending copy
    local cid = int(e.c, 0)
    if cid and g.u == c.u and c.pend[cid] then
        local p = c.pend[cid]
        c.pend[cid] = nil
        for i, o in ipairs(list) do if o == p.echo then table.remove(list, i) break end end
    end
    local isNew = insertMsg(list, g)
    while #list > MAXHIST do table.remove(list, 1) end
    if (c.seq[ch] or 0) < n then
        if n > (c.seq[ch] or 0) + 1 and not e.old and (c.seq[ch] or 0) > 0 then
            Cl.send(c, { t = "sync", ch = ch, since = c.seq[ch] or 0 })
        end
        c.seq[ch] = n
    end
    c.dirty = true
    if isNew and not e.old then
        pushFlash(c, ch, n)
        if g.u ~= c.u and not g.sy then
            local here = (R.ui and R.ui.room == c.rid and R.ui.ch == ch and R.ui.atBottom)
            if not here then
                if mentions(c, g.x) then c.ment[ch] = (c.ment[ch] or 0) + 1 end
            end
            if R.onMessage then R.onMessage(c, ch, g) end
        end
    end
    R.dirty = true
end

function Cl.unread(c, ch)
    local last = c.seq[ch] or 0
    local seen = c.read[ch] or 0
    if last <= seen then return 0 end
    local n = 0
    local list = c.hist[ch] or {}
    for i = #list, 1, -1 do
        if list[i].n <= seen then break end
        if list[i].u ~= c.u and not list[i].sy then n = n + 1 end
    end
    return n
end

function Cl.markRead(c, ch)
    if (c.read[ch] or 0) ~= (c.seq[ch] or 0) then
        c.read[ch] = c.seq[ch] or 0
        c.ment[ch] = nil
        c.dirty = true
    end
end

function Cl.unreadDm(c, key)
    local list = c.dms[key] or {}
    local seen = c.dmRead[key] or 0
    local n = 0
    for i = #list, 1, -1 do
        if (list[i].id or 0) <= seen then break end
        if not list[i].mine then n = n + 1 end
    end
    return n
end

function Cl.markDmRead(c, key)
    local list = c.dms[key]
    if list and #list > 0 and (c.dmRead[key] or 0) ~= (list[#list].id or 0) then
        c.dmRead[key] = list[#list].id or 0
        c.dirty = true
    end
end

local function findIn(c, ch, n)
    local list = c.hist[ch]
    if not list then return nil end
    for i = #list, 1, -1 do
        if list[i].n == n then return list[i], i end
        if list[i].n < n then return nil end
    end
end
Cl.findMsg = findIn

local nextDmId = 1

local function receiveDm(c, e)
    local fu = int(e.fu, 1)
    local m = fu and c.mem[fu]
    if not m or type(e.env) ~= "table" or not rm then return end
    local ok, plain = pcall(rm.open, e.env)
    if not ok or type(plain) ~= "string" then return end
    local data = textutils.unserialize(plain)
    if type(data) ~= "table" or type(data.x) ~= "string" or type(data.sig) ~= "string" then return end
    local myIpk = R.me and R.me.ipk or ""
    local okv, valid = pcall(rm.verify, m.ipk, "dm|" .. myIpk .. "|" .. tostring(data.ts) .. "|" .. data.x, data.sig)
    if not okv or not valid then return end
    local key = m.ipk
    local list = c.dms[key]
    if not list then list = {}; c.dms[key] = list end
    nextDmId = math.max(nextDmId, (list[#list] and list[#list].id or 0) + 1)
    list[#list + 1] = { id = nextDmId, ts = int(data.ts, 0) or floor(nowSec()), x = data.x:sub(1, 600), mine = false }
    nextDmId = nextDmId + 1
    while #list > 120 do table.remove(list, 1) end
    c.dirty = true
    R.dirty = true
    if R.onDm then R.onDm(c, m, list[#list]) end
end

local function xferDone(c, fid, ok, why)
    local x = c.xfer[fid]
    if not x then return end
    x.done, x.ok, x.why = true, ok, why
    x.at = nowSec()
    R.dirty = true
end

local handlers = {}

handlers.welcome = function(c, e)
    c.name = str(e.nm, 30) or c.name
    c.mode = str(e.md, 10) or c.mode
    if e.keep then R.dirty = true return end
    c.u, c.ro = int(e.u, 1), int(e.ro, 0, 3) or 0
    c.state = "online"
    c.joinPw = nil
    c.waiting = nil
    c.lastHead = nowSec()
    Cl.saveCfg()
    R.dirty = true
end
handlers.chans = function(c, e)
    if type(e.l) ~= "table" then return end
    local o = {}
    for _, ch in ipairs(e.l) do
        if type(ch) == "table" and str(ch.id, 8) and str(ch.nm, 20) then
            o[#o + 1] = { id = ch.id, nm = ch.nm, tp = str(ch.tp, 80) or "", kd = (ch.kd == "announce") and "announce" or nil }
        end
    end
    if #o > 0 then c.chans = o end
    c.rv = int(e.rv, 0) or c.rv
    R.dirty = true
end
handlers.mem = function(c, e)
    local u = int(e.u, 1)
    if not (u and isHex(e.ipk, 64) and isHex(e.xpk, 64) and str(e.nm, 24)) then return end
    local old = c.mem[u]
    c.mem[u] = { u = u, ipk = e.ipk, xpk = e.xpk, nm = e.nm, ro = int(e.ro, 0, 3) or 0, on = e.on == 1, mu = e.mu }
    c.byIpk[e.ipk] = u
    if u == c.u then c.ro = c.mem[u].ro end
    c.dirty = true
    R.dirty = true
end
handlers.gone = function(c, e)
    local u = int(e.u, 1)
    if u and c.mem[u] then c.mem[u] = nil end
    R.dirty = true
end
handlers.head = function(c, e)
    c.lastHead = nowSec()
    if c.state == "offline" then c.state = "online" end
    if type(e.h) == "table" then
        for ch, n in pairs(e.h) do
            if str(ch, 8) and int(n, 0) and n > (c.seq[ch] or 0) then
                Cl.send(c, { t = "sync", ch = ch, since = c.seq[ch] or 0 })
            end
        end
    end
    R.dirty = true
end
handlers.m = ev_m
handlers.x = function(c, e)
    local g, i = findIn(c, str(e.ch, 8) or "", int(e.n, 1) or 0)
    if g then table.remove(c.hist[e.ch], i); c.dirty = true; R.dirty = true end
end
handlers.e = function(c, e)
    local g = findIn(c, str(e.ch, 8) or "", int(e.n, 1) or 0)
    local x = str(e.x, 2000)
    if g and x then g.x, g.ed = x, 1; c.dirty = true; R.dirty = true end
end
handlers.r = function(c, e)
    local ch, n, em, u = str(e.ch, 8), int(e.n, 1), str(e.e, 4), int(e.u, 0)
    local g = ch and n and findIn(c, ch, n)
    if not g or not em or not REACT_OK[em] or not u then return end
    g.rx = g.rx or {}
    local list = g.rx[em] or {}
    for i = #list, 1, -1 do if list[i] == u then table.remove(list, i) end end
    if e.on == 1 then list[#list + 1] = u end
    g.rx[em] = (#list > 0) and list or nil
    if next(g.rx) == nil then g.rx = nil end
    if e.on == 1 and R.onReact then R.onReact(c, ch, g, em, u) end
    c.dirty = true
    R.dirty = true
end
handlers.typ = function(c, e)
    local u = int(e.u, 1)
    if u then c.typing[u] = { ch = str(e.ch, 8), t = nowSec() }; R.dirty = true end
end
handlers.ack = function(c, e)
    local cid = int(e.c, 0)
    local p = cid and c.pend[cid]
    if p then
        p.acked = true
        if p.dm then
            c.pend[cid] = nil
            if p.echo then p.echo.sent = true end
        end
        R.dirty = true
    end
end
handlers.deny = function(c, e)
    local cid = int(e.c, 0)
    local why = str(e.why, 60) or "Not allowed"
    local p = cid and c.pend[cid]
    if p then
        p.failed = why
        if p.echo then p.echo.failed = why end
    end
    note(why, "warn")
end
handlers.dm = receiveDm
handlers.req = function(c, e)
    if isHex(e.ipk, 64) and str(e.nm, 24) then
        c.reqs[e.ipk] = { nm = e.nm, t = nowSec() }
        note(e.nm .. " asks to join " .. c.name, "info")
    end
end
handlers.bans = function(c, e)
    c.bans = {}
    for _, b in ipairs(type(e.l) == "table" and e.l or {}) do
        if isHex(b.ipk, 64) and str(b.nm, 24) then c.bans[#c.bans + 1] = { ipk = b.ipk, nm = b.nm } end
    end
    R.dirty = true
end
handlers.pend = function(c, e)
    c.reqs = {}
    for _, b in ipairs(type(e.l) == "table" and e.l or {}) do
        if isHex(b.ipk, 64) and str(b.nm, 24) then c.reqs[b.ipk] = { nm = b.nm, t = nowSec() } end
    end
    R.dirty = true
end
handlers.kicked = function(c, e)
    note("You were removed from " .. c.name, "warn")
    R.rooms[c.rid] = nil
    pcall(fs.delete, cacheName(c.rid))
    Net.listen(false)
    Cl.saveCfg()
    if R.onRoomGone then R.onRoomGone(c.rid) end
end
handlers.banned = function(c, e)
    note("You were banned from " .. c.name, "warn")
    handlers.kicked(c, e)
end
handlers.closed = function(c, e)
    note(c.name .. " was closed by its host", "warn")
    handlers.kicked(c, e)
end
handlers.fack = function(c, e)
    local fid = str(e.fid, 12)
    local x = fid and c.xfer[fid]
    if x and x.up then
        x.acked = int(e.i, 0) or x.acked
        x.sentAt = nil
        R.dirty = true
    end
end
handlers.fnack = function(c, e)
    local fid = str(e.fid, 12)
    local why = str(e.why, 60) or "Failed"
    if fid and c.xfer[fid] then xferDone(c, fid, false, why) end
    note(why, "warn")
end
handlers.fdat = function(c, e)
    local fid = str(e.fid, 12)
    local x = fid and c.xfer[fid]
    local i, n = int(e.i, 1, 200), int(e.n, 1, 200)
    if not (x and not x.up and i and n and str(e.d, 7000)) then return end
    if i ~= x.next then return end
    x.n = n
    x.parts[#x.parts + 1] = b64dc(e.d)
    x.next = i + 1
    x.got = i
    x.sentAt = nil
    if i == n then
        local dir = "downloads/rooms"
        if not fs.exists("downloads") then pcall(fs.makeDir, "downloads") end
        ensureDir(dir)
        local base = safeFile(x.nm)
        local path = dir .. "/" .. base
        local k = 1
        while fs.exists(path) do
            k = k + 1
            path = dir .. "/" .. k .. "_" .. base
        end
        if writeAll(path, table.concat(x.parts)) then
            x.saved = path
            xferDone(c, fid, true)
        else
            xferDone(c, fid, false, "Cannot save the file")
        end
        x.parts = {}
    end
    R.dirty = true
end

-- Batch of events from the host.
function Cl.onBatch(c, t)
    if type(t.ev) ~= "table" then return end
    for _, e in ipairs(t.ev) do
        if type(e) == "table" and type(e.k) == "string" then
            local h = handlers[e.k]
            if h then pcall(h, c, e) end
        end
    end
    if c.dirty and not c.saveAt then c.saveAt = nowSec() + 8 end
end

-- Any packet that arrived (real or from the loop queue).
function Cl.incoming(pk)
    local t = pk.t
    if type(t) ~= "table" or type(t.t) ~= "string" then return end
    local ty = t.t
    local rid = str(t.r, 8)
    -- host side
    if rid and Host.rooms[rid] and (ty == "join" or ty == "hello" or ty == "hb" or ty == "sync" or ty == "typ" or ty == "leave"
        or ty == "msg" or ty == "rx" or ty == "del" or ty == "edit" or ty == "dm" or ty == "bans" or ty == "mod"
        or ty == "fup" or ty == "fget") then
        if type(pk.ipk) == "string" and isHex(pk.ipk, 64) then
            local ok, err = pcall(Host.handle, Host.rooms[rid], pk, t)
            if not ok then R.lastErr = tostring(err) end
        end
        return
    end
    -- client side
    if ty == "bc" then
        if rid and str(t.nm, 24) then
            R.found[pk.from .. ":" .. rid] = { rid = rid, nm = t.nm, mc = int(t.mc, 0, 999) or 0, md = str(t.md, 10) or "open",
                o = str(t.o, 24) or "?", hostId = pk.from, hostIpk = pk.ipk, hostXpk = pk.xpk, fp = pk.fp, seen = nowSec() }
            R.dirty = true
        end
        return
    elseif ty == "info" then
        if rid and str(t.nm, 24) and R.wantInfo and R.wantInfo.hostId == pk.from and R.wantInfo.rid == rid then
            R.info = { rid = rid, nm = t.nm, mc = int(t.mc, 0, 999) or 0, md = str(t.md, 10) or "open", o = str(t.o, 24) or "?",
                hostId = pk.from, hostIpk = pk.ipk, hostXpk = pk.xpk, fp = pk.fp }
            R.dirty = true
        end
        return
    end
    local c = rid and R.rooms[rid]
    if not c or c.hostId ~= pk.from or c.hostIpk ~= pk.ipk then return end
    if ty == "b" then
        c.lastSeen = nowSec()
        Cl.onBatch(c, t)
    elseif ty == "deny" then
        c.state = "denied"
        c.denyWhy = str(t.why, 80) or "Denied"
        if t.gone and c.u then
            -- the host forgot us: join again
            c.state = "joining"
            Cl.join(c)
        else
            R.rooms[rid] = nil
            Net.listen(false)
            Cl.saveCfg()
            note(c.denyWhy, "warn")
            if R.onRoomGone then R.onRoomGone(rid, c.denyWhy) end
        end
    elseif ty == "wait" then
        c.state = "waiting"
        R.dirty = true
    end
end

-- Messages --------------------------------------------------------------------

function Cl.sendMessage(c, ch, text, reply)
    text = cleanText(text)
    if not text then return false end
    local cid = c.nextCid
    c.nextCid = cid + 1
    local list = c.hist[ch]
    if not list then list = {}; c.hist[ch] = list end
    local echo = { n = (c.seq[ch] or 0) + 0.5 + (cid % 1000) / 100000, ts = floor(nowSec()), u = c.u or 0, x = text, re = reply, local_ = true, sending = true }
    list[#list + 1] = echo
    local p = { cid = cid, t = { t = "msg", ch = ch, x = text, re = reply, c = cid }, echo = echo, sent = nowSec(), tries = 1 }
    c.pend[cid] = p
    Cl.send(c, p.t)
    R.dirty = true
    return true
end

function Cl.resendFailed(c, g)
    for cid, p in pairs(c.pend) do
        if p.echo == g then
            p.failed, g.failed = nil, nil
            p.sent, p.tries = nowSec(), 1
            Cl.send(c, p.t)
            return
        end
    end
end

function Cl.dropLocal(c, ch, g)
    local list = c.hist[ch] or {}
    for i, o in ipairs(list) do if o == g then table.remove(list, i) break end end
    for cid, p in pairs(c.pend) do if p.echo == g then c.pend[cid] = nil end end
end

function Cl.sendDm(c, u, text)
    text = cleanText(text)
    local m = c.mem[u]
    if not (text and m and rm and rm.seal and rm.sign) then return false, "Cannot send" end
    local ts = floor(nowSec())
    local sig = rm.sign("dm|" .. m.ipk .. "|" .. ts .. "|" .. text)
    if not sig then return false, "Slow down" end
    local env = rm.seal(m.xpk, ser({ x = text, ts = ts, sig = sig }))
    if not env then return false, "Cannot send" end
    local cid = c.nextCid
    c.nextCid = cid + 1
    local list = c.dms[m.ipk]
    if not list then list = {}; c.dms[m.ipk] = list end
    nextDmId = math.max(nextDmId, (list[#list] and list[#list].id or 0) + 1)
    local echo = { id = nextDmId, ts = ts, x = text, mine = true }
    nextDmId = nextDmId + 1
    list[#list + 1] = echo
    c.pend[cid] = { cid = cid, dm = true, echo = echo, t = { t = "dm", to = u, c = cid, env = env }, sent = nowSec(), tries = 1 }
    Cl.send(c, c.pend[cid].t)
    c.dirty = true
    R.dirty = true
    return true
end

function Cl.react(c, ch, n, e) Cl.send(c, { t = "rx", ch = ch, n = n, e = e }) end
function Cl.delete(c, ch, n) Cl.send(c, { t = "del", ch = ch, n = n }) end
function Cl.edit(c, ch, n, x) Cl.send(c, { t = "edit", ch = ch, n = n, x = x }) end
function Cl.mod(c, t) t.t = "mod"; Cl.send(c, t) end

-- Files -------------------------------------------------------------------------

function Cl.upload(c, ch, path, caption, reply)
    if not fs.exists(path) or fs.isDir(path) then return false, "No such file" end
    local size = fs.getSize(path)
    if size < 1 then return false, "File is empty" end
    if size > 524288 then return false, "File too big" end
    local data = readAll(path)
    if not data then return false, "Cannot read the file" end
    local fid = randHex(10)
    local n = math.max(1, math.ceil(#data / FILE_CHUNK))
    c.xfer[fid] = { up = true, fid = fid, nm = fs.getName(path), sz = #data, n = n, acked = 0, ch = ch, data = data,
        caption = caption, re = reply, started = nowSec() }
    R.dirty = true
    return true, fid
end

function Cl.download(c, f)
    if c.xfer[f.id] and not c.xfer[f.id].done then return end
    c.xfer[f.id] = { up = false, fid = f.id, nm = f.nm, sz = f.sz, next = 1, got = 0, n = 1, parts = {}, started = nowSec() }
    R.dirty = true
end

function Cl.xferStep(c)
    for fid, x in pairs(c.xfer) do
        if x.done then
            if nowSec() - (x.at or 0) > 20 then c.xfer[fid] = nil end
        elseif x.up then
            if not x.sentAt or nowSec() - x.sentAt > 3 then
                if (x.tries or 0) > 24 then xferDone(c, fid, false, "Host did not answer")
                else
                    local i = x.acked + 1
                    if i <= x.n then
                        local part = x.data:sub((i - 1) * FILE_CHUNK + 1, i * FILE_CHUNK)
                        local ok = Cl.send(c, { t = "fup", ch = x.ch, fid = fid, nm = x.nm, sz = x.sz, i = i, n = x.n, d = b64enc(part),
                            x = x.caption, re = x.re })
                        if ok then x.sentAt = nowSec(); x.tries = (x.tries or 0) + ((x.lastI == i) and 1 or 0); x.lastI = i end
                    else
                        xferDone(c, fid, true)
                    end
                end
            end
        else
            if not x.sentAt or nowSec() - x.sentAt > 3 then
                if (x.tries or 0) > 24 then xferDone(c, fid, false, "Host did not answer")
                else
                    local ok = Cl.send(c, { t = "fget", fid = fid, i = x.next })
                    if ok then x.sentAt = nowSec(); x.tries = (x.tries or 0) + ((x.lastI == x.next) and 1 or 0); x.lastI = x.next end
                end
            end
        end
    end
end

-- Once a second or so ---------------------------------------------------------

function Cl.tick()
    local t = nowSec()
    for rid, c in pairs(R.rooms) do
        -- typing indicators fade
        for u, ty in pairs(c.typing) do if t - ty.t > 5 then c.typing[u] = nil; R.dirty = true end end
        if c.state == "joining" or c.state == "waiting" then
            if t - c.joinTry > 8 then Cl.join(c) end
        elseif c.state == "online" or c.state == "offline" then
            if not c.nextHb or t >= c.nextHb then
                c.nextHb = t + 12
                Cl.send(c, { t = "hb", rv = c.rv, h = c.seq })
            end
            local was = c.state
            c.state = (t - (c.lastHead or 0) < 40) and "online" or "offline"
            if c.hostId == (R.me and R.me.id) then c.state = "online" end
            if was ~= c.state then R.dirty = true end
        end
        -- resend what was not answered
        for cid, p in pairs(c.pend) do
            if not p.acked and not p.failed and t - p.sent > 3 then
                if p.tries >= 3 then
                    p.failed = "No answer"
                    if p.echo then p.echo.failed = "No answer" end
                    R.dirty = true
                else
                    p.tries = p.tries + 1
                    p.sent = t
                    Cl.send(c, p.t)
                end
            elseif p.acked and t - p.sent > 8 then
                c.pend[cid] = nil
                if p.echo then p.echo.sending = nil end
            end
        end
        Cl.xferStep(c)
        if c.saveAt and t >= c.saveAt then c.saveAt = nil; Cl.saveCache(c) end
    end
    for k, f in pairs(R.found) do if t - f.seen > 70 then R.found[k] = nil end end
end

-- The loop queue holds packets this computer sent to itself.
function Cl.drainLoop()
    local n = 0
    while #R.loop > 0 and n < 40 do
        local pk = table.remove(R.loop, 1)
        n = n + 1
        pcall(Cl.incoming, pk)
    end
end

function Cl.saveAll()
    for _, c in pairs(R.rooms) do Cl.saveCache(c) end
    Cl.saveCfg()
    Host.saveAll()
end

function Cl.totalUnread()
    local n, m = 0, 0
    for _, c in pairs(R.rooms) do
        for _, ch in ipairs(c.chans) do n = n + Cl.unread(c, ch.id); m = m + (c.ment[ch.id] or 0) end
        for k in pairs(c.dms) do n = n + Cl.unreadDm(c, k) end
    end
    return n, m
end

-- ── Rooms: screen ────────────────────────────────────────────────────────────
local U = {
    room = nil, ch = nil, dm = nil,
    scroll = 0, atBottom = true, sel = nil,
    input = { text = "", pos = 0 },
    modal = nil, members = nil, ctrl = false,
    reply = nil, editing = nil, railTop = 0, memTop = 0,
    fx = {}, wipe = nil, splash = nil, lastType = 0, lastClick = 0, lastClickK = nil,
    strip = nil, msgRows = {}, compact = false,
}
local LAY = {}
local ICONS = {}

local function curRoom() return U.room and R.rooms[U.room] or nil end

local function roomList()
    local l = {}
    for rid, c in pairs(R.rooms) do l[#l + 1] = c end
    table.sort(l, function(a, b) return (a.order or 0) < (b.order or 0) or ((a.order or 0) == (b.order or 0) and a.name < b.name) end)
    return l
end

local function layout()
    W, H = term.getSize()
    U.compact = W < 40
    local L = { top = 2, bot = H - 2, strip = H - 1, inp = H }
    if U.compact then
        L.rail, L.chw, L.mpw = 0, 0, 0
    else
        L.rail = 5
        L.chw = clamp(floor(W * 0.3), 14, 22)
        local want = U.members
        if want == nil then want = W >= 66 end
        L.mpw = want and clamp(floor(W * 0.22), 13, 18) or 0
        if L.rail + L.chw + L.mpw + 24 > W then L.mpw = 0 end
    end
    if not curRoom() then L.chw = 0 end
    L.mx = L.rail + L.chw + 1
    L.mx2 = W - L.mpw
    L.mw = L.mx2 - L.mx + 1
    L.mpx = W - L.mpw + 1
    LAY = L
    return L
end

-- ── Messages: lines of a channel ────────────────────────────────────────────

local function wrapText(s, w)
    local out = {}
    if w < 4 then return { s:sub(1, math.max(1, w)) } end
    for para in (s .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            while #word > w do
                if line ~= "" then out[#out + 1] = line; line = "" end
                out[#out + 1] = word:sub(1, w)
                word = word:sub(w + 1)
            end
            if line == "" then line = word
            elseif #line + 1 + #word <= w then line = line .. " " .. word
            else out[#out + 1] = line; line = word end
        end
        out[#out + 1] = line
    end
    if #out == 0 then out[1] = "" end
    return out
end

local function nameColor(name)
    local pool = C.names
    return pool[(hash(name) % #pool) + 1] or C.text
end

local function userName(c, u)
    if u == 0 then return "Room" end
    local m = c.mem[u]
    return m and m.nm or ("user" .. tostring(u))
end

-- Builds display rows for a list of messages, newest last. Each row is
-- { kind, g, text, first, last } and holds only what draw needs.
local function buildRows(c, list, width, peer, newFrom)
    local rows = {}
    local prev, prev_new
    local tw = width - 5
    local isDm = peer ~= nil
    local from = math.max(1, #list - 70)
    for i = from, #list do
        local g = list[i]
        local author = isDm and (g.mine and (c.mem[c.u] and c.mem[c.u].nm or "You") or peer) or userName(c, g.u)
        local au = isDm and (g.mine and "me" or "peer") or g.u
        if newFrom and g.n and g.n > newFrom and not prev_new then
            prev_new = true
            rows[#rows + 1] = { k = "new" }
            prev = nil
        end
        if g.sy then
            rows[#rows + 1] = { k = "sys", g = g, text = g.x }
            prev = nil
        else
            local group = prev and prev.au == au and prev.ts and (g.ts - prev.ts) < 300 and not g.re and not (prev.f or prev.rx)
            local base = #rows
            if g.re and not isDm then
                local rg
                for _, o in ipairs(list) do if o.n == g.re then rg = o break end end
                rows[#rows + 1] = { k = "reply", g = g, text = rg and (userName(c, rg.u) .. ": " .. (rg.x ~= "" and rg.x or "[file]")) or "(message not loaded)" }
            end
            if not group then
                rows[#rows + 1] = { k = "head", g = g, name = author, au = au, ts = g.ts }
            end
            if g._wx ~= g.x or g._ww ~= tw then
                g._wl = wrapText(g.x or "", tw)
                g._wx, g._ww = g.x, tw
            end
            if g.x ~= "" or not g.f then
                for li, line in ipairs(g._wl) do
                    rows[#rows + 1] = { k = "text", g = g, text = line, avatar = (not group and li == 1) and (author) or nil, au = au }
                end
            end
            if g.f then
                rows[#rows + 1] = { k = "file", g = g }
            end
            if g.rx and not isDm then
                rows[#rows + 1] = { k = "rx", g = g }
            end
            if g.failed then rows[#rows + 1] = { k = "fail", g = g } end
            prev = { au = au, ts = g.ts, f = g.f, rx = g.rx }
            for j = base + 1, #rows do rows[j].mstart = base + 1 end
        end
    end
    return rows
end

local function fxAdd(kind, x, y, extra)
    local f = { kind = kind, x = x, y = y, t0 = nowSec() }
    if extra then for k, v in pairs(extra) do f[k] = v end end
    U.fx[#U.fx + 1] = f
    R.dirty = true
end

local function animating()
    if U.splash then return true end
    if #U.fx > 0 or U.wipe then return true end
    local c = curRoom()
    if c then
        for _, ty in pairs(c.typing) do if ty then return true end end
        for k, t in pairs(c.flash) do if nowSec() - t < 1.2 then return true end end
        for _, x in pairs(c.xfer) do if not x.done then return true end end
    end
    if #R.notes > 0 then return true end
    if U.modal and U.modal.anim then return true end
    return false
end

-- ── Rooms: drawing ───────────────────────────────────────────────────────────
local D = {}

local function roomsTheme()
    local function pickBg(list)
        for _, col in ipairs(list) do
            if col and gap(col, C.text) >= 0.35 and gap(col, C.bg) >= 0.05 then return col end
        end
        return C.bg
    end
    C.rowSel = pickBg({ C.bar, C.guide, C.rail, C.barBtn, C.hdr })
    C.rowFlash = pickBg({ C.barBtn, C.hdr, C.bar, C.rail })
    C.chip = C.bar
    if gap(C.chip, C.barText) < 0.3 then C.chip = C.barBtn end
    C.chipMine = C.sel
    C.mentionBg = C.accent
    C.mentionFg = (gap(colors.black, C.accent) >= gap(colors.white, C.accent)) and colors.black or colors.white
    C.railText = (gap(C.text, C.rail) >= 0.35) and C.text or ((gap(colors.white, C.rail) >= 0.35) and colors.white or colors.black)
    C.railDim = (gap(C.hint, C.rail) >= 0.22) and C.hint or C.railText
end
roomsTheme()

-- put with a clip to the right edge x2
local function putClip(x, y, text, fg, bg, x2)
    local room = (x2 or W) - x + 1
    if room <= 0 then return end
    put(x, y, text:sub(1, room), fg, bg)
end

local function mentionMe(c, word)
    local me = c.mem[c.u]
    if not me then return false end
    local w = word:sub(2):lower()
    return w == me.nm:lower():gsub(" ", "") or w == "everyone" or w == me.nm:lower()
end

local function putRich(x, y, text, fg, bg, c, x2)
    local pos = 1
    while pos <= #text do
        local s, e = text:find("[@#][%w_%-]+", pos)
        if not s then putClip(x + pos - 1, y, text:sub(pos), fg, bg, x2) break end
        if s > pos then putClip(x + pos - 1, y, text:sub(pos, s - 1), fg, bg, x2) end
        local word = text:sub(s, e)
        if word:sub(1, 1) == "@" then
            if mentionMe(c, word) then putClip(x + s - 1, y, word, C.mentionFg, C.mentionBg, x2)
            else putClip(x + s - 1, y, word, C.accent, bg, x2) end
        else
            putClip(x + s - 1, y, word, C.info, bg, x2)
        end
        pos = e + 1
    end
end

local ROLE_TAG = { [1] = "MOD", [2] = "ADMIN", [3] = "OWNER" }

function D.rail(L)
    if L.rail == 0 then return end
    for y = 2, H do put(1, y, string.rep(" ", L.rail), C.text, C.bg) end
    local y = 2
    -- home / menu
    local menuBg = (U.room == nil) and C.sel or C.chip
    local c = newCanvas(3, 2)
    rect(c, 1, 1, c.pw, c.ph, menuBg)
    -- a small "rooms" glyph: four squares
    local gcol = (U.room == nil) and C.selText or C.barText
    rect(c, 1, 1, 2, 2, gcol); rect(c, 5, 1, 6, 2, gcol); rect(c, 1, 5, 2, 6, gcol); rect(c, 5, 5, 6, 6, gcol)
    rect(c, 3, 3, 4, 4, gcol)
    renderOwn(c, 2, y, C.bg)
    addHit(1, L.rail, y, { a = "home" }, y + 1)
    y = y + 3
    local list = roomList()
    local capacity = floor((H - 1 - y - 3) / 3)
    U.railCap = capacity
    U.railTop = clamp(U.railTop or 0, 0, math.max(0, #list - capacity))
    for i = U.railTop + 1, math.min(#list, U.railTop + capacity) do
        local c2 = list[i]
        local on = (c2.rid == U.room)
        identicon(2, y, 3, 2, c2.name, nil)
        if on then
            for yy = y, y + 1 do put(1, yy, "\149", C.sel, C.bg) end
        end
        -- unread / state marks
        local un, men = 0, 0
        for _, ch in ipairs(c2.chans) do un = un + Cl.unread(c2, ch.id); men = men + (c2.ment[ch.id] or 0) end
        for k in pairs(c2.dms) do un = un + Cl.unreadDm(c2, k) end
        if un > 0 and not on then
            local pulse = (men > 0) and C.err or C.text
            put(5, y, men > 0 and "!" or "\7", pulse, C.bg)
            if not on and men == 0 then put(1, y, "\7", C.text, C.bg) end
        end
        if c2.state ~= "online" and c2.state ~= nil then put(5, y + 1, c2.state == "denied" and "x" or "\167", C.warn, C.bg) end
        addHit(1, L.rail, y, { a = "room", rid = c2.rid }, y + 1)
        y = y + 3
    end
    if #list > capacity then
        put(2, H - 1, "\30", C.dim, C.bg); addHit(2, 4, H - 1, { a = "railup" })
        put(4, H - 1, "\31", C.dim, C.bg); addHit(4, 5, H - 1, { a = "raildown" })
    end
    -- add button
    if y + 1 <= H - 2 then
        local ac = newCanvas(3, 2)
        rect(ac, 1, 1, ac.pw, ac.ph, C.chip)
        rect(ac, 3, 3, 4, 4, C.ok); rect(ac, 3, 2, 4, 5, C.ok); rect(ac, 2, 3, 5, 4, C.ok)
        renderOwn(ac, 2, y, C.bg)
        addHit(1, L.rail, y, { a = "join" }, y + 1)
    end
end

function D.channels(L)
    if L.chw == 0 then return end
    local x, w = L.rail + 1, L.chw
    for y = 2, H do put(x, y, string.rep(" ", w), C.railText, C.rail) end
    local c = curRoom()
    if not c then
        put(x + 1, 3, fit("Rooms", w - 2), C.railText, C.rail)
        put(x + 1, 5, fit("No Room open", w - 2), C.railDim, C.rail)
        return
    end
    -- room name bar
    put(x, 2, string.rep(" ", w), C.barText, C.barBtn)
    put(x + 1, 2, fit(c.name, w - 3), C.barText, C.barBtn)
    local dot = c.state == "online" and C.ok or (c.state == "offline" and C.err or C.warn)
    put(x + w - 2, 2, "\7", dot, C.barBtn)
    addHit(x, x + w - 1, 2, { a = "roommenu" })
    local y = 4
    put(x + 1, y - 1, fit("CHANNELS", w - 2), C.railDim, C.rail)
    for _, ch in ipairs(c.chans) do
        if y > H - 4 then break end
        local on = (U.ch == ch.id and not U.dm)
        local un = Cl.unread(c, ch.id)
        local men = c.ment[ch.id] or 0
        local bg = on and C.sel or C.rail
        local fg = on and C.selText or ((un > 0) and C.railText or C.railDim)
        put(x, y, string.rep(" ", w), fg, bg)
        local icon = ch.kd == "announce" and "!" or "#"
        put(x + 1, y, icon, on and C.selText or C.railDim, bg)
        put(x + 3, y, fit(ch.nm, w - 4 - ((un > 0 and not on) and 4 or 0)), fg, bg)
        if un > 0 and not on then
            local badge = men > 0 and (" " .. men .. " ") or (" " .. math.min(99, un) .. " ")
            put(x + w - #badge - 1, y, badge, men > 0 and C.mentionFg or C.barText, men > 0 and C.mentionBg or C.barBtn)
        end
        addHit(x, x + w - 1, y, { a = "chan", id = ch.id })
        y = y + 1
    end
    -- direct messages
    if y <= H - 6 then
        y = y + 1
        put(x + 1, y, fit("DIRECT MESSAGES", w - 2), C.railDim, C.rail)
        y = y + 1
        local peers = {}
        for ipk, list in pairs(c.dms) do
            local u = c.byIpk[ipk]
            if u and c.mem[u] and #list > 0 then peers[#peers + 1] = { ipk = ipk, u = u, last = list[#list].ts or 0 } end
        end
        table.sort(peers, function(a, b) return a.last > b.last end)
        for _, p in ipairs(peers) do
            if y > H - 4 then break end
            local m = c.mem[p.u]
            local on = (U.dm == p.ipk)
            local un = Cl.unreadDm(c, p.ipk)
            local bg = on and C.sel or C.rail
            local fg = on and C.selText or ((un > 0) and C.railText or C.railDim)
            put(x, y, string.rep(" ", w), fg, bg)
            put(x + 1, y, m.on and "\7" or "\7", m.on and C.ok or (on and C.selText or C.railDim), bg)
            put(x + 3, y, fit(m.nm, w - 8), fg, bg)
            if un > 0 and not on then
                local badge = " " .. math.min(99, un) .. " "
                put(x + w - #badge - 1, y, badge, C.barText, C.barBtn)
            end
            addHit(x, x + w - 1, y, { a = "dm", ipk = p.ipk })
            y = y + 1
        end
        if #peers == 0 and y <= H - 4 then
            put(x + 1, y, fit("Click a name", w - 2), C.railDim, C.rail)
        end
    end
    -- you
    local me = c.mem[c.u]
    local uy = H
    put(x, uy - 1, string.rep(" ", w), C.railText, C.rail)
    put(x, uy, string.rep(" ", w), C.railText, C.rail)
    if me then
        identicon(x + 1, uy - 1, 2, 2, me.nm, nil)
        put(x + 4, uy - 1, fit(me.nm, w - 5), C.railText, C.rail)
        put(x + 4, uy, fit(ROLE_NAME[me.ro] or "", w - 5), C.railDim, C.rail)
    end
end

function D.members(L)
    if L.mpw == 0 then return end
    local c = curRoom()
    local x, w = L.mpx, L.mpw
    for y = 2, H do put(x, y, string.rep(" ", w), C.railText, C.rail) end
    if not c then return end
    local list = {}
    for _, m in pairs(c.mem) do list[#list + 1] = m end
    table.sort(list, function(a, b)
        if (a.on and 1 or 0) ~= (b.on and 1 or 0) then return a.on end
        if a.ro ~= b.ro then return a.ro > b.ro end
        return a.nm:lower() < b.nm:lower()
    end)
    local y = 2
    put(x + 1, y, fit("MEMBERS " .. #list, w - 2), C.railDim, C.rail)
    y = y + 1
    local cap = H - 1 - y
    U.memTop = clamp(U.memTop or 0, 0, math.max(0, #list - cap))
    for i = U.memTop + 1, math.min(#list, U.memTop + cap) do
        local m = list[i]
        local fg = m.on and nameColor(m.nm) or C.railDim
        put(x, y, string.rep(" ", w), fg, C.rail)
        put(x + 1, y, "\7", m.on and C.ok or C.railDim, C.rail)
        put(x + 3, y, fit(m.nm, w - 4 - (ROLE_TAG[m.ro] and 1 or 0)), fg, C.rail)
        if m.ro >= 1 then put(x + w - 1, y, m.ro == 3 and "\4" or (m.ro == 2 and "*" or "+"), C.accent, C.rail) end
        addHit(x, x + w - 1, y, { a = "member", u = m.u })
        y = y + 1
    end
end

local function fileLine(c, g, y, x, x2, bg)
    local f = g.f
    put(x, y, "[F]", C.accent, bg)
    local label = fit(f.nm, math.max(6, x2 - x - 22))
    put(x + 4, y, label, C.info, bg)
    put(x + 5 + #label, y, fmtSize(f.sz), C.dim, bg)
    local xf = c.xfer[f.id]
    local bx = x2 - 11
    if xf and not xf.up and not xf.done then
        local frac = (xf.got or 0) / math.max(1, xf.n or 1)
        local cells = 10
        local cv = newCanvas(cells, 1)
        for px = 1, cv.pw do cv[2][px] = C.bar end
        for px = 1, floor(cv.pw * frac) do cv[2][px] = C.ok end
        render(cv, bx, y, bg)
    elseif xf and xf.done then
        if xf.ok then put(bx - 4, y, "Saved to downloads/rooms", C.ok, bg)
        else put(bx, y, fit(xf.why or "Failed", 11), C.err, bg) end
    else
        local t = " Download "
        put(x2 - #t + 1, y, t, C.barText, C.barBtn)
        addHit(x2 - #t + 1, x2, y, { a = "download", f = f })
    end
end

function D.rowDraw(c, row, y, L, state)
    local x, x2 = L.mx + 1, L.mx2 - 1
    local g = row.g
    local bg = C.bg
    if state.sel then bg = C.rowSel
    elseif g and g.n and c.flash[state.ch .. ":" .. g.n] then
        local age = nowSec() - c.flash[state.ch .. ":" .. g.n]
        if age < 0.7 then bg = C.rowFlash else c.flash[state.ch .. ":" .. g.n] = nil end
    end
    put(L.mx, y, string.rep(" ", L.mw), C.text, bg)
    local mine = g and ((state.dm and g.mine) or (not state.dm and g.u == c.u))
    local hitKey
    if g and not g.local_ or (g and g.local_) then hitKey = { a = "msg", g = g } end
    local k = row.k
    if k == "sys" then
        local t = "- " .. row.text .. " -"
        put(x + math.max(0, floor((x2 - x + 1 - #t) / 2)), y, fit(t, x2 - x + 1), C.dim, bg)
        return
    elseif k == "new" then
        put(L.mx, y, string.rep("-", L.mw), C.err, C.bg)
        put(x2 - 3, y, " NEW", C.err, C.bg)
        return
    elseif k == "reply" then
        put(x + 3, y, "\149", C.dim, bg)
        putClip(x + 5, y, fit(row.text, x2 - x - 5), C.dim, bg, x2)
        if hitKey then addHit(L.mx, L.mx2, y, hitKey) end
        return
    elseif k == "head" then
        local nameCol = nameColor(row.name)
        put(x + 3, y, row.name, nameCol, bg)
        local px = x + 4 + #row.name
        local m = (not state.dm) and c.mem[row.g.u]
        if m and ROLE_TAG[m.ro] then
            put(px, y, ROLE_TAG[m.ro], C.accent, bg)
            px = px + #ROLE_TAG[m.ro] + 1
        end
        put(px, y, fmtClock(row.ts), C.dim, bg)
        px = px + 6
        if g.ed then put(px, y, "(edited)", C.dim, bg) end
        if g.sending and not g.failed then put(x2 - 7, y, "sending", C.dim, bg) end
    elseif k == "text" then
        local fg = C.text
        if g.sending or g.failed then fg = g.failed and C.err or C.dim end
        putRich(x + 3, y, row.text, fg, bg, c, x2)
        if state.mention then put(L.mx, y, "\149", C.accent, bg) end
    elseif k == "file" then
        fileLine(c, g, y, x + 3, x2, bg)
    elseif k == "rx" then
        local cx = x + 3
        for _, e in ipairs(REACT) do
            local list = g.rx[e]
            if list then
                local mineR = false
                for _, u in ipairs(list) do if u == c.u then mineR = true end end
                local t = " " .. e .. " " .. #list .. " "
                if cx + #t - 1 > x2 then break end
                put(cx, y, t, mineR and C.selText or C.barText, mineR and C.chipMine or C.chip)
                addHit(cx, cx + #t - 1, y, { a = "react", g = g, e = e })
                cx = cx + #t + 1
            end
        end
        return
    elseif k == "fail" then
        put(x + 3, y, "! " .. fit(g.failed, 20), C.err, bg)
        local b1 = " Retry "
        put(x + 26, y, b1, C.barText, C.barBtn); addHit(x + 26, x + 25 + #b1, y, { a = "retry", g = g })
        put(x + 34, y, " Drop ", C.barText, C.barBtn); addHit(x + 34, x + 39, y, { a = "drop", g = g })
        return
    end
    if hitKey then addHit(L.mx, L.mx2, y, hitKey) end
end

function D.avatars(rows, firstRow, L, c, state)
end

function D.messages(L, c)
    local top, bot = L.top, L.bot
    local viewH = bot - top + 1
    for y = top, bot do put(L.mx, y, string.rep(" ", L.mw), C.text, C.bg) end
    local list, peer
    if U.dm then
        list = c.dms[U.dm] or {}
        local u = c.byIpk[U.dm]
        peer = u and c.mem[u] and c.mem[u].nm or "?"
    else
        list = c.hist[U.ch] or {}
    end
    local rows = buildRows(c, list, L.mw, peer, U.newFrom)
    U.rows = rows
    local total = #rows
    local maxScroll = math.max(0, total - viewH)
    U.scroll = clamp(U.scroll, 0, maxScroll)
    if U.ensure and U.sel then
        local r0, r1
        for i, row in ipairs(rows) do if row.g == U.sel then r0 = r0 or i; r1 = i end end
        if r0 then
            local lastRow = total - U.scroll
            if r1 > lastRow then U.scroll = total - r1
            elseif r0 < lastRow - viewH + 1 then U.scroll = total - (r0 + viewH - 1) end
            U.scroll = clamp(U.scroll, 0, maxScroll)
        end
    end
    U.ensure = false
    U.atBottom = U.scroll == 0
    local last = total - U.scroll
    local first = math.max(1, last - viewH + 1)
    local y = bot - (last - first)
    if total < viewH then y = top + (viewH - total) end     -- short channels sit at the bottom
    if total == 0 then
        local t = U.dm and ("This is the start of your talk with " .. tostring(peer)) or "No messages yet. Say hello."
        put(L.mx + 2, top + 1, fit(t, L.mw - 3), C.dim, C.bg)
        return
    end
    -- selected message rows
    local selG = U.sel
    local mentionOf = {}
    local startY = y
    for i = first, last do
        local row = rows[i]
        local g = row.g
        local isSel = selG and g == selG
        local men = g and not g.sy and not U.dm and g.u ~= c.u and Cl.mentions(c, g.x or "")
        D.rowDraw(c, row, y, L, { sel = isSel, ch = U.ch, dm = U.dm, mention = men })
        if row.k == "head" then
            local h = (y + 1 <= bot) and 2 or 1
            identicon(L.mx + 1, y, 2, h, row.name, nil)
        end
        y = y + 1
    end
    -- "new messages" pill
    if U.scroll > 0 then
        local t = " " .. "\31" .. " Jump to latest "
        put(L.mx2 - #t, bot, t, C.barText, C.barBtn)
        addHit(L.mx2 - #t, L.mx2 - 1, bot, { a = "bottom" })
    end
end

function D.strip(L, c)
    local y = L.strip
    put(L.mx, y, string.rep(" ", L.mw), C.hint, C.bg)
    local x = L.mx
    local g = U.sel
    if g then
        put(x, y, "", C.hint, C.bg)
        local bx = x + 1
        local function btn(label, k)
            if bx + #label + 1 > W then return end
            put(bx, y, " " .. label .. " ", C.barText, C.barBtn)
            addHit(bx, bx + #label + 1, y, k)
            bx = bx + #label + 3
        end
        if g.failed then btn("Retry", { a = "retry", g = g }); btn("Drop", { a = "drop", g = g })
        else
            if not U.dm then btn("Reply", { a = "do", d = "reply" }); btn("React", { a = "do", d = "react" }) end
            local mine = (U.dm and g.mine) or (not U.dm and g.u == c.u)
            if mine and not g.f and not U.dm then btn("Edit", { a = "do", d = "edit" }) end
            if (mine or c.ro >= 1) and not U.dm then btn("Delete", { a = "do", d = "delete" }) end
            if g.f then btn("Download", { a = "download", f = g.f }) end
        end
        btn("Close", { a = "do", d = "close" })
        return
    end
    if U.reply then
        local rg = U.reply
        local t = "Replying to " .. userName(c, rg.u) .. ": " .. (rg.x or "")
        put(x + 1, y, fit(t, L.mw - 6), C.accent, C.bg)
        put(L.mx2 - 3, y, "[x]", C.err, C.bg); addHit(L.mx2 - 3, L.mx2 - 1, y, { a = "cancelreply" })
        return
    end
    if U.editing then
        put(x + 1, y, fit("Editing your message. Enter saves, Esc cancels.", L.mw - 6), C.warn, C.bg)
        return
    end
    -- transfers
    for _, xf in pairs(c.xfer) do
        if xf.up and not xf.done then
            local frac = (xf.acked or 0) / math.max(1, xf.n)
            put(x + 1, y, fit("Uploading " .. xf.nm, 24), C.info, C.bg)
            local cv = newCanvas(10, 1)
            for px = 1, cv.pw do cv[2][px] = C.bar end
            for px = 1, floor(cv.pw * frac) do cv[2][px] = C.ok end
            render(cv, x + 27, y, C.bg)
            return
        end
    end
    local n = R.notes[#R.notes]
    if n and nowSec() - n.t < 5 then
        put(x + 1, y, fit(n.text, L.mw - 2), n.kind == "warn" and C.warn or C.info, C.bg)
        return
    end
    -- typing
    local names = {}
    for u, ty in pairs(c.typing) do
        if ty.ch == U.ch and u ~= c.u then names[#names + 1] = userName(c, u) end
    end
    if #names > 0 and not U.dm then
        local text = (#names == 1) and (names[1] .. " is typing") or ((#names == 2) and (names[1] .. " and " .. names[2] .. " are typing") or "Several people are typing")
        local ph = floor(nowSec() * 3) % 4
        put(x + 1, y, fit(text, L.mw - 6), C.dim, C.bg)
        put(x + 1 + math.min(#text, L.mw - 6), y, string.rep(".", ph), C.accent, C.bg)
        return
    end
    -- hints
    local hint = {}
    if U.compact then
        hint = { { "Tab", "rooms" }, { "Up", "messages" }, { "F1", "help" } }
    else
        hint = { { "Up", "pick a message" }, { "Tab", "next channel" }, { "Ctrl+K", "jump" }, { "F1", "help" } }
    end
    local hx = x + 1
    for _, it in ipairs(hint) do
        local need = #it[1] + 1 + #it[2]
        if hx + need > L.mx2 then break end
        put(hx, y, it[1], C.line, C.bg)
        put(hx + #it[1] + 1, y, it[2], C.hint, C.bg)
        hx = hx + need + 2
    end
end

function D.input(L, c)
    local y = L.inp
    put(L.mx, y, string.rep(" ", L.mw), C.text, C.bg)
    local x = L.mx
    local ch = U.dm and nil or Cl.chanOf(c, U.ch)
    local locked = ch and ch.kd == "announce" and c.ro < 1
    put(x, y, " + ", C.barText, C.barBtn)
    addHit(x, x + 2, y, { a = "attach" })
    local fx = x + 4
    local fw = L.mx2 - fx - 6
    if fw < 4 then return end
    local ph
    if locked then ph = "Only staff post here"
    elseif U.dm then
        local u = c.byIpk[U.dm]
        ph = "Message " .. (u and c.mem[u] and c.mem[u].nm or "")
    else ph = "Message #" .. (ch and ch.nm or "") end
    local focus = not U.sel and not U.modal
    if #U.input.text == 0 then
        put(fx, y, pad(ph, fw), C.dim, C.bg)
        if focus then put(fx, y, ph:sub(1, 1), C.bg, C.text) end
    else
        fieldDraw(fx, y, fw, U.input, C.text, C.bg)
    end
    put(L.mx2 - 5, y, " Send ", C.barText, C.barBtn)
    addHit(L.mx2 - 5, L.mx2, y, { a = "send" })
end

function D.topbar(L, c)
    put(1, 1, string.rep(" ", W), C.barText, C.bar)
    if U.compact then
        put(1, 1, " \127 ", C.barText, C.barBtn)
        addHit(1, 3, 1, { a = "nav" })
    else
        put(1, 1, " Rooms ", C.barText, C.barBtn)
    end
    local x = U.compact and 5 or 9
    if c then
        local ch = (not U.dm) and Cl.chanOf(c, U.ch)
        local title
        if U.dm then
            local u = c.byIpk[U.dm]
            title = "@ " .. (u and c.mem[u] and c.mem[u].nm or "")
        else title = (ch and (ch.kd == "announce" and "! " or "# ") .. ch.nm or "") end
        if U.compact then title = c.name .. "  " .. title end
        put(x, 1, fit(title, W - x - 12), C.barText, C.bar)
        if ch and ch.tp and ch.tp ~= "" and not U.compact then
            local tx = x + #title + 2
            if tx < W - 14 then put(tx, 1, fit(ch.tp, W - tx - 12), C.hint, C.bar) end
        end
    else
        put(x, 1, "Welcome", C.barText, C.bar)
    end
    local bx = W
    local function tb(label, k)
        local t = " " .. label .. " "
        bx = bx - #t
        put(bx + 1, 1, t, C.barText, C.barBtn)
        addHit(bx + 1, bx + #t, 1, k)
        bx = bx - 1
    end
    tb("Menu", { a = "menu" })
    if c and not U.compact then tb("People", { a = "people" }) end
    local un, men = Cl.totalUnread()
    if un > 0 then
        local t = men > 0 and ("@" .. men) or tostring(un)
        put(bx - #t, 1, t, men > 0 and C.warn or C.hint, C.bar)
    end
end


-- ── Rooms: forms, menus and windows ──────────────────────────────────────────
local UI = {}
local Form = {}

function Form.focusable(it, f)
    if it.show and not it.show(f) then return false end
    return it.t == "text" or it.t == "choice" or it.t == "buttons"
end
function Form.new(items, on)
    local f = { items = items, focus = 1, on = on }
    for i, it in ipairs(items) do if Form.focusable(it, f) then f.focus = i break end end
    return f
end
function Form.get(f, id)
    for _, it in ipairs(f.items) do
        if it.id == id then
            if it.t == "text" then return it.st.text end
            if it.t == "choice" then return it.i, it.opts[it.i] end
        end
    end
end
function Form.step(f, d)
    local n = #f.items
    local i = f.focus
    for _ = 1, n do
        i = ((i - 1 + d) % n) + 1
        if Form.focusable(f.items[i], f) then f.focus = i return end
    end
end
function Form.height(f, w)
    local n = 0
    for _, it in ipairs(f.items) do
        if not it.show or it.show(f) then
            if it.t == "label" then n = n + #wrapText(it.text, w)
            elseif it.t == "text" then n = n + 2
            else n = n + 1 end
        end
    end
    return n
end
function Form.draw(f, x, y, w)
    for idx, it in ipairs(f.items) do
        if not it.show or it.show(f) then
            local on = f.focus == idx
            if it.t == "label" then
                for _, line in ipairs(wrapText(it.text, w)) do
                    put(x, y, pad(line, w), it.fg or C.dim, C.panel)
                    y = y + 1
                end
            elseif it.t == "gap" then
                y = y + 1
            elseif it.t == "text" then
                put(x, y, pad(it.label, w), on and C.text or C.dim, C.panel)
                y = y + 1
                local fb = on and C.bar or C.bg
                local ff = on and C.barText or C.text
                put(x, y, string.rep(" ", w), ff, fb)
                fieldDraw(x + 1, y, w - 2, it.st, ff, fb, it.mask, not on)
                addHit(x, x + w - 1, y, { a = "form", idx = idx })
                y = y + 1
            elseif it.t == "choice" then
                local label = it.label .. ": "
                put(x, y, pad(label, w), on and C.text or C.dim, C.panel)
                local v = " " .. tostring(it.opts[it.i]) .. " "
                put(x + #label, y, "<" .. v .. ">", on and C.selText or C.barText, on and C.sel or C.barBtn)
                addHit(x, x + w - 1, y, { a = "form", idx = idx })
                y = y + 1
            elseif it.t == "buttons" then
                local bx = x
                for bi, b in ipairs(it.list) do
                    local t = " " .. b.label .. " "
                    local sel = on and (it.sel or 1) == bi
                    put(bx, y, t, sel and C.selText or C.barText, sel and C.sel or C.barBtn)
                    addHit(bx, bx + #t - 1, y, { a = "form", idx = idx, btn = bi })
                    bx = bx + #t + 1
                end
                y = y + 1
            end
        end
    end
    return y
end
function Form.key(f, key)
    local it = f.items[f.focus]
    if not it then return false end
    if key == keys.tab or key == keys.down then Form.step(f, 1) return true end
    if key == keys.up then Form.step(f, -1) return true end
    if it.t == "text" then
        if editKey(it.st, key) then return true end
        if key == keys.enter then
            if f.submit then f.submit(f) else Form.step(f, 1) end
            return true
        end
    elseif it.t == "choice" then
        if key == keys.left then it.i = ((it.i - 2) % #it.opts) + 1 return true end
        if key == keys.right or key == keys.enter or key == keys.space then it.i = (it.i % #it.opts) + 1 return true end
    elseif it.t == "buttons" then
        if key == keys.left then it.sel = math.max(1, (it.sel or 1) - 1) return true end
        if key == keys.right then it.sel = math.min(#it.list, (it.sel or 1) + 1) return true end
        if key == keys.enter or key == keys.space then
            local b = it.list[it.sel or 1]
            if b and f.on then f.on(b.id, f) end
            return true
        end
    end
    return false
end
function Form.char(f, ch)
    local it = f.items[f.focus]
    if it and it.t == "text" then editChar(it.st, ch, it.max or 60) return true end
    return false
end
function Form.click(f, k)
    local it = f.items[k.idx]
    if not it then return end
    f.focus = k.idx
    if it.t == "choice" then it.i = (it.i % #it.opts) + 1
    elseif it.t == "text" then it.st.pos = #it.st.text
    elseif it.t == "buttons" then
        it.sel = k.btn
        local b = it.list[k.btn]
        if b and f.on then f.on(b.id, f) end
    end
end
local function tfield(id, label, text, max, mask, show)
    return { t = "text", id = id, label = label, st = { text = text or "", pos = #(text or "") }, max = max, mask = mask, show = show }
end

-- ── Modal frame ──────────────────────────────────────────────────────────────

function UI.open(m)
    U.modal = m
    U.sel = nil
    R.dirty = true
    if m.onOpen then m.onOpen(m) end
end
function UI.close()
    local m = U.modal
    U.modal = nil
    if m and m.onClose then m.onClose(m) end
    Net.listen(false)
    R.dirty = true
end

function D.modal()
    local m = U.modal
    U.modalBase = #hits
    if not m then return end
    if m.fit then m.fit(m) end
    local w = clamp(m.w or 38, 24, W - 2)
    if m.form and not m.draw and not m.fixedH then m.h = Form.height(m.form, w - 4) + 4 end
    local h = clamp(m.h or 12, 6, H - 2)
    local x = floor((W - w) / 2) + 1
    local y = floor((H - h) / 2) + 1
    box(x, y, w, h)
    put(x + 2, y, " " .. fit(m.title or "", w - 10) .. " ", C.barText, C.barBtn)
    put(x + w - 4, y, " x ", C.barText, C.barBtn)
    addHit(x + w - 4, x + w - 2, y, { a = "mclose" })
    m.r = { x = x, y = y, w = w, h = h }
    local ix, iy, iw, ih = x + 2, y + 2, w - 4, h - 3
    for yy = y + 1, y + h - 2 do put(x + 1, yy, string.rep(" ", w - 2), C.text, C.panel) end
    local ny = iy
    if m.draw then ny = m.draw(m, ix, iy, iw, ih) or iy end
    if m.form then Form.draw(m.form, ix, ny, iw) end
end

-- A list the person picks from. items = { { label, right, fn, key } }
function UI.pick(opts)
    local m = {
        title = opts.title, items = opts.items, sel = 1, top = 0, w = opts.w or 36, h = opts.h or 14,
        filter = opts.filter, st = { text = "", pos = 0 }, head = opts.head, headH = opts.headH or 0,
        empty = opts.empty or "Nothing here", onPick = opts.onPick,
    }
    function m.visible()
        local out = {}
        local q = m.st.text:lower()
        for _, it in ipairs(m.items) do
            if q == "" or it.label:lower():find(q, 1, true) then out[#out + 1] = it end
        end
        return out
    end
    function m.draw(self, x, y, w, h)
        if self.head then y = self.head(self, x, y, w) end
        if self.filter then
            put(x, y, string.rep(" ", w), C.barText, C.bar)
            fieldDraw(x + 1, y, w - 2, self.st, C.barText, C.bar, false, false)
            if #self.st.text == 0 then put(x + 1, y, "Type to search", C.hint, C.bar) end
            y = y + 2
        end
        local list = self.visible()
        local cap = h - (y - (self.r.y + 2)) - 0
        cap = math.max(1, self.r.y + self.r.h - 2 - y)
        self.sel = clamp(self.sel, 1, math.max(1, #list))
        if self.sel <= self.top then self.top = self.sel - 1 end
        if self.sel > self.top + cap then self.top = self.sel - cap end
        self.top = clamp(self.top, 0, math.max(0, #list - cap))
        if #list == 0 then put(x, y, fit(self.empty, w), C.dim, C.panel) end
        for i = self.top + 1, math.min(#list, self.top + cap) do
            local it = list[i]
            local on = i == self.sel
            local bg = on and C.sel or C.panel
            local fg = on and C.selText or (it.dim and C.dim or C.text)
            put(x, y, string.rep(" ", w), fg, bg)
            local right = it.right or ""
            put(x + 1, y, fit(it.label, w - 3 - #right), fg, bg)
            if right ~= "" then put(x + w - #right - 1, y, right, on and C.selText or (it.rightFg or C.hint), bg) end
            addHit(x, x + w - 1, y, { a = "pick", i = i })
            y = y + 1
        end
        return y
    end
    function m.activate(self, i)
        local list = self.visible()
        local it = list[i or self.sel]
        if it and it.fn then
            UI.close()
            it.fn(it)
        end
    end
    function m.key(self, key)
        local list = self.visible()
        if key == keys.up then self.sel = math.max(1, self.sel - 1) return true end
        if key == keys.down then self.sel = math.min(#list, self.sel + 1) return true end
        if key == keys.pageUp then self.sel = math.max(1, self.sel - 5) return true end
        if key == keys.pageDown then self.sel = math.min(#list, self.sel + 5) return true end
        if key == keys.enter then self:activate() return true end
        if self.filter and editKey(self.st, key) then self.sel = 1 return true end
        return false
    end
    function m.char(self, ch)
        if self.filter then editChar(self.st, ch, 30); self.sel = 1 return true end
        return false
    end
    function m.click(self, k)
        if k.a == "pick" then
            if self.sel == k.i then self:activate(k.i) else self.sel = k.i end
        end
    end
    function m.scroll(self, d) self.sel = clamp(self.sel + d, 1, math.max(1, #self.visible())) end
    return m
end

function UI.message(title, lines, buttons)
    local m = { title = title, w = 40, h = #lines + 5 }
    local items = { { t = "label", text = table.concat(lines, "\n") } }
    local wrapped = 0
    for _, l in ipairs(lines) do wrapped = wrapped + 1 end
    items[#items + 1] = { t = "gap" }
    local bl = {}
    for _, b in ipairs(buttons or { { label = "OK", id = "ok" } }) do bl[#bl + 1] = b end
    items[#items + 1] = { t = "buttons", list = bl }
    m.form = Form.new(items, function(id)
        UI.close()
        for _, b in ipairs(bl) do if b.id == id and b.fn then b.fn() end end
    end)
    m.form.focus = #items
    function m.fit(self)
        local w = clamp(self.w, 24, W - 2)
        local n = 0
        for _, l in ipairs(lines) do n = n + #wrapText(l, w - 4) end
        self.h = n + 5
    end
    return m
end

function UI.confirm(title, text, yes, fn)
    UI.open(UI.message(title, { text }, { { label = yes, id = "y", fn = fn }, { label = "Cancel", id = "n" } }))
end

-- ── First run: a name ────────────────────────────────────────────────────────

function UI.askName(after)
    local me = Net.refreshMe()
    local default = R.cfg.name or cleanName(me and me.name or "") or ""
    local m = { title = "Your name", w = 38, h = 11 }
    m.form = Form.new({
        { t = "label", text = "This is the name people see in Rooms. You can change it later." },
        tfield("nm", "Name", default, 20),
        { t = "gap" },
        { t = "buttons", list = { { label = "Save", id = "ok" }, { label = "Cancel", id = "no" } } },
    }, function(id, f)
        if id == "no" then UI.close() return end
        local nm = cleanName(Form.get(f, "nm"))
        if not nm then note("Use 2 to 20 letters or digits", "warn") return end
        R.cfg.name = nm
        Cl.saveCfg()
        UI.close()
        if after then after() end
    end)
    m.form.submit = function(f) m.form.on("ok", f) end
    m.form.focus = 2
    UI.open(m)
end

-- ── Create a Room ────────────────────────────────────────────────────────────

function UI.askBackground()
    local bg = osApi and osApi.background
    if type(bg) == "table" and type(bg.request) == "function" then
        local ok, allowed = pcall(bg.request)
        R.bgAllowed = ok and allowed == true
        if not R.bgAllowed then note("Without background permission your Room goes quiet when you leave this app.", "warn") end
    end
end

function UI.create()
    if not R.cfg.name then UI.askName(UI.create) return end
    local m = { title = "Create a Room", w = 42, h = 15 }
    m.form = Form.new({
        tfield("nm", "Room name", "", 20),
        { t = "choice", id = "md", label = "Who can join", opts = { "Anyone nearby", "Password", "You approve" }, i = 1 },
        tfield("pw", "Password", "", 30, true, function(f) return Form.get(f, "md") == 2 end),
        { t = "label", text = "The Room lives on this computer. Keep this app running so people can reach it." },
        { t = "buttons", list = { { label = "Create", id = "ok" }, { label = "Cancel", id = "no" } } },
    }, function(id, f)
        if id == "no" then UI.close() return end
        local mdi = Form.get(f, "md")
        local mode = (mdi == 2) and "password" or ((mdi == 3) and "approval" or "open")
        local pw = Form.get(f, "pw")
        if mode == "password" and #pw < 3 then note("Password needs 3 characters", "warn") return end
        local room, why = Host.create(Form.get(f, "nm"), mode, pw)
        if not room then note(why or "Cannot create", "warn") return end
        local me = R.me
        local c = Cl.addRoom({ rid = room.rid, nm = room.name, hostId = me.id, hostIpk = me.ipk, hostXpk = me.xpk, md = mode })
        UI.close()
        UI.goRoom(room.rid)
        UI.askBackground()
        Net.listen(false)
    end)
    m.form.submit = function(f) m.form.on("ok", f) end
    UI.open(m)
end

-- ── Join a Room ──────────────────────────────────────────────────────────────

function UI.join()
    if not R.cfg.name then UI.askName(UI.join) return end
    local m = { title = "Join a Room", w = 46, h = 17, tab = 1, sel = 1, stage = "pick", anim = true }
    m.codeForm = Form.new({
        { t = "label", text = "Ask the host for the host number and the Room code. Example: 12 a1b2c3d4" },
        tfield("code", "Host number and code", "", 30),
        { t = "buttons", list = { { label = "Look up", id = "ok" } } },
    }, function(id, f)
        local hid, rid = Form.get(f, "code"):match("^%s*(%d+)[%s:,]+(%x+)%s*$")
        if not hid then note("Type the number, a space, then the code", "warn") return end
        m.wait = { hostId = tonumber(hid), rid = rid:lower(), t = nowSec() }
        R.wantInfo = m.wait
        R.info = nil
        Net.send(m.wait.hostId, { t = "hello", r = m.wait.rid })
        Net.send(m.wait.hostId, { t = "hello", r = m.wait.rid })
    end)
    m.codeForm.submit = function(f) m.codeForm.on("ok", f) end
    m.codeForm.focus = 2
    function m.nearby()
        local out = {}
        for key, f in pairs(R.found) do
            if not R.rooms[f.rid] then out[#out + 1] = f end
        end
        table.sort(out, function(a, b) return a.nm:lower() < b.nm:lower() end)
        return out
    end
    function m.pickInfo(info)
        m.info = info
        m.stage = "confirm"
        m.form = Form.new({
            { t = "label", text = "Host key " .. tostring(info.fp) .. ". You trust this key from now on. Check it with the host if you are unsure.", fg = C.warn },
            tfield("pw", "Password", "", 30, true, function() return info.md == "password" end),
            { t = "gap" },
            { t = "buttons", list = { { label = "Join", id = "ok" }, { label = "Back", id = "no" } } },
        }, function(id, f)
            if id == "no" then m.stage, m.form, m.info = "pick", nil, nil return end
            if info.md == "password" and #Form.get(f, "pw") < 1 then note("This Room needs a password", "warn") return end
            local c = Cl.addRoom(info, Form.get(f, "pw"))
            UI.close()
            UI.goRoom(info.rid)
            note("Asking " .. info.nm .. " to let you in", "info")
        end)
        m.form.submit = function(f) m.form.on("ok", f) end
        m.form.focus = (info.md == "password") and 2 or 4
    end
    function m.draw(self, x, y, w, h)
        if R.info and self.wait and R.info.rid == self.wait.rid then
            local info = R.info
            R.info = nil; self.wait = nil
            self:pickInfo(info)
        end
        if self.stage == "confirm" then
            local info = self.info
            put(x, y, fit(info.nm, w), C.text, C.panel)
            put(x, y + 1, fit("Host: " .. tostring(info.o) .. " (computer " .. info.hostId .. ")  " .. info.mc .. " in the Room", w), C.dim, C.panel)
            put(x, y + 2, fit("Access: " .. (info.md == "open" and "anyone" or (info.md == "password" and "password" or "approval by staff")), w), C.dim, C.panel)
            identicon(x + w - 4, y, 3, 2, info.nm, nil)
            return y + 4
        end
        local tabs = { "Nearby", "By code" }
        local tx = x
        for i, t in ipairs(tabs) do
            local label = " " .. t .. " "
            put(tx, y, label, self.tab == i and C.selText or C.barText, self.tab == i and C.sel or C.barBtn)
            addHit(tx, tx + #label - 1, y, { a = "jtab", i = i })
            tx = tx + #label + 1
        end
        y = y + 2
        if self.tab == 1 then
            local list = self:nearby()
            if #list == 0 then
                put(x, y, fit("Looking for Rooms in range...", w), C.dim, C.panel)
                local ph = floor(nowSec() * 3) % 4
                put(x, y + 1, string.rep(".", ph), C.accent, C.panel)
                put(x, y + 3, fit("Hosts announce their Room every 20 seconds.", w), C.dim, C.panel)
            end
            self.sel = clamp(self.sel, 1, math.max(1, #list))
            local cap = self.r.y + self.r.h - 2 - y
            for i = 1, math.min(#list, cap) do
                local f = list[i]
                local on = i == self.sel
                local bg = on and C.sel or C.panel
                put(x, y, string.rep(" ", w), on and C.selText or C.text, bg)
                put(x + 1, y, fit(f.nm, w - 20), on and C.selText or C.text, bg)
                local right = f.mc .. " in, " .. (f.md == "open" and "open" or (f.md == "password" and "locked" or "request"))
                put(x + w - #right - 1, y, right, on and C.selText or C.hint, bg)
                addHit(x, x + w - 1, y, { a = "jpick", i = i })
                y = y + 1
            end
            return y
        else
            local ny = Form.draw(self.codeForm, x, y, w)
            if self.wait then
                if nowSec() - self.wait.t > 6 then
                    put(x, ny + 1, fit("No answer. Check the numbers and the range.", w), C.warn, C.panel)
                else
                    put(x, ny + 1, fit("Asking the host...", w), C.dim, C.panel)
                end
            end
            return ny
        end
    end
    function m.key(self, key)
        if self.stage == "confirm" then
            if key == keys.escape then self.stage, self.form = "pick", nil return true end
            return Form.key(self.form, key)
        end
        if key == keys.left or (key == keys.tab and self.tab == 1) then self.tab = 1 + (self.tab % 2) self.sel = 1 return true end
        if key == keys.right then self.tab = 1 + (self.tab % 2) return true end
        if self.tab == 1 then
            local list = self:nearby()
            if key == keys.up then self.sel = math.max(1, self.sel - 1) return true end
            if key == keys.down then self.sel = math.min(#list, self.sel + 1) return true end
            if key == keys.enter and list[self.sel] then self:pickInfo(list[self.sel]) return true end
        else
            if key == keys.tab then self.tab = 1 return true end
            return Form.key(self.codeForm, key)
        end
        return false
    end
    function m.char(self, ch)
        if self.stage == "confirm" then return Form.char(self.form, ch) end
        if self.tab == 2 then return Form.char(self.codeForm, ch) end
        return false
    end
    function m.click(self, k)
        if k.a == "jtab" then self.tab = k.i self.sel = 1
        elseif k.a == "jpick" then
            local list = self:nearby()
            if list[k.i] then self.sel = k.i; self:pickInfo(list[k.i]) end
        elseif k.a == "form" then
            Form.click(self.stage == "confirm" and self.form or self.codeForm, k)
        end
    end
    m.formHandled = true
    Net.listen(true)
    UI.open(m)
end

-- ── Room info (join code) ────────────────────────────────────────────────────

function UI.invite(c)
    local m = { title = "Invite people", w = 42, h = 12 }
    m.draw = function(self, x, y, w)
        local hostName = c.hostId == (R.me and R.me.id) and "this computer" or ("computer " .. c.hostId)
        put(x, y, fit(c.name, w), C.text, C.panel)
        put(x, y + 1, fit("Host: " .. hostName, w), C.dim, C.panel)
        put(x, y + 3, "Join code", C.dim, C.panel)
        put(x, y + 4, fit(c.hostId .. " " .. c.rid, w), C.accent, C.panel)
        put(x, y + 6, fit("People nearby also see the Room under Join, Nearby,", w), C.dim, C.panel)
        put(x, y + 7, fit("when the host lists it.", w), C.dim, C.panel)
        return y + 8
    end
    UI.open(m)
end

-- ── People ───────────────────────────────────────────────────────────────────

function UI.member(c, u)
    local mm = c.mem[u]
    if not mm then return end
    local mine = c.u == u
    local items = {}
    if not mine then
        items[#items + 1] = { label = "Send a message", fn = function() UI.goDm(c.rid, mm.ipk) end }
    end
    if not mine and c.ro >= 1 and mm.ro < c.ro then
        if mm.mu then items[#items + 1] = { label = "Unmute", fn = function() Cl.mod(c, { a = "unmute", u = u }) end }
        else items[#items + 1] = { label = "Mute for 10 minutes", fn = function() Cl.mod(c, { a = "mute", u = u, v = 10 }) end } end
        items[#items + 1] = { label = "Remove from the Room", fn = function() UI.confirm("Remove " .. mm.nm, "They can join again.", "Remove", function() Cl.mod(c, { a = "kick", u = u }) end) end }
        if c.ro >= 2 then
            items[#items + 1] = { label = "Ban", fn = function() UI.confirm("Ban " .. mm.nm, "They cannot join again until unbanned.", "Ban", function() Cl.mod(c, { a = "ban", u = u }) end) end }
        end
    end
    if not mine and c.ro >= 2 and mm.ro < c.ro then
        if mm.ro ~= 1 then items[#items + 1] = { label = "Make Mod", fn = function() Cl.mod(c, { a = "role", u = u, v = 1 }) end } end
        if mm.ro ~= 2 and c.ro >= 3 then items[#items + 1] = { label = "Make Admin", fn = function() Cl.mod(c, { a = "role", u = u, v = 2 }) end } end
        if mm.ro > 0 then items[#items + 1] = { label = "Remove role", fn = function() Cl.mod(c, { a = "role", u = u, v = 0 }) end } end
    end
    items[#items + 1] = { label = "Close", fn = function() end, dim = true }
    local m = UI.pick({ title = mm.nm, items = items, w = 36, h = #items + 9 })
    m.head = function(self, x, y, w)
        identicon(x, y, 3, 2, mm.nm, nil)
        put(x + 4, y, fit(mm.nm, w - 4), nameColor(mm.nm), C.panel)
        put(x + 4, y + 1, fit(ROLE_NAME[mm.ro] .. (mm.on and ", online" or ", away") .. (mm.mu and ", muted" or ""), w - 4), C.dim, C.panel)
        put(x, y + 3, fit("Key " .. mm.ipk:sub(1, 8) .. "-" .. mm.ipk:sub(9, 16), w), C.dim, C.panel)
        return y + 5
    end
    UI.open(m)
end

function UI.people(c)
    local list = {}
    for _, mm in pairs(c.mem) do list[#list + 1] = mm end
    table.sort(list, function(a, b)
        if (a.on and 1 or 0) ~= (b.on and 1 or 0) then return a.on end
        return a.nm:lower() < b.nm:lower()
    end)
    local items = {}
    for _, mm in ipairs(list) do
        items[#items + 1] = { label = (mm.on and "\7 " or "  ") .. mm.nm, right = ROLE_TAG[mm.ro] or "", rightFg = C.accent, fn = function() UI.member(c, mm.u) end }
    end
    UI.open(UI.pick({ title = "People in " .. c.name, items = items, filter = true, w = 36, h = 16 }))
end

-- ── Room settings (staff) ────────────────────────────────────────────────────

function UI.channelEdit(c, ch)
    local m = { title = ch and ("Channel #" .. ch.nm) or "New channel", w = 40, h = 13 }
    local items = {
        tfield("nm", "Name", ch and ch.nm or "", 16),
        tfield("tp", "Topic", ch and ch.tp or "", 60, nil, function() return ch ~= nil end),
        { t = "choice", id = "kd", label = "Who posts", opts = { "Everyone", "Staff only" }, i = (ch and ch.kd == "announce") and 2 or 1, show = function() return ch == nil end },
        { t = "gap" },
        { t = "buttons", list = ch and { { label = "Save", id = "ok" }, { label = "Delete", id = "del" }, { label = "Cancel", id = "no" } }
            or { { label = "Add", id = "ok" }, { label = "Cancel", id = "no" } } },
    }
    m.form = Form.new(items, function(id, f)
        if id == "no" then UI.close() return end
        if id == "del" then
            UI.close()
            UI.confirm("Delete #" .. ch.nm, "All messages in it are lost.", "Delete", function() Cl.mod(c, { a = "chdel", ch = ch.id }) end)
            return
        end
        if ch then
            Cl.mod(c, { a = "chedit", ch = ch.id, nm = Form.get(f, "nm"), tp = Form.get(f, "tp") })
        else
            Cl.mod(c, { a = "chadd", nm = Form.get(f, "nm"), kd = (Form.get(f, "kd") == 2) and "announce" or nil })
        end
        UI.close()
    end)
    m.form.submit = function(f) m.form.on("ok", f) end
    UI.open(m)
end

function UI.channelsMenu(c)
    local items = { { label = "+ Add a channel", fn = function() UI.channelEdit(c, nil) end } }
    for _, ch in ipairs(c.chans) do
        items[#items + 1] = { label = (ch.kd == "announce" and "! " or "# ") .. ch.nm, right = ch.kd == "announce" and "staff" or "", fn = function() UI.channelEdit(c, ch) end }
    end
    UI.open(UI.pick({ title = "Channels", items = items, w = 34, h = math.min(16, #items + 5) }))
end

function UI.requestsMenu(c)
    Cl.send(c, { t = "bans" })
    local items = {}
    for ipk, r in pairs(c.reqs) do
        items[#items + 1] = { label = r.nm, right = "wants in", fn = function()
            UI.open(UI.pick({ title = r.nm, w = 30, h = 8, items = {
                { label = "Let them in", fn = function() Cl.mod(c, { a = "approve", ipk = ipk }); c.reqs[ipk] = nil end },
                { label = "Decline", fn = function() Cl.mod(c, { a = "deny", ipk = ipk }); c.reqs[ipk] = nil end },
            } }))
        end }
    end
    UI.open(UI.pick({ title = "Join requests", items = items, empty = "No requests", w = 34, h = 12 }))
end

function UI.bansMenu(c)
    Cl.send(c, { t = "bans" })
    local items = {}
    for _, b in ipairs(c.bans) do
        items[#items + 1] = { label = b.nm, right = "unban", fn = function() Cl.mod(c, { a = "unban", ipk = b.ipk }) end }
    end
    UI.open(UI.pick({ title = "Banned people", items = items, empty = "Nobody is banned", w = 34, h = 12 }))
end

function UI.roomSettings(c)
    local isHost = c.hostId == (R.me and R.me.id)
    local hr = isHost and Host.rooms[c.rid]
    local items = {}
    if c.ro >= 3 then
        items[#items + 1] = { label = "Rename the Room", fn = function()
            local m = { title = "Rename", w = 36, h = 9 }
            m.form = Form.new({ tfield("nm", "Room name", c.name, 20), { t = "gap" }, { t = "buttons", list = { { label = "Save", id = "ok" }, { label = "Cancel", id = "no" } } } },
                function(id, f) if id == "ok" then Cl.mod(c, { a = "setname", v = Form.get(f, "nm") }) end UI.close() end)
            m.form.submit = function(f) m.form.on("ok", f) end
            UI.open(m)
        end }
        items[#items + 1] = { label = "Who can join", right = c.mode == "open" and "anyone" or (c.mode == "password" and "password" or "approval"), fn = function()
            local m = { title = "Who can join", w = 38, h = 12 }
            m.form = Form.new({
                { t = "choice", id = "md", label = "Access", opts = { "Anyone nearby", "Password", "You approve" }, i = c.mode == "password" and 2 or (c.mode == "approval" and 3 or 1) },
                tfield("pw", "New password", "", 30, true, function(f) return Form.get(f, "md") == 2 end),
                { t = "gap" },
                { t = "buttons", list = { { label = "Save", id = "ok" }, { label = "Cancel", id = "no" } } } },
                function(id, f)
                    if id == "ok" then
                        local mdi = Form.get(f, "md")
                        Cl.mod(c, { a = "setmode", v = mdi == 2 and "password" or (mdi == 3 and "approval" or "open"), pw = Form.get(f, "pw") })
                        c.mode = mdi == 2 and "password" or (mdi == 3 and "approval" or "open")
                    end
                    UI.close()
                end)
            UI.open(m)
        end }
        if hr then
            items[#items + 1] = { label = "List nearby", right = hr.listed and "yes" or "no", fn = function() Cl.mod(c, { a = "listed", v = hr.listed and 0 or 1 }) end }
            items[#items + 1] = { label = "Biggest file", right = fmtSize(hr.maxFile), fn = function()
                local sizes = { 32768, 98304, 196608, 524288 }
                local nextV = sizes[1]
                for i, s in ipairs(sizes) do if hr.maxFile == s then nextV = sizes[(i % #sizes) + 1] end end
                Cl.mod(c, { a = "maxfile", v = nextV })
            end }
        end
    end
    if c.ro >= 2 then items[#items + 1] = { label = "Channels", fn = function() UI.channelsMenu(c) end } end
    if c.ro >= 1 and c.mode == "approval" then
        local n = 0
        for _ in pairs(c.reqs) do n = n + 1 end
        items[#items + 1] = { label = "Join requests", right = n > 0 and tostring(n) or "", fn = function() UI.requestsMenu(c) end }
    end
    if c.ro >= 2 then items[#items + 1] = { label = "Banned people", fn = function() UI.bansMenu(c) end } end
    items[#items + 1] = { label = "Invite people", fn = function() UI.invite(c) end }
    if c.ro >= 3 and isHost then
        items[#items + 1] = { label = "Close this Room", fn = function()
            UI.confirm("Close " .. c.name, "Everyone is removed and all messages are deleted.", "Close it", function()
                Host.delete(c.rid)
                R.rooms[c.rid] = nil
                pcall(fs.delete, cacheName(c.rid))
                Cl.saveCfg()
                UI.goRoom(nil)
            end)
        end }
    end
    UI.open(UI.pick({ title = c.name, items = items, w = 36, h = math.min(16, #items + 5) }))
end

-- ── Main menu ────────────────────────────────────────────────────────────────

function UI.helpModal()
    local lines = {
        "ROOMS", "",
        "A Room is a chat for the people on your server. It lives on the computer of its host. Keep that computer running.", "",
        "TYPE and press Enter to send.",
        "UP picks a message. Then R reply, E react, Enter edit, X delete, D download, Esc back.",
        "TAB at an @ completes a name. Otherwise it moves to the next channel.",
        "CTRL+K jumps to any Room, channel or person.",
        "CTRL+UP/DOWN change channel. CTRL+LEFT/RIGHT change Room.",
        "PAGE UP/DOWN scroll. F2 people. F3 menu.", "",
        "COMMANDS", "/file path   send a file (up to 96 KB)", "/nick name   change your name", "/dm name text   private message", "/help", "",
        "Private messages are locked to the other person. The host cannot read them.",
        "Room messages can be read by the host.", "",
        "Hosts keep Rooms for friends. Staff can mute, remove or ban. Press F3 for settings.",
    }
    local all = {}
    local m = { title = "Help", w = 50, h = 18, top = 0 }
    function m.draw(self, x, y, w, h)
        all = {}
        for _, l in ipairs(lines) do
            if l == "" then all[#all + 1] = ""
            else for _, wl in ipairs(wrapText(l, w)) do all[#all + 1] = wl end end
        end
        local cap = self.r.y + self.r.h - 2 - y
        self.top = clamp(self.top, 0, math.max(0, #all - cap))
        for i = 1, cap do
            local line = all[self.top + i]
            if not line then break end
            local head = line:match("^%u[%u ]+$")
            put(x, y + i - 1, pad(line, w), head and C.accent or C.text, C.panel)
        end
        return y + cap
    end
    function m.key(self, key)
        if key == keys.up then self.top = self.top - 1 return true end
        if key == keys.down then self.top = self.top + 1 return true end
        if key == keys.pageUp then self.top = self.top - 8 return true end
        if key == keys.pageDown then self.top = self.top + 8 return true end
        return false
    end
    m.scroll = function(self, d) self.top = self.top + d end
    UI.open(m)
end

function UI.menu()
    local c = curRoom()
    local items = {
        { label = "Create a Room", fn = UI.create },
        { label = "Join a Room", fn = UI.join },
    }
    if c then
        items[#items + 1] = { label = "People", fn = function() UI.people(c) end }
        items[#items + 1] = { label = "Room settings", right = c.ro >= 1 and "" or "view", fn = function() UI.roomSettings(c) end }
        items[#items + 1] = { label = "Mark all as read", fn = function()
            for _, ch in ipairs(c.chans) do Cl.markRead(c, ch.id) end
            for k in pairs(c.dms) do Cl.markDmRead(c, k) end
        end }
    end
    items[#items + 1] = { label = "My name", right = R.cfg.name or "", fn = function() UI.askName() end }
    if c then
        if c.ro >= 3 and c.hostId == (R.me and R.me.id) then
            -- owners close the Room from its settings
        else
            items[#items + 1] = { label = "Leave this Room", fn = function()
                UI.confirm("Leave " .. c.name, "You can join again later.", "Leave", function()
                    Cl.leave(c)
                    UI.goRoom(nil)
                end)
            end }
        end
    end
    items[#items + 1] = { label = "Help", fn = UI.helpModal }
    items[#items + 1] = { label = "Quit Rooms", fn = function() U.quit = true end }
    UI.open(UI.pick({ title = "Rooms", items = items, w = 34, h = math.min(H - 2, #items + 5) }))
end

function UI.switcher()
    local items = {}
    for _, c in ipairs(roomList()) do
        for _, ch in ipairs(c.chans) do
            local un = Cl.unread(c, ch.id)
            items[#items + 1] = { label = c.name .. "  #" .. ch.nm, right = un > 0 and (un .. " new") or "", rightFg = C.accent,
                fn = function() UI.goRoom(c.rid, ch.id) end }
        end
        for ipk, list in pairs(c.dms) do
            local u = c.byIpk[ipk]
            if u and c.mem[u] then
                items[#items + 1] = { label = c.name .. "  @" .. c.mem[u].nm, right = "message", fn = function() UI.goDm(c.rid, ipk) end }
            end
        end
        for _, mm in pairs(c.mem) do
            if mm.u ~= c.u and not (c.dms[mm.ipk] and #c.dms[mm.ipk] > 0) then
                items[#items + 1] = { label = c.name .. "  @" .. mm.nm, right = "new message", dim = true, fn = function() UI.goDm(c.rid, mm.ipk) end }
            end
        end
    end
    items[#items + 1] = { label = "Create a Room", dim = true, fn = UI.create }
    items[#items + 1] = { label = "Join a Room", dim = true, fn = UI.join }
    items[#items + 1] = { label = "Menu", dim = true, fn = UI.menu }
    UI.open(UI.pick({ title = "Jump to", items = items, filter = true, w = 44, h = 16 }))
end

function UI.reactPicker(g)
    local c = curRoom()
    local m = { title = "React", w = 32, h = 9 }
    m.draw = function(self, x, y, w)
        local cx, cy = x, y
        for i, e in ipairs(REACT) do
            local t = " " .. i .. " " .. e .. " "
            if cx + #t > x + w then cx = x; cy = cy + 2 end
            put(cx, cy, t, C.barText, C.barBtn)
            addHit(cx, cx + #t - 1, cy, { a = "pickreact", e = e })
            cx = cx + #t + 1
        end
        put(x, cy + 3, "Press a number or click", C.dim, C.panel)
        return cy + 4
    end
    m.key = function(self, key) return false end
    m.char = function(self, ch)
        local n = tonumber(ch)
        if n and REACT[n] then
            Cl.react(c, U.ch, g.n, REACT[n])
            UI.close()
            fxAdd("burst", LAY.mx + 6, LAY.bot - 2)
        end
        return true
    end
    m.click = function(self, k)
        if k.a == "pickreact" then
            Cl.react(c, U.ch, g.n, k.e)
            UI.close()
            fxAdd("burst", LAY.mx + 6, LAY.bot - 2)
        end
    end
    UI.open(m)
end

function UI.filePicker()
    local c = curRoom()
    if not c then return end
    local m = { title = "Send a file", w = 46, h = 16, dir = "", sel = 1, top = 0 }
    function m.entries()
        local out = {}
        if m.dir ~= "" then out[#out + 1] = { name = "..", dir = true } end
        local ok, names = pcall(fs.list, m.dir)
        if not ok then return out end
        local dirs, files = {}, {}
        for _, n in ipairs(names) do
            local p = fs.combine(m.dir, n)
            if fs.isDir(p) then
                if not (p == "rom" or p == "prismarine" or p == "rooms_data") then dirs[#dirs + 1] = { name = n, dir = true } end
            else
                files[#files + 1] = { name = n, size = fs.getSize(p) }
            end
        end
        table.sort(dirs, function(a, b) return a.name < b.name end)
        table.sort(files, function(a, b) return a.name < b.name end)
        for _, d in ipairs(dirs) do out[#out + 1] = d end
        for _, f in ipairs(files) do out[#out + 1] = f end
        return out
    end
    function m.draw(self, x, y, w, h)
        put(x, y, fit("/" .. self.dir, w), C.accent, C.panel)
        y = y + 1
        local list = self.entries()
        self.list = list
        local cap = self.r.y + self.r.h - 3 - y
        self.sel = clamp(self.sel, 1, math.max(1, #list))
        if self.sel <= self.top then self.top = self.sel - 1 end
        if self.sel > self.top + cap then self.top = self.sel - cap end
        for i = self.top + 1, math.min(#list, self.top + cap) do
            local e = list[i]
            local on = i == self.sel
            local bg = on and C.sel or C.panel
            put(x, y, string.rep(" ", w), on and C.selText or C.text, bg)
            put(x + 1, y, fit((e.dir and "\16 " or "  ") .. e.name, w - 12), on and C.selText or (e.dir and C.info or C.text), bg)
            if not e.dir then
                local s = fmtSize(e.size)
                put(x + w - #s - 1, y, s, on and C.selText or C.hint, bg)
            end
            addHit(x, x + w - 1, y, { a = "fpick", i = i })
            y = y + 1
        end
        put(x, self.r.y + self.r.h - 2, fit("Files up to 96 KB. Enter sends. Esc closes.", w), C.dim, C.panel)
        return y
    end
    function m.activate(self, i)
        local e = self.list and self.list[i]
        if not e then return end
        if e.dir then
            if e.name == ".." then self.dir = fs.getDir(self.dir) else self.dir = fs.combine(self.dir, e.name) end
            self.sel, self.top = 1, 0
        else
            local path = fs.combine(self.dir, e.name)
            local caption = U.input.text
            local ok, why = Cl.upload(c, U.ch, path, caption, U.reply and U.reply.n or nil)
            UI.close()
            if ok then U.input = { text = "", pos = 0 }; U.reply = nil; note("Sending " .. e.name, "info")
            else note(why or "Cannot send", "warn") end
        end
    end
    function m.key(self, key)
        if key == keys.up then self.sel = math.max(1, self.sel - 1) return true end
        if key == keys.down then self.sel = self.sel + 1 return true end
        if key == keys.enter then self:activate(self.sel) return true end
        if key == keys.backspace then self.dir = fs.getDir(self.dir) self.sel = 1 return true end
        return false
    end
    function m.click(self, k)
        if k.a == "fpick" then
            if self.sel == k.i then self:activate(k.i) else self.sel = k.i end
        end
    end
    m.scroll = function(self, d) self.sel = self.sel + d end
    UI.open(m)
end

-- ── Rooms: navigation, input and main loop ──────────────────────────────────

function UI.goRoom(rid, ch)
    U.sel, U.reply, U.editing = nil, nil, nil
    U.input = { text = "", pos = 0 }
    U.wipe = { t0 = nowSec() }
    U.room = rid
    U.dm = nil
    U.scroll = 0
    if not rid or not R.rooms[rid] then
        U.room, U.ch = nil, nil
        return
    end
    local c = R.rooms[rid]
    ch = ch or c.lastCh
    if not (ch and Cl.chanOf(c, ch)) then ch = c.chans[1] and c.chans[1].id end
    U.ch = ch
    if ch then
        local seen = c.read[ch] or 0
        U.newFrom = (seen > 0 and (c.seq[ch] or 0) > seen) and seen or nil
        c.lastCh = ch
    end
    R.cfg.ui.room = rid
    R.dirty = true
end

function UI.goChan(id)
    local c = curRoom()
    if not c then return end
    UI.goRoom(c.rid, id)
end

function UI.goDm(rid, ipk)
    local c = R.rooms[rid]
    if not c then return end
    U.sel, U.reply, U.editing = nil, nil, nil
    U.input = { text = "", pos = 0 }
    U.room, U.dm, U.ch = rid, ipk, nil
    U.scroll = 0
    U.wipe = { t0 = nowSec() }
    c.dms[ipk] = c.dms[ipk] or {}
    R.cfg.ui.room = rid
    R.dirty = true
end

function UI.nextChan(d)
    local c = curRoom()
    if not c or #c.chans == 0 then return end
    local at = 1
    for i, ch in ipairs(c.chans) do if ch.id == U.ch then at = i end end
    UI.goChan(c.chans[((at - 1 + d) % #c.chans) + 1].id)
end

function UI.nextRoom(d)
    local list = roomList()
    if #list == 0 then return end
    local at = 0
    for i, c in ipairs(list) do if c.rid == U.room then at = i end end
    local nx = ((at - 1 + d) % #list) + 1
    if at == 0 then nx = 1 end
    UI.goRoom(list[nx].rid)
end

-- ── Splash and home ──────────────────────────────────────────────────────────

function D.title(x, y, cw, text, scale)
    local cv = newCanvas(cw, 5)
    local t = nowSec()
    local pal = C.names
    local tw = fontWidth(text, scale)
    fontDraw(cv, text, floor((cv.pw - tw) / 2) + 1, 3, scale, function(px, py)
        local k = floor((px + py * 0.5 + t * 16) / 5) % #pal + 1
        return pal[k] or C.text
    end)
    render(cv, x, y, C.bg)
end

function D.splash()
    local age = nowSec() - U.splash
    local scale = (W >= 44) and 3 or ((W >= 30) and 2 or 1)
    local cw = clamp(floor(fontWidth("ROOMS", scale) / 2) + 4, 10, W)
    local rows = 5
    local x = floor((W - cw) / 2) + 1
    local y = floor((H - rows) / 2)
    D.title(x, y, cw, "ROOMS", scale)
    local sub = "Chat with your server"
    put(floor((W - #sub) / 2) + 1, y + rows + 1, sub, C.dim, C.bg)
    local bw = 24
    local cv = newCanvas(bw, 1)
    for px = 1, cv.pw do cv[2][px] = C.bar end
    for px = 1, floor(cv.pw * clamp(age / 1.3, 0, 1)) do cv[2][px] = C.accent end
    render(cv, floor((W - bw) / 2) + 1, y + rows + 3, C.bg)
    if age > 1.4 then U.splash = nil; R.dirty = true end
end

function D.welcome(L)
    for y = 2, H do put(L.mx, y, string.rep(" ", L.mw), C.text, C.bg) end
    local cw = clamp(L.mw - 2, 12, 30)
    local x = L.mx + floor((L.mw - cw) / 2)
    local top = 3
    if H >= 16 then D.title(x, top, cw, "ROOMS", (cw >= 24) and 2 or 1) top = top + 6 else top = 2 end
    local function center(y, text, fg)
        put(L.mx + max0(floor((L.mw - #text) / 2)), y, fit(text, L.mw), fg or C.dim, C.bg)
    end
    center(top, "Chat with people on your server", C.dim)
    top = top + 2
    local bx = L.mx + max0(floor((L.mw - 36) / 2))
    local function btn(label, k)
        local t = "  " .. label .. "  "
        put(bx, top, t, C.barText, C.barBtn)
        addHit(bx, bx + #t - 1, top, k)
        bx = bx + #t + 1
    end
    if L.mw >= 40 then
        btn("Create a Room", { a = "create" }); btn("Join a Room", { a = "join" })
    else
        btn("Create", { a = "create" }); btn("Join", { a = "join" }); btn("Help", { a = "help" })
    end
    top = top + 2
    local list = roomList()
    if #list > 0 then
        center(top, "YOUR ROOMS", C.accent)
        top = top + 1
        for _, c in ipairs(list) do
            if top > H - 2 then break end
            local un = 0
            for _, ch in ipairs(c.chans) do un = un + Cl.unread(c, ch.id) end
            local label = fit(c.name, 24) .. (un > 0 and ("  " .. un .. " new") or "")
            put(L.mx + max0(floor((L.mw - 30) / 2)), top, pad(" " .. label, 30), C.text, C.rowSel)
            addHit(L.mx, L.mx2, top, { a = "room", rid = c.rid })
            top = top + 1
        end
    elseif L.mw >= 40 then
        center(top, "No Rooms yet. Create one for your friends,", C.dim)
        center(top + 1, "or join one that is nearby.", C.dim)
    end
end

function D.fx(L)
    local t = nowSec()
    for i = #U.fx, 1, -1 do
        local f = U.fx[i]
        local age = t - f.t0
        if age > 0.8 then table.remove(U.fx, i)
        elseif f.kind == "burst" then
            local chars = { "*", "+", "." }
            for p = 1, 8 do
                local ang = p * 0.785
                local dist = age * 9
                local px = floor(f.x + math.cos(ang) * dist + 0.5)
                local py = floor(f.y - age * 3 + math.sin(ang) * dist * 0.35 + 0.5)
                if px >= L.mx and px <= L.mx2 and py >= L.top and py <= L.bot then
                    put(px, py, chars[(p + floor(age * 10)) % 3 + 1], C.names[(p % #C.names) + 1] or C.accent, C.bg)
                end
            end
        end
    end
    if U.wipe then
        local age = t - U.wipe.t0
        if age > 0.25 then U.wipe = nil
        else
            local p = age / 0.25
            local bx = L.mx + floor(p * L.mw)
            for y = L.top, L.bot do
                if bx >= L.mx and bx <= L.mx2 then put(bx, y, "\149", C.line, C.bg) end
                if bx - 1 >= L.mx and bx - 1 <= L.mx2 then put(bx - 1, y, "\128", C.line, C.bg) end
            end
        end
    end
end

function max0(v) return v > 0 and v or 0 end

function UI.draw()
    win.setVisible(false)
    hits = {}
    term.setBackgroundColor(C.bg)
    term.setTextColor(C.text)
    term.clear()
    if U.splash then
        D.splash()
    else
        local L = layout()
        local c = curRoom()
        if c and not U.dm and (not U.ch or not Cl.chanOf(c, U.ch)) and c.chans[1] then
            U.ch = (c.lastCh and Cl.chanOf(c, c.lastCh)) and c.lastCh or c.chans[1].id
            c.lastCh = U.ch
        end
        D.topbar(L, c)
        D.rail(L)
        D.channels(L)
        if c and (U.ch or U.dm) then
            D.messages(L, c)
            D.strip(L, c)
            D.input(L, c)
            D.members(L)
            if U.atBottom and not U.modal then
                if U.dm then Cl.markDmRead(c, U.dm) else Cl.markRead(c, U.ch) end
            end
            local stateText
            if c.state == "joining" then stateText = "Joining..."
            elseif c.state == "waiting" then stateText = "Waiting for staff to let you in..."
            elseif c.state == "offline" then stateText = "Host not answering" end
            if stateText then
                local t = " " .. stateText .. " "
                put(L.mx2 - #t, L.top, t, C.selText == C.warn and C.text or colors.black, C.warn)
            end
            D.fx(L)
        else
            D.welcome(L)
        end
        D.modal()
    end
    term.setCursorBlink(false)
    win.setVisible(true)
    R.dirty = false
end

-- ── Actions ──────────────────────────────────────────────────────────────────

local function selectIndex(list, g)
    for i, o in ipairs(list) do if o == g then return i end end
end

function UI.currentList()
    local c = curRoom()
    if not c then return {} end
    if U.dm then return c.dms[U.dm] or {} end
    return c.hist[U.ch] or {}
end

function UI.moveSel(d)
    local list = UI.currentList()
    local at = U.sel and selectIndex(list, U.sel)
    local i = at or (d < 0 and #list + 1 or 0)
    repeat
        i = i + d
    until i < 1 or i > #list or not list[i].sy
    if i < 1 then return end
    if i > #list then U.sel = nil; return end
    U.sel = list[i]
    U.ensure = true
end

function UI.doAction(d)
    local c, g = curRoom(), U.sel
    if not c or not g then return end
    if d == "close" then U.sel = nil
    elseif d == "reply" and not U.dm then U.reply = g; U.sel = nil; U.editing = nil
    elseif d == "react" and not U.dm and g.n and not g.local_ then UI.reactPicker(g)
    elseif d == "edit" and not U.dm and g.u == c.u and not g.f and not g.local_ then
        U.editing = g
        U.input = { text = g.x, pos = #g.x }
        U.sel, U.reply = nil, nil
    elseif d == "delete" and not U.dm and g.n and not g.local_ then
        Cl.delete(c, U.ch, g.n)
        U.sel = nil
    elseif d == "download" and g.f then
        Cl.download(c, g.f)
        U.sel = nil
    end
    R.dirty = true
end

local function findMember(c, name)
    name = name:lower():gsub("^@", "")
    for _, m in pairs(c.mem) do
        if m.nm:lower() == name or m.nm:lower():gsub(" ", "") == name then return m end
    end
end

function UI.send()
    local c = curRoom()
    if not c then return end
    local text = U.input.text
    if text:match("^%s*$") then
        U.editing = nil
        return
    end
    local cmd, rest = text:match("^/(%a+)%s*(.*)$")
    if cmd then
        cmd = cmd:lower()
        U.input = { text = "", pos = 0 }
        if cmd == "help" then UI.helpModal()
        elseif cmd == "nick" then
            local nm = cleanName(rest)
            if not nm then note("Use 2 to 20 letters or digits", "warn") return end
            R.cfg.name = nm
            for _, rc in pairs(R.rooms) do Cl.join(rc) end
            Cl.saveCfg()
            note("Name is now " .. nm, "info")
        elseif cmd == "file" then
            local ok, why = Cl.upload(c, U.ch, rest, nil, nil)
            if not ok then note(why or "Cannot send", "warn") else note("Sending " .. fs.getName(rest), "info") end
        elseif cmd == "dm" then
            local who, msg = rest:match("^(%S+)%s+(.+)$")
            local m = who and findMember(c, who)
            if not m then note("Use /dm name message", "warn") return end
            local ok, why = Cl.sendDm(c, m.u, msg)
            if ok then UI.goDm(c.rid, m.ipk) else note(why or "Cannot send", "warn") end
        else
            note("Unknown command. Type /help", "warn")
        end
        return
    end
    if U.editing then
        Cl.edit(c, U.ch, U.editing.n, text)
        U.editing = nil
        U.input = { text = "", pos = 0 }
        return
    end
    if U.dm then
        local u = c.byIpk[U.dm]
        if u then
            local ok, why = Cl.sendDm(c, u, text)
            if not ok then note(why or "Cannot send", "warn") return end
        end
    else
        local ch = Cl.chanOf(c, U.ch)
        if ch and ch.kd == "announce" and c.ro < 1 then note("Only staff post here", "warn") return end
        if not Cl.sendMessage(c, U.ch, text, U.reply and U.reply.n or nil) then return end
    end
    U.input = { text = "", pos = 0 }
    U.reply = nil
    U.scroll = 0
    U.newFrom = nil
end

local function complete()
    local c = curRoom()
    if not c then return false end
    local t = U.input.text
    local partial = t:match("@([%w_%-]*)$")
    if not partial then return false end
    local low = partial:lower()
    local best
    for _, m in pairs(c.mem) do
        local nm = m.nm:gsub(" ", "")
        if nm:lower():sub(1, #low) == low and (not best or #nm < #best) then best = nm end
    end
    if not best then return true end
    U.input.text = t:sub(1, #t - #partial) .. best .. " "
    U.input.pos = #U.input.text
    return true
end

function UI.noteTyping()
    local c = curRoom()
    if c and U.ch and not U.dm and nowSec() - U.lastType > 3 and #U.input.text > 0 then
        U.lastType = nowSec()
        Cl.send(c, { t = "typ", ch = U.ch })
    end
end

-- ── Keys ─────────────────────────────────────────────────────────────────────

function UI.modalKey(key)
    local m = U.modal
    if m.key and m:key(key) then return end
    if m.form and Form.key(m.form, key) then return end
    if key == keys.escape then UI.close() end
end

function UI.key(key)
    if U.splash then U.splash = nil return end
    if key == keys.leftCtrl or key == keys.rightCtrl then U.ctrl = true return end
    if U.modal then UI.modalKey(key) return end
    local c = curRoom()
    if U.ctrl then
        if key == keys.k then UI.switcher() return end
        if key == keys.up then UI.nextChan(-1) return end
        if key == keys.down then UI.nextChan(1) return end
        if key == keys.left then UI.nextRoom(-1) return end
        if key == keys.right then UI.nextRoom(1) return end
        if key == keys.q then U.quit = true return end
        return
    end
    if key == keys.f1 then UI.helpModal() return end
    if key == keys.f2 then
        if c then
            if U.compact then UI.people(c) else U.members = not (U.members == nil and W >= 66 or U.members) end
        end
        return
    end
    if key == keys.f3 then UI.menu() return end
    if not c or not (U.ch or U.dm) then
        if key == keys.enter then UI.create() end
        if key == keys.tab then UI.switcher() end
        return
    end
    if U.sel then
        if key == keys.up then UI.moveSel(-1)
        elseif key == keys.down then UI.moveSel(1)
        elseif key == keys.escape then U.sel = nil
        elseif key == keys.enter then
            if (U.dm and U.sel.mine) or (not U.dm and U.sel.u == c.u) then UI.doAction("edit") else UI.doAction("reply") end
        elseif key == keys.delete then UI.doAction("delete") end
        return
    end
    if key == keys.enter then UI.send()
    elseif key == keys.up and U.input.text == "" and not U.editing then
        UI.moveSel(-1)
        if U.sel then U.ensure = true end
    elseif key == keys.pageUp then U.scroll = U.scroll + math.max(1, LAY.bot - LAY.top - 2)
    elseif key == keys.pageDown then U.scroll = math.max(0, U.scroll - math.max(1, LAY.bot - LAY.top - 2))
    elseif key == keys.tab then
        if not complete() then
            if U.compact then UI.switcher() else UI.nextChan(1) end
        end
    elseif key == keys.escape then
        if U.editing then U.editing = nil; U.input = { text = "", pos = 0 }
        elseif U.reply then U.reply = nil
        elseif U.input.text ~= "" then U.input = { text = "", pos = 0 }
        elseif U.scroll > 0 then U.scroll = 0 end
    else
        editKey(U.input, key)
    end
end

function UI.keyUp(key)
    if key == keys.leftCtrl or key == keys.rightCtrl then U.ctrl = false end
end

function UI.char(ch)
    if U.splash then U.splash = nil return end
    if U.modal then
        local m = U.modal
        if m.char and m:char(ch) then return end
        if m.form then Form.char(m.form, ch) end
        return
    end
    local c = curRoom()
    if not c or not (U.ch or U.dm) then return end
    if U.sel then
        local k = ch:lower()
        if k == "r" then UI.doAction("reply")
        elseif k == "e" then UI.doAction("react")
        elseif k == "x" then UI.doAction("delete")
        elseif k == "d" then UI.doAction("download")
        end
        return
    end
    editChar(U.input, ch, 500)
    UI.noteTyping()
end

function UI.paste(text)
    if U.modal then
        local m = U.modal
        if m.form then for ch in tostring(text):gmatch(".") do if ch:byte() >= 32 then Form.char(m.form, ch) end end end
        return
    end
    if U.sel then return end
    text = tostring(text):gsub("[%c]", " ")
    editChar(U.input, text, 500)
end

-- ── Mouse ────────────────────────────────────────────────────────────────────

function UI.click(x, y, button)
    if U.splash then U.splash = nil return end
    local h = hitAt(x, y)
    if U.modal then
        local m = U.modal
        if h and h.i > U.modalBase then
            local k = h.k
            if k.a == "mclose" then UI.close()
            elseif k.a == "form" and not m.formHandled then Form.click(m.form, k)
            elseif m.click then m:click(k) end
            return
        end
        local r = m.r
        if r and (x < r.x or x >= r.x + r.w or y < r.y or y >= r.y + r.h) then UI.close() end
        return
    end
    local c = curRoom()
    if not h then
        if U.sel and y >= LAY.top and y <= LAY.bot then U.sel = nil end
        return
    end
    local k = h.k
    local a = k.a
    if a == "home" then UI.goRoom(nil)
    elseif a == "room" then UI.goRoom(k.rid)
    elseif a == "railup" then U.railTop = math.max(0, U.railTop - 1)
    elseif a == "raildown" then U.railTop = U.railTop + 1
    elseif a == "join" then UI.join()
    elseif a == "create" then UI.create()
    elseif a == "help" then UI.helpModal()
    elseif a == "roommenu" then if c then UI.roomSettings(c) end
    elseif a == "chan" then UI.goChan(k.id)
    elseif a == "dm" then if c then UI.goDm(c.rid, k.ipk) end
    elseif a == "member" then if c then UI.member(c, k.u) end
    elseif a == "menu" then UI.menu()
    elseif a == "people" then
        if c then
            if LAY.mpw > 0 then U.members = false else U.members = true end
        end
    elseif a == "nav" then UI.switcher()
    elseif a == "attach" then if c and not U.dm then UI.filePicker() else note("Files go in channels", "warn") end
    elseif a == "send" then UI.send()
    elseif a == "cancelreply" then U.reply = nil
    elseif a == "bottom" then U.scroll = 0
    elseif a == "msg" then
        if k.g.sy then return end
        if button == 2 or U.sel ~= k.g then U.sel = k.g else U.sel = nil end
    elseif a == "react" then
        if c and k.g.n then Cl.react(c, U.ch, k.g.n, k.e) end
    elseif a == "download" then
        if c then Cl.download(c, k.f) end
    elseif a == "retry" then if c then Cl.resendFailed(c, k.g); U.sel = nil end
    elseif a == "drop" then if c then Cl.dropLocal(c, U.ch, k.g); U.sel = nil end
    elseif a == "do" then UI.doAction(k.d)
    end
end

function UI.scrollWheel(dir, x, y)
    if U.modal then
        if U.modal.scroll then U.modal:scroll(dir) end
        return
    end
    if LAY.rail > 0 and x <= LAY.rail then U.railTop = math.max(0, (U.railTop or 0) + dir) return end
    if LAY.mpw > 0 and x >= LAY.mpx then U.memTop = math.max(0, (U.memTop or 0) + dir) return end
    U.scroll = math.max(0, U.scroll - dir * 3)
end

-- ── Main loop ────────────────────────────────────────────────────────────────

local function bootScreen()
    local sc = api and api.boot and api.gfx and api.boot.start(false, "ROOMS")
    if not sc then
        Cl.loadAll()
        Host.loadAll()
        return false
    end
    sc.tag = "Rooms  v" .. VERSION
    api.boot.stage(sc, "Starting", 0.2)
    api.boot.stage(sc, "Opening network chat", 0.5, function()
        if rm and rm.enable then pcall(rm.enable) end
    end)
    api.boot.stage(sc, "Reading your Rooms", 0.85, function(tick)
        Cl.loadAll()
        Host.loadAll()
        tick()
    end)
    api.boot.finish(sc)
    if api.restorePalette then pcall(api.restorePalette) end
    return true
end

local function resize()
    local t = nativeTerm or term.native()
    W, H = t.getSize()
    win.reposition(1, 1, W, H)
    pbCache, pbCount = {}, 0
end

local function housekeeping()
    Host.tick()
    Host.flush()
    Cl.tick()
    Cl.drainLoop()
    Cl.drainLoop()
    -- pending notices fade
    local n = R.notes[1]
    if n and nowSec() - n.t > 5 then table.remove(R.notes, 1); R.dirty = true end
    -- reaction burst when someone reacts in view
end

local function loop()
    local interval = function()
        if animating() then return 0.1 end
        return 0.25
    end
    local timer = os.startTimer(0.1)
    UI.draw()
    while not U.quit do
        local ev, a, b, c = os.pullEventRaw()
        if ev == "terminate" then
            U.quit = true
        elseif ev == "timer" then
            if a == timer then
                local ok, err = pcall(housekeeping)
                if not ok then R.lastErr = tostring(err) end
                timer = os.startTimer(interval())
                if animating() then R.dirty = true end
            end
        elseif ev == "pm_rooms" then
            if type(a) == "table" and type(a.body) == "string" then
                local t = textutils.unserialize(a.body)
                if type(t) == "table" then
                    local ok, err = pcall(Cl.incoming, { from = a.from, ipk = a.ipk, xpk = a.xpk, fp = a.fp, t = t })
                    if not ok then R.lastErr = tostring(err) end
                end
            end
            R.dirty = true
        elseif ev == "key" then
            UI.key(a)
            R.dirty = true
        elseif ev == "key_up" then
            UI.keyUp(a)
        elseif ev == "char" then
            UI.char(a)
            R.dirty = true
        elseif ev == "paste" then
            UI.paste(a)
            R.dirty = true
        elseif ev == "mouse_click" then
            UI.click(b, c, a)
            R.dirty = true
        elseif ev == "mouse_scroll" then
            UI.scrollWheel(a, b, c)
            R.dirty = true
        elseif ev == "term_resize" then
            resize()
            R.dirty = true
        elseif ev == "prismarine_theme" then
            loadTheme(); roomsTheme()
            pbCache, pbCount = {}, 0
            R.dirty = true
        end
        local drain = pcall(Cl.drainLoop)
        if R.dirty then
            local ok, err = pcall(UI.draw)
            if not ok then
                R.lastErr = tostring(err)
                R.dirty = false
                if R.debug then error(err, 0) end
            end
        end
    end
end

local function main()
    if not term.isColour() then
        print("Prismarine Rooms needs an advanced computer (colour).")
        return
    end
    if not rm then
        print("Rooms needs Prismarine OS network chat.")
        print("It is off in Archive mode, or this is not Prismarine OS.")
        print("Press any key.")
        os.pullEvent("key")
        return
    end
    math.randomseed(os.epoch("utc"))
    local usedBoot = bootScreen()
    local allowed = pcall(rm.enable) and Net.refreshMe() ~= nil
    nativeTerm = term.current()
    W, H = nativeTerm.getSize()
    win = window.create(nativeTerm, 1, 1, W, H, true)
    term.redirect(win)
    loadTheme(); roomsTheme()
    R.ui = U
    Net.refreshMe()
    if not R.me then
        term.redirect(nativeTerm)
        print("Network chat was not allowed, or this computer has no modem.")
        print("Press any key.")
        os.pullEvent("key")
        return
    end
    Net.listen(false)
    if not usedBoot then U.splash = nowSec() end
    local list = roomList()
    local want = R.cfg.ui.room
    if want and R.rooms[want] then UI.goRoom(want)
    elseif list[1] then UI.goRoom(list[1].rid) end
    U.wipe = nil
    if not R.cfg.name then
        UI.askName()
    end
    if next(Host.rooms) then UI.askBackground() end
    local ok, err = pcall(loop)
    pcall(Cl.saveAll)
    pcall(rm.unlisten)
    term.redirect(nativeTerm)
    nativeTerm.setBackgroundColor(colors.black)
    nativeTerm.setTextColor(colors.white)
    nativeTerm.setCursorBlink(false)
    nativeTerm.clear()
    nativeTerm.setCursorPos(1, 1)
    if not ok and not tostring(err):find("Terminated") then
        print("Prismarine Rooms stopped: " .. tostring(err))
        print("Press any key.")
        os.pullEvent("key")
    end
end

main()
