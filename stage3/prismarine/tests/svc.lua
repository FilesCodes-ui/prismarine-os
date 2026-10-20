-- Test service: runs in the background, crashes after 8 ticks.
-- Watch the top row: it should restart with a growing delay (2s, 4s, 8s...).
local n = 0
while true do
  sleep(1)
  n = n + 1
  term.clear()
  term.setCursorPos(1, 1)
  print("SERVICE tick " .. n)
  if n == 8 then error("service crash test") end
end
