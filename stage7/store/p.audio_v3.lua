--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Audio
--@prismarine-api
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

-- The OS passes its helpers (boot screen, palette restore, network events)
-- when it opens this app. Run by hand there is no api and those are skipped.
local api = ...
if type(api) ~= "table" then api = nil end

local VERSION = "3"
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
-- bar and hl are the title bar and highlight colors, ramp goes from dark to
-- bright and colors the bars, the seek bar and the cover art.
local THEMES = {
    Prismarine = { bar = {48, 104, 205}, hl = {120, 190, 240},
        ramp = { {18,70,120}, {28,115,175}, {45,165,210}, {80,205,215}, {140,235,205}, {225,250,230} } },
    Midnight = { bar = {104, 60, 190}, hl = {150, 170, 250},
        ramp = { {50,30,110}, {85,45,160}, {125,65,200}, {170,95,225}, {215,140,240}, {245,205,250} } },
    Sunset = { bar = {214, 110, 30}, hl = {250, 200, 80},
        ramp = { {120,30,40}, {175,50,45}, {220,85,40}, {245,135,45}, {250,190,70}, {255,235,150} } },
    Forest = { bar = {40, 140, 70}, hl = {150, 225, 100},
        ramp = { {20,70,45}, {30,110,60}, {55,155,70}, {100,195,80}, {160,225,100}, {225,245,170} } },
    Mono = { bar = {90, 96, 108}, hl = {190, 196, 206},
        ramp = { {50,54,62}, {80,86,96}, {115,122,134}, {155,162,174}, {200,206,216}, {245,247,250} } },
}
local function theme() return THEMES[cfg.theme] or THEMES.Prismarine end

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
S.peak, S.hold = {}, {}
for b = 1, BANDS do S.disp[b], S.peak[b], S.hold[b] = 0, 0, 0 end

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

-- Loudness follows the loudest recent band and falls slowly, so quiet and loud
-- songs both fill the bars. Heights use a log scale like a real spectrum.
local log10 = math.log10 or function(x) return math.log(x) / math.log(10) end
local REF_FLOOR, REF_DECAY = 3, 0.97
local LOG_SPAN, LOG_OFFSET = 1.6, 2.0
local function analyse(buf, startAt)
    local count = #buf
    local need = WINDOW * STRIDE
    local spacing = 0.085
    local frames = math.max(1, math.min(4, math.floor(count / 12000 * 4 + 0.5)))
    for fr = 0, frames - 1 do
        local first = 1 + math.floor(fr * (count - need) / math.max(1, frames - 1))
        if count < need then first = 1 end
        local mags, peak = {}, 0
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
            mag = mag * (1 + (b - 1) / BANDS * 1.6)
            mags[b] = mag
            if mag > peak then peak = mag end
        end
        S.ref = math.max(REF_FLOOR, (S.ref or REF_FLOOR) * REF_DECAY, peak)
        local logRef = log10(S.ref)
        local bands = {}
        for b = 1, BANDS do
            bands[b] = clamp((log10(mags[b] + 0.02) - logRef + LOG_OFFSET) / LOG_SPAN, 0, 1)
        end
        table.insert(S.frames, { t = startAt + fr * spacing, bands = bands })
    end
    -- The speaker buffer holds a few seconds, so keep enough frames ahead.
    while #S.frames > 120 do table.remove(S.frames, 1) end
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
    S.ref = nil
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

-- ── Sub-pixel graphics ───────────────────────────────────────────────────────
-- Every terminal cell holds 2x3 pixels (the teletext characters 128-159). A
-- canvas is a grid of pixels (a color, or false for the background). render
-- turns it into characters, using the two most common colors in each cell.

local W, H = term.getSize()
local win
local hits = {}
local listRect = { y1 = 0, y2 = 0 }
local seekRect, volRect

-- Palette slots. The app sets its own palette while it runs and the OS puts
-- the normal one back when it closes.
local C = {
    bg = colors.black, text = colors.white, dim = colors.lightGray, track = colors.gray,
    bar = colors.blue, hl = colors.lightBlue, panel = colors.purple, tick = colors.brown,
    reflect = colors.pink, peak = colors.magenta,
    ramp = { colors.green, colors.cyan, colors.lime, colors.yellow, colors.orange, colors.red },
}
local TONE = {}

