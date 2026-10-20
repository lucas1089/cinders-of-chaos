-- luajit shopicon_test.lua && lua5.3 shopicon_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'shopicon.lua')
local S = ShopIcon
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function main(play) return play[1] and play[1].b end

-- no look: the item or creature as before
eq(S.plan({ type = 'item', item = 2160 }, main).mode, 'native', 'item')
eq(S.plan({ type = 'outfit', outfit = { type = 128 } }, main).mode, 'native', 'creature without a look')
eq(S.plan(nil, main).mode, 'native', 'nil')
-- creature looks stay creatures
for _, k in ipairs({ 'outfit', 'mount', 'wings', 'aura', 'shader', 'subject' }) do
  eq(S.plan({ type = 'outfit', look = { kind = k, look = 5 } }, main).mode, 'native', k .. ' is drawn by the creature widget')
end
-- an outline: the plain figure with the outline, the glow picture when the engine cannot
local p = S.plan({ type = 'outfit', look = { kind = 'outline', art = 'radiant', pulse = true } }, main)
eq(p.mode, 'creature', 'outline') eq(p.outline.art, 'radiant', 'art') eq(p.outline.pulse, true, 'pulse')
eq(p.glow, '/modules/game_cosmeticfx/images/glows/radiant', 'glow picture')
eq(S.plan({ type = 'item', look = { kind = 'outline', art = 'gold' } }, main).mode, 'native', 'an outline offer from an old server (item): the item')
eq(S.plan({ type = 'outfit', look = { kind = 'outline', art = '../etc' } }, main).mode, 'native', 'a bad art name')
-- a bundle with an outline part
p = S.plan({ type = 'outfit', look = { kind = 'bundle', parts = { { kind = 'wings', look = 1 }, { kind = 'outline', art = 'frost' } } } }, main)
eq(p.mode, 'creature', 'bundle outline') eq(p.outline.art, 'frost', 'its art')
eq(S.plan({ type = 'outfit', look = { kind = 'bundle', parts = { { kind = 'wings', look = 1 } } } }, main).mode, 'native', 'bundle without outline')
-- pictures
p = S.plan({ type = 'item', look = { kind = 'footprint', art = 'ash' } }, main)
eq(p.mode, 'image', 'footprint') eq(p.image, '/modules/game_cosmeticfx/images/prints/ash', 'print') eq(p.rotation, 90, 'rotated')
p = S.plan({ type = 'item', look = { kind = 'nameplate', frame = 'frost' } }, main)
eq(p.mode, 'image', 'plate') eq(p.image, '/modules/game_nameplate/images/plate_frost', 'plate art') eq(p.fixed, true, 'ratio kept')
eq(S.plan({ type = 'item', look = { kind = 'nameplate', frame = 'a b' } }, main).mode, 'native', 'bad frame name')
-- effects
p = S.plan({ type = 'item', look = { kind = 'effects', play = { { b = { id = 77, n = 'fx_x' } } } } }, main)
eq(p.mode, 'effect', 'effects') eq(p.spec.id, 77, 'main effect')
eq(S.plan({ type = 'item', look = { kind = 'effects', play = {} } }, main).mode, 'native', 'no effect to draw')
eq(S.plan({ type = 'item', look = { kind = 'effects', play = { { b = { id = 1 } } } } }, nil).mode, 'native', 'no preview module: the item')
-- samples
p = S.plan({ type = 'item', look = { kind = 'swatch', color = '#ff8800' } }, main)
eq(p.mode, 'swatch', 'chat colour') eq(p.color, '#ff8800', 'colour') eq(p.accent, false, 'text sample') eq(S.sampleText(p), 'Aa', 'sample text')
p = S.plan({ type = 'item', look = { kind = 'swatch', color = '#102030', accent = true } }, main)
eq(p.accent, true, 'loot label accent') eq(S.sampleText(p), '', 'a bar, no text')
eq(S.plan({ type = 'item', look = { kind = 'swatch', color = '#100c0ef0', accent = true } }, main).mode, 'swatch', 'accent with alpha')
eq(S.plan({ type = 'item', look = { kind = 'swatch', color = 'red' } }, main).mode, 'native', 'bad colour')
eq(S.plan({ type = 'item', look = { kind = 'swatch', color = '#1234567' } }, main).mode, 'native', 'seven digits')
if fails > 0 then error(fails .. ' failure(s)') end
print('shopicon_test: all passed')
