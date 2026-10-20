-- Pure helpers of the buff bar (no client calls; tested by buffmath_test.lua): applying the server's messages to a
-- table of buffs, the time left (counted down here from the milliseconds the server sent), the compact time text, the
-- order of the icons, the layout under the character plate, the tooltip, the icon names and the settings.
--
-- Server messages (extended opcode 234, JSON {action, data}):
--   full  {list = [entry]}  the whole bar
--   diff  {add = [entry], upd = [{k, l, s}], del = [key]}
--   entry {k key, n name, d description, i icon, t 0 buff / 1 debuff, l ms left (none: no timer), s stacks}
-- An entry in the table: {key, name, desc, icon, debuff, endAt (client clock seconds, nil: no timer), stacks, seq}.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

BuffMath = {}

BuffMath.ICON_SIZE, BuffMath.GAP = 26, 2
BuffMath.GRACE = 1.5 -- seconds past its end a timed buff stays before the client drops it by itself (the server's `del` is late)

-- where the bar sits on the character plate (game_chaoshud, image 300 x 96): the drawn plate starts 7 px in from the
-- left of its widget and ends 3 px before the right; the bar starts 2 px under the widget (below the level badge)
BuffMath.PLATE = { left = 7, right = 3, below = 2 }
-- without the plate module the bar takes the plate's own spot: the top-left of the game view (chaoshud.otui margins)
BuffMath.FALLBACK = { x = 34, y = 40, width = 300, height = 96 }

-- the settings that are left: the bar is fixed under the plate (no position, size, icons per row or lock any more; old
-- saved values of those are dropped on the next save)
BuffMath.DEFAULTS = {shown = true, timers = true}

local function num(v)
  v = tonumber(v)
  if v ~= v then return nil end
  return v
end

-- the saved settings node -> valid settings (unknown or wrong values fall back to the defaults; anything else is dropped)
function BuffMath.sanitize(node)
  node = type(node) == 'table' and node or {}
  local s = {}
  for k, v in pairs(BuffMath.DEFAULTS) do
    if type(node[k]) == 'boolean' then s[k] = node[k] else s[k] = v end
  end
  return s
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
    state.synced = true
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
  state.buffs, state.seq, state.synced = {}, 0, false
end

-- the buffs on the character now as { [lowercase name] = true } (debuffs and buffs whose time is over left out), or nil
-- while the server has not sent its list yet (the bar is hidden, offline): the helper's Support spells read this
-- (modules.game_buffbar.activeBuffs) to know whether a buff is up
function BuffMath.activeNames(state, now)
  if not state.synced then return nil end
  local set = {}
  for _, e in pairs(state.buffs or {}) do
    if not e.debuff and not (e.endAt and now > e.endAt) then set[tostring(e.name):lower()] = true end
  end
  return set
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

-- the entries to draw: the buffs, then the debuffs, each in the order the server listed them (stable: nothing jumps
-- about); also how many of them are buffs
function BuffMath.ordered(state)
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
  local nBuffs = #buffs
  for _, e in ipairs(debuffs) do buffs[#buffs + 1] = e end
  return buffs, nBuffs
end

-- a key of the drawn order (a new layout is needed when it changes)
function BuffMath.orderKey(list)
  local keys = {}
  for i, e in ipairs(list) do keys[i] = e.key end
  return table.concat(keys, ',')
end

function BuffMath.count(state)
  local n = 0
  for _ in pairs(state.buffs or {}) do n = n + 1 end
  return n
end

-- icons that fit in a row `rowWidth` wide (at least one)
function BuffMath.perRow(rowWidth, size, gap)
  return math.max(1, math.floor(((tonumber(rowWidth) or 0) + gap) / (size + gap)))
end

-- left to right in rows as wide as the plate, a new row below when one is full: the cells {x, y} of `count` icons
-- (relative to the bar), the number of rows and the bar's height (0 without icons: an empty bar takes no space)
function BuffMath.flow(count, rowWidth, size, gap)
  size, gap = size or BuffMath.ICON_SIZE, gap or BuffMath.GAP
  local per = BuffMath.perRow(rowWidth, size, gap)
  local cells = {}
  for i = 0, count - 1 do
    cells[#cells + 1] = { x = (i % per) * (size + gap), y = math.floor(i / per) * (size + gap) }
  end
  local rows = math.ceil(count / per)
  return cells, rows, rows > 0 and rows * (size + gap) - gap or 0
end

-- where the bar goes: `plate` = {x, y, width, height, visible} of the character plate (nil: no plate module).
-- Returns {x, y, width, shown}: under the plate and left-aligned with its drawn edge, as wide as the drawn plate; hidden
-- with the plate; at the plate's own spot (FALLBACK, relative to the game view at `view` {x, y}) without a plate module.
function BuffMath.attach(plate, view)
  local P = BuffMath.PLATE
  if type(plate) ~= 'table' then
    local F = BuffMath.FALLBACK
    view = type(view) == 'table' and view or { x = 0, y = 0 }
    return { x = (view.x or 0) + F.x + P.left, y = (view.y or 0) + F.y + F.height + P.below,
      width = F.width - P.left - P.right, shown = true }
  end
  return { x = plate.x + P.left, y = plate.y + plate.height + P.below,
    width = math.max(BuffMath.ICON_SIZE, plate.width - P.left - P.right), shown = plate.visible ~= false }
end

function BuffMath.tooltip(entry, now)
  local lines = { entry.name .. (entry.debuff and '  (debuff)' or '') }
  if entry.desc ~= '' then lines[#lines + 1] = entry.desc end
  if entry.stacks and entry.stacks > 0 then lines[#lines + 1] = 'Stacks: ' .. math.floor(entry.stacks) end
  local left = BuffMath.remaining(entry, now)
  lines[#lines + 1] = left and (tr('Time left: %s', BuffMath.formatLong(left))) or tr('No time limit')
  return table.concat(lines, '\n')
end

-- "spell:utani hur" -> 'spell', 'utani hur'; "cond:05" -> 'cond', '05'; "buff:regen" -> 'buff', 'regen'
function BuffMath.parseIcon(spec)
  local kind, arg = tostring(spec or ''):match('^(%a+):(.+)$')
  if kind == 'spell' or kind == 'cond' or kind == 'buff' then return kind, arg end
  return nil
end

-- our own icons (client/tools/gen_buff_icons.py): 26 x 26 pixel art, the bar's cell size, drawn 1:1
BuffMath.OWN_CLIP = '0 0 26 26'

function BuffMath.ownPath(name)
  if not tostring(name):match('^[%w_]+$') then return nil end
  return '/images/game/buffs/' .. name
end

-- painted icons (client/tools/gen_painted_icons.py), client setting "Painted icons" (g_settings key below, off by
-- default): the same name in /images/game/buffs_painted, same 26 px size. `exists(file)` (g_resources.fileExists) says
-- whether that name has a painted icon; a name without one keeps its normal icon.
BuffMath.PAINTED_SETTING = 'chaosPaintedIcons'

function BuffMath.iconPath(name, painted, exists)
  local own = BuffMath.ownPath(name)
  if not own then return nil end
  if painted then
    local p = '/images/game/buffs_painted/' .. name
    if not exists or exists(p .. '.png') then return p end
  end
  return own
end

-- the own icon a spec draws: "buff:<name>" is that name; anything else (an older server's "cond:<NN>" or
-- "spell:<words>", an unknown spec) draws the key's own icon; 'spellbuff' when neither is a valid name. Neither the
-- stock condition art nor the spell sheet is used: every icon on the bar is one of ours, in the same frame.
function BuffMath.ownName(spec, key)
  local kind, arg = BuffMath.parseIcon(spec)
  if kind == 'buff' and BuffMath.ownPath(arg) then return arg end
  if key and BuffMath.ownPath(key) then return key end
  return 'spellbuff'
end
