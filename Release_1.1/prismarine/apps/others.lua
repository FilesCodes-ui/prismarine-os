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

local kit = dofile("/prismarine/ui/kit.lua")
local function draw()
  W, H = term.getSize()
  if page == 2 or page == 4 then refreshPw() end
  local s = kit.scene()
  local gray, text, hint = kit.c("bar"), kit.c("barText"), kit.c("hint")
  if W < 40 then
    local x = s:pill(2, 1, PAGES[page], kit.c("sel"), kit.c("selText"))
    s:text(x, 1, page .. "/" .. #PAGES .. " Left/Right", hint, kit.c("bg"))
  else
    s:tabs(2, 1, PAGES, page)
  end
  local ch = H - 4
  local function card(y, h) s:card(2, y, W - 2, h or ch, gray) end
  local function note(y, msgText, col)
    s:text(4, y, kit.fit(msgText, W - 6), col or hint, gray)
  end
  if page == 1 then
    local st = net and net.status()
    card(3, 9)
    s:text(4, 4, "Prismarine OS", kit.c("line"), gray)
    s:text(4 + 14, 4, kit.fit(tostring(api.version), W - 20), text, gray)
    s:text(4, 5, "Computer #" .. os.getComputerID() .. (os.getComputerLabel() and (" (" .. os.getComputerLabel() .. ")") or ""), hint, gray)
    s:rule(4, 6, W - 6, kit.c("hdr"))
    if st then
      s:text(4, 7, "Name", hint, gray)
      s:text(15, 7, kit.fit(tostring(st.name), W - 17), text, gray)
      s:text(4, 8, "Key code", hint, gray)
      s:text(15, 8, kit.fit(tostring(st.fp), W - 17), text, gray)
      s:text(4, 9, "Network", hint, gray)
      s:text(15, 9, kit.fit(st.isArchive and "This is an Archive" or st.enrolled and ("Archive " .. st.archive.name) or "Open (no Archive)", W - 17), text, gray)
      s:text(4, 10, "Modem", hint, gray)
      s:badge(15, 10, st.modem and "found" or "none", st.modem and "ok" or "warn")
    end
    s:card(2, 13, W - 2, H - 15, gray)
    note(14, "Security: password keys, signed and encrypted", text)
    note(15, "messages, system file check at every boot.", hint)
    if H >= 19 then
      note(16, "Crypto: ccryptolib (MIT), Miguel Oliveira.", hint)
      note(17, "Graphics: Pixelbox Lite, 9551-Dev.", hint)
    end
  elseif page == 2 then
    card(3, ch - 1)
    if not account then note(4, "Not available.", kit.c("warn")) else
      note(4, pwOn and "Change your password" or "Password is off. Turn it on.", text)
      local function box(y, label, key)
        s:text(4, y, label, hint, gray)
        s:field(4, y + 1, 30, fields[key], field == key, true)
      end
      if pwOn then box(6, "Current password", "old") end
      box(9, "New password (6+ characters)", "new")
      box(12, "New password again", "again")
      s:text(4, 15, kit.fit(msg, W - 6), msgColor == colors.lime and kit.c("ok") or (msgColor == colors.orange and kit.c("warn") or kit.c("info")), gray)
      s:hintText(H - 1, pwOn and "Tab: next   Enter: change   F4: turn off" or "Tab: next field   Enter: turn password on", 1)
    end
  elseif page == 3 then
    card(3, ch - 1)
    note(4, "Press keys, click, scroll. Esc leaves this page.", hint)
    for i, l in ipairs(lastEv) do s:text(4, 5 + i, kit.fit(l, W - 6), text, gray) end
  elseif page == 5 then
    card(3, ch)
    for i, l in ipairs(GUIDE) do
      if 3 + i < H - 1 then
        local col = l[2] == colors.cyan and kit.c("line") or (l[2] == colors.lightGray and hint or text)
        s:text(4, 3 + i, kit.fit(l[1], W - 6), col, gray)
      end
    end
  elseif page == 4 then
    card(3, ch - 1)
    if not update then note(4, "Not available.", kit.c("warn")) else
      local st = update.status()
      note(4, "Update", text)
      note(6, st.text or "", st.state == "error" and kit.c("warn") or (st.state == "available" and kit.c("warn") or kit.c("ok")))
      if st.state == "installing" and st.frac then
        s:meter(4, 8, W - 6, st.frac, kit.c("ok"), kit.c("bg"))
      end
      if st.state == "available" then
        if pwOn then
          note(9, "Password to install:", hint)
          s:field(4, 10, 30, fields.upw, true, true)
        else
          note(9, "No password is set.", hint)
        end
        note(12, "Enter: install", kit.c("line"))
      elseif st.state == "done" then
        note(9, "Press R to reboot now.", kit.c("line"))
      else
        note(9, "Press C to check again.", kit.c("line"))
      end
      note(14, "Files are downloaded, checked against their", hint)
      note(15, "SHA-256, then swapped in. Your password is", hint)
      note(16, "needed. The boot check is renewed for you.", hint)
    end
  end
  s:flush()
  term.setCursorBlink(false)
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
  local ticked = (ev[1] == "timer" and ev[2] == refresh)
  if ticked then refresh = os.startTimer(0.5) end
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
    local x = 2
    for i, t in ipairs(PAGES) do
      local w = #t + 2
      if ev[3] >= x and ev[3] < x + w then page = i end
      x = x + #t + 3
    end
  end
  if not (ticked and page ~= 4 and page ~= 2) then draw() end
end
