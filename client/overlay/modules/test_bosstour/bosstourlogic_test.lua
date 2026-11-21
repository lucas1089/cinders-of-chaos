-- run from the repository root: luajit client/overlay/modules/test_bosstour/bosstourlogic_test.lua
dofile('client/overlay/modules/test_bosstour/bosstourlogic.lua')
local L = ChaosBossTourLogic
local n, bad = 0, 0
local function check(c, what) n = n + 1; if not c then bad = bad + 1; print('FAIL ' .. what) end end
local function env(t) return function(k) return t[k] end end

local base = {CHAOS_BOSSTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'p w', CHAOS_LIVE_CHARACTER = 'Live Aldric A',
  CHAOS_BOSSTOUR_FOLLOW = 'Tester Aka, Tester Bel,Tester Cor'}
local function with(extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- the environment
local cfg = L.parseEnv(env(base))
check(cfg and cfg.account == 'a1' and cfg.password == 'p w' and cfg.character == 'Live Aldric A', 'armed with account, password and character')
check(cfg.boss == 'Malgrath' and cfg.seconds == 480 and cfg.waitSeconds == 7200, 'defaults: Malgrath, 480 s of fight, 7200 s of waiting')
check(#cfg.follow == 3 and cfg.follow[1] == 'Tester Aka' and cfg.follow[2] == 'Tester Bel' and cfg.follow[3] == 'Tester Cor', 'the party names are split and trimmed')
local c0, why0 = L.parseEnv(env(with({CHAOS_BOSSTOUR = false})))
check(c0 == nil and why0 == 'off', 'no switch: off, whatever else is set')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR = '0'}))) == nil and L.parseEnv(env(with({CHAOS_BOSSTOUR = 'yes'}))) == nil, 'only 1 arms it')
local c1, why1 = L.parseEnv(env(with({CHAOS_LIVE_PASSWORD = false})))
check(c1 == nil and why1:find('password', 1, true), 'no password: refused with the reason')
local c2, why2 = L.parseEnv(env(with({CHAOS_BOSSTOUR_FOLLOW = ' , ,'})))
check(c2 == nil and why2:find('follow', 1, true), 'no party names: refused')
check(L.parseEnv(nil) == nil and L.parseEnv(function() error('boom') end) == nil, 'no getenv or one that throws: off')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR_SECONDS = '600'}))).seconds == 600, 'the fight seconds come from the environment')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR_SECONDS = '5000'}))).seconds == L.MAX_SECONDS, 'the fight seconds stop at the maximum (900)')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR_SECONDS = '2'}))).seconds == L.MIN_SECONDS, 'and at the minimum')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR_SECONDS = 'abc'}))).seconds == 480, 'not a number: the default')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR_WAIT = '999999'}))).waitSeconds == L.MAX_WAIT, 'the wait stops at its maximum')
check(L.parseEnv(env(with({CHAOS_BOSSTOUR_BOSS = 'Vhoss'}))).boss == 'Vhoss', 'another boss')
check(L.MAX_SECONDS == 900 and L.DEFAULT_SECONDS == 480, 'the limits of the task: default 480 s, at most 900 s')

-- the arena: the grid of pinnacle_config.lua (a python test holds these numbers to the config)
check(L.inArena({x = 11520, y = 10112, z = 7}) and L.inArena({x = 11711, y = 10207, z = 7}), 'the corners of the grid are inside')
check(not L.inArena({x = 11519, y = 10112, z = 7}) and not L.inArena({x = 11712, y = 10112, z = 7}), 'one tile west or east is outside')
check(not L.inArena({x = 11600, y = 10111, z = 7}) and not L.inArena({x = 11600, y = 10208, z = 7}), 'one tile north or south is outside')
check(not L.inArena({x = 11600, y = 10150, z = 6}) and not L.inArena(nil) and not L.inArena({x = 32929, y = 32073, z = 7}), 'another floor, no position, the temple')

