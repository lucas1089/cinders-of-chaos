-- Seasonal Journey tab of the Season window: the pure parts (no client API), tested by journeyview_test.lua.
-- Server: server/data/scripts/chaos/season_journey.lua, on the season opcode 246:
--   journey {name, set, pieces, piecesTotal, finished, current, preview, why, mode, none,
--            chapters = [{key, name, text, level, state = open|locked|done|preview, lockedWhy, done, total}]}
--   journeyChapter {index, objectives = [{key, text, target, progress, done, only}],
--                   rewards = [{kind, text, piece, clientId, count, look}]}
--   journeyDone {text, chapter?}
-- The window code (journey.lua) keeps one JourneyView state and draws from it.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

JourneyView = {}
local V = JourneyView

V.STATE_COLOR = { done = '#7fc86a', open = '#f6cf72', locked = '#6b6258', preview = '#b8b0a0' }
V.ONLY_TAG = { hc = 'Hardcore', ssf = 'Self-Found', nossf = 'Not Self-Found', nohc = 'Not Hardcore' }

local ROMAN = { 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII' }
function V.roman(i)
  return ROMAN[i] or tostring(i)
end

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

function V.new()
  return { header = nil, chapters = {}, details = {}, selected = nil }
end

-- a header (journey message): the chapter summaries; details of chapters whose key changed are dropped
function V.onHeader(st, data)
  data = type(data) == 'table' and data or {}
  if data.none then
    st.header, st.chapters, st.details, st.selected = { none = true }, {}, {}, nil
    return st
  end
  local old = st.chapters
  st.header = data
  st.chapters = list(data.chapters)
  for i, c in ipairs(st.chapters) do
    if not old[i] or old[i].key ~= c.key then st.details[i] = nil end
  end
  for i in pairs(st.details) do
    if not st.chapters[i] then st.details[i] = nil end
  end
  if not st.selected or not st.chapters[st.selected] then
    st.selected = tonumber(data.current) or (#st.chapters > 0 and V.lastOpen(st.chapters)) or nil
  end
  return st
end

-- the chapter to show first: the open one, else the last finished one, else the first
function V.lastOpen(chapters)
  local best = 1
  for i, c in ipairs(chapters) do
    if c.state == 'open' then return i end
    if c.state == 'done' then best = i end
  end
  return best
end

function V.onChapter(st, data)
  data = type(data) == 'table' and data or {}
  local i = tonumber(data.index)
  if not i or i < 1 or i > 64 then return st end
  st.details[i] = { objectives = list(data.objectives), rewards = list(data.rewards) }
  return st
end

function V.select(st, i)
  if st.chapters[i] then st.selected = i end
  return st.selected
end

-- the chapter list: "II. Ash and Iron" and the status on its right
function V.chapterLabel(c, i)
  return string.format('%s. %s', V.roman(i), tostring(c.name or '?'))
end

function V.chapterStatus(c)
  if c.state == 'done' then return 'Complete' end
  if c.state == 'locked' then
    return (tonumber(c.level) or 0) > 0 and string.format('Lv %d', c.level) or 'Locked'
  end
  if c.state == 'preview' then return tr('%d goals', tonumber(c.total) or 0) end
  return string.format('%d / %d', tonumber(c.done) or 0, tonumber(c.total) or 0)
end

-- the line under the chapter name: its text, or why it is locked
function V.chapterNote(c)
  if c.state == 'locked' and c.lockedWhy then
    return tr('Locked: %s', c.lockedWhy)
  end
  return tostring(c.text or '')
end

-- one objective row: text, percent, the bar's label, colour, the mode tag under the text (none when the text already
-- starts with it, as "Hardcore: ..." does)
function V.objectiveRow(o, preview)
  local target = math.max(1, tonumber(o.target) or 1)
  local text = tostring(o.text or '?')
  local tag = o.only and V.ONLY_TAG[o.only] or nil
  if tag and text:sub(1, #tag + 1) == tag .. ':' then tag = nil end
  if preview then
    return { text = text, tag = tag, percent = 0, label = tr('Goal: %d', target), color = '#b8b0a0', done = false }
  end
  if o.done then
    return { text = text, tag = tag, percent = 100, label = 'Done', color = '#7fc86a', done = true }
  end
  local p = math.max(0, math.min(target, tonumber(o.progress) or 0))
  return { text = text, tag = tag, percent = math.floor(p * 100 / target), label = string.format('%d / %d', p, target),
    color = '#d6c9ae', done = false }
end

function V.rewardLine(r)
  local text = tostring(r.text or '')
  if r.piece then text = text .. ' (set)' end
  return text
end

-- the line above the tabs' content
function V.title(h)
  if not h or h.none then return tr('No journey this season') end
  local t = tostring(h.name or 'Journey')
  if h.mode then t = t .. '  -  ' .. tostring(h.mode) end
  return t
end

function V.summary(h, chapterCount)
  if not h or h.none then return '' end
  local parts = {}
  if h.preview then
    parts[#parts + 1] = 'Preview'
  else
    parts[#parts + 1] = tr('Chapters %d / %d', tonumber(h.finished) or 0, chapterCount or 0)
  end
  if h.set then
    parts[#parts + 1] = tr('%s set %d / %d', h.set, tonumber(h.pieces) or 0, tonumber(h.piecesTotal) or 0)
  end
  return table.concat(parts, '   ')
end

-- the banner of the open tab when something completes
function V.doneText(d)
  if type(d) ~= 'table' then return '' end
  if d.chapter then return tr('Chapter complete: %s!', tostring(d.text or '')) end
  return tr('Objective done: %s', tostring(d.text or ''))
end

return V
