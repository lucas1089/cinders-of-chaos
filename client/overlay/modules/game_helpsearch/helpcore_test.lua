-- luajit helpcore_test.lua && lua5.3 helpcore_test.lua (CI runs every client module test from the repo root)
-- helpcore.lua with the real data (How it works cards, helpsearch_data.lua, the Codex): folding (UTF-8 and cp1252),
-- words and plurals, synonyms, the ranking of the owner's examples in English and pt-BR (with and without accents), title
-- matches first, "where does it come from" questions, the first steps, snippets and their length.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, count = 0, 0
local function eq(a, b, what)
  count = count + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(v, what) eq(v and true or false, true, what) end

dofile(dir .. '../game_howitworks/howitworks_data.lua')
dofile(dir .. 'helpsearch_data.lua')
dofile(dir .. '../game_codex/codex_data.lua')
dofile(dir .. 'helpcore.lua')
local C = HelpCore

-- folding: UTF-8 (the data) and cp1252 (the client's text box) give the same ASCII
eq(C.fold('N\195\173vel'), 'nivel', 'UTF-8 accent off')
eq(C.fold('N\237vel'), 'nivel', 'cp1252 accent off')
eq(C.fold('Masmorras, Fac\195\167\195\181es!'), 'masmorras, faccoes!', 'cedilla and tilde')
eq(C.fold('\226\128\148x'), ' x', 'another UTF-8 letter becomes a space')

-- words
local t = C.tokens('How do I get Orbs?')
eq(#t, 1, 'small words out')
eq(t[1], 'orb', 'plural cut')
eq(C.tokens('como subir de n\195\173vel')[1], 'subir', 'pt small words out')
eq(C.stem('niveis'), 'nivel', 'niveis')
eq(C.stem('faccoes'), 'faccao', 'faccoes')
eq(C.stem('itens'), 'item', 'itens')
eq(C.stem('bounties'), 'bounty', 'bounties')
eq(C.stem('boss'), 'boss', 'boss keeps its ss')
eq(C.expand('orbe').orb, C.WEIGHT.synonym, 'orbe -> orb')
eq(C.expand('masmorra').dungeon, C.WEIGHT.synonym, 'masmorra -> dungeon')
eq(C.expand('orb').orb, 1, 'the word itself counts fully')

-- the index
local ix = C.buildIndex(HowData, HelpSearchData, CodexData)
local cards, codex = 0, 0
for _, d in ipairs(ix.docs) do
  if d.kind == 'card' then cards = cards + 1 elseif d.kind == 'codex' then codex = codex + 1 end
end
eq(cards, #HowData.features, 'every card is in the index')
ok(codex > 100, 'the Codex entries are in the index (' .. codex .. ')')
eq(ix.cards.bounty.menu, 'Adventure > Bounty Board', 'a card knows its menu path')
eq(ix.cards.rift.level, 100, 'a card knows its level from its unlock entry')

local function top(q, n)
  local r = C.search(ix, q, n or 5)
  local out = {}
  for i, x in ipairs(r) do out[i] = x.doc.kind .. ':' .. x.doc.key end
  return out, r
end
local function has(list, id)
  for _, v in ipairs(list) do if v == id then return true end end
  return false
end

-- the owner's examples
local r = top('how do I get orbs')
ok(r[1] and r[1]:match('^card:'), 'orbs: a card first (where orbs come from)')
ok(has(top('how do I get orbs', 8), 'card:bounty'), 'orbs: the Bounty Board pays orbs')
r = top('gems')
ok(has(r, 'card:crafting'), 'gems: the Crafting Bench')
ok(has(top('gems', 8), 'codex:gem:sockets') and has(top('gemas', 8), 'codex:gem:sockets'), 'gems / gemas: the Codex page on sockets')
r = top('como subir de nivel')
eq(r[1], 'card:goals', 'como subir de nivel: Next Goals')
eq(top('como subir de n\195\173vel')[1], 'card:goals', 'with the accent (UTF-8)')
eq(top('como subir de n\237vel')[1], 'card:goals', 'with the accent (cp1252, the text box)')
eq(top('masmorras')[1], 'card:dungeons', 'masmorras: Dungeons (pt title)')
eq(top('dungeons')[1], 'card:dungeons', 'dungeons')
eq(top('fendas')[1], 'card:rift', 'fendas: Rifts')
eq(top('pets')[1], 'card:pets', 'pets')
eq(top('onde guardar itens')[1], 'card:stash', 'onde guardar itens: Supply Stash')
eq(top('orb of fate')[1], 'codex:orb:divine', 'orb of fate: its Codex page first (title)')
r = top('what happens if I die')
ok(r[1] and r[1]:match('^card:'), 'if I die: a card with a death row')
eq(top('torre infinita')[1], 'card:tower', 'torre: Infinity Tower by synonym')
eq(#C.search(ix, 'how do I'), 0, 'only small words: nothing')
eq(#C.search(ix, 'zzzzqx'), 0, 'an unknown word: nothing')
eq(#C.search(ix, 'rift', 3), 3, 'the limit')

-- title matches come first
local _, full = top('guild')
eq(full[1].doc.key, 'guild', 'guild: the Guild card')
ok(full[1].score > full[#full].score, 'sorted by score')
ok(C.isSource('como conseguir orbes') and C.isSource('how do I get gems') and not C.isSource('gems'), 'source questions')

-- snippets
local words = C.tokens('if I die')
local s = C.snippet(ix.cards.arena, words, 'en')
ok(s:find('death', 1, true) ~= nil, 'the snippet is the row that answers: ' .. s)
s = C.snippet(ix.cards.arena, C.tokens('morrer'), 'pt-BR')
ok(s:find('morte', 1, true) ~= nil, 'pt snippet: ' .. s)
ok(#C.snippet(ix.cards.tower, {}, 'en') <= C.SNIPPET, 'snippet length')
eq(C.shorten('one two three four', 12), 'one two...', 'cut at a space')
eq(C.shorten('short', 12), 'short', 'short text kept')

-- the first steps
local steps = C.firstSteps(ix, HelpSearchData)
eq(#steps, #HelpSearchData.steps, 'every first step has its card')
eq(steps[1].doc.key, HelpSearchData.steps[1].card, 'in order')
ok(steps[1].tip.pt ~= nil and steps[1].tip.en ~= nil, 'tips in both languages')

-- an unlock entry without a card is its own result
local own = C.buildIndex(HowData, { cards = {}, unlocks = { { key = 'x', level = 40, menu = 'Xylo Menu',
  title = { en = 'Xylophone', pt = 'Xilofone' }, why = { en = 'Play music.', pt = 'Toque musica.' } } } }, nil)
local u = C.search(own, 'xilofone')
eq(u[1] and u[1].doc.kind, 'unlock', 'unlock entry found by its pt title')
eq(u[1] and u[1].doc.level, 40, 'with its level')

print(('helpcore_test: %d of %d checks failed'):format(fails, count))
if fails > 0 then os.exit(1) end
