-- Test service: sends notifications 4 seconds after you press a key, so you
-- have time to switch away. A toast is not shown for the app you are viewing.
-- Run it from Apps > Toaster, then open it from the RUNNING list.
local n = prismarine
local pending = {}

local function show()
  term.clear()
  term.setCursorPos(1, 1)
  print("TOASTER (service)")
  print("Press a key, then go Home or open another app.")
  print("1 info toast")
  print("2 warning toast")
  print("3 error toast")
  print("4 private message toast")
  print("5 spam: 6 toasts at once (rate limit is 3)")
  print("Toasts arrive after 4 seconds.")
end
show()

while true do
  local ev, a = os.pullEvent()
  if ev == "char" and a >= "1" and a <= "5" then
    pending[os.startTimer(4)] = a
    show()
    print()
    print("Queued toast " .. a)
  elseif ev == "timer" and pending[a] then
    local c = pending[a]
    pending[a] = nil
    if c == "1" then
      n.notify("Hello", "A short info toast from the toaster test app.", "info")
    elseif c == "2" then
      n.notify("Careful", "This is a warning toast.", "warn")
    elseif c == "3" then
      n.notify("Failed", "This is an error toast and it stays a little longer.", "error")
    elseif c == "4" then
      n.notify("Message from Alex", "this text is private and hidden by default", "info", true)
    elseif c == "5" then
      for i = 1, 6 do n.notify("Spam " .. i, "spam text " .. i, "info") end
    end
  end
end
