-- Prismarine Shell for CC:Tweaked 1.20.1, with Pixelbox lite graphics.
-- A drop-in replacement for the vanilla shell prompt that keeps everything the
-- default shell does (programs, aliases, paths, Tab autocomplete, shell.run)
-- and adds command history, chaining, a top bar, a boot screen and settings.
--
-- Save this file as any program name (for example /pshell.lua) and run it, or
-- call it from /startup.lua. Type "shellhelp" at the prompt for the features.
-- Errors are saved to /prismshell_error.log.

if not shell then
    error("Run Prismarine Shell from a shell, for example: pshell", 0)
end

local W, H = term.getSize()

local LOG_FILE = "prismshell_error.log"

local VERSION = "2"
local SELF = (shell.getRunningProgram and shell.getRunningProgram()) or "pshell.lua"
if not SELF or SELF == "" then SELF = "pshell.lua" end

local DATA_DIR      = ".prismshell"
local HISTORY_FILE  = DATA_DIR .. "/history"
local ALIAS_FILE    = DATA_DIR .. "/aliases"
local LOGO_FILE     = DATA_DIR .. "/logo.txt"
local SETTINGS_FILE = ".prismshell_settings"

-- The palette this program started with, put back when the shell exits.
local PAL0 = {}
for i = 0, 15 do
    local c = 2 ^ i
    PAL0[c] = { term.getPaletteColor(c) }
end

-- ── Settings ─────────────────────────────────────────────────────────────────

local COLOR_CHOICES = {
    { name = "Blue",       value = colors.blue },
    { name = "Red",        value = colors.red },
    { name = "Green",      value = colors.green },
    { name = "Purple",     value = colors.purple },
    { name = "Orange",     value = colors.orange },
    { name = "Cyan",       value = colors.cyan },
    { name = "Magenta",    value = colors.magenta },
    { name = "Brown",      value = colors.brown },
    { name = "Gray",       value = colors.gray },
    { name = "Black",      value = colors.black },
    { name = "Light blue", value = colors.lightBlue },
    { name = "Lime",       value = colors.lime },
    { name = "Yellow",     value = colors.yellow },
    { name = "Pink",       value = colors.pink },
}

local LIGHT = {}
for _, c in ipairs({ colors.white, colors.lightGray, colors.yellow, colors.lime,
                     colors.pink, colors.lightBlue, colors.cyan, colors.orange }) do
    LIGHT[c] = true
end

local function colorValue(name, fallback)
    for _, c in ipairs(COLOR_CHOICES) do
        if c.name == name then return c.value end
    end
    return fallback
end

-- Picks black or white text for a background color.
local function textOn(bg)
    return LIGHT[bg] and colors.black or colors.white
end

-- The shell also offers white and light gray for text colors.
table.insert(COLOR_CHOICES, { name = "White",      value = colors.white })
table.insert(COLOR_CHOICES, { name = "Light gray", value = colors.lightGray })

local DEFAULT_SETTINGS = {
    -- Same options as Prismarine
    osName     = "Prismarine Shell",
    barColor   = "Blue",
    highlight  = "Light blue",
    clock      = "Both",
    hour24     = true,
    updateRepo = "FilesCodes-ui/prismarine-os",  -- owner/name, or owner/name@branch
    logoColor  = "Blue",   -- lower half of the logo: preset name or #RRGGBB
    graphics   = true,     -- Pixelbox lite graphics (boot screen, top bar)
    bootAnim   = true,
    mirror     = true,     -- copy the screen to attached monitors
    monScale   = "Auto",
    theme      = true,     -- refined Prismarine colors for the whole shell
    -- Shell options
    logoArt       = "Shell",     -- Shell, Base or Custom (/.prismshell/logo.txt)
    headerBar     = true,        -- Prismarine top bar above the prompt
    titleDir      = true,        -- show the current folder in the top bar
    promptFormat  = "%d> ",
    promptColor   = "Yellow",
    textColor     = "White",
    failTint      = true,        -- tint the prompt after a failed command
    failColor     = "Red",
    historySave   = true,
    historyMax    = 200,
    historyDedupe = true,
    slowCmd       = 2,           -- show run time of commands slower than this (0 = off)
    autoCd        = true,        -- typing a folder name changes into it
    chaining      = true,        -- ;  &&  ||
    checkUpdates  = true,
}

local settings = {}

local function resetSettings()
    settings = {}
    for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end
end

local function saveSettings()
    local f = fs.open(SETTINGS_FILE, "w")
    if f then
        f.write(textutils.serialize(settings))
        f.close()
    end
end

local function loadSettings()
    resetSettings()
    if fs.exists(SETTINGS_FILE) then
        local f = fs.open(SETTINGS_FILE, "r")
        if f then
            local data = textutils.unserialize(f.readAll() or "")
            f.close()
            if type(data) == "table" then
                for k, v in pairs(data) do
                    if DEFAULT_SETTINGS[k] ~= nil and type(v) == type(DEFAULT_SETTINGS[k]) then
                        settings[k] = v
                    end
                end
            end
        end
    end
end

loadSettings()

-- The GitHub account was renamed. Move a saved update repo to the new name.
do
    local old = "filesoriginuknown-ui"
    local repo = settings.updateRepo
    if repo:sub(1, #old):lower() == old and repo:sub(#old + 1, #old + 1) == "/" then
        settings.updateRepo = "FilesCodes-ui" .. repo:sub(#old + 1)
        saveSettings()
    end
end

-- ── Hashing and secure boot data ─────────────────────────────────────────────

local SHA_K = { 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 }
local SHA_H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local function hex32(n)
    local out = ""
    for _ = 1, 8 do
        local d = n % 16
        out = string.sub("0123456789abcdef", d + 1, d + 1) .. out
        n = (n - d) / 16
    end
    return out
end

-- SHA-256. Yields now and then so long files do not hit the timeout.
local function sha256(msg, tick)
    local band, bxor, bnot, bor = bit32.band, bit32.bxor, bit32.bnot, bit32.bor
    local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate
    local M = 4294967296

    local len = #msg
    local bits = len * 8
    local function u32(n)
        return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255),
                           band(rshift(n, 8), 255), band(n, 255))
    end
    msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
        .. u32(math.floor(bits / M)) .. u32(bits % M)

    local h = {}
    for n = 1, 8 do h[n] = SHA_H0[n] end
    local w = {}
    local blocks = 0

    for i = 1, #msg, 64 do
        local bytes = { string.byte(msg, i, i + 63) }
        for j = 1, 16 do
            local o = (j - 1) * 4
            w[j] = bor(lshift(bytes[o + 1], 24), lshift(bytes[o + 2], 16),
                       lshift(bytes[o + 3], 8), bytes[o + 4])
        end
        for j = 17, 64 do
            local v15, v2 = w[j - 15], w[j - 2]
            local s0 = bxor(rrotate(v15, 7), rrotate(v15, 18), rshift(v15, 3))
            local s1 = bxor(rrotate(v2, 17), rrotate(v2, 19), rshift(v2, 10))
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % M
        end

        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for j = 1, 64 do
            local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = (hh + S1 + ch + SHA_K[j] + w[j]) % M
            local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = (S0 + maj) % M
            hh = g
            g = f
            f = e
            e = (d + t1) % M
            d = c
            c = b
            b = a
            a = (t1 + t2) % M
        end
        h[1] = (h[1] + a) % M
        h[2] = (h[2] + b) % M
        h[3] = (h[3] + c) % M
        h[4] = (h[4] + d) % M
        h[5] = (h[5] + e) % M
        h[6] = (h[6] + f) % M
        h[7] = (h[7] + g) % M
        h[8] = (h[8] + hh) % M

        blocks = blocks + 1
        if blocks % 8 == 0 then
            os.queueEvent("simpleos_yield")
            os.pullEventRaw("simpleos_yield")
            if tick then tick() end
        end
    end

    local out = {}
    for n = 1, 8 do out[n] = hex32(h[n]) end
    return table.concat(out)
end

local function readFile(path)
    local f = fs.open(path, "rb")
    if not f then return nil end
    local data = f.readAll()
    f.close()
    return data
end

local function hashFile(path, tick)
    local data = readFile(path)
    if not data then return nil end
    return sha256(data, tick)
end
-- ── Display layer, palette and Pixelbox graphics ─────────────────────────────
-- Everything the OS draws goes through one buffered window (gfx.win). That
-- window is copied to every attached monitor, and monitor touches come back
-- in as mouse clicks. Pixelbox lite (downloaded on first boot) draws the boot
-- screen, the logo and the header fade. If it is missing, the plain text UI
-- is used and nothing else changes.

local gfx = {
    pb      = nil,   -- the Pixelbox lite module once loaded
    err     = nil,   -- why it is not loaded
    native  = nil,   -- the real computer terminal
    win     = nil,   -- buffered window the OS draws into
    mirrors = {},    -- { name, mon, win, ox, oy }
    ready   = false,
}

local PB_DIR  = ".prismarine"
local PB_FILE = PB_DIR .. "/pixelbox_lite.lua"
-- Pinned to one commit and checked against a SHA-256, so the file that runs at
-- boot is exactly the one this OS was written for.
local PB_URL  = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/82098c8dca939b7689f119d0a577c311d4a09281/pixelbox_lite.lua"
local PB_HASH = "e9923dc24ed6d968de668f42a3c324d0957778a709d93bc9190617c32889de99"

local function nowSec() return os.epoch("utc") / 1000 end

-- ── Monitor mirroring ────────────────────────────────────────────────────────

local TEE_ALL = { "write", "blit", "clear", "clearLine", "scroll", "setCursorPos",
    "setCursorBlink", "setTextColor", "setTextColour", "setBackgroundColor",
    "setBackgroundColour", "setPaletteColor", "setPaletteColour" }
local TEE_ONE = { "getCursorPos", "getCursorBlink", "getSize", "isColor", "isColour",
    "getTextColor", "getTextColour", "getBackgroundColor", "getBackgroundColour",
    "getPaletteColor", "getPaletteColour" }

-- A terminal object that sends every call to the main window and to each
-- mirrored monitor. Answers to questions come from the main window.
local tee = {}
for _, name in ipairs(TEE_ONE) do
    tee[name] = function(...) return gfx.win[name](...) end
end
for _, name in ipairs(TEE_ALL) do
    tee[name] = function(...)
        local a, b, c = gfx.win[name](...)
        local list = gfx.mirrors
        for i = #list, 1, -1 do
            local m = list[i]
            if m.win then pcall(m.win[name], ...) end
        end
        return a, b, c
    end
end

local SCALES = { 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5 }

-- Picks the biggest text scale where the whole screen still fits.
local function chooseScale(mon)
    local want = tonumber(settings.monScale)
    if want then
        pcall(mon.setTextScale, want)
        return
    end
    for _, s in ipairs(SCALES) do
        if pcall(mon.setTextScale, s) then
            local mw, mh = mon.getSize()
            if mw >= W and mh >= H then return end
        end
    end
    pcall(mon.setTextScale, 0.5)
end

local function mirrorCopy(m)
    local src = gfx.win
    pcall(function()
        for i = 0, 15 do
            m.win.setPaletteColor(2 ^ i, src.getPaletteColor(2 ^ i))
        end
        for y = 1, H do
            local t, f, b = src.getLine(y)
            m.win.setCursorPos(1, y)
            m.win.blit(t, f, b)
        end
        local cx, cy = src.getCursorPos()
        m.win.setCursorPos(cx, cy)
        m.win.setCursorBlink(src.getCursorBlink())
    end)
end

