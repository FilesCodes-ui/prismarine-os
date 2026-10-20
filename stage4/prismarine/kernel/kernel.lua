-- /prismarine/kernel/kernel.lua
-- Prismarine OS v23, stage 2: kernel core (stage 1 plus overlay and UI support).
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

local step, finish, startProc, scheduleRestart, remove

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

function K.apiFor(p)
  return {
    version = "23.0-stage4",
    appName = p.name,
    ui = K.uiApi,
    notify = function(title, text, level, private)
      return K.notify(p, title, text, level, private)
    end,
  }
end

-- ------------------------------------------------------------- stepping

-- Resume one process with one event. `force` skips the filter check
-- (first resume, graceful terminate).
function step(p, ev, force)
  if not p.alive then return end
  if not force and p.filter ~= nil and p.filter ~= ev[1] and ev[1] ~= "terminate" then
    return
  end
  term.redirect(p.termTarget)
  local ok, res = coroutine.resume(p.co, unpack(ev, 1, ev.n))
  p.termTarget = term.current()
  term.redirect(nativeTerm)
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
  p.termTarget = p.win

  p.win.setBackgroundColor(colors.black)
  p.win.setTextColor(colors.white)
  p.win.clear()
  p.win.setCursorPos(1, 1)
  p.win.setVisible(focused == p.pid)

  local env = sandbox.build(p, K.apiFor(p), nativeTerm)
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
  if name == "terminate" then return end -- Ctrl+T is ignored: the kernel owns recovery

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

-- spec = { name=, path=, class="app"|"service", pinned=bool, args={...} }
function K.spawn(spec)
  assert(type(spec) == "table" and type(spec.path) == "string", "spec.path required")
  spec.class = spec.class or "app"
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

-- Kernel-to-process synthetic event (e.g. decrypted messages for Messenger).
-- Never travels through the real event queue, so apps cannot forge it.
function K.send(pid, ...)
  local p = procs[pid]
  if p and p.alive and p.spec.class == "service" then
    step(p, pack(...))
    return true
  end
  return false
end

function K.stop()
  running = false
end

function K.run(h)
  hooks = h or {}
  running = true
  if hooks.onStart then pcall(hooks.onStart) end

  while running do
    local ev = pack(os.pullEventRaw())
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
