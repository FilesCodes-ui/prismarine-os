--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Editor. Write and fix text, Lua and JSON files.
-- It also makes new files. Colors follow the code as you type.
-- Keys: Ctrl+S save, Ctrl+O open, Ctrl+N new file, Ctrl+F find, F3 find next,
-- Ctrl+G go to line, Ctrl+Z undo, Ctrl+Y redo, Ctrl+Q quit, F1 help.
local W, H = term.getSize()
local MAXSIZE = 300000

local lines = { "" }
local cx, cy = 1, 1
local top, left = 1, 0
local path = nil
local modified = false
local trailing = true
local sel = nil
local clip = ""
local undo, redo, lastKind = {}, {}, nil
local flash, flashColor, flashAt = nil, colors.lightGray, 0
local ctrl, shift = false, false
local wantX = 1
local findText = ""
local errLine = nil
local drag = false
local menuHits = {}

-- ------------------------------------------------------------ helpers

local function set(list)
  local t = {}
  for _, v in ipairs(list) do t[v] = true end
  return t
end

local function note(text, color)
  flash, flashColor, flashAt = text, color or colors.lightGray, os.clock()
  os.startTimer(6)
end

local function langOf(p)
  local ext = p and p:lower():match("%.([%w_]+)$") or ""
  if ext == "lua" then return "lua" end
  if ext == "json" or ext == "sjson" then return "json" end
  return "text"
end
local lang = "text"
local LANGNAME = { lua = "Lua", json = "JSON", text = "Text" }

local function nameOf()
  if not path then return "untitled" end
  return fs.getName(path)
end

-- ------------------------------------------------------------ colors

local TEXT, KW, CONST, BUILTIN, CALL, STR, NUM, COM, PUN, KEY =
  colors.white, colors.purple, colors.yellow, colors.cyan, colors.lightBlue,
  colors.lime, colors.orange, colors.gray, colors.lightGray, colors.cyan

local KEYWORDS = set { "and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if", "in",
  "local", "not", "or", "repeat", "return", "then", "until", "while" }
local CONSTS = set { "true", "false", "nil" }
local GLOBALS = set { "print", "write", "read", "pairs", "ipairs", "next", "type", "tostring", "tonumber",
  "pcall", "xpcall", "error", "assert", "select", "unpack", "require", "load", "loadstring", "setmetatable",
  "getmetatable", "rawget", "rawset", "rawequal", "sleep", "term", "fs", "os", "string", "table", "math",
  "textutils", "colors", "colours", "keys", "peripheral", "redstone", "rs", "http", "parallel", "shell",
  "multishell", "turtle", "paintutils", "window", "settings", "disk", "gps", "rednet", "vector", "io",
  "coroutine", "bit", "bit32", "utf8", "_G", "_ENV", "printError", "fs" }

local EMPTY = {}

local function closeAt(line, i, lvl)
  local _, e = line:find("]" .. string.rep("=", lvl) .. "]", i, true)
  return e
end