local function setRGB(slot, rgb)
    win.setPaletteColor(slot, rgb[1] / 255, rgb[2] / 255, rgb[3] / 255)
    TONE[slot] = (0.3 * rgb[1] + 0.59 * rgb[2] + 0.11 * rgb[3]) / 255
end

local function applyPalette()
    local t = theme()
    setRGB(C.bg, { 7, 10, 17 })
    setRGB(C.text, { 236, 242, 248 })
    setRGB(C.dim, { 138, 150, 168 })
    setRGB(C.track, { 32, 38, 52 })
    setRGB(C.panel, { 16, 23, 36 })
    setRGB(C.tick, { 64, 74, 96 })
    setRGB(C.peak, { 255, 255, 255 })
    setRGB(C.bar, t.bar)
    setRGB(C.hl, t.hl)
    for i, slot in ipairs(C.ramp) do setRGB(slot, t.ramp[i]) end
    local d = t.ramp[1]
    setRGB(C.reflect, { math.floor(d[1] * 0.55), math.floor(d[2] * 0.55), math.floor(d[3] * 0.55) })
end

local function resetPalette()
    local cur = term.current()
    for i = 0, 15 do
        local slot = 2 ^ i
        pcall(cur.setPaletteColor, slot, term.nativePaletteColor(slot))
    end
    if api and api.restorePalette then pcall(api.restorePalette) end
end

local function newCanvas(cw, ch)
    local c = { cw = cw, ch = ch, pw = cw * 2, ph = ch * 3 }
    for y = 1, c.ph do
        local row = {}
        for x = 1, c.pw do row[x] = false end
        c[y] = row
    end
    return c
end

local function rect(c, x1, y1, x2, y2, col)
    for y = math.max(1, y1), math.min(c.ph, y2) do
        local row = c[y]
        for x = math.max(1, x1), math.min(c.pw, x2) do row[x] = col end
    end
end

-- Takes r pixels off each corner (a rounded corner). r = 1 removes one pixel.
local function rounded(c, x1, y1, x2, y2, r)
    for d = 0, r - 1 do
        for e = 0, r - 1 - d do
            if c[y1 + e] then
                c[y1 + e][x1 + d] = false
                c[y1 + e][x2 - d] = false
            end
            if c[y2 - e] then
                c[y2 - e][x1 + d] = false
                c[y2 - e][x2 - d] = false
            end
        end
    end
end

