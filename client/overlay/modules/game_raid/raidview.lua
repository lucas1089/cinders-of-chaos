-- Pure helpers of the raid window and HUD (no client calls; tested by raidview_test.lua): the lockout rows, the saved
-- raids, the boss journal, the vendor rows, the HUD lines and the call-out colours.
-- Server messages (extended opcode 213, server/data/scripts/chaos/raid.lua):
--   info {name, minLevel, level, minPlayers, maxPlayers, lock = {bosses = [{k, n, l}], looted, total, reset}, saved =
--         [{id, killed = [bool], done, next, leader, members, cleared, open, inside, mine}], marks, kills, clears, best,
--         vendor = {marks, stock = [{k, n, kind, price, weekly, bought, can, level, rarity, mods, items, cid}]}, inRaid, pz}
--   journal {bosses = [{k, n, intro, roles, phases = [{n, at}], mech = [text], enrage, final, loot = {gold, items, gear,
--            gearRolls, gearLevel, unique, uniques, marks}}]}
--   hud {raid, id, boss, idx, total, done, killed, state = clear|idle|fight, hp, phase, phases, phaseName, enrage,
--        enraged, adds, totems, players, fallen, alerts = [text], stacks = {sunder, hexed}, hexed, trash}
--   alert {text, kind}, loot {boss, eligible, lines}, end {text}, msg {text, ok}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

RaidView = {}

local function num(v)
  v = tonumber(v)
  if v ~= v then return nil end
  return v
end

function RaidView.clock(secs)
  secs = math.max(0, math.floor(num(secs) or 0))
  return string.format('%d:%02d', math.floor(secs / 60), secs % 60)
end

-- seconds left now of a countdown that had `left` at `receivedAt`
function RaidView.left(left, receivedAt, now)
  return math.max(0, math.floor((num(left) or 0) - ((now or 0) - (receivedAt or 0))))
end

-- "2d 5h", "5h 12m", "12m" (the weekly reset)
function RaidView.resetText(secs)
  secs = math.max(0, math.floor(num(secs) or 0))
  local d, h, m = math.floor(secs / 86400), math.floor(secs / 3600) % 24, math.floor(secs / 60) % 60
  if d > 0 then return string.format('%dd %dh', d, h) end
  if h > 0 then return string.format('%dh %dm', h, m) end
  return string.format('%dm', m)
end

