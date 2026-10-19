-- REMINDER (local-variable limit fix):
-- CC:Tweaked rejected this file with "function at line N has more than 200
-- local variables". Its Lua engine seems to count the top-level locals against
-- every function, so the top-level count has to stay well below 200.
-- To save slots, the UPPERCASE constants now live in the table C (C.PROTO,
-- C.CHUNK, C.APPS, ...) instead of being separate locals.
-- When adding new constants, put them in C. If the error comes back, move more
-- helpers into tables. buildLogo keeps its own local SRC/LOGO_W/LOGO_R/
-- LOGO_SPLIT on purpose.
--                ▐■                                      ▐■
--                ▀                                       ▀
-- ▀▄▓▓▓▄  ▄ ▄▓▄  ▄▒    ▄▓▓▄  ▄  ▄▓▄ ▄▓▄   ▄▓▓▄ █▄ ▄ ▄▓▄  ▄▒   ▄  ▄▓▄   ▄▓▓▄
-- ░▒▀ ▀▒░  ░▒  ▀ ▒░   ░▒  ▀▀  ▓▒▀ ▓█▀ ▓█ ░▒▀  ▀▒░  ░▒  ▀ ▒░    ▓▒▀ ▓█ ░▒  ▒█
-- ▄▄   ▄▄  ▀▄    ▄▀     ▀▀░▄  ▀░  ▀▀  ▀▀ ▄▄    ▄▀  ▀▄    ▄▀    ▀░  ▀▀ ▄▄ ▀▀
-- ▓░▒▄▒░▀  ▒░▄   ░▒ ▄  ░▄ ▄▓  ▒▄  ▒▓  ▒▓ ▀░▒▄ ▄░▒  ▒░▄   ░▒ ▄  ▒▄  ▒▓ ▀░▒▄ ▄
-- ▓▒▀▀▀▀  ▀▀  ▀   ▀▀    ▀▀▀▀ ▀ ▀  ▀▀  ▀▀   ▀▀▀  ▀ ▀▀  ▀   ▀▀  ▀ ▀  ▀▀   ▀▀▀
-- ░▒
-- ▀█
--
-- Prismarine OS for CC:Tweaked 1.20.1. Pixelbox_Lite draws the interface and the
-- loading screens. Without it the plain text interface is used.
-- Save this file as /startup.lua on the computer.
-- Every action has a clickable button and a keyboard shortcut.
-- Errors are shown on screen and saved to /simpleos_error.log.

local W, H = term.getSize()

local C = {}   -- constants live here to save local-variable slots
C.PROTO = "simpleos_msg"
C.FILE_PROTO = "simpleos_file"  -- Messenger file transfer
C.PRIV_PROTO = "simpleos_private"  -- sealed private messages (broadcast)
C.AUDIT_PROTO = "simpleos_audit"   -- sealed activity reports for the Archive (broadcast)
C.CHUNK = 8192               -- bytes per transfer packet
C.MAX_FILE = 1000000         -- largest file the Messenger will send
C.NAME_FILE = ".simpleos_name"
C.LOG_FILE = "simpleos_error.log"

local VERSION = "21"
local SELF = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "startup.lua"
if not SELF or SELF == "" then SELF = "startup.lua" end

-- ── Settings ─────────────────────────────────────────────────────────────────

C.SETTINGS_FILE = ".simpleos_settings"
C.SECURE_FILE = ".simpleos_secureboot"

