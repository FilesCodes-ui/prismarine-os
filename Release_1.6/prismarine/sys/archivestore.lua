--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/sys/archivestore.lua
-- Where the Archive keeps its day logs. Kernel code.
-- Storage modes: computer, overflow (computer, then disks when space runs low),
-- disks, mirror (computer and disks). Lines are always encrypted before they
-- reach any disk. Export and print write plain text, so the caller checks the
-- password first.
local AS = {}
local C, S, K, N

local DIR = "/prismarine/archive/"
local DISKDIR = "prismarine-archive/"
local EXPORT = "/prismarine/archive/export/"
local MODES = { computer = true, overflow = true, disks = true, mirror = true }

local cfg = nil
local mountCache, mountAt = {}, -100

function AS.init(crypto, secure, kernel, net)
  C, S, K, N = crypto, secure, kernel, net
end

local function yield()
  os.queueEvent("pm_y")
  os.pullEventRaw("pm_y")
end

-- ------------------------------------------------------------ settings

local function loadCfg()
  if cfg then return cfg end
  cfg = { storage = "computer", reserve = 20000 }
  if fs.exists(DIR .. "config.dat") then
    local h = fs.open(DIR .. "config.dat", "r")
    if h then
      local ok, t = pcall(textutils.unserialize, h.readAll())
      h.close()
      if ok and type(t) == "table" then
        if MODES[t.storage] then cfg.storage = t.storage end
        if type(t.reserve) == "number" then cfg.reserve = math.max(5000, math.min(12000000, math.floor(t.reserve))) end
      end
    end
  end
  return cfg
end

local function saveCfg()
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  local h = fs.open(DIR .. "config.dat", "w")
  if h then h.write(textutils.serialize(cfg)) h.close() end
end

function AS.config()
  local c = loadCfg()
  return { storage = c.storage, reserve = c.reserve }
end

function AS.set(key, value)
  local c = loadCfg()
  if key == "storage" and MODES[value] then c.storage = value
  elseif key == "reserve" and type(value) == "number" then c.reserve = math.max(5000, math.min(12000000, math.floor(value)))
  else return false end
  saveCfg()
  return true
end

-- ------------------------------------------------------------ disks

