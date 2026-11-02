-- run from the repository root: luajit client/overlay/modules/client_chaos_phonetest/phonetest_core_test.lua
dofile('client/overlay/modules/client_chaos_phonetest/phonetest_core.lua')
local M = ChaosPhoneTestCore
local n, bad = 0, 0
local function check(c, what) n = n + 1; if not c then bad = bad + 1; print('FAIL ' .. what) end end

local m = M.parseMarker('account=phonetest\npassword=phone1234\r\n')
check(m and m.account == 'phonetest' and m.password == 'phone1234', 'account and password read')
check(m and m.npc == 'Loot Buyer' and m.monster == 'Rat', 'defaults kept')
m = M.parseMarker('account = a1b\npassword = x y z \nmonster=Cave Rat\nNPC=Elder Bramwyn')
check(m and m.password == 'x y z' and m.monster == 'Cave Rat' and m.npc == 'Elder Bramwyn', 'spaces trimmed, keys any case')
check(M.parseMarker('account=a') == nil, 'no password: refused')
check(M.parseMarker(nil) == nil, 'empty marker: refused')
local ok, text = M.fits(10, 10, 300, 200, 960, 540)
check(ok and text == '300x200 at 10,10 on 960x540', 'a window inside fits')
ok, text = M.fits(0, 0, 1000, 600, 960, 540)
check(not ok and text:find('outside', 1, true), 'a window larger than the screen does not')
check(not M.fits(-1, 0, 10, 10, 960, 540), 'off the left edge does not fit')
local p = {x = 1, y = 1, z = 7}
check(M.moved({p, {x = 1, y = 0, z = 7}, {x = 1, y = 0, z = 7}, {x = 2, y = 0, z = 7}}) == 2, 'moves counted, a blocked step not')
check(M.moved({}) == 0 and M.moved({p}) == 0, 'no move from nothing')
check(M.STEPS[1] == 'login' and M.STEPS[#M.STEPS] == 'done', 'steps from login to done')
local fs = M.fpsSummary({{fps = 30, gfx = 31, cpu = 90}, {fps = 12, gfx = 12, cpu = 40}, {fps = 45.7, gfx = 46, cpu = 120}})
check(fs.fps == 30 and fs.minFps == 12 and fs.gfx == 31 and fs.cpu == 90, 'fps medians and the lowest')
local fe = M.fpsSummary({})
check(fe.fps == 0 and fe.minFps == 0 and fe.gfx == 0 and fe.cpu == 0, 'no samples: zeros')
check(M.STEPS[3] == 'perf', 'perf right after entering')
print(('phonetest_core_test: %d checks, %d failures'):format(n, bad))
os.exit(bad == 0 and 0 or 1)