-- the lines of /instances
local run = L.parseInstanceLine('pinnacle 7, Ascended Malgrath, slot 3, running, 19:58 left, 5 player(s)')
check(run and run.kind == 'run' and run.id == 7 and run.boss == 'Ascended Malgrath' and run.slot == 3 and run.state == 'running', 'a running fight line')
local won = L.parseInstanceLine('pinnacle 7, Ascended Malgrath, slot 3, success, 4 player(s)')
check(won and won.state == 'success' and won.slot == 3, 'a won fight line')
check(L.parseInstanceLine('0 instance(s) running of pinnacle. /instances close <type> <id> ends one (everyone out).').kind == 'summary', 'the summary line')
check(L.parseInstanceLine('1 instância(s) em execução de pinnacle.').kind == 'summary', 'the summary line in pt-BR')
check(L.parseInstanceLine('rift 4, tier 3, 02:10 left, 1 player(s)') == nil and L.parseInstanceLine('You see a rat.') == nil and L.parseInstanceLine(nil) == nil, 'other lines are not read')
check(L.parseInstanceLine('pinnacle 9, something odd').state == '?', 'a run line of an unknown shape is still a run')
check(L.bossMatches(cfg, 'Ascended Malgrath') and L.bossMatches(cfg, 'ascended MALGRATH') and not L.bossMatches(cfg, 'Ascended Vhoss'), 'the boss is matched by a part of its name, any case')

