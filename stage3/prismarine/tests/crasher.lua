-- Test app: crashes after 2 seconds.
print("CRASHER: will error in 2s")
sleep(2)
error("boom from crasher test")
