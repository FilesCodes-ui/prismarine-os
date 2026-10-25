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
-- prismarine: background pixelbox
-- A DFPWM music player for Prismarine OS (CC:Tweaked). Colors follow the OS
-- theme from Settings. Put .dfpwm files in /music, or press F to pick a folder.
-- O opens a pop-up where you pick the speakers (one, several or all). The app asks
-- once to keep playing when it is not in front. Pixelbox draws the pop-up and
-- the visualizer when the OS offers it; without it the app draws them itself.
--
--   Space play/pause   N / P next / previous   Left / Right seek 10 s
--   0-9 jump to 0-90%  + / - volume            M mute
--   S shuffle          R repeat (Off, All, One)
--   A queue            C clear queue           B favorite       W favorites only
--   Y sort             E equalizer             Z sleep timer
--   / search           V visualizer            O speakers       F music folder
--   L rescan           ? help                  Q quit

local dfpwm = require("cc.audio.dfpwm")

-- The OS passes its helpers (boot screen, palette restore, network events)
-- when it opens this app. Run by hand there is no api and those are skipped.
local api = ...
if type(api) ~= "table" then api = nil end

local VERSION = "5"
local SETTINGS_FILE = ".prismaudio_settings"
local BYTES_PER_SEC = 6000      -- DFPWM is 48000 samples per second at 1 bit
local CHUNK = 2048              -- bytes per step (about 0.34 s of sound)
local LEAD = 1.2                -- seconds of sound sent ahead of the speaker
local BANDS = 16
local floor = math.floor

-- ── Settings ─────────────────────────────────────────────────────────────────

local VIZ_LIST = { "Calm", "Lively", "Float", "Off" }
local TONE_LIST = { "Flat", "Bass", "Treble", "Voice" }
local SORT_LIST = { "Name", "Shortest", "Longest" }
local REPEAT_LIST = { "Off", "All", "One" }
local SLEEP_LIST = { 0, 15, 30, 45, 60 }    -- minutes, 0 is off

local DEFAULTS = {
    volume = 0.5,
    muted = false,
    shuffle = false,
    repeatMode = "Off",     -- Off, All, One
    viz = "Calm",           -- Calm, Lively, Float, Off
    tone = "Flat",          -- Flat, Bass, Treble, Voice
    sort = "Name",          -- Name, Shortest, Longest
    favOnly = false,
    speaker = "Auto",       -- Auto, All, or Pick (see picks)
    picks = {},             -- speaker name -> true, used when speaker is Pick
    folder = "music",       -- "" is the main folder
    favs = {},              -- track name -> true
    last = "",              -- last track, for resuming
    lastPos = 0,            -- seconds into that track
}

local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
cfg.favs = {}
cfg.picks = {}
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

local function oneOf(list, v)
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

-- Old settings files hold values this version does not know. Fix them.
if not oneOf(VIZ_LIST, cfg.viz) then cfg.viz = "Calm" end
if not oneOf(TONE_LIST, cfg.tone) then cfg.tone = "Flat" end
if not oneOf(SORT_LIST, cfg.sort) then cfg.sort = "Name" end
if not oneOf(REPEAT_LIST, cfg.repeatMode) then cfg.repeatMode = "Off" end
if cfg.volume ~= cfg.volume or cfg.volume < 0 or cfg.volume > 1 then cfg.volume = DEFAULTS.volume end
if cfg.lastPos ~= cfg.lastPos or cfg.lastPos < 0 then cfg.lastPos = 0 end
-- Older files stored one speaker name. It becomes a pick of one.
if cfg.speaker ~= "Auto" and cfg.speaker ~= "All" and cfg.speaker ~= "Pick" then
    cfg.picks = { [tostring(cfg.speaker)] = true }
    cfg.speaker = "Pick"
end
do
    local picks = {}
    for k, v in pairs(cfg.picks) do
        if type(k) == "string" and v then picks[k] = true end
    end
    cfg.picks = picks
end
do
    local clean = {}
    for k, v in pairs(cfg.favs) do
        if type(k) == "string" and v then clean[k] = true end
    end
    cfg.favs = clean
end

local function saveCfg()
    local f = fs.open(SETTINGS_FILE, "w")
    if f then f.write(textutils.serialize(cfg)); f.close() end
end

-- ── Theme ────────────────────────────────────────────────────────────────────
-- Every color comes from the OS theme (prismarine.theme), so the player looks
-- like the rest of Prismarine and follows the look chosen in Settings. Run by
-- hand, or on an OS without a theme, these plain colors are used.

local FALLBACK = {
    bg = colors.black, panel = colors.black, hdr = colors.blue, text = colors.white,
    dim = colors.lightGray, line = colors.cyan, sel = colors.lightBlue, selText = colors.black,
    bar = colors.gray, barBtn = colors.blue, barText = colors.white, ok = colors.lime,
    warn = colors.yellow, err = colors.red, accent = colors.orange, hint = colors.lightGray,
}
local C = {}
local TONE = {}     -- how bright each color is, for the pixel renderer

local function osColors()
    local ok, c = pcall(function()
        local p = rawget(_G, "prismarine")
        local t = (p and p.theme) or (api and api.theme)
        return t and t.colors
    end)
    if ok then return c end
    return nil
end

-- Standard brightness of the 16 colors, used until the real palette is read.
local DEFAULT_TONE = {
    [colors.white] = 0.94, [colors.orange] = 0.72, [colors.magenta] = 0.55, [colors.lightBlue] = 0.6,
    [colors.yellow] = 0.85, [colors.lime] = 0.7, [colors.pink] = 0.7, [colors.gray] = 0.3,
    [colors.lightGray] = 0.6, [colors.cyan] = 0.55, [colors.purple] = 0.33, [colors.blue] = 0.28,
    [colors.brown] = 0.31, [colors.green] = 0.45, [colors.red] = 0.4, [colors.black] = 0.07,
}
local ALL_COLORS = {
    colors.black, colors.gray, colors.brown, colors.blue, colors.purple, colors.red, colors.green,
    colors.cyan, colors.magenta, colors.lightGray, colors.lightBlue, colors.pink, colors.lime,
    colors.orange, colors.yellow, colors.white,
}

local function tone(col) return TONE[col] or DEFAULT_TONE[col] or 0.5 end
local function gap(a, b) return math.abs(tone(a) - tone(b)) end

-- The color from prefs that stands apart from bg by at least need. When none
-- does, the color of all 16 that stands apart the most.
local function standout(bg, need, prefs)
    for _, c in ipairs(prefs or {}) do
        if c and gap(c, bg) >= need then return c end
    end
    local best, bestGap = colors.white, -1
    for _, c in ipairs(ALL_COLORS) do
        local g = gap(c, bg)
        if g > bestGap then best, bestGap = c, g end
    end
    return best
end

-- A theme may put two roles on near-equal colors (a custom theme, or Mono,
-- Crimson and Matrix). Anything that would vanish is swapped for a color that
-- reads clearly on its background.
local function ensure(role, against, need, prefs)
    if gap(C[role], C[against]) < need then
        C[role] = standout(C[against], need, prefs)
    end
end

