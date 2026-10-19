-- Prismarine v23 stage 2 test launcher. Run: ui_test
-- Mouse: click [= Apps], [v Active: ...] and [H] on the top bar.
-- Keys:  Left Alt = Apps menu, Right Alt = switcher, Up/Down/Enter/Backspace in menus.
--        F12 quits.
local K = dofile("/prismarine/kernel/kernel.lua")
local UI = dofile("/prismarine/ui/ui.lua")

local native = term.native()
local TESTS = "/prismarine/tests/"

local function paintDashboard()
  local w, h = native.getSize()
  native.setBackgroundColor(colors.black)
  native.setTextColor(colors.cyan)
  for y = 2, h do
    native.setCursorPos(1, y)
    native.clearLine()
  end
  native.setCursorPos(2, 3)
  native.write("DASHBOARD - no app focused")
  native.setCursorBlink(false)
end

local apps = {
  { name = "Counter", path = TESTS .. "counter.lua" },
  { name = "Toaster", path = TESTS .. "toaster.lua", class = "service" },
  { name = "Crasher", path = TESTS .. "crasher.lua" },
  { name = "Spinner", path = TESTS .. "spinner.lua" },
  { name = "Probe", path = TESTS .. "probe.lua" },
  { name = "Test service", path = TESTS .. "svc.lua", class = "service", pinned = true },
}

local ui = UI.create(K, { apps = apps, paintDashboard = paintDashboard })
local hooks = ui.hooks
local baseEvent = hooks.onEvent
hooks.onEvent = function(ev)
  if ev[1] == "key" and ev[2] == keys.f12 then
    K.stop()
    return true
  end
  return baseEvent(ev)
end

K.run(hooks)

native.setBackgroundColor(colors.black)
native.setTextColor(colors.white)
native.clear()
native.setCursorPos(1, 1)
native.setCursorBlink(true)
print("Kernel stopped. Last kernel error: " .. tostring(K.lastError))
