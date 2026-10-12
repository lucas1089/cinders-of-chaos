-- luajit groundlabels_test.lua && lua5.3 groundlabels_test.lua (from any folder)
-- Ground label rules with the real loot filter rules (game_lootfilter/lootfilterlogic.lua): settings, candidates,
-- which rows get a label (filter highlight / dim, Rare+, Alt, corpses), text, timer, colour, priority and the cap, and
-- the layout: labels of the same and neighbouring tiles never overlap and stay near their tile.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. '../game_lootfilter/lootfilterlogic.lua')
dofile(dir .. 'groundlabelslogic.lua')
local L, GL = LootFilterLogic, GroundLabelsLogic
GL.setFilterLogic(L)
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- settings
local d = GL.defaults()
eq(d.enabled and d.rarePlus and d.altAll and d.corpses and d.timers, true, 'all on by default')
eq(d.size, 'normal', 'normal size')
local s = GL.normalize({ enabled = 'false', rarePlus = 'true', size = 'huge', timers = false })
eq(s.enabled, false, 'g_settings strings: false')
eq(s.rarePlus, true, 'g_settings strings: true')
eq(s.altAll, true, 'missing = default')
eq(s.timers, false, 'boolean false')
eq(s.size, 'normal', 'unknown size')
eq(GL.normalize(nil).corpses, true, 'nil = defaults')
eq(GL.normalize({ size = 'large' }).size, 'large', 'large')

-- ---------------------------------------------------------------- candidates
eq(GL.isCandidate({ pickupable = true }), true, 'a sword')
eq(GL.isCandidate({ ground = true, pickupable = true }), false, 'ground')
eq(GL.isCandidate({ border = true }), false, 'border')
eq(GL.isCandidate({ bottom = true, pickupable = true }), false, 'wall-like')
eq(GL.isCandidate({ top = true, pickupable = true }), false, 'on top (doors, arches)')
eq(GL.isCandidate({ container = true, corpse = true }), true, 'a corpse')
eq(GL.isCandidate({ container = true, pickupable = false }), false, 'a chest on the floor')
eq(GL.isCandidate({ pickupable = false }), false, 'furniture')
eq(GL.signature({ { id = 3264, c = 1 }, { id = 3031, c = 40 } }), '3264x1;3031x40', 'signature')
eq(GL.signature({}), '', 'empty signature')
eq(GL.posKey({ x = 1, y = 2, z = 7 }), '1,2,7', 'key')

-- ---------------------------------------------------------------- decisions
local filter = L.normalize({ highlight = 4, dim = 2, show = { supplies = false } }) -- Epic+ glows, Common dimmed
local on = GL.defaults()
local function decide(row, alt, st) return GL.decide(row, st or on, filter, alt) end
local epic = { id = 1, nm = 'fire sword', r = 4, g = 'equipment', c = 1 }
local rare = { id = 1, nm = 'fire sword', r = 3, g = 'equipment', c = 1 }
local unc = { id = 1, nm = 'sword', r = 2, g = 'equipment', c = 1 }
local common = { id = 1, nm = 'sword', r = 1, g = 'equipment', c = 1 }
local potion = { id = 2, nm = 'mana potion', g = 'supplies', c = 5 }
local junk = { id = 3, nm = 'bone', g = 'other', c = 1 }
local unique = { id = 4, nm = 'soulreaper', u = 1, g = 'equipment', c = 1 }
local orb = { id = 5, nm = 'chaos orb', o = 1, g = 'currency', c = 3 }
local power = { id = 6, nm = 'axe', r = 1, pw = 1, g = 'equipment', c = 1 }

eq(decide(epic).highlight, true, 'Epic glows: label, highlighted')
eq(decide(rare).highlight, false, 'Rare: label (Rare+), not highlighted')
eq(decide(unc), nil, 'Uncommon: no label without Alt')
eq(decide(common), nil, 'Common is dimmed: no label')
eq(decide(potion), nil, 'supplies switched off: hidden')
eq(decide(junk), nil, 'other: only with Alt')
eq(decide(unique).highlight, true, 'unique always')
eq(decide(orb).highlight, true, 'orb always')
eq(decide(power).highlight, true, 'a legendary power always glows')
local noRare = GL.normalize({ rarePlus = false })
eq(decide(rare, false, noRare), nil, 'Rare+ off: Rare is only shown when it glows')
eq(decide(epic, false, noRare).highlight, true, 'Rare+ off: what glows still shows')
local strict = L.normalize({ highlight = 5, dim = 4 })
eq(GL.decide(rare, on, strict, false), nil, 'the filter hides Rare (dim below Epic): no label even with Rare+')
-- Alt
eq(decide(unc, true).dim, false, 'Alt: Uncommon shown')
eq(decide(common, true).dim, true, 'Alt: hidden item shown faded')
eq(decide(potion, true).dim, true, 'Alt: switched-off category shown faded')
eq(decide(junk, true).dim, false, 'Alt: other items')
eq(decide(junk, true, GL.normalize({ altAll = false })), nil, 'Alt switched off in the settings')
eq(GL.decide(epic, GL.normalize({ enabled = false }), filter, true), nil, 'labels off')
eq(GL.decide(nil, on, filter, false), nil, 'no row')