C.COLOR_CHOICES = {
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

C.LIGHT = {}
for _, c in ipairs({ colors.white, colors.lightGray, colors.yellow, colors.lime,
                     colors.pink, colors.lightBlue, colors.cyan, colors.orange }) do
    C.LIGHT[c] = true
end

local function colorValue(name, fallback)
    for _, c in ipairs(C.COLOR_CHOICES) do
        if c.name == name then return c.value end
    end
    return fallback
end

-- Picks black or white text for a background color.
local function textOn(bg)
    return C.LIGHT[bg] and colors.black or colors.white
end

C.DEFAULT_SETTINGS = {
    osName    = "Prismarine",
    barColor  = "Blue",
    highlight = "Light blue",
    clock     = "Both",
    hour24    = true,
    showRom   = false,
    updateRepo = "FilesCodes-ui/prismarine-os",  -- owner/name, or owner/name@branch
    logoColor = "Blue",   -- lower half of the logo: preset name or #RRGGBB
    uiEngine  = "Pixelbox_Lite",  -- the only engine. Old saved values (Basalt) reset to it.
    graphics  = true,     -- Pixelbox_Lite interface (header, bars, logo).
    audit     = true,     -- report activity (commands, apps, files, errors) to the Archive
    netKey    = "",       -- key made from the network passphrase (private messages), "" is not set
    bootAnim  = true,
    menuLogo  = "Off",    -- Off, Corner (animated wordmark) or Large
    monMode   = "Mirror", -- Mirror, Dashboard (logo and clock) or Off
    monScale  = "Auto",   -- Auto, Pixel (0.5, advanced monitors) or 0.5 to 5
    theme     = "Prismarine",  -- Prismarine, Midnight, Sunset, Forest, Mono, Classic
    transitions = true,   -- fade between the menu and apps
    saver     = 5,        -- idle minutes before the screen saver, 0 is off
    importDir = "",       -- Import app folder, "" is the main folder (no folder)
    importHost = "localhost:8000",
    importOverwrite = "Ask",  -- Ask, Replace or Rename
    importClean = true,
    importKeep = false,
    importVerify = false,
    importChunk = 2,      -- MB per HTTP step in Downloads
}

local settings = {}

local function resetSettings()
    settings = {}
    for k, v in pairs(C.DEFAULT_SETTINGS) do settings[k] = v end
end

local function saveSettings()
    local f = fs.open(C.SETTINGS_FILE, "w")
    if f then
        f.write(textutils.serialize(settings))
        f.close()
    end
end

local function loadSettings()
    resetSettings()
    if fs.exists(C.SETTINGS_FILE) then
        local f = fs.open(C.SETTINGS_FILE, "r")
        if f then
            local data = textutils.unserialize(f.readAll() or "")
            f.close()
            if type(data) == "table" then
                for k, v in pairs(data) do
                    if C.DEFAULT_SETTINGS[k] ~= nil and type(v) == type(C.DEFAULT_SETTINGS[k]) then
                        settings[k] = v
                    end
                end
                -- Settings from older versions.
                if data.theme == false then settings.theme = "Classic" end
                if data.mirror == false and data.monMode == nil then settings.monMode = "Off" end
            end
        end
    end
end

loadSettings()

-- Keeps the string settings to values this version knows. Anything else (an
-- old or hand edited settings file) goes back to the default.
do
    local function oneOf(key, list)
        for _, v in ipairs(list) do
            if settings[key] == v then return end
        end
        settings[key] = C.DEFAULT_SETTINGS[key]
    end
    oneOf("menuLogo", { "Off", "Corner", "Large" })
    oneOf("monMode", { "Mirror", "Dashboard", "Off" })
    oneOf("importOverwrite", { "Ask", "Replace", "Rename" })
    -- Basalt was removed from the OS. A saved "Basalt" (or an empty value) goes
    -- back to Pixelbox_Lite and is saved that way.
    if settings.uiEngine ~= "Pixelbox_Lite" then
        settings.uiEngine = "Pixelbox_Lite"
        saveSettings()
    end
    settings.graphics = true
    if #settings.netKey ~= 64 or settings.netKey:find("%X") then settings.netKey = "" end
    if settings.monScale ~= "Auto" and settings.monScale ~= "Pixel"
        and not tonumber(settings.monScale) then
        settings.monScale = C.DEFAULT_SETTINGS.monScale
    end
end

-- The GitHub account was renamed. Move a saved update repo to the new name.
do
    local old = "filesoriginuknown-ui"
    local repo = settings.updateRepo
    if repo:sub(1, #old):lower() == old and repo:sub(#old + 1, #old + 1) == "/" then
        settings.updateRepo = "FilesCodes-ui" .. repo:sub(#old + 1)
        saveSettings()
    end
end

local showRom = settings.showRom

-- ── Hashing and secure boot data ─────────────────────────────────────────────

C.SHA_K = { 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 }
C.SHA_H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

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
-- Pass false as tick to never yield (short inputs only, used by private messages).
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
    for n = 1, 8 do h[n] = C.SHA_H0[n] end
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
            local t1 = (hh + S1 + ch + C.SHA_K[j] + w[j]) % M
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
        if tick ~= false and blocks % 8 == 0 then
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

local function loadSecure()
    if not fs.exists(C.SECURE_FILE) then return nil end
    local text = readFile(C.SECURE_FILE)
    local data = text and textutils.unserialize(text)
    if type(data) == "table" and data.fileHash and data.salt and data.passHash then
        return data
    end
    return nil
end

local function saveSecure(data)
    local f = fs.open(C.SECURE_FILE, "w")
    if f then
        f.write(textutils.serialize(data))
        f.close()
    end
end

local function newSalt()
    local s = ""
    for _ = 1, 16 do s = s .. string.format("%x", math.random(0, 15)) end
    return s .. tostring(os.epoch("utc"))
end

local function passwordMatches(data, pw)
    return sha256(data.salt .. pw) == data.passHash
end

-- ── Display layer, palette and Pixelbox graphics ─────────────────────────────
-- Everything the OS draws goes through one buffered window (gfx.win). That
-- window is copied to every attached monitor, and monitor touches come back
-- in as mouse clicks. Pixelbox_Lite (downloaded on first boot) draws every
-- loading screen, the header fade, the selection bars and the logo.
-- If it is missing, the plain text UI is used and nothing else changes.

local gfx = {
    pb      = nil,   -- the Pixelbox_Lite module once loaded
    err     = nil,   -- why it is not loaded
    native  = nil,   -- the real computer terminal
    win     = nil,   -- buffered window the OS draws into
    mirrors = {},    -- { name, mon, win, ox, oy }
    dashes  = {},    -- monitors showing the dashboard
    dashTimer = nil,
    ready   = false,
    beat    = nil,   -- heartbeat timer id (see gfx.init)
    beatAt  = 0,
    beatOn  = true,  -- false while a plain shell program has the screen
}

C.PB_DIR  = ".prismarine"
C.PB_FILE = C.PB_DIR .. "/pixelbox_lite.lua"
-- Pinned to one commit and checked against a SHA-256, so the file that runs at
-- boot is exactly the one this OS was written for.
C.PB_URL  = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/82098c8dca939b7689f119d0a577c311d4a09281/pixelbox_lite.lua"
C.PB_HASH = "e9923dc24ed6d968de668f42a3c324d0957778a709d93bc9190617c32889de99"

-- Basalt was removed in version 20. A copy that an older version downloaded is deleted.
pcall(fs.delete, C.PB_DIR .. "/basalt.lua")

local function nowSec() return os.epoch("utc") / 1000 end

-- ── Monitor mirroring ────────────────────────────────────────────────────────

C.TEE_ALL = { "write", "blit", "clear", "clearLine", "scroll", "setCursorPos",
    "setCursorBlink", "setTextColor", "setTextColour", "setBackgroundColor",
    "setBackgroundColour", "setPaletteColor", "setPaletteColour" }
C.TEE_ONE = { "getCursorPos", "getCursorBlink", "getSize", "isColor", "isColour",
    "getTextColor", "getTextColour", "getBackgroundColor", "getBackgroundColour",
    "getPaletteColor", "getPaletteColour" }

-- A terminal object that sends every call to the main window and to each
-- mirrored monitor. Answers to questions come from the main window.
local tee = {}
for _, name in ipairs(C.TEE_ONE) do
    tee[name] = function(...) return gfx.win[name](...) end
end
for _, name in ipairs(C.TEE_ALL) do
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

C.SCALES = { 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5 }

-- Picks the biggest text scale where the whole screen still fits.
local function chooseScale(mon)
    local want = tonumber(settings.monScale)
    if want then
        pcall(mon.setTextScale, want)
        return
    end
    -- Pixel: the smallest text scale, so an Advanced Monitor gives Pixelbox its
    -- full pixel resolution. A plain monitor cannot show it and uses Auto.
    if settings.monScale == "Pixel" then
        local advanced = false
        pcall(function() advanced = mon.isColor() end)
        if advanced then
            pcall(mon.setTextScale, 0.5)
            return
        end
    end
    for _, s in ipairs(C.SCALES) do
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
    local mode = settings.monMode
    if mode == "Dashboard" and not gfx.pb then mode = "Mirror" end
    local wantMirror, wantDash = {}, {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            if mode == "Mirror" then wantMirror[name] = true
            elseif mode == "Dashboard" then wantDash[name] = true end
        end
    end

    -- Remove what is no longer wanted first. A monitor that changes from the
    -- dashboard to a mirror is cleaned up before the mirror draws on it.
    for i = #gfx.dashes, 1, -1 do
        local d = gfx.dashes[i]
        if wantDash[d.name] then
            wantDash[d.name] = nil
        else
            table.remove(gfx.dashes, i)
            pcall(function()
                for n = 0, 15 do
                    local c = 2 ^ n
                    d.mon.setPaletteColor(c, term.nativePaletteColor(c))
                end
                d.mon.setBackgroundColor(colors.black)
                d.mon.clear()
            end)
        end
    end
    for i = #gfx.mirrors, 1, -1 do
        local m = gfx.mirrors[i]
        if wantMirror[m.name] then
            wantMirror[m.name] = nil
        else
            table.remove(gfx.mirrors, i)
            pcall(function()
                m.mon.setBackgroundColor(colors.black)
                m.mon.clear()
            end)
        end
    end

    for name in pairs(wantMirror) do
        local mon = peripheral.wrap(name)
        if mon then
            chooseScale(mon)
            local m = { name = name, mon = mon }
            placeMirror(m)
            table.insert(gfx.mirrors, m)
        end
    end
    for name in pairs(wantDash) do
        local mon = peripheral.wrap(name)
        if mon then
            local d = { name = name, mon = mon }
            if pcall(gfx.dashSetup, d) then table.insert(gfx.dashes, d) end
        end
    end
    if #gfx.dashes > 0 and not gfx.dashTimer then
        gfx.dashLast = nowSec()
        gfx.dashTimer = os.startTimer(0.25)
    end
end

-- Used when the monitor scale setting changes.
function gfx.refitAll()
    for _, m in ipairs(gfx.mirrors) do
        chooseScale(m.mon)
        pcall(placeMirror, m)
    end
    for _, d in ipairs(gfx.dashes) do
        pcall(gfx.dashSetup, d)
    end
end

function gfx.nativeResized()
    local nw, nh = gfx.native.getSize()
    gfx.win.reposition(1, 1, nw, nh)
    W, H = nw, nh
    for _, m in ipairs(gfx.mirrors) do pcall(placeMirror, m) end
end

-- Turns the OS output into the buffered, mirrored terminal. Safe to call once.
function gfx.init()
    if gfx.ready then return end
    gfx.native = term.current()
    local nw, nh = gfx.native.getSize()
    gfx.win = window.create(gfx.native, 1, 1, nw, nh, true)
    term.redirect(tee)
    gfx.ready = true
    W, H = term.getSize()

    -- Every program (and read) gets events through os.pullEventRaw. Wrapping
    -- it once lets monitor touches arrive as mouse clicks everywhere, and keeps
    -- the mirrors in step when a monitor is attached, removed or resized.
    --
    -- It also runs a heartbeat. A timer that a screen starts for itself can be
    -- eaten by any other code that waits for "timer" events (fades, animations,
    -- sleep), and then the clock stops until a key is pressed. The heartbeat
    -- is restarted here, before anything else sees the event, so it cannot be
    -- lost. It reaches callers as a "prismarine_tick" event, and only callers
    -- that ask for any event (no filter) see it.
    local rawPull = os.pullEventRaw
    local BEAT = 0.5
    gfx.beat, gfx.beatAt = os.startTimer(BEAT), nowSec()
    os.pullEventRaw = function(filter)
        while true do
            local ev = table.pack(rawPull())
            local name = ev[1]
            local drop = false
            if name == "timer" and ev[2] == gfx.beat then
                gfx.beat, gfx.beatAt = os.startTimer(BEAT), nowSec()
                if gfx.beatOn then
                    ev = table.pack("prismarine_tick", gfx.beatAt)
                    name = ev[1]
                else
                    drop = true
                end
            elseif nowSec() - gfx.beatAt > 2 then
                -- The heartbeat timer was lost anyway. Start it again.
                gfx.beat, gfx.beatAt = os.startTimer(BEAT), nowSec()
            end
            -- If the dashboard timer was swallowed by a program that does not
            -- use this function, any event starts it again.
            if #gfx.dashes > 0 and nowSec() - (gfx.dashLast or 0) > 1.5 then
                gfx.dashLast = nowSec()
                gfx.dashTimer = os.startTimer(0.25)
            end
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
            elseif name == "timer" and gfx.dashTimer and ev[2] == gfx.dashTimer then
                -- The dashboard has its own clock. Its timer never reaches programs.
                drop = true
                gfx.dashTimer = nil
                if gfx.dashTick then pcall(gfx.dashTick) end
                if #gfx.dashes > 0 then gfx.dashTimer = os.startTimer(0.25) end
            elseif name == "monitor_resize" then
                for _, m in ipairs(gfx.mirrors) do
                    if m.name == ev[2] then pcall(placeMirror, m) end
                end
                for _, d in ipairs(gfx.dashes) do
                    if d.name == ev[2] then pcall(gfx.dashSetup, d) end
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
C.LOGO_COLORS = {
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
    for i, c in ipairs(C.LOGO_COLORS) do
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
    return parseHex(settings.logoColor) or C.LOGO_COLORS[1].rgb
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

-- Screen transitions dim every palette color by this factor (1 is normal).
local dimLevel = 1

local function setPal(c, rgb, f)
    f = (f or 1) * dimLevel
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

local function nativePalette(dimmed)
    local k = dimmed and dimLevel or 1
    for i = 0, 15 do
        local c = 2 ^ i
        local r, g, b = term.nativePaletteColor(c)
        term.setPaletteColor(c, r * k, g * k, b * k)
    end
end

-- Puts the normal OS colors back (also undoes boot screen and menu logo shades).
local function restorePalette()
    local t = gfx.themeByName(settings.theme)
    if t.pal then
        for c, rgb in pairs(t.pal) do setPal(c, rgb) end
    else
        nativePalette(true)
    end
end

-- Themes. Every theme gives all 16 slots a shade of their usual hue, so cyan
-- stays cyan, and suggests a bar color, highlight and logo color to match.
-- Classic has no palette and leaves the stock colors.
do
    local order = { colors.black, colors.gray, colors.lightGray, colors.white,
        colors.blue, colors.lightBlue, colors.cyan, colors.green, colors.lime,
        colors.yellow, colors.orange, colors.red, colors.pink, colors.magenta,
        colors.purple, colors.brown }
    local function pal16(list)
        local out = {}
        for i, c in ipairs(order) do out[c] = list[i] end
        return out
    end

    gfx.themes = {
        { name = "Prismarine", bar = "Blue", hl = "Light blue", logo = "Blue", pal = pal16({
            { 9, 12, 20 }, { 34, 41, 56 }, { 146, 158, 176 }, { 236, 241, 248 },
            { 52, 104, 236 }, { 116, 170, 255 }, { 64, 196, 214 }, { 44, 160, 96 },
            { 132, 222, 92 }, { 246, 206, 84 }, { 250, 152, 52 }, { 240, 82, 92 },
            { 246, 142, 192 }, { 208, 84, 222 }, { 144, 96, 232 }, { 150, 100, 62 } }) },
        { name = "Midnight", bar = "Purple", hl = "Light blue", logo = "Violet", pal = pal16({
            { 6, 7, 18 }, { 26, 28, 58 }, { 132, 138, 190 }, { 228, 230, 255 },
            { 86, 76, 240 }, { 150, 140, 255 }, { 96, 180, 255 }, { 52, 170, 140 },
            { 140, 230, 150 }, { 255, 214, 110 }, { 255, 160, 90 }, { 255, 92, 120 },
            { 255, 150, 210 }, { 220, 90, 240 }, { 160, 110, 255 }, { 140, 100, 130 } }) },
        { name = "Sunset", bar = "Orange", hl = "Yellow", logo = "Orange", pal = pal16({
            { 20, 10, 14 }, { 54, 30, 38 }, { 196, 156, 146 }, { 255, 240, 228 },
            { 235, 100, 110 }, { 255, 160, 130 }, { 255, 190, 140 }, { 150, 190, 90 },
            { 190, 230, 100 }, { 255, 210, 90 }, { 255, 138, 50 }, { 255, 70, 80 },
            { 255, 130, 170 }, { 225, 70, 150 }, { 170, 80, 190 }, { 190, 110, 70 } }) },
        { name = "Forest", bar = "Green", hl = "Lime", logo = "Emerald", pal = pal16({
            { 7, 14, 10 }, { 24, 44, 34 }, { 148, 176, 156 }, { 232, 246, 236 },
            { 40, 150, 130 }, { 110, 210, 180 }, { 90, 215, 170 }, { 46, 170, 90 },
            { 150, 230, 90 }, { 238, 214, 100 }, { 240, 160, 70 }, { 232, 86, 80 },
            { 238, 150, 170 }, { 200, 100, 190 }, { 130, 110, 200 }, { 150, 106, 64 } }) },
        { name = "Mono", bar = "Blue", hl = "Light blue", logo = "Ice", pal = pal16({
            { 10, 10, 10 }, { 40, 40, 40 }, { 150, 150, 150 }, { 240, 240, 240 },
            { 118, 118, 118 }, { 205, 205, 205 }, { 172, 172, 172 }, { 132, 132, 132 },
            { 110, 220, 110 }, { 245, 215, 90 }, { 245, 160, 70 }, { 235, 80, 80 },
            { 190, 190, 190 }, { 150, 150, 150 }, { 100, 100, 100 }, { 80, 80, 80 } }) },
        { name = "Classic", bar = "Blue", hl = "Light blue", logo = "Blue" },
    }

    function gfx.themeByName(name)
        for _, t in ipairs(gfx.themes) do
            if t.name == name then return t end
        end
        return gfx.themes[1]
    end

    -- A saved theme name this version does not know goes back to the first.
    if gfx.themeByName(settings.theme).name ~= settings.theme then
        settings.theme = gfx.themes[1].name
    end

    -- Switches to a theme and takes over its bar, highlight and logo colors.
    function gfx.applyTheme(name)
        local t = gfx.themeByName(name)
        settings.theme = t.name
        settings.barColor = t.bar
        settings.highlight = t.hl
        settings.logoColor = t.logo
        restorePalette()
    end

    local function sleepTick(sec)
        local timer = os.startTimer(sec)
        repeat
            local ev, id = os.pullEventRaw("timer")
        until ev == "timer" and id == timer
    end

    -- Moves the screen brightness from one level to another. redraw puts the
    -- palette back at the current level.
    function gfx.fade(from, to, redraw)
        for i = 1, 6 do
            dimLevel = from + (to - from) * i / 6
            pcall(redraw)
            sleepTick(0.02)
        end
        dimLevel = to
        pcall(redraw)
    end

    function gfx.setDim(v) dimLevel = v end

    -- An app that opens from a black screen calls this once it has drawn.
    function gfx.reveal()
        if dimLevel < 1 then gfx.fade(dimLevel, 1, restorePalette) end
    end
end

-- ── Pixelbox_Lite ────────────────────────────────────────────────────────────

-- Loads the downloaded library after checking its SHA-256.
function gfx.loadPixelbox(tick)
    if gfx.pb then return true end
    if not fs.exists(C.PB_FILE) then
        gfx.err = "not downloaded"
        return false
    end
    local text = readFile(C.PB_FILE)
    if not text or sha256(text, tick) ~= C.PB_HASH then
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

-- Downloads Pixelbox_Lite. Returns true, or false and a reason.
function gfx.download()
    if not http then return false, "HTTP is disabled on this server" end
    local resp, err = http.get(C.PB_URL, nil, true)
    if not resp then return false, tostring(err) end
    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()
    if status ~= 200 or not body or body == "" then
        return false, "Status " .. tostring(status)
    end
    if sha256(body) ~= C.PB_HASH then
        return false, "Checksum mismatch, file not saved"
    end
    if not fs.exists(C.PB_DIR) then fs.makeDir(C.PB_DIR) end
    local f = fs.open(C.PB_FILE, "wb")
    if not f then return false, "Cannot write " .. C.PB_FILE end
    f.write(body)
    f.close()
    return true
end

-- 4x4 ordered dither threshold in (0, 1).
C.BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local function thr(x, y)
    return (C.BAYER[(y - 1) % 4 + 1][(x - 1) % 4 + 1] + 0.5) / 16
end

-- ---------------------------------------------------------------------------
-- Pixel shape toolkit. It sits on top of Pixelbox_Lite without changing the
-- downloaded file, so the pinned SHA-256 still matches. A surface is a cached
-- window + Pixelbox canvas. Pixels are 2x3 per terminal cell, and a cell can
-- only show two colors, so shapes keep to two colors per cell where they can.
-- ---------------------------------------------------------------------------
gfx.px = { surf = {} }

-- Cached surface for slot at cell x, y with size w x h cells, or nil.
function gfx.px.surface(slot, x, y, w, h)
    if not gfx.pb or not settings.graphics or w < 1 or h < 1 then return nil end
    local s = gfx.px.surf[slot]
    if not s or s.w ~= w or s.h ~= h then
        local ok, res = pcall(function()
            local win = window.create(term.current(), x, y, w, h, true)
            return { win = win, box = gfx.pb.new(win, colors.black), w = w, h = h }
        end)
        if not ok then
            gfx.px.surf[slot] = nil
            return nil
        end
        s = res
        gfx.px.surf[slot] = s
    end
    if not pcall(s.win.reposition, x, y) then
        gfx.px.surf[slot] = nil
        return nil
    end
    return s
end

function gfx.px.fill(s, color)
    local canvas = s.box.canvas
    for py = 1, s.h * 3 do
        local row = canvas[py]
        for px = 1, s.w * 2 do row[px] = color end
    end
end

-- Is pixel x, y inside the rectangle x1..x2, y1..y2 with corner radius r?
function gfx.px.inside(x, y, x1, y1, x2, y2, r)
    if x < x1 or x > x2 or y < y1 or y > y2 then return false end
    if r <= 0 then return true end
    local cx = (x < x1 + r) and (x1 + r) or ((x > x2 - r) and (x2 - r) or x)
    local cy = (y < y1 + r) and (y1 + r) or ((y > y2 - r) and (y2 - r) or y)
    local dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r + r * 0.5
end

-- Fills a rounded rectangle. paint is a color or a function(x, y) -> color.
function gfx.px.round(s, x1, y1, x2, y2, r, paint)
    local canvas = s.box.canvas
    for y = math.max(1, y1), math.min(s.h * 3, y2) do
        local row = canvas[y]
        for x = math.max(1, x1), math.min(s.w * 2, x2) do
            if gfx.px.inside(x, y, x1, y1, x2, y2, r) then
                if type(paint) == "function" then row[x] = paint(x, y) else row[x] = paint end
            end
        end
    end
end

-- A three pixel tall pill on cell row `row` (1-based) between pixel columns
-- x1 and x2. The outer corner pixels of a rounded end are left out.
function gfx.px.pill(s, row, x1, x2, color, left, right)
    local canvas = s.box.canvas
    local y0 = (row - 1) * 3
    for px = math.max(1, x1), math.min(s.w * 2, x2) do
        for k = 1, 3 do
            local skip = (k ~= 2) and ((left and px == x1) or (right and px == x2))
            if not skip then canvas[y0 + k][px] = color end
        end
    end
end

-- A tapered, dithered tail from pixel column x0 to x1 on cell row `row`. Each
-- cell blends only two colors, and the top and bottom pixel rows fade sooner
-- than the middle one.
function gfx.px.tail(s, row, x0, x1, color, mid)
    local canvas = s.box.canvas
    local y0 = (row - 1) * 3
    local span = math.max(1, x1 - x0)
    for px = math.max(1, x0), math.min(s.w * 2, x1) do
        local cell = math.floor((px - 1) / 2)
        local t = math.min(1, math.max(0, (cell * 2 + 1.5 - x0) / span)) * 0.9
        local a, b, f
        if t < 0.5 then
            a, b, f = color, mid, t * 2
        else
            a, b, f = mid, colors.black, (t - 0.5) * 2
        end
        for k = 1, 3 do
            local fk = (k == 2) and f or math.min(1, f + 0.3)
            canvas[y0 + k][px] = (fk > thr(px, y0 + k)) and b or a
        end
    end
end

-- A rounded panel with an accent stripe on its left, covering w x h cells at
-- cell x, y. The caller writes the text on top, starting at the third cell.
function gfx.px.card(x, y, w, h, stripe, body)
    local s = gfx.px.surface("card", x, y, w, h)
    if not s then return false end
    local ok = pcall(function()
        gfx.px.fill(s, colors.black)
        local pw, ph = w * 2, h * 3
        local r = (ph >= 12) and 4 or 3
        gfx.px.round(s, 1, 1, pw, ph, r, function(px)
            return (px <= 4) and stripe or body
        end)
    end)
    return ok and (pcall(s.box.render, s.box))
end

-- Header: a rounded title pill, a one cell gap, then a tapered dithered tail.
-- The caller writes the title (from the second cell) on top afterwards.
function gfx.header(title, bar)
    if bar == colors.black then return false end
    local solid = math.min(W, #title + 3)
    if solid >= W - 4 then return false end
    local s = gfx.px.surface("hdr", 1, 1, W, 1)
    if not s then return false end
    local key = W .. ":" .. bar .. ":" .. solid
    if s.key ~= key then
        local ok = pcall(function()
            local mid = (bar == colors.gray) and colors.lightGray or colors.gray
            gfx.px.fill(s, colors.black)
            gfx.px.pill(s, 1, 1, solid * 2, bar, true, true)
            gfx.px.tail(s, 1, solid * 2 + 3, math.min(W * 2, solid * 2 + 44), bar, mid)
        end)
        if not ok then return false end
        s.key = key
    end
    return (pcall(s.box.render, s.box))
end

-- Highlight for the selected list row: a rounded pill behind the text, a one
-- cell gap, then a tapered tail. The caller writes the label from the second
-- cell on top afterwards.
function gfx.selectBar(row, solid, color)
    if color == colors.black or solid >= W - 4 then return false end
    local s = gfx.px.surface("sel", 1, row, W, 1)
    if not s then return false end
    local key = color .. ":" .. solid
    if s.key ~= key then
        local ok = pcall(function()
            local mid = (color == colors.gray) and colors.black or colors.gray
            gfx.px.fill(s, colors.black)
            gfx.px.pill(s, 1, 1, solid * 2, color, true, true)
            gfx.px.tail(s, 1, solid * 2 + 3, math.min(W * 2, solid * 2 + 44), color, mid)
        end)
        if not ok then return false end
        s.key = key
    end
    return (pcall(s.box.render, s.box))
end

-- Footer buttons as rounded pills on the gray bar. layout is a list of
-- { x, tag, total } with the tag length in cells (0 for none).
function gfx.px.footer(layout, accent)
    local s = gfx.px.surface("foot", 1, H, W, 1)
    if not s then return false end
    local ok = pcall(function()
        gfx.px.fill(s, colors.gray)
        for _, b in ipairs(layout) do
            local x1, x2 = (b.x - 1) * 2 + 1, (b.x + b.total - 1) * 2
            if b.tag > 0 then
                local seam = (b.x + b.tag - 1) * 2
                gfx.px.pill(s, 1, x1, seam, accent, true, false)
                gfx.px.pill(s, 1, seam + 1, x2, colors.lightGray, false, true)
            else
                gfx.px.pill(s, 1, x1, x2, colors.lightGray, true, true)
            end
        end
    end)
    return ok and (pcall(s.box.render, s.box))
end

-- A three pixel tall progress bar with a lit top edge, a glowing head and a
-- moving highlight. Three unused palette slots hold its shades.
do
    local prog = {}
    function gfx.progress(row, x0, width, frac)
        if not gfx.pb or not settings.graphics then return false end
        local accent = colorValue(settings.barColor, colors.blue)
        if accent == colors.black or accent == colors.gray then accent = colors.blue end
        local r, g, b = term.getPaletteColor(accent)
        local rgb = { r * 255, g * 255, b * 255 }
        local slots = {}
        for _, c in ipairs({ colors.brown, colors.magenta, colors.purple, colors.pink, colors.green }) do
            if c ~= accent and #slots < 3 then table.insert(slots, c) end
        end
        local dark, base, light = slots[1], slots[2], slots[3]
        setPal(dark, mix(rgb, { 0, 0, 0 }, 0.45))
        setPal(base, rgb)
        setPal(light, mix(rgb, { 255, 255, 255 }, 0.55))

        local ok = pcall(function()
            if not prog.win or prog.w ~= width then
                prog.win = window.create(term.current(), x0, row, width, 1, true)
                prog.box = gfx.pb.new(prog.win, colors.gray)
                prog.w = width
            end
            prog.win.reposition(x0, row)
            local pw = width * 2
            local fill = math.floor(pw * frac + 0.5)
            local sweep = (nowSec() * 40) % (pw + 30) - 15
            local canvas = prog.box.canvas
            for px = 1, pw do
                for py = 1, 3 do
                    local c = colors.gray
                    if (px == 1 or px == pw) and py ~= 2 then
                        c = colors.black
                    elseif px <= fill then
                        c = (py == 1) and light or ((py == 2) and base or dark)
                        if math.abs(px - sweep) < 3 then c = light end
                        if px > fill - 2 and py == 2 then c = colors.white end
                    end
                    canvas[py][px] = c
                end
            end
        end)
        if not ok then
            prog.win = nil
            return false
        end
        return (pcall(prog.box.render, prog.box))
    end
end

-- ── The PRISMARINE logo ──────────────────────────────────────────────────────
-- Digits: 0 blank, 1-4 light to solid shade, 5 lower half block, 6 upper half
-- block. The first four rows are the gray half, the last four the colored half.

C.LOGO_ROWS = {
    "0111150011115011051110511511150051115001111501101111505111",
    "0110110011011011011000110110110011011001101101101101101106",
    "0222260022226022062250220220220022222002222602202202202220",
    "0340000034034034000340340340340034034003403403403403403400",
    "0550000055055055000550550550550055055005505505505505505500",
    "0110000011011011000110110110110011011001101101101101101100",
    "0220000022022022000220220000220022022002202202202202202205",
    "5335000533033033033360330000330533033053303303303303306333",
}
C.LOGO_W, C.LOGO_R = 58, #C.LOGO_ROWS
C.SHADE = { [0] = 0, 0.34, 0.58, 0.80, 1.0 }
C.ROWBASE = { 0.34, 0.34, 0.58, 0.85, 0.50, 0.34, 0.58, 0.85 }
C.LOGO_SPLIT = 8 -- half-rows 1..8 are gray, 9..16 are colored

-- SRC[halfRow][col] = brightness 0..1
C.SRC = {}
for r = 1, C.LOGO_R do
    local top, bot = {}, {}
    local row = C.LOGO_ROWS[r]
    for x = 1, C.LOGO_W do
        local ch = tonumber(row:sub(x, x))
        local tl, bl = 0, 0
        if ch >= 1 and ch <= 4 then
            tl, bl = C.SHADE[ch], C.SHADE[ch]
        elseif ch == 5 then
            bl = C.ROWBASE[r]
        elseif ch == 6 then
            tl = C.ROWBASE[r]
        end
        top[x], bot[x] = tl, bl
    end
    C.SRC[r * 2 - 1], C.SRC[r * 2] = top, bot
end

local logoCache = {}

-- Scales the logo to dw pixels wide. A terminal cell is 6x9 units and holds
-- 2x3 Pixelbox pixels, so one art character is 2x3 pixels at full size.
-- art is the PRISMARINE logo unless another art table is given (gfx.wordArt).
local function buildLogo(dw, art)
    art = art or { src = C.SRC, w = C.LOGO_W, r = C.LOGO_R, split = C.LOGO_SPLIT, key = "prism" }
    local SRC, LOGO_W, LOGO_R, LOGO_SPLIT = art.src, art.w, art.r, art.split
    local cacheKey = art.key .. ":" .. dw
    if logoCache[cacheKey] then return logoCache[cacheKey] end
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
    logoCache[cacheKey] = logo
    return logo
end

-- Block letter logos for apps: gfx.wordArt("AUDIO") gives an art table for
-- buildLogo, gray on the top half and colored on the bottom half like the
-- PRISMARINE logo. Letters A-Z and spaces only (anything else is blank).
do
    local G = {
        A = ".###.|#...#|#...#|#####|#...#|#...#|#...#", B = "####.|#...#|#...#|####.|#...#|#...#|####.",
        C = ".####|#....|#....|#....|#....|#....|.####", D = "####.|#...#|#...#|#...#|#...#|#...#|####.",
        E = "#####|#....|#....|####.|#....|#....|#####", F = "#####|#....|#....|####.|#....|#....|#....",
        G = ".####|#....|#....|#..##|#...#|#...#|.####", H = "#...#|#...#|#...#|#####|#...#|#...#|#...#",
        I = "#####|..#..|..#..|..#..|..#..|..#..|#####", J = "..###|....#|....#|....#|....#|#...#|.###.",
        K = "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#", L = "#....|#....|#....|#....|#....|#....|#####",
        M = "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#", N = "#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
        O = ".###.|#...#|#...#|#...#|#...#|#...#|.###.", P = "####.|#...#|#...#|####.|#....|#....|#....",
        Q = ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#", R = "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
        S = ".####|#....|#....|.###.|....#|....#|####.", T = "#####|..#..|..#..|..#..|..#..|..#..|..#..",
        U = "#...#|#...#|#...#|#...#|#...#|#...#|.###.", V = "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
        W = "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#", X = "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
        Y = "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..", Z = "#####|....#|...#.|..#..|.#...|#....|#####",
        [" "] = ".....|.....|.....|.....|.....|.....|.....",
    }
    function gfx.wordArt(word)
        word = tostring(word):upper()
        local wide = #word <= 6
        local rows = {}
        for r = 1, 7 do
            local parts = {}
            for i = 1, #word do
                local g = G[word:sub(i, i)] or G[" "]
                local line, n = "", 0
                for part in (g .. "|"):gmatch("([^|]*)|") do
                    n = n + 1
                    if n == r then line = part break end
                end
                line = line:gsub(".", function(ch)
                    if wide then return ch == "#" and "##" or "  " end
                    return ch == "#" and "#" or " "
                end)
                parts[#parts + 1] = line
            end
            rows[r] = table.concat(parts, wide and "  " or " ")
        end
        local w = 0
        for _, l in ipairs(rows) do w = math.max(w, #l) end
        local src = {}
        for r, line in ipairs(rows) do
            local row = {}
            for x = 1, w do row[x] = (line:sub(x, x) == "#") and 1.0 or 0 end
            src[r * 2 - 1], src[r * 2] = row, row
        end
        return { src = src, w = w, r = #rows, split = #rows, key = "word:" .. word }
    end
end

-- Which of n palette shades a brightness maps to, with ordered dithering.
local function slotFor(level, n, x, y)
    local i = math.floor(level * (n - 1) + thr(x, y))
    if i < 0 then i = 0 elseif i > n - 1 then i = n - 1 end
    return i + 1
end

-- The main menu logo uses the same smooth shades as the boot screen. The menu
-- itself only needs a few of the 16 colors, so the unused slots are
-- reprogrammed into shade ramps. Whoever leaves the menu calls
-- restorePalette() to put them back.
--   Corner: the PRISMARINE wordmark, animated, in the bottom right corner.
--   Large:  the big boot logo under the list.
local menuLogo = { key = nil, pal = nil, mode = nil, acc = nil, t0 = nowSec() }

do
    -- The wordmark in half block pixels: t top half, b bottom half, f full,
    -- m a softer middle. Each cell is 1 pixel wide and 2 tall.
    local rows = {
        "bb  bb  b bbb b   b  b  bb  b b  b bb",
        "fmt fmb b tmb ftmtf fmf fmb b ftmf fm",
        "t   t t t ttt t   t t t t t t t  t tt" }
    local w = #rows[1]
    local lv = {}
    local LEVELS = { [" "] = { 0, 0 }, b = { 0, 1 }, t = { 1, 0 }, f = { 1, 1 }, m = { 0.6, 0.6 } }
    for r = 1, 3 do
        lv[r * 2 - 1], lv[r * 2] = {}, {}
        for c = 1, w do
            local v = LEVELS[rows[r]:sub(c, c)] or LEVELS[" "]
            lv[r * 2 - 1][c] = v[1]
            lv[r * 2][c] = v[2]
        end
    end
    menuLogo.w, menuLogo.lv = w, lv

    -- Slots the menu does not draw with, so they can hold logo shades.
    local function spareSlots()
        local bar = colorValue(settings.barColor, colors.blue)
        local hl = colorValue(settings.highlight, colors.lightBlue)
        local keep = {
            [colors.black] = true, [colors.white] = true, [colors.gray] = true,
            [colors.lightGray] = true, [colors.cyan] = true, [colors.orange] = true,
            [colors.yellow] = true, [bar] = true, [hl] = true,
        }
        local spare = {}
        for i = 0, 15 do
            local c = 2 ^ i
            if not keep[c] then table.insert(spare, c) end
        end
        return spare, bar, hl
    end

    local function isRainbow()
        local p = logoPreset(settings.logoColor)
        return p and p.rainbow
    end

    local MAP = { 1, 1, 2, 3, 3, 4, 5, 5, 6 }   -- 9 pixel rows from 6 art rows

    local function paintWordmark()
        local acc = menuLogo.acc
        if not acc or not menuLogo.box then return end
        local canvas = menuLogo.box.canvas
        local t = nowSec() - menuLogo.t0
        local sweep = (t * 26) % (w * 2 + 70) - 25
        for y = 1, 9 do
            local src = lv[MAP[y]]
            local crow = canvas[y]
            for x = 1, w * 2 do
                local v = src[math.floor((x + 1) / 2)]
                if v > 0 then
                    local d = (x + y * 1.6) - sweep
                    local l = v * (0.5 + 0.22 * math.sin(x * 0.2 - t * 2.4))
                    if d > -9 and d < 9 then
                        local k = 1 - math.abs(d) / 9
                        l = l + k * k * 0.65
                    end
                    crow[x] = acc[slotFor(l, #acc, x, y)]
                end
            end
        end
    end

    local function drawCorner(rows)
        if not gfx.pb or not settings.graphics then return end
        if rows < 3 or W < w + 2 then return end
        local spare = spareSlots()
        if #spare < 5 then return end
        local acc = { spare[1], spare[2], spare[3], spare[4], spare[5] }
        local function applyPal()
            local accent = logoRGB(isRainbow() and (nowSec() - menuLogo.t0) or 0)
            for i, c in ipairs(acc) do setPal(c, accentAt(accent, (i - 1) / 4)) end
        end
        applyPal()
        menuLogo.pal, menuLogo.mode, menuLogo.acc = applyPal, "Corner", acc

        local key = table.concat({ "c", W, H }, ":")
        if menuLogo.key ~= key or not menuLogo.win then
            local ok = pcall(function()
                menuLogo.win = window.create(term.current(), W - w, H - 3, w, 3, true)
                menuLogo.box = gfx.pb.new(menuLogo.win, colors.black)
            end)
            if not ok then
                menuLogo.key, menuLogo.pal, menuLogo.mode = nil, nil, nil
                return
            end
            menuLogo.key = key
        end
        paintWordmark()
        pcall(menuLogo.box.render, menuLogo.box)
    end

    local function drawLarge(y0, rows)
        if not gfx.pb or not settings.graphics then return end
        local dw = math.min(98, W * 2 - 4, math.floor(rows * 14.5))
        if rows < 4 or dw < 40 then return end
        local spare, bar, hl = spareSlots()
        if #spare < 7 then return end
        local acc = { spare[1], spare[2], spare[3], spare[4], spare[5] }
        local g2, g3 = spare[6], spare[7]

        local hueStep = isRainbow() and math.floor(nowSec() / 3) or 0
        local accent = logoRGB(hueStep * 3)
        local function applyPal()
            for i, c in ipairs(acc) do setPal(c, accentAt(accent, (i - 1) / 4)) end
            local function between(dest, a, b2)
                local r1, g1, b1 = term.getPaletteColor(a)
                local r2, g2c, b3 = term.getPaletteColor(b2)
                term.setPaletteColor(dest, (r1 + r2) / 2, (g1 + g2c) / 2, (b1 + b3) / 2)
            end
            between(g2, colors.gray, colors.lightGray)
            between(g3, colors.lightGray, colors.white)
        end
        applyPal()
        menuLogo.pal, menuLogo.mode = applyPal, "Large"
        local grays = { colors.gray, g2, colors.lightGray, g3, colors.white }

        local key = table.concat({ "l", W, rows, y0, dw, tostring(settings.logoColor), hueStep, bar, hl }, ":")
        if menuLogo.key ~= key then
            local ok = pcall(function()
                local logo = buildLogo(dw)
                menuLogo.win = window.create(term.current(), 1, y0, W, rows, true)
                menuLogo.box = gfx.pb.new(menuLogo.win, colors.black)
                local ox = math.floor((W * 2 - dw) / 2)
                local oy = math.max(0, math.floor((rows * 3 - logo.h) / 2))
                for dy = 1, logo.h do
                    local crow = menuLogo.box.canvas[oy + dy]
                    if crow then
                        local ramp = (logo.rg[dy] == 1) and grays or acc
                        for dx = 1, dw do
                            local l = logo.lv[dy][dx]
                            if l > 0.03 then
                                crow[ox + dx] = ramp[slotFor(l, 5, dx, dy)]
                            end
                        end
                    end
                end
            end)
            if not ok then
                menuLogo.key, menuLogo.pal, menuLogo.mode = nil, nil, nil
                return
            end
            menuLogo.key = key
        end
        pcall(menuLogo.box.render, menuLogo.box)
    end

    -- Draws the logo in the free rows between the list and the footer.
    function gfx.menuLogo(y0, rows)
        menuLogo.pal, menuLogo.mode = nil, nil
        local mode = settings.menuLogo
        if mode == "Corner" then
            drawCorner(rows)
        elseif mode == "Large" then
            drawLarge(y0, rows)
        end
    end

    -- True when the menu logo moves, so the menu should call gfx.menuTick.
    function gfx.menuAnimated()
        return settings.menuLogo == "Corner" and gfx.pb ~= nil and settings.graphics
    end

    -- Draws the next frame of the wordmark without touching the rest of the screen.
    function gfx.menuTick()
        if menuLogo.mode ~= "Corner" or not menuLogo.box or not menuLogo.pal then return end
        if isRainbow() then menuLogo.pal() end
        paintWordmark()
        pcall(menuLogo.box.render, menuLogo.box)
    end

    -- Puts every palette slot at the current brightness, logo shades included.
    function gfx.menuRedraw()
        restorePalette()
        if menuLogo.pal then menuLogo.pal() end
    end
end

-- ── Monitor dashboard ────────────────────────────────────────────────────────
-- A monitor in Dashboard mode shows a big, centered PRISMARINE logo drawn with
-- Pixelbox straight onto the monitor, so it uses the monitor's full pixel
-- resolution. The computer ID sits in the top left corner and the real time and
-- game time along the bottom. The monitor has its own palette, so nothing here
-- touches the colors of the computer screen.
-- gfx.dashTick runs from the event wrapper every 0.25 seconds (os.startTimer).

do
    -- A 3x5 pixel font for the clock and labels. Each glyph is 5 rows of 3.
    local FONT = {
        ["0"] = "111101101101111", ["1"] = "010110010010111",
        ["2"] = "111001111100111", ["3"] = "111001111001111",
        ["4"] = "101101111001001", ["5"] = "111100111001111",
        ["6"] = "111100111101111", ["7"] = "111001010010010",
        ["8"] = "111101111101111", ["9"] = "111101111001111",
        [":"] = "000010000010000", [" "] = "000000000000000",
        A = "010101111101101", D = "110101101101110", E = "111100110100111",
        G = "111100101101111", I = "111010010010111", L = "100100100100111",
        M = "101111111101101", P = "111101111100100", R = "110101110101101",
    }

    local function textW(str, s) return #str * 4 * s - s end

    local function fillPx(d, x1, y1, x2, y2, color)
        local canvas = d.box.canvas
        x1, x2 = math.max(1, x1), math.min(d.pw, x2)
        for y = math.max(1, y1), math.min(d.ph, y2) do
            local row = canvas[y]
            if row then
                for x = x1, x2 do row[x] = color end
            end
        end
    end

    local function drawStr(d, x, y, str, s, color)
        local canvas, pw = d.box.canvas, d.pw
        for ci = 1, #str do
            local g = FONT[str:sub(ci, ci)] or FONT[" "]
            for ry = 0, 4 do
                for rx = 0, 2 do
                    local at = ry * 3 + rx + 1
                    if g:sub(at, at) == "1" then
                        for sy = 0, s - 1 do
                            local row = canvas[y + ry * s + sy]
                            if row then
                                for sx = 0, s - 1 do
                                    local px = x + (ci - 1) * 4 * s + rx * s + sx
                                    if px >= 1 and px <= pw then row[px] = color end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- The monitor's own palette: grays and the logo accent ramp.
    local function dashPalette(d)
        local function set(c, rgb)
            pcall(d.mon.setPaletteColor, c,
                clamp(rgb[1] / 255, 0, 1), clamp(rgb[2] / 255, 0, 1), clamp(rgb[3] / 255, 0, 1))
        end
        local p = logoPreset(settings.logoColor)
        local accent = logoRGB((p and p.rainbow) and (nowSec() - d.t0) or 0)
        set(P.bg, { 5, 7, 12 })
        set(P.txt, { 236, 242, 248 })
        set(P.dim, { 120, 132, 148 })
        set(P.track, { 26, 31, 42 })
        for i, c in ipairs(P.gr) do set(c, grayAt((i - 1) / (#P.gr - 1))) end
        for i, c in ipairs(P.ac) do set(c, accentAt(accent, (i - 1) / (#P.ac - 1))) end
    end

    -- Works out where everything goes for the monitor's current size and
    -- clears the canvas. Called on setup, and again if the time format changes.
    local function dashLayout(d)
        local pw, ph = d.pw, d.ph
        local s = math.max(1, math.min(math.floor(pw / 70), math.floor(ph / 45), 8))
        local m = math.max(2, s * 2)
        local lineH = 5 * s
        -- Longest possible text decides whether both clocks fit on one line.
        local nReal = 5 + (settings.hour24 and 8 or 11)
        local nGame = 5 + (settings.hour24 and 5 or 8)
        local single = (nReal + nGame) * 4 * s + 6 * s + 2 * m <= pw
        d.s, d.m, d.single = s, m, single
        d.y1 = ph - m - lineH + 1
        d.y2 = single and d.y1 or (d.y1 - lineH - 2 * s)
        d.divY = d.y2 - m
        local top = m + lineH + m
        local avail = (d.divY - m) - top
        local dw = math.min(math.floor(pw * 0.86), math.floor(avail * 4.5), 320)
        if dw < 16 then error("monitor too small for the dashboard") end
        d.logo = buildLogo(dw)
        d.ox = math.floor((pw - dw) / 2)
        d.oy = top + math.max(0, math.floor((avail - d.logo.h) / 2))

        fillPx(d, 1, 1, pw, ph, colors.black)
        drawStr(d, m, m, "ID", s, P.dim)
        drawStr(d, m + 12 * s, m, tostring(os.getComputerID()), s, P.txt)
        fillPx(d, m, d.divY, pw - m, d.divY + s - 1, P.gr[2])
        d.tkey = nil
        d.layoutKey = tostring(settings.hour24)
    end

    local function paintTimes(d, real, game)
        local s, m = d.s, d.m
        fillPx(d, 1, d.divY + s, d.pw, d.ph, colors.black)
        drawStr(d, m, d.y1, "REAL", s, P.dim)
        drawStr(d, m + 20 * s, d.y1, real, s, P.txt)
        local gx = m
        if d.single then
            gx = d.pw - m - textW("GAME " .. game, s)
        end
        drawStr(d, gx, d.y2, "GAME", s, P.dim)
        drawStr(d, gx + 20 * s, d.y2, game, s, P.txt)
    end

    -- The logo in the same smooth shades as the boot screen, with a bright band
    -- sweeping across it. Pixels that are blank in the art stay black.
    local function paintLogo(d, t)
        local logo = d.logo
        local canvas = d.box.canvas
        local span = logo.w + logo.h * 2 + 60
        local sweep = (t * 45) % span - 30
        local grays, accs = P.gr, P.ac
        for dy = 1, logo.h do
            local crow = canvas[d.oy + dy]
            if crow then
                local ramp = (logo.rg[dy] == 1) and grays or accs
                local n = #ramp
                local lrow = logo.lv[dy]
                for dx = 1, logo.w do
                    local l = lrow[dx]
                    if l > 0.03 then
                        local dd = (dx + dy * 2) - sweep
                        if dd > -14 and dd < 14 then
                            local k = 1 - math.abs(dd) / 14
                            l = l + k * k * 0.45
                        end
                        crow[d.ox + dx] = ramp[slotFor(l, n, dx, dy)]
                    end
                end
            end
        end
    end

    local function dashDraw(d)
        if d.layoutKey ~= tostring(settings.hour24) then dashLayout(d) end
        local p = logoPreset(settings.logoColor)
        local ck = tostring(settings.logoColor)
        if (p and p.rainbow) or d.colorKey ~= ck then
            d.colorKey = ck
            dashPalette(d)
        end
        paintLogo(d, nowSec() - d.t0)

        local real = settings.hour24 and os.date("%H:%M:%S") or os.date("%I:%M:%S %p")
        local game = textutils.formatTime(os.time(), settings.hour24)
        real, game = real:upper(), game:upper()
        local tkey = real .. "|" .. game
        if d.tkey ~= tkey then
            paintTimes(d, real, game)
            d.tkey = tkey
        end
        d.box:render()
    end

    -- Sets a monitor up as a dashboard (also used when it is resized).
    function gfx.dashSetup(d)
        if not gfx.pb then error("Pixelbox_Lite is not loaded") end
        local mon = d.mon
        -- Auto and Pixel both give the full 0.5 resolution. A number is kept.
        pcall(mon.setTextScale, tonumber(settings.monScale) or 0.5)
        pcall(function()
            mon.setBackgroundColor(colors.black)
            mon.clear()
        end)
        local mw, mh = mon.getSize()
        d.win = window.create(mon, 1, 1, mw, mh, true)
        d.box = gfx.pb.new(d.win, colors.black)
        d.mw, d.mh, d.pw, d.ph = mw, mh, mw * 2, mh * 3
        d.t0 = nowSec()
        d.colorKey = tostring(settings.logoColor)
        dashPalette(d)
        dashLayout(d)
        dashDraw(d)
    end

    -- Draws the next frame on every dashboard monitor. A monitor that fails is
    -- set up again a little later instead of freezing.
    function gfx.dashTick()
        gfx.dashLast = nowSec()
        for _, d in ipairs(gfx.dashes) do
            if pcall(dashDraw, d) then
                d.fails = 0
            else
                d.fails = (d.fails or 0) + 1
                if d.fails % 20 == 1 then pcall(gfx.dashSetup, d) end
            end
        end
    end
end

-- ── Network state ────────────────────────────────────────────────────────────

local net = {
    peers   = {},  -- id -> { name = "..." }
    history = {},  -- key ("all" or sender id) -> list of messages
    unread  = {},  -- key -> count
    offers  = {},  -- incoming file offers waiting for an answer
}

local function loadName()
    if fs.exists(C.NAME_FILE) then
        local f = fs.open(C.NAME_FILE, "r")
        if f then
            local n = f.readLine()
            f.close()
            if n and n ~= "" then return n end
        end
    end
    return os.getComputerLabel() or ("PC" .. os.getComputerID())
end

local function saveName(n)
    local f = fs.open(C.NAME_FILE, "w")
    if f then
        f.write(n)
        f.close()
    end
end

local myName = loadName()

local function openModems()
    local found = false
    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            local ok = pcall(function()
                if not rednet.isOpen(side) then rednet.open(side) end
            end)
            if ok then found = true end
        end
    end
    return found
end

local function addHistory(key, line)
    local h = net.history[key]
    if not h then
        h = {}
        net.history[key] = h
    end
    table.insert(h, line)
    if #h > 100 then table.remove(h, 1) end
end

-- Drops file offers that are older than two minutes.
local function pruneOffers()
    local now = nowSec()
    for i = #net.offers, 1, -1 do
        if now - net.offers[i].at > 120 then table.remove(net.offers, i) end
    end
end

local function unreadTotal()
    local n = 0
    for _, v in pairs(net.unread) do n = n + v end
    pruneOffers()
    return n + #net.offers
end

-- ── Private messages ─────────────────────────────────────────────────────────
-- A private message is broadcast to the whole network, but sealed. The envelope
-- holds the text twice: once for the target computer and once for the Archive.
-- Each copy is encrypted (HMAC-SHA256 keystream) with a key made from the
-- network passphrase (settings.netKey) and the recipient ("id:<computer id>" or
-- "archive"), and carries a message authentication code. A computer that is not
-- the recipient cannot match the recipient tag, so it denies the message and
-- drops it at once. Nothing of it is kept. Everything lives in C.cr to save
-- local-variable slots.

C.cr = { kc = {}, seen = {}, seenList = {}, denied = 0, ctr = 0 }

function C.cr.unhex(h)
    return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

function C.cr.hex(s)
    return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

-- Raw 32 byte SHA-256 digest.
function C.cr.hr(s)
    return C.cr.unhex(sha256(s, false))
end

function C.cr.hmac(key, msg)
    if #key > 64 then key = C.cr.hr(key) end
    key = key .. string.rep("\0", 64 - #key)
    local ip, op = {}, {}
    for i = 1, 64 do
        local b = key:byte(i)
        ip[i] = string.char(bit32.bxor(b, 0x36))
        op[i] = string.char(bit32.bxor(b, 0x5c))
    end
    return C.cr.hr(table.concat(op) .. C.cr.hr(table.concat(ip) .. msg))
end

-- Compares two strings without stopping at the first difference.
function C.cr.same(a, b)
    if #a ~= #b then return false end
    local d = 0
    for i = 1, #a do d = bit32.bor(d, bit32.bxor(a:byte(i), b:byte(i))) end
    return d == 0
end

-- Turns a passphrase into the stored network key (64 hex characters).
function C.cr.derive(pass)
    local k = C.cr.hr("KHI-Prismarine-private-v1|" .. pass)
    for i = 1, 1000 do
        k = C.cr.hr(k .. pass)
        if i % 100 == 0 then os.sleep(0) end
    end
    return C.cr.hex(k)
end

-- Encryption key and MAC key for one recipient.
function C.cr.keys(label)
    local c = C.cr.kc[label]
    if c and c.mk == settings.netKey then return c.ke, c.km end
    local k = C.cr.hmac(C.cr.unhex(settings.netKey), "KHI-key|" .. label)
    c = { mk = settings.netKey, ke = C.cr.hmac(k, "enc"), km = C.cr.hmac(k, "mac") }
    C.cr.kc[label] = c
    return c.ke, c.km
end

-- Encrypts or decrypts (the same operation) with an HMAC counter keystream.
function C.cr.stream(ke, nonce, data)
    local out = {}
    for i = 1, #data, 32 do
        local n = math.floor((i - 1) / 32)
        local ks = C.cr.hmac(ke, nonce .. string.char(n % 256, math.floor(n / 256) % 256))
        local bytes = {}
        for j = 1, math.min(32, #data - i + 1) do
            bytes[j] = string.char(bit32.bxor(data:byte(i + j - 1), ks:byte(j)))
        end
        out[#out + 1] = table.concat(bytes)
    end
    return table.concat(out)
end

function C.cr.seal(label, nonce, plain)
    local ke, km = C.cr.keys(label)
    local ct = C.cr.stream(ke, nonce, plain)
    return {
        t = C.cr.hex(C.cr.hmac(km, "tag" .. nonce)):sub(1, 16),
        c = C.cr.hex(ct),
        m = C.cr.hex(C.cr.hmac(km, "mac1" .. label .. nonce .. ct)),
    }
end

-- Opens one slot ("a" for the target, "r" for the Archive) of an envelope.
-- Returns the message, or nil and a reason ("foreign" means it is not for us).
function C.cr.open(env, slot, label)
    if settings.netKey == "" then return nil, "no key" end
    if type(env) ~= "table" or (env.type ~= "priv" and env.type ~= "aud") or env.v ~= 1 then return nil, "bad" end
    local n, s = env.n, env[slot]
    if type(n) ~= "string" or #n ~= 32 or n:find("%X") then return nil, "bad" end
    if type(s) ~= "table" or type(s.t) ~= "string" or type(s.c) ~= "string" or type(s.m) ~= "string" then
        return nil, "bad"
    end
    if #s.t ~= 16 or #s.m ~= 64 or #s.c < 2 or #s.c > 1400 or #s.c % 2 ~= 0
        or s.t:find("%X") or s.c:find("%X") or s.m:find("%X") then
        return nil, "bad"
    end
    local nonce = C.cr.unhex(n)
    local ke, km = C.cr.keys(label)
    if not C.cr.same(C.cr.hex(C.cr.hmac(km, "tag" .. nonce)):sub(1, 16), s.t) then return nil, "foreign" end
    local ct = C.cr.unhex(s.c)
    if not C.cr.same(C.cr.hex(C.cr.hmac(km, "mac1" .. label .. nonce .. ct)), s.m) then return nil, "bad" end
    local key = label .. n
    if C.cr.seen[key] then return nil, "repeat" end
    local from, to, at, name, text = C.cr.stream(ke, nonce, ct):match("^(%d+)\n(%d+)\n(%d+)\n([^\n]*)\n(.*)$")
    if not from then return nil, "bad" end
    at = tonumber(at)
    if math.abs(os.epoch("utc") - at) > 300000 then return nil, "old" end
    C.cr.seen[key] = true
    C.cr.seenList[#C.cr.seenList + 1] = key
    if #C.cr.seenList > 200 then C.cr.seen[table.remove(C.cr.seenList, 1)] = nil end
    return { from = tonumber(from), to = tonumber(to), at = at, name = name, text = text }
end

-- For this computer. The sender written inside must be the sender Rednet saw.
function C.cr.openMine(sender, env)
    local me = os.getComputerID()
    if type(env) ~= "table" or env.type ~= "priv" then return nil, "bad" end
    local m, why = C.cr.open(env, "a", "id:" .. string.format("%.0f", me))
    if not m then return nil, why end
    if m.from ~= sender or m.to ~= me then return nil, "bad" end
    return m
end

-- For the Archive app (api.openPrivate). Any computer with the network
-- passphrase can open the Archive copy. spoofed is true when the sender
-- written inside is not the sender Rednet saw.
function C.cr.openArchive(sender, env)
    local m, why = C.cr.open(env, "r", "archive")
    if not m then return nil, why end
    m.spoofed = m.from ~= sender
    m.kind = env.type
    return m
end

-- Broadcasts one sealed private message (at most about 200 characters).
function C.cr.send(target, text)
    if settings.netKey == "" then return false end
    C.cr.ctr = C.cr.ctr + 1
    local me, now = os.getComputerID(), os.epoch("utc")
    local nonce = C.cr.hr(table.concat({
        string.format("%.0f", now), me, C.cr.ctr, math.random(0, 2147483647), os.clock(),
    }, "|")):sub(1, 16)
    local plain = table.concat({
        string.format("%.0f", me), string.format("%.0f", target), string.format("%.0f", now),
        (myName:gsub("[\r\n]", " ")), text,
    }, "\n")
    local env = {
        type = "priv", v = 1, n = C.cr.hex(nonce),
        a = C.cr.seal("id:" .. string.format("%.0f", target), nonce, plain),
        r = C.cr.seal("archive", nonce, plain),
    }
    if C.au.loop then os.queueEvent("rednet_message", me, env, C.PRIV_PROTO) end
    return pcall(rednet.broadcast, env, C.PRIV_PROTO)
end

-- ── Activity reports ─────────────────────────────────────────────────────────
-- Every computer running this OS reports what it does to the Archive: boots,
-- programs and shell commands, files sent and received, errors, secure boot
-- results and attached peripherals. A report is broadcast sealed like a private
-- message, but only the Archive copy exists, so only the Archive can read it.
-- Reports need the network passphrase and can be turned off in Settings
-- (Activity reports). Apps can report too with api.audit(kind, text).

-- loop is true while the Archive runs here, so it also sees what this computer does.
C.au = { last = {}, n = 0, winAt = 0, winN = 0, beatAt = 0, loop = false }

function C.au.send(kind, text)
    C.cr.ctr = C.cr.ctr + 1
    local me, now = os.getComputerID(), os.epoch("utc")
    local nonce = C.cr.hr(table.concat({
        string.format("%.0f", now), me, C.cr.ctr, math.random(0, 2147483647), os.clock(), "aud",
    }, "|")):sub(1, 16)
    local plain = table.concat({
        string.format("%.0f", me), "0", string.format("%.0f", now),
        (myName:gsub("[\r\n]", " ")), kind .. "|" .. text,
    }, "\n")
    local env = { type = "aud", v = 1, n = C.cr.hex(nonce), r = C.cr.seal("archive", nonce, plain) }
    if C.au.loop then os.queueEvent("rednet_message", me, env, C.AUDIT_PROTO) end
    pcall(rednet.broadcast, env, C.AUDIT_PROTO)
end

-- Reports one thing. Never raises an error and never reports the same thing
-- twice within two seconds. At most 10 reports go out in any 5 seconds.
function C.au.log(kind, text)
    if settings.audit == false or settings.netKey == "" then return end
    kind = tostring(kind or "event"):gsub("[^%w_]", "_"):sub(1, 20)
    text = tostring(text or ""):gsub("%c", " "):sub(1, 160)
    local key, now = kind .. "|" .. text, os.epoch("utc")
    if C.au.last[key] and now - C.au.last[key] < 2000 then return end
    C.au.n = C.au.n + 1
    if C.au.n > 50 then C.au.last, C.au.n = {}, 0 end
    C.au.last[key] = now
    if now - C.au.winAt > 5000 then C.au.winAt, C.au.winN = now, 0 end
    if C.au.winN >= 10 then return end
    C.au.winN = C.au.winN + 1
    pcall(C.au.send, kind, text)
end

-- A sign of life once a minute.
function C.au.beat()
    local now = os.epoch("utc")
    if now - C.au.beatAt < 60000 then return end
    C.au.beatAt = now
    C.au.log("presence", "online, Prismarine OS v" .. VERSION .. ", label " .. (os.getComputerLabel() or "none"))
end

function C.au.event(ev, a)
    if ev == "prismarine_tick" then
        C.au.beat()
    elseif ev == "peripheral" or ev == "peripheral_detach" then
        C.au.log("peripheral", (ev == "peripheral" and "attached " or "detached ") .. tostring(a))
    end
end

-- Commands typed at the shell prompt, and programs started with shell.run.
function C.au.hook()
    if C.au.hooked or not shell or type(shell.run) ~= "function" then return end
    local run = shell.run
    C.au.hooked = true
    shell.run = function(...)
        local words, parts = table.pack(...), {}
        for i = 1, words.n do parts[i] = tostring(words[i]) end
        pcall(C.au.log, "command", table.concat(parts, " "))
        return run(...)
    end
end
C.au.hook()

local function handleNet(sender, msg, protocol)
    if protocol == C.FILE_PROTO then
        -- Only offers are handled here. Chunks and acknowledgements belong to
        -- the send and receive screens.
        if type(msg) ~= "table" or type(msg.xid) ~= "string" then return end
        if msg.type == "offer" then
            local size, chunk, sum, chunks = msg.size, msg.chunk, msg.sum, msg.chunks
            if type(msg.name) ~= "string" or type(size) ~= "number" or type(chunk) ~= "number"
                or type(sum) ~= "number" or type(chunks) ~= "number" then return end
            if size < 1 or size > C.MAX_FILE or chunk < 256 or chunk > 16384 then return end
            if chunks ~= math.ceil(size / chunk) then return end
            pruneOffers()
            for _, o in ipairs(net.offers) do
                if o.xid == msg.xid then return end
            end
            if #net.offers >= 10 then return end
            table.insert(net.offers, {
                xid = msg.xid, from = sender, who = tostring(msg.from or "Unknown"):sub(1, 20),
                name = msg.name:sub(1, 64), size = size, chunk = chunk, sum = sum,
                chunks = chunks, at = nowSec(),
            })
        elseif msg.type == "cancel" then
            for i = #net.offers, 1, -1 do
                if net.offers[i].xid == msg.xid and net.offers[i].from == sender then
                    table.remove(net.offers, i)
                end
            end
        end
        return
    end
    if protocol == C.PRIV_PROTO then
        -- A sealed private message. Only its target can open it. For every
        -- other computer it is denied and dropped right here.
        if sender == os.getComputerID() then return end
        local m = C.cr.openMine(sender, msg)
        msg = nil
        if not m then
            C.cr.denied = C.cr.denied + 1
            return
        end
        local who = m.name:sub(1, 20)
        net.peers[sender] = { name = who }
        addHistory(sender, { who = who, text = m.text, mine = false })
        net.unread[sender] = (net.unread[sender] or 0) + 1
        return
    end
    if protocol ~= C.PROTO or type(msg) ~= "table" then return end
    local name = tostring(msg.name or "Unknown")
    if msg.type == "discover" then
        net.peers[sender] = { name = name }
        pcall(rednet.send, sender, { type = "hello", name = myName }, C.PROTO)
    elseif msg.type == "hello" then
        net.peers[sender] = { name = name }
    elseif msg.type == "msg" then
        net.peers[sender] = { name = name }
        local key = msg.all and "all" or sender
        addHistory(key, { who = name, text = tostring(msg.text or ""), mine = false })
        net.unread[key] = (net.unread[key] or 0) + 1
    end
end

-- Runs next to a launched program so messages keep arriving.
local function backgroundNet()
    while true do
        local _, a, b, c = os.pullEventRaw("rednet_message")
        handleNet(a, b, c)
    end
end

-- ── Drawing and input helpers ────────────────────────────────────────────────

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


local clk = { state = nil, lastText = nil, lastAt = 0 }

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
    clk.state = { title = title, bar = bar, fancy = fancy, len = 0 }
    if clock ~= "" and W >= #title + #clock + 4 then
        term.setCursorPos(W - #clock, 1)
        if fancy then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
        end
        term.write(clock)
        clk.state.len = #clock
    end
end

-- Repaints just the clock in the header. Screens that wait for a key without
-- redrawing (messages, yes/no questions) call this on every tick.
function clk.refresh()
    local h = clk.state
    if not h then return end
    local clock = clockText()
    local width = math.max(h.len, #clock)
    if clock == "" and h.len == 0 then return end
    if W < #h.title + width + 4 then return end
    term.setCursorBlink(false)
    term.setCursorPos(W - width, 1)
    if h.fancy then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    else
        term.setBackgroundColor(h.bar)
        term.setTextColor(textOn(h.bar))
    end
    term.write(string.rep(" ", width - #clock) .. clock)
    h.len = #clock
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
    local layout, x = {}, 1
    for _, b in ipairs(buttons) do
        local tagText = (b.tag ~= "") and (" " .. b.tag .. " ") or ""
        local labelText = ((b.tag ~= "") and "" or " ") .. b.label .. " "
        local total = #tagText + #labelText
        if x + total - 1 > W then break end
        table.insert(layout, { x = x, tag = #tagText, total = total, tagText = tagText,
                               labelText = labelText, k = b.k })
        x = x + total + 1
    end
    -- Rounded pills when Pixelbox is on. The first and last cell of each
    -- button are the rounded ends, so the text skips them.
    local pill = gfx.px.footer(layout, accent)
    for _, b in ipairs(layout) do
        local lx = b.x
        if b.tag > 0 then
            term.setBackgroundColor(accent)
            term.setTextColor(textOn(accent))
            if pill then
                term.setCursorPos(lx + 1, H)
                term.write(b.tagText:sub(2))
            else
                term.setCursorPos(lx, H)
                term.write(b.tagText)
            end
            lx = lx + b.tag
        end
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        if pill then
            local text = b.labelText:sub(1, -2)
            if b.tag == 0 then
                text = text:sub(2)
                lx = lx + 1
            end
            term.setCursorPos(lx, H)
            term.write(text)
        else
            term.setCursorPos(lx, H)
            term.write(b.labelText)
        end
        table.insert(buttonHits, { x1 = b.x, x2 = b.x + b.total - 1, k = b.k })
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
--   tick   true when the heartbeat says the clock changed (or two seconds
--          passed), so every screen that redraws after readInput stays live
-- Letters arrive as both a key event and a char event. The char event that
-- follows a key event for the same letter is dropped.
local lastKeyName, lastKeyAt = nil, 0

local function readInput()
    while true do
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
        elseif ev == "prismarine_tick" then
            -- Twice a second. A redraw is only worth it when the clock text
            -- changed, plus every two seconds for unread counts and file lists.
            C.au.event(ev, a)
            local text = clockText()
            local now = os.epoch("utc")
            if text ~= clk.lastText or now - clk.lastAt >= 2000 then
                clk.lastText, clk.lastAt = text, now
                return { tick = true }
            end
        else
            C.au.event(ev, a)
            return { ev = ev }
        end
    end
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
                if fancy then
                    -- The first and last cells belong to the rounded pill.
                    term.setCursorPos(2, row)
                    term.write(pad(e.label, solid - 2))
                else
                    term.setCursorPos(1, row)
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
        if i and i.tick then clk.refresh() end
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
    if not gfx.px.card(2, y, W - 2, h, stripe or colors.lightBlue, colors.gray) then
        fillRect(2, y, W - 1, y + h - 1, colors.gray)
        fillRect(2, y, 2, y + h - 1, stripe or colors.lightBlue)
    end
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
        if i.tick then clk.refresh() end
        if i.k == "y" then
            return true
        elseif i.k == "n" or i.k == "enter" or i.k == "q" or i.k == "backspace" then
            return false
        end
    end
end

-- Shows a short list of options. Returns the chosen number or nil.
local function pickMenu(title, options, start)
    local entries = {}
    for n, o in ipairs(options) do entries[n] = { label = o } end
    local sel, top = math.max(1, math.min(#options, start or 1)), 1
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

-- Network passphrase for private messages. Only a key made from it is saved.
function C.cr.setPass()
    local lines = {
        "Use the same passphrase on every computer and in the Archive.",
        "At least 8 characters. A long phrase is safer.",
    }
    local v = ask("Network passphrase", lines, nil, "*")
    if not v then return end
    if #v < 8 then
        showMessage("Network passphrase", { "Too short. Use at least 8 characters." }, colors.red)
        return
    end
    local again = ask("Network passphrase", { "Type it again to confirm:" }, nil, "*")
    if again ~= v then
        showMessage("Network passphrase", { "The two entries differ. Nothing was changed." }, colors.red)
        return
    end
    showBusy("Network passphrase", "Making the key...")
    settings.netKey = C.cr.derive(v)
    C.cr.kc, C.cr.seen, C.cr.seenList = {}, {}, {}
    saveSettings()
    showMessage("Network passphrase", { "Passphrase set.", "Private messages are now sealed." }, colors.lime)
end

function C.cr.menu()
    local pick = pickMenu("Network passphrase", { "Set a passphrase", "Remove the passphrase", "Back" }, 1)
    if pick == 1 then
        C.cr.setPass()
    elseif pick == 2 and settings.netKey ~= "" then
        if confirm({ "Remove the passphrase?", "Private messages stop until a new one is set." }) then
            settings.netKey = ""
            C.cr.kc = {}
            saveSettings()
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

-- ── Messenger ────────────────────────────────────────────────────────────────

local function discover(wait)
    net.peers = {}
    pcall(rednet.broadcast, { type = "discover", name = myName }, C.PROTO)
    local timer = os.startTimer(wait)
    while true do
        local ev, a, b, c = os.pullEventRaw()
        if ev == "rednet_message" then
            handleNet(a, b, c)
        elseif ev == "timer" and a == timer then
            break
        end
    end
end

local function wrap(text, width)
    if #text == 0 then return { "" } end
    local out = {}
    for i = 1, #text, width do
        table.insert(out, text:sub(i, i + width - 1))
    end
    return out
end

local function drawChat(entry, input)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header("Chat: " .. entry.name)

    local lines = {}
    for _, m in ipairs(net.history[entry.key] or {}) do
        for _, l in ipairs(wrap(m.who .. ": " .. m.text, W)) do
            table.insert(lines, { text = l, mine = m.mine })
        end
    end
    local visible = H - 3
    local start = math.max(1, #lines - visible + 1)
    term.setBackgroundColor(colors.black)
    for n = start, #lines do
        term.setCursorPos(1, 2 + n - start)
        term.setTextColor(lines[n].mine and colors.lime or colors.white)
        term.write(lines[n].text)
    end

    local shown = "> " .. input
    if #shown > W - 1 then shown = shown:sub(-(W - 1)) end
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(pad(shown, W))
    footerButtons({
        { tag = "Ent", label = "Send", k = "enter" },
        { tag = "Tab", label = "Back", k = "tab" },
    })
    term.setCursorPos(math.min(#shown + 1, W), H - 1)
    term.setBackgroundColor(colors.gray)
    term.setCursorBlink(true)
end

local function chat(entry)
    local input = ""

    local function send()
        if input == "" then return end
        if entry.key == "all" then
            pcall(rednet.broadcast, { type = "msg", name = myName, text = input, all = true }, C.PROTO)
        else
            -- Private: broadcast sealed, so only the target and the Archive can read it.
            if settings.netKey == "" then
                if confirm({
                    "Private messages need a network passphrase.",
                    "Use the same one on every computer and in the Archive.",
                    "Set it now?",
                }) then C.cr.setPass() end
                if settings.netKey == "" then return end
            end
            for i = 1, #input, 200 do
                C.cr.send(entry.id, input:sub(i, i + 199))
            end
        end
        addHistory(entry.key, { who = "You", text = input, mine = true })
        input = ""
    end

    while true do
        net.unread[entry.key] = nil
        drawChat(entry, input)
        local ev, a, b, c = os.pullEventRaw()
        if ev == "char" or ev == "paste" then
            input = input .. a
        elseif ev == "key" then
            if a == keys.enter then
                send()
            elseif a == keys.backspace then
                input = input:sub(1, -2)
            elseif a == keys.tab then
                term.setCursorBlink(false)
                return
            end
        elseif ev == "mouse_click" then
            local k = hitButton(b, c)
            if k == "enter" then
                send()
            elseif k == "tab" then
                term.setCursorBlink(false)
                return
            end
        elseif ev == "rednet_message" then
            handleNet(a, b, c)
        elseif ev == "term_resize" then
            W, H = term.getSize()
        end
    end
end

-- ── File transfer ────────────────────────────────────────────────────────────
-- Files travel over rednet, so they work on any modem: a wireless modem, or a
-- wired modem on a networking cable. When a computer has both, the sender picks
-- which link to use. The receiver always listens on every modem.
-- Each packet is acknowledged and sent again if it gets lost.

local function checksum(data)
    local a, b = 1, 0
    for i = 1, #data, 4096 do
        local bytes = { data:byte(i, math.min(i + 4095, #data)) }
        for j = 1, #bytes do
            a = (a + bytes[j]) % 65521
            b = (b + a) % 65521
        end
        if i % 65536 == 1 then sleep(0) end
    end
    return b * 65536 + a
end

-- Returns whether a wireless modem and whether a wired (cable) modem is attached.
local function modemKinds()
    local wireless, wired = false, false
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local ok, w = pcall(peripheral.call, name, "isWireless")
            if ok and w then wireless = true else wired = true end
        end
    end
    return wireless, wired
end

-- mode: "auto" opens every modem, "wireless" or "cable" opens only that kind.
local function setLink(mode)
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local ok, w = pcall(peripheral.call, name, "isWireless")
            local isWireless = ok and w
            local keep = mode == "auto" or (mode == "wireless" and isWireless) or (mode == "cable" and not isWireless)
            pcall(function()
                if keep then
                    if not rednet.isOpen(name) then rednet.open(name) end
                elseif rednet.isOpen(name) then
                    rednet.close(name)
                end
            end)
        end
    end
end

local barRow = nil

local function drawTransfer(title, lines)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    local y = drawCard(3, lines, colors.lightBlue, colors.white)
    barRow = math.min(y + 1, H - 3)
    footerButtons({ { tag = "Q", label = "Cancel", k = "q" } })
end

local function drawBar(frac)
    if not barRow then return end
    frac = math.max(0, math.min(1, frac))
    local width = W - 4
    local filled = math.floor(width * frac + 0.5)
    term.setCursorPos(3, barRow)
    term.setBackgroundColor(colors.lime)
    term.write(string.rep(" ", filled))
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", width - filled))
    local label = math.floor(frac * 100 + 0.5) .. "%"
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(math.floor((W - #label) / 2) + 1, barRow + 1)
    term.write(label)
end

-- Waits up to timeout seconds for a transfer message from the other computer.
-- want(msg) says whether a message is the one wanted. Returns the message, nil
-- on timeout, or "cancel" when the user presses Q or clicks Cancel.
local function awaitReply(xid, from, timeout, want)
    local timer = os.startTimer(timeout)
    while true do
        local ev, a, b, c = os.pullEventRaw()
        if ev == "rednet_message" then
            if c == C.FILE_PROTO and a == from and type(b) == "table" and b.xid == xid and want(b) then
                os.cancelTimer(timer)
                return b
            elseif c ~= C.FILE_PROTO or a ~= from then
                handleNet(a, b, c)
            end
        elseif ev == "timer" and a == timer then
            return nil
        elseif (ev == "key" and a == keys.q) or (ev == "mouse_click" and hitButton(b, c) == "q") then
            os.cancelTimer(timer)
            return "cancel"
        elseif ev == "term_resize" then
            W, H = term.getSize()
        end
    end
end

-- Returns true and a note, or false and the reason it failed.
local function transmit(id, peerName, name, data, sum)
    local xid = os.getComputerID() .. "-" .. os.epoch("utc")
    local chunks = math.ceil(#data / C.CHUNK)
    local function send(m)
        m.xid = xid
        pcall(rednet.send, id, m, C.FILE_PROTO)
    end
    local function isCancel(m) return m.type == "cancel" or m.type == "decline" end

    drawTransfer("Send file", {
        name .. " (" .. fmtSize(#data) .. ")",
        "To: " .. peerName,
        "Waiting for them to accept...",
    })
    send({ type = "offer", name = name, size = #data, chunk = C.CHUNK, chunks = chunks, sum = sum, from = myName })
    local r = awaitReply(xid, id, 60, function(m) return m.type == "accept" or isCancel(m) end)
    if r == "cancel" then send({ type = "cancel" }) return false, "Cancelled." end
    if not r then
        send({ type = "cancel" })
        return false, peerName .. " did not answer in time."
    end
    if r.type ~= "accept" then return false, tostring(r.why or (peerName .. " declined.")) end

    drawTransfer("Send file", {
        name .. " (" .. fmtSize(#data) .. ")",
        "To: " .. peerName,
        "Sending...",
    })
    drawBar(0)
    for n = 1, chunks do
        local piece = data:sub((n - 1) * C.CHUNK + 1, n * C.CHUNK)
        local tries = 0
        while true do
            send({ type = "chunk", n = n, data = piece })
            local a = awaitReply(xid, id, 3, function(m) return isCancel(m) or (m.type == "ack" and m.n == n) end)
            if a == "cancel" then send({ type = "cancel" }) return false, "Cancelled." end
            if type(a) == "table" then
                if a.type == "ack" then break end
                return false, peerName .. " cancelled the transfer."
            end
            tries = tries + 1
            if tries >= 5 then return false, "Lost contact with " .. peerName .. "." end
        end
        drawBar(n / chunks)
    end

    send({ type = "done" })
    local fin = awaitReply(xid, id, 30, function(m) return m.type == "result" or isCancel(m) end)
    if fin == "cancel" then return false, "Cancelled." end
    if type(fin) ~= "table" then return false, "No confirmation from " .. peerName .. "." end
    if fin.type == "result" and fin.ok then
        return true, "Sent " .. name .. " to " .. peerName .. "."
    end
    return false, tostring(fin.why or "The other computer cancelled.")
end

local function sendFile(id, peerName, given)
    local path = given or ask("Send file", { "Send a file to " .. peerName .. ".", "Path of the file:" })
    if not path then return end
    path = fs.combine("", path)
    if not fs.exists(path) or fs.isDir(path) then
        showMessage("Send file", { "No such file:", path }, colors.red)
        return
    end
    C.au.log("file", "sending " .. path .. " to #" .. tostring(id))
    local size = fs.getSize(path)
    if size == 0 then
        showMessage("Send file", { "That file is empty." }, colors.red)
        return
    elseif size > C.MAX_FILE then
        showMessage("Send file", { "Files can be up to " .. fmtSize(C.MAX_FILE) .. "." }, colors.red)
        return
    end

    local wireless, wired = modemKinds()
    if not wireless and not wired then
        showMessage("Send file", { "No modem found." }, colors.red)
        return
    end
    local mode = "auto"
    if wireless and wired then
        local pick = pickMenu("Send over", { "Any link (wireless and cable)", "Wireless only", "Cable only" })
        if not pick then return end
        mode = ({ "auto", "wireless", "cable" })[pick]
    end

    local f = fs.open(path, "rb")
    if not f then
        showMessage("Send file", { "Cannot read " .. path .. "." }, colors.red)
        return
    end
    local data = f.readAll() or ""
    f.close()

    showBusy("Send file", "Preparing " .. fs.getName(path) .. "...")
    local sum = checksum(data)
    setLink(mode)
    local ok, good, text = pcall(transmit, id, peerName, fs.getName(path), data, sum)
    setLink("auto")
    if not ok then good, text = false, tostring(good) end
    showMessage("Send file", { text }, good and colors.lime or colors.red)
end

-- Returns true and a note, or false and the reason it failed.
local function receiveFile(offer)
    local function send(m)
        m.xid = offer.xid
        pcall(rednet.send, offer.from, m, C.FILE_PROTO)
    end

    if offer.size + 512 > fs.getFreeSpace("") then
        send({ type = "decline", why = "Not enough free space on the other computer." })
        return false, "Not enough free space for " .. fmtSize(offer.size) .. "."
    end

    local name = fs.getName(offer.name):gsub("[^%w%._%- ]", "_")
    if name == "" or name == "." or name == ".." then name = "file" end
    fs.makeDir("received")
    local base, ext = name:match("^(.*)(%.[^%.]*)$")
    if not base then base, ext = name, "" end
    local target = fs.combine("received", name)
    local copy = 1
    while fs.exists(target) do
        target = fs.combine("received", base .. "_" .. copy .. ext)
        copy = copy + 1
    end

    local function isCancel(m) return m.type == "cancel" end
    send({ type = "accept" })
    drawTransfer("Receive file", {
        offer.name .. " (" .. fmtSize(offer.size) .. ")",
        "From: " .. offer.who,
        "Saving to " .. target,
    })
    drawBar(0)

    local parts, nextN = {}, 1
    while nextN <= offer.chunks do
        local m = awaitReply(offer.xid, offer.from, 15, function(x)
            return x.type == "chunk" or isCancel(x)
        end)
        if m == "cancel" then send({ type = "cancel" }) return false, "Cancelled." end
        if not m then return false, "Timed out. " .. offer.who .. " stopped sending." end
        if m.type == "cancel" then return false, offer.who .. " cancelled the transfer." end
        if m.n == nextN and type(m.data) == "string" then
            parts[nextN] = m.data
            send({ type = "ack", n = nextN })
            nextN = nextN + 1
            drawBar((nextN - 1) / offer.chunks)
        elseif type(m.n) == "number" and m.n < nextN then
            send({ type = "ack", n = m.n })  -- the sender missed an earlier ack
        end
    end

    awaitReply(offer.xid, offer.from, 5, function(x) return x.type == "done" or isCancel(x) end)

    local data = table.concat(parts)
    if #data ~= offer.size or checksum(data) ~= offer.sum then
        send({ type = "result", ok = false, why = "The file arrived damaged. Try again." })
        return false, "The file arrived damaged. Nothing was saved."
    end
    local f = fs.open(target, "wb")
    if not f then
        send({ type = "result", ok = false, why = "Cannot write the file." })
        return false, "Cannot write " .. target .. "."
    end
    f.write(data)
    f.close()
    send({ type = "result", ok = true })
    C.au.log("file", "received " .. target .. " from " .. tostring(offer.who) .. " (#" .. tostring(offer.from) .. ")")
    return true, "Saved " .. target .. " (" .. fmtSize(#data) .. ")."
end

local function inboxApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Accept", k = "enter" },
        { tag = "D", label = "Decline", k = "d" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local first = true

    local function accept(o)
        local ok, good, text = pcall(receiveFile, o)
        if not ok then good, text = false, tostring(good) end
        showMessage("Receive file", { text }, good and colors.lime or colors.red)
    end

    while true do
        pruneOffers()
        if #net.offers == 0 then
            if first then showMessage("Incoming files", { "No incoming files." }, colors.yellow) end
            return
        end
        first = false
        local entries = {}
        for n, o in ipairs(net.offers) do
            entries[n] = { label = o.name .. " (" .. fmtSize(o.size) .. ") from " .. o.who }
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Incoming files", entries, sel, top, buttons)

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            accept(table.remove(net.offers, sel))
        elseif i.k == "d" then
            local o = table.remove(net.offers, sel)
            pcall(rednet.send, o.from, { type = "decline", xid = o.xid, why = "They declined." }, C.FILE_PROTO)
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            accept(table.remove(net.offers, sel))
        end
    end
end

local function messengerApp()
    if not openModems() then
        showMessage("Messenger", {
            "No modem found.",
            "Attach a modem to this computer",
            "and open the Messenger again.",
        }, colors.red)
        return
    end

    discover(1.5)
    local sel, top = 1, 1
    -- Rename still works with the N key. Buttons that do not fit are skipped.
    local buttons = {
        { tag = "Ent", label = "Chat", k = "enter" },
        { tag = "F", label = "Send", k = "f" },
        { tag = "I", label = "Files", k = "i" },
        { tag = "R", label = "Scan", k = "r" },
        { tag = "Q", label = "Back", k = "q" },
        { tag = "N", label = "Name", k = "n" },
    }

    local function openEntry(e)
        if e.files then inboxApp() else chat(e) end
    end

    while true do
        local entries = { { key = "all", name = "Everyone", label = "Everyone (broadcast)" } }
        pruneOffers()
        if #net.offers > 0 then
            table.insert(entries, { files = true, label = "Incoming files (" .. #net.offers .. ")", color = colors.lime })
        end
        local ids = {}
        for id in pairs(net.peers) do table.insert(ids, id) end
        table.sort(ids, function(x, y)
            return net.peers[x].name:lower() < net.peers[y].name:lower()
        end)
        for _, id in ipairs(ids) do
            table.insert(entries, { key = id, id = id, name = net.peers[id].name, label = net.peers[id].name })
        end
        for _, e in ipairs(entries) do
            local n = net.unread[e.key]
            if n and n > 0 then e.label = e.label .. " (" .. n .. ")" end
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)

        drawList("Messenger: " .. myName, entries, sel, top, buttons)

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            openEntry(entries[sel])
        elseif i.k == "i" then
            inboxApp()
        elseif i.k == "f" then
            local e = entries[sel]
            if e and e.id then
                sendFile(e.id, e.name)
            else
                showMessage("Send file", { "Select a computer in the list first." }, colors.yellow)
            end
        elseif i.k == "r" then
            discover(1.5)
        elseif i.k == "n" then
            local name = ask("Rename", { "New name:" }, myName)
            if name then
                myName = name:sub(1, 20)
                saveName(myName)
            end
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            openEntry(entries[sel])
        end
    end
end

-- ── Disk and ROM manager ─────────────────────────────────────────────────────

local function usage(path)
    local ok, free = pcall(fs.getFreeSpace, path)
    if not ok then return "" end
    local ok2, cap = pcall(fs.getCapacity, path)
    if ok2 and type(cap) == "number" then
        return fmtSize(cap - free) .. " used / " .. fmtSize(cap)
    end
    return fmtSize(free) .. " free"
end

local function driveMenu(drive, root)
    local choice = pickMenu("Disk: " .. drive, {
        "Set label",
        "Eject disk",
        "Format (erase everything)",
        "Make bootable (copy startup.lua)",
    })

    if choice == 1 then
        local text = ask("Set label", { "New label:" }, disk.getLabel(drive))
        if text then
            local ok, err = pcall(disk.setLabel, drive, text)
            if not ok then showMessage("Set label", { tostring(err) }, colors.red) end
        end

    elseif choice == 2 then
        pcall(disk.eject, drive)
        return "exit"

    elseif choice == 3 then
        if confirm({ "Erase everything on this disk?", "This cannot be undone." }) then
            local count = 0
            for _, name in ipairs(fs.list(root)) do
                if pcall(fs.delete, fs.combine(root, name)) then count = count + 1 end
            end
            showMessage("Format", { "Deleted " .. count .. " items." }, colors.lime)
        end

    elseif choice == 4 then
        if not fs.exists("startup.lua") then
            showMessage("Make bootable", { "startup.lua not found on this computer." }, colors.red)
        else
            local dest = fs.combine(root, "startup.lua")
            if fs.exists(dest) then pcall(fs.delete, dest) end
            local ok, err = pcall(fs.copy, "startup.lua", dest)
            if ok then
                showMessage("Make bootable", { "Copied startup.lua to the disk." }, colors.lime)
            else
                showMessage("Make bootable", { tostring(err) }, colors.red)
            end
        end
    end
end

-- File browser for one location (computer, ROM, or a disk).
local function browse(root, drive)
    root = fs.combine(root, "")
    local path = root
    local sel, top = 1, 1

    local buttons = { { tag = "Ent", label = "Open", k = "enter" } }
    if drive then
        table.insert(buttons, { tag = "M", label = "Menu", k = "m" })
    end
    table.insert(buttons, { tag = "C", label = "Copy", k = "c" })
    table.insert(buttons, { tag = "D", label = "Del", k = "d" })
    table.insert(buttons, { tag = "N", label = "New", k = "n" })
    table.insert(buttons, { tag = "Q", label = "Up", k = "q" })

    local function goUp()
        if path == root then return true end
        path = fs.getDir(path)
        sel, top = 1, 1
        return false
    end

    local function activate(item)
        if not item then return end
        if item.isUp then
            goUp()
        elseif item.isDir then
            path = item.full
            sel, top = 1, 1
        else
            resetTerm()
            term.clear()
            term.setCursorPos(1, 1)
            pcall(shell.run, "edit", item.full)
            resetTerm()
            W, H = term.getSize()
        end
    end

    while true do
        if not fs.exists(path) or not fs.isDir(path) then
            showMessage("Disks and ROM", { "This location is no longer available." }, colors.red)
            return
        end

        local dirs, files = {}, {}
        for _, name in ipairs(fs.list(path)) do
            local full = fs.combine(path, name)
            if fs.isDir(full) then
                table.insert(dirs, { name = name, full = full, isDir = true })
            else
                table.insert(files, { name = name, full = full })
            end
        end
        local byName = function(x, y) return x.name:lower() < y.name:lower() end
        table.sort(dirs, byName)
        table.sort(files, byName)

        local items, entries = {}, {}
        if path ~= root then
            table.insert(items, { isUp = true })
            table.insert(entries, { label = ".. (up)", color = colors.gray })
        end
        for _, d in ipairs(dirs) do
            table.insert(items, d)
            table.insert(entries, { label = "[D] " .. d.name, color = colors.cyan })
        end
        for _, f in ipairs(files) do
            table.insert(items, f)
            table.insert(entries, { label = "    " .. f.name .. "  " .. fmtSize(fs.getSize(f.full)) })
        end
        local shown = entries
        if #entries == 0 then
            shown = { { label = "(empty)", color = colors.gray } }
        end

        if sel > #items then sel = math.max(1, #items) end
        top = clampTop(sel, top)

        local title = "/" .. path
        if fs.isReadOnly(path) then
            title = title .. "  read-only"
        else
            title = title .. "  free " .. fmtSize(fs.getFreeSpace(path))
        end
        drawList(title, shown, sel, top, buttons)

        local i = readInput() or {}
        local item = items[sel]
        local real = item and not item.isUp
        local k = i.k

        if k == "up" and sel > 1 then
            sel = sel - 1
        elseif k == "down" and sel < #items then
            sel = sel + 1
        elseif k == "enter" then
            activate(item)
        elseif k == "q" or k == "backspace" then
            if goUp() then return end
        elseif k == "c" and real then
            local dest = ask("Copy", {
                "Copy " .. item.full .. " to:",
                "Use a disk mount path to copy to a disk.",
            }, item.full)
            if dest then
                local go = true
                if fs.exists(dest) then
                    go = confirm({ dest .. " exists.", "Replace it?" })
                    if go then pcall(fs.delete, dest) end
                end
                if go then
                    local ok, err = pcall(fs.copy, item.full, dest)
                    if ok then
                        showMessage("Copy", { "Copied to " .. dest .. "." }, colors.lime)
                    else
                        showMessage("Copy", { tostring(err) }, colors.red)
                    end
                end
            end
        elseif k == "d" and real then
            if fs.isReadOnly(item.full) then
                showMessage("Delete", { "This location is read-only." }, colors.red)
            elseif confirm({ "Delete " .. item.full .. "?" }) then
                local ok, err = pcall(fs.delete, item.full)
                if not ok then showMessage("Delete", { tostring(err) }, colors.red) end
            end
        elseif k == "n" then
            if fs.isReadOnly(path) then
                showMessage("New folder", { "This location is read-only." }, colors.red)
            else
                local name = ask("New folder", { "Folder name:" })
                if name then
                    local ok, err = pcall(fs.makeDir, fs.combine(path, name))
                    if not ok then showMessage("New folder", { tostring(err) }, colors.red) end
                end
            end
        elseif k == "m" and drive then
            if driveMenu(drive, root) == "exit" then return end
        elseif i.click and i.y >= 2 and i.y <= H - 1 and items[top + i.y - 2] then
            sel = top + i.y - 2
            activate(items[sel])
        elseif i.scroll then
            sel = math.max(1, math.min(#items, sel + i.scroll))
        end
    end
end

local function diskApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Open", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    while true do
        local entries = {
            { label = "Computer storage  " .. usage(""), path = "" },
            { label = "ROM (read-only)", path = "rom", color = colors.yellow },
        }
        for _, name in ipairs(peripheral.getNames()) do
            if peripheral.getType(name) == "drive" then
                if disk.isPresent(name) then
                    if disk.hasData(name) then
                        local mount = disk.getMountPath(name)
                        local label = disk.getLabel(name) or "unlabeled"
                        table.insert(entries, {
                            label = name .. ": " .. label .. "  " .. usage(mount),
                            path = mount,
                            drive = name,
                            color = colors.cyan,
                        })
                    else
                        table.insert(entries, {
                            label = name .. ": audio disk",
                            note = "Audio disks hold no files.",
                            color = colors.gray,
                        })
                    end
                else
                    table.insert(entries, {
                        label = name .. ": no disk",
                        note = "No disk in this drive.",
                        color = colors.gray,
                    })
                end
            end
        end

        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Disks and ROM", entries, sel, top, buttons)

        local function open(e)
            if e.path then
                browse(e.path, e.drive)
            else
                showMessage("Disks and ROM", { e.note }, colors.yellow)
            end
        end

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            open(entries[sel])
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            open(entries[sel])
        end
        -- Disk and peripheral events fall through and redraw the list.
    end
end

-- ── Input test ───────────────────────────────────────────────────────────────

-- Shows every raw event. Use it to check which keys and clicks reach the OS.
-- Leave with Ctrl+T or the Exit button.
local function inputTestApp()
    local log = {}
    while true do
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        header("Input Test")
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        local visible = H - 2
        local start = math.max(1, #log - visible + 1)
        for n = start, #log do
            term.setCursorPos(1, 2 + n - start)
            term.write(log[n]:sub(1, W))
        end
        footerButtons({ { tag = "", label = "Exit (or Ctrl+T)", k = "exit" } })

        local ev, a, b, c = os.pullEventRaw()
        if ev == "terminate" then return end
        if ev == "mouse_click" and hitButton(b, c) == "exit" then return end
        if ev ~= "timer" and ev ~= "prismarine_tick" then
            local line = ev .. " " .. tostring(a) .. " " .. tostring(b) .. " " .. tostring(c)
            if ev == "key" then line = line .. " (" .. tostring(keys.getName(a)) .. ")" end
            table.insert(log, line)
        end
    end
end

-- ── Main menu ────────────────────────────────────────────────────────────────

-- ── Secure boot, update, settings, others ───────────────────────────────────

-- ── Boot screen and logo studio ──────────────────────────────────────────────
-- These draw with Pixelbox on top of a reprogrammed 16 color palette, so the
-- gradients are smooth. The palette is always put back before the normal UI.

-- Sets up a full screen pixel scene with the logo centered in it. reserve is
-- the number of text rows kept below the logo. Returns nil on a tiny screen.
local function newScene(reserve, art)
    -- Loading screens always use Pixelbox_Lite, whichever UI engine is picked.
    if not gfx.pb then return nil end
    local pw, ph = W * 2, H * 3
    local ratio = art and (art.w * 6 / (art.r * 9)) or (348 / 72)
    local dw = math.min(98, pw - 4, math.floor((H - reserve) * 3 * ratio))
    if dw < 36 then return nil end
    local logo = buildLogo(dw, art)
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
-- name (optional) shows that word as the logo instead of PRISMARINE.
function boot.start(fast, name)
    local sc = newScene(5, name and gfx.wordArt(name) or nil)
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

    centerText(sc.tagRow, sc.tag or (settings.osName .. "  v" .. VERSION), P.txt)
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

-- Reads one event the way readInput does, without blocking.
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
    if not fs.exists(C.PB_FILE) then
        showBusy("Pixelbox_Lite", "Downloading Pixelbox_Lite...")
        local ok, err = gfx.download()
        if not ok then
            showMessage("Pixelbox_Lite", { "Download failed.", tostring(err) }, colors.red)
            return false
        end
    end
    showBusy("Pixelbox_Lite", "Loading Pixelbox_Lite...")
    if not gfx.loadPixelbox() then
        showMessage("Pixelbox_Lite", { "Could not load Pixelbox_Lite.", tostring(gfx.err) }, colors.red)
        return false
    end
    pcall(gfx.syncMonitors)
    return true
end

-- Plain text status line for the moments before the boot screen exists.
local function plainStatus(lines)
    resetTerm()
    term.clear()
    local y = math.max(1, math.floor(H / 2) - math.floor(#lines / 2))
    for n, text in ipairs(lines) do
        term.setCursorPos(math.max(1, math.floor((W - #text) / 2) + 1), y + n - 1)
        term.write(text)
    end
end

-- ── UI engine ────────────────────────────────────────────────────────────────
-- Pixelbox_Lite is the only engine. Settings > UI engine downloads and loads it
-- when it is missing (for example after a failed first download).

local eng = {}

function eng.apply()
    settings.uiEngine = "Pixelbox_Lite"
    settings.graphics = true
    saveSettings()
end

function eng.switch()
    if gfx.pb then return end
    if not ensureGraphics() then return end
    eng.apply()
    restorePalette()
end

-- Live preview of the logo. Pick a color and watch the colored half change.
local function logoStudio()
    if not gfx.pb then
        showMessage("Logo color", {
            "Pixelbox_Lite is not loaded.",
            "Pick Pixelbox_Lite under UI engine in Settings to download it.",
        }, colors.yellow)
        return
    end
    local sc = newScene(4)
    if not sc then
        showMessage("Logo color", { "This screen is too small for the preview." }, colors.yellow)
        return
    end

    local original = settings.logoColor
    local count = #C.LOGO_COLORS
    local _, hexNow = parseHex(settings.logoColor)
    local custom = hexNow
    local _, presetIdx = logoPreset(settings.logoColor)
    local idx = presetIdx or (count + 1)
    local saved = false

    local function apply()
        if idx <= count then
            settings.logoColor = C.LOGO_COLORS[idx].name
        elseif custom then
            settings.logoColor = custom
        end
    end
    local function label()
        if idx <= count then return C.LOGO_COLORS[idx].name end
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
    if not gfx.pb then
        showMessage("Boot screen", {
            "Pixelbox_Lite is not loaded.",
            "Pick Pixelbox_Lite under UI engine in Settings to download it.",
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
        boot.stage(sc, "Opening network", 0.45)
        boot.stage(sc, "Checking secure boot", 0.70)
        boot.stage(sc, "Scanning programs", 0.90)
        boot.stage(sc, "Starting desktop", 1.00)
        boot.finish(sc)
    end)
    if not ok then
        boot.abort()
        showMessage("Boot screen", { tostring(err) }, colors.red)
    end
end

local function enrollSecureBoot()
    if loadSecure() then
        showMessage("Secure boot", { "This computer is already enrolled." }, colors.yellow)
        return
    end
    local pw = ask("Enroll in secure boot", { "Choose a password (4 or more characters):" }, nil, "*")
    if not pw then return end
    if #pw < 4 then
        showMessage("Secure boot", { "The password is too short." }, colors.red)
        return
    end
    local again = ask("Enroll in secure boot", { "Repeat the password:" }, nil, "*")
    if again ~= pw then
        showMessage("Secure boot", { "The passwords do not match." }, colors.red)
        return
    end
    showBusy("Secure boot", "Hashing " .. SELF .. "...")
    local fileHash = hashFile(SELF)
    if not fileHash then
        showMessage("Secure boot", { "Cannot read " .. SELF .. "." }, colors.red)
        return
    end
    local salt = newSalt()
    saveSecure({ fileHash = fileHash, salt = salt, passHash = sha256(salt .. pw) })
    showMessage("Secure boot", {
        "Enrolled.",
        "Each boot now checks " .. SELF,
        "and asks for the password.",
    }, colors.lime)
end

local function unenrollSecureBoot()
    local data = loadSecure()
    if not data then
        showMessage("Secure boot", { "This computer is not enrolled." }, colors.yellow)
        return
    end
    local pw = ask("Un-enroll from secure boot", { "Enter the password:" }, nil, "*")
    if not pw then return end
    if not passwordMatches(data, pw) then
        showMessage("Secure boot", { "Wrong password." }, colors.red)
        return
    end
    fs.delete(C.SECURE_FILE)
    showMessage("Secure boot", { "Un-enrolled. Boot no longer asks for a password." }, colors.lime)
end

-- Versions live in the update repo as startup_v<number>.lua, for example
-- startup_v9.lua. Upload a new file with a bigger number to publish an update.
local function repoParts()
    local repo, branch = settings.updateRepo:match("^([^@]+)@?(.*)$")
    if not branch or branch == "" then branch = "main" end
    return repo, branch
end

-- prefix is the file name before the number: "startup_v" or "p.shell_v".
local function versionUrl(n, prefix)
    local repo, branch = repoParts()
    return "https://raw.githubusercontent.com/" .. repo .. "/" .. branch .. "/" .. (prefix or "startup_v") .. n .. ".lua"
end

-- Returns the body, or nil and a reason.
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

-- Finds every startup_v<number>.lua in the repo, newest first. It asks GitHub
-- for the file list. If that is blocked or rate limited it tries each number.
local function listVersions(prefix)
    prefix = prefix or "startup_v"
    local pattern = "^" .. (prefix:gsub("%p", "%%%0")) .. "(%d+)%.lua$"
    local repo, branch = repoParts()
    local found = {}
    local body = httpGet("https://api.github.com/repos/" .. repo .. "/contents/?ref=" .. branch)
    local data = body and textutils.unserialiseJSON(body)
    if type(data) == "table" then
        for _, f in ipairs(data) do
            local n = type(f) == "table" and type(f.name) == "string" and f.name:match(pattern)
            if n then table.insert(found, tonumber(n)) end
        end
    end
    if #found == 0 then
        for n = 1, 40 do
            showBusy("Update", "Looking for versions... " .. n .. " of 40")
            if urlExists(versionUrl(n, prefix)) then table.insert(found, n) end
        end
    end
    if #found == 0 then return nil, "No " .. prefix .. "<number>.lua files in " .. repo end
    table.sort(found, function(x, y) return x > y end)
    return found
end

local function installVersion(n, data)
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

    -- Refuse a file that does not compile, so a bad download cannot break the OS.
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

    if data then
        showBusy("Update", "Updating secure boot hash...")
        data.fileHash = hashFile(SELF) or data.fileHash
        saveSecure(data)
    end

    if confirm({ "Installed version " .. newVersion .. ".", "Reboot now?" }) then
        os.reboot()
    end
end

local function updateApp()
    local data = loadSecure()
    if data then
        local pw = ask("Update", { "Secure boot is on.", "Enter the password to update:" }, nil, "*")
        if not pw then return end
        if not passwordMatches(data, pw) then
            showMessage("Update", { "Wrong password." }, colors.red)
            return
        end
    end

    if not http then
        showMessage("Update", { "HTTP is disabled on this server." }, colors.red)
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
        installVersion(newest, data)
    elseif choice == 2 then
        local labels = {}
        for i, n in ipairs(versions) do
            labels[i] = "Version " .. n .. (n == cur and "  (installed)" or "")
        end
        local pick = pickMenu("Choose a version", labels)
        if pick then installVersion(versions[pick], data) end
    end
end

local function aboutApp()
    local free = fs.getFreeSpace("")
    local lines = {
        settings.osName .. " version " .. VERSION,
        "Computer ID: " .. os.getComputerID(),
        "Label: " .. (os.getComputerLabel() or "none"),
        "Messenger name: " .. myName,
        "Running file: " .. SELF,
        "Free space: " .. fmtSize(free),
        "Secure boot: " .. (loadSecure() and "enrolled" or "not enrolled"),
        "Update repo: " .. settings.updateRepo,
        "HTTP: " .. (http and "enabled" or "disabled"),
        "Private messages: " .. (settings.netKey ~= "" and "passphrase set" or "no passphrase")
            .. ", denied " .. C.cr.denied,
        "Activity reports: " .. (settings.audit and "on" or "off"),
        "Pixelbox_Lite: " .. (gfx.pb and "loaded" or ("not loaded" .. (gfx.err and (" (" .. gfx.err .. ")") or ""))),
        "Monitors mirrored: " .. #gfx.mirrors,
        "Monitors on dashboard: " .. #gfx.dashes,
    }
    showMessage("About", lines)
end

local function settingsApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Change", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    -- Pixel sets the text scale to 0.5, which gives Advanced Monitors their
    -- full pixel resolution. Plain monitors fall back to Auto.
    local MON_SCALES = { "Auto", "Pixel", "0.5", "1", "1.5", "2", "2.5", "3", "3.5", "4", "4.5", "5" }

    local function indexOf(list, value)
        for i, v in ipairs(list) do
            if v == value then return i end
        end
        return 1
    end

    local function chooseColor(title, current)
        local names = {}
        for n, c in ipairs(C.COLOR_CHOICES) do names[n] = c.name end
        local idx = pickMenu(title, names)
        if idx then return C.COLOR_CHOICES[idx].name end
        return current
    end

    local function change(n)
        if n == 1 then
            local v = ask("OS name", { "New OS name:" }, settings.osName)
            if v then settings.osName = v:sub(1, 20) end
        elseif n == 2 then
            settings.barColor = chooseColor("Top bar color", settings.barColor)
        elseif n == 3 then
            settings.highlight = chooseColor("Highlight color", settings.highlight)
        elseif n == 4 then
            local modes = { "Both", "Real", "Game", "Off" }
            local idx = pickMenu("Clock", modes)
            if idx then settings.clock = modes[idx] end
        elseif n == 5 then
            settings.hour24 = not settings.hour24
        elseif n == 6 then
            local v = ask("Messenger name", { "New messenger name:" }, myName)
            if v then
                myName = v:sub(1, 20)
                saveName(myName)
            end
        elseif n == 7 then
            settings.showRom = not settings.showRom
        elseif n == 8 then
            local v = ask("Update repo", {
                "GitHub repo as owner/name.",
                "Add @branch for another branch.",
                "Files must be named startup_v<number>.lua",
            }, settings.updateRepo)
            if v then
                if v:match("^[%w%-%._]+/[%w%-%._]+@?[%w%-%._/]*$") then
                    settings.updateRepo = v
                else
                    showMessage("Settings", { "That is not owner/name." }, colors.red)
                end
            end
        elseif n == 9 then
            logoStudio()
        elseif n == 10 then
            if gfx.pb then
                showMessage("UI engine", { "Pixelbox_Lite is loaded.", "It is the only UI engine." }, colors.lightBlue)
            else
                eng.switch()
            end
        elseif n == 11 then
            settings.bootAnim = not settings.bootAnim
        elseif n == 12 then
            local modes = { "Off", "Corner", "Large" }
            local idx = pickMenu("Menu logo", modes, indexOf(modes, settings.menuLogo))
            if idx then settings.menuLogo = modes[idx] end
        elseif n == 13 then
            local modes = { "Mirror", "Dashboard", "Off" }
            local idx = pickMenu("Monitor mode", modes, indexOf(modes, settings.monMode))
            if idx then
                -- The dashboard is drawn with Pixelbox_Lite.
                if modes[idx] ~= "Dashboard" or ensureGraphics() then
                    settings.monMode = modes[idx]
                    gfx.syncMonitors()
                end
            end
        elseif n == 14 then
            local idx = pickMenu("Monitor text scale", MON_SCALES, indexOf(MON_SCALES, settings.monScale))
            if idx then
                settings.monScale = MON_SCALES[idx]
                gfx.refitAll()
            end
        elseif n == 15 then
            local tNames = {}
            for i, t in ipairs(gfx.themes) do tNames[i] = t.name end
            local idx = pickMenu("Theme", tNames, indexOf(tNames, settings.theme))
            if idx then
                gfx.applyTheme(tNames[idx])
            end
        elseif n == 16 then
            previewBoot()
        elseif n == 17 then
            C.cr.menu()
        elseif n == 18 then
            settings.audit = not settings.audit
            if settings.audit then C.au.log("presence", "activity reports turned on") end
        elseif n == 19 then
            if confirm({ "Reset all settings to defaults?" }) then
                -- The network key stays. It belongs to the network, not to the look.
                local key = settings.netKey
                resetSettings()
                settings.netKey = key
                restorePalette()
                gfx.syncMonitors()
                gfx.refitAll()
            end
        end
        saveSettings()
    end

    while true do
        local entries = {
            { label = "OS name: " .. settings.osName },
            { label = "Top bar color: " .. settings.barColor, swatch = colorValue(settings.barColor, colors.blue) },
            { label = "Highlight color: " .. settings.highlight, swatch = colorValue(settings.highlight, colors.lightBlue) },
            { label = "Clock: " .. settings.clock },
            { label = "Time format: " .. (settings.hour24 and "24 hour" or "12 hour") },
            { label = "Messenger name: " .. myName },
            { label = "Show ROM programs at start: " .. (settings.showRom and "yes" or "no") },
            { label = "Update repo: " .. settings.updateRepo },
            { label = "Logo color (lower half): " .. logoName() },
            { label = "UI engine: Pixelbox_Lite" .. (gfx.pb and "" or " (not loaded)") },
            { label = "Boot animation: " .. (settings.bootAnim and "on" or "off") },
            { label = "Menu logo: " .. tostring(settings.menuLogo) },
            { label = "Monitor mode: " .. tostring(settings.monMode) },
            { label = "Monitor text scale: " .. settings.monScale },
            { label = "Theme: " .. tostring(settings.theme) },
            { label = "Preview boot screen" },
            { label = "Network passphrase: " .. (settings.netKey ~= "" and "set" or "not set") },
            { label = "Activity reports: " .. (settings.audit and "on" or "off") },
            { label = "Reset all settings" },
        }
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
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            change(sel)
        end
    end
end

local function othersApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Open", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }

    local function run(n)
        if n == 1 then
            local data = loadSecure()
            if data then
                showMessage("Secure boot", {
                    "Enrolled.",
                    "File: " .. SELF,
                    "Hash: " .. data.fileHash:sub(1, 24) .. "...",
                }, colors.lime)
            else
                showMessage("Secure boot", { "Not enrolled." }, colors.yellow)
            end
        elseif n == 2 then
            enrollSecureBoot()
        elseif n == 3 then
            unenrollSecureBoot()
        elseif n == 4 then
            updateApp()
        elseif n == 5 then
            inputTestApp()
        elseif n == 6 then
            aboutApp()
        end
    end

    while true do
        local enrolled = loadSecure() ~= nil
        local entries = {
            { label = "Secure boot status: " .. (enrolled and "enrolled" or "not enrolled"),
              color = enrolled and colors.lime or colors.gray },
            { label = "Enroll in secure boot" },
            { label = "Un-enroll from secure boot" },
            { label = "Update / choose version" },
            { label = "Input test" },
            { label = "About" },
        }
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Others", entries, sel, top, buttons)

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            run(sel)
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            run(sel)
        end
    end
end

-- Prismarine Shell is not shipped inside this file. The first time someone
-- opens Shell, the newest p.shell_v<number>.lua is downloaded from the update
-- repo into a hidden folder. The shell updates itself from then on.
C.SHELL_FILE = ".prismshell/pshell.lua"
C.SHELL_PREFIX = "p.shell_v"

-- Returns the path to run, plus an optional banner. Returns nil to stay in the menu.
local function ensureShell()
    if fs.exists(C.SHELL_FILE) and not fs.isDir(C.SHELL_FILE) then
        return "/" .. C.SHELL_FILE
    end

    local why
    if not http then
        why = "HTTP is disabled on this server."
    else
        showBusy("Shell", "Downloading Prismarine Shell...")
        local versions, err = listVersions(C.SHELL_PREFIX)
        if not versions then
            why = err
        else
            local body, err2 = httpGet(versionUrl(versions[1], C.SHELL_PREFIX) .. "?cb=" .. os.epoch("utc"))
            if not body then
                why = err2
            else
                local fn, syntaxErr = load(body, "=pshell")
                if not fn then
                    why = "The downloaded file has a syntax error: " .. tostring(syntaxErr)
                else
                    fs.makeDir(".prismshell")
                    local f = fs.open(C.SHELL_FILE, "wb")
                    if f then
                        f.write(body)
                        f.close()
                        return "/" .. C.SHELL_FILE
                    end
                    why = "Cannot write " .. C.SHELL_FILE .. "."
                end
            end
        end
    end

    if confirm({
        "Prismarine Shell could not be downloaded.",
        tostring(why),
        "Open the basic shell instead?",
    }) then
        return "shell", "Type exit to return to " .. settings.osName .. "."
    end
    return nil
end

-- The Downloads app is not shipped inside this file either. The first time
-- Download is opened, official_downloads.lua is fetched from the update repo
-- into a hidden folder. The app can update itself from its own menu.
C.DL_FILE = ".prismdl/downloads.lua"
C.DL_REMOTE = "official_downloads.lua"

local function rawUrl(name)
    local repo, branch = repoParts()
    return "https://raw.githubusercontent.com/" .. repo .. "/" .. branch .. "/" .. name
end

-- Downloads the app into DL_FILE. Returns true, or false and a reason.
local function fetchDownloads()
    if not http then return false, "HTTP is disabled on this server." end
    local body, why = httpGet(rawUrl(C.DL_REMOTE) .. "?cb=" .. os.epoch("utc"))
    if not body then return false, tostring(why) end
    local fn, syntaxErr = load(body, "=downloads")
    if not fn then return false, "The downloaded file has a syntax error: " .. tostring(syntaxErr) end
    fs.makeDir(".prismdl")
    local f = fs.open(C.DL_FILE, "wb")
    if not f then return false, "Cannot write " .. C.DL_FILE .. "." end
    f.write(body)
    f.close()
    return true
end

-- ComputerCraft keeps require out of the global table: the shell adds it to
-- each program's own environment. Programs started from here get the same.
local function programEnv(path)
    local env = setmetatable({}, { __index = _G })
    local ok, mod = pcall(dofile, "rom/modules/main/cc/require.lua")
    if ok and type(mod) == "table" and type(mod.make) == "function" then
        local ok2, req, pkg = pcall(mod.make, env, fs.getDir(path))
        if ok2 then env.require, env.package = req, pkg end
    end
    return env
end

local function makeApi()
    return {
        settings = settings, saveSettings = saveSettings,
        header = header, footer = footer, footerButtons = footerButtons,
        drawList = drawList, drawCard = drawCard, clampTop = clampTop,
        ask = ask, confirm = confirm, pickMenu = pickMenu,
        showMessage = showMessage, showBusy = showBusy,
        readInput = readInput, inputFrom = inputFrom, handleNet = handleNet,
        openPrivate = function(sender, msg) return C.cr.openArchive(sender, msg) end,
        audit = function(kind, text) C.au.log(kind, text) end,
        auditLoopback = function(on) C.au.loop = on == true end,
        fmtSize = fmtSize, pad = pad, nowSec = nowSec,
        gfx = gfx, boot = boot, colorValue = colorValue,
        sha256 = sha256, hashFile = hashFile,
        rawUrl = rawUrl, repoParts = repoParts,
        restorePalette = restorePalette,
        size = function() return W, H end,
        resize = function() W, H = term.getSize() end,
        DL_FILE = C.DL_FILE, SELF = SELF,
        SETTINGS_FILE = C.SETTINGS_FILE, SECURE_FILE = C.SECURE_FILE,
    }
end

local function downloadApp()
    if not fs.exists(C.DL_FILE) or fs.isDir(C.DL_FILE) then
        showBusy("Download", "Getting the Downloads app...")
        local ok, why = fetchDownloads()
        if not ok then
            showMessage("Download", {
                "The Downloads app could not be downloaded.",
                tostring(why),
                "Check the update repo in Settings.",
            }, colors.red)
            return
        end
    end
    local fn, err = loadfile(C.DL_FILE, "t", programEnv(C.DL_FILE))
    if not fn then
        showMessage("Download", { "The Downloads app is damaged.", tostring(err), "Open Download again to fetch a new copy." }, colors.red)
        fs.delete(C.DL_FILE)
        return
    end
    local api = makeApi()
    local ok, runErr = pcall(fn, api)
    if not ok then
        showMessage("Download", { "The Downloads app stopped:", tostring(runErr) }, colors.red)
    end
end

C.APPS = {
    messenger = messengerApp,
    download  = downloadApp,
    disks     = diskApp,
    settings  = settingsApp,
    others    = othersApp,
}

local function walk(dir, depth, out, skip)
    if depth > 6 or #out >= 400 then return end
    local ok, names = pcall(fs.list, dir)
    if not ok then return end
    for _, name in ipairs(names) do
        local path = fs.combine(dir, name)
        if fs.isDir(path) then
            if not skip[path] and name:sub(1, 1) ~= "." then
                walk(path, depth + 1, out, skip)
            end
        elseif name:sub(-4) == ".lua" and name ~= "startup.lua" then
            table.insert(out, { label = path:sub(1, -5), path = path })
        end
    end
end

-- ── Programs ─────────────────────────────────────────────────────────────────
-- Manages the apps the player installed: the .lua programs in the main folder
-- tree. Edit opens the editor, Delete removes after asking, Share sends the
-- file to another computer through Messenger. startup.lua, the OS's own hidden
-- folders and the rom are never listed, so they cannot be touched from here.
local function programApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Actions", k = "enter" },
        { tag = "E", label = "Edit", k = "e" },
        { tag = "S", label = "Share", k = "s" },
        { tag = "D", label = "Delete", k = "d" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local function list()
        local out = {}
        walk("", 0, out, { rom = true })
        local keep = {}
        for _, p in ipairs(out) do
            if fs.combine("", p.path) ~= fs.combine("", SELF) then table.insert(keep, p) end
        end
        table.sort(keep, function(a, b) return a.label:lower() < b.label:lower() end)
        return keep
    end

    local function edit(p)
        resetTerm()
        term.clear()
        term.setCursorPos(1, 1)
        pcall(shell.run, "edit", p.path)
        resetTerm()
        W, H = term.getSize()
    end

    local function delete(p)
        if fs.isReadOnly(p.path) then
            showMessage("Delete", { "This location is read-only." }, colors.red)
        elseif confirm({ "Delete " .. p.path .. "?", "This cannot be undone." }) then
            local ok, err = pcall(fs.delete, p.path)
            if not ok then showMessage("Delete", { tostring(err) }, colors.red) end
        end
    end

    local function share(p)
        if not openModems() then
            showMessage("Share", { "No modem found.", "Attach a modem to share programs." }, colors.red)
            return
        end
        showBusy("Share", "Looking for computers...")
        discover(1.5)
        local ids = {}
        for id in pairs(net.peers) do table.insert(ids, id) end
        table.sort(ids, function(x, y) return net.peers[x].name:lower() < net.peers[y].name:lower() end)
        if #ids == 0 then
            showMessage("Share", { "No other computer answered.", "Open Messenger on the other one." }, colors.yellow)
            return
        end
        local names = {}
        for n, id in ipairs(ids) do names[n] = net.peers[id].name end
        local pick = pickMenu("Share " .. fs.getName(p.path) .. " with", names)
        if pick then sendFile(ids[pick], names[pick], p.path) end
    end

    local function actions(p)
        local pick = pickMenu(fs.getName(p.path), { "Edit", "Share via Messenger", "Delete" })
        if pick == 1 then edit(p) elseif pick == 2 then share(p) elseif pick == 3 then delete(p) end
    end

    while true do
        local items = list()
        local entries = {}
        for n, p in ipairs(items) do
            entries[n] = { label = p.path .. "  " .. fmtSize(fs.getSize(p.path)) }
        end
        if #entries == 0 then
            entries[1] = { label = "No installed programs yet. Get some from Download.", color = colors.gray }
        end
        if sel > #items then sel = math.max(1, #items) end
        top = clampTop(sel, top)
        drawList("Programs (" .. #items .. ")", entries, sel, top, buttons)
        local i = readInput() or {}
        local p = items[sel]
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #items then
            sel = sel + 1
        elseif i.k == "enter" and p then actions(p)
        elseif i.k == "e" and p then edit(p)
        elseif i.k == "s" and p then share(p)
        elseif i.k == "d" and p then delete(p)
        elseif i.k == "q" then
            return
        elseif i.scroll then
            sel = math.max(1, math.min(math.max(1, #items), sel + i.scroll))
        elseif i.click and i.y >= 2 and i.y <= H - 1 and items[top + i.y - 2] then
            sel = top + i.y - 2
            actions(items[sel])
        end
    end
end
C.APPS.programs = programApp

local function scan()
    local programs = {}
    walk("", 0, programs, { rom = true })
    table.sort(programs, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    local list = {
        { label = "Shell",             shell = true,      color = colors.cyan },
        { label = "Messenger",         app = "messenger", color = colors.cyan },
        { label = "Download",          app = "download",  color = colors.cyan },
        { label = "Programs",          app = "programs",  color = colors.cyan },
        { label = "Disks and ROM",     app = "disks",     color = colors.cyan },
        { label = "Settings",          app = "settings",  color = colors.cyan },
        { label = "Others",            app = "others",    color = colors.cyan },
    }
    for _, p in ipairs(programs) do table.insert(list, p) end

    if showRom then
        local romPrograms = {}
        walk("rom/programs", 0, romPrograms, {})
        table.sort(romPrograms, function(a, b)
            return a.label:lower() < b.label:lower()
        end)
        for _, p in ipairs(romPrograms) do
            p.label = "[ROM] " .. p.label:sub(#"rom/programs/" + 1)
            p.color = colors.yellow
            table.insert(list, p)
        end
    end

    table.insert(list, { label = "Reboot",   action = "reboot",   color = colors.orange })
    table.insert(list, { label = "Shutdown", action = "shutdown", color = colors.orange })
    return list
end

local function launch(item)
    if item.action == "reboot" then
        C.au.log("power", "reboot")
        os.reboot()
        return
    elseif item.action == "shutdown" then
        C.au.log("power", "shutdown")
        os.shutdown()
        return
    elseif item.app then
        C.au.log("app", "opened " .. tostring(item.label))
        restorePalette()
        local ok, err = pcall(C.APPS[item.app])
        restorePalette()
        resetTerm()
        if not ok then
            showMessage(item.label, { "Error:", tostring(err) }, colors.red)
        end
        return
    end

    if item.shell then
        local path, banner = ensureShell()
        if not path then return end
        item = { label = item.label, path = path, banner = banner, color = item.color }
    end

    -- A program whose first lines contain --@prismarine-api is opened with the
    -- OS helpers (boot screen, graphics, dialogs) instead of the plain shell.
    if item.path and fs.exists(item.path) and not fs.isDir(item.path) then
        local f = fs.open(item.path, "r")
        local head = f and f.read(400)
        if f then f.close() end
        if head and head:find("--@prismarine-api", 1, true) then
            restorePalette()
            local fn, err = loadfile(item.path, "t", programEnv(item.path))
            if not fn then
                showMessage(item.label, { "Cannot start this program.", tostring(err) }, colors.red)
            else
                C.au.log("app", "opened " .. tostring(item.label) .. " (" .. tostring(item.path) .. ")")
                local ok, runErr = pcall(fn, makeApi())
                if not ok then
                    C.au.log("error", tostring(item.label) .. " stopped: " .. tostring(runErr))
                    showMessage(item.label, { "Error:", tostring(runErr) }, colors.red)
                end
            end
            restorePalette()
            resetTerm()
            return
        end
    end

    nativePalette()
    resetTerm()
    term.clear()
    term.setCursorPos(1, 1)
    if item.banner then
        print(item.banner)
        print()
    end

    local result = false
    -- A plain program should not see the heartbeat events.
    gfx.beatOn = false
    local okRun, runErr = pcall(parallel.waitForAny, function()
        result = shell.run(item.path)
    end, backgroundNet)
    gfx.beatOn = true
    if not okRun then error(runErr, 0) end

    if not result then
        print()
        print("Program ended with an error. Press any key.")
        os.pullEvent("key")
    end
    restorePalette()
    resetTerm()
end

-- Keeps a log of errors. The menu restarts after a crash.
local function logError(err)
    C.au.log("error", tostring(err))
    local f = fs.open(C.LOG_FILE, "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M") .. "  " .. tostring(err))
        f.close()
    end
end

local function main()
    openModems()
    C.au.log("boot", "Prismarine OS v" .. VERSION .. " started")
    local items = scan()
    local sel, top = 1, 1
    local pendingOpen = nil   -- a program to open once the menu has let go of the screen
    local function mainButtons()
        return {
            { tag = "Ent", label = "Open", k = "enter" },
            { tag = "R", label = "Refresh", k = "r" },
            { tag = "T", label = showRom and "Hide ROM" or "Show ROM", k = "t" },
        }
    end

    local function view()
        local out = {}
        local unread = unreadTotal()
        for n, item in ipairs(items) do
            local label = item.label
            if item.app == "messenger" and unread > 0 then
                label = label .. " (" .. unread .. ")"
            end
            out[n] = { label = label, color = item.color }
        end
        return out
    end

    local function open(idx)
        launch(items[idx])
        W, H = term.getSize()
        openModems()
        items = scan()
        if sel > #items then sel = #items end
        top = clampTop(sel, top)
    end

    -- Handles one event. Opening a program is only noted (pendingOpen) and done
    -- after the menu has been redrawn.
    local function step(ev, a, b, c)
        C.au.event(ev, a)
        if ev == "rednet_message" then
            handleNet(a, b, c)
        elseif ev == "term_resize" then
            W, H = term.getSize()
            top = clampTop(sel, top)
        elseif ev == "key" or ev == "char" or ev == "mouse_click" or ev == "mouse_scroll" then
            -- Feed the event through the same translation used by every app.
            local i
            if ev == "key" then
                local name = keys.getName(a)
                if name then
                    lastKeyName, lastKeyAt = name, os.epoch("utc")
                    i = { k = name }
                end
            elseif ev == "char" then
                local ch = tostring(a):lower()
                if lastKeyName == ch and os.epoch("utc") - lastKeyAt < 250 then
                    lastKeyName = nil
                else
                    i = { k = ch }
                end
            elseif ev == "mouse_click" then
                local k = hitButton(b, c)
                if k then i = { k = k } else i = { click = true, x = b, y = c } end
            else
                i = { scroll = a }
            end

            i = i or {}
            local k = i.k
            if k == "up" and sel > 1 then
                sel = sel - 1
            elseif k == "down" and sel < #items then
                sel = sel + 1
            elseif k == "pageUp" then
                sel = math.max(1, sel - (H - 2))
            elseif k == "pageDown" then
                sel = math.min(#items, sel + (H - 2))
            elseif k == "home" then
                sel = 1
            elseif k == "end" then
                sel = #items
            elseif k == "r" then
                items = scan()
                if sel > #items then sel = #items end
            elseif k == "t" then
                showRom = not showRom
                items = scan()
                sel, top = 1, 1
            elseif k == "enter" then
                pendingOpen = sel
            elseif i.click and i.y >= 2 and i.y <= H - 1 and items[top + i.y - 2] then
                sel = top + i.y - 2
                pendingOpen = sel
            elseif i.scroll then
                sel = math.max(1, math.min(#items, sel + i.scroll))
            end
            top = clampTop(sel, top)
        end
        -- The terminate event is ignored here, so Ctrl+T does not close the menu.
        -- Heartbeat ticks and other events only cause a redraw.
    end

    local lastClockText, lastDrawAt = nil, 0

    while true do
        drawList(settings.osName, view(), sel, top, mainButtons())
        gfx.menuLogo(#items + 2, H - 2 - #items)
        lastClockText, lastDrawAt = clockText(), os.epoch("utc")
        -- Wait for something worth redrawing. The heartbeat arrives twice a
        -- second and never gets lost, so the clock keeps moving by itself.
        repeat
            local ev, a, b, c = os.pullEventRaw()
            local redraw = true
            if ev == "prismarine_tick" then
                redraw = clockText() ~= lastClockText or os.epoch("utc") - lastDrawAt >= 2000
                if gfx.menuAnimated() then pcall(gfx.menuTick) end
            end
            step(ev, a, b, c)
        until redraw or pendingOpen

        if pendingOpen then
            local idx = pendingOpen
            pendingOpen = nil
            open(idx)
        end
    end
end

-- Secure boot is split in two so the boot screen can show the check running.
-- The check hashes this file. The prompt asks for the password.
local function secureBootCheck(tick, say)
    local data = loadSecure()
    if not data then return nil end

    if say then
        say("Verifying " .. SELF)
    else
        showBusy("Secure boot", "Verifying " .. SELF .. "...")
    end
    local current = hashFile(SELF, tick)
    return {
        data = data,
        current = current,
        intact = current ~= nil and current == data.fileHash,
    }
end

local function secureBootPrompt(res)
    if not res then return end
    local data, current, intact = res.data, res.current, res.intact

    for attempt = 1, 3 do
        local title = intact and "Secure boot" or "Secure boot: file changed"
        local lines = intact and { "Enter the password to boot:" }
            or { SELF .. " changed since enrollment.", "Enter the password to trust it and boot:" }
        local pw = ask(title, lines, nil, "*")
        if pw and passwordMatches(data, pw) then
            C.au.log("secure", "boot password accepted" .. (intact and "" or ", file had changed"))
            if not intact and current then
                data.fileHash = current
                saveSecure(data)
            end
            return
        end
        C.au.log("secure", "wrong boot password, attempt " .. attempt .. " of 3")
        showMessage(title, { "Wrong password. Attempt " .. attempt .. " of 3." }, colors.red)
    end

    os.shutdown()
    while true do os.pullEventRaw() end
end

local function secureBootFailed(err)
    -- A bug in the check must not lock the owner out. Log it and warn.
    logError("secure boot check failed: " .. tostring(err))
    resetTerm()
    showMessage("Secure boot error", {
        tostring(err),
        "",
        "The check did not finish. Booting without it.",
    }, colors.red)
end

-- Makes Pixelbox_Lite ready: downloads it on the first boot, checks it, loads
-- it. This happens whichever UI engine is picked, because the loading screens
-- always use it. Returns true when Pixelbox_Lite is loaded.
local function loadGraphics()
    if not fs.exists(C.PB_FILE) then
        if not http then
            gfx.err = "HTTP is disabled"
            return false
        end
        plainStatus({ settings.osName, "", "First boot: downloading Pixelbox_Lite..." })
        local ok, err = gfx.download()
        if not ok then
            gfx.err = tostring(err)
            showMessage("Pixelbox_Lite", {
                "Could not download Pixelbox_Lite.",
                tostring(err),
                "",
                "Starting without pixel graphics.",
                "Settings > UI engine tries again.",
            }, colors.yellow)
            return false
        end
    end

    plainStatus({ settings.osName, "", "Loading Pixelbox_Lite..." })
    if not gfx.loadPixelbox() then
        if gfx.err ~= "not downloaded" then
            showMessage("Pixelbox_Lite", {
                "Pixelbox_Lite could not be loaded.",
                tostring(gfx.err),
                "",
                "Starting without pixel graphics.",
                "Delete /" .. C.PB_DIR .. " to download it again.",
            }, colors.yellow)
        end
        return false
    end
    -- Monitors were set up before Pixelbox was ready. A saved Dashboard mode
    -- could not start then, so set the monitors up again now.
    pcall(gfx.syncMonitors)
    return true
end

-- The boot sequence. Every step on the boot screen is real work.
-- Returns the secure boot check result (nil when not enrolled).
local function runBoot()
    local ready = loadGraphics()

    local secure = nil
    local enrolled = loadSecure() ~= nil

    local sc = nil
    if ready and settings.bootAnim then sc = boot.start(false) end

    if sc then
        local ok, err = pcall(function()
            boot.stage(sc, "Opening network", 0.30, function() openModems() end)
            boot.stage(sc, enrolled and "Verifying secure boot" or "Secure boot is off", 0.75, function(tick)
                secure = secureBootCheck(tick, function(text) sc.status = text end)
            end)
            boot.stage(sc, "Scanning programs", 0.92, function() scan() end)
            boot.stage(sc, "Starting desktop", 1.00)
            boot.finish(sc)
        end)
        if not ok then
            boot.abort()
            logError("boot screen failed: " .. tostring(err))
            if enrolled and not secure then secure = secureBootCheck(nil, nil) end
        end
    else
        secure = secureBootCheck(nil, nil)
    end

    return secure
end

-- Display first, so everything after it is buffered and mirrored.
local displayOk, displayErr = pcall(gfx.init)
if not displayOk then logError("display setup failed: " .. tostring(displayErr)) end
pcall(restorePalette)

local bootRes
local runOk, runErr = pcall(function() bootRes = runBoot() end)
if not runOk then
    pcall(boot.abort)
    logError("boot failed: " .. tostring(runErr))
    local ok2, res = pcall(secureBootCheck, nil, nil)
    if ok2 then bootRes = res else secureBootFailed(res) end
end

local gateOk, gateErr = pcall(secureBootPrompt, bootRes)
if not gateOk then secureBootFailed(gateErr) end

while true do
    local ok, err = pcall(main)
    if ok then break end
    logError(err)
    pcall(restorePalette)
    resetTerm()
    showMessage(settings.osName .. " error", {
        tostring(err),
        "",
        "Saved to " .. C.LOG_FILE,
    }, colors.red)
end