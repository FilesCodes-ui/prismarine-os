--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- prismarine-boot-v1
-- Prismarine OS startup. This replaces the CraftOS shell and multishell.
-- Prismarine runs its own kernel. If it fails to start, this file shows the
-- error and offers Recovery, which needs your password.
local native = term.native()

local function reset()
  term.redirect(native)
  for i = 0, 15 do
    local r, g, b = term.nativePaletteColor(2 ^ i)
    native.setPaletteColor(2 ^ i, r, g, b)
  end
  native.setBackgroundColor(colors.black)
  native.setTextColor(colors.white)
  native.clear()
  native.setCursorPos(1, 1)
  native.setCursorBlink(false)
end

local function readPassword()
  local pw = ""
  while true do
    native.setCursorPos(1, select(2, native.getCursorPos()))
    native.clearLine()
    native.write("Password: " .. string.rep("*", #pw))
    native.setCursorBlink(true)
    local ev, a = os.pullEventRaw()
    if ev == "char" then pw = pw .. a
    elseif ev == "key" and a == keys.backspace then pw = pw:sub(1, -2)
    elseif ev == "key" and a == keys.enter then print() return pw end
  end
end

-- Recovery: the normal shell, but only for the owner.
local function recovery()
  local ok, C = pcall(dofile, "/prismarine/sys/crypto.lua")
  local ok2, S = pcall(dofile, "/prismarine/sys/secure.lua")
  if not (ok and ok2) then
    print("Security code is damaged. Opening the shell.")
    return true
  end
  S.init(C)
  C.initRandom(false)
  if not S.hasPassword() then return true end
  for _ = 1, 3 do
    if S.lockoutLeft() > 0 then
      print("Locked. Wait " .. S.lockoutLeft() .. " seconds.")
      return false
    end
    local good = S.checkPassword(readPassword())
    if good then return true end
    print("Wrong password.")
  end
  return false
end

while true do
  local ok, err = pcall(dofile, "/prismarine/boot.lua")
  reset()
  if ok then
    print("Prismarine stopped. Press R to restart, S for Recovery.")
  else
    term.setTextColor(colors.red)
    print("Prismarine stopped with an error:")
    native.setTextColor(colors.white)
    print(tostring(err))
    print()
    print("R: restart   S: Recovery (password needed)")
  end
  local choice
  while not choice do
    local ev, a = os.pullEventRaw()
    if ev == "key" and a == keys.r then choice = "restart"
    elseif ev == "key" and a == keys.s then choice = "recovery" end
  end
  if choice == "recovery" then
    reset()
    if recovery() then
      print("Recovery shell. Type exit to go back.")
      shell.run("shell")
    end
  else
    os.reboot()
  end
end
