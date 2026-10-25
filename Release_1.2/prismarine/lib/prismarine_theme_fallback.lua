--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/lib/prismarine_theme_fallback.lua
-- For apps that also run outside Prismarine. Same shape as prismarine.theme,
-- with the default Ocean colors and no change events.
--   local T = prismarine and prismarine.theme or require("prismarine_theme_fallback")
local roles = { "bg", "panel", "hdr", "text", "dim", "line", "sel", "selText", "bar", "barBtn",
  "barOn", "barText", "ok", "warn", "err", "info", "accent", "hint" }
local c = {
  bg = colors.black, panel = colors.black, hdr = colors.blue, text = colors.white,
  dim = colors.lightGray, line = colors.cyan, sel = colors.lightBlue, selText = colors.black,
  bar = colors.gray, barBtn = colors.blue, barOn = colors.cyan, barText = colors.white,
  ok = colors.lime, warn = colors.yellow, err = colors.red, info = colors.cyan,
  accent = colors.orange, hint = colors.lightGray,
}
local T = { name = "Ocean", version = 1, live = false, roles = roles, colors = c }
function T.apply(win)
  win = win or term.current()
  win.setBackgroundColor(c.bg)
  win.setTextColor(c.text)
  win.clear()
  win.setCursorPos(1, 1)
end
function T.get()
  local copy = {}
  for k, v in pairs(c) do copy[k] = v end
  return { name = T.name, version = T.version, live = false, colors = copy }
end
return T