function AS.disks()
  if os.clock() - mountAt < 5 then return mountCache end
  local out = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "drive" then
      local ok, path = pcall(peripheral.call, name, "getMountPath")
      if ok and type(path) == "string" and fs.isDir(path) and not fs.isReadOnly(path) then
        local _, label = pcall(peripheral.call, name, "getDiskLabel")
        out[#out + 1] = { mount = path, free = fs.getFreeSpace(path), label = type(label) == "string" and label or nil }
      end
    end
  end
  mountCache, mountAt = out, os.clock()
  return out
end

function AS.refreshDisks() mountAt = -100 end

local function diskDirs(need)
  local d = {}
  for _, x in ipairs(AS.disks()) do
    if fs.getFreeSpace(x.mount) > (need or 0) + 512 then d[#d + 1] = fs.combine(x.mount, DISKDIR) .. "/" end
  end
  return d
end

local function allDirs()
  local d = { DIR }
  for _, x in ipairs(AS.disks()) do d[#d + 1] = fs.combine(x.mount, DISKDIR) .. "/" end
  return d
end

local function targets(need)
  local c = loadCfg()
  local d = diskDirs(need)
  if c.storage == "computer" then return { DIR } end
  if c.storage == "mirror" then
    table.insert(d, 1, DIR)
    return d
  end
  if c.storage == "disks" then
    if #d > 0 then return d end
    return { DIR }
  end
  -- overflow
  if fs.getFreeSpace("/") > c.reserve + need then return { DIR } end
  if #d > 0 then return d end
  return { DIR }
end

-- ------------------------------------------------------------ log files

local function appendLine(dir, day, line)
  -- A disk pulled out mid-write must not raise an error.
  local ok, res = pcall(function()
    if not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(dir .. day .. ".log", "a")
    if h then
      h.writeLine(line)
      h.close()
      return true
    end
    return false
  end)
  return ok and res == true
end

local function tryWrite(day, line)
  local wrote = false
  local okT, list = pcall(targets, #line + 2)
  if not okT then list = { DIR } end
  for _, dir in ipairs(list) do
    if appendLine(dir, day, line) then wrote = true end
  end
  if not wrote then wrote = appendLine(DIR, day, line) end
  return wrote
end

-- A line that no place could keep waits in memory (up to 500) and is tried
-- again with the next record and on a timer. The first failure raises a
-- warning through AS.warn, which the OS shows as an alert.
local queue, failedTotal, droppedTotal, warned = {}, 0, 0, false
AS.warn = nil

-- Tries the waiting lines again. Returns how many are still waiting.
function AS.flush()
  while queue[1] do
    local q = queue[1]
    if tryWrite(q[1], q[2]) then table.remove(queue, 1) else break end
  end
  if #queue == 0 and warned then
    warned = false
    if AS.warn then pcall(AS.warn, "The Archive log works again. Waiting records were saved.", "info") end
  end
  return #queue
end

function AS.status() return { queued = #queue, failed = failedTotal, dropped = droppedTotal } end

-- One sealed line for one day. Called for every record.
-- Returns true when at least one place kept the line.
function AS.write(day, line)
  if #queue > 0 then AS.flush() end
  local wrote = tryWrite(day, line)
  if not wrote then
    failedTotal = failedTotal + 1
    if #queue < 500 then queue[#queue + 1] = { day, line } else droppedTotal = droppedTotal + 1 end
    if not warned then
      warned = true
      if AS.warn then pcall(AS.warn, "The Archive could not write a log record. It keeps trying. Free space or fix the disk.", "warn") end
    end
  end
  return wrote
end

function AS.days()
  local seen, out = {}, {}
  for _, dir in ipairs(allDirs()) do
    if fs.isDir(dir) then
      for _, n in ipairs(fs.list(dir)) do
        local d = n:match("^(%d%d%d%d%-%d%d%-%d%d)%.log$")
        if d and not seen[d] then
          seen[d] = true
          out[#out + 1] = d
        end
      end
    end
  end
  table.sort(out)
  return out
end

local function validDay(d)
  return type(d) == "string" and d:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end
AS.validDay = validDay

-- Records for a day from every place that holds it. open(bytes) decrypts a line.
function AS.day(d, open)
  if not validDay(d) then return {} end
  local seen, recs, n = {}, {}, 0
  for _, dir in ipairs(allDirs()) do
    local h = fs.open(dir .. d .. ".log", "r")
    if h then
      while true do
        local line = h.readLine()
        if not line then break end
        if not seen[line] then
          seen[line] = true
          local ok, rec = pcall(function() return C.decode(open(C.unhex(line))) end)
          if ok and type(rec) == "table" then recs[#recs + 1] = rec end
          n = n + 1
          if n % 25 == 0 then yield() end
        end
      end
      h.close()
    end
  end
  table.sort(recs, function(a, b) return (a.t or 0) < (b.t or 0) end)
  return recs
end

-- Deleting a day is final. The caller checks the password first and writes
-- the record that says who deleted what.
function AS.delete(d)
  if not validDay(d) then return false end
  local gone = false
  for _, dir in ipairs(allDirs()) do
    local p = dir .. d .. ".log"
    if fs.exists(p) then fs.delete(p) gone = true end
  end
  return gone
end

-- Copy any local day lines the first disk lacks. Returns lines copied.
function AS.copyAll()
  local dirs = diskDirs(2000)
  if #dirs == 0 then return false, "No disk with free space" end
  local target = dirs[1]
  if not fs.exists(target) then fs.makeDir(target) end
  local copied = 0
  for _, n in ipairs(fs.isDir(DIR) and fs.list(DIR) or {}) do
    local d = n:match("^(%d%d%d%d%-%d%d%-%d%d)%.log$")
    if d then
      local have = {}
      local h = fs.open(target .. n, "r")
      if h then
        while true do
          local line = h.readLine()
          if not line then break end
          have[line] = true
        end
        h.close()
      end
      local src = fs.open(DIR .. n, "r")
      if src then
        while true do
          local line = src.readLine()
          if not line then break end
          if not have[line] then
            if fs.getFreeSpace(target) < #line + 512 then src.close() return copied, "Disk is full" end
            appendLine(target, d, line)
            copied = copied + 1
          end
        end
        src.close()
      end
      yield()
    end
  end
  return copied
end

-- ------------------------------------------------------------ plain text

local function stampFull(ms)
  return os.date("!%Y-%m-%d %H:%M:%S", math.floor((ms or 0) / 1000))
end

local function plainLines(recs)
  local out = {}
  for _, r in ipairs(recs) do
    local text = tostring(r.text or r.kind or "?"):gsub("%c", " ")
    if r.kind == "file_data" then text = text .. " (" .. tostring(r.data and #r.data or 0) .. " bytes, not exported)" end
    out[#out + 1] = stampFull(r.t) .. "  " .. text
  end
  return out
end
AS.plainLines = plainLines

-- Writes decrypted text. dest: "computer" or "disk". day: a date or "all".
-- Returns the path, or false and a reason.
function AS.export(day, dest, open)
  local days = {}
  if day == "all" then days = AS.days()
  elseif validDay(day) then days = { day }
  else return false, "Bad day" end
  if #days == 0 then return false, "Nothing to export" end
  local dir
  if dest == "disk" then
    local d = AS.disks()[1]
    if not d then return false, "No disk found" end
    dir = fs.combine(d.mount, "prismarine-export") .. "/"
  else
    dir = EXPORT
  end
  if not fs.exists(dir) then fs.makeDir(dir) end
  local text = {}
  for _, d in ipairs(days) do
    text[#text + 1] = "== " .. d
    for _, l in ipairs(plainLines(AS.day(d, open))) do text[#text + 1] = l end
    text[#text + 1] = ""
  end
  local body = table.concat(text, "\n")
  local name = (day == "all") and "archive-all.txt" or ("archive-" .. day .. ".txt")
  if dest == "disk" and fs.getFreeSpace(dir) < #body + 256 then return false, "Disk is full" end
  local h = fs.open(dir .. name, "w")
  if not h then return false, "Could not write the file" end
  h.write(body)
  h.close()
  return dir .. name, #days
end

-- ------------------------------------------------------------ printing

local PCOLS, PROWS, MAXPAGES = 25, 21, 40

local function wrap(line)
  local out = {}
  line = line:gsub("%c", " ")
  while #line > PCOLS do
    local cut = line:sub(1, PCOLS):match("^.*()%s") or PCOLS
    if cut < 8 then cut = PCOLS end
    out[#out + 1] = line:sub(1, cut):gsub("%s+$", "")
    line = line:sub(cut + 1):gsub("^%s+", "")
  end
  out[#out + 1] = line
  return out
end

function AS.hasPrinter()
  return peripheral.find("printer") ~= nil
end

-- Prints one day. Returns pages printed, or false and a reason.
function AS.print(day, open)
  if not validDay(day) then return false, "Bad day" end
  local pr = peripheral.find("printer")
  if not pr then return false, "No printer found" end
  local lines = {}
  for _, l in ipairs(plainLines(AS.day(day, open))) do
    for _, w in ipairs(wrap(l:sub(12))) do lines[#lines + 1] = w end
  end
  if #lines == 0 then return false, "Nothing on this day" end
  local pages, i = 0, 1
  while i <= #lines do
    if pages >= MAXPAGES then return pages, "Stopped at " .. MAXPAGES .. " pages" end
    if not pr.newPage() then return pages, "Out of paper or ink" end
    pr.setPageTitle("Archive " .. day .. " p" .. (pages + 1))
    for row = 1, PROWS do
      if i > #lines then break end
      pr.setCursorPos(1, row)
      pr.write(lines[i])
      i = i + 1
    end
    if not pr.endPage() then return pages, "Printer output is full" end
    pages = pages + 1
  end
  return pages
end

return AS
