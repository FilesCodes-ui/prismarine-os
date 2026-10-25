--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/sys/update.lua
-- Prismarine OS v24: update check, install, add-ons and the app store list.
--
-- The release manifest (manifest.txt in the repo folder) lists every file with
-- its SHA-256. A check compares it with the files on this computer. An install
-- downloads each changed file, checks its hash, and only then replaces the old
-- one. The password is needed to install. The sealed system file check is
-- renewed afterward, so the next boot has no warning.
--
-- The manifest can carry a signature (manifest.sig, Ed25519 over manifest.txt).
-- A wrong signature is always refused. A missing one is allowed on a normal
-- computer, with a note, and refused in Archive mode.
--
-- It also lists add-ons (parts that install on request, like the Archive app)
-- and the app store (downloadable apps and music, each with a pinned SHA-256).
--
-- Kernel code only.

local U = {}

local K, C, S
local DEFAULT_BASE = "https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/release/"
local INSTALL = "/prismarine/data/install.json"
-- Public half of the KHI release key. Signed releases verify against it.
local RELEASE_KEY = "43711e10b721b1c1302ef39d91121d2101bc6c70358c1adc721fc76b0d2012ad"
-- True: an update list needs a valid signature from the release key, or it is
-- refused. Sign each release with tools/sign_manifest.py (it writes
-- manifest.sig). Set this to false only for a private server you trust.
local REQUIRE_SIGNATURE = true
local wantedFiles, commit
local JOURNAL = "/prismarine/data/update.journal"
local STORE_MAX = 18000000   -- bytes. Computers have about 20 MB.
local state = { state = "idle", text = "Not checked yet.", changed = {}, version = nil, at = nil }

function U.init(kernel, crypto, secure)
  K, C, S = kernel, crypto, secure
end

local function base()
  local h = fs.open(INSTALL, "r")
  if h then
    local ok, t = pcall(textutils.unserialiseJSON, h.readAll())
    h.close()
    if ok and type(t) == "table" and type(t.base) == "string" and t.base:match("^https://") then
      if t.base:sub(-1) ~= "/" then t.base = t.base .. "/" end
      return t.base
    end
  end
  return DEFAULT_BASE
end

-- Download one URL. Runs inside a kernel task, so it may wait for events.
local function get(url)
  local ok, err = http.request({ url = url, binary = true })
  if not ok then return nil, tostring(err) end
  local timer = os.startTimer(25)
  while true do
    local ev, a, b = os.pullEventRaw()
    if ev == "http_success" and a == url then
      local data = b.readAll()
      b.close()
      return data
    elseif ev == "http_failure" and a == url then
      return nil, tostring(b or "no answer")
    elseif ev == "timer" and a == timer then
      return nil, "timed out"
    end
  end
end

local function okPath(p)
  return type(p) == "string" and #p < 120 and not p:find("%.%.") and not p:find("%c") and p:sub(1, 1) ~= "/"
end

