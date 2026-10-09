-- Pure helpers of the buff bar (no client calls; tested by buffmath_test.lua): applying the server's messages to a
-- table of buffs, the time left (counted down here from the milliseconds the server sent), the compact time text, the
-- rows, the tooltip, the icon names and the settings.
--
-- Server messages (extended opcode 234, JSON {action, data}):
--   full  {list = [entry]}  the whole bar
--   diff  {add = [entry], upd = [{k, l, s}], del = [key]}
--   entry {k key, n name, d description, i icon, t 0 buff / 1 debuff, l ms left (none: no timer), s stacks}
-- An entry in the table: {key, name, desc, icon, debuff, endAt (client clock seconds, nil: no timer), stacks, seq}.

BuffMath = {}

BuffMath.BASE_SIZE = 26
BuffMath.SCALE_MIN, BuffMath.SCALE_MAX, BuffMath.SCALE_STEP = 70, 180, 10
BuffMath.PER_ROW_MIN, BuffMath.PER_ROW_MAX = 4, 16
BuffMath.GRACE = 1.5 -- seconds past its end a timed buff stays before the client drops it by itself (the server's `del` is late)

BuffMath.DEFAULTS = {scale = 100, locked = false, shown = true, timers = true, hideEmpty = true, perRow = 10}

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

local function num(v)
  v = tonumber(v)
  if v ~= v then return nil end
  return v
end

-- the saved settings node -> valid settings (unknown or wrong values fall back to the defaults)
function BuffMath.sanitize(node)
  node = type(node) == 'table' and node or {}
  local d = BuffMath.DEFAULTS
  local s = {}
  local scale = num(node.scale)
  s.scale = scale and clamp(math.floor(scale / BuffMath.SCALE_STEP + 0.5) * BuffMath.SCALE_STEP, BuffMath.SCALE_MIN, BuffMath.SCALE_MAX) or d.scale
  for _, k in ipairs({ 'locked', 'shown', 'timers', 'hideEmpty' }) do
    if type(node[k]) == 'boolean' then s[k] = node[k] else s[k] = d[k] end
  end
  local per = num(node.perRow)
  s.perRow = per and clamp(math.floor(per), BuffMath.PER_ROW_MIN, BuffMath.PER_ROW_MAX) or d.perRow
  local x, y = num(node.x), num(node.y)
  if x and y then s.x, s.y = math.floor(x), math.floor(y) end
  return s
end

function BuffMath.iconSize(scale)
  return math.floor(BuffMath.BASE_SIZE * clamp(scale or 100, BuffMath.SCALE_MIN, BuffMath.SCALE_MAX) / 100 + 0.5)
end

function BuffMath.stepScale(scale, dir)
  return clamp((scale or 100) + dir * BuffMath.SCALE_STEP, BuffMath.SCALE_MIN, BuffMath.SCALE_MAX)
end

-- a position that keeps a widget of w x h inside a parent of pw x ph (at least `keep` pixels of it stay visible)
function BuffMath.clampPosition(x, y, w, h, pw, ph, keep)
  keep = keep or 24
  return clamp(x, keep - w, math.max(keep - w, pw - keep)), clamp(y, 0, math.max(0, ph - math.min(h, keep)))
end

-- ------------------------------------------------------------------ the table of buffs
local function entryFrom(e, now, seq)
  if type(e) ~= 'table' or type(e.k) ~= 'string' or e.k == '' then return nil end
  local left = num(e.l)
  return {
    key = e.k, name = tostring(e.n or e.k), desc = tostring(e.d or ''), icon = tostring(e.i or ''),
    debuff = e.t == 1, endAt = left and (now + math.max(0, left) / 1000) or nil,
    stacks = num(e.s), seq = seq,
  }
end

-- applies one message; returns true when something changed. `state` = {buffs = {key -> entry}, seq = n}
function BuffMath.apply(state, action, data, now)
  state.buffs = state.buffs or {}
  state.seq = state.seq or 0
  data = type(data) == 'table' and data or {}
  local changed = false
  local function put(e)
    local old = state.buffs[type(e) == 'table' and e.k or '']
    state.seq = state.seq + 1
    local entry = entryFrom(e, now, old and old.seq or state.seq)
    if entry then state.buffs[entry.key] = entry changed = true end
  end
  if action == 'full' then
    state.buffs = {}
    state.seq = 0
    for _, e in ipairs(type(data.list) == 'table' and data.list or {}) do put(e) end
    changed = true
  elseif action == 'diff' then
    for _, e in ipairs(type(data.add) == 'table' and data.add or {}) do put(e) end
    for _, u in ipairs(type(data.upd) == 'table' and data.upd or {}) do
      local b = type(u) == 'table' and state.buffs[u.k]
      if b then
        local left = num(u.l)
        b.endAt = left and (now + math.max(0, left) / 1000) or nil
        b.stacks = num(u.s)
        changed = true
      end
    end
    for _, key in ipairs(type(data.del) == 'table' and data.del or {}) do
      if state.buffs[key] then state.buffs[key] = nil changed = true end
    end
  end
  return changed
end

function BuffMath.clear(state)
  state.buffs, state.seq = {}, 0
end

-- seconds left (never negative), or nil for a buff without a timer
function BuffMath.remaining(entry, now)
  if not entry.endAt then return nil end
  return math.max(0, entry.endAt - now)
end

function BuffMath.expired(entry, now)
  return entry.endAt ~= nil and now > entry.endAt + BuffMath.GRACE
end

-- drops the buffs whose time is long over (a lost `del`); returns how many went
function BuffMath.prune(state, now)
  local n = 0
  for key, e in pairs(state.buffs or {}) do
    if BuffMath.expired(e, now) then state.buffs[key] = nil n = n + 1 end
  end
  return n
end

-- compact time: 45s, 1:05, 12m, 2h
function BuffMath.format(sec)
  if sec == nil then return '' end
  sec = math.max(0, math.ceil(sec - 1e-9)) + 0
  if sec < 60 then return sec .. 's' end
  if sec < 600 then return string.format('%d:%02d', math.floor(sec / 60), sec % 60) end
  if sec < 3600 then return math.floor(sec / 60) .. 'm' end
  local h = math.floor(sec / 3600)
  if h >= 24 then return math.floor(h / 24) .. 'd' end
  return h .. 'h'
end

-- longer text for the tooltip: 1h 05m 09s, 5m 03s, 45s
function BuffMath.formatLong(sec)
  sec = math.max(0, math.ceil((sec or 0) - 1e-9)) + 0
  local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
  if h > 0 then return string.format('%dh %02dm %02ds', h, m, s) end
  if m > 0 then return string.format('%dm %02ds', m, s) end
  return s .. 's'
end

-- the entries to draw: {buffs, debuffs}, each in the order the server listed them (stable: nothing jumps about)
function BuffMath.rows(state)
  local buffs, debuffs = {}, {}
  for _, e in pairs(state.buffs or {}) do
    if e.debuff then debuffs[#debuffs + 1] = e else buffs[#buffs + 1] = e end
  end
  local function bySeq(a, b)
    if a.seq ~= b.seq then return a.seq < b.seq end
    return a.key < b.key
  end
  table.sort(buffs, bySeq)
  table.sort(debuffs, bySeq)
  return buffs, debuffs
end

function BuffMath.count(state)
  local n = 0
  for _ in pairs(state.buffs or {}) do n = n + 1 end
  return n
end

-- positions of icons in rows of `perRow`: {{x, y} ...} for `count` icons, cell = size + gap; also the width and height used
function BuffMath.grid(count, perRow, size, gap, x0, y0)
  local cells = {}
  for i = 0, count - 1 do
    cells[#cells + 1] = { x = x0 + (i % perRow) * (size + gap), y = y0 + math.floor(i / perRow) * (size + gap) }
  end
  local rows = math.ceil(count / perRow)
  local cols = math.min(count, perRow)
  return cells, cols * (size + gap) - (cols > 0 and gap or 0), rows * (size + gap) - (rows > 0 and gap or 0)
end

function BuffMath.tooltip(entry, now)
  local lines = { entry.name .. (entry.debuff and '  (debuff)' or '') }
  if entry.desc ~= '' then lines[#lines + 1] = entry.desc end
  if entry.stacks and entry.stacks > 0 then lines[#lines + 1] = 'Stacks: ' .. math.floor(entry.stacks) end
  local left = BuffMath.remaining(entry, now)
  lines[#lines + 1] = left and ('Time left: ' .. BuffMath.formatLong(left)) or 'No time limit'
  return table.concat(lines, '\n')
end

-- "spell:utani hur" -> 'spell', 'utani hur'; "cond:05" -> 'cond', '05'; "buff:regen" -> 'buff', 'regen'
function BuffMath.parseIcon(spec)
  local kind, arg = tostring(spec or ''):match('^(%a+):(.+)$')
  if kind == 'spell' or kind == 'cond' or kind == 'buff' then return kind, arg end
  return nil
end

function BuffMath.condPath(arg)
  if not tostring(arg):match('^%d%d$') then return nil end
  return '/images/arcs/conditions/player-state-flags-' .. arg
end

function BuffMath.ownPath(name)
  if not tostring(name):match('^[%w_]+$') then return nil end
  return '/images/game/buffs/' .. name
end
