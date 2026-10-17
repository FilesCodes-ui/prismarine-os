-- Simple OS v3 for CC:Tweaked
-- Save this file as /startup.lua on the computer.
-- Features: program launcher, clock, pastebin downloader, modem messenger
-- (keeps receiving while programs run), disk and ROM manager.

local W, H = term.getSize()

local PROTO = "simpleos_msg"
local NAME_FILE = ".simpleos_name"

-- Folders to scan for programs. "" is the root folder.
local FOLDERS = { "", "programs", "rom/programs" }

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
            if not rednet.isOpen(side) then rednet.open(side) end
            found = true
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

-- Handles every network message. Runs in the menu, in every built-in app, and
-- in the background while a program runs, so this computer always answers
-- discovery requests and stores incoming messages.
local function handleNet(sender, msg, protocol)
    if protocol ~= PROTO or type(msg) ~= "table" then return end
    local name = tostring(msg.name or "Unknown")
    if msg.type == "discover" then
        net.peers[sender] = { name = name }
        rednet.send(sender, { type = "hello", name = myName }, PROTO)
    elseif msg.type == "hello" then
        net.peers[sender] = { name = name }
    elseif msg.type == "msg" then
        net.peers[sender] = { name = name }
        local key = msg.all and "all" or sender
        addHistory(key, { who = name, text = tostring(msg.text or ""), mine = false })
        net.unread[key] = (net.unread[key] or 0) + 1
    end
end

-- Runs next to a launched program. Every coroutine receives each event, so
-- the program and this listener both see network messages.
local function backgroundNet()
    while true do
        local _, a, b, c = os.pullEventRaw("rednet_message")
        handleNet(a, b, c)
    end
end

-- ── Drawing helpers ──────────────────────────────────────────────────────────

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

local function footer(text)
    term.setCursorPos(1, H)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(pad(" " .. text, W))
end

local function drawList(title, entries, sel, top, foot)
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
    footer(foot)
end

local function clampTop(sel, top, count)
    local visible = H - 2
    if sel < top then top = sel end
    if sel > top + visible - 1 then top = sel - visible + 1 end
    if top < 1 then top = 1 end
    return top
end

local function waitKey()
    while true do
        local ev, a, b, c = os.pullEventRaw()
        if ev == "key" then return end
        if ev == "rednet_message" then handleNet(a, b, c) end
    end
end

local function showMessage(title, lines, color)
    term.setBackgroundColor(colors.black)
    term.clear()
    header(title)
    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    for i, l in ipairs(lines) do
        term.setCursorPos(2, i + 2)
        term.write(l:sub(1, W - 2))
    end
    footer("Press any key")
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
    for i, l in ipairs(lines) do
        term.setCursorPos(2, 2 + i)
        term.write(l:sub(1, W - 2))
    end
    footer("Leave blank to cancel")
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

-- Returns true when the user presses Y.
local function confirm(lines)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header("Confirm")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    for i, l in ipairs(lines) do
        term.setCursorPos(2, 2 + i)
        term.write(l:sub(1, W - 2))
    end
    footer("Y = yes, Enter = no")
    while true do
        local ev, a, b, c = os.pullEventRaw()
        if ev == "char" then
            return a:lower() == "y"
        elseif ev == "key" and (a == keys.enter or a == keys.tab or a == keys.backspace) then
            return false
        elseif ev == "rednet_message" then
            handleNet(a, b, c)
        end
    end
end

