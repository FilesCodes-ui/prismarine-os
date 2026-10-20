-- Test app: counts once a second. Press q to quit.
-- Switch away and back: it should resume (frozen apps buffer their own timer).
local n = 0
local id = os.startTimer(1)

local function draw()
  term.clear()
  term.setCursorPos(1, 1)
  print("COUNTER app: " .. n)
  print("Type letters. q quits.")
  term.setCursorBlink(true)
end

draw()
while true do
  local ev, a = os.pullEvent()
  if ev == "timer" and a == id then
    n = n + 1
    id = os.startTimer(1)
    draw()
  elseif ev == "char" then
    print("char: " .. a)
    if a == "q" then return end
  end
end
