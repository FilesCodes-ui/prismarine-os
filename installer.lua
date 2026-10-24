-- Prismarine OS installer v4 for CC:Tweaked 1.20.1
--
-- Installs four editions:
--   Release   the 1.x line (Release 1.0, 1.1, ...). Files come from the repo's
--             release/ folder, each one checked against release/manifest.txt.
--   Full      the older kernel version, installed from a stage folder (stage5, ...).
--   Classic   the single file versions 17 and up. Version 18 is broken, so it is
--             never offered.
--   Simple    Classic Simple OS, the original versions before the loading
--             screen (6 and below).
-- Every install can be upgraded, downgraded and undone. A classic version is a
-- GitHub release tagged pv<number>, a startup_v<number>.lua file in the repo
-- root, or the same file in a classic/ folder (the folder copy wins).
-- A Release version is the one in release/ on the main branch (the newest), or
-- a GitHub release tagged r<major>.<minor> such as r1.0, which holds the
-- release/ folder as it was for that version.
--
--   pastebin run <code>                  menu
--   pastebin run <code> release          menu of releases (1.x)
--   pastebin run <code> release 1.1      install Release 1.1
--   pastebin run <code> 1.1              same as release 1.1 (a number with a dot picks Release)
--   pastebin run <code> full             install the newest full stage
--   pastebin run <code> full 5           install stage 5
--   pastebin run <code> classic          menu of classic versions
--   pastebin run <code> classic 21       install classic version 21
--   pastebin run <code> simple 6         install Simple OS version 6
--   pastebin run <code> 21               same as classic 21 (a whole number picks the edition)
--   pastebin run <code> undo             restore what the last install replaced
--   add owner/repo to any command to take it from another GitHub repo

local INSTALLER_VERSION = "4"
local REPO   = "FilesCodes-ui/prismarine-os"   -- owner/name, or owner/name@branch
local STATE  = "/.prismarine_installed.json"
local STAGE  = "/.prismarine_stage"
local BACKUP = "/.prismarine_backup"
local SETUP  = "/.prismarine_setup.lua"

-- Editions
local CLASSIC_MIN = 17
local SIMPLE_MAX  = 6
local STAGE_MAX   = 12
local BROKEN = { [18] = true }   -- never offered, never installed
local function inClassic(n) return n >= CLASSIC_MIN and not BROKEN[n] end
local function inSimple(n) return n <= SIMPLE_MAX and not BROKEN[n] end

-- Release (1.x). The same pinned Pixelbox the release's own setup.lua uses.
-- It is optional: without it the UI falls back to plain text mode.
local RELEASE_MAJOR = 1
local RELEASE_PROBE = 30     -- minors checked one by one when GitHub's API is blocked
local RELEASE_NEED  = 700 * 1024
local RELEASE_KEEP  = { "prismarine/data/", "appdata/" }
local INSTALL_JSON  = "prismarine/data/install.json"
local PB_URL  = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/82098c8dca939b7689f119d0a577c311d4a09281/pixelbox_lite.lua"
local PB_PATH = "prismarine/lib/pixelbox_lite.lua"
local PB_HASH = "e9923dc24ed6d968de668f42a3c324d0957778a709d93bc9190617c32889de99"

local args = { ... }

-- ── Version compare ─────────────────────────────────────────────────────────
-- Classic and Simple versions are whole numbers. Release versions are "1.10"
-- style text, compared part by part (1.10 is newer than 1.9).
local function relParts(v)
    local a, b = tostring(v):match("^(%d+)%.(%d+)$")
    if a then return tonumber(a), tonumber(b) end
end

local function isOlder(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    local a1, a2 = relParts(a)
    local b1, b2 = relParts(b)
    if a1 and b1 then return a1 < b1 or (a1 == b1 and a2 < b2) end
    return false
end

-- ── SHA-256 (the same code the OS uses to check its own file) ───────────────
local SHA_K = { 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 }
local SHA_H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

local function hex32(n)
    local out = ""
    for _ = 1, 8 do
        local d = n % 16
        out = string.sub("0123456789abcdef", d + 1, d + 1) .. out
        n = (n - d) / 16
    end
    return out
end

-- SHA-256. Yields now and then so long files do not hit the timeout.
local function sha256(msg, tick)
    local band, bxor, bnot, bor = bit32.band, bit32.bxor, bit32.bnot, bit32.bor
    local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate
    local M = 4294967296

    local len = #msg
    local bits = len * 8
    local function u32(n)
        return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255),
                           band(rshift(n, 8), 255), band(n, 255))
    end
    msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
        .. u32(math.floor(bits / M)) .. u32(bits % M)

    local h = {}
    for n = 1, 8 do h[n] = SHA_H0[n] end
    local w = {}
    local blocks = 0

    for i = 1, #msg, 64 do
        local bytes = { string.byte(msg, i, i + 63) }
        for j = 1, 16 do
            local o = (j - 1) * 4
            w[j] = bor(lshift(bytes[o + 1], 24), lshift(bytes[o + 2], 16),
                       lshift(bytes[o + 3], 8), bytes[o + 4])
        end
        for j = 17, 64 do
            local v15, v2 = w[j - 15], w[j - 2]
            local s0 = bxor(rrotate(v15, 7), rrotate(v15, 18), rshift(v15, 3))
            local s1 = bxor(rrotate(v2, 17), rrotate(v2, 19), rshift(v2, 10))
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % M
        end

        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for j = 1, 64 do
            local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = (hh + S1 + ch + SHA_K[j] + w[j]) % M
            local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = (S0 + maj) % M
            hh = g
            g = f
            f = e
            e = (d + t1) % M
            d = c
            c = b
            b = a
            a = (t1 + t2) % M
        end
        h[1] = (h[1] + a) % M
        h[2] = (h[2] + b) % M
        h[3] = (h[3] + c) % M
        h[4] = (h[4] + d) % M
        h[5] = (h[5] + e) % M
        h[6] = (h[6] + f) % M
        h[7] = (h[7] + g) % M
        h[8] = (h[8] + hh) % M

        blocks = blocks + 1
        if blocks % 8 == 0 then
            os.queueEvent("simpleos_yield")
            os.pullEventRaw("simpleos_yield")
            if tick then tick() end
        end
    end

    local out = {}
    for n = 1, 8 do out[n] = hex32(h[n]) end
    return table.concat(out)