function RaidView.number(n)
  n = math.floor(num(n) or 0)
  local s = tostring(math.abs(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  if out:sub(1, 1) == ',' then out = out:sub(2) end
  return (n < 0 and '-' or '') .. out
end

-- ---------------------------------------------------------------- lockouts
-- one row per boss: {text, state, color}
function RaidView.lockRows(info)
  local out = {}
  local lock = type(info) == 'table' and type(info.lock) == 'table' and info.lock or {}
  for i, b in ipairs(type(lock.bosses) == 'table' and lock.bosses or {}) do
    local looted = b.l == true
    out[#out + 1] = { text = string.format('%d. %s', i, tostring(b.n or '?')), state = looted and tr('Looted this week') or tr('Loot available'),
      color = looted and '#8c8070' or '#9fd89f', looted = looted }
  end
  return out
end

function RaidView.lockSummary(info)
  local lock = type(info) == 'table' and type(info.lock) == 'table' and info.lock or {}
  return tr('%d of %d bosses looted this week. Lockouts reset in %s.', num(lock.looted) or 0,
    num(lock.total) or 0, RaidView.resetText(lock.reset))
end

-- ---------------------------------------------------------------- saved raids
-- {title, progress, next, action = 'continue' | 'join' | 'inside' | nil, color}
function RaidView.savedRow(s)
  local done, total = num(s.done) or 0, type(s.killed) == 'table' and #s.killed or 0
  local marks = {}
  for i = 1, total do marks[i] = s.killed[i] and 'X' or '-' end
  local row = { title = string.format('Raid #%d (%s)', num(s.id) or 0, tostring(s.leader or '?')),
    progress = string.format('%d / %d slain  [%s]', done, total, table.concat(marks)),
    next = s.cleared and 'Cleared' or ('Next: ' .. tostring(s.next or '?')), color = s.cleared and '#8c8070' or '#e8b84a' }
  if s.inside then
    row.action = 'inside'
  elseif s.open then
    row.action = 'join'
  elseif not s.cleared then
    row.action = 'continue'
  end
  return row
end

function RaidView.actionText(action)
  return ({ continue = 'Continue', join = 'Join', inside = 'Inside' })[action] or ''
end

-- the start button: {text, can, why}
function RaidView.startState(info)
  if type(info) ~= 'table' then return { text = 'Open New Raid', can = false } end
  if info.inRaid then return { text = 'In a raid', can = false, why = 'You are inside a raid.' } end
  if (num(info.level) or 0) < (num(info.minLevel) or 0) then
    return { text = 'Open New Raid', can = false, why = string.format('Level %d needed.', num(info.minLevel) or 0) }
  end
  return { text = 'Open New Raid', can = true,
    why = tr('Your party of %d-%d within range comes along (protection zone, out of combat).',
      num(info.minPlayers) or 5, num(info.maxPlayers) or 15) }
end

function RaidView.recordLine(info)
  if type(info) ~= 'table' then return '' end
  local best = num(info.best) or 0
  return tr('Sepulchre Marks: %s   Bosses looted: %d   Full clears: %d%s', RaidView.number(info.marks),
    num(info.kills) or 0, num(info.clears) or 0, best > 0 and (tr('   Best clear: %s', RaidView.clock(best))) or '')
end

-- ---------------------------------------------------------------- journal
-- the text blocks of one boss: {title, intro, roles, phases, mech = {..}, loot = {..}}
function RaidView.journalBoss(b, index)
  b = type(b) == 'table' and b or {}
  local phases = {}
  for _, p in ipairs(type(b.phases) == 'table' and b.phases or {}) do
    phases[#phases + 1] = string.format('%s (%d%%)', tostring(p.n or ''), num(p.at) or 0)
  end
  local mech = {}
  for _, m in ipairs(type(b.mech) == 'table' and b.mech or {}) do mech[#mech + 1] = '- ' .. tostring(m) end
  local l = type(b.loot) == 'table' and b.loot or {}
  local loot = {}
  loot[#loot + 1] = tr('%s gold to the bank, %d Sepulchre Marks', RaidView.number(l.gold), num(l.marks) or 0)
  for _, it in ipairs(type(l.items) == 'table' and l.items or {}) do
    loot[#loot + 1] = it.n and string.format('%d %s', num(it.count) or 0, tostring(it.n)) or
      RaidView.lootText(string.format('%d item %d', num(it.count) or 0, num(it.id) or 0))
  end
  local lv = type(l.gearLevel) == 'table' and l.gearLevel or {}
  loot[#loot + 1] = tr('%d gear rolls, item level %d-%d (%d base items)', num(l.gearRolls) or 0, num(lv[1]) or 0,
    num(lv[2]) or 0, type(l.gear) == 'table' and #l.gear or 0)
  local u = type(l.uniques) == 'table' and l.uniques or {}
  if #u > 0 then
    loot[#loot + 1] = tr('%s%% chance of a raid unique: %s', string.format('%.1f', (num(l.unique) or 0) / 100),
      table.concat(u, ', '))
  end
  return { title = string.format('%d. %s%s', index or 0, tostring(b.n or '?'), b.final and ' (final)' or ''),
    intro = tostring(b.intro or ''), roles = 'Roles: ' .. tostring(b.roles or ''),
    phases = tr('Phases: %s%s', table.concat(phases, ', '), tr('. Enrage at %s.', RaidView.clock(b.enrage))),
    mech = mech, loot = loot }
end

-- the item names the journal knows (orbs by server id); the rest stay "item <id>"
RaidView.ITEMS = { [29856] = 'Orbs of Upheaval', [29857] = 'Orbs of Fate', [29855] = 'Exalted Orb' }
function RaidView.lootText(line)
  return (tostring(line):gsub('item (%d+)', function(id)
    return RaidView.ITEMS[tonumber(id)] or ('item ' .. id)
  end))
end

-- ---------------------------------------------------------------- vendor
local RARITY = { 'Common', 'Uncommon', 'Magic', 'Rare', 'Legendary' } -- by rarity id (the vendor gear is 4, Rare)
function RaidView.vendorRow(e, marks)
  e = type(e) == 'table' and e or {}
  local sub
  if e.kind == 'gear' then
    sub = tr('%s, item level %d: %s', tr(RARITY[num(e.rarity) or 0] or 'Rare'), num(e.level) or 0,
      table.concat(type(e.mods) == 'table' and e.mods or {}, ', '))
  else
    local parts = {}
    for _, it in ipairs(type(e.items) == 'table' and e.items or {}) do
      parts[#parts + 1] = string.format('%d %s', num(it.c) or 0, tostring(it.n or ''))
    end
    sub = table.concat(parts, ', ')
  end
  local bought, weekly = num(e.bought) or 0, num(e.weekly) or 1
  local price = num(e.price) or 0
  local can = bought < weekly and (num(marks) or 0) >= price
  local button = bought >= weekly and tr('Sold out') or string.format('%d marks', price)
  return { name = tostring(e.n or '?'), sub = sub, limit = tr('%d / %d this week', bought, weekly),
    button = button, can = can }
end

-- ---------------------------------------------------------------- HUD
function RaidView.hudTitle(d)
  return string.format('%s #%d', tostring(d.raid or 'Raid'), num(d.id) or 0)
end

function RaidView.progress(d)
  local total = num(d.total) or 0
  if total <= 0 then return 0 end
  return math.floor((num(d.done) or 0) * 100 / total)
end

function RaidView.bossLine(d)
  if d.state == 'clear' then return tr('Every boss is slain.') end
  local who = string.format('%d. %s', num(d.idx) or 0, tostring(d.boss or '?'))
  if d.state == 'fight' then
    return string.format('%s - %d%%', who, num(d.hp) or 100)
  end
  if num(d.trash) then
    return tr('%s - clear the corridor (%d left)', who, num(d.trash))
  end
  return who .. ' awaits'
end

function RaidView.phaseLine(d)
  if d.state ~= 'fight' or not d.phase then return '' end
  return string.format('Phase %d of %d: %s', num(d.phase) or 1, num(d.phases) or 1, tostring(d.phaseName or ''))
end

function RaidView.enrageText(d, left)
  if d.state ~= 'fight' then return '', '#f4d27a' end
  if d.enraged then return 'ENRAGED', '#ff4030' end
  return 'Enrage ' .. RaidView.clock(left), (left or 0) <= 60 and '#ff9a30' or '#f4d27a'
end

function RaidView.countsLine(d)
  local parts = { string.format('Raiders %d', num(d.players) or 0) }
  if num(d.fallen) then parts[#parts + 1] = string.format('fallen %d', num(d.fallen)) end
  if num(d.adds) then parts[#parts + 1] = string.format('adds %d', num(d.adds)) end
  if num(d.totems) then parts[#parts + 1] = string.format('effigies %d', num(d.totems)) end
  return table.concat(parts, ', ')
end

-- the player's own marks: "Sundered 3", "Hexed 2", "HEX 5s"
function RaidView.stacksLine(d)
  local s = type(d.stacks) == 'table' and d.stacks or {}
  local parts = {}
  if (num(s.sunder) or 0) > 0 then parts[#parts + 1] = tr('Sundered x%s', num(s.sunder)) end
  if (num(s.hexed) or 0) > 0 then parts[#parts + 1] = tr('Hexed x%s', num(s.hexed)) end
  if num(d.hexed) then parts[#parts + 1] = tr('WITHERING HEX %ds: cleanse!', num(d.hexed)) end
  return table.concat(parts, '   ')
end

RaidView.ALERT_COLORS = { mech = '#f6cf72', tank = '#ff9a30', swap = '#9fd8ff', fail = '#ff4030', phase = '#e8b84a',
  pull = '#ff7a2a', kill = '#7fd07f', wipe = '#ff4030', fall = '#c8a0a0', door = '#9fd89f' }
function RaidView.alertColor(kind)
  return RaidView.ALERT_COLORS[kind] or '#f6cf72'
end

-- seconds a call-out stays on screen
function RaidView.alertSeconds(kind)
  if kind == 'kill' or kind == 'wipe' or kind == 'pull' then return 6 end
  return 4
end

function RaidView.lootSummary(d)
  if not d.eligible then
    return tr('%s slain. You looted it already this week: no spoils until the reset.', tostring(d.boss or '?'))
  end
  local lines = {}
  for _, l in ipairs(type(d.lines) == 'table' and d.lines or {}) do lines[#lines + 1] = tostring(l) end
  return tr('Spoils of %s: %s', tostring(d.boss or '?'), table.concat(lines, ', '))
end
