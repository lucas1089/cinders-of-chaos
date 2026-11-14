-- Trainer DPS panel, pure parts (no UI calls): the settings, when the panel opens and closes, the numbers of the header,
-- the rows of the three tabs (skills, elements, party), the status line and the exported texts. Tested by
-- trainerdpslogic_test.lua (luajit and lua5.3). The server (trainer_meter_core.lua M.view) counts everything; this file
-- only reads its state. The number and time formats, the row icons and the bar colours are the DPS meter's
-- (game_dpsmeter dpsmath.lua), reached as DpsMath or modules.game_dpsmeter.DpsMath.
local function tr(s, ...) local g = (rawget(_G, 'tr') or (rawget(_G, 'ChaosLocale') or {}).tr) if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

TrainerDpsLogic = {}
local L = TrainerDpsLogic

L.TEXT_COLOR = '#d6c9ae'
L.DIM_COLOR = '#8c8070'
L.TABS = {
  { key = 'src', name = 'Skills', tip = 'Damage to the trainer by skill' },
  { key = 'el', name = 'Elements', tip = 'Damage to the trainer by element' },
  { key = 'party', name = 'Party', tip = 'The party members that hit this trainer' },
}
L.ELEMENT_COLORS = {
  physical = '#b0a090', fire = '#e0662a', earth = '#5aa03a', energy = '#b050d0', ice = '#5ac8e8', holy = '#e8d070',
  death = '#7a4a8a', drown = '#3a7ab0', lifedrain = '#c04a4a', manadrain = '#4a60c0',
}
L.DEFAULTS = { auto = true, keep = false, tab = 'src', closeAfter = 15 }
L.CLOSE_AFTER = { 5, 10, 15, 30, 60 }

local function dm()
  if DpsMath then return DpsMath end
  if modules and modules.game_dpsmeter then return modules.game_dpsmeter.DpsMath end
  return nil
end

local function num(v)
  v = tonumber(v)
  if v and v == v and v ~= math.huge and v ~= -math.huge then return v end
  return nil
end

local function short(n) local d = dm() if d then return d.short(n) end return tostring(math.floor(tonumber(n) or 0)) end
local function exact(n) local d = dm() if d then return d.exact(n) end return tostring(math.floor(tonumber(n) or 0)) end
local function clock(ms)
  local d = dm()
  if d then return d.duration(ms) end
  local s = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- ---------------------------------------------------------------- settings (g_settings node)
function L.sanitize(node)
  local out = {}
  for k, v in pairs(L.DEFAULTS) do out[k] = v end
  if type(node) ~= 'table' then return out end
  if type(node.auto) == 'boolean' then out.auto = node.auto end
  if type(node.keep) == 'boolean' then out.keep = node.keep end
  for _, t in ipairs(L.TABS) do
    if node.tab == t.key then out.tab = t.key end
  end
  local c = num(node.closeAfter)
  if c then out.closeAfter = math.floor(math.max(3, math.min(300, c))) end
  return out
end

function L.tab(key)
  for _, t in ipairs(L.TABS) do
    if t.key == key then return t end
  end
  return L.TABS[1]
end

-- ---------------------------------------------------------------- when the panel opens and closes
-- ctx = {visible, closeAt (ms or nil), sid (the session last seen)}; a state of the server. Returns
-- {open, closeAt, sid}: open = the panel should be shown (it may be shown already), closeAt = when it hides by itself
-- (nil: never), sid = the session now shown. A session that begins opens the panel (when "open by itself" is on; a panel
-- that is shown stays); a session that ended hides it closeAfter seconds later unless "keep open" is on; a state without a
-- session (`none`) changes nothing.
function L.onState(ctx, state, settings, now)
  local r = { open = false, closeAt = ctx.closeAt, sid = ctx.sid }
  if type(state) ~= 'table' or state.none then return r end
  r.sid = state.sid
  if state.act == 1 then
    r.closeAt = nil
    -- a closed panel opens for a NEW session only: closing it in the middle of one keeps it closed
    r.open = ctx.visible or (settings.auto and ctx.sid ~= state.sid)
  elseif state['end'] == 1 then
    r.open = ctx.visible
    if ctx.visible and not settings.keep and (ctx.sid ~= state.sid or ctx.closeAt == nil) then
      r.closeAt = now + settings.closeAfter * 1000
    end
    if settings.keep then r.closeAt = nil end
  else
    -- an empty session (after a reset): the panel stays as it is
    r.open = ctx.visible
    r.closeAt = nil
  end
  return r