-- Shows a short list of options. Returns the chosen number or nil.
local function pickMenu(title, options)
    local entries = {}
    for i, o in ipairs(options) do entries[i] = { label = o } end
    local sel = 1
    while true do
        drawList(title, entries, sel, 1, "Enter=select Q=back")
        local ev, a, b, c = os.pullEventRaw()
        if ev == "key" then
            if a == keys.up and sel > 1 then
                sel = sel - 1
            elseif a == keys.down and sel < #entries then
                sel = sel + 1
            elseif a == keys.enter then
                return sel
            elseif a == keys.q or a == keys.backspace then
                return nil
            end
        elseif ev == "mouse_click" then
            if c >= 2 and entries[c - 1] then return c - 1 end
        elseif ev == "rednet_message" then
            handleNet(a, b, c)
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
    rednet.broadcast({ type = "discover", name = myName }, PROTO)
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
    for i = start, #lines do
        term.setCursorPos(1, 2 + i - start)
        term.setTextColor(lines[i].mine and colors.lime or colors.white)
        term.write(lines[i].text)
    end

    local shown = "> " .. input
    if #shown > W - 1 then shown = shown:sub(-(W - 1)) end
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(pad(shown, W))
    footer("Enter=send Tab=back")
    term.setCursorPos(math.min(#shown + 1, W), H - 1)
    term.setBackgroundColor(colors.gray)
    term.setCursorBlink(true)
end

local function chat(entry)
    local input = ""
    while true do
        net.unread[entry.key] = nil
        drawChat(entry, input)
        local ev, a, b, c = os.pullEventRaw()
        if ev == "char" or ev == "paste" then
            input = input .. a
        elseif ev == "key" then
            if a == keys.enter and input ~= "" then
                if entry.key == "all" then
                    rednet.broadcast({ type = "msg", name = myName, text = input, all = true }, PROTO)
                else
                    rednet.send(entry.id, { type = "msg", name = myName, text = input }, PROTO)
                end
                addHistory(entry.key, { who = "You", text = input, mine = true })
                input = ""
            elseif a == keys.backspace then
                input = input:sub(1, -2)
            elseif a == keys.tab then
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
            e.color = colors.white
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top, #entries)

        drawList("Messenger: " .. myName, entries, sel, top, "Enter=chat R=rescan N=rename Q=back")

        local ev, a, b, c = os.pullEventRaw()
        if ev == "key" then
            if a == keys.up and sel > 1 then
                sel = sel - 1
            elseif a == keys.down and sel < #entries then
                sel = sel + 1
            elseif a == keys.enter then
                chat(entries[sel])
            elseif a == keys.r then
                discover(1.5)
            elseif a == keys.n then
                local name = ask("Rename", { "New name:" }, myName)
                if name then
                    myName = name:sub(1, 20)
                    saveName(myName)
                end
            elseif a == keys.q then
                return
            end
        elseif ev == "mouse_click" then
            local idx = top + (c - 2)
            if c >= 2 and c <= H - 1 and entries[idx] then
                sel = idx
                chat(entries[idx])
            end
        elseif ev == "rednet_message" then
            handleNet(a, b, c)
        elseif ev == "term_resize" then
            W, H = term.getSize()
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

    local function activate(item)
        if not item then return end
        if item.isDir then
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
        top = clampTop(sel, top, #shown)

        local title = "/" .. path
        if fs.isReadOnly(path) then
            title = title .. "  read-only"
        else
            title = title .. "  free " .. fmtSize(fs.getFreeSpace(path))
        end
        local foot = drive and "Enter=open C=copy D=del N=folder M=menu Q=up"
            or "Enter=open C=copy D=del N=folder Q=up"
        drawList(title, shown, sel, top, foot)

        local ev, a, b, c = os.pullEventRaw()
        if ev == "key" then
            local item = items[sel]
            if a == keys.up and sel > 1 then
                sel = sel - 1
            elseif a == keys.down and sel < #items then
                sel = sel + 1
            elseif a == keys.enter then
                activate(item)
            elseif a == keys.q or a == keys.backspace then
                if path == root then return end
                path = fs.getDir(path)
                sel, top = 1, 1
            elseif a == keys.c and item then
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
            elseif a == keys.d and item then
                if fs.isReadOnly(item.full) then
                    showMessage("Delete", { "This location is read-only." }, colors.red)
                elseif confirm({ "Delete " .. item.full .. "?" }) then
                    local ok, err = pcall(fs.delete, item.full)
                    if not ok then showMessage("Delete", { tostring(err) }, colors.red) end
                end
            elseif a == keys.n then
                if fs.isReadOnly(path) then
                    showMessage("New folder", { "This location is read-only." }, colors.red)
                else
                    local name = ask("New folder", { "Folder name:" })
                    if name then
                        local ok, err = pcall(fs.makeDir, fs.combine(path, name))
                        if not ok then showMessage("New folder", { tostring(err) }, colors.red) end
                    end
                end
            elseif a == keys.m and drive then
                if driveMenu(drive, root) == "exit" then return end
            end
        elseif ev == "mouse_click" then
            local idx = top + (c - 2)
            if c >= 2 and c <= H - 1 and items[idx] then
                sel = idx
                activate(items[idx])
            end
        elseif ev == "rednet_message" then
            handleNet(a, b, c)
        elseif ev == "term_resize" then
            W, H = term.getSize()
        end
    end
end

local function diskApp()
    local sel, top = 1, 1
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
        top = clampTop(sel, top, #entries)
        drawList("Disks and ROM", entries, sel, top, "Enter=open Q=back")

        local ev, a, b, c = os.pullEventRaw()
        local function open(e)
            if e.path then
                browse(e.path, e.drive)
            else
                showMessage("Disks and ROM", { e.note }, colors.yellow)
            end
        end
        if ev == "key" then
            if a == keys.up and sel > 1 then
                sel = sel - 1
            elseif a == keys.down and sel < #entries then
                sel = sel + 1
            elseif a == keys.enter then
                open(entries[sel])
            elseif a == keys.q then
                return
            end
        elseif ev == "mouse_click" then
            local idx = top + (c - 2)
            if c >= 2 and c <= H - 1 and entries[idx] then
                sel = idx
                open(entries[idx])
            end
        elseif ev == "rednet_message" then
            handleNet(a, b, c)
        elseif ev == "term_resize" then
            W, H = term.getSize()
        end
        -- Disk and peripheral events fall through and redraw the list.
    end
end

-- ── Main menu ────────────────────────────────────────────────────────────────

local APPS = {
    messenger = messengerApp,
    pastebin  = pastebinApp,
    disks     = diskApp,
}

local function scan()
    local programs, seen = {}, {}
    for _, dir in ipairs(FOLDERS) do
        if fs.exists(dir) and fs.isDir(dir) then
            for _, name in ipairs(fs.list(dir)) do
                local path = fs.combine(dir, name)
                if not fs.isDir(path)
                    and name:sub(-4) == ".lua"
                    and name ~= "startup.lua" then
                    local label = name:sub(1, -5)
                    if not seen[label] then
                        seen[label] = true
                        table.insert(programs, { label = label, path = path })
                    end
                end
            end
        end
    end
    table.sort(programs, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    local list = {
        { label = "Messenger",         app = "messenger", color = colors.cyan },
        { label = "Pastebin Download", app = "pastebin",  color = colors.cyan },
        { label = "Disks and ROM",     app = "disks",     color = colors.cyan },
    }
    for _, p in ipairs(programs) do table.insert(list, p) end
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

    -- The listener runs beside the program, so messages keep arriving.
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

    local function view()
        local out = {}
        local unread = unreadTotal()
        for i, item in ipairs(items) do
            local label = item.label
            if item.app == "messenger" and unread > 0 then
                label = label .. " (" .. unread .. ")"
            end
            out[i] = { label = label, color = item.color }
        end
        return out
    end

    local function open(idx)
        launch(items[idx])
        W, H = term.getSize()
        openModems()
        items = scan()
        if sel > #items then sel = #items end
        top = clampTop(sel, top, #items)
        timer = os.startTimer(1)
    end

    while true do
        drawList("Simple OS", view(), sel, top, "Arrows+Enter or click | R = refresh")
        local ev, a, b, c = os.pullEventRaw()

        if ev == "key" then
            if a == keys.up and sel > 1 then
                sel = sel - 1
            elseif a == keys.down and sel < #items then
                sel = sel + 1
            elseif a == keys.pageUp then
                sel = math.max(1, sel - (H - 2))
            elseif a == keys.pageDown then
                sel = math.min(#items, sel + (H - 2))
            elseif a == keys.home then
                sel = 1
            elseif a == keys["end"] then
                sel = #items
            elseif a == keys.r then
                items = scan()
                if sel > #items then sel = #items end
            elseif a == keys.enter then
                open(sel)
            end
            top = clampTop(sel, top, #items)

        elseif ev == "mouse_click" then
            local idx = top + (c - 2)
            if c >= 2 and c <= H - 1 and items[idx] then
                sel = idx
                open(idx)
            end

        elseif ev == "mouse_scroll" then
            local maxTop = math.max(1, #items - (H - 2) + 1)
            top = math.min(maxTop, math.max(1, top + a))

        elseif ev == "rednet_message" then
            handleNet(a, b, c)

        elseif ev == "term_resize" then
            W, H = term.getSize()
            top = clampTop(sel, top, #items)

        elseif ev == "timer" and a == timer then
            timer = os.startTimer(1)
        end
        -- The terminate event is ignored here, so Ctrl+T does not close the menu.
    end
end

main()
