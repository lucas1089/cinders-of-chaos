-- luajit tryon_test.lua && lua5.3 tryon_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tryon.lua')
local T = TryOn
local fails, n = 0, 0
local function eq(a, b, what)
  n = n + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(T.MS, 10000, 'ten seconds')
-- looks on the own character
for _, k in ipairs({ 'outfit', 'addons', 'mount', 'wings', 'aura', 'shader', 'outline', 'footprint', 'effects' }) do
  local p = T.plan({}, { kind = k }, true)
  eq(p.panel, true, k .. ' in the panel') eq(p.show, true, k .. ' has the button')
  eq(T.plan({}, { kind = k }, false).show, false, k .. ' without the panel (mobile) has none')
end
-- not worn
for _, k in ipairs({ 'nameplate', 'subject', 'swatch' }) do
  eq(T.plan({}, { kind = k }, true).show, false, k .. ' keeps its icon')
end
eq(T.plan({ type = 'item' }, nil, true).show, false, 'an item') eq(T.plan(nil, nil, true).show, false, 'nothing')
eq(T.plan({}, 'junk', true).show, false, 'junk option')
-- bundles: when a part is worn
eq(T.plan({}, { kind = 'bundle', parts = { { kind = 'outfit' }, { kind = 'nameplate' } } }, true).panel, true, 'a bundle with an outfit')
eq(T.plan({}, { kind = 'bundle', parts = { { kind = 'nameplate' } } }, true).show, false, 'a bundle of plates only')
eq(T.plan({}, { kind = 'bundle' }, true).show, false, 'an empty bundle')
-- name plate frames: tried on the own plate when game_nameplate can draw them
local pl = T.plan({}, { kind = 'nameplate', frame = 'frost' }, true, true)
eq(pl.plate, 'frost', 'the frame') eq(pl.show, true, 'a plate has the button') eq(pl.panel, false, 'not in the panel')
eq(T.plan({}, { kind = 'nameplate', frame = 'frost' }, false, true).show, true, 'also without the panel (mobile)')
eq(T.plan({}, { kind = 'nameplate', frame = 'frost' }, true, false).show, false, 'no plate module: no button')
eq(T.plan({}, { kind = 'nameplate' }, true, true).show, false, 'a plate without a frame')
eq(T.plan({}, { kind = 'nameplate', frame = '' }, true, true).plate, nil, 'an empty frame')
pl = T.plan({}, { kind = 'bundle', parts = { { kind = 'outfit' }, { kind = 'nameplate', frame = 'ember' } } }, true, true)
eq(pl.panel and pl.plate == 'ember', true, 'a bundle: the outfit in the panel, the plate on the plate')
eq(T.plan({}, { kind = 'bundle', parts = { { kind = 'nameplate', frame = 'ember' } } }, true, true).show, true, 'a bundle of plates only')
eq(T.plateFrame('junk'), nil, 'junk') eq(T.plateFrame(nil), nil, 'nil')
-- the server's effect: with or without the panel
local p = T.plan({ preview = { effect = true } }, { kind = 'effects' }, true)
eq(p.panel and p.server, true, 'an effect cosmetic: panel and map')
p = T.plan({ preview = { effect = true } }, nil, false)
eq(p.panel, false, 'no panel') eq(p.server, true, 'the map alone') eq(p.show, true, 'still a button')
eq(T.plan({ preview = { color = '#ffffff' } }, nil, true).show, false, 'a chat colour has none')
eq(T.plan({ preview = { accent = '#101010f0' } }, nil, true).server, false, 'a loot label has none')
-- the clock
eq(T.secondsLeft(20000, 10000), 10, 'ten left') eq(T.secondsLeft(20000, 19001), 1, 'rounded up')
eq(T.secondsLeft(20000, 20000), 0, 'over') eq(T.secondsLeft(20000, 25000), 0, 'long over') eq(T.secondsLeft(nil, 5), 0, 'nothing')
eq(T.countdown(8), '8s', 'text') eq(T.countdown(0), nil, 'normal text again') eq(T.countdown(nil), nil, 'nil')
eq(T.margins(true).button, 48, 'room for the gift button') eq(T.margins(false).description, 120, 'room for the button alone')
eq(T.margins(true).description > T.margins(false).description, true, 'more text room is taken with a gift button')

if fails > 0 then os.exit(1) end
print('tryon_test: ' .. n .. ' checks OK')