local function render(c, x0, y0, bg)
    bg = bg or C.bg
    local blit = colors.toBlit
    for cy = 1, c.ch do
        local chars, fgs, bgs = {}, {}, {}
        local py = (cy - 1) * 3
        local r1, r2, r3 = c[py + 1], c[py + 2], c[py + 3]
        for cx = 1, c.cw do
            local px = (cx - 1) * 2
            local p = {
                r1[px + 1] or bg, r1[px + 2] or bg, r2[px + 1] or bg,
                r2[px + 2] or bg, r3[px + 1] or bg, r3[px + 2] or bg,
            }
            local counts, order = {}, {}
            for i = 1, 6 do
                local k = p[i]
                if not counts[k] then counts[k] = 0; order[#order + 1] = k end
                counts[k] = counts[k] + 1
            end
            local ch, fg, back
            if #order == 1 then
                ch, fg, back = " ", order[1], order[1]
            else
                if #order > 2 then
                    table.sort(order, function(x, y)
                        if counts[x] ~= counts[y] then return counts[x] > counts[y] end
                        return x < y
                    end)
                end
                local a, b = order[1], order[2]
                local bits, last = 0, false
                for i = 1, 6 do
                    local k = p[i]
                    local isB
                    if k == b then isB = true
                    elseif k == a then isB = false
                    else isB = math.abs((TONE[k] or 0) - (TONE[b] or 0)) < math.abs((TONE[k] or 0) - (TONE[a] or 0)) end
                    if i == 6 then last = isB
                    elseif isB then bits = bits + 2 ^ (i - 1) end
                end
                if last then
                    -- The sixth pixel always shows the background color, so
                    -- swap the colors and the set pixels.
                    ch, fg, back = string.char(128 + (31 - bits)), a, b
                else
                    ch, fg, back = string.char(128 + bits), b, a
                end
            end
            chars[cx], fgs[cx], bgs[cx] = ch, blit(fg), blit(back)
        end
        term.setCursorPos(x0, y0 + cy - 1)
        term.blit(table.concat(chars), table.concat(fgs), table.concat(bgs))
    end
end

-- ── Text helpers ─────────────────────────────────────────────────────────────

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

-- Rounded ends for a chip: chip is the chip color, page the color behind it.
local function capLeft(x, y, chip, page)
    term.setCursorPos(x, y)
    term.blit(string.char(145), colors.toBlit(page), colors.toBlit(chip))
end
local function capRight(x, y, chip, page)
    term.setCursorPos(x, y)
    term.blit(string.char(157), colors.toBlit(chip), colors.toBlit(page))
end

-- A rounded chip with text. Returns the width it used.
local function chip(x, y, text, fg, bg, page)
    capLeft(x, y, bg, page)
    put(x + 1, y, text, fg, bg)
    capRight(x + 1 + #text, y, bg, page)
    return #text + 2
end

local function addHit(x1, x2, y, k) table.insert(hits, { x1 = x1, x2 = x2, y = y, k = k }) end

local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }
local function bayer(x, y) return (BAYER[(y - 1) % 4 + 1][(x - 1) % 4 + 1] + 0.5) / 16 end

-- A card: a rounded panel with room for text. Text goes on top of the cells
-- inside, with the panel color behind it.
local function card(x, y, cw, ch)
    local c = newCanvas(cw, ch)
    rect(c, 1, 1, c.pw, c.ph, C.panel)
    rounded(c, 1, 1, c.pw, c.ph, 3)
    render(c, x, y)
end

-- ── Elements ─────────────────────────────────────────────────────────────────

local function header(title, right)
    local titleW = #title + 3
    put(1, 1, pad("  " .. title, titleW), C.text, C.bar)
    local fadeW = W - titleW
    if fadeW > 0 then
        local c = newCanvas(fadeW, 1)
        for x = 1, c.pw do
            local level = 1 - x / c.pw
            for y = 1, 3 do
                c[y][x] = (level > bayer(x, y)) and C.bar or false
            end
        end
        render(c, titleW + 1, 1)
    end
    if right and W >= 36 then put(W - #right - 1, 1, right, C.dim, C.bg) end
end

-- A rounded pill bar. frac fills it with the theme ramp. ticks marks every 10%.
local function pill(x, y, cw, frac, ticks, shimmer)
    local c = newCanvas(cw, 1)
    rect(c, 1, 1, c.pw, 3, C.track)
    if ticks then
        for i = 1, 9 do
            local tx = math.floor(c.pw * i / 10 + 0.5)
            c[1][tx] = C.tick
            c[3][tx] = C.tick
        end
    end
    local fill = math.floor(c.pw * frac + 0.5)
    for px = 1, fill do
        local level = (px - 1) / math.max(1, c.pw - 1)
        local idx = math.min(#C.ramp, math.floor(level * (#C.ramp - 1) + 1.5))
        local col = C.ramp[idx]
        c[1][px], c[2][px], c[3][px] = col, col, col
        if shimmer and math.abs(px - shimmer) < 2 then c[1][px] = C.peak end
    end
    if fill >= 2 then
        c[1][fill], c[2][fill], c[3][fill] = C.peak, C.peak, C.peak
    end
    c[1][1], c[3][1], c[1][c.pw], c[3][c.pw] = false, false, false
    render(c, x, y)
end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- Small generated cover art, different for every track.
local function cover(x, y, name, live)
    local c = newCanvas(3, 2)
    rect(c, 1, 1, c.pw, c.ph, C.panel)
    if name then
        local h = hash(name)
        local shift, twist = h % 6, 1 + math.floor(h / 7) % 3
        for py = 1, c.ph do
            for px = 1, c.pw do
                local v = ((px * twist + py * (4 - twist) + shift) % 6) / 5
                local diag = (px + py) / (c.pw + c.ph)
                local idx = math.floor(((v * 0.55 + diag * 0.45 + (h % 100) / 100) % 1) * #C.ramp) + 1
                c[py][px] = C.ramp[math.min(#C.ramp, idx)]
            end
        end
        if live then
            local beat = math.floor(nowSec() * 3) % 2
            c[1][c.pw - 1 + beat] = C.peak
        end
    else
        local note = { "..####", "..#..#", "..#..#", ".##.##", "###.##", ".#...." }
        for py, row in ipairs(note) do
            for px = 1, 6 do
                if row:sub(px, px) == "#" then c[py][px] = C.tick end
            end
        end
    end
    rounded(c, 1, 1, c.pw, c.ph, 2)
    render(c, x, y)
end

local function vizRows()
    if cfg.viz == "Off" then return 0 end
    if H >= 19 then return 6 end
    if H >= 15 then return 4 end
    if H >= 13 then return 3 end
    return 0
end

local function drawViz(y1, rows)
    local c = newCanvas(W, rows)
    local pw, ph = c.pw, c.ph
    local per = math.max(2, math.floor((pw - 4) / BANDS))
    local bw = per - 1
    local x0 = math.floor((pw - per * BANDS) / 2) + 1
    local mirror = cfg.viz == "Mirror"
    local base = mirror and math.floor(ph / 2) or math.floor(ph * 0.78)
    local up = mirror and (ph / 2 - 1) or (base - 2)

    -- Guide lines
    for _, f in ipairs(mirror and { 0.25, 0.75 } or { 0.25, 0.5, 0.75 }) do
        local gy = math.floor(base - up * f)
        for x = 1, pw, 2 do if c[gy] then c[gy][x] = C.panel end end
    end

    for b = 1, BANDS do
        local v = S.disp[b]
        local x1 = x0 + (b - 1) * per
        local x2 = x1 + bw - 1
        local h = math.floor(v * up + 0.5)
        -- Bar, colored by height
        for k = 1, h do
            local idx = math.min(#C.ramp, math.floor((k / up) * (#C.ramp - 1) + 1.5))
            for x = x1, x2 do
                if c[base - k + 1] then c[base - k + 1][x] = C.ramp[idx] end
            end
        end
        if h >= 2 and bw >= 3 then
            local top = base - h + 1
            if c[top] then c[top][x1], c[top][x2] = false, false end
        end
        -- Reflection (or the lower half of a mirrored bar)
        local rh = mirror and h or math.floor(h * 0.45)
        for k = 1, rh do
            local ry = base + k
            if c[ry] then
                for x = x1, x2 do
                    if mirror then
                        local idx = math.min(#C.ramp, math.floor((k / up) * (#C.ramp - 1) + 1.5))
                        c[ry][x] = C.ramp[idx]
                    elseif (x + k) % 2 == 0 then
                        c[ry][x] = C.reflect
                    end
                end
            end
        end
        -- Peak cap
        local pk = math.floor((S.peak[b] or 0) * up + 0.5)
        if pk > h + 1 then
            for x = x1, x2 do
                if c[base - pk + 1] then c[base - pk + 1][x] = C.peak end
                if mirror and c[base + pk] then c[base + pk][x] = C.peak end
            end
        end
        if h == 0 then
            for x = x1, x2 do if c[base] then c[base][x] = C.track end end
        end
    end
    -- Baseline
    if not mirror then
        for x = 1, pw do if c[base + 1] and not c[base + 1][x] then c[base + 1][x] = C.track end end
    end
    render(c, 1, y1)
end

local function footer(buttons)
    put(1, H, string.rep(" ", W), C.text, C.panel)
    local x = 1
    for _, b in ipairs(buttons) do
        local tagText = " " .. b.tag .. " "
        local labelText = " " .. b.label
        local total = 1 + #tagText + #labelText + 1
        if x + total - 1 > W then break end
        capLeft(x, H, C.bar, C.panel)
        put(x + 1, H, tagText, C.text, C.bar)
        put(x + 1 + #tagText, H, labelText, C.bg, C.hl)
        capRight(x + total - 1, H, C.hl, C.panel)
        addHit(x, x + total - 1, H, b.k)
        x = x + total + 1
    end
end

local function plural(n) return n .. (n == 1 and " track" or " tracks") end

local function stripName(name) return (name:gsub("%.[dD][fF][pP][wW][mM]$", "")) end

local function draw()
    win.setVisible(false)
    hits = {}
    seekRect, volRect = nil, nil
    term.setBackgroundColor(C.bg)
    term.setTextColor(C.text)
    term.clear()
    term.setCursorBlink(false)

    header("Prismarine Audio", S.query ~= "" and (#S.view .. "/" .. plural(#S.tracks)) or plural(#S.tracks))

    -- Layout from the bottom up
    local rowStatus, rowSeek, rowSub, rowTitle = H - 1, H - 2, H - 3, H - 4
    local vr = vizRows()
    local vizTop = rowTitle - vr
    local listTop, listBottom = 2, vizTop - 1
    if listBottom - listTop < 2 then vr = 0; vizTop = rowTitle; listBottom = rowTitle - 1 end

    -- Search bar
    if S.searching or S.query ~= "" then
        local label = S.searching and "Find: " or "Filter: "
        capLeft(2, listTop, C.hl, C.bg)
        put(3, listTop, pad(label .. S.query, W - 4), C.bg, C.hl)
        capRight(W - 1, listTop, C.hl, C.bg)
        if S.searching then
            term.setCursorPos(math.min(W - 2, 3 + #label + #S.query), listTop)
            term.setTextColor(C.bg)
            term.setCursorBlink(true)
        end
        listTop = listTop + 1
    end

    -- Track list (the selected row has rounded ends)
    local rows = math.max(0, listBottom - listTop + 1)
    listRect = { y1 = listTop, y2 = listBottom }
    if S.sel < S.top then S.top = S.sel end
    if S.sel > S.top + rows - 1 then S.top = S.sel - rows + 1 end
    S.top = clamp(S.top, 1, math.max(1, #S.view - rows + 1))

    if #S.view == 0 and rows >= 3 then
        local lines = S.query ~= "" and { "No track matches \"" .. S.query .. "\"." } or {
            "No .dfpwm files in /" .. folderPath() .. ".",
            "Add some with Download > Import from PC,",
            "or press F to choose another folder.",
        }
        local ch = math.min(rows, #lines + 2)
        card(2, listTop, W - 2, ch)
        for i, l in ipairs(lines) do
            if i + 1 <= ch - 1 then put(4, listTop + i, pad(l, W - 6), C.dim, C.panel) end
        end
    end
    for r = 0, rows - 1 do
        local n = S.top + r
        local ti = S.view[n]
        if ti then
            local tr = S.tracks[ti]
            local y = listTop + r
            local isCur = tr.name == S.current and S.playing
            local selected = n == S.sel
            local bg = selected and C.hl or ((r % 2 == 1) and C.panel or C.bg)
            local fg = selected and C.bg or C.text
            local len = fmtTime(tr.size / BYTES_PER_SEC)
            if selected then
                capLeft(2, y, C.hl, C.bg)
                capRight(W - 2, y, C.hl, C.bg)
                put(3, y, string.rep(" ", W - 5), fg, bg)
            else
                put(2, y, string.rep(" ", W - 2), fg, bg)
            end
            local mark = isCur and (S.paused and "\7" or "\16") or " "
            put(3, y, mark, selected and C.bg or C.ramp[4], bg)
            put(5, y, pad(stripName(tr.name), W - #len - 9), fg, bg)
            put(W - 3 - #len, y, len, selected and C.bg or C.dim, bg)
        end
    end
    if #S.view > rows and rows > 2 then
        local c = newCanvas(1, rows)
        rect(c, 1, 1, 1, c.ph, C.panel)
        local thumb = math.max(3, math.floor(c.ph * rows / #S.view))
        local at = math.floor((S.top - 1) / math.max(1, #S.view - rows) * (c.ph - thumb)) + 1
        rect(c, 1, at, 2, at + thumb - 1, C.hl)
        rounded(c, 1, at, 2, at + thumb - 1, 1)
        render(c, W, listTop)
    end

    -- Visualizer
    if vr > 0 then drawViz(vizTop, vr) end

    -- Now playing: cover, title, details
    local showCover = H >= 13
    local tx = showCover and 6 or 2
    if showCover then cover(2, rowTitle, S.playing and S.current or nil, S.playing and not S.paused) end
    if S.current and S.playing then
        put(tx, rowTitle, pad(stripName(S.current), W - tx), C.text, C.bg)
    else
        put(tx, rowTitle, pad("Nothing playing", W - tx), C.dim, C.bg)
    end
    if S.msg and nowSec() < S.msgUntil then
        put(tx, rowSub, pad(S.msg, W - tx), colors.yellow, C.bg)
    else
        local sub
        local idx = trackIndex(S.current)
        if S.playing and idx then
            sub = string.format("Track %d of %d", idx, #S.tracks)
            local nxt = S.tracks[idx % #S.tracks + 1]
            if cfg.repeatMode == "One" then nxt = S.tracks[idx]
            elseif cfg.shuffle then nxt = nil end
            if nxt and #S.tracks > 1 and W >= 40 then sub = sub .. "   Next: " .. stripName(nxt.name) end
        else
            sub = plural(#S.tracks) .. " in /" .. folderPath()
        end
        put(tx, rowSub, pad(sub, W - tx), C.dim, C.bg)
    end

    -- Seek bar:  0:12 [=====-----] 3:45
    local cur = position()
    local total = S.playing and duration() or 0
    local left, rightT = fmtTime(cur), fmtTime(total)
    put(2, rowSeek, left, C.text, C.bg)
    put(W - #rightT, rowSeek, rightT, C.dim, C.bg)
    local bx1, bx2 = 2 + #left + 1, W - #rightT - 2
    if bx2 - bx1 >= 4 then
        local frac = total > 0 and clamp(cur / total, 0, 1) or 0
        local shim = (S.playing and not S.paused) and (math.floor(nowSec() * 30) % ((bx2 - bx1 + 1) * 2 + 20) - 10) or nil
        pill(bx1, rowSeek, bx2 - bx1 + 1, frac, S.playing, shim)
        seekRect = { x1 = bx1, x2 = bx2, y = rowSeek }
    end

    -- Volume and chips
    local vw = W >= 45 and 12 or (W >= 32 and 8 or 5)
    put(2, rowStatus, "Vol", C.dim, C.bg)
    pill(6, rowStatus, vw, cfg.muted and 0 or cfg.volume, false, nil)
    volRect = { x1 = 6, x2 = 5 + vw, y = rowStatus }
    local pct = cfg.muted and "mute" or (math.floor(cfg.volume * 100 + 0.5) .. "%")
    put(7 + vw, rowStatus, pad(pct, 4), C.text, C.bg)
    local x = 12 + vw
    local function flag(text, on, k)
        if x + #text + 2 > W then return end
        local used = chip(x, rowStatus, text, on and C.bg or C.dim, on and C.hl or C.panel, C.bg)
        addHit(x, x + used - 1, rowStatus, k)
        x = x + used + 1
    end
    flag("SHUF", cfg.shuffle, "s")
    flag("REP:" .. cfg.repeatMode, cfg.repeatMode ~= "Off", "r")
    if W >= 40 then flag("VIZ:" .. cfg.viz, cfg.viz ~= "Off", "v") end
    if W >= 46 then flag("SPK:" .. speakerLabel():sub(1, 10), #speakerNames() > 0, "o") end

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
    -- key, long description, short description (for narrow screens)
    local rows = {
        { "Space", "Play / pause", "Play/pause" },
        { "Enter", "Play the selected track", "Play track" },
        { "N / P", "Next / previous track", "Next/prev" },
        { "Left/Right", "Seek 10 seconds", "Seek 10s", "Arrow" },
        { "0-9", "Jump to 0-90% of the track", "Jump to %" },
        { "+ / -", "Volume   M mute", "Volume, M mute" },
        { "S", "Shuffle", "Shuffle" },
        { "R", "Repeat: Off, All, One", "Repeat mode" },
        { "/", "Search (Enter keeps, Esc clears)", "Search" },
        { "V", "Visualizer: Bars, Mirror, Off", "Visualizer" },
        { "O", "Speaker (Auto, All, or one)", "Speaker" },
        { "T", "Theme", "Theme" },
        { "F", "Music folder   L rescan", "Folder, L scan" },
        { "Click", "Tracks, seek bar, volume, chips", "Controls", "Mouse" },
        { "Q", "Quit", "Quit" },
    }
    local narrow = W < 40
    local lines = {}
    for i, r in ipairs(rows) do
        lines[i] = pad(narrow and (r[4] or r[1]) or r[1], narrow and 6 or 12) .. (narrow and r[3] or r[2])
    end
    while true do
        win.setVisible(false)
        term.setBackgroundColor(C.bg)
        term.clear()
        header("Help")
        local ch = math.min(H - 3, #lines + 2)
        card(2, 3, W - 2, ch)
        for i, l in ipairs(lines) do
            if i + 1 <= ch - 1 then put(4, 3 + i, pad(l, W - 6), C.text, C.panel) end
        end
        put(1, H, pad("  Press any key", W), C.bg, C.hl)
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
    local text = default or ""
    while true do
        win.setVisible(false)
        term.setBackgroundColor(C.bg)
        term.clear()
        header(label:sub(1, W - 6))
        card(2, 3, W - 2, 4)
        put(4, 4, pad(text:sub(-(W - 8)) .. "_", W - 6), C.text, C.panel)
        put(4, 5, pad("Enter saves, Esc cancels", W - 6), C.dim, C.panel)
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
    if k == "space" or k == " " then togglePause()
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
        say("Visualizer: " .. cfg.viz .. (cfg.viz == "Off" and "  (V turns it on)" or ""), 3)
    elseif k == "t" then
        cfg.theme = cycle(THEME_LIST, cfg.theme)
        saveCfg()
        applyPalette()
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
        if d >= S.peak[b] then
            S.peak[b], S.hold[b] = d, 6
        elseif S.hold[b] > 0 then
            S.hold[b] = S.hold[b] - 1
        else
            S.peak[b] = math.max(0, S.peak[b] - 0.04)
        end
    end
end

local function animating()
    if S.playing and not S.paused then return true end
    if S.msg and nowSec() < S.msgUntil + 0.2 then return true end
    for b = 1, BANDS do if S.disp[b] > 0 or S.peak[b] > 0 then return true end end
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
        elseif ev == "rednet_message" then
            if api and api.handleNet then pcall(api.handleNet, a, b, c) end
            redraw = false
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

-- ── Boot animation ───────────────────────────────────────────────────────────
-- The OS boot screen with this app's name as the logo, while the speakers and
-- the music folder are read for real.

local function bootScreen()
    local sc = api and api.boot and api.gfx and api.boot.start(false, "AUDIO")
    if not sc then rescan(); return end
    sc.tag = "Audio  v" .. VERSION
    api.boot.stage(sc, "Starting", 0.15)
    api.boot.stage(sc, "Finding speakers", 0.45, function() speakerNames() end)
    api.boot.stage(sc, "Reading /" .. folderPath(), 0.8, function(tick)
        rescan()
        tick()
    end)
    api.boot.stage(sc, plural(#S.tracks), 0.95)
    api.boot.finish(sc)
    api.restorePalette()
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local function main()
    if not term.isColour() then
        print("Prismarine Audio needs an advanced computer (colour).")
        return
    end
    math.randomseed(os.epoch("utc"))
    bootScreen()
    local native = term.current()
    W, H = native.getSize()
    win = window.create(native, 1, 1, W, H, true)
    term.redirect(win)
    applyPalette()
    local ok, err = pcall(function()
        parallel.waitForAny(audioTask, inputTask)
    end)
    stopSpeakers()
    term.redirect(native)
    resetPalette()
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
