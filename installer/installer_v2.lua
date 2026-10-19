-- Prismarine OS installer v2 for CC:Tweaked 1.20.1
--
-- Installs, upgrades, downgrades and undoes Prismarine OS versions.
-- A version is a GitHub release tagged pv<number>, for example pv23.
-- A release with a manifest.json is a multi file version. A release without
-- one is a single file version (startup_v<number>.lua). Single file versions
-- that have no release are still found in the repo root.
--
--   pastebin run <code>              menu
--   pastebin run <code> latest       install the newest version
--   pastebin run <code> 21           install version 21 (upgrade or downgrade)
--   pastebin run <code> undo         restore what the last install replaced
--   pastebin run <code> 21 owner/repo   take it from another GitHub repo

local INSTALLER_VERSION = "2"
local REPO   = "FilesCodes-ui/prismarine-os"   -- owner/name, or owner/name@branch
local STATE  = "/.prismarine_installed.json"
local STAGE  = "/.prismarine_stage"
local BACKUP = "/.prismarine_backup"

local args = { ... }

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
    write(question .. " (Y/N) ")
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

local function writeFile(path, data)
    fs.makeDir(fs.getDir(path))
    local f = fs.open(path, "wb")
    if not f then return false end
    f.write(data)
    f.close()
    return true
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

