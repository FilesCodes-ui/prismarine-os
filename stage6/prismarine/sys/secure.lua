-- /prismarine/sys/secure.lua
-- Prismarine OS v23: password, keys at rest, and system file checks.
--
-- Everything here lives in /prismarine/secure, a folder no app can see.
--   auth      salt, password check value, failed tries, lock-out time
--   identity  this computer's public keys, and its secret keys sealed with
--             a key made from the password (so a copied disk is useless)
--   manifest  SHA-256 of every system file, sealed with the password key so
--             nobody can forge it without the password
--
-- Kernel code only.

local DIR = "/prismarine/secure/"
local S = {}

local C -- crypto, set by S.init

local function readTable(name)
  local h = fs.open(DIR .. name, "r")
  if not h then return nil end
  local s = h.readAll()
  h.close()
  local ok, t = pcall(textutils.unserialize, s)
  if ok and type(t) == "table" then return t end
  return nil
end

local function writeTable(name, t)
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  local tmp = DIR .. name .. ".new"
  local h = fs.open(tmp, "w")
  if not h then return false end
  h.write(textutils.serialize(t))
  h.close()
  if fs.exists(DIR .. name) then fs.delete(DIR .. name) end
  fs.move(tmp, DIR .. name)
  return true
end
S.readTable, S.writeTable = readTable, writeTable

function S.init(crypto)
  C = crypto
end

-- ------------------------------------------------------------- password

S.MIN_PASSWORD = 6
local kek = nil          -- key made from the password, only after login
local identity = nil     -- secret keys, only after login

local function subkey(label)
  return C.kdf("prismarine v1 " .. label)(kek)
end

-- A real password exists (not the device-key "open" mode).
function S.hasPassword()
  local a = readTable("auth")
  return a ~= nil and type(a.salt) == "string" and type(a.check) == "string"
end

-- Open mode: no password. A random key kept on this computer seals the secrets.
-- That only hides them from casual reading. Anyone holding the disk can read the key.
function S.isOpen()
  local a = readTable("auth")
  return a ~= nil and a.open == true and type(a.dkey) == "string"
end

function S.isSetUp() return S.hasPassword() or S.isOpen() end

function S.unlocked() return kek ~= nil end

-- Seconds until another try is allowed (0 when allowed now).
function S.lockoutLeft()
  local a = readTable("auth")
  if not a or not a.lockUntil then return 0 end
  local left = (a.lockUntil - os.epoch("utc")) / 1000
  if left < 0 then return 0 end
  return math.ceil(left)
end

function S.failedTries()
  local a = readTable("auth")
  return a and a.fails or 0
end

