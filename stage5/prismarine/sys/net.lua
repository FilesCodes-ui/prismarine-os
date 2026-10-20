-- /prismarine/sys/net.lua
-- Prismarine OS v23: the network service. Kernel code only.
--
-- Only the kernel touches modems. Apps talk to it through narrow APIs:
--   net        Messenger: contacts, chats, files, pairing
--   netadmin   Settings: join or leave an Archive, become an Archive
--   archive    the Archive app: enrolments, members, bans, approvals, logs
--
-- Security design (see README_stage5):
--   Every computer has an Ed25519 signing key and an X25519 exchange key,
--   sealed on disk with the login password.
--   A peer is trusted only after pairing (both people compare a code) or when
--   an Archive the user confirmed has signed its certificate.
--   Private messages: a fresh random key encrypts the message (ChaCha20-
--   Poly1305). That key is wrapped for the recipient, and for the Archive when
--   there is one, each with a new ephemeral X25519 key. The sender signs the
--   message, so it cannot be forged or altered, and a counter plus a time
--   window stop replays.
--   Unknown or banned senders are dropped before any expensive work, and each
--   sender is rate limited.
--   No message can make another computer delete, run or change anything.

local N = {}
N.CHANNEL = 47823
N.PROTO = "pm1"
N.MAX_TEXT = 1000
N.CHUNK = 8192
N.MAX_FILE = 1000000
N.WINDOW = 300000          -- ms: messages older or newer than 5 min are dropped

local K, C, S
local me = nil              -- { id, name, ipk, xpk, isk, xsk }
local state = nil           -- persisted (secure/net)
local arc = nil             -- Archive role keys when this computer is the Archive
local ui = {}               -- callbacks into the UI (notify)

local history, unread = {}, {}
local peers = {}            -- id -> { name, ipk, xpk, seen } from hello beacons (not trusted)
local pairIn, pairOut = {}, {}
local offers, sending, receiving = {}, {}, {}
local finished = {}        -- xid -> result of a finished receive, kept 60 s so a lost reply can be repeated
local archives = {}         -- archive id -> beacon info, while looking for one
local enrollWait = nil      -- { archiveId, cert, ... } waiting for the user to confirm
local buckets = {}
local stats = { dropped = 0, bad = 0, ok = 0, sent = 0 }
local arcPending, arcApprovals = {}, {}
local arcFiles = nil

-- ------------------------------------------------------------- helpers

local function now() return os.epoch("utc") end
local function idStr(id) return string.format("%.0f", id) end

local function clean(s, max)
  return tostring(s or ""):gsub("[%c]", " "):sub(1, max or 40)
end

local function save()
  S.writeTable("net", state)
end

local function saveArchive()
  if arc then
    S.writeTable("archive", {
      v = 1, apk = C.hex(arc.apk), axpk = C.hex(arc.axpk),
      box = S.sealTable("archive", { ask = arc.ask, axsk = arc.axsk, logKey = arc.logKey }),
      roster = state.roster,
    })
  end
end

