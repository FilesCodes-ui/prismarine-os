-- /prismarine/sys/crypto.lua
-- Prismarine OS v23: the one place that touches cryptography.
-- Wraps ccryptolib (MIT, Miguel Oliveira, vendored in /prismarine/lib/ccryptolib)
-- and adds the helpers the OS needs: random bytes, hashing, password keys,
-- signing keys, sealed boxes and authenticated encryption.
--
-- Kernel code only. Apps never get this table; they get narrow APIs instead.

local LIB = "/prismarine/lib/ccryptolib/"
local SEED = "/prismarine/secure/seed"

local C = {}
local mods = {}

-- A tiny require for the vendored library. cc.expect comes from the ROM.
local function req(name)
  if mods[name] then return mods[name] end
  local path
  if name == "cc.expect" then
    path = "/rom/modules/main/cc/expect.lua"
  elseif name:sub(1, 11) == "ccryptolib." then
    path = LIB .. name:sub(12):gsub("%.", "/") .. ".lua"
  else
    error("crypto: unknown module " .. name, 2)
  end
  local h = fs.open(path, "r")
  if not h then error("crypto: missing " .. path, 0) end
  local src = h.readAll()
  h.close()
  local env = setmetatable({ require = req }, { __index = _G })
  local fn, err = load(src, "@" .. path, "t", env)
  if not fn then error(err, 0) end
  local m = fn()
  mods[name] = m
  return m
end

local config = req("ccryptolib.config")
-- No peripheral offload: the OS never trusts a block to do its crypto.
config.usePeripherals(false)

local random = req("ccryptolib.random")
local sha256 = req("ccryptolib.sha256")
local blake3 = req("ccryptolib.blake3")
local aead = req("ccryptolib.aead")
local ed = req("ccryptolib.ed25519")
local x25519 = req("ccryptolib.x25519")
local util = req("ccryptolib.util")

C.lib = { random = random, sha256 = sha256, blake3 = blake3, aead = aead, ed25519 = ed, x25519 = x25519 }

-- ------------------------------------------------------------- randomness
-- Seeded from VM timing noise (512 ms), the clock, and a seed file that is
-- rewritten every boot, so a computer never starts from the same state twice.

local function readFile(path)
  local h = fs.open(path, "rb")
  if not h then return nil end
  local s = h.readAll()
  h.close()
  return s
end

local function writeFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "wb")
  if not h then return false end
  h.write(data)
  h.close()
  return true
end
C.readFile, C.writeFile = readFile, writeFile

function C.initRandom(timing)
  local old = readFile(SEED) or ""
  local parts = {
    old, tostring(os.epoch("utc")), tostring(os.clock()), tostring(os.getComputerID()),
    tostring({}), tostring(math.random()),
  }
  random.init(table.concat(parts, "|"))
  if timing ~= false then
    local ok = pcall(random.initWithTiming)
    if not ok then random.mix(tostring(os.epoch("utc")) .. tostring({})) end
  end
  writeFile(SEED, random.random(32))
end

function C.mix(data) random.mix(tostring(data)) end
function C.bytes(n) return random.random(n) end

-- ------------------------------------------------------------- encodings