-- Centers the mirrored screen on the monitor.
local function placeMirror(m)
    local mw, mh = m.mon.getSize()
    m.ox = math.max(0, math.floor((mw - W) / 2))
    m.oy = math.max(0, math.floor((mh - H) / 2))
    if m.win then
        m.win.reposition(m.ox + 1, m.oy + 1, W, H)
    else
        m.win = window.create(m.mon, m.ox + 1, m.oy + 1, W, H, true)
    end
    pcall(function()
        m.mon.setBackgroundColor(colors.black)
        m.mon.clear()
    end)
    mirrorCopy(m)
end

function gfx.syncMonitors()
    local want = {}
    if settings.mirror then
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "monitor" then want[name] = true end
        end
    end
    for i = #gfx.mirrors, 1, -1 do
        local m = gfx.mirrors[i]
        if want[m.name] then
            want[m.name] = nil
        else
            table.remove(gfx.mirrors, i)
            pcall(function()
                m.mon.setBackgroundColor(colors.black)
                m.mon.clear()
            end)
        end
    end
    for name in pairs(want) do
        local mon = peripheral.wrap(name)
        if mon then
            chooseScale(mon)
            local m = { name = name, mon = mon }
            placeMirror(m)
            table.insert(gfx.mirrors, m)
        end
    end
end

-- Used when the monitor scale setting changes.
function gfx.refitAll()
    for _, m in ipairs(gfx.mirrors) do
        chooseScale(m.mon)
        pcall(placeMirror, m)
    end
end

function gfx.nativeResized()
    local nw, nh = gfx.native.getSize()
    gfx.win.reposition(1, 1, nw, nh)
    W, H = nw, nh
    for _, m in ipairs(gfx.mirrors) do pcall(placeMirror, m) end
end

-- Turns the OS output into the buffered, mirrored terminal. Safe to call once.

-- ── Display setup and teardown ───────────────────────────────────────────────
-- Same buffered, mirrored terminal as Prismarine. When this shell is started
-- from inside Prismarine (or anything else that already redirects the
-- terminal) the outer program already handles monitors, so they are skipped.

local function looksNested()
    local cur = term.current()
    local ok, nat = pcall(term.native)
    return ok and cur ~= nat and cur.getLine == nil
end

function gfx.init()
    if gfx.ready then return end
    gfx.nested = looksNested()
    gfx.prev = term.current()
    gfx.native = gfx.prev
    local nw, nh = gfx.native.getSize()
    gfx.win = window.create(gfx.native, 1, 1, nw, nh, true)
    term.redirect(tee)
    gfx.ready = true
    W, H = term.getSize()
    if gfx.nested then return end

    -- Monitor touches arrive as mouse clicks, and the mirrors follow monitors
    -- being attached, removed or resized.
    local rawPull = os.pullEventRaw
    gfx.rawPull = rawPull
    os.pullEventRaw = function(filter)
        while true do
            local ev = table.pack(rawPull())
            local name = ev[1]
            local drop = false
            if name == "monitor_touch" then
                drop = true
                for _, m in ipairs(gfx.mirrors) do
                    if m.name == ev[2] then
                        local x, y = ev[3] - m.ox, ev[4] - m.oy
                        if x >= 1 and y >= 1 and x <= W and y <= H then
                            ev = table.pack("mouse_click", 1, x, y)
                            drop = false
                        end
                        break
                    end
                end
            elseif name == "monitor_resize" then
                for _, m in ipairs(gfx.mirrors) do
                    if m.name == ev[2] then pcall(placeMirror, m) end
                end
            elseif name == "peripheral" or name == "peripheral_detach" then
                pcall(gfx.syncMonitors)
            elseif name == "term_resize" then
                pcall(gfx.nativeResized)
            end
            if not drop and (filter == nil or ev[1] == filter or ev[1] == "terminate") then
                return table.unpack(ev, 1, ev.n)
            end
        end
    end

    pcall(gfx.syncMonitors)
end

-- Gives the terminal back exactly as it was found.
function gfx.shutdown()
    if not gfx.ready then return end
    gfx.ready = false
    for i = #gfx.mirrors, 1, -1 do
        local m = gfx.mirrors[i]
        pcall(function()
            for n = 0, 15 do
                local c = 2 ^ n
                m.mon.setPaletteColor(c, term.nativePaletteColor(c))
            end
            m.mon.setBackgroundColor(colors.black)
            m.mon.clear()
        end)
    end
    gfx.mirrors = {}
    if gfx.rawPull then
        os.pullEventRaw = gfx.rawPull
        gfx.rawPull = nil
    end
    term.redirect(gfx.prev)
    for c, v in pairs(PAL0) do
        pcall(term.setPaletteColor, c, v[1], v[2], v[3])
    end
end

-- Mirroring is the outer program's job when nested.
local function syncMonitors()
    if not gfx.nested then gfx.syncMonitors() end
end
local function refitMonitors()
    if not gfx.nested then gfx.refitAll() end
end

-- ── Color math and the boot palette ──────────────────────────────────────────

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
    local i = math.floor(h)
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

-- Choices for the colored lower half of the logo. Any #RRGGBB also works.
local LOGO_COLORS = {
    { name = "Blue",       rgb = { 63, 85, 255 } },
    { name = "Prismarine", rgb = { 70, 214, 178 } },
    { name = "Aqua",       rgb = { 0, 200, 255 } },
    { name = "Emerald",    rgb = { 46, 204, 113 } },
    { name = "Lime",       rgb = { 163, 230, 53 } },
    { name = "Gold",       rgb = { 255, 200, 46 } },
    { name = "Orange",     rgb = { 255, 138, 31 } },
    { name = "Red",        rgb = { 255, 69, 77 } },
    { name = "Rose",       rgb = { 255, 107, 181 } },
    { name = "Magenta",    rgb = { 224, 75, 229 } },
    { name = "Violet",     rgb = { 155, 92, 255 } },
    { name = "Ice",        rgb = { 184, 230, 255 } },
    { name = "Rainbow",    rainbow = true },
}

local function parseHex(text)
    if type(text) ~= "string" then return nil end
    local h = text:match("^#?(%x%x%x%x%x%x)$")
    if not h then return nil end
    return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) },
        "#" .. h:lower()
end

local function logoPreset(name)
    for i, c in ipairs(LOGO_COLORS) do
        if c.name == name then return c, i end
    end
end

-- Color of the lower half at time t (only Rainbow changes over time).
local function logoRGB(t)
    local p = logoPreset(settings.logoColor)
    if p then
        if p.rainbow then return hsv((t or 0) * 0.1, 0.72, 1) end
        return p.rgb
    end
    return parseHex(settings.logoColor) or LOGO_COLORS[1].rgb
end

local function logoName()
    if logoPreset(settings.logoColor) then return settings.logoColor end
    local _, hex = parseHex(settings.logoColor)
    return hex or "Blue"
end

-- Smooth dark to bright ramps, sampled at t = 0..1.
local function accentAt(acc, t)
    local dark = { acc[1] * 0.10, acc[2] * 0.10, acc[3] * 0.10 }
    if t <= 0.65 then return mix(dark, acc, t / 0.65) end
    local light = mix(acc, { 255, 255, 255 }, 0.40)
    return mix(acc, light, (t - 0.65) / 0.35)
end

local function grayAt(t)
    local v
    if t <= 0.6 then v = lerp(24, 150, t / 0.6) else v = lerp(150, 245, (t - 0.6) / 0.4) end
    return { v, v, math.min(255, v + 3) }
end

-- Which palette slot holds what while the boot screen or logo studio is up.
-- All 16 are used, so everything is put back with restorePalette afterwards.
local P = {
    bg    = colors.black,
    txt   = colors.white,
    dim   = colors.lightGray,
    track = colors.gray,
    gr    = { colors.orange, colors.yellow, colors.lime, colors.pink, colors.cyan },
    ac    = { colors.brown, colors.green, colors.red, colors.magenta, colors.purple, colors.blue },
    spark = colors.lightBlue,
}

local function setPal(c, rgb, f)
    f = f or 1
    term.setPaletteColor(c,
        clamp(rgb[1] * f / 255, 0, 1), clamp(rgb[2] * f / 255, 0, 1), clamp(rgb[3] * f / 255, 0, 1))
end

