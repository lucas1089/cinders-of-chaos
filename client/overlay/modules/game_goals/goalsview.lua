-- Next Goals: the pure parts of the panel and the tracker (no client API), tested by goalsview_test.lua.
-- Server: server/data/scripts/chaos/goals.lua (and ascension_tracker.lua), extended opcode 178 (JSON {action, data}):
--   goals {header = {level, done, total, season, more, next, nextName,
--                    band = {key, name, text, from, to, index, count}},
--          goals = [row], upcoming = [row], gear = [{text, where}], hunts = [{id, name, lo, hi, where}], hereWhere}
--     row = {key, level, state = open | done | locked, title, why, effort, where, progress, target, reward}
--     where = {k = window | info | tasks | finder | npc | temple | hunts | plan | room, m, f, page, q, id, pos, label}
--   tracker {rows = [{key, title, progress, target}]}
--   ascension {rows = [{key, title, progress, target, state}]}
--   spellquest {rows = [{key, title, progress, target, state}]}
--   done {text}
-- The window code (goals.lua) keeps one GoalsView state and draws from it.
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

GoalsView = {}
local V = GoalsView

V.STATE_COLOR = { open = '#f6cf72', done = '#7fc86a', locked = '#6b6258' }

local function list(value)
  local out = {}
  if type(value) == 'table' then
    for _, v in ipairs(value) do
      if type(v) == 'table' then out[#out + 1] = v end
    end
  end
  return out
end

local function num(v, d)
  return tonumber(v) or d or 0
end

function V.new()
  return { header = nil, goals = {}, upcoming = {}, gear = {}, hunts = {}, here = nil, tracker = {}, ascension = {}, spellquest = {} }
end

function V.onGoals(st, data)
  data = type(data) == 'table' and data or {}
  st.header = type(data.header) == 'table' and data.header or nil
  st.goals = list(data.goals)
  st.upcoming = list(data.upcoming)
  st.gear = list(data.gear)
  st.hunts = list(data.hunts)
  st.here = type(data.hereWhere) == 'table' and data.hereWhere or nil
  return st
end

function V.onTracker(st, data)
  st.tracker = list(type(data) == 'table' and data.rows or nil)
  return st
end

-- ascension {rows = [{key, title, progress, target, state = open | done}]}: the steps of the ascension quest (server
-- ascension_tracker.lua); no rows hides the section
function V.onAscension(st, data)
  st.ascension = list(type(data) == 'table' and data.rows or nil)
  return st
end

-- spellquest {rows = [...]}: the steps of the line spell quest the character is on (server spellquest_tracker.lua); same
-- rows as the ascension section (V.ascensionLine draws them); no rows hides the section
function V.onSpellQuest(st, data)
  st.spellquest = list(type(data) == 'table' and data.rows or nil)
  return st
end

-- "Level 300-499: World bosses" / "Level 2000+: The apex"
function V.headerLine(h)
  if not h or type(h.band) ~= 'table' then return tr('Next Goals') end
  local b = h.band
  if b.to then
    return tr('Level %d-%d: %s', num(b.from, 1), num(b.to), tostring(b.name or ''))
  end
  return tr('Level %d+: %s', num(b.from, 1), tostring(b.name or ''))
end

function V.summaryLine(h)
  if not h then return '' end
  local parts = { tr('Goals done: %d / %d', num(h.done), num(h.total)) }
  if h.next then
    parts[#parts + 1] = tr('Next band at level %d: %s', num(h.next), tostring(h.nextName or ''))
  end
  return table.concat(parts, '   ')
end

-- the band strip: "4 / 13" bands, a percent of the way through the game's bands
function V.bandPercent(h)
  if not h or type(h.band) ~= 'table' then return 0 end
  local i, n = num(h.band.index, 1), math.max(1, num(h.band.count, 1))
  return math.floor(i * 100 / n)
end

-- one goal row: text lines, the bar, the button
function V.goalRow(r)
  local target = math.max(1, num(r.target, 1))
  local p = math.max(0, math.min(target, num(r.progress)))
  local out = { title = tostring(r.title or '?'), why = tostring(r.why or ''), effort = tostring(r.effort or ''),
    reward = '', state = r.state or 'open', color = V.STATE_COLOR[r.state or 'open'] or V.STATE_COLOR.open }
  if r.state == 'locked' then
    out.percent, out.label = 0, tr('Unlocks at level %d', num(r.level))
  elseif r.state == 'done' then
    out.percent, out.label = 100, tr('Done')
  else
    out.percent = math.floor(p * 100 / target)
    out.label = target == 1 and tr('Not yet') or string.format('%d / %d', p, target)
  end
  if r.reward and r.reward ~= '' and r.state ~= 'done' then
    out.reward = tr('Reward: %s', tostring(r.reward))
  end
  out.button = (r.state == 'open' and type(r.where) == 'table') and V.whereButton(r.where) or nil
  return out
end

-- the text of a "where" button
function V.whereButton(w)
  if type(w) ~= 'table' then return nil end
  if w.k == 'window' or w.k == 'info' then return tr('Open') end
  if w.k == 'tasks' then return tr('Kill Tasks') end
  if w.k == 'finder' then return tr('Item Finder') end
  if type(w.pos) == 'table' then return tr('Show on map') end
  if w.k == 'hunts' then return tr('Bestiary') end
  return nil
end

-- what a "where" button does (goals.lua runs it):
--   {call = 'module.function', args = {...}}   a window
--   {map = pos, label}                         a mark on the map
--   nil                                        nothing to do
function V.action(w)
  if type(w) ~= 'table' then return nil end
  if w.k == 'window' and type(w.m) == 'string' and type(w.f) == 'string' then
    return { call = w.m .. '.' .. w.f, args = {} }
  elseif w.k == 'info' and type(w.page) == 'string' then
    return { call = 'game_chaosinfo.openPage', args = { w.page } }
  elseif w.k == 'tasks' then
    return { call = 'game_bestiary.showTasks', args = {} }
  elseif w.k == 'finder' and tonumber(w.id) then
    return { call = 'game_itemfinder.open', args = { tonumber(w.id) } }
  end
  local pos = type(w.pos) == 'table' and w.pos or nil
  if pos and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z) then
    return { map = { x = tonumber(pos.x), y = tonumber(pos.y), z = tonumber(pos.z) }, label = tostring(w.label or '') }
  end
  if w.k == 'hunts' then
    return { call = 'game_bestiary.show', args = {} }
  end
  return nil
end

function V.huntLine(h)
  return tr('%s (levels %d-%d)', tostring(h.name or h.id or '?'), num(h.lo), num(h.hi))
end

function V.upcomingLine(r)
  return tr('Level %d: %s', num(r.level), tostring(r.title or '?'))
end

-- the tracker: "Defeat a world boss" and "0 / 1"
function V.trackerLine(r)
  local target = math.max(1, num(r.target, 1))
  local p = math.max(0, math.min(target, num(r.progress)))
  local count = target == 1 and '' or string.format('  %d/%d', p, target)
  return tostring(r.title or '?') .. count, math.floor(p * 100 / target)
end

-- an ascension row for the tracker: text (the count is shown when there are several steps, "Done" once finished),
-- the bar percent and the colour of the text
function V.ascensionLine(r)
  local target = math.max(1, num(r.target, 1))
  local p = math.max(0, math.min(target, num(r.progress)))
  local title = tostring(r.title or '?')
  if r.state == 'done' or p >= target then
    return title .. '  ' .. tr('Done'), 100, V.STATE_COLOR.done
  end
  local count = target == 1 and '' or string.format('  %d/%d', p, target)
  return title .. count, math.floor(p * 100 / target), V.STATE_COLOR.open
end

-- a tracker line broken into lines of at most `width` characters at the spaces (a word longer than that gets its own
-- line), so the whole goal shows in the narrow tracker. Returns the text with newlines and the line count.
function V.wrapLine(text, width)
  text = tostring(text or '')
  width = math.max(1, width or 28)
  local lines, cur = {}, ''
  for word in text:gmatch('%S+') do
    if cur == '' then
      cur = word
    elseif #cur + 1 + #word <= width then
      cur = cur .. ' ' .. word
    else
      lines[#lines + 1] = cur
      cur = word
    end
  end
  if cur ~= '' or #lines == 0 then lines[#lines + 1] = cur end
  return table.concat(lines, '\n'), #lines
end

function V.doneText(d)
  if type(d) ~= 'table' then return '' end
  return tr('Goal done: %s', tostring(d.text or ''))
end

-- "and 3 more from earlier levels"
function V.moreLine(h)
  local n = h and num(h.more) or 0
  if n <= 0 then return '' end
  return tr('and %d more from earlier levels', n)
end

return V
