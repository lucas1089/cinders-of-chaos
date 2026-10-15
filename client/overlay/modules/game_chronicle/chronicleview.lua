-- Pure helpers of the Chronicle window (no client API), tested by chronicleview_test.lua.
-- The data comes from the server, extended opcode 171 (JSON {action, data}):
--   state (server/data/scripts/chaos/chronicle_core.lua K.payload):
--     {now, season, active, arc, title = {en, pt}, intro = {en, pt}, ending = {en, pt} | nil, done,
--      chapters = [{i, key, state = 'done' | 'open' | 'locked', pct, doneAt, title = {en, pt}, text = {en = [..], pt = [..]},
--                   world = {en, pt}, pending = [area keys], goals = [{l, lp, p, t}], mine, top = [{n, p}]}],
--      record = [{season, name, title = {en, pt}, chapters = [{i, title = {en, pt}, top = [{n, p}]}]}]}
--   mem (server/data/scripts/chaos/memorial_core.lua M.payload):
--     {season, records, fallen, ask, firsts = [{t, n, at}], recs = [{t, v, n, c, at}], falls = [{n, l, c, k, at}]}
-- Texts the server sends in both languages are picked here (V.pick); fixed words go through tr() (V.tr: string.format
-- without the client).
ChronicleView = {}
local V = ChronicleView

V.COLORS = {
  done = '#f6cf72',
  open = '#6fd86f',
  locked = '#6b6258',
  bar = '#c8641e',
  barDone = '#e8b84a',
  hidden = '#8c8070',
}

local function num(v) return tonumber(v) or 0 end
local function list(v) return type(v) == 'table' and v or {} end
local function str(v) return type(v) == 'string' and v or (type(v) == 'number' and tostring(v) or '') end

function V.tr(text, ...)
  if type(tr) == 'function' then return tr(text, ...) end
  if select('#', ...) > 0 then return string.format(text, ...) end
  return text
end

-- 'pt' for Portuguese (pt, pt-BR, pt_BR), else 'en'
function V.lang(code)
  code = str(code):lower()
  if code:sub(1, 2) == 'pt' then return 'pt' end
  return 'en'
end

-- a server text in both languages: {en = ..., pt = ...} (a string or a list of paragraphs)
function V.pick(field, lang)
  if type(field) ~= 'table' then return field end
  if lang == 'pt' and field.pt ~= nil then return field.pt end
  if field.en ~= nil then return field.en end
  return field.pt
end

