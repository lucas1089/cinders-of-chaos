-- luajit lootfilter_test.lua && lua5.3 lootfilter_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'lootfilterlogic.lua')
local L = LootFilterLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(#L.RARITY, 15, '15 rarities')
eq(L.rarityName(5), 'Legendary', 'name 5')
eq(L.rarityName(0), nil, 'no rarity')

local s = L.normalize({ highlight = 4, dim = 2, show = { supplies = false } })
eq(s.lootMin, 0, 'missing field = default')
eq(s.show.supplies, false, 'category off')
eq(s.show.other, true, 'category on')
eq(L.normalize({ highlight = 40 }).highlight, 15, 'clamped')
eq(L.normalize(nil).highlight, 3, 'nil = defaults')

eq(L.classify({ r = 4, g = 'equipment' }, s), 'highlight', 'Epic glows')
eq(L.classify({ r = 3, g = 'equipment' }, s), 'normal', 'Rare plain')
eq(L.classify({ r = 1, g = 'equipment' }, s), 'dim', 'Common dimmed')
eq(L.classify({ r = 0, g = 'supplies' }, s), 'dim', 'supplies off')
eq(L.classify({ u = 1, g = 'equipment' }, s), 'highlight', 'unique (JSON 1)')
eq(L.classify({ o = true, g = 'currency' }, { highlight = 0, dim = 15, show = { currency = false } }), 'highlight', 'orb')
eq(L.classify({ r = 0, g = 'other' }, s), 'normal', 'other shown')
eq(s.tier, 0, 'tier rule off by default')
local ts = L.normalize({ highlight = 5, tier = 7 })
eq(ts.tier, 7, 'tier rule')
eq(L.classify({ r = 1, t = 7, g = 'equipment' }, ts), 'highlight', 'a T7 modifier glows on Common gear')
eq(L.classify({ r = 1, t = 6, g = 'equipment' }, ts), 'normal', 'T6 does not')
eq(L.normalize({ tier = 99 }).tier, 8, 'tier clamped')

eq(L.color({ r = 5 }), '#ffd040', 'legendary colour')
eq(L.color({ u = 1, r = 5 }), L.UNIQUE_COLOR, 'unique colour')
eq(L.color({ o = 1 }), L.ORB_COLOR, 'orb colour')
eq(L.color({ r = 0 }), nil, 'no colour')

eq(L.label({ nm = 'Dawnforged Helmet', r = 5 }), '[Legendary] Dawnforged Helmet', 'label')
eq(L.label({ nm = 'Soulreaper', u = 1 }), '[Unique] Soulreaper', 'unique label')
eq(L.tooltip({ nm = 'gold coin', c = 50, left = 20 }), '50x gold coin\n20 left in the corpse\nClick: loot all   Shift+click: loot one', 'stack tooltip')
eq(L.tooltip({ nm = 'Sword', r = 3, c = 1, left = 0 }), '[Rare] Sword\nLooted (or gone)', 'gone tooltip')
eq(L.tooltip({ nm = 'Sword', c = 1, left = 1 }), 'Sword\nClick: loot', 'single tooltip')
eq(L.tooltip({ nm = 'Sword', r = 4, c = 1, left = 1, x = 'Attack Speed +5%; Life on Kill +12' }),
  '[Epic] Sword\nAttack Speed +5%; Life on Kill +12\nClick: loot', 'tooltip with Chaos modifiers')
eq(L.thresholdText(0), 'Off', 'off')
eq(L.thresholdText(5), 'Legendary+', 'threshold')

local list = { 1, 2, 3, 4 }
local dropped = L.trim(list, 2)
eq(#list, 2, 'trimmed')
eq(list[1], 3, 'oldest dropped')
eq(dropped[2], 2, 'dropped keys')

-- loot feed rows: the monster icon and the item icons, no text
local o = L.outfit({ type = 34, head = 10, body = 20, legs = 30, feet = 40, addons = 3, shader = 'orange_energizer' })
eq(o.type .. ',' .. o.head .. ',' .. o.body .. ',' .. o.legs .. ',' .. o.feet .. ',' .. o.addons .. ',' .. o.auxType,
  '34,10,20,30,40,3,0', 'outfit for UICreature')
eq(o.shader, 'orange_energizer', 'tier shader kept')
eq(L.outfit({ type = 0, auxType = 2148 }).auxType, 2148, 'item look')
eq(L.outfit({ type = 0 }), nil, 'nothing to draw')
eq(L.outfit(nil), nil, 'no look (older server)')
eq(L.outfit({ type = '35', head = 999 }).head, 0, 'colour out of range')
eq(L.outfit({ type = 35, shader = '' }).shader, nil, 'no empty shader')
local t0 = os.time({ year = 2026, month = 10, day = 10, hour = 14, min = 32, sec = 5 })
eq(L.killTip('Dragon', t0), 'Dragon\nKilled at 14:32:05', 'monster tooltip')
eq(L.killTip(nil, t0, true), 'Unknown creature\nKilled at 14:32:05\nNothing to loot', 'empty corpse tooltip')
local row = L.feedRow({ k = '7', m = 'Dragon', look = { type = 34 }, items = { { id = 3031, c = 50, left = 50 }, 'junk', { n = 5, id = 1 } } }, t0)
eq(row.k, 7, 'kill id')
eq(row.outfit.type, 34, 'row outfit')
eq(row.empty, false, 'not empty')
eq(#row.items .. ':' .. row.items[1].n .. ':' .. row.items[2].n, '2:1:5', 'items in order, entry numbers kept')
row = L.feedRow({ k = 8, m = 'Rat', look = { type = 21 }, items = {} }, t0)
eq(row.empty, true, 'an empty corpse is a row too')
eq(row.tip, 'Rat\nKilled at 14:32:05\nNothing to loot', 'its tooltip')
eq(L.feedRow({ m = 'Rat' }, t0), nil, 'no kill id')
local c, gone = L.iconCount({ c = 50, left = 20 })
eq(c .. tostring(gone), '20false', 'count left in the corpse')
c, gone = L.iconCount({ c = 50, left = 0 })
eq(c .. tostring(gone), '50true', 'gone: the dropped count, greyed')
c, gone = L.iconCount({ c = 1 })
eq(c .. tostring(gone), '1false', 'no left yet')

-- rule counters and sounds (mirror of the server's lootfilter_core.lua)
local snd = L.normalizeSound(nil)
eq(snd.rules.unique .. snd.rules.power .. snd.rules.orb .. '/' .. snd.vol, '510/70', 'sound defaults like the server')
eq(snd.hunt, true, 'hunt tracker on by default')
local file, gain, rule = L.pickSound({ orb = 3, unique = 1 }, snd)
eq(file, '/modules/game_lootfilter/sounds/fanfare.ogg', 'unique first')
eq(gain, 0.7, 'volume as gain')
eq(rule, 'unique', 'the rule that played')
eq(L.pickSound({ orb = 3 }, snd), nil, 'orbs silent by default')
eq(L.pickSound({ rarity = 1, tier = 1 }, L.normalizeSound({ rules = { rarity = 0, tier = 3 } })), '/modules/game_lootfilter/sounds/ping.ogg',
  'a rule without sound is skipped')
eq(L.pickSound({ unique = 1 }, L.normalizeSound({ mute = true })), nil, 'mute all')
eq(L.pickSound({ unique = 1 }, L.normalizeSound({ vol = 0 })), nil, 'volume 0')
eq(L.pickSound(nil, snd), nil, 'no hits')
local n = L.normalizeSound({ rules = { unique = 9, orb = '2', bogus = 1 }, vol = 300, mute = 1, hunt = false })
eq(n.rules.unique .. n.rules.orb .. '/' .. n.vol .. tostring(n.mute) .. tostring(n.hunt), '02/100truefalse', 'normalized')
eq(L.soundFile(2), '/modules/game_lootfilter/sounds/bell.ogg', 'sound file')
eq(L.soundFile(0), nil, 'none')
eq(#L.SOUNDS, 5, 'five sounds')
eq(L.countLine({ session = { orb = 3 }, total = { orb = 1234 } }, 'orb'), 'Session 3   Total 1,234', 'counter line')
eq(L.countLine(nil, 'orb'), 'Session 0   Total 0', 'no counters yet')
local hr = L.huntRows({ session = { power = 2 }, total = { power = 7, tier = -1 } })
eq(#hr .. hr[2].key .. hr[2].session .. hr[2].total .. hr[4].total, '5power270', 'hunt rows')
-- the sound files the window offers exist (generated by client/tools/gen_lootfilter_sounds.py)
for _, s in ipairs(L.SOUNDS) do
  local f = io.open(dir .. 'sounds/' .. s.key .. '.ogg', 'rb')
  eq(f ~= nil, true, 'sound file ' .. s.key)
  if f then eq(f:read(4), 'OggS', 'Ogg ' .. s.key) f:close() end
end

if fails > 0 then os.exit(1) end
print('lootfilter client tests OK')
