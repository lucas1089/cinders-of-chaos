-- Patch notes window: what to draw and when to open it (no client API, tested by patchnotesview_test.lua).
--   PatchNotesView.blocks(note)        the server's note -> a list of blocks to draw, top to bottom:
--                                      {style = 'title'|'date'|'intro'|'section'|'paragraph'|'bullet', text, color,
--                                       lead, leadColor, level}
--   PatchNotesView.weekText(week)      {date, title} lines of an entry in the week list
--   PatchNotesView.formatDate(s)       '2026-10-08' -> '8 October 2026' (anything else as it is)
--   PatchNotesView.autoStep(st, dailyVisible, now)   login auto-open: 'wait' or 'show' (see below)
--   PatchNotesView.join(parts, total)  the parts of a long note (server PN.parts) -> one note, or nil if one is missing
-- The Changelog tab (server changelog_core.lua; entries stay as written, in English):
--   PatchNotesView.changelogRows(entries, filter, seenTs)   rows to draw: {kind = 'date', text} and {kind = 'entry',
--                                      parts = {text, colour, ...}, color (dot), new, tooltip}; returns rows, shown
--   PatchNotesView.newCount(entries, seenTs)   entries newer than the last look (0 before the first look)
--   PatchNotesView.newestTs(entries)   what is stored as the last look
--   PatchNotesView.clientInfo(status, update)   {version, build} of this client: ChaosUpdater.status() and
--                                      Services.update (the applied update or the package's baseline; the package build)
--   PatchNotesView.infoText(serverDate, info)   the line above the list: server update date and client version
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

-- ---------------------------------------------------------------- changelog
V.TAG_ORDER = { 'server', 'client', 'content', 'website' }
V.TAG_COLORS = {
  server = '#e8b84a',   -- ember gold
  client = '#6aa8ff',   -- arcane blue
  content = '#d07aff',  -- violet
  website = '#7cd35a'   -- green
}
V.NEW = '#7cd35a'
V.FILTERS = { 'all', 'server', 'client', 'content', 'website' }

function V.tagLabel(tag)
  if tag == 'server' then return tr('Server') end
  if tag == 'client' then return tr('Client') end
  if tag == 'content' then return tr('Content') end
  if tag == 'website' then return tr('Website') end
  return tr('All')
end

local function int(v)
  v = tonumber(v)
  if not v or v ~= v or v < 0 or v > 1e12 then return 0 end
  return math.floor(v)
end

local function hasTag(e, tag)
  for _, t in ipairs(list(e.tags)) do
    if t == tag then return true end
  end
  return false
end

function V.matches(e, filter)
  return filter == nil or filter == 'all' or hasTag(e, filter)
end

function V.isNew(e, seenTs)
  seenTs = int(seenTs)
  return seenTs > 0 and int(e.ts) > seenTs
end

function V.newestTs(entries)
  local m = 0
  for _, e in ipairs(list(entries)) do
    if type(e) == 'table' and int(e.ts) > m then m = int(e.ts) end
  end
  return m
end

function V.newCount(entries, seenTs)
  local n = 0
  for _, e in ipairs(list(entries)) do
    if type(e) == 'table' and V.isNew(e, seenTs) then n = n + 1 end
  end
  return n
end

-- the label of one tag of an entry: the client tag names the client update the change came with
function V.tagText(e, tag)
  if tag == 'client' then
    local n = int(e.client)
    if e.pending == true or n == 0 then return tr('Client: next update') end
    return tr('Client %d', n)
  end
  return V.tagLabel(tag)
end

function V.changelogRows(entries, filter, seenTs)
  local rows, shown, lastDate = {}, 0, nil
  for _, e in ipairs(list(entries)) do
    if type(e) == 'table' and str(e.text) ~= '' and V.matches(e, filter) then
      local date = str(e.date)
      if date ~= lastDate then
        rows[#rows + 1] = { kind = 'date', text = V.formatDate(date) }
        lastDate = date
      end
      local parts, first = {}, nil
      local new = V.isNew(e, seenTs)
      if new then
        parts[#parts + 1] = tr('NEW') .. ' '
        parts[#parts + 1] = V.NEW
      end
      for _, tag in ipairs(V.TAG_ORDER) do
        if hasTag(e, tag) then
          first = first or tag
          parts[#parts + 1] = '[' .. V.tagText(e, tag) .. '] '
          parts[#parts + 1] = V.TAG_COLORS[tag]
        end
      end
      parts[#parts + 1] = str(e.text)
      parts[#parts + 1] = V.TEXT
      local plain = {}
      for i = 1, #parts, 2 do plain[#plain + 1] = parts[i] end
      rows[#rows + 1] = { kind = 'entry', parts = parts, plain = table.concat(plain), new = new,
                          color = V.TAG_COLORS[first] or V.DIM }
      shown = shown + 1
    end
  end
  return rows, shown
end

function V.clientInfo(status, update)
  status = type(status) == 'table' and status or {}
  update = type(update) == 'table' and update or {}
  return { version = math.max(int(status.version), int(status.baseline), int(update.baseline)),
           build = int(update.package) }
end

function V.infoText(serverDate, info)
  info = info or {}
  local server = str(serverDate) ~= '' and tr('Server updated: %s', V.formatDate(str(serverDate)))
    or tr('Server updated: unknown')
  local client
  if int(info.version) > 0 and int(info.build) > 0 then
    client = tr('Client: update %d (build %d)', int(info.version), int(info.build))
  elseif int(info.version) > 0 then
    client = tr('Client: update %d', int(info.version))
  elseif int(info.build) > 0 then
    client = tr('Client: build %d', int(info.build))
  else
    client = tr('Client: version unknown')
  end
  return server .. '     ' .. client
end
