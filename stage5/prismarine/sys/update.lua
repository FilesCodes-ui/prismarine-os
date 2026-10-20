-- /prismarine/sys/update.lua
-- Prismarine OS v23: update check and install.
--
-- The release manifest (manifest.txt in the repo folder) lists every file with
-- its SHA-256. A check compares it with the files on this computer. An install
-- downloads each changed file, checks its hash, and only then replaces the old
-- one. The password is needed to install. The sealed system file check is
-- renewed afterward, so the next boot has no warning.
--
-- Kernel code only.

local U = {}

local K, C, S
local DEFAULT_BASE = "https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage5/"
local INSTALL = "/prismarine/data/install.json"
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

local function parseManifest(data)
  local ok, t = pcall(textutils.unserialise, data)
  if not ok or type(t) ~= "table" or type(t.files) ~= "table" or type(t.version) ~= "string" then return nil end
  for p, h in pairs(t.files) do
    if type(p) ~= "string" or type(h) ~= "string" or #h ~= 64 or p:find("%.%.") or p:sub(1, 1) == "/" then return nil end
    if not (p == "startup.lua" or p:sub(1, 10) == "prismarine") then return nil end
  end
  return t
end

function U.status() return state end

-- Compare the release manifest with this computer. Runs as a kernel task.
function U.check(done)
  if state.state == "checking" or state.state == "installing" then return end
  state.state, state.text = "checking", "Checking for updates..."
  K.task(function()
    local data, err = get(base() .. "manifest.txt")
    if not data then
      state.state, state.text = "error", "Could not reach the update server (" .. tostring(err) .. ")."
      return
    end
    local m = parseManifest(data)
    if not m then
      state.state, state.text = "error", "The update list is damaged."
      return
    end
    local have = S.lastHashes or S.hashSystem()
    local changed = {}
    for p, h in pairs(m.files) do
      if have[p] ~= h then changed[#changed + 1] = p end
    end
    table.sort(changed)
    state.manifest, state.version, state.at = m, m.version, os.epoch("utc")
    state.changed = changed
    if #changed == 0 then
      state.state, state.text = "current", "You are up to date (" .. m.version .. ")."
    else
      state.state, state.text = "available", #changed .. " files differ. Version " .. m.version .. "." .. (#changed <= 3 and (" " .. table.concat(changed, ", ")) or "")
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
    local staged = {}
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
      if C.sha256hex(data) ~= m.files[p] then
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
    end
    state.text = "Installing..."
    for _, tmp in ipairs(staged) do
      local final = tmp:sub(1, -5)
      if fs.exists(final) then fs.delete(final) end
      fs.move(tmp, final)
    end
    -- Files the release no longer lists are removed from system folders.
    for _, p in ipairs(S.systemFiles()) do
      if m.files[p] == nil and p:sub(1, 21) ~= "prismarine/lib/pixelb" then
        pcall(fs.delete, p)
      end
    end
    local hashes = S.hashSystem()
    S.sealManifest(hashes)
    state.state, state.text, state.frac = "done", "Updated to " .. m.version .. ". Reboot to use it.", 1
    state.changed = {}
  end, function(ok, err)
    if not ok then state.state, state.text = "available", "Install failed: " .. tostring(err) end
    if done then pcall(done, state) end
  end)
  return true
end

return U
