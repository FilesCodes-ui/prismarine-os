--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- Prismarine Others. About, password, secure boot, input test, update help.
-- Keys: Left/Right page, q quit.
local api = prismarine
local account, ui, update = api.account, api.ui, api.update
local net = api.net
local W, H = term.getSize()
local PAGES = { "About", "Password", "Input test", "Update", "Guides" }
local page = 1
local fields = { old = "", new = "", again = "", upw = "" }
local field = "old"
local pwOn = true
local function refreshPw()
  local st = account and account.status and account.status() or {}
  pwOn = st.password ~= false
  if not pwOn and field == "old" then field = "new" end
  if pwOn and field == nil then field = "old" end
end
refreshPw()
local msg, msgColor = "", colors.lightGray
local lastEv = {}

local function put(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local GUIDE = {
  { "More disk space", colors.cyan },
  { "" },
  { "Prismarine needs about 0.5 MB. A computer holds", colors.white },
  { "only 1 MB until you raise the limit.", colors.white },
  { "" },
  { "1. Close the world.", colors.white },
  { "2. Open the world folder, then serverconfig.", colors.white },
  { "3. Open computercraft-server.toml in a text", colors.white },
  { "   editor, such as Notepad.", colors.white },
  { "4. Find computer_space_limit and set it to", colors.white },
  { "   20000000. That is 20 MB.", colors.white },
  { "5. Save the file and open the world again.", colors.white },
  { "" },
  { "On a server, edit the same file inside the", colors.lightGray },
  { "world folder, then restart the server.", colors.lightGray },
  { "" },
  { "Computers you already have get the new limit.", colors.lightGray },
}

local function draw()
  if page == 2 or page == 4 then refreshPw() end
  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorBlink(false)
  local x = 1
  put(1, 1, string.rep(" ", W), colors.white, colors.gray)
  for i, t in ipairs(PAGES) do
    local on = i == page
    put(x, 1, " " .. t .. " ", on and colors.white or colors.lightGray, on and colors.blue or colors.gray)
    x = x + #t + 3
  end
  if page == 1 then
    local st = net and net.status()
    put(2, 3, "Prismarine OS " .. tostring(api.version), colors.cyan)
    put(2, 4, "Computer #" .. os.getComputerID() .. (os.getComputerLabel() and (" (" .. os.getComputerLabel() .. ")") or ""), colors.white)
    if st then
      put(2, 6, "Name:      " .. tostring(st.name), colors.white)
      put(2, 7, "Key code:  " .. tostring(st.fp), colors.white)
      put(2, 8, "Network:   " .. (st.isArchive and "This is an Archive" or st.enrolled and ("Archive " .. st.archive.name) or "Open (no Archive)"), colors.white)
      put(2, 9, "Modem:     " .. (st.modem and "found" or "none"), st.modem and colors.lime or colors.orange)
    end
    put(2, 11, "Security: password keys, signed and encrypted", colors.lightGray)
    put(2, 12, "messages, system file check at every boot.", colors.lightGray)
    put(2, 14, "Crypto: ccryptolib (MIT), Miguel Oliveira.", colors.gray)
    put(2, 15, "Graphics: Pixelbox Lite, 9551-Dev.", colors.gray)
  elseif page == 2 then
    if not account then put(2, 3, "Not available.", colors.orange) else
      put(2, 3, pwOn and "Change your password" or "Password is off. Turn it on.", colors.white)
      local function box(y, label, key)
        put(2, y, label, colors.lightGray)
        put(2, y + 1, (" " .. string.rep("*", #fields[key]) .. string.rep(" ", W)):sub(1, 30), colors.white, field == key and colors.blue or colors.gray)
      end
      if pwOn then box(5, "Current password", "old") end
      box(8, "New password (6+ characters)", "new")
      box(11, "New password again", "again")
      put(2, 14, msg, msgColor)
      put(2, 16, pwOn and "Tab: next   Enter: change   F4: turn off" or "Tab: next field   Enter: turn password on", colors.cyan)
      if pwOn then put(2, 17, "F4 uses the current password box.", colors.gray) end
      local y = ({ old = 6, new = 9, again = 12 })[field]
      term.setCursorPos(3 + #fields[field], y)
      term.setCursorBlink(true)
    end
  elseif page == 3 then
    put(2, 3, "Press keys, click, scroll. Esc leaves this page.", colors.lightGray)
    for i, l in ipairs(lastEv) do put(2, 4 + i, l:sub(1, W - 2), colors.white) end
  elseif page == 5 then
    for i, l in ipairs(GUIDE) do
      if 2 + i < H then put(2, 2 + i, l[1], l[2]) end
    end
  elseif page == 4 then
    if not update then put(2, 3, "Not available.", colors.orange) else
      local st = update.status()
      put(2, 3, "Update", colors.white)
      put(2, 5, st.text or "", st.state == "error" and colors.orange or (st.state == "available" and colors.yellow or colors.lime))
      if st.state == "installing" and st.frac then
        local n = math.floor(30 * st.frac)
        put(2, 7, "[" .. string.rep("=", n) .. string.rep(" ", 30 - n) .. "]", colors.cyan)
      end
      if st.state == "available" then
        if pwOn then
          put(2, 8, "Password to install:", colors.lightGray)
          put(2, 9, (" " .. string.rep("*", #fields.upw) .. string.rep(" ", 30)):sub(1, 30), colors.white, colors.blue)
          term.setCursorPos(3 + #fields.upw, 9)
          term.setCursorBlink(true)
        else
          put(2, 8, "No password is set.", colors.lightGray)
        end
        put(2, 11, "Enter: install", colors.cyan)
      elseif st.state == "done" then
        put(2, 8, "Press R to reboot now.", colors.cyan)
      else
        put(2, 8, "Press C to check again.", colors.cyan)
      end
      put(2, 14, "Files are downloaded, checked against their", colors.gray)
      put(2, 15, "SHA-256, then swapped in. Your password is", colors.gray)
      put(2, 16, "needed. The boot check is renewed for you.", colors.gray)
    end
  end
end

local function changePassword()
  if fields.new ~= fields.again then msg, msgColor = "The new passwords differ.", colors.orange return end
  if #fields.new < 6 then msg, msgColor = "Use at least 6 characters.", colors.orange return end
  msg, msgColor = "Working...", colors.yellow
  draw()
  local ok, why
  if pwOn then ok, why = account.changePassword(fields.old, fields.new)
  else ok, why = account.enablePassword(fields.new) end
  if ok then
    msg, msgColor = pwOn and "Password changed." or "Password is on. F9 locks.", colors.lime
    fields = { old = "", new = "", again = "", upw = "" }
    refreshPw()
    field = pwOn and "old" or "new"
  else
    msg, msgColor = (why == "locked" and "Too many tries. Wait." or why == "wrong" and "Wrong current password." or "Could not change it."), colors.orange
  end
end

local function turnOff()
  if not pwOn then return end
  msg, msgColor = "Working...", colors.yellow
  draw()
  local ok, why = account.disablePassword(fields.old)
  if ok then
    msg, msgColor = "Password is off.", colors.lime
    fields = { old = "", new = "", again = "", upw = "" }
    refreshPw()
  elseif why == "archive" then
    msg, msgColor = "Archive computers keep a password.", colors.orange
  else
    msg, msgColor = (why == "locked" and "Too many tries. Wait." or why == "wrong" and "Wrong current password." or "Could not turn it off."), colors.orange
  end
end

draw()
local refresh = os.startTimer(0.5)
while true do
  local ev = { os.pullEvent() }
  if ev[1] == "timer" and ev[2] == refresh then refresh = os.startTimer(0.5) end
  local e = ev[1]
  if page == 3 and e ~= "timer" and e ~= "pm_net" then
    local s = e
    for i = 2, math.min(#ev, 5) do s = s .. " " .. tostring(ev[i]) end
    table.insert(lastEv, 1, s)
    while #lastEv > H - 6 do table.remove(lastEv) end
  end
  if page == 2 and account then
    if e == "char" then fields[field] = fields[field] .. ev[2]
    elseif e == "key" then
      if ev[2] == keys.backspace then fields[field] = fields[field]:sub(1, -2)
      elseif ev[2] == keys.tab then
        if pwOn then field = ({ old = "new", new = "again", again = "old" })[field]
        else field = (field == "new") and "again" or "new" end
      elseif ev[2] == keys.f4 then turnOff()
      elseif ev[2] == keys.enter then changePassword() end
    end
  end
  if page == 4 and update then
    local st = update.status()
    if st.state == "available" then
      if e == "char" then fields.upw = fields.upw .. ev[2]
      elseif e == "key" and ev[2] == keys.backspace then fields.upw = fields.upw:sub(1, -2)
      elseif e == "key" and ev[2] == keys.enter then
        update.install(fields.upw)
        fields.upw = ""
      end
    elseif e == "char" and (ev[2] == "c" or ev[2] == "C") then update.check()
    elseif e == "char" and (ev[2] == "r" or ev[2] == "R") and st.state == "done" then update.reboot()
    end
  end
  if e == "key" then
    if ev[2] == keys.right and page ~= 2 and not (page == 4 and update and update.status().state == "available") then page = page % #PAGES + 1
    elseif ev[2] == keys.left and page ~= 2 and not (page == 4 and update and update.status().state == "available") then page = (page - 2) % #PAGES + 1
    elseif ev[2] == keys.pageDown then page = page % #PAGES + 1
    elseif ev[2] == keys.pageUp then page = (page - 2) % #PAGES + 1
    elseif ev[2] == keys.escape and page == 3 then page = 1 end
  elseif e == "char" and ev[2] == "q" and page ~= 2 and page ~= 3 and not (page == 4 and update and update.status().state == "available") then
    return
  elseif e == "mouse_click" and ev[4] == 1 then
    local x = 1
    for i, t in ipairs(PAGES) do
      local w = #t + 2
      if ev[3] >= x and ev[3] < x + w then page = i end
      x = x + #t + 3
    end
  end
  draw()
end
