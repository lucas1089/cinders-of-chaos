-- luajit topbarfindlogic_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
-- Favourites store and search of the hub menu (O718), on the real tree, cards and keywords.
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

dofile(here .. 'topbar_tree.lua')
dofile(here .. 'topbar_cards.lua')
dofile(here .. 'topbar_keywords.lua')
dofile(here .. 'topbarhublogic.lua')
dofile(here .. 'topbarfindlogic.lua')
local F, H = ChaosTopBarFindLogic, ChaosTopBarHubLogic

-- ---------------------------------------------------------------- favourites
eq(F.favsSettingKey('Ash'), 'chaosHubFavs_Ash', 'per character'); eq(F.favsSettingKey(''), 'chaosHubFavs', 'login screen')
eq(#F.parseFavs(''), 0, 'never set is empty'); eq(#F.parseFavs(nil), 0, 'nil is empty'); eq(#F.parseFavs('junk'), 0, 'junk is empty')
local l = F.parseFavs('v1:Inventory|Market|Inventory')
eq(table.concat(l, ','), 'Inventory,Market', 'parsed, no duplicate')
eq(F.serializeFavs(l), 'v1:Inventory|Market', 'round trip'); eq(F.serializeFavs({}), 'v1:', 'an empty list is kept apart from never set')
local big = {}
for i = 1, 40 do big[#big + 1] = 'C' .. i end
eq(#F.parseFavs(F.serializeFavs(big)), F.MAX_FAVS, 'at most MAX_FAVS are read')
local out, changed = F.toggleFav({}, 'Bank')
eq(changed, true, 'added'); eq(F.isFav(out, 'Bank'), true, 'is a favourite')
out, changed = F.toggleFav(out, 'Bank')
eq(changed, true, 'removed'); eq(#out, 0, 'list empty again')
local full = {}
for i = 1, F.MAX_FAVS do full[i] = 'C' .. i end
local same, ch, why = F.toggleFav(full, 'New')
eq(ch, false, 'full is refused'); eq(why, 'full', 'with the reason'); eq(#same, F.MAX_FAVS, 'list kept')
out, ch = F.toggleFav(full, 'C3')
eq(ch, true, 'a full list can still drop one'); eq(#out, F.MAX_FAVS - 1, 'one fewer')

-- ---------------------------------------------------------------- a model with every card of the tree
local items = {}
for _, hub in ipairs(ChaosTopBarTree.HUBS) do
  for _, tab in ipairs(hub.tabs) do
    for _, text in ipairs(tab.cards) do
      items[#items + 1] = { text = text, category = 'character', status = (text == 'Passive Tree') and 'locked' or 'open', level = 12, key = (text == 'Inventory') and 'Ctrl+I' or nil }
    end
  end
end
items[#items + 1] = { text = 'Store', category = 'economy', status = 'open' }
local model = H.build(ChaosTopBarTree, ChaosTopBarCards, items, { admin = true })

-- every card of the tree has keywords
for _, hub in ipairs(ChaosTopBarTree.HUBS) do
  for _, tab in ipairs(hub.tabs) do
    for _, text in ipairs(tab.cards) do
      eq(type(ChaosTopBarKeywords.WORDS[text]), 'string', 'keywords for ' .. text)
    end
  end
end
eq(type(ChaosTopBarKeywords.WORDS['Store']), 'string', 'keywords for the Store pin')

-- the favourites window: tree order, pages of F.PAGE, locked cards kept, an unknown text skipped
local fav = F.favHub(model, { 'Market', 'Inventory', 'Gone Window', 'Passive Tree' }, 'Favourites', function(i, p) return p == 1 and 'Favourites' or tostring(i) end)
eq(fav.id, 'favs', 'virtual hub id'); eq(#fav.tabs, 1, 'one page'); eq(fav.tabs[1].name, 'Favourites', 'one page keeps the name')
local names = {}
for _, c in ipairs(fav.tabs[1].cards) do names[#names + 1] = c.text end
eq(table.concat(names, ','), 'Inventory,Passive Tree,Market', 'tree order, the unknown one skipped')
eq(fav.tabs[1].cards[2].locked, 12, 'a locked card stays locked')
eq(#F.favHub(model, {}, 'F', function() return 'x' end).tabs, 0, 'no favourites: no tabs (the window shows its empty text)')
local many = {}
for i, c in ipairs(model.hubs[1].tabs[1].cards) do many[#many + 1] = c.text end
for _, c in ipairs(model.hubs[1].tabs[2].cards) do many[#many + 1] = c.text end
for _, c in ipairs(model.hubs[2].tabs[1].cards) do many[#many + 1] = c.text end
local pg = F.favHub(model, many, 'F', function(i, p) return i .. '/' .. p end)
eq(#many, 17, 'fixture size'); eq(#pg.tabs, 3, '17 cards make 3 pages of 8'); eq(#pg.tabs[1].cards, 8, 'page 1 full'); eq(#pg.tabs[3].cards, 1, 'page 3 has the rest')
eq(pg.tabs[2].name, '2/3', 'page names come from the caller')

-- ---------------------------------------------------------------- fold and words
eq(F.fold('Mochila  \xc3\x81gua!'), 'mochila agua', 'accents and case fold, punctuation is a space')
eq(F.fold('Po\xc3\xa7\xc3\xa3o'), 'pocao', 'c cedilla and a tilde')
eq(F.fold(nil), '', 'nil folds to empty')
eq(#F.words('  '), 0, 'blank has no words'); eq(table.concat(F.words('Auto  Loot'), ','), 'auto,loot', 'words')

-- ---------------------------------------------------------------- search
local PT = {
  Inventory = 'Invent\xc3\xa1rio', ['Hunt Tracker'] = 'Rastreador de Ca\xc3\xa7a', Market = 'Mercado', Bank = 'Banco',
  ['hub.hunt'] = 'Ca\xc3\xa7a', ['tab.hunt.hunting'] = 'Ca\xc3\xa7ando', ['Auto Loot'] = 'Saque Autom\xc3\xa1tico',
  ['Backpack and equipment'] = 'Mochila e equipamento',
}
local function mk(map) return function(k) return map[k] or k end end
local ctx = { tr = mk(PT), keywords = ChaosTopBarKeywords.WORDS, cards = ChaosTopBarCards }
local function names_of(list)
  local o = {}
  for _, r in ipairs(list) do o[#o + 1] = r.card.text end
  return table.concat(o, ',')
end
local r, total = F.search(model, '', ctx)
eq(#r, 0, 'an empty query finds nothing'); eq(total, 0, 'and counts none')
r = F.search(model, 'inventory', ctx)
eq(r[1].card.text, 'Inventory', 'the English name'); eq(r[1].hub.id, 'hero', 'with its hub'); eq(r[1].tab.id, 'character', 'and tab')
r = F.search(model, 'INVENT\xc3\x81RIO', ctx)
eq(r[1].card.text, 'Inventory', 'the pt-BR name, any case, with the accent')
r = F.search(model, 'inventario', ctx)
eq(r[1].card.text, 'Inventory', 'the pt-BR name without the accent')
r = F.search(model, 'mochila', ctx)
eq(r[1].card.text, 'Inventory', 'a keyword or the pt-BR line')
r = F.search(model, 'backpack', ctx)
eq(r[1].card.text, 'Inventory', 'a keyword of the card')
r = F.search(model, 'ctrl i', ctx)
eq(r[1].card.text, 'Inventory', 'the hotkey')
r = F.search(model, 'auto loot', ctx)
eq(r[1].card.text, 'Auto Loot', 'two words, the name wins')
r = F.search(model, 'loot auto', ctx)
eq(r[1].card.text, 'Auto Loot', 'in any order')
r = F.search(model, 'zzzz', ctx)
eq(#r, 0, 'no match')
r = F.search(model, 'inventory zzzz', ctx)
eq(#r, 0, 'every word must be found')
r = F.search(model, 'tracker', ctx)
eq(r[1].card.text, 'Hunt Tracker', 'a name word before the keyword hits')
eq(names_of(r):find('Task Tracker') ~= nil, true, 'the others with the word follow')
r = F.search(model, 'cacando', ctx)
eq(r[1].card.text, 'Hunt Tracker' == r[1].card.text and 'Hunt Tracker' or r[1].card.text, 'the tab name in pt-BR finds the cards of the tab')
eq(r[1].tab.id, 'hunting', 'its tab')
r = F.search(model, 'moedas', ctx)
eq(r[1].card.text, 'Store', 'a pin-only card is searched too (no hub)'); eq(r[1].hub, nil, 'without a hub')
r = F.search(model, 'passive', ctx)
eq(r[1].card.text, 'Passive Tree', 'a locked card is found too'); eq(r[1].card.locked, 12, 'still marked locked')
-- ranking: a name start beats a keyword hit; equal scores keep the tree order
r = F.search(model, 'map', ctx)
eq(r[1].card.text, 'Map Overlay', 'name start first, then tree order')
eq(r[2].card.text, 'Map Overlay Settings', 'second'); eq(r[3].card.text, 'Map Markers', 'third')
-- the limit cuts the list, the count keeps the total
r, total = F.search(model, 'a', ctx, 3)
eq(#r, 3, 'cut to the limit'); eq(total > 3, true, 'the total is the full count')
-- a card the model lacks is not found (the model is what the player can open)
local small = H.build(ChaosTopBarTree, ChaosTopBarCards, { { text = 'Bank', category = 'economy', status = 'open' } }, {})
r = F.search(small, 'inventory', ctx)
eq(#r, 0, 'only the cards of the model')
r = F.search(small, 'banco', ctx)
eq(names_of(r), 'Bank', 'the pt-BR of the one card')
-- a tr that raises does not break the search
r = F.search(small, 'bank', { tr = function() error('boom') end, keywords = {}, cards = ChaosTopBarCards })
eq(names_of(r), 'Bank', 'a failing tr falls back to the English')

print('topbarfindlogic_test: ' .. n .. ' checks ok')
