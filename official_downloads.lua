-- Prismarine Downloads
-- Runs inside Prismarine OS. The OS downloads this file from the update repo
-- into .prismdl/downloads.lua the first time Download is opened, and passes in
-- its screen helpers. It is not a program you run by hand.
--
--   Official files   scans the GitHub repo and lists the files made for
--                    Prismarine (the OS startup files and the license are
--                    hidden).
--   Custom link      downloads any https link. GitHub and Pastebin page
--                    links are turned into raw links for you.
--   Import from PC   Drop files onto the window, join split parts, or pull
--                    files of any size (18 GB and up) from a PC running
--                    prismarine_share.py. Interrupted downloads resume.

local api = ...
if type(api) ~= "table" or not api.header then
    error("Open Download from the Prismarine OS menu.", 0)
end

local VERSION = "3"

local settings, header, footer, footerButtons = api.settings, api.header, api.footer, api.footerButtons
local drawList, drawCard, clampTop = api.drawList, api.drawCard, api.clampTop
local ask, confirm, pickMenu = api.ask, api.confirm, api.pickMenu
local showMessage, showBusy = api.showMessage, api.showBusy
local readInput, fmtSize, pad, nowSec = api.readInput, api.fmtSize, api.pad, api.nowSec
local gfx, boot = api.gfx, api.boot

local W, H = api.size()

local D = {}            -- every function of this app lives here
D.req = 0
D.CACHE = ".prismdl/list"
D.STEP = 262144         -- bytes read and written per step

-- ── Small helpers ────────────────────────────────────────────────────────────

local function num(n) return string.format("%.0f", n) end

local function refreshSize()
    api.resize()
    W, H = api.size()
end

-- Lets other events run (the monitor dashboard keeps ticking).
function D.yield()
    os.queueEvent("dl_yield")
    os.pullEventRaw("dl_yield")
end

function D.free(n)
    if n == math.huge or n > 2 ^ 50 then return "unlimited" end
    return fmtSize(n)
end

