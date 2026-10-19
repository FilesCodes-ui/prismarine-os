-- Prismarine Archive
--@prismarine-api
-- Records everything this computer receives over Rednet and files it away on
-- the computer's drive or on any of your disk drives. Browse, search, print,
-- export, copy and delete what you stored. Download it from the Download app,
-- or put it on the computer and open it from the Prismarine OS menu.
--
--   Live feed      messages as they arrive, with where each one was saved
--   Browse         search, filter, mark, view, print, export, delete
--   Print          printer status, summaries, full text, auto-print
--   Storage        usage bars for the computer and every disk, copy, clear
--   Settings       where to save, how much to keep free, what to ignore
--
--   Up / Down move   Enter open   Q back   R (main menu) pause or resume
--   Browse: F filter  M mark  P print  D delete  X more
--   Message: N next  B previous  H hex  P print  E export  D delete
--
-- Messages are written as one log file per day (archive/log/DATE.arc), so
-- thousands of messages do not use thousands of files.
--
-- Computers running Prismarine OS 21 or newer also report what they do (boots,
-- programs and shell commands, files, errors, secure boot results, peripherals).
-- Archive saves each report as protocol audit_<kind>, for example audit_command.
-- Network check on the main menu shows what Archive hears and why a message
-- could not be opened.
--
-- Private Messenger messages travel sealed (protocol simpleos_private). Inside
-- Prismarine OS version 20 or newer, Archive opens them with the network
-- passphrase (Settings > Network passphrase) and saves them as protocol
-- "private" in readable text. Without the right passphrase, or when Archive is
-- run by hand, the sealed envelope is saved as protocol "private_locked".

local api = ...
if type(api) ~= "table" then api = nil end

local VERSION = "3"
local PRIVATE_PROTO = "simpleos_private"   -- sealed private Messenger messages
local AUDIT_PROTO = "simpleos_audit"       -- sealed activity reports from Prismarine OS computers
local SETTINGS_FILE = ".prismarchive_settings"
local VIEWMAX = 32768           -- most bytes of one message shown or read for printing
local SEGMAX = 98304            -- a day log is split into a new file past this size
local PW, PH = 25, 21           -- a printer page is 25 columns by 21 lines
local AUTO_PAGES = 3            -- most pages auto-print uses for one message

local Store, Net, Prn, A, B, S, U, F = {}, {}, {}, {}, {}, {}, {}, {}

-- ── Settings ─────────────────────────────────────────────────────────────────

local DEFAULTS = {
    record = true,              -- save incoming messages
    mode = "computer",          -- computer, overflow, disks, mirror, or disk:<mount>
    folder = "archive",         -- folder used on the computer and on every disk
    reserve = 32768,            -- bytes kept free on the computer
    maxRecord = 65536,          -- bytes kept per message (0 = no limit)
    whenFull = "Stop",          -- Stop, or Drop oldest
    ignore = "",                -- protocols to skip, separated by commas
    autoPrint = "Off",          -- Off, All, or Protocol
    printProtocol = "",
    printer = "Auto",
    exportDir = "archive_export",
}

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
do
    if fs.exists(SETTINGS_FILE) then
        local f = fs.open(SETTINGS_FILE, "r")
        local data = f and textutils.unserialize(f.readAll() or "")
        if f then f.close() end
        if type(data) == "table" then
            for k, v in pairs(data) do
                if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then cfg[k] = v end
            end
        end
    end
end

local function saveCfg()
    local f = fs.open(SETTINGS_FILE, "w")
    if f then f.write(textutils.serialize(cfg)); f.close() end
end

-- ── Small helpers ────────────────────────────────────────────────────────────

local KIND = { s = "text", t = "table", n = "number", b = "boolean", o = "other" }

local function nowSec() return os.epoch("utc") / 1000 end
local function localMs() return os.epoch("local") end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function stamp(ms) return os.date("!%m-%d %H:%M:%S", math.floor(ms / 1000)) end
local function stampLong(ms) return os.date("!%Y-%m-%d %H:%M:%S", math.floor(ms / 1000)) end
local function clock(ms) return os.date("!%H:%M:%S", math.floor(ms / 1000)) end
local function dayOf(ms) return os.date("!%Y-%m-%d", math.floor(ms / 1000)) end

local function fmtSizeLocal(n)
    n = tonumber(n) or 0
    if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
    if n >= 1024 then return string.format("%.1f KB", n / 1024) end
    return string.format("%d B", math.floor(n))
end

local function fmt(n)
    if n == nil then return "?" end
    if n == math.huge or n > 2 ^ 50 then return "unlimited" end
    if api and api.fmtSize then
        local ok, s = pcall(api.fmtSize, n)
        if ok and type(s) == "string" then return s end
    end
    return fmtSizeLocal(n)
end

