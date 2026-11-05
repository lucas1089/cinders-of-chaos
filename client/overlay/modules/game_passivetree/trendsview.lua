-- Trending builds texts of the passive tree window (O409; no client API, tested by trendsview_test.lua). The server
-- (server/data/scripts/chaos/build_trends.lua) sends, on opcode 65:
--   buildTrends {class, className, at, total, classes = [{key, name}], rows = [{rank, share (per mille), count, level,
--                keystones, code (CB<n>-), full (CC1-)}]}
-- No character name or id is ever in it.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
TrendsView = {}
local V = TrendsView

V.ROWS = 5

-- 429 -> "42.9%", 1000 -> "100%"
function V.share(perMille)
  local n = math.max(0, math.min(1000, math.floor(tonumber(perMille) or 0)))
  if n % 10 == 0 then
    return string.format('%d%%', n / 10)
  end
  return string.format('%d.%d%%', math.floor(n / 10), n % 10)
end

-- the two lines of a row: rank, share, characters, average level; then the keystones
function V.rowText(row)
  if type(row) ~= 'table' then
    return ''
  end
  local head = tr('#%d  %s of the class, %d characters, average level %d', tonumber(row.rank) or 0, V.share(row.share),
    tonumber(row.count) or 0, tonumber(row.level) or 0)
  local ks = type(row.keystones) == 'string' and row.keystones ~= '' and row.keystones or tr('no keystone')
  return head .. '\n' .. tr('Keystones: %s', ks)
end

-- the code the Import button pastes: the full build code, else the tree code
function V.importCode(row)
  if type(row) ~= 'table' then
    return nil
  end
  local full, code = row.full, row.code
  if type(full) == 'string' and full:match('^CC1%-') then
    return full
  end
  if type(code) == 'string' and code:match('^CB%d+%-') then
    return code
  end
  return nil
end

-- the next (dir 1) or previous (dir -1) class tab key, wrapping; the first one for an unknown key
function V.step(classes, key, dir)
  if type(classes) ~= 'table' or #classes == 0 then
    return key
  end
  local index = 0
  for i, c in ipairs(classes) do
    if c.key == key then
      index = i
    end
  end
  if index == 0 then
    return classes[1].key
  end
  index = (index - 1 + (dir or 1)) % #classes + 1
  return classes[index].key
end

-- the line under the class name
function V.info(data)
  if type(data) ~= 'table' or (tonumber(data.at) or 0) <= 0 then
    return tr('No snapshot yet: the server counts the builds once a day.')
  end
  local day = os.date('%Y-%m-%d', tonumber(data.at))
  if (tonumber(data.total) or 0) <= 0 or type(data.rows) ~= 'table' or #data.rows == 0 then
    return tr('Snapshot of %s: no build of this class is played by enough characters yet.', day)
  end
  return tr('Snapshot of %s: %d active characters of this class (level 100+, last 7 days).', day, tonumber(data.total))
end

-- the rows to show (at most V.ROWS, only valid ones)
function V.rows(data)
  local out = {}
  for _, r in ipairs(type(data) == 'table' and type(data.rows) == 'table' and data.rows or {}) do
    if #out < V.ROWS and type(r) == 'table' and V.importCode(r) then
      out[#out + 1] = r
    end
  end
  return out
end