end


-- ── Screen helpers ──────────────────────────────────────────────────────────
local color = term.isColor and term.isColor()

local function setColor(fg, bg)
    if not color then return end
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
end

local function say(text, fg)
    setColor(fg or colors.white, colors.black)
    print(text)
end

local function banner()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    local w = term.getSize()
    setColor(colors.white, colors.blue)
    local title = " Prismarine OS installer  v" .. INSTALLER_VERSION
    term.write(title .. string.rep(" ", math.max(0, w - #title)))
    setColor(colors.white, colors.black)
    print()
    print()
end

local function fail(text, detail)
    say(text, colors.red)
    if detail then say(tostring(detail), colors.lightGray) end
    print()
    error("", 0)
end

-- Y or N. Returns true for Y.
local function yesNo(question)
    setColor(colors.yellow, colors.black)
    write(question .. " Y/N ")
    setColor(colors.white, colors.black)
    while true do
        local _, key = os.pullEvent("key")
        if key == keys.y then print("Y") return true end
        if key == keys.n or key == keys.q then print("N") return false end
    end
end

-- Arrow key menu. Returns the chosen index, or nil when cancelled.
local function menu(title, options)
    local _, h = term.getSize()
    local sel, top = 1, 1
    local visible = h - 6
    while true do
        banner()
        say(title, colors.lightBlue)
        print()
        local startY = 5
        if sel < top then top = sel end
        if sel > top + visible - 1 then top = sel - visible + 1 end
        for i = 0, visible - 1 do
            local idx = top + i
            local label = options[idx]
            if not label then break end
            term.setCursorPos(2, startY + i)
            if idx == sel then
                setColor(colors.black, colors.lightBlue)
                term.write(" " .. label .. " ")
            else
                setColor(colors.white, colors.black)
                term.write(" " .. label .. " ")
            end
        end
        term.setCursorPos(1, h)
        setColor(colors.lightGray, colors.black)
        term.write("Up/Down choose, Enter select, Q cancel")
        setColor(colors.white, colors.black)

        local ev, a, b, c = os.pullEvent()
        if ev == "key" then
            if a == keys.up and sel > 1 then sel = sel - 1
            elseif a == keys.down and sel < #options then sel = sel + 1
            elseif a == keys.enter then return sel
            elseif a == keys.q or a == keys.backspace then return nil
            end
        elseif ev == "mouse_scroll" then
            sel = math.max(1, math.min(#options, sel + a))
        elseif ev == "mouse_click" then
            local idx = top + (c - startY)
            if c >= startY and options[idx] then return idx end
        end
    end
end


-- ── Download helpers ────────────────────────────────────────────────────────
local function repoParts()
    local repo, branch = REPO:match("^([^@]+)@?(.*)$")
    if not branch or branch == "" then branch = "main" end
    return repo, branch
end

-- ref is a tag such as pv23. Without it the repo's branch is used.
local function rawUrl(path, ref)
    local repo, branch = repoParts()
    return "https://raw.githubusercontent.com/" .. repo .. "/" .. (ref or branch) .. "/" .. path
end

local function fresh(url)
    return url .. "?cb=" .. os.epoch("utc")
end

-- Returns the body, or nil and a reason.
local function httpGet(url)
    local resp, err, failed = http.get(url, nil, true)
    if not resp then
        local code
        if failed then
            if failed.getResponseCode then code = failed.getResponseCode() end
            pcall(failed.close)
        end
        return nil, code and ("Status " .. code) or tostring(err)
    end
    local status = resp.getResponseCode()
    local body = resp.readAll()
    resp.close()
    if status ~= 200 or not body or body == "" then
        return nil, "Status " .. tostring(status)
    end
    return body
end

-- True when a file exists at the url (asks for the headers only).
local function urlExists(url)
    local ok, resp = pcall(http.get, { url = url, method = "HEAD", binary = true })
    if ok and resp then
        local code = resp.getResponseCode()
        resp.close()
        return code == 200
    end
    return false
end

local function readLine(prompt)
    setColor(colors.lightBlue, colors.black)
    write(prompt)
    setColor(colors.white, colors.black)
    return read()
end

local function readFile(path)
    local f = fs.open(path, "rb")
    if not f then return nil end
    local s = f.readAll()
    f.close()
    return s
end

-- Returns false when the file cannot be written (a full computer included).
local function writeFile(path, data)
    local ok, res = pcall(function()
        fs.makeDir(fs.getDir(path))
        local f = fs.open(path, "wb")
        if not f then return false end
        f.write(data)
        f.close()
        return true
    end)
    return ok and res and true or false
end

-- A path from a manifest is never trusted. No absolute paths, no "..",
-- nothing inside the installer's own folders or the ROM.
local function safePath(p)
    if type(p) ~= "string" or p == "" or #p > 200 then return false end
    if p:sub(1, 1) == "/" or p:find("\\", 1, true) or p:find("%c") then return false end
    if p:find("//", 1, true) or p:sub(-1) == "/" then return false end
    for part in p:gmatch("[^/]+") do
        if part == ".." or part == "." then return false end
    end
    if p:sub(1, 12) == ".prismarine_" or p:sub(1, 4) == "rom/" or p == "rom" then return false end
    return true
end

local function isKept(path, keep)
    for _, k in ipairs(keep or {}) do
        if path == k or (k:sub(-1) == "/" and path:sub(1, #k) == k) then return true end
    end
    return false
end

-- ── Version list ────────────────────────────────────────────────────────────
-- Releases tagged pv<number>, plus single file versions in the repo root that
-- have no release. Newest first.
local function releasesFromApi()
    local repo = repoParts()
    local body = httpGet("https://api.github.com/repos/" .. repo .. "/releases?per_page=100")
    local data = body and textutils.unserialiseJSON(body)
    if type(data) ~= "table" then return nil end
    local out = {}
    for _, r in ipairs(data) do
        local tag = type(r) == "table" and not r.draft and type(r.tag_name) == "string" and r.tag_name
        local n = tag and tag:match("^pv(%d+)$")
        if n then out[#out + 1] = { version = tonumber(n), kind = "tag", ref = tag } end
    end
    return out
end

-- Lists a repo folder through GitHub's API. Returns nil when the API is blocked
-- (second value "blocked") or the folder is not there (second value "Not Found").
local function contents(folder)
    local repo, branch = repoParts()
    local path = (folder ~= "" and (folder .. "/") or "")
    local body = httpGet("https://api.github.com/repos/" .. repo .. "/contents/" .. path .. "?ref=" .. branch)
    local data = body and textutils.unserialiseJSON(body)
    if type(data) ~= "table" then return nil, "blocked" end
    if data.message then return nil, tostring(data.message) end
    return data
end

-- Single file versions in a folder ("" is the repo root).
local function legacyFromApi(folder)
    local data = contents(folder)
    if not data then return nil end
    local prefix = (folder ~= "" and (folder .. "/") or "")
    local out = {}
    for _, f in ipairs(data) do
        local n = type(f) == "table" and type(f.name) == "string" and f.name:match("^startup_v(%d+)%.lua$")
        if n then out[#out + 1] = { version = tonumber(n), kind = "legacy", file = prefix .. f.name } end
    end
    return out
end

-- Used when GitHub's API is blocked or rate limited.
local function probeVersions()
    local out = {}
    for n = 1, 40 do
        local x, y = term.getCursorPos()
        term.setCursorPos(1, y)
        term.clearLine()
        write("Checking version " .. n .. " of 40")
        local tag = "pv" .. n
        local file = "startup_v" .. n .. ".lua"
        if urlExists(rawUrl("manifest.json", tag)) or urlExists(rawUrl(file, tag)) then
            out[#out + 1] = { version = n, kind = "tag", ref = tag }
        elseif urlExists(rawUrl("classic/" .. file)) then
            out[#out + 1] = { version = n, kind = "legacy", file = "classic/" .. file }
        elseif urlExists(rawUrl(file)) then
            out[#out + 1] = { version = n, kind = "legacy", file = file }
        end
    end
    print()
    return out
end

-- Every single file version GitHub shows, newest first. Edition filters come later.
local function listVersions()
    local byVer, list = {}, {}
    local rel, root, dir = releasesFromApi(), legacyFromApi(""), legacyFromApi("classic")
    if not rel and not root then
        say("GitHub file list unavailable, checking each version...", colors.lightGray)
        rel = probeVersions()
    end
    for _, v in ipairs(rel or {}) do byVer[v.version] = v end
    for _, v in ipairs(root or {}) do
        if not byVer[v.version] then byVer[v.version] = v end
    end
    for _, v in ipairs(dir or {}) do
        if not byVer[v.version] or byVer[v.version].kind == "legacy" then byVer[v.version] = v end
    end
    for _, v in pairs(byVer) do list[#list + 1] = v end
    table.sort(list, function(a, b) return a.version > b.version end)
    return list
end

-- Release (1.x) versions, newest first. The newest is whatever release/ holds
-- on the branch. Older ones are GitHub releases tagged r1.0, r1.1 ... whose
-- release/ folder is that version.
local function releaseTagsFromApi()
    local repo = repoParts()
    local body = httpGet("https://api.github.com/repos/" .. repo .. "/releases?per_page=100")
    local data = body and textutils.unserialiseJSON(body)
    if type(data) ~= "table" or data.message then return nil end
    local out = {}
    for _, r in ipairs(data) do
        local tag = type(r) == "table" and not r.draft and type(r.tag_name) == "string" and r.tag_name
        local v = tag and tag:match("^r(%d+%.%d+)$")
        if v then out[#out + 1] = { version = v, kind = "release", ref = tag, folder = "release" } end
    end
    return out
end

local function listReleases()
    local out, seen = {}, {}
    local function add(e)
        if not seen[e.version] then
            seen[e.version] = true
            out[#out + 1] = e
        end
    end
    local body = httpGet(fresh(rawUrl("release/manifest.txt")))
    local t = body and textutils.unserialise(body)
    local cur = type(t) == "table" and type(t.version) == "string" and t.version:match("^Release (%d+%.%d+)$")
    if cur then add({ version = cur, kind = "release", folder = "release" }) end

    local tagged = releaseTagsFromApi()
    if not tagged then
        say("GitHub release list unavailable, checking each version...", colors.lightGray)
        tagged = {}
        for minor = 0, RELEASE_PROBE do
            local x, y = term.getCursorPos()
            term.setCursorPos(1, y)
            term.clearLine()
            write("Checking release " .. RELEASE_MAJOR .. "." .. minor .. " of " .. RELEASE_MAJOR .. "." .. RELEASE_PROBE)
            local tag = "r" .. RELEASE_MAJOR .. "." .. minor
            if urlExists(rawUrl("release/manifest.txt", tag)) then
                tagged[#tagged + 1] = { version = RELEASE_MAJOR .. "." .. minor, kind = "release", ref = tag, folder = "release" }
            end
        end
        print()
    end
    for _, e in ipairs(tagged) do add(e) end
    table.sort(out, function(a, b) return isOlder(b.version, a.version) end)
    return out
end

-- Full version stages, newest first. A stage folder holds a setup.lua.
-- New stages live in full/stageN. Older ones sit in the repo root as stageN.
local function listStages()
    local out, seen = {}, {}
    local function add(n, path)
        if not seen[n] then
            seen[n] = true
            out[#out + 1] = { n = n, path = path }
        end
    end
    local function scan(folder)
        local data = contents(folder)
        if not data then return false end
        local prefix = (folder ~= "" and (folder .. "/") or "")
        for _, f in ipairs(data) do
            local n = type(f) == "table" and f.type == "dir" and type(f.name) == "string" and f.name:match("^stage(%d+)$")
            if n and urlExists(rawUrl(prefix .. f.name .. "/setup.lua")) then add(tonumber(n), prefix .. f.name) end
        end
        return true
    end
    local a, b = scan("full"), scan("")
    if not a and not b then
        say("GitHub file list unavailable, checking each stage...", colors.lightGray)
        for n = STAGE_MAX, 1, -1 do
            for _, path in ipairs({ "full/stage" .. n, "stage" .. n }) do
                if urlExists(rawUrl(path .. "/setup.lua")) then add(n, path) end
            end
        end
    end
    table.sort(out, function(x, y) return x.n > y.n end)
    return out
end

-- ── Manifest ────────────────────────────────────────────────────────────────
local function singleFile(entry, want)
    return {
        version = entry.version, dataFormat = 1, bootstrap = "startup.lua", keep = {},
        ref = entry.ref, legacy = true,
        files = { { path = "startup.lua", src = entry.file, sha256 = want } },
    }
end

-- Where the OS's own updater looks for new releases afterward.
local function installBase()
    local repo, branch = repoParts()
    return "https://raw.githubusercontent.com/" .. repo .. "/" .. branch .. "/release/"
end

-- A Release version: release/manifest.txt lists every file with its SHA-256.
-- Returns a manifest in the installer's own shape, or nil and a reason.
local function loadRelease(entry, want)
    local body, err = httpGet(fresh(rawUrl(entry.folder .. "/manifest.txt", entry.ref)))
    if not body then return nil, "Could not download manifest.txt.\n" .. tostring(err) end
    local got = sha256(body)
    if want and got ~= want then
        return nil, "Manifest does not match your hash.\nGot " .. got
    end
    local t = textutils.unserialise(body)
    if type(t) ~= "table" or type(t.files) ~= "table" or t.version ~= "Release " .. entry.version then
        return nil, "Manifest is malformed or is not Release " .. entry.version .. "."
    end
    local names = {}
    for p, h in pairs(t.files) do
        if not safePath(p) or type(h) ~= "string" or #h ~= 64 or not h:match("^%x+$") then
            return nil, "Manifest has a bad entry: " .. tostring(p)
        end
        names[#names + 1] = p
    end
    if not t.files["startup.lua"] then return nil, "Manifest has no startup.lua." end
    table.sort(names)
    local files = {}
    for _, p in ipairs(names) do
        files[#files + 1] = { path = p, src = entry.folder .. "/" .. p, sha256 = t.files[p]:lower() }
    end
    if not t.files[PB_PATH] then
        files[#files + 1] = { path = PB_PATH, url = PB_URL, sha256 = PB_HASH, optional = true }
    end
    -- Written here, not downloaded. It tells the OS where updates come from.
    files[#files + 1] = {
        path = INSTALL_JSON,
        content = textutils.serialiseJSON({ base = installBase(), version = t.version }),
    }
    return {
        version = entry.version, dataFormat = 1, bootstrap = "startup.lua", keep = RELEASE_KEEP,
        ref = entry.ref, release = true, manifestSha256 = got, files = files,
    }
end

-- Turns a version into a manifest table, or returns nil and a reason.
-- want is the SHA-256 the user typed, or nil.
local function loadManifest(entry, want)
    if entry.kind == "release" then return loadRelease(entry, want) end
    if entry.kind == "legacy" then return singleFile(entry, want) end
    local body = httpGet(fresh(rawUrl("manifest.json", entry.ref)))
    if not body then
        -- A release with no manifest holds one file: startup_v<number>.lua.
        entry.file = "startup_v" .. entry.version .. ".lua"
        return singleFile(entry, want)
    end
    local got = sha256(body)
    if want and got ~= want then
        return nil, "Manifest does not match your hash.\nGot " .. got
    end
    local m = textutils.unserialiseJSON(body)
    if type(m) ~= "table" or m.format ~= 1 or m.version ~= entry.version
       or type(m.files) ~= "table" or #m.files == 0 or not safePath(m.bootstrap) then
        return nil, "Manifest is malformed or does not belong to " .. entry.ref .. "."
    end
    local seen, hasBoot = {}, false
    for _, f in ipairs(m.files) do
        if type(f) ~= "table" or not safePath(f.path) or not safePath(f.src)
           or type(f.sha256) ~= "string" or #f.sha256 ~= 64 or seen[f.path] then
            return nil, "Manifest has a bad entry: " .. tostring(f and f.path)
        end
        seen[f.path] = true
        if f.path == m.bootstrap then hasBoot = true end
    end
    if not hasBoot then return nil, "Manifest has no bootstrap file." end
    m.keep = type(m.keep) == "table" and m.keep or {}
    m.dataFormat = m.dataFormat or 1
    m.manifestSha256 = got
    m.ref = entry.ref
    return m
end

-- ── Installed state ─────────────────────────────────────────────────────────
-- v21 and older installs have no state file. Their version is in startup.lua.
-- A Release put on by its own setup.lua has no state file either, but it
-- leaves prismarine/data/install.json.
local function installedState()
    local raw = readFile(STATE)
    local st = raw and textutils.unserialiseJSON(raw)
    if type(st) == "table" and type(st.files) == "table" then return st end
    local ij = readFile(INSTALL_JSON)
    local info = ij and textutils.unserialiseJSON(ij)
    local rv = type(info) == "table" and type(info.version) == "string" and info.version:match("^Release (%d+%.%d+)$")
    if rv then return { version = rv, edition = "release", dataFormat = 1, files = {}, guessed = true } end
    local boot = readFile("startup.lua")
    local v = boot and boot:match('local VERSION = "(%d+)"')
    if v then return { version = tonumber(v), dataFormat = 1, files = { "startup.lua" }, guessed = true } end
    return nil
end

local function copyPath(from, to)
    if fs.exists(to) then fs.delete(to) end
    fs.makeDir(fs.getDir(to))
    fs.copy(from, to)
end

local function pruneEmptyDirs(path)
    local dir = fs.getDir(path)
    while dir ~= "" and fs.isDir(dir) and #fs.list(dir) == 0 do
        fs.delete(dir)
        dir = fs.getDir(dir)
    end
end

-- ── Install ─────────────────────────────────────────────────────────────────
local function install(entry)
    banner()
    local cur = installedState()
    local n = entry.version
    local isRelease = entry.kind == "release"
    say("Target: version " .. n .. (isRelease and "  (Release)" or ""), colors.lightBlue)
    say("Installed: " .. (cur and ("version " .. cur.version) or "none found"), colors.lightGray)
    print()

    local want = readLine("SHA-256 of the manifest or file, Enter to skip: ")
    want = want:lower():gsub("%s", "")
    if want == "" then
        want = nil
    elseif not want:match("^%x+$") or #want ~= 64 then
        fail("That is not a SHA-256 hash.", "Nothing was changed.")
    end

    local m, why = loadManifest(entry, want)
    if not m then fail("Cannot use this version.", why) end

    -- Versions only compare inside one edition: Release 1.1 against Release 1.0.
    local curEdition = cur and (cur.edition or "legacy")
    local downgrade = cur and curEdition == (m.release and "release" or "legacy") and isOlder(n, cur.version)
    local dataDown = cur and (m.dataFormat or 1) < (cur.dataFormat or 1)
    print()
    say(m.legacy and "Single file version." or ("Multi file version, " .. #m.files .. " files."), colors.lightGray)
    if downgrade then
        say("WARNING: version " .. n .. " is OLDER than version " .. cur.version .. ".", colors.red)
        say("An old version has security holes that are fixed now.", colors.yellow)
    end
    if dataDown then
        say("Saved data uses a newer format than this version reads.", colors.yellow)
        say("Your data is copied to the backup first.", colors.yellow)
    end
    say(want and "Hash given. Every file is checked." or "Hash NOT given.", want and colors.lime or colors.yellow)
    print()
    if downgrade then
        local typed = readLine("Type " .. n .. " to confirm the downgrade: ")
        if typed ~= tostring(n) then
            say("Cancelled. Nothing was changed.", colors.yellow)
            return false
        end
    elseif not yesNo((cur and cur.version == n and "Reinstall" or "Install") .. " version " .. n .. "?") then
        say("Cancelled. Nothing was changed.", colors.yellow)
        return false
    end

    -- A fresh Release needs about 700 KB. Stop early with a clear message.
    if m.release and not fs.exists("prismarine") then
        local okFree, free = pcall(fs.getFreeSpace, "/")
        if okFree and type(free) == "number" and free < RELEASE_NEED then
            say(("Not enough room: %d KB free, about %d KB needed."):format(math.floor(free / 1024), math.floor(RELEASE_NEED / 1024)), colors.red)
            say("Raise the computer space limit to 20 MB:")
            say("  1. Close the world.")
            say("  2. Open the world folder, then serverconfig.")
            say("  3. Edit computercraft-server.toml.")
            say("  4. Set computer_space_limit = 20000000.")
            say("  5. Open the world and run this installer again.")
            return false
        end
    end

    -- 1. Download and check everything into a staging folder. A file that is
    --    already on the computer unchanged is not staged again, which keeps an
    --    upgrade small. A file the manifest marks optional is skipped when it
    --    cannot be fetched or checked.
    fs.delete(STAGE)
    local total = #m.files
    local unchanged, usable = {}, {}
    for i, f in ipairs(m.files) do
        local x, y = term.getCursorPos()
        term.setCursorPos(1, y)
        term.clearLine()
        write("Downloading " .. i .. "/" .. total .. " " .. f.path:sub(-30))
        local body, err = f.content, nil
        if not body then body, err = httpGet(fresh(f.url or rawUrl(f.src, m.ref))) end
        local problem
        if not body then
            problem = "Download failed: " .. f.path
        else
            local got = sha256(body)
            if f.sha256 and got ~= f.sha256 then
                problem, err = "Hash mismatch: " .. f.path, "Got " .. got .. "\nNothing was changed."
            else
                f.sha256 = f.sha256 or got
            end
        end
        if not problem and f.path:match("%.lua$") then
            local fn, serr = load(body, "=" .. f.path)
            if not fn then problem, err = "Syntax error in " .. f.path, serr end
        end
        if problem and f.optional then
            print()
            say("Skipped " .. f.path .. ". " .. problem, colors.yellow)
            if fs.exists(f.path) then
                -- the copy already here was checked when it went in; keep it
                usable[#usable + 1] = f
                unchanged[f.path] = true
            end
        elseif problem then
            fs.delete(STAGE)
            print()
            fail(problem, err)
        else
            usable[#usable + 1] = f
            if readFile(f.path) == body then
                unchanged[f.path] = true
            elseif not writeFile(STAGE .. "/" .. f.path, body) then
                fs.delete(STAGE)
                print()
                fail("Cannot write staging file. The computer may be out of space.", f.path)
            end
        end
    end
    m.files = usable
    print()
    say("All " .. #m.files .. " files verified.", colors.lime)

    -- 2. Work out what changes, then save the old copies.
    local newSet, writes, removes = {}, {}, {}
    for _, f in ipairs(m.files) do
        newSet[f.path] = true
        if not unchanged[f.path] then writes[#writes + 1] = f.path end
    end
    -- Leaving the Release line for another edition leaves its files in place,
    -- as installing over a full version always did.
    local leaving = cur and cur.edition == "release" and not m.release
    if not leaving then
        for _, p in ipairs(cur and cur.files or {}) do
            if safePath(p) and not newSet[p] and not isKept(p, m.keep) and not isKept(p, cur.keep) then
                removes[#removes + 1] = p
            end
        end
    end
    for _, p in ipairs(writes) do
        if fs.isReadOnly(p) then fs.delete(STAGE) fail("Cannot write " .. p) end
    end

    fs.delete(BACKUP)
    local journal = { from = cur and cur.version or false, to = n, backedUp = {}, created = {},
                      hadState = fs.exists(STATE), data = {} }
    local function save(p)
        if fs.exists(p) then
            copyPath(p, BACKUP .. "/files/" .. p)
            journal.backedUp[#journal.backedUp + 1] = p
        else
            journal.created[#journal.created + 1] = p
        end
    end
    for _, p in ipairs(writes) do save(p) end
    for _, p in ipairs(removes) do save(p) end
    if journal.hadState then copyPath(STATE, BACKUP .. "/state.json") end
    if dataDown then
        for _, k in ipairs((cur and cur.keep) or m.keep) do
            local p = k:gsub("/$", "")
            if safePath(p) and fs.exists(p) then
                copyPath(p, BACKUP .. "/data/" .. p)
                journal.data[#journal.data + 1] = p
            end
        end
    end
    writeFile(BACKUP .. "/journal.json", textutils.serialiseJSON(journal))
    say("Old files saved. Run the installer with 'undo' to restore them.", colors.lightGray)

    -- A startup.lua that is not Prismarine's is kept as startup.lua.bak.
    if m.release and fs.exists("startup.lua") then
        local old = readFile("startup.lua")
        if old and not old:find("-- prismarine-boot-v1", 1, true) then
            copyPath("startup.lua", "startup.lua.bak")
            say("Old startup saved as startup.lua.bak", colors.lightGray)
        end
    end

    -- 3. Move into place. The bootstrap goes last, so a crash halfway
    --    leaves the old startup.lua running.
    for _, p in ipairs(writes) do
        if p ~= m.bootstrap then
            if fs.exists(p) then fs.delete(p) end
            fs.makeDir(fs.getDir(p))
            fs.move(STAGE .. "/" .. p, p)
        end
    end
    if not unchanged[m.bootstrap] then
        if fs.exists(m.bootstrap) then fs.delete(m.bootstrap) end
        fs.makeDir(fs.getDir(m.bootstrap))
        fs.move(STAGE .. "/" .. m.bootstrap, m.bootstrap)
    end

    -- 4. Remove files the target version does not own.
    for _, p in ipairs(removes) do
        if fs.exists(p) then fs.delete(p) end
        pruneEmptyDirs(p)
    end
    fs.delete(STAGE)

    -- 5. Record what is installed.
    local names = {}
    for _, f in ipairs(m.files) do names[#names + 1] = f.path end
    writeFile(STATE, textutils.serialiseJSON({
        version = n, edition = m.release and "release" or "legacy",
        dataFormat = m.dataFormat, files = names, keep = m.keep,
        manifestSha256 = m.manifestSha256,
    }))

    print()
    if m.release then
        say("Installed Prismarine Release " .. n .. ".", colors.lime)
    else
        say("Installed Prismarine OS version " .. n .. ".", colors.lime)
    end
    local changed = #writes
    if m.release and cur then say(changed .. " of " .. #m.files .. " files changed.", colors.lightGray) end
    if #removes > 0 then say(#removes .. " old files removed.", colors.lightGray) end
    if m.manifestSha256 then say("Manifest SHA-256 " .. m.manifestSha256, colors.lightGray) end
    if m.release and not cur then say("Reboot to start Prismarine. You will choose a password.", colors.lightGray) end
    say("If secure boot was enrolled, re-enroll it.", colors.lightGray)
    return true
end

-- ── Undo ────────────────────────────────────────────────────────────────────
local function undo()
    banner()
    local raw = readFile(BACKUP .. "/journal.json")
    local j = raw and textutils.unserialiseJSON(raw)
    if type(j) ~= "table" then
        say("There is nothing to undo.", colors.yellow)
        return false
    end
    say("Last install: version " .. tostring(j.from) .. " to version " .. tostring(j.to), colors.lightBlue)
    if not yesNo("Restore the old files?") then
        say("Cancelled. Nothing was changed.", colors.yellow)
        return false
    end
    for _, p in ipairs(j.backedUp or {}) do
        if safePath(p) and fs.exists(BACKUP .. "/files/" .. p) then
            copyPath(BACKUP .. "/files/" .. p, p)
        end
    end
    for _, p in ipairs(j.created or {}) do
        if safePath(p) and p ~= "startup.lua" and fs.exists(p) then
            fs.delete(p)
            pruneEmptyDirs(p)
        end
    end
    for _, p in ipairs(j.data or {}) do
        if safePath(p) and fs.exists(BACKUP .. "/data/" .. p) then
            copyPath(BACKUP .. "/data/" .. p, p)
        end
    end
    if j.hadState then
        copyPath(BACKUP .. "/state.json", STATE)
    else
        fs.delete(STATE)
    end
    fs.delete(BACKUP)
    say("Restored.", colors.lime)
    return true
end

-- ── Full version ───────────────────────────────────────────────────────────
-- A stage folder has its own setup.lua. It downloads the stage's file list,
-- checks every file's SHA-256 and installs startup.lua (the old one is saved as
-- startup.lua.bak). This installer downloads setup.lua, checks it, then runs it.
local function installStage(entry)
    banner()
    say("Target: Prismarine full version, stage " .. entry.n, colors.lightBlue)
    say("Source: " .. entry.path .. "/setup.lua", colors.lightGray)
    print()
    say("setup.lua checks every file against the stage's hash list.", colors.lightGray)
    say("Your old startup.lua is saved as startup.lua.bak.", colors.lightGray)
    print()

    local want = readLine("SHA-256 of setup.lua, Enter to skip: ")
    want = want:lower():gsub("%s", "")
    if want == "" then
        want = nil
    elseif not want:match("^%x+$") or #want ~= 64 then
        fail("That is not a SHA-256 hash.", "Nothing was changed.")
    end

    local body, err = httpGet(fresh(rawUrl(entry.path .. "/setup.lua")))
    if not body then fail("Could not download setup.lua.", err) end
    local got = sha256(body)
    if want and got ~= want then
        fail("setup.lua does not match your hash.", "Got " .. got .. "\nNothing was changed.")
    end
    local fn, serr = load(body, "=setup.lua")
    if not fn then fail("setup.lua has a syntax error.", serr) end
    say("setup.lua SHA-256 " .. got, want and colors.lime or colors.lightGray)
    print()
    if not yesNo("Install stage " .. entry.n .. "?") then
        say("Cancelled. Nothing was changed.", colors.yellow)
        return false
    end
    if not writeFile(SETUP, body) then fail("Cannot write the setup file.") end
    local ok, why
    if shell and shell.run then
        ok, why = pcall(shell.run, SETUP)
    else
        ok, why = pcall(fn)
    end
    pcall(fs.delete, SETUP)
    if not ok or why == false then
        fail("Setup stopped before it finished.", ok and "See the message above." or tostring(why))
    end
    return true
end

-- ── Release, Classic and Simple ────────────────────────────────────────────
local function chooseEntry(title, items, label)
    local opts = { "Install the newest, " .. label(items[1]), "Choose a version...", "Cancel" }
    local choice = menu(title, opts)
    if choice == 1 then return items[1] end
    if choice == 2 then
        local labels = {}
        for i, v in ipairs(items) do
            labels[i] = label(v) .. (i == 1 and "  newest" or "")
        end
        local pick = menu(title, labels)
        if pick then return items[pick] end
    end
    return nil
end

local function classicLabel(prefix)
    local cur = installedState()
    return function(v)
        return prefix .. " " .. v.version .. (cur and cur.version == v.version and "  installed" or "")
    end
end

-- Returns true when something was installed, false or nil when it was not.
local function runLegacy(edition, wantedN)
    local inEdition = edition == "simple" and inSimple or inClassic
    local name = edition == "simple" and "Classic Simple OS" or "Prismarine Classic"
    say("Looking for " .. name .. " versions in " .. REPO .. " ...")
    local all = listVersions()
    local items = {}
    for _, v in ipairs(all or {}) do
        if inEdition(v.version) then items[#items + 1] = v end
    end
    if #items == 0 then
        fail("No " .. name .. " versions found in " .. REPO .. ".",
            edition == "simple" and ("Simple OS is version " .. SIMPLE_MAX .. " and below.")
            or ("Classic is version " .. CLASSIC_MIN .. " and up, without 18."))
    end
    local entry
    if wantedN then
        if BROKEN[wantedN] then fail("Version " .. wantedN .. " is broken and cannot be installed.") end
        for _, v in ipairs(items) do
            if v.version == wantedN then entry = v end
        end
        if not entry then fail(name .. " has no version " .. wantedN .. ".") end
    else
        local title = name .. (edition == "simple" and ", before the loading screen" or ", 17 and up, no 18")
        entry = chooseEntry(title, items, classicLabel(edition == "simple" and "Simple OS" or "Version"))
    end
    if not entry then return nil end
    if fs.exists("/prismarine/boot.lua") then
        print()
        say("The full version is installed on this computer.", colors.yellow)
        say("This replaces startup.lua. The /prismarine folder stays.", colors.yellow)
        if not yesNo("Continue?") then
            say("Cancelled. Nothing was changed.", colors.yellow)
            return false
        end
    end
    return install(entry)
end

-- wantedVer is "1.1" style text, or nil to choose from a menu.
local function runRelease(wantedVer)
    say("Looking for Prismarine releases in " .. REPO .. " ...")
    local items = listReleases()
    if #items == 0 then
        fail("No release found in " .. REPO .. ".",
            "Looking for release/manifest.txt, or a GitHub release tagged r1.0, r1.1 ...")
    end
    local entry
    if wantedVer then
        for _, v in ipairs(items) do
            if v.version == wantedVer then entry = v end
        end
        if not entry then fail("There is no Release " .. wantedVer .. ".") end
    else
        entry = chooseEntry("Prismarine Release, 1.x", items, classicLabel("Release"))
    end
    if not entry then return nil end
    return install(entry)
end

local function runFull(wantedN)
    say("Looking for full versions in " .. REPO .. " ...")
    local stages = listStages()
    if #stages == 0 then fail("No full version stage found in " .. REPO .. ".", "A stage folder needs a setup.lua.") end
    local entry
    if wantedN then
        for _, st in ipairs(stages) do
            if st.n == wantedN then entry = st end
        end
        if not entry then fail("There is no full stage " .. wantedN .. ".") end
    else
        entry = chooseEntry("Prismarine full version", stages, function(st) return "Stage " .. st.n end)
    end
    if not entry then return nil end
    return installStage(entry)
end

-- ── Main ────────────────────────────────────────────────────────────────────
local function run()
    banner()
    if not http then
        fail("HTTP is disabled on this server.", "The installer needs it to download Prismarine OS.")
    end
    -- An owner/repo argument anywhere picks another GitHub repo.
    local words = {}
    for _, a in ipairs(args) do
        if a:match("^[%w%-%._]+/[%w%-%._]+@?[%w%-%._/]*$") then REPO = a else words[#words + 1] = a end
    end
    local wanted, second = words[1], words[2]
    local num = second and second:match("^%d+$") and tonumber(second) or nil

    local done
    if wanted == "undo" then
        done = undo()
    elseif wanted == "release" then
        done = runRelease(second and second:match("^%d+%.%d+$") or nil)
    elseif wanted and wanted:match("^%d+%.%d+$") then
        done = runRelease(wanted)
    elseif wanted == "full" or wanted == "latest" then
        done = runFull(num)
    elseif wanted == "classic" or wanted == "simple" then
        done = runLegacy(wanted, num)
    elseif wanted and wanted:match("^%d+$") then
        local n = tonumber(wanted)
        if BROKEN[n] then fail("Version " .. n .. " is broken and cannot be installed.") end
        if inClassic(n) then done = runLegacy("classic", n)
        elseif inSimple(n) then done = runLegacy("simple", n)
        else fail("Version " .. n .. " is not offered.", "Classic is " .. CLASSIC_MIN .. " and up without 18. Simple OS is " .. SIMPLE_MAX .. " and below.") end
    else
        local opts, acts = {}, {}
        local function add(label, fn)
            opts[#opts + 1] = label
            acts[#acts + 1] = fn
        end
        add("Release, 1.x (newest)", function() return runRelease(nil) end)
        add("Full version, older kernel stages", function() return runFull(nil) end)
        add("Classic, versions 17 and up, no 18", function() return runLegacy("classic", nil) end)
        add("Classic Simple OS, before the loading screen", function() return runLegacy("simple", nil) end)
        if fs.exists(BACKUP .. "/journal.json") then add("Undo the last install", undo) end
        add("Cancel", function() return nil end)
        local choice = menu("Prismarine installer v" .. INSTALLER_VERSION, opts)
        if choice then done = acts[choice]() end
    end

    if done == nil then
        banner()
        say("Cancelled. Nothing was changed.", colors.yellow)
    elseif done then
        print()
        if yesNo("Reboot now?") then
            sleep(0.5)
            os.reboot()
        end
    end
end

local ok, err = pcall(run)
if not ok then
    if err and err ~= "" then
        setColor(colors.red, colors.black)
        print(tostring(err))
    end
    setColor(colors.white, colors.black)
    print("Installer stopped.")
end
