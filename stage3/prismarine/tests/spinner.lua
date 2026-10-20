-- Test app: infinite loop that never yields.
-- Shows what happens when an app hogs the computer.
print("SPINNER: tight loop starts in 2s...")
sleep(2)
print("looping now")
while true do end