-- f fades the whole screen: 1 is normal, 0 is black.
local function applyPalette(accent, f)
    setPal(P.bg, { 5, 7, 12 }, f)
    setPal(P.txt, { 236, 242, 248 }, f)
    setPal(P.dim, { 120, 132, 148 }, f)
    setPal(P.track, { 26, 31, 42 }, f)
    for i, c in ipairs(P.gr) do setPal(c, grayAt((i - 1) / (#P.gr - 1)), f) end
    for i, c in ipairs(P.ac) do setPal(c, accentAt(accent, (i - 1) / (#P.ac - 1)), f) end
    setPal(P.spark, mix(accent, { 255, 255, 255 }, 0.7), f)
end

-- The OS colors. Every one of the 16 slots keeps its hue (cyan stays cyan) but
-- gets a softer, more modern shade. Switch off in Settings for classic colors.
local THEME = {
    [colors.black]     = { 9, 12, 20 },
    [colors.gray]      = { 34, 41, 56 },
    [colors.lightGray] = { 146, 158, 176 },
    [colors.white]     = { 236, 241, 248 },
    [colors.blue]      = { 52, 104, 236 },
    [colors.lightBlue] = { 116, 170, 255 },
    [colors.cyan]      = { 64, 196, 214 },
    [colors.green]     = { 44, 160, 96 },
    [colors.lime]      = { 132, 222, 92 },
    [colors.yellow]    = { 246, 206, 84 },
    [colors.orange]    = { 250, 152, 52 },
    [colors.red]       = { 240, 82, 92 },
    [colors.pink]      = { 246, 142, 192 },
    [colors.magenta]   = { 208, 84, 222 },
    [colors.purple]    = { 144, 96, 232 },
    [colors.brown]     = { 150, 100, 62 },
}

local function nativePalette()
    for i = 0, 15 do
        local c = 2 ^ i
        term.setPaletteColor(c, term.nativePaletteColor(c))
    end
end

local function themePalette()
    for c, rgb in pairs(THEME) do setPal(c, rgb) end
end

-- Puts the normal OS colors back (also undoes boot screen and menu logo shades).
local function restorePalette()
    if settings.theme then themePalette() else nativePalette() end
end

-- ── Pixelbox lite ────────────────────────────────────────────────────────────

-- Loads the downloaded library after checking its SHA-256.
function gfx.loadPixelbox(tick)
    if gfx.pb then return true end
    if not fs.exists(PB_FILE) then
        gfx.err = "not downloaded"
        return false
    end
    local text = readFile(PB_FILE)
    if not text or sha256(text, tick) ~= PB_HASH then
        gfx.err = "checksum mismatch"
        return false
    end
    local fn, err = load(text, "=pixelbox_lite")
    if not fn then
        gfx.err = tostring(err)
        return false
    end
    local ok, mod = pcall(fn)
    if not ok or type(mod) ~= "table" or type(mod.new) ~= "function" then
        gfx.err = "bad module"
        return false
    end
    -- The first box builds Pixelbox's lookup tables, which takes a moment.
    local okBox = pcall(mod.new, term.current(), colors.black)
    if not okBox then
        gfx.err = "setup failed"
        return false
    end
    gfx.pb = mod
    gfx.err = nil
    return true
end

-- Downloads Pixelbox lite. Returns true, or false and a reason.
function gfx.download()
    if not http then return false, "HTTP is disabled on this server" end
    local resp, err = http.get(PB_URL, nil, true)
    if not resp then return false, tostring(err) end
    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()
    if status ~= 200 or not body or body == "" then
        return false, "Status " .. tostring(status)
    end
    if sha256(body) ~= PB_HASH then
        return false, "Checksum mismatch, file not saved"
    end
    if not fs.exists(PB_DIR) then fs.makeDir(PB_DIR) end
    local f = fs.open(PB_FILE, "wb")
    if not f then return false, "Cannot write " .. PB_FILE end
    f.write(body)
    f.close()
    return true
end

-- 4x4 ordered dither threshold in (0, 1).
local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local function thr(x, y)
    return (BAYER[(y - 1) % 4 + 1][(x - 1) % 4 + 1] + 0.5) / 16
end

-- Header: solid behind the title, then a dithered fade to black.
local hdr = { key = nil }
function gfx.header(title, bar)
    if not gfx.pb or not settings.graphics or bar == colors.black then return false end
    local solid = math.min(W, #title + 3)
    if solid >= W - 3 then return false end
    local key = W .. ":" .. bar .. ":" .. solid
    if hdr.key ~= key then
        local ok = pcall(function()
            hdr.win = window.create(term.current(), 1, 1, W, 1, true)
            hdr.box = gfx.pb.new(hdr.win, colors.black)
            local mid = (bar == colors.gray) and colors.lightGray or colors.gray
            local pw = W * 2
            local x0 = solid * 2
            for py = 1, 3 do
                for px = 1, pw do
                    local col = bar
                    if px > x0 then
                        local t = (px - x0) / (pw - x0)
                        local a, b, f
                        if t < 0.5 then
                            a, b, f = bar, mid, t * 2
                        else
                            a, b, f = mid, colors.black, (t - 0.5) * 2
                        end
                        col = (f > thr(px, py)) and b or a
                    end
                    hdr.box.canvas[py][px] = col
                end
            end
        end)
        if not ok then
            hdr.key = nil
            return false
        end
        hdr.key = key
    end
    return (pcall(hdr.box.render, hdr.box))
end

-- Highlight for the selected list row: solid behind the text, then a dithered
-- fade to black. The caller writes the text on top afterwards.
local selBar = { key = nil }
function gfx.selectBar(row, solid, color)
    if not gfx.pb or not settings.graphics or color == colors.black then return false end
    if solid >= W - 3 then return false end
    if selBar.w ~= W then
        selBar.win, selBar.box, selBar.key, selBar.w = nil, nil, nil, W
    end
    local key = color .. ":" .. solid
    local ok = pcall(function()
        if not selBar.win then
            selBar.win = window.create(term.current(), 1, row, W, 1, true)
            selBar.box = gfx.pb.new(selBar.win, colors.black)
        else
            selBar.win.reposition(1, row)
        end
        if selBar.key ~= key then
            local mid = (color == colors.gray) and colors.black or colors.gray
            local pw, x0 = W * 2, solid * 2
            local canvas = selBar.box.canvas
            for py = 1, 3 do
                for px = 1, pw do
                    local col = color
                    if px > x0 then
                        local t = (px - x0) / (pw - x0)
                        local a, b, f
                        if t < 0.5 then
                            a, b, f = color, mid, t * 2
                        else
                            a, b, f = mid, colors.black, (t - 0.5) * 2
                        end
                        col = (f > thr(px, py)) and b or a
                    end
                    canvas[py][px] = col
                end
            end
            selBar.key = key
        end
    end)
    if not ok then
        selBar.win, selBar.key = nil, nil
        return false
    end
    return (pcall(selBar.box.render, selBar.box))
end

-- ── The logo ─────────────────────────────────────────────────────────────────
-- The boot screen logo is drawn from plain text art. In the art a space is
-- empty, "." ":" "+" are light shades, and every other character is solid. The
-- top half of the art is gray and the bottom half takes the logo color, like
-- the Prismarine logo.
local SRC, LOGO_W, LOGO_R, LOGO_SPLIT = {}, 1, 1, 1
local logoCache = {}

-- Scales the logo to dw pixels wide. A terminal cell is 6x9 units and holds
-- 2x3 Pixelbox pixels, so one art character is 2x3 pixels at full size.
local function buildLogo(dw)
    if logoCache[dw] then return logoCache[dw] end
    local SH = LOGO_R * 2
    local dh = math.max(4, math.floor(dw * (LOGO_R * 9) / (LOGO_W * 6) + 0.5))
    local lv, rg = {}, {}
    for dy = 1, dh do
        local y0, y1 = (dy - 1) * SH / dh, dy * SH / dh
        local row = {}
        for dx = 1, dw do
            local x0, x1 = (dx - 1) * LOGO_W / dw, dx * LOGO_W / dw
            local sum, wsum = 0, 0
            for sy = math.floor(y0) + 1, math.min(SH, math.ceil(y1)) do
                local wy = math.min(sy, y1) - math.max(sy - 1, y0)
                local srow = SRC[sy]
                for sx = math.floor(x0) + 1, math.min(LOGO_W, math.ceil(x1)) do
                    local wx = math.min(sx, x1) - math.max(sx - 1, x0)
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

-- Which of n palette shades a brightness maps to, with ordered dithering.
local function slotFor(level, n, x, y)
    local i = math.floor(level * (n - 1) + thr(x, y))
    if i < 0 then i = 0 elseif i > n - 1 then i = n - 1 end
    return i + 1
end

local SHADE_CH = { [" "] = 0, ["."] = 0.34, [":"] = 0.58, ["+"] = 0.8 }

-- Turns lines of text art into the brightness map buildLogo scales.
local function setLogoArt(lines)
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, #l) end
    LOGO_W, LOGO_R = math.max(1, w), #lines
    SRC = {}
    for r, line in ipairs(lines) do
        local row = {}
        for x = 1, LOGO_W do
            local ch = line:sub(x, x)
            if ch == "" then ch = " " end
            row[x] = SHADE_CH[ch] or 1.0
        end
        SRC[r * 2 - 1], SRC[r * 2] = row, row
    end
    LOGO_SPLIT = LOGO_R
    logoCache = {}
end

-- Built in block letters. Each # becomes two characters of solid art.
local GLYPHS = {
    S = { ".####", "#....", "#....", ".###.", "....#", "....#", "####." },
    H = { "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
    E = { "#####", "#....", "#....", "####.", "#....", "#....", "#####" },
    L = { "#....", "#....", "#....", "#....", "#....", "#....", "#####" },
    B = { "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####." },
    A = { ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#" },
}

local function wordArt(word)
    local rows = {}
    for r = 1, 7 do
        local parts = {}
        for i = 1, #word do
            local g = GLYPHS[word:sub(i, i):upper()]
            local line = g[r]:gsub(".", function(ch) return ch == "#" and "##" or "  " end)
            parts[#parts + 1] = line
        end
        rows[r] = table.concat(parts, "  ")
    end
    return rows
end

-- Reads /.prismshell/logo.txt. Returns nil when it is missing or empty.
local function customArt()
    if not fs.exists(LOGO_FILE) then return nil end
    local f = fs.open(LOGO_FILE, "r")
    if not f then return nil end
    local lines = {}
    while true do
        local l = f.readLine()
        if not l then break end
        l = (l:gsub("\r", ""))
        l = (l:gsub("\t", "    "))
        lines[#lines + 1] = (l:gsub("%s+$", ""))
    end
    f.close()
    while #lines > 0 and lines[1] == "" do table.remove(lines, 1) end
    while #lines > 0 and lines[#lines] == "" do table.remove(lines) end
    while #lines > 20 do table.remove(lines) end
    if #lines == 0 then return nil end
    return lines
end

-- Picks the art named in the settings. Falls back to the built in SHELL.
local function loadLogoArt()
    local lines
    if settings.logoArt == "Custom" then lines = customArt() end
    if not lines then
        lines = wordArt(settings.logoArt == "Base" and "BASE" or "SHELL")
    end
    setLogoArt(lines)
end

loadLogoArt()


-- ── Shell state ──────────────────────────────────────────────────────────────

local S = {
    history   = {},     -- command history, oldest first
    aliases   = {},     -- aliases saved by this shell: name -> program
    prevAlias = {},     -- what each touched alias was before (false = none)
    prevDir   = nil,    -- for "cd -"
    lastOk    = nil,    -- did the last command succeed
    quit      = false,
    restart   = false,  -- start the shell again after an update
    paused    = false,  -- a full screen menu is open, so the top bar waits
    update    = nil,    -- newer version found by the background check
    checkUrl  = nil,
    headKey   = nil,
    loaded    = false,
}

local L = { body = nil }   -- the window the prompt and programs draw in

-- Messenger events do not exist in the shell. Kept so shared code can call it.
local function handleNet() end

local buttonHits = {}

local function pad(text, width)
    if width < 0 then width = 0 end
    text = text:sub(1, width)
    return text .. string.rep(" ", width - #text)
end

local function resetTerm()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorBlink(false)
end

local function clockText()
    local mode = settings.clock
    if mode == "Off" then return "" end
    local real = settings.hour24 and os.date("%H:%M") or os.date("%I:%M %p")
    local game = textutils.formatTime(os.time(), settings.hour24)
    if mode == "Real" then return real end
    if mode == "Game" then return game end
    return real .. " | " .. game
end

local function header(title)
    local bar = colorValue(settings.barColor, colors.blue)
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(bar)
    term.setTextColor(textOn(bar))
    term.write(string.rep(" ", W))
    -- Pixelbox draws a dithered fade to black over the plain bar. The title is
    -- written on top of its solid part afterwards.
    local fancy = gfx.header(title, bar)
    term.setBackgroundColor(bar)
    term.setTextColor(textOn(bar))
    term.setCursorPos(2, 1)
    term.write(title:sub(1, W - 2))
    local clock = clockText()
    if clock ~= "" and W >= #title + #clock + 4 then
        term.setCursorPos(W - #clock, 1)
        if fancy then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
        end
        term.write(clock)
    end
end

-- Plain text bar on the bottom row.
local function footer(text)
    buttonHits = {}
    term.setCursorPos(1, H)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(pad(" " .. text, W))
end

-- Clickable button bar on the bottom row.
-- buttons: list of { tag = "Q", label = "Back", k = "q" }
-- Buttons that do not fit the screen are skipped. Their keys still work.
local function footerButtons(buttons)
    buttonHits = {}
    term.setCursorPos(1, H)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", W))
    local accent = colorValue(settings.barColor, colors.blue)
    if accent == colors.black or accent == colors.gray then accent = colors.blue end
    local x = 1
    for _, b in ipairs(buttons) do
        local tagText = (b.tag ~= "") and (" " .. b.tag .. " ") or ""
        local labelText = ((b.tag ~= "") and "" or " ") .. b.label .. " "
        local total = #tagText + #labelText
        if x + total - 1 > W then break end
        term.setCursorPos(x, H)
        if tagText ~= "" then
            term.setBackgroundColor(accent)
            term.setTextColor(textOn(accent))
            term.write(tagText)
        end
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(labelText)
        table.insert(buttonHits, { x1 = x, x2 = x + total - 1, k = b.k })
        x = x + total + 1
    end
end

local function hitButton(x, y)
    if y ~= H then return nil end
    for _, h in ipairs(buttonHits) do
        if x >= h.x1 and x <= h.x2 then return h.k end
    end
    return nil
end

-- Reads the next input event and turns it into a table:
--   k      key name ("q", "enter", "up", ...) from a key press, a typed
--          character, or a clicked footer button
--   click  true with x and y for a mouse click outside the button bar
--   scroll mouse wheel direction
-- Letters arrive as both a key event and a char event. The char event that
-- follows a key event for the same letter is dropped.
local lastKeyName, lastKeyAt = nil, 0

local function readInput()
    local ev, a, b, c = os.pullEventRaw()
    if ev == "key" then
        local name = keys.getName(a)
        if not name then return nil end
        lastKeyName, lastKeyAt = name, os.epoch("utc")
        return { k = name }
    elseif ev == "char" then
        local ch = tostring(a):lower()
        if lastKeyName == ch and os.epoch("utc") - lastKeyAt < 250 then
            lastKeyName = nil
            return nil
        end
        return { k = ch }
    elseif ev == "mouse_click" then
        local k = hitButton(b, c)
        if k then return { k = k } end
        return { click = true, x = b, y = c }
    elseif ev == "mouse_scroll" then
        return { scroll = a }
    elseif ev == "rednet_message" then
        handleNet(a, b, c)
        return {}
    elseif ev == "term_resize" then
        W, H = term.getSize()
        return {}
    end
    return { ev = ev }
end

local function drawList(title, entries, sel, top, buttons)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    local visible = H - 2
    local scroll = #entries > visible
    local w = scroll and (W - 1) or W
    local hl = colorValue(settings.highlight, colors.lightBlue)
    for i = 1, visible do
        local idx = top + i - 1
        local e = entries[idx]
        if e then
            local row = i + 1
            if idx == sel then
                local solid = #e.label + 3
                local fancy = solid < w - 3 and gfx.selectBar(row, solid, hl)
                term.setBackgroundColor(hl)
                term.setTextColor(textOn(hl))
                term.setCursorPos(1, row)
                if fancy then
                    term.write(pad(" " .. e.label, solid))
                else
                    term.write(pad(" " .. e.label, w))
                end
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(e.color or colors.white)
                term.setCursorPos(1, row)
                term.write(pad(" " .. e.label, w))
            end
            if e.swatch then
                term.setBackgroundColor(e.swatch)
                term.setCursorPos(w - 2, row)
                term.write("  ")
            end
        end
    end
    if scroll then
        local total = #entries
        local thumb = math.max(1, math.floor(visible * visible / total + 0.5))
        local span = visible - thumb
        local pos = math.floor((top - 1) / (total - visible) * span + 0.5)
        for i = 1, visible do
            term.setCursorPos(W, i + 1)
            term.setBackgroundColor((i > pos and i <= pos + thumb) and colors.lightGray or colors.gray)
            term.write(" ")
        end
    end
    footerButtons(buttons)
end

local function clampTop(sel, top)
    local visible = H - 2
    if sel < top then top = sel end
    if sel > top + visible - 1 then top = sel - visible + 1 end
    if top < 1 then top = 1 end
    return top
end

local function waitKey()
    while true do
        local i = readInput()
        if i and (i.k or i.click) then return end
    end
end

local function fillRect(x1, y1, x2, y2, bg)
    if x2 < x1 then return end
    term.setBackgroundColor(bg)
    local blank = string.rep(" ", x2 - x1 + 1)
    for y = y1, y2 do
        term.setCursorPos(x1, y)
        term.write(blank)
    end
end

-- Splits text into lines of at most width characters, at spaces when it can.
local function wrapText(text, width)
    text = tostring(text)
    width = math.max(1, width)
    if text == "" then return { "" } end
    local out = {}
    while #text > width do
        local cut = width
        local sp = text:sub(1, width + 1):match("^.*() ")
        if sp and sp > 1 then cut = sp - 1 end
        table.insert(out, text:sub(1, cut))
        text = text:sub(cut + 1):gsub("^ +", "")
    end
    table.insert(out, text)
    return out
end

-- A panel with a colored stripe on the left. Returns the row below it.
local function drawCard(y, lines, stripe, fg)
    local rows = {}
    for _, l in ipairs(lines) do
        for _, piece in ipairs(wrapText(l, W - 6)) do table.insert(rows, piece) end
    end
    local maxRows = math.max(1, H - y - 3)
    while #rows > maxRows do table.remove(rows) end
    local h = #rows + 2
    fillRect(2, y, W - 1, y + h - 1, colors.gray)
    fillRect(2, y, 2, y + h - 1, stripe or colors.lightBlue)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(fg or colors.white)
    for n, text in ipairs(rows) do
        term.setCursorPos(4, y + n)
        term.write(text)
    end
    return y + h
end

local function showMessage(title, lines, color)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    drawCard(3, lines, color, colors.white)
    footerButtons({ { tag = "", label = "Continue (any key)", k = "enter" } })
    waitKey()
end

local function showBusy(title, text)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    drawCard(3, { text }, colors.yellow, colors.white)
end

-- Asks for a line of text. Returns nil when the answer is blank.
local function ask(title, lines, default, mask)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    local below = drawCard(3, lines, colors.lightBlue, colors.white)
    footer("Press Enter to confirm. Leave blank to cancel.")
    local row = math.min(below + 1, H - 1)
    fillRect(2, row, W - 1, row, colors.gray)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(3, row)
    term.setCursorBlink(true)
    local ok, value = pcall(read, mask, nil, nil, default)
    term.setCursorBlink(false)
    if not ok or not value then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

-- Returns true when the user presses Y or clicks Yes.
local function confirm(lines)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header("Confirm")
    drawCard(3, lines, colors.yellow, colors.white)
    footerButtons({
        { tag = "Y", label = "Yes", k = "y" },
        { tag = "N", label = "No", k = "n" },
    })
    while true do
        local i = readInput() or {}
        if i.k == "y" then
            return true
        elseif i.k == "n" or i.k == "enter" or i.k == "q" or i.k == "backspace" then
            return false
        end
    end
end

-- Shows a short list of options. Returns the chosen number or nil.
local function pickMenu(title, options)
    local entries = {}
    for n, o in ipairs(options) do entries[n] = { label = o } end
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Select", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    while true do
        top = clampTop(sel, top)
        drawList(title, entries, sel, top, buttons)
        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            return sel
        elseif i.k == "q" or i.k == "backspace" then
            return nil
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            return top + i.y - 2
        elseif i.scroll then
            sel = math.max(1, math.min(#entries, sel + i.scroll))
        end
    end
end

local function fmtSize(n)
    if n >= 1048576 then
        return string.format("%.1f MB", n / 1048576)
    elseif n >= 1024 then
        return string.format("%.1f KB", n / 1024)
    end
    return n .. " B"
end
-- ── Boot screen and logo studio ──────────────────────────────────────────────
-- These draw with Pixelbox on top of a reprogrammed 16 color palette, so the
-- gradients are smooth. The palette is always put back before the normal UI.

-- Sets up a full screen pixel scene with the logo centered in it. reserve is
-- the number of text rows kept below the logo. Returns nil on a tiny screen.
local function newScene(reserve)
    if not gfx.pb or not settings.graphics then return nil end
    local pw, ph = W * 2, H * 3
    local dw = math.min(98, pw - 4, math.floor((H - reserve) * 3 * (LOGO_W * 6) / (LOGO_R * 9)))
    if dw < 36 then return nil end
    local logo = buildLogo(dw)
    local logoRows = math.ceil(logo.h / 3)
    local top = math.max(1, math.floor((H - logoRows - reserve) / 2) + 1)
    local ok, box = pcall(gfx.pb.new, term.current(), P.bg)
    if not ok then return nil end
    local sc = {
        box = box, logo = logo, pw = pw, ph = ph, logoRows = logoRows, top = top,
        ox = math.floor((pw - dw) / 2),
        oy = (top - 1) * 3 + math.floor((logoRows * 3 - logo.h) / 2),
        t = 0, last = nowSec(), bubbles = {},
    }
    for i = 1, 16 do
        sc.bubbles[i] = {
            x = math.random(2, pw - 1), y = math.random(1, ph),
            v = 4 + math.random() * 10, ph = math.random() * 6, c = math.random(2, 4),
        }
    end
    return sc
end

local function paintBubbles(sc, dt)
    local canvas = sc.box.canvas
    for _, b in ipairs(sc.bubbles) do
        b.y = b.y - b.v * dt
        b.x = b.x + math.sin(b.y * 0.2 + b.ph) * dt * 4
        if b.y < 1 then
            b.y = sc.ph
            b.x = math.random(2, sc.pw - 1)
            b.v = 4 + math.random() * 10
        end
        local x, y = math.floor(b.x + 0.5), math.floor(b.y + 0.5)
        if x >= 1 and x <= sc.pw and y >= 1 and y <= sc.ph then
            canvas[y][x] = P.ac[b.c]
        end
    end
end

-- The gray half shines, the colored half ripples like water. intro (0..1)
-- wipes the logo in from the left, the colored half a little behind.
local function paintLogo(sc, intro)
    local logo, canvas, t = sc.logo, sc.box.canvas, sc.t
    local dw, dh = logo.w, logo.h
    local ngr, nac = #P.gr, #P.ac
    local lastGray = 0
    for dy = 1, dh do
        if logo.rg[dy] == 1 then lastGray = dy end
    end
    local shine = ((t * 0.45) % 2.4 - 0.6) * (dw + dh * 1.6)
    local edgeTop = intro * (dw + 14)
    local edgeBot = clamp((intro - 0.25) / 0.75, 0, 1) * (dw + 14)
    for dy = 1, dh do
        local lvrow = logo.lv[dy]
        local gray = logo.rg[dy] == 1
        local crow = canvas[sc.oy + dy]
        local r = dy - lastGray
        local off = 0
        if not gray then
            off = math.floor(math.sin(r * 0.95 - t * 4.2) * (0.6 + r * 0.05) * 1.2 + 0.5)
        end
        for dx = 1, dw do
            local l = lvrow[clamp(dx + off, 1, dw)]
            if l > 0.03 then
                local a = ((gray and edgeTop or edgeBot) - dx) / 10
                if a > 0 then
                    if a > 1 then a = 1 end
                    if gray then
                        local d = (dx + dy * 1.6) - shine
                        if d > -9 and d < 9 then
                            local k = 1 - math.abs(d) / 9
                            l = l + k * k * 0.6
                        end
                    else
                        l = l * (0.86 + 0.14 * math.sin(dx * 0.45 + r * 0.8 - t * 3.2))
                    end
                    l = l * a + (1 - a) * a * 1.6
                    if gray then
                        crow[sc.ox + dx] = P.gr[slotFor(l, ngr, dx, dy)]
                    else
                        crow[sc.ox + dx] = P.ac[slotFor(l, nac, dx, dy)]
                    end
                end
            end
        end
    end
end

-- A three pixel tall bar with a glowing head and a moving highlight.
local function paintBar(sc, prog)
    local nac = #P.ac
    local bw, x0, y0 = sc.barW, sc.barX, sc.barY
    local canvas = sc.box.canvas
    local fl = math.floor(bw * prog + 0.5)
    local sweep = (sc.t * 28) % (bw + 24) - 12
    for i = 1, bw do
        for k = 0, 2 do
            local corner = (i == 1 or i == bw) and k ~= 1
            if not corner then
                local c = P.track
                if i <= fl then
                    local level = (0.30 + 0.70 * i / bw) * ((k == 1) and 1 or 0.72)
                    if math.abs(i - sweep) < 3 then level = level + 0.25 end
                    c = P.ac[slotFor(level, nac, x0 + i, y0 + k)]
                    if k == 1 and i > fl - 2 then c = P.spark end
                end
                canvas[y0 + k][x0 + i - 1] = c
            end
        end
    end
end

local function centerText(row, text, fg)
    term.setBackgroundColor(P.bg)
    term.setTextColor(fg)
    term.setCursorPos(math.max(1, math.floor((W - #text) / 2) + 1), row)
    term.write(text)
end

local boot = {}

-- Starts the boot screen. Returns nil when it cannot be shown.
function boot.start(fast)
    local sc = newScene(5)
    if not sc or W < 20 then return nil end
    local cells = math.min(W - 12, 40)
    sc.barW = cells * 2
    sc.barCol = math.floor((W - cells) / 2) + 1
    sc.barCells = cells
    sc.barX = (sc.barCol - 1) * 2 + 1
    sc.tagRow = sc.top + sc.logoRows + 1
    sc.barRow = sc.tagRow + 2
    sc.statRow = sc.barRow + 1
    sc.barY = (sc.barRow - 1) * 3 + 1
    sc.intro, sc.shown, sc.target = 0, 0, 0
    sc.status, sc.fast, sc.out = "", fast or false, 0
    sc.born = nowSec()
    sc.lastF = nil
    applyPalette(logoRGB(0), 0)
    term.setCursorBlink(false)
    return sc
end

function boot.frame(sc)
    local now = nowSec()
    local dt = math.min(0.1, now - sc.last)
    sc.last = now
    sc.t = sc.t + dt
    sc.intro = math.min(1, sc.intro + dt / (sc.fast and 0.3 or 1.2))
    sc.shown = sc.shown + (sc.target - sc.shown) * math.min(1, dt * (sc.fast and 16 or 7))
    if sc.target - sc.shown < 0.002 then sc.shown = sc.target end

    local f = clamp((now - sc.born) / (sc.fast and 0.1 or 0.45), 0, 1) * (1 - sc.out)
    local preset = logoPreset(settings.logoColor)
    if f ~= sc.lastF or (preset and preset.rainbow) then
        applyPalette(logoRGB(sc.t), f)
        sc.lastF = f
    end

    sc.box:clear(P.bg)
    paintBubbles(sc, dt)
    paintLogo(sc, sc.intro)
    paintBar(sc, sc.shown)
    sc.box:render()

    centerText(sc.tagRow, settings.osName .. "  v" .. VERSION, P.txt)
    centerText(sc.statRow, sc.status, P.dim)
    term.setCursorPos(sc.barCol + sc.barCells + 1, sc.barRow)
    term.setTextColor(P.dim)
    term.write(string.format("%3d%%", math.floor(sc.shown * 100 + 0.5)))
end

-- Draws frames until untilFn() is true or maxSec passes. A key press or click
-- makes the rest of the boot screen quick.
function boot.wait(sc, untilFn, maxSec)
    local start = nowSec()
    while true do
        boot.frame(sc)
        if untilFn() or nowSec() - start >= maxSec then return end
        local timer = os.startTimer(0.05)
        while true do
            local ev, a = os.pullEventRaw()
            if ev == "timer" and a == timer then break end
            if ev == "key" or ev == "mouse_click" then sc.fast = true end
        end
    end
end

-- Runs one step of real work while the screen keeps animating. work gets a
-- tick function to call from long loops (the hash does).
function boot.stage(sc, label, frac, work)
    sc.status = label
    sc.target = sc.target + (frac - sc.target) * 0.4
    local tick = function()
        if nowSec() - sc.last >= 0.05 then boot.frame(sc) end
    end
    local result
    if work then result = work(tick) end
    sc.target = frac
    boot.wait(sc, function() return sc.shown >= frac - 0.01 end, 1.5)
    return result
end

function boot.finish(sc)
    sc.status = "Ready"
    sc.target = 1
    boot.wait(sc, function() return sc.shown >= 0.995 and sc.intro >= 1 end, 4)
    boot.wait(sc, function() return false end, sc.fast and 0.05 or 0.35)
    local start = nowSec()
    local dur = sc.fast and 0.12 or 0.55
    repeat
        sc.out = clamp((nowSec() - start) / dur, 0, 1)
        boot.frame(sc)
        if sc.out < 1 then
            local timer = os.startTimer(0.05)
            repeat
                local ev, a = os.pullEventRaw()
            until ev == "timer" and a == timer
        end
    until sc.out >= 1
    restorePalette()
    resetTerm()
    term.clear()
end

function boot.abort()
    pcall(restorePalette)
    resetTerm()
    term.clear()
    term.setCursorPos(1, 1)
end

local function inputFrom(ev, a, b, c)
    if ev == "key" then
        local name = keys.getName(a)
        if not name then return nil end
        lastKeyName, lastKeyAt = name, os.epoch("utc")
        return { k = name }
    elseif ev == "char" then
        local ch = tostring(a):lower()
        if lastKeyName == ch and os.epoch("utc") - lastKeyAt < 250 then
            lastKeyName = nil
            return nil
        end
        return { k = ch }
    elseif ev == "mouse_click" then
        local k = hitButton(b, c)
        if k then return { k = k } end
        return { click = true, x = b, y = c }
    end
    return nil
end

local function ensureGraphics()
    if gfx.pb then return true end
    if not fs.exists(PB_FILE) then
        showBusy("Pixelbox", "Downloading Pixelbox lite...")
        local ok, err = gfx.download()
        if not ok then
            showMessage("Pixelbox", { "Download failed.", tostring(err) }, colors.red)
            return false
        end
    end
    showBusy("Pixelbox", "Loading Pixelbox lite...")
    if not gfx.loadPixelbox() then
        showMessage("Pixelbox", { "Could not load Pixelbox lite.", tostring(gfx.err) }, colors.red)
        return false
    end
    return true
end

-- Live preview of the logo. Pick a color and watch the colored half change.
local function logoStudio()
    if not settings.graphics or not gfx.pb then
        showMessage("Logo color", {
            "Pixel graphics are off or not loaded.",
            "Turn on Pixel graphics in Settings first.",
        }, colors.yellow)
        return
    end
    local sc = newScene(4)
    if not sc then
        showMessage("Logo color", { "This screen is too small for the preview." }, colors.yellow)
        return
    end

    local original = settings.logoColor
    local count = #LOGO_COLORS
    local _, hexNow = parseHex(settings.logoColor)
    local custom = hexNow
    local _, presetIdx = logoPreset(settings.logoColor)
    local idx = presetIdx or (count + 1)
    local saved = false

    local function apply()
        if idx <= count then
            settings.logoColor = LOGO_COLORS[idx].name
        elseif custom then
            settings.logoColor = custom
        end
    end
    local function label()
        if idx <= count then return LOGO_COLORS[idx].name end
        return "Custom " .. (custom or "(press H)")
    end

    local function draw()
        local now = nowSec()
        local dt = math.min(0.1, now - sc.last)
        sc.last = now
        sc.t = sc.t + dt
        applyPalette(logoRGB(sc.t), 1)
        sc.box:clear(P.bg)
        paintBubbles(sc, dt)
        paintLogo(sc, 1)
        sc.box:render()
        local nameRow = sc.top + sc.logoRows + 1
        centerText(nameRow, "<  " .. label() .. "  >", P.txt)
        centerText(nameRow + 1, idx .. " of " .. (count + 1), P.dim)
        term.setBackgroundColor(P.bg)
        term.setTextColor(P.txt)
        term.setCursorPos(2, 1)
        term.write("Logo color")
        footerButtons({
            { tag = "<", label = "Prev", k = "left" },
            { tag = ">", label = "Next", k = "right" },
            { tag = "H", label = "Hex", k = "h" },
            { tag = "Ent", label = "Save", k = "enter" },
            { tag = "Q", label = "Cancel", k = "q" },
        })
    end

    local function hexPrompt()
        restorePalette()
        local v = ask("Custom logo color", { "Hex color, like #3F55FF or 3f55ff:" }, custom)
        if v then
            local rgb, hex = parseHex(v)
            if rgb then
                custom = hex
                idx = count + 1
                apply()
            else
                showMessage("Custom logo color", {
                    "That is not a hex color.",
                    "Use 6 digits, like #3F55FF.",
                }, colors.red)
            end
        end
        resetTerm()
    end

    apply()
    local running = true
    while running do
        draw()
        local timer = os.startTimer(0.05)
        while true do
            local ev, a, b, c = os.pullEventRaw()
            if ev == "timer" and a == timer then break end
            local i = inputFrom(ev, a, b, c)
            if i and i.k then
                local k = i.k
                if k == "left" or k == "a" then
                    idx = (idx - 2) % (count + 1) + 1
                    apply()
                elseif k == "right" or k == "d" then
                    idx = idx % (count + 1) + 1
                    apply()
                elseif k == "h" then
                    hexPrompt()
                elseif k == "enter" then
                    saved = true
                    running = false
                elseif k == "q" or k == "backspace" then
                    running = false
                end
                os.cancelTimer(timer)
                break
            end
        end
    end

    if not saved then settings.logoColor = original end
    restorePalette()
    resetTerm()
    term.clear()
end

-- Plays the boot screen with pretend steps, so a new color can be admired.
local function previewBoot()
    if not settings.graphics or not gfx.pb then
        showMessage("Boot screen", {
            "Pixel graphics are off or not loaded.",
            "Turn on Pixel graphics in Settings first.",
        }, colors.yellow)
        return
    end
    local sc = boot.start(false)
    if not sc then
        showMessage("Boot screen", { "This screen is too small for the boot screen." }, colors.yellow)
        return
    end
    local ok, err = pcall(function()
        boot.stage(sc, "Starting display", 0.20)
        boot.stage(sc, "Loading history", 0.45)
        boot.stage(sc, "Restoring aliases", 0.70)
        boot.stage(sc, "Preparing prompt", 0.90)
        boot.stage(sc, "Starting shell", 1.00)
        boot.finish(sc)
    end)
    if not ok then
        boot.abort()
        showMessage("Boot screen", { tostring(err) }, colors.red)
    end
end
local function logError(err)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M") .. "  " .. tostring(err))
        f.close()
    end
end
local function plainStatus(lines)
    resetTerm()
    term.clear()
    local y = math.max(1, math.floor(H / 2) - math.floor(#lines / 2))
    for n, text in ipairs(lines) do
        term.setCursorPos(math.max(1, math.floor((W - #text) / 2) + 1), y + n - 1)
        term.write(text)
    end
end

-- Makes Pixelbox lite ready: downloads it on the first boot, checks it, loads it.
-- Returns true when pixel graphics can be used.
local function loadGraphics()
    if not settings.graphics then return false end

    if not fs.exists(PB_FILE) then
        if not http then
            gfx.err = "HTTP is disabled"
            return false
        end
        plainStatus({ settings.osName, "", "First boot: downloading Pixelbox lite..." })
        local ok, err = gfx.download()
        if not ok then
            gfx.err = tostring(err)
            showMessage("Pixelbox", {
                "Could not download Pixelbox lite.",
                tostring(err),
                "",
                "Starting without pixel graphics.",
                "Settings > Pixel graphics tries again.",
            }, colors.yellow)
            return false
        end
    end

    plainStatus({ settings.osName, "", "Loading Pixelbox lite..." })
    if not gfx.loadPixelbox() then
        if gfx.err ~= "not downloaded" then
            showMessage("Pixelbox", {
                "Pixelbox lite could not be loaded.",
                tostring(gfx.err),
                "",
                "Starting without pixel graphics.",
                "Delete /" .. PB_DIR .. " to download it again.",
            }, colors.yellow)
        end
        return false
    end
    return true
end

-- The boot sequence. Every step on the boot screen is real work.

-- ── Updater and version selector ─────────────────────────────────────────────
-- Versions live in the same repo as Prismarine, as p.shell_v<number>.lua, for
-- example p.shell_v1.lua. Upload a file with a bigger number to publish an
-- update. The startup_v<number>.lua files belong to Prismarine and are ignored.

local function repoParts()
    local repo, branch = settings.updateRepo:match("^([^@]+)@?(.*)$")
    if not branch or branch == "" then branch = "main" end
    return repo, branch
end

local function versionUrl(n)
    local repo, branch = repoParts()
    return "https://raw.githubusercontent.com/" .. repo .. "/" .. branch .. "/p.shell_v" .. n .. ".lua"
end

local function listUrl()
    local repo, branch = repoParts()
    return "https://api.github.com/repos/" .. repo .. "/contents/?ref=" .. branch
end

-- Version numbers from a GitHub directory listing, newest first.
local function versionsFromJson(body)
    local found = {}
    local data = body and textutils.unserialiseJSON(body)
    if type(data) == "table" then
        for _, f in ipairs(data) do
            local n = type(f) == "table" and type(f.name) == "string" and f.name:match("^p%.shell_v(%d+)%.lua$")
            if n then table.insert(found, tonumber(n)) end
        end
    end
    table.sort(found, function(x, y) return x > y end)
    return found
end

local function httpGet(url)
    local resp, err, failed = http.get(url, nil, true)
    if not resp then
        local code
        if failed then
            if failed.getResponseCode then code = failed.getResponseCode() end
            pcall(failed.close)
        end
        return nil, code and ("Status " .. code) or tostring(err)
    end
    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()
    if status ~= 200 or not body or body == "" then
        return nil, "Status " .. tostring(status)
    end
    return body
end

-- True when a file exists at the url (asks for the headers only).
local function urlExists(url)
    local ok, resp = pcall(http.get, { url = url, method = "HEAD", binary = true })
    if ok and resp then
        local code = resp.getResponseCode()
        resp.close()
        return code == 200
    end
    return false
end

-- Finds every p.shell_v<number>.lua in the repo, newest first. It asks GitHub
-- for the file list. If that is blocked or rate limited it tries each number
-- (skipped when quiet is true).
local function listVersions(quiet)
    local found = versionsFromJson(httpGet(listUrl()))
    if #found == 0 and not quiet then
        for n = 1, 40 do
            showBusy("Update", "Looking for versions... " .. n .. " of 40")
            if urlExists(versionUrl(n)) then table.insert(found, n) end
        end
        table.sort(found, function(x, y) return x > y end)
    end
    if #found == 0 then return nil, "No p.shell_v<number>.lua files in " .. settings.updateRepo end
    return found
end

local function installVersion(n)
    local want = ask("Update", {
        "Expected SHA-256 of version " .. n .. " (optional):",
        "Leave blank to skip the check.",
    })
    if want then
        want = want:lower():gsub("%s", "")
        if not want:match("^%x+$") or #want ~= 64 then
            showMessage("Update", { "That is not a SHA-256 hash.", "Nothing was changed." }, colors.red)
            return
        end
    end

    showBusy("Update", "Downloading version " .. n .. "...")
    local body, why = httpGet(versionUrl(n) .. "?cb=" .. os.epoch("utc"))
    if not body then
        showMessage("Update", { "Download failed.", tostring(why) }, colors.red)
        return
    end

    if want then
        showBusy("Update", "Checking SHA-256...")
        local got = sha256(body)
        if got ~= want then
            showMessage("Update", {
                "The file does not match the hash.",
                "Got " .. got:sub(1, 16) .. "...",
                "Nothing was changed.",
            }, colors.red)
            return
        end
    end

    -- Refuse a file that does not compile, so a bad download cannot break the shell.
    local fn, syntaxErr = load(body, "=update")
    if not fn then
        showMessage("Update", { "The downloaded file has a syntax error.", tostring(syntaxErr), "Nothing was changed." }, colors.red)
        return
    end

    if body == readFile(SELF) then
        showMessage("Update", { "Already running this exact file.", "Version " .. VERSION }, colors.lime)
        return
    end

    local newVersion = body:match('local VERSION = "([^"]+)"') or tostring(n)
    local older = n < (tonumber(VERSION) or 0)
    if not confirm({
        (older and "Go back to" or "Update to") .. " version " .. newVersion .. "?",
        "Current version: " .. VERSION,
        older and "WARNING: this is OLDER than what you run." or "A backup is saved as " .. SELF .. ".bak",
        want and "SHA-256 verified." or "NOT verified: no hash was given.",
    }) then
        return
    end

    if fs.exists(SELF .. ".bak") then fs.delete(SELF .. ".bak") end
    pcall(fs.copy, SELF, SELF .. ".bak")
    local f = fs.open(SELF, "wb")
    if not f then
        showMessage("Update", { "Cannot write " .. SELF .. "." }, colors.red)
        return
    end
    f.write(body)
    f.close()

    if confirm({ "Installed version " .. newVersion .. ".", "Restart the shell now?" }) then
        S.restart = true
        S.quit = true
    end
end

-- direct: a version number to install right away, or nil to show the menu.
local function updateApp(direct)
    if not http then
        showMessage("Update", { "HTTP is disabled on this server." }, colors.red)
        return
    end

    if direct then
        installVersion(direct)
        return
    end

    showBusy("Update", "Looking for versions...")
    local versions, why = listVersions()
    if not versions then
        showMessage("Update", { "Could not find any versions.", tostring(why), "Check the update repo in Settings." }, colors.red)
        return
    end

    local cur = tonumber(VERSION)
    local newest = versions[1]
    local choice = pickMenu("Update (installed: " .. VERSION .. ")", {
        "Newest: version " .. newest .. (newest == cur and "  (installed)" or ""),
        "Choose a version...",
    })
    if choice == 1 then
        installVersion(newest)
    elseif choice == 2 then
        local labels = {}
        for i, n in ipairs(versions) do
            labels[i] = "Version " .. n .. (n == cur and "  (installed)" or "")
        end
        local pick = pickMenu("Choose a version", labels)
        if pick then installVersion(versions[pick]) end
    end
end


-- ── Settings and About ───────────────────────────────────────────────────────

local function aboutApp()
    local free = fs.getFreeSpace("")
    local lines = {
        settings.osName .. " version " .. VERSION,
        "Computer ID: " .. os.getComputerID(),
        "Label: " .. (os.getComputerLabel() or "none"),
        "Running file: " .. SELF,
        "Free space: " .. fmtSize(free),
        "History: " .. #S.history .. " commands",
        "Update repo: " .. settings.updateRepo .. " (p.shell_v<number>.lua)",
        "HTTP: " .. (http and "enabled" or "disabled"),
        "Pixelbox lite: " .. (gfx.pb and "loaded" or ("not loaded" .. (gfx.err and (" (" .. gfx.err .. ")") or ""))),
        "Monitors mirrored: " .. (gfx.nested and "handled by the host program" or tostring(#gfx.mirrors)),
    }
    if S.update then
        table.insert(lines, "Update available: version " .. S.update)
    end
    showMessage("About", lines)
end

local function settingsApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Change", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local MON_SCALES = { "Auto", "0.5", "1", "1.5", "2", "2.5", "3", "3.5", "4", "4.5", "5" }
    local HISTORY_SIZES = { "50", "100", "200", "500", "1000" }
    local SLOW_LABELS = { "Off", "1 second", "2 seconds", "5 seconds", "10 seconds" }
    local SLOW_VALUES = { 0, 1, 2, 5, 10 }

    local function yesno(v) return v and "on" or "off" end

    local function chooseColor(title, current)
        local names = {}
        for n, c in ipairs(COLOR_CHOICES) do names[n] = c.name end
        local idx = pickMenu(title, names)
        if idx then return COLOR_CHOICES[idx].name end
        return current
    end

    local function toggle(key)
        return function() settings[key] = not settings[key] end
    end

    local items = {
        { label = function() return "Shell name: " .. settings.osName end,
          act = function()
              local v = ask("Shell name", { "New shell name:" }, settings.osName)
              if v then settings.osName = v:sub(1, 20) end
          end },
        { label = function() return "Top bar color: " .. settings.barColor end,
          swatch = function() return colorValue(settings.barColor, colors.blue) end,
          act = function() settings.barColor = chooseColor("Top bar color", settings.barColor) end },
        { label = function() return "Highlight color: " .. settings.highlight end,
          swatch = function() return colorValue(settings.highlight, colors.lightBlue) end,
          act = function() settings.highlight = chooseColor("Highlight color", settings.highlight) end },
        { label = function() return "Clock: " .. settings.clock end,
          act = function()
              local modes = { "Both", "Real", "Game", "Off" }
              local idx = pickMenu("Clock", modes)
              if idx then settings.clock = modes[idx] end
          end },
        { label = function() return "Time format: " .. (settings.hour24 and "24 hour" or "12 hour") end,
          act = toggle("hour24") },
        { label = function() return "Top bar: " .. yesno(settings.headerBar) end,
          act = toggle("headerBar") },
        { label = function() return "Folder in top bar: " .. yesno(settings.titleDir) end,
          act = toggle("titleDir") },
        { label = function() return "Prompt format: " .. settings.promptFormat end,
          act = function()
              local v = ask("Prompt format", {
                  "%d folder   %p /folder   %i computer ID",
                  "%l label    %t real time %g game time",
                  "%e shows ! after a failed command, %% is a %",
              }, settings.promptFormat)
              if v then settings.promptFormat = v:sub(1, 40) end
          end },
        { label = function() return "Prompt color: " .. settings.promptColor end,
          swatch = function() return colorValue(settings.promptColor, colors.yellow) end,
          act = function() settings.promptColor = chooseColor("Prompt color", settings.promptColor) end },
        { label = function() return "Typed text color: " .. settings.textColor end,
          swatch = function() return colorValue(settings.textColor, colors.white) end,
          act = function() settings.textColor = chooseColor("Typed text color", settings.textColor) end },
        { label = function() return "Tint prompt after an error: " .. yesno(settings.failTint) end,
          act = toggle("failTint") },
        { label = function() return "Error prompt color: " .. settings.failColor end,
          swatch = function() return colorValue(settings.failColor, colors.red) end,
          act = function() settings.failColor = chooseColor("Error prompt color", settings.failColor) end },
        { label = function() return "Keep history between sessions: " .. yesno(settings.historySave) end,
          act = function()
              settings.historySave = not settings.historySave
              if not settings.historySave and fs.exists(HISTORY_FILE) then fs.delete(HISTORY_FILE) end
          end },
        { label = function() return "History size: " .. settings.historyMax end,
          act = function()
              local idx = pickMenu("History size", HISTORY_SIZES)
              if idx then settings.historyMax = tonumber(HISTORY_SIZES[idx]) end
          end },
        { label = function() return "Remove duplicate history: " .. yesno(settings.historyDedupe) end,
          act = toggle("historyDedupe") },
        { label = function()
              return "Show time of slow commands: " .. (settings.slowCmd == 0 and "off" or (settings.slowCmd .. " s"))
          end,
          act = function()
              local idx = pickMenu("Show time of slow commands", SLOW_LABELS)
              if idx then settings.slowCmd = SLOW_VALUES[idx] end
          end },
        { label = function() return "Type a folder to open it: " .. yesno(settings.autoCd) end,
          act = toggle("autoCd") },
        { label = function() return "Chain commands ; && ||: " .. yesno(settings.chaining) end,
          act = toggle("chaining") },
        { label = function() return "Check for updates at start: " .. yesno(settings.checkUpdates) end,
          act = toggle("checkUpdates") },
        { label = function() return "Update / choose version (installed " .. VERSION .. ")" end,
          act = function() updateApp() end },
        { label = function() return "Update repo: " .. settings.updateRepo end,
          act = function()
              local v = ask("Update repo", {
                  "GitHub repo as owner/name.",
                  "Add @branch for another branch.",
                  "Files must be named p.shell_v<number>.lua",
              }, settings.updateRepo)
              if v then
                  if v:match("^[%w%-%._]+/[%w%-%._]+@?[%w%-%._/]*$") then
                      settings.updateRepo = v
                  else
                      showMessage("Settings", { "That is not owner/name." }, colors.red)
                  end
              end
          end },
        { label = function() return "Logo art: " .. settings.logoArt end,
          act = function()
              local choices = { "Shell", "Base", "Custom" }
              local idx = pickMenu("Logo art", choices)
              if not idx then return end
              if choices[idx] == "Custom" and not customArt() then
                  showMessage("Logo art", {
                      "Put your art in /" .. LOGO_FILE .. " first.",
                      "A space is empty, . : + are light shades,",
                      "and any other character is solid.",
                      "The top half is gray, the bottom half takes the logo color.",
                  }, colors.yellow)
                  return
              end
              settings.logoArt = choices[idx]
              loadLogoArt()
          end },
        { label = function() return "Logo color (lower half): " .. logoName() end,
          act = function() logoStudio() end },
        { label = function()
              return "Pixel graphics: " .. (settings.graphics and (gfx.pb and "on" or "on (not loaded)") or "off")
          end,
          act = function()
              if settings.graphics then
                  settings.graphics = false
              elseif ensureGraphics() then
                  settings.graphics = true
              end
          end },
        { label = function() return "Boot animation: " .. yesno(settings.bootAnim) end,
          act = toggle("bootAnim") },
        { label = function()
              if gfx.nested then return "Monitor mirror: handled by the host program" end
              return "Monitor mirror: " .. yesno(settings.mirror) .. " (" .. #gfx.mirrors .. " found)"
          end,
          act = function()
              settings.mirror = not settings.mirror
              syncMonitors()
          end },
        { label = function() return "Monitor text scale: " .. settings.monScale end,
          act = function()
              local idx = pickMenu("Monitor text scale", MON_SCALES)
              if idx then
                  settings.monScale = MON_SCALES[idx]
                  refitMonitors()
              end
          end },
        { label = function() return "Theme: " .. (settings.theme and "Prismarine" or "Classic colors") end,
          act = function()
              settings.theme = not settings.theme
              restorePalette()
          end },
        { label = function() return "Preview boot screen" end, act = function() previewBoot() end },
        { label = function() return "Reset all settings" end,
          act = function()
              if confirm({ "Reset all settings to defaults?" }) then
                  resetSettings()
                  loadLogoArt()
                  restorePalette()
                  syncMonitors()
                  refitMonitors()
              end
          end },
    }

    local function change(n)
        local it = items[n]
        if it then it.act() end
        saveSettings()
    end

    while true do
        local entries = {}
        for n, it in ipairs(items) do
            entries[n] = { label = it.label(), swatch = it.swatch and it.swatch() or nil }
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Settings", entries, sel, top, buttons)

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            change(sel)
        elseif i.k == "q" or i.k == "backspace" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            change(sel)
        elseif i.scroll then
            sel = math.max(1, math.min(#entries, sel + i.scroll))
        end
    end
end


-- ── History ──────────────────────────────────────────────────────────────────

local function trimHistory()
    local h = S.history
    local max = settings.historyMax
    while #h > max do table.remove(h, 1) end
end

local function saveHistory()
    if not settings.historySave then return end
    if not fs.exists(DATA_DIR) then fs.makeDir(DATA_DIR) end
    local f = fs.open(HISTORY_FILE, "w")
    if f then
        for _, line in ipairs(S.history) do f.writeLine(line) end
        f.close()
    end
end

local function loadHistory()
    if S.loaded then return end
    S.loaded = true
    S.history = {}
    if settings.historySave and fs.exists(HISTORY_FILE) then
        local f = fs.open(HISTORY_FILE, "r")
        if f then
            while true do
                local l = f.readLine()
                if not l then break end
                if l ~= "" then table.insert(S.history, l) end
            end
            f.close()
        end
    end
    trimHistory()
end

local function addHistory(line)
    if line == "" then return end
    local h = S.history
    if settings.historyDedupe then
        for i = #h, 1, -1 do
            if h[i] == line then table.remove(h, i) end
        end
    elseif h[#h] == line then
        return
    end
    table.insert(h, line)
    trimHistory()
    saveHistory()
end

-- !!  last command    !5  entry number 5    !ed  newest command starting with ed
local function expandHistory(t)
    if t:sub(1, 1) ~= "!" or #t < 2 then return nil end
    local h = S.history
    if t == "!!" then
        if #h == 0 then return nil, "History is empty." end
        return h[#h]
    end
    local n = t:match("^!(%d+)$")
    if n then
        local e = h[tonumber(n)]
        if not e then return nil, "No history entry " .. n .. "." end
        return e
    end
    local pre = t:sub(2)
    for i = #h, 1, -1 do
        if h[i]:sub(1, #pre) == pre then return h[i] end
    end
    return nil, "No history entry starting with " .. pre .. "."
end

-- ── Aliases (saved between sessions) ─────────────────────────────────────────

local function saveAliases()
    if not fs.exists(DATA_DIR) then fs.makeDir(DATA_DIR) end
    local f = fs.open(ALIAS_FILE, "w")
    if f then
        f.write(textutils.serialize(S.aliases))
        f.close()
    end
end

local function rememberAlias(name)
    if S.prevAlias[name] == nil then
        S.prevAlias[name] = shell.aliases()[name] or false
    end
end

local function loadAliases()
    if not fs.exists(ALIAS_FILE) then return end
    local f = fs.open(ALIAS_FILE, "r")
    if not f then return end
    local data = textutils.unserialize(f.readAll() or "")
    f.close()
    if type(data) ~= "table" then return end
    for name, target in pairs(data) do
        if type(name) == "string" and type(target) == "string" then
            rememberAlias(name)
            shell.setAlias(name, target)
            S.aliases[name] = target
        end
    end
end

local function removeAlias(name)
    rememberAlias(name)
    shell.clearAlias(name)
    if S.aliases[name] then
        S.aliases[name] = nil
        saveAliases()
    end
end

-- Puts the parent shell's aliases back how they were.
local function restoreAliases()
    for name, prev in pairs(S.prevAlias) do
        if prev then shell.setAlias(name, prev) else shell.clearAlias(name) end
    end
end

-- ── Layout: top bar and the window programs run in ───────────────────────────

local function headerTitle()
    local t = settings.osName
    if settings.titleDir then t = t .. "  /" .. shell.dir() end
    if S.update then t = t .. "  update v" .. S.update end
    return t
end

local function drawHeader()
    if not settings.headerBar or S.paused or not L.body then return end
    local prev = term.redirect(tee)
    pcall(header, headerTitle())
    term.redirect(prev)
    local cur = term.current()
    if cur.restoreCursor then pcall(cur.restoreCursor) end
end

-- The body keeps its own copy of the palette, so it is matched to the screen.
local function syncBodyPalette()
    if not L.body then return end
    for i = 0, 15 do
        local c = 2 ^ i
        local r, g, b = tee.getPaletteColor(c)
        pcall(L.body.setPaletteColor, c, r, g, b)
    end
end

-- Sizes the body below the top bar and redraws everything.
local function applyLayout()
    local prev = term.redirect(tee)
    W, H = term.getSize()
    local top = settings.headerBar and 2 or 1
    local bh = math.max(1, H - top + 1)
    if not L.body then
        L.body = window.create(tee, 1, top, W, bh, false)
    else
        L.body.setVisible(false)
        L.body.reposition(1, top, W, bh)
    end
    term.setBackgroundColor(colors.black)
    term.clear()
    syncBodyPalette()
    L.body.setVisible(true)
    term.redirect(prev)
    hdr.key = nil
    selBar.key = nil
    S.headKey = nil
    drawHeader()
end

-- Runs a full screen menu (settings, update...) over the whole screen.
local function withUI(fn, ...)
    S.paused = true
    local prev = term.redirect(tee)
    L.body.setVisible(false)
    local ok, err = pcall(fn, ...)
    if not ok then
        logError(err)
        pcall(restorePalette)
        pcall(showMessage, "Error", { tostring(err) }, colors.red)
    end
    pcall(restorePalette)
    term.redirect(prev)
    S.paused = false
    loadLogoArt()
    applyLayout()
    resetTerm()
end

-- ── Parsing ──────────────────────────────────────────────────────────────────

-- Splits a command line into words the way the vanilla shell does.
local function tokenise(text)
    local words, cur, quoted = {}, nil, false
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == '"' then
            quoted = not quoted
            cur = cur or ""
        elseif ch == " " and not quoted then
            if cur then
                words[#words + 1] = cur
                cur = nil
            end
        else
            cur = (cur or "") .. ch
        end
    end
    if cur then words[#words + 1] = cur end
    return words
end

-- Splits at ; && || outside of double quotes. Each part has the operator that
-- follows it. The last part is always there, even if it is empty.
local function splitChain(line)
    local parts, buf, quoted = {}, {}, false
    local function flush(op)
        parts[#parts + 1] = { text = table.concat(buf), op = op }
        buf = {}
    end
    local i, n = 1, #line
    while i <= n do
        local ch = line:sub(i, i)
        local two = line:sub(i, i + 1)
        if ch == '"' then
            quoted = not quoted
            buf[#buf + 1] = ch
        elseif not quoted and ch == ";" then
            flush(";")
        elseif not quoted and (two == "&&" or two == "||") then
            flush(two)
            i = i + 1
        else
            buf[#buf + 1] = ch
        end
        i = i + 1
    end
    flush(nil)
    return parts
end

-- ── Printing helpers ─────────────────────────────────────────────────────────

local function textColor()
    return colorValue(settings.textColor, colors.white)
end

local function say(text, color)
    term.setTextColor(color or colors.lightGray)
    print(text)
    term.setTextColor(textColor())
end

local function fail(text)
    term.setTextColor(colorValue(settings.failColor, colors.red))
    print(text)
    term.setTextColor(textColor())
    return false
end

-- ── Built in commands ────────────────────────────────────────────────────────

local B = {}

B.exit = function()
    S.quit = true
    return true
end

B.cd = function(words, raw)
    local here = shell.dir()
    if #words == 1 then
        shell.setDir("")
        if here ~= "" then S.prevDir = here end
        return true
    elseif words[2] == "-" and #words == 2 then
        if not S.prevDir then return fail("No previous folder.") end
        local target = S.prevDir
        S.prevDir = here
        shell.setDir(target)
        say("/" .. target)
        return true
    end
    local ok = shell.run(raw)
    if shell.dir() ~= here then S.prevDir = here end
    return ok
end

B.alias = function(words)
    if #words == 1 then
        local list = {}
        for k, v in pairs(shell.aliases()) do list[#list + 1] = k .. ":" .. v end
        table.sort(list)
        if #list == 0 then
            say("No aliases.")
        else
            textutils.pagedPrint(table.concat(list, "\n"))
        end
        return true
    elseif #words == 2 then
        removeAlias(words[2])
        return true
    end
    local name, target = words[2], words[3]
    rememberAlias(name)
    shell.setAlias(name, target)
    S.aliases[name] = target
    saveAliases()
    say("Alias saved: " .. name .. " -> " .. target)
    return true
end

B.unalias = function(words)
    if #words < 2 then return fail("Usage: unalias <name>") end
    for i = 2, #words do removeAlias(words[i]) end
    return true
end

B.history = function(words)
    local h = S.history
    local arg = words[2]
    if arg == "clear" then
        S.history = {}
        saveHistory()
        say("History cleared.")
        return true
    elseif arg == "search" then
        local needle = table.concat(words, " ", 3):lower()
        if needle == "" then return fail("Usage: history search <text>") end
        local out = {}
        for i, line in ipairs(h) do
            if line:lower():find(needle, 1, true) then out[#out + 1] = i .. "  " .. line end
        end
        if #out == 0 then say("Nothing found.") else textutils.pagedPrint(table.concat(out, "\n")) end
        return true
    end
    local from = 1
    local count = tonumber(arg)
    if count then from = math.max(1, #h - count + 1) end
    local out = {}
    for i = from, #h do out[#out + 1] = i .. "  " .. h[i] end
    if #out == 0 then say("History is empty.") else textutils.pagedPrint(table.concat(out, "\n")) end
    return true
end

B.which = function(words)
    local name = words[2]
    if not name then return fail("Usage: which <command>") end
    local found = false
    if B[name] then
        say(name .. ": shell command", textColor())
        found = true
    end
    local target = shell.aliases()[name]
    if target then
        say(name .. ": alias for " .. target, textColor())
        found = true
    end
    local path = shell.resolveProgram(name)
    if path then
        say("/" .. path, textColor())
        found = true
    end
    if not found then return fail(name .. ": not found") end
    return true
end

B.settings = function()
    withUI(settingsApp)
    return true
end

B.about = function()
    withUI(aboutApp)
    return true
end

B.update = function(words)
    if words[2] == "check" then
        if not http then return fail("HTTP is disabled on this server.") end
        local versions, why = listVersions(true)
        if not versions then return fail(tostring(why)) end
        say("Installed: " .. VERSION .. "   Newest: " .. versions[1], textColor())
        return true
    end
    withUI(updateApp, tonumber(words[2]))
    return true
end

B.shellhelp = function()
    local lines = {
        "Everything in the normal shell still works, including Tab autocomplete.",
        "",
        "Up / Down        browse history (kept between sessions)",
        "!!  !5  !ed      run the last, the numbered or the newest matching command",
        "history          list history. history 10, history search <text>, history clear",
        "a ; b            run both.  a && b  only if a works.  a || b  only if a fails",
        "cd -  /  cd      go back to the last folder  /  go to the root",
        "<folder>         typing just a folder name opens it",
        "alias a prog     save an alias between sessions.  unalias a  removes it",
        "which <name>     show what a command runs",
        "settings         change colors, prompt, history, logo, monitors...",
        "update           pick a version.  update check  /  update <number>",
        "about            version and system info",
        "Start a line with a space to keep it out of history. exit leaves the shell.",
    }
    textutils.pagedPrint(table.concat(lines, "\n"))
    return true
end

local BUILTIN_NAMES = {}
for name in pairs(B) do BUILTIN_NAMES[#BUILTIN_NAMES + 1] = name end
table.sort(BUILTIN_NAMES)

-- ── Running commands ─────────────────────────────────────────────────────────

local function runSegment(seg)
    seg = seg:match("^%s*(.-)%s*$")
    if seg == "" then return true end
    local words = tokenise(seg)
    local name = words[1]
    if not name then return true end

    local builtin = B[name]
    if builtin then
        return builtin(words, seg) and true or false
    end

    -- Typing a folder name opens it, unless it is also a command.
    if settings.autoCd and #words == 1 and not shell.aliases()[name] and not shell.resolveProgram(name) then
        local path = shell.resolve(name)
        if fs.exists(path) and fs.isDir(path) then
            return B.cd({ "cd", name }, "cd " .. name)
        end
    end

    return shell.run(seg) and true or false
end

local function runSafe(seg)
    local ok, res = pcall(runSegment, seg)
    if ok then return res end
    local msg = tostring(res)
    if msg:find("Terminated") then
        fail("Terminated")
    else
        logError(msg)
        fail(msg)
    end
    return false
end

local function runChain(line)
    if not settings.chaining then return runSafe(line) end
    local last = true
    local pending = nil
    for _, part in ipairs(splitChain(line)) do
        if part.text:match("%S") then
            local run = true
            if pending == "&&" then run = last
            elseif pending == "||" then run = not last end
            if run then last = runSafe(part.text) end
        end
        pending = part.op
        if S.quit then break end
    end
    return last
end

local function handleLine(raw)
    local line = raw:match("^%s*(.-)%s*$")
    local expanded, err = expandHistory(line)
    if err then
        S.lastOk = fail(err)
        return
    end
    if expanded then
        say(expanded)
        line = expanded
    end
    if raw:sub(1, 1) ~= " " then addHistory(line) end

    local started = os.epoch("utc")
    S.lastOk = runChain(line)
    local elapsed = (os.epoch("utc") - started) / 1000

    if settings.slowCmd > 0 and elapsed >= settings.slowCmd and not S.quit then
        local x = term.getCursorPos()
        if x > 1 then print() end
        say(string.format("took %.1f s", elapsed))
    end

    -- Programs may have changed the palette or the folder.
    pcall(restorePalette)
    if multishell and multishell.setTitle then
        pcall(multishell.setTitle, multishell.getCurrent(), settings.osName)
    end
    drawHeader()
end

-- ── Prompt and Tab completion ────────────────────────────────────────────────

local function promptText()
    local function sub(c)
        if c == "d" then return shell.dir()
        elseif c == "p" then return "/" .. shell.dir()
        elseif c == "i" then return tostring(os.getComputerID())
        elseif c == "l" then return os.getComputerLabel() or ""
        elseif c == "t" then return settings.hour24 and os.date("%H:%M") or os.date("%I:%M %p")
        elseif c == "g" then return textutils.formatTime(os.time(), settings.hour24)
        elseif c == "e" then return (S.lastOk == false) and "!" or ""
        elseif c == "%" then return "%"
        end
        return "%" .. c
    end
    return (settings.promptFormat:gsub("%%(.)", sub))
end

local function drawPrompt()
    local x = term.getCursorPos()
    if x > 1 then print() end
    local failed = (S.lastOk == false) and settings.failTint
    term.setBackgroundColor(colors.black)
    if failed then
        term.setTextColor(colorValue(settings.failColor, colors.red))
    else
        term.setTextColor(colorValue(settings.promptColor, colors.yellow))
    end
    write(promptText())
    term.setTextColor(textColor())
end

-- The vanilla completions, applied to the command after the last ; && ||, plus
-- the commands this shell adds.
local function completer(line)
    local seg = line
    if settings.chaining then
        local parts = splitChain(line)
        seg = parts[#parts].text
    end
    seg = seg:gsub("^%s+", "")
    local ok, res = pcall(shell.complete, seg)
    local out = {}
    if ok and type(res) == "table" then
        for _, v in ipairs(res) do out[#out + 1] = v end
    end
    if seg ~= "" and not seg:find(" ", 1, true) then
        for _, name in ipairs(BUILTIN_NAMES) do
            if #name > #seg and name:sub(1, #seg) == seg then
                out[#out + 1] = name:sub(#seg + 1) .. " "
            end
        end
    elseif seg == "history " then
        out[#out + 1] = "search "
        out[#out + 1] = "clear"
    elseif seg == "update " then
        out[#out + 1] = "check"
    end
    return out
end

local function repl()
    while not S.quit do
        drawPrompt()
        local ok, line = pcall(read, nil, S.history, completer)
        if not ok then
            -- Ctrl+T at the prompt cancels the line.
            print()
            local msg = tostring(line)
            if not msg:find("Terminated") then logError(msg) end
        elseif line and line:match("%S") then
            handleLine(line)
        end
    end
end

-- ── Top bar clock and the background update check ────────────────────────────

local function startUpdateCheck()
    if not settings.checkUpdates or not http then return end
    local url = listUrl()
    if pcall(http.request, url) then S.checkUrl = url end
end

local function finishUpdateCheck(handle)
    local body = handle.readAll()
    handle.close()
    local found = versionsFromJson(body)
    local cur = tonumber(VERSION) or 0
    if found[1] and found[1] > cur then
        S.update = found[1]
        S.headKey = nil
    end
end

local function ticker()
    local timer = os.startTimer(1)
    while true do
        local ev, a, b = os.pullEventRaw()
        if ev == "timer" and a == timer then
            timer = os.startTimer(1)
            if not S.paused then
                local key = clockText() .. "|" .. shell.dir() .. "|" .. tostring(S.update)
                if key ~= S.headKey then
                    S.headKey = key
                    drawHeader()
                end
            end
        elseif ev == "term_resize" then
            if not S.paused then
                pcall(gfx.nativeResized)
                pcall(applyLayout)
            end
        elseif ev == "http_success" and S.checkUrl and a == S.checkUrl then
            S.checkUrl = nil
            pcall(finishUpdateCheck, b)
        elseif ev == "http_failure" and S.checkUrl and a == S.checkUrl then
            S.checkUrl = nil
        end
    end
end

-- ── Start up ─────────────────────────────────────────────────────────────────

local function runBoot()
    local ready = loadGraphics()
    local sc = nil
    if ready and settings.bootAnim then sc = boot.start(false) end

    if sc then
        local ok, err = pcall(function()
            boot.stage(sc, "Loading history", 0.35, function() loadHistory() end)
            boot.stage(sc, "Restoring aliases", 0.65, function() loadAliases() end)
            boot.stage(sc, "Preparing prompt", 0.90, function() startUpdateCheck() end)
            boot.stage(sc, "Starting shell", 1.00)
            boot.finish(sc)
        end)
        if not ok then
            boot.abort()
            logError("boot screen failed: " .. tostring(err))
        end
    end

    -- Anything the boot screen did not get to (or no boot screen at all).
    loadHistory()
    if next(S.aliases) == nil then pcall(loadAliases) end
    if not S.checkUrl and not S.update then pcall(startUpdateCheck) end
end

local function main()
    applyLayout()
    term.redirect(L.body)
    resetTerm()
    term.clear()
    term.setCursorPos(1, 1)
    say(settings.osName .. " v" .. VERSION, colorValue(settings.promptColor, colors.yellow))
    say("Type shellhelp to see what is new. exit leaves the shell.")
    parallel.waitForAny(repl, ticker)
end

local displayOk, displayErr = pcall(gfx.init)
if not displayOk then logError("display setup failed: " .. tostring(displayErr)) end
pcall(restorePalette)

local bootOk, bootErr = pcall(runBoot)
if not bootOk then
    pcall(boot.abort)
    logError("boot failed: " .. tostring(bootErr))
    pcall(loadHistory)
    pcall(loadAliases)
end

local crashes = 0
while not S.quit do
    local ok, err = pcall(main)
    if ok then break end
    logError(err)
    crashes = crashes + 1
    pcall(restorePalette)
    pcall(function()
        term.redirect(tee)
        resetTerm()
        showMessage(settings.osName .. " error", { tostring(err), "", "Saved to " .. LOG_FILE }, colors.red)
    end)
    if crashes >= 5 then break end
end

-- Leave the terminal the way it was found.
pcall(saveHistory)
pcall(restoreAliases)
pcall(gfx.shutdown)
pcall(function()
    resetTerm()
    term.clear()
    term.setCursorPos(1, 1)
end)

if S.restart then
    shell.run(SELF)
end