local function loadTheme()
    local src = osColors()
    for role, default in pairs(FALLBACK) do
        local v
        if src then
            local ok, got = pcall(function() return src[role] end)
            if ok then v = got end
        end
        C[role] = (type(v) == "number" and DEFAULT_TONE[v]) and v or default
    end
    for i = 0, 15 do
        local slot = 2 ^ i
        local ok, r, g, b = pcall(term.getPaletteColor, slot)
        if ok and r then TONE[slot] = 0.3 * r + 0.59 * g + 0.11 * b end
    end
    -- Text and lines must be readable on the theme's own backgrounds.
    for _, bgRole in ipairs({ "bg", "panel" }) do
        ensure("text", bgRole, 0.4, { C.text, colors.white, colors.black })
        ensure("hint", bgRole, 0.25, { C.hint, C.dim, C.text })
        ensure("line", bgRole, 0.25, { C.line, C.accent, C.sel, C.text })
        ensure("accent", bgRole, 0.25, { C.accent, C.line, C.text })
        ensure("ok", bgRole, 0.25, { C.ok, C.line, C.text })
        ensure("warn", bgRole, 0.25, { C.warn, C.accent, C.text })
        ensure("err", bgRole, 0.2, { C.err, C.warn, C.text })
    end
    -- The selected row: its fill must show against the list, and its text against the fill.
    if gap(C.sel, C.bg) < 0.12 or gap(C.sel, C.panel) < 0.12 then
        C.sel = standout(C.bg, 0.3, { C.line, C.accent, colors.lightGray })
    end
    ensure("selText", "sel", 0.4, { colors.black, colors.white })
    ensure("barText", "bar", 0.4, { C.text, colors.white, colors.black })
    C.guide = (gap(C.bar, C.bg) >= 0.12) and C.bar or C.hint

    -- Visualizer colors: distinct theme colors that show against the background,
    -- dark to bright, so a bar fades from its root to its tip in any theme.
    local pool, seen = {}, {}
    for _, col in ipairs({ C.barBtn, C.line, C.sel, C.accent, C.info or C.line, C.ok, C.warn, C.text }) do
        if col and not seen[col] and gap(col, C.bg) >= 0.2 then
            seen[col] = true
            pool[#pool + 1] = col
        end
    end
    if #pool < 3 then
        for _, col in ipairs(ALL_COLORS) do
            if not seen[col] and gap(col, C.bg) >= 0.25 then
                seen[col] = true
                pool[#pool + 1] = col
            end
        end
    end
    table.sort(pool, function(a, b) return tone(a) < tone(b) end)
    local want = math.min(4, #pool)
    local ramp = {}
    if want <= 1 then
        ramp = { pool[1] or colors.white, pool[1] or colors.white, pool[1] or colors.white }
    else
        for i = 1, want do
            ramp[i] = pool[math.floor((i - 1) * (#pool - 1) / (want - 1) + 1.5)]
        end
    end
    C.ramp = ramp
    local cv = {}
    for i = 1, 3 do cv[i] = ramp[math.min(#ramp, i)] end
    C.cover = cv
end
loadTheme()

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
    queue = {},         -- track names to play next
    frames = {},        -- visualizer frames waiting for their time
    disp = {},          -- smoothed band heights
    msg = nil, msgUntil = 0,
    sleepAt = nil, sleepMin = 0,
    lastSave = 0,
    rearm = false,      -- a full screen page ran, so restart the tick timer
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

local function plural(n) return n .. (n == 1 and " track" or " tracks") end

local function stripName(name) return (name:gsub("%.[dD][fF][pP][wW][mM]$", "")) end

-- Cut to n columns. A cut text ends with "~".
local function fit(s, n)
    s = tostring(s)
    if n <= 0 then return "" end
    if #s > n then return s:sub(1, math.max(0, n - 1)) .. "~" end
    return s
end

local function pad(text, width)
    if width <= 0 then return "" end
    text = text:sub(1, width)
    return text .. string.rep(" ", width - #text)
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

local function selName()
    local i = S.view[S.sel]
    local t = i and S.tracks[i]
    return t and t.name or nil
end

local function sortTracks(list)
    local mode = cfg.sort
    table.sort(list, function(a, b)
        if mode == "Shortest" and a.size ~= b.size then return a.size < b.size end
        if mode == "Longest" and a.size ~= b.size then return a.size > b.size end
        return a.name:lower() < b.name:lower()
    end)
end

-- Rebuilds the visible list. The selection stays on the same track when it
-- can: first the track named in keep, then the playing track.
local function applyFilter(keep)
    keep = keep or selName()
    S.view = {}
    local q = S.query:lower()
    for i, t in ipairs(S.tracks) do
        if (q == "" or t.name:lower():find(q, 1, true)) and (not cfg.favOnly or cfg.favs[t.name]) then
            S.view[#S.view + 1] = i
        end
    end
    local function find(name)
        if not name then return nil end
        for n, i in ipairs(S.view) do
            if S.tracks[i].name == name then return n end
        end
        return nil
    end
    S.sel = find(keep) or find(S.current) or clamp(S.sel, 1, math.max(1, #S.view))
end

local function rescan()
    local keep = selName()
    local out = {}
    local dir = folderPath()
    if dir == "music" and not fs.exists(dir) then pcall(fs.makeDir, dir) end
    scanDir(dir, "", 0, out)
    sortTracks(out)
    S.tracks = out
    applyFilter(keep)
end

local function trackIndex(name)
    for i, t in ipairs(S.tracks) do if t.name == name then return i end end
    return nil
end

-- The tracks next and previous walk through: what the list shows now (search
-- or favorites), or every track when the list is empty.
local function pool()
    local out = {}
    for _, i in ipairs(S.view) do out[#out + 1] = S.tracks[i].name end
    if #out == 0 then
        for _, t in ipairs(S.tracks) do out[#out + 1] = t.name end
    end
    return out
end

local function poolIndex(list, name)
    for i, n in ipairs(list) do
        if n == name then return i end
    end
    return nil
end

-- Place of a track in the queue, or nil.
local function queuePos(name)
    for i, n in ipairs(S.queue) do
        if n == name then return i end
    end
    return nil
end

local function nextFromQueue()
    while #S.queue > 0 do
        local name = table.remove(S.queue, 1)
        if trackIndex(name) then return name end
    end
    return nil
end

-- The track that plays after this one, or nil when it is not known yet.
local function peekNext()
    if cfg.repeatMode == "One" then return S.current end
    for _, n in ipairs(S.queue) do
        if trackIndex(n) then return n end
    end
    if cfg.shuffle then return nil end
    local list = pool()
    local cur = poolIndex(list, S.current)
    local nx = (cur or 0) + 1
    if nx <= #list then return list[nx] end
    if cfg.repeatMode == "All" then return list[1] end
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
    elseif cfg.speaker == "Pick" then
        for _, n in ipairs(names) do
            if cfg.picks[n] then table.insert(list, peripheral.wrap(n)) end
        end
        -- Every picked speaker is gone: use the first one, so music still plays.
        if #list == 0 and names[1] then table.insert(list, peripheral.wrap(names[1])) end
    elseif names[1] then
        table.insert(list, peripheral.wrap(names[1]))
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
    if cfg.speaker == "Pick" then
        local n, last = 0, nil
        for _, name in ipairs(names) do
            if cfg.picks[name] then n = n + 1; last = name end
        end
        if n == 1 then return last end
        if n > 1 then return n .. " of " .. #names end
    end
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

-- Loudness follows the loudest recent band and falls fairly fast, so quiet and
-- loud songs both fill the bars and a soft passage still moves them. Heights use
-- a log scale like a real spectrum. A larger offset or a smaller span makes the
-- bars more sensitive.
local log10 = math.log10 or function(x) return math.log(x) / math.log(10) end
local REF_FLOOR, REF_DECAY = 1.5, 0.95
local LOG_SPAN, LOG_OFFSET = 1.5, 2.3
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
            mag = mag * (1 + (b - 1) / BANDS * 2.0)
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
    local now = nowSec()
    while #S.frames > 600 and S.frames[1].t < now do table.remove(S.frames, 1) end
    while #S.frames > 2400 do table.remove(S.frames, 1) end
end


-- ── Equalizer ────────────────────────────────────────────────────────────────
-- Simple one pole filters on the decoded sound. Flat leaves it alone.

local toneState = { a = 0, b = 0 }
local function resetTone() toneState.a, toneState.b = 0, 0 end

local function applyTone(buf)
    local mode = cfg.tone
    if mode == "Flat" then return end
    local a, b = toneState.a, toneState.b
    for i = 1, #buf do
        local x = buf[i]
        local y
        if mode == "Bass" then
            a = a + 0.03 * (x - a)
            y = x + 0.8 * a
        elseif mode == "Treble" then
            a = a + 0.3 * (x - a)
            y = x + (x - a)
        else
            a = a + 0.37 * (x - a)
            b = b + 0.04 * (x - b)
            y = 0.5 * x + 1.2 * (a - b)
        end
        y = floor(y + 0.5)
        if y > 127 then y = 127 elseif y < -128 then y = -128 end
        buf[i] = y
    end
    toneState.a, toneState.b = a, b
end

-- Raises the first 0.1 s from silence so a start, resume or seek does not pop.
local function fadeIn(buf)
    local n = math.min(#buf, 4800)
    for i = 1, n do buf[i] = floor(buf[i] * i / n + 0.5) end
end

-- ── Audio task ───────────────────────────────────────────────────────────────

local function onTrackEnd()
    local list = pool()
    local cur = poolIndex(list, S.current)
    local nextName
    if cfg.repeatMode == "One" then
        nextName = S.current
    else
        nextName = nextFromQueue()
        if not nextName then
            if cfg.shuffle and #list > 1 then
                local n
                repeat n = math.random(1, #list) until n ~= cur
                nextName = list[n]
            else
                local nx = (cur or 0) + 1
                if nx <= #list then
                    nextName = list[nx]
                elseif cfg.repeatMode == "All" and #list > 0 then
                    nextName = list[1]
                end
            end
        end
    end
    if nextName then
        if nextName ~= S.current then table.insert(S.history, S.current) end
        S.current = nextName
        S.want = { name = nextName, offset = 0, auto = true }
        cfg.last, cfg.lastPos = nextName, 0
    else
        S.playing, S.paused = false, false
        cfg.lastPos = 0
        saveCfg()
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
    if want.stop then
        stopSpeakers()
        S.frames = {}
        S.playing, S.paused = false, false
        return
    end
    local path = fs.combine(folderPath(), want.name)
    local f = fs.exists(path) and fs.open(path, "rb")
    if not f then
        say("Cannot open " .. want.name, 4)
        S.playing, S.paused = false, false
        return
    end
    -- Sound still queued from the last track must not play over this one. A
    -- track that follows on its own has already played out.
    if not want.auto then stopSpeakers() end
    local size = fs.getSize(path)
    S.size = size
    local pos = clamp(math.floor(want.offset or 0), 0, math.max(0, size - 1))
    if pos > 0 then f.seek("set", pos) end
    local decoder = dfpwm.make_decoder()
    resetTone()
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
            resetTone()
            S.base = pos / BYTES_PER_SEC
            fresh = true
        end
        local chunk = f.read(CHUNK)
        if not chunk then finished = true; break end
        local buf = decoder(chunk)
        applyTone(buf)
        if fresh then
            S.t0 = nowSec()
            fresh = false
            fadeIn(buf)
        end
        local startAt = S.t0 + (pos / BYTES_PER_SEC - S.base)
        -- Keep the speaker only a little ahead, so volume, equalizer and skips
        -- take effect within a second.
        local lead = startAt - nowSec()
        if lead > LEAD then sleep(lead - LEAD) end
        if S.quit or S.want then break end
        if cfg.viz ~= "Off" then
            local okA, errA = pcall(analyse, buf, startAt)
            if not okA then say("Viz error: " .. tostring(errA), 6) end
        end
        pos = pos + #chunk
        send(buf)
    end
    f.close()
    if finished and not S.quit and not S.want then
        -- Let the last second of sound play out before moving on.
        local endAt = S.t0 + (size / BYTES_PER_SEC - S.base)
        while nowSec() < endAt and not S.quit and not S.want and not S.paused do sleep(0.1) end
        if S.paused and not S.quit and not S.want then
            -- Paused while the last seconds were still playing. Load the track
            -- again, paused at the same spot, so Play still works.
            stopSpeakers()
            S.want = { name = S.current, offset = S.frozen * BYTES_PER_SEC, paused = true }
        elseif not S.want and not S.quit then
            onTrackEnd()
        end
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

local function cycle(list, value)
    for i, v in ipairs(list) do
        if v == value then return list[i % #list + 1] end
    end
    return list[1]
end

-- Remembers the track and the spot, so the next start can continue from here.
local function savePos()
    S.lastSave = nowSec()
    if S.current and S.playing then
        cfg.last = S.current
        cfg.lastPos = floor(position())
        saveCfg()
    end
end

local function startTrack(name, offset, noHistory)
    if not name then return end
    if #speakerNames() == 0 then say("No speaker attached.", 4); return end
    if not noHistory and S.current and S.current ~= name then
        table.insert(S.history, S.current)
        if #S.history > 100 then table.remove(S.history, 1) end
    end
    S.current = name
    for i = #S.queue, 1, -1 do
        if S.queue[i] == name then table.remove(S.queue, i) end
    end
    local i = trackIndex(name)
    S.size = i and S.tracks[i].size or 0
    S.paused = false
    S.playing = true
    S.base, S.t0 = (offset or 0) / BYTES_PER_SEC, nowSec()
    S.want = { name = name, offset = offset or 0 }
    cfg.last, cfg.lastPos = name, floor((offset or 0) / BYTES_PER_SEC)
end

local function pauseNow()
    if S.playing and not S.paused then
        S.frozen = position()
        S.paused = true
        savePos()
    end
end

local function togglePause()
    if not S.playing then
        startTrack(selName() or S.current)
        return
    end
    if S.paused then
        if #speakerNames() == 0 then say("No speaker attached.", 4); return end
        S.paused = false
    else
        pauseNow()
    end
end

local function stepTrack(dir)
    local list = pool()
    if #list == 0 then return end
    if #speakerNames() == 0 then say("No speaker attached.", 4); return end
    local cur = poolIndex(list, S.current)
    if dir > 0 then
        local name = nextFromQueue()
        if not name then
            if cfg.shuffle and #list > 1 then
                local n
                repeat n = math.random(1, #list) until n ~= cur
                name = list[n]
            else
                name = list[(cur or 0) % #list + 1]
            end
        end
        startTrack(name)
    else
        if position() > 4 and S.current then
            startTrack(S.current, 0, true)
            return
        end
        local prev = table.remove(S.history)
        if prev and trackIndex(prev) then
            startTrack(prev, 0, true)
        else
            local n = (cur or 1) - 1
            if n < 1 then n = #list end
            startTrack(list[n], 0, true)
        end
    end
end

local function seekTo(sec)
    if not S.current or not S.playing then return end
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

-- Plays the same spot again, so a changed setting is heard at once.
local function restartHere()
    if S.playing and not S.paused then seekTo(position()) end
end

local function setVolume(v)
    cfg.volume = clamp(math.floor(v * 100 + 0.5) / 100, 0, 1)
    if cfg.volume > 0 then cfg.muted = false end
    S.cfgDirty = nowSec()
end

local function toggleQueue()
    local name = selName()
    if not name then return end
    local at = queuePos(name)
    if at then
        table.remove(S.queue, at)
        say("Removed from the queue: " .. stripName(name), 2)
    else
        S.queue[#S.queue + 1] = name
        say("Queued " .. #S.queue .. ": " .. stripName(name), 2)
    end
end

local function clearQueue()
    if #S.queue == 0 then say("The queue is empty.", 2); return end
    S.queue = {}
    say("Queue cleared.", 2)
end

local function toggleFav()
    local name = selName()
    if not name then return end
    if cfg.favs[name] then
        cfg.favs[name] = nil
        say("Removed from favorites.", 2)
    else
        cfg.favs[name] = true
        say("Added to favorites.", 2)
    end
    saveCfg()
    if cfg.favOnly then applyFilter() end
end

local function toggleFavOnly()
    cfg.favOnly = not cfg.favOnly
    saveCfg()
    S.top = 1
    applyFilter()
    say(cfg.favOnly and "Showing favorites only." or "Showing all tracks.", 2)
end

local function cycleSort()
    local keep = selName()
    cfg.sort = cycle(SORT_LIST, cfg.sort)
    saveCfg()
    sortTracks(S.tracks)
    applyFilter(keep)
    say("Sort: " .. cfg.sort, 2)
end

local function cycleTone()
    cfg.tone = cycle(TONE_LIST, cfg.tone)
    saveCfg()
    restartHere()
    say("Equalizer: " .. cfg.tone, 2)
end

local function cycleViz()
    cfg.viz = cycle(VIZ_LIST, cfg.viz)
    saveCfg()
    for b = 1, BANDS do S.peak[b], S.hold[b] = 0, 0 end
    S.frames = {}
    say("Visualizer: " .. (cfg.viz == "Float" and "Floating" or cfg.viz), 2)
end

local function cycleSleep()
    local idx = 1
    for i, m in ipairs(SLEEP_LIST) do
        if m == S.sleepMin then idx = i end
    end
    S.sleepMin = SLEEP_LIST[idx % #SLEEP_LIST + 1]
    if S.sleepMin == 0 then
        S.sleepAt = nil
        say("Sleep timer off.", 2)
    else
        S.sleepAt = nowSec() + S.sleepMin * 60
        say("Sleep timer: " .. S.sleepMin .. " min", 2)
    end
end

-- Runs about ten times a second: the sleep timer and saving the spot.
local function housekeeping()
    local now = nowSec()
    if S.sleepAt and now >= S.sleepAt then
        S.sleepAt, S.sleepMin = nil, 0
        if S.playing and not S.paused then
            pauseNow()
            say("Sleep timer ended. Paused.", 8)
        end
    end
    if S.playing and not S.paused and now - S.lastSave >= 10 then savePos() end
    if S.cfgDirty and now - S.cfgDirty >= 0.5 then S.cfgDirty = nil; saveCfg() end
end

-- Stops the music and forgets what was queued. Used when the folder changes,
-- since the loaded track no longer exists in the new folder.
local function stopPlayback()
    S.queue, S.history = {}, {}
    S.current, S.playing, S.paused, S.size = nil, false, false, 0
    S.want = { stop = true }
    cfg.last, cfg.lastPos = "", 0
    saveCfg()
end

local function applyFolder(path)
    path = fs.combine("", path)
    if path == "rom" or path:sub(1, 4) == "rom/" then
        say("The rom folder cannot be used.", 3)
        return false
    end
    if path ~= "" and (not fs.exists(path) or not fs.isDir(path)) then
        say("There is no folder called " .. path, 4)
        return false
    end
    if path ~= cfg.folder then stopPlayback() end
    cfg.folder = path
    saveCfg()
    S.query = ""
    S.top, S.sel = 1, 1
    rescan()
    say("Folder: /" .. path .. "  (" .. #S.tracks .. " tracks)", 3)
    return true
end

-- Loads the last track, paused at the spot where it stopped.
local function restoreLast()
    if cfg.last == "" or S.playing then return end
    local i = trackIndex(cfg.last)
    if not i then return end
    local size = S.tracks[i].size
    local pos = cfg.lastPos
    if pos > size / BYTES_PER_SEC - 3 then pos = 0 end
    S.current = cfg.last
    S.size = size
    S.frozen = pos
    S.paused, S.playing = true, true
    S.want = { name = S.current, offset = pos * BYTES_PER_SEC, paused = true }
    applyFilter(S.current)
end

-- ── Screen basics ────────────────────────────────────────────────────────────

local W, H = term.getSize()
local win
local hits = {}
local listRect = { y1 = 0, y2 = 0 }
local seekRect, volRect

local function put(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end

local function addHit(x1, x2, y, k) table.insert(hits, { x1 = x1, x2 = x2, y = y, k = k }) end

-- ── Sub-pixel graphics ───────────────────────────────────────────────────────
-- Every terminal cell holds 2x3 pixels (the teletext characters 128-159). A
-- canvas is a grid of pixels (a color, or false for the background). render
-- turns it into characters, using the two most common colors in each cell.

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

local function renderOwn(c, x0, y0, bg)
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

-- ── Pixelbox ─────────────────────────────────────────────────────────────────
-- When the OS offers Pixelbox_lite (prismarine.pixelbox), canvases are drawn
-- with it. Each canvas size and place gets its own small window and box, kept
-- for the next frame. If anything fails, the built-in drawing above takes over.

local osApi = rawget(_G, "prismarine")
local PBM = nil
do
    local ok, m = pcall(function() return osApi and osApi.pixelbox end)
    if ok and type(m) == "table" and type(m.new) == "function" then PBM = m end
end
local pbCache, pbCount = {}, 0

local function renderPB(c, x0, y0, bg)
    bg = bg or C.bg
    local key = c.cw .. "x" .. c.ch .. "@" .. x0 .. "," .. y0
    local e = pbCache[key]
    if not e then
        local sub = window.create(term.current(), x0, y0, c.cw, c.ch, true)
        local box, why = PBM.new(sub, bg)
        if not box then error(why or "no box", 0) end
        if pbCount >= 24 then pbCache, pbCount = {}, 0 end
        e = { box = box }
        pbCache[key] = e
        pbCount = pbCount + 1
    end
    local cv = e.box.canvas
    for y = 1, c.ph do
        local src, dst = c[y], cv[y]
        for x = 1, c.pw do dst[x] = src[x] or bg end
    end
    e.box:render()
end

local function render(c, x0, y0, bg)
    if PBM then
        if pcall(renderPB, c, x0, y0, bg) then return end
        PBM = nil       -- something is off, so draw with the built-in code from now on
    end
    renderOwn(c, x0, y0, bg)
end

-- ── Elements ─────────────────────────────────────────────────────────────────
-- The same look as the OS apps: a title chip on a bar, key hints along the
-- bottom, a ">" on the selected row, boxes with a solid border.

local function header(title, context, right)
    put(1, 1, string.rep(" ", W), C.barText, C.bar)
    local chipText = " " .. title .. " "
    put(1, 1, chipText, C.barText, C.barBtn)
    local x = #chipText + 2
    local hasRight = right and right ~= ""
    if hasRight then
        right = fit(right, math.max(0, W - x - 2))
        put(W - #right, 1, right, C.hint, C.bar)
    end
    if context and context ~= "" then
        local room = W - x - (hasRight and (#right + 2) or 0)
        put(x, 1, fit(context, room), C.barText, C.bar)
    end
end

-- Key hints on row y. list = { { "N", "next", "n" } }. The third value makes
-- the hint clickable. Hints that do not fit are left out from the end.
local function hintLine(y, list, withHits)
    put(1, y, string.rep(" ", W), C.hint, C.bg)
    local x = 2
    for _, it in ipairs(list) do
        local key, label = it[1], it[2]
        local need = #key + 1 + #label
        if x + need - 1 > W then break end
        put(x, y, key, C.line, C.bg)
        put(x + #key + 1, y, label, C.hint, C.bg)
        if withHits and it[3] then addHit(x, x + need - 1, y, it[3]) end
        x = x + need + 2
    end
end

-- A box with a solid border in the line color.
local function box(x, y, w, h)
    if w < 3 or h < 2 then return end
    for r = 0, h - 1 do
        if r == 0 or r == h - 1 then
            put(x, y + r, string.rep(" ", w), C.text, C.line)
        else
            put(x, y + r, " ", C.text, C.line)
            put(x + 1, y + r, string.rep(" ", w - 2), C.text, C.panel)
            put(x + w - 1, y + r, " ", C.text, C.line)
        end
    end
end

-- One list row across the width.
local function itemRow(y, text, right, on, mark)
    local bg = on and C.sel or C.bg
    local fg = on and C.selText or C.text
    put(1, y, string.rep(" ", W), fg, bg)
    if on then put(1, y, ">", C.selText, bg) end
    if mark then put(3, y, "\16", on and C.selText or C.line, bg) end
    right = right or ""
    put(5, y, pad(text, W - 5 - #right - 2), fg, bg)
    if right ~= "" then put(W - #right, y, right, on and C.selText or C.hint, bg) end
end

-- A thin slider: a line with a tall marker at the fill point.
local function pill(x, y, cw, frac)
    local c = newCanvas(cw, 1)
    for px = 1, c.pw do c[2][px] = C.bar end
    local fill = math.floor(c.pw * clamp(frac, 0, 1) + 0.5)
    for px = 1, fill do c[2][px] = C.line end
    if fill >= 1 then
        local head = math.max(1, math.min(c.pw, fill))
        c[1][head], c[2][head], c[3][head] = C.sel, C.sel, C.sel
    end
    render(c, x, y)
end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

-- Small generated cover art, different for every track. Three theme colors.
local function cover(x, y, name)
    local c = newCanvas(3, 2)
    rect(c, 1, 1, c.pw, c.ph, C.panel)
    if name then
        local h = hash(name)
        local shift, twist = h % 6, 1 + math.floor(h / 7) % 3
        local tones = C.cover
        for py = 1, c.ph do
            for px = 1, c.pw do
                local v = ((px * twist + py * (4 - twist) + shift) % 6) / 5
                local diag = (px + py) / (c.pw + c.ph)
                local idx = math.floor(((v * 0.55 + diag * 0.45 + (h % 100) / 100) % 1) * #tones) + 1
                c[py][px] = tones[math.min(#tones, idx)]
            end
        end
    else
        local note = { "..####", "..#..#", "..#..#", ".##.##", "###.##", ".#...." }
        for py, row in ipairs(note) do
            for px = 1, 6 do
                if row:sub(px, px) == "#" then c[py][px] = C.bar end
            end
        end
    end
    render(c, x, y)
end

-- ── Visualizer ───────────────────────────────────────────────────────────────

-- Two rows more than before. Float needs the most room, since it grows both ways.
local function vizRows()
    if cfg.viz == "Off" then return 0 end
    local calm = cfg.viz == "Calm"
    if H >= 19 then return calm and 6 or 8 end
    if H >= 15 then return calm and 5 or 6 end
    if H >= 13 then return calm and 4 or 5 end
    return 0
end

-- Blends two palette colors by picking from a short ramp, so a bar fades from
-- its root to its tip using only theme colors.
local function rampColor(t)
    local n = #C.ramp
    return C.ramp[clamp(floor(t * (n - 1) + 1.5), 1, n)]
end

-- Floating mode: a center line, with every bar growing up and down from it.
local function drawFloat(c)
    local pw, ph = c.pw, c.ph
    local per = math.max(2, floor((pw - 4) / BANDS))
    local x0 = floor((pw - per * BANDS) / 2) + 1
    local bw = math.max(1, per - 2)
    local half = floor((ph - 1) / 2)       -- pixels above and below the line
    local mid = half + 1
    -- the line itself, dotted so it reads as a guide and not as a bar
    for x = 1, pw do
        if x % 2 == 1 then c[mid][x] = C.guide end
    end
    for b = 1, BANDS do
        local x1 = x0 + (b - 1) * per
        local x2 = x1 + bw - 1
        local h = floor(S.disp[b] * half + 0.5)
        -- idle dot on the line, so a quiet band still shows
        local lit = math.max(1, h)
        for k = 1, lit do
            local col = h == 0 and C.line or rampColor(k / half)
            local up, down = c[mid - k], c[mid + k]
            for x = math.max(1, x1), math.min(pw, x2) do
                if up then up[x] = col end
                if down then down[x] = col end
            end
        end
        -- center pixel in the band color, so the bar looks anchored on the line
        for x = math.max(1, x1), math.min(pw, x2) do c[mid][x] = C.line end
        -- slim caps that hang a little past the tip
        local pk = floor((S.peak[b] or 0) * half + 0.5)
        if pk > h + 1 then
            local up, down = c[mid - pk], c[mid + pk]
            for x = math.max(1, x1), math.min(pw, x2) do
                if up then up[x] = C.text end
                if down then down[x] = C.dim end
            end
        end
    end
end

local function drawViz(y1, rows)
    local calm = cfg.viz == "Calm"
    local c = newCanvas(W, rows)
    local pw, ph = c.pw, c.ph
    local per = math.max(2, math.floor((pw - 4) / BANDS))
    local x0 = math.floor((pw - per * BANDS) / 2) + 1

    if cfg.viz == "Float" then
        drawFloat(c)
        render(c, 1, y1)
        return
    end

    if calm then
        -- Slim bars in one color, a bright tip, a faint line underneath.
        local bw = math.max(1, per - 2)
        local base = ph - 1
        local up = math.max(1, ph - 3)
        for x = 1, pw do c[ph][x] = C.bar end
        for b = 1, BANDS do
            local h = math.floor(S.disp[b] * up * 0.95 + 0.5)
            local x1 = x0 + (b - 1) * per
            for k = 1, h do
                local row = c[base - k + 1]
                if row then
                    local col = (k == h and h >= 2) and C.sel or C.line
                    for x = math.max(1, x1), math.min(pw, x1 + bw - 1) do row[x] = col end
                end
            end
        end
        render(c, 1, y1)
        return
    end

    -- Lively: ramp colors, peak caps, a dotted reflection.
    local bw = per - 1
    local base = math.floor(ph * 0.78)
    local up = base - 2
    for _, f in ipairs({ 0.25, 0.5, 0.75 }) do
        local gy = math.floor(base - up * f)
        for x = 1, pw, 2 do if c[gy] then c[gy][x] = C.bar end end
    end
    for b = 1, BANDS do
        local x1 = x0 + (b - 1) * per
        local x2 = x1 + bw - 1
        local h = math.floor(S.disp[b] * up + 0.5)
        for k = 1, h do
            local idx = math.min(#C.ramp, math.floor((k / up) * (#C.ramp - 1) + 1.5))
            local row = c[base - k + 1]
            if row then
                for x = math.max(1, x1), math.min(pw, x2) do row[x] = C.ramp[idx] end
            end
        end
        local rh = math.floor(h * 0.45)
        for k = 1, rh do
            local row = c[base + k]
            if row then
                for x = math.max(1, x1), math.min(pw, x2) do
                    if (x + k) % 2 == 0 then row[x] = C.bar end
                end
            end
        end
        local pk = math.floor((S.peak[b] or 0) * up + 0.5)
        if pk > h + 1 then
            local row = c[base - pk + 1]
            if row then
                for x = math.max(1, x1), math.min(pw, x2) do row[x] = C.text end
            end
        end
        if h == 0 then
            local row = c[base]
            if row then
                for x = math.max(1, x1), math.min(pw, x2) do row[x] = C.bar end
            end
        end
    end
    for x = 1, pw do
        if c[base + 1] and not c[base + 1][x] then c[base + 1][x] = C.bar end
    end
    render(c, 1, y1)
end

-- ── Speaker pop-up ───────────────────────────────────────────────────────────
-- O opens a box in the middle of the screen. Auto plays on the first speaker.
-- Tick any speakers to play on those. The frame is drawn as pixels (Pixelbox
-- when available): a double outline with a light that runs along the edge.

local POP_ANIM = 0.18
local popRows = {}
local popRect = nil

local function activeNameSet()
    local names, set = speakerNames(), {}
    if cfg.speaker == "All" then
        for _, n in ipairs(names) do set[n] = true end
    elseif cfg.speaker == "Pick" then
        for _, n in ipairs(names) do if cfg.picks[n] then set[n] = true end end
        if next(set) == nil and names[1] then set[names[1]] = true end
    elseif names[1] then
        set[names[1]] = true
    end
    return set
end

local function openSpeakers()
    S.pop = { sel = 1, top = 1, at = nowSec(), names = speakerNames() }
    local set = activeNameSet()
    -- start on the first speaker that is in use, when one is picked
    if cfg.speaker ~= "Auto" then
        for i, n in ipairs(S.pop.names) do
            if set[n] then S.pop.sel = i + 1; break end
        end
    end
end

local function closePop() S.pop = nil; popRows, popRect = {}, nil end

local function applySpeakers(mode, picks)
    if S.playing then stopSpeakers() end
    cfg.speaker, cfg.picks = mode, picks or {}
    saveCfg()
    restartHere()
end

local function popToggle()
    local pop = S.pop
    if not pop then return end
    if pop.sel == 1 then
        applySpeakers("Auto")
        return
    end
    local name = pop.names[pop.sel - 1]
    if not name then return end
    local set = {}
    if cfg.speaker == "All" then
        for _, n in ipairs(pop.names) do set[n] = true end
    elseif cfg.speaker == "Pick" then
        for k in pairs(cfg.picks) do set[k] = true end
    end
    if set[name] then set[name] = nil else set[name] = true end
    if next(set) == nil then applySpeakers("Auto") else applySpeakers("Pick", set) end
end

local function popTest()
    local pop = S.pop
    local name = pop and (pop.sel == 1 and pop.names[1] or pop.names[pop.sel - 1])
    local sp = name and peripheral.wrap(name)
    if sp then
        pcall(sp.playNote, "bell", 1, 14)
        say("Test tone on " .. name, 2)
    else
        say("No speaker attached.", 3)
    end
end

local function popMove(d)
    local pop = S.pop
    local n = 1 + #pop.names
    pop.sel = (pop.sel - 1 + d) % n + 1
end

-- Returns true when the key belonged to the pop-up (it always does while open).
local function popKey(a)
    local pop = S.pop
    if a == keys.up then popMove(-1)
    elseif a == keys.down then popMove(1)
    elseif a == keys.home then pop.sel = 1
    elseif a == keys["end"] then pop.sel = 1 + #pop.names
    elseif a == keys.enter or a == keys.escape or a == keys.numPadEnter then closePop()
    elseif a == keys.space then popToggle()
    end
end

local function popChar(ch)
    local k = tostring(ch):lower()
    if k == " " then popToggle()
    elseif k == "a" then
        if #S.pop.names > 0 then applySpeakers("All"); say("All speakers.", 2) end
    elseif k == "t" then popTest()
    elseif k == "o" or k == "q" then closePop()
    end
end

local function popClick(x, y)
    if popRect and x >= popRect.x1 and x <= popRect.x2 and y >= popRect.y1 and y <= popRect.y2 then
        for _, r in ipairs(popRows) do
            if y == r.y and x >= r.x1 and x <= r.x2 then
                S.pop.sel = r.idx
                popToggle()
                return
            end
        end
    else
        closePop()
    end
end

-- The frame: a bright outline, a dim line just inside it, rounded corners, and
-- a small light that runs along the top and bottom edges.
local function popFrame(cw, ch, full)
    local c = newCanvas(cw, ch)
    local pw, ph = c.pw, c.ph
    rect(c, 1, 1, pw, ph, C.panel)
    rect(c, 2, 2, pw - 1, ph - 1, C.bar)
    rect(c, 3, 3, pw - 2, ph - 2, C.panel)
    rect(c, 1, 1, pw, 1, C.line)
    rect(c, 1, ph, pw, ph, C.line)
    rect(c, 1, 1, 1, ph, C.line)
    rect(c, pw, 1, pw, ph, C.line)
    -- rounded corners: the corner pixel shows the screen background
    c[1][1], c[1][pw], c[ph][1], c[ph][pw] = false, false, false, false
    local t = floor(nowSec() * 24)
    local span = pw + 10
    local head = t % span - 5
    for k = 0, 7 do
        local x = head + k
        if x >= 3 and x <= pw - 2 then
            c[1][x] = (k >= 3 and k <= 5) and C.text or C.sel
        end
        local xb = pw - head - k
        if xb >= 3 and xb <= pw - 2 then
            c[ph][xb] = (k >= 3 and k <= 5) and C.text or C.sel
        end
    end
    if full and ch >= 5 then
        for x = 5, pw - 4 do c[8][x] = C.bar end
    end
    return c
end

local function drawPopup()
    local pop = S.pop
    if not pop then return end
    local names = pop.names
    local noSpk = #names == 0
    local n = 1 + #names
    local rowsNeeded = n + (noSpk and 1 or 0)
    local vr = clamp(rowsNeeded, 1, math.max(1, math.min(10, H - 8)))
    local popW = clamp(W - 4, 20, 40)
    if popW > W then popW = W end
    local popH = math.min(H, vr + 5)
    local p = clamp((nowSec() - pop.at) / POP_ANIM, 0, 1)
    local eased = 1 - (1 - p) ^ 3
    local curH = math.max(3, floor(popH * eased + 0.5))
    local x = floor((W - popW) / 2) + 1
    local y = floor((H - curH) / 2) + 1
    popRect = { x1 = x, y1 = y, x2 = x + popW - 1, y2 = y + curH - 1 }
    popRows = {}
    render(popFrame(popW, curH, curH == popH), x, y)
    if curH < popH then return end

    local inner = popW - 2
    put(x + 1, y + 1, pad(" Speakers", inner), C.text, C.panel)
    local who = speakerLabel()
    put(x + popW - 2 - #who, y + 1, who, C.hint, C.panel)

    if pop.sel < pop.top then pop.top = pop.sel end
    if pop.sel > pop.top + vr - 1 then pop.top = pop.sel - vr + 1 end
    pop.top = clamp(pop.top, 1, math.max(1, rowsNeeded - vr + 1))

    local set = activeNameSet()
    for i = 1, vr do
        local idx = pop.top + i - 1
        local yy = y + 2 + i
        local on = idx == pop.sel
        local bg = on and C.sel or C.panel
        local fg = on and C.selText or C.text
        local dim = on and C.selText or C.hint
        put(x + 1, yy, string.rep(" ", inner), fg, bg)
        if idx == 1 then
            put(x + 2, yy, (cfg.speaker == "Auto") and "[x]" or "[ ]", (cfg.speaker == "Auto") and (on and C.selText or C.ok) or dim, bg)
            put(x + 6, yy, "Auto", fg, bg)
            local note = (inner >= 28 and "first speaker") or (inner >= 20 and "first") or ""
            if note ~= "" then put(x + popW - 2 - #note, yy, note, dim, bg) end
        elseif names[idx - 1] then
            local name = names[idx - 1]
            local ticked = (cfg.speaker == "All") or (cfg.speaker == "Pick" and cfg.picks[name])
            put(x + 2, yy, ticked and "[x]" or "[ ]", ticked and (on and C.selText or C.ok) or dim, bg)
            local tag = set[name] and "on" or ""
            put(x + 6, yy, fit(name, inner - 6 - #tag - 3), fg, bg)
            if tag ~= "" then put(x + popW - 2 - #tag, yy, tag, dim, bg) end
        elseif noSpk and idx == 2 then
            put(x + 2, yy, "No speaker attached.", C.warn, bg)
        end
        if idx == 1 or names[idx - 1] then
            popRows[#popRows + 1] = { x1 = x + 1, x2 = x + popW - 2, y = yy, idx = idx }
        end
    end
    if pop.top > 1 then put(x + popW - 2, y + 3, "\30", C.line, C.panel) end
    if pop.top + vr - 1 < rowsNeeded then put(x + popW - 2, y + 2 + vr, "\31", C.line, C.panel) end
    put(x + 1, y + 3 + vr, pad(fit(" Space pick  A all  T test  Enter done", inner), inner), C.hint, C.panel)
end

-- ── Main screen ──────────────────────────────────────────────────────────────

local function draw()
    win.setVisible(false)
    hits = {}
    seekRect, volRect = nil, nil
    term.setBackgroundColor(C.bg)
    term.setTextColor(C.text)
    term.clear()
    term.setCursorBlink(false)

    local count = S.query ~= "" and (#S.view .. " of " .. plural(#S.tracks)) or plural(#S.tracks)
    local ctx = "/" .. folderPath() .. "  " .. count
    if cfg.favOnly then ctx = ctx .. "  (favorites)" end
    header("Audio", ctx, #S.queue > 0 and ("Queue " .. #S.queue) or nil)

    -- Layout from the bottom up
    local rowHints, rowStatus, rowSeek, rowSub, rowTitle = H, H - 1, H - 2, H - 3, H - 4
    local vr = vizRows()
    -- A small screen gives rows back to the list before the visualizer goes.
    while vr > 0 and (rowTitle - vr - 1) - 2 < 2 do vr = vr - 1 end
    local vizTop = rowTitle - vr
    local listTop, listBottom = 2, vizTop - 1

    -- Search bar
    if S.searching or S.query ~= "" then
        local label = S.searching and " Find " or " Filter "
        put(1, listTop, string.rep(" ", W), C.barText, C.bar)
        put(1, listTop, label, C.barText, C.barBtn)
        put(#label + 2, listTop, fit(S.query, W - #label - 2), C.barText, C.bar)
        if S.searching then
            term.setCursorPos(math.min(W, #label + 2 + #S.query), listTop)
            term.setTextColor(C.barText)
            term.setCursorBlink(true)
        end
        listTop = listTop + 1
    end

    -- Track list
    local rows = math.max(0, listBottom - listTop + 1)
    listRect = { y1 = listTop, y2 = listBottom }
    if S.sel < S.top then S.top = S.sel end
    if S.sel > S.top + rows - 1 then S.top = S.sel - rows + 1 end
    S.top = clamp(S.top, 1, math.max(1, #S.view - rows + 1))
    local needBar = #S.view > rows and rows > 2
    local rowW = needBar and W - 1 or W

    if #S.view == 0 and rows >= 3 then
        -- Each line is a list of pieces. A piece starting with "*" is a key and
        -- shows in the line color, the rest in the hint color.
        local lines
        if S.query ~= "" then
            lines = { { "\14 ", "No track matches \"" .. S.query .. "\"." }, {}, { "Press ", "*Esc", " to clear the search." } }
        elseif cfg.favOnly then
            lines = {
                { "\14 ", "No favorites yet." }, {},
                { "Press ", "*B", " on a track to add one," },
                { "or ", "*W", " to show every track." },
            }
        else
            lines = {
                { "\14 ", "No .dfpwm files in /" .. folderPath() },
                {},
                { "Add some with ", "*Download > Import from PC" },
                { "or press ", "*F", " to choose another folder." },
            }
        end
        -- One blank row above and below the text when there is room for it.
        local padRows = (rows >= #lines + 4) and 1 or 0
        local bh = math.min(rows, #lines + 2 + padRows * 2)
        box(2, listTop, W - 2, bh)
        local innerW = W - 6
        for i, parts in ipairs(lines) do
            local y = listTop + padRows + i
            if y <= listTop + bh - 2 then
                put(4, y, string.rep(" ", innerW), C.text, C.panel)
                local len = 0
                for _, p in ipairs(parts) do len = len + #(p:gsub("^%*", "")) end
                local x = 4 + math.max(0, floor((innerW - len) / 2))
                for pi, p in ipairs(parts) do
                    local isKey = p:sub(1, 1) == "*"
                    local txt = isKey and p:sub(2) or p
                    local col = isKey and C.line or C.hint
                    if i == 1 then col = (pi == 1) and C.accent or C.text end
                    if x + #txt - 1 > 4 + innerW - 1 then txt = txt:sub(1, math.max(0, 4 + innerW - x)) end
                    put(x, y, txt, col, C.panel)
                    x = x + #txt
                end
            end
        end
    end
    for r = 0, rows - 1 do
        local n = S.top + r
        local ti = S.view[n]
        if ti then
            local tr = S.tracks[ti]
            local y = listTop + r
            local selected = n == S.sel
            local isCur = S.playing and tr.name == S.current
            local bg = selected and C.sel or C.bg
            local fg = selected and C.selText or (isCur and C.line or C.text)
            put(1, y, string.rep(" ", rowW), fg, bg)
            if selected then put(1, y, ">", C.selText, bg) end
            if cfg.favs[tr.name] then put(2, y, "*", selected and C.selText or C.accent, bg) end
            if isCur then put(3, y, S.paused and "\7" or "\16", selected and C.selText or C.line, bg) end
            local right = fmtTime(tr.size / BYTES_PER_SEC)
            local qi = queuePos(tr.name)
            if qi then right = "+" .. qi .. "  " .. right end
            put(5, y, pad(stripName(tr.name), rowW - 5 - #right - 1), fg, bg)
            put(rowW - #right, y, right, selected and C.selText or C.hint, bg)
        end
    end
    if needBar then
        local th = math.max(1, floor(rows * rows / #S.view + 0.5))
        local maxFirst = #S.view - rows
        local ty = floor((rows - th) * math.min(S.top - 1, maxFirst) / math.max(1, maxFirst) + 0.5)
        for i = 0, rows - 1 do
            local on = i >= ty and i < ty + th
            put(W, listTop + i, " ", C.bar, on and C.line or C.bar)
        end
    end

    -- Visualizer
    if vr > 0 then drawViz(vizTop, vr) end

    -- Now playing: cover, title, details
    local showCover = H >= 13
    local tx = showCover and 6 or 2
    if showCover then cover(2, rowTitle, S.playing and S.current or nil) end
    if S.current and S.playing then
        put(tx, rowTitle, pad(stripName(S.current), W - tx), S.paused and C.dim or C.text, C.bg)
    else
        put(tx, rowTitle, pad("Nothing playing", W - tx), C.dim, C.bg)
    end
    if S.msg and nowSec() < S.msgUntil then
        put(tx, rowSub, pad(S.msg, W - tx), C.accent, C.bg)
    else
        local sub
        local idx = trackIndex(S.current)
        if S.playing and idx then
            sub = (S.paused and "Paused   " or "") .. string.format("Track %d of %d", idx, #S.tracks)
            local nxt = peekNext()
            if nxt and W >= 40 then sub = sub .. "   Next: " .. stripName(nxt) end
        else
            sub = plural(#S.tracks) .. " in /" .. folderPath()
        end
        put(tx, rowSub, pad(sub, W - tx), C.dim, C.bg)
    end

    -- Seek bar:  0:12 ------|---- 3:45
    local cur = position()
    local total = S.playing and duration() or 0
    local left, rightT = fmtTime(cur), fmtTime(total)
    put(2, rowSeek, left, C.text, C.bg)
    put(W - #rightT, rowSeek, rightT, C.dim, C.bg)
    local bx1, bx2 = 2 + #left + 1, W - #rightT - 2
    if bx2 - bx1 >= 4 then
        local frac = total > 0 and clamp(cur / total, 0, 1) or 0
        pill(bx1, rowSeek, bx2 - bx1 + 1, frac)
        seekRect = { x1 = bx1, x2 = bx2, y = rowSeek }
    end

    -- Volume and settings
    local vw = W >= 45 and 10 or (W >= 32 and 8 or 5)
    put(2, rowStatus, "Vol", C.dim, C.bg)
    pill(6, rowStatus, vw, cfg.muted and 0 or cfg.volume)
    volRect = { x1 = 6, x2 = 5 + vw, y = rowStatus }
    local pct = cfg.muted and "mute" or (math.floor(cfg.volume * 100 + 0.5) .. "%")
    put(7 + vw, rowStatus, pad(pct, 4), C.text, C.bg)
    local x = 12 + vw
    local function flag(text, on, k)
        local width = #text + 2
        if x + width - 1 > W then return end
        put(x, rowStatus, " " .. text .. " ", on and C.barText or C.dim, on and C.barBtn or C.bg)
        addHit(x, x + width - 1, rowStatus, k)
        x = x + width + 1
    end
    flag("SHUF", cfg.shuffle, "s")
    flag("REP:" .. cfg.repeatMode, cfg.repeatMode ~= "Off", "r")
    if S.sleepAt then
        flag("SLEEP " .. math.max(1, math.ceil((S.sleepAt - nowSec()) / 60)) .. "m", true, "z")
    end
    flag("VIZ:" .. cfg.viz, cfg.viz ~= "Off", "v")
    flag("EQ:" .. cfg.tone, cfg.tone ~= "Flat", "e")
    flag("SORT:" .. cfg.sort, false, "y")
    flag("FAV", cfg.favOnly, "w")
    flag("SPK:" .. speakerLabel():sub(1, 10), #speakerNames() > 0, "o")

    hintLine(rowHints, {
        { "Spc", S.paused and "play" or (S.playing and "pause" or "play"), "space" },
        { "N", "next", "n" },
        { "P", "prev", "p" },
        { "/", "find", "/" },
        { "?", "help", "?" },
        { "Q", "quit", "q" },
        { "A", "queue", "a" },
        { "B", "fav", "b" },
        { "E", "eq", "e" },
    }, true)

    drawPopup()
    win.setVisible(true)
end

-- ── Full screen pages ────────────────────────────────────────────────────────
-- These keep the music playing. Each one sets S.rearm on the way out, because
-- it swallowed the tick timer events while it was open.

local nativeTerm

local function resize()
    local t = nativeTerm or term.native()
    W, H = t.getSize()
    win.reposition(1, 1, W, H)
    pbCache, pbCount = {}, 0
    if S.pop then closePop() end
end

local function clearPage()
    term.setBackgroundColor(C.bg)
    term.setTextColor(C.text)
    term.clear()
end

local function helpScreen()
    local rows = {
        { "Space", "Play / pause" },
        { "Enter", "Play the selected track" },
        { "N / P", "Next / previous track" },
        { "Left/Right", "Seek 10 seconds" },
        { "0-9", "Jump to 0-90% of the track" },
        { "+ / -", "Volume   M mute" },
        { "A", "Add to or remove from the queue" },
        { "C", "Clear the queue" },
        { "B", "Favorite the selected track" },
        { "W", "Show favorites only" },
        { "Y", "Sort: Name, Shortest, Longest" },
        { "E", "Equalizer: Flat, Bass, Treble, Voice" },
        { "Z", "Sleep timer: off, 15, 30, 45, 60 min" },
        { "S", "Shuffle" },
        { "R", "Repeat: Off, All, One" },
        { "/", "Search (Enter keeps, Esc clears)" },
        { "V", "Visualizer: Calm, Lively, Float, Off" },
        { "O", "Pick speakers in a pop-up" },
        { "F", "Pick the music folder   L rescan" },
        { "Mouse", "Click rows, bars and labels. Right click queues" },
        { "Q", "Quit" },
    }
    local off = 0
    local done = false
    while not done do
        local inner = math.max(1, H - 6)
        local maxOff = math.max(0, #rows - inner)
        off = clamp(off, 0, maxOff)
        win.setVisible(false)
        clearPage()
        header("Help", "Follows any OS theme, even custom")
        box(2, 3, W - 2, H - 4)
        local keyW = W < 40 and 6 or 12
        for i = 1, inner do
            local r = rows[off + i]
            if r then
                put(4, 3 + i, pad(r[1], keyW), C.line, C.panel)
                put(4 + keyW, 3 + i, pad(r[2], W - 6 - keyW), C.text, C.panel)
            end
        end
        hintLine(H, { { "Up/Down", "scroll" }, { "Esc", "back" } })
        win.setVisible(true)
        local ev, a = os.pullEventRaw()
        if ev == "terminate" then
            S.quit = true
            done = true
        elseif ev == "term_resize" then
            resize()
        elseif ev == "mouse_click" then
            done = true
        elseif ev == "mouse_scroll" then
            off = off + a
        elseif ev == "char" then
            local k = tostring(a):lower()
            if k == "q" or k == "?" or k == "h" then done = true end
        elseif ev == "key" then
            if a == keys.up then off = off - 1
            elseif a == keys.down then off = off + 1
            elseif a == keys.pageUp then off = off - inner
            elseif a == keys.pageDown then off = off + inner
            elseif a == keys.home then off = 0
            elseif a == keys["end"] then off = maxOff
            elseif a == keys.escape or a == keys.enter then done = true end
        end
    end
    S.rearm = true
end

-- Reads one line while the music keeps playing. Returns nil when cancelled.
local function promptLine(label, default)
    local text = default or ""
    local result
    local done = false
    while not done do
        win.setVisible(false)
        clearPage()
        header("Audio", label)
        box(2, 3, W - 2, 4)
        put(4, 4, pad(text:sub(-(W - 8)) .. "_", W - 6), C.text, C.panel)
        put(4, 5, pad("Enter saves, Esc cancels", W - 6), C.hint, C.panel)
        win.setVisible(true)
        local ev, a = os.pullEventRaw()
        if ev == "char" or ev == "paste" then
            text = text .. a
        elseif ev == "key" then
            if a == keys.enter then
                result = text
                done = true
            elseif a == keys.backspace then
                text = text:sub(1, -2)
            elseif a == keys.escape then
                done = true
            end
        elseif ev == "terminate" then
            S.quit = true
            done = true
        elseif ev == "term_resize" then
            resize()
        end
    end
    S.rearm = true
    return result
end

-- Folders that hold music, at most two levels down, for the folder page.
local function folderChoices()
    local out = {}
    local function count(dir)
        local t = {}
        scanDir(dir, "", 0, t)
        return #t
    end
    out[1] = { path = "", n = count("") }
    local ok, names = pcall(fs.list, "")
    if ok then
        table.sort(names)
        for _, name in ipairs(names) do
            if #out >= 40 then break end
            if name:sub(1, 1) ~= "." and name ~= "rom" and fs.isDir(name) then
                local n = count(name)
                if n > 0 or name == cfg.folder or name == "music" then
                    out[#out + 1] = { path = name, n = n }
                end
                local ok2, subs = pcall(fs.list, name)
                if ok2 then
                    table.sort(subs)
                    for _, sub in ipairs(subs) do
                        local p = fs.combine(name, sub)
                        if #out < 40 and sub:sub(1, 1) ~= "." and fs.isDir(p) then
                            local m = count(p)
                            if m > 0 or p == cfg.folder then out[#out + 1] = { path = p, n = m } end
                        end
                    end
                end
            end
        end
    end
    return out
end

local function pickFolder()
    local list = folderChoices()
    local sel, top = 1, 1
    for i, e in ipairs(list) do
        if e.path == cfg.folder then sel = i end
    end
    local done = false
    while not done do
        local rows = math.max(1, H - 4)
        if sel < top then top = sel end
        if sel > top + rows - 1 then top = sel - rows + 1 end
        win.setVisible(false)
        clearPage()
        header("Folder", "Where the music files are")
        for r = 0, rows - 1 do
            local e = list[top + r]
            if e then
                local label = e.path == "" and "/  (main folder)" or ("/" .. e.path)
                itemRow(3 + r, label, e.n .. (e.n == 1 and " track" or " tracks"), top + r == sel, e.path == cfg.folder)
            end
        end
        hintLine(H, { { "Enter", "choose" }, { "T", "type a path" }, { "Esc", "back" } })
        win.setVisible(true)
        local ev, a, b, c = os.pullEventRaw()
        if ev == "terminate" then
            S.quit = true
            done = true
        elseif ev == "term_resize" then
            resize()
        elseif ev == "key" then
            if a == keys.up then sel = sel > 1 and sel - 1 or #list
            elseif a == keys.down then sel = sel < #list and sel + 1 or 1
            elseif a == keys.pageUp then sel = math.max(1, sel - rows)
            elseif a == keys.pageDown then sel = math.min(#list, sel + rows)
            elseif a == keys.home then sel = 1
            elseif a == keys["end"] then sel = #list
            elseif a == keys.enter then
                applyFolder(list[sel].path)
                done = true
            elseif a == keys.escape then
                done = true
            end
        elseif ev == "char" then
            local k = tostring(a):lower()
            if k == "t" then
                local v = promptLine("Folder path (blank is the main folder)", cfg.folder)
                if v ~= nil then
                    v = v:gsub("^%s+", ""):gsub("%s+$", "")
                    applyFolder(v)
                    done = true
                end
            elseif k == "q" then
                done = true
            end
        elseif ev == "mouse_click" then
            local idx = top + (c - 3)
            if c >= 3 and c <= 2 + rows and list[idx] then
                applyFolder(list[idx].path)
                done = true
            end
        elseif ev == "mouse_scroll" then
            sel = clamp(sel + a, 1, #list)
        end
    end
    S.rearm = true
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
        cfg.repeatMode = cycle(REPEAT_LIST, cfg.repeatMode)
        saveCfg()
    elseif k == "v" then cycleViz()
    elseif k == "e" then cycleTone()
    elseif k == "y" then cycleSort()
    elseif k == "z" then cycleSleep()
    elseif k == "a" then toggleQueue()
    elseif k == "c" then clearQueue()
    elseif k == "b" then toggleFav()
    elseif k == "w" then toggleFavOnly()
    elseif k == "t" then say("Colors follow the OS theme. Settings > Themes adds your own.", 3)
    elseif k == "o" then openSpeakers()
    elseif k == "m" then
        cfg.muted = not cfg.muted
        saveCfg()
    elseif k == "+" or k == "=" then setVolume(cfg.volume + 0.05)
    elseif k == "-" or k == "_" then setVolume(cfg.volume - 0.05)
    elseif k == "/" then
        S.searching = true
    elseif k == "f" then pickFolder()
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
    local name = selName()
    if not name then return end
    if S.playing and S.current == name then togglePause() else startTrack(name) end
end

local function handleKey(a)
    if S.pop then popKey(a); return end
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

-- drag is true for mouse_drag. Dragging only moves the volume, so a drag across
-- the labels or the seek bar does not fire commands again and again.
local function handleClick(x, y, drag, button)
    if S.pop then
        if not drag then popClick(x, y) end
        return
    end
    if not drag then
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
    end
    if volRect and y == volRect.y and x >= volRect.x1 and x <= volRect.x2 then
        setVolume((x - volRect.x1 + 1) / (volRect.x2 - volRect.x1 + 1))
        return
    end
    if drag then return end
    if y >= listRect.y1 and y <= listRect.y2 then
        local n = S.top + (y - listRect.y1)
        if S.view[n] then
            if button == 2 then
                S.sel = n
                toggleQueue()
                return
            end
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
    if frame then S.lastFrame = frame
    elseif S.lastFrame and S.frames[1] and now - S.lastFrame.t < 0.25 then frame = S.lastFrame end
    local live = S.playing and not S.paused
    local calm = cfg.viz == "Calm"
    local float = cfg.viz == "Float"
    for b = 1, BANDS do
        local target = (live and frame) and frame.bands[b] or nil
        local d = S.disp[b]
        if target then
            -- a small boost, so quiet sounds still lift the bars
            target = math.min(1, target * 1.12)
            if calm then
                target = target ^ 1.15
                d = d + (target - d) * 0.55
            elseif float then
                -- quick rise, smooth fall: the bars glide instead of snapping
                d = target > d and d + (target - d) * 0.8 or math.max(target, d * 0.8)
            else
                d = target > d and target or math.max(target, d * 0.7)
            end
        else
            d = d * (live and (calm and 0.9 or 0.8) or 0.6)
        end
        if d < 0.015 then d = 0 end
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
    if S.pop then return true end
    if S.playing and not S.paused then return true end
    if S.msg and nowSec() < S.msgUntil + 0.2 then return true end
    for b = 1, BANDS do if S.disp[b] > 0 or S.peak[b] > 0 then return true end end
    return false
end

-- Ask once to keep playing when the app is not in front. The OS shows the
-- question, like any other permission. Without a yes the OS freezes the app
-- when another one is in front, so the music stops after a few seconds.
local function askBackground()
    local bg = osApi and osApi.background
    if type(bg) ~= "table" or type(bg.request) ~= "function" then return end
    local ok, allowed = pcall(bg.request)
    S.bgAllowed = ok and allowed == true
    if not S.bgAllowed then
        say("Not allowed to run in the background. Music stops when you leave.", 6)
    end
end

local function inputTask()
    local timer = os.startTimer(0.1)
    draw()
    askBackground()
    timer = os.startTimer(0.1)
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
                housekeeping()
                redraw = animating()
            else
                redraw = false
            end
        elseif ev == "key" then
            handleKey(a)
        elseif ev == "char" then
            if S.pop then
                popChar(a)
            elseif S.searching then
                S.query = S.query .. a
                applyFilter()
            else
                command(tostring(a):lower())
            end
        elseif ev == "paste" then
            if S.pop then
                -- nothing to paste into
            elseif S.searching then
                S.query = S.query .. a
                applyFilter()
            end
        elseif ev == "mouse_click" then
            handleClick(b, c, false, a)
        elseif ev == "mouse_drag" then
            handleClick(b, c, true, a)
        elseif ev == "mouse_scroll" then
            if S.pop then
                popMove(a)
            elseif volRect and c == volRect.y and b >= volRect.x1 and b <= volRect.x2 then
                setVolume(cfg.volume - a * 0.05)
            elseif #S.view > 0 then
                S.sel = clamp(S.sel + a, 1, #S.view)
            end
        elseif ev == "term_resize" then
            resize()
        elseif ev == "prismarine_theme" then
            loadTheme()
        elseif ev == "rednet_message" then
            if api and api.handleNet then pcall(api.handleNet, a, b, c) end
            redraw = false
        elseif ev == "peripheral" or ev == "peripheral_detach" then
            if S.pop then
                S.pop.names = speakerNames()
                S.pop.sel = clamp(S.pop.sel, 1, 1 + #S.pop.names)
            end
            if ev == "peripheral_detach" and S.playing and not S.paused and #speakerNames() == 0 then
                pauseNow()
                say("Speaker removed. Paused.", 4)
            end
        else
            redraw = false
        end
        if S.rearm then
            S.rearm = false
            timer = os.startTimer(0.1)
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
    if api.restorePalette then pcall(api.restorePalette) end
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local function main()
    if not term.isColour() then
        print("Prismarine Audio needs an advanced computer (colour).")
        return
    end
    math.randomseed(os.epoch("utc"))
    bootScreen()
    nativeTerm = term.current()
    W, H = nativeTerm.getSize()
    win = window.create(nativeTerm, 1, 1, W, H, true)
    term.redirect(win)
    loadTheme()
    restoreLast()
    local ok, err = pcall(function()
        parallel.waitForAny(audioTask, inputTask)
    end)
    savePos()
    saveCfg()
    stopSpeakers()
    term.redirect(nativeTerm)
    nativeTerm.setBackgroundColor(colors.black)
    nativeTerm.setTextColor(colors.white)
    nativeTerm.setCursorBlink(false)
    nativeTerm.clear()
    nativeTerm.setCursorPos(1, 1)
    if not ok and not tostring(err):find("Terminated") then
        print("Prismarine Audio stopped: " .. tostring(err))
        print("Press any key.")
        os.pullEvent("key")
    end
end

main()
