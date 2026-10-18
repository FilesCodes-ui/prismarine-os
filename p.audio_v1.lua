-- IMPERIAL CRIMSON-AUDIO v4.0 (Prismarine Edition)
-- Modernized for Prismarine OS v12
-- Requires: CC:Tweaked 1.20.1, Advanced Peripherals (or standard speaker)

local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
local music_dir = "/music"
local playlist_file = ".khi_audio_settings"

local VERSION = "4.0"
local LOG_FILE = "khi_audio_error.log"

local W, H = term.getSize()

-- ── Settings & Theme ─────────────────────────────────────────────────────────

local COLORS = {
    black = colors.black, white = colors.white, gray = colors.gray,
    lightGray = colors.lightGray, red = colors.red, blue = colors.blue,
    lightBlue = colors.lightBlue, cyan = colors.cyan, lime = colors.lime,
    yellow = colors.yellow, orange = colors.orange, purple = colors.purple,
}

local LIGHT = { [colors.white]=true, [colors.lightGray]=true, [colors.yellow]=true,
                [colors.lime]=true, [colors.pink]=true, [colors.lightBlue]=true,
                [colors.cyan]=true, [colors.orange]=true }

local function textOn(bg) return LIGHT[bg] and colors.black or colors.white end

local DEFAULT_SETTINGS = {
    volume = 0.5,
    shuffle = false,
    repeat = "None", -- None, All, One
    theme = "Prismarine",
}

local settings = {}
local function loadSettings()
    for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end
    if fs.exists(playlist_file) then
        local f = fs.open(playlist_file, "r")
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

local function saveSettings()
    local f = fs.open(playlist_file, "w")
    if f then f.write(textutils.serialize(settings)); f.close() end
end

loadSettings()

-- Themes (matches Prismarine OS)
local THEMES = {
    Prismarine = { bar = colors.blue, hl = colors.lightBlue, bg = colors.black, txt = colors.white, dim = colors.lightGray, prog = colors.lime },
    Midnight   = { bar = colors.purple, hl = colors.lightBlue, bg = colors.black, txt = colors.white, dim = colors.lightGray, prog = colors.cyan },
    Sunset     = { bar = colors.orange, hl = colors.yellow, bg = colors.black, txt = colors.white, dim = colors.lightGray, prog = colors.orange },
    Forest     = { bar = colors.green, hl = colors.lime, bg = colors.black, txt = colors.white, dim = colors.lightGray, prog = colors.lime },
    Mono       = { bar = colors.gray, hl = colors.lightGray, bg = colors.black, txt = colors.white, dim = colors.gray, prog = colors.white },
}

local function getTheme() return THEMES[settings.theme] or THEMES.Prismarine end

-- ── Playlist & State ─────────────────────────────────────────────────────────

if not fs.exists(music_dir) then fs.makeDir(music_dir) end
local playlist = fs.list(music_dir)
table.sort(playlist)

local state = {
    current_index = 1,
    playing_index = 0,
    is_playing = false,
    quit = false,
    progress = 0,
    last_progress = 0,
}

if #playlist == 0 then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("No music found in /" .. music_dir)
    print("Please put .dfpwm files there and restart.")
    return
end

-- ── UI Helpers ───────────────────────────────────────────────────────────────

local buttonHits = {}

local function pad(text, width)
    if width < 0 then width = 0 end
    text = text:sub(1, width)
    return text .. string.rep(" ", width - #text)
end

local function header(title)
    local t = getTheme()
    term.setCursorBlink(false)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.bar)
    term.setTextColor(textOn(t.bar))
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write(title:sub(1, W - 2))
end

local function footerButtons(buttons)
    buttonHits = {}
    local t = getTheme()
    term.setCursorPos(1, H)
    term.setBackgroundColor(t.dim)
    term.setTextColor(t.bg)
    term.write(string.rep(" ", W))
    local x = 1
    for _, b in ipairs(buttons) do
        local tagText = (b.tag ~= "") and (" " .. b.tag .. " ") or ""
        local labelText = ((b.tag ~= "") and "" or " ") .. b.label .. " "
        local total = #tagText + #labelText
        if x + total - 1 > W then break end
        term.setCursorPos(x, H)
        if tagText ~= "" then
            term.setBackgroundColor(t.bar)
            term.setTextColor(textOn(t.bar))
            term.write(tagText)
        end
        term.setBackgroundColor(t.hl)
        term.setTextColor(textOn(t.hl))
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

local function drawProgressBar(y, pct)
    local t = getTheme()
    local barW = W - 4
    local fill = math.floor(barW * pct)
    term.setCursorPos(2, y)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.prog)
    term.write("[")
    term.setBackgroundColor(t.prog)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(t.dim)
    term.write(string.rep(" ", barW - fill))
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.prog)
    term.write("]")
end

