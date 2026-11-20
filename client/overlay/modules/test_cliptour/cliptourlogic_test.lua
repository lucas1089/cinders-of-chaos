-- run from the repository root: luajit client/overlay/modules/test_cliptour/cliptourlogic_test.lua
dofile('client/overlay/modules/test_cliptour/cliptourlogic.lua')
local L = ChaosClipTourLogic
local n, bad = 0, 0
local function check(c, what) n = n + 1; if not c then bad = bad + 1; print('FAIL ' .. what) end end
local function env(t) return function(k) return t[k] end end
local base = {CHAOS_CLIPTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'p w'}
local function with(extra) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(extra or {}) do t[k] = v end return t end

-- arming
local cfg = L.parseEnv(env(with({CHAOS_LIVE_CHARACTER = 'Tester Aka'})))
check(cfg and cfg.account == 'a1' and cfg.password == 'p w' and cfg.character == 'Tester Aka', 'armed with account, password and character')
check(cfg and #cfg.shots == #L.SHOTS, 'no shot list: every shot')
local off, why = L.parseEnv(env({CHAOS_LIVE_ACCOUNT = 'a', CHAOS_LIVE_PASSWORD = 'x'}))
check(off == nil and why == 'off', 'no switch: off, whatever else is set')
check(L.parseEnv(env(with({CHAOS_CLIPTOUR = '0'}))) == nil and L.parseEnv(env(with({CHAOS_CLIPTOUR = 'yes'}))) == nil, 'only 1 arms it')
local c4, why4 = L.parseEnv(env({CHAOS_CLIPTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a'}))
check(c4 == nil and why4:find('password', 1, true), 'no password: refused with the reason')
check(L.parseEnv(nil) == nil and L.parseEnv(function() error('boom') end) == nil, 'no getenv or one that throws: off')

-- the shot list
local ids = L.shotIds()
check(#ids == 10, 'ten shots, one per slot of the website')
local seen = {}
for _, s in ipairs(L.SHOTS) do
  check(not seen[s.id] and s.id:match('^[a-z0-9-]+$'), 'shot id ' .. s.id .. ' is a plain unique slug')
  seen[s.id] = true
  check(s.seconds >= 6 and s.seconds <= 10, s.id .. ': a loop of 6 to 10 s')
  check(s.staging == 'ready' or s.staging == 'check', s.id .. ': a staging state')
  check(type(s.action) == 'table' and #s.action > 0, s.id .. ': has an action')
  for _, a in ipairs(s.action) do
    local kinds = (a.say and 1 or 0) + (a.window and 1 or 0) + (a.zoom and 1 or 0) + (a.key and 1 or 0)
    check(kinds == 1 and a.at and a.at >= 0 and a.at < s.seconds * 1000, s.id .. ': one action kind inside the loop')
  end
  for _, st in ipairs(s.setup or {}) do check(st.say and st.wait and st.wait > 0, s.id .. ': a setup line waits for its answer') end
  for _, st in ipairs(s.cleanup or {}) do check((st.say or st.window) and st.wait and st.wait > 0, s.id .. ': a cleanup step waits') end
  -- every said line is a helper line (the tester helper answers only those) and no player-facing text
  for _, list in ipairs({s.setup or {}, s.cleanup or {}, s.action}) do
    for _, st in ipairs(list) do check(not st.say or st.say:match('^!tester '), s.id .. ': says only helper lines') end
  end
end
check(seen['loot-explosion'] and seen['loot-beams'] and seen['rift'] and seen['pinnacle'] and seen['passive-tree'] and seen['ember-descent']
  and seen['infinity-tower'] and seen['dungeon-cards'] and seen['cosmetics'] and seen['spell-effects'], 'the slots of the plan')

-- choosing shots
local only = L.parseEnv(env(with({CHAOS_CLIPTOUR_SHOTS = 'rift, loot-explosion'})))
check(only and #only.shots == 2 and only.shots[1] == 'loot-explosion' and only.shots[2] == 'rift', 'a list: those shots, in tour order')
local bogus, why5 = L.parseEnv(env(with({CHAOS_CLIPTOUR_SHOTS = 'rift,nope'})))
check(bogus == nil and why5 == 'unknown shot nope', 'an unknown shot is refused')
check(#L.pickShots(' , ') == #L.SHOTS, 'a list with no id: every shot')

-- the timeline
local tl = L.timeline({'loot-explosion', 'passive-tree'})
local marks, last = {}, -1
for _, s in ipairs(tl) do
  check(s.at >= last, 'steps in time order')
  last = s.at
  if s['do'] == 'mark' then marks[#marks + 1] = s.what .. ':' .. s.shot end
end
check(table.concat(marks, ',') == 'begin:loot-explosion,end:loot-explosion,begin:passive-tree,end:passive-tree', 'begin and end of each shot in order')
check(tl[#tl]['do'] == 'exit' and tl[1].at >= L.GRACE_MS, 'the tour starts after the grace and ends with the exit')
local begin, finish, act
for _, s in ipairs(tl) do
  if s['do'] == 'mark' and s.shot == 'loot-explosion' then
    if s.what == 'begin' then begin = s else finish = s end
  elseif s['do'] == 'say' and s.shot == 'loot-explosion' and not act then act = s end
end
check(begin.seconds == 8 and finish.at - begin.at == L.LEAD_MS + 8000 + L.TAIL_MS, 'the end line comes after the seconds of the loop')
check(act.at >= begin.at + L.LEAD_MS, 'the action starts after the recorder had its lead')
local rift = L.timeline({'rift'})
check(rift[1]['do'] == 'say' and rift[2]['do'] == 'mark' and rift[2].at - rift[1].at == 9000, 'setup lines come first and the begin waits for their answer')
check(L.duration() > 120000 and L.duration() < 600000 and L.WATCHDOG_MS > L.duration() * 4, 'the whole tour is minutes, the watchdog far above it')
check(L.duration({'loot-beams'}) < L.duration({'loot-beams', 'rift'}), 'more shots, a longer tour')

check(L.WINDOW.width % 2 == 0 and L.WINDOW.height % 2 == 0 and L.WINDOW.width * 9 == L.WINDOW.height * 16, 'the window is an even 16:9 size (the blur boxes of the site are cut for 1920x1080)')
check(L.pickCharacter({'Tester Aka', 'Tester Bel'}, 'tester bel') == 2 and L.pickCharacter({'A'}) == 1 and L.pickCharacter({}) == nil, 'the character: named, first, none')

print(('cliptourlogic_test: %d checks, %d failures'):format(n, bad))
os.exit(bad == 0 and 0 or 1)
