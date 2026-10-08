-- Patch notes window: what to draw and when to open it (no client API, tested by patchnotesview_test.lua).
--   PatchNotesView.blocks(note)        the server's note -> a list of blocks to draw, top to bottom:
--                                      {style = 'title'|'date'|'intro'|'section'|'paragraph'|'bullet', text, color,
--                                       lead, leadColor, level}
--   PatchNotesView.weekText(week)      {date, title} lines of an entry in the week list
--   PatchNotesView.formatDate(s)       '2026-10-08' -> '8 October 2026' (anything else as it is)
--   PatchNotesView.autoStep(st, dailyVisible, now)   login auto-open: 'wait' or 'show' (see below)
--   PatchNotesView.join(parts, total)  the parts of a long note (server PN.parts) -> one note, or nil if one is missing
PatchNotesView = {}
local V = PatchNotesView

-- section name colours (the palette of client_chaos_theme plus three accents)
V.COLORS = {
  new = '#7cd35a',      -- green
  changes = '#e8b84a',  -- ember gold
  fixes = '#6aa8ff',    -- arcane blue
  balance = '#d07aff',  -- violet
  other = '#d6c9ae'     -- parchment
}
V.TEXT = '#d6c9ae'
V.DIM = '#8c8070'
V.TITLE = '#f6cf72'
V.LEAD = '#f6cf72'

-- seconds the login auto-open waits for a Daily Reward window the server expects, and the pause after it closed
V.DAILY_WAIT = 6
V.AFTER_DAILY = 0.6

local MONTHS = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December' }

function V.formatDate(s, short)
  if type(s) ~= 'string' then return '' end
  local y, m, d = s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  m = tonumber(m)
  if not y or not MONTHS[m] then return s end
  local month = MONTHS[m]
  if short then month = month:sub(1, 3) end
  return string.format('%d %s %s', tonumber(d), month, y)
end

local function list(v)
  local out = {}
  if type(v) == 'table' then
    for _, x in ipairs(v) do out[#out + 1] = x end
  end
  return out
end

local function str(v)
  if type(v) == 'string' then return v end
  if type(v) == 'number' then return tostring(v) end
  return ''
end

function V.blocks(note)
  local out = {}
  if type(note) ~= 'table' then return out end
  out[#out + 1] = { style = 'title', text = str(note.title), color = V.TITLE }
  if str(note.date) ~= '' then
    out[#out + 1] = { style = 'date', text = V.formatDate(note.date), color = V.DIM }
  end
  for _, line in ipairs(list(note.intro)) do
    if str(line) ~= '' then out[#out + 1] = { style = 'intro', text = str(line), color = V.TEXT } end
  end
  for _, sec in ipairs(list(note.sections)) do
    local items = list(sec.items)
    if #items > 0 then
      local color = V.COLORS[str(sec.kind)] or V.COLORS.other
      out[#out + 1] = { style = 'section', text = str(sec.name), color = color }
      for _, it in ipairs(items) do
        local level = tonumber(it.level) or 1
        local b = { text = str(it.text), color = V.TEXT, level = level }
        if level == 0 then
          b.style = 'paragraph'
        else
          b.style = 'bullet'
          b.level = level >= 2 and 2 or 1
          b.bulletColor = b.level == 1 and color or V.DIM
        end
        if str(it.lead) ~= '' then
          b.lead = str(it.lead)
          b.leadColor = V.LEAD
        end
        if b.text ~= '' or b.lead then out[#out + 1] = b end
      end
    end
  end
  return out
end

-- the coloured text of a block for label:setColoredText ({text, colour, text, colour, ...}), or nil for plain text
function V.colored(b)
  if not b.lead then return nil end
  if b.text == '' then return { b.lead, b.leadColor } end
  return { b.lead .. ' ', b.leadColor, b.text, b.color }
end

function V.plain(b)
  if b.lead and b.text ~= '' then return b.lead .. ' ' .. b.text end
  return b.lead or b.text
end

function V.weekText(week)
  week = type(week) == 'table' and week or {}
  local date = V.formatDate(str(week.date), true)
  return { date = date ~= '' and date or str(week.id), title = str(week.title), new = week.new == true }
end

-- Login auto-open. st = {dailyFirst = server expects the Daily Reward window, since = time the auto message came}
-- (st.sawDaily / st.closedAt are kept here). The patch notes never stack on the daily window: while it is visible
-- they wait; after it closed they open (a short pause, so they do not pop up in the same frame); when the server
-- expected it but it has not shown up after DAILY_WAIT seconds, they open anyway.
function V.autoStep(st, dailyVisible, now)
  if dailyVisible then
    st.sawDaily = true
    st.closedAt = nil
    return 'wait'
  end
  if st.sawDaily then
    st.closedAt = st.closedAt or now
    if now - st.closedAt < V.AFTER_DAILY then return 'wait' end
    return 'show'
  end
  if st.dailyFirst and now - (st.since or now) < V.DAILY_WAIT then return 'wait' end
  return 'show'
end

-- parts[1..total] of one note -> the note; a section with cont = true continues the last section of the parts before
function V.join(parts, total)
  if type(parts) ~= 'table' then return nil end
  total = total or #parts
  local first = parts[1]
  if type(first) ~= 'table' then return nil end
  local note = { id = first.id, title = first.title, date = first.date, intro = list(first.intro), sections = {} }
  for i = 1, total do
    local p = parts[i]
    if type(p) ~= 'table' then return nil end
    for _, sec in ipairs(list(p.sections)) do
      if type(sec) == 'table' then
        local last = note.sections[#note.sections]
        if sec.cont == true and last and last.name == sec.name then
          for _, it in ipairs(list(sec.items)) do last.items[#last.items + 1] = it end
        else
          note.sections[#note.sections + 1] = { name = sec.name, kind = sec.kind, items = list(sec.items) }
        end
      end
    end
  end
  return note
end
