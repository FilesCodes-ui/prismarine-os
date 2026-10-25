--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- The shell API for Prismarine Shell. Same calls as the CraftOS shell global.
-- Programs run through os.run inside the app sandbox.
local M = {}

function M.new()
  local sh = {}
  local cwd = ""
  local aliases = { ls = "list", dir = "list", cp = "copy", mv = "move", rm = "delete", rename = "move" }
  local pathList = "/rom/programs:/programs"
  local completers = {}
  local running = { "shell" }
  local env = nil

  local function root(p) return "/" .. fs.combine(p or "", "") end

  function sh.dir() return cwd end
  function sh.setDir(d) cwd = fs.combine("", d) end
  function sh.path() return pathList end
  function sh.setPath(p) pathList = tostring(p) end
  function sh.resolve(p)
    p = tostring(p or "")
    if p:sub(1, 1) == "/" then return fs.combine(p, "") end
    return fs.combine(cwd, p)
  end
  function sh.getRunningProgram() return running[#running] end
  function sh.exit() sh.done = true end
  function sh.aliases()
    local out = {}
    for k, v in pairs(aliases) do out[k] = v end
    return out
  end
  function sh.setAlias(a, p) aliases[a] = p end
  function sh.clearAlias(a) aliases[a] = nil end

  function sh.resolveProgram(name)
    name = aliases[name] or name
    if name:find("/") then
      local p = sh.resolve(name)
      for _, n in ipairs({ p, p .. ".lua" }) do
        if fs.exists(n) and not fs.isDir(n) then return "/" .. n end
      end
      return nil
    end
    local dirs = {}
    for d in sh.path():gmatch("[^:]+") do dirs[#dirs + 1] = d end
    table.insert(dirs, 1, "/" .. cwd)
    for _, d in ipairs(dirs) do
      for _, n in ipairs({ name, name .. ".lua" }) do
        local p = fs.combine(d, n)
        if fs.exists(p) and not fs.isDir(p) then return "/" .. p end
      end
    end
    return nil
  end

  function sh.programs(hidden)
    local seen, out = {}, {}
    for d in sh.path():gmatch("[^:]+") do
      if fs.isDir(d) then
        for _, n in ipairs(fs.list(d)) do
          local p = fs.combine(d, n)
          if not fs.isDir(p) and (hidden or n:sub(1, 1) ~= ".") then
            n = n:gsub("%.lua$", "")
            if not seen[n] then seen[n] = true out[#out + 1] = n end
          end
        end
      end
    end
    for a in pairs(aliases) do
      if not seen[a] then seen[a] = true out[#out + 1] = a end
    end
    table.sort(out)
    return out
  end

  function sh.setCompletionFunction(path, fn) completers[sh.resolve(path)] = fn end
  function sh.getCompletionInfo() return completers end

  -- Text after the cursor that finishes the word. Same as the CraftOS shell.
  function sh.completeProgram(line)
    local out = {}
    if line:find("/") then
      local ok, r = pcall(fs.complete, line, cwd, true, false)
      if ok then return r end
    end
    for _, n in ipairs(sh.programs()) do
      if n:sub(1, #line) == line and #n > #line then out[#out + 1] = n:sub(#line + 1) end
    end
    return out
  end

  function sh.complete(line)
    line = tostring(line or "")
    local words = {}
    for w in line:gmatch("%S+") do words[#words + 1] = w end
    if line == "" or (#words == 1 and not line:find("%s$")) then
      return sh.completeProgram(line)
    end
    local last = line:find("%s$") and "" or words[#words]
    local ok, r = pcall(fs.complete, last, cwd, true, true)
    if ok and type(r) == "table" then return r end
    return {}
  end

  function sh.setEnv(e) env = e end

  function sh.execute(cmd, ...)
    local file = sh.resolveProgram(cmd)
    if not file then
      printError("No such program")
      return false
    end
    local e = setmetatable({ shell = sh }, { __index = env or _ENV or _G })
    running[#running + 1] = file:gsub("^/", "")
    local args = { ... }
    local ok, res = pcall(os.run, e, file, table.unpack(args))
    running[#running] = nil
    if not ok then printError(tostring(res)) return false end
    return res and true or false
  end

  function sh.run(...)
    local line = table.concat({ ... }, " ")
    local words = {}
    for w in line:gmatch("%S+") do words[#words + 1] = w end
    if #words == 0 then return true end
    local cmd = table.remove(words, 1)
    return sh.execute(cmd, table.unpack(words))
  end

  function sh.openTab() return nil end
  function sh.switchTab() end
  return sh
end

return M
