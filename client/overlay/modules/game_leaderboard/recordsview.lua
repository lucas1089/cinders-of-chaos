-- Pure helpers of the Records view of the Leaderboards window (no client API), tested by recordsview_test.lua.
-- Server: server/data/scripts/chaos/records.lua (actions rmeta / rcat / rboard / rfirsts on opcode 229).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
RecordsView = {}

-- the meta comes in parts: rcat {cat, boards} (each at most 6 boards), then rmeta {categories, parts, ...}.
-- state = {pending = {[cat] = {boards...}}, parts = n}. Returns the state.
function RecordsView.addPart(state, data)
  state = state or { pending = {}, parts = 0 }
  if type(data) ~= 'table' or type(data.cat) ~= 'string' or type(data.boards) ~= 'table' then return state end
  local list = state.pending[data.cat] or {}
  for _, b in ipairs(data.boards) do
    if type(b) == 'table' and type(b.key) == 'string' then list[#list + 1] = b end
  end
  state.pending[data.cat] = list
  state.parts = state.parts + 1
  return state
end

-- rmeta + the parts -> meta = {categories = {{key, name, title, info, boards}}, periods, groups, season, complete}
function RecordsView.finish(state, data)
  local meta = { categories = {}, periods = {}, groups = {}, season = nil, complete = false }
  if type(data) ~= 'table' then return meta end
  state = state or { pending = {}, parts = 0 }
  for _, c in ipairs(type(data.categories) == 'table' and data.categories or {}) do
    if type(c) == 'table' and type(c.key) == 'string' then
      meta.categories[#meta.categories + 1] = { key = c.key, name = tostring(c.name or c.key), title = c.title,
        info = c.info, boards = state.pending[c.key] or {} }
    end
  end
  for _, p in ipairs(type(data.periods) == 'table' and data.periods or {}) do
    if type(p) == 'table' and type(p.key) == 'string' then meta.periods[#meta.periods + 1] = p end
  end
  for _, g in ipairs(type(data.groups) == 'table' and data.groups or {}) do
    if type(g) == 'table' and g.key ~= nil then meta.groups[#meta.groups + 1] = g end
  end
  -- the realm firsts: a category of the client (its own request)
  meta.categories[#meta.categories + 1] = { key = 'firsts', name = 'Realm Firsts', boards = {},
    info = 'The first player or party to defeat each boss this season.' }
  meta.season = type(data.season) == 'table' and data.season or nil
  meta.badge = data.badge
  meta.complete = (tonumber(data.parts) or 0) == state.parts
  return meta
end

function RecordsView.category(meta, key)
  for _, c in ipairs(meta and meta.categories or {}) do
    if c.key == key then return c end
  end
  return nil
end

function RecordsView.board(meta, key)
  for _, c in ipairs(meta and meta.categories or {}) do
    for _, b in ipairs(c.boards) do
      if b.key == key then return b, c end
    end
  end
  return nil
end

local function has(list, key)
  for _, x in ipairs(list or {}) do
    if x.key == key then return true end
  end
  return false
end

-- the filters of a board kept valid: sel = {variant, size, period, group}; a filter the board does not have is dropped,
-- one it has but that is not set (or not valid) becomes the first
function RecordsView.normalize(board, sel, periods)
  sel = sel or {}
  local out = { period = sel.period, group = sel.group }
  if not has(periods, out.period) then out.period = periods and periods[1] and periods[1].key or 'week' end
  local variants, sizes = board and board.variants or {}, board and board.sizes or {}
  if #variants > 0 then out.variant = has(variants, sel.variant) and sel.variant or variants[1].key end
  if #sizes > 0 then out.size = has(sizes, sel.size) and sel.size or sizes[1].key end
  if not (board and board.byClass) then out.group = nil end
  return out
end

-- the "rget" request of a board and its filters
function RecordsView.request(board, sel)
  return { board = board and board.key, variant = sel.variant, size = sel.size, period = sel.period, group = sel.group }
end

function RecordsView.valueText(value, format)
  value = tonumber(value) or 0
  if format == 'time' then
    local s = math.max(0, math.floor(value))
    if s >= 3600 then return string.format('%d:%02d:%02d', math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60) end
    return string.format('%d:%02d', math.floor(s / 60), s % 60)
  elseif format == 'pct' then
    return string.format('%.2f%%', value / 100)
  end
  return tostring(math.floor(value))
end

-- the "your rank" line
function RecordsView.ownText(board, data)
  local own = type(data) == 'table' and type(data.own) == 'table' and data.own or nil
  if not own then return tr('You have no result on this board in this view yet.') end
  return tr('Your rank: #%d of %d   -   %s: %s', tonumber(own.rank) or 0, tonumber(data.total) or 0,
    board and board.value or 'Best', RecordsView.valueText(own.value, board and board.format))
end

-- "the all-time record" line under the tabs
function RecordsView.recordText(board, data)
  if type(data) ~= 'table' or not tonumber(data.record) then return tr('No all-time record yet: be the first.') end
  return tr('All-time record: %s', RecordsView.valueText(data.record, board and board.format))
end

function RecordsView.dateText(at)
  at = tonumber(at)
  if not at or at <= 0 then return '' end
  return os.date('%Y-%m-%d', at)
end
