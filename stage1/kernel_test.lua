-- /kernel_test.lua
-- Prismarine OS v23, stage 1 dev harness.
-- TEMPORARY: stage 2 replaces this with the real top bar, menus and cabinet.
-- Run it from the normal CraftOS shell:  kernel_test
-- F12 quits (Ctrl+T is deliberately ignored while the kernel runs).

local K = dofile("/prismarine/kernel/kernel.lua")
local native = term.native()
local status = ""
local TESTS = "/prismarine/tests/"

local function launch(name, file, class)
  class = class or "app"
  local pid, err = K.spawn({ name = name, path = TESTS .. file, class = class })
  if not pid then
    status = tostring(err)
    return
  end
  if class == "app" then K.focus(pid) end
end

local function cycle()
  local list = K.list()
  if #list == 0 then return end
  local cur, idx = K.getFocus(), 0
  for i, p in ipairs(list) do
    if p.pid == cur then idx = i end
  end
  K.focus(list[idx % #list + 1].pid)
end

local function paintDashboard()
  local _, h = native.getSize()
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

local function draw()
  local w = native.getSize()
  native.setBackgroundColor(colors.gray)
  native.setTextColor(colors.white)
  native.setCursorPos(1, 1)
  native.clearLine()
  local parts = {}
  for _, p in ipairs(K.list()) do
    local flag = ""
    if not p.alive then flag = (p.exitKind == "crashed") and "!" or "x" end
    if p.restartIn then flag = flag .. "(" .. math.ceil(p.restartIn) .. "s)" end
    parts[#parts + 1] = (p.focused and ">" or "") .. p.pid .. ":" .. p.name .. flag
  end
  local line = table.concat(parts, " ")
  if line == "" then
    line = "F1 cnt F2 spin F3 crash F4 stop F5 next F6 home F7 svc F8 probe F9 retry F12 quit"
  end
  if status ~= "" then line = line .. " | " .. status end
  if K.lastError then line = line .. " | KERNEL: " .. K.lastError end
  native.write(line:sub(1, w))
  K.restoreCursor()
end

local function onEvent(ev)
  if ev[1] ~= "key" then return false end
  local k = ev[2]
  if k == keys.f1 then launch("counter", "counter.lua")
  elseif k == keys.f2 then launch("spinner", "spinner.lua")
  elseif k == keys.f3 then launch("crasher", "crasher.lua")
  elseif k == keys.f4 then
    local pid = K.getFocus()
    if pid then
      local ok, err = K.kill(pid)
      if not ok then status = tostring(err) end
    end
  elseif k == keys.f5 then cycle()
  elseif k == keys.f6 then K.focus(nil)
  elseif k == keys.f7 then launch("svc", "svc.lua", "service")
  elseif k == keys.f8 then launch("probe", "probe.lua")
  elseif k == keys.f9 then
    local pid = K.getFocus()
    if pid and not K.restart(pid) then K.dismiss(pid) end
  elseif k == keys.f12 then K.stop()
  else
    return false -- not a dev key: pass it to the focused app
  end
  return true
end

K.run({
  onStart = function() paintDashboard() draw() end,
  onEvent = onEvent,
  onTick = draw,
  onFocus = function(pid)
    if pid == nil then paintDashboard() end
  end,
  onExit = function(p, kind, err)
    status = p.name .. " " .. kind .. (err and (": " .. err:sub(1, 30)) or "")
  end,
  onServiceDown = function(p, delay)
    status = p.name .. " restarting in " .. math.ceil(delay) .. "s"
  end,
})

native.setBackgroundColor(colors.black)
native.setTextColor(colors.white)
native.clear()
native.setCursorPos(1, 1)
print("Kernel stopped. Last kernel error: " .. tostring(K.lastError))
