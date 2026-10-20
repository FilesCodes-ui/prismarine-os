-- Prismarine OS v24 stage 6 installer.
-- Run: wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/full/stage6/setup.lua
--
-- It downloads manifest.txt, then every file in it, and checks each file's
-- SHA-256 before saving. Pixelbox_lite (MIT, 9551-Dev) comes from a pinned
-- commit and is hash checked too. Then it installs startup.lua, so the
-- computer boots Prismarine instead of the CraftOS shell.
-- An old startup.lua is saved as startup.lua.bak first.
local base = "https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/full/stage6/"
local PB_URL = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/82098c8dca939b7689f119d0a577c311d4a09281/pixelbox_lite.lua"
local PB_PATH = "/prismarine/lib/pixelbox_lite.lua"
local PB_HASH = "e9923dc24ed6d968de668f42a3c324d0957778a709d93bc9190617c32889de99"

if not http then error("HTTP is disabled on this server.", 0) end

local function get(url)
  local r = http.get(url .. "?cb=" .. os.epoch("utc"), nil, true)
  if not r then return nil end
  local body = r.readAll()
  r.close()
  return body
end

local function save(path, body)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "wb")
  f.write(body)
  f.close()
end

-- SHA-256 for the checks. It is fetched first, then used on everything else.
local manifestText = get(base .. "manifest.txt")
if not manifestText then error("Could not download manifest.txt", 0) end
local manifest = textutils.unserialise(manifestText)
if type(manifest) ~= "table" or type(manifest.files) ~= "table" then error("manifest.txt is damaged", 0) end

local shaText = get(base .. "prismarine/lib/sha256.lua")
if not shaText then error("Could not download sha256.lua", 0) end
local sha = load(shaText, "@sha256", "t", _ENV)()

local names = {}
for p in pairs(manifest.files) do names[#names + 1] = p end
table.sort(names)

-- Download everything to a staging name first. Nothing is replaced until
-- every file has passed its check.
local staged = {}
for i, p in ipairs(names) do
  write(("%d/%d %s ... "):format(i, #names, p))
  local body = get(base .. p)
  if not body then
    for _, s in ipairs(staged) do fs.delete(s) end
    print("FAILED")
    error("Download failed: " .. p, 0)
  end
  if sha(body) ~= manifest.files[p] then
    for _, s in ipairs(staged) do fs.delete(s) end
    print("HASH MISMATCH")
    error("Refused: " .. p .. " does not match the release list.", 0)
  end
  save("/" .. p .. ".new", body)
  staged[#staged + 1] = "/" .. p .. ".new"
  print("ok")
end

-- Pixelbox, hash checked
write("pixelbox_lite.lua ... ")
local pbOk = false
local pb = get(PB_URL)
if pb then
  if sha(pb) == PB_HASH then
    save(PB_PATH, pb)
    pbOk = true
    print("ok (hash matches)")
  else
    print("HASH MISMATCH, not saved")
  end
else
  print("FAILED")
end
if not pbOk then
  if fs.exists(PB_PATH) then fs.delete(PB_PATH) end
  print("The UI will use plain text mode.")
end

-- Swap in. The old startup is kept the first time.
if fs.exists("/startup.lua") then
  local h = fs.open("/startup.lua", "r")
  local old = h.readAll()
  h.close()
  if old:sub(1, 21) ~= "-- prismarine-boot-v1" then
    if fs.exists("/startup.lua.bak") then fs.delete("/startup.lua.bak") end
    fs.copy("/startup.lua", "/startup.lua.bak")
    print("old startup saved as startup.lua.bak")
  end
end
for _, tmp in ipairs(staged) do
  local final = tmp:sub(1, -5)
  if fs.exists(final) then fs.delete(final) end
  fs.move(tmp, final)
end

-- Remember where updates come from.
save("/prismarine/data/install.json", textutils.serialiseJSON({ base = base, version = manifest.version }))

print()
print("Installed " .. tostring(manifest.version) .. ".")
print("Reboot to start Prismarine. You will choose a password.")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