local function padTo(s, n)
    s = tostring(s)
    if #s >= n then return s:sub(1, n) end
    return s .. string.rep(" ", n - #s)
end

-- One line of text with no control characters, cut to n characters.
local function oneLine(s, n)
    s = tostring(s):gsub("%c", " ")
    s = s:gsub("%s+", " ")
    if #s > n then s = s:sub(1, n) end
    return s
end

-- Splits text into lines no longer than width, breaking at spaces when it can.
local function wrap(text, width)
    local out = {}
    width = math.max(1, width)
    text = tostring(text or ""):gsub("\r\n", "\n")
    text = text:gsub("\r", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("\t", "  "):gsub("%c", ".")
        while #line > width do
            local cut
            for i = math.min(#line, width + 1), 2, -1 do
                if line:sub(i, i) == " " then cut = i break end
            end
            if cut then
                out[#out + 1] = line:sub(1, cut - 1)
                line = line:sub(cut + 1)
            else
                out[#out + 1] = line:sub(1, width)
                line = line:sub(width + 1)
            end
        end
        out[#out + 1] = line
    end
    while #out > 0 and out[#out] == "" do out[#out] = nil end
    return out
end

local function urlDecode(s)
    s = s:gsub("%+", " ")
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

local function rootShort(rid)
    if rid == "computer" then return "Computer" end
    return (rid:gsub("^disk:", ""))
end

local function modeLabel(mode)
    if mode == "computer" then return "Computer only" end
    if mode == "overflow" then return "Computer, then disks" end
    if mode == "disks" then return "Disks (fill one, then next)" end
    if mode == "mirror" then return "Mirror to everything" end
    if mode:sub(1, 5) == "disk:" then return "Only " .. mode:sub(6) end
    return mode
end

-- ── Screen helpers ───────────────────────────────────────────────────────────
-- Inside Prismarine OS these come from the OS so Archive looks like the other
-- apps. Run by hand there is no api, so plain versions below are used instead.

function F.size() return term.getSize() end

function F.fill(y, bg, fg, text)
    local W = F.size()
    term.setCursorPos(1, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.write(padTo(text, W))
end

function F.header(title) F.fill(1, colors.blue, colors.white, " " .. title) end

function F.footer(text)
    local _, H = F.size()
    F.fill(H, colors.gray, colors.white, " " .. text)
end

F.hits = {}

function F.footerButtons(buttons)
    local W, H = F.size()
    F.fill(H, colors.gray, colors.white, "")
    F.hits = {}
    local x = 2
    for _, b in ipairs(buttons or {}) do
        local label = b.tag .. " " .. b.label
        if x + #label > W then break end
        term.setCursorPos(x, H)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.yellow)
        term.write(b.tag)
        term.setTextColor(colors.white)
        term.write(" " .. b.label)
        F.hits[#F.hits + 1] = { x1 = x, x2 = x + #label - 1, k = b.k }
        x = x + #label + 2
    end
end

function F.clampTop(sel, top)
    local _, H = F.size()
    local rows = math.max(1, H - 2)
    if sel < top then top = sel elseif sel > top + rows - 1 then top = sel - rows + 1 end
    return math.max(1, top)
end

function F.drawList(title, entries, sel, top, buttons)
    local W, H = F.size()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    F.header(title)
    for row = 2, H - 1 do
        local n = top + row - 2
        local e = entries[n]
        if e then
            local on = n == sel
            term.setCursorPos(1, row)
            term.setBackgroundColor(on and colors.lightBlue or colors.black)
            term.setTextColor(on and colors.black or (e.color or colors.white))
            term.write(padTo(" " .. e.label, W))
        end
    end
    F.footerButtons(buttons)
end

-- Draws wrapped lines on a colored card. Returns the last row it used.
function F.drawCard(row, lines, color, textColor)
    local W, H = F.size()
    local last = row
    for _, l in ipairs(lines) do
        for _, part in ipairs(wrap(l, W - 4)) do
            if row >= H - 1 then return last end
            term.setCursorPos(2, row)
            term.setBackgroundColor(color)
            term.setTextColor(textColor)
            term.write(padTo(" " .. part, W - 2))
            last = row
            row = row + 1
        end
    end
    return last
end

function F.inputFrom(name, a, b, c)
    if name == "key" then
        local k = keys.getName(a)
        if k and #k > 1 then return { k = k } end
    elseif name == "char" then
        return { k = tostring(a):lower() }
    elseif name == "mouse_click" then
        local _, H = F.size()
        if c == H then
            for _, h in ipairs(F.hits) do
                if b >= h.x1 and b <= h.x2 then return { k = h.k } end
            end
            return {}
        end
        return { click = true, x = b, y = c, button = a }
    end
    return {}
end

function F.next()
    while true do
        local ev = table.pack(os.pullEventRaw())
        local n = ev[1]
        if n == "terminate" then
            error("Terminated", 0)
        elseif n == "mouse_scroll" then
            return { scroll = ev[2] }
        elseif n == "term_resize" then
            return { resized = true }
        elseif n == "key" or n == "char" or n == "mouse_click" then
            return F.inputFrom(n, ev[2], ev[3], ev[4])
        end
    end
end

function F.cardColors(color)
    color = color or colors.lightBlue
    if color == colors.lime or color == colors.yellow then return color, colors.black end
    return color, colors.white
end

function F.showMessage(title, lines, color)
    term.setBackgroundColor(colors.black)
    term.clear()
    F.header(title)
    local bg, fg = F.cardColors(color)
    F.drawCard(3, lines, bg, fg)
    F.footerButtons({ { tag = "Ent", label = "OK", k = "enter" } })
    while true do
        local i = F.next()
        if i.k == "enter" or i.k == "q" or i.k == "space" or i.click then return end
    end
end

function F.showBusy(title, text)
    term.setBackgroundColor(colors.black)
    term.clear()
    F.header(title)
    F.drawCard(3, { text }, colors.lightBlue, colors.white)
    F.footer("Working...")
end

function F.confirm(lines)
    term.setBackgroundColor(colors.black)
    term.clear()
    F.header("Archive")
    F.drawCard(3, lines, colors.orange, colors.black)
    F.footerButtons({ { tag = "Y", label = "Yes", k = "y" }, { tag = "N", label = "No", k = "n" } })
    while true do
        local i = F.next()
        if i.k == "y" or i.k == "enter" then return true end
        if i.k == "n" or i.k == "q" then return false end
    end
end

function F.ask(title, lines, default)
    term.setBackgroundColor(colors.black)
    term.clear()
    F.header(title)
    local last = F.drawCard(3, lines, colors.lightBlue, colors.white)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(2, last + 2)
    local v = trim(read(nil, nil, nil, default))
    if v == "" then return nil end
    return v
end

function F.pickMenu(title, labels, default)
    local sel, top = default or 1, 1
    local buttons = { { tag = "Ent", label = "Select", k = "enter" }, { tag = "Q", label = "Cancel", k = "q" } }
    while true do
        local entries = {}
        for n, l in ipairs(labels) do entries[n] = { label = l } end
        top = F.clampTop(sel, top)
        F.drawList(title, entries, sel, top, buttons)
        local i = F.next()
        local _, H = F.size()
        if i.k == "up" and sel > 1 then sel = sel - 1
        elseif i.k == "down" and sel < #labels then sel = sel + 1
        elseif i.k == "enter" then return sel
        elseif i.k == "q" then return nil
        elseif i.click and i.y >= 2 and i.y <= H - 1 and labels[top + i.y - 2] then
            return top + i.y - 2
        end
    end
end

local function fromApi(name, fallback)
    if api and type(api[name]) == "function" then return api[name] end
    return fallback
end

function U.size()
    if api and api.size then return api.size() end
    return term.getSize()
end

U.header = fromApi("header", F.header)
U.footer = fromApi("footer", F.footer)
U.footerButtons = fromApi("footerButtons", F.footerButtons)
U.drawList = fromApi("drawList", F.drawList)
U.drawCard = fromApi("drawCard", F.drawCard)
U.clampTop = fromApi("clampTop", F.clampTop)
U.ask = fromApi("ask", F.ask)
U.confirm = fromApi("confirm", F.confirm)
U.pickMenu = fromApi("pickMenu", F.pickMenu)
U.showMessage = fromApi("showMessage", F.showMessage)
U.showBusy = fromApi("showBusy", F.showBusy)
U.inputFrom = fromApi("inputFrom", F.inputFrom)
U.pad = padTo

function U.restore()
    if api and api.restorePalette then pcall(api.restorePalette) end
end

-- Pixelbox bar from the OS when there is one, plain blocks otherwise.
function U.bar(row, col, width, frac, fillColor)
    frac = clamp(frac or 0, 0, 1)
    if api and api.gfx and api.gfx.progress then
        local ok, drawn = pcall(api.gfx.progress, row, col, width, frac)
        if ok and drawn then return end
    end
    local fill = math.floor(width * frac + 0.5)
    term.setCursorPos(col, row)
    term.setBackgroundColor(fillColor or colors.blue)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", width - fill))
end

-- Reads one event. Returns the same kind of table readInput does. Rednet
-- messages are passed on to the OS here. Saving them is done by Net.task,
-- which sees every message however deep in a menu the person is.
function A.event()
    while true do
        local ev = table.pack(os.pullEventRaw())
        local name = ev[1]
        if name == "terminate" then
            error("Terminated", 0)
        elseif name == "mouse_scroll" then
            return { scroll = ev[2] }
        elseif name == "rednet_message" then
            if api and api.handleNet then pcall(api.handleNet, ev[2], ev[3], ev[4]) end
            return {}
        elseif name == "archive_update" then
            return { update = true }
        elseif name == "term_resize" then
            if api and api.resize then pcall(api.resize) end
            return { resized = true }
        elseif name == "key" or name == "char" or name == "mouse_click" or name == "mouse_drag" then
            return U.inputFrom(name, ev[2], ev[3], ev[4]) or {}
        end
    end
end

-- Lets the other tasks run (the receiver keeps saving while a long job runs).
function A.yield()
    os.queueEvent("archive_yield")
    os.pullEventRaw("archive_yield")
end

-- A full screen progress display with a bar.
function A.progress(title, lines, frac, status)
    local W, H = U.size()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    U.header(title)
    local below = U.drawCard(3, lines, colors.lightBlue, colors.white)
    local row = math.min(below + 1, H - 3)
    U.bar(row, 3, math.max(8, W - 4), frac)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(3, math.min(row + 1, H - 1))
    term.write(padTo(status or "", W - 4))
    U.footer("Working...")
end

-- A scrolling list. spec.items(state) returns { label, color } entries,
-- spec.on(key, index, state) returns true to leave. The list returns the
-- selected index. Clicking a row acts like Enter.
function A.list(spec)
    local st = spec.state or {}
    st.sel, st.top = st.sel or 1, st.top or 1
    while true do
        local _, H = U.size()
        local entries, empty = spec.items(st), false
        if #entries == 0 then
            local text = type(spec.empty) == "function" and spec.empty() or spec.empty
            entries = { { label = text or "Nothing here.", color = colors.gray } }
            empty = true
        end
        st.sel = clamp(st.sel, 1, #entries)
        st.top = U.clampTop(st.sel, st.top)
        local title = type(spec.title) == "function" and spec.title() or spec.title
        local buttons = type(spec.buttons) == "function" and spec.buttons() or spec.buttons
        U.drawList(title, entries, st.sel, st.top, buttons)
        local i = A.event()
        local act
        if i.k == "up" then
            if st.sel > 1 then st.sel = st.sel - 1 end
        elseif i.k == "down" then
            if st.sel < #entries then st.sel = st.sel + 1 end
        elseif i.scroll then
            st.sel = clamp(st.sel + i.scroll, 1, #entries)
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[st.top + i.y - 2] then
            st.sel = st.top + i.y - 2
            act = "enter"
        elseif i.k then
            act = i.k
        end
        if act and spec.on(act, (not empty) and st.sel or nil, st) then return st.sel end
    end
end

-- Pick one label from a long list.
function A.choose(title, labels, sel)
    local picked
    A.list({
        title = title,
        state = { sel = sel or 1, top = 1 },
        items = function()
            local t = {}
            for n, l in ipairs(labels) do t[n] = { label = l } end
            return t
        end,
        buttons = { { tag = "Ent", label = "Select", k = "enter" }, { tag = "Q", label = "Cancel", k = "q" } },
        on = function(k, idx)
            if k == "enter" and idx then picked = idx return true end
            if k == "q" then return true end
        end,
    })
    return picked
end

-- ── Storage ──────────────────────────────────────────────────────────────────
-- Every message is one record: a header line, the message bytes, a newline.
--   ARC1|time|sender|protocol|kind|length|flag|id
-- Records are appended to archive/log/DATE.arc on each storage in use.

local HDR = "^ARC1|(%d+)|(%-?%d+)|([^|]*)|(%a)|(%d+)|([T%-])|(%x+)$"

local function parseHeader(line)
    local t, sender, proto, kind, len, flag, id = line:match(HDR)
    if not t then return nil end
    return {
        t = tonumber(t), sender = tonumber(sender),
        proto = proto ~= "" and urlDecode(proto) or nil,
        kind = kind, len = tonumber(len), trunc = flag == "T", id = id,
    }
end

local function buildHeader(rec)
    return table.concat({
        "ARC1", string.format("%.0f", rec.t), string.format("%.0f", rec.sender),
        textutils.urlEncode(rec.proto or ""), rec.kind, string.format("%.0f", #rec.payload),
        rec.trunc and "T" or "-", rec.id,
    }, "|")
end

Store.entries, Store.byKey, Store.roots = {}, {}, {}
Store.rev, Store.bad, Store.rootsAt, Store.dirty = 0, 0, 0, true

-- The computer first, then every disk drive with a data disk in it.
function Store.discover()
    local list = { {
        id = "computer", label = "Computer", mount = "", computer = true,
        path = fs.combine("", cfg.folder),
    } }
    local disks = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "drive" then
            local ok, d = pcall(peripheral.wrap, name)
            if ok and d then
                local present, mount, label = false, nil, nil
                pcall(function() present = d.isDiskPresent() and d.hasData() end)
                if present then
                    pcall(function() mount = d.getMountPath() end)
                    pcall(function() label = d.getDiskLabel() end)
                end
                if mount then
                    disks[#disks + 1] = {
                        id = "disk:" .. mount, mount = mount, drive = name,
                        label = ((label and label ~= "") and label or "Disk") .. " (" .. mount .. ")",
                        path = fs.combine(mount, cfg.folder),
                    }
                end
            end
        end
    end
    table.sort(disks, function(a, b) return a.mount < b.mount end)
    for _, d in ipairs(disks) do list[#list + 1] = d end
    Store.roots, Store.dirty, Store.rootsAt = list, false, nowSec()
    return list
end

function Store.refresh()
    if Store.dirty or nowSec() - Store.rootsAt > 15 then Store.discover() end
end

function Store.root(id)
    for _, r in ipairs(Store.roots) do
        if r.id == id then return r end
    end
    return nil
end

function Store.free(root)
    local ok, n = pcall(fs.getFreeSpace, root.mount == "" and "/" or root.mount)
    if ok and type(n) == "number" then return n end
    return 0
end

function Store.room(root, need)
    local free = Store.free(root)
    if root.computer then free = free - cfg.reserve end
    if free < need then return false end
    if not root.computer then
        local ok, ro = pcall(fs.isReadOnly, root.mount)
        if ok and ro then return false end
    end
    return true
end

-- The storages the current "Save to" setting allows, whether or not they have room.
function Store.modeRoots()
    local roots, mode, out = Store.roots, cfg.mode, {}
    if mode == "computer" then
        out[1] = roots[1]
    elseif mode == "disks" then
        for i = 2, #roots do out[#out + 1] = roots[i] end
    elseif mode == "overflow" or mode == "mirror" then
        for i = 1, #roots do out[#out + 1] = roots[i] end
    elseif mode:sub(1, 5) == "disk:" then
        for i = 2, #roots do
            if roots[i].id == mode then out[1] = roots[i] end
        end
    end
    return out
end

-- Where the next message goes: the first storage with room, or all of them when mirroring.
function Store.targets(need)
    local out = {}
    for _, r in ipairs(Store.modeRoots()) do
        if Store.room(r, need) then
            out[#out + 1] = r
            if cfg.mode ~= "mirror" then break end
        end
    end
    return out
end

function Store.addIndex(h, locs)
    local key = h.id .. "|" .. string.format("%.0f", h.t) .. "|" .. string.format("%.0f", h.sender)
    local e = Store.byKey[key]
    if e then
        for _, l in ipairs(locs) do e.locs[#e.locs + 1] = l end
        return e
    end
    e = { key = key, t = h.t, sender = h.sender, proto = h.proto, kind = h.kind,
          len = h.len, trunc = h.trunc, locs = locs }
    Store.entries[#Store.entries + 1] = e
    Store.byKey[key] = e
    Store.rev = Store.rev + 1
    return e
end

-- The day log to append to. A day moves to DATE_2.arc once a file is large.
function Store.segment(root, day)
    local dir = fs.combine(root.path, "log")
    local n = 1
    while true do
        local p = fs.combine(dir, day .. (n > 1 and ("_" .. n) or "") .. ".arc")
        if not fs.exists(p) or fs.getSize(p) < SEGMAX then return p end
        n = n + 1
    end
end

-- Puts a log file back to the size it had before a failed write.
function Store.rollback(path, size)
    pcall(function()
        if size <= 0 then
            fs.delete(path)
            return
        end
        local h = fs.open(path, "rb")
        local keep = h.read(size)
        h.close()
        local w = fs.open(path, "wb")
        w.write(keep)
        w.close()
    end)
end

function Store.append(root, rec, header)
    local dir = fs.combine(root.path, "log")
    local path, before = nil, 0
    local ok, err = pcall(function()
        if not fs.exists(dir) then fs.makeDir(dir) end
        path = Store.segment(root, dayOf(rec.t))
        before = fs.exists(path) and fs.getSize(path) or 0
        local f = fs.open(path, "ab")
        if not f then error("cannot open " .. path, 0) end
        f.write(header .. "\n")
        f.write(rec.payload)
        f.write("\n")
        f.close()
    end)
    if not ok then
        if path then Store.rollback(path, before) end
        return nil, tostring(err)
    end
    return { rid = root.id, file = path, off = before + #header + 1 }
end

-- Deletes the oldest day log among the allowed storages. Used by "Drop oldest".
function Store.pruneOldest()
    local best, bestName
    for _, r in ipairs(Store.modeRoots()) do
        local dir = fs.combine(r.path, "log")
        if fs.exists(dir) and fs.isDir(dir) then
            for _, n in ipairs(fs.list(dir)) do
                if n:match("%.arc$") and (not bestName or n < bestName) then
                    bestName, best = n, fs.combine(dir, n)
                end
            end
        end
    end
    if not best then return false end
    pcall(fs.delete, best)
    Store.scan()
    return true
end

-- Saves one record. Returns the index entry, or nil and the reason.
function Store.save(rec)
    local header = buildHeader(rec)
    local need = #header + #rec.payload + 2
    Store.refresh()
    local targets = Store.targets(need)
    local tries = 0
    while #targets == 0 and cfg.whenFull == "Drop oldest" and tries < 25 do
        tries = tries + 1
        if not Store.pruneOldest() then break end
        targets = Store.targets(need)
    end
    if #targets == 0 then return nil, "No storage has room" end
    local locs, why = {}, nil
    for _, root in ipairs(targets) do
        local loc, err = Store.append(root, rec, header)
        if loc then locs[#locs + 1] = loc else why = err end
    end
    if #locs == 0 then return nil, why or "Write failed" end
    return Store.addIndex(parseHeader(header), locs)
end

function Store.scanFile(root, path, tick)
    local h = fs.open(path, "rb")
    if not h then return end
    local size, pos = fs.getSize(path), 0
    while pos < size do
        local line = h.readLine()
        if not line then break end
        local hd = parseHeader(line)
        if not hd then Store.bad = Store.bad + 1 break end
        local off = pos + #line + 1
        if off + hd.len + 1 > size then Store.bad = Store.bad + 1 break end
        local skip = h.read(hd.len + 1)
        if not skip or #skip < hd.len + 1 then Store.bad = Store.bad + 1 break end
        Store.addIndex(hd, { { rid = root.id, file = path, off = off } })
        pos = off + hd.len + 1
        if tick then tick() end
    end
    h.close()
end

-- Reads every day log on the computer and on every disk into the index.
function Store.scan(tick)
    Store.entries, Store.byKey, Store.bad = {}, {}, 0
    Store.discover()
    local last = 0
    local function gate()
        if tick and nowSec() - last >= 0.05 then
            last = nowSec()
            tick()
        end
    end
    for _, root in ipairs(Store.roots) do
        local dir = fs.combine(root.path, "log")
        if fs.exists(dir) and fs.isDir(dir) then
            local names = fs.list(dir)
            table.sort(names)
            for _, n in ipairs(names) do
                local p = fs.combine(dir, n)
                if n:match("%.arc$") and not fs.isDir(p) then Store.scanFile(root, p, gate) end
            end
        end
    end
    table.sort(Store.entries, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.key < b.key
    end)
    Store.rev = Store.rev + 1
end

-- The message bytes of an entry (at most limit bytes).
function Store.read(e, limit)
    local want = math.min(e.len, limit or e.len)
    if want <= 0 then return "" end
    for _, loc in ipairs(e.locs) do
        local h = fs.exists(loc.file) and fs.open(loc.file, "rb")
        if h then
            if h.seek then h.seek("set", loc.off) else h.read(loc.off) end
            local data = h.read(want)
            h.close()
            if data and #data == want then return data end
        end
    end
    return nil, "The stored file could not be read"
end

-- Rewrites one day log without the records whose message starts at the offsets in drop.
function Store.rewrite(file, drop)
    local h = fs.open(file, "rb")
    if not h then return false end
    local data = h.readAll() or ""
    h.close()
    local out, pos, size = {}, 1, #data
    while pos <= size do
        local nl = data:find("\n", pos, true)
        if not nl then break end
        local hd = parseHeader(data:sub(pos, nl - 1))
        if not hd or nl + hd.len + 1 > size then break end
        if not drop[nl] then out[#out + 1] = data:sub(pos, nl + hd.len + 1) end
        pos = nl + hd.len + 2
    end
    if #out == 0 then
        pcall(fs.delete, file)
        return true
    end
    local body = table.concat(out)
    for _ = 1, 2 do
        local ok = pcall(function()
            local w = fs.open(file, "wb")
            w.write(body)
            w.close()
        end)
        if ok then return true end
    end
    return false
end

-- Removes entries from every storage they were saved on. Returns the number of files that failed.
function Store.delete(list)
    local byFile = {}
    for _, e in ipairs(list) do
        for _, loc in ipairs(e.locs) do
            byFile[loc.file] = byFile[loc.file] or {}
            byFile[loc.file][loc.off] = true
        end
    end
    local failed = 0
    for file, offs in pairs(byFile) do
        if not Store.rewrite(file, offs) then failed = failed + 1 end
    end
    Store.scan()
    return failed
end

function Store.clear(root)
    pcall(fs.delete, fs.combine(root.path, "log"))
    Store.scan()
end

function Store.info(root)
    local used, files = 0, 0
    local dir = fs.combine(root.path, "log")
    if fs.exists(dir) and fs.isDir(dir) then
        for _, n in ipairs(fs.list(dir)) do
            local p = fs.combine(dir, n)
            if not fs.isDir(p) then used, files = used + fs.getSize(p), files + 1 end
        end
    end
    local cap
    pcall(function() cap = fs.getCapacity(root.mount == "" and "/" or root.mount) end)
    if type(cap) ~= "number" or cap <= 0 or cap == math.huge then cap = nil end
    local count = 0
    for _, e in ipairs(Store.entries) do
        for _, l in ipairs(e.locs) do
            if l.rid == root.id then count = count + 1 end
        end
    end
    return { used = used, files = files, free = Store.free(root), cap = cap, count = count }
end

-- Copies every day log of src into dst. Logs that are already there are skipped.
function Store.copyTo(src, dst, progress)
    local sdir = fs.combine(src.path, "log")
    if not (fs.exists(sdir) and fs.isDir(sdir)) then return 0, 0, 0 end
    local ddir = fs.combine(dst.path, "log")
    pcall(fs.makeDir, ddir)
    local names = {}
    for _, n in ipairs(fs.list(sdir)) do
        if n:match("%.arc$") then names[#names + 1] = n end
    end
    local copied, skipped, failed = 0, 0, 0
    for i, n in ipairs(names) do
        local sp, dp = fs.combine(sdir, n), fs.combine(ddir, n)
        local size = fs.getSize(sp)
        if fs.exists(dp) and fs.getSize(dp) == size then
            skipped = skipped + 1
        else
            local target = dp
            if fs.exists(dp) then
                local base = (n:gsub("%.arc$", ""))
                local k = 2
                repeat
                    target = fs.combine(ddir, base .. "_c" .. k .. ".arc")
                    k = k + 1
                until not fs.exists(target)
            end
            if Store.room(dst, size + 500) and pcall(fs.copy, sp, target) then
                copied = copied + 1
            else
                failed = failed + 1
            end
        end
        if progress then progress(i, #names) end
    end
    return copied, skipped, failed
end

-- ── Rednet receiving ─────────────────────────────────────────────────────────

S.feed, S.fid, S.session, S.errors, S.ignored, S.missed, S.printed = {}, 0, 0, 0, 0, 0, 0
S.lastError, S.printNote = nil, nil
S.heard, S.raw, S.privNote, S.audNote = {}, 0, nil, nil

-- Opens a modem for Rednet when none is open.
function Net.ensure()
    local open = false
    pcall(function() open = rednet.isOpen() end)
    if open then return true end
    local any = false
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            if pcall(rednet.open, name) then any = true end
        end
    end
    return any
end

function Net.sides()
    local open = {}
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "modem" then
            local ok, isOpen = pcall(rednet.isOpen, n)
            if ok and isOpen then open[#open + 1] = n end
        end
    end
    if #open == 0 then return "no modem open" end
    return "rednet: " .. table.concat(open, ",")
end

function Net.ignored(proto)
    if cfg.ignore == "" or proto == nil then return false end
    if Net.ignoreFor ~= cfg.ignore then
        Net.ignoreFor, Net.ignoreSet = cfg.ignore, {}
        for item in cfg.ignore:gmatch("[^,]+") do
            Net.ignoreSet[trim(item):lower()] = true
        end
    end
    return Net.ignoreSet[tostring(proto):lower()] == true
end

-- Turns whatever was sent into a record. Strings are kept byte for byte,
-- tables are serialized, numbers and booleans are kept as text.
function Net.record(sender, msg, proto)
    local kind, payload = "o", tostring(msg)
    local ty = type(msg)
    if ty == "string" then
        kind, payload = "s", msg
    elseif ty == "number" then
        kind, payload = "n", tostring(msg)
    elseif ty == "boolean" then
        kind, payload = "b", tostring(msg)
    elseif ty == "table" then
        local ok, s = pcall(textutils.serialize, msg, { compact = true })
        if not ok then ok, s = pcall(textutils.serialize, msg, { compact = true, allow_repetitions = true }) end
        if ok and type(s) == "string" then kind, payload = "t", s end
    end
    local trunc = false
    if cfg.maxRecord > 0 and #payload > cfg.maxRecord then
        payload, trunc = payload:sub(1, cfg.maxRecord), true
    end
    return {
        t = localMs(), sender = tonumber(sender) or 0,
        proto = (proto ~= nil and tostring(proto) ~= "") and tostring(proto) or nil,
        kind = kind, payload = payload, trunc = trunc,
        id = string.format("%06x", math.random(0, 16777215)),
    }
end

function Net.note(rec, e, err)
    S.fid = S.fid + 1
    S.feed[#S.feed + 1] = {
        n = S.fid, t = rec.t, sender = rec.sender, proto = rec.proto, kind = rec.kind,
        len = #rec.payload, snip = oneLine(rec.payload, 60), e = e, err = err,
    }
    if #S.feed > 100 then table.remove(S.feed, 1) end
end

function Net.wantsPrint(proto)
    if cfg.autoPrint == "All" then return true end
    if cfg.autoPrint == "Protocol" and cfg.printProtocol ~= "" and proto then
        return proto:lower() == cfg.printProtocol:lower()
    end
    return false
end

-- Private Messenger messages are broadcast sealed. The OS opens the Archive
-- copy (api.openPrivate) with the network passphrase. The readable text is
-- saved as protocol "private". When the OS cannot open it, the sealed envelope
-- is saved as it came, under "private_locked".
function Net.unseal(sender, msg, proto)
    local isPriv = proto == PRIVATE_PROTO and type(msg) == "table" and msg.type == "priv"
    local isAud = proto == AUDIT_PROTO and type(msg) == "table" and msg.type == "aud"
    if not isPriv and not isAud then return msg, proto end
    local note = isPriv and "privNote" or "audNote"
    if not (api and type(api.openPrivate) == "function") then
        S[note] = "Archive is not running inside Prismarine OS 20 or newer, so it cannot open these."
        return msg, isPriv and "private_locked" or "audit_locked"
    end
    local ok, m, why = pcall(api.openPrivate, sender, msg)
    if ok and type(m) == "table" then
        S[note] = "Last one opened from #" .. tostring(m.from) .. "."
        local who = (m.name ~= nil and m.name ~= "") and (" " .. m.name) or ""
        if isPriv then
            local text = "#" .. tostring(m.from) .. who .. " to #" .. tostring(m.to) .. ": " .. tostring(m.text)
            if m.spoofed then text = "[sender mismatch] " .. text end
            return text, "private"
        end
        local kind, body = tostring(m.text):match("^([%w_]+)|(.*)$")
        local text = "#" .. tostring(m.from) .. who .. ": " .. tostring(body or m.text)
        if m.spoofed then text = "[sender mismatch] " .. text end
        return text, "audit_" .. (kind or "event")
    end
    local reason = ok and tostring(why or "unknown") or tostring(m)
    if reason == "no key" then reason = "no network passphrase is set on this computer (Settings > Network passphrase)"
    elseif reason == "foreign" then reason = "it does not match this network passphrase (use the same one everywhere)"
    elseif reason == "repeat" then reason = "it was already opened (duplicate)"
    elseif reason == "old" then reason = "its clock is more than 5 minutes off"
    elseif reason == "bad" then reason = "it is damaged or was changed on the way" end
    S[note] = "Could not open one from #" .. tostring(sender) .. ": " .. reason
    return msg, isPriv and "private_locked" or "audit_locked"
end

function Net.handle(sender, msg, proto)
    if not cfg.record then
        S.missed = S.missed + 1
        return
    end
    msg, proto = Net.unseal(sender, msg, proto)
    if Net.ignored(proto) then
        S.ignored = S.ignored + 1
        return
    end
    local rec = Net.record(sender, msg, proto)
    local e, err = Store.save(rec)
    if e then
        S.session = S.session + 1
        Net.note(rec, e, nil)
        if Net.wantsPrint(rec.proto) and #Prn.queue < 50 then
            Prn.queue[#Prn.queue + 1] = e
            os.queueEvent("archive_print")
        end
    else
        S.errors = S.errors + 1
        S.lastError = err
        Net.note(rec, nil, err)
    end
    os.queueEvent("archive_update")
end

-- Runs next to the screens and sees every Rednet message.
function Net.task()
    while true do
        local ev = table.pack(os.pullEventRaw())
        local name = ev[1]
        if name == "modem_message" then
            S.raw = S.raw + 1
        elseif name == "rednet_message" then
            local key = ev[4] ~= nil and tostring(ev[4]) or "(none)"
            local h = S.heard[key]
            if not h then h = { n = 0 }; S.heard[key] = h end
            h.n, h.t, h.from = h.n + 1, localMs(), ev[2]
            local ok, err = pcall(Net.handle, ev[2], ev[3], ev[4])
            if not ok then
                S.errors, S.lastError = S.errors + 1, tostring(err)
            end
        elseif name == "peripheral" or name == "peripheral_detach" or name == "disk" or name == "disk_eject" then
            Store.dirty = true
            if name == "peripheral" then Net.ensure() end
            os.queueEvent("archive_update")
        elseif name == "terminate" then
            error("Terminated", 0)
        end
    end
end

-- ── Printing ─────────────────────────────────────────────────────────────────

Prn.queue, Prn.busy = {}, false

function Prn.names()
    local out = {}
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "printer" then out[#out + 1] = n end
    end
    return out
end

function Prn.get()
    local names = Prn.names()
    if #names == 0 then return nil, "No printer is attached." end
    local name = names[1]
    if cfg.printer ~= "Auto" then
        for _, n in ipairs(names) do
            if n == cfg.printer then name = n end
        end
    end
    local p = peripheral.wrap(name)
    if not p then return nil, "Cannot use printer " .. name end
    return p, name
end

function Prn.lock()
    local waited = 0
    while Prn.busy do
        os.sleep(0.25)
        waited = waited + 0.25
        if waited > 120 then return false end
    end
    Prn.busy = true
    return true
end

-- Prints already wrapped lines. ui.wait(reason) says whether to try again after
-- a problem, ui.progress(page, pages) is called as each page starts.
function Prn.job(lines, title, ui)
    local p, name = Prn.get()
    if not p then return false, name end
    local pages = math.max(1, math.ceil(#lines / PH))
    local i, page = 1, 0
    local ok, err = pcall(function()
        while i <= #lines do
            while true do
                local paper, ink = p.getPaperLevel(), p.getInkLevel()
                if paper > 0 and ink > 0 then break end
                local why = paper > 0 and "out of ink" or "out of paper"
                if not ui.wait(why) then error("Printer is " .. why, 0) end
            end
            if not p.newPage() then error("The printer could not start a page", 0) end
            page = page + 1
            if ui.progress then ui.progress(page, pages) end
            pcall(p.setPageTitle, (title or "Archive"):sub(1, 24) .. " " .. page)
            for row = 1, PH do
                local l = lines[i]
                if not l then break end
                p.setCursorPos(1, row)
                p.write(l:sub(1, PW))
                i = i + 1
            end
            while not p.endPage() do
                if not ui.wait("the output tray is full") then error("The printer output tray is full", 0) end
            end
        end
    end)
    if not ok then
        pcall(p.endPage)
        return false, tostring(err)
    end
    return true, pages
end

-- Full text of entries, each starting on a new page. maxPages cuts long messages.
function Prn.docLines(list, maxPages)
    local out = {}
    local function add(text)
        for _, l in ipairs(wrap(text, PW)) do out[#out + 1] = l end
    end
    for _, e in ipairs(list) do
        local start = #out
        add("ARCHIVE  " .. stampLong(e.t))
        add("From #" .. e.sender .. (e.proto and ("  " .. e.proto) or ""))
        add((KIND[e.kind] or "?") .. ", " .. fmt(e.len) .. (e.trunc and ", cut" or ""))
        out[#out + 1] = string.rep("-", PW)
        local limit = maxPages and (maxPages * PH * PW) or VIEWMAX
        local data = Store.read(e, limit)
        if data then add(A.bodyText(e, data)) else add("[could not be read]") end
        if maxPages and #out - start > maxPages * PH then
            local stop = start + maxPages * PH
            for j = #out, stop + 1, -1 do out[j] = nil end
            out[stop] = "[cut: page limit]"
        end
        while #out % PH ~= 0 do out[#out + 1] = "" end
    end
    return out
end

-- Two lines per message.
function Prn.summaryLines(list, title)
    local out = {}
    local function add(text)
        for _, l in ipairs(wrap(text, PW)) do out[#out + 1] = l end
    end
    add(title or "ARCHIVE SUMMARY")
    add(stampLong(localMs()))
    add(plural(#list, "message"))
    out[#out + 1] = string.rep("-", PW)
    for _, e in ipairs(list) do
        out[#out + 1] = (stamp(e.t) .. " #" .. e.sender):sub(1, PW)
        out[#out + 1] = (" " .. (e.proto or "-") .. " " .. (KIND[e.kind] or "?") .. " " .. fmt(e.len)):sub(1, PW)
    end
    return out
end

-- Prints messages that arrive while Auto-print is on.
function Prn.task()
    while true do
        if #Prn.queue == 0 then
            local ev = os.pullEventRaw("archive_print")
            if ev == "terminate" then error("Terminated", 0) end
        else
            local e = table.remove(Prn.queue, 1)
            local ok, err = pcall(function()
                if not Prn.lock() then error("the printer is busy", 0) end
                local tries = 0
                local good, why = pcall(function()
                    local lines = Prn.docLines({ e }, AUTO_PAGES)
                    local ok2, err2 = Prn.job(lines, "Archive", {
                        wait = function(w)
                            tries = tries + 1
                            S.printNote = "Auto-print waiting: " .. w
                            if tries > 20 then return false end
                            os.sleep(3)
                            return true
                        end,
                    })
                    if not ok2 then error(err2, 0) end
                end)
                Prn.busy = false
                if not good then error(why, 0) end
            end)
            if ok then
                S.printNote = nil
                S.printed = S.printed + 1
            else
                S.printNote = "Auto-print failed: " .. tostring(err)
            end
        end
    end
end

function Prn.status()
    local names = Prn.names()
    if #names == 0 then
        return {
            "No printer is attached.",
            "Place a printer next to this computer, or on its wired modem network, and give it paper and ink.",
        }
    end
    local lines = {}
    for _, n in ipairs(names) do
        local p = peripheral.wrap(n)
        local paper, ink = "?", "?"
        if p then pcall(function() paper, ink = p.getPaperLevel(), p.getInkLevel() end) end
        lines[#lines + 1] = n .. ": paper " .. tostring(paper) .. ", ink " .. tostring(ink)
    end
    lines[#lines + 1] = "Auto-print: " .. A.autoLabel()
    if S.printNote then lines[#lines + 1] = S.printNote end
    return lines
end

-- ── Message text ─────────────────────────────────────────────────────────────

-- Tables are shown as readable Lua, everything else as it was sent.
function A.bodyText(e, payload)
    if e.kind == "t" and not e.trunc then
        local ok, t = pcall(textutils.unserialize, payload)
        if ok and t ~= nil then
            local ok2, pretty = pcall(textutils.serialize, t)
            if ok2 and type(pretty) == "string" then return pretty end
        end
    end
    return payload
end

function A.hexLines(data, width)
    local bpr = math.max(2, math.floor((width - 5) / 4))
    local out = {}
    for off = 1, #data, bpr do
        local chunk = data:sub(off, off + bpr - 1)
        local hex, asc = {}, {}
        for j = 1, #chunk do
            local b = chunk:byte(j)
            hex[j] = string.format("%02X", b)
            asc[j] = (b >= 32 and b < 127) and string.char(b) or "."
        end
        out[#out + 1] = string.format("%04X ", (off - 1) % 65536) .. table.concat(hex, " ") .. " " .. table.concat(asc)
    end
    return out
end

function A.where(e)
    local seen, out = {}, {}
    for _, l in ipairs(e.locs) do
        local name = rootShort(l.rid)
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return table.concat(out, ", ")
end

function A.rowLabel(e, width, mark)
    local s = (mark and "*" or " ") .. stamp(e.t) .. " #" .. e.sender .. " " .. (e.proto or "-")
        .. "  " .. (KIND[e.kind] or "?") .. " " .. fmt(e.len)
    return s:sub(1, width)
end

function A.autoLabel()
    if cfg.autoPrint == "All" then return "every message" end
    if cfg.autoPrint == "Protocol" then
        return "protocol " .. (cfg.printProtocol ~= "" and cfg.printProtocol or "?")
    end
    return "off"
end

-- ── Browse state: filters and marks ─────────────────────────────────────────

B.text, B.sender, B.proto, B.day = "", nil, nil, nil
B.marks, B.cache, B.list = {}, {}, {}
B.ver, B.builtVer, B.builtRev = 0, -1, -1

function B.matchText(e, q)
    local c = B.cache[e.key]
    if c == nil then
        local data = Store.read(e, 4096) or ""
        local hay = ((e.proto or "") .. " " .. e.sender .. " " .. data):gsub("%c", " "):lower()
        c = hay:find(q, 1, true) ~= nil
        B.cache[e.key] = c
    end
    return c
end

function B.build()
    local out = {}
    local q = B.text ~= "" and B.text:lower() or nil
    local entries = Store.entries
    for i = #entries, 1, -1 do
        local e = entries[i]
        if (not B.sender or e.sender == B.sender)
            and (not B.proto or (e.proto or "") == B.proto)
            and (not B.day or dayOf(e.t) == B.day)
            and (not q or B.matchText(e, q)) then
            out[#out + 1] = e
        end
    end
    return out
end

function B.refresh()
    if B.builtVer ~= B.ver or B.builtRev ~= Store.rev then
        B.list = B.build()
        B.builtVer, B.builtRev = B.ver, Store.rev
    end
end

function B.filterText()
    local parts = {}
    if B.text ~= "" then parts[#parts + 1] = "\"" .. B.text .. "\"" end
    if B.sender then parts[#parts + 1] = "#" .. B.sender end
    if B.proto then parts[#parts + 1] = B.proto == "" and "no protocol" or B.proto end
    if B.day then parts[#parts + 1] = B.day end
    if #parts == 0 then return "" end
    return "  [" .. table.concat(parts, " ") .. "]"
end

-- Marked entries, or the highlighted one when nothing is marked.
function B.targets(idx)
    local out = {}
    for _, e in ipairs(B.list) do
        if B.marks[e.key] then out[#out + 1] = e end
    end
    if #out == 0 and idx and B.list[idx] then out[1] = B.list[idx] end
    return out
end

-- ── Actions ──────────────────────────────────────────────────────────────────

function A.toggleRecord()
    cfg.record = not cfg.record
    saveCfg()
end

function A.printLines(lines, title, label)
    local pages = math.max(1, math.ceil(#lines / PH))
    if pages > 5 then
        if not U.confirm({ label .. " needs " .. pages .. " pages of paper.", "Print it?" }) then return end
    end
    if not Prn.lock() then
        U.showMessage("Print", { "The printer is busy.", "Try again in a moment." }, colors.yellow)
        return
    end
    local ok, err
    local good, e2 = pcall(function()
        ok, err = Prn.job(lines, title, {
            wait = function(why)
                return U.confirm({ "Printer: " .. why .. ".", "Fix it, then choose Yes to continue." })
            end,
            progress = function(page, total)
                A.progress("Printing", { label, "Page " .. page .. " of " .. total }, (page - 1) / total, "Printing...")
                A.yield()
            end,
        })
    end)
    Prn.busy = false
    U.restore()
    if not good then
        if tostring(e2):find("Terminated") then error(e2, 0) end
        ok, err = false, tostring(e2)
    end
    if ok then
        U.showMessage("Print", { "Sent " .. plural(err, "page") .. " to the printer." }, colors.lime)
    else
        U.showMessage("Print", { "Printing stopped.", tostring(err) }, colors.red)
    end
end

function A.printEntries(list)
    if #list == 0 then return end
    U.showBusy("Print", "Preparing " .. plural(#list, "message") .. "...")
    local lines = Prn.docLines(list, nil)
    A.printLines(lines, "Archive", plural(#list, "message"))
end

-- Returns true when the messages were deleted.
function A.deleteEntries(list)
    if #list == 0 then return false end
    if not U.confirm({ "Delete " .. plural(#list, "message") .. "?", "They are removed from every storage." }) then
        return false
    end
    U.showBusy("Archive", "Deleting...")
    local failed = Store.delete(list)
    B.marks = {}
    B.ver = B.ver + 1
    if failed > 0 then
        U.showMessage("Delete", { plural(failed, "file") .. " could not be rewritten.", "Some messages may remain." }, colors.red)
    end
    return true
end

function A.exportDirReady()
    local dir = fs.combine("", cfg.exportDir)
    local bad
    if dir == "" or dir == "rom" or dir:sub(1, 4) == "rom/" then
        bad = "Choose another export folder in Settings."
    elseif fs.exists(dir) and not fs.isDir(dir) then
        bad = dir .. " is a file."
    else
        if not fs.exists(dir) then pcall(fs.makeDir, dir) end
        if not fs.isDir(dir) then
            bad = "Cannot create " .. dir
        elseif fs.isReadOnly(dir) then
            bad = dir .. " is read only."
        end
    end
    if bad then
        U.showMessage("Export", { bad }, colors.red)
        return nil
    end
    return dir
end

function A.uniquePath(dir, base, ext)
    local path = fs.combine(dir, base .. "." .. ext)
    local n = 2
    while fs.exists(path) do
        path = fs.combine(dir, base .. "_" .. n .. "." .. ext)
        n = n + 1
    end
    return path
end

function A.writeFile(path, body)
    if fs.getFreeSpace(fs.getDir(path) == "" and "/" or fs.getDir(path)) < #body + 500 then return false end
    return pcall(function()
        local f = fs.open(path, "wb")
        f.write(body)
        f.close()
    end)
end

-- One file per message in the export folder.
function A.exportFiles(list)
    if #list == 0 then return end
    local dir = A.exportDirReady()
    if not dir then return end
    local saved, failed = 0, 0
    for _, e in ipairs(list) do
        local data = Store.read(e)
        if not data then
            failed = failed + 1
        else
            local body = e.kind == "t" and A.bodyText(e, data) or data
            local base = os.date("!%Y%m%d_%H%M%S", math.floor(e.t / 1000)) .. "_from" .. e.sender
            local path = A.uniquePath(dir, base, e.kind == "t" and "lua" or "txt")
            if A.writeFile(path, body) then saved = saved + 1 else failed = failed + 1 end
        end
    end
    local lines = { "Saved " .. plural(saved, "file") .. " to /" .. dir }
    if failed > 0 then lines[#lines + 1] = plural(failed, "message") .. " could not be saved (read error or no room)." end
    U.showMessage("Export", lines, failed > 0 and colors.yellow or colors.lime)
end

-- All the messages in one readable text file.
function A.exportLog(list)
    if #list == 0 then return end
    local dir = A.exportDirReady()
    if not dir then return end
    local parts = {}
    for n = #list, 1, -1 do
        local e = list[n]
        local data = Store.read(e, VIEWMAX) or "[could not be read]"
        parts[#parts + 1] = "== " .. stampLong(e.t) .. "  from #" .. e.sender .. "  protocol " .. (e.proto or "-")
            .. "  " .. (KIND[e.kind] or "?") .. " " .. fmt(e.len) .. " ==\n" .. A.bodyText(e, data) .. "\n\n"
    end
    local body = table.concat(parts)
    local path = A.uniquePath(dir, "archive_" .. os.date("!%Y%m%d_%H%M%S", math.floor(localMs() / 1000)), "log")
    if A.writeFile(path, body) then
        U.showMessage("Export", { "Saved " .. path, plural(#list, "message") .. ", " .. fmt(#body) }, colors.lime)
    else
        U.showMessage("Export", { "Could not write " .. path, "Check the free space." }, colors.red)
    end
end

-- Looks through the start of every message for the search words.
function A.prepareSearch()
    local q = B.text:lower()
    local total, last = #Store.entries, 0
    for n, e in ipairs(Store.entries) do
        B.matchText(e, q)
        if nowSec() - last > 0.15 then
            last = nowSec()
            A.progress("Search", { "Looking through " .. plural(total, "message") .. "..." }, n / math.max(1, total), "")
            A.yield()
        end
    end
    U.restore()
end

-- ── Message view ─────────────────────────────────────────────────────────────

function A.detail(list, idx)
    local hex, scroll, lines, meta, e = false, 0, {}, {}, nil

    local function load()
        e = list[idx]
        local W = U.size()
        local data, err = Store.read(e, VIEWMAX)
        meta = {
            stampLong(e.t) .. "   from #" .. e.sender,
            "Protocol: " .. (e.proto or "-") .. "   " .. (KIND[e.kind] or "?") .. ", " .. fmt(e.len) .. (e.trunc and " (cut)" or ""),
            "Stored on: " .. A.where(e),
        }
        if not data then
            lines = { "[" .. tostring(err) .. "]" }
        elseif hex then
            lines = A.hexLines(data, W - 2)
        else
            lines = wrap(A.bodyText(e, data), W - 2)
            if #lines == 0 then lines = { "[empty message]" } end
        end
        if data and #data < e.len then lines[#lines + 1] = "[showing the first " .. fmt(#data) .. "]" end
        scroll = 0
    end

    local function draw()
        local W, H = U.size()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        U.header("Message " .. idx .. " of " .. #list)
        local below = U.drawCard(3, meta, colors.lightBlue, colors.white)
        local rows = math.max(1, H - 1 - below)
        scroll = clamp(scroll, 0, math.max(0, #lines - rows))
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        for r = 1, rows do
            local l = lines[scroll + r]
            if not l then break end
            term.setCursorPos(2, below + r)
            term.write(l:sub(1, W - 2))
        end
        U.footerButtons({
            { tag = "P", label = "Print", k = "p" },
            { tag = "E", label = "Export", k = "e" },
            { tag = "D", label = "Delete", k = "d" },
            { tag = "H", label = hex and "Text" or "Hex", k = "h" },
            { tag = "N", label = "Next", k = "n" },
            { tag = "Q", label = "Back", k = "q" },
        })
    end

    load()
    while true do
        draw()
        local i = A.event()
        if i.k == "q" then
            return
        elseif i.k == "up" then
            scroll = scroll - 1
        elseif i.k == "down" then
            scroll = scroll + 1
        elseif i.scroll then
            scroll = scroll + i.scroll * 3
        elseif i.k == "n" then
            if idx < #list then idx = idx + 1 load() end
        elseif i.k == "b" then
            if idx > 1 then idx = idx - 1 load() end
        elseif i.k == "h" then
            hex = not hex
            load()
        elseif i.k == "p" then
            A.printEntries({ e })
            U.restore()
        elseif i.k == "e" then
            A.exportFiles({ e })
        elseif i.k == "d" then
            if A.deleteEntries({ e }) then return end
        elseif i.resized then
            load()
        end
    end
end

-- ── Live feed ────────────────────────────────────────────────────────────────

function A.live()
    local view = {}
    A.list({
        state = { sel = 1, top = 1 },
        title = function()
            return "Live feed  " .. (cfg.record and "REC" or "PAUSED") .. "  " .. Net.sides()
        end,
        empty = function()
            if Net.sides() == "no modem open" then return "No modem is open. Attach a modem to receive." end
            return "Waiting for Rednet messages..."
        end,
        buttons = function()
            return {
                { tag = "Ent", label = "View", k = "enter" },
                { tag = "P", label = cfg.record and "Pause" or "Resume", k = "p" },
                { tag = "C", label = "Clear", k = "c" },
                { tag = "Q", label = "Back", k = "q" },
            }
        end,
        items = function(state)
            local cur = view[state.sel]
            view = {}
            for n = #S.feed, 1, -1 do view[#view + 1] = S.feed[n] end
            if cur then
                for n, it in ipairs(view) do
                    if it.n == cur.n then state.sel = n break end
                end
            end
            local out = {}
            for n, it in ipairs(view) do
                local label
                if it.err then
                    label = clock(it.t) .. "  #" .. it.sender .. "  NOT SAVED: " .. it.err
                else
                    label = clock(it.t) .. "  #" .. it.sender .. "  " .. (it.proto or "-") .. "  "
                        .. (KIND[it.kind] or "?") .. " " .. fmt(it.len) .. "  " .. it.snip
                end
                out[n] = { label = label, color = it.err and colors.red or colors.lime }
            end
            return out
        end,
        on = function(k, idx)
            if k == "q" then return true end
            if k == "p" then A.toggleRecord() end
            if k == "c" then S.feed = {} end
            if k == "enter" and idx and view[idx] and view[idx].e then
                A.detail({ view[idx].e }, 1)
                U.restore()
            end
        end,
    })
end

-- ── Browse ───────────────────────────────────────────────────────────────────

function A.filterMenu()
    local pick = U.pickMenu("Filter", {
        "Search text...", "From one computer...", "One protocol...", "One day...", "Clear all filters", "Back",
    }, 1)
    if pick == 1 then
        local v = U.ask("Search", {
            "Words to look for in the sender, protocol and first 4 KB of each message:",
            "Leave blank to clear the search.",
        }, B.text ~= "" and B.text or nil)
        B.text = v and trim(v) or ""
        B.cache = {}
        B.ver = B.ver + 1
        if B.text ~= "" then A.prepareSearch() end
    elseif pick == 2 or pick == 3 or pick == 4 then
        local counts, keys = {}, {}
        for _, e in ipairs(Store.entries) do
            local k
            if pick == 2 then k = e.sender elseif pick == 3 then k = e.proto or "" else k = dayOf(e.t) end
            if not counts[k] then counts[k] = 0; keys[#keys + 1] = k end
            counts[k] = counts[k] + 1
        end
        if #keys == 0 then
            U.showMessage("Filter", { "Nothing is stored yet." }, colors.yellow)
            return
        end
        if pick == 4 then
            table.sort(keys, function(a, b) return a > b end)
        else
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            if pick == 2 then table.sort(keys) end
        end
        local labels = {}
        for n, k in ipairs(keys) do
            local name
            if pick == 2 then name = "#" .. k elseif pick == 3 then name = (k == "" and "(no protocol)" or k) else name = k end
            labels[n] = name .. "  (" .. plural(counts[k], "message") .. ")"
        end
        local idx = A.choose(pick == 2 and "From" or (pick == 3 and "Protocol" or "Day"), labels, 1)
        if idx then
            if pick == 2 then B.sender = keys[idx] elseif pick == 3 then B.proto = keys[idx] else B.day = keys[idx] end
            B.ver = B.ver + 1
        end
    elseif pick == 5 then
        B.text, B.sender, B.proto, B.day, B.cache = "", nil, nil, nil, {}
        B.ver = B.ver + 1
    end
end

function A.moreMenu(idx)
    local pick = U.pickMenu("More", {
        "Mark everything shown", "Clear all marks", "Export to files", "Export as one log file",
        "Delete everything shown", "Rescan storage", "Back",
    }, 1)
    if pick == 1 then
        for _, e in ipairs(B.list) do B.marks[e.key] = true end
    elseif pick == 2 then
        B.marks = {}
    elseif pick == 3 then
        A.exportFiles(B.targets(idx))
    elseif pick == 4 then
        local list = B.targets(idx)
        if next(B.marks) == nil then list = B.list end
        A.exportLog(list)
    elseif pick == 5 then
        local list = {}
        for n, e in ipairs(B.list) do list[n] = e end
        A.deleteEntries(list)
    elseif pick == 6 then
        U.showBusy("Archive", "Reading storage...")
        Store.scan()
        B.cache = {}
        B.ver = B.ver + 1
    end
end

function A.browse()
    B.refresh()
    A.list({
        state = { sel = 1, top = 1 },
        title = function()
            return "Archive  " .. #B.list .. " of " .. #Store.entries .. B.filterText()
        end,
        empty = "No messages here. Change the filter, or wait for Rednet messages.",
        buttons = {
            { tag = "Ent", label = "View", k = "enter" },
            { tag = "F", label = "Filter", k = "f" },
            { tag = "M", label = "Mark", k = "m" },
            { tag = "P", label = "Print", k = "p" },
            { tag = "X", label = "More", k = "x" },
            { tag = "Q", label = "Back", k = "q" },
        },
        items = function(state)
            local cur = B.list[state.sel]
            B.refresh()
            if cur and (not B.list[state.sel] or B.list[state.sel].key ~= cur.key) then
                for n, e in ipairs(B.list) do
                    if e.key == cur.key then state.sel = n break end
                end
            end
            local W = U.size()
            local out = {}
            for n, e in ipairs(B.list) do
                local marked = B.marks[e.key]
                out[n] = { label = A.rowLabel(e, W - 2, marked), color = marked and colors.yellow or nil }
            end
            return out
        end,
        on = function(k, idx, state)
            local e = idx and B.list[idx]
            if k == "q" then
                return true
            elseif k == "enter" and e then
                A.detail(B.list, idx)
                U.restore()
            elseif k == "f" then
                A.filterMenu()
            elseif k == "m" and e then
                B.marks[e.key] = (not B.marks[e.key]) or nil
                state.sel = math.min(#B.list, state.sel + 1)
            elseif k == "p" then
                A.printEntries(B.targets(idx))
                U.restore()
            elseif k == "d" then
                A.deleteEntries(B.targets(idx))
            elseif k == "x" then
                A.moreMenu(idx)
            end
        end,
    })
end

-- ── Print menu ───────────────────────────────────────────────────────────────

function A.autoPrintMenu()
    local pick = U.pickMenu("Auto-print", { "Off", "Every message", "Only one protocol..." }, 1)
    if pick == 1 then
        cfg.autoPrint = "Off"
    elseif pick == 2 then
        cfg.autoPrint = "All"
    elseif pick == 3 then
        local v = U.ask("Auto-print", { "Protocol to print:" }, cfg.printProtocol ~= "" and cfg.printProtocol or nil)
        if v then
            cfg.autoPrint, cfg.printProtocol = "Protocol", v
        end
    end
    saveCfg()
end

function A.choosePrinter()
    local names = Prn.names()
    if #names == 0 then
        U.showMessage("Printer", Prn.status(), colors.yellow)
        return
    end
    local labels = { "Automatic (first printer found)" }
    for _, n in ipairs(names) do labels[#labels + 1] = n end
    local pick = U.pickMenu("Printer", labels, 1)
    if pick == 1 then cfg.printer = "Auto" elseif pick then cfg.printer = names[pick - 1] end
    saveCfg()
end

function A.newest(count, today)
    local out = {}
    local day = dayOf(localMs())
    for i = #Store.entries, 1, -1 do
        local e = Store.entries[i]
        if (not today or dayOf(e.t) == day) and (not count or #out < count) then
            out[#out + 1] = e
        end
    end
    return out
end

function A.printMenu()
    local labels = {
        "Printer status", "Summary list...", "Full text of messages...",
        "Test page", "Auto-print...", "Choose printer...",
    }
    A.list({
        title = "Print",
        state = { sel = 1, top = 1 },
        buttons = { { tag = "Ent", label = "Open", k = "enter" }, { tag = "Q", label = "Back", k = "q" } },
        items = function()
            local out = {}
            for n, l in ipairs(labels) do out[n] = { label = l, color = colors.cyan } end
            out[5].label = "Auto-print: " .. A.autoLabel()
            return out
        end,
        on = function(k, idx)
            if k == "q" then return true end
            if k ~= "enter" or not idx then return end
            if idx == 1 then
                U.showMessage("Printer status", Prn.status(), colors.lightBlue)
            elseif idx == 2 then
                local p = U.pickMenu("Summary of", { "Today", "Newest 100", "Everything stored", "Back" }, 1)
                if p and p < 4 then
                    local list = p == 1 and A.newest(nil, true) or A.newest(p == 2 and 100 or nil, false)
                    if #list == 0 then
                        U.showMessage("Print", { "No messages to print." }, colors.yellow)
                    else
                        A.printLines(Prn.summaryLines(list), "Summary", plural(#list, "message") .. " summary")
                    end
                end
            elseif idx == 3 then
                local p = U.pickMenu("Full text of", { "Today", "Newest 10", "Newest 25", "Back" }, 1)
                if p and p < 4 then
                    local list = p == 1 and A.newest(nil, true) or A.newest(p == 2 and 10 or 25, false)
                    if #list == 0 then
                        U.showMessage("Print", { "No messages to print." }, colors.yellow)
                    else
                        A.printEntries(list)
                    end
                end
            elseif idx == 4 then
                local lines = { "ARCHIVE TEST PAGE", stampLong(localMs()), string.rep("-", PW), "Printer is working.",
                    "1234567890123456789012345" }
                A.printLines(lines, "Test", "Test page")
            elseif idx == 5 then
                A.autoPrintMenu()
            elseif idx == 6 then
                A.choosePrinter()
            end
            U.restore()
        end,
    })
end

-- ── Storage screen ───────────────────────────────────────────────────────────

function A.manageRoot(r)
    local pick = U.pickMenu(r.label, {
        "Save only here", "Copy its archive to another storage...", "Clear its archive", "Back",
    }, 1)
    if pick == 1 then
        cfg.mode = r.computer and "computer" or r.id
        saveCfg()
        U.showMessage("Storage", { "New messages are saved only on " .. r.label .. "." }, colors.lime)
    elseif pick == 2 then
        local others, labels = {}, {}
        for _, o in ipairs(Store.roots) do
            if o.id ~= r.id then
                others[#others + 1] = o
                labels[#labels + 1] = o.label
            end
        end
        if #others == 0 then
            U.showMessage("Storage", { "There is no other storage.", "Insert a disk in a disk drive first." }, colors.yellow)
            return
        end
        local idx = A.choose("Copy to", labels, 1)
        if not idx then return end
        local dst = others[idx]
        if not U.confirm({ "Copy the archive from " .. r.label .. " to " .. dst.label .. "?", "Logs already there are skipped." }) then
            return
        end
        local copied, skipped, failed = Store.copyTo(r, dst, function(i, total)
            A.progress("Copy archive", { r.label .. " to " .. dst.label }, i / math.max(1, total), "Log " .. i .. " of " .. total)
            A.yield()
        end)
        U.restore()
        Store.scan()
        B.ver = B.ver + 1
        U.showMessage("Copy archive", {
            "Copied " .. plural(copied, "log file") .. ", skipped " .. skipped .. ".",
            failed > 0 and (plural(failed, "file") .. " failed (not enough room).") or "Every log was copied.",
        }, failed > 0 and colors.yellow or colors.lime)
    elseif pick == 3 then
        local info = Store.info(r)
        if U.confirm({ "Delete the whole archive on " .. r.label .. "?", plural(info.count, "message") .. ", " .. fmt(info.used) .. ". This cannot be undone." }) then
            U.showBusy("Archive", "Clearing...")
            Store.clear(r)
            B.marks = {}
            B.ver = B.ver + 1
        end
    end
end

function A.storage()
    local sel, top = 1, 1
    local per = 4
    while true do
        Store.refresh()
        local roots = Store.roots
        local W, H = U.size()
        local rows = math.max(1, math.floor((H - 2) / per))
        sel = clamp(sel, 1, #roots)
        if sel < top then top = sel elseif sel > top + rows - 1 then top = sel - rows + 1 end
        top = math.max(1, top)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        U.header("Storage  " .. modeLabel(cfg.mode))
        local writing = {}
        for _, t in ipairs(Store.targets(1)) do writing[t.id] = true end
        for n = 0, rows - 1 do
            local r = roots[top + n]
            if not r then break end
            local y = 2 + n * per
            local info = Store.info(r)
            local on = top + n == sel
            term.setCursorPos(1, y)
            term.setBackgroundColor(on and colors.lightBlue or colors.black)
            term.setTextColor(on and colors.black or (writing[r.id] and colors.lime or colors.white))
            term.write(padTo(" " .. r.label .. (writing[r.id] and "   [saving here]" or ""), W))
            local frac = 0
            if info.cap and info.free ~= math.huge then
                frac = 1 - info.free / info.cap
            elseif info.free ~= math.huge then
                frac = info.used / math.max(1, info.used + info.free)
            end
            U.bar(y + 1, 3, math.max(8, W - 4), frac, colors.blue)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.lightGray)
            term.setCursorPos(3, y + 2)
            term.write(padTo(plural(info.count, "message") .. "   archive " .. fmt(info.used) .. "   free " .. fmt(info.free), W - 4))
        end
        if Store.bad > 0 then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.orange)
            term.setCursorPos(2, H - 1)
            term.write(padTo(plural(Store.bad, "damaged log") .. " skipped.", W - 2))
        end
        U.footerButtons({
            { tag = "Ent", label = "Manage", k = "enter" },
            { tag = "R", label = "Rescan", k = "r" },
            { tag = "Q", label = "Back", k = "q" },
        })
        local i = A.event()
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #roots then
            sel = sel + 1
        elseif i.scroll then
            sel = clamp(sel + i.scroll, 1, #roots)
        elseif i.k == "r" then
            U.showBusy("Archive", "Reading storage...")
            Store.scan()
        elseif i.k == "enter" then
            U.restore()
            A.manageRoot(roots[sel])
        elseif i.k == "q" then
            U.restore()
            return
        elseif i.click and i.y >= 2 and i.y < H - 1 then
            local n = top + math.floor((i.y - 2) / per)
            if roots[n] then
                sel = n
                U.restore()
                A.manageRoot(roots[n])
            end
        end
    end
end

-- ── Settings ─────────────────────────────────────────────────────────────────

function A.settings()
    local RESERVE = { 8192, 32768, 131072, 524288 }
    local MAXREC = { 16384, 65536, 262144, 0 }

    local function listLabels(values)
        local out = {}
        for n, v in ipairs(values) do out[n] = v == 0 and "No limit" or fmt(v) end
        return out
    end

    local function indexOf(values, v)
        for n, x in ipairs(values) do
            if x == v then return n end
        end
        return 1
    end

    local function change(n)
        if n == 1 then
            A.toggleRecord()
        elseif n == 2 then
            Store.refresh()
            local modes = { "computer", "overflow", "disks", "mirror" }
            local labels = {
                "Computer only", "Computer, then disks when full",
                "Disks only (fill one, then the next)", "Mirror to the computer and every disk",
            }
            for i = 2, #Store.roots do
                modes[#modes + 1] = Store.roots[i].id
                labels[#labels + 1] = "Only " .. Store.roots[i].label
            end
            local pick = U.pickMenu("Save to", labels, indexOf(modes, cfg.mode))
            if pick then cfg.mode = modes[pick] end
        elseif n == 3 then
            local v = U.ask("Archive folder", {
                "Folder name used on the computer and on every disk:",
                "Changing it hides archives saved under the old name.",
            }, cfg.folder)
            if v then
                v = fs.combine("", v)
                if v == "" or v == "rom" or v:sub(1, 4) == "rom/" then
                    U.showMessage("Archive folder", { "That folder cannot be used." }, colors.red)
                else
                    cfg.folder = v
                    U.showBusy("Archive", "Reading storage...")
                    Store.scan()
                    B.ver = B.ver + 1
                end
            end
        elseif n == 4 then
            local pick = U.pickMenu("Keep free on the computer", listLabels(RESERVE), indexOf(RESERVE, cfg.reserve))
            if pick then cfg.reserve = RESERVE[pick] end
        elseif n == 5 then
            local pick = U.pickMenu("Most kept per message", listLabels(MAXREC), indexOf(MAXREC, cfg.maxRecord))
            if pick then cfg.maxRecord = MAXREC[pick] end
        elseif n == 6 then
            local pick = U.pickMenu("When all storage is full", { "Stop saving", "Drop the oldest day log" }, cfg.whenFull == "Stop" and 1 or 2)
            if pick == 1 then cfg.whenFull = "Stop" elseif pick == 2 then cfg.whenFull = "Drop oldest" end
        elseif n == 7 then
            local v = U.ask("Ignore protocols", {
                "Protocols to skip, separated by commas (for example: dns,ping).",
                "Leave blank to save everything.",
            }, cfg.ignore ~= "" and cfg.ignore or nil)
            cfg.ignore = v or ""
        elseif n == 8 then
            A.autoPrintMenu()
        elseif n == 9 then
            A.choosePrinter()
        elseif n == 10 then
            local v = U.ask("Export folder", { "Folder for exported files (use disk/name to export to a disk):" }, cfg.exportDir)
            if v then
                v = fs.combine("", v)
                if v == "" or v == "rom" or v:sub(1, 4) == "rom/" then
                    U.showMessage("Export folder", { "That folder cannot be used." }, colors.red)
                else
                    cfg.exportDir = v
                end
            end
        elseif n == 11 then
            U.showMessage("Setup help: receiving", {
                "Archive saves every Rednet message this computer receives, direct or broadcast, while Archive is open.",
                "It needs a modem. Archive opens one if Rednet is not already open.",
                "Leaving Archive stops saving. Use Pause (R on the main menu) to stop without leaving.",
                "Private Messenger messages are opened with the network passphrase from Prismarine OS Settings and saved as protocol private.",
                "Activity reports from Prismarine OS computers (commands, programs, files, errors) are saved as audit_command, audit_app and so on.",
            }, colors.lightBlue)
            U.showMessage("Setup help: disks", {
                "Put a disk drive next to the computer (or on its wired modem network) and insert a floppy disk.",
                "Under Save to, choose Computer then disks, Disks only, Mirror, or one disk.",
                "Disks fill one at a time. Swap in a new disk when one is full.",
            }, colors.lightBlue)
            U.showMessage("Setup help: printing", {
                "Messages print on 25 by 21 pages. Long messages need several pages.",
                "Auto-print prints new messages as they arrive, at most 3 pages each.",
                "In a message, N shows the next older one and B the newer one.",
            }, colors.lightBlue)
        end
        saveCfg()
    end

    A.list({
        title = "Archive settings",
        state = { sel = 1, top = 1 },
        buttons = { { tag = "Ent", label = "Change", k = "enter" }, { tag = "Q", label = "Back", k = "q" } },
        items = function()
            return {
                { label = "Recording: " .. (cfg.record and "on" or "paused") },
                { label = "Save to: " .. modeLabel(cfg.mode) },
                { label = "Archive folder: /" .. cfg.folder },
                { label = "Keep free on the computer: " .. fmt(cfg.reserve) },
                { label = "Most kept per message: " .. (cfg.maxRecord == 0 and "no limit" or fmt(cfg.maxRecord)) },
                { label = "When storage is full: " .. (cfg.whenFull == "Stop" and "stop saving" or "drop the oldest day log") },
                { label = "Ignore protocols: " .. (cfg.ignore ~= "" and cfg.ignore or "none") },
                { label = "Auto-print: " .. A.autoLabel() },
                { label = "Printer: " .. cfg.printer },
                { label = "Export folder: /" .. cfg.exportDir },
                { label = "Setup help" },
            }
        end,
        on = function(k, idx)
            if k == "q" then return true end
            if k == "enter" and idx then
                change(idx)
                U.restore()
            end
        end,
    })
end

-- ── Network check ────────────────────────────────────────────────────────────

function A.netCheck()
    local lines = { Net.sides() }
    local names, total = {}, 0
    for k, h in pairs(S.heard) do
        names[#names + 1] = k
        total = total + h.n
    end
    table.sort(names, function(a, b) return S.heard[a].n > S.heard[b].n end)
    lines[#lines + 1] = "Radio messages seen: " .. S.raw .. ". Rednet messages: " .. total .. "."
    if #names == 0 then
        lines[#lines + 1] = "No Rednet message has arrived yet. Check that a modem is open and in range."
    end
    for i = 1, math.min(8, #names) do
        local h = S.heard[names[i]]
        lines[#lines + 1] = names[i] .. ": " .. h.n .. ", last from #" .. tostring(h.from) .. " at " .. clock(h.t)
    end
    lines[#lines + 1] = "Can open sealed messages: " .. ((api and api.openPrivate) and "yes" or "no (needs Prismarine OS 21)")
    lines[#lines + 1] = "Private chats: " .. (S.privNote or "none heard yet")
    lines[#lines + 1] = "Activity reports: " .. (S.audNote or "none heard yet")
    U.showMessage("Network check", lines, colors.lightBlue)
end

-- ── Main menu ────────────────────────────────────────────────────────────────

-- Messages are only saved while this app is open, so ask before leaving.
function A.leave()
    if cfg.record and Net.sides() ~= "no modem open" then
        return U.confirm({ "Archive stops saving Rednet messages when you leave.", "Leave now?" })
    end
    return true
end

function A.main()
    A.list({
        state = { sel = 1, top = 1 },
        title = function()
            local status = cfg.record and "REC" or "PAUSED"
            if S.errors > 0 then status = status .. " !" end
            return "Archive  " .. status .. "  " .. plural(#Store.entries, "message") .. " stored"
        end,
        buttons = function()
            return {
                { tag = "Ent", label = "Open", k = "enter" },
                { tag = "R", label = cfg.record and "Pause" or "Resume", k = "r" },
                { tag = "Q", label = "Quit", k = "q" },
            }
        end,
        items = function()
            local live = "Live feed"
            if S.session > 0 then live = live .. "  (" .. S.session .. " this session)" end
            if S.lastError then live = live .. "  last error: " .. S.lastError end
            return {
                { label = live, color = cfg.record and colors.lime or colors.yellow },
                { label = "Browse archive", color = colors.cyan },
                { label = "Print", color = colors.cyan },
                { label = "Storage", color = colors.cyan },
                { label = "Settings", color = colors.cyan },
                { label = "Network check", color = colors.cyan },
            }
        end,
        on = function(k, idx)
            if k == "r" then
                A.toggleRecord()
            elseif k == "q" then
                if A.leave() then return true end
            elseif k == "enter" and idx then
                if idx == 1 then A.live()
                elseif idx == 2 then A.browse()
                elseif idx == 3 then A.printMenu()
                elseif idx == 4 then A.storage()
                elseif idx == 5 then A.settings()
                elseif idx == 6 then A.netCheck()
                end
                U.restore()
            end
        end,
    })
end

-- ── Loading screen ───────────────────────────────────────────────────────────
-- The OS boot screen with "ARCHIVE" as the logo while Rednet, the disks and the
-- stored messages are read for real.

function A.boot()
    local sc = api and api.boot and api.gfx and api.boot.start(false, "ARCHIVE")
    if not sc then
        Net.ensure()
        Store.scan()
        return
    end
    sc.tag = "Archive  v" .. VERSION
    api.boot.stage(sc, "Starting", 0.15)
    api.boot.stage(sc, "Opening Rednet", 0.35, function() Net.ensure() end)
    api.boot.stage(sc, "Finding disks", 0.55, function() Store.discover() end)
    api.boot.stage(sc, "Reading the archive", 0.85, function(tick)
        Store.scan(tick)
        if tick then tick() end
    end)
    api.boot.stage(sc, plural(#Store.entries, "message") .. " stored", 0.95)
    api.boot.finish(sc)
    api.restorePalette()
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local function main()
    if not term.isColour() then
        print("Prismarine Archive needs an advanced computer (colour).")
        return
    end
    math.randomseed(os.epoch("utc"))
    A.boot()
    if api and api.auditLoopback then pcall(api.auditLoopback, true) end
    local ok, err = pcall(function()
        parallel.waitForAny(A.main, Net.task, Prn.task)
    end)
    if api and api.auditLoopback then pcall(api.auditLoopback, false) end
    U.restore()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorBlink(false)
    term.clear()
    term.setCursorPos(1, 1)
    if not ok and not tostring(err):find("Terminated") then
        print("Prismarine Archive stopped: " .. tostring(err))
        print("Press any key.")
        os.pullEvent("key")
    end
end

main()
