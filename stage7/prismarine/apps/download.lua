--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Download.
--   Official: apps and music from the signed KHI list. Each file is checked
--             against a pinned SHA-256 before it is saved.
--   Custom link: any https address. Shows the SHA-256 so you can compare it
--             with the publisher. The 18 MB limit keeps a 20 MB computer safe.
-- Downloaded programs never run in Archive mode until the Archive approves them.
local api = prismarine
local tools, store = api.tools, api.store
local W, H = term.getSize()

local LIMIT = 18000000
local tab = (store and 1 or 2)
local url, name = "", ""
local field = 1
local status = { "Type a web address, then press Enter.", colors.lightGray }
local busy = false
local sel, top = 1, 0
local hits = {}
local flash, flashAt = nil, 0

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function pad(s, n)
  s = tostring(s)
  if #s >= n then return s:sub(1, n) end
  return s .. string.rep(" ", n - #s)
end

local function sizeText(n)
  if n >= 1000000 then return ("%.1f MB"):format(n / 1000000) end
  return math.max(1, math.floor(n / 1000 + 0.5)) .. " KB"
end

-- Spaces and a few other characters must be encoded in a web address.
local function encode(u)
  return (u:gsub("[^%w%-%._~:/%?#%[%]@!$&'()*+,;=%%]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

local function decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function explain(why)
  why = tostring(why or "")
  local l = why:lower()
  if l:find("too large") or l:find("too big") then return "The file is too big for this server's limit." end
  if l:find("malformed") then return "That web address is not valid. Check it for odd characters." end
  if l:find("domain") or l:find("not whitelisted") or l:find("blocked") then return "The server does not allow that website." end
  if l:find("404") or l:find("not found") then return "No file at that address (404)." end
  return "Download failed: " .. (why ~= "" and why or "no reason")
end

local kit = dofile("/prismarine/ui/kit.lua")

local function head(s)
  s:header("Download", nil, nil)
  local x = (W < 40) and 13 or 14
  local function tabBtn(label, which)
    local on = (tab == which)
    local x0 = x
    x = s:pill(x, 1, label, on and kit.c("sel") or kit.c("bar"), on and kit.c("selText") or kit.c("hint"))
    hits[#hits + 1] = { x0, 1, x - 2, 1, function() tab = which end }
  end
  if store then tabBtn("Official", 1) end
  tabBtn(W < 40 and "Link" or "Custom link", 2)
end

local function drawOfficial(s, st)
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  local ch = H - 6
  local area = ch - 2
  if sel > #st.entries then sel = #st.entries end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + area then top = sel - area end
  if top < 0 then top = 0 end
  s:card(2, 3, W - 2, ch, gray)
  local nameW = math.min(14, math.floor(W / 4))
  for i = 1, area do
    local e = st.entries[top + i]
    if e then
      local idx = top + i
      local on = (idx == sel)
      local y = 3 + i
      if on then s:card(3, y, W - 4, 1, kit.c("sel")) end
      local bg = on and kit.c("sel") or gray
      local fg = on and kit.c("selText") or text
      local label, kind = "Get", "ok"
      if e.status == "installed" then label, kind = "Installed", "dim"
      elseif e.status == "update" then label, kind = "Update", "warn" end
      if st.busy == e.name then label, kind = "Working", "warn" end
      s:text(4, y, kit.fit(e.name, nameW), fg, bg)
      s:text(4 + nameW + 1, y, kit.fit(e.about, math.max(0, W - 8 - nameW - 1 - #label - 3)), on and kit.c("selText") or hint, bg)
      local bx = W - #label - 5
      if on then
        s:text(bx + 1, y, label, kit.c("selText"), bg)
      else
        s:badge(bx, y, label, kind)
      end
      hits[#hits + 1] = { 3, y, W - 3, y, function() sel = idx end }
      hits[#hits + 1] = { bx, y, W - 3, y, function() sel = idx; store.install(e.name) end }
    end
  end
  s:scroll(W - 1, 4, area, #st.entries, top, area)
  if #st.entries == 0 then
    if st.state == "loading" then
      s:empty(2, 3, W - 2, ch, { "Loading the list...", "One moment." })
    else
      s:empty(2, 3, W - 2, ch, { "Nothing to show", "Press R to try again." })
    end
  end
  local line = st.text
  if flash and os.clock() - flashAt < 3 then line = flash end
  local level = nil
  if st.state == "error" then level = "warn" end
  if st.signed == "ok" and st.state == "ready" and (line or "") == "" then line, level = "Signed list. Every file is hash checked.", "ok" end
  if st.signed == "none" and st.state == "ready" and (line or "") == "" then line, level = "This list is not signed. Files are still hash checked.", "warn" end
  if st.state == "installing" and st.frac then
    s:meter(2, H - 3, W - 2, st.frac, kit.c("ok"), kit.c("bar"))
  end
  if (line or "") ~= "" then s:status(H - 2, line, level) end
  s:hints(H - 1, { { "Enter", "get" }, { "R", "reload" }, { "Tab", "custom link" }, { "Esc", "quit" } })
end

local function drawCustom(s)
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  s:card(2, 3, W - 2, 10, gray)
  s:text(4, 4, "Web address (https only)", hint, gray)
  s:field(4, 5, W - 6, url, field == 1, false, "https://")
  s:text(4, 7, "Save as (in /downloads)", hint, gray)
  s:field(4, 8, W - 6, name, field == 2, false, "file name")
  local sc = status[2]
  local lvl = (sc == colors.orange or sc == colors.yellow) and "warn" or ((sc == colors.lime) and "ok" or nil)
  local col = (lvl == "warn" and kit.c("warn")) or (lvl == "ok" and kit.c("ok")) or kit.c("info")
  s:text(4, 10, kit.fit(status[1], W - 6), col, gray)
  s:text(4, 12, "Limit " .. sizeText(LIMIT) .. "    Free " .. sizeText(fs.getFreeSpace("/")), hint, gray)
  s:hints(H - 1, store and { { "Tab", "official list" }, { "Enter", "download" }, { "Esc", "quit" } }
    or { { "Tab", "switch field" }, { "Enter", "download" }, { "Esc", "quit" } })
end

-- Ask the OS for the list before drawing. A call into the OS pauses this app.
local function draw()
  W, H = term.getSize()
  hits = {}
  local st = (tab == 1 and store) and store.status() or nil
  local s = kit.scene()
  head(s)
  if st then drawOfficial(s, st) else drawCustom(s) end
  s:flush()
end

local function fetch()
  if busy then return end
  if not url:match("^https://[%w%.%-]+/") then status = { "Use an https:// address.", colors.orange } return end
  if name == "" then
    name = decode(url:match("([^/%?#]+)[%?#]?[^/]*$") or "download.lua")
    name = name:gsub("[^%w%._%- ]", "_")
  end
  if name:find("/") or name:find("%.%.") then status = { "That name is not allowed.", colors.orange } return end
  busy = true
  status = { "Downloading...", colors.yellow }
  draw()
  http.request({ url = encode(url), binary = true })
end

local function saveBody(h)
  local data = h.readAll()
  h.close()
  busy = false
  if not data or #data == 0 then
    status = { "The server sent nothing.", colors.orange }
  elseif #data > LIMIT then
    status = { "Too big (" .. sizeText(LIMIT) .. " limit).", colors.orange }
  elseif #data + 20000 > fs.getFreeSpace("/") then
    status = { "Not enough free space (" .. sizeText(fs.getFreeSpace("/")) .. " free).", colors.orange }
  else
    if not fs.exists("/downloads") then fs.makeDir("/downloads") end
    local f = fs.open("/downloads/" .. name, "wb")
    if f then
      f.write(data)
      f.close()
      local sum = "(big file, not hashed)"
      if tools and #data <= 1000000 then
        local ok, hex = pcall(tools.sha256, data)
        sum = ok and ("sha256 " .. hex:sub(1, 16) .. "...") or "?"
      end
      status = { "Saved /downloads/" .. name .. "  " .. sum, colors.lime }
    else
      status = { "Could not save the file.", colors.orange }
    end
  end
end

if store then store.refresh() end
draw()
local tick = os.startTimer(0.5)
local lastSig = ""
local skip = false
local function signature()
  if not (tab == 1 and store) then return "custom" .. tostring(busy) end
  local st = store.status()
  local n = 0
  for _, e in ipairs(st.entries) do n = n + #tostring(e.status) end
  local fl = (flash and os.clock() - flashAt < 3) and flash or ""
  return table.concat({ tostring(st.state), tostring(st.busy), tostring(st.frac), tostring(st.text),
    tostring(#st.entries), n, tostring(st.signed), fl }, "|")
end
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  skip = false
  if e == "timer" and ev[2] == tick then
    tick = os.startTimer(0.5)
    -- Redraw only when something changed, so the screen stays still.
    local sig = signature()
    if sig == lastSig then skip = true end
    lastSig = sig
  elseif e == "mouse_click" then
    for _, h in ipairs(hits) do
      if ev[4] == h[2] and ev[3] >= h[1] and ev[3] <= h[3] then h[5]() break end
    end
  elseif e == "mouse_scroll" and tab == 1 then
    sel = sel + ev[2]
  elseif tab == 1 and store then
    if e == "key" then
      local k = ev[2]
      if k == keys.up then sel = sel - 1
      elseif k == keys.down then sel = sel + 1
      elseif k == keys.tab then tab = 2
      elseif k == keys.r then store.refresh()
      elseif k == keys.enter then
        local st = store.status()
        local ent = st.entries[sel]
        if ent then
          local ok, why = store.install(ent.name)
          if not ok then flash, flashAt = tostring(why), os.clock() end
        end
      elseif k == keys.escape or k == keys.q then return end
    end
  else
    if e == "char" then
      if field == 1 then url = url .. ev[2] else name = name .. ev[2] end
    elseif e == "paste" then
      local t = ev[2]:gsub("%c", "")
      if field == 1 then url = url .. t else name = name .. t end
    elseif e == "key" then
      local k = ev[2]
      if k == keys.backspace then
        if field == 1 then url = url:sub(1, -2) else name = name:sub(1, -2) end
      elseif k == keys.tab then
        if field == 1 then field = 2 elseif store then tab, field = 1, 1 else field = 1 end
      elseif k == keys.enter then fetch()
      elseif k == keys.escape then return end
    elseif e == "http_success" and busy and ev[2] == encode(url) then
      saveBody(ev[3])
    elseif e == "http_failure" and busy and ev[2] == encode(url) then
      busy = false
      status = { explain(ev[3]), colors.orange }
    end
  end
  if not skip then draw() end
end