end

-- the periodic check: does the panel hide now?
function L.shouldClose(closeAt, settings, now)
  return closeAt ~= nil and not settings.keep and now >= closeAt
end

-- seconds left before it hides, or nil
function L.secondsLeft(closeAt, now)
  if closeAt == nil then return nil end
  return math.max(0, math.ceil((closeAt - now) / 1000))
end

-- ---------------------------------------------------------------- the header
function L.profileText(state)
  local p = state and state.prof
  if type(p) ~= 'table' then return '' end
  local class = tr(tostring(p.c or 'normal'))
  if (tonumber(p.l) or 0) > 0 then
    return tr('Target: a %s monster of level %d', class, math.floor(tonumber(p.l)))
  end
  return tr('Target: a %s monster of your level', class)
end

-- the numbers of the panel: strings, ready to show
function L.stats(state)
  local s = state or {}
  local hits = tonumber(s.hits) or 0
  local crit = hits > 0 and math.floor(100 * (tonumber(s.crits) or 0) / hits + 0.5) or 0
  local biggest = short(s.max or 0)
  if hits > 0 and type(s.mxn) == 'string' and s.mxn ~= '' then biggest = biggest .. '  ' .. s.mxn end
  return {
    cur = short(s.cur or 0), avg = short(s.avg or 0), total = short(s.tot or 0), time = clock(s.dur or 0),
    biggest = biggest, hits = tr('%d hits, %d%% critical', hits, crit),
    exactCur = exact(s.cur or 0), exactAvg = exact(s.avg or 0), exactTotal = exact(s.tot or 0),
    exactMax = exact(s.max or 0),
  }
end

-- the line under the numbers: waiting, running, finished (with the seconds left before the panel hides)
function L.status(state, secondsLeft)
  if type(state) ~= 'table' or state.none then return tr('Hit a trainer to start.') end
  if state.empty == 1 then return tr('Reset. Hit the trainer to count again.') end
  if state.act == 1 then return tr('Counting. %d s of silence ends it.', math.floor(tonumber(state.e) or 10)) end
  if secondsLeft then return tr('Finished. This panel hides in %d s.', secondsLeft) end
  return tr('Finished. This is the last result.')
end

-- ---------------------------------------------------------------- the rows
local function pct(part, total)
  if not total or total <= 0 then return 0 end
  return math.floor(100 * part / total + 0.5)
end

-- the skills tab: [{name, kind, icon, total, pct, hits, critPct, avg, max, rate, frac, color}], largest first as the server sent them
function L.skillRows(state)
  local out = {}
  if type(state) ~= 'table' then return out end
  local total = tonumber(state.tot) or 0
  local dur = tonumber(state.dur) or 0
  local top = 0
  for _, r in ipairs(state.rows or {}) do top = math.max(top, tonumber(r.v) or 0) end
  local d = dm()
  for _, r in ipairs(state.rows or {}) do
    local v, h = tonumber(r.v) or 0, tonumber(r.h) or 0
    local name = tostring(r.n or '')
    if name == 'Others' or name == 'Other' then name = tr(name) end
    out[#out + 1] = {
      name = name, kind = r.t, icon = r.i, total = v, pct = pct(v, total), hits = h,
      critPct = h > 0 and math.floor(100 * (tonumber(r.c) or 0) / h + 0.5) or 0,
      avg = h > 0 and math.floor(v / h) or 0, max = tonumber(r.m) or 0,
      rate = dur > 0 and math.floor(v * 1000 / math.max(1000, dur)) or 0,
      frac = top > 0 and v / top or 0, color = d and d.barColor(r.t, 1) or '#6b6258',
    }
  end
  return out
end