function V.paragraphs(field, lang)
  local v = V.pick(field, lang)
  if type(v) == 'string' then return { v } end
  local out = {}
  for _, p in ipairs(list(v)) do
    if type(p) == 'string' and p ~= '' then out[#out + 1] = p end
  end
  return out
end

-- 1234567 -> "1,234,567"
function V.fmt(n)
  n = math.floor(num(n))
  local neg = n < 0
  local s = tostring(math.abs(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
  return (neg and '-' or '') .. s
end

local MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
function V.dateText(t)
  t = num(t)
  if t <= 0 then return '' end
  local d = os.date('*t', t)
  return string.format('%d %s %d', d.day, MONTHS[d.month], d.year)
end

-- a goal's bar: whole percent and "1,234 / 1,500"
function V.goalPercent(g)
  if type(g) ~= 'table' or num(g.t) <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor(num(g.p) * 100 / num(g.t))))
end

function V.goalText(g)
  if type(g) ~= 'table' then return '' end
  return string.format('%s / %s', V.fmt(g.p), V.fmt(g.t))
end

function V.goalLabel(g, lang)
  if type(g) ~= 'table' then return '' end
  return str(lang == 'pt' and g.lp ~= nil and g.lp or g.l)
end

-- the line under a chapter in the list, and its colour
function V.chapterLine(ch)
  if type(ch) ~= 'table' then return '', V.COLORS.locked end
  if ch.state == 'done' then
    local when = V.dateText(ch.doneAt)
    return when ~= '' and V.tr('Written on %s', when) or V.tr('Written'), V.COLORS.done
  elseif ch.state == 'open' then
    local pct = num(ch.pct)
    local shown = pct == math.floor(pct) and tostring(math.floor(pct)) or string.format('%.1f', pct)
    return V.tr('Open: %s%% written', shown), V.COLORS.open
  end
  return V.tr('Not yet told'), V.COLORS.locked
end

-- the chapters of the list (the open one selected first)
function V.chapters(data)
  return list(data and data.chapters)
end

function V.defaultChapter(data)
  local chs = V.chapters(data)
  for i, ch in ipairs(chs) do
    if type(ch) == 'table' and ch.state == 'open' then return i end
  end
  return #chs > 0 and #chs or nil
end

-- "1. Vexa  1,234"
function V.topRows(top)
  local out = {}
  for i, e in ipairs(list(top)) do
    if type(e) == 'table' then
      out[#out + 1] = { place = i, name = str(e.n), text = V.fmt(e.p) }
    end
  end
  return out
end

-- the areas a written chapter opened in the story that are not on the map yet
function V.pendingText(ch)
  local p = list(ch and ch.pending)
  if #p == 0 then return nil end
  return V.tr('The way is not on the map yet: the staff is placing it.')
end

-- ---------------------------------------------------------------- the record of past seasons
function V.recordSeasons(data)
  local out = {}
  for _, s in ipairs(list(data and data.record)) do
    if type(s) == 'table' then out[#out + 1] = s end
  end
  return out
end

function V.seasonTitle(s, lang)
  if type(s) ~= 'table' then return '' end
  local name = str(s.name)
  local title = str(V.pick(s.title, lang))
  if name ~= '' and title ~= '' then return name .. ': ' .. title end
  return name ~= '' and name or title
end

-- ---------------------------------------------------------------- the Memorial
function V.memorialFirsts(mem)
  local out = {}
  for _, e in ipairs(list(mem and mem.firsts)) do
    if type(e) == 'table' then
      out[#out + 1] = { title = str(e.t), text = str(e.n), when = V.dateText(e.at) }
    end
  end
  return out
end

function V.memorialRecords(mem)
  local out = {}
  for _, e in ipairs(list(mem and mem.recs)) do
    if type(e) == 'table' then
      local who = str(e.n) ~= '' and (str(e.n) .. (str(e.c) ~= '' and (', ' .. str(e.c)) or '')) or V.tr('a hero who keeps their name')
      out[#out + 1] = { title = str(e.t), text = str(e.v) .. ', ' .. who, when = V.dateText(e.at), hidden = str(e.n) == '' }
    end
  end
  return out
end

function V.memorialFalls(mem)
  local out = {}
  for _, e in ipairs(list(mem and mem.falls)) do
    if type(e) == 'table' then
      out[#out + 1] = { title = str(e.n),
        text = V.tr('level %d %s, %s', math.floor(num(e.l)), str(e.c) ~= '' and str(e.c) or V.tr('adventurer'), str(e.k)),
        when = V.dateText(e.at) }
    end
  end
  return out
end

-- the Memorial's sections (the list on the left of the Memorial tab)
function V.memorialSections(mem)
  local m = type(mem) == 'table' and mem or {}
  return {
    { id = 'choice', name = V.tr('Your choice'), sub = m.ask and V.tr('Your fall waits for an answer') or V.tr('Show me on the Memorial') },
    { id = 'firsts', name = V.tr('Realm firsts'), sub = V.tr('%d remembered', #V.memorialFirsts(m)) },
    { id = 'records', name = V.tr('Records'), sub = V.tr('%d remembered', #V.memorialRecords(m)) },
    { id = 'falls', name = V.tr('The fallen'), sub = V.tr('%d remembered', #V.memorialFalls(m)) },
  }
end

-- the request of the choice page (booleans only: the server refuses anything else)
function V.choiceRequest(records, fallen)
  return { records = records == true, fallen = fallen == true }
end
