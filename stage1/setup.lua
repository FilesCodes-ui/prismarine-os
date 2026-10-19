-- Downloads the Prismarine v23 stage 1 test files to this computer.
-- Run: wget run https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage1/setup.lua
local base = "https://raw.githubusercontent.com/FilesCodes-ui/prismarine-os/main/stage1/"
local files = {
  "kernel_test.lua",
  "prismarine/kernel/kernel.lua",
  "prismarine/kernel/sandbox.lua",
  "prismarine/tests/counter.lua",
  "prismarine/tests/crasher.lua",
  "prismarine/tests/spinner.lua",
  "prismarine/tests/svc.lua",
  "prismarine/tests/probe.lua",
}
if not http then error("HTTP is disabled on this server.", 0) end
for i, path in ipairs(files) do
  write(i .. "/" .. #files .. " " .. path .. " ... ")
  local r = http.get(base .. path .. "?cb=" .. os.epoch("utc"), nil, true)
  if not r then print("FAILED") error("Download failed: " .. path, 0) end
  local body = r.readAll()
  r.close()
  local f = fs.open(path, "wb")
  f.write(body)
  f.close()
  print("ok")
end
print()
print("Done. Run: kernel_test")
