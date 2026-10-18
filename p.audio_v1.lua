-- Prismarine Audio
-- A DFPWM music player for Prismarine OS (CC:Tweaked). Download it from the
-- Download app (Official files). Put .dfpwm files in /music, or point the
-- player at any folder with F.
--
--   Space play/pause   N / P next / previous   Left / Right seek 10 s
--   0-9 jump to 0-90%  + / - volume            M mute
--   S shuffle          R repeat (Off, All, One)
--   / search           V visualizer            O speaker       T theme
--   F music folder     L rescan                ? help          Q quit

local dfpwm = require("cc.audio.dfpwm")

local VERSION = "1"
local SETTINGS_FILE = ".prismaudio_settings"
local BYTES_PER_SEC = 6000      -- DFPWM is 48000 samples per second at 1 bit
local CHUNK = 2048              -- bytes per step (about 0.34 s of sound)
local BANDS = 16

-- ── Settings and themes ──────────────────────────────────────────────────────

local DEFAULTS = {
    volume = 0.5,
    muted = false,
    shuffle = false,
    repeatMode = "Off",     -- Off, All, One
    theme = "Prismarine",
    viz = "Bars",           -- Bars, Mirror, Off
    speaker = "Auto",       -- Auto, All, or a speaker name
    folder = "music",       -- "" is the main folder
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

local THEME_LIST = { "Prismarine", "Midnight", "Sunset", "Forest", "Mono" }
local THEMES = {
    Prismarine = { bar = colors.blue,   hl = colors.lightBlue, prog = colors.cyan,   peak = colors.white },
    Midnight   = { bar = colors.purple, hl = colors.lightBlue, prog = colors.magenta, peak = colors.white },
    Sunset     = { bar = colors.orange, hl = colors.yellow,    prog = colors.red,    peak = colors.yellow },
    Forest     = { bar = colors.green,  hl = colors.lime,      prog = colors.green,  peak = colors.lime },
    Mono       = { bar = colors.gray,   hl = colors.lightGray, prog = colors.white,  peak = colors.white },
}
local function theme() return THEMES[cfg.theme] or THEMES.Prismarine end

local LIGHT = {
    [colors.white] = true, [colors.lightGray] = true, [colors.yellow] = true,
    [colors.lime] = true, [colors.pink] = true, [colors.lightBlue] = true,
    [colors.cyan] = true, [colors.orange] = true,
}
local function textOn(bg) return LIGHT[bg] and colors.black or colors.white end

-- ── State ────────────────────────────────────────────────────────────────────

local S = {
    tracks = {},        -- { name, size } sorted
    view = {},          -- indexes into tracks that match the search
    sel = 1, top = 1,
    query = "", searching = false,
    current = nil,      -- name of the loaded track
    size = 0,
    playing = false,    -- a track is loaded and started
    paused = false,
    want = nil,         -- { name, offset } request for the audio task
    t0 = 0, base = 0,   -- real time and track seconds at the start of playback
    frozen = 0,         -- track seconds while paused
    history = {},
    frames = {},        -- visualizer frames waiting for their time
    disp = {},          -- smoothed band heights
    msg = nil, msgUntil = 0,
    quit = false,
}
for b = 1, BANDS do S.disp[b] = 0 end

local function nowSec() return os.epoch("utc") / 1000 end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function say(text, secs)
    S.msg, S.msgUntil = text, nowSec() + (secs or 3)
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function duration() return S.size / BYTES_PER_SEC end

-- Where the sound is right now, in seconds.
local function position()
    if not S.playing then return 0 end
    local p
    if S.paused then p = S.frozen else p = nowSec() - S.t0 + S.base end
    return clamp(p, 0, math.max(duration(), 0))
end

-- ── Playlist ─────────────────────────────────────────────────────────────────

local function folderPath() return fs.combine("", cfg.folder) end

local function scanDir(dir, prefix, depth, out)
    local ok, names = pcall(fs.list, dir)
    if not ok then return end
    for _, name in ipairs(names) do
        local path = fs.combine(dir, name)
        if fs.isDir(path) then
            if depth < 2 and name:sub(1, 1) ~= "." and path ~= "rom" then
                scanDir(path, prefix .. name .. "/", depth + 1, out)
            end
        elseif name:lower():sub(-6) == ".dfpwm" then
            table.insert(out, { name = prefix .. name, size = fs.getSize(path) })
        end
    end
end

local function applyFilter()
    local keep = S.current
    S.view = {}
    local q = S.query:lower()
    for i, t in ipairs(S.tracks) do
        if q == "" or t.name:lower():find(q, 1, true) then table.insert(S.view, i) end
    end
    S.sel = clamp(S.sel, 1, math.max(1, #S.view))
    if keep then
        for n, i in ipairs(S.view) do
            if S.tracks[i].name == keep then S.sel = n end
        end
    end
end

local function rescan()
    local out = {}
    local dir = folderPath()
    if dir == "music" and not fs.exists(dir) then pcall(fs.makeDir, dir) end
    scanDir(dir, "", 0, out)
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    S.tracks = out
    applyFilter()
end

local function trackIndex(name)
    for i, t in ipairs(S.tracks) do if t.name == name then return i end end
    return nil
end

-- ── Speakers ─────────────────────────────────────────────────────────────────

local function speakerNames()
    local names = {}
    for _, n in ipairs(peripheral.getNames()) do
        if peripheral.getType(n) == "speaker" then table.insert(names, n) end
    end
    table.sort(names)
    return names
end

local function activeSpeakers()
    local names = speakerNames()
    local list = {}
    if cfg.speaker == "All" then
        for _, n in ipairs(names) do table.insert(list, peripheral.wrap(n)) end
    else
        local pick
        for _, n in ipairs(names) do if n == cfg.speaker then pick = n end end
        pick = pick or names[1]
        if pick then table.insert(list, peripheral.wrap(pick)) end
    end
    return list
end

local function stopSpeakers()
    for _, sp in ipairs(activeSpeakers()) do pcall(sp.stop) end
end

local function speakerLabel()
    local names = speakerNames()
    if #names == 0 then return "none" end
    if cfg.speaker == "All" then return "all " .. #names end
    for _, n in ipairs(names) do if n == cfg.speaker then return n end end
    return names[1]
end

-- ── Visualizer analysis ──────────────────────────────────────────────────────
-- A cheap spectrum: a Goertzel filter for each of 16 log spaced frequencies on
-- a short, down-sampled slice of the decoded sound.

local STRIDE, WINDOW = 4, 384
local FS = 48000 / STRIDE
local coeffs = {}
for b = 1, BANDS do
    local f = 60 * (4800 / 60) ^ ((b - 1) / (BANDS - 1))
    coeffs[b] = 2 * math.cos(2 * math.pi * f / FS)
end

local function analyse(buf, startAt)
    local count = #buf
    local need = WINDOW * STRIDE
    local spacing = 0.085
    local frames = math.max(1, math.min(4, math.floor(count / 12000 * 4 + 0.5)))
    for fr = 0, frames - 1 do
        local first = 1 + math.floor(fr * (count - need) / math.max(1, frames - 1))
        if count < need then first = 1 end
        local bands = {}
        for b = 1, BANDS do
            local c = coeffs[b]
            local s1, s2 = 0, 0
            local i = first
            for _ = 1, WINDOW do
                local s = buf[i] or 0
                local s0 = s + c * s1 - s2
                s2, s1 = s1, s0
                i = i + STRIDE
            end
            local mag = math.sqrt(math.max(0, s1 * s1 + s2 * s2 - c * s1 * s2)) / (WINDOW / 2)
            local v = (mag / 55) * (1 + (b - 1) / BANDS * 1.6)
            bands[b] = clamp(v, 0, 1) ^ 0.7
        end
        table.insert(S.frames, { t = startAt + fr * spacing, bands = bands })
    end
    while #S.frames > 40 do table.remove(S.frames, 1) end
end

-- ── Audio task ───────────────────────────────────────────────────────────────

local function onTrackEnd()
    local cur = trackIndex(S.current)
    local nextName
    if cfg.repeatMode == "One" then
        nextName = S.current
    elseif cfg.shuffle and #S.tracks > 1 then
        local n
        repeat n = math.random(1, #S.tracks) until n ~= cur
        nextName = S.tracks[n].name
    elseif cur and cur < #S.tracks then
        nextName = S.tracks[cur + 1].name
    elseif cfg.repeatMode == "All" and #S.tracks > 0 then
        nextName = S.tracks[1].name
    end
    if nextName then
        if nextName ~= S.current then table.insert(S.history, S.current) end
        S.current = nextName
        S.want = { name = nextName, offset = 0 }
    else
        S.playing, S.paused = false, false
    end
end

-- Sends one buffer to the speakers. Returns false when playback was changed.
local function send(buf)
    while true do
        if S.quit or S.want then return false end
        if S.paused then return false end
        local speakers = activeSpeakers()
        if #speakers == 0 then
            say("No speaker attached.", 4)
            S.paused = true
            S.frozen = position()
            return false
        end
        local vol = cfg.muted and 0 or cfg.volume * 3
        local done = {}
        local all = true
        for i, sp in ipairs(speakers) do
            local ok, accepted = pcall(sp.playAudio, buf, vol)
            if ok and accepted then done[i] = true else all = false end
        end
        if all then return true end
        -- Some speakers took it and some did not. Resend only to the others.
        local pending = {}
        for i, sp in ipairs(speakers) do if not done[i] then table.insert(pending, sp) end end
        local timer = os.startTimer(0.4)
        while #pending > 0 do
            local ev, a = os.pullEvent()
            if S.quit or S.want or S.paused then return false end
            if ev == "speaker_audio_empty" or (ev == "timer" and a == timer) then
                local still = {}
                for _, sp in ipairs(pending) do
                    local ok, accepted = pcall(sp.playAudio, buf, vol)
                    if not (ok and accepted) then table.insert(still, sp) end
                end
                pending = still
                if #pending > 0 then timer = os.startTimer(0.4) end
            end
        end
        return true
    end
end

local function playTrack(want)
    local path = fs.combine(folderPath(), want.name)
    local f = fs.exists(path) and fs.open(path, "rb")
    if not f then
        say("Cannot open " .. want.name, 4)
        S.playing, S.paused = false, false
        return
    end
    local size = fs.getSize(path)
    S.size = size
    local pos = clamp(math.floor(want.offset or 0), 0, math.max(0, size - 1))
    if pos > 0 then f.seek("set", pos) end
    local decoder = dfpwm.make_decoder()
    S.frames = {}
    S.base = pos / BYTES_PER_SEC
    S.t0 = nowSec()
    S.paused = want.paused and true or false
    S.playing = true
    local fresh = true       -- the clock starts at the first buffer
    local finished = false

    while true do
        if S.quit or S.want then break end
        if S.paused then
            stopSpeakers()
            S.frames = {}
            while S.paused and not S.quit and not S.want do sleep(0.1) end
            if S.quit or S.want then break end
            -- The speaker was flushed, so continue from where the sound stopped.
            pos = clamp(math.floor(S.frozen * BYTES_PER_SEC), 0, math.max(0, size - 1))
            f.seek("set", pos)
            decoder = dfpwm.make_decoder()
            S.base = pos / BYTES_PER_SEC
            fresh = true
        end
        local chunk = f.read(CHUNK)
        if not chunk then finished = true; break end
        local buf = decoder(chunk)
        if fresh then
            S.t0 = nowSec()
            fresh = false
        end
        local startAt = S.t0 + (pos / BYTES_PER_SEC - S.base)
        if cfg.viz ~= "Off" then analyse(buf, startAt) end
        pos = pos + #chunk
        send(buf)
    end
    f.close()
    if finished and not S.quit and not S.want then
        -- Let the last second of sound play out before moving on.
        local endAt = S.t0 + (size / BYTES_PER_SEC - S.base)
        while nowSec() < endAt and not S.quit and not S.want and not S.paused do sleep(0.1) end
        if not S.want and not S.quit and not S.paused then onTrackEnd() end
    end
end

local function audioTask()
    while not S.quit do
        if S.want then
            local w = S.want
            S.want = nil
            local ok, err = pcall(playTrack, w)
            if not ok then
                if tostring(err):find("Terminated") then error(err, 0) end
                say("Playback error: " .. tostring(err), 5)
                S.playing, S.paused = false, false
            end
        else
            sleep(0.05)
        end
    end
end

-- ── Commands ─────────────────────────────────────────────────────────────────

local function startTrack(name, offset, noHistory)
    if not name then return end
    if #speakerNames() == 0 then say("No speaker attached.", 4); return end
    if not noHistory and S.current and S.current ~= name then
        table.insert(S.history, S.current)
        if #S.history > 100 then table.remove(S.history, 1) end
    end
    S.current = name
    local i = trackIndex(name)
    S.size = i and S.tracks[i].size or 0
    S.paused = false
    S.playing = true
    S.base, S.t0 = (offset or 0) / BYTES_PER_SEC, nowSec()
    S.want = { name = name, offset = offset or 0 }
end

local function selectedName()
    local i = S.view[S.sel]
    return i and S.tracks[i].name or nil
end

local function togglePause()
    if not S.playing then
        startTrack(selectedName() or S.current)
        return
    end
    if S.paused then
        S.paused = false
    else
        S.frozen = position()
        S.paused = true
    end
end

local function stepTrack(dir)
    if #S.tracks == 0 then return end
    local cur = trackIndex(S.current) or 0
    local n
    if dir > 0 then
        if cfg.shuffle and #S.tracks > 1 then
            repeat n = math.random(1, #S.tracks) until n ~= cur
        else
            n = cur + 1
            if n > #S.tracks then n = 1 end
        end
        startTrack(S.tracks[n].name)
    else
        if position() > 4 and S.current then
            startTrack(S.current, 0, true)
            return
        end
        local prev = table.remove(S.history)
        if prev and trackIndex(prev) then
            startTrack(prev, 0, true)
        else
            n = cur - 1
            if n < 1 then n = #S.tracks end
            startTrack(S.tracks[n].name, 0, true)
        end
    end
end

local function seekTo(sec)
    if not S.current then return end
    local limit = math.max(0, duration() - 1)
    sec = clamp(sec, 0, limit)
    if S.paused then
        S.frozen = sec
        S.want = { name = S.current, offset = sec * BYTES_PER_SEC, paused = true }
    else
        S.base, S.t0 = sec, nowSec()
        S.want = { name = S.current, offset = sec * BYTES_PER_SEC }
    end
end

local function cycle(list, value)
    for i, v in ipairs(list) do
        if v == value then return list[i % #list + 1] end
    end
    return list[1]
end

local function setVolume(v)
    cfg.volume = clamp(math.floor(v * 100 + 0.5) / 100, 0, 1)
    if cfg.volume > 0 then cfg.muted = false end
    saveCfg()
end

local function cycleSpeaker()
    local options = { "Auto" }
    local names = speakerNames()
    if #names > 1 then table.insert(options, "All") end
    for _, n in ipairs(names) do table.insert(options, n) end
    cfg.speaker = cycle(options, cfg.speaker)
    saveCfg()
    if S.playing then stopSpeakers() end
    say("Speaker: " .. speakerLabel(), 2)
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

local W, H = term.getSize()
local win
local hits = {}
local listRect = { y1 = 0, y2 = 0 }
local seekRect, volRect

local function pad(text, width)
    if width <= 0 then return "" end
    text = text:sub(1, width)
    return text .. string.rep(" ", width - #text)
end

local function put(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end

local function addHit(x1, x2, y, k) table.insert(hits, { x1 = x1, x2 = x2, y = y, k = k }) end

local function vizRows()
    if cfg.viz == "Off" then return 0 end
    if H >= 19 then return 6 end
    if H >= 15 then return 4 end
    if H >= 12 then return 2 end
    return 0
end

local function drawViz(y1, rows)
    local t = theme()
    local barW = math.max(1, math.floor((W - 2) / BANDS))
    local gap = barW > 1 and 1 or 0
    local total = BANDS * barW
    local x0 = math.floor((W - total) / 2) + 1
    for b = 1, BANDS do
        local v = S.disp[b]
        local x = x0 + (b - 1) * barW
        local w = barW - gap
        if cfg.viz == "Mirror" then
            local half = rows / 2
            local reach = v * half
            for r = 0, rows - 1 do
                local dist = math.abs((r + 0.5) - half)
                if dist <= reach then
                    local frac = dist / half
                    local col = frac < 0.5 and t.prog or (frac < 0.85 and t.hl or t.peak)
                    put(x, y1 + r, string.rep(" ", w), col, col)
                end
            end
        else
            local height = math.floor(v * rows + 0.5)
            for r = 0, height - 1 do
                local frac = r / rows
                local col = frac < 0.5 and t.prog or (frac < 0.8 and t.hl or t.peak)
                put(x, y1 + rows - 1 - r, string.rep(" ", w), col, col)
            end
            if height == 0 then
                put(x, y1 + rows - 1, string.rep(" ", w), colors.gray, colors.gray)
            end
        end
    end
end

local function footer(buttons)
    local t = theme()
    put(1, H, string.rep(" ", W), t.bar, colors.lightGray)
    local x = 1
    for _, b in ipairs(buttons) do
        local tagText = " " .. b.tag .. " "
        local labelText = b.label .. " "
        local total = #tagText + #labelText
        if x + total - 1 > W then break end
        put(x, H, tagText, textOn(t.bar), t.bar)
        put(x + #tagText, H, labelText, textOn(t.hl), t.hl)
        addHit(x, x + total - 1, H, b.k)
        x = x + total + 1
    end
end

local function draw()
    local t = theme()
    win.setVisible(false)
    hits = {}
    seekRect, volRect = nil, nil
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorBlink(false)

    -- Header
    put(1, 1, string.rep(" ", W), textOn(t.bar), t.bar)
    put(2, 1, "Prismarine Audio", textOn(t.bar), t.bar)
    local right = #S.view .. (S.query ~= "" and ("/" .. #S.tracks) or "") .. " tracks"
    if W >= 40 then put(W - #right, 1, right, textOn(t.bar), t.bar) end

    -- Layout from the bottom up
    local rowFooter = H
    local rowStatus = H - 1
    local rowSeek = H - 2
    local rowTitle = H - 3
    local vr = vizRows()
    local vizTop = rowTitle - vr
    local listTop = 2
    local listBottom = vizTop - 1
    if listBottom - listTop < 2 then vr = 0; vizTop = rowTitle; listBottom = rowTitle - 1 end

    -- Search bar
    if S.searching or S.query ~= "" then
        local label = S.searching and "Find: " or "Filter: "
        put(1, listTop, pad(" " .. label .. S.query, W), textOn(t.hl), t.hl)
        listTop = listTop + 1
        if S.searching then
            term.setCursorPos(math.min(W, 3 + #label + #S.query), 2)
            term.setTextColor(textOn(t.hl))
            term.setCursorBlink(true)
        end
    end

    -- Track list
    local rows = math.max(0, listBottom - listTop + 1)
    listRect = { y1 = listTop, y2 = listBottom }
    if S.sel < S.top then S.top = S.sel end
    if S.sel > S.top + rows - 1 then S.top = S.sel - rows + 1 end
    S.top = clamp(S.top, 1, math.max(1, #S.view - rows + 1))
    if #S.view == 0 then
        local lines = S.query ~= "" and { "No track matches \"" .. S.query .. "\"." } or {
            "No .dfpwm files in /" .. folderPath() .. ".",
            "Add some with Download > Import from PC,",
            "or press F to choose another folder.",
        }
        for i, l in ipairs(lines) do
            if listTop + i - 1 <= listBottom then
                put(2, listTop + i - 1, pad(l, W - 2), colors.lightGray, colors.black)
            end
        end
    end
    for r = 0, rows - 1 do
        local n = S.top + r
        local ti = S.view[n]
        if ti then
            local tr = S.tracks[ti]
            local isCur = tr.name == S.current and S.playing
            local label = tr.name:gsub("%.[dD][fF][pP][wW][mM]$", "")
            local len = fmtTime(tr.size / BYTES_PER_SEC)
            local nameW = W - #len - 5
            local bg, fg = colors.black, colors.white
            if n == S.sel then bg, fg = t.hl, textOn(t.hl) end
            local mark = isCur and (S.paused and "|" or ">") or " "
            put(1, listTop + r, string.rep(" ", W), fg, bg)
            put(2, listTop + r, mark, (n == S.sel) and fg or t.prog, bg)
            put(4, listTop + r, pad(label, nameW), fg, bg)
            put(W - #len, listTop + r, len, (n == S.sel) and fg or colors.lightGray, bg)
        end
    end
    -- Scroll marker on the right edge
    if #S.view > rows and rows > 2 then
        local pos = math.floor((S.top - 1) / (#S.view - rows) * (rows - 1)) + 1
        put(W, listTop + pos - 1, "\127", t.hl, colors.black)
    end

    -- Visualizer
    if vr > 0 then drawViz(vizTop, vr) end

    -- Title line (or a message)
    local title
    local msgOn = S.msg and nowSec() < S.msgUntil
    if msgOn then
        put(1, rowTitle, pad(" " .. S.msg, W), colors.yellow, colors.black)
    else
        if S.current and S.playing then
            local label = S.current:gsub("%.[dD][fF][pP][wW][mM]$", "")
            local state = S.paused and "Paused" or "Playing"
            put(1, rowTitle, pad(" " .. state .. ": " .. label, W), colors.white, colors.black)
        else
            put(1, rowTitle, pad(" Nothing playing", W), colors.lightGray, colors.black)
        end
    end

    -- Seek bar:  0:12 [=====-----] 3:45
    local cur = position()
    local total = S.playing and duration() or 0
    local left = fmtTime(cur)
    local rightT = fmtTime(total)
    local bx1 = 2 + #left + 1
    local bx2 = W - #rightT - 2
    put(2, rowSeek, left, colors.white, colors.black)
    put(W - #rightT, rowSeek, rightT, colors.lightGray, colors.black)
    if bx2 - bx1 >= 4 then
        local bw = bx2 - bx1 + 1
        local frac = total > 0 and clamp(cur / total, 0, 1) or 0
        local fill = math.floor(bw * frac + 0.5)
        put(bx1, rowSeek, string.rep(" ", fill), t.prog, t.prog)
        put(bx1 + fill, rowSeek, string.rep(" ", bw - fill), colors.gray, colors.gray)
        seekRect = { x1 = bx1, x2 = bx2, y = rowSeek }
    end

    -- Status: volume, shuffle, repeat, speaker
    local vw = W >= 45 and 12 or (W >= 32 and 8 or 5)
    put(2, rowStatus, "Vol", colors.lightGray, colors.black)
    local vfill = cfg.muted and 0 or math.floor(vw * cfg.volume + 0.5)
    put(6, rowStatus, string.rep(" ", vfill), t.prog, t.prog)
    put(6 + vfill, rowStatus, string.rep(" ", vw - vfill), colors.gray, colors.gray)
    volRect = { x1 = 6, x2 = 5 + vw, y = rowStatus }
    local pct = cfg.muted and "mute" or (math.floor(cfg.volume * 100 + 0.5) .. "%")
    put(7 + vw, rowStatus, pad(pct, 4), colors.white, colors.black)
    local x = 12 + vw
    local function flag(text, on, k)
        if x + #text > W then return end
        put(x, rowStatus, text, on and t.peak or colors.gray, colors.black)
        addHit(x, x + #text - 1, rowStatus, k)
        x = x + #text + 1
    end
    flag("SHUF", cfg.shuffle, "s")
    flag("REP:" .. cfg.repeatMode, cfg.repeatMode ~= "Off", "r")
    if W >= 40 then flag("SPK:" .. speakerLabel():sub(1, 12), #speakerNames() > 0, "o") end

    footer({
        { tag = "Spc", label = S.paused and "Play" or (S.playing and "Pause" or "Play"), k = "space" },
        { tag = "N", label = "Next", k = "n" },
        { tag = "P", label = "Prev", k = "p" },
        { tag = "/", label = "Find", k = "/" },
        { tag = "V", label = "Viz", k = "v" },
        { tag = "T", label = "Theme", k = "t" },
        { tag = "?", label = "Help", k = "?" },
        { tag = "Q", label = "Quit", k = "q" },
    })

    win.setVisible(true)
end

-- ── Help and prompts ─────────────────────────────────────────────────────────

local function helpScreen()
    local t = theme()
    local lines = {
        "Space       Play / pause",
        "Enter       Play the selected track",
        "N / P       Next / previous track",
        "Left/Right  Seek 10 seconds",
        "0-9         Jump to 0-90% of the track",
        "+ / -       Volume   M mute",
        "S           Shuffle",
        "R           Repeat: Off, All, One",
        "/           Search (Enter keeps the filter, Esc clears)",
        "V           Visualizer: Bars, Mirror, Off",
        "O           Speaker (Auto, All, or one)",
        "T           Theme",
        "F           Music folder   L rescan",
        "Click       A track, the seek bar, the volume bar",
        "Q           Quit",
    }
    while true do
        win.setVisible(false)
        term.setBackgroundColor(colors.black)
        term.clear()
        put(1, 1, string.rep(" ", W), textOn(t.bar), t.bar)
        put(2, 1, "Help", textOn(t.bar), t.bar)
        for i, l in ipairs(lines) do
            if i + 2 < H then put(2, i + 2, l:sub(1, W - 2), colors.white, colors.black) end
        end
        put(1, H, pad(" Press any key", W), textOn(t.hl), t.hl)
        win.setVisible(true)
        local ev = os.pullEventRaw()
        if ev == "key" or ev == "mouse_click" then return end
        if ev == "terminate" then S.quit = true; return end
        if ev == "term_resize" then
            W, H = term.getSize()
            win.reposition(1, 1, W, H)
        end
    end
end

-- Reads one line while the music keeps playing. Returns nil when cancelled.
local function promptLine(label, default)
    local t = theme()
    local text = default or ""
    while true do
        win.setVisible(false)
        term.setBackgroundColor(colors.black)
        term.clear()
        put(1, 1, string.rep(" ", W), textOn(t.bar), t.bar)
        put(2, 1, label:sub(1, W - 2), textOn(t.bar), t.bar)
        put(2, 3, text:sub(-(W - 3)) .. "_", colors.white, colors.black)
        put(2, 5, "Enter saves, Esc cancels", colors.lightGray, colors.black)
        win.setVisible(true)
        local ev, a = os.pullEventRaw()
        if ev == "char" then text = text .. a
        elseif ev == "key" then
            if a == keys.enter then return text
            elseif a == keys.backspace then text = text:sub(1, -2)
            elseif a == keys.escape then return nil end
        elseif ev == "terminate" then S.quit = true; return nil
        elseif ev == "term_resize" then
            W, H = term.getSize()
            win.reposition(1, 1, W, H)
        end
    end
end

local function chooseFolder()
    local value = promptLine("Music folder (blank = main folder)", cfg.folder)
    if value == nil then return end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    local path = fs.combine("", value)
    if path == "rom" or path:sub(1, 4) == "rom/" then
        say("The rom folder cannot be used.", 3)
        return
    end
    if path ~= "" and (not fs.exists(path) or not fs.isDir(path)) then
        say("There is no folder called " .. path, 4)
        return
    end
    cfg.folder = path
    saveCfg()
    S.query = ""
    rescan()
    say("Folder: /" .. path .. "  (" .. #S.tracks .. " tracks)", 3)
end

-- ── Input ────────────────────────────────────────────────────────────────────

local lastClickAt, lastClickSel = 0, 0

local function command(k)
    if k == "space" then togglePause()
    elseif k == "n" then stepTrack(1)
    elseif k == "p" then stepTrack(-1)
    elseif k == "s" then
        cfg.shuffle = not cfg.shuffle
        saveCfg()
    elseif k == "r" then
        cfg.repeatMode = cycle({ "Off", "All", "One" }, cfg.repeatMode)
        saveCfg()
    elseif k == "v" then
        cfg.viz = cycle({ "Bars", "Mirror", "Off" }, cfg.viz)
        saveCfg()
        say("Visualizer: " .. cfg.viz, 2)
    elseif k == "t" then
        cfg.theme = cycle(THEME_LIST, cfg.theme)
        saveCfg()
    elseif k == "o" then cycleSpeaker()
    elseif k == "m" then
        cfg.muted = not cfg.muted
        saveCfg()
    elseif k == "+" or k == "=" then setVolume(cfg.volume + 0.05)
    elseif k == "-" or k == "_" then setVolume(cfg.volume - 0.05)
    elseif k == "/" then
        S.searching = true
    elseif k == "f" then chooseFolder()
    elseif k == "l" then
        rescan()
        say("Found " .. #S.tracks .. " tracks.", 2)
    elseif k == "?" or k == "h" then helpScreen()
    elseif k == "q" then
        S.quit = true
    elseif k:match("^%d$") and S.playing then
        seekTo(duration() * tonumber(k) / 10)
    end
end

local function playSelected()
    local name = selectedName()
    if not name then return end
    if S.playing and S.current == name then togglePause() else startTrack(name) end
end

local function handleKey(a)
    if S.searching then
        if a == keys.enter then
            S.searching = false
        elseif a == keys.escape then
            S.searching, S.query = false, ""
            applyFilter()
        elseif a == keys.backspace then
            S.query = S.query:sub(1, -2)
            applyFilter()
        elseif a == keys.down then
            S.sel = math.min(#S.view, S.sel + 1)
        elseif a == keys.up then
            S.sel = math.max(1, S.sel - 1)
        end
        return
    end
    if a == keys.up then S.sel = S.sel > 1 and S.sel - 1 or #S.view
    elseif a == keys.down then S.sel = S.sel < #S.view and S.sel + 1 or 1
    elseif a == keys.pageUp then S.sel = math.max(1, S.sel - 8)
    elseif a == keys.pageDown then S.sel = math.min(#S.view, S.sel + 8)
    elseif a == keys.home then S.sel = 1
    elseif a == keys["end"] then S.sel = #S.view
    elseif a == keys.enter then playSelected()
    elseif a == keys.left then seekTo(position() - 10)
    elseif a == keys.right then seekTo(position() + 10)
    elseif a == keys.escape and S.query ~= "" then
        S.query = ""
        applyFilter()
    end
    S.sel = math.max(1, S.sel)
end

local function handleClick(x, y)
    for _, h in ipairs(hits) do
        if y == h.y and x >= h.x1 and x <= h.x2 then
            command(h.k)
            return
        end
    end
    if seekRect and y == seekRect.y and x >= seekRect.x1 and x <= seekRect.x2 and S.playing then
        local frac = (x - seekRect.x1) / math.max(1, seekRect.x2 - seekRect.x1)
        seekTo(duration() * frac)
        return
    end
    if volRect and y == volRect.y and x >= volRect.x1 and x <= volRect.x2 then
        setVolume((x - volRect.x1 + 1) / (volRect.x2 - volRect.x1 + 1))
        return
    end
    if y >= listRect.y1 and y <= listRect.y2 then
        local n = S.top + (y - listRect.y1)
        if S.view[n] then
            local now = nowSec()
            if n == lastClickSel and now - lastClickAt < 0.5 then
                S.sel = n
                playSelected()
                lastClickAt = 0
            else
                S.sel = n
                lastClickAt, lastClickSel = now, n
            end
        end
    end
end

-- Moves the smoothed bars toward the frame that belongs to this moment.
local function stepViz()
    local now = nowSec()
    local frame
    while S.frames[1] and S.frames[1].t <= now do frame = table.remove(S.frames, 1) end
    local live = S.playing and not S.paused
    for b = 1, BANDS do
        local target = (live and frame) and frame.bands[b] or nil
        local d = S.disp[b]
        if target then
            d = target > d and target or math.max(target, d * 0.7)
        else
            d = d * (live and 0.82 or 0.6)
            if d < 0.02 then d = 0 end
        end
        S.disp[b] = d
    end
end

local function animating()
    if S.playing and not S.paused then return true end
    if S.msg and nowSec() < S.msgUntil + 0.2 then return true end
    for b = 1, BANDS do if S.disp[b] > 0 then return true end end
    return false
end

local function inputTask()
    local timer = os.startTimer(0.1)
    draw()
    while not S.quit do
        local ev, a, b, c = os.pullEventRaw()
        local redraw = true
        if ev == "terminate" then
            S.quit = true
        elseif ev == "timer" then
            if a == timer then
                timer = os.startTimer(0.1)
                stepViz()
                redraw = animating()
            else
                redraw = false
            end
        elseif ev == "key" then
            handleKey(a)
        elseif ev == "char" then
            if S.searching then
                S.query = S.query .. a
                applyFilter()
            else
                command(tostring(a):lower())
            end
        elseif ev == "mouse_click" then
            handleClick(b, c)
        elseif ev == "mouse_scroll" then
            if volRect and c == volRect.y and b >= volRect.x1 and b <= volRect.x2 then
                setVolume(cfg.volume - a * 0.05)
            elseif #S.view > 0 then
                S.sel = clamp(S.sel + a, 1, #S.view)
            end
        elseif ev == "term_resize" then
            W, H = term.getSize()
            win.reposition(1, 1, W, H)
        elseif ev == "peripheral" or ev == "peripheral_detach" then
            if ev == "peripheral_detach" and S.playing and #speakerNames() == 0 then
                S.frozen = position()
                S.paused = true
                say("Speaker removed. Paused.", 4)
            end
        elseif ev == "mouse_drag" then
            handleClick(b, c)
            lastClickAt = 0
        else
            redraw = false
        end
        if redraw and not S.quit then draw() end
    end
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local function main()
    if not term.isColour() then
        print("Prismarine Audio needs an advanced computer (colour).")
        return
    end
    math.randomseed(os.epoch("utc"))
    rescan()
    local native = term.current()
    W, H = native.getSize()
    win = window.create(native, 1, 1, W, H, true)
    term.redirect(win)
    local ok, err = pcall(function()
        parallel.waitForAny(audioTask, inputTask)
    end)
    stopSpeakers()
    term.redirect(native)
    native.setBackgroundColor(colors.black)
    native.setTextColor(colors.white)
    native.setCursorBlink(false)
    native.clear()
    native.setCursorPos(1, 1)
    if not ok and not tostring(err):find("Terminated") then
        print("Prismarine Audio stopped: " .. tostring(err))
        print("Press any key.")
        os.pullEvent("key")
    end
end

main()
