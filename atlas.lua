-- atlas.lua
-- Map atlas for Lake's CC Additions (Forge 1.20.1, CC:Tweaked 1.119+)
--   atlas import          scan filled maps and export an atlas to a disk
--   atlas view [monitor]  show the atlas on this screen, a monitor, or a named peripheral
--   atlas probe           write raw scanner map data to /atlas_probe.txt

local args = { ... }
local PROGRAM = shell.getRunningProgram()
local DIR = "atlas"

-- Palette slots used for map colours. The other slots keep their normal colours
-- (white, black, red, yellow, lime, cyan) for text, pins and buttons.
local MAP_SLOTS = { 1, 2, 3, 6, 7, 8, 10, 11, 12, 13 }
local BLACK = 15
local PIN_COLORS = { red = colors.red, yellow = colors.yellow, lime = colors.lime, cyan = colors.cyan, white = colors.white }
local PIN_ORDER = { "red", "yellow", "lime", "cyan", "white" }
local ZOOMS = { 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4 }

-- Vanilla map base colours by colour id (0 to 61), then brightness multipliers.
local BASE = { [0] = 0x000000,
  0x7FB238, 0xF7E9A3, 0xC7C7C7, 0xFF0000, 0xA0A0FF, 0xA7A7A7, 0x007C00, 0xFFFFFF,
  0xA4A8B8, 0x976D4D, 0x707070, 0x4040FF, 0x8F7748, 0xFFFCF5, 0xD87F33, 0xB24CD8,
  0x6699D8, 0xE5E533, 0x7FCC19, 0xF27FA5, 0x4C4C4C, 0x999999, 0x4C7F99, 0x7F3FB2,
  0x334CB2, 0x664C33, 0x667F33, 0x993333, 0x191919, 0xFAEE4D, 0x5CDBD5, 0x4A80FF,
  0x00D93A, 0x815631, 0x700200,
  0xD1B1A1, 0x9F5224, 0x95576C, 0x706C8A, 0xBA8524, 0x677535, 0xA04D4E, 0x392923,
  0x876B62, 0x575C5C, 0x7A4958, 0x4C3E5C, 0x4C3223, 0x4C522A, 0x8E3C2E, 0x251610,
  0xBD3031, 0x943F61, 0x5C191D, 0x167E86, 0x3A8E8C, 0x562C3E, 0x14B485, 0x646464,
  0xD8AF93, 0x7FA796 }
local BRIGHT = { [0] = 180, 220, 255, 135 }

---------------------------------------------------------------- files

local function readFile(path, mode)
  local f = fs.open(path, mode or "r")
  if not f then return nil end
  local d = f.readAll()
  f.close()
  return d
end

local function writeFile(path, data, mode)
  local f = fs.open(path, mode or "w")
  if not f then return false end
  local ok = pcall(f.write, data)
  f.close()
  return ok
end

local function loadTable(path)
  local d = readFile(path)
  return d and textutils.unserialize(d)
end

