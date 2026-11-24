-- run from the repository root: luajit client/overlay/modules/test_docktour/docktourlogic_test.lua
dofile('client/overlay/modules/test_docktour/docktourlogic.lua')
dofile('client/overlay/modules/game_chaosdock/chaosdocklogic.lua')
local L = ChaosDockTourLogic
local D = ChaosDockLogic
local n, bad = 0, 0
local function check(c, what) n = n + 1; if not c then bad = bad + 1; print('FAIL ' .. what) end end
local function env(t) return function(k) return t[k] end end

local cfg = L.parseEnv(env({CHAOS_DOCKTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'p w', CHAOS_LIVE_CHARACTER = 'Dock Viewer'}))
check(cfg and cfg.account == 'a1' and cfg.password == 'p w' and cfg.character == 'Dock Viewer', 'armed with account, password and character')
local c3, why = L.parseEnv(env({CHAOS_LIVE_ACCOUNT = 'a1', CHAOS_LIVE_PASSWORD = 'x'}))
check(c3 == nil and why == 'off', 'no switch: off, whatever else is set')
check(L.parseEnv(env({CHAOS_DOCKTOUR = 'yes', CHAOS_LIVE_ACCOUNT = 'a', CHAOS_LIVE_PASSWORD = 'x'})) == nil, 'only 1 arms it')
local c4, why4 = L.parseEnv(env({CHAOS_DOCKTOUR = '1', CHAOS_LIVE_ACCOUNT = 'a'}))
check(c4 == nil and why4:find('password', 1, true), 'no password: refused with the reason')
check(L.parseEnv(nil) == nil and L.parseEnv(function() error('boom') end) == nil, 'no getenv or one that throws: off')

local tl = L.timeline()
check(#tl == #L.STEPS, 'one timed step per step')
check(tl[1].at >= 2000, 'the recording has time to start before the first step')
for i = 2, #tl do check(tl[i].at >= tl[i - 1].at, 'step ' .. i .. ' not before step ' .. (i - 1)) end
check(tl[#tl]['do'] == 'exit', 'the tour ends with the exit')
check(L.duration() >= 50000 and L.duration() <= 95000, 'about 60 to 90 s from ready to exit')
check(L.WATCHDOG_MS > L.duration() * 5, 'the watchdog is far above the tour')

-- every tab of the dock is shown, every sub tab named exists, the keys are the dock's own
local seen, tab = {}, nil
local keys = {}
for _, k in ipairs(D.hotkeys()) do keys[k.key] = k.tab or 'toggle' end
for _, s in ipairs(tl) do
  if s['do'] == 'key' then
    check(keys[s.key] ~= nil, 'the key ' .. s.key .. ' is a key of the dock')
    if s.open then tab = s.tab or tab end
  elseif s['do'] == 'tab' then
    check(D.tab(s.tab) ~= nil, 'tab ' .. tostring(s.tab) .. ' exists')
    tab = s.tab
  elseif s['do'] == 'sub' then
    local t = D.tab(tab)
    check(t and s.sub >= 1 and s.sub <= #t.windows, 'sub ' .. s.sub .. ' of ' .. tostring(tab) .. ' exists')
  end
  if tab then seen[tab] = true end
end
for _, t in ipairs(D.TABS) do check(seen[t.id], 'the tour shows the tab ' .. t.id) end
check(tl[2]['do'] == 'key' and tl[2].key == D.TOGGLE_KEY and tl[2].open, 'the dock opens with its own key')
local last = tl[#tl - 2]
check(last['do'] == 'key' and last.key == D.TOGGLE_KEY and last.open == false, 'and closes with it')

check(L.keyWorked({open = true, tab = 'quests'}, true, 'quests'), 'key worked: open on the tab')
check(not L.keyWorked({open = true, tab = 'quests'}, true, 'equip'), 'key not worked: another tab')
check(not L.keyWorked({open = true}, false, nil), 'key not worked: closed')
check(L.keyWorked({open = false}, false, nil) and not L.keyWorked({open = false}, true, 'equip'), 'close key')

check(L.WINDOW.width % 2 == 0 and L.WINDOW.height % 2 == 0, 'the video window is an even size')
check(L.pickCharacter({'Tester Aka', 'Dock Viewer'}, 'dock viewer') == 2, 'the named character, any case')
check(L.pickCharacter({'A'}) == 1 and L.pickCharacter({}) == nil, 'first, or none')

print(('docktourlogic_test: %d checks, %d failures'):format(n, bad))
os.exit(bad == 0 and 0 or 1)
