--[==[ Prismarine
 ____ 
/\ _`\ __ __ 
\ \ \L\ \_ __ /\_\ ____ ___ ___ __ _ __ /\_\ ___ __ 
 \ \ ,__/\`'__\/\ \ /',__\ /' __` __`\ /'__`\ /\`'__\/\ \ /' _ `\ /'__`\ 
 \ \ \/\ \ \/ \ \ \/\__, `\/\ \/\ \/\ \/\ \L\.\_\ \ \/ \ \ \/\ \/\ \/\ __/ 
 \ \_\ \ \_\ \ \_\/\____/\ \_\ \_\ \_\ \__/.\_\\ \_\ \ \_\ \_\ \_\ \____\
 \/_/ \/_/ \/_/\/___/ \/_/\/_/\/_/\/__/\/_/ \/_/ \/_/\/_/\/_/\/____/
]==]
-- /prismarine/boot.lua
-- Prismarine OS. The real start of the system.
--   1. load the graphics, kernel and security code behind the splash
--   2. first run: choose a password. Later runs: log in.
--   3. check every system file against the sealed manifest
--   4. start the network service, then the desktop
local native = term.native()

local function fail(msg)
  native.setBackgroundColor(colors.black)
  native.setTextColor(colors.red)
  native.clear()
  native.setCursorPos(1, 1)
  print("Prismarine could not start.")
  native.setTextColor(colors.white)
  print(tostring(msg))
  print()
  print("Press any key to open the normal shell.")
  os.pullEventRaw("key")
  native.setTextColor(colors.white)
  native.clear()
  native.setCursorPos(1, 1)
end

local function main()
  local G = dofile("/prismarine/ui/gfx.lua")
  G.init()

  local K, UI, C, S, N, L, SB, U, AS, PM, IN
  G.splash({
    { "Loading kernel", function()
      SB = dofile("/prismarine/kernel/sandbox.lua")
      K = dofile("/prismarine/kernel/kernel.lua")
    end },
    { "Loading security", function()
      C = dofile("/prismarine/sys/crypto.lua")
      S = dofile("/prismarine/sys/secure.lua")
      N = dofile("/prismarine/sys/net.lua")
      U = dofile("/prismarine/sys/update.lua")
      AS = dofile("/prismarine/sys/archivestore.lua")
      PM = dofile("/prismarine/sys/perms.lua")
      IN = dofile("/prismarine/sys/inputs.lua")
      S.init(C)
      C.initRandom()
    end },
    { "Loading interface", function()
      UI = dofile("/prismarine/ui/ui.lua")
      L = dofile("/prismarine/ui/login.lua")
    end },
  }, 2.4)

  L.init(G)

  -- ----------------------------------------------------------- password
  local function archiveHere()
    if fs.exists("/prismarine/secure/archive") then return true end
    local d = "/prismarine/archive"
    if fs.isDir(d) then
      for _, n in ipairs(fs.list(d)) do
        if n:match("%.log$") then return true end
      end
    end
    return false
  end
  local bunkerFlag = archiveHere()

  -- apply(pw, progress) makes the new password real (first run, or turning one on).
  local function setupPassword(title, apply, hint)
    local err
    while true do
      local pw = L.prompt({
        title = title, label = "Choose a password for this computer",
        mask = "*", hint = hint or ("At least " .. S.MIN_PASSWORD .. " characters. There is no recovery."), err = err,
      })
      if pw and #pw < S.MIN_PASSWORD then
        err = "Too short. Use at least " .. S.MIN_PASSWORD .. " characters."
      elseif pw then
        local again = L.prompt({ title = title, label = "Type it again", mask = "*", hint = "" })
        if again == pw then
          local show = L.busy(title, "Making your keys...")
          apply(pw, function(i) show("Making your keys...", i / C.PBKDF_ROUNDS) end)
          return true
        end
        err = "They did not match. Try again."
      end
    end
  end

  local function firstRun()
    local pick = L.message("Welcome to Prismarine", {
      "Protect this computer with a password?",
      "P: yes (recommended)   N: no password",
      "Change it later in Others. Archives need one.",
    }, colors.white, { p = true, n = true })
    if pick == "n" then
      S.setupOpen()
    else
      setupPassword("Welcome to Prismarine", function(pw, prog) S.setup(pw, prog) end)
    end
  end

  local function resetComputer()
    local ans = L.prompt({
      title = "Reset this computer", label = "Type RESET to erase the password and keys",
      hint = "Your Archive membership and messages are lost. Files stay.", allowCancel = true,
    })
    if ans == "RESET" then
      S.wipe()
      for _, p in ipairs({ "/prismarine/data/ui_settings.json", "/prismarine/archive" }) do
        if fs.exists(p) then pcall(fs.delete, p) end
      end
      return true
    end
    return false
  end

  local function login()
    local err
    while true do
      local left = S.lockoutLeft()
      if left > 0 then
        L.message("Locked", { "Too many wrong passwords.", "Wait " .. left .. " seconds, then press Enter.", "" }, colors.orange)
        err = nil
      else
        local pw = L.prompt({
          title = "Prismarine", label = "Password", mask = "*", err = err, forgot = true,
          hint = (S.failedTries() > 0) and (S.failedTries() .. " wrong tries so far") or "",
        })
        if pw == "\0forgot" then
          if resetComputer() then return "reset" end
        elseif pw then
          local show = L.busy("Prismarine", "Checking...")
          local ok, why = S.login(pw, function(i) show("Checking...", i / C.PBKDF_ROUNDS) end)
          if ok then return true end
          if why == "wrong" then err = "Wrong password."
          elseif why == "damaged" then err = "The key file is damaged."
          else err = "Could not log in." end
        end
      end
    end
  end

  local needArchivePw = false
  if not S.isSetUp() then
    firstRun()
  elseif S.isOpen() then
    local ok = S.autoLogin()
    if not ok then
      local pick = L.message("Keys damaged", {
        "The key file is damaged.", "R: reset this computer   S: shut down", "Files stay. Messages and Archive keys are lost.",
      }, colors.orange, { r = true, s = true })
      if pick == "s" then
        os.shutdown()
        while true do os.pullEventRaw() end
      end
      S.wipe()
      if fs.exists("/prismarine/archive") then pcall(fs.delete, "/prismarine/archive") end
      bunkerFlag = false
      firstRun()
    elseif bunkerFlag then
      needArchivePw = true
    end
  else
    local r = login()
    if r == "reset" then
      bunkerFlag = false
      firstRun()
    end
  end

  -- ----------------------------------------------------------- secure boot
  do
    local show = L.busy("Checking system files", "Checking system files...")
    local hashes = S.hashSystem(function(i, n) show("Checking system files...", i / n) end)
    local state, diff = S.compareManifest(hashes)
    if state == "new" then
      S.sealManifest(hashes)
    elseif state ~= "ok" then
      local items = {}
      for _, d in ipairs(diff) do items[#items + 1] = d.what .. "  " .. d.path end
      local header = (state == "forged") and "The file check was damaged or forged. Nothing can be trusted."
        or (#diff .. " system files differ from the last trusted state.")
      local pick = L.list("System files changed", header, items,
        "A: accept (I just updated)   S: shut down", { a = true, s = true })
      if pick == "s" then
        os.shutdown()
        while true do os.pullEventRaw() end
      end
      S.sealManifest(hashes)
    end
  end

  if needArchivePw then
    -- An Archive never runs without a password. The file check above already passed.
    L.message("Archive found", {
      "This computer holds an Archive.", "It needs a password now.", "Press Enter.",
    }, colors.yellow)
    setupPassword("Archive password", function(pw, prog) S.enablePassword(pw, prog) end)
  end

  -- ----------------------------------------------------------- network
  local settingsRaw = {}
  pcall(function()
    local h = fs.open("/prismarine/data/ui_settings.json", "r")
    if h then
      settingsRaw = textutils.unserialiseJSON(h.readAll()) or {}
      h.close()
    end
  end)
  local myName = settingsRaw.msgName or os.getComputerLabel() or ("Computer " .. os.getComputerID())

  local uiApi -- set after UI.create
  local addArchiveApp -- set below, once the app list exists
  local cb = {}
  function cb.notify(title, text, level)
    K.notifySystem(title, text, level or "info")
  end
  function cb.event(...)
    K.sendCap("net", "pm_net", ...)
  end

  local logKeyDir = "/prismarine/archive/"
  local arcApi
  function cb.archiveRecord(rec)
    arcApi = arcApi or N.archiveApi()
    local day = os.date("!%Y-%m-%d", math.floor((rec.t or os.epoch("utc")) / 1000))
    AS.write(day, C.hex(arcApi.seal(C.encode(rec))))
    K.sendCap("archive", "pm_arc", rec)
  end

  U.init(K, C, S)
  PM.init(K, C)
  IN.init(K)
  K.permStored, K.permSave, K.permSeen = PM.stored, PM.save, PM.seen
  AS.init(C, S, K, N)
  N.init(K, C, S, cb)
  N.start(myName)

  -- ----------------------------------------------------------- archive mode
  local function bunker()
    return bunkerFlag or N.isArchive()
  end
  local function lockdown()
    return N.enrolled() or bunker()
  end
  K.lockdown = lockdown
  K.bunker = bunker

  local function approved(hash)
    return N.allowList()[hash] ~= nil
  end

  -- What may start as a program without an approval: the built-in apps.
  local function isSystemPath(path)
    path = fs.combine("", path or "")
    return path:sub(1, 16) == "prismarine/apps/" or path:sub(1, 4) == "rom/" or path == "rom"
  end

  -- What an app may load with dofile or require in Archive mode: files the OS
  -- ships. The built-in apps load the UI kit from prismarine/ui, so that
  -- folder and prismarine/lib must pass too, or every app crashes with
  -- "Not approved by the Archive". Apps cannot write under prismarine/, and
  -- the boot check hashes every file in these folders.
  local TRUSTED_DIRS = { "prismarine/apps/", "prismarine/ui/", "prismarine/lib/" }
  local function isTrustedCode(path)
    path = fs.combine("", path or "")
    if path == "rom" or path:sub(1, 4) == "rom/" then return true end
    for _, d in ipairs(TRUSTED_DIRS) do
      if path:sub(1, #d) == d then return true end
    end
    return false
  end

  -- The policy follows Archive mode live: an app that started before the
  -- computer joined an Archive loses its extra powers the moment it joins.
  local function canRun(path, src)
    if isTrustedCode(path) then return true end
    if src and approved(C.sha256hex(src)) then return true end
    return false, "Not approved by the Archive: " .. tostring(fs.combine("", path or ""))
  end
  local lockedFields = { rawLua = false, disksRO = true, canRun = canRun }
  K.policyFor = function(spec)
    local open = SB.policy(spec.system and { rawLua = true } or nil)
    return setmetatable({}, {
      __index = function(_, k)
        if lockdown() and lockedFields[k] ~= nil then return lockedFields[k] end
        if k == "canRun" then return nil end
        return open[k]
      end,
    })
  end

  local LOCKED_PATHS = { ["/prismarine/apps/shell.lua"] = true }
  local BUNKER_PATHS = {
    ["/prismarine/apps/programs.lua"] = true, ["/prismarine/apps/download.lua"] = true,
    ["/prismarine/apps/disks.lua"] = true,
  }

  K.canSpawn = function(spec)
    if not lockdown() then return true end
    if LOCKED_PATHS[spec.path] then return false, "The shell is locked in Archive mode" end
    if bunker() and BUNKER_PATHS[spec.path] then return false, "Locked on an Archive computer" end
    if spec.system or isSystemPath(spec.path) then return true end
    local data = C.readFile(spec.path)
    if data and approved(C.sha256hex(data)) then return true end
    return false, "The Archive has not approved this program"
  end

  -- ----------------------------------------------------------- capabilities
  K.caps.net = function(p) return N.api(p) end
  K.caps.netadmin = function(p)
    local A = N.adminApi(p)
    local become, join = A.becomeArchive, A.join
    function A.becomeArchive(name)
      if not S.hasPassword() then return false, "Turn on a password first (Others)" end
      -- The Archive app is an add-on: fetched once, checked against the signed list.
      if not fs.exists("/prismarine/apps/archive.lua") then
        local got, why = K.await(p, function() return U.installAddon("archive") end)
        if not got then return false, "Archive app: " .. tostring(why) end
        if addArchiveApp then addArchiveApp() end
      end
      local ok, fp = become(name)
      if ok then
        bunkerFlag = true
        K.notifySystem("Bunker mode", "This computer is now an Archive. Extra locks are on.", "info")
      end
      return ok, fp
    end
    function A.join(id)
      if bunker() then return false, "This computer holds an Archive" end
      return join(id)
    end
    return A
  end
  local function selfLog(kind, text)
    cb.archiveRecord({ t = os.epoch("utc"), sender = os.getComputerID(), kind = kind, text = "this Archive: " .. text })
  end
  K.caps.archive = function(p)
    if not N.isArchive() then return nil end
    local A = N.archiveApi(p)
    local function run(fn) return K.await(p, fn) end
    local function gate(pw)
      if type(pw) ~= "string" or not S.hasPassword() then return false, "wrong" end
      local ok, why, extra = run(function() return S.checkPassword(pw) end)
      if ok then return true end
      return false, why or "wrong", extra
    end
    function A.days() return AS.days() end
    function A.day(d)
      return run(function() return AS.day(d, A.open) end)
    end
    function A.deleteDay(d) return AS.delete(d) end

    -- Disk storage
    function A.storage()
      local c = AS.config()
      c.disks = AS.disks()
      return c
    end
    function A.setStorage(key, value) return AS.set(key, value) end
    function A.copyToDisk() return run(function() return AS.copyAll() end) end
    function A.refreshDisks() AS.refreshDisks() return AS.disks() end

    -- Marks: a short list of record keys the person flagged.
    local MARKS = logKeyDir .. "marks.dat"
    function A.marks()
      local out = {}
      if fs.exists(MARKS) then
        local h = fs.open(MARKS, "r")
        if h then
          local ok, t = pcall(textutils.unserialize, h.readAll())
          h.close()
          if ok and type(t) == "table" then
            for k, v in pairs(t) do
              if type(k) == "string" and #k < 60 and v == true then out[k] = true end
            end
          end
        end
      end
      return out
    end
    function A.setMark(key, on)
      if type(key) ~= "string" or #key > 60 then return false end
      local m = A.marks()
      local n = 0
      for _ in pairs(m) do n = n + 1 end
      if on and n >= 500 then return false end
      m[key] = on and true or nil
      local h = fs.open(MARKS, "w")
      if h then h.write(textutils.serialize(m)) h.close() end
      return true
    end

    -- Plain text leaves the Archive only after the password.
    function A.hasPrinter() return AS.hasPrinter() end
    function A.print(day, pw)
      local ok, why, extra = gate(pw)
      if not ok then return false, why, extra end
      return run(function()
        local pages, why = AS.print(day, A.open)
        if pages then selfLog("audit_print", "Printed day " .. tostring(day)) end
        return pages, why
      end)
    end
    function A.export(day, dest, pw)
      local ok, why, extra = gate(pw)
      if not ok then return false, why, extra end
      return run(function()
        local path, why = AS.export(day, dest, A.open)
        if path then selfLog("audit_export", "Exported " .. tostring(day) .. " to " .. tostring(dest)) end
        return path, why
      end)
    end
    return A
  end

  K.caps.update = function(p)
    return {
      status = function()
        local s = U.status()
        return { state = s.state, text = s.text, version = s.version, frac = s.frac, count = #s.changed }
      end,
      check = function() U.check() return true end,
      reboot = function() os.reboot() end,
      install = function(pw)
        if type(pw) ~= "string" then return false end
        return U.install(pw)
      end,
    }
  end
  -- Settings only: see and change what apps may do.
  K.caps.perms = function(p)
    return {
      labels = K.PERM_LABEL,
      order = K.PERM_ORDER,
      list = function() return PM.list() end,
      set = function(key, perm, value)
        if type(key) ~= "string" or type(perm) ~= "string" or type(value) ~= "string" then return false end
        return PM.set(key, perm, value)
      end,
      forget = function(key)
        if type(key) ~= "string" then return false end
        return PM.forget(key)
      end,
      bunker = bunker(),
    }
  end
  -- The app store list, for the Download app.
  K.caps.store = function(p)
    return {
      status = function() return U.storeStatus() end,
      refresh = function() return U.storeRefresh() end,
      install = function(name)
        if type(name) ~= "string" then return false, "bad" end
        return U.storeInstall(name)
      end,
    }
  end
  K.caps.tools = function(p)
    local shaY
    return {
      -- Big data is hashed in a kernel task that yields now and then.
      sha256 = function(data)
        data = tostring(data)
        if #data < 20000 then return C.sha256hex(data) end
        return K.await(p, function()
          shaY = shaY or dofile("/prismarine/lib/sha256.lua")
          return shaY(data)
        end)
      end,
    }
  end
  -- A program can say what it needs in its first lines:
  --   -- prismarine: service inputs touch
  -- "service" runs it in the background. The other words are capabilities an
  -- app may ask for; each one still waits for the person's permission.
  local function readHeader(path)
    local h = fs.open(path, "r")
    if not h then return {} end
    local words = {}
    for _ = 1, 20 do
      local line = h.readLine()
      if not line then break end
      local list = line:lower():match("^%-%-+%s*prismarine%s*:%s*(.-)%s*$")
      if list then
        for w in list:gmatch("[%a_]+") do
          if #words < 8 then words[#words + 1] = w end
        end
      end
    end
    h.close()
    return words
  end
  K.caps.launch = function(p)
    return {
      run = function(path, name)
        if type(path) ~= "string" then return nil, "Bad path" end
        if not fs.exists(path) or fs.isDir(path) then return nil, "No such program" end
        local spec = { name = tostring(name or fs.getName(path)), path = path, class = "app", caps = {} }
        for _, w in ipairs(readHeader(path)) do
          if w == "service" then
            spec.class = "service"
          elseif K.APP_CAPS[w] then
            spec.caps[#spec.caps + 1] = w
          end
        end
        local pid, why, existed = K.spawn(spec)
        if existed then
          -- Already running: switch to it instead of opening another.
          if spec.class == "app" then pcall(K.focus, pid) end
          return pid, nil, true
        end
        if pid and spec.class == "service" then
          K.notifySystem(spec.name, "Running in the background.", "info", pid)
        end
        return pid, why
      end,
    }
  end
  -- Saved redstone inputs. Built-in apps use it freely. Any other app waits for
  -- the person's permission on the first call.
  local function gate(p, perm, api, what)
    if p.spec.system or p.spec.trusted then return api end
    local out = {}
    for k, v in pairs(api) do
      if type(v) == "function" then
        out[k] = function(...)
          if not K.checkPerm(p, perm, what) then return nil, "Not allowed" end
          return v(...)
        end
      else
        out[k] = v
      end
    end
    return out
  end
  K.caps.inputs = function(p)
    return gate(p, "inputs", {
      list = IN.list, read = IN.read, sides = IN.sides, remove = IN.remove,
      save = function(d) return IN.save(d) end,
      max = IN.MAX,
    }, "Redstone inputs")
  end
  K.caps.touch = function(p)
    return {
      -- Call once. Afterwards the app gets monitor_touch events.
      enable = function() return K.checkPerm(p, "touch", "Monitor touches") end,
    }
  end
  K.caps.account = function(p)
    return {
      check = function(pw)
        local good = K.await(p, function() return S.checkPassword(pw) end)
        return good == true
      end,
      status = function()
        return { password = S.hasPassword(), lockdown = lockdown(), bunker = bunker() }
      end,
      enablePassword = function(new)
        if type(new) ~= "string" then return false, "bad" end
        local good, why = K.await(p, function() return S.enablePassword(new) end)
        if good then return true end
        return false, why
      end,
      disablePassword = function(old)
        if type(old) ~= "string" then return false, "bad" end
        if lockdown() then return false, "archive" end
        local good, why = K.await(p, function() return S.disablePassword(old) end)
        if good then return true end
        return false, why
      end,
      changePassword = function(old, new)
        local good, why = K.await(p, function() return S.changePassword(old, new) end)
        if good then return true end
        return false, why
      end,
    }
  end

  -- ----------------------------------------------------------- vault
  -- The Vault keeps a short list of secrets, sealed with a key made from the
  -- password. The file sits in /prismarine/secure, which no app can see.
  -- Only the built-in Vault app is given this capability.
  local VAULT_FILE = "vault"
  local VAULT_MAX_ITEMS, VAULT_MAX_BYTES = 100, 60000
  local VAULT_LIMITS = { title = 40, user = 60, secret = 120, note = 200 }
  local function vaultClean(items)
    if type(items) ~= "table" or #items > VAULT_MAX_ITEMS then return nil end
    local out, total = {}, 0
    for i, it in ipairs(items) do
      if type(it) ~= "table" then return nil end
      local row = {}
      for field, max in pairs(VAULT_LIMITS) do
        local v = it[field]
        if v == nil then v = "" end
        if type(v) ~= "string" then return nil end
        row[field] = v:sub(1, max)
        total = total + #row[field]
      end
      row.changed = tonumber(it.changed) or 0
      out[i] = row
    end
    if total > VAULT_MAX_BYTES then return nil end
    return out
  end
  local function vaultLoad()
    if not S.unlocked() then return nil, "locked" end
    local t = S.readTable(VAULT_FILE)
    if not t then return {} end
    local data = S.openTable("vault", t.box)
    if not data then return nil, "unreadable" end
    return data.items or {}
  end
  S.rekeyHooks[#S.rekeyHooks + 1] = function(oldKek, newKek)
    local t = S.readTable(VAULT_FILE)
    if not t then return end
    local plain = C.open(C.kdf("prismarine v1 vault")(oldKek), C.unhex(t.box), "vault")
    local data = plain and C.decode(plain)
    if data then S.writeTable(VAULT_FILE, { v = 1, box = S.sealTable("vault", data) }) end
  end
  K.caps.vault = function(p)
    return {
      mode = function() return S.hasPassword() and "password" or "open" end,
      load = function()
        local items, why = K.await(p, vaultLoad)
        if not items then return nil, why end
        return items
      end,
      save = function(items)
        local clean = vaultClean(items)
        if not clean then return false, "Too much data" end
        local good, why = K.await(p, function()
          if not S.unlocked() then return false, "locked" end
          S.writeTable(VAULT_FILE, { v = 1, box = S.sealTable("vault", { items = clean }) })
          return true
        end)
        return good == true, why
      end,
      -- Fresh random bytes for the password maker.
      random = function(n)
        n = tonumber(n) or 16
        if n < 1 then n = 1 elseif n > 64 then n = 64 end
        return C.bytes(math.floor(n))
      end,
    }
  end

  -- ----------------------------------------------------------- apps
  local A = "/prismarine/apps/"
  local candidates = {
    { name = "Messenger", path = A .. "messenger.lua", caps = { "net" } },
    { name = "Archive", path = A .. "archive.lua", caps = { "archive" }, hidden = function() return not N.isArchive() end },
    { name = "Programs", path = A .. "programs.lua", caps = { "net", "launch", "tools" }, hidden = bunker },
    { name = "Disks", path = A .. "disks.lua", hidden = bunker },
    { name = "Editor", path = A .. "editor.lua", hidden = bunker },
    { name = "Download", path = A .. "download.lua", caps = { "tools", "store" }, hidden = bunker },
    { name = "Vault", path = A .. "vault.lua", caps = { "vault", "account" } },
    { name = "Shell", path = A .. "shell.lua", terminate = true, locked = lockdown, system = true },
    { name = "Settings", path = A .. "settings.lua", caps = { "settings", "netadmin", "account", "perms" } },
    { name = "Others", path = A .. "others.lua", caps = { "settings", "account", "net", "update" } },
  }
  local apps = {}
  local archiveEntry
  for _, a in ipairs(candidates) do
    a.trusted = true -- built-in apps: the sealed file check covers them
    if a.path == A .. "archive.lua" then archiveEntry = a end
    if fs.exists(a.path) then apps[#apps + 1] = a end
  end
  -- After the Archive app is fetched, it joins the list without a reboot.
  addArchiveApp = function()
    if not archiveEntry then return end
    for _, a in ipairs(apps) do
      if a == archiveEntry then return end
    end
    apps[#apps + 1] = archiveEntry
  end

  local ui = UI.create(K, {
    gfx = G,
    noBoot = false,
    apps = apps,
    dashHint = "Left Alt: Apps   Right Alt: Switch   F9: Lock   F8: Alerts",
    lock = {
      check = function(pw, progress) return S.checkPassword(pw, progress) end,
    },
    lockOn = function() return S.hasPassword() end,
    power = function(what)
      if what == "reboot" then os.reboot() else os.shutdown() end
    end,
    netText = function()
      if N.isArchive() then return "Archive" end
      if N.enrolled() then return "Secured" end
      return "Open"
    end,
    statusExtra = function()
      if bunker() then return "   Bunker" end
      return lockdown() and "   Archive mode" or ""
    end,
  })
  uiApi = ui

  local hooks = ui.hooks
  local baseEvent, baseStart = hooks.onEvent, hooks.onStart

  hooks.onStart = function()
    baseStart()
    if not ui.graphics then
      K.notifySystem("Plain mode", ui.gfx.pbError or "Pixelbox not loaded", "warn")
    end
    -- A computer with little room cannot update or hold apps. Tell the person once per boot.
    local okCap, cap = pcall(fs.getCapacity, "/")
    if okCap and type(cap) == "number" and cap < 5 * 1024 * 1024 then
      K.notifySystem("Low disk space", ("This computer holds only %.1f MB. Open Others, then Guides."):format(cap / 1048576), "warn")
    end
    if bunker() then
      K.notifySystem("Bunker mode", "Archive computer. Shell, raw Lua, Programs, Download and Disks are locked.", "info")
    elseif lockdown() then
      K.notifySystem("Archive mode", "Shell, raw Lua and new programs are locked.", "info")
    end
    -- Look for updates a few seconds after boot, then on the schedule from
    -- Settings, Alerts (30 seconds to 6 hours, or never). A toast shows once
    -- for each new version.
    local toldVersion = nil
    local function setting(k)
      local ok, g = pcall(function() return K.uiApi.get() end)
      return ok and g and g[k] or nil
    end
    local function autoCheck()
      local every = setting("updateEvery")
      if every == nil then every = 21600 end
      if every > 0 then
        U.check(function(s)
          if s.state == "available" and s.version ~= toldVersion then
            toldVersion = s.version
            if setting("updateToast") ~= false then
              K.notifySystem("Update available", s.text .. " Open Others to install.", "info")
            end
          elseif s.state == "current" then
            toldVersion = nil
          end
        end)
      end
      -- Look again soon when checks are off, so turning them on takes effect.
      K.after(every > 0 and every or 30, autoCheck)
    end
    K.after(8, autoCheck)
  end

  hooks.onEvent = function(ev)
    local name = ev[1]
    if name == "redstone" then pcall(IN.poll) end
    if name == "modem_message" then
      pcall(N.handleModem, ev[2], ev[3], ev[4], ev[5])
      return true
    elseif name == "timer" then
      -- A fault in the network timer must never stop the desktop.
      local okT, mine = pcall(N.handleTimer, ev[2])
      if okT and mine then return true end
      if not okT then K.lastError = "net timer: " .. tostring(mine) end
    end
    return baseEvent(ev)
  end

  K.run(hooks)
  ui.restore()
  native.setBackgroundColor(colors.black)
  native.setTextColor(colors.white)
  native.clear()
  native.setCursorPos(1, 1)
  native.setCursorBlink(true)
  print("Prismarine stopped. Last error: " .. tostring(K.lastError))
end

local ok, err = pcall(main)
if not ok then
  fail(err)
end