local function parseManifest(data)
  local ok, t = pcall(textutils.unserialise, data)
  if not ok or type(t) ~= "table" or type(t.files) ~= "table" or type(t.version) ~= "string" then return nil end
  for p, h in pairs(t.files) do
    if type(p) ~= "string" or type(h) ~= "string" or #h ~= 64 or p:find("%.%.") or p:sub(1, 1) == "/" then return nil end
    if not (p == "startup.lua" or p:sub(1, 10) == "prismarine") then return nil end
  end
  -- add-ons: built-in parts that install on request
  local addons = {}
  if type(t.addons) == "table" then
    for name, a in pairs(t.addons) do
      if type(name) == "string" and type(a) == "table" and okPath(a.path) and a.path:sub(1, 16) == "prismarine/apps/"
        and type(a.sha256) == "string" and #a.sha256 == 64 then
        addons[name] = { path = a.path, sha256 = a.sha256 }
      end
    end
  end
  t.addons = addons
  -- the app store list
  local store = {}
  if type(t.store) == "table" then
    for _, e in ipairs(t.store) do
      if type(e) == "table" and type(e.name) == "string" and #e.name <= 24 and not e.name:find("%c")
        and type(e.about) == "string" and #e.about <= 80
        and (e.sha256 == nil or (type(e.sha256) == "string" and #e.sha256 == 64))
        and (e.size == nil or (type(e.size) == "number" and e.size > 0 and e.size <= STORE_MAX))
        and okPath(e.dest) and (e.dest:sub(1, 9) == "programs/" or e.dest:sub(1, 6) == "music/")
        and ((okPath(e.file) and not e.url) or (type(e.url) == "string" and e.url:match("^https://[%w%.%-]+/") and not e.file)) then
        store[#store + 1] = { name = e.name, about = e.about, sha256 = e.sha256, size = e.size,
          dest = e.dest, file = e.file, url = e.url }
      end
    end
  end
  t.store = store
  return t
end

local lastVerified = nil

-- "Release 1.2" -> 1.002. Compares major, then minor.
local function versionNumber(v)
  local a, b = tostring(v or ""):match("(%d+)%.(%d+)")
  if not a then return nil end
  return tonumber(a) + tonumber(b) / 1000
end

-- Fetch manifest.txt and its signature. Runs inside a kernel task.
-- Returns manifest, signed ("ok" | "none"), or nil, reason.
local function fetchManifest()
  local data, err = get(base() .. "manifest.txt")
  if not data then return nil, "Could not reach the update server (" .. tostring(err) .. ")." end
  local signed = "none"
  local sigText = get(base() .. "manifest.sig")
  if sigText then
    local hex = sigText:gsub("%s", "")
    local sig = (#hex == 128 and hex:match("^%x+$")) and C.unhex(hex) or nil
    -- The same list and signature were already checked: skip the slow math.
    local seen = sig and C.sha256hex(data .. hex) or nil
    if not sig or (seen ~= lastVerified and not C.verify(C.unhex(RELEASE_KEY), data, sig)) then
      return nil, "The update list has a wrong signature. Nothing was changed."
    end
    lastVerified = seen
    signed = "ok"
  elseif REQUIRE_SIGNATURE or (K.lockdown and K.lockdown()) then
    return nil, "The update list is not signed, so it was refused. Sign it with tools/sign_manifest.py, or set REQUIRE_SIGNATURE to false in update.lua."
  end
  local m = parseManifest(data)
  if not m then return nil, "The update list is damaged." end
  -- Never go back to an older release. An old signed list is still validly
  -- signed, so the signature alone would not stop it.
  local have, want = versionNumber(K.VERSION), versionNumber(m.version)
  if have and want and want < have then
    return nil, "The update list (" .. tostring(m.version) .. ") is older than this release (" .. tostring(K.VERSION) .. "). Refused."
  end
  return m, signed
end

function U.status() return state end

-- Theme download. A theme is a small JSON file of color names. The text goes to
-- the UI service, which checks every field before it keeps anything.
local themeDl = { state = "idle", text = "" }
function U.themeStatus() return { state = themeDl.state, text = themeDl.text, name = themeDl.name } end
function U.themeDownload(url)
  if themeDl.state == "loading" then return false, "A download is running" end
  if type(url) ~= "string" or #url > 300 or url:find("%c") or url:find("%s") or not url:match("^https://[%w%.%-]+/") then
    return false, "Use a link that starts with https://"
  end
  if K.lockdown and K.lockdown() then return false, "Blocked in Archive mode" end
  if not http or not http.request then return false, "HTTP is off on this server" end
  if not (K.themeAdmin and K.themeAdmin.install) then return false, "Themes are not available" end
  themeDl = { state = "loading", text = "Downloading..." }
  K.task(function()
    local data, err = get(url)
    if not data then themeDl = { state = "error", text = tostring(err) } return end
    if #data > 4096 then themeDl = { state = "error", text = "That file is too big for a theme" } return end
    local ok, r = K.themeAdmin.install(data)
    if ok then themeDl = { state = "done", text = "Installed " .. tostring(r), name = r }
    else themeDl = { state = "error", text = tostring(r) } end
  end, function(ok, err)
    if not ok then themeDl = { state = "error", text = "Failed: " .. tostring(err) } end
  end)
  return true
end

-- Every file the release lists, plus the add-ons already installed here, so an
-- installed add-on (the Archive app) updates with the release and is hash checked.
function wantedFiles(m)
  local want = {}
  for p, h in pairs(m.files) do want[p] = h end
  for _, a in pairs(m.addons or {}) do
    if fs.exists("/" .. a.path) then want[a.path] = a.sha256 end
  end
  return want
end

-- Crash safe commit. The new copies are already written as name.new. A journal
-- (paths and hashes, sealed with a key only the password makes) is written
-- first, then the files move into place, then the system check is renewed and
-- the journal goes. After a power cut, U.recover() finishes the same steps at
-- the next start, so there is no half installed release and no false warning.
function commit(entries)
  local body = textutils.serialize(entries)
  local mac = C.hex(C.mac(S.key("update journal"), body))
  local h = fs.open(JOURNAL, "w")
  if not h then return false, "Could not write the update journal." end
  h.write(textutils.serialize({ body = body, mac = mac }))
  h.close()
  return U.finish(entries)
end

function U.finish(entries)
  for _, e in ipairs(entries) do
    local final, tmp = "/" .. e.path, "/" .. e.path .. ".new"
    if e.delete then
      pcall(fs.delete, final)
    elseif fs.exists(tmp) then
      local data = C.readFile(tmp)
      if not data or C.sha256hex(data) ~= e.hash then
        pcall(fs.delete, tmp)
        return false, e.path .. " was damaged on the disk."
      end
      if fs.exists(final) then fs.delete(final) end
      fs.move(tmp, final)
    end
  end
  S.sealManifest(S.hashSystem())
  pcall(fs.delete, JOURNAL)
  return true
end

-- Called at start, after login and before the system file check.
-- Returns "finished" when an interrupted update was completed.
function U.recover()
  if not fs.exists(JOURNAL) then return nil end
  local raw = C.readFile(JOURNAL)
  local ok, j = pcall(textutils.unserialize, raw or "")
  if not ok or type(j) ~= "table" or type(j.body) ~= "string" or type(j.mac) ~= "string" then
    pcall(fs.delete, JOURNAL)
    return nil
  end
  local good = C.hex(C.mac(S.key("update journal"), j.body))
  if good ~= j.mac then
    pcall(fs.delete, JOURNAL)
    return nil
  end
  local entries = textutils.unserialize(j.body)
  if type(entries) ~= "table" then pcall(fs.delete, JOURNAL) return nil end
  for _, e in ipairs(entries) do
    if type(e.path) ~= "string" or e.path:find("%.%.") or e.path:sub(1, 1) == "/"
      or not (e.path == "startup.lua" or e.path:sub(1, 10) == "prismarine") then
      pcall(fs.delete, JOURNAL)
      return nil
    end
  end
  local done = U.finish(entries)
  return done and "finished" or nil
end

-- Compare the release manifest with this computer. Runs as a kernel task.
function U.check(done)
  if state.state == "checking" or state.state == "installing" then return end
  state.state, state.text = "checking", "Checking for updates..."
  K.task(function()
    local m, signed = fetchManifest()
    if not m then
      state.state, state.text = "error", tostring(signed)
      return
    end
    state.signed = signed
    local note = (signed == "ok") and " Signed." or " Not signed."
    local have = S.lastHashes or S.hashSystem()
    local changed = {}
    local want = wantedFiles(m)
    for p, h in pairs(want) do
      if have[p] ~= h then changed[#changed + 1] = p end
    end
    table.sort(changed)
    state.manifest, state.version, state.at = m, m.version, os.epoch("utc")
    state.changed = changed
    if #changed == 0 then
      state.state, state.text = "current", "You are up to date (" .. m.version .. ")." .. note
    else
      state.state, state.text = "available", #changed .. " files differ. Version " .. m.version .. "." .. note .. (#changed <= 3 and (" " .. table.concat(changed, ", ")) or "")
    end
  end, function(ok, err)
    if not ok then state.state, state.text = "error", "Check failed: " .. tostring(err) end
    if done then pcall(done, state) end
  end)
end

-- Install the checked update. Needs the password. Runs as a kernel task.
function U.install(password, done)
  if state.state ~= "available" or not state.manifest then
    return false, "Check for updates first."
  end
  state.state, state.text = "installing", "Checking your password..."
  K.task(function()
    local good, why, extra = S.checkPassword(password)
    if not good then
      state.state, state.text = "available", (why == "locked") and ("Too many tries. Wait " .. tostring(extra) .. " s.") or "Wrong password."
      return
    end
    local m = state.manifest
    local want = wantedFiles(m)
    local staged, entries = {}, {}
    local total = #state.changed
    for i, p in ipairs(state.changed) do
      state.text = ("Downloading %d of %d: %s"):format(i, total, fs.getName(p))
      state.frac = (i - 1) / total
      local data, err = get(base() .. p)
      if not data then
        state.state, state.text = "available", "Download failed: " .. p .. " (" .. tostring(err) .. ")"
        for _, s in ipairs(staged) do pcall(fs.delete, s) end
        return
      end
      if C.sha256hex(data) ~= want[p] then
        state.state, state.text = "available", "Refused: " .. p .. " does not match its hash."
        for _, s in ipairs(staged) do pcall(fs.delete, s) end
        return
      end
      local tmp = "/" .. p .. ".new"
      local h = fs.open(tmp, "wb")
      if not h then
        state.state, state.text = "available", "Could not write " .. p
        for _, s in ipairs(staged) do pcall(fs.delete, s) end
        return
      end
      h.write(data)
      h.close()
      staged[#staged + 1] = tmp
      entries[#entries + 1] = { path = p, hash = want[p] }
    end
    state.text = "Installing..."
    -- Files the release no longer lists are removed from system folders.
    local keep = {}
    for _, a in pairs(m.addons or {}) do keep[a.path] = true end
    for _, p in ipairs(S.systemFiles()) do
      if m.files[p] == nil and not keep[p] and p:sub(1, 21) ~= "prismarine/lib/pixelb" then
        entries[#entries + 1] = { path = p, delete = true }
      end
    end
    local okC, errC = commit(entries)
    if not okC then
      state.state, state.text = "available", "Install stopped: " .. tostring(errC) .. " It finishes at the next start."
      return
    end
    state.state, state.text, state.frac = "done", "Updated to " .. m.version .. ". Reboot to use it.", 1
    state.changed = {}
  end, function(ok, err)
    if not ok then state.state, state.text = "available", "Install failed: " .. tostring(err) end
    if done then pcall(done, state) end
  end)
  return true
end

-- ------------------------------------------------------------------ add-ons
-- A built-in part that installs on request. Today that is the Archive app.
-- The hash comes from the (signed) update list. Works in Bunker mode too,
-- because the kernel does the download, not an app. Runs inside a kernel task.
-- Returns true, or false and a reason.
function U.installAddon(name)
  local m, signed = fetchManifest()
  if not m then return false, tostring(signed) end
  local a = m.addons[name]
  if not a then return false, "This release has no '" .. tostring(name) .. "' add-on." end
  local data, err = get(base() .. a.path)
  if not data then return false, "Download failed (" .. tostring(err) .. ")." end
  if C.sha256hex(data) ~= a.sha256 then return false, "Refused: the file does not match its hash." end
  local tmp = "/" .. a.path .. ".new"
  local h = fs.open(tmp, "wb")
  if not h then return false, "Could not write the file." end
  h.write(data)
  h.close()
  local okC, errC = commit({ { path = a.path, hash = a.sha256 } })
  if not okC then return false, tostring(errC) end
  return true
end

-- --------------------------------------------------------------- app store
-- A list of downloadable apps and music with pinned hashes. Apps only see a
-- short summary. The kernel downloads, checks size and hash, and saves.

local store = { state = "idle", text = "Not loaded.", entries = {}, busy = nil, signed = nil }
local sha256y -- hash that yields now and then, loaded when first needed

local function hashBig(data)
  if #data < 20000 then return C.sha256hex(data) end
  sha256y = sha256y or dofile("/prismarine/lib/sha256.lua")
  return sha256y(data)
end

-- What is installed is worked out once per file and remembered. Hashing a
-- file on every screen redraw made the Download app lag the whole computer.

-- ------------------------------------------------------- live repo listing
-- Instead of a hand-kept list, read the GitHub repo itself. Any .lua file in a
-- folder named "store" becomes a program, any .dfpwm file in a folder named
-- "store" or "music" becomes a music track. No hash is checked on these.
-- Skipped in Archive mode, which only trusts the signed list.
local aboutCache = {}

local function urlEncode(u)
  return (u:gsub("[^%w%-%._~:/%?#%[%]@!$&'()*+,;=%%]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function titleCase(w)
  return (w:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function listRepo()
  local o, r, b, sub = base():match("^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.*)$")
  if not o then return nil, "The update address is not a GitHub address." end
  local data, err = get("https://api.github.com/repos/" .. o .. "/" .. r .. "/git/trees/" .. b .. "?recursive=1")
  if not data then return nil, "GitHub did not answer (" .. tostring(err) .. ")." end
  local ok, t = pcall(textutils.unserialiseJSON, data)
  if not ok or type(t) ~= "table" or type(t.tree) ~= "table" then return nil, "GitHub gave an unreadable list." end
  local raw = "https://raw.githubusercontent.com/" .. o .. "/" .. r .. "/" .. b .. "/"
  local found, byDest = {}, {}
  for _, f in ipairs(t.tree) do
    local path = f.path
    if f.type == "blob" and type(path) == "string" and type(f.size) == "number" and f.size > 0 and f.size <= STORE_MAX
      and not path:find("%.%.") then
      local parts = {}
      for part in path:gmatch("[^/]+") do parts[#parts + 1] = part end
      local file = parts[#parts]
      local ext = file:match("%.(%w+)$")
      local inDir = false
      for i = 1, #parts - 1 do
        if parts[i] == "store" or (parts[i] == "music" and ext == "dfpwm") then inDir = true end
      end
      if inDir and (ext == "lua" or ext == "dfpwm") then
        local stem = file:sub(1, -#ext - 2)
        local ver = 0
        local e
        if ext == "lua" then
          stem = stem:gsub("^p%.", "")
          local v = stem:match("_v(%d+)$")
          if v then ver = tonumber(v); stem = stem:gsub("_v%d+$", "") end
          local nm = titleCase((stem:gsub("[_%-]+", " ")))
          e = { name = nm:sub(1, 24), dest = "programs/" .. stem:lower():gsub("[^%w]+", "_") .. ".lua",
            size = f.size, url = raw .. urlEncode(path), ver = ver, lua = true }
        else
          local nm = stem:gsub("^%d+[%-%.]%d*%.?%s*", "")
          if nm == "" then nm = stem end
          e = { name = nm:sub(1, 24), dest = "music/" .. file, size = f.size,
            url = raw .. urlEncode(path), ver = 0,
            about = ("Music track (%.1f MB)"):format(f.size / 1000000) }
        end
        if okPath(e.dest) and not e.name:find("%c") then
          local old = byDest[e.dest]
          if not old then byDest[e.dest] = e; found[#found + 1] = e
          elseif e.ver > old.ver then
            for i, x in ipairs(found) do if x == old then found[i] = e end end
            byDest[e.dest] = e
          end
        end
      end
    end
  end
  -- one line of description from each program's own header
  for _, e in ipairs(found) do
    if e.lua then
      local key = e.url .. ":" .. e.size
      if aboutCache[key] == nil then
        local src = get(e.url)
        local about = "Program"
        if src then
          local seenTitle = false
          local n = 0
          for line in (src:sub(1, 3000) .. "\n"):gmatch("(.-)\r?\n") do
            n = n + 1
            if n > 40 then break end
            if line:match("^%-%- Prismarine") then seenTitle = true
            elseif seenTitle and line:match("^%-%-%s*%S") and not line:match("^%-%-@") then
              about = line:gsub("^%-%-%s*", ""); break
            end
          end
        end
        aboutCache[key] = about
      end
      e.about = aboutCache[key]:sub(1, 80)
    end
  end
  table.sort(found, function(a, b) return a.name:lower() < b.name:lower() end)
  return found
end

local instCache = {}

local function fileKey(e)
  local p = "/" .. e.dest
  if not fs.exists(p) or fs.isDir(p) then return "none" end
  local mod = 0
  local ok, a = pcall(fs.attributes, p)
  if ok and type(a) == "table" then mod = a.modified or 0 end
  return fs.getSize(p) .. ":" .. mod .. ":" .. (e.sha256 or "")
end

-- Cheap answer from the size alone.
local function quickState(e)
  local p = "/" .. e.dest
  if not fs.exists(p) or fs.isDir(p) then return "none" end
  if e.size and fs.getSize(p) ~= e.size then return "update" end
  return "installed"
end

-- Exact answer. Hashes the file, so only call it inside a kernel task.
local function checkState(e)
  local state = quickState(e)
  if state == "installed" and e.sha256 and e.size and e.size <= 200000 then
    local h = fs.open("/" .. e.dest, "rb")
    local d = h and h.readAll() or ""
    if h then h.close() end
    state = (hashBig(d) == e.sha256) and "installed" or "update"
  end
  instCache[e.dest] = { key = fileKey(e), state = state }
  return state
end

local function installedState(e)
  local c = instCache[e.dest]
  if c and c.key == fileKey(e) then return c.state end
  return quickState(e)
end

function U.storeStatus()
  local list = {}
  for i, e in ipairs(store.entries) do
    list[i] = { name = e.name, about = e.about, size = e.size, dest = e.dest, status = installedState(e) }
  end
  return { state = store.state, text = store.text, entries = list, busy = store.busy, signed = store.signed,
    frac = store.frac }
end

function U.storeRefresh()
  if store.state == "loading" or store.state == "installing" then return false end
  store.state, store.text, store.frac = "loading", "Loading the list...", nil
  K.task(function()
    local m, signed = fetchManifest()
    local entries = m and m.store or nil
    if not (K.lockdown and K.lockdown()) then
      local live, why = listRepo()
      if live then entries, signed = live, "live"
      elseif not entries then store.state, store.text = "error", tostring(why) return end
    end
    if not entries then
      store.state, store.text = "error", tostring(signed)
      return
    end
    store.entries, store.signed = entries, signed
    store.state = "ready"
    store.text = (#entries == 0) and "The list is empty." or ""
    for _, e in ipairs(entries) do checkState(e) end
  end, function(ok, err)
    if not ok then store.state, store.text = "error", "Load failed: " .. tostring(err) end
  end)
  return true
end

function U.storeInstall(name)
  if store.state ~= "ready" then return false, "Load the list first." end
  local e
  for _, x in ipairs(store.entries) do
    if x.name == name then e = x end
  end
  if not e then return false, "Not in the list." end
  store.state, store.busy, store.text, store.frac = "installing", e.name, "Downloading " .. e.name .. "...", 0.1
  local dest = "/" .. e.dest
  K.task(function()
    local free = fs.getFreeSpace("/")
    local old = fs.exists(dest) and not fs.isDir(dest) and fs.getSize(dest) or 0
    local need = e.size or 1000000
    if free + old < need + 20000 then
      store.text = "Not enough free space (" .. math.floor(free / 1000) .. " KB free, needs " .. math.floor(need / 1000) .. " KB)."
      return
    end
    local url = e.url or (base() .. e.file)
    local data, err = get(url)
    if not data then store.text = "Download failed (" .. tostring(err) .. ")." return end
    if e.size and #data ~= e.size then store.text = "Refused: wrong size." return end
    store.text, store.frac = "Checking " .. e.name .. "...", 0.6
    if e.sha256 and hashBig(data) ~= e.sha256 then store.text = "Refused: the file does not match its hash." return end
    local dir = fs.getDir(dest)
    if not fs.exists(dir) then fs.makeDir(dir) end
    local tmp = dest .. ".new"
    local h = fs.open(tmp, "wb")
    if not h then store.text = "Could not save the file." return end
    h.write(data)
    h.close()
    if fs.exists(dest) then fs.delete(dest) end
    fs.move(tmp, dest)
    store.text, store.frac = "Saved " .. dest, 1
  end, function(ok, err)
    store.state, store.busy = "ready", nil
    if not ok then store.text = "Install failed: " .. tostring(err) end
  end)
  return true
end

return U
