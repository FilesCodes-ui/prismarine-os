-- Simple OS v4 for CC:Tweaked 1.20.1
-- Save this file as /startup.lua on the computer.
-- Every action has a clickable button and a keyboard shortcut.
-- Errors are shown on screen and saved to /simpleos_error.log.

local W, H = term.getSize()

local PROTO = "simpleos_msg"
local NAME_FILE = ".simpleos_name"
local LOG_FILE = "simpleos_error.log"

local VERSION = "6.0"
local SELF = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "startup.lua"
if not SELF or SELF == "" then SELF = "startup.lua" end

-- ── Settings ─────────────────────────────────────────────────────────────────

local SETTINGS_FILE = ".simpleos_settings"
local SECURE_FILE = ".simpleos_secureboot"

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

local DEFAULT_SETTINGS = {
    osName    = "Simple OS",
    barColor  = "Blue",
    highlight = "Light blue",
    clock     = "Both",
    hour24    = true,
    showRom   = false,
    updateId  = "c2DjWY18",
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

local showRom = settings.showRom

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
local function sha256(msg)
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

local function hashFile(path)
    local data = readFile(path)
    if not data then return nil end
    return sha256(data)
end

local function loadSecure()
    if not fs.exists(SECURE_FILE) then return nil end
    local text = readFile(SECURE_FILE)
    local data = text and textutils.unserialize(text)
    if type(data) == "table" and data.fileHash and data.salt and data.passHash then
        return data
    end
    return nil
end

local function saveSecure(data)
    local f = fs.open(SECURE_FILE, "w")
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

-- ── Network state ────────────────────────────────────────────────────────────

local net = {
    peers   = {},  -- id -> { name = "..." }
    history = {},  -- key ("all" or sender id) -> list of messages
    unread  = {},  -- key -> count
}

local function loadName()
    if fs.exists(NAME_FILE) then
        local f = fs.open(NAME_FILE, "r")
        if f then
            local n = f.readLine()
            f.close()
            if n and n ~= "" then return n end
        end
    end
    return os.getComputerLabel() or ("PC" .. os.getComputerID())
end

local function saveName(n)
    local f = fs.open(NAME_FILE, "w")
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

local function unreadTotal()
    local n = 0
    for _, v in pairs(net.unread) do n = n + v end
    return n
end

local function handleNet(sender, msg, protocol)
    if protocol ~= PROTO or type(msg) ~= "table" then return end
    local name = tostring(msg.name or "Unknown")
    if msg.type == "discover" then
        net.peers[sender] = { name = name }
        pcall(rednet.send, sender, { type = "hello", name = myName }, PROTO)
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

local function header(title)
    local bar = colorValue(settings.barColor, colors.blue)
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(bar)
    term.setTextColor(textOn(bar))
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write(title:sub(1, W - 2))
    local clock = clockText()
    if clock ~= "" and W >= #title + #clock + 4 then
        term.setCursorPos(W - #clock, 1)
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
    local x = 1
    for _, b in ipairs(buttons) do
        local text = " " .. (b.tag ~= "" and (b.tag .. " ") or "") .. b.label .. " "
        if x + #text - 1 > W then break end
        term.setCursorPos(x, H)
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(text)
        table.insert(buttonHits, { x1 = x, x2 = x + #text - 1, k = b.k })
        x = x + #text + 1
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
    for i = 1, H - 2 do
        local idx = top + i - 1
        local e = entries[idx]
        if e then
            term.setCursorPos(1, i + 1)
            if idx == sel then
                local hl = colorValue(settings.highlight, colors.lightBlue)
                term.setBackgroundColor(hl)
                term.setTextColor(textOn(hl))
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(e.color or colors.white)
            end
            term.write(pad(" " .. e.label, W))
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

local function showMessage(title, lines, color)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    for n, l in ipairs(lines) do
        term.setCursorPos(2, n + 2)
        term.write(tostring(l):sub(1, W - 2))
    end
    footerButtons({ { tag = "", label = "Continue (any key)", k = "enter" } })
    waitKey()
end

-- Asks for a line of text. Returns nil when the answer is blank.
local function ask(title, lines, default, mask)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    for n, l in ipairs(lines) do
        term.setCursorPos(2, 2 + n)
        term.write(l:sub(1, W - 2))
    end
    footer("Press Enter to confirm. Leave blank to cancel.")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(2, 3 + #lines)
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
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    for n, l in ipairs(lines) do
        term.setCursorPos(2, 2 + n)
        term.write(l:sub(1, W - 2))
    end
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
    local sel = 1
    local buttons = {
        { tag = "Ent", label = "Select", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    while true do
        drawList(title, entries, sel, 1, buttons)
        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" then
            return sel
        elseif i.k == "q" or i.k == "backspace" then
            return nil
        elseif i.click and i.y >= 2 and entries[i.y - 1] then
            return i.y - 1
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

-- ── Pastebin downloader ──────────────────────────────────────────────────────

local function pastebinApp()
    local input = ask("Pastebin Download", { "Paste code or link:" })
    if not input then return end

    local paste = input:match("([^/%s]+)/?%s*$")
    if not paste or not paste:match("^%w+$") then
        showMessage("Pastebin Download", { "Invalid code or link." }, colors.red)
        return
    end

    local name = ask("Pastebin Download", { "Save as:" }, paste)
    if not name then return end
    if not name:find("%.") then name = name .. ".lua" end

    if fs.isReadOnly(name) then
        showMessage("Pastebin Download", { "Cannot write to " .. name .. "." }, colors.red)
        return
    end

    if fs.exists(name) then
        if not confirm({ name .. " exists.", "Overwrite it?" }) then return end
    end

    if not http then
        showMessage("Pastebin Download", { "HTTP is disabled on this server." }, colors.red)
        return
    end

    term.setBackgroundColor(colors.black)
    term.clear()
    header("Pastebin Download")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 3)
    term.write("Downloading...")

    local url = "https://pastebin.com/raw/" .. paste .. "?cb=" .. os.epoch("utc")
    local resp, err = http.get(url)
    if not resp then
        showMessage("Pastebin Download", { "Download failed.", tostring(err) }, colors.red)
        return
    end
    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()
    if status ~= 200 or not body or body == "" then
        showMessage("Pastebin Download", { "Download failed.", "Status: " .. tostring(status) }, colors.red)
        return
    end

    local f = fs.open(name, "w")
    if not f then
        showMessage("Pastebin Download", { "Cannot open " .. name .. " for writing." }, colors.red)
        return
    end
    f.write(body)
    f.close()
    showMessage("Pastebin Download", { "Saved " .. name, #body .. " bytes." }, colors.lime)
end

-- ── Messenger ────────────────────────────────────────────────────────────────

local function discover(wait)
    net.peers = {}
    pcall(rednet.broadcast, { type = "discover", name = myName }, PROTO)
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
            pcall(rednet.broadcast, { type = "msg", name = myName, text = input, all = true }, PROTO)
        else
            pcall(rednet.send, entry.id, { type = "msg", name = myName, text = input }, PROTO)
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
    local buttons = {
        { tag = "Ent", label = "Chat", k = "enter" },
        { tag = "R", label = "Rescan", k = "r" },
        { tag = "N", label = "Rename", k = "n" },
        { tag = "Q", label = "Back", k = "q" },
    }

    while true do
        local entries = { { key = "all", name = "Everyone", label = "Everyone (broadcast)" } }
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
            chat(entries[sel])
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
            chat(entries[sel])
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
        if ev ~= "timer" then
            local line = ev .. " " .. tostring(a) .. " " .. tostring(b) .. " " .. tostring(c)
            if ev == "key" then line = line .. " (" .. tostring(keys.getName(a)) .. ")" end
            table.insert(log, line)
        end
    end
end

-- ── Main menu ────────────────────────────────────────────────────────────────

-- ── Secure boot, update, settings, others ───────────────────────────────────

local function showBusy(title, text)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 3)
    term.write(text:sub(1, W - 2))
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
    fs.delete(SECURE_FILE)
    showMessage("Secure boot", { "Un-enrolled. Boot no longer asks for a password." }, colors.lime)
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

    showBusy("Update", "Downloading from pastebin " .. settings.updateId .. "...")
    local url = "https://pastebin.com/raw/" .. settings.updateId .. "?cb=" .. os.epoch("utc")
    local resp, err = http.get(url)
    if not resp then
        showMessage("Update", { "Download failed.", tostring(err) }, colors.red)
        return
    end
    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()
    if status ~= 200 or not body or body == "" then
        showMessage("Update", { "Download failed.", "Status: " .. tostring(status) }, colors.red)
        return
    end

    -- Refuse a file that does not compile, so a bad paste cannot break the OS.
    local fn, syntaxErr = load(body, "=update")
    if not fn then
        showMessage("Update", { "The downloaded file has a syntax error.", tostring(syntaxErr), "Nothing was changed." }, colors.red)
        return
    end

    if body == readFile(SELF) then
        showMessage("Update", { "Already up to date.", "Version " .. VERSION }, colors.lime)
        return
    end

    local newVersion = body:match('local VERSION = "([^"]+)"') or "unknown"
    if not confirm({
        "Update to version " .. newVersion .. "?",
        "Current version: " .. VERSION,
        "A backup is saved as " .. SELF .. ".bak",
    }) then
        return
    end

    if fs.exists(SELF .. ".bak") then fs.delete(SELF .. ".bak") end
    pcall(fs.copy, SELF, SELF .. ".bak")
    local f = fs.open(SELF, "w")
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

    if confirm({ "Update installed (version " .. newVersion .. ").", "Reboot now?" }) then
        os.reboot()
    end
end

local function aboutApp()
    local free = fs.getFreeSpace("")
    local lines = {
        settings.osName .. " (Simple OS) version " .. VERSION,
        "Computer ID: " .. os.getComputerID(),
        "Label: " .. (os.getComputerLabel() or "none"),
        "Messenger name: " .. myName,
        "Running file: " .. SELF,
        "Free space: " .. fmtSize(free),
        "Secure boot: " .. (loadSecure() and "enrolled" or "not enrolled"),
        "Update paste ID: " .. settings.updateId,
        "HTTP: " .. (http and "enabled" or "disabled"),
    }
    showMessage("About", lines)
end

local function settingsApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Change", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }

    local function chooseColor(title, current)
        local names = {}
        for n, c in ipairs(COLOR_CHOICES) do names[n] = c.name end
        local idx = pickMenu(title, names)
        if idx then return COLOR_CHOICES[idx].name end
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
            local v = ask("Update paste ID", { "Pastebin code or link:" }, settings.updateId)
            if v then
                local code = v:match("([^/%s]+)/?%s*$")
                if code and code:match("^%w+$") then
                    settings.updateId = code
                else
                    showMessage("Settings", { "Invalid code or link." }, colors.red)
                end
            end
        elseif n == 9 then
            if confirm({ "Reset all settings to defaults?" }) then
                resetSettings()
            end
        end
        saveSettings()
    end

    while true do
        local entries = {
            { label = "OS name: " .. settings.osName },
            { label = "Top bar color: " .. settings.barColor },
            { label = "Highlight color: " .. settings.highlight },
            { label = "Clock: " .. settings.clock },
            { label = "Time format: " .. (settings.hour24 and "24 hour" or "12 hour") },
            { label = "Messenger name: " .. myName },
            { label = "Show ROM programs at start: " .. (settings.showRom and "yes" or "no") },
            { label = "Update paste ID: " .. settings.updateId },
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
            { label = "Update Simple OS" },
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

local APPS = {
    messenger = messengerApp,
    pastebin  = pastebinApp,
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

local function scan()
    local programs = {}
    walk("", 0, programs, { rom = true })
    table.sort(programs, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    local list = {
        { label = "Shell",             path = "shell", banner = "Type exit to return to Simple OS.", color = colors.cyan },
        { label = "Messenger",         app = "messenger", color = colors.cyan },
        { label = "Pastebin Download", app = "pastebin",  color = colors.cyan },
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
        os.reboot()
        return
    elseif item.action == "shutdown" then
        os.shutdown()
        return
    elseif item.app then
        local ok, err = pcall(APPS[item.app])
        resetTerm()
        if not ok then
            showMessage(item.label, { "Error:", tostring(err) }, colors.red)
        end
        return
    end

    resetTerm()
    term.clear()
    term.setCursorPos(1, 1)
    if item.banner then
        print(item.banner)
        print()
    end

    local result = false
    parallel.waitForAny(function()
        result = shell.run(item.path)
    end, backgroundNet)

    if not result then
        print()
        print("Program ended with an error. Press any key.")
        os.pullEvent("key")
    end
    resetTerm()
end

local function main()
    openModems()
    local items = scan()
    local sel, top = 1, 1
    local timer = os.startTimer(1)
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
        timer = os.startTimer(1)
    end

    while true do
        drawList(settings.osName, view(), sel, top, mainButtons())
        local ev, a, b, c = os.pullEventRaw()

        if ev == "timer" then
            if a == timer then timer = os.startTimer(1) end
        elseif ev == "rednet_message" then
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
                open(sel)
            elseif i.click and i.y >= 2 and i.y <= H - 1 and items[top + i.y - 2] then
                sel = top + i.y - 2
                open(sel)
            elseif i.scroll then
                sel = math.max(1, math.min(#items, sel + i.scroll))
            end
            top = clampTop(sel, top)
        end
        -- The terminate event is ignored here, so Ctrl+T does not close the menu.
    end
end

-- Restart the menu after a crash and keep a log of the error.
local function logError(err)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M") .. "  " .. tostring(err))
        f.close()
    end
end

-- Secure boot gate. Runs before the menu opens.
local function secureBootGate()
    local data = loadSecure()
    if not data then return end

    showBusy("Secure boot", "Verifying " .. SELF .. "...")
    local current = hashFile(SELF)
    local intact = current ~= nil and current == data.fileHash

    for attempt = 1, 3 do
        local title = intact and "Secure boot" or "Secure boot: file changed"
        local lines = intact and { "Enter the password to boot:" }
            or { SELF .. " changed since enrollment.", "Enter the password to trust it and boot:" }
        local pw = ask(title, lines, nil, "*")
        if pw and passwordMatches(data, pw) then
            if not intact and current then
                data.fileHash = current
                saveSecure(data)
            end
            return
        end
        showMessage(title, { "Wrong password. Attempt " .. attempt .. " of 3." }, colors.red)
    end

    os.shutdown()
    while true do os.pullEventRaw() end
end

local gateOk, gateErr = pcall(secureBootGate)
if not gateOk then
    -- A bug in the check must not lock the owner out. Log it and warn.
    logError("secure boot check failed: " .. tostring(gateErr))
    resetTerm()
    showMessage("Secure boot error", {
        tostring(gateErr),
        "",
        "The check did not finish. Booting without it.",
    }, colors.red)
end

while true do
    local ok, err = pcall(main)
    if ok then break end
    logError(err)
    resetTerm()
    showMessage("Simple OS error", {
        tostring(err),
        "",
        "Saved to " .. LOG_FILE,
    }, colors.red)
end
