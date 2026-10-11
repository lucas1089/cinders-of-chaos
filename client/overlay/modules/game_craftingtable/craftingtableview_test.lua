-- luajit craftingtableview_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'craftingtableview.lua')
local V = CraftingTableView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function ok(c, m) n = n + 1 if not c then error(m or 'check', 2) end end
local function has(text, part, m) n = n + 1 if not tostring(text):find(part, 1, true) then error((m or '') .. ': ' .. tostring(text), 2) end end

-- categories and skills
eq(#V.CATEGORIES, 7, 'seven categories')
eq(V.skillIndex('generalcrafting'), 0, 'general crafting = skill 7 = index 0')
eq(V.skillIndex('herbalist'), 3, 'herbalist = skill 10')
eq(V.skillIndex('jewelsmith'), 6, 'jewelsmith = skill 13')
eq(V.skillIndex('nope'), nil, 'unknown category')
eq(V.fmtNum(1234567), '1,234,567', 'thousands')
eq(V.goldText(1000), '1,000 gp', 'gold')

-- message parsing
eq(V.parse({ action = 'show', data = { category = 'mining' } }).category, 'mining', 'show')
eq(V.parse({ action = 'show', data = { category = 'bogus' } }).kind, nil, 'show of an unknown category ignored')
eq(V.parse({ action = 'money', data = 5300 }).money, 5300, 'money')
eq(V.parse({ action = 'craft', data = { success = true } }).kind, 'accepted', 'craft accepted')
local m = V.parse({ action = 'message', data = { kind = 'ok', text = 'done' } })
eq(m.kind, 'message', 'message') eq(m.ok, true, 'message ok') eq(m.text, 'done', 'message text')
eq(V.parse({ action = 'message', data = { kind = 'error', text = 'no' } }).ok, false, 'error message')
eq(V.parse({ action = 'tip', data = { category = 'mining', craftId = 3, tip = false } }).tip, nil, 'tip false')
eq(V.parse({ action = 'tip', data = { category = 'mining', craftId = 3, tip = { name = 'x' } } }).tip.name, 'x', 'tip')
eq(V.parse({ action = 'chunkedFetch', chunkData = { msgID = 'a' } }).kind, 'chunk', 'chunk')
eq(V.parse('junk').kind, nil, 'junk')
eq(V.parse({ action = 'materials', data = {} }).kind, nil, 'unused action ignored')

-- chunks: out of order, duplicates, two messages interleaved
local st = V.newState()
eq(V.addChunk(st, { msgID = 'p1', index = 2, count = 3, payload = 'BB' }), nil, 'part 2 of 3')
eq(V.addChunk(st, { msgID = 'p2', index = 1, count = 1, payload = 'only' }), 'only', 'one-piece message')
eq(V.addChunk(st, { msgID = 'p1', index = 2, count = 3, payload = 'BB' }), nil, 'duplicate part')
eq(V.addChunk(st, { msgID = 'p1', index = 1, count = 3, payload = 'AA' }), nil, 'part 1 of 3')
eq(V.addChunk(st, { msgID = 'p1', index = 3, count = 3, payload = 'CC' }), 'AABBCC', 'joined in order')
eq(st.chunks.p1, nil, 'joined message forgotten')
eq(V.addChunk(st, { msgID = 'x', index = 4, count = 3, payload = 'z' }), nil, 'index past count ignored')
eq(V.addChunk(st, { msgID = 'x', index = 1, count = 1 }), nil, 'no payload ignored')

-- fetch pages
local function raw(i, extra)
  local r = { index = i, name = 'Recipe ' .. i, id = 26700 + i, clientId = 9000 + i, level = 10 + i, cost = 1000,
    count = 1, storage = 0, playerStorage = -1, storageText = '',
    materials = { { id = 26712, clientId = 5001, count = 2, player = 3, name = 'pruning knife' },
      { id = 26729, clientId = 5002, count = 5, player = 4, name = 'leaf' } } }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end
eq(V.missingPages(st, 'herbalist')[1], 1, 'unknown category: page 1 first')
local page1 = {}
for i = 1, 10 do page1[i] = raw(i) end
eq(V.applyFetch(st, { category = 'herbalist', page = 1, totalPages = 4, crafts = page1 }), 'herbalist', 'page 1')
eq(#V.missingPages(st, 'herbalist'), 3, 'three pages missing')
eq(V.missingPages(st, 'herbalist')[1], 2, 'next page 2')
ok(not V.loaded(st, 'herbalist'), 'not loaded yet')
V.applyFetch(st, { category = 'herbalist', page = 2, totalPages = 4, crafts = { raw(11, { name = 'Silver Scissor',
  materials = { { id = 1, count = 1, player = 1 } } }) } })
V.applyFetch(st, { category = 'herbalist', page = 3, totalPages = 4, crafts = {} })
V.applyFetch(st, { category = 'herbalist', page = 4, totalPages = 4,
  crafts = { raw(31, { storage = 50000, playerStorage = 0, storageText = 'Read the herb book.' }) } })
ok(V.loaded(st, 'herbalist'), 'all pages in')
eq(V.applyFetch(st, { category = 'bogus', page = 1, crafts = {} }), nil, 'unknown category ignored')
local list = V.recipes(st, 'herbalist')
eq(#list, 12, '12 recipes')
eq(list[1].index, 1, 'sorted by index')
eq(list[12].index, 31, 'last recipe')
ok(list[12].locked, 'storage recipe locked')
ok(not list[1].locked, 'storage 0 not locked')
eq(list[1].materials[2].have, 4, 'have count from the server')
eq(list[1].materials[2].need, 5, 'need count')
eq(V.haveNeed(list[1].materials[2]), '4/5', 'have/need text')
eq(V.materialName(list[11].materials[1], 'fallback'), 'fallback', 'unnamed material: fallback name')
eq(V.materialName(list[1].materials[1]), 'pruning knife', 'material name')
eq(V.pageOf(1), 1, 'page of 1') eq(V.pageOf(10), 1, 'page of 10') eq(V.pageOf(11), 2, 'page of 11')

-- a page sent again after a craft replaces the counts
local again = raw(1)
again.materials[2].player = 9
V.applyFetch(st, { category = 'herbalist', page = 1, totalPages = 4, crafts = { again } })
eq(V.recipes(st, 'herbalist')[1].materials[2].have, 9, 'count updated')
V.markStale(st, 'herbalist')
eq(#V.missingPages(st, 'herbalist'), 4, 'stale: every page asked again')
eq(#V.recipes(st, 'herbalist'), 12, 'stale: recipes stay on screen')

-- checks
local r = V.recipes(st, 'herbalist')[1] -- level 11, 1000 gp, 2 knives (has 3), 5 leaves (has 9)
local ctx = { money = 5000, skill = 20, atTable = 'herbalist', near = true }
local c = V.check(r, ctx)
ok(c.ok, 'craftable') ok(c.mats[1] and c.mats[2], 'both materials enough')
c = V.check(r, { money = 500, skill = 20, atTable = 'herbalist', near = true })
ok(not c.ok, 'no gold') eq(c.reasons[1], 'gold', 'gold reason')
has(V.blockText(c, r, { money = 500 }), '1,000 gp', 'gold text')
c = V.check(r, { money = 5000, skill = 5, atTable = 'herbalist' })
eq(c.reasons[1], 'skill', 'skill reason')
has(V.blockText(c, r, { skill = 5 }), 'Herbalist 11 (yours 5)', 'skill text')
c = V.check(r, { money = 5000, atTable = 'herbalist' })
ok(c.ok, 'unknown skill does not block')
c = V.check(r, { money = 5000, skill = 20, atTable = 'mining' })
ok(not c.ok and c.recipeOk, 'other table: blocked, recipe ok')
has(V.blockText(c, r, {}), 'Herbalist table', 'table text')
c = V.check(r, { money = 5000, skill = 20 })
eq(c.reasons[1], 'table', 'opened from nowhere: table reason')
c = V.check(r, { money = 5000, skill = 20, atTable = 'herbalist', near = false })
eq(c.reasons[1], 'away', 'walked away')
local short = V.recipes(st, 'herbalist')[2] -- 4 of 5 leaves
c = V.check(short, ctx)
eq(c.reasons[1], 'materials', 'materials reason')
ok(c.mats[1] and not c.mats[2], 'per material flags')
local locked = V.recipes(st, 'herbalist')[12]
c = V.check(locked, ctx)
eq(c.reasons[1], 'locked', 'locked first')
has(V.blockText(c, locked, ctx), 'Read the herb book.', 'unlock text')

-- how many
eq(V.maxCraftable(r, 5000), 1, 'knives limit: 3 / 2 = 1')
eq(V.maxCraftable(r, 500), 0, 'gold limit')
r.materials[1].have = 10
eq(V.maxCraftable(r, 2500), 1, 'leaves 9/5 = 1')
r.materials[2].have = 50
eq(V.maxCraftable(r, 3500), 3, 'gold 3500/1000 = 3')
eq(V.maxCraftable({ materials = {}, cost = 0 }, 0), V.MAX_REPEAT, 'free recipe capped')
eq(V.clampQty(0, 3), 1, 'at least 1') eq(V.clampQty(9, 3), 3, 'at most max') eq(V.clampQty('2', 3), 2, 'text')

-- search and filter
eq(#V.filter(list, '', 'all', ctx), 12, 'all')
eq(#V.filter(list, 'silver', 'all', ctx), 1, 'by name')
eq(#V.filter(list, 'LEAF', 'all', ctx), 11, 'by material name, any case')
eq(#V.filter(list, '  recipe 5 ', 'all', ctx), 1, 'trimmed')
local craftable = V.filter(V.recipes(st, 'herbalist'), '', 'craftable', { money = 5000, skill = 15, atTable = 'mining' })
-- recipe 1 has its materials (10 knives, 50 leaves after the edits above); recipes 2..10 are a leaf short or over
-- skill 15; 11 has its material but needs level 21; 31 is locked
eq(#craftable, 1, 'craftable now (the table aside)')
eq(craftable[1].index, 1, 'the craftable one')

-- rows and tooltips
eq(V.rowSub({ level = 10, cost = 1500, count = 1 }), 'Lv 10  -  1,500 gp', 'row sub')
has(V.rowSub({ level = 10, cost = 1500, count = 5 }), 'x5', 'row sub with count')
has(V.plainTip(r), 'Herbalist level 11', 'plain tip')
eq(V.tipKey('mining', 4), 'craftingtable:mining:4', 'tip key')

-- crafting bonus (server craft_bonus.lua through patch_base_crafting_bonus.py)
eq(V.pctText(12), '12%', 'whole percent')
eq(V.pctText(0.4), '0.4%', 'tenths')
eq(V.pctText(17.25), '17.25%', 'hundredths')
eq(V.bonusText(r), '', 'no bonus: no line')
local g = V.recipe(raw(40, { bonus = { kind = 'gear', level = 37, odds = {
  { rarity = 5, name = 'Legendary', pct = 0.6 }, { rarity = 3, name = 'Rare', pct = 4.5 },
  { rarity = 1, name = 'Common', pct = 18 }, { rarity = 2, name = 'junk', pct = 0 }, 'junk' } } }), 'armorsmith')
eq(V.bonusText(g), 'Rarity at item level 37: Common 18% / Rare 4.5% / Legendary 0.6%', 'gear odds, lowest first')
has(V.plainTip(g), 'Rarity at item level 37', 'plain tip names the odds')
local s = V.recipe(raw(41, { bonus = { kind = 'stack', odds = { { extra = 5, pct = 4 }, { extra = 3, pct = 17.5 } } } }),
  'herbalist')
eq(V.bonusText(s), 'Bonus yield: +3 at 17.5% / +5 at 4%', 'stack odds')
eq(V.recipe(raw(42, { bonus = { kind = 'stack', odds = {} } }), 'herbalist').bonus.kind, 'stack', 'empty odds kept')
eq(V.bonusText(V.recipe(raw(42, { bonus = { kind = 'stack', odds = {} } }), 'herbalist')), '', 'empty odds: no line')
eq(V.recipe(raw(43, { bonus = { kind = 'other', odds = {} } }), 'herbalist').bonus, nil, 'unknown kind ignored')
eq(V.recipe(raw(44, { bonus = false }), 'herbalist').bonus, nil, 'false ignored')

-- progress and repeat
eq(V.progress(nil, 100), 0, 'no craft')
eq(V.progress(1000, 1430), 50, 'half way')
eq(V.progress(1000, 5000), 100, 'capped')
eq(V.repeatDelay(nil, 0), 0, 'first request at once')
eq(V.repeatDelay(1000, 1900), 250, 'wait for the cooldown')
eq(V.repeatDelay(1000, 9000), 0, 'cooldown over')

-- requests
local q = V.request('craft', { category = 'mining', craftId = 2 })
eq(q.action, 'craft', 'request action') eq(q.data.craftId, 2, 'request data')
eq(type(V.request('fetch').data), 'table', 'request data defaults to a table')

print('craftingtableview_test: ' .. n .. ' checks OK')
