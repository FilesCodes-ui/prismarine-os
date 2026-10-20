-- Sandbox probe. Each line should say PASS. Any FAIL is a sandbox hole.
-- Non-destructive: only reads and copies; it cleans up after itself.
local function check(label, ok)
  term.setTextColor(ok and colors.lime or colors.red)
  write(ok and "PASS " or "FAIL ")
  term.setTextColor(colors.white)
  print(label)
end

check("settings file hidden", fs.exists(".simpleos_settings") == false)
check("settings file unreadable", fs.open(".simpleos_settings", "r") == nil)
check("startup hidden", fs.exists("startup.lua") == false)
check("kernel dir hidden", fs.exists("prismarine/kernel") == false)

local copied = pcall(fs.copy, "prismarine", "probe_tmp")
if fs.exists("probe_tmp") then pcall(fs.delete, "probe_tmp") end
check("cannot copy parent of protected dir", copied == false)

local listing = fs.list("prismarine")
local sees = false
for _, n in ipairs(listing) do if n == "kernel" then sees = true end end
check("fs.list hides kernel dir", sees == false)

check("no modem access", peripheral.find("modem") == nil)
check("no rednet", rednet == nil)
check("no getfenv/setfenv/debug", getfenv == nil and setfenv == nil and debug == nil)
check("no shell/os.run", shell == nil and os.run == nil)
check("no os.shutdown", os.shutdown == nil and os.reboot == nil)

local f = load("return fs")()
check("load() defaults to sandbox env", f == fs)

local mt = getmetatable("")
mt.__index.probeflag = 1
check("string table not shared", ("").probeflag == nil)

check("cannot fake rednet_message", pcall(os.queueEvent, "rednet_message") == false)

print("")
print("Press q to close.")
while true do
  local _, c = os.pullEvent("char")
  if c == "q" then return end
end