local function drawUI()
    local t = getTheme()
    term.setBackgroundColor(t.bg)
    term.clear()
    header("KHI Crimson-Audio v" .. VERSION)
    
    local list_start = 3
    local list_end = H - 6
    
    -- Draw the list of songs
    for i = 1, (list_end - list_start + 1) do
        local idx = i
        local song = playlist[idx]
        if song then
            term.setCursorPos(1, list_start + i - 1)
            if idx == state.current_index then
                term.setBackgroundColor(t.hl)
                term.setTextColor(textOn(t.hl))
                term.write(pad(" >> " .. song, W))
            else
                term.setBackgroundColor(t.bg)
                term.setTextColor(t.txt)
                term.write(pad("    " .. song, W))
            end
        end
    end

    -- Volume Bar
    local volRow = H - 4
    term.setCursorPos(2, volRow)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.dim)
    term.write("VOL: ")
    local volBarMax = W - 10
    local volFill = math.floor((settings.volume / 3.0) * volBarMax)
    term.setTextColor(t.prog)
    term.write(string.rep("|", volFill))
    term.setTextColor(t.dim)
    term.write(string.rep(".", volBarMax - volFill))

    -- Now playing & Progress
    local current_song = playlist[state.current_index]
    if current_song then
        local status = state.is_playing and "PLAYING: " or "PAUSED: "
        term.setCursorPos(2, H - 3)
        term.setTextColor(t.txt)
        term.write(status .. current_song:upper():sub(1, W - 4))
        drawProgressBar(H - 2, state.progress)
    end

    footerButtons({
        { tag = "Ent", label = "Play/Pause", k = "enter" },
        { tag = "+/-", label = "Vol", k = "vol" },
        { tag = "R", label = "Repeat", k = "r" },
        { tag = "S", label = "Shuffle", k = "s" },
        { tag = "Q", label = "Exit", k = "q" },
    })
end

-- ── Audio Logic ──────────────────────────────────────────────────────────────

local function getNextTrack()
    if settings.shuffle then
        local new
        repeat new = math.random(1, #playlist) until new ~= state.current_index or #playlist == 1
        return new
    end
    if settings.repeat == "One" then return state.current_index end
    if state.current_index < #playlist then return state.current_index + 1 end
    if settings.repeat == "All" then return 1 end
    return nil
end

local function audioTask()
    while not state.quit do
        if state.is_playing and playlist[state.current_index] then
            state.playing_index = state.current_index
            local path = fs.combine(music_dir, playlist[state.playing_index])
            
            if not fs.exists(path) then
                state.is_playing = false
                state.playing_index = 0
                goto continue
            end

            local decoder = dfpwm.make_decoder()
            local file = fs.open(path, "rb")
            if not file then state.is_playing = false goto continue end
            
            local totalSize = fs.getSize(path)
            local played = 0

            while true do
                local chunk = file.read(4 * 1024)
                if not chunk then break end
                if state.quit or state.playing_index ~= state.current_index or not state.is_playing then break end

                local buffer = decoder(chunk)
                played = played + #chunk
                state.progress = played / totalSize
                
                if speaker then
                    while state.is_playing and not speaker.playAudio(buffer, settings.volume * 3) do
                        os.pullEvent("speaker_audio_empty")
                    end
                end
            end
            file.close()

            -- Auto-advance if the song finished naturally
            if not state.quit and state.playing_index == state.current_index and state.progress >= 0.99 then
                local nextIdx = getNextTrack()
                if nextIdx then
                    state.current_index = nextIdx
                    state.progress = 0
                else
                    state.is_playing = false
                    state.progress = 0
                end
            end
        end
        ::continue::
        os.sleep(0.1)
    end
end

-- ── Input Task ───────────────────────────────────────────────────────────────

local function inputTask()
    while not state.quit do
        drawUI()
        local ev, a, b, c = os.pullEvent()
        
        if ev == "key" then
            if a == keys.up then 
                state.current_index = (state.current_index > 1) and state.current_index - 1 or #playlist
                state.progress = 0 
            elseif a == keys.down then 
                state.current_index = (state.current_index < #playlist) and state.current_index + 1 or 1
                state.progress = 0
            elseif a == keys.enter then 
                state.is_playing = not state.is_playing
            elseif a == keys.q then 
                state.quit = true
                if speaker then speaker.stop() end
            elseif a == keys.equals or a == keys.numPadAdd then 
                settings.volume = math.min(3.0, settings.volume + 0.1)
                saveSettings()
            elseif a == keys.minus or a == keys.numPadSubtract then 
                settings.volume = math.max(0.0, settings.volume - 0.1)
                saveSettings()
            elseif a == keys.r then
                local modes = { "None", "All", "One" }
                local idx = 1
                for i, m in ipairs(modes) do if m == settings.repeat then idx = i end end
                settings.repeat = modes[(idx % #modes) + 1]
                saveSettings()
            elseif a == keys.s then
                settings.shuffle = not settings.shuffle
                saveSettings()
            end
        elseif ev == "mouse_click" then
            local k = hitButton(b, c)
            if k == "enter" then state.is_playing = not state.is_playing
            elseif k == "q" then state.quit = true; if speaker then speaker.stop() end
            elseif k == "r" then
                local modes = { "None", "All", "One" }
                local idx = 1
                for i, m in ipairs(modes) do if m == settings.repeat then idx = i end end
                settings.repeat = modes[(idx % #modes) + 1]
                saveSettings()
            elseif k == "s" then
                settings.shuffle = not settings.shuffle
                saveSettings()
            elseif k == "vol" then
                -- Simple toggle for volume on click
                settings.volume = settings.volume >= 1.0 and 0.2 or settings.volume + 0.2
                saveSettings()
            end
        end
    end
end

-- ── Main ─────────────────────────────────────────────────────────────────────

-- Error Logging
local function logError(err)
    local f = fs.open(LOG_FILE, "a")
    if f then f.writeLine(os.date("%Y-%m-%d %H:%M") .. " " .. tostring(err)); f.close() end
end

local ok, err = pcall(function()
    parallel.waitForAny(audioTask, inputTask)
end)

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
    logError(err)
    print("Audio crashed: " .. tostring(err))
else
    print("KHI Crimson-Audio disengaged.")
end