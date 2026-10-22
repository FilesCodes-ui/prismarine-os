--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
local sh = dofile("/prismarine/apps/shellapi.lua").new()
local env = setmetatable({ shell = sh }, { __index = _ENV or _G })
sh.setEnv(_ENV or _G)
local ok, err = pcall(os.run, env, "/prismarine/apps/shellv2.lua")
if not ok then
  term.setBackgroundColor(colors.black) term.setTextColor(colors.red) term.clear() term.setCursorPos(1,1)
  print(tostring(err))
  os.sleep(10)
end
