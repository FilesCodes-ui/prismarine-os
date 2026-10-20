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

local function tabs()
  put(1, 1, pad(" Download", W), colors.white, colors.gray)
  if store then
    put(14, 1, " Official ", tab == 1 and colors.black or colors.white, tab == 1 and colors.cyan or colors.gray)
    hits[#hits + 1] = { 14, 1, 23, 1, function() tab = 1 end }
  end
  put(25, 1, " Custom link ", tab == 2 and colors.black or colors.white, tab == 2 and colors.cyan or colors.gray)
  hits[#hits + 1] = { 25, 1, 37, 1, function() tab = 2 end }
end

local function drawOfficial()
  local st = store.status()
  local area = H - 5
  if sel > #st.entries then sel = #st.entries end
  if sel < 1 then sel = 1 end
  if sel - 1 < top then top = sel - 1 end
  if sel > top + area then top = sel - area end
  for i = 1, area do
    local e = st.entries[top + i]
    if e then
      local on = (top + i == sel)
      local bg = on and colors.cyan or colors.black
      put(1, 2 + i, pad(" " .. e.name, 13), on and colors.black or colors.white, bg)
      put(14, 2 + i, pad(e.about, W - 32), on and colors.black or colors.lightGray, bg)
      put(W - 18, 2 + i, pad(sizeText(e.size), 8), on and colors.black or colors.gray, bg)
      local label, fg = "[ Get ]", colors.lime
      if e.status == "installed" then label, fg = "Installed", colors.gray
      elseif e.status == "update" then label, fg = "[Update]", colors.yellow end
      if st.busy == e.name then label, fg = "Working..", colors.yellow end
      put(W - 9, 2 + i, pad(label, 9), on and colors.black or fg, bg)
      local idx = top + i
      hits[#hits + 1] = { 1, 2 + i, W, 2 + i, function() sel = idx end }
      hits[#hits + 1] = { W - 10, 2 + i, W, 2 + i, function() sel = idx; store.install(e.name) end }
    end
  end
  if #st.entries == 0 then
    put(2, 4, st.state == "loading" and "Loading the list..." or "Nothing to show.", colors.gray)
  end
  local line = st.text
  if flash and os.clock() - flashAt < 3 then line = flash end
  local fg = colors.lightGray
  if st.state == "error" then fg = colors.orange end
  if st.signed == "ok" and st.state == "ready" and (line or "") == "" then line, fg = "Signed list. Every file is hash checked.", colors.lime end
  if st.signed == "none" and st.state == "ready" and (line or "") == "" then line, fg = "This list is not signed. Files are still hash checked.", colors.yellow end
  put(2, H - 2, pad(line or "", W - 2), fg)
  put(2, H - 1, pad("Enter: get   R: reload   Tab: custom link   Esc: quit", W - 2), colors.cyan)
  if st.state == "installing" and st.frac then
    local n = math.floor((W - 4) * st.frac)
    put(2, H - 3, string.rep(" ", n), colors.black, colors.lime)
  end
end

local function drawCustom()
  put(2, 3, "Web address (https only):", colors.lightGray)
  put(2, 4, pad(" " .. url, W - 2), colors.white, field == 1 and colors.blue or colors.gray)
  put(2, 6, "Save as (in /downloads):", colors.lightGray)
  put(2, 7, pad(" " .. name, W - 2), colors.white, field == 2 and colors.blue or colors.gray)
  put(2, 9, status[1]:sub(1, W - 2), status[2])
  put(2, 10, ("Limit " .. sizeText(LIMIT) .. ". Free: " .. sizeText(fs.getFreeSpace("/"))), colors.gray)
  put(2, H, store and "Tab: official list   Enter: download   Esc: quit" or "Tab: switch field   Enter: download   Esc: quit", colors.cyan)
  if field == 1 then term.setCursorPos(math.min(W - 1, 3 + #url), 4) else term.setCursorPos(math.min(W - 1, 3 + #name), 7) end
  term.setCursorBlink(true)
end

local function draw()
  hits = {}
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorBlink(false)
  tabs()
  if tab == 1 and store then drawOfficial() else drawCustom() end
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
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  if e == "timer" and ev[2] == tick then
    tick = os.startTimer(0.5)
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
  draw()
end
