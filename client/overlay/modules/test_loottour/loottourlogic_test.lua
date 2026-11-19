-- run from the repository root: luajit client/overlay/modules/test_loottour/loottourlogic_test.lua
dofile('client/overlay/modules/test_loottour/loottourlogic.lua')
local L = ChaosLootTourLogic
local n, bad = 0, 0
local function check(c, what) n = n + 1; if not c then bad = bad + 1; print('FAIL ' .. what) end end
local function env(t) return function(k) return t[k] end end

local cfg = L.parseEnv(env({CHAOS_LOOTTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'p w', CHAOS_LIVE_CHARACTER = 'Tester Aka'}))
check(cfg and cfg.account == 'a1' and cfg.password == 'p w' and cfg.character == 'Tester Aka', 'armed with account, password and character')
local c2 = L.parseEnv(env({CHAOS_LOOTTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'x'}))
check(c2 and c2.character == nil, 'the character is optional')
local c3, why = L.parseEnv(env({CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'x'}))
check(c3 == nil and why == 'off', 'no switch: off, whatever else is set')
check(L.parseEnv(env({CHAOS_LOOTTOUR = '0', CHAOS_LIVE_ACCOUNT = 'a', CHAOS_LIVE_PASSWORD = 'x'})) == nil, 'switch 0: off')
check(L.parseEnv(env({CHAOS_LOOTTOUR = 'yes', CHAOS_LIVE_ACCOUNT = 'a', CHAOS_LIVE_PASSWORD = 'x'})) == nil, 'only 1 arms it')
local c4, why4 = L.parseEnv(env({CHAOS_LOOTTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a'}))
check(c4 == nil and why4:find('password', 1, true), 'no password: refused with the reason')
check(L.parseEnv(env({CHAOS_LOOTTOUR = '1', CHAOS_LIVE_ACCOUNT = '', CHAOS_LIVE_PASSWORD = 'x'})) == nil, 'empty account: refused')
check(L.parseEnv(nil) == nil and L.parseEnv(function() error('boom') end) == nil, 'no getenv or one that throws: off')

local tl = L.timeline()
check(#tl == 4, 'four steps')
check(tl[1]['do'] == 'say' and tl[2]['do'] == 'say' and tl[1].text == '!tester explode run' and tl[2].text == tl[1].text, 'explode twice')
check(tl[3]['do'] == 'lootall' and tl[4]['do'] == 'exit', 'Loot all, then exit')
for i = 2, #tl do check(tl[i].at > tl[i - 1].at, 'step ' .. i .. ' after step ' .. (i - 1)) end
check(tl[1].at >= 2000, 'the recording has time to start before the first step')
check(tl[2].at - tl[1].at >= 3000 and tl[2].at - tl[1].at <= 10000, 'a few seconds between the explosions')
check(tl[3].at - tl[2].at >= 4000, 'the loot lies on show before Loot all')
check(tl[4].at - tl[3].at >= 3000, 'the pickup is on show before the exit')
check(L.duration() >= 15000 and L.duration() <= 25000, 'about 20 s from ready to exit')
check(L.duration() == tl[#tl].at and L.WATCHDOG_MS > L.duration() * 10, 'the watchdog is far above the tour')

check(L.WINDOW.width % 2 == 0 and L.WINDOW.height % 2 == 0 and L.WINDOW.width / L.WINDOW.height > 1.7, 'the video window is an even 16:9 size')
check(L.pickCharacter({'Tester Aka', 'Tester Bel'}, 'tester bel') == 2, 'the named character, any case')
check(L.pickCharacter({'Tester Aka', 'Tester Bel'}, 'Nobody') == 1, 'unknown name: the first')
check(L.pickCharacter({'A'}) == 1 and L.pickCharacter({}) == nil and L.pickCharacter(nil) == nil, 'first, or none')

print(('loottourlogic_test: %d checks, %d failures'):format(n, bad))
os.exit(bad == 0 and 0 or 1)
