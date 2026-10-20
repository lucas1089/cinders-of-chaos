-- Stat help maths of the passive tree window (no client API, tested by statinfoview_test.lua). The server sends the stats of
-- the player's class already in the player's language (server/data/scripts/chaos/passivetree_stats.lua):
--   statInfo {cls, part, parts, header = {primary, secondary} (part 1), stats = [{k, n, d, t = "primary" | "secondary" | nil}]}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
StatInfoView = {}
local V = StatInfoView

V.GOLD, V.SILVER, V.TEXT, V.DIM = '#e8c860', '#b8c0c8', '#d8cfc0', '#8c8070'

function V.new()
  return {byKey = {}, order = {}, header = nil, cls = nil, got = 0, parts = 0}
end

-- adds one statInfo message; a message of another class (the player changed character) starts over. Returns the state.
function V.add(state, data)
  if type(data) ~= 'table' or type(data.stats) ~= 'table' then
    return state
  end
  if state.cls ~= data.cls or data.part == 1 then
    state = V.new()
    state.cls = data.cls
  end
  state.parts, state.got = tonumber(data.parts) or 1, state.got + 1
  if type(data.header) == 'table' then
    state.header = data.header
  end
  for _, s in ipairs(data.stats) do
    if type(s) == 'table' and type(s.k) == 'string' and not state.byKey[s.k] then
      state.byKey[s.k] = {k = s.k, n = tostring(s.n or s.k), d = tostring(s.d or ''), t = s.t}
      state.order[#state.order + 1] = s.k
    end
  end
  return state
end

-- 'primary' when any stat of the node is a primary one of the class, else 'secondary', else nil. stats = a node's customStats
function V.tag(state, stats)
  local tag
  for key in pairs(stats or {}) do
    local s = state.byKey[key]
    if s and s.t == 'primary' then
      return 'primary'
    elseif s and s.t == 'secondary' then
      tag = 'secondary'
    end
  end
  return tag
end

function V.color(tag)
  return tag == 'primary' and V.GOLD or tag == 'secondary' and V.SILVER or nil
end

-- the description lines under the stats of a node tooltip: "Name: what it does", in a fixed order
function V.lines(state, stats)
  local keys = {}
  for key in pairs(stats or {}) do
    if state.byKey[key] then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local out = {}
  for _, key in ipairs(keys) do
    local s = state.byKey[key]
    if s.d ~= '' then out[#out + 1] = s.n .. ': ' .. s.d end
  end
  return out
end

-- the line above the tree: the Primary and Secondary stats of the class
function V.headerText(state)
  local h = state.header
  if not h or ((h.primary or '') == '' and (h.secondary or '') == '') then
    return ''
  end
  local parts = {}
  if (h.primary or '') ~= '' then parts[#parts + 1] = tr('Primary') .. ': ' .. h.primary end
  if (h.secondary or '') ~= '' then parts[#parts + 1] = tr('Secondary') .. ': ' .. h.secondary end
  return table.concat(parts, '   ')
end

-- the rows of the Stats panel: {text, color}; primary first, then secondary, then the rest, a legend at the top
function V.rows(state)
  local rows = {{text = tr('Gold marks a Primary stat of your class, silver a Secondary one.'), color = V.DIM}}
  for _, tag in ipairs({'primary', 'secondary', false}) do
    for _, key in ipairs(state.order) do
      local s = state.byKey[key]
      if (s.t or false) == tag then
        rows[#rows + 1] = {text = s.n .. (tag and (' [' .. (tag == 'primary' and tr('Primary') or tr('Secondary')) .. ']') or ''),
          color = V.color(tag) or V.TEXT}
        if s.d ~= '' then rows[#rows + 1] = {text = s.d, color = V.DIM} end
      end
    end
  end
  return rows
end

return V
