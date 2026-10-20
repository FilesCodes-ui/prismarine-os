-- /prismarine/kernel/kernel.lua
-- Prismarine OS v24, stage 6: kernel core.
--
-- Owns: the real event queue, one coroutine + hidden window per process,
-- app limit, crash handling, service auto-restart, focus, notifications API.
-- Does NOT draw any UI: the HUD / menus / cabinet (stage 2) plug in via hooks.
--
-- hooks (all optional, all pcall'd):
--   onStart()                      before the loop begins
--   onEvent(ev) -> true            see every raw event first; return true to consume
--   onTick()                       after every event (redraw the HUD here)
--   onFocus(pid|nil)               focus changed (nil = dashboard)
--   onExit(proc, kind, err)        kind = "exited" | "crashed" | "stopped"
--   onServiceDown(proc, delay)     a service died and will restart in `delay` s
--   onNotify(n)                    a notification was queued
--
-- Process classes:
--   "app"      foreground or frozen; counts toward K.MAX_APPS
--   "service"  always runs (timers, network); input only when focused;
--              auto-restarts with growing delay; never counts toward the cap

local sandbox = dofile("/prismarine/kernel/sandbox.lua")
local unpack = table.unpack or unpack

local K = {}
K.MAX_APPS = 6
K.GRACE = 3            -- seconds between a graceful stop and a force-kill
K.RESTART_MIN = 2
K.RESTART_MAX = 60
K.BUFFER_MAX = 64      -- events buffered per frozen app
K.HUD_ROWS = 1
K.notifications = {}
K.overlay = false      -- true while a menu hides the focused app's window

local nativeTerm = term.native()
local procs, order = {}, {}
local nextPid = 1
local focused = nil
local hooks = {}
local ktimers = {}
local running = false

K.lastError = nil -- last error swallowed by the kernel itself (bug detector)

-- Raw events that go only to the focused process.
local INPUT = {
  key = true, key_up = true, char = true, paste = true,
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
}
local MOUSE = {
  mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true,
}
-- Raw events broadcast to processes. Anything not listed here is dropped,
-- including modem_message (the kernel owns the modem) and unknown names.
local BROADCAST = {
  timer = true, alarm = true, term_resize = true, monitor_resize = true,
  http_success = true, http_failure = true, http_check = true,
  websocket_success = true, websocket_failure = true,
  websocket_message = true, websocket_closed = true,
  peripheral = true, peripheral_detach = true, redstone = true,
  disk = true, disk_eject = true, file_transfer = true,
  speaker_audio_empty = true, turtle_inventory = true,
}
-- Subset that is buffered for frozen apps and replayed when they regain focus.
local BUFFERED = {
  timer = true, alarm = true,
  http_success = true, http_failure = true, http_check = true,
  websocket_success = true, websocket_failure = true,
  websocket_message = true, websocket_closed = true,
}

local function pack(...)
  return { n = select("#", ...), ... }
end

local step, finish, startProc, scheduleRestart, remove, dropRequests

-- ------------------------------------------------------------ utilities

local function appArea()
  local w, h = nativeTerm.getSize()
  return 1, 1 + K.HUD_ROWS, w, h - K.HUD_ROWS
end

local function after(seconds, fn)
  local id = os.startTimer(seconds)
  ktimers[id] = fn
  return id
end
K.after = after -- kernel timers for the UI: fn runs inside the router

local function snapshotPids()
  local t = {}
  for i, pid in ipairs(order) do t[i] = pid end
  return t
end

local function compile(path, env)
  local h = fs.open(path, "r")
  if not h then return nil, "cannot open " .. tostring(path) end
  local src = h.readAll()
  h.close()
  return load(src or "", "@" .. path, "t", env)
end

local function cleanup(p)
  for h in pairs(p.handles) do pcall(h.close) end
  p.handles = setmetatable({}, { __mode = "k" })
  for id in pairs(p.timers) do os.cancelTimer(id) end
  for id in pairs(p.alarms) do os.cancelAlarm(id) end
  p.timers, p.alarms, p.pending = {}, {}, {}
  dropRequests(p)
  -- Keep the window object (restarts reuse it). A focused app keeps showing
  -- its last frame so the UI can draw a crash card over it.
  if focused ~= p.pid then p.win.setVisible(false) end
end

-- --------------------------------------------------------- notifications

local function queueNotification(n)
  local list = K.notifications
  list[#list + 1] = n
  if #list > 50 then table.remove(list, 1) end
  if hooks.onNotify then pcall(hooks.onNotify, n) end
end

local function clean(s, max)
  s = tostring(s or ""):gsub("%c", "")
  return s:sub(1, max)
end

local LEVELS = { info = true, warn = true, error = true }

-- Called through the `prismarine.notify` API by apps: sanitized, rate-limited,
-- and always labelled with the app's name (an app cannot pose as "System").
function K.notify(p, title, text, level, private)
  local now = os.clock()
  p.notifyTimes = p.notifyTimes or {}
  local t = p.notifyTimes
  while t[1] and now - t[1] > 10 do table.remove(t, 1) end
  if #t >= 3 then return false, "rate limited" end
  t[#t + 1] = now
  queueNotification({
    system = false,
    from = p.name,
    pid = p.pid,
    private = private and true or false,
    title = clean(title, 32),
    text = clean(text, 120),
    level = LEVELS[level] and level or "info",
  })
  return true
end

-- Kernel-only: the HUD must style these so apps cannot imitate them.
function K.notifySystem(title, text, level, pid)
  queueNotification({
    system = true,
    from = "System",
    pid = pid,
    title = clean(title, 32),
    text = clean(text, 120),
    level = LEVELS[level] and level or "info",
  })
end

K.VERSION = "24.0-stage6"

-- Capability APIs. Services (the UI, the network, the Archive) register a
-- maker here; an app gets one only when its spec lists that capability.
--   K.caps[name] = function(proc) return apiTable end
K.caps = {}

function K.apiFor(p)
  local api = {
    version = K.VERSION,
    appName = p.name,
    notify = function(title, text, level, private)
      return K.notify(p, title, text, level, private)
    end,
    lockdown = function() return K.lockdown and K.lockdown() or false end,
    home = "/" .. K.homeDir(p.spec),
  }
  for _, cap in ipairs(p.spec.caps or {}) do
    local maker = K.caps[cap]
    if maker then
      local ok, t = pcall(maker, p)
      if ok and t ~= nil then api[cap] = t end
    end
  end
  -- Older apps look for prismarine.ui; every app may read the look settings.
  if api.ui == nil and K.caps.ui then
    local ok, t = pcall(K.caps.ui, p)
    if ok then api.ui = t end
  end
  -- prismarine.theme: read-only colors, for apps that want to match the OS.
  if api.theme == nil and K.caps.theme then
    local ok, t = pcall(K.caps.theme, p)
    if ok then api.theme = t end
  end
  return api
end


-- ------------------------------------------------------------ permissions
-- Three tiers. Safe things (speaker, monitor, printer, colors, an app's own
-- folder, redstone input) need nothing. Ask-first things stop the app until the
-- person answers: Allow once (until the app stops), Always (remembered), or No.
-- Never things (keys, OS files, the password) are hidden by the sandbox.
K.PERM_LABEL = {
  web = "use the internet",
  redstone = "control redstone outputs",
  devices = "use a connected device",
  files = "use files outside its own folder",
  inputs = "read and change your saved redstone inputs",
  touch = "get touches on your monitors",
}
K.PERM_ORDER = { "web", "redstone", "devices", "files", "inputs", "touch" }
-- Capabilities an app can ask for in its header (not built-in apps). Each one
-- stays behind its permission of the same name.
K.APP_CAPS = { inputs = true, touch = true }
K.PERM_TIMEOUT = 90
K.permQueue = {}
local permSeq = 0

-- Boot replaces these. permStored(p, perm) -> "always" | "never" | nil.
K.permStored = function(p, perm) return nil end
K.permSave = function(p, perm, value) end
K.permSeen = function(p, perm) end

-- The folder an app may always use: appdata/<file name>.
function K.homeDir(spec)
  local base = fs.getName(spec.path or "app"):gsub("%.lua$", ""):gsub("[^%w_%-]", "_"):lower()
  if base == "" then base = "app" end
  return "appdata/" .. base
end

dropRequests = function(p)
  for i = #K.permQueue, 1, -1 do
    if K.permQueue[i].p == p then table.remove(K.permQueue, i) end
  end
end

-- The person answered (or the request timed out). choice: "once" | "always" | "no".
function K.permAnswer(req, choice)
  for i, r in ipairs(K.permQueue) do
    if r == req then table.remove(K.permQueue, i) break end
  end
  local p = req.p
  if req.done then return end
  req.done = true
  p.perms = p.perms or {}
  if choice == "always" then
    pcall(K.permSave, p, req.perm, "always")
    p.perms[req.perm] = "once"
  elseif choice == "once" then
    p.perms[req.perm] = "once"
  else
    p.perms[req.perm] = "no"
  end
  if p.alive then K.send(p.pid, "pm_perm") end
end

-- Called from inside an app's coroutine (sandbox wrappers). Returns true when
-- the app may go ahead. It waits for the person when the answer is not known.
function K.checkPerm(p, perm, detail)
  p.perms = p.perms or {}
  if p.spec.system or p.spec.trusted then
    p.perms[perm] = "once"
    return true
  end
  local d = p.perms[perm]
  if d == "once" then return true elseif d == "no" then return false end
  local stored = K.permStored(p, perm)
  if stored == "always" then p.perms[perm] = "once" return true elseif stored == "never" then return false end
  if K.bunker and K.bunker() then return false end
  if not K.permUI then return false end -- nobody can answer
  local req
  for _, r in ipairs(K.permQueue) do
    if r.p == p and r.perm == perm then req = r end
  end
  if not req then
    permSeq = permSeq + 1
    req = { p = p, perm = perm, detail = clean(detail, 80), id = permSeq, at = os.clock() }
    K.permQueue[#K.permQueue + 1] = req
    pcall(K.permSeen, p, perm)
    K.after(K.PERM_TIMEOUT, function()
      if not req.done then
        K.permAnswer(req, "no")
        K.notifySystem("No answer", p.name .. " was refused: " .. (K.PERM_LABEL[perm] or perm), "warn", p.pid)
      end
    end)
  end
  while p.perms[perm] == nil do
    local ev = coroutine.yield("pm_perm")
    if ev == "terminate" then return false end
  end
  return p.perms[perm] == "once"
end

-- The policy for a new process. Boot replaces this to apply Archive mode.
K.policyFor = function(spec) return nil end

-- ------------------------------------------------------------- stepping

-- Resume one process with one event. `force` skips the filter check
-- (first resume, graceful terminate).
function step(p, ev, force)
  if not p.alive then return end
  if not force and p.filter ~= nil and p.filter ~= ev[1] and ev[1] ~= "terminate" then
    return
  end
  -- Steps can nest (an app sends an event to a service while it runs), so
  -- put the caller's terminal back instead of assuming it was the native one.
  local prev = term.current()
  term.redirect(p.termTarget)
  p.stepping = true
  local ok, res = coroutine.resume(p.co, unpack(ev, 1, ev.n))
  p.stepping = false
  p.termTarget = term.current()
  term.redirect(prev)
  if ok and p.defer and #p.defer > 0 and coroutine.status(p.co) ~= "dead" then
    -- Events sent to this process while it was running arrive right after.
    local nextEv = table.remove(p.defer, 1)
    p.filter = res
    return step(p, nextEv)
  end
  if not ok then
    finish(p, "crashed", res)
  elseif coroutine.status(p.co) == "dead" then
    finish(p, "exited")
  else
    p.filter = res
  end
end

function remove(p)
  p.win.setVisible(false)
  procs[p.pid] = nil
  for i, pid in ipairs(order) do
    if pid == p.pid then table.remove(order, i) break end
  end
  if focused == p.pid then
    focused = nil
    if hooks.onFocus then pcall(hooks.onFocus, nil) end
  end
end

function scheduleRestart(p)
  local lived = os.clock() - p.startedAt
  if lived > 60 then p.crashes = 0 end
  p.crashes = (p.crashes or 0) + 1
  local delay = math.min(K.RESTART_MAX, K.RESTART_MIN * 2 ^ (p.crashes - 1))
  p.restartAt = os.clock() + delay
  p.degraded = p.crashes >= 5
  local gen = p.gen
  after(delay, function()
    if procs[p.pid] == p and not p.alive and not p.stopRequested and p.gen == gen then
      startProc(p)
    end
  end)
  if hooks.onServiceDown then pcall(hooks.onServiceDown, p, delay) end
end

function finish(p, kind, err)
  if p.stopRequested then kind, err = "stopped", nil end
  p.alive = false
  p.exitKind = kind
  p.err = (kind == "crashed") and tostring(err) or nil
  cleanup(p)
  if hooks.onExit then pcall(hooks.onExit, p, kind, p.err) end

  if p.stopRequested then
    remove(p)
  elseif p.spec.class == "service" then
    if focused ~= p.pid then
      K.notifySystem(p.name .. " stopped", p.err or "service exited", "warn", p.pid)
    end
    scheduleRestart(p)
  elseif kind == "crashed" then
    -- stays in the table so the UI can show a crash card until dismissed
    if focused ~= p.pid then
      K.notifySystem(p.name .. " crashed", p.err, "error", p.pid)
    end
  else
    remove(p)
  end
end

function startProc(p)
  p.gen = p.gen + 1
  p.alive = true
  p.stopRequested = false
  p.exitKind, p.err, p.restartAt = nil, nil, nil
  p.startedAt = os.clock()
  p.handles = setmetatable({}, { __mode = "k" })
  p.timers, p.alarms, p.pending = {}, {}, {}
  p.filter = nil
  p.perms = {}
  p.hashV = nil
  p.termTarget = p.win

  p.win.setBackgroundColor(colors.black)
  p.win.setTextColor(colors.white)
  p.win.clear()
  p.win.setCursorPos(1, 1)
  p.win.setVisible(focused == p.pid)

  local env = sandbox.build(p, K.apiFor(p), nativeTerm, K.policyFor(p.spec))
  local fn, err = compile(p.spec.path, env)
  if not fn then
    finish(p, "crashed", err)
    return
  end
  p.co = coroutine.create(fn)
  step(p, pack(unpack(p.spec.args or {})), true)
end

-- ---------------------------------------------------------------- routing

local function deliver(p, ev)
  if not p.alive then return end
  local name = ev[1]
  local live = (p.spec.class == "service") or (focused == p.pid)
  if live then
    step(p, ev)
  elseif BUFFERED[name] then
    local owned = (name == "timer" and p.timers[ev[2]])
      or (name == "alarm" and p.alarms[ev[2]])
      or (name ~= "timer" and name ~= "alarm")
    if owned then
      local q = p.pending
      if #q >= K.BUFFER_MAX then table.remove(q, 1) end
      q[#q + 1] = ev
    end
  end
  if p.alive then
    if name == "timer" then p.timers[ev[2]] = nil end
    if name == "alarm" then p.alarms[ev[2]] = nil end
  end
end

local function route(ev)
  local name = ev[1]
  if name == "terminate" then
    -- Ctrl+T reaches only an app that asks for it (the shell). Never the OS.
    local p = procs[focused]
    if p and p.alive and p.spec.terminate and not K.overlay then step(p, ev) end
    return
  end

  -- An app's own queued event goes back to that app only.
  if name == "pm_app" then
    local p = procs[ev[2]]
    if p and p.alive and p.gen == ev[3] then
      local inner = pack(unpack(ev, 4, ev.n))
      if p.spec.class == "service" or focused == p.pid then
        step(p, inner)
      else
        local q = p.pending
        if #q >= K.BUFFER_MAX then table.remove(q, 1) end
        q[#q + 1] = inner
      end
    end
    return
  end

  if name == "timer" and ktimers[ev[2]] then
    local fn = ktimers[ev[2]]
    ktimers[ev[2]] = nil
    fn()
    return
  end

  if INPUT[name] then
    local p = procs[focused]
    if p and p.alive then
      if MOUSE[name] then
        ev[4] = ev[4] - K.HUD_ROWS
        if ev[4] < 1 then return end
      end
      step(p, ev)
    end
    return
  end

  if name == "term_resize" then K.relayout() end

  if name == "monitor_touch" then
    for _, pid in ipairs(snapshotPids()) do
      local p = procs[pid]
      if p and p.alive and p.perms and p.perms.touch == "once" then deliver(p, ev) end
    end
    return
  end

  if BROADCAST[name] then
    for _, pid in ipairs(snapshotPids()) do
      local p = procs[pid]
      if p then deliver(p, ev) end
    end
  end
end

-- ------------------------------------------------------------- public API

function K.relayout()
  local x, y, w, h = appArea()
  for _, p in pairs(procs) do p.win.reposition(x, y, w, h) end
end

function K.appCount()
  local n = 0
  for _, p in pairs(procs) do
    if p.spec.class == "app" then n = n + 1 end
  end
  return n
end

-- spec = { name=, path=, class="app"|"service", pinned=bool, args={...},
--          caps={...}, terminate=bool }
-- K.canSpawn(spec) may refuse (Archive mode, unapproved programs).
function K.spawn(spec)
  assert(type(spec) == "table" and type(spec.path) == "string", "spec.path required")
  spec.class = spec.class or "app"
  if K.canSpawn then
    local ok, why = K.canSpawn(spec)
    if not ok then return nil, why or "Blocked" end
  end
  if spec.class == "app" and K.appCount() >= K.MAX_APPS then
    return nil, "App limit reached (" .. K.MAX_APPS .. ")"
  end
  local x, y, w, h = appArea()
  local p = {
    pid = nextPid,
    name = spec.name or fs.getName(spec.path),
    spec = spec,
    gen = 0,
    win = window.create(nativeTerm, x, y, w, h, false),
  }
  p.home = K.homeDir(spec)
  p.checkPerm = function(perm, detail) return K.checkPerm(p, perm, detail) end
  nextPid = nextPid + 1
  procs[p.pid] = p
  order[#order + 1] = p.pid
  startProc(p)
  return p.pid
end

-- Graceful stop sends the standard CC "terminate" event (apps using
-- os.pullEvent unwind via error "Terminated"), then force-kills after GRACE.
function K.kill(pid, force)
  local p = procs[pid]
  if not p then return false, "no such process" end
  if p.spec.pinned and not force then return false, "pinned" end
  p.stopRequested = true
  if not p.alive then
    remove(p)
    return true
  end
  if force then
    finish(p, "stopped")
    return true
  end
  step(p, pack("terminate"), true)
  if p.alive then
    local gen = p.gen
    after(K.GRACE, function()
      if p.alive and p.gen == gen and p.stopRequested then finish(p, "stopped") end
    end)
  end
  return true
end

function K.restart(pid)
  local p = procs[pid]
  if p and not p.alive then
    startProc(p)
    return true
  end
  return false
end

function K.dismiss(pid)
  local p = procs[pid]
  if p and not p.alive then
    remove(p)
    return true
  end
  return false
end

function K.focus(pid)
  if pid ~= nil and not procs[pid] then return false end
  if pid == focused then return true end
  local old = procs[focused]
  if old then old.win.setVisible(false) end
  focused = pid
  local p = procs[pid]
  if p then
    p.win.setVisible(not K.overlay) -- redraws the window's saved buffer
    local queue = p.pending
    p.pending = {}
    for _, ev in ipairs(queue) do step(p, ev) end
  end
  if hooks.onFocus then pcall(hooks.onFocus, pid) end
  return true
end

function K.getFocus()
  return focused
end

-- A menu is open: hide the focused app's window so the app keeps drawing into
-- its buffer but cannot paint over the menu. Turning it off redraws the app.
function K.setOverlay(on)
  K.overlay = on and true or false
  local p = procs[focused]
  if p then p.win.setVisible(not K.overlay) end
end

-- Repaint the focused app's window (restores pixels a toast or card covered).
function K.redrawFocused()
  local p = procs[focused]
  if p and not K.overlay then p.win.redraw() end
end

function K.restoreCursor()
  local p = procs[focused]
  if p and p.alive and p.win.restoreCursor then p.win.restoreCursor() end
end

function K.list()
  local out = {}
  for _, pid in ipairs(order) do
    local p = procs[pid]
    out[#out + 1] = {
      pid = p.pid,
      name = p.name,
      path = p.spec.path,
      class = p.spec.class,
      pinned = p.spec.pinned,
      alive = p.alive,
      focused = (focused == p.pid),
      exitKind = p.exitKind,
      err = p.err,
      crashes = p.crashes or 0,
      degraded = p.degraded,
      restartIn = p.restartAt and math.max(0, p.restartAt - os.clock()) or nil,
      pending = #p.pending,
    }
  end
  return out
end

-- Copy of a process's last frame for the cabinet preview (stage 2).
-- Returns nil if this CC version has no window.getLine.
-- The first and last row of an app window (for the rounded frame).
function K.edgeRows(pid)
  local p = procs[pid]
  if not p then return nil end
  local _, h = p.win.getSize()
  local ok1, t1, f1, b1 = pcall(p.win.getLine, 1)
  local ok2, t2, f2, b2 = pcall(p.win.getLine, h)
  if not (ok1 and ok2) then return nil end
  return { top = { text = t1, fg = f1, bg = b1 }, bottom = { text = t2, fg = f2, bg = b2 } }
end

function K.snapshot(pid)
  local p = procs[pid]
  if not p then return nil end
  local w, h = p.win.getSize()
  local rows = {}
  for y = 1, h do
    local ok, text, fg, bg = pcall(p.win.getLine, y)
    if not ok then return nil end
    rows[y] = { text = text, fg = fg, bg = bg }
  end
  return { w = w, h = h, rows = rows }
end

-- Kernel-to-process synthetic event (e.g. new messages for Messenger).
-- Never travels through the real event queue, so apps cannot forge it.
-- A frozen app gets it when it comes back.
function K.send(pid, ...)
  local p = procs[pid]
  if not (p and p.alive) then return false end
  local ev = pack(...)
  if p.stepping then
    p.defer = p.defer or {}
    if #p.defer < K.BUFFER_MAX then p.defer[#p.defer + 1] = ev end
  elseif p.spec.class == "service" or focused == p.pid then
    step(p, ev)
  else
    local q = p.pending
    if #q >= K.BUFFER_MAX then table.remove(q, 1) end
    q[#q + 1] = ev
  end
  return true
end

-- Send an event to every process that holds a capability.
function K.sendCap(cap, ...)
  for _, pid in ipairs(snapshotPids()) do
    local p = procs[pid]
    if p and p.alive then
      local allowed = true
      if K.APP_CAPS[cap] and not (p.spec.system or p.spec.trusted) then
        allowed = p.perms ~= nil and p.perms[cap] == "once"
      end
      if allowed then
        for _, c in ipairs(p.spec.caps or {}) do
          if c == cap then K.send(pid, ...) break end
        end
      end
    end
  end
end

function K.find(name)
  for _, pid in ipairs(order) do
    local p = procs[pid]
    if p and p.name == name then return pid end
  end
  return nil
end

function K.stop()
  running = false
end

-- ------------------------------------------------------------------ tasks
-- Kernel work that has to wait for events (password hashing) runs as a task,
-- so apps and services keep getting their events meanwhile.
local tasks = {}

function K.task(fn, done)
  local t = { co = coroutine.create(fn), done = done }
  tasks[#tasks + 1] = t
  local r = table.pack(coroutine.resume(t.co))
  t.filter = r[2]
  if not r[1] or coroutine.status(t.co) == "dead" then
    for i = #tasks, 1, -1 do
      if tasks[i] == t then table.remove(tasks, i) break end
    end
    if done then pcall(done, unpack(r, 1, r.n)) end
  end
  return t
end

local function stepTasks(ev)
  for i = #tasks, 1, -1 do
    local t = tasks[i]
    if t and (t.filter == nil or t.filter == ev[1]) then
      local r = table.pack(coroutine.resume(t.co, unpack(ev, 1, ev.n)))
      if not r[1] or coroutine.status(t.co) == "dead" then
        table.remove(tasks, i)
        if t.done then pcall(t.done, unpack(r, 1, r.n)) end
      else
        t.filter = r[2]
      end
    end
  end
end

-- Called from inside an app's coroutine (a capability API): runs fn as a
-- kernel task and returns its results to the app when it finishes.
local taskSeq = 0
function K.await(proc, fn)
  taskSeq = taskSeq + 1
  local id = taskSeq
  local result = nil
  K.task(fn, function(ok, ...)
    result = table.pack(ok, ...)
    if proc.co and coroutine.status(proc.co) == "suspended" then K.send(proc.pid, "pm_task", id) end
  end)
  while not result do
    local ev, got = coroutine.yield("pm_task")
    if ev == "terminate" then break end
  end
  if not result then return nil end
  if not result[1] then error(result[2], 0) end
  return unpack(result, 2, result.n)
end

function K.run(h)
  hooks = h or {}
  running = true
  if hooks.onStart then pcall(hooks.onStart) end

  while running do
    local ev = pack(os.pullEventRaw())
    if #tasks > 0 then
      local ok, err = pcall(stepTasks, ev)
      if not ok then K.lastError = "task: " .. tostring(err) end
    end
    local consumed = false
    if hooks.onEvent then
      local ok, res = pcall(hooks.onEvent, ev)
      if ok then consumed = res else K.lastError = "hook: " .. tostring(res) end
    end
    if not consumed then
      local ok, err = pcall(route, ev)
      if not ok then K.lastError = "route: " .. tostring(err) end
    end
    if hooks.onTick then
      local ok, err = pcall(hooks.onTick)
      if not ok then K.lastError = "tick: " .. tostring(err) end
    end
  end

  for _, pid in ipairs(snapshotPids()) do
    local p = procs[pid]
    if p then
      p.stopRequested = true
      if p.alive then finish(p, "stopped") else remove(p) end
    end
  end
  focused = nil
  term.redirect(nativeTerm)
end

return K
