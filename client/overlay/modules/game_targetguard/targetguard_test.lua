-- luajit targetguard_test.lua && lua5.3 targetguard_test.lua (CI runs it from the repo root)
-- A mock of the helper's and the battle list's targeting choice (base patch 0112, ChaosTargetGuard).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'targetguard.lua')
local G = ChaosTargetGuard
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function creature(id, ctype)
  return {id = id, getId = function(self) return self.id end, getType = function() return ctype end}
end
local wolf = creature(1, 1) -- a wild monster
local mine = creature(2, 3) -- my own risen warrior
local theirs = creature(3, 4) -- another player's summon
local player = creature(4, 0)

eq(G.isOwnSummon(mine), true, 'own summon')
eq(G.isOwnSummon(theirs), false, 'another player\'s summon is not mine')
eq(G.isSummon(theirs), true, 'another player\'s summon is a summon')
eq(G.isSummon(wolf), false, 'a monster is no summon')
eq(G.isOwnSummon({}), false, 'no getType: not a summon')
eq(G.isOwnSummon(nil), false, 'nil')

-- the lock: never on my own summon; a monster, a player (PvP) or another player's summon is kept
eq(G.keepLock(mine), false, 'lock on own summon dropped')
eq(G.keepLock(wolf), true, 'lock on a monster kept')
eq(G.keepLock(player), true, 'lock on a player kept')
eq(G.keepLock(theirs), true, 'lock on another player\'s summon kept')
eq(G.keepLock(nil), false, 'no creature')

-- the re-send loop: a lock the server keeps refusing is dropped after 3 re-sends within 3 s
local s = {id = 0, sends = {}}
eq(G.lockAction(s, 7, 7, 0), 'keep', 'attacking the lock')
eq(G.lockAction(s, 7, 0, 100), 'attack', 'refused once: send again')
eq(G.lockAction(s, 7, 7, 150), 'keep', 'the client shows the attack until the cancel arrives')
eq(G.lockAction(s, 7, 0, 300), 'attack', 'refused twice')
eq(G.lockAction(s, 7, 0, 500), 'attack', 'refused three times')
eq(G.lockAction(s, 7, 0, 700), 'drop', 'refused again: the lock goes')
eq(s.id, 0, 'state cleared')
-- a target that left the view now and then is re-attacked: re-sends far apart never add up
local t = {id = 0, sends = {}}
for i = 1, 10 do
  eq(G.lockAction(t, 9, 0, i * 4000), 'attack', 'a re-send every 4 s, #' .. i)
end
-- a new lock starts a new count
local u = {id = 0, sends = {}}
G.lockAction(u, 5, 0, 0); G.lockAction(u, 5, 0, 10); G.lockAction(u, 5, 0, 20)
eq(G.lockAction(u, 6, 0, 30), 'attack', 'another lock: its own count')
eq(G.lockAction(u, 0, 0, 40), 'keep', 'no lock')

-- the battle list's attack next / previous: never my own summon
local list = G.attackCycle({mine, wolf, theirs, player})
eq(#list, 3, 'own summon left out')
eq(list[1], wolf, 'the monster comes first')
eq(list[2], theirs, 'another player\'s summon stays (PvP)')
eq(#G.attackCycle(nil), 0, 'nil list')

print(string.format('targetguard_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
