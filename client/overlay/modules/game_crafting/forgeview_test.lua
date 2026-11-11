-- luajit forgeview_test.lua && lua5.3 forgeview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
-- The forge window's view logic (forgeview.lua): rows from a server state, tab counts, which actions are enabled and why,
-- the current step, the cost with both counts, the request that is only sent for an explained action. FORGE_DUMP=file
-- writes the text rows of the sample states (the review picture's source).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'forgeview.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function has(text, part, what)
  checks = checks + 1
  if type(text) ~= 'string' or not text:find(part, 1, true) then
    print('FAIL ' .. what .. ': ' .. tostring(text)); fails = fails + 1
  end
end
local V = CraftingForgeView

-- the tooltip's tier colours are the ones of the window
dofile(dir .. '../game_itemtooltip/tooltiplogic.lua')
for i = 1, 8 do eq(V.TIER_COLORS[i], ItemTooltipLogic.TIER_COLORS[i], 'tier colour ' .. i .. ' as the item tooltip') end
eq(#V.TIER_COLORS, #ItemTooltipLogic.TIER_COLORS, 'as many tier colours')

-- ---------------------------------------------------------------- the sample
local info = { orbs = {
  { key = 'ember', name = 'Ember Orb', clientId = 25045, text = 'Raises a modifier one tier.' },
  { key = 'reforging', name = 'Orb of Reforging', clientId = 25048, text = 'Rolls tier and value again.' },
  { key = 'excision', name = 'Orb of Excision', clientId = 25049, text = 'Removes the modifier.' },
  { key = 'binding', name = 'Orb of Binding', clientId = 25047, text = 'Binds a modifier.' },
  { key = 'exalted', name = 'Orb of Grafting', clientId = 29855, text = 'Adds a modifier.' },
  { key = 'unveiling', name = 'Orb of Unveiling', clientId = 25046, text = 'Reveals the veil.' },
  { key = 'tempering', name = 'Orb of Tempering', clientId = 24483, text = 'Rolls the values.' },
  { key = 'chaos', name = 'Orb of Upheaval', clientId = 29856, text = 'Rerolls everything.' },
  { key = 'void', name = 'Void Orb', clientId = 678, text = 'Corrupts.' },
  { key = 'sockets', name = 'Orb of Sockets', clientId = 32005, text = 'Sockets.' }
}, reasons = {
  needMod = 'Choose a modifier of the item first.', badMod = 'That modifier cannot be chosen for this orb.',
  allBound = 'Every modifier of this item is bound.', corrupted = 'This item is corrupted: no orb can change it any more.',
  keyNoMods = 'This Rift Key has no modifiers.', needRarity = 'This orb works only on an item with a rarity.',
  noMods = 'This item has no modifier to remove.', keySockets = 'Rift Keys have no sockets.',
  voidRarity = 'A Void Orb works only on Rare or better gear.', keyOrb = 'This orb does not work on Rift Keys.' } }
local forge = { orbs = {
  ember = { kind = 'mod', safety = 'safe' }, reforging = { kind = 'mod', safety = 'random' },
  excision = { kind = 'mod', safety = 'risky' }, binding = { kind = 'mod', safety = 'safe' },
  exalted = { kind = 'add', safety = 'random' }, unveiling = { kind = 'add', safety = 'safe' },
  tempering = { kind = 'whole', safety = 'random' }, chaos = { kind = 'whole', safety = 'risky' },
  void = { kind = 'whole', safety = 'risky' }, sockets = { kind = 'sockets', safety = 'random' } } }

local function helmet()
  return { path = '0', id = 2475, sig = 'S1', name = 'Iron Visage', rarity = 4, rarityName = 'Rare', level = 82, quality = 12,
    sockets = { count = 1, max = 2 }, maxMods = 6, prefixes = { 3, 3 }, suffixes = { 3, 3 }, free = { prefix = 0, suffix = 0 },
    mods = {
      { key = 'a1', group = 'chaos', text = '+37 Armour', tier = 6, side = 'prefix', lo = 30, hi = 40, v = 37 },
      { key = 'a2', group = 'chaos', text = '+58 maximum Life', tier = 3, side = 'prefix', lo = 50, hi = 60, v = 58 },
      { key = 'a3', group = 'chaos', text = '+12% Physical damage', tier = 2, side = 'prefix', lo = 10, hi = 14, bound = true, v = 12 },
      { key = 'b1', group = 'absorb', text = 'Fire +32%', tier = 5, side = 'suffix', lo = 30, hi = 34 },
      { key = 'b2', group = 'absorb', text = 'Earth +24%', tier = 3, side = 'suffix', lo = 22, hi = 26, v = 24 },
      { key = 'b3', group = 'skill', text = 'Shielding +2', tier = 1, side = 'suffix', lo = 2, hi = 2, v = 2 } },
    orbs = { ember = '', reforging = '', excision = '', binding = '', exalted = 'full', unveiling = 'notVeiled', tempering = '',
      chaos = '', void = '', sockets = '' },
    pick = { ember = { 'a1', 'a2', 'b1', 'b2', 'b3' }, reforging = { 'a1', 'a2', 'b1', 'b2', 'b3' },
      excision = { 'a1', 'a2', 'b1', 'b2', 'b3' }, binding = { 'a1', 'a2', 'b1', 'b2', 'b3' } } }
end
local reasonsFull = info.reasons
info.reasons.full = 'This item has no free modifier slot.'
info.reasons.notVeiled = 'This item has no veiled modifier.'
local function stateOf(item, bag, stash)
  local counts = {}
  for k, v in pairs(bag) do counts[k] = v end
  for k, v in pairs(stash) do counts[k] = (counts[k] or 0) + v end
  return { counts = counts, bag = bag, stash = stash, item = item }
end
local BAG = { ember = 3, reforging = 12, excision = 4, binding = 2, exalted = 0, unveiling = 0, tempering = 31, chaos = 18, void = 0, sockets = 3 }
local STASH = { ember = 4, reforging = 0, excision = 0, binding = 0, exalted = 5, unveiling = 0, tempering = 0, chaos = 0, void = 0, sockets = 0 }
local state = stateOf(helmet(), BAG, STASH)
local function ctx(sel, explain, st)
  return { info = info, forge = forge, state = st or state, sel = sel or {}, explain = explain, mod = sel and sel.mod }
end

-- ---------------------------------------------------------------- the modifiers in groups
local groups = V.groupList(state.item)
eq(#groups, 2, 'two groups: prefixes and suffixes')
eq(groups[1].side, 'prefix', 'prefixes first') eq(groups[2].side, 'suffix', 'then suffixes')
eq(#groups[1].rows, 3, 'three prefixes') eq(#groups[2].rows, 3, 'three suffixes')
eq(groups[1].rows[1].tierText, 'T6', 'tier text') eq(groups[1].rows[1].color, V.tierColor(6), 'tier colour')
eq(groups[1].rows[3].bound, true, 'bound') eq(groups[1].rows[3].mark, 'BOUND', 'bound mark')
eq(groups[1].rows[2].rangeText, '50 to 60', 'range') eq(groups[2].rows[3].rangeText, '2', 'a one-value range')
eq(groups[1].rows[2].frac, 0.8, 'the roll sits at 80% of its range (58 in 50 to 60)') eq(groups[2].rows[3].frac, 1, 'a one-value range is full')
eq(V.keepSelection(state.item, 'a2'), 'a2', 'a modifier still there stays chosen')
eq(V.keepSelection(state.item, 'zz'), nil, 'a modifier that went is no longer chosen')
eq(V.keepSelection(state.item, nil), nil, 'no choice stays none')

-- ---------------------------------------------------------------- the item
local h = V.header(state.item)
eq(h.name, 'Iron Visage', 'name') eq(h.color, V.rarityColor(4), 'rarity colour')
has(h.line, 'Rare', 'rarity') has(h.line, 'item level 82', 'item level') has(h.line, 'quality 12%', 'quality') has(h.line, 'sockets 1/2', 'sockets')
eq(h.free, 'Free slots: 0 prefix, 0 suffix', 'free slots from the server')
local openItem = helmet()
openItem.free = { prefix = 1, suffix = 2 }
eq(V.freeText(openItem), 'Free slots: 1 prefix, 2 suffix', 'free slots')
openItem.free = nil
openItem.prefixes, openItem.suffixes = { 2, 3 }, { 1, 3 }
eq(V.freeText(openItem), 'Free slots: 1 prefix, 2 suffix', 'free slots from the limits when the server sends no free')
local locked = helmet() locked.locked = true
eq(V.header(locked).lock, 'Locked', 'lock state')
local corrupt = helmet() corrupt.corrupted = true
has(V.header(corrupt).line, 'CORRUPTED', 'corrupted')
local uniq = helmet() uniq.unique = true
has(V.header(uniq).line, 'Unique item', 'unique')
eq(V.header(nil).name, 'Empty bench', 'empty bench')

-- ---------------------------------------------------------------- the actions and why not
local actions = V.actions(ctx())
eq(#actions, 10, 'every orb of the server list is an action')
local ember = V.find(actions, 'ember')
eq(ember.kind, 'mod', 'kind from forgeinfo') eq(ember.tag, 'safe', 'tag from forgeinfo') eq(ember.total, 7, 'total = bag + stash')
eq(ember.bag, 3, 'bag') eq(ember.stash, 4, 'stash')
eq(ember.can, false, 'an action aimed at a modifier waits for one') eq(ember.why, 'Choose a modifier of the item first.', 'the server reason')
actions = V.actions(ctx({ mod = 'a2' }))
ember = V.find(actions, 'ember')
eq(ember.can, true, 'ember with a modifier chosen') eq(ember.why, '', 'no reason')
eq(V.find(actions, 'tempering').can, true, 'a whole-item action needs no modifier')
local exalted = V.find(actions, 'exalted')
eq(exalted.can, false, 'no free slot') eq(exalted.why, 'This item has no free modifier slot.', 'the server reason, not a client one')
eq(exalted.total, 5, 'stash only: still counted')
local void = V.find(actions, 'void')
eq(void.can, false, 'no void orb') eq(void.why, 'You have no Void Orb.', 'no orb in bag or stash')
eq(V.find(actions, 'unveiling').why, 'This item has no veiled modifier.', 'the server reason before the count')
actions = V.actions(ctx({ mod = 'zz' }))
eq(V.find(actions, 'ember').why, 'That modifier cannot be chosen for this orb.', 'a modifier the orb cannot take')
-- old client state: no bag / stash tables, counts only
local old = stateOf(helmet(), {}, {})
old.bag, old.stash = nil, nil
old.counts = { ember = 2 }
local oa = V.find(V.actions({ info = info, forge = forge, state = old, mod = 'a1' }), 'ember')
eq(oa.total, 2, 'counts only') eq(oa.bag, 2, 'all counted as backpack') eq(oa.stash, 0, 'no stash')
-- a reason is always a sentence: a code the table lacks shows a generic text, never the code
local strange = stateOf(helmet(), BAG, STASH)
strange.item.orbs.ember = 'someNewCode'
local sa = V.find(V.actions({ info = info, forge = forge, state = strange, mod = 'a1' }), 'ember')
eq(sa.why, 'This action is not possible on this item.', 'an unknown code is not shown')
-- no forgeinfo yet: whole item, random
local fa = V.find(V.actions({ info = info, forge = nil, state = state }), 'ember')
eq(fa.kind, 'whole', 'no forgeinfo: whole item') eq(fa.tag, 'random', 'and random: never claims safe')
-- no item
local none = stateOf(nil, BAG, STASH)
eq(V.find(V.actions({ info = info, forge = forge, state = none }), 'ember').why, 'Put an item on the bench first.', 'no item')

-- ---------------------------------------------------------------- the tabs and their counts
local tabs = V.tabs(V.actions(ctx({ mod = 'a2' })), state.item)
eq(#tabs, 6, 'four kinds, Salvage, Guide')
eq(tabs[1].id, 'mod', 'shape first') eq(tabs[1].exist, 4, 'four actions on one modifier') eq(tabs[1].can, 4, 'all four can be done')
eq(tabs[2].id, 'add', 'add') eq(tabs[2].exist, 2, 'two actions that add') eq(tabs[2].can, 0, 'none now: no slot, no veil')
eq(tabs[3].id, 'whole', 'whole item') eq(tabs[3].exist, 3, 'three') eq(tabs[3].can, 2, 'void: none owned')
eq(tabs[4].id, 'sockets', 'sockets') eq(tabs[4].exist, 1, 'one') eq(tabs[4].can, 1, 'one')
eq(V.tabText(tabs[1]), 'Shape (4/4)', 'tab text with the count')
eq(V.tabText(tabs[5]), 'Salvage', 'salvage: no count') eq(tabs[6].id, 'guide', 'guide last')
-- a Rift Key has no sockets tab
local key = { path = '1', id = 10155, sig = 'K', kind = 'riftkey', name = 'Rift Key', rarityName = 'Rift Key', tier = 3, level = 120,
  maxMods = 3, mods = { { group = 'rift', key = '4', text = 'Brutality +15' }, { group = 'rift', key = '9', text = 'Swarm +2' } },
  orbs = { ember = 'keyOrb', reforging = 'keyOrb', excision = '', binding = 'keyOrb', exalted = '', unveiling = 'keyOrb', tempering = '',
    chaos = '', void = 'keyOrb', sockets = 'keySockets' }, pick = { excision = { '4', '9' } }, rewards = '+10% quantity' }
local keyState = stateOf(key, BAG, STASH)
local keyTabs = V.tabs(V.actions({ info = info, forge = forge, state = keyState }), key)
eq(#keyTabs, 5, 'no sockets tab on a Rift Key')
for _, t in ipairs(keyTabs) do eq(t.id ~= 'sockets', true, 'tab ' .. t.id) end
local kg = V.groupList(key)
eq(#kg, 1, 'one group of key modifiers') eq(kg[1].side, 'key', 'key group') eq(kg[1].rows[1].tierText, '', 'no tier on a key modifier')
local kh = V.header(key)
has(kh.line, 'Rift Key, tier 3', 'key header') eq(kh.color, V.KEY_COLOR, 'key colour')
-- a normal item with no modifiers
local plainItem = { path = '2', id = 2400, sig = 'P', name = 'Magic Sword', rarity = 0, rarityName = 'Normal', level = 0, mods = {}, pick = {},
  orbs = { ember = 'needRarity', reforging = 'needRarity', excision = 'needRarity', binding = 'needRarity', exalted = 'needRarity',
    unveiling = 'notVeiled', tempering = 'needRarity', chaos = 'needRarity', void = 'voidRarity', sockets = '' }, sockets = { count = 0, max = 3 } }
local plainState = stateOf(plainItem, BAG, STASH)
for _, kind in ipairs({ 'plainItem', 'keyItem' }) do
  local st = kind == 'plainItem' and plainState or keyState
  for _, a2 in ipairs(V.actions({ info = info, forge = forge, state = st, mod = '4' })) do
    eq(a2.why == '' or a2.why:find(' ', 1, true) ~= nil, true, 'no code as a reason: ' .. kind .. ' ' .. a2.key)
  end
end
eq(#V.groupList(plainItem), 0, 'no groups, no empty headers')
eq(V.freeText(plainItem), '', 'no slots line without a limit')
eq(V.find(V.actions({ info = info, forge = forge, state = plainState }), 'ember').why, 'This orb works only on an item with a rarity.', 'why on a normal item')

-- ---------------------------------------------------------------- the materials strip
local mats = V.materials(ctx())
eq(#mats, 10, 'one entry per material')
eq(mats[1].name, 'Ember Orb', 'a short name') eq(mats[2].name, 'Reforging', '"Orb of" left off')
eq(mats[1].count, 7, 'bag plus stash') eq(mats[1].dim, false, 'owned: lit') eq(mats[9].dim, true, 'none owned: dim')
has(mats[1].tip, '3 in backpack, 4 in stash', 'the tip counts both') has(mats[1].tip, 'Raises a modifier one tier.', 'the tip has what it does')

-- ---------------------------------------------------------------- the steps
local cur, done = V.step(ctx({}, nil, none))
eq(cur, 1, 'no item: step 1') eq(done[1], false, 'nothing done')
cur, done = V.step(ctx({}))
eq(cur, 2, 'an item: step 2') eq(done[1], true, 'step 1 done') eq(done[2], false, 'step 2 not')
cur, done = V.step(ctx({ orb = 'ember', mod = 'a2' }))
eq(cur, 3, 'an action chosen, not explained: step 3') eq(done[2], true, 'step 2 done')
local ex = { orb = 'ember', mod = 'a2', sig = 'S1', ok = true, kind = 'mod', tag = 'safe', text = 'Guaranteed: tier 3 to tier 4. The value rolls 61 to 72.',
  change = { kind = 'tier', text = '+58 maximum Life', from = { tier = 3, lo = 50, hi = 60 }, to = { tier = 4, lo = 61, hi = 72 } },
  cost = { orb = 'ember', n = 1, bag = 3, stash = 4, from = 'bag' } }
cur, done = V.step(ctx({ orb = 'ember', mod = 'a2' }, ex))
eq(cur, 4, 'explained: step 4') eq(done[3], true, 'step 3 done') eq(done[4], false, 'forge not done')
local stale = { orb = 'ember', mod = 'a2', sig = 'OLD', ok = true }
eq(V.step(ctx({ orb = 'ember', mod = 'a2' }, stale)), 3, 'an answer for another version of the item is no answer')
local other = { orb = 'ember', mod = 'a1', sig = 'S1', ok = true }
eq(V.step(ctx({ orb = 'ember', mod = 'a2' }, other)), 3, 'an answer for another modifier is no answer')
local refused = { orb = 'ember', mod = 'a2', sig = 'S1', ok = false, reason = 'allBound', reasonText = 'Every modifier of this item is bound.' }
eq(V.step(ctx({ orb = 'ember', mod = 'a2' }, refused)), 3, 'a refusal stays at step 3')

-- ---------------------------------------------------------------- the request: only for an explained action
local req, why = V.request(ctx({ orb = 'ember', mod = 'a2' }))
eq(req, nil, 'no apply before the server answered') has(why, 'Wait', 'says to wait')
req = V.request(ctx({ orb = 'ember', mod = 'a2' }, stale))
eq(req, nil, 'no apply for a stale answer')
req = V.request(ctx({ orb = 'ember', mod = 'a2' }, refused))
eq(req, nil, 'no apply for a refusal')
req = V.request(ctx({ orb = 'ember', mod = 'a2' }, ex))
eq(req ~= nil, true, 'apply once explained')
eq(req.orb, 'ember', 'orb') eq(req.mod, 'a2', 'mod') eq(req.path, '0', 'path') eq(req.sig, 'S1', 'sig') eq(req.id, 2475, 'id')
req, why = V.request(ctx({}, ex))
eq(req, nil, 'no apply without an action chosen')
local poor = stateOf(helmet(), { ember = 0 }, { ember = 0 })
poor.item.orbs.ember = ''
req, why = V.request({ info = info, forge = forge, state = poor, sel = { orb = 'ember', mod = 'a2' }, explain = ex })
eq(req, nil, 'no apply without the orb') eq(why, 'You have no Ember Orb.', 'says so')
req = V.request(ctx({ orb = 'tempering' }, { orb = 'tempering', sig = 'S1', ok = true }))
eq(req ~= nil, true, 'a whole-item action needs no modifier') eq(req.mod, nil, 'and sends none')

-- ---------------------------------------------------------------- the bottom bar
local bar = V.bar(ctx({ orb = 'ember', mod = 'a2' }, ex))
eq(bar.can, true, 'forge on') eq(bar.tag, 'safe', 'tag') has(bar.summary, 'Raise tier', 'summary') has(bar.summary, '+58 maximum Life', 'names the modifier')
has(bar.detail, 'Guaranteed: tier 3 to tier 4.', 'the server words') has(bar.cost, 'Costs 1 Ember Orb (backpack first, then stash)', 'cost')
eq(bar.confirm, nil, 'a safe action asks nothing')
local ex2 = { orb = 'excision', mod = 'a2', sig = 'S1', ok = true, tag = 'risky', text = 'Guaranteed: this modifier is removed. The others stay.' }
bar = V.bar(ctx({ orb = 'excision', mod = 'a2' }, ex2))
eq(bar.tag, 'risky', 'risky') has(bar.confirm, 'Orb of Excision can cost you modifiers', 'a risky action asks once')
local ex3 = { orb = 'chaos', sig = 'S1', ok = true, tag = 'risky', lead = 'random', warn = true, text = 'Stays Rare: 6 new modifiers.' }
bar = V.bar(ctx({ orb = 'chaos' }, ex3))
has(bar.detail, 'Random: Stays Rare', 'a random lead') has(bar.detail, 'This can cost you modifiers.', 'and the warning')
bar = V.bar(ctx({}))
eq(bar.can, false, 'no action: forge off') has(bar.why, 'Pick an action', 'says so')
bar = V.bar(ctx({}, nil, none))
has(bar.why, 'Put an item', 'no item')
eq(V.costLine(V.find(V.actions(ctx({ mod = 'a2' })), 'ember')), 'Cost: 1 Ember Orb. You have 7 (3 in backpack, 4 in stash).', 'the cost line with both counts')
eq(V.resultLine({ ok = true, text = 'Done.', from = 'stash' }), 'Done. (the orb came from the stash)', 'result from the stash')
eq(V.resultLine({ ok = true, text = 'Done.', from = 'bag' }), 'Done.', 'result from the bag')
eq(V.explainText(refused), 'Every modifier of this item is bound.', 'a refusal in the server words')


-- ---------------------------------------------------------------- the polished layout
-- the stepper: done / now / next, the colour of each from the theme palette
local st = V.stepper(ctx({ orb = 'ember', mod = 'a2' }, ex))
eq(#st, 4, 'four steps') eq(st[1].state, 'done', 'step 1 done') eq(st[3].state, 'done', 'step 3 done') eq(st[4].state, 'now', 'step 4 now')
eq(st[1].color, V.C.bright, 'done: ember gold bright') eq(st[4].color, V.C.gold, 'now: ember gold') eq(st[1].lineLit, true, 'a line after a done step is lit')
st = V.stepper(ctx({}, nil, none))
eq(st[1].state, 'now', 'no item: step 1 now') eq(st[2].color, V.C.off, 'later: disabled grey')
-- the chips: pitch floor(864 / n), at least 36, then a second row
local pitch, per, nrows = V.chipLayout(18, 864)
eq(pitch, 48, '18 orbs: a 48 px pitch') eq(per, 18, 'one row of 18') eq(nrows, 1, 'one row')
pitch, per, nrows = V.chipLayout(20, 864)
eq(pitch, 43, '20 orbs: floor(864 / 20)') eq(nrows, 1, 'still one row')
pitch, per, nrows = V.chipLayout(24, 864)
eq(pitch, 36, '24 orbs: the 36 px floor') eq(nrows, 1, 'one row of 24')
pitch, per, nrows = V.chipLayout(30, 864)
eq(pitch, 36, '30 orbs: still 36') eq(per, 24, '24 to a row') eq(nrows, 2, 'a second row')
eq(select(3, V.chipLayout(2, 864)), 1, 'few orbs: one row') eq(V.chipLayout(2, 864), 48, 'few orbs: never wider than 48')
local chips = V.chips(ctx({ orb = 'ember', mod = 'a2' }, ex))
eq(chips[1].use, true, 'the orb of the chosen action is marked') eq(chips[2].use, false, 'the others are not') eq(chips[1].countText, '7', 'count')
-- the item panel
local ip = V.itemPanel(state.item)
eq(ip.rarityText, 'Rare', 'rarity text') eq(ip.rarityColor, V.rarityColor(4), 'rarity colour') eq(ip.level, 82, 'level')
eq(ip.quality.q, 12, 'quality') eq(ip.quality.cap, 0, 'no cap sent: no fraction') eq(ip.quality.frac, 0, 'a bar of zero')
local capped = helmet() capped.qualityCap = 20
eq(V.itemPanel(capped).quality.frac, 0.6, 'quality 12 of 20')
eq(ip.sockets.filled, 0, 'sockets: none filled in the sample') eq(ip.sockets.max, 2, 'sockets max')
local gemmed = helmet() gemmed.sockets = { count = 2, max = 3, list = { { id = 5 }, { id = 0 }, 5 } }
eq(V.itemPanel(gemmed).sockets.filled, 1, 'one gem in the list')
eq(ip.prefix.used, 3, 'prefix pips used') eq(ip.prefix.max, 3, 'prefix pips total') eq(ip.suffix.used, 3, 'suffix pips used')
eq(ip.free, 'no free slot', 'no free slot')
local one = helmet() one.free = { prefix = 1, suffix = 0 }
eq(V.itemPanel(one).free, '1 free', 'one free') one.free = { prefix = 1, suffix = 2 }
eq(V.itemPanel(one).free, '3 free', 'several free')
local kp = V.itemPanel(key)
has(kp.line, 'Rift Key', 'a key has its own line') eq(kp.keyMods.used, 2, 'key pips used') eq(kp.keyMods.max, 3, 'key pips total')
eq(V.itemPanel(nil).name, 'Empty bench', 'empty panel')
-- the cards and the short reason
eq(V.cut('short', 24), 'short', 'a short text stays')
eq(V.cut('This orb works only on an item with a rarity.', 24), 'This orb works only...', 'cut at a word with ...')
eq(#V.cut('Averyveryverylongwordwithoutanyspaces here', 20) <= 20, true, 'never longer than asked')
local cards = V.cards(V.actions(ctx({ orb = 'ember', mod = 'a2' })), 'mod', { orb = 'ember', mod = 'a2' })
eq(#cards, 4, 'four cards') eq(cards[1].chosen, true, 'the chosen card') eq(cards[1].stripe, V.C.good, 'safe: the good green')
eq(cards[1].sub, 'Ember Orb', 'a card shows the orb name') eq(cards[1].dim, false, 'a usable card is bright')
eq(cards[3].stripe, V.C.blood, 'risky: blood') eq(cards[2].stripe, V.C.gold, 'random: ember gold')
local wholeCards = V.cards(V.actions(ctx({ mod = 'a2' })), 'whole', {})
local voidCard
for _, c in ipairs(wholeCards) do if c.key == 'void' then voidCard = c end end
eq(voidCard.dim, true, 'a card that cannot be done is dim') eq(voidCard.subIsReason, true, 'it shows the reason') eq(voidCard.sub, 'You have no Void Orb.', 'the short reason')
has(voidCard.tip, 'You have no Void Orb.', 'the tooltip has the whole sentence')
eq(V.cardsFit(4, 104), true, 'two lines fit') eq(V.cardsFit(6, 104), true, 'three lines fit exactly') eq(V.cardsFit(7, 104), false, 'four lines need a scrollbar')
-- the sentence, the compare row, the cost row
eq(V.firstSentence('Guaranteed: tier 3 to tier 4. The value rolls 61 to 72.'), 'Guaranteed: tier 3 to tier 4.', 'the first sentence')
local se = V.sentence(ex)
eq(se.lead, 'Guaranteed:', 'the lead word') eq(se.leadColor, V.C.good, 'green') eq(se.text, 'tier 3 to tier 4. The value rolls 61 to 72.', 'the rest')
local sr = V.sentence(ex3)
eq(sr.lead, 'Random:', 'random lead') eq(sr.leadColor, V.C.gold, 'amber') eq(sr.warn, 'This can cost you modifiers.', 'the warning')
local cmp = V.compare(ex)
eq(cmp.kind, 'tier', 'a tier change') eq(cmp.left.pill, 'T3', 'before: T3') eq(cmp.left.text, '50 to 60', 'before: its range')
eq(cmp.right.pill, 'T4', 'after: T4') eq(cmp.right.text, '61 to 72', "after: the NEW tier's range (not the old one)") eq(cmp.tail, 'up 1 tier', 'up one tier')
has(ex.text, 'rolls ' .. ex.change.to.lo .. ' to ' .. ex.change.to.hi, 'the sentence and the change agree')
eq(V.compare({ ok = true, change = { kind = 'tier', from = { tier = 3, lo = 1, hi = 1 }, to = { tier = 5, lo = 2, hi = 2 } } }).tail, 'up 2 tiers', 'two tiers')
local bc = V.compare({ ok = true, change = { kind = 'bind', text = '+58 maximum Life' } })
eq(bc.right.bound, 'BOUND', 'bind: the BOUND mark') eq(bc.left.text, '+58 maximum Life', 'bind: the modifier')
local rc = V.compare({ ok = true, change = { kind = 'remove', text = '+58 maximum Life' } })
eq(rc.right.text, 'removed', 'remove: removed') eq(rc.right.color, V.C.blood, 'in blood')
local qc = V.compare({ ok = true, change = { kind = 'quality', from = 12, to = 13 } })
eq(qc.left.text, 'Quality 12%', 'quality before') eq(qc.right.text, '13%', 'quality after')
eq(V.compare({ ok = true, text = 'x' }), nil, 'no change table: no compare row (the text alone)')
eq(V.compare({ ok = false, change = { kind = 'bind' } }), nil, 'a refusal: no compare row')
eq(V.compare({ ok = true, change = { kind = 'mystery' } }), nil, 'an unknown change: none')
local cr = V.costRow(V.find(V.actions(ctx({ mod = 'a2' })), 'ember'))
eq(cr.name, 'Cost: 1 Ember Orb', 'cost name') eq(cr.have, 'you have 7 · 3 backpack · 4 stash', 'cost have')
-- the FORGE button and the bottom lines
local go = V.go(ctx({ orb = 'ember', mod = 'a2' }, ex))
eq(go.enabled, true, 'enabled') eq(go.risky, false, 'safe') eq(go.sub, 'spends 1 Ember Orb', 'sub line')
go = V.go(ctx({ orb = 'excision', mod = 'a2' }, ex2))
eq(go.risky, true, 'a risky action') eq(go.sub, 'risky: asks to confirm', 'risky sub line') eq(go.enabled, true, 'still enabled')
go = V.go(ctx({}))
eq(go.enabled, false, 'nothing chosen: off') eq(go.sub, 'Pick an action first.', 'the reason as sub line')
local bl = V.barLines(ctx({ orb = 'ember', mod = 'a2' }, ex), nil)
eq(bl.verb, 'Raise tier on', 'line 1 verb') eq(bl.target, '+58 maximum Life', 'line 1 target') eq(bl.guarantee, 'Guaranteed: tier 3 to tier 4.', 'line 2: one short sentence')
eq(bl.result.text, '', 'no result before the first craft') eq(bl.result.mark, nil, 'no mark')
bl = V.barLines(ctx({ orb = 'ember', mod = 'a2' }, ex), { ok = true, text = 'Iron Visage: Armour rose.', from = 'stash' })
eq(bl.result.mark, 'ok', 'a good result') has(bl.result.text, 'Last: Iron Visage: Armour rose.', 'the text') has(bl.result.text, 'stash', 'from the stash')
bl = V.barLines(ctx({ orb = 'ember', mod = 'a2' }, ex), { ok = false, text = 'You have no Ember Orb.' })
eq(bl.result.mark, 'fail', 'a refusal')
bl = V.barLines(ctx({}), nil)
eq(bl.verb, 'Choose an action', 'no action chosen') eq(bl.target, '', 'no target')
eq(V.iconCount(678), 100, 'the Void Orb draws with the count pattern of a full stack') eq(V.iconCount(25045), 1, 'other orbs at count 1') eq(V.iconCount(nil), 1, 'no id')
-- palette: only theme colours and the item tooltip's
local allowed = { ['#d6c9ae'] = 1, ['#8c8070'] = 1, ['#6b6258'] = 1, ['#e8b84a'] = 1, ['#f6cf72'] = 1, ['#e03a1e'] = 1, ['#0d0b0e'] = 1, ['#5ccf5c'] = 1 }
for name, c in pairs(V.C) do eq(allowed[c] == 1, true, 'palette colour ' .. name .. ' ' .. c) end
eq(V.C.good, ItemTooltipLogic.COLORS.better, 'the good green is the tooltip\'s')

-- ---------------------------------------------------------------- the classic choice
eq(V.savedMode(nil, 'Ann'), 'forge', 'the forge is the default')
local node = V.rememberMode(nil, 'Ann', 'classic')
eq(V.savedMode(node, 'Ann'), 'classic', 'remembered per character') eq(V.savedMode(node, 'Bob'), 'forge', 'another character keeps the default')
node = V.rememberMode(node, 'Bob', 'classic')
node = V.rememberMode(node, 'Ann', 'forge')
eq(V.savedMode(node, 'Ann'), 'forge', 'back to the forge') eq(V.savedMode(node, 'Bob'), 'classic', 'the other kept')
eq(V.savedMode({ chars = 'junk' }, 'Ann'), 'forge', 'a damaged setting is the default')

-- ---------------------------------------------------------------- hostile shapes: nothing raises
local junk = { 1, 'x', {}, { mods = 5 }, { mods = { 1, 'a', { tier = 'x' } } }, { orbs = 3, pick = 'p' } }
for _, it in ipairs(junk) do
  local st = { counts = 'x', bag = 5, stash = { ember = 'y' }, item = it }
  V.groupList(it) V.header(it) V.freeText(it) V.keepSelection(it, 'a')
  V.actions({ info = { orbs = { 1, { key = 5 }, { key = 'ember', name = {} } }, reasons = 3 }, forge = { orbs = 7 }, state = st, mod = {} })
  V.tabs(V.actions({ info = info, forge = forge, state = st }), it)
  V.bar({ info = info, forge = forge, state = st, sel = { orb = 'ember' }, explain = 5 })
  V.lines({ info = info, forge = forge, state = st, sel = {}, explain = nil })
end
checks = checks + 1

if os.getenv('FORGE_DUMP') then
  local f = assert(io.open(os.getenv('FORGE_DUMP'), 'w'))
  local function dump(title, c)
    f:write('== ' .. title .. '\n')
    for _, l in ipairs(V.lines(c)) do f:write(l .. '\n') end
    f:write('\n')
  end
  dump('Rare helmet: 3 prefixes, 3 suffixes, one bound; a modifier selected, raise a tier chosen', ctx({ orb = 'ember', mod = 'a2' }, ex))
  dump('Item with no modifiers (a Normal sword)', { info = info, forge = forge, state = plainState, sel = {}, explain = nil })
  dump('Rift Key', { info = info, forge = forge, state = keyState, sel = {}, explain = nil })
  dump('Corrupted item', { info = info, forge = forge, state = stateOf((function()
    local c = helmet()
    c.corrupted = true
    c.free = { prefix = 0, suffix = 0 }
    for k in pairs(c.orbs) do c.orbs[k] = 'corrupted' end
    c.pick = {}
    return c
  end)(), BAG, STASH), sel = {}, explain = nil })
  f:close()
end

print(string.format('forgeview_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
