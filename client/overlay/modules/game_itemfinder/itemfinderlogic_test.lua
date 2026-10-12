-- luajit itemfinderlogic_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
dofile(here .. 'itemfinderlogic.lua')
local L = ItemFinderLogic
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- the opcode and the sections
eq(L.OPCODE, 155, 'opcode')
eq(L.title('monster'), 'Monsters and bosses', 'section title')
eq(L.title('sellto'), 'NPCs that buy it', 'use section title')
eq(L.title('xyz'), 'xyz', 'unknown section keeps its key')
eq(#L.SECTIONS, 11, 'every server section has a title')
for _, s in ipairs(L.SECTIONS) do eq(type(L.SHORT[s.k]), 'string', 'short name of ' .. s.k) end

-- the search text and when it goes out
eq(L.query('  orb   of  fate '), 'orb of fate', 'query folded')
eq(#L.query(string.rep('a', 90)), L.MAX_QUERY, 'query cut')
local go, q = L.shouldSearch('o', nil)
eq(go, false, 'too short')
go, q = L.shouldSearch('Orb ', nil)
eq(go, true, 'long enough')
eq(q, 'Orb', 'the trimmed text')
eq(L.shouldSearch('orb', 'ORB'), false, 'the same text again is not sent')
eq(L.shouldSearch('orb of', 'orb'), true, 'a longer text is sent')

-- texts
eq(L.kindsText({ 'monster', 'shop', 'usedin' }), 'drops, shops, used in', 'kinds')
eq(L.kindsText({ 'monster', 'drop', 'reward', 'craft', 'shop' }, 4), 'drops, Chaos drops, rewards, recipes, ...', 'kinds cut')
eq(L.kindsText(nil), '', 'no kinds')
eq(L.pageText(2, 5), '2 / 5', 'page text')
eq(L.totalText(1), '1 source or use', 'one source')
eq(L.totalText(12), '12 sources and uses', 'sources')
eq(L.pageText(1, 1), '', 'one page: no text')
eq(L.sectionHead({ k = 'shop', total = 12, rows = {} }), 'NPCs that sell it (12)', 'section head')
local main, sub, value = L.rowTexts({ n = 'Dragon Lord', d = 'boss, level 300', v = '12.5%', c = 'x1-3', b = true })
eq(main, 'Dragon Lord (boss)', 'boss row')
eq(sub, 'boss, level 300', 'detail')
eq(value, '12.5%  x1-3', 'value and count')
main, sub, value = L.rowTexts({ n = 'Daily reward' })
eq(sub, '', 'no detail')
eq(value, '', 'no value')
eq(L.materialText({ c = 5, n = 'dragon scale' }), '5 x dragon scale', 'material')

-- answers are checked
eq(L.results(nil), nil, 'no results')
local r = L.results({ q = 'drag', p = 1, pages = 2, total = 13, rows = {
  { id = 5000, cid = 4900, name = 'dragon scale', n = 4, kinds = { 'monster' } },
  { id = 'x', name = 'broken' }, 'junk', { id = 5001, name = 7 } } })
eq(#r.rows, 1, 'only valid result rows')
eq(r.rows[1].cid, 4900, 'client id kept')
eq(r.total, 13, 'total')
local it = L.item({ id = 5000, cid = 4900, name = 'dragon scale', total = 3, secs = {
  { k = 'shop', p = 1, pages = 1, total = 1, rows = { { n = 'Agnes', d = 'in Brassgate', v = '4 gold' } } },
  { k = 'monster', p = 1, pages = 3, total = 40, rows = { { n = 'Dragon', v = '25%', c = 'x1-3' }, { d = 'no name' } } },
  { k = 'craft', rows = { { n = 'Mining table', m = { { i = 4900, l = 5000, n = 'dragon scale', c = 5 }, 'junk' } } } },
  'junk', { rows = {} } } })
eq(#it.secs, 3, 'valid sections only')
eq(it.secs[1].k, 'monster', 'sections sorted in the known order')
eq(it.secs[2].k, 'craft', 'craft before shop')
eq(#it.secs[1].rows, 1, 'rows without a name are dropped')
eq(it.secs[2].rows[1].m[1].c, 5, 'material count')
eq(#it.secs[2].rows[1].m, 1, 'junk materials dropped')
eq(it.none, false, 'an item with sources')
local none = L.item({ cid = 33, none = true })
eq(none.none, true, 'no source')
eq(none.cid, 33, 'its client id')
eq(none.name, nil, 'no name')

-- a page of a section
eq(L.applyPage(it, { id = 5000, k = 'monster', p = 2, pages = 3, total = 40, rows = { { n = 'Dragon Lord', v = '50%' } } }), true,
  'page applied')
eq(it.secs[1].p, 2, 'page number')
eq(it.secs[1].rows[1].n, 'Dragon Lord', 'page rows')
eq(L.applyPage(it, { id = 1, k = 'monster', rows = {} }), false, 'a page of another item is ignored')
eq(L.applyPage(it, { id = 5000, k = 'store', rows = {} }), false, 'a section the item has not')
eq(L.applyPage(nil, { id = 5000, k = 'monster' }), false, 'no item shown')

-- history
local h = {}
L.push(h, { id = 1, cid = 2 })
L.push(h, { id = 1, cid = 2 })
eq(#h, 1, 'the same item twice is kept once')
for i = 2, 30 do L.push(h, { id = i, cid = i }) end
eq(#h, L.HISTORY, 'history is capped')
eq(L.pop(h).id, 30, 'back to the last')
eq(#h, L.HISTORY - 1, 'popped')

-- client ids
eq(L.validClientId(3031), true, 'valid client id')
eq(L.validClientId(0), false, 'zero')
eq(L.validClientId(70000), false, 'too big')
eq(L.validClientId('x'), false, 'not a number')

-- the Codex link: on the real Codex data every entry with items maps its server ids
local map = L.codexIndex({ tabs = { { entries = { { id = 'orb:chaos', items = { 29856 } }, { id = 'gem:ruby', items = { 32001, 32002 } },
  { id = 'mod:x' } } } } })
eq(map[29856], 'orb:chaos', 'orb')
eq(map[32002], 'gem:ruby', 'gem tiers')
local ok = pcall(dofile, here .. '../game_codex/codex_data.lua')
if ok and CodexData then
  local real = L.codexIndex(CodexData)
  local count = 0
  for _ in pairs(real) do count = count + 1 end
  eq(count > 100, true, 'the generated Codex has item ids (' .. count .. ')')
  eq(real[29856], 'orb:chaos', 'Orb of Upheaval in the Codex')
  eq(real[32051], 'cur:shard', 'rune shard in the Codex')
  eq(real[32001], 'gem:ruby', 'chipped ruby in the Codex')
  eq(real[32351] ~= nil, true, 'a gathering material in the Codex')
end

print('itemfinderlogic_test: ' .. n .. ' checks ok')
