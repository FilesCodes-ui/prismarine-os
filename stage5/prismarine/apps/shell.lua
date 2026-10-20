-- Prismarine Shell. A small command line inside the sandbox.
-- Built in: help ls cd cat mkdir rm cp mv edit lua clear exit
-- Any other word runs /rom/programs/<word>.lua, /programs/<word>.lua or a path.
-- Locked in Archive mode.
local api = prismarine
local W, H = term.getSize()
local cwd = ""
local history, hpos = {}, 0

local function path(p) return fs.combine(cwd, p) end

local sh = {}
function sh.dir() return cwd end
function sh.setDir(d) cwd = fs.combine("", d) end
function sh.resolve(p) return "/" .. fs.combine(cwd, p) end
function sh.resolveProgram(name)
  for _, d in ipairs({ cwd, "rom/programs", "programs" }) do
    for _, n in ipairs({ name, name .. ".lua" }) do
      local p = fs.combine(d, n)
      if fs.exists(p) and not fs.isDir(p) then return "/" .. p end
    end
  end
  return nil
end
function sh.path() return "/rom/programs:/programs" end
function sh.getRunningProgram() return "shell" end
function sh.exit() sh.done = true end
function sh.aliases() return {} end
function sh.programs()
  local out = {}
  for _, d in ipairs({ "rom/programs", "programs" }) do
    if fs.isDir(d) then
      for _, n in ipairs(fs.list(d)) do out[#out + 1] = (n:gsub("%.lua$", "")) end
    end
  end
  table.sort(out)
  return out
end
function sh.complete() return {} end
function sh.completeProgram() return {} end

local function runProgram(file, args)
  local env = setmetatable({ shell = sh }, { __index = _ENV or _G })
  local ok, err = pcall(os.run, env, file, table.unpack(args))
  if not ok then printError(tostring(err)) end
end

local cmds = {}
function cmds.help()
  print("ls cd cat mkdir rm cp mv edit lua clear exit")
  print("Other words run programs from /rom/programs or /programs.")
end
function cmds.ls(a)
  local d = path(a[1] or "")
  if not fs.isDir(d) then printError("Not a folder") return end
  local names = fs.list(d)
  table.sort(names)
  local dirs, files = {}, {}
  for _, n in ipairs(names) do
    if fs.isDir(fs.combine(d, n)) then dirs[#dirs + 1] = n else files[#files + 1] = n end
  end
  term.setTextColor(colors.lightBlue)
  textutils.pagedTabulate(dirs)
  term.setTextColor(colors.white)
  textutils.pagedTabulate(files)
end
function cmds.cd(a)
  local d = fs.combine(cwd, a[1] or "")
  if fs.isDir(d) then cwd = d else printError("No such folder") end
end
function cmds.cat(a)
  local f = path(a[1] or "")
  if not fs.exists(f) or fs.isDir(f) then printError("No such file") return end
  local h = fs.open(f, "r")
  textutils.pagedPrint(h.readAll())
  h.close()
end
function cmds.mkdir(a) fs.makeDir(path(a[1] or "")) end
function cmds.rm(a) fs.delete(path(a[1] or "")) end
function cmds.cp(a) fs.copy(path(a[1] or ""), path(a[2] or "")) end
function cmds.mv(a) fs.move(path(a[1] or ""), path(a[2] or "")) end
function cmds.clear() term.clear() term.setCursorPos(1, 1) end
function cmds.exit() sh.done = true end
function cmds.edit(a)
  local f = sh.resolve(a[1] or "")
  runProgram("/rom/programs/edit.lua", { f })
end
function cmds.lua()
  runProgram("/rom/programs/lua.lua", {})
end

term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.cyan)
print("Prismarine Shell. Type help.")
while not sh.done do
  term.setTextColor(colors.lime)
  write("/" .. cwd .. "> ")
  term.setTextColor(colors.white)
  local line = read(nil, history)
  if line and line ~= "" then
    history[#history + 1] = line
    local parts = {}
    for w in line:gmatch("%S+") do parts[#parts + 1] = w end
    local cmd = table.remove(parts, 1)
    if cmds[cmd] then
      local ok, err = pcall(cmds[cmd], parts)
      if not ok then printError(tostring(err):gsub("^.-:%d+: ", "")) end
    else
      local file = sh.resolveProgram(cmd)
      if file then runProgram(file, parts) else printError("Unknown command: " .. cmd) end
    end
  end
end