-- the tour: wait, open, fight, the boss falls
local TEMPLE = {x = 32929, y = 32073, z = 7}
local ARENA = {x = 11600, y = 10150, z = 7}
local S = L.new(cfg, 0)
local function actions(list, key)
  local out = {}
  for _, a in ipairs(list) do if a[key] then out[#out + 1] = a[key] end end
  return out
end
local function run_step(now, pos, nearest) return L.step(S, {now = now, pos = pos, nearest = nearest}) end

local a = run_step(0, TEMPLE)
check(#actions(a, 'say') == 1 and actions(a, 'say')[1] == '/instances pinnacle', 'the first look asks the instance list')
check(#run_step(1000, TEMPLE) == 0, 'no second ask before the answer, within a second')
L.onText(S, '0 instance(s) running of pinnacle.')
check(S.run == nil and S.answered == 1, 'an answer with no fight: nothing open')
check(#run_step(2000, TEMPLE) == 0, 'not yet time to ask again (3 s)')
a = run_step(3100, TEMPLE)
check(actions(a, 'say')[1] == '/instances pinnacle' and S.phase == 'wait', 'asks again after 3 s; still waiting')
L.onText(S, 'pinnacle 7, Ascended Malgrath, slot 3, running, 19:58 left, 5 player(s)')
L.onText(S, '1 instance(s) running of pinnacle.')
check(S.run and S.run.state == 'running', 'the fight is listed')
a = run_step(3200, TEMPLE)
check(actions(a, 'say')[1] == '/goto Tester Aka' and S.phase == 'wait', 'the spectator jumps to the first party member')
check(#run_step(4000, TEMPLE) == 0 or actions(run_step(4000, TEMPLE), 'say')[1] ~= '/goto Tester Bel', 'no second jump within 6 s')
-- the first member was carried out already: the jump landed in the temple, 6 s later the next name
a = run_step(9400, TEMPLE)
check(table.concat(actions(a, 'say'), '|'):find('/goto Tester Bel', 1, true), 'not in the arena after 6 s: the next member')
a = run_step(10000, ARENA, 2)
check(S.phase == 'fight' and actions(a, 'log')[1] == 'ready', 'inside the arena: the fight phase, the ready line')
check(S.fightAt == 10000, 'the fight clock starts on the ready line')

-- following
a = run_step(11000, ARENA, 3)
check(#actions(a, 'say') == 0 or actions(a, 'say')[1] == '/instances pinnacle', 'a member in sight: no jump')
local jumped
for t = 12000, 20000, 1000 do
  for _, x in ipairs(actions(run_step(t, ARENA, nil), 'say')) do if x:find('/goto', 1, true) then jumped = x end end
end
check(jumped == '/goto Tester Cor', 'no member in sight for 4 s: the next name (' .. tostring(jumped) .. ')')
-- outside the arena a member in sight does not count (a bot that was carried out stands in the temple)
S.farAt, S.gotoAt = nil, nil
local out_jump
for t = 21000, 27000, 1000 do
  for _, x in ipairs(actions(run_step(t, TEMPLE, 1), 'say')) do if x:find('/goto', 1, true) then out_jump = x end end
end
check(out_jump ~= nil, 'outside the arena the spectator goes back to a member of the fight')

-- the boss falls: the list says success
S.polls, S.answered = S.polls + 1, S.polls + 1
L.onText(S, 'pinnacle 7, Ascended Malgrath, slot 3, success, 4 player(s)')
L.onText(S, '1 instance(s) running of pinnacle.')
a = run_step(30000, ARENA, 2)
check(S.endWhy == 'boss dead' and S.endAt == 30000 + L.OUTRO_WIN_MS, 'success: the outro starts')
check(#run_step(35000, ARENA, 2) == 0 and not S.done, 'the outro lets the cheer show')
a = run_step(39500, ARENA, 2)
check(S.done and a[#a].finish == 'boss dead' and a[#a].ok == true, 'then the tour ends: boss dead, ok')
check(#run_step(40000, ARENA, 2) == 0, 'a finished tour does nothing more')

-- a wipe: the fight is gone from the list while it was running
S = L.new(cfg, 0)
run_step(0, TEMPLE)
L.onText(S, 'pinnacle 7, Ascended Malgrath, slot 3, running, 19:58 left, 5 player(s)'); L.onText(S, '1 instance(s) running of pinnacle.')
run_step(100, ARENA, 2)
check(S.phase == 'fight', 'a spectator already in the arena starts the fight phase')
S.polls = S.polls + 1
L.onText(S, '0 instance(s) running of pinnacle.')
check(S.run == nil, 'an answer without the fight: it is gone')
a = run_step(5000, ARENA, nil)
check(S.endAt == 5000 + L.OUTRO_END_MS and S.endWhy:find('no kill', 1, true), 'gone while it was running: the party fell or the clock ran out')
a = run_step(11500, ARENA, nil)
check(S.done and a[#a].finish:find('no kill', 1, true) and a[#a].ok == true, 'the tour ends ok (a video was made)')

-- a failed state line (kept in the list for a moment) is also an end without a kill
S = L.new(cfg, 0)
run_step(0, ARENA, 2)
S.polls = S.polls + 1
L.onText(S, 'pinnacle 7, Ascended Malgrath, slot 3, failed, 0 player(s)'); L.onText(S, '1 instance(s) running of pinnacle.')
run_step(2000, ARENA, 2)
check(S.endWhy and S.endWhy:find('failed', 1, true), 'a failed line ends the fight')

-- the time limit
S = L.new(L.parseEnv(env(with({CHAOS_BOSSTOUR_SECONDS = '60'}))), 0)
run_step(0, ARENA, 2)
S.polls = S.polls + 1
L.onText(S, 'pinnacle 7, Ascended Malgrath, slot 3, running, 19:58 left, 5 player(s)'); L.onText(S, '1 instance(s) running of pinnacle.')
run_step(30000, ARENA, 2)
check(not S.done, 'inside the limit the fight goes on')
a = run_step(60500, ARENA, 2)
check(S.done and a[#a].finish == 'time limit' and a[#a].ok == true, 'at the limit the tour ends: time limit, ok')

-- no fight ever opens
S = L.new(L.parseEnv(env(with({CHAOS_BOSSTOUR_WAIT = '120'}))), 0)
for t = 0, 119000, 3000 do run_step(t, TEMPLE) end
check(not S.done, 'inside the wait nothing ends the tour')
a = run_step(121000, TEMPLE)
check(S.done and a[#a].ok == false and a[#a].finish:find('no fight opened', 1, true), 'after the wait with no fight: a failed tour')

-- the fight was over before the spectator arrived
S = L.new(cfg, 0)
run_step(0, TEMPLE)
L.onText(S, 'pinnacle 7, Ascended Malgrath, slot 3, running, 19:58 left, 5 player(s)'); L.onText(S, '1 instance(s) running of pinnacle.')
S.polls = S.polls + 1
L.onText(S, '0 instance(s) running of pinnacle.')
a = run_step(4000, TEMPLE)
check(S.done and a[#a].ok == false and a[#a].finish:find('over before', 1, true), 'listed, then gone before the jump: a failed tour with the reason')

-- another boss in the list is not this tour's fight
S = L.new(cfg, 0)
run_step(0, TEMPLE)
L.onText(S, 'pinnacle 8, Ascended Vhoss, slot 1, running, 19:00 left, 1 player(s)'); L.onText(S, '1 instance(s) running of pinnacle.')
check(S.run == nil, 'a fight of another boss is not followed')

-- the boss's health is read from the creature locked on first (O694)
do
  local W = L.new(cfg, 0)
  local hp, logs = L.watchBoss(W, {})
  check(hp == nil and #logs == 0 and W.bossId == nil, 'no boss in view: no health, nothing locked, no line')
  hp, logs = L.watchBoss(W, {{id = 7, name = 'Ascended Malgrath', hp = 100}})
  check(hp == 100 and W.bossId == 7 and #logs == 1 and logs[1]:find('locked', 1, true), 'the first match is locked, with a line')
  hp, logs = L.watchBoss(W, {{id = 9, name = 'Malgrath Echo', hp = 40}, {id = 7, name = 'Ascended Malgrath', hp = 80}})
  check(hp == 80, 'a second creature with the name does not take the reading, whatever its place in the list')
  check(#logs == 1 and logs[1]:find('another creature', 1, true) and logs[1]:find('9', 1, true), 'the other creature is logged')
  hp, logs = L.watchBoss(W, {{id = 7, name = 'Ascended Malgrath', hp = 79}, {id = 9, name = 'Malgrath Echo', hp = 40}})
  check(hp == 79 and #logs == 0, 'the other creature is logged once, not on every look')
  hp, logs = L.watchBoss(W, {{id = 9, name = 'Malgrath Echo', hp = 100}})
  check(hp == nil, 'the locked creature out of view and another one in: no health (the other is not the boss)')
  check(#logs == 1 and logs[1]:find('left the view', 1, true), 'the lock leaving the view is logged')
  hp, logs = L.watchBoss(W, {{id = 9, name = 'Malgrath Echo', hp = 100}})
  check(hp == nil and #logs == 0, 'and only once')
  hp, logs = L.watchBoss(W, {{id = 7, name = 'Ascended Malgrath', hp = 83}})
  check(hp == 83 and #logs == 1 and logs[1]:find('in view again', 1, true), 'the locked creature back in view is logged, with its health')
end

check(L.maxTourSeconds(cfg) == 489, 'the tour length: the limit and the outro')
check(L.WINDOW.width % 2 == 0 and L.WINDOW.height % 2 == 0 and L.WINDOW.width / L.WINDOW.height > 1.7, 'the video window is an even 16:9 size')
check(L.pickCharacter({'Live Aldric A', 'Live Brenna A'}, 'live brenna a') == 2, 'the named character, any case')
check(L.pickCharacter({'A'}) == 1 and L.pickCharacter({}) == nil and L.pickCharacter(nil) == nil, 'first, or none')
check(L.GHOST_SAY == '/ghost' and L.POLL_SAY == '/instances pinnacle' and L.GOTO_SAY == '/goto ', 'the staff commands')

print(('bosstourlogic_test: %d checks, %d failures'):format(n, bad))
os.exit(bad == 0 and 0 or 1)
