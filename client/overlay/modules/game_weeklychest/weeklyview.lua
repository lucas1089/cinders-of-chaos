-- Weekly Chest window: pure parts (no client API), so weeklyview_test.lua runs under plain Lua. The server's "state"
-- payload (server weeklychest.lua: weeklychest_core.lua K.view) becomes the lines the window shows. Every text is
-- {pattern, args...}: the window passes it to tr(pattern, args...), so each pattern is a key of the client's pt-BR table
-- (client_chaos_locale, "Run-time keys").
--   state = {endsIn, acts = {{k, done 0/1, open 0/1, lv}}, got, need, bonusNeed (0: none), open, chests,
--            chest = {given 0/1, gold, it = {{cid, n, name}}}, bonus = {given 0/1, lo, hi}}

WeeklyView = {}
local V = WeeklyView

V.MAX_TEXT = 48
V.DONE = '#7ccf5c'
V.OPEN = '#c8b89a'
V.LOCKED = '#6e655c'

-- activity key -> {name, what to do}; the server's keys (weeklychest_config.lua activities)
V.ACTS = {
  dungeon = { 'Dungeon', 'Clear a dungeon.' },
  rift = { 'Rift', 'Seal a rift.' },
  waystone = { 'Waystone run', 'Open a waystone map.' },
  tower = { 'Infinity Tower', 'Clear a floor of the Infinity Tower.' },
  boss = { 'World boss or invasion', 'Fight a world boss or an invasion.' },
  bounty = { 'Bounty contract', 'Finish a bounty contract.' },
}

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v == math.huge or v == -math.huge then return 0 end
  return math.max(0, math.floor(v))
end

local function tbl(v)
  return type(v) == 'table' and v or {}
end

local function str(v)
  if type(v) ~= 'string' then return '' end
  if #v > V.MAX_TEXT then return v:sub(1, V.MAX_TEXT) end
  return v
end

function V.plain(t)
  if type(t) ~= 'table' then return tostring(t or '') end
  if #t <= 1 then return tostring(t[1] or '') end
  local ok, s = pcall(string.format, t[1], (table.unpack or unpack)(t, 2))
  return ok and s or tostring(t[1])
end

-- 1234 -> '1.2k', 1234567 -> '1.2M' (a value, not a key)
function V.short(n)
  n = int(n)
  local units = { { 1e12, 'T' }, { 1e9, 'B' }, { 1e6, 'M' }, { 1e3, 'k' } }
  for _, u in ipairs(units) do
    if n >= u[1] then
      local v = n / u[1]
      local s = v >= 100 and string.format('%d', math.floor(v)) or string.format('%.1f', math.floor(v * 10) / 10)
      return (s:gsub('%.0$', '')) .. u[2]
    end
  end
  return tostring(n)
end

-- seconds left -> {'%d days', n} / {'%d day', 1} / {'%d h', n} / {'under an hour'}
function V.left(seconds)
  seconds = int(seconds)
  local d, h = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600)
  if d >= 2 then return { '%d days', d } end
  if d == 1 then return { '%d day', 1 } end
  if h >= 1 then return { '%d h', h } end
  return { 'under an hour' }
end

-- the reward line: '12k gold, 2x Orb of Upheaval, Orb of Fate'
function V.reward(gold, items)
  local parts = {}
  for _, it in ipairs(tbl(items)) do
    if type(it) == 'table' then
      local n, name = int(it.n), str(it.name)
      if name ~= '' then parts[#parts + 1] = (n > 1 and (n .. 'x ') or '') .. name end
    end
  end
  if #parts == 0 then return { '%s gold', V.short(gold) } end
  return { '%s gold, %s', V.short(gold), table.concat(parts, ', ') }
end

-- the rows of the six activities in the server's order; an unknown key is shown by its own text
function V.rows(state)
  local out = {}
  for _, a in ipairs(tbl(tbl(state).acts)) do
    if type(a) == 'table' and type(a.k) == 'string' then
      local info = V.ACTS[a.k] or { str(a.k), '' }
      local row = { key = a.k, name = { info[1] }, what = { info[2] } }
      if int(a.done) == 1 then
        row.status, row.color = { 'Done' }, V.DONE
      elseif int(a.open) == 1 then
        row.status, row.color = { 'Not yet' }, V.OPEN
      else
        row.status, row.color = { 'Unlocks at level %d', int(a.lv) }, V.LOCKED
      end
      out[#out + 1] = row
    end
  end
  return out
end

-- the whole window: {head, ends, rows, chest, chestColor, reward, bonus, bonusColor, chests}
function V.build(state)
  state = tbl(state)
  local got, need, bonusNeed = int(state.got), int(state.need), int(state.bonusNeed)
  local chest, bonus = tbl(state.chest), tbl(state.bonus)
  local v = {
    head = { '%d of %d activities done this week', got, math.max(need, 1) },
    ends = { 'The week ends in %s', V.plain(V.left(state.endsIn)) },
    rows = V.rows(state),
    chests = { 'Chests opened so far: %d', int(state.chests) },
  }
  if int(chest.given) == 1 then
    v.chest, v.chestColor = { 'The chest is open: this week\'s reward is yours.' }, V.DONE
  else
    v.chest, v.chestColor = { 'The chest opens at %d of %d activities.', need, int(state.open) }, V.OPEN
  end
  v.reward = V.reward(chest.gold, chest.it)
  if bonusNeed <= 0 then
    v.bonus, v.bonusColor = { 'No bonus roll at your level: more systems unlock as you level.' }, V.LOCKED
  elseif int(bonus.given) == 1 then
    v.bonus, v.bonusColor = { 'Bonus roll taken this week.' }, V.DONE
  else
    v.bonus, v.bonusColor = { 'All %d activities add a bonus roll: %s to %s gold or orbs.', bonusNeed,
      V.short(bonus.lo), V.short(bonus.hi) }, V.OPEN
  end
  return v
end
