-- Prismarine Download. Fetch a file from the web into /downloads.
-- It shows the SHA-256 so you can check it against the publisher.
-- Downloaded programs never run in Archive mode until the Archive approves them.
local api = prismarine
local tools = api.tools
local W, H = term.getSize()
local url, name = "", ""
local field = 1
local status = { "Type a web address, then press Enter.", colors.lightGray }
local busy = false

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  put(1, 1, (" Download" .. string.rep(" ", W)):sub(1, W), colors.white, colors.gray)
  put(2, 3, "Web address (https only):", colors.lightGray)
  put(2, 4, (" " .. url .. string.rep(" ", W)):sub(1, W - 2), colors.white, field == 1 and colors.blue or colors.gray)
  put(2, 6, "Save as (in /downloads):", colors.lightGray)
  put(2, 7, (" " .. name .. string.rep(" ", W)):sub(1, W - 2), colors.white, field == 2 and colors.blue or colors.gray)
  put(2, 9, status[1]:sub(1, W - 2), status[2])
  put(2, H, "Tab: switch field   Enter: download   Esc: quit", colors.cyan)
  if field == 1 then term.setCursorPos(3 + #url, 4) else term.setCursorPos(3 + #name, 7) end
  term.setCursorBlink(true)
end

local function fetch()
  if busy then return end
  if not url:match("^https://[%w%.%-]+/") then status = { "Use an https:// address.", colors.orange } return end
  if name == "" then name = url:match("([^/]+)$") or "download.lua" name = name:gsub("[^%w%._%-]", "_") end
  if name:find("/") or name:find("%.%.") then status = { "That name is not allowed.", colors.orange } return end
  busy = true
  status = { "Downloading...", colors.yellow }
  draw()
  http.request({ url = url, binary = true })
end

draw()
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]
  if e == "char" then
    if field == 1 then url = url .. ev[2] else name = name .. ev[2] end
  elseif e == "paste" then
    if field == 1 then url = url .. ev[2]:gsub("%c", "") else name = name .. ev[2]:gsub("%c", "") end
  elseif e == "key" then
    local k = ev[2]
    if k == keys.backspace then
      if field == 1 then url = url:sub(1, -2) else name = name:sub(1, -2) end
    elseif k == keys.tab then field = field % 2 + 1
    elseif k == keys.enter then fetch()
    elseif k == keys.escape then return end
  elseif e == "http_success" and ev[2] == url then
    local h = ev[3]
    local data = h.readAll()
    h.close()
    busy = false
    if not data or #data == 0 then
      status = { "The server sent nothing.", colors.orange }
    elseif #data > 1000000 then
      status = { "Too big (1 MB limit).", colors.orange }
    else
      if not fs.exists("/downloads") then fs.makeDir("/downloads") end
      local f = fs.open("/downloads/" .. name, "wb")
      if f then
        f.write(data)
        f.close()
        status = { "Saved /downloads/" .. name .. "  sha256 " .. (tools and tools.sha256(data):sub(1, 16) or "?") .. "...", colors.lime }
      else
        status = { "Could not save the file.", colors.orange }
      end
    end
  elseif e == "http_failure" and ev[2] == url then
    busy = false
    status = { "Download failed: " .. tostring(ev[3] or "no reason"), colors.orange }
  end
  draw()
end
