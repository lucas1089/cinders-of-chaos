-- Item finder: the logic without client API (tested by itemfinderlogic_test.lua; itemfinder.lua draws).
-- The server (data/scripts/chaos/itemfinder.lua, extended opcode 155) sends ready texts; this file checks the answers,
-- names the sections, lays out a row's texts, keeps the history and the search timing, and links the Codex.
ItemFinderLogic = {}
local L = ItemFinderLogic

L.OPCODE = 155
L.SEARCH_DELAY_MS = 350 -- type-ahead: the search goes out this long after the last key
L.RESEND_MS = 900       -- a search without an answer this long is sent again once (the server drops requests that come too fast)
L.MIN_QUERY = 2
L.MAX_QUERY = 40
L.HISTORY = 20

-- the sections in the server's order, with their titles
L.SECTIONS = {
  { k = 'monster', title = 'Monsters and bosses' },
  { k = 'drop', title = 'Chaos drops' },
  { k = 'reward', title = 'Chests and rewards' },
  { k = 'craft', title = 'Crafted from' },
  { k = 'shop', title = 'NPCs that sell it' },
  { k = 'store', title = 'Store and vendors' },
  { k = 'gamble', title = 'The Gambler' },
  { k = 'gather', title = 'Gathering' },
  { k = 'usedin', title = 'Used to make' },
  { k = 'sellto', title = 'NPCs that buy it' },
  { k = 'use', title = 'Other uses' },
}
L.SHORT = {
  monster = 'drops', drop = 'Chaos drops', reward = 'rewards', craft = 'recipes', shop = 'shops', store = 'store',
  gamble = 'Gambler', gather = 'gathering', usedin = 'used in', sellto = 'sold to NPCs', use = 'uses',
}

local byKind = {}
for i, s in ipairs(L.SECTIONS) do byKind[s.k] = i end

function L.title(k)
  local i = byKind[k]
  return i and L.SECTIONS[i].title or tostring(k)
end

-- the text sent as a search: trimmed, inner spaces folded, at most MAX_QUERY characters
function L.query(text)
  text = tostring(text or ''):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  return text:sub(1, L.MAX_QUERY)
end

-- whether `text` should go out: long enough and not the one already asked for
function L.shouldSearch(text, lastSent)
  local q = L.query(text)
  if #q < L.MIN_QUERY then return false, q end
  return q:lower() ~= tostring(lastSent or ''):lower(), q
end