-- corpses
local corpse = { id = 9, k = 1, n = 4, i = { epic, common, potion, { nm = 'gold coin', g = 'currency', c = 30 } }, e = 100 }
local cd = decide(corpse)
eq(cd.kind, 'corpse', 'corpse label')
eq(cd.matches, 1, 'one item glows (the Epic)')
eq(cd.best, epic, 'best item for the colour')
eq(GL.corpseText(corpse, cd), 'Corpse: 1 item', 'singular')
local corpse2 = { id = 9, k = 1, n = 3, i = { epic, rare, unique } }
local cd2 = decide(corpse2)
eq(cd2.matches, 3, 'Epic, Rare (Rare+) and the unique')
eq(cd2.best, unique, 'unique colour wins')
eq(GL.corpseText(corpse2, cd2), 'Corpse: 3 items', 'plural')
local dull = { id = 9, k = 1, n = 2, i = { common, junk } }
eq(decide(dull), nil, 'nothing worth it: no corpse label')
eq(decide(dull, true).dim, true, 'Alt: dull corpse shown faded')
eq(GL.corpseText(dull, decide(dull, true)), 'Corpse: 2 items', 'Alt counts everything')
eq(decide({ id = 9, k = 1, n = 0, i = {} }, true), nil, 'empty corpse: never')
eq(decide(corpse, false, GL.normalize({ corpses = false })), nil, 'corpse labels off')

-- ---------------------------------------------------------------- text, timer, colour
eq(GL.titleCase('fire sword'), 'Fire Sword', 'title case')
eq(GL.titleCase("knight's axe"), "Knight's Axe", 'apostrophe')
eq(GL.itemText(rare), 'Rare Fire Sword', 'rarity prefix')
eq(GL.itemText(unique), 'Soulreaper', 'unique: its own name')
eq(GL.itemText(orb), '3x Chaos Orb', 'stack count')
eq(GL.itemText(junk), 'Bone', 'plain')
eq(GL.timerText(102), '1:42', '1:42')
eq(GL.timerText(7), '0:07', 'seconds')
eq(GL.timerText(3723), '1:02:03', 'hours')
eq(GL.timerText(-5), '0:00', 'never negative')
local timed = { id = 1, nm = 'sword', r = 3, g = 'equipment', c = 1, e = 120, at = 1000 }
eq(GL.secondsLeft(timed, 1018), 102, 'counts down from when it arrived')
eq(GL.secondsLeft(timed, 5000), 0, 'stops at 0')
eq(GL.secondsLeft(rare, 5000), nil, 'no decay')
eq(GL.text(timed, decide(timed), on, 1018), 'Rare Sword  1:42', 'Rare Sword  1:42')
eq(GL.text(timed, decide(timed), GL.normalize({ timers = false }), 1018), 'Rare Sword', 'timers off')
local timedJunk = { id = 3, nm = 'bone', g = 'other', c = 1, e = 50, at = 0 }
eq(GL.showTimer(timedJunk, decide(timedJunk, true), on), false, 'no timer for junk (Alt)')
corpse.at = 0
eq(GL.text(corpse, cd, on, 10), 'Corpse: 1 item  1:30', 'corpse timer')
eq(GL.color(epic, decide(epic)), L.RARITY[4].color, 'Epic colour')
eq(GL.color(unique, decide(unique)), L.UNIQUE_COLOR, 'unique colour')
eq(GL.color(orb, decide(orb)), L.ORB_COLOR, 'orb colour')
eq(GL.color(junk, decide(junk, true)), GL.TEXT_COLOR, 'plain colour')
eq(GL.color(common, decide(common, true)), GL.DIM_COLOR, 'faded colour')
eq(GL.color(corpse2, cd2), L.UNIQUE_COLOR, 'corpse in its best item colour')
local tip = GL.corpseTooltip({ n = 14, i = { unique, orb } })
eq(tip:find('[Unique] Soulreaper', 1, true) ~= nil, true, 'tooltip lists the unique')
eq(tip:find('3x Chaos Orb', 1, true) ~= nil, true, 'tooltip counts')
eq(tip:find('and 12 more', 1, true) ~= nil, true, 'tooltip: the rest')