-- First run: choose the password. Makes the identity keys too.
function S.setup(password, progress)
  assert(not S.hasPassword(), "already set up")
  assert(#password >= S.MIN_PASSWORD, "password too short")
  local salt = C.bytes(16)
  kek = C.passwordKey(password, salt, nil, progress)
  local auth = {
    v = 1, salt = C.hex(salt), rounds = C.PBKDF_ROUNDS,
    check = C.hex(C.mac(kek, "prismarine auth check v1")), fails = 0,
  }
  identity = C.newIdentity()
  writeTable("auth", auth)
  S.saveIdentity()
  return true
end

-- First run, no password. Makes the device key and the identity keys.
function S.setupOpen()
  assert(not S.isSetUp(), "already set up")
  kek = C.bytes(32)
  writeTable("auth", { v = 1, open = true, dkey = C.hex(kek), fails = 0 })
  identity = C.newIdentity()
  S.saveIdentity()
  return true
end

local function loadIdentity()
  local id = readTable("identity")
  if id then
    local plain = C.open(subkey("identity"), C.unhex(id.box), C.unhex(id.ipk))
    local keys = plain and C.decode(plain)
    if not keys then return false end
    identity = { isk = keys.isk, xsk = keys.xsk, ipk = C.unhex(id.ipk), xpk = C.unhex(id.xpk) }
  else
    identity = C.newIdentity()
    S.saveIdentity()
  end
  return true
end

-- Open mode start. Returns true, or false and a reason.
function S.autoLogin()
  local a = readTable("auth")
  if not (a and a.open and type(a.dkey) == "string") then return false, "not open" end
  kek = C.unhex(a.dkey)
  if not loadIdentity() then kek = nil return false, "damaged" end
  return true
end

function S.saveIdentity()
  local box = C.seal(subkey("identity"), C.encode({ isk = identity.isk, xsk = identity.xsk }), identity.ipk)
  writeTable("identity", { v = 1, ipk = C.hex(identity.ipk), xpk = C.hex(identity.xpk), box = C.hex(box) })
end

-- Returns true, or false and a reason.
function S.login(password, progress)
  local a = readTable("auth")
  if not a then return false, "not set up" end
  if S.lockoutLeft() > 0 then return false, "locked", S.lockoutLeft() end
  local key = C.passwordKey(password, C.unhex(a.salt), a.rounds, progress)
  if not C.same(C.mac(key, "prismarine auth check v1"), C.unhex(a.check)) then
    a.fails = (a.fails or 0) + 1
    if a.fails >= 5 then
      local wait = math.min(3600, 30 * 2 ^ (a.fails - 5))
      a.lockUntil = os.epoch("utc") + wait * 1000
    end
    writeTable("auth", a)
    return false, "wrong", a.fails
  end
  a.fails, a.lockUntil = 0, nil
  writeTable("auth", a)
  kek = key
  if not loadIdentity() then
    kek = nil
    return false, "damaged"
  end
  return true
end

-- Checks a password without changing anything (lock screen, risky settings).
function S.checkPassword(password, progress)
  local a = readTable("auth")
  if not a then return false end
  if a.open then return true end
  if S.lockoutLeft() > 0 then return false, "locked", S.lockoutLeft() end
  local key = C.passwordKey(password, C.unhex(a.salt), a.rounds, progress)
  if C.same(C.mac(key, "prismarine auth check v1"), C.unhex(a.check)) then
    if (a.fails or 0) > 0 then
      a.fails, a.lockUntil = 0, nil
      writeTable("auth", a)
    end
    return true
  end
  a.fails = (a.fails or 0) + 1
  if a.fails >= 5 then
    a.lockUntil = os.epoch("utc") + math.min(3600, 30 * 2 ^ (a.fails - 5)) * 1000
  end
  writeTable("auth", a)
  return false, "wrong", a.fails
end

function S.changePassword(old, new, progress)
  if S.isOpen() then return false, "open" end
  if #new < S.MIN_PASSWORD then return false, "too short" end
  local ok, why = S.checkPassword(old, progress)
  if not ok then return false, why end
  local salt = C.bytes(16)
  local oldKek = kek
  kek = C.passwordKey(new, salt, nil, progress)
  local a = readTable("auth")
  a.salt, a.rounds = C.hex(salt), C.PBKDF_ROUNDS
  a.check = C.hex(C.mac(kek, "prismarine auth check v1"))
  writeTable("auth", a)
  S.saveIdentity()
  -- Anything else sealed with the old key is sealed again.
  for _, fn in ipairs(S.rekeyHooks) do pcall(fn, oldKek, kek) end
  S.sealManifest(S.lastHashes or {})
  return true
end
S.rekeyHooks = {}

-- Open mode to password mode.
function S.enablePassword(new, progress)
  if not S.isOpen() then return false, "has password" end
  if type(new) ~= "string" or #new < S.MIN_PASSWORD then return false, "too short" end
  local salt = C.bytes(16)
  local oldKek = kek
  kek = C.passwordKey(new, salt, nil, progress)
  writeTable("auth", {
    v = 1, salt = C.hex(salt), rounds = C.PBKDF_ROUNDS,
    check = C.hex(C.mac(kek, "prismarine auth check v1")), fails = 0,
  })
  S.saveIdentity()
  for _, fn in ipairs(S.rekeyHooks) do pcall(fn, oldKek, kek) end
  S.sealManifest(S.lastHashes or {})
  return true
end

-- Password mode to open mode. Needs the current password.
function S.disablePassword(old, progress)
  if not S.hasPassword() then return false, "open" end
  local ok, why = S.checkPassword(old, progress)
  if not ok then return false, why end
  local oldKek = kek
  kek = C.bytes(32)
  writeTable("auth", { v = 1, open = true, dkey = C.hex(kek), fails = 0 })
  S.saveIdentity()
  for _, fn in ipairs(S.rekeyHooks) do pcall(fn, oldKek, kek) end
  S.sealManifest(S.lastHashes or {})
  return true
end

-- The secret keys. Kernel only.
function S.identity() return identity end
function S.publicIdentity()
  local id = readTable("identity")
  if not id then return nil end
  return { ipk = C.unhex(id.ipk), xpk = C.unhex(id.xpk) }
end

-- A key for a named purpose, made from the password key. Kernel only.
function S.key(label)
  assert(kek, "locked")
  return subkey(label)
end

-- Seal and open small tables with a password-derived key.
function S.sealTable(label, t)
  return C.hex(C.seal(subkey(label), C.encode(t), label))
end
function S.openTable(label, hex)
  if type(hex) ~= "string" then return nil end
  local plain = C.open(subkey(label), C.unhex(hex), label)
  return plain and C.decode(plain)
end

-- Erase every secret on this computer. Used by "Reset this computer".
function S.wipe()
  kek, identity = nil, nil
  if fs.exists(DIR) then fs.delete(DIR) end
end

-- ------------------------------------------------------------- system files

-- Every file the OS runs. Apps and user data are not part of it.
S.SYSTEM = { "startup.lua", "prismarine/boot.lua" }
S.SYSTEM_DIRS = { "prismarine/kernel", "prismarine/sys", "prismarine/ui", "prismarine/lib", "prismarine/apps" }

function S.systemFiles()
  local out = {}
  for _, p in ipairs(S.SYSTEM) do
    if fs.exists(p) then out[#out + 1] = p end
  end
  local function walk(dir)
    if not fs.isDir(dir) then return end
    local names = fs.list(dir)
    table.sort(names)
    for _, n in ipairs(names) do
      local p = fs.combine(dir, n)
      if fs.isDir(p) then walk(p) else out[#out + 1] = p end
    end
  end
  for _, d in ipairs(S.SYSTEM_DIRS) do walk(d) end
  return out
end

-- Hashes every system file. tick(i, n, path) reports progress.
function S.hashSystem(tick)
  local files = S.systemFiles()
  local hashes = {}
  for i, p in ipairs(files) do
    hashes[p] = C.hashFile(p)
    if tick then tick(i, #files, p) end
    if i % 4 == 0 then
      os.queueEvent("prismarine_hash_yield")
      os.pullEventRaw("prismarine_hash_yield")
    end
  end
  S.lastHashes = hashes
  return hashes
end

function S.sealManifest(hashes)
  if not kek then return false end
  writeTable("manifest", { v = 1, at = os.epoch("utc"), box = S.sealTable("manifest", hashes) })
  return true
end

-- After login. Returns "new" (no manifest yet), "ok", or "changed" plus a list
-- of { path, what } where what is "changed", "added" or "removed".
-- A manifest that does not open (forged or damaged) counts as all changed.
function S.compareManifest(hashes)
  local m = readTable("manifest")
  if not m then return "new", {} end
  local old = S.openTable("manifest", m.box)
  local diff = {}
  if not old then
    for p in pairs(hashes) do diff[#diff + 1] = { path = p, what = "unverified" } end
    table.sort(diff, function(a, b) return a.path < b.path end)
    return "forged", diff
  end
  for p, h in pairs(hashes) do
    if old[p] == nil then diff[#diff + 1] = { path = p, what = "added" }
    elseif old[p] ~= h then diff[#diff + 1] = { path = p, what = "changed" } end
  end
  for p in pairs(old) do
    if hashes[p] == nil then diff[#diff + 1] = { path = p, what = "removed" } end
  end
  table.sort(diff, function(a, b) return a.path < b.path end)
  return (#diff == 0) and "ok" or "changed", diff
end

return S
