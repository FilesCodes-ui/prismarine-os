-- Prismarine App Store
-- Fetches a list of files from the Prismarine OS GitHub repo.
-- Hides startup files and the LICENSE. Downloads directly to the computer.

local W, H = term.getSize()
local VERSION = "1.0"
local SETTINGS_FILE = ".simpleos_settings"
local LOG_FILE = "prismarine_store_error.log"

local REPO = "FilesCodes-ui/prismarine-os"
local BRANCH = "main"
local API_URL = "https://api.github.com/repos/" .. REPO .. "/contents/?ref=" .. BRANCH

local SELF = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "store.lua"
if not SELF or SELF == "" then SELF = "store.lua" end

-- ── Settings & Colors ────────────────────────────────────────────────────────

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

local function textOn(bg) return LIGHT[bg] and colors.black or colors.white end

local function colorValue(name, fallback)
    for _, c in ipairs(COLOR_CHOICES) do
        if c.name == name then return c.value end
    end
    return fallback
end

local settings = {
    barColor  = "Blue",
    highlight = "Light blue",
    theme     = "Prismarine",
    graphics  = true,
}

local function loadSettings()
    if fs.exists(SETTINGS_FILE) then
        local f = fs.open(SETTINGS_FILE, "r")
        if f then
            local data = textutils.unserialize(f.readAll() or "")
            f.close()
            if type(data) == "table" then
                for k, v in pairs(data) do
                    if settings[k] ~= nil and type(v) == type(settings[k]) then
                        settings[k] = v
                    end
                end
            end
        end
    end
end
loadSettings()

-- ── UI Helpers ───────────────────────────────────────────────────────────────

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
    local bar = colorValue(settings.barColor, colors.blue)
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(bar)
    term.setTextColor(textOn(bar))
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write(title:sub(1, W - 2))
end

local function footer(text)
    buttonHits = {}
    term.setCursorPos(1, H)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(pad(" " .. text, W))
end

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
    elseif ev == "term_resize" then
        W, H = term.getSize()
        return {}
    end
    return { ev = ev }
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
        if i.k == "y" then return true
        elseif i.k == "n" or i.k == "enter" or i.k == "q" or i.k == "backspace" then return false end
    end
end

-- ── List Renderer ────────────────────────────────────────────────────────────

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
                term.setBackgroundColor(hl)
                term.setTextColor(textOn(hl))
                term.setCursorPos(1, row)
                term.write(pad(" " .. e.label, w))
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(e.color or colors.white)
                term.setCursorPos(1, row)
                term.write(pad(" " .. e.label, w))
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

-- ── Network & App Logic ──────────────────────────────────────────────────────

local function fmtSize(n)
    if n >= 1048576 then
        return string.format("%.1f MB", n / 1048576)
    elseif n >= 1024 then
        return string.format("%.1f KB", n / 1024)
    end
    return n .. " B"
end

local function fetchRepoList()
    if not http then
        showMessage("App Store", { "HTTP is disabled on this server." }, colors.red)
        return nil
    end

    showBusy("App Store", "Fetching repository list...")
    local ok, res = pcall(http.get, API_URL)
    if not ok or not res then
        showMessage("App Store", { "Could not connect to GitHub.", tostring(res) }, colors.red)
        return nil
    end

    local body = res.readAll()
    res.close()
    local data = textutils.unserialiseJSON(body)

    if type(data) ~= "table" then
        showMessage("App Store", { "GitHub API returned an error.", "You may be rate-limited." }, colors.red)
        return nil
    end

    local apps = {}
    for _, file in ipairs(data) do
        if file.type == "file" then
            local name = file.name
            -- Filter out startup files, shell files, and the LICENSE
            if not name:match("^startup_v%d+%.lua$") 
               and not name:match("^p%.shell_v%d+%.lua$")
               and name ~= "LICENSE" then
                table.insert(apps, {
                    label = string.format("%-18s %s", name, fmtSize(file.size)),
                    name = name,
                    size = file.size,
                    url = file.download_url
                })
            end
        end
    end

    if #apps == 0 then
        showMessage("App Store", { "No downloadable files found." }, colors.yellow)
        return nil
    end

    return apps
end

local function downloadApp(app)
    local path = app.name
    if fs.exists(path) then
        if not confirm({ path .. " already exists.", "Overwrite it?" }) then return end
    end

    showBusy("App Store", "Downloading " .. app.name .. "...")
    
    local resp = http.get(app.url, nil, true)
    if not resp then
        showMessage("App Store", { "Download failed." }, colors.red)
        return
    end

    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()

    if status ~= 200 or not body or body == "" then
        showMessage("App Store", { "Failed to download file.", "Status: " .. tostring(status) }, colors.red)
        return
    end

    local f = fs.open(path, "wb")
    if not f then
        showMessage("App Store", { "Cannot write to disk.", "Check permissions." }, colors.red)
        return
    end
    
    f.write(body)
    f.close()

    showMessage("App Store", { 
        "Successfully downloaded " .. app.name,
        fmtSize(#body) .. " saved."
    }, colors.lime)
end

-- ── Main Loop ────────────────────────────────────────────────────────────────

local function main()
    local apps = fetchRepoList()
    if not apps then return end

    local sel, top = 1, 1
    local buttons = {
        { tag = "Ent", label = "Download", k = "enter" },
        { tag = "R", label = "Refresh", k = "r" },
        { tag = "Q", label = "Exit", k = "q" },
    }

    while true do
        local visible = H - 2
        if sel < top then top = sel end
        if sel > top + visible - 1 then top = sel - visible + 1 end

        drawList("Prismarine App Store", apps, sel, top, buttons)

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #apps then
            sel = sel + 1
        elseif i.k == "enter" then
            downloadApp(apps[sel])
            apps = fetchRepoList() or apps
            if sel > #apps then sel = #apps end
        elseif i.k == "r" then
            apps = fetchRepoList() or apps
            sel = 1
            top = 1
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and apps[top + i.y - 2] then
            sel = top + i.y - 2
            downloadApp(apps[sel])
            apps = fetchRepoList() or apps
            if sel > #apps then sel = #apps end
        elseif i.scroll then
            sel = math.max(1, math.min(#apps, sel + i.scroll))
        end
    end
end

-- ── Execution & Crash Handling ───────────────────────────────────────────────

local function logError(err)
    local f = fs.open(LOG_FILE, "a")
    if f then
        f.writeLine(os.date("%Y-%m-%d %H:%M") .. "  " .. tostring(err))
        f.close()
    end
end

local ok, err = pcall(main)
if not ok then
    logError(err)
    resetTerm()
    term.clear()
    showMessage("App Store Error", { tostring(err), "", "Saved to " .. LOG_FILE }, colors.red)
end

-- Cleanup terminal on exit
resetTerm()
term.clear()
term.setCursorPos(1, 1)