-- ---------------------------------------------------------------- priority and cap
eq(GL.priority(unique, decide(unique)) > GL.priority(epic, decide(epic)), true, 'unique first')
eq(GL.priority(epic, decide(epic)) > GL.priority(rare, decide(rare)), true, 'higher rarity first')
eq(GL.priority(rare, decide(rare)) > GL.priority(junk, decide(junk, true)), true, 'Rare before junk')
eq(GL.priority(junk, decide(junk, true)) > GL.priority(common, decide(common, true)), true, 'faded last')
local many = {}
for i = 1, 100 do many[i] = { prio = i % 3, dist = i % 7, order = i } end
local kept = GL.select(many)
eq(#kept, GL.MAX_LABELS, 'capped at 40')
eq(kept[1].prio, 2, 'best first')
eq(kept[1].dist, 0, 'then nearest')
eq(#GL.select({ { prio = 1, dist = 1 } }), 1, 'fewer than the cap')

-- ---------------------------------------------------------------- layout
local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local function check(groups, o, what)
  local boxes = GL.layout(groups, o)
  local abs = {}
  for _, g in ipairs(groups) do
    local b = boxes[g.key]
    abs[#abs + 1] = { x = g.ax + b.x, y = g.ay + b.y, w = b.w, h = b.h, key = g.key, ax = g.ax, ay = g.ay }
  end
  for i = 1, #abs do
    for j = i + 1, #abs do
      if overlap(abs[i], abs[j]) then
        eq(false, true, what .. ': ' .. abs[i].key .. ' overlaps ' .. abs[j].key)
      end
    end
  end
  return boxes, abs
end
-- one lone label: centred, its bottom `lift` above the tile centre
local boxes = check({ { key = 'a', ax = 100, ay = 100, w = 80, h = 16 } }, { lift = 10 }, 'single')
eq(boxes.a.x, -40, 'centred')
eq(boxes.a.y, -26, 'bottom 10 px above the anchor')
-- a row of five tiles side by side with wide labels (64 px tiles, 150 px labels): all overlap at first
local row = {}
for i = 1, 5 do row[i] = { key = 't' .. i, ax = i * 64, ay = 0, w = 150, h = 16 } end
local _, abs = check(row, { gap = 2, lift = 10, maxShift = 192 }, 'row of five')
for _, a in ipairs(abs) do
  eq(a.y + a.h <= a.ay and a.ay - a.y <= 10 + 16 + 192 + 18, true, a.key .. ' stays near its tile')
end
-- a 4 x 3 cluster of tiles, each with a 3-label block, plus a tall block in the middle
local cluster = { { key = 'mid', ax = 128, ay = 64, w = 120, h = 50 } }
for x = 0, 3 do
  for y = 0, 2 do
    cluster[#cluster + 1] = { key = x .. ':' .. y, ax = x * 64, ay = y * 64, w = 100, h = 3 * 17 }
  end
end
check(cluster, { gap = 2, lift = 10, maxShift = 192 }, 'cluster')
-- the same tile twice (two blocks on one anchor) never share a spot
check({ { key = 'p', ax = 0, ay = 0, w = 60, h = 16 }, { key = 'q', ax = 0, ay = 0, w = 60, h = 16 } }, { gap = 1 }, 'same anchor')
-- when going up would go too far, it goes down
local capped = GL.layout({ { key = 'a', ax = 0, ay = 0, w = 60, h = 100 }, { key = 'b', ax = 0, ay = 0, w = 60, h = 16 } },
  { gap = 0, lift = 0, maxShift = 50 })
eq(capped.b.y >= 0, true, 'moved down below the tall block')
-- widget box: the engine centres the widget, the block keeps its offset inside it
local wb = GL.widgetBox({ x = -40, y = -26, w = 80, h = 16 })
eq(wb.w, 80, 'widget width')
eq(wb.h, 52, 'widget height (symmetric around the centre)')
eq(wb.cx, 0, 'block x in the widget')
eq(wb.cy, 0, 'block y in the widget (top half)')
wb = GL.widgetBox({ x = -30, y = 10, w = 60, h = 16 })
eq(wb.h, 52, 'below the centre')
eq(wb.cy, 36, 'block in the lower half')
eq(GL.filterKey(filter) ~= GL.filterKey(strict), true, 'filter fingerprint changes')
eq(GL.filterKey(nil), '', 'no filter')

-- the loot label accent cosmetic: only the background of highlighted labels, the rarity colour stays
local hl = { kind = 'item', highlight = true, dim = false }
local plain = { kind = 'item', highlight = false, dim = false }
local st = GL.style(hl, '#ffd040')
eq(st.background, GL.HIGHLIGHT_BACKGROUND, 'default highlight background')
eq(GL.setAccent('#0a1632f0'), '#0a1632f0', 'accent set')
st = GL.style(hl, '#ffd040')
eq(st.background, '#0a1632f0', 'accent behind a highlighted label')
eq(st.text, '#ffd040', 'rarity text colour kept') eq(st.border, '#ffd040', 'rarity border kept')
eq(GL.style(plain, '#ffd040').background, GL.PLAIN_BACKGROUND, 'labels that do not glow keep theirs')
eq(GL.setAccent('url(evil)'), nil, 'a bad colour is ignored')
eq(GL.style(hl, '#4a90ff').background, GL.HIGHLIGHT_BACKGROUND, 'back to the default')

print(string.format('groundlabels_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
