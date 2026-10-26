-- luajit topbarunlockslogic_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'topbarunlockslogic.lua')
local L = ChaosTopBarUnlocksLogic
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local ENTRIES = {
  { key = 'bounty', level = 8, menu = 'Bounty Board' }, { key = 'passive', level = 12, menu = 'Passive Tree' },
  { key = 'events', level = 30, menu = 'Events' }, { key = 'arena', level = 50, menu = 'Arena' },
}
local function state(unlocked, seen, nextEntry, extra)
  local s = L.newState()
  local data = { entries = ENTRIES, unlocked = unlocked or {}, seen = seen or {}, next = nextEntry }
  for k, v in pairs(extra or {}) do data[k] = v end
  return L.apply(s, data)
end

-- before the server's state: the whole menu
local s = L.newState()
eq(L.status(s, 'Arena'), 'open', 'no state yet')
eq(L.blockedLevel(s, 'Arena'), nil, 'no hotkey is blocked before the state')

-- unlocked entries open, the next one locked with its level, the rest hidden, entries the table does not name open
s = state({ 'bounty' }, {}, { key = 'passive', level = 12 })
eq(L.status(s, 'Bounty Board'), 'open')
do local st, lv = L.status(s, 'Passive Tree'); eq(st, 'locked'); eq(lv, 12) end
do local st, lv = L.status(s, 'Events'); eq(st, 'hidden'); eq(lv, 30) end
eq(L.status(s, 'Arena'), 'hidden')
eq(L.status(s, 'Skills'), 'open', 'an entry the table does not name')
eq(L.blockedLevel(s, 'Passive Tree'), 12, 'a locked entry blocks its hotkey')
eq(L.blockedLevel(s, 'Events'), 30, 'a hidden entry blocks its hotkey too')
eq(L.blockedLevel(s, 'Bounty Board'), nil)
eq(L.blockedLevel(s, 'Skills'), nil)

-- the whole menu: the player's option and the server's `all`
s.showAll = true
eq(L.status(s, 'Events'), 'open', 'option: the whole menu'); eq(L.blockedLevel(s, 'Events'), nil)
s.showAll = false
eq(L.status(state({}, {}, nil, { all = true }), 'Events'), 'open', 'server: all')

-- the badge: unlocked and not opened
s = state({ 'bounty', 'passive' }, { 'bounty' }, { key = 'events', level = 30 })
eq(L.isNew(s, 'Bounty Board'), false); eq(L.isNew(s, 'Passive Tree'), true); eq(L.isNew(s, 'Events'), false, 'locked is not new')
eq(L.isNew(s, 'Skills'), false)
eq(L.markSeen(s, 'Passive Tree'), 'passive', 'the key to tell the server')
eq(L.isNew(s, 'Passive Tree'), false); eq(L.markSeen(s, 'Passive Tree'), nil, 'once')
eq(L.markSeen(s, 'Events'), nil, 'a locked entry is not seen'); eq(L.markSeen(s, 'Skills'), nil)

-- a new unlock: open at once, with the badge, no longer next
s = state({ 'bounty' }, { 'bounty' }, { key = 'passive', level = 12 })
L.markUnlocked(s, 'passive')
eq(L.status(s, 'Passive Tree'), 'open'); eq(L.isNew(s, 'Passive Tree'), true); eq(s.next, nil)
L.markUnlocked(s, 'arena')
eq(s.next, nil); eq(L.status(s, 'Arena'), 'open')
-- a state replaces the old one
L.apply(s, { entries = ENTRIES, unlocked = { 'bounty' }, seen = {}, next = { key = 'passive', level = 12 } })
eq(L.status(s, 'Arena'), 'hidden', 'replaced'); eq(L.status(s, 'Passive Tree'), 'locked')
L.apply(s, { entries = ENTRIES, unlocked = { 'bounty', 'passive', 'events', 'arena' }, seen = {} })
eq(s.next, nil, 'no next when all are unlocked')

-- texts
local tr = function(t) return t end
local pt = function(t)
  return ({ ['Level %d'] = 'Nível %d', ['Unlocks at level %d'] = 'Abre no nível %d', ['New: %s!'] = 'Novo: %s!', ['New'] = 'Novo' })[t] or t
end
eq(L.levelLabel(12, tr), 'Level 12'); eq(L.levelLabel(12, pt), 'Nível 12')
eq(L.unlocksAt(100, tr), 'Unlocks at level 100'); eq(L.unlocksAt(100, pt), 'Abre no nível 100')
eq(L.screenText('Rifts', tr), 'New: Rifts!'); eq(L.screenText('Fendas', pt), 'Novo: Fendas!')
eq(L.rowText('Arena', 'locked', 50, false, tr), 'Arena  Level 50')
eq(L.rowText('Arena', 'open', 50, true, tr), 'Arena  New'); eq(L.rowText('Arena', 'open', 50, true, pt), 'Arena  Novo')
eq(L.rowText('Arena', 'open', 50, false, tr), 'Arena')

-- the announcement
local a = L.announcement({ key = 'rifts', menu = 'Rifts', title = 'Fendas', level = 100, why = { 'one', 'two' } })
eq(a.title, 'Fendas'); eq(a.line1, 'one'); eq(a.line2, 'two'); eq(a.level, 100); eq(a.menu, 'Rifts')
eq(L.announcement({ key = 'x' }), nil, 'no title'); eq(L.announcement('x'), nil)
eq(L.announcement({ key = 'x', title = 'T' }).line2, '', 'missing lines are empty')
eq(L.WINDOW_SECONDS > 0, true)

print('topbarunlockslogic_test: ' .. n .. ' checks ok')
