-- luajit client/overlay/modules/game_helperrotation/onboarding_test.lua (from the repository root; also lua5.3)
-- The first-login Helper opening (onboarding.lua): which messages open it, the hint, the blink frames.
dofile('client/overlay/modules/game_helperrotation/onboarding.lua')
local O = ChaosHelperOnboarding
local n, bad = 0, 0
local function eq(a, b, what)
  n = n + 1
  if a ~= b then bad = bad + 1 print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)) end
end
eq(O.plan(nil, false, 'x'), nil, 'no message')
eq(O.plan({ action = 'newplayer', message = 'hi' }, false, 'x'), nil, 'a plain toast does not open the helper')
local p = O.plan({ openHelper = true, hint = 'Set up' }, false, 'fallback')
eq(p.toggle, true, 'hidden window: toggled open')
eq(p.hint, 'Set up', 'the server hint')
p = O.plan({ openHelper = true }, true, 'fallback')
eq(p.toggle, false, 'an open window is not toggled shut')
eq(p.hint, 'fallback', 'no hint: the client text')
eq(O.plan({ openHelper = true, hint = '' }, true, 'fb').hint, 'fb', 'empty hint: the client text')
local f = O.blinkFrames(12000, 400)
eq(#f, 30, 'thirty frames')
eq(f[1], true, 'starts gold') eq(f[#f], false, 'ends on its own colour')
eq(#O.blinkFrames(1000, 400) % 2, 0, 'an even count')
eq(#O.blinkFrames(0, 400), 0, 'no blink')
print(('onboarding_test: %d checks, %d failed'):format(n, bad))
if bad > 0 then os.exit(1) end
