-- luajit helper_follow_test.lua && lua5.3 helper_follow_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_logic.lua')
dofile(dir .. 'helper_ally.lua')
dofile(dir .. 'helper_follow.lua')
local F = ChaosHelperFollow
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local me = { x = 100, y = 100, z = 7 }
local function player(id, name, x, y, shield, z)
  return { id = id, name = name, position = { x = x, y = y, z = z or 7 }, shield = shield or 0, isSelf = false }
end
local ann = player(10, 'Ann', 103, 100)
local bob = player(11, 'Bob Smith', 105, 101, 4) -- a yellow shield: the party leader
local players = { { id = 1, name = 'Me', position = me, isSelf = true, shield = 4 }, ann, bob, player(12, 'Cy', 102, 100, 3) }

-- ---------------------------------------------------------------- who is the leader
eq(F.leaderOf({ mode = 'name', name = 'ann' }, players), ann, 'a friend by name, any case')
eq(F.leaderOf({ mode = 'name', name = ' Bob  Smith ' }, players), bob, 'a name with spaces')
eq(F.leaderOf({ mode = 'name', name = 'Dan' }, players), nil, 'a friend who is not in view')
eq(F.leaderOf({ mode = 'name', name = '' }, players), nil, 'no name, no leader')
eq(F.leaderOf({ mode = 'name', name = 'Me' }, players), nil, 'never yourself')
eq(F.leaderOf({ mode = 'name', name = 'A"; say' }, players), nil, 'a bad name matches nobody')
eq(F.leaderOf({ mode = 'leader' }, players), bob, 'the party leader is the yellow shield')
eq(F.leaderOf({ mode = 'leader' }, { ann }), nil, 'no leader in view')
eq(F.leaderOf(nil, players), nil, 'no config')

-- ---------------------------------------------------------------- the decision
local function input(over)
  local t = { helperOn = true, pz = false, leader = ann, from = me, following = nil, now = 1000 }
  for k, v in pairs(over or {}) do t[k] = v end
  return t
end
local cfg = { enabled = true, mode = 'name', name = 'Ann', distance = 1 }

local st = F.newState()
local act, why = F.decide({ enabled = false }, st, input())
eq(act, nil, 'off: nothing')
eq(why, 'off', 'off: reason')
act, why = F.decide(cfg, st, input({ helperOn = false }))
eq(why, 'helperoff', 'the helper off')
act, why = F.decide(cfg, st, input({ pz = true }))
eq(act, nil, 'a protection zone pauses it')
eq(why, 'pz', 'protection zone reason')

-- asks to follow, at most every 250 ms
st = F.newState()
eq((F.decide(cfg, st, input({ now = 1000 }))), 'follow', 'follows a leader in view')
eq((F.decide(cfg, st, input({ now = 1100 }))), nil, 'not again within 250 ms')
eq((F.decide(cfg, st, input({ now = 1300 }))), 'follow', 'again after the gap if no follow started')

-- following the leader: nothing to do
st = F.newState()
F.decide(cfg, st, input())
act, why = F.decide(cfg, st, input({ following = 10, now = 2000 }))
eq(act, nil, 'already following')
eq(why, 'following', 'following reason')
eq(st.fails, 0, 'a follow that started resets the failures')

-- adjacent with distance 1: a follow is not needed
act, why = F.decide(cfg, F.newState(), input({ leader = player(10, 'Ann', 101, 100) }))
eq(act, nil, 'next to the leader')
eq(why, 'adjacent', 'adjacent reason')

-- another creature followed by hand is left alone
act, why = F.decide(cfg, F.newState(), input({ following = 99 }))
eq(act, nil, 'a follow the player chose is left alone')
eq(why, 'other', 'other reason')
-- one the helper started is taken over
st = F.newState()
F.decide(cfg, st, input())
eq((F.decide(cfg, st, input({ following = 99, now = 2000 }))), 'follow', 'our own follow of someone else is corrected')

-- the leader leaves the screen or the floor: let go, never chase
st = F.newState()
F.decide(cfg, st, input())
act, why = F.decide(cfg, st, input({ following = 10, leader = false, now = 2000 }))
eq(act, 'release', 'out of view: our follow is let go')
eq(why, 'away', 'away reason')
eq((F.decide(cfg, st, input({ following = nil, leader = false, now = 2500 }))), nil, 'and nothing after')
st = F.newState()
F.decide(cfg, st, input())
act, why = F.decide(cfg, st, input({ following = 10, leader = player(10, 'Ann', 103, 100, 0, 6), now = 2000 }))
eq(act, 'release', 'another floor: let go')
eq(why, 'away', 'another floor reason')
act, why = F.decide(cfg, F.newState(), input({ leader = player(10, 'Ann', 103, 100, 0, 8) }))
eq(act, nil, 'another floor: no follow asked')
act, why = F.decide(cfg, F.newState(), input({ leader = player(10, 'Ann', 120, 100) }))
eq(act, nil, 'beyond the screen: no follow asked')
-- a follow the player started is not let go
st = F.newState()
act = F.decide(cfg, st, input({ following = 10, leader = false }))
eq(act, nil, 'a follow the helper did not start is not let go')

-- turned off while following: let go once
st = F.newState()
F.decide(cfg, st, input())
act, why = F.decide({ enabled = false }, st, input({ following = 10 }))
eq(act, 'release', 'switched off: our follow is let go')
eq((F.decide({ enabled = false }, st, input({ following = 10 }))), nil, 'and only once')

-- distance 3: walks until the leader is within 3, then lets go; takes up again at 5
local far = { enabled = true, mode = 'name', name = 'Ann', distance = 3 }
st = F.newState()
eq((F.decide(far, st, input({ leader = player(10, 'Ann', 106, 100) }))), 'follow', 'far: follow')
act, why = F.decide(far, st, input({ leader = player(10, 'Ann', 103, 100), following = 10, now = 2000 }))
eq(act, 'release', 'close enough: let go')
eq(why, 'near', 'near reason')
eq((F.decide(far, st, input({ leader = player(10, 'Ann', 104, 100), now = 3000 }))), nil, 'one tile farther: still no follow')
eq((F.decide(far, st, input({ leader = player(10, 'Ann', 105, 100), now = 4000 }))), 'follow', 'two tiles farther: follow again')

-- a leader behind a wall: a few asks, then a pause
st = F.newState()
local asks, pauses = 0, 0
for i = 1, 80 do
  local a2, w2 = F.decide(cfg, st, input({ now = 1000 + i * 300 }))
  if a2 == 'follow' then asks = asks + 1 end
  if w2 == 'giveup' then pauses = pauses + 1 end
end
eq(asks <= 5 * 5, true, 'a leader who cannot be reached costs few asks (' .. asks .. ')')
eq(pauses >= 3, true, 'and the helper backs off')
eq((F.decide(cfg, st, input({ now = 10 }))), nil, 'no ask during the hold')

-- a distance out of range is clamped
eq((F.decide({ enabled = true, mode = 'name', name = 'Ann', distance = 99 }, F.newState(),
  input({ leader = player(10, 'Ann', 103, 100) }))), nil, 'distance clamped to 5: three tiles is near enough')

if fails > 0 then os.exit(1) end
print('helper_follow_test: ok')