-- Returns a color for each column, and the state at the end of the line.
-- State 0 means normal. "c1" or "s1" means inside a long comment or string
-- with one "=" in its brackets.
local function luaColors(line, state)
  local n = #line
  local cols = {}
  local function paint(a, b, c) for k = a, b do cols[k] = c end end
  local i = 1
  if state ~= 0 then
    local kind, lvl = state:sub(1, 1), tonumber(state:sub(2))
    local e = closeAt(line, 1, lvl)
    local c = kind == "c" and COM or STR
    if e then
      paint(1, e, c)
      i = e + 1
    else
      paint(1, n, c)
      return cols, state
    end
  end
  while i <= n do
    local ch = line:sub(i, i)
    if ch == " " or ch == "\t" then
      i = i + 1
    elseif line:sub(i, i + 1) == "--" then
      local eq = line:match("^%-%-%[(=*)%[", i)
      if eq then
        local lvl = #eq
        local e = closeAt(line, i + lvl + 4, lvl)
        if e then
          paint(i, e, COM)
          i = e + 1
        else
          paint(i, n, COM)
          return cols, "c" .. lvl
        end
      else
        paint(i, n, COM)
        i = n + 1
      end
    elseif ch == "[" and line:match("^%[=*%[", i) then
      local lvl = #line:match("^%[(=*)%[", i)
      local e = closeAt(line, i + lvl + 2, lvl)
      if e then
        paint(i, e, STR)
        i = e + 1
      else
        paint(i, n, STR)
        return cols, "s" .. lvl
      end
    elseif ch == '"' or ch == "'" then
      local j = i + 1
      while j <= n do
        local d = line:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == ch then break
        else j = j + 1 end
      end
      if j > n then j = n end
      paint(i, j, STR)
      i = j + 1
    elseif ch:match("%d") or (ch == "." and line:sub(i + 1, i + 1):match("%d")) then
      local s = line:match("^0[xX]%x+", i) or line:match("^%d*%.?%d+[eE][+-]?%d+", i)
        or line:match("^%d+%.?%d*", i) or line:match("^%.%d+", i) or ch
      paint(i, i + #s - 1, NUM)
      i = i + #s
    elseif ch:match("[%a_]") then
      local id = line:match("^[%a_][%w_]*", i)
      local e = i + #id - 1
      local c = TEXT
      if KEYWORDS[id] then c = KW
      elseif CONSTS[id] then c = CONST
      elseif GLOBALS[id] then c = BUILTIN
      else
        local nxt = line:match("^%s*(.)", e + 1)
        if nxt == "(" or nxt == '"' or nxt == "'" or nxt == "{" then c = CALL end
      end
      paint(i, e, c)
      i = e + 1
    else
      paint(i, i, PUN)
      i = i + 1
    end
  end
  return cols, 0
end

local function jsonColors(line)
  local n = #line
  local cols = {}
  local function paint(a, b, c) for k = a, b do cols[k] = c end end
  local i = 1
  while i <= n do
    local ch = line:sub(i, i)
    if ch == '"' then
      local j = i + 1
      while j <= n do
        local d = line:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == '"' then break
        else j = j + 1 end
      end
      if j > n then j = n end
      local isKey = line:match("^%s*:", j + 1) ~= nil
      paint(i, j, isKey and KEY or STR)
      i = j + 1
    elseif ch:match("[%d%-]") then
      local s = line:match("^%-?%d+%.?%d*[eE]?[+-]?%d*", i) or ch
      paint(i, i + #s - 1, NUM)
      i = i + #s
    elseif ch:match("%a") then
      local id = line:match("^%a+", i)
      if id == "true" or id == "false" or id == "null" then paint(i, i + #id - 1, CONST) end
      i = i + #id
    elseif ch == " " then
      i = i + 1
    else
      paint(i, i, PUN)
      i = i + 1
    end
  end
  return cols, 0
end

local st, stValid, cache = { 0 }, 1, {}

local function tokenizer(line, state)
  if lang == "lua" then return luaColors(line, state) end
  if lang == "json" then return jsonColors(line) end
  return EMPTY, 0
end

local function colorLine(i)
  local line, s = lines[i], st[i]
  local c = cache[i]
  if c and c.text == line and c.state == s then return c.cols, c.out end
  local cols, out = tokenizer(line, s)
  cache[i] = { text = line, state = s, cols = cols, out = out }
  return cols, out
end

local function colorsFor(i)
  while stValid < i do
    local _, out = colorLine(stValid)
    st[stValid + 1] = out
    stValid = stValid + 1
  end
  return (colorLine(i))
end

local function changed(y)
  if y < stValid then stValid = y end
  if stValid < 1 then stValid = 1 end
  modified = true
  errLine = nil
end

-- ------------------------------------------------------------ undo

local function snapshot()
  local copy = {}
  for i, l in ipairs(lines) do copy[i] = l end
  return { lines = copy, cx = cx, cy = cy }
end

local function restore(s)
  lines, cx, cy = s.lines, s.cx, s.cy
  sel = nil
  stValid = 1
  cache = {}
  modified = true
  errLine = nil
end

local function mark(kind)
  if kind == "other" or kind ~= lastKind then
    undo[#undo + 1] = snapshot()
    if #undo > 80 then table.remove(undo, 1) end
    redo = {}
  end
  lastKind = kind
end

-- ------------------------------------------------------------ selection

local function selRange()
  if not sel then return nil end
  local ax, ay = sel[1], sel[2]
  if ax == cx and ay == cy then return nil end
  if ay < cy or (ay == cy and ax < cx) then return ax, ay, cx, cy end
  return cx, cy, ax, ay
end

local function selText()
  local sx, sy, ex, ey = selRange()
  if not sx then return "" end
  if sy == ey then return lines[sy]:sub(sx, ex - 1) end
  local out = { lines[sy]:sub(sx) }
  for y = sy + 1, ey - 1 do out[#out + 1] = lines[y] end
  out[#out + 1] = lines[ey]:sub(1, ex - 1)
  return table.concat(out, "\n")
end

local function deleteSel()
  local sx, sy, ex, ey = selRange()
  if not sx then sel = nil return false end
  local head, tail = lines[sy]:sub(1, sx - 1), lines[ey]:sub(ex)
  for _ = sy + 1, ey do table.remove(lines, sy + 1) end
  lines[sy] = head .. tail
  cx, cy = sx, sy
  sel = nil
  changed(sy)
  return true
end

-- ------------------------------------------------------------ editing

local function insertText(s)
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "  ")
  deleteSel()
  local start = cy
  local line = lines[cy]
  local before, after = line:sub(1, cx - 1), line:sub(cx)
  local parts = {}
  for part in (s .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = part end
  if #parts == 1 then
    lines[cy] = before .. parts[1] .. after
    cx = cx + #parts[1]
  else
    lines[cy] = before .. parts[1]
    for k = 2, #parts - 1 do table.insert(lines, cy + k - 1, parts[k]) end
    table.insert(lines, cy + #parts - 1, parts[#parts] .. after)
    cy = cy + #parts - 1
    cx = #parts[#parts] + 1
  end
  changed(start)
end

local function newline()
  deleteSel()
  local line = lines[cy]
  local before = line:sub(1, cx - 1)
  local indent = before:match("^%s*") or ""
  if lang == "lua" then
    local t = before:gsub("%s+$", "")
    if t:match("then$") or t:match("[%s]do$") or t == "do" or t:match("else$") or t:match("repeat$")
      or t:match("function%s*[%w_.:]*%b()$") or t:match("{$") then
      indent = indent .. "  "
    end
  elseif lang == "json" then
    if before:match("[%[{]%s*$") then indent = indent .. "  " end
  end
  local start = cy
  lines[cy] = before
  table.insert(lines, cy + 1, indent .. line:sub(cx))
  cy = cy + 1
  cx = #indent + 1
  changed(start)
end

local function backspace()
  if deleteSel() then return end
  if cx > 1 then
    local line = lines[cy]
    local n = 1
    -- In leading spaces, remove two at a time to match the indent.
    if line:sub(1, cx - 1):match("^%s+$") and (cx - 1) % 2 == 0 then n = 2 end
    lines[cy] = line:sub(1, cx - 1 - n) .. line:sub(cx)
    cx = cx - n
    changed(cy)
  elseif cy > 1 then
    local prev = lines[cy - 1]
    lines[cy - 1] = prev .. lines[cy]
    table.remove(lines, cy)
    cy = cy - 1
    cx = #prev + 1
    changed(cy)
  end
end

local function delete()
  if deleteSel() then return end
  local line = lines[cy]
  if cx <= #line then
    lines[cy] = line:sub(1, cx - 1) .. line:sub(cx + 1)
    changed(cy)
  elseif cy < #lines then
    lines[cy] = line .. lines[cy + 1]
    table.remove(lines, cy + 1)
    changed(cy)
  end
end

local function deleteLine()
  if #lines == 1 then lines[1] = "" cx = 1 else table.remove(lines, cy) end
  if cy > #lines then cy = #lines end
  if cx > #lines[cy] + 1 then cx = #lines[cy] + 1 end
  sel = nil
  changed(cy)
end

local function indentLines(out)
  local sx, sy, ex, ey = selRange()
  if not sx then sx, sy, ex, ey = cx, cy, cx, cy end
  if ex == 1 and ey > sy then ey = ey - 1 end
  for y = sy, ey do
    if out then
      local sp = lines[y]:match("^ +") or ""
      local cut = math.min(2, #sp)
      lines[y] = lines[y]:sub(cut + 1)
      if y == cy then cx = math.max(1, cx - cut) end
    else
      lines[y] = "  " .. lines[y]
      if y == cy then cx = cx + 2 end
    end
  end
  changed(sy)
end

-- ------------------------------------------------------------ moving

local function clampCursor()
  if cy < 1 then cy = 1 end
  if cy > #lines then cy = #lines end
  if cx < 1 then cx = 1 end
  if cx > #lines[cy] + 1 then cx = #lines[cy] + 1 end
end

local function moveTo(nx, ny, extend, keepWant)
  if extend then
    if not sel then sel = { cx, cy } end
  else
    sel = nil
  end
  cx, cy = nx, ny
  clampCursor()
  if not keepWant then wantX = cx end
end

local function isWord(c) return c ~= "" and c:match("[%w_]") ~= nil end

local function wordLeft()
  local x, y = cx, cy
  if x == 1 then
    if y > 1 then return #lines[y - 1] + 1, y - 1 end
    return 1, 1
  end
  local line = lines[y]
  x = x - 1
  while x > 1 and not isWord(line:sub(x, x)) do x = x - 1 end
  while x > 1 and isWord(line:sub(x - 1, x - 1)) do x = x - 1 end
  return x, y
end

local function wordRight()
  local x, y = cx, cy
  local line = lines[y]
  if x > #line then
    if y < #lines then return 1, y + 1 end
    return x, y
  end
  while x <= #line and not isWord(line:sub(x, x)) do x = x + 1 end
  while x <= #line and isWord(line:sub(x, x)) do x = x + 1 end
  return x, y
end

local function gutterW()
  return math.max(2, #tostring(#lines)) + 2
end

local function areaH() return H - 3 end

local function scrollToCursor()
  local gw = gutterW()
  local tw = W - gw
  if cy < top then top = cy end
  if cy > top + areaH() - 1 then top = cy - areaH() + 1 end
  if top < 1 then top = 1 end
  if cx - 1 < left then left = cx - 1 end
  if cx > left + tw - 1 then left = cx - tw + 1 end
  if left < 0 then left = 0 end
end

-- ------------------------------------------------------------ drawing

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function pad(s, n)
  if #s > n then return s:sub(1, n) end
  return s .. string.rep(" ", n - #s)
end

local kit = dofile("/prismarine/ui/kit.lua")

local MENU = {
  { "^S Save", "save" }, { "^O Open", "open" }, { "^N New", "new" },
  { "^F Find", "find" }, { "^G Go", "go" }, { "^Q Quit", "quit" },
}

local function draw()
  term.setCursorBlink(false)
  scrollToCursor()
  local gw = gutterW()
  local tw = W - gw
  -- Top bar
  local ln = LANGNAME[lang]
  kit.header("Editor", nameOf() .. (modified and " *" or ""), ln)

  -- Text
  local sx, sy, ex, ey = selRange()
  local function inSel(c, y)
    if not sx then return false end
    if y < sy or y > ey then return false end
    if y == sy and c < sx then return false end
    if y == ey and c >= ex then return false end
    return true
  end
  for r = 1, areaH() do
    local y = top + r - 1
    local row = r + 1
    term.setCursorPos(1, row)
    if y <= #lines then
      if y == cy then
        term.setBackgroundColor(kit.c("sel"))
        term.setTextColor(kit.c("selText"))
      else
        term.setBackgroundColor(kit.c("bar"))
        term.setTextColor(y == errLine and colors.red or kit.c("hint"))
      end
      term.write(("%" .. (gw - 1) .. "d "):format(y))
      local line = lines[y]
      local cols = lang == "text" and EMPTY or colorsFor(y)
      local buf, bf, bb = {}, nil, nil
      for c = left + 1, left + tw do
        local ch = c <= #line and line:sub(c, c) or " "
        local fg = cols[c] or TEXT
        local bg = inSel(c, y) and colors.blue or colors.black
        if fg ~= bf or bg ~= bb then
          if #buf > 0 then
            term.setTextColor(bf)
            term.setBackgroundColor(bb)
            term.write(table.concat(buf))
            buf = {}
          end
          bf, bb = fg, bg
        end
        buf[#buf + 1] = ch
      end
      if #buf > 0 then
        term.setTextColor(bf)
        term.setBackgroundColor(bb)
        term.write(table.concat(buf))
      end
    else
      term.setBackgroundColor(colors.gray)
      term.write(string.rep(" ", gw))
      term.setBackgroundColor(colors.black)
      term.write(string.rep(" ", tw))
    end
  end

  -- Status line
  put(1, H - 1, string.rep(" ", W), kit.c("barText"), kit.c("bg"))
  if flash and os.clock() - flashAt < 6 then
    put(2, H - 1, pad(flash, W - 2), flashColor, kit.c("bg"))
  else
    local pos = (" Ln %d/%d  Col %d "):format(cy, #lines, cx)
    put(2, H - 1, pos, kit.c("barText"), kit.c("bar"))
    put(3 + #pos, H - 1, (" " .. LANGNAME[lang] .. " "), kit.c("barText"), kit.c("barBtn"))
    if W >= 36 then put(W - 8, H - 1, " F1 help ", kit.c("line"), kit.c("bar")) end
  end

  -- Menu bar
  term.setCursorPos(1, H)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.write(string.rep(" ", W))
  menuHits = {}
  local x = 2
  for _, m in ipairs(MENU) do
    put(x, H, m[1]:sub(1, 2), colors.cyan, colors.gray)
    put(x + 2, H, m[1]:sub(3), colors.white, colors.gray)
    menuHits[#menuHits + 1] = { x, x + #m[1] - 1, m[2] }
    x = x + #m[1] + 2
  end

  term.setCursorPos(gw + (cx - left), cy - top + 2)
  term.setTextColor(colors.white)
  term.setCursorBlink(true)
end

-- ------------------------------------------------------------ prompts

-- Reads one line at the bottom. Returns the text, or nil on Escape.
local function ask(label, default)
  local buf = default or ""
  local pos = #buf + 1
  while true do
    term.setCursorBlink(false)
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", W))
    put(2, H - 1, label, colors.cyan)
    local room = W - #label - 3
    local from = math.max(1, pos - room + 1)
    put(2 + #label, H - 1, buf:sub(from, from + room - 1), colors.white)
    term.setCursorPos(2 + #label + (pos - from), H - 1)
    term.setCursorBlink(true)
    local ev = { os.pullEvent() }
    if ev[1] == "char" then
      buf = buf:sub(1, pos - 1) .. ev[2] .. buf:sub(pos)
      pos = pos + #ev[2]
    elseif ev[1] == "paste" then
      local t = ev[2]:gsub("[\r\n]", " ")
      buf = buf:sub(1, pos - 1) .. t .. buf:sub(pos)
      pos = pos + #t
    elseif ev[1] == "key" then
      local k = ev[2]
      if k == keys.enter then term.setCursorBlink(false) return buf
      elseif k == keys.escape then term.setCursorBlink(false) return nil
      elseif k == keys.backspace then
        if pos > 1 then buf = buf:sub(1, pos - 2) .. buf:sub(pos) pos = pos - 1 end
      elseif k == keys.delete then buf = buf:sub(1, pos - 1) .. buf:sub(pos + 1)
      elseif k == keys.left then pos = math.max(1, pos - 1)
      elseif k == keys.right then pos = math.min(#buf + 1, pos + 1)
      elseif k == keys.home then pos = 1
      elseif k == keys["end"] then pos = #buf + 1 end
    end
  end
end

-- Returns "y", "n", or nil for Escape.
local function confirm(text)
  while true do
    term.setCursorBlink(false)
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", W))
    put(2, H - 1, text, colors.orange)
    local ev = { os.pullEvent() }
    if ev[1] == "char" then
      local c = ev[2]:lower()
      if c == "y" then return "y" elseif c == "n" then return "n" end
    elseif ev[1] == "key" and ev[2] == keys.escape then
      return nil
    end
  end
end

local HELP = {
  { "Files", "" },
  { "Ctrl+S", "Save (asks for a name if new)" },
  { "Ctrl+O", "Open a file. N new file, M new folder" },
  { "Ctrl+N", "Make a new file" },
  { "Ctrl+Q", "Quit" },
  { "Edit", "" },
  { "Shift+Arrows", "Select text" },
  { "Ctrl+C X V A", "Copy, cut, paste, select all" },
  { "Ctrl+Z / Y", "Undo / redo" },
  { "Ctrl+D", "Delete the current line" },
  { "Tab", "Indent. Shift+Tab takes it back" },
  { "Find", "" },
  { "Ctrl+F / F3", "Find / find next" },
  { "Ctrl+G", "Go to a line" },
  { "Ctrl+K", "Check the code for mistakes" },
}

local function help()
  term.setBackgroundColor(colors.black)
  term.clear()
  put(1, 1, pad(" Editor help", W), colors.white, colors.gray)
  for i, h in ipairs(HELP) do
    if h[2] == "" then
      put(2, 2 + i, h[1], colors.cyan)
    else
      put(3, 2 + i, h[1], colors.lime)
      put(18, 2 + i, h[2], colors.white)
    end
  end
  put(2, H, "Press any key to go back", colors.lightGray)
  while true do
    local e = os.pullEvent()
    if e == "key" or e == "mouse_click" then break end
  end
end

-- ------------------------------------------------------------ files

local function openText(data, p)
  if #data > MAXSIZE then return false, "File too big (limit " .. math.floor(MAXSIZE / 1000) .. " KB)" end
  if data:find("%z") then return false, "This looks like a binary file" end
  trailing = data:sub(-1) == "\n" or data == ""
  data = data:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "  ")
  local out = {}
  for l in (data .. "\n"):gmatch("(.-)\n") do out[#out + 1] = l end
  if #out > 1 and out[#out] == "" and data:sub(-1) == "\n" then out[#out] = nil end
  if #out == 0 then out[1] = "" end
  lines, cx, cy, top, left, sel = out, 1, 1, 1, 0, nil
  undo, redo, lastKind = {}, {}, nil
  path = p
  lang = langOf(p)
  stValid, cache = 1, {}
  modified = false
  errLine = nil
  wantX = 1
  return true
end

local function loadFile(p)
  if not fs.exists(p) then return false, "No such file" end
  if fs.isDir(p) then return false, "That is a folder" end
  local h = fs.open(p, "rb")
  if not h then return false, "Cannot read that file" end
  local data = h.readAll() or ""
  h.close()
  return openText(data, p)
end

local function checkCode(quiet)
  local text = table.concat(lines, "\n")
  if lang == "lua" then
    local fn, err = load(text, "=code")
    if fn then
      errLine = nil
      if not quiet then note("No mistakes found", colors.lime) end
      return true
    end
    local n, msg = tostring(err):match("code:(%d+): (.*)")
    if n then
      errLine = tonumber(n)
      note("Line " .. n .. ": " .. msg, colors.red)
    else
      note(tostring(err), colors.red)
    end
    return false
  elseif lang == "json" then
    if text:match("^%s*$") then return true end
    local v, err = textutils.unserialiseJSON(text)
    if v == nil and not text:match("^%s*null%s*$") then
      note("Not valid JSON" .. (err and (": " .. tostring(err):gsub("^.-: ", "")) or ""), colors.red)
      return false
    end
    if not quiet then note("JSON is valid", colors.lime) end
    return true
  end
  if not quiet then note("Nothing to check in a text file", colors.lightGray) end
  return true
end

local function save(as)
  local p = path
  if not p or as then
    local dir = p and fs.getDir(p) or ""
    local given = ask("Save as: ", "/" .. (dir ~= "" and (dir .. "/") or ""))
    if not given or given == "" or given:sub(-1) == "/" then return false end
    p = "/" .. fs.combine("", given)
  end
  if fs.isReadOnly(p) then note("That place is read only", colors.red) return false end
  if fs.exists(p) and fs.isDir(p) then note("That name is a folder", colors.red) return false end
  if p ~= path and fs.exists(p) then
    if confirm("Replace " .. fs.getName(p) .. "?  Y yes   N no") ~= "y" then return false end
  end
  local dir = fs.getDir(p)
  if dir ~= "" and not fs.exists(dir) then
    local ok = pcall(fs.makeDir, dir)
    if not ok then note("Cannot make the folder", colors.red) return false end
  end
  local text = table.concat(lines, "\n") .. (trailing and "\n" or "")
  local h = fs.open(p, "wb")
  if not h then note("Cannot save here (disk full or locked)", colors.red) return false end
  h.write(text)
  h.close()
  path = p
  if lang ~= langOf(p) then
    lang = langOf(p)
    stValid, cache = 1, {}
  end
  modified = false
  local ok = checkCode(true)
  if ok then note("Saved " .. #text .. " bytes", colors.lime) else flashColor = colors.red end
  if not ok then flash = "Saved, but " .. (flash or "there is a mistake") end
  return true
end

-- Asks to save when there are changes. Returns true when it is fine to go on.
local function settle()
  if not modified then return true end
  local a = confirm("Save changes to " .. nameOf() .. "?  Y yes   N no   Esc stay")
  if a == "y" then return save() end
  return a == "n"
end

-- A simple file picker. Returns a path, or nil.
local function browse(start)
  local dir = start or ""
  local sel2, top2 = 1, 0
  local items = {}
  local hits = {}
  local function refresh()
    items = {}
    if dir ~= "" then items[#items + 1] = { name = "..", dir = true, path = fs.getDir(dir) } end
    local dirs, files = {}, {}
    local ok, names = pcall(fs.list, "/" .. dir)
    if ok then
      table.sort(names)
      for _, n in ipairs(names) do
        local p = fs.combine(dir, n)
        if fs.isDir(p) then dirs[#dirs + 1] = { name = n .. "/", dir = true, path = p }
        else files[#files + 1] = { name = n, path = p } end
      end
    end
    for _, d in ipairs(dirs) do items[#items + 1] = d end
    for _, f in ipairs(files) do items[#items + 1] = f end
    if sel2 > #items then sel2 = #items end
    if sel2 < 1 then sel2 = 1 end
  end
  refresh()
  while true do
    term.setBackgroundColor(colors.black)
    term.clear()
    put(1, 1, pad(" Open   /" .. dir, W), colors.white, colors.gray)
    local rows = H - 3
    if sel2 - 1 < top2 then top2 = sel2 - 1 end
    if sel2 > top2 + rows then top2 = sel2 - rows end
    hits = {}
    for i = 1, rows do
      local it = items[top2 + i]
      if it then
        local on = top2 + i == sel2
        put(1, 1 + i, pad(" " .. it.name, W), on and colors.black or (it.dir and colors.cyan or colors.white), on and colors.cyan or colors.black)
        local idx = top2 + i
        hits[#hits + 1] = { 1 + i, idx }
      end
    end
    if #items == 0 then put(2, 3, "This folder is empty.", colors.gray) end
    if fs.isReadOnly("/" .. dir) then put(2, H - 2, "Read only place. You can open files, not save.", colors.orange) end
    put(1, H - 1, pad(" Enter: open   N: new file   M: new folder", W), colors.cyan)
    put(1, H, pad(" Esc: cancel", W), colors.lightGray)
    local ev = { os.pullEvent() }
    local it = items[sel2]
    if ev[1] == "key" then
      local k = ev[2]
      if k == keys.up then sel2 = math.max(1, sel2 - 1)
      elseif k == keys.down then sel2 = math.min(#items, sel2 + 1)
      elseif k == keys.pageUp then sel2 = math.max(1, sel2 - rows)
      elseif k == keys.pageDown then sel2 = math.min(#items, sel2 + rows)
      elseif k == keys.escape then return nil
      elseif k == keys.backspace and dir ~= "" then dir = fs.getDir(dir) sel2 = 1 top2 = 0 refresh()
      elseif k == keys.enter and it then
        if it.dir then dir = it.path sel2 = 1 top2 = 0 refresh() else return "/" .. it.path end
      end
    elseif ev[1] == "char" then
      local c = ev[2]:lower()
      if c == "n" then
        local name = ask("New file name: ", "")
        if name and name ~= "" then
          local p = "/" .. fs.combine(dir, name)
          if fs.isReadOnly(p) then note("That place is read only", colors.red)
          elseif fs.exists(p) and fs.isDir(p) then note("That name is a folder", colors.red)
          else
            if not fs.exists(p) then
              local pd = fs.getDir(p)
              if pd ~= "" and not fs.exists(pd) then pcall(fs.makeDir, pd) end
              local h = fs.open(p, "wb")
              if h then h.close() end
            end
            if fs.exists(p) then return p end
            note("Cannot make that file", colors.red)
          end
        end
      elseif c == "m" then
        local name = ask("New folder name: ", "")
        if name and name ~= "" then
          local p = "/" .. fs.combine(dir, name)
          if fs.isReadOnly(p) then note("That place is read only", colors.red)
          elseif pcall(fs.makeDir, p) then refresh()
          else note("Cannot make that folder", colors.red) end
        end
      end
    elseif ev[1] == "mouse_click" then
      for _, h in ipairs(hits) do
        if ev[4] == h[1] then
          local clicked = items[h[2]]
          if sel2 == h[2] and clicked then
            if clicked.dir then dir = clicked.path sel2 = 1 top2 = 0 refresh() else return "/" .. clicked.path end
          else
            sel2 = h[2]
          end
        end
      end
    elseif ev[1] == "mouse_scroll" then
      sel2 = math.max(1, math.min(#items, sel2 + ev[2]))
    end
  end
end

-- ------------------------------------------------------------ actions

local function find(again)
  if not again or findText == "" then
    local t = ask("Find: ", findText)
    if not t or t == "" then return end
    findText = t
  end
  local needle = findText:lower()
  local sx0, sy0 = cx, cy
  local _, _, ex, ey = selRange()
  if ex then sx0, sy0 = ex, ey end
  local function search(y, from, to)
    for yy = y, to do
      local s = lines[yy]:lower():find(needle, yy == y and from or 1, true)
      if s then return s, yy end
    end
  end
  local s, y = search(sy0, sx0, #lines)
  local wrapped = false
  if not s then s, y = search(1, 1, sy0) wrapped = true end
  if s then
    sel = { s, y }
    cx, cy = s + #needle, y
    wantX = cx
    note(wrapped and "Back at the top" or "Found", colors.lightGray)
  else
    note("Not found: " .. findText, colors.orange)
  end
end

local function goTo()
  local t = ask("Go to line (1-" .. #lines .. "): ", "")
  local n = t and tonumber(t)
  if n then moveTo(1, math.floor(n)) else if t then note("Type a number", colors.orange) end end
end

local function newFile()
  if not settle() then return end
  local dir = path and fs.getDir(path) or ""
  local given = ask("New file: ", "/" .. (dir ~= "" and (dir .. "/") or ""))
  if not given or given == "" or given:sub(-1) == "/" then return end
  local p = "/" .. fs.combine("", given)
  if fs.isReadOnly(p) then note("That place is read only", colors.red) return end
  if fs.exists(p) then
    if fs.isDir(p) then note("That name is a folder", colors.red) return end
    local ok, why = loadFile(p)
    if not ok then note(why, colors.red) end
    return
  end
  local pd = fs.getDir(p)
  if pd ~= "" and not fs.exists(pd) then pcall(fs.makeDir, pd) end
  local h = fs.open(p, "wb")
  if not h then note("Cannot make that file", colors.red) return end
  h.close()
  openText("", p)
  note("Made " .. fs.getName(p), colors.lime)
end

local function openFile()
  if not settle() then return end
  local p = browse(path and fs.getDir(path) or "")
  if not p then return end
  local ok, why = loadFile(p)
  if not ok then note(why, colors.red) else note("Opened " .. fs.getName(p), colors.lightGray) end
end

local function copySel(cut)
  if not selRange() then note("Hold Shift and press the arrows to select text", colors.orange) return end
  clip = selText()
  if cut then mark("other") deleteSel() end
  note((cut and "Cut " or "Copied ") .. #clip .. " characters", colors.lightGray)
end

local function act(name)
  if name == "save" then save()
  elseif name == "open" then openFile()
  elseif name == "new" then newFile()
  elseif name == "find" then find(false)
  elseif name == "go" then goTo()
  elseif name == "quit" then
    if settle() then term.setCursorBlink(false) return "quit" end
  end
end

-- ------------------------------------------------------------ start

do
  local arg = ...
  if type(arg) == "string" and arg ~= "" then
    local ok, why = loadFile(arg)
    if not ok then note(why, colors.red) end
  end
end

local function posFromMouse(mx, my)
  local gw = gutterW()
  local y = math.max(1, math.min(#lines, top + my - 2))
  local x = math.max(1, left + mx - gw)
  return math.min(x, #lines[y] + 1), y
end

while true do
  draw()
  local ev = { os.pullEvent() }
  local e = ev[1]
  if e == "key" then
    local k = ev[2]
    if k == keys.leftCtrl or k == keys.rightCtrl then ctrl = true
    elseif k == keys.leftShift or k == keys.rightShift then shift = true
    elseif ctrl then
      -- A prompt hides the key release, so forget the held keys afterwards.
      if k == keys.s then local sh = shift save(sh) ctrl, shift = false, false
      elseif k == keys.o then openFile() ctrl, shift = false, false
      elseif k == keys.n then newFile() ctrl, shift = false, false
      elseif k == keys.f then find(false) ctrl, shift = false, false
      elseif k == keys.g then goTo() ctrl, shift = false, false
      elseif k == keys.k then checkCode(false)
      elseif k == keys.q then
        if act("quit") == "quit" then return end
        ctrl, shift = false, false
      elseif k == keys.z then
        local s = table.remove(undo)
        if s then redo[#redo + 1] = snapshot() restore(s) lastKind = nil else note("Nothing to undo", colors.lightGray) end
      elseif k == keys.y then
        local s = table.remove(redo)
        if s then undo[#undo + 1] = snapshot() restore(s) lastKind = nil else note("Nothing to redo", colors.lightGray) end
      elseif k == keys.a then
        sel = { 1, 1 }
        cy = #lines
        cx = #lines[cy] + 1
      elseif k == keys.c then copySel(false)
      elseif k == keys.x then copySel(true)
      elseif k == keys.v then
        if clip ~= "" then mark("other") insertText(clip) wantX = cx end
      elseif k == keys.d then mark("other") deleteLine()
      elseif k == keys.left then local x, y = wordLeft() moveTo(x, y, shift)
      elseif k == keys.right then local x, y = wordRight() moveTo(x, y, shift)
      elseif k == keys.home then moveTo(1, 1, shift)
      elseif k == keys["end"] then moveTo(#lines[#lines] + 1, #lines, shift)
      end
    elseif k == keys.up then
      if cy > 1 then moveTo(math.min(wantX, #lines[cy - 1] + 1), cy - 1, shift, true) else moveTo(1, 1, shift) end
    elseif k == keys.down then
      if cy < #lines then moveTo(math.min(wantX, #lines[cy + 1] + 1), cy + 1, shift, true) else moveTo(#lines[cy] + 1, cy, shift) end
    elseif k == keys.left then
      if cx > 1 then moveTo(cx - 1, cy, shift)
      elseif cy > 1 then moveTo(#lines[cy - 1] + 1, cy - 1, shift) end
    elseif k == keys.right then
      if cx <= #lines[cy] then moveTo(cx + 1, cy, shift)
      elseif cy < #lines then moveTo(1, cy + 1, shift) end
    elseif k == keys.home then
      local first = #(lines[cy]:match("^%s*") or "") + 1
      moveTo(cx == first and 1 or first, cy, shift)
    elseif k == keys["end"] then moveTo(#lines[cy] + 1, cy, shift)
    elseif k == keys.pageUp then moveTo(cx, cy - areaH() + 1, shift)
    elseif k == keys.pageDown then moveTo(cx, cy + areaH() - 1, shift)
    elseif k == keys.enter then mark("other") newline() wantX = cx
    elseif k == keys.backspace then mark("back") backspace() wantX = cx
    elseif k == keys.delete then mark("other") delete()
    elseif k == keys.tab then
      mark("other")
      if shift then indentLines(true)
      elseif selRange() then indentLines(false)
      else insertText("  ") wantX = cx end
    elseif k == keys.f1 then help() ctrl, shift = false, false
    elseif k == keys.f3 then find(true) ctrl, shift = false, false
    end
  elseif e == "key_up" then
    local k = ev[2]
    if k == keys.leftCtrl or k == keys.rightCtrl then ctrl = false
    elseif k == keys.leftShift or k == keys.rightShift then shift = false end
  elseif e == "char" then
    ctrl = false
    mark("type")
    insertText(ev[2])
    wantX = cx
  elseif e == "paste" then
    mark("other")
    insertText(ev[2])
    wantX = cx
  elseif e == "mouse_click" then
    local mx, my = ev[3], ev[4]
    if my == H then
      for _, h in ipairs(menuHits) do
        if mx >= h[1] and mx <= h[2] then
          if act(h[3]) == "quit" then return end
          ctrl, shift = false, false
          break
        end
      end
    elseif my >= 2 and my <= H - 2 then
      local x, y = posFromMouse(mx, my)
      if shift then moveTo(x, y, true) else sel = nil cx, cy = x, y wantX = x end
      drag = true
    end
  elseif e == "mouse_drag" and drag then
    local mx, my = ev[3], ev[4]
    if my >= 2 and my <= H - 2 then
      if not sel then sel = { cx, cy } end
      local x, y = posFromMouse(mx, my)
      cx, cy = x, y
      wantX = x
    elseif my < 2 then
      top = math.max(1, top - 1)
    end
  elseif e == "mouse_up" then
    drag = false
    if sel and sel[1] == cx and sel[2] == cy then sel = nil end
  elseif e == "mouse_scroll" then
    top = math.max(1, math.min(math.max(1, #lines - areaH() + 1), top + ev[2] * 3))
    -- keep the cursor in view without jumping back
    if cy < top then cy = top elseif cy > top + areaH() - 1 then cy = top + areaH() - 1 end
    clampCursor()
  end
end
