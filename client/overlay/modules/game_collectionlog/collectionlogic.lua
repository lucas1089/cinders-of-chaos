-- Pure helpers of the Collection log window (O753; no UI calls): the payload cleaned, the filter, the list lines (group
-- headers and items), the texts as {pattern, args...} for tr(), the pity lines. Tested by collectionlogic_test.lua
-- (luajit / lua5.3). Server: server/data/scripts/chaos/collection_log.lua, extended opcode 170 (JSON {action, data}).
CollectionLogLogic = {}
local L = CollectionLogLogic

L.OPCODE = 170

-- the status filter: value, English label (tr() in the view)
L.STATUS = {
  { 'all', 'All' },
  { 'owned', 'Owned' },
  { 'seen', 'Seen' },
  { 'missing', 'Not yet' },
}

L.STATE_TEXT = { [2] = 'Owned', [1] = 'Seen', [0] = 'Not yet' }
L.STATE_COLOR = { [2] = '#7ec97a', [1] = '#e8c76a', [0] = '#8a7f6e' }

local function int(v)
  v = tonumber(v)
  if not v or v ~= v then return 0 end
  return math.floor(v)
end

local function str(v)
  if type(v) == 'string' then return v end
  if type(v) == 'number' then return tostring(v) end
  return ''
end

-- the server's state: {rows = [{i, c, n, g, s, k, d}], groups = [{k, l, a}], pity = [{k, l, a, d, n}], owned, seen, total}
function L.clean(data)
  local out = { rows = {}, groups = {}, order = {}, pity = {}, owned = 0, seen = 0, total = 0 }
  if type(data) ~= 'table' then return out end
  for _, r in ipairs(type(data.rows) == 'table' and data.rows or {}) do
    if type(r) == 'table' and int(r.i) > 0 then
      local s = int(r.s)
      if s < 0 or s > 2 then s = 0 end
      out.rows[#out.rows + 1] = { id = int(r.i), cid = int(r.c) > 0 and int(r.c) or int(r.i), name = str(r.n), group = str(r.g),
        state = s, count = math.max(0, int(r.k)), date = math.max(0, int(r.d)) }
    end
  end
  for _, g in ipairs(type(data.groups) == 'table' and data.groups or {}) do
    if type(g) == 'table' and str(g.k) ~= '' and not out.groups[str(g.k)] then
      out.groups[str(g.k)] = { label = str(g.l), arg = g.a ~= nil and str(g.a) or nil }
      out.order[#out.order + 1] = str(g.k)
    end
  end
  for _, p in ipairs(type(data.pity) == 'table' and data.pity or {}) do
    if type(p) == 'table' and str(p.k) ~= '' then
      local n = math.max(1, int(p.n))
      out.pity[#out.pity + 1] = { key = str(p.k), label = str(p.l), arg = p.a ~= nil and str(p.a) or nil,
        done = math.min(n, math.max(0, int(p.d))), n = n }
    end
  end
  out.owned, out.seen, out.total = int(data.owned), int(data.seen), int(data.total)
  if out.total <= 0 then out.total = #out.rows end
  return out
end

local function lower(s)
  return tostring(s or ''):lower()
end

function L.match(row, status, search)
  if status == 'owned' and row.state ~= 2 then return false end
  if status == 'seen' and row.state ~= 1 then return false end
  if status == 'missing' and row.state ~= 0 then return false end
  search = lower(search):gsub('^%s+', ''):gsub('%s+$', '')
  if search ~= '' and not lower(row.name):find(search, 1, true) then return false end
  return true
end

-- the list: for every group (in the server's order) that has a matching row, a header line, then its rows
-- header: {kind = 'header', key, label, arg, owned, total}; item: {kind = 'item', row}
function L.lines(state, status, search)
  local out = {}
  if not state then return out end
  local byGroup, totals = {}, {}
  for _, r in ipairs(state.rows) do
    local t = totals[r.group]
    if not t then
      t = { owned = 0, total = 0 }
      totals[r.group] = t
    end
    t.total = t.total + 1
    if r.state == 2 then t.owned = t.owned + 1 end
    if L.match(r, status, search) then
      byGroup[r.group] = byGroup[r.group] or {}
      table.insert(byGroup[r.group], r)
    end
  end
  local order, used = {}, {}
  for _, k in ipairs(state.order) do
    order[#order + 1] = k
    used[k] = true
  end
  local extra = {}
  for k in pairs(byGroup) do
    if not used[k] then extra[#extra + 1] = k end
  end
  table.sort(extra)
  for _, k in ipairs(extra) do order[#order + 1] = k end
  for _, k in ipairs(order) do
    local list = byGroup[k]
    if list and #list > 0 then
      local g = state.groups[k] or { label = k }
      out[#out + 1] = { kind = 'header', key = k, label = g.label, arg = g.arg, owned = totals[k].owned, total = totals[k].total }
      for _, r in ipairs(list) do
        out[#out + 1] = { kind = 'item', row = r }
      end
    end
  end
  return out
end

-- the first drop date, day/month/year ('' when unknown)
function L.dateText(ts)
  ts = int(ts)
  if ts <= 0 then return '' end
  return os.date('%d/%m/%Y', ts)
end

-- the text of an item line's right side, as {pattern, args...}
function L.itemDetail(row)
  if row.state == 2 and row.count > 0 and row.date > 0 then
    return { 'x%d, first on %s', row.count, L.dateText(row.date) }
  elseif row.state == 2 and row.count > 0 then
    return { 'x%d', row.count }
  end
  return { L.STATE_TEXT[row.state] or 'Not yet' }
end

function L.summary(state)
  if not state then return { 'Loading...' } end
  return { 'Owned %d of %d, seen %d', state.owned, state.total, state.seen }
end

-- a pity line: {label, arg, text = '37 / 60', ratio 0..1}
function L.pityLines(state)
  local out = {}
  for _, p in ipairs(state and state.pity or {}) do
    out[#out + 1] = { label = p.label, arg = p.arg, text = string.format('%d / %d', p.done, p.n), ratio = p.done / p.n }
  end
  return out
end

function L.valueOf(options, label)
  for _, o in ipairs(options) do
    if o[2] == label or o[3] == label then return o[1] end
  end
  return 'all'
end

return L