-- the elements tab: [{name, element, total, pct, frac, color}]
function L.elementRows(state)
  local out = {}
  if type(state) ~= 'table' then return out end
  local total = tonumber(state.tot) or 0
  local top = 0
  for _, e in ipairs(state.el or {}) do top = math.max(top, tonumber(e[2]) or 0) end
  local d = dm()
  local names = d and d.ELEMENT_NAMES or {}
  for _, e in ipairs(state.el or {}) do
    local v = tonumber(e[2]) or 0
    out[#out + 1] = {
      name = tr(names[e[1]] or tostring(e[1])), element = e[1], total = v, pct = pct(v, total),
      frac = top > 0 and v / top or 0, color = L.ELEMENT_COLORS[e[1]] or '#6b6258',
    }
  end
  return out
end

-- the party tab: [{name, cur, tot, pct, frac, me}]
function L.partyRows(state)
  local out = {}
  if type(state) ~= 'table' then return out end
  local sum, top = 0, 0
  for _, m in ipairs(state.party or {}) do
    sum = sum + (tonumber(m.tot) or 0)
    top = math.max(top, tonumber(m.tot) or 0)
  end
  for _, m in ipairs(state.party or {}) do
    local t = tonumber(m.tot) or 0
    out[#out + 1] = { name = tostring(m.n or ''), cur = tonumber(m.cur) or 0, tot = t, pct = pct(t, sum),
      frac = top > 0 and t / top or 0, me = m.me == 1 }
  end
  return out
end

function L.hasParty(state)
  return type(state) == 'table' and type(state.party) == 'table' and #state.party > 1
end

-- ---------------------------------------------------------------- exports
-- several lines for the clipboard
function L.summary(state, maxRows)
  if type(state) ~= 'table' or state.none or (tonumber(state.hits) or 0) == 0 then return '' end
  local st = L.stats(state)
  local lines = {
    tr('Trainer DPS - %s (%s)', tostring(state.tn or ''), st.time),
    tr('DPS now %s, average %s, total %s, biggest hit %s', exact(state.cur), exact(state.avg), exact(state.tot), exact(state.max)),
  }
  local profile = L.profileText(state)
  if profile ~= '' then lines[#lines + 1] = profile end
  for i, r in ipairs(L.skillRows(state)) do
    if i > (maxRows or 10) + 1 then break end
    lines[#lines + 1] = tr('%2d. %s  %s  %s%%  hits %d  crit %d%%  avg %s  max %s', i, r.name, exact(r.total),
      tostring(r.pct), r.hits, r.critPct, exact(r.avg), exact(r.max))
  end
  local parts = {}
  for _, e in ipairs(L.elementRows(state)) do
    parts[#parts + 1] = string.format('%s %s%%', e.name, tostring(e.pct))
  end
  if #parts > 0 then lines[#lines + 1] = tr('Elements: ') .. table.concat(parts, ', ') end
  return table.concat(lines, '\n')
end

-- the first n bytes of s, never ending inside a UTF-8 character
local function cut(s, n)
  if #s <= n then return s end
  local c = s:sub(1, n)
  local i = #c
  while i > 0 and c:byte(i) >= 0x80 and c:byte(i) < 0xC0 do i = i - 1 end
  if i > 0 and c:byte(i) >= 0xC0 then
    local need = c:byte(i) >= 0xF0 and 4 or (c:byte(i) >= 0xE0 and 3 or 2)
    if #c - i + 1 < need then c = c:sub(1, i - 1) end
  end
  return c
end

-- one line for the chat input (the player sends it, or not): at most maxLen characters
function L.chatLine(state, maxLen)
  if type(state) ~= 'table' or state.none or (tonumber(state.hits) or 0) == 0 then return '' end
  maxLen = maxLen or 240
  local st = L.stats(state)
  local line = tr('[%s] %s, %s: %s DPS avg, %s DPS now, %s total, max %s', tr('Trainer'), tostring(state.tn or ''),
    st.time, short(state.avg), short(state.cur), short(state.tot), short(state.max))
  for _, r in ipairs(L.skillRows(state)) do
    local part = string.format(' | %s %s%%', r.name, tostring(r.pct))
    if #line + #part > maxLen then break end
    line = line .. part
  end
  return cut(line, maxLen)
end
