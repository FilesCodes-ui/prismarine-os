-- Downloads the Prismarine v23 stage 4 test files to this computer.
-- Run: wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage4/setup.lua
-- It also installs a small startup.lua so the computer boots into Prismarine.
-- An old startup.lua is saved as startup.lua.bak first.
-- Pixelbox_lite (MIT, 9551-Dev) is fetched from a pinned commit and checked
-- against a SHA-256 hash. If the check fails the file is deleted and the UI
-- runs in plain text mode.
local base = "https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage4/"
local PB_URL = "https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/82098c8dca939b7689f119d0a577c311d4a09281/pixelbox_lite.lua"
local PB_PATH = "/prismarine/lib/pixelbox_lite.lua"
local PB_HASH = "e9923dc24ed6d968de668f42a3c324d0957778a709d93bc9190617c32889de99"

local files = {
  "ui_test.lua",
  "prismarine/kernel/kernel.lua",
  "prismarine/kernel/sandbox.lua",
  "prismarine/lib/sha256.lua",
  "prismarine/ui/gfx.lua",
  "prismarine/ui/ui.lua",
  "prismarine/tests/counter.lua",
  "prismarine/tests/crasher.lua",
  "prismarine/tests/spinner.lua",
  "prismarine/tests/svc.lua",
  "prismarine/tests/probe.lua",
  "prismarine/tests/toaster.lua",
}

if not http then error("HTTP is disabled on this server.", 0) end

local function get(url)
  local r = http.get(url .. "?cb=" .. os.epoch("utc"), nil, true)
  if not r then return nil end
  local body = r.readAll()
  r.close()
  return body
end

local function save(path, body)
  local f = fs.open(path, "wb")
  f.write(body)
  f.close()
end

local total = #files + 2
for i, path in ipairs(files) do
  write(i .. "/" .. total .. " " .. path .. " ... ")
  local body = get(base .. path)
  if not body then print("FAILED") error("Download failed: " .. path, 0) end
  save(path, body)
  print("ok")
end

-- Pixelbox, hash checked
write(#files + 1 .. "/" .. total .. " pixelbox_lite.lua ... ")
local pbOk = false
local pb = get(PB_URL)
if pb then
  local sha = dofile("/prismarine/lib/sha256.lua")
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

-- boot file
write(total .. "/" .. total .. " startup.lua ... ")
local MARK = "-- prismarine-boot-v1"
local boot = MARK .. [[

-- Starts Prismarine on boot. Hold R during the first second to skip it.
-- Delete this file to boot to the normal shell.
print("Starting Prismarine. Hold R to skip.")
local timer = os.startTimer(1)
while true do
  local ev, a = os.pullEventRaw()
  if ev == "timer" and a == timer then break end
  if ev == "terminate" or (ev == "key" and a == keys.r) then
    print("Skipped.")
    return
  end
end
local ok, err = pcall(dofile, "/ui_test.lua")
local native = term.native()
term.redirect(native)
for i = 0, 15 do
  local r, g, b = term.nativePaletteColor(2 ^ i)
  native.setPaletteColor(2 ^ i, r, g, b)
end
native.setBackgroundColor(colors.black)
native.setTextColor(colors.white)
if not ok then
  native.clear()
  native.setCursorPos(1, 1)
  native.setCursorBlink(true)
  print("Prismarine stopped with an error:")
  print(tostring(err))
  print("Press any key for the shell.")
  os.pullEventRaw("key")
end
]]
local old = fs.exists("/startup.lua") and fs.open("/startup.lua", "r")
local oldText = old and old.readAll()
if old then old.close() end
if oldText and oldText:sub(1, #MARK) ~= MARK then
  if fs.exists("/startup.lua.bak") then fs.delete("/startup.lua.bak") end
  fs.copy("/startup.lua", "/startup.lua.bak")
  print("old startup saved as startup.lua.bak")
end
save("/startup.lua", boot)
print("ok")

print()
print("Done. Run: ui_test   (or reboot)")