local function modems()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then list[#list + 1] = name end
  end
  return list
end

function N.openModems()
  local any = false
  for _, name in ipairs(modems()) do
    if pcall(peripheral.call, name, "open", N.CHANNEL) then any = true end
  end
  return any
end

local function transmit(t)
  t.p = N.PROTO
  local sent = false
  for _, name in ipairs(modems()) do
    pcall(peripheral.call, name, "open", N.CHANNEL)
    if pcall(peripheral.call, name, "transmit", N.CHANNEL, N.CHANNEL, t) then sent = true end
  end
  if sent then stats.sent = stats.sent + 1 end
  return sent
end

local function nextCtr()
  state.ctr = (state.ctr or 0) + 1
  save()
  return state.ctr
end

local function addHistory(key, line)
  local h = history[key]
  if not h then h = {} history[key] = h end
  h[#h + 1] = line
  if #h > 100 then table.remove(h, 1) end
end

-- Token bucket per sender: 12 messages, 3 more per second.
local function allow(from)
  local b = buckets[from]
  local t = os.clock()
  if not b then b = { n = 12, t = t } buckets[from] = b end
  b.n = math.min(12, b.n + (t - b.t) * 3)
  b.t = t
  if b.n < 1 then return false end
  b.n = b.n - 1
  return true
end

local function fresh(ts)
  return type(ts) == "number" and math.abs(now() - ts) <= N.WINDOW
end

-- ------------------------------------------------------------- trust

N.enrolled = function() return state and state.archive ~= nil end

-- The public keys of someone we trust, or nil.
local function trusted(id)
  if not state then return nil end
  if arc and state.roster then
    -- This computer is the Archive: its members are the roster.
    local sid = idStr(id)
    if state.roster.bans and state.roster.bans[sid] then return nil end
    local m = state.roster.members and state.roster.members[sid]
    if m then return { name = m.name, ipk = C.unhex(m.ipk), xpk = C.unhex(m.xpk) } end
    return nil
  end
  if state.archive then
    if state.roster and state.roster.bans and state.roster.bans[idStr(id)] then return nil end
    local m = state.roster and state.roster.members and state.roster.members[idStr(id)]
    if m then return { name = m.name, ipk = C.unhex(m.ipk), xpk = C.unhex(m.xpk) } end
    if id == state.archive.id then
      return { name = state.archive.name, ipk = C.unhex(state.archive.apk), xpk = C.unhex(state.archive.axpk) }
    end
    return nil
  end
  local c = state.contacts[idStr(id)]
  if c then return { name = c.name, ipk = C.unhex(c.ipk), xpk = C.unhex(c.xpk) } end
  return nil
end
N.trusted = trusted

local function nameOf(id)
  local t = trusted(id)
  if t then return t.name end
  local p = peers[id]
  if p then return p.name .. "?" end
  return "#" .. idStr(id)
end

local function archiveKeys()
  if not state.archive then return nil end
  return { ipk = C.unhex(state.archive.apk), xpk = C.unhex(state.archive.axpk) }
end

-- ------------------------------------------------------------- sending

-- Sends one sealed private message. data is a table.
local function sealedSend(kind, to, data, toArchiveOnly)
  local peer = (not toArchiveOnly) and trusted(to) or nil
  if not toArchiveOnly and not peer then return false, "Not a trusted contact" end
  local ak = archiveKeys()
  if toArchiveOnly and not ak then return false, "No Archive" end
  local ts, ctr = now(), nextCtr()
  local head = { f = me.id, to = to, ts = ts, ctr = ctr, k = kind }
  local body = C.encode(data)
  local sig = C.sign(me, "pm1|" .. C.encode(head) .. body)
  local key = C.bytes(32)
  local env = {
    k = kind, f = me.id, to = to, ts = ts, ctr = ctr,
    box = C.seal(key, C.encode({ d = body, s = sig }), C.encode(head)),
  }
  if peer then env.wk = C.wrap(key, peer.xpk) end
  if ak then env.wa = C.wrap(key, ak.xpk) end
  local ok = transmit(env)
  if not ok then return false, "No modem" end
  return true, key
end

-- Opens a sealed envelope with the given exchange identity (me or the Archive).
-- Returns data, sender keys, message key; or nil.
local function sealedOpen(env, who, wrapped)
  local from = trusted(env.f)
  if not from then return nil, "unknown" end
  local key = C.unwrap(who, wrapped)
  if not key then return nil, "wrap" end
  local head = { f = env.f, to = env.to, ts = env.ts, ctr = env.ctr, k = env.k }
  local plain = C.open(key, env.box, C.encode(head))
  local inner = plain and C.decode(plain)
  if type(inner) ~= "table" or type(inner.d) ~= "string" or type(inner.s) ~= "string" then return nil, "box" end
  if not C.verify(from.ipk, "pm1|" .. C.encode(head) .. inner.d, inner.s) then return nil, "sig" end
  local data = C.decode(inner.d)
  if type(data) ~= "table" then return nil, "data" end
  return data, from, key
end

local function signedSend(t)
  t.f, t.ts = me.id, now()
  t.p = N.PROTO
  t.sig = nil
  t.sig = C.sign(me, "pm1s|" .. C.encode(t))
  return transmit(t)
end

local function signedCheck(t, ipk)
  local sig = t.sig
  if type(sig) ~= "string" then return false end
  t.sig = nil
  local ok = C.verify(ipk, "pm1s|" .. C.encode(t), sig)
  t.sig = sig
  return ok
end

-- ------------------------------------------------------------- audit

local auditLast, auditWin, auditN = {}, 0, 0
function N.audit(kind, text)
  if not (state and state.archive and me) then return end
  kind = tostring(kind or "event"):gsub("[^%w_]", "_"):sub(1, 20)
  text = clean(text, 160)
  local key, t = kind .. "|" .. text, now()
  if auditLast[key] and t - auditLast[key] < 2000 then return end
  auditLast[key] = t
  if t - auditWin > 5000 then auditWin, auditN = t, 0 end
  if auditN >= 10 then return end
  auditN = auditN + 1
  pcall(sealedSend, "audit", state.archive.id, { kind = kind, text = text, name = me.name }, true)
end

-- ------------------------------------------------------------- receiving

local handlers = {}

local function notify(title, text, level, pid)
  if ui.notify then pcall(ui.notify, title, text, level, pid) end
end

local function event(...)
  if ui.event then pcall(ui.event, ...) end
end

function handlers.hello(m)
  if type(m.name) ~= "string" or type(m.ipk) ~= "string" or #m.ipk ~= 32 or type(m.xpk) ~= "string" or #m.xpk ~= 32 then return end
  if not signedCheck(m, m.ipk) then return end
  peers[m.f] = { name = clean(m.name, 20), ipk = m.ipk, xpk = m.xpk, seen = os.clock() }
  if m.ask and not m.reply then
    signedSend({ k = "hello", name = me.name, ipk = me.ipk, xpk = me.xpk, reply = true })
  end
  event("net_peers")
end

-- Pairing: both people compare the same code before trust is given.
local function pairCode(a, b)
  if a > b then a, b = b, a end
  return C.fingerprint(a .. b, 3)
end
N.pairCode = pairCode

function handlers.pair(m)
  if state.archive then return end -- Archive mode: only the Archive decides
  if m.to ~= me.id or type(m.ipk) ~= "string" or #m.ipk ~= 32 or type(m.xpk) ~= "string" or #m.xpk ~= 32 then return end
  if not signedCheck(m, m.ipk) then return end
  local n = 0
  for _ in pairs(pairIn) do n = n + 1 end
  if n >= 8 and not pairIn[m.f] then return end
  pairIn[m.f] = { id = m.f, name = clean(m.name, 20), ipk = m.ipk, xpk = m.xpk, at = os.clock(), code = pairCode(me.ipk, m.ipk) }
  notify("Pair request", clean(m.name, 20) .. " (#" .. idStr(m.f) .. ") wants to pair", "info")
  event("net_pair")
end

function handlers.pair_ok(m)
  local out = pairOut[m.f]
  if not out or m.to ~= me.id then return end
  if type(m.ipk) ~= "string" or #m.ipk ~= 32 or type(m.xpk) ~= "string" or #m.xpk ~= 32 then return end
  if not signedCheck(m, m.ipk) then return end
  out.ipk, out.xpk, out.name = m.ipk, m.xpk, clean(m.name, 20)
  out.code = pairCode(me.ipk, m.ipk)
  out.answered = true
  event("net_pair")
end

function handlers.msg(m)
  if m.to ~= me.id or type(m.wk) ~= "string" then return end
  if not trusted(m.f) then return "unknown" end
  if not fresh(m.ts) or type(m.ctr) ~= "number" then return "old" end
  local last = state.last[idStr(m.f)] or 0
  if m.ctr <= last then return "replay" end
  local data, from, key = sealedOpen(m, me, m.wk)
  if not data then return "bad" end
  state.last[idStr(m.f)] = m.ctr
  save()
  if m.k == "msg" then
    if data.kind == "text" and type(data.text) == "string" then
      local key = m.f
      addHistory(key, { who = from.name, text = data.text:sub(1, N.MAX_TEXT), mine = false, at = m.ts })
      unread[key] = (unread[key] or 0) + 1
      event("net_message", m.f)
      notify(from.name, data.text:sub(1, 60), "info", nil)
    elseif data.kind == "file_offer" then
      if type(data.xid) ~= "string" or type(data.name) ~= "string" or type(data.size) ~= "number"
        or type(data.chunks) ~= "number" or type(data.fk) ~= "string" or #data.fk ~= 32 then return "bad" end
      if data.size < 1 or data.size > N.MAX_FILE or data.chunks ~= math.ceil(data.size / N.CHUNK) then return "bad" end
      if receiving[data.xid] then
        -- Our "accept" was lost. Say it again.
        local rr = receiving[data.xid]
        if rr.from == m.f then
          local t = { k = "fctl", to = rr.from, xid = rr.xid, op = "accept", f = me.id }
          t.mac = C.mac(rr.fk, C.encode({ op = "accept", xid = rr.xid, n = nil, why = nil, f = me.id }))
          transmit(t)
        end
        return true
      end
      local n = 0
      for _ in pairs(offers) do n = n + 1 end
      if n >= 10 then return "full" end
      offers[data.xid] = {
        xid = data.xid, from = m.f, who = from.name, name = clean(fs.getName(data.name), 64),
        size = data.size, chunks = data.chunks, sum = data.sum, fk = data.fk, at = os.clock(),
      }
      notify("File from " .. from.name, clean(data.name, 40), "info")
      event("net_files")
    end
  end
  return true
end

-- File transfer control and chunks, authenticated with the file key.
function handlers.fctl(m)
  if m.to ~= me.id or type(m.xid) ~= "string" then return end
  local s = sending[m.xid] or receiving[m.xid] or offers[m.xid]
  if not s then return end
  local peer = s.to or s.from
  if m.f ~= peer then return end
  local expect = C.mac(s.fk, C.encode({ op = m.op, xid = m.xid, n = m.n, why = m.why, f = m.f }))
  if not C.same(expect, m.mac) then return "bad" end
  if sending[m.xid] then
    local x = sending[m.xid]
    if m.op == "accept" then x.accepted = true
    elseif m.op == "ack" and type(m.n) == "number" then x.acked = math.max(x.acked or 0, m.n)
    elseif m.op == "decline" or m.op == "cancel" then x.failed = m.why or "Declined"
    elseif m.op == "result" then x.result = m.why or "ok" end
    if x.wake then x.wake() end
  elseif receiving[m.xid] then
    if m.op == "cancel" then receiving[m.xid].failed = "Cancelled" end
  elseif offers[m.xid] and m.op == "cancel" then
    offers[m.xid] = nil
    event("net_files")
  end
end

function handlers.fchunk(m)
  if m.to ~= me.id or type(m.xid) ~= "string" then return end
  local r = receiving[m.xid]
  if not r then
    local f = finished[m.xid]
    if f and m.f == f.from and os.clock() - f.at < 60 then
      local t = { k = "fctl", to = f.from, xid = m.xid, op = "result", why = f.why, f = me.id }
      t.mac = C.mac(f.fk, C.encode({ op = "result", xid = m.xid, n = nil, why = f.why, f = me.id }))
      transmit(t)
    end
    return
  end
  if m.f ~= r.from or type(m.n) ~= "number" then return end
  local data = C.open(r.fk, m.box, C.encode({ xid = m.xid, n = m.n, f = m.f, to = m.to }))
  if not data then return "bad" end
  if m.n == r.next then
    r.parts[m.n] = data
    r.next = r.next + 1
  end
  local function ctl(op, n, why)
    local t = { k = "fctl", to = r.from, xid = r.xid, op = op, n = n, why = why, f = me.id }
    t.mac = C.mac(r.fk, C.encode({ op = op, xid = r.xid, n = n, why = why, f = me.id }))
    transmit(t)
  end
  if m.n < r.next then ctl("ack", m.n) end
  event("net_progress", m.xid, (r.next - 1) / r.chunks)
  if r.next > r.chunks then
    local all = table.concat(r.parts)
    receiving[m.xid] = nil
    if #all ~= r.size or (r.sum and C.sha256hex(all) ~= r.sum) then
      finished[m.xid] = { from = r.from, fk = r.fk, why = "The file arrived damaged.", at = os.clock() }
      ctl("result", nil, "The file arrived damaged.")
      event("net_file_done", r.xid, false, "The file arrived damaged.")
      return
    end
    finished[m.xid] = { from = r.from, fk = r.fk, why = "ok", at = os.clock() }
    ctl("result", nil, "ok")
    N.audit("file", "received " .. r.name .. " from #" .. idStr(r.from))
    if r.done then r.done(all) end
    event("net_file_done", r.xid, true, r.name)
  end
end

function handlers.pub(m)
  local t = trusted(m.f)
  if not t or type(m.text) ~= "string" then return "unknown" end
  if not fresh(m.ts) then return "old" end
  local last = state.lastPub[idStr(m.f)] or 0
  if type(m.ctr) ~= "number" or m.ctr <= last then return "replay" end
  if not signedCheck(m, t.ipk) then return "bad" end
  state.lastPub[idStr(m.f)] = m.ctr
  addHistory("all", { who = t.name, text = m.text:sub(1, N.MAX_TEXT), mine = false, at = m.ts })
  unread.all = (unread.all or 0) + 1
  event("net_message", "all")
end

-- --- Archive side of the protocol (clients)

function handlers.abeacon(m)
  if type(m.apk) ~= "string" or #m.apk ~= 32 or type(m.axpk) ~= "string" or #m.axpk ~= 32 then return end
  if not signedCheck(m, m.apk) then return end
  archives[m.f] = { id = m.f, name = clean(m.name, 24), apk = m.apk, axpk = m.axpk, fp = C.fingerprint(m.apk), seen = os.clock() }
  event("net_archives")
  -- An enrolled computer asks for the newest roster when its Archive shows up.
  if state.archive and m.f == state.archive.id and C.same(m.apk, C.unhex(state.archive.apk)) then
    if (m.rv or 0) > ((state.roster and state.roster.v) or 0) then
      transmit({ k = "roster_req", f = me.id, to = m.f })
    end
  end
end

function handlers.enrolled(m)
  if not enrollWait or m.to ~= me.id or m.f ~= enrollWait.id then return end
  local a = enrollWait
  if type(m.cert) ~= "string" or type(m.csig) ~= "string" then return end
  if not C.verify(a.apk, "pm1cert|" .. m.cert, m.csig) then return "bad" end
  local cert = C.decode(m.cert)
  if type(cert) ~= "table" or cert.id ~= me.id or not C.same(cert.ipk or "", C.hex(me.ipk)) then return "bad" end
  a.cert, a.csig = m.cert, m.csig
  a.answered = true
  event("net_enroll")
end

function handlers.denied(m)
  if not enrollWait or m.to ~= me.id or m.f ~= enrollWait.id then return end
  if not signedCheck(m, enrollWait.apk) then return end
  enrollWait.refused = true
  event("net_enroll")
end

function handlers.roster(m)
  if not state.archive or m.f ~= state.archive.id then return end
  if type(m.body) ~= "string" or type(m.rsig) ~= "string" then return end
  if not C.verify(C.unhex(state.archive.apk), "pm1roster|" .. m.body, m.rsig) then return "bad" end
  local r = C.decode(m.body)
  if type(r) ~= "table" or type(r.v) ~= "number" then return "bad" end
  if r.v <= ((state.roster and state.roster.v) or 0) then return end
  state.roster = r
  save()
  -- Banned: Archive mode stays on. Released: the Archive let this computer go.
  if r.released and r.released[idStr(me.id)] then
    state.archive, state.roster = nil, nil
    save()
    notify("Archive", "This computer left the Archive network", "info")
  end
  event("net_roster")
end

-- --- Archive role (this computer is the Archive)

local function arcSign(msg) return C.sign({ isk = arc.ask, ipk = arc.apk }, msg) end

local function rosterBody()
  return C.encode(state.roster)
end

function N.arcBroadcastRoster()
  if not arc then return end
  local body = rosterBody()
  transmit({ k = "roster", f = me.id, body = body, rsig = arcSign("pm1roster|" .. body) })
end

local function arcBeacon(ask)
  if not arc then return end
  local t = { k = "abeacon", f = me.id, ts = now(), name = state.arcName or ("Archive #" .. idStr(me.id)),
    apk = arc.apk, axpk = arc.axpk, rv = state.roster and state.roster.v or 0 }
  t.p = N.PROTO
  t.sig = arcSign("pm1s|" .. C.encode(t))
  transmit(t)
end

local function arcRecord(rec)
  if ui.archiveRecord then pcall(ui.archiveRecord, rec) end
end

function handlers.enroll(m)
  if not arc or m.to ~= me.id then return end
  if type(m.ipk) ~= "string" or #m.ipk ~= 32 or type(m.xpk) ~= "string" or #m.xpk ~= 32 then return end
  if not fresh(m.ts) or not signedCheck(m, m.ipk) then return end
  local n = 0
  for _ in pairs(arcPending) do n = n + 1 end
  if n >= 20 and not arcPending[m.f] then return end
  arcPending[m.f] = { id = m.f, name = clean(m.name, 20), ipk = m.ipk, xpk = m.xpk, fp = C.fingerprint(m.ipk), at = now() }
  notify("Archive", "Join request from " .. clean(m.name, 20) .. " (#" .. idStr(m.f) .. ")", "info")
  arcRecord({ t = now(), sender = m.f, kind = "enroll", text = "join request from " .. clean(m.name, 20) .. ", key " .. C.fingerprint(m.ipk) })
  event("archive_pending")
end

function handlers.roster_req(m)
  if not arc or m.to ~= me.id then return end
  if not state.roster.members[idStr(m.f)] then return end
  N.arcBroadcastRoster()
end

-- The Archive reads its copy of every sealed message.
local function arcOpen(m)
  if not arc or type(m.wa) ~= "string" then return end
  if not trusted(m.f) and m.f ~= me.id then
    arcRecord({ t = now(), sender = m.f, kind = "unknown", text = "sealed message from an unknown computer" })
    return
  end
  local data, from, key = sealedOpen(m, { xsk = arc.axsk, xpk = arc.axpk }, m.wa)
  if not data then
    arcRecord({ t = now(), sender = m.f, kind = "bad", text = "a sealed message did not open (" .. tostring(from) .. ")" })
    return
  end
  local who = from.name .. " (#" .. idStr(m.f) .. ")"
  if m.k == "audit" then
    arcRecord({ t = m.ts, sender = m.f, kind = "audit_" .. tostring(data.kind):sub(1, 20), text = who .. ": " .. tostring(data.text) })
  elseif data.kind == "text" then
    arcRecord({ t = m.ts, sender = m.f, kind = "private", text = who .. " to " .. nameOf(m.to) .. " (#" .. idStr(m.to) .. "): " .. tostring(data.text) })
  elseif data.kind == "file_offer" then
    arcRecord({ t = m.ts, sender = m.f, kind = "file", text = who .. " offers " .. tostring(data.name) .. " (" .. tostring(data.size) .. " bytes) to #" .. idStr(m.to) .. ", sha256 " .. tostring(data.sum) })
    arcFiles = arcFiles or {}
    arcFiles[data.xid] = { fk = data.fk, name = data.name, from = m.f, to = m.to, size = data.size, chunks = data.chunks, parts = {}, got = 0 }
  elseif data.kind == "approve_req" then
    arcApprovals[data.hash or "?"] = { hash = data.hash, name = clean(data.name, 40), size = data.size, body = data.body, from = m.f, who = who, at = m.ts }
    notify("Archive", who .. " asks to approve " .. clean(data.name, 30), "info")
    arcRecord({ t = m.ts, sender = m.f, kind = "approval", text = who .. " asks to run " .. tostring(data.name) .. " (sha256 " .. tostring(data.hash) .. ")" })
    event("archive_approvals")
  end
end

local function arcChunk(m)
  if not arc or not arcFiles then return end
  local f = arcFiles[m.xid]
  if not f or m.f ~= f.from then return end
  local data = C.open(f.fk, m.box, C.encode({ xid = m.xid, n = m.n, f = m.f, to = m.to }))
  if data and not f.parts[m.n] then
    f.parts[m.n] = data
    f.got = f.got + 1
    if f.got >= f.chunks then
      local all = table.concat(f.parts)
      arcFiles[m.xid] = nil
      arcRecord({ t = now(), sender = f.from, kind = "file_data", text = "file " .. tostring(f.name) .. " from #" .. idStr(f.from) .. " to #" .. idStr(f.to), data = all, name = f.name })
    end
  end
end

-- ------------------------------------------------------------- dispatcher

function N.handleModem(side, channel, reply, m)
  if channel ~= N.CHANNEL or type(m) ~= "table" or m.p ~= N.PROTO then return end
  if type(m.k) ~= "string" or type(m.f) ~= "number" then return end
  if m.f == me.id then return end
  if not allow(m.f) then
    stats.dropped = stats.dropped + 1
    return
  end
  -- Archive copies first: the Archive hears everything.
  if arc then
    if m.k == "msg" or m.k == "audit" then pcall(arcOpen, m) end
    if m.k == "fchunk" then pcall(arcChunk, m) end
    if m.k == "pub" then
      local t = trusted(m.f)
      if t and type(m.text) == "string" and signedCheck(m, t.ipk) then
        arcRecord({ t = m.ts, sender = m.f, kind = "public", text = t.name .. " (#" .. idStr(m.f) .. ") to everyone: " .. m.text })
      end
    end
  end
  local h = handlers[m.k]
  if m.k == "audit" then return end
  if h then
    local ok, why = pcall(h, m)
    if not ok then stats.bad = stats.bad + 1 K.lastError = "net: " .. tostring(why)
    elseif why and why ~= true then stats.bad = stats.bad + 1
    else stats.ok = stats.ok + 1 end
  end
end

-- ------------------------------------------------------------- lifecycle

function N.init(kernel, crypto, secure, callbacks)
  K, C, S = kernel, crypto, secure
  ui = callbacks or {}
  -- A new password re-seals the Archive keys, or the Archive would be lost.
  S.rekeyHooks[#S.rekeyHooks + 1] = function()
    if arc and state then saveArchive() end
  end
end

function N.start(name)
  local id = S.identity()
  me = { id = os.getComputerID(), name = clean(name, 20), ipk = id.ipk, xpk = id.xpk, isk = id.isk, xsk = id.xsk }
  state = S.readTable("net") or {}
  state.contacts = state.contacts or {}
  state.last = state.last or {}
  state.lastPub = state.lastPub or {}
  state.ctr = state.ctr or 0
  save()
  local a = S.readTable("archive")
  if a then
    local keys = S.openTable("archive", a.box)
    if keys then
      arc = { apk = C.unhex(a.apk), axpk = C.unhex(a.axpk), ask = keys.ask, axsk = keys.axsk, logKey = keys.logKey }
      state.roster = state.roster or a.roster or { v = 1, members = {}, bans = {}, allow = {}, released = {} }
    end
  end
  N.openModems()
  if arc then arcBeacon() end
  N.audit("boot", "Prismarine " .. tostring(K.VERSION) .. " started")
  N.timer = os.startTimer(30)
end

function N.handleTimer(id)
  if id ~= N.timer then return false end
  N.timer = os.startTimer(30)
  if arc then arcBeacon() N.arcBroadcastRoster() end
  if state and state.archive then N.audit("presence", "online") end
  for xid, o in pairs(offers) do
    if os.clock() - o.at > 120 then offers[xid] = nil end
  end
  return true
end

function N.setName(name)
  if not me then return end
  me.name = clean(name, 20)
end

function N.fingerprint()
  return me and C.fingerprint(me.ipk) or "?"
end

function N.isArchive() return arc ~= nil end
function N.myId() return me and me.id end

-- ------------------------------------------------------------- app APIs

-- Messenger
function N.api(proc)
  local A = {}
  function A.status()
    return {
      id = me.id, name = me.name, fp = C.fingerprint(me.ipk), modem = #modems() > 0,
      enrolled = state.archive ~= nil, archive = state.archive and { id = state.archive.id, name = state.archive.name, fp = state.archive.fp } or nil,
      isArchive = arc ~= nil,
    }
  end
  function A.contacts()
    local out = {}
    if (state.archive or arc) and state.roster then
      for sid, m in pairs(state.roster.members or {}) do
        local id = tonumber(sid)
        if id ~= me.id and not (state.roster.bans or {})[sid] then
          out[#out + 1] = { id = id, name = m.name, fp = C.fingerprint(C.unhex(m.ipk)), unread = unread[id] or 0 }
        end
      end
    else
      for sid, c in pairs(state.contacts) do
        local id = tonumber(sid)
        out[#out + 1] = { id = id, name = c.name, fp = C.fingerprint(C.unhex(c.ipk)), unread = unread[id] or 0 }
      end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
  end
  function A.peers()
    local out = {}
    for id, p in pairs(peers) do
      if not trusted(id) then out[#out + 1] = { id = id, name = p.name } end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
  end
  function A.scan()
    if not me then return false end
    return signedSend({ k = "hello", name = me.name, ipk = me.ipk, xpk = me.xpk, ask = true })
  end
  function A.history(key)
    local out = {}
    for i, l in ipairs(history[key] or {}) do
      out[i] = { who = l.who, text = l.text, mine = l.mine, at = l.at }
    end
    return out
  end
  function A.unread(key)
    if key == nil then
      local n = 0
      for _, v in pairs(unread) do n = n + v end
      return n
    end
    return unread[key] or 0
  end
  function A.markRead(key) unread[key] = nil end
  function A.send(to, text)
    if type(text) ~= "string" or text == "" then return false, "Empty" end
    text = text:sub(1, N.MAX_TEXT)
    if to == "all" then
      local t = { k = "pub", text = text, ctr = nextCtr() }
      if not signedSend(t) then return false, "No modem" end
      addHistory("all", { who = "You", text = text, mine = true, at = now() })
      return true
    end
    local ok, why = sealedSend("msg", to, { kind = "text", text = text })
    if ok then addHistory(to, { who = "You", text = text, mine = true, at = now() }) end
    if ok then return true end
    return false, why
  end
  -- Pairing (not in Archive mode)
  function A.pair(id)
    if state.archive then return false, "This computer is in an Archive network. The Archive adds contacts." end
    local p = peers[id]
    pairOut[id] = { id = id, name = p and p.name or ("#" .. idStr(id)), at = os.clock() }
    return signedSend({ k = "pair", to = id, name = me.name, ipk = me.ipk, xpk = me.xpk, nonce = C.hex(C.bytes(8)) })
  end
  function A.pairRequests()
    local out = {}
    for id, r in pairs(pairIn) do out[#out + 1] = { id = id, name = r.name, code = r.code, dir = "in" } end
    for id, r in pairs(pairOut) do
      out[#out + 1] = { id = id, name = r.name, code = r.code, dir = "out", answered = r.answered }
    end
    return out
  end
  -- Accept an incoming request after the codes matched. Replies with our keys.
  function A.acceptPair(id, yes)
    local r = pairIn[id]
    if not r then return false end
    pairIn[id] = nil
    if not yes then return true end
    state.contacts[idStr(id)] = { name = r.name, ipk = C.hex(r.ipk), xpk = C.hex(r.xpk), at = now() }
    save()
    signedSend({ k = "pair_ok", to = id, name = me.name, ipk = me.ipk, xpk = me.xpk })
    event("net_peers")
    return true
  end
  -- Confirm an outgoing request once the other side answered and codes match.
  function A.confirmPair(id, yes)
    local r = pairOut[id]
    if not r or not r.answered then return false end
    pairOut[id] = nil
    if not yes then return true end
    state.contacts[idStr(id)] = { name = r.name, ipk = C.hex(r.ipk), xpk = C.hex(r.xpk), at = now() }
    save()
    event("net_peers")
    return true
  end
  function A.forget(id)
    if state.archive then return false end
    state.contacts[idStr(id)] = nil
    save()
    return true
  end
  -- Files: the app reads the file with its own sandboxed fs and hands us the bytes.
  function A.sendFile(to, name, data)
    if type(data) ~= "string" or #data == 0 then return false, "Empty file" end
    if #data > N.MAX_FILE then return false, "Too big" end
    local xid = idStr(me.id) .. "-" .. C.hex(C.bytes(6))
    local fk = C.bytes(32)
    local x = { xid = xid, to = to, fk = fk, data = data, chunks = math.ceil(#data / N.CHUNK), acked = 0 }
    sending[xid] = x
    x.offer = {
      kind = "file_offer", xid = xid, name = clean(fs.getName(name), 64), size = #data,
      chunks = x.chunks, sum = C.sha256hex(data), fk = fk,
    }
    local ok, why = sealedSend("msg", to, x.offer)
    if not ok then sending[xid] = nil return false, why end
    x.offerAt, x.offerTries = os.clock(), 1
    N.audit("file", "offering " .. clean(name, 40) .. " to #" .. idStr(to))
    return xid
  end
  -- Drive a send: call again until it returns "done" or "failed".
  function A.sendStep(xid)
    local x = sending[xid]
    if not x then return "failed", "Unknown transfer" end
    if x.failed then sending[xid] = nil return "failed", x.failed end
    if x.result then
      sending[xid] = nil
      if x.result == "ok" then return "done" end
      return "failed", x.result
    end
    if not x.accepted then
      -- The offer may have been lost on the way. Send it again, a few times.
      if os.clock() - (x.offerAt or 0) > 3 then
        x.offerTries = (x.offerTries or 1) + 1
        if x.offerTries > 6 then sending[xid] = nil return "failed", "No answer" end
        x.offerAt = os.clock()
        sealedSend("msg", x.to, x.offer)
      end
      return "waiting", 0
    end
    local n = (x.acked or 0) + 1
    if n <= x.chunks then
      x.tries = (x.lastN == n) and (x.tries or 0) + 1 or 0
      x.lastN = n
      if x.tries > 6 then sending[xid] = nil return "failed", "Lost contact" end
      local piece = x.data:sub((n - 1) * N.CHUNK + 1, n * N.CHUNK)
      transmit({ k = "fchunk", f = me.id, to = x.to, xid = xid, n = n,
        box = C.seal(x.fk, piece, C.encode({ xid = xid, n = n, f = me.id, to = x.to })) })
    end
    if n > x.chunks and os.clock() - (x.lastFinal or 0) > 1.5 then
      x.lastFinal = os.clock()
      x.finalTries = (x.finalTries or 0) + 1
      if x.finalTries > 8 then sending[xid] = nil return "failed", "No confirmation" end
      local piece = x.data:sub((x.chunks - 1) * N.CHUNK + 1, x.chunks * N.CHUNK)
      transmit({ k = "fchunk", f = me.id, to = x.to, xid = xid, n = x.chunks,
        box = C.seal(x.fk, piece, C.encode({ xid = xid, n = x.chunks, f = me.id, to = x.to })) })
    end
    return "sending", (x.acked or 0) / x.chunks
  end
  function A.cancelSend(xid)
    local x = sending[xid]
    if not x then return end
    sending[xid] = nil
    local t = { k = "fctl", to = x.to, xid = xid, op = "cancel", f = me.id }
    t.mac = C.mac(x.fk, C.encode({ op = "cancel", xid = xid, f = me.id }))
    transmit(t)
  end
  function A.offers()
    local out = {}
    for xid, o in pairs(offers) do
      out[#out + 1] = { xid = xid, from = o.from, who = o.who, name = o.name, size = o.size }
    end
    table.sort(out, function(a, b) return a.xid < b.xid end)
    return out
  end
  -- Accept: the file arrives in the background; "net_file_done" brings the
  -- bytes back through fetchFile(xid).
  local done = {}
  function A.acceptOffer(xid, yes)
    local o = offers[xid]
    if not o then return false end
    offers[xid] = nil
    local function ctl(op, why)
      local t = { k = "fctl", to = o.from, xid = xid, op = op, why = why, f = me.id }
      t.mac = C.mac(o.fk, C.encode({ op = op, xid = xid, why = why, f = me.id }))
      transmit(t)
    end
    if not yes then ctl("decline", "They declined.") return true end
    receiving[xid] = { xid = xid, from = o.from, fk = o.fk, size = o.size, chunks = o.chunks, sum = o.sum,
      name = o.name, next = 1, parts = {}, done = function(all) done[xid] = { name = o.name, data = all } end }
    ctl("accept")
    return true
  end
  function A.fetchFile(xid)
    local d = done[xid]
    done[xid] = nil
    if d then return d.name, d.data end
    return nil
  end
  function A.stats() return { dropped = stats.dropped, bad = stats.bad, ok = stats.ok, sent = stats.sent } end
  -- Ask the Archive to approve a program (Archive mode).
  function A.requestApproval(name, data)
    if not state.archive then return false, "No Archive" end
    if #data > 60000 then return false, "Too big to send for review" end
    return sealedSend("msg", state.archive.id, {
      kind = "approve_req", name = clean(name, 40), size = #data, hash = C.sha256hex(data), body = data,
    }, true)
  end
  return A
end

-- Settings: join or leave an Archive, become one.
function N.adminApi(proc)
  local A = {}
  function A.findArchives()
    archives = {}
    transmit({ k = "afind", f = me.id })
    return true
  end
  function A.archives()
    local out = {}
    for id, a in pairs(archives) do out[#out + 1] = { id = id, name = a.name, fp = a.fp } end
    return out
  end
  function A.join(id)
    local a = archives[id]
    if not a then return false, "Archive not found" end
    if arc then return false, "This computer is an Archive" end
    enrollWait = { id = id, name = a.name, apk = a.apk, axpk = a.axpk, fp = a.fp }
    signedSend({ k = "enroll", to = id, name = me.name, ipk = me.ipk, xpk = me.xpk })
    return true, C.fingerprint(me.ipk)
  end
  -- After the Archive approved: the user compares the Archive's code and confirms.
  function A.enrollState()
    if not enrollWait then return nil end
    return { id = enrollWait.id, name = enrollWait.name, fp = enrollWait.fp, answered = enrollWait.answered, refused = enrollWait.refused,
      myFp = C.fingerprint(me.ipk) }
  end
  function A.confirmJoin(yes)
    local a = enrollWait
    if not a or not a.answered then enrollWait = nil return false end
    enrollWait = nil
    if not yes then return true end
    state.archive = { id = a.id, name = a.name, apk = C.hex(a.apk), axpk = C.hex(a.axpk), fp = a.fp, cert = a.cert, csig = a.csig }
    state.roster = nil
    state.contacts = {}
    save()
    transmit({ k = "roster_req", f = me.id, to = a.id })
    N.audit("enrolled", "joined Archive " .. a.name)
    return true
  end
  function A.cancelJoin() enrollWait = nil end
  -- Become the Archive of a network. The password check happens in the UI.
  function A.becomeArchive(name)
    if arc then return false, "Already an Archive" end
    if state.archive then return false, "Leave your Archive first" end
    local k = C.newIdentity()
    arc = { apk = k.ipk, ask = k.isk, axpk = k.xpk, axsk = k.xsk, logKey = C.bytes(32) }
    state.arcName = clean(name or ("Archive #" .. idStr(me.id)), 24)
    state.roster = { v = 1, members = {}, bans = {}, allow = {}, released = {} }
    state.roster.members[idStr(me.id)] = { name = me.name, ipk = C.hex(me.ipk), xpk = C.hex(me.xpk), serial = 1 }
    save()
    saveArchive()
    arcBeacon()
    return true, C.fingerprint(arc.apk)
  end
  function A.status()
    return { enrolled = state.archive ~= nil, archive = state.archive and { id = state.archive.id, name = state.archive.name, fp = state.archive.fp },
      isArchive = arc ~= nil, archiveFp = arc and C.fingerprint(arc.apk) or nil, arcName = state.arcName,
      myFp = C.fingerprint(me.ipk), contacts = (function() local n = 0 for _ in pairs(state.contacts) do n = n + 1 end return n end)() }
  end
  return A
end

-- The Archive app.
function N.archiveApi(proc)
  if not arc then return nil end
  local A = {}
  local function bump()
    state.roster.v = state.roster.v + 1
    save()
    saveArchive()
    N.arcBroadcastRoster()
  end
  function A.fingerprint() return C.fingerprint(arc.apk) end
  function A.name() return state.arcName end
  function A.pending()
    local out = {}
    for id, p in pairs(arcPending) do out[#out + 1] = { id = id, name = p.name, fp = p.fp, at = p.at } end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
  end
  function A.approve(id, yes)
    local p = arcPending[id]
    if not p then return false end
    arcPending[id] = nil
    if not yes then
      local t = { k = "denied", f = me.id, to = id, ts = now() }
      t.p = N.PROTO
  t.sig = arcSign("pm1s|" .. C.encode(t))
      transmit(t)
      arcRecord({ t = now(), sender = id, kind = "enroll", text = "refused " .. p.name .. " (#" .. idStr(id) .. ")" })
      return true
    end
    local serial = (state.roster.serial or 1) + 1
    state.roster.serial = serial
    local cert = C.encode({ id = id, name = p.name, ipk = C.hex(p.ipk), xpk = C.hex(p.xpk), serial = serial, at = now() })
    local csig = arcSign("pm1cert|" .. cert)
    state.roster.members[idStr(id)] = { name = p.name, ipk = C.hex(p.ipk), xpk = C.hex(p.xpk), serial = serial }
    state.roster.bans[idStr(id)] = nil
    state.roster.released[idStr(id)] = nil
    transmit({ k = "enrolled", f = me.id, to = id, cert = cert, csig = csig })
    arcRecord({ t = now(), sender = id, kind = "enroll", text = "approved " .. p.name .. " (#" .. idStr(id) .. "), key " .. p.fp })
    bump()
    return true
  end
  function A.members()
    local out = {}
    for sid, m in pairs(state.roster.members) do
      out[#out + 1] = { id = tonumber(sid), name = m.name, fp = C.fingerprint(C.unhex(m.ipk)), banned = state.roster.bans[sid] == true }
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
  end
  function A.ban(id, yes)
    if id == me.id then return false end
    state.roster.bans[idStr(id)] = yes and true or nil
    arcRecord({ t = now(), sender = id, kind = "ban", text = (yes and "banned #" or "unbanned #") .. idStr(id) })
    bump()
    return true
  end
  -- Let a computer leave Archive mode (it stops being a member).
  function A.release(id)
    if id == me.id then return false end
    state.roster.members[idStr(id)] = nil
    state.roster.released[idStr(id)] = true
    arcRecord({ t = now(), sender = id, kind = "release", text = "released #" .. idStr(id) })
    bump()
    return true
  end
  function A.approvals()
    local out = {}
    for h, a in pairs(arcApprovals) do out[#out + 1] = { hash = h, name = a.name, size = a.size, who = a.who, at = a.at } end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
  end
  function A.approvalBody(hash) local a = arcApprovals[hash] return a and a.body end
  function A.allow(hash, yes)
    local a = arcApprovals[hash]
    arcApprovals[hash] = nil
    if yes then
      state.roster.allow[hash] = a and a.name or "program"
      arcRecord({ t = now(), sender = a and a.from or 0, kind = "approval", text = "approved " .. tostring(a and a.name) .. " sha256 " .. hash })
    else
      arcRecord({ t = now(), sender = a and a.from or 0, kind = "approval", text = "refused " .. tostring(a and a.name) .. " sha256 " .. hash })
    end
    bump()
    return true
  end
  function A.allowed()
    local out = {}
    for h, name in pairs(state.roster.allow) do out[#out + 1] = { hash = h, name = name } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end
  function A.revoke(hash) state.roster.allow[hash] = nil bump() return true end
  -- Log storage is sealed with a key only this Archive holds (after login).
  function A.seal(text) return C.seal(arc.logKey, text, "archive log") end
  function A.open(box) return C.open(arc.logKey, box, "archive log") end
  function A.setName(name) state.arcName = clean(name, 24) save() arcBeacon() return true end
  function A.stats() return { dropped = stats.dropped, bad = stats.bad, ok = stats.ok, sent = stats.sent, rosterV = state.roster.v } end
  return A
end

-- Programs the Archive approved (hash -> name). Empty when not enrolled.
function N.allowList()
  if state and state.archive and state.roster and state.roster.allow then return state.roster.allow end
  if arc and state.roster then return state.roster.allow end
  return {}
end

handlers.afind = function(m) if arc then arcBeacon() end end

return N