function C.hex(s) return util.toHex(s) end
function C.unhex(h) return util.fromHex(h) end
function C.same(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
  return util.compare(a, b)
end

-- Base32 style groups for fingerprints a person compares by eye.
local B32 = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
function C.fingerprint(data, groups)
  groups = groups or 4
  local h = blake3.digest("prismarine fingerprint v1" .. data, 16)
  local bits, nbits, out = 0, 0, {}
  for i = 1, #h do
    bits = bits * 256 + h:byte(i)
    nbits = nbits + 8
    while nbits >= 5 do
      nbits = nbits - 5
      local v = math.floor(bits / 2 ^ nbits) % 32
      out[#out + 1] = B32:sub(v + 1, v + 1)
      bits = bits % (2 ^ nbits)
    end
    if #out >= groups * 4 then break end
  end
  local g = {}
  for i = 1, groups do g[i] = table.concat(out, "", (i - 1) * 4 + 1, i * 4) end
  return table.concat(g, "-")
end

-- ------------------------------------------------------------- hashing

function C.sha256(data) return sha256.digest(data) end
function C.sha256hex(data) return util.toHex(sha256.digest(data)) end
function C.hash(data, len) return blake3.digest(data, len) end
function C.mac(key, data) return blake3.digestKeyed(key, data) end
function C.kdf(context) return blake3.deriveKey(context) end

-- Hash a file in pieces, yielding now and then so big files never time out.
function C.hashFile(path)
  local data = readFile(path)
  if not data then return nil end
  return util.toHex(sha256.digest(data))
end

-- Password to key: PBKDF2-HMAC-SHA256. progress(i) is called every 50 rounds.
C.PBKDF_ROUNDS = 10000
function C.passwordKey(password, salt, rounds, progress)
  local n = 0
  local function tick(i)
    n = n + 1
    if n % 20 == 0 then
      os.queueEvent("prismarine_crypto_yield")
      os.pullEventRaw("prismarine_crypto_yield")
    end
    if progress then progress(i) end
  end
  return sha256.pbkdf2(password, salt, rounds or C.PBKDF_ROUNDS, tick)
end

-- ------------------------------------------------------------- keys

-- A signing key (Ed25519) plus an exchange key (X25519).
function C.newIdentity()
  local isk = random.random(32)
  local xsk = random.random(32)
  return {
    isk = isk, ipk = ed.publicKey(isk),
    xsk = xsk, xpk = x25519.publicKey(xsk),
  }
end

function C.publicOf(id)
  return { ipk = id.ipk, xpk = id.xpk }
end

function C.sign(id, msg) return ed.sign(id.isk, id.ipk, msg) end
function C.verify(ipk, msg, sig)
  if type(ipk) ~= "string" or #ipk ~= 32 or type(sig) ~= "string" or #sig ~= 64 or type(msg) ~= "string" then
    return false
  end
  local ok, res = pcall(ed.verify, ipk, msg, sig)
  return ok and res == true
end

-- ------------------------------------------------------------- encryption

-- Authenticated encryption. Returns nonce .. ciphertext .. tag.
function C.seal(key, plain, aad)
  local nonce = random.random(12)
  local ct, tag = aead.encrypt(key, nonce, plain, aad or "")
  return nonce .. ct .. tag
end

function C.open(key, box, aad)
  if type(box) ~= "string" or #box < 28 then return nil end
  local nonce, ct, tag = box:sub(1, 12), box:sub(13, -17), box:sub(-16)
  local ok, plain = pcall(aead.decrypt, key, nonce, tag, ct, aad or "")
  if ok and plain then return plain end
  return nil
end

-- Wrap a 32-byte key for one recipient exchange key. Each wrap uses a fresh
-- ephemeral key, so only the holder of the recipient's secret can unwrap.
local wrapKdf = blake3.deriveKey("prismarine v1 key wrap")
function C.wrap(key, xpk)
  local esk = random.random(32)
  local epk = x25519.publicKey(esk)
  local shared = x25519.exchange(esk, xpk)
  local kek = wrapKdf(shared .. epk .. xpk)
  return epk .. C.seal(kek, key, epk)
end

function C.unwrap(id, wrapped)
  if type(wrapped) ~= "string" or #wrapped < 32 + 28 then return nil end
  local epk = wrapped:sub(1, 32)
  local ok, shared = pcall(x25519.exchange, id.xsk, epk)
  if not ok then return nil end
  local kek = wrapKdf(shared .. epk .. id.xpk)
  return C.open(kek, wrapped:sub(33), epk)
end

-- ------------------------------------------------------------- serialising
-- A stable byte encoding for signing: keys sorted, types tagged. Only plain
-- strings, numbers, booleans and tables of those.

local function enc(v, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then
    out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "nil" then
    out[#out + 1] = "N"
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do
      enc(k, out)
      enc(v[k], out)
    end
    out[#out + 1] = "}"
  else
    error("crypto: cannot encode " .. t, 0)
  end
end

function C.encode(v)
  local out = {}
  enc(v, out)
  return table.concat(out)
end

-- Turn a decoded byte string back into a value. Strict: anything odd fails.
function C.decode(s)
  if type(s) ~= "string" then return nil end
  local pos = 1
  local depth = 0
  local function val()
    local c = s:sub(pos, pos)
    if c == "s" then
      local colon = s:find(":", pos, true)
      if not colon then error("bad") end
      local n = tonumber(s:sub(pos + 1, colon - 1))
      if not n or n < 0 or n % 1 ~= 0 then error("bad") end
      local v = s:sub(colon + 1, colon + n)
      if #v ~= n then error("bad") end
      pos = colon + n + 1
      return v
    elseif c == "n" then
      local semi = s:find(";", pos, true)
      if not semi then error("bad") end
      local v = tonumber(s:sub(pos + 1, semi - 1))
      if not v then error("bad") end
      pos = semi + 1
      return v
    elseif c == "T" then pos = pos + 1 return true
    elseif c == "F" then pos = pos + 1 return false
    elseif c == "N" then pos = pos + 1 return nil
    elseif c == "{" then
      depth = depth + 1
      if depth > 16 then error("bad") end
      pos = pos + 1
      local t = {}
      local count = 0
      while s:sub(pos, pos) ~= "}" do
        if pos > #s then error("bad") end
        local k = val()
        local v = val()
        if k == nil then error("bad") end
        t[k] = v
        count = count + 1
        if count > 4096 then error("bad") end
      end
      pos = pos + 1
      depth = depth - 1
      return t
    end
    error("bad")
  end
  local ok, v = pcall(val)
  if not ok or pos ~= #s + 1 then return nil end
  return v
end

return C