local function legacyFromApi()
    local repo, branch = repoParts()
    local body = httpGet("https://api.github.com/repos/" .. repo .. "/contents/?ref=" .. branch)
    local data = body and textutils.unserialiseJSON(body)
    if type(data) ~= "table" then return nil end
    local out = {}
    for _, f in ipairs(data) do
        local n = type(f) == "table" and type(f.name) == "string" and f.name:match("^startup_v(%d+)%.lua$")
        if n then out[#out + 1] = { version = tonumber(n), kind = "legacy", file = f.name } end
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
        elseif urlExists(rawUrl(file)) then
            out[#out + 1] = { version = n, kind = "legacy", file = file }
        end
    end
    print()
    return out
end

local function listVersions()
    local byVer, list = {}, {}
    local rel, leg = releasesFromApi(), legacyFromApi()
    if not rel and not leg then
        say("GitHub file list unavailable, checking each version...", colors.lightGray)
        rel = probeVersions()
    end
    for _, v in ipairs(rel or {}) do byVer[v.version] = v end
    for _, v in ipairs(leg or {}) do
        if not byVer[v.version] then byVer[v.version] = v end
    end
    for _, v in pairs(byVer) do list[#list + 1] = v end
    if #list == 0 then return nil, "No pv<number> releases in " .. REPO end
    table.sort(list, function(a, b) return a.version > b.version end)
    return list
end

-- ── Manifest ────────────────────────────────────────────────────────────────
local function singleFile(entry, want)
    return {
        version = entry.version, dataFormat = 1, bootstrap = "startup.lua", keep = {},
        ref = entry.ref, legacy = true,
        files = { { path = "startup.lua", src = entry.file, sha256 = want } },
    }
end

-- Turns a version into a manifest table, or returns nil and a reason.
-- want is the SHA-256 the user typed, or nil.
local function loadManifest(entry, want)
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
local function installedState()
    local raw = readFile(STATE)
    local st = raw and textutils.unserialiseJSON(raw)
    if type(st) == "table" and type(st.files) == "table" then return st end
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
    say("Target: version " .. n, colors.lightBlue)
    say("Installed: " .. (cur and ("version " .. cur.version) or "none found"), colors.lightGray)
    print()

    local want = readLine("SHA-256 of the manifest or file (Enter to skip): ")
    want = want:lower():gsub("%s", "")
    if want == "" then
        want = nil
    elseif not want:match("^%x+$") or #want ~= 64 then
        fail("That is not a SHA-256 hash.", "Nothing was changed.")
    end

    local m, why = loadManifest(entry, want)
    if not m then fail("Cannot use this version.", why) end

    local downgrade = cur and n < cur.version
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

    -- 1. Download and check everything into a staging folder.
    fs.delete(STAGE)
    local total = #m.files
    for i, f in ipairs(m.files) do
        local x, y = term.getCursorPos()
        term.setCursorPos(1, y)
        term.clearLine()
        write("Downloading " .. i .. "/" .. total .. " " .. f.path:sub(-30))
        local body, err = httpGet(fresh(rawUrl(f.src, m.ref)))
        if not body then
            fs.delete(STAGE)
            print()
            fail("Download failed: " .. f.path, err)
        end
        local got = sha256(body)
        if f.sha256 and got ~= f.sha256 then
            fs.delete(STAGE)
            print()
            fail("Hash mismatch: " .. f.path, "Got " .. got .. "\nNothing was changed.")
        end
        f.sha256 = f.sha256 or got
        if f.path:match("%.lua$") then
            local fn, serr = load(body, "=" .. f.path)
            if not fn then
                fs.delete(STAGE)
                print()
                fail("Syntax error in " .. f.path, serr)
            end
        end
        if not writeFile(STAGE .. "/" .. f.path, body) then
            fs.delete(STAGE)
            print()
            fail("Cannot write staging file.", f.path)
        end
    end
    print()
    say("All " .. total .. " files verified.", colors.lime)

    -- 2. Work out what changes, then save the old copies.
    local newSet, writes, removes = {}, {}, {}
    for _, f in ipairs(m.files) do
        newSet[f.path] = true
        writes[#writes + 1] = f.path
    end
    for _, p in ipairs(cur and cur.files or {}) do
        if safePath(p) and not newSet[p] and not isKept(p, m.keep) and not isKept(p, cur.keep) then
            removes[#removes + 1] = p
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

    -- 3. Move into place. The bootstrap goes last, so a crash halfway
    --    leaves the old startup.lua running.
    for _, p in ipairs(writes) do
        if p ~= m.bootstrap then
            if fs.exists(p) then fs.delete(p) end
            fs.makeDir(fs.getDir(p))
            fs.move(STAGE .. "/" .. p, p)
        end
    end
    if fs.exists(m.bootstrap) then fs.delete(m.bootstrap) end
    fs.makeDir(fs.getDir(m.bootstrap))
    fs.move(STAGE .. "/" .. m.bootstrap, m.bootstrap)

    -- 4. Remove files the target version does not own.
    for _, p in ipairs(removes) do
        if fs.exists(p) then fs.delete(p) end
        pruneEmptyDirs(p)
    end
    fs.delete(STAGE)

    -- 5. Record what is installed.
    local names = {}
    for _, p in ipairs(writes) do names[#names + 1] = p end
    writeFile(STATE, textutils.serialiseJSON({
        version = n, dataFormat = m.dataFormat, files = names, keep = m.keep,
        manifestSha256 = m.manifestSha256,
    }))

    print()
    say("Installed Prismarine OS version " .. n .. ".", colors.lime)
    if #removes > 0 then say(#removes .. " old files removed.", colors.lightGray) end
    if m.manifestSha256 then say("Manifest SHA-256 " .. m.manifestSha256, colors.lightGray) end
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

-- ── Main ────────────────────────────────────────────────────────────────────
local function run()
    banner()
    if not http then
        fail("HTTP is disabled on this server.", "The installer needs it to download Prismarine OS.")
    end
    if args[2] and args[2]:match("^[%w%-%._]+/[%w%-%._]+@?[%w%-%._/]*$") then
        REPO = args[2]
    end

    local done
    local wanted = args[1]
    if wanted == "undo" then
        done = undo()
    else
        say("Looking for versions in " .. REPO .. " ...")
        local versions, why = listVersions()
        if not versions then fail("Could not find any versions.", why) end

        local entry
        if wanted == "latest" then
            entry = versions[1]
        elseif wanted and wanted:match("^%d+$") then
            for _, v in ipairs(versions) do
                if v.version == tonumber(wanted) then entry = v end
            end
            if not entry then fail("Version " .. wanted .. " does not exist.") end
        else
            local opts = {
                "Install the newest version (" .. versions[1].version .. ")",
                "Choose a version...",
            }
            local hasUndo = fs.exists(BACKUP .. "/journal.json")
            if hasUndo then opts[#opts + 1] = "Undo the last install" end
            opts[#opts + 1] = "Cancel"
            local choice = menu("Prismarine OS installer", opts)
            if choice == 1 then
                entry = versions[1]
            elseif choice == 2 then
                local cur = installedState()
                local labels = {}
                for i, v in ipairs(versions) do
                    labels[i] = "Version " .. v.version
                        .. (i == 1 and "  (newest)" or "")
                        .. (cur and cur.version == v.version and "  (installed)" or "")
                end
                local pick = menu("Choose a version", labels)
                if pick then entry = versions[pick] end
            elseif choice == 3 and hasUndo then
                done = undo()
            end
        end
        if entry then done = install(entry) end
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