-- "drops, shops, recipes" of a result's kinds (at most `max`)
function L.kindsText(kinds, max)
  local out = {}
  for _, k in ipairs(type(kinds) == 'table' and kinds or {}) do
    if #out >= (max or 4) then
      out[#out + 1] = '...'
      break
    end
    out[#out + 1] = L.SHORT[k] or tostring(k)
  end
  return table.concat(out, ', ')
end

function L.pageText(p, pages)
  p, pages = tonumber(p) or 1, tonumber(pages) or 1
  if pages <= 1 then return '' end
  return string.format('%d / %d', p, pages)
end

-- "1 source or use", "12 sources and uses"
function L.totalText(n)
  n = tonumber(n) or 0
  return n == 1 and '1 source or use' or string.format('%d sources and uses', n)
end

-- the head line of a section: "Monsters and bosses (12)"
function L.sectionHead(sec)
  return string.format('%s (%d)', L.title(sec.k), tonumber(sec.total) or #(sec.rows or {}))
end

-- a row's texts: main (name, " (boss)"), sub (detail), value (chance or price, then the count)
function L.rowTexts(row)
  local main = tostring(row.n or '')
  if row.b then main = main .. ' (boss)' end
  local value = row.v and tostring(row.v) or ''
  if row.c then value = (value ~= '' and (value .. '  ') or '') .. tostring(row.c) end
  return main, row.d and tostring(row.d) or '', value
end

-- the tooltip of a material: "5 x dragon scale"
function L.materialText(m)
  return string.format('%d x %s', tonumber(m.c) or 1, tostring(m.n or '?'))
end

-- ---------------------------------------------------------------- answers
local function isList(t) return type(t) == 'table' end

local function cleanRows(rows)
  local out = {}
  for _, r in ipairs(isList(rows) and rows or {}) do
    if type(r) == 'table' and type(r.n) == 'string' then
      local m = {}
      for _, e in ipairs(isList(r.m) and r.m or {}) do
        if type(e) == 'table' then
          m[#m + 1] = { i = tonumber(e.i) or 0, l = tonumber(e.l), n = tostring(e.n or ''), c = tonumber(e.c) or 1 }
        end
      end
      out[#out + 1] = { n = r.n, d = type(r.d) == 'string' and r.d or nil, v = type(r.v) == 'string' and r.v or nil,
        c = type(r.c) == 'string' and r.c or nil, i = tonumber(r.i), l = tonumber(r.l), b = r.b == true or nil,
        m = #m > 0 and m or nil }
    end
  end
  return out
end

local function cleanSection(s)
  if type(s) ~= 'table' or type(s.k) ~= 'string' then return nil end
  return { k = s.k, p = tonumber(s.p) or 1, pages = tonumber(s.pages) or 1, total = tonumber(s.total) or 0,
    rows = cleanRows(s.rows) }
end

-- results {q, p, pages, total, rows} -> a checked copy (nil when it is not one)
function L.results(d)
  if type(d) ~= 'table' then return nil end
  local out = { q = tostring(d.q or ''), p = tonumber(d.p) or 1, pages = tonumber(d.pages) or 1,
    total = tonumber(d.total) or 0, rows = {} }
  for _, r in ipairs(isList(d.rows) and d.rows or {}) do
    if type(r) == 'table' and tonumber(r.id) and type(r.name) == 'string' then
      out.rows[#out.rows + 1] = { id = tonumber(r.id), cid = tonumber(r.cid) or 0, name = r.name,
        n = tonumber(r.n) or 0, kinds = isList(r.kinds) and r.kinds or {} }
    end
  end
  return out
end

-- item {id, cid, name, total, secs | none} -> a checked copy, sections in the known order
function L.item(d)
  if type(d) ~= 'table' then return nil end
  local out = { id = tonumber(d.id) or 0, cid = tonumber(d.cid) or 0, name = type(d.name) == 'string' and d.name or nil,
    total = tonumber(d.total) or 0, none = d.none == true, secs = {} }
  for _, s in ipairs(isList(d.secs) and d.secs or {}) do
    local c = cleanSection(s)
    if c then out.secs[#out.secs + 1] = c end
  end
  table.sort(out.secs, function(a, b) return (byKind[a.k] or 99) < (byKind[b.k] or 99) end)
  return out
end

-- a page of one section into the item shown (only when it is that item); true when it changed something
function L.applyPage(item, d)
  if type(item) ~= 'table' or type(d) ~= 'table' or tonumber(d.id) ~= item.id then return false end
  local c = cleanSection(d)
  if not c then return false end
  for i, s in ipairs(item.secs) do
    if s.k == c.k then
      item.secs[i] = c
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------- history (items opened by links)
function L.push(history, entry)
  if type(entry) ~= 'table' then return history end
  local last = history[#history]
  if last and last.id == entry.id and last.cid == entry.cid then return history end
  history[#history + 1] = entry
  while #history > L.HISTORY do table.remove(history, 1) end
  return history
end

function L.pop(history)
  return table.remove(history)
end

-- ---------------------------------------------------------------- the Codex
-- server item id -> Codex entry id, from the Codex data (entries with `items` = {server ids})
function L.codexIndex(codexData)
  local map = {}
  for _, tab in ipairs(type(codexData) == 'table' and codexData.tabs or {}) do
    for _, e in ipairs(tab.entries or {}) do
      for _, id in ipairs(type(e.items) == 'table' and e.items or {}) do
        if tonumber(id) and not map[tonumber(id)] then map[tonumber(id)] = e.id end
      end
    end
  end
  return map
end

-- a client item id the window may show (the engine draws ids 1..65535)
function L.validClientId(cid)
  cid = tonumber(cid)
  return cid ~= nil and cid >= 1 and cid <= 65535 and cid == math.floor(cid)
end