local function rleEncode(rows)
  local s = table.concat(rows)
  local out, n, i = {}, #s, 1
  while i <= n do
    local b = s:byte(i)
    local j = i
    while j < n and j - i < 254 and s:byte(j + 1) == b do j = j + 1 end
    out[#out + 1] = string.char(j - i + 1, b)
    i = j + 1
  end
  return table.concat(out)
end

local function rleDecode(data)
  local parts = {}
  for i = 1, #data - 1, 2 do
    parts[#parts + 1] = string.rep(string.char(data:byte(i + 1)), data:byte(i))
  end
  local s = table.concat(parts)
  local rows = {}
  for r = 0, 127 do rows[r + 1] = s:sub(r * 128 + 1, r * 128 + 128) end
  return rows
end

---------------------------------------------------------------- atlas data

local function newAtlas(mount)
  return { id = tostring(os.epoch("utc")), tiles = {}, list = {}, mount = mount, shared = false, pins = {} }
end

local function addTile(atlas, gx, gz, cx, cz, rows)
  atlas.tiles[gx] = atlas.tiles[gx] or {}
  atlas.tiles[gx][gz] = rows
  atlas.list[gx .. "," .. gz] = { gx, gz, cx, cz }
end

local function diskMounts()
  local list = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "drive" and disk.hasData(n) then
      local p = disk.getMountPath(n)
      if p then list[#list + 1] = p end
    end
  end
  return list
end

local function pinsPath(atlas)
  if atlas.shared then return fs.combine(atlas.mount, DIR, "markers") end
  return "/atlas_local/" .. atlas.id
end

local function loadPins(atlas)
  return loadTable(pinsPath(atlas)) or {}
end

local function savePins(atlas)
  if not atlas.shared then fs.makeDir("/atlas_local") end
  return writeFile(pinsPath(atlas), textutils.serialize(atlas.pins))
end

local function loadAtlas(mount)
  local idx = loadTable(fs.combine(mount, DIR, "index"))
  if not idx then return nil end
  local atlas = newAtlas(mount)
  atlas.id, atlas.scale, atlas.dim, atlas.shared = idx.id, idx.scale, idx.dim, idx.shared
  for _, t in ipairs(idx.tiles) do
    local data = readFile(fs.combine(mount, DIR, t[1] .. "_" .. t[2] .. ".rle"), "rb")
    if data then addTile(atlas, t[1], t[2], t[3], t[4], rleDecode(data)) end
  end
  return atlas
end

local function exportAtlas(atlas)
  local mount = atlas.mount
  local dir = fs.combine(mount, DIR)
  fs.makeDir(dir)
  local blobs, total, idx = {}, 0, { version = 1, id = atlas.id, scale = atlas.scale, dim = atlas.dim, shared = atlas.shared, tiles = {} }
  for _, t in pairs(atlas.list) do
    local data = rleEncode(atlas.tiles[t[1]][t[2]])
    blobs[t[1] .. "_" .. t[2] .. ".rle"] = data
    total = total + #data + 512
    idx.tiles[#idx.tiles + 1] = t
  end
  local pinData = atlas.shared and textutils.serialize(atlas.pins) or ""
  total = total + #pinData + #textutils.serialize(idx) + 1024
  local dest = fs.combine(mount, "atlas.lua")
  local copyProgram = fs.combine(PROGRAM) ~= dest
  if copyProgram then total = total + fs.getSize(PROGRAM) + 512 end
  local existing = 0
  for _, n in ipairs(fs.list(dir)) do existing = existing + fs.getSize(fs.combine(dir, n)) end
  if copyProgram and fs.exists(dest) then existing = existing + fs.getSize(dest) end
  local free = fs.getFreeSpace(mount) + existing
  if total > free then
    print(("Disk too small. Need %d bytes, have %d."):format(total, free))
    print("Use fewer maps, a second disk, or raise floppy_space_limit in the server config.")
    return false
  end
  for _, n in ipairs(fs.list(dir)) do fs.delete(fs.combine(dir, n)) end
  for name, data in pairs(blobs) do
    if not writeFile(fs.combine(dir, name), data, "wb") then print("Write failed: " .. name) return false end
  end
  writeFile(fs.combine(dir, "index"), textutils.serialize(idx))
  if atlas.shared then
    writeFile(fs.combine(dir, "markers"), pinData)
  else
    savePins(atlas)
  end
  if copyProgram then
    if fs.exists(dest) then fs.delete(dest) end
    fs.copy(PROGRAM, dest)
  end
  return true
end

---------------------------------------------------------------- colours

local function baseRGB(v)
  local base = BASE[math.floor(v / 4)]
  if not base then return nil end
  local m = BRIGHT[v % 4] / 255
  return math.floor(math.floor(base / 65536) * m),
    math.floor((math.floor(base / 256) % 256) * m),
    math.floor((base % 256) * m)
end

-- Median cut over the colours that appear in the atlas.
local function buildPalette(atlas)
  local counts = {}
  for _, col in pairs(atlas.tiles) do
    for _, rows in pairs(col) do
      for _, row in ipairs(rows) do
        for i = 1, #row do
          local v = row:byte(i)
          counts[v] = (counts[v] or 0) + 1
        end
      end
    end
  end
  local items = {}
  for v, n in pairs(counts) do
    local r, g, b = baseRGB(v)
    if r and v >= 4 then items[#items + 1] = { v = v, n = n, c = { r, g, b } } end
  end
  local boxes = { items }
  while #boxes < #MAP_SLOTS do
    local bi, bc, br = nil, nil, 0
    for i, box in ipairs(boxes) do
      if #box > 1 then
        for ch = 1, 3 do
          local lo, hi = 255, 0
          for _, it in ipairs(box) do
            lo = math.min(lo, it.c[ch])
            hi = math.max(hi, it.c[ch])
          end
          if hi - lo > br then bi, bc, br = i, ch, hi - lo end
        end
      end
    end
    if not bi then break end
    local box = boxes[bi]
    table.sort(box, function(a, b) return a.c[bc] < b.c[bc] end)
    local total = 0
    for _, it in ipairs(box) do total = total + it.n end
    local acc, cut = 0, 1
    for i, it in ipairs(box) do
      acc = acc + it.n
      if acc >= total / 2 then
        cut = math.min(i, #box - 1)
        break
      end
    end
    local a, b = {}, {}
    for i, it in ipairs(box) do
      if i <= cut then a[#a + 1] = it else b[#b + 1] = it end
    end
    boxes[bi] = a
    boxes[#boxes + 1] = b
  end
  local lut, palette = {}, {}
  for v = 0, 255 do lut[v] = BLACK end
  for i, box in ipairs(boxes) do
    local slot = MAP_SLOTS[i]
    local sr, sg, sb, sn = 0, 0, 0, 0
    for _, it in ipairs(box) do
      sr = sr + it.c[1] * it.n
      sg = sg + it.c[2] * it.n
      sb = sb + it.c[3] * it.n
      sn = sn + it.n
      lut[it.v] = slot
    end
    if sn > 0 then palette[slot] = { sr / sn / 255, sg / sn / 255, sb / sn / 255 } end
  end
  local rgb = { [BLACK] = { 0.07, 0.07, 0.07 } }
  for s, c in pairs(palette) do rgb[s] = c end
  local D = {}
  for a, ca in pairs(rgb) do
    D[a] = {}
    for b, cb in pairs(rgb) do
      D[a][b] = (ca[1] - cb[1]) ^ 2 + (ca[2] - cb[2]) ^ 2 + (ca[3] - cb[3]) ^ 2
    end
  end
  return lut, palette, D
end

---------------------------------------------------------------- import

local function decoToWorld(d, meta, f)
  local x, z = d.worldX or d.x, d.worldZ or d.z or d.y
  if type(x) ~= "number" or type(z) ~= "number" then return nil end
  if d.worldX == nil and math.abs(x) <= 128 and math.abs(z) <= 128 then
    x = meta.centerX + x / 2 * f
    z = meta.centerZ + z / 2 * f
  end
  return math.floor(x + 0.5), math.floor(z + 0.5)
end

local function addFromScanner(sc, atlas)
  local ok, meta = pcall(sc.scanMap)
  if not ok then print("Scan failed: " .. tostring(meta)) return end
  local ok2, px = pcall(sc.scanMapPixels)
  if not ok2 then print("Scan failed: " .. tostring(px)) return end
  if type(px) ~= "table" or #px ~= 128 or #px[1] ~= 128 then
    print("Unexpected pixel data. Run: atlas probe")
    return
  end
  local scale, dim = meta.scale or 0, tostring(meta.dimension)
  if atlas.scale and (atlas.scale ~= scale or atlas.dim ~= dim) then
    print("Scale or dimension differs from this atlas. Skipped.")
    return
  end
  atlas.scale, atlas.dim = scale, dim
  local f = 2 ^ scale
  local size = 128 * f
  local gx = math.floor((meta.centerX + 64) / size)
  local gz = math.floor((meta.centerZ + 64) / size)
  addTile(atlas, gx, gz, meta.centerX, meta.centerZ, px)
  local added = 0
  for _, d in pairs(meta.decorations or {}) do
    local name = d.name or d.label or d.text
    if type(name) == "string" and name ~= "" then
      local x, z = decoToWorld(d, meta, f)
      if x then
        local dup = false
        for _, p in ipairs(atlas.pins) do
          if p.name == name and math.abs(p.x - x) < 4 and math.abs(p.z - z) < 4 then dup = true end
        end
        if not dup then
          atlas.pins[#atlas.pins + 1] = { name = name, note = "from banner", x = x, z = z, color = "yellow" }
          added = added + 1
        end
      end
    end
  end
  print(("Added tile %d,%d. Banner pins added: %d."):format(gx, gz, added))
end

local function cmdImport()
  local sc = peripheral.find("scanner")
  if not sc then error("No scanner found. Attach a scanner from Lake's CC Additions.", 0) end
  local mounts = diskMounts()
  if #mounts == 0 then error("No data disk found. Put a floppy disk in a disk drive.", 0) end
  local atlas = loadAtlas(mounts[1]) or newAtlas(mounts[1])
  atlas.mount = mounts[1]
  atlas.pins = loadPins(atlas)
  print("Atlas import. Disk: " .. atlas.mount)
  while true do
    write("Enter = add map in scanner, s = save, q = quit: ")
    local a = (read() or ""):lower()
    if a == "q" then
      return
    elseif a == "s" then
      write("Store markers on the disk for every computer that uses it? (y/n): ")
      atlas.shared = (read() or ""):lower() == "y"
      if exportAtlas(atlas) then
        print("Saved. Markers are " .. (atlas.shared and "on the disk." or "local to this computer."))
        print("Run on any computer: disk/atlas view")
      end
      return
    else
      addFromScanner(sc, atlas)
    end
  end
end

local function cmdProbe()
  local sc = peripheral.find("scanner")
  if not sc then error("No scanner found.", 0) end
  local meta = sc.scanMap()
  local px = sc.scanMapPixels()
  local out = { meta = meta, rows = #px, rowLength = px[1] and #px[1], firstBytes = { px[1]:byte(1, 16) } }
  writeFile("/atlas_probe.txt", textutils.serialize(out))
  print("Wrote /atlas_probe.txt")
end

---------------------------------------------------------------- viewer

local function run(atlas, disp, monName)
  local w, h = disp.getSize()
  local mh = h - 2
  local f = 2 ^ atlas.scale
  local lut, palette, D = buildPalette(atlas)
  for slot, c in pairs(palette) do disp.setPaletteColour(2 ^ slot, c[1], c[2], c[3]) end
  local hexOf = {}
  for i = 0, 15 do hexOf[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end

  local minGx, maxGx, minGz, maxGz = math.huge, -math.huge, math.huge, -math.huge
  for _, t in pairs(atlas.list) do
    minGx, maxGx = math.min(minGx, t[1]), math.max(maxGx, t[1])
    minGz, maxGz = math.min(minGz, t[2]), math.max(maxGz, t[2])
  end
  local view = { cx = (minGx + maxGx + 1) * 64, cz = (minGz + maxGz + 1) * 64, zoom = ZOOMS[1] }
  local fit = math.min(w * 2 / ((maxGx - minGx + 1) * 128), mh * 3 / ((maxGz - minGz + 1) * 128))
  for _, z in ipairs(ZOOMS) do if z <= fit then view.zoom = z end end

  local frame, tick
  local mode, ui, page = "nav", "map", 0
  local selected, ruler, gpsPos, gpsOn, msg = nil, {}, nil, false, ""
  local running = true
  local buttons = {}
  local redraw

  local function sample(px, pz)
    local gx, gz = math.floor(px / 128), math.floor(pz / 128)
    local col = atlas.tiles[gx]
    local tile = col and col[gz]
    if not tile then return BLACK end
    return lut[tile[pz - gz * 128 + 1]:byte(px - gx * 128 + 1)]
  end

  local function w2c(x, z)
    local sx = ((x + 64) / f - view.cx) * view.zoom + w
    local sy = ((z + 64) / f - view.cz) * view.zoom + mh * 1.5
    return math.floor(sx / 2) + 1, math.floor(sy / 3) + 2
  end

  local function c2w(c, r)
    local sx, sy = (c - 1) * 2 + 1, (r - 2) * 3 + 1.5
    local px = view.cx + (sx - w) / view.zoom
    local pz = view.cz + (sy - mh * 1.5) / view.zoom
    return px * f - 64, pz * f - 64
  end

  local function buildFrame()
    local W, H = w * 2, mh * 3
    local xs, zs = {}, {}
    for i = 0, W - 1 do xs[i] = math.floor(view.cx + (i + 0.5 - W / 2) / view.zoom) end
    for j = 0, H - 1 do zs[j] = math.floor(view.cz + (j + 0.5 - H / 2) / view.zoom) end
    frame = {}
    local c = {}
    for cy = 0, mh - 1 do
      local ch, fg, bg = {}, {}, {}
      for cx = 0, w - 1 do
        for k = 0, 5 do
          c[k + 1] = sample(xs[cx * 2 + k % 2], zs[cy * 3 + math.floor(k / 2)])
        end
        local bgc, fgc, best, cnt = c[6], nil, 0, {}
        for k = 1, 5 do
          local s = c[k]
          if s ~= bgc then
            cnt[s] = (cnt[s] or 0) + 1
            if cnt[s] > best then best, fgc = cnt[s], s end
          end
        end
        if not fgc then
          ch[#ch + 1], fg[#fg + 1], bg[#bg + 1] = " ", hexOf[bgc], hexOf[bgc]
        else
          local bits = 0
          for k = 1, 5 do
            local s = c[k]
            if s == fgc or (s ~= bgc and D[s][fgc] < D[s][bgc]) then bits = bits + 2 ^ (k - 1) end
          end
          ch[#ch + 1], fg[#fg + 1], bg[#bg + 1] = string.char(128 + bits), hexOf[fgc], hexOf[bgc]
        end
      end
      frame[cy + 1] = { table.concat(ch), table.concat(fg), table.concat(bg) }
      if cy % 6 == 5 then sleep(0) end
    end
  end

  local function put(c, r, text, fg, bg)
    if r < 2 or r > h - 1 or c > w then return end
    if c < 1 then text = text:sub(2 - c) c = 1 end
    text = text:sub(1, w - c + 1)
    if #text == 0 then return end
    disp.setCursorPos(c, r)
    disp.blit(text, fg:rep(#text), bg:rep(#text))
  end

  local function fl(n) return math.floor(n + 0.5) end

  local function describe(p)
    local s = ("%s (%d, %d)"):format(p.name, p.x, p.z)
    if p.note and p.note ~= "" then s = s .. " " .. p.note end
    if gpsPos then s = s .. (" | %d blocks away"):format(fl(math.sqrt((p.x - gpsPos.x) ^ 2 + (p.z - gpsPos.z) ^ 2))) end
    return s
  end

  local function ask(label, default)
    local t = term.current()
    local _, th = t.getSize()
    t.setBackgroundColour(colors.black)
    t.setTextColour(colors.white)
    t.setCursorPos(1, th)
    t.clearLine()
    t.write(label)
    return read(nil, nil, nil, default) or ""
  end

  local function save()
    if not savePins(atlas) then msg = "Could not save markers." end
  end

  local function status()
    local text = msg
    if text == "" then
      text = ("X %d Z %d  zoom %s%s"):format(fl(view.cx * f - 64), fl(view.cz * f - 64), tostring(view.zoom),
        gpsPos and ("  you %d,%d"):format(gpsPos.x, gpsPos.z) or "")
    end
    text = (text .. (" "):rep(w)):sub(1, w)
    disp.setCursorPos(1, 1)
    disp.blit(text, ("0"):rep(w), ("f"):rep(w))
  end

  local function pinAt(c, r)
    for _, p in ipairs(atlas.pins) do
      local pc, pr = w2c(p.x, p.z)
      if pr == r and math.abs(pc - c) <= 1 then return p end
    end
  end

  local function drawList()
    disp.setBackgroundColour(colors.black)
    for r = 2, h - 1 do disp.setCursorPos(1, r) disp.clearLine() end
    if #atlas.pins == 0 then put(1, 2, "No markers yet.", "0", "f") end
    for r = 2, h - 1 do
      local p = atlas.pins[page * mh + (r - 1)]
      if p then
        put(1, r, "#", colors.toBlit(PIN_COLORS[p.color] or colors.red), "f")
        put(3, r, p.name .. " " .. p.x .. "," .. p.z, "0", "f")
      end
    end
  end

  local function overlays()
    for _, p in ipairs(atlas.pins) do
      local c, r = w2c(p.x, p.z)
      local col = colors.toBlit(PIN_COLORS[p.color] or colors.red)
      if p == selected then put(c, r, "#", "f", col) else put(c, r, "#", col, "f") end
      put(c + 1, r, p.name:sub(1, 16), "0", "f")
    end
    if ruler.a then local c, r = w2c(ruler.a.x, ruler.a.z) put(c, r, "A", "f", "4") end
    if ruler.b then local c, r = w2c(ruler.b.x, ruler.b.z) put(c, r, "B", "f", "4") end
    if gpsPos then local c, r = w2c(gpsPos.x, gpsPos.z) put(c, r, "@", "0", "e") end
  end

  -- actions
  local function zoomBy(dir)
    local i = 1
    for n, z in ipairs(ZOOMS) do if z <= view.zoom then i = n end end
    view.zoom = ZOOMS[math.max(1, math.min(#ZOOMS, i + dir))]
    redraw(true)
  end
  local function pan(dx, dz)
    view.cx = view.cx + dx * (w / 2) / view.zoom
    view.cz = view.cz + dz * (mh * 1.5 / 2) / view.zoom
    redraw(true)
  end
  local function centerOn(x, z)
    view.cx, view.cz = (x + 64) / f, (z + 64) / f
  end
  local function setMode(m)
    mode = (mode == m) and "nav" or m
    ruler = {}
    msg = mode == "pin" and "Tap the map to place a pin." or mode == "ruler" and "Tap point A, then point B." or ""
    redraw(false)
  end
  local function toggleGps()
    gpsOn = not gpsOn
    if gpsOn then
      local x, y, z = gps.locate(1)
      if x then gpsPos = { x = fl(x), y = fl(y), z = fl(z) } msg = "GPS fix." else msg = "No GPS fix." end
    else
      gpsPos = nil
      msg = "GPS off."
    end
    redraw(false)
  end
  local function showList() ui, page, selected = "list", 0, nil redraw(false) end
  local function quit() running = false end
  local function back() ui, selected, msg = "map", nil, "" redraw(false) end
  local function listPage(d)
    local pages = math.max(1, math.ceil(#atlas.pins / mh))
    page = (page + d) % pages
    redraw(false)
  end
  local function editPin()
    local p = selected
    if not p then return end
    local name = ask("Name: ", p.name)
    if name ~= "" then p.name = name end
    p.note = ask("Note: ", p.note or "")
    save()
    msg = describe(p)
    redraw(false)
  end
  local function cycleColor()
    local p = selected
    if not p then return end
    local i = 1
    for n, c in ipairs(PIN_ORDER) do if c == p.color then i = n end end
    p.color = PIN_ORDER[i % #PIN_ORDER + 1]
    save()
    redraw(false)
  end
  local function deletePin()
    for i, p in ipairs(atlas.pins) do
      if p == selected then table.remove(atlas.pins, i) break end
    end
    selected, msg = nil, "Pin deleted."
    save()
    redraw(false)
  end
  local function newPin(x, z)
    local name = ask("Pin name: ")
    if name == "" then msg = "Cancelled." return end
    local note = ask("Note (optional): ")
    local col = ask("Colour (red/yellow/lime/cyan/white): ", "red")
    local pin = { name = name, note = note, x = fl(x), z = fl(z), color = PIN_COLORS[col] and col or "red" }
    atlas.pins[#atlas.pins + 1] = pin
    selected, msg = pin, describe(pin)
    save()
  end

  local function drawToolbar()
    buttons = {}
    local short = w < 46
    local defs
    if ui == "list" then
      defs = { { "Back", back }, { "Prev", function() listPage(-1) end }, { "Next", function() listPage(1) end } }
    elseif selected then
      defs = { { "Edit", editPin }, { "Color", cycleColor }, { "Del", deletePin }, { "Back", back } }
    else
      defs = {
        { "+", function() zoomBy(1) end }, { "-", function() zoomBy(-1) end },
        { "<", function() pan(-1, 0) end }, { ">", function() pan(1, 0) end },
        { "^", function() pan(0, -1) end }, { "v", function() pan(0, 1) end },
        { short and "P" or "Pin", function() setMode("pin") end, mode == "pin" },
        { short and "R" or "Rule", function() setMode("ruler") end, mode == "ruler" },
        { short and "G" or "GPS", toggleGps, gpsOn },
        { short and "L" or "List", showList },
        { short and "Q" or "Quit", quit },
      }
      if short then table.remove(defs, 3) table.remove(defs, 3) table.remove(defs, 3) table.remove(defs, 3) end
    end
    local x, text, fg = 1, "", ""
    for _, d in ipairs(defs) do
      local label = "[" .. d[1] .. "]"
      buttons[#buttons + 1] = { x1 = x, x2 = x + #label - 1, fn = d[2] }
      text = text .. label
      fg = fg .. (d[3] and ("4"):rep(#label) or ("0"):rep(#label))
      x = x + #label
    end
    text = (text .. (" "):rep(w)):sub(1, w)
    fg = (fg .. ("0"):rep(w)):sub(1, w)
    disp.setCursorPos(1, h)
    disp.blit(text, fg, ("f"):rep(w))
  end

  redraw = function(full)
    if ui == "list" then
      drawList()
    else
      if full or not frame then
        buildFrame()
        tick = os.startTimer(3)
      end
      for i = 1, mh do
        disp.setCursorPos(1, i + 1)
        disp.blit(frame[i][1], frame[i][2], frame[i][3])
      end
      overlays()
    end
    status()
    drawToolbar()
  end

  local function onTap(c, r)
    if r == h then
      for _, b in ipairs(buttons) do
        if c >= b.x1 and c <= b.x2 then b.fn() return end
      end
      return
    end
    if r == 1 then return end
    if ui == "list" then
      local p = atlas.pins[page * mh + (r - 1)]
      if p then
        ui, selected = "map", p
        centerOn(p.x, p.z)
        msg = describe(p)
        redraw(true)
      end
      return
    end
    local x, z = c2w(c, r)
    if mode == "pin" then
      newPin(x, z)
      mode = "nav"
      redraw(false)
    elseif mode == "ruler" then
      local pt = { x = fl(x), z = fl(z) }
      if not ruler.a or ruler.b then
        ruler = { a = pt }
        msg = "Point A set. Tap point B."
      else
        ruler.b = pt
        local dx, dz = pt.x - ruler.a.x, pt.z - ruler.a.z
        msg = ("A to B: %d blocks (dx %d, dz %d, walk %d)"):format(fl(math.sqrt(dx * dx + dz * dz)), dx, dz, math.abs(dx) + math.abs(dz))
      end
      redraw(false)
    else
      local p = pinAt(c, r)
      if p then
        selected, msg = p, describe(p)
        redraw(false)
      else
        selected = nil
        centerOn(x, z)
        msg = ("X %d Z %d"):format(fl(x), fl(z))
        redraw(true)
      end
    end
  end

  redraw(true)
  while running do
    local e, a, b, c = os.pullEvent()
    if e == "timer" and a == tick then
      if gpsOn then
        local x, y, z = gps.locate(1)
        if x then gpsPos = { x = fl(x), y = fl(y), z = fl(z) } end
      end
      tick = os.startTimer(3)
      if gpsOn then redraw(false) end
    elseif e == "mouse_click" and not monName then
      onTap(b, c)
    elseif e == "monitor_touch" and monName and a == monName then
      onTap(b, c)
    elseif e == "mouse_scroll" and not monName then
      zoomBy(-a)
    elseif e == "key" then
      if a == keys.left then pan(-1, 0)
      elseif a == keys.right then pan(1, 0)
      elseif a == keys.up then pan(0, -1)
      elseif a == keys.down then pan(0, 1) end
    elseif e == "char" then
      if a == "+" or a == "=" then zoomBy(1)
      elseif a == "-" then zoomBy(-1)
      elseif a == "p" then setMode("pin")
      elseif a == "r" then setMode("ruler")
      elseif a == "g" then toggleGps()
      elseif a == "l" then showList()
      elseif a == "c" and gpsPos then centerOn(gpsPos.x, gpsPos.z) redraw(true)
      elseif a == "q" then quit() end
    end
  end
end

local function cmdView(arg)
  local atlas
  for _, m in ipairs(diskMounts()) do
    atlas = loadAtlas(m)
    if atlas then break end
  end
  if not atlas then error("No atlas found on an attached disk. Run: atlas import", 0) end
  atlas.pins = loadPins(atlas)
  local disp, monName = term.current(), nil
  if arg and arg ~= "term" then
    disp = arg == "monitor" and peripheral.find("monitor") or peripheral.wrap(arg)
    if not disp then error("Monitor not found.", 0) end
    disp.setTextScale(0.5)
    monName = peripheral.getName(disp)
  end
  if not disp.isColour() then error("An advanced computer or advanced monitor is required.", 0) end
  if monName then
    term.clear()
    term.setCursorPos(1, 1)
    print("Atlas on monitor " .. monName)
    print("Tap the monitor to use it.")
    print("Pin prompts appear here.")
  end
  local ok, err = pcall(run, atlas, disp, monName)
  for _, s in ipairs(MAP_SLOTS) do
    disp.setPaletteColour(2 ^ s, term.nativePaletteColour(2 ^ s))
  end
  disp.setBackgroundColour(colors.black)
  disp.setTextColour(colors.white)
  disp.clear()
  disp.setCursorPos(1, 1)
  if not ok and err ~= "Terminated" then error(err, 0) end
end

---------------------------------------------------------------- main

if args[1] == "import" then
  cmdImport()
elseif args[1] == "view" then
  cmdView(args[2])
elseif args[1] == "probe" then
  cmdProbe()
else
  print("Usage:")
  print("  atlas import")
  print("  atlas view [monitor|peripheral name]")
  print("  atlas probe")
end
