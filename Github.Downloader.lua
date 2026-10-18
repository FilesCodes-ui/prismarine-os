-- Prismarine App Store
-- Downloads apps directly from the Prismarine OS GitHub repo.
-- Filters out startup and shell updates.

local VERSION = "1.0"
local W, H = term.getSize()

-- You can change this to your repo name/branch
local REPO = "FilesCodes-ui/prismarine-os"
local BRANCH = "main"
local API_URL = "https://api.github.com/repos/" .. REPO .. "/contents/?ref=" .. BRANCH
local RAW_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"

-- ── Colors & Helpers ─────────────────────────────────────────────────────────

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

local DEFAULT_SETTINGS = {
    barColor  = "Blue",
    highlight = "Light blue",
    theme     = "Prismarine",
}

local settings = {}
local function loadSettings()
    for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end
    if fs.exists(".simpleos_settings") then
        local f = fs.open(".simpleos_settings", "r")
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

local function colorValue(name, fallback)
    for _, c in ipairs(COLOR_CHOICES) do
        if c.name == name then return c.value end
    end
    return fallback
end

local function pad(text, width)
    if width < 0 then width = 0 end
    text = text:sub(1, width)
    return text .. string.rep(" ", width - #text)
end

local function fmtSize(n)
    if n >= 1048576 then return string.format("%.1f MB", n / 1048576)
    elseif n >= 1024 then return string.format("%.1f KB", n / 1024) end
    return n .. " B"
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

-- ── UI Drawing ───────────────────────────────────────────────────────────────

local buttonHits = {}

local function drawHeader(title)
    local bar = colorValue(settings.barColor, colors.blue)
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(bar)
    term.setTextColor(textOn(bar))
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write(title:sub(1, W - 2))
end

local function drawFooter(buttons)
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

local function fillRect(x1, y1, x2, y2, bg)
    if x2 < x1 then return end
    term.setBackgroundColor(bg)
    local blank = string.rep(" ", x2 - x1 + 1)
    for y = y1, y2 do
        term.setCursorPos(x1, y)
        term.write(blank)
    end
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
    drawHeader(title)
    drawCard(3, lines, color, colors.white)
    drawFooter({ { tag = "", label = "Continue (any key)", k = "enter" } })
    while true do
        local ev, a, b, c = os.pullEventRaw()
        if ev == "key" or ev == "mouse_click" then return end
    end
end

local function showBusy(title, text)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    drawHeader(title)
    drawCard(3, { text }, colors.yellow, colors.white)
end

local function readInput()
    local ev, a, b, c = os.pullEventRaw()
    if ev == "key" then
        local name = keys.getName(a)
        if not name then return nil end
        return { k = name }
    elseif ev == "char" then
        return { k = tostring(a):lower() }
    elseif ev == "mouse_click" then
        local k = hitButton(b, c)
        if k then return { k = k } end
        return { click = true, x = b, y = c }
    elseif ev == "mouse_scroll" then
        return { scroll = a }
    end
    return { ev = ev }
end

local function drawList(title, entries, sel, top, buttons)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    drawHeader(title)
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
    drawFooter(buttons)
end

-- ── Network Logic ────────────────────────────────────────────────────────────

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
            -- Filter out startup files and shell files
            if not name:match("^startup_v%d+%.lua$") and not name:match("^p%.shell_v%d+%.lua$") then
                table.insert(apps, {
                    label = name,
                    name = name,
                    size = file.size,
                    url = file.download_url
                })
            end
        end
    end

    if #apps == 0 then
        showMessage("App Store", { "No files found in the repository." }, colors.yellow)
        return nil
    end

    return apps
end

local function downloadApp(app)
    local path = app.name
    if fs.exists(path) then
        -- Simple yes/no confirm
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("Overwrite")
        drawCard(3, { path .. " already exists.", "Overwrite it?" }, colors.yellow, colors.white)
        drawFooter({ { tag = "Y", label = "Yes", k = "y" }, { tag = "N", label = "No", k = "n" } })
        
        local confirmed = false
        while true do
            local i = readInput()
            if i and i.k == "y" then confirmed = true; break
            elseif i and (i.k == "n" or i.k == "escape") then break end
        end
        if not confirmed then return end
    end

    showBusy("App Store", "Downloading " .. app.name .. "...")
    
    local resp = http.get(app.url)
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

-- ── Main ─────────────────────────────────────────────────────────────────────

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
        local entries = {}
        for _, app in ipairs(apps) do
            table.insert(entries, {
                label = string.format("%-20s %s", app.name, fmtSize(app.size)),
                color = colors.cyan,
            })
        end

        local visible = H - 2
        if sel < top then top = sel end
        if sel > top + visible - 1 then top = sel - visible + 1 end

        drawList("Prismarine App Store", entries, sel, top, buttons)

        local i = readInput() or {}
        if i.k == "up" and sel > 1 then
            sel = sel - 1
        elseif i.k == "down" and sel < #apps then
            sel = sel + 1
        elseif i.k == "enter" then
            downloadApp(apps[sel])
            -- Refresh list after download
            apps = fetchRepoList() or apps
        elseif i.k == "r" then
            apps = fetchRepoList() or apps
            sel = 1
            top = 1
        elseif i.k == "q" then
            return
        elseif i.click and i.y >= 2 and i.y <= H - 1 and entries[top + i.y - 2] then
            sel = top + i.y - 2
            downloadApp(apps[sel])
            apps = fetchRepoList() or apps
        elseif i.scroll then
            sel = math.max(1, math.min(#apps, sel + i.scroll))
        end
    end
end

main()

-- Restore terminal state on exit
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)