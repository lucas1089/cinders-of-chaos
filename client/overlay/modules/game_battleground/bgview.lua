-- Pure helpers of the battleground module (no client API; tested by bgview_test.lua with plain Lua).
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)
BgView = {}
local V = BgView

V.IMAGES = '/images/chaos/battleground/'
V.ROLE_NAMES = { tank = 'Tank', healer = 'Healer', dps = 'DPS' }
V.ROLE_COLORS = { tank = '#7fb8e8', healer = '#6fd8a8', dps = '#e8846a' }
V.RESULT_TEXT = { win = 'VICTORY', loss = 'DEFEAT', draw = 'DRAW' }
V.RESULT_COLOR = { win = '#f6cf72', loss = '#e03a1e', draw = '#d6c9ae' }
V.REASON_TEXT = { score = 'first to the goal', time = 'time ran out', forfeit = 'the other side left', stop = 'stopped by the staff' }
V.BRACKET_ORDER = { '1v1', '2v2', '3v3', 'bg' }

local function num(v, d) return tonumber(v) or d or 0 end

-- 75 -> "1:15"
function V.clock(s)
  s = math.max(0, math.floor(num(s)))
  return string.format('%d:%02d', math.floor(s / 60), s % 60)
end

-- 1234567 -> "1,234,567"
function V.number(n)
  local s = tostring(math.floor(num(n)))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''):gsub('^%-,', '-'))
end

-- a duration for waits and season ends: "45s", "3m", "2h 5m", "3d 4h", "2w 1d"
function V.span(s)
  s = math.max(0, math.floor(num(s)))
  if s < 60 then return s .. 's' end
  if s < 3600 then return math.floor(s / 60) .. 'm' end
  if s < 86400 then return string.format('%dh %dm', math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  if s < 7 * 86400 then return string.format('%dd %dh', math.floor(s / 86400), math.floor(s % 86400 / 3600)) end
  return string.format('%dw %dd', math.floor(s / 604800), math.floor(s % 604800 / 86400))
end

function V.delta(d)
  d = math.floor(num(d))
  return (d >= 0 and '+' or '') .. d
end

function V.result(r)
  return V.RESULT_TEXT[r] or tostring(r or '?'):upper(), V.RESULT_COLOR[r] or '#d6c9ae'
end

function V.tierImage(key)
  return V.IMAGES .. 'tier_' .. tostring(key or 'ashen')
end

function V.wellImage(owner)
  owner = num(owner)
  return V.IMAGES .. 'well_' .. ((owner == 1 or owner == 2) and owner or 0)
end

-- the tier key of a tier index from the preview list
function V.tierKey(tiers, index)
  local t = type(tiers) == 'table' and tiers[num(index, 1)] or nil
  return t and t.key or 'ashen'
end

-- one bracket card of the season tab / the queue tab: view = server ChaosPvpSeason.viewOf(...)[bracket]
function V.bracketCard(view, tiers, placementTotal)
  view = type(view) == 'table' and view or {}
  local c = { name = view.name or '?', rating = tostring(num(view.rating, 1500)) }
  c.record = string.format('%d-%d-%d', num(view.wins), num(view.losses), num(view.draws))
  if view.placed then
    c.tier = view.tierName or '?'
    c.color = view.color or '#d6c9ae'
    c.image = V.tierImage(V.tierKey(tiers, view.tier))
  else
    local left = num(view.placementLeft, num(placementTotal, 5))
    local total = num(placementTotal, 5)
    c.tier = tr('Placement %d/%d', total - left, total)
    c.color = '#8c8070'
    c.image = V.tierImage('ashen')
    c.rating = '?'
    c.unplaced = true
  end
  if view.decayIn and num(view.decayIn) > 0 then
    c.decay = tr('Decay in %s without a rated match', V.span(view.decayIn))
  end
  c.tooltip = tr('Season rating %d (deviation %d), peak %d, %d matches.', num(view.rating, 1500), num(view.rd),
    num(view.peak, num(view.rating, 1500)), num(view.matches))
  return c
end

-- the queue line: in the queue, in a match, deserter, or the estimate
function V.queueStatus(state, elapsed)
  state = type(state) == 'table' and state or {}
  elapsed = num(elapsed)
  if type(state.match) == 'table' then
    return tr('You are in a battleground match.'), '#f6cf72'
  end
  if num(state.deserter) - elapsed > 0 then
    return tr('Deserter: no queue for %s.', V.span(num(state.deserter) - elapsed)), '#e03a1e'
  end
  if type(state.queue) == 'table' then
    local q = state.queue
    local waited = num(q.waited) + elapsed
    local est = math.max(0, num(q.est) - elapsed)
    return tr('In the queue %s (%d players waiting). Estimated: %s', V.clock(waited), num(q.players),
      est > 0 and ('~' .. V.span(est)) or tr('any moment')), '#f6cf72'
  end
  if not state.bracket then
    return tr('You need level %d for the battleground.', num(state.minLevel, 100)), '#e03a1e'
  end
  return tr('%d waiting in your bracket. Estimated wait: ~%s', num(state.waiting), V.span(state.est)), '#d6c9ae'
end

-- the role buttons: the class's roles, the chosen one marked
function V.roleOptions(state)
  local out = {}
  local roles = type(state) == 'table' and type(state.roles) == 'table' and state.roles or { 'dps' }
  for _, r in ipairs(roles) do
    out[#out + 1] = { key = r, text = V.ROLE_NAMES[r] or r, color = V.ROLE_COLORS[r] or '#d6c9ae', chosen = r == state.role }
  end
  return out
end

-- the honor line of the window
function V.honorLine(state)
  state = type(state) == 'table' and state or {}
  return tr('Honor %s   (this week %s / %s)   Weekly first win: %s', V.number(state.honor),
    V.number(state.weekHonor), V.number(state.weekCap), state.firstWinDone and 'taken' or 'ready')
end

function V.recordLine(state)
  local r = type(state) == 'table' and type(state.record) == 'table' and state.record or {}
  return tr('Battlegrounds %d   W-L-D %d-%d-%d   Downs dealt %d   Wells taken %d', num(r.matches), num(r.wins),
    num(r.losses), num(r.draws), num(r.kills), num(r.captures))
end

-- a vendor row: {title, sub, button, can}
function V.vendorRow(o, honor)
  o = type(o) == 'table' and o or {}
  local r = { title = o.name or '?', button = V.number(o.cost) .. ' honor' }
  if o.owned then
    r.sub, r.can, r.button = tr('Unlocked for your account.'), false, tr('Owned')
  elseif num(honor) < num(o.cost) then
    r.sub, r.can = tr('You need %s more honor.', V.number(num(o.cost) - num(honor))), false
  else
    r.sub, r.can = o.kind == 'cosmetic' and tr('Cosmetic, account-wide.') or tr('Delivered to your backpack (inbox when full).'), true
  end
  return r
end

-- the season rewards preview: one row per tier
function V.rewardRows(tiers, seasonId)
  local out = {}
  for _, t in ipairs(type(tiers) == 'table' and tiers or {}) do
    local parts = {}
    if t.title then parts[#parts + 1] = tr('title "%s (S%d)"', t.title, num(seasonId)) end
    if t.frame then parts[#parts + 1] = tr('%s plate frame', t.frame) end
    local cos = type(t.cosmetics) == 'table' and #t.cosmetics or 0
    if cos > 0 then parts[#parts + 1] = cos .. (cos == 1 and ' cosmetic' or ' cosmetics') end
    parts[#parts + 1] = V.number(t.honor) .. ' honor'
    out[#out + 1] = { name = t.name, from = num(t.min) > 0 and (V.number(t.min) .. '+') or 'below ' .. V.number((tiers[2] or {}).min or 0),
      text = table.concat(parts, ', '), color = t.color or '#d6c9ae', image = V.tierImage(t.key) }
  end
  return out
end

-- ---------------------------------------------------------------- the match HUD
-- the score bars: percent of the goal
function V.scorePercent(score, goal)
  goal = math.max(1, num(goal, 1000))
  return math.min(100, math.floor(num(score) * 100 / goal))
end

-- a brazier: owner name and colour, "contested", or the capture progress towards a team
function V.brazierState(b, teams, colors)
  b = type(b) == 'table' and b or {}
  teams = type(teams) == 'table' and teams or { 'Team 1', 'Team 2' }
  colors = type(colors) == 'table' and colors or { '#ff9a3c', '#8fb8ff' }
  local owner, progress = num(b.owner), num(b.progress)
  local s = { name = b.name or '?', image = V.wellImage(owner) }
  if b.contested then
    s.text, s.color = 'contested', '#ff5050'
  elseif owner == 1 or owner == 2 then
    s.text, s.color = teams[owner], colors[owner]
    if (owner == 1 and progress < 100) or (owner == 2 and progress > -100) then
      s.text = s.text .. ' ' .. math.floor(math.abs(progress)) .. '%'
    end
  elseif progress ~= 0 then
    local t = progress > 0 and 1 or 2
    s.text, s.color = string.format('%d%% %s', math.floor(math.abs(progress)), teams[t]), colors[t]
  else
    s.text, s.color = 'neutral', '#8c8070'
  end
  return s
end

-- the centre of the HUD: the clock and what it counts
function V.hudCenter(d)
  d = type(d) == 'table' and d or {}
  if d.phase == 'prep' then
    return tostring(math.max(0, math.floor(num(d.left)))), tr('the wells open in')
  elseif d.phase == 'fight' then
    return V.clock(d.left), 'left'
  end
  return '-', 'over'
end

-- what the player sees under the HUD: downed (respawn wave), AFK warning
function V.hudNotice(d)
  d = type(d) == 'table' and d or {}
  if d.respawn then
    return tr('Downed: back with the next wave in %ds', math.max(0, math.floor(num(d.respawn)))), '#e03a1e'
  end
  if d.afk then
    return tr('Inactive: move or fight within %ds', math.max(0, math.floor(num(d.afk)))), '#ff5050'
  end
  return '', '#d6c9ae'
end

-- the scoreboard: rows split by team, own team first; every row's cells
function V.boardSides(rows, myTeam)
  local sides = { {}, {} }
  myTeam = num(myTeam, 1)
  for _, r in ipairs(type(rows) == 'table' and rows or {}) do
    local t = num(r.team, 1)
    local side = t == myTeam and 1 or 2
    table.insert(sides[side], {
      name = (r.name or '?') .. (r.left and ' (left)' or ''), role = V.ROLE_NAMES[r.role] or '', roleColor = V.ROLE_COLORS[r.role] or '#d6c9ae',
      kills = num(r.kills), assists = num(r.assists), downs = num(r.downs), captures = num(r.captures),
      damage = V.number(r.damage), healing = V.number(r.healing), honor = r.honor and V.number(r.honor) or '',
      left = r.left and true or false })
  end
  return sides
end

-- the end summary lines
function V.summary(d, myTeam)
  d = type(d) == 'table' and d or {}
  local title, color = V.result(d.result)
  local team = num(d.team, num(myTeam, 1))
  local score = type(d.score) == 'table' and d.score or { 0, 0 }
  local teams = type(d.teams) == 'table' and d.teams or { 'Team 1', 'Team 2' }
  local s = { title = title, color = color }
  s.score = string.format('%s %d  -  %d %s', teams[team] or '?', num(score[team]), num(score[3 - team]), teams[3 - team] or '?')
  s.reason = V.REASON_TEXT[d.reason] or tostring(d.reason or '')
  if d.rated == false then
    s.rating = 'Not rated'
    s.honor = ''
  else
    local se = type(d.season) == 'table' and d.season or nil
    if se then
      s.rating = tr('Season rating %d -> %d (%s)', num(se.before), num(se.after), V.delta(se.delta))
      if se.placed then
        s.rating = s.rating .. '  ' .. tostring(se.tierName or '')
      else
        s.rating = s.rating .. tr('  (placement: %d left)', num(se.placementLeft))
      end
    else
      s.rating = ''
    end
    s.honor = tr('Honor +%d%s', num(d.honor), d.firstWin and tr(' (first win of the week)') or '')
    if d.items and d.items ~= '' then s.honor = s.honor .. '  ' .. d.items end
  end
  return s
end

return BgView