function D.eta(secs)
    if not secs or secs ~= secs or secs == math.huge or secs < 0 then return "?" end
    secs = math.floor(secs)
    if secs >= 3600 then
        return string.format("%dh %02dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
    elseif secs >= 60 then
        return string.format("%dm %02ds", math.floor(secs / 60), secs % 60)
    end
    return secs .. "s"
end

-- Turns a raw event into the table readInput returns. Used by screens that
-- also need events readInput does not pass on.
function D.translate(ev)
    local name = ev[1]
    if name == "mouse_scroll" then
        return { scroll = ev[2] }
    elseif name == "rednet_message" then
        api.handleNet(ev[2], ev[3], ev[4])
        return {}
    elseif name == "term_resize" then
        refreshSize()
        return { resized = true }
    end
    return api.inputFrom(ev[1], ev[2], ev[3], ev[4])
end

-- A file name that is safe to create: no folders, no hidden dot files, and
-- (when the setting is on) no spaces or odd characters.
function D.safeName(name)
    name = tostring(name or ""):gsub("\\", "/")
    name = name:match("([^/]*)$") or ""
    name = name:gsub("%c", "")
    name = name:gsub("^%.+", "")
    if settings.importClean then
        name = name:gsub("%s+", "_")
        name = name:gsub("[^%w%._%-%(%)]", "_")
    end
    name = name:sub(1, 80)
    if name == "" then return nil end
    return name
end

-- name.ext becomes name (2).ext, then name (3).ext, until it is free.
function D.unique(dir, name)
    local base, ext = name:match("^(.*)(%.[^%.]*)$")
    if not base or base == "" then base, ext = name, "" end
    local n = 2
    while true do
        local try = base .. " (" .. n .. ")" .. ext
        if not fs.exists(fs.combine(dir, try)) then return try end
        n = n + 1
    end
end

-- Files the OS needs. This app never overwrites, renames or deletes them.
function D.protected(path)
    path = fs.combine("", path)
    local first = path:match("^([^/]*)") or path
    if path == fs.combine("", api.SELF) or path == "startup.lua" or path == "startup" then return true end
    if path == api.SETTINGS_FILE or path == api.SECURE_FILE then return true end
    if first == "rom" or first == ".prismshell" or first == ".prismdl" then return true end
    return false
end

-- Makes sure the save folder exists and can be written to. Returns its path.
function D.dirReady()
    local dir = fs.combine("", tostring(settings.importDir or ""))
    local ok, err = pcall(function()
        if fs.exists(dir) and not fs.isDir(dir) then error(dir .. " is a file", 0) end
        if not fs.exists(dir) then fs.makeDir(dir) end
        if fs.isReadOnly(dir) then error(dir .. " is read only", 0) end
    end)
    if not ok then
        showMessage("Downloads", {
            "Cannot use the save folder.", tostring(err),
            "Change it in Settings.",
        }, colors.red)
        return nil
    end
    return dir
end

-- Where to write a file called name. Follows the "if file exists" setting.
-- Returns nil when the file is skipped.
function D.target(dir, name)
    local path = fs.combine(dir, name)
    if D.protected(path) then
        showMessage("Downloads", { name .. " is a system file.", "It will not be replaced." }, colors.red)
        return nil
    end
    if fs.exists(path) then
        if fs.isDir(path) then return nil end
        local mode = settings.importOverwrite
        if mode == "Rename" then
            path = fs.combine(dir, D.unique(dir, name))
        elseif mode ~= "Replace" then
            if not confirm({ name .. " already exists.", "Replace it?" }) then return nil end
        end
    end
    return path
end

function D.room(dir, need)
    local free = fs.getFreeSpace(dir == "" and "/" or dir)
    return free >= need, free
end

-- A full screen progress display with a Pixelbox bar. cancel adds a Cancel button.
function D.draw(title, lines, frac, status, cancel)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    header(title)
    local below = drawCard(3, lines, colors.lightBlue, colors.white)
    local row = math.min(below + 1, H - 3)
    local width = math.max(8, W - 4)
    frac = math.max(0, math.min(1, frac or 0))
    if not gfx.progress(row, 3, width, frac) then
        local fill = math.floor(width * frac + 0.5)
        term.setCursorPos(3, row)
        term.setBackgroundColor(api.colorValue(settings.barColor, colors.blue))
        term.write(string.rep(" ", fill))
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", width - fill))
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(3, math.min(row + 1, H - 1))
    term.write(pad(status or "", W - 4))
    if cancel then
        footerButtons({ { tag = "Q", label = "Cancel", k = "q" } })
    else
        footer("Working...")
    end
end

-- ── One HTTP request that Q cancels ──────────────────────────────────────────
-- Returns the body and status code, or nil, the reason, the status code (if
-- any), and true when cancelled. tick (optional) is called about 20 times a
-- second so a loading screen keeps moving.

function D.http(url, headers, redraw, tick)
    if not http then return nil, "HTTP is disabled on this server" end
    D.req = D.req + 1
    local full = url .. (url:find("?", 1, true) and "&" or "?") .. "n=" .. D.req .. "x" .. os.epoch("utc")
    local ok, err = http.request({ url = full, headers = headers, binary = true })
    if ok == false then return nil, tostring(err) end
    local timer = os.startTimer(45)
    local anim = tick and os.startTimer(0.05)
    while true do
        local ev = table.pack(os.pullEventRaw())
        local name = ev[1]
        if name == "http_success" and ev[2] == full then
            os.cancelTimer(timer)
            local h = ev[3]
            local code = h.getResponseCode()
            local body = h.readAll()
            h.close()
            return body or "", code
        elseif name == "http_failure" and ev[2] == full then
            os.cancelTimer(timer)
            local h, code = ev[4], nil
            if type(h) == "table" then
                pcall(function() code = h.getResponseCode() end)
                pcall(h.close)
            end
            return nil, tostring(ev[3]), code
        elseif name == "timer" and ev[2] == timer then
            return nil, "timed out"
        elseif name == "timer" and anim and ev[2] == anim then
            tick()
            anim = os.startTimer(0.05)
        elseif name == "terminate" then
            error("Terminated", 0)
        else
            local i = D.translate(ev)
            if i and i.k == "q" and not tick then
                os.cancelTimer(timer)
                return nil, "cancelled", nil, true
            end
            if i and i.resized and redraw then redraw() end
        end
    end
end

-- Plain words for the errors people hit most.
function D.explain(err, code)
    local text = tostring(err):lower()
    if text:find("permit") or text:find("not allowed") or text:find("blocked") then
        return {
            "The server's HTTP rules do not allow this address.",
            "For a PC, add an allow rule in computercraft-server.toml (Settings > Setup help).",
        }
    elseif text:find("refused") or text:find("connect") or text:find("unknown host") or text:find("timed out") then
        return {
            "Could not reach the address.",
            "For a PC: is prismarine_share.py running, and is the address right?",
            "A server hosted online cannot reach a PC at home.",
        }
    elseif code == 403 or code == 429 then
        return { "GitHub is limiting requests. Try again in a few minutes." }
    elseif code then
        return { "The server answered with status " .. code .. "." }
    end
    return {}
end

-- ── Saving a file from a link ────────────────────────────────────────────────

-- Writes body to dir/name after the usual checks. Returns true when saved.
function D.saveBody(title, name, body)
    local dir = D.dirReady()
    if not dir then return false end
    local safe = D.safeName(name)
    if not safe then
        showMessage(title, { "That file name cannot be used." }, colors.red)
        return false
    end
    if safe:sub(-4):lower() == ".lua" then
        local fn, err = load(body, "=" .. safe)
        if not fn then
            showMessage(title, { "The file has a Lua syntax error.", tostring(err), "It was not saved." }, colors.red)
            return false
        end
    elseif body:sub(1, 15):lower():find("<!doctype html", 1, true) or body:sub(1, 6):lower() == "<html>" then
        if not confirm({ "This looks like a web page, not a file.", "Save it anyway?" }) then return false end
    end
    local path = D.target(dir, safe)
    if not path then return false end
    local room, free = D.room(dir, #body)
    if not room then
        showMessage(title, { safe .. " needs " .. fmtSize(#body) .. ".", "Only " .. D.free(free) .. " is free." }, colors.red)
        return false
    end
    local f = fs.open(path, "wb")
    if not f then
        showMessage(title, { "Cannot write " .. path }, colors.red)
        return false
    end
    f.write(body)
    f.close()
    showMessage(title, { "Saved " .. path, fmtSize(#body) }, colors.lime)
    return true
end

function D.fetchAndSave(title, url, name, want)
    D.draw(title, { "Downloading " .. name, url }, 0, "Waiting for the server...", true)
    local body, code, status, cancelled = D.http(url, nil, nil)
    if not body then
        if cancelled then return false end
        local lines = { "Download failed.", tostring(code) }
        for _, l in ipairs(D.explain(code, status)) do table.insert(lines, l) end
        showMessage(title, lines, colors.red)
        return false
    end
    if code ~= 200 or body == "" then
        showMessage(title, { "The server answered with status " .. tostring(code) .. "." }, colors.red)
        return false
    end
    if want then
        D.draw(title, { "Checking SHA-256..." }, 1, "", false)
        if api.sha256(body) ~= want then
            api.restorePalette()
            showMessage(title, { "The file does not match the hash.", "Nothing was saved." }, colors.red)
            return false
        end
    end
    api.restorePalette()
    return D.saveBody(title, name, body)
end

-- ── Official files (GitHub) ──────────────────────────────────────────────────

local DESCRIBE = {
    { "^p%.shell_v", "Prismarine Shell" },
    { "^p%.audio_v", "Audio player" },
    { "^prismarine_share%.py$", "PC helper for Import" },
}

function D.hidden(name)
    local n = name:lower()
    if n:sub(1, 1) == "." then return true end
    if n:match("^startup") then return true end
    if n:match("^licen[sc]e") then return true end
    if n:match("^readme") then return true end
    if n == "official_downloads.lua" then return true end
    return false
end

function D.describe(name)
    for _, d in ipairs(DESCRIBE) do
        if name:match(d[1]) then return d[2] end
    end
    return nil
end

-- Reads the file list from GitHub. Falls back to the list saved last time.
-- Returns the list, a note, and true when the list is from the saved copy.
function D.scan(tick)
    local repo, branch = api.repoParts()
    local url = "https://api.github.com/repos/" .. repo .. "/contents/?ref=" .. branch
    local body, why, status = D.http(url, nil, nil, tick)
    local files
    if body then
        local data = textutils.unserialiseJSON(body)
        if type(data) == "table" then
            files = {}
            for _, f in ipairs(data) do
                if type(f) == "table" and f.type == "file" and type(f.name) == "string"
                    and not D.hidden(f.name) then
                    table.insert(files, { name = f.name, size = tonumber(f.size) or 0 })
                end
            end
        else
            why = "GitHub sent an unexpected answer"
        end
    end
    if files then
        table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
        pcall(function()
            fs.makeDir(".prismdl")
            local out = fs.open(D.CACHE, "w")
            out.write(textutils.serialize(files))
            out.close()
        end)
        return files, "Found " .. #files .. " official file" .. (#files == 1 and "" or "s")
    end
    if fs.exists(D.CACHE) then
        local f = fs.open(D.CACHE, "r")
        local saved = f and textutils.unserialize(f.readAll() or "")
        if f then f.close() end
        if type(saved) == "table" then
            return saved, "Offline. Showing the saved list", true
        end
    end
    local note = tostring(why)
    local more = D.explain(why, status)
    if more[1] then note = more[1] end
    return nil, note
end

-- Splits p.shell_v2.lua into group "p.shell" and number 2.
function D.groupOf(name)
    local base, n = name:match("^(.-)_v(%d+)%.lua$")
    if base then return base, tonumber(n) end
    return nil
end

function D.visible(files, showAll)
    if showAll then return files end
    local best = {}
    for _, f in ipairs(files) do
        local g, n = D.groupOf(f.name)
        if g and (not best[g] or n > best[g]) then best[g] = n end
    end
    local out = {}
    for _, f in ipairs(files) do
        local g, n = D.groupOf(f.name)
        if not g or best[g] == n then table.insert(out, f) end
    end
    return out
end

function D.officialApp()
    if not D.files then
        showMessage("Official files", { "The file list is not loaded.", "Open Official files again." }, colors.yellow)
        return
    end
    local sel, top, showAll = 1, 1, false
    local repo = api.repoParts()
    local function buttons()
        return {
            { tag = "Ent", label = "Download", k = "enter" },
            { tag = "A", label = showAll and "Newest only" or "All versions", k = "a" },
            { tag = "R", label = "Refresh", k = "r" },
            { tag = "Q", label = "Back", k = "q" },
        }
    end
    local function get(f)
        local url = api.rawUrl(f.name)
        D.fetchAndSave("Official files", url, f.name)
        api.restorePalette()
    end
    while true do
        local files = D.visible(D.files, showAll)
        local entries = {}
        for n, f in ipairs(files) do
            local path = fs.combine(fs.combine("", tostring(settings.importDir or "")), f.name)
            local state, color = "", nil
            if fs.exists(path) and not fs.isDir(path) then
                if fs.getSize(path) == f.size then
                    state, color = "  installed", colors.lime
                else
                    state, color = "  different", colors.yellow
                end
            end
            local desc = D.describe(f.name)
            local label = f.name .. "  " .. fmtSize(f.size) .. state
            if desc and #label + #desc + 3 < W - 3 then label = label .. "  - " .. desc end
            entries[n] = { label = label, color = color }
        end
        if #entries == 0 then
            entries[1] = { label = "No official files in " .. repo, color = colors.gray }
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Official files  " .. repo, entries, sel, top, buttons())
        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.scroll then
            sel = math.max(1, math.min(#entries, sel + i.scroll))
        elseif i.k == "a" then
            showAll = not showAll
            sel, top = 1, 1
        elseif i.k == "r" then
            D.draw("Official files", { "Asking GitHub for its files..." }, 0, "", false)
            local list, note = D.scan(nil)
            if list then
                D.files, D.note = list, note
                sel, top = 1, 1
            else
                showMessage("Official files", { "Could not read GitHub.", tostring(note) }, colors.red)
            end
        elseif i.k == "enter" and files[sel] then
            get(files[sel])
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and files[top + i.y - 2] then
            sel = top + i.y - 2
            get(files[sel])
        end
    end
end

-- ── Custom link ──────────────────────────────────────────────────────────────

-- GitHub and Pastebin page links become raw links.
function D.fixLink(url)
    local user, repo, rest = url:match("^https://github%.com/([^/]+)/([^/]+)/blob/(.+)$")
    if user then
        return "https://raw.githubusercontent.com/" .. user .. "/" .. repo .. "/" .. rest:gsub("[?#].*$", "")
    end
    local code = url:match("^https://pastebin%.com/(%w+)$")
    if code then return "https://pastebin.com/raw/" .. code end
    return url
end

function D.customApp()
    local url = ask("Custom link", {
        "Link to the file (https://...):",
        "GitHub and Pastebin page links work. Only download files you trust.",
    })
    if not url then return end
    if not url:match("^https://[%w%.%-]+/%S+$") then
        showMessage("Custom link", { "That is not a valid https link." }, colors.red)
        return
    end
    url = D.fixLink(url)
    local clean = url:gsub("[?#].*$", "")
    local name = ask("Custom link", { "Save as:" }, clean:match("([^/]+)$") or "download.lua")
    if not name then return end
    if not name:find("%.") then name = name .. ".lua" end
    local want = ask("Custom link", {
        "Expected SHA-256 (optional):",
        "Leave blank to skip the check.",
    })
    if want then
        want = want:lower():gsub("%s", "")
        if not want:match("^%x+$") or #want ~= 64 then
            showMessage("Custom link", { "That is not a SHA-256 hash.", "Nothing was downloaded." }, colors.red)
            return
        end
    end
    D.fetchAndSave("Custom link", url, name, want)
    api.restorePalette()
end

-- ── Import from PC ───────────────────────────────────────────────────────────

-- Copies a dropped file handle into path. Returns true and the size, or false
-- and the reason. A half written file is never left behind.
function D.copy(src, path)
    local tmp = path .. ".importing"
    local total = 0
    local ok, err = pcall(function()
        local out = fs.open(tmp, "wb")
        if not out then error("cannot write " .. path, 0) end
        while true do
            local chunk = src.read(D.STEP)
            if not chunk then break end
            out.write(chunk)
            total = total + #chunk
        end
        out.close()
    end)
    if not ok then
        pcall(fs.delete, tmp)
        return false, tostring(err)
    end
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true, total
end

function D.receive(files, dir, say)
    for _, f in ipairs(files.getFiles()) do
        local name = D.safeName(f.getName())
        if not name then
            say("Skipped a file with no usable name", colors.red)
        else
            local size = f.seek("end") or 0
            f.seek("set", 0)
            local path = D.target(dir, name)
            local room, free = D.room(dir, size)
            if not path then
                say("Skipped " .. name, colors.yellow)
            elseif not room then
                say("No room for " .. name .. " (" .. fmtSize(size) .. ", free " .. D.free(free) .. ")", colors.red)
            else
                local ok, res = D.copy(f, path)
                if ok then
                    say("Saved " .. fs.getName(path) .. "  " .. fmtSize(res), colors.lime)
                    if name:match("%.part%d+$") then
                        say("  That is a part. Use Join parts when all are in.", colors.lightGray)
                    end
                else
                    say("Failed " .. name .. ": " .. res, colors.red)
                end
            end
        end
        pcall(f.close)
    end
end

function D.dropApp()
    local dir = D.dirReady()
    if not dir then return end
    local log = {}
    local function say(text, color)
        table.insert(log, { text = text, color = color or colors.white })
        while #log > 60 do table.remove(log, 1) end
    end

    local function draw()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        header("Import: drop files")
        local free = D.free(fs.getFreeSpace(dir == "" and "/" or dir))
        local below = drawCard(3, {
            "Drag files from your PC onto this window.",
            "Saved to /" .. dir .. "     Free: " .. free,
            "The game refuses very large drops. For those, use Import from PC (HTTP), or split the file with prismarine_share.py, drop the parts, then Join.",
        }, colors.lightBlue, colors.white)
        local rows = H - 1 - below
        for i = 1, rows do
            local e = log[#log - rows + i]
            if e then
                term.setBackgroundColor(colors.black)
                term.setTextColor(e.color)
                term.setCursorPos(2, below + i)
                term.write(e.text:sub(1, W - 2))
            end
        end
        footerButtons({ { tag = "Q", label = "Done", k = "q" } })
    end

    say("Waiting for files...", colors.lightGray)
    draw()
    while true do
        local ev = table.pack(os.pullEventRaw())
        if ev[1] == "file_transfer" then
            D.receive(ev[2], dir, say)
            draw()
        else
            local i = D.translate(ev)
            if i then
                if i.k == "q" then return end
                if i.resized then draw() end
            end
        end
    end
end

-- Finds name.part1, name.part2, ... groups in the save folder.
function D.scanParts(dir)
    local groups, list = {}, {}
    local ok, names = pcall(fs.list, dir)
    if not ok then return list end
    for _, n in ipairs(names) do
        local base, idxText = n:match("^(.+)%.part(%d+)$")
        local path = fs.combine(dir, n)
        if base and not fs.isDir(path) then
            local g = groups[base]
            if not g then
                g = { base = base, parts = {}, total = 0, count = 0, max = 0 }
                groups[base] = g
                table.insert(list, g)
            end
            local idx = tonumber(idxText)
            if not g.parts[idx] then
                g.parts[idx] = path
                g.count = g.count + 1
                g.total = g.total + fs.getSize(path)
                if idx > g.max then g.max = idx end
            end
        end
    end
    for _, g in ipairs(list) do
        for i = 1, g.max do
            if not g.parts[i] then g.missing = i break end
        end
    end
    table.sort(list, function(a, b) return a.base:lower() < b.base:lower() end)
    return list
end

function D.join(dir, g)
    if g.missing then
        showMessage("Join parts", { "Part " .. g.missing .. " of " .. g.base .. " is missing.", "Drop it, then try again." }, colors.red)
        return
    end
    local name = D.safeName(g.base) or g.base
    local target = D.target(dir, name)
    if not target then return end
    local room, free = D.room(dir, g.total)
    if not room then
        showMessage("Join parts", {
            "Not enough room to join " .. name .. ".",
            "Needs " .. fmtSize(g.total) .. ", free " .. D.free(free) .. ".",
        }, colors.red)
        return
    end

    local tmp = target .. ".importing"
    local done, last = 0, 0
    local lines = { "Joining " .. g.max .. " parts into " .. fs.getName(target), fmtSize(g.total) }
    local ok, err = pcall(function()
        local out = fs.open(tmp, "wb")
        if not out then error("cannot write " .. target, 0) end
        for i = 1, g.max do
            local src = fs.open(g.parts[i], "rb")
            if not src then
                out.close()
                error("cannot read part " .. i, 0)
            end
            while true do
                local chunk = src.read(D.STEP)
                if not chunk then break end
                out.write(chunk)
                done = done + #chunk
                if nowSec() - last >= 0.15 then
                    last = nowSec()
                    D.draw("Join parts", lines, done / g.total, "Part " .. i .. " of " .. g.max .. "   " .. fmtSize(done), false)
                    D.yield()
                end
            end
            src.close()
        end
        out.close()
        if fs.getSize(tmp) ~= g.total then error("size check failed", 0) end
    end)
    if not ok then
        pcall(fs.delete, tmp)
        showMessage("Join parts", { "Joining failed.", tostring(err), "The parts were not touched." }, colors.red)
        return
    end
    if fs.exists(target) then fs.delete(target) end
    fs.move(tmp, target)
    if not settings.importKeep then
        for i = 1, g.max do pcall(fs.delete, g.parts[i]) end
    end
    showMessage("Join parts", {
        "Saved " .. target,
        fmtSize(g.total) .. (settings.importKeep and ". Parts kept." or ". Parts deleted."),
    }, colors.lime)
end

function D.joinApp()
    local dir = D.dirReady()
    if not dir then return end
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Join", k = "enter" },
        { tag = "R", label = "Rescan", k = "r" },
        { tag = "Q", label = "Back", k = "q" },
    }
    while true do
        local groups = D.scanParts(dir)
        local entries = {}
        for n, g in ipairs(groups) do
            local state = g.missing and ("missing part " .. g.missing) or (g.count .. " parts")
            entries[n] = {
                label = g.base .. "  " .. state .. "  " .. fmtSize(g.total),
                color = g.missing and colors.yellow or colors.lime,
            }
        end
        if #entries == 0 then
            entries[1] = { label = "No parts found in /" .. dir, color = colors.gray }
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Join parts", entries, sel, top, buttons)
        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" and groups[sel] then
            D.join(dir, groups[sel])
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and groups[top + i.y - 2] then
            sel = top + i.y - 2
            D.join(dir, groups[sel])
        end
    end
end

function D.hostUrl()
    local host = tostring(settings.importHost or "localhost:8000")
    host = host:gsub("^https?://", "")
    host = host:gsub("/+$", "")
    -- "localhost" can resolve to the IPv6 address ::1, which the usual
    -- "127.0.0.0/8" allow rule does not cover. Use the IPv4 loopback instead.
    host = host:gsub("^[Ll][Oo][Cc][Aa][Ll][Hh][Oo][Ss][Tt]", "127.0.0.1")
    return "http://" .. host
end

function D.fetchList(base)
    D.draw("Import from PC", { "Asking " .. base .. " for its files..." }, 0, "", true)
    local body, code, status, cancelled = D.http(base .. "/list", nil, nil)
    if not body then
        if cancelled then return nil end
        local lines = { "Could not get the file list.", tostring(code) }
        for _, l in ipairs(D.explain(code, status)) do table.insert(lines, l) end
        showMessage("Import from PC", lines, colors.red)
        return nil
    end
    local data = textutils.unserializeJSON(body)
    if type(data) ~= "table" or type(data.files) ~= "table" then
        showMessage("Import from PC", { "That is not a prismarine_share.py server." }, colors.red)
        return nil
    end
    local files = {}
    for _, f in ipairs(data.files) do
        if type(f) == "table" and type(f.name) == "string" and tonumber(f.size) then
            table.insert(files, { name = f.name, size = tonumber(f.size), sha256 = f.sha256, mtime = f.mtime })
        end
    end
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)
    return files
end

-- A partly downloaded file keeps a small note beside it so a later run only
-- resumes the same file.
function D.readInfo(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    local data = f and textutils.unserialize(f.readAll() or "")
    if f then f.close() end
    return type(data) == "table" and data or nil
end

function D.writeInfo(path, entry)
    local f = fs.open(path, "w")
    if f then
        f.write(textutils.serialize({ size = entry.size, mtime = entry.mtime }))
        f.close()
    end
end

function D.download(base, entry, dir)
    local name = D.safeName(entry.name)
    if not name then
        showMessage("Import from PC", { "That file name cannot be used." }, colors.red)
        return
    end
    local target = D.target(dir, name)
    if not target then return end

    local tmp = target .. ".importing"
    local info = tmp .. ".info"
    local pos = 0
    if fs.exists(tmp) and not fs.isDir(tmp) then
        local have = fs.getSize(tmp)
        local saved = D.readInfo(info)
        local same = saved and saved.size == entry.size and saved.mtime == entry.mtime
        if same and have > 0 and have < entry.size then
            local pick = pickMenu("Unfinished download", {
                "Resume at " .. fmtSize(have) .. " of " .. fmtSize(entry.size),
                "Start over",
                "Cancel",
            }, 1)
            if pick == 1 then
                pos = have
            elseif pick == 2 then
                pcall(fs.delete, tmp)
            else
                return
            end
        else
            pcall(fs.delete, tmp)
        end
    end

    local need = entry.size - pos
    local room, free = D.room(dir, need)
    if not room then
        showMessage("Import from PC", {
            name .. " needs " .. fmtSize(need) .. " more.",
            "Only " .. D.free(free) .. " is free.",
            "The server's computer_space_limit may need raising (Settings > Setup help).",
        }, colors.red)
        return
    end

    local started, startPos = nowSec(), pos
    local lines = { "Downloading " .. fs.getName(target), fmtSize(entry.size) .. " from " .. tostring(settings.importHost) }
    local function status()
        local secs = math.max(0.5, nowSec() - started)
        local rate = (pos - startPos) / secs
        local text = fmtSize(pos) .. " of " .. fmtSize(entry.size)
        if rate > 0 then
            text = text .. "   " .. fmtSize(rate) .. "/s   " .. D.eta((entry.size - pos) / rate) .. " left"
        end
        return text
    end
    local function redraw()
        D.draw("Import from PC", lines, entry.size > 0 and pos / entry.size or 1, status(), true)
    end

    local out = fs.open(tmp, pos > 0 and "ab" or "wb")
    if not out then
        showMessage("Import from PC", { "Cannot write " .. target }, colors.red)
        return
    end
    D.writeInfo(info, entry)
    -- keep: leave the partial file so the next run resumes.
    local function stop(lines2, color, keep)
        pcall(out.close)
        if not keep then
            pcall(fs.delete, tmp)
            pcall(fs.delete, info)
        end
        api.restorePalette()
        showMessage("Import from PC", lines2, color or colors.red)
    end

    redraw()
    local url = base .. "/file?name=" .. textutils.urlEncode(entry.name)
    local step = math.max(1, math.min(8, tonumber(settings.importChunk) or 2)) * 1048576
    while pos < entry.size do
        local last = math.min(entry.size, pos + step) - 1
        local body, code, st, cancelled = D.http(url, { Range = "bytes=" .. num(pos) .. "-" .. num(last) }, redraw)
        if not body then
            if cancelled then
                return stop({ "Paused at " .. fmtSize(pos) .. ".", "Open this file again to resume." }, colors.yellow, true)
            end
            local msg = { "Download stopped at " .. fmtSize(pos) .. ".", tostring(code), "Open this file again to resume." }
            for _, l in ipairs(D.explain(code, st)) do table.insert(msg, l) end
            return stop(msg, colors.red, true)
        end
        local want = last - pos + 1
        if code == 200 and pos == 0 and #body == entry.size then
            -- The server ignored the range and sent the whole file.
            out.write(body)
            pos = #body
            break
        elseif code ~= 206 or #body ~= want then
            return stop({
                "The PC sent an unexpected answer.",
                "Status " .. tostring(st or code) .. ", got " .. #body .. " of " .. num(want) .. " bytes.",
            }, colors.red, true)
        end
        local ok, err = pcall(function()
            out.write(body)
            out.flush()
        end)
        if not ok then return stop({ "Could not write the file.", tostring(err) }, colors.red, false) end
        pos = pos + #body
        redraw()
        D.yield()
    end
    out.close()

    if fs.getSize(tmp) ~= entry.size then
        pcall(fs.delete, tmp)
        pcall(fs.delete, info)
        api.restorePalette()
        showMessage("Import from PC", { "The saved size does not match.", "Nothing was kept." }, colors.red)
        return
    end

    local verified = false
    if settings.importVerify and entry.sha256 and entry.size <= 8388608 then
        local ticks = 0
        local lines3 = { "Checking SHA-256 of " .. fs.getName(target), "This is slow." }
        D.draw("Import from PC", lines3, 1, "Hashing...", false)
        local sum = api.hashFile(tmp, function()
            ticks = ticks + 1
            if ticks % 40 == 0 then D.draw("Import from PC", lines3, 1, "Hashing... " .. ticks * 512 .. " bytes", false) end
        end)
        if sum ~= tostring(entry.sha256):lower() then
            pcall(fs.delete, tmp)
            pcall(fs.delete, info)
            api.restorePalette()
            showMessage("Import from PC", { "The SHA-256 does not match.", "The file was deleted." }, colors.red)
            return
        end
        verified = true
    end

    if fs.exists(target) then fs.delete(target) end
    fs.move(tmp, target)
    pcall(fs.delete, info)
    api.restorePalette()
    local secs = math.max(0.1, nowSec() - started)
    showMessage("Import from PC", {
        "Saved " .. target,
        fmtSize(entry.size) .. " in " .. D.eta(secs) .. " (" .. fmtSize(entry.size / secs) .. "/s)."
            .. (verified and " SHA-256 verified." or " Size verified."),
    }, colors.lime)
end

function D.pcApp()
    local dir = D.dirReady()
    if not dir then return end
    local base = D.hostUrl()
    local files = D.fetchList(base)
    if not files then return end
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Download", k = "enter" },
        { tag = "R", label = "Refresh", k = "r" },
        { tag = "Q", label = "Back", k = "q" },
    }
    while true do
        local entries = {}
        for n, f in ipairs(files) do
            local safe = D.safeName(f.name) or "?"
            local here = fs.exists(fs.combine(dir, safe))
            local partial = fs.exists(fs.combine(dir, safe .. ".importing"))
            entries[n] = {
                label = f.name .. "  " .. fmtSize(f.size) .. (partial and "  (unfinished)" or (here and "  (on this computer)" or "")),
                color = partial and colors.yellow or (here and colors.lightGray or nil),
            }
        end
        if #entries == 0 then
            entries[1] = { label = "The PC folder has no files.", color = colors.gray }
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Import from PC  " .. tostring(settings.importHost), entries, sel, top, buttons)
        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "r" then
            local again = D.fetchList(base)
            if again then files, sel, top = again, 1, 1 end
        elseif i.k == "enter" and files[sel] then
            D.download(base, files[sel], dir)
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and files[top + i.y - 2] then
            sel = top + i.y - 2
            D.download(base, files[sel], dir)
        end
    end
end

-- ── Files in the save folder ─────────────────────────────────────────────────

function D.filesApp()
    local dir = D.dirReady()
    if not dir then return end
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Manage", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local function manage(name)
        local path = fs.combine(dir, name)
        if D.protected(path) then return end
        local pick = pickMenu(name, { "Delete", "Rename", "Back" })
        if pick == 1 then
            if confirm({ "Delete " .. name .. "?", fmtSize(fs.getSize(path)) }) then
                pcall(fs.delete, path)
            end
        elseif pick == 2 then
            local v = ask("Rename", { "New name for " .. name .. ":" }, name)
            local new = v and D.safeName(v)
            if new and new ~= name then
                if fs.exists(fs.combine(dir, new)) or D.protected(fs.combine(dir, new)) then
                    showMessage("Rename", { new .. " already exists or is protected." }, colors.red)
                else
                    local ok, err = pcall(fs.move, path, fs.combine(dir, new))
                    if not ok then showMessage("Rename", { tostring(err) }, colors.red) end
                end
            end
        end
    end
    while true do
        local names, entries = {}, {}
        local ok, list = pcall(fs.list, dir)
        for _, n in ipairs(ok and list or {}) do
            local p = fs.combine(dir, n)
            if not fs.isDir(p) and not D.protected(p) and n:sub(1, 1) ~= "." then
                table.insert(names, n)
            end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        for n, name in ipairs(names) do
            entries[n] = { label = name .. "  " .. fmtSize(fs.getSize(fs.combine(dir, name))) }
        end
        if #entries == 0 then
            entries[1] = { label = "No files here.", color = colors.gray }
        end
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Files in /" .. dir .. "  free " .. D.free(fs.getFreeSpace(dir == "" and "/" or dir)), entries, sel, top, buttons)
        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #entries then
            sel = sel + 1
        elseif i.k == "enter" and names[sel] then
            manage(names[sel])
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and names[top + i.y - 2] then
            sel = top + i.y - 2
            manage(names[sel])
        end
    end
end

-- ── Import menu ──────────────────────────────────────────────────────────────

function D.importMenu()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Open", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local function run(n)
        if n == 1 then D.pcApp()
        elseif n == 2 then D.dropApp()
        elseif n == 3 then D.joinApp()
        elseif n == 4 then D.filesApp()
        end
        api.restorePalette()
    end
    while true do
        local entries = {
            { label = "From a PC over HTTP (any size)", color = colors.cyan },
            { label = "Drop files onto the window", color = colors.cyan },
            { label = "Join split parts", color = colors.cyan },
            { label = "Files in the save folder", color = colors.cyan },
        }
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Import from PC", entries, sel, top, buttons)
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

-- ── Settings ─────────────────────────────────────────────────────────────────

function D.settingsApp()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Change", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local OVERWRITE = { "Ask", "Replace", "Rename" }
    local CHUNKS = { 1, 2, 4, 8 }

    local function change(n)
        if n == 1 then
            local pick = pickMenu("Save folder", { "Main folder (no folder)", "Choose a folder" }, settings.importDir == "" and 1 or 2)
            if pick == 1 then
                settings.importDir = ""
            elseif pick == 2 then
                local v = ask("Save folder", { "Folder for downloaded files:", "Use a disk path such as disk/audio to save on a disk." }, settings.importDir ~= "" and settings.importDir or nil)
                if v then
                    v = fs.combine("", v)
                    if v == "rom" or v:sub(1, 4) == "rom/" then
                        showMessage("Save folder", { "The rom folder is read only." }, colors.red)
                    else
                        settings.importDir = v
                    end
                end
            end
        elseif n == 2 then
            local v = ask("PC address", {
                "Address of the PC running prismarine_share.py.",
                "Example: 127.0.0.1:8000 or 192.168.1.20:8000",
            }, settings.importHost)
            if v then
                v = v:gsub("^https?://", ""):gsub("/+$", "")
                if v:match("^[%w%.%-]+:?%d*$") then
                    settings.importHost = v
                else
                    showMessage("PC address", { "That is not a host:port address." }, colors.red)
                end
            end
        elseif n == 3 then
            local idx = pickMenu("If a file already exists", OVERWRITE, 1)
            if idx then settings.importOverwrite = OVERWRITE[idx] end
        elseif n == 4 then
            settings.importClean = not settings.importClean
        elseif n == 5 then
            settings.importKeep = not settings.importKeep
        elseif n == 6 then
            settings.importVerify = not settings.importVerify
        elseif n == 7 then
            local labels = {}
            for k, mb in ipairs(CHUNKS) do labels[k] = mb .. " MB per request" end
            local idx = pickMenu("Download step", labels, 2)
            if idx then settings.importChunk = CHUNKS[idx] end
        elseif n == 8 then
            showMessage("Setup help: the PC helper", {
                "1. On your PC run:  python prismarine_share.py serve <folder>",
                "2. In computercraft-server.toml add, ABOVE the \"$private\" deny rule:",
                "[[http.rules]]  host = \"127.0.0.1\"  port = 8000  action = \"allow\"",
                "   (use your PC's address instead of 127.0.0.1 if the game is on another machine)",
                "3. Restart the server, then open Import from PC.",
                "Add --lan to the serve command if the game runs on another machine.",
            }, colors.lightBlue)
            showMessage("Setup help: big files", {
                "Files of any size download over HTTP, up to 18 GB and more. Interrupted downloads resume.",
                "A computer holds only what computer_space_limit allows (default 1 MB). Raise it in computercraft-server.toml, for example computer_space_limit = 20000000000.",
                "http.max_download must be at least the step size (default 16 MB).",
            }, colors.lightBlue)
            showMessage("Setup help: drag and drop", {
                "The game refuses large single drops before any program sees them. Split on the PC:",
                "python prismarine_share.py split song.dfpwm",
                "The parts are saved next to the file, not in a folder. Drop every .partN file, then open Join parts.",
            }, colors.lightBlue)
        end
        api.saveSettings()
    end

    while true do
        local entries = {
            { label = "Save folder: /" .. tostring(settings.importDir) .. (settings.importDir == "" and "  (no folder)" or "") },
            { label = "PC address: " .. tostring(settings.importHost) },
            { label = "If a file exists: " .. tostring(settings.importOverwrite) },
            { label = "Clean file names (no spaces): " .. (settings.importClean and "yes" or "no") },
            { label = "Keep parts after joining: " .. (settings.importKeep and "yes" or "no") },
            { label = "Verify SHA-256 (files up to 8 MB): " .. (settings.importVerify and "yes" or "no") },
            { label = "Download step: " .. tostring(settings.importChunk) .. " MB" },
            { label = "Setup help" },
        }
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Download settings", entries, sel, top, buttons)
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

-- ── Update this app ──────────────────────────────────────────────────────────

function D.updateSelf()
    D.draw("Update Downloads", { "Downloading the newest official_downloads.lua..." }, 0, "", true)
    local body, code, status, cancelled = D.http(api.rawUrl("official_downloads.lua"), nil, nil)
    if not body then
        if cancelled then return end
        local lines = { "Download failed.", tostring(code) }
        for _, l in ipairs(D.explain(code, status)) do table.insert(lines, l) end
        showMessage("Update Downloads", lines, colors.red)
        return
    end
    if code ~= 200 or body == "" then
        showMessage("Update Downloads", { "The server answered with status " .. tostring(code) .. "." }, colors.red)
        return
    end
    local fn, err = load(body, "=downloads")
    if not fn then
        showMessage("Update Downloads", { "The file has a syntax error.", tostring(err), "Nothing was changed." }, colors.red)
        return
    end
    local v = body:match('local VERSION = "([^"]+)"')
    fs.makeDir(".prismdl")
    local f = fs.open(api.DL_FILE, "wb")
    if not f then
        showMessage("Update Downloads", { "Cannot write " .. api.DL_FILE }, colors.red)
        return
    end
    f.write(body)
    f.close()
    api.restorePalette()
    showMessage("Update Downloads", {
        "Saved version " .. tostring(v or "?") .. " (this is version " .. VERSION .. ").",
        "Close and open Download again to use it.",
    }, colors.lime)
end

-- ── Loading screen and main menu ─────────────────────────────────────────────

-- The loading screen reads the GitHub file list while the logo animates.
function D.load()
    local sc = boot and boot.start(false, "DOWNLOADS")
    if sc then
        sc.tag = "Downloads  v" .. VERSION
        boot.stage(sc, "Starting", 0.15)
        local list, note
        boot.stage(sc, http and "Contacting GitHub" or "HTTP is off", 0.45, function(tick)
            if not http then
                list, note = nil, "HTTP is disabled on this server"
                return
            end
            list, note = D.scan(tick)
        end)
        boot.stage(sc, note or "", 0.85)
        D.files, D.note = list, note
        boot.finish(sc)
    else
        showBusy("Downloads", "Contacting GitHub...")
        D.files, D.note = D.scan(nil)
    end
    api.restorePalette()
end

function D.main()
    D.load()
    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Open", k = "enter" },
        { tag = "Q", label = "Back", k = "q" },
    }
    local function run(n)
        if n == 1 then
            if D.files then
                D.officialApp()
            else
                local lines = { "Could not read the GitHub file list.", tostring(D.note) }
                showMessage("Official files", lines, colors.red)
                D.draw("Official files", { "Asking GitHub for its files..." }, 0, "", false)
                local list, note = D.scan(nil)
                if list then
                    D.files, D.note = list, note
                    D.officialApp()
                end
            end
        elseif n == 2 then D.customApp()
        elseif n == 3 then D.importMenu()
        elseif n == 4 then D.settingsApp()
        elseif n == 5 then D.updateSelf()
        end
        api.restorePalette()
    end
    while true do
        local entries = {
            { label = "Official files (GitHub)", color = colors.cyan },
            { label = "Custom link", color = colors.cyan },
            { label = "Import from PC", color = colors.cyan },
            { label = "Settings", color = colors.cyan },
            { label = "Update this app", color = colors.cyan },
        }
        if sel > #entries then sel = #entries end
        top = clampTop(sel, top)
        drawList("Downloads", entries, sel, top, buttons)
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

D.main()
