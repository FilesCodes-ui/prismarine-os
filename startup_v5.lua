-- Simple OS v4 for CC:Tweaked 1.20.1
-- Save this file as /startup.lua on the computer.
-- Every action has a clickable button and a keyboard shortcut.
-- Errors are shown on screen and saved to /simpleos_error.log.

local W, H = term.getSize()

local PROTO = "simpleos_msg"
local NAME_FILE = ".simpleos_name"
local LOG_FILE = "simpleos_error.log"

-- The menu lists every .lua file on the computer and on inserted disks, in all
-- folders. ROM programs (ls, cd, copy and so on) stay hidden until you press T.
local showRom = false

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

local function header(title)
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write(title:sub(1, W - 2))
    local clock = os.date("%H:%M") .. " | " .. textutils.formatTime(os.time(), true)
    if W >= #title + #clock + 4 then
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
                term.setBackgroundColor(colors.lightBlue)
                term.setTextColor(colors.black)
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
local function ask(title, lines, default)
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
    local ok, value = pcall(read, nil, nil, nil, default)
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

local APPS = {
    messenger = messengerApp,
    pastebin  = pastebinApp,
    disks     = diskApp,
    inputtest = inputTestApp,
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
        { label = "Messenger",         app = "messenger", color = colors.cyan },
        { label = "Pastebin Download", app = "pastebin",  color = colors.cyan },
        { label = "Disks and ROM",     app = "disks",     color = colors.cyan },
        { label = "Input Test",        app = "inputtest", color = colors.cyan },
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
        drawList("Simple OS", view(), sel, top, mainButtons())
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
