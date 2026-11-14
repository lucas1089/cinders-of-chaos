-- luajit npctalk_logic_test.lua && lua5.3 npctalk_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'npctalk_logic.lua')
local L = NpcTalkLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function join(t) return table.concat(t, '|') end

-- keywords
local greet = 'Be greeted, noble Np Skipper and welcome to the post office. Ask me for a {trade} or about {letters}.'
local seg = L.segments(greet)
eq(#seg, 5, 'segments: text, key, text, key, text')
eq(seg[2].text, 'trade', 'first keyword')
eq(seg[2].key, true, 'keyword flag')
eq(seg[1].key, nil, 'plain part')
eq(seg[5].text, '.', 'tail')
eq(L.plain(greet), 'Be greeted, noble Np Skipper and welcome to the post office. Ask me for a trade or about letters.', 'plain')
eq(join(L.keywords(greet)), 'trade|letters', 'keywords')
eq(join(L.keywords({ 'A {Trade}.', 'B {trade} and {twist of fate}?' })), 'Trade|twist of fate', 'keywords once, case-insensitive')
eq(join(L.keywords('no keywords here')), '', 'none')
eq(join(L.keywords('{ spaced }')), 'spaced', 'trimmed')
eq(#L.segments('a {} b'), 1, 'empty braces dropped, parts merged')
eq(L.plain('a {} b'), 'a  b', 'empty braces plain')
eq(L.plain('broken {brace'), 'broken {brace', 'unclosed brace kept')
eq(L.plain(nil), '', 'nil')
eq(join(L.keywords('{a}{b}')), 'a|b', 'adjacent keywords')

-- coloured text
local c, keys = L.coloredText('Ask for a {trade}.', '#111111', '#222222')
eq(#c, 6, 'coloured: three parts')
eq(c[3], '[text-event]trade[/text-event]', 'keyword clickable')
eq(c[4], '#222222', 'keyword colour')
eq(c[2], '#111111', 'text colour')
eq(keys, true, 'has keywords')
c, keys = L.coloredText('plain', nil, nil)
eq(c[1], 'plain', 'plain coloured')
eq(keys, false, 'no keywords')
eq(L.coloredText('{x}', nil, nil, false)[1], 'x', 'not clickable')
eq(#L.coloredText(''), 2, 'empty text still a pair')

-- greetings and farewells
eq(L.isGreeting('hi'), true, 'hi')
eq(L.isGreeting(' Hello! '), true, 'hello!')
eq(L.isGreeting('hi Dove'), true, 'hi name')
eq(L.isGreeting('history'), false, 'history is no greeting')
eq(L.isFarewell('bye'), true, 'bye')
eq(L.isFarewell('Farewell.'), true, 'farewell.')
eq(L.isFarewell('bye bye birdie'), false, 'not just bye')

-- quick buttons
local b = L.buttons({ 'Would you like to receive that protection for 10000 gold, child?' })
eq(b.yes and b.no, true, 'question: yes/no')
eq(b.trade, false, 'no trade talk')
eq(b.bye, true, 'bye always')
b = L.buttons({ 'Welcome.' }, { 'Welcome. Ask me for a {trade}.', 'Welcome.' })
eq(b.yes, false, 'no question')
eq(b.trade, true, 'trade mentioned earlier in the conversation')
eq(L.buttons({ 'Do you want {yes} or {no}' }).yes, true, 'offered yes')
eq(L.buttons({ 'Look at my offers.' }).trade, true, 'offers')
eq(L.buttons({ 'A trader.' }).trade, false, 'trader is not trade')
eq(L.buttons({}, {}, true).trade, true, 'trade window open')

-- chips
eq(join(L.chips({ 'Ask me for a {trade}, {mail} or {Yes}.' }, { trade = true, yes = true })), 'mail', 'chips without buttons')
eq(#L.chips({ '{a} {b} {c} {d}' }, nil, 2), 2, 'chips capped')
local pos, h = L.flow({ 50, 60, 70 }, 120, 20, 4, 4)
eq(pos[1].x, 0, 'flow first')
eq(pos[2].x, 54, 'flow second on row 1')
eq(pos[3].y, 24, 'flow third wraps')
eq(h, 44, 'flow height')
eq(select(2, L.flow({}, 100, 20)), 0, 'no chips no height')
eq(L.flow({ 300 }, 100, 20)[1].width, 100, 'too wide chip capped')

-- geometry: a 15x11 map at 32 px per tile, no stretch
local vis = { width = 15, height = 11 }
local panel = { x = 100, y = 50, width = 482, height = 354 }
local m = L.mapRect(panel, vis, true)
eq(m.width, 480, 'map width')
eq(m.height, 352, 'map height')
eq(m.x, 101, 'map x')
local s = L.stretch(m, vis, 32)
eq(s, 1, 'stretch 1')
local cam = { x = 1000, y = 1000, z = 7 }
local p = L.tileCenter(m, s, 32, cam, nil, cam, nil)
eq(p.x, 101 + 240, 'camera tile centre x')
eq(p.y, 51 + 176, 'camera tile centre y')
p = L.tileCenter(m, s, 32, cam, nil, { x = 1002, y = 999, z = 7 }, nil)
eq(p.x, 341 + 64, 'npc two east')
eq(p.y, 227 - 32, 'npc one north')
eq(L.tileCenter(m, s, 32, cam, nil, { x = 1000, y = 1000, z = 6 }), nil, 'other floor')
-- the player half way through a step east: the map is drawn half a tile back west, so the NPC moves with it
local ox, oy = L.walkOffset({ x = 999, y = 1000, z = 7 }, cam, 0.5, 32)
eq(ox, -16, 'walk offset x')
eq(oy, 0, 'walk offset y')
p = L.tileCenter(m, s, 32, cam, { x = ox, y = oy }, { x = 1002, y = 1000, z = 7 }, nil)
eq(p.x, 341 + 64 + 16, 'player walking shifts the npc')
eq(select(1, L.walkOffset({ x = 990, y = 1000, z = 7 }, cam, 0.5)), 0, 'teleport: no offset')
eq(select(2, L.walkOffset({ x = 1000, y = 1001, z = 7 }, cam, 1)), 0, 'step done')
-- doubled panel: stretch 2; a wide panel without keepAspect cuts the map, the larger factor wins
local big = L.mapRect({ x = 0, y = 0, width = 962, height = 706 }, vis, true)
eq(L.stretch(big, vis, 32), 2, 'stretch 2')
local wide = L.mapRect({ x = 0, y = 0, width = 962, height = 354 }, vis, false)
eq(L.stretch(wide, vis, 32), 2, 'wide: width decides')

-- the NPC's name and title
local who, title = L.splitName('Archivist Maelis')
eq(who, 'Maelis', 'name without the title'); eq(title, 'Archivist', 'the title is a word of the name')
who, title = L.splitName('Osric the Chandler')
eq(who, 'Osric', 'name before "the"'); eq(title, 'Chandler', 'the trade after "the"')
who, title = L.splitName('Veyra the Apothecary')
eq(who, 'Veyra', 'Veyra'); eq(title, 'Apothecary', 'Apothecary')
who, title = L.splitName('Loot Buyer')
eq(who, 'Loot Buyer', 'a job name stays whole'); eq(title, nil, 'and has no title')
who, title = L.splitName('Keeper of Trials')
eq(who, 'Keeper of Trials', 'Keeper of Trials stays whole'); eq(title, nil, 'no title')
who, title = L.splitName('Tavish Coldhand')
eq(who, 'Tavish Coldhand', 'a plain name'); eq(title, nil, 'no title')
who, title = L.splitName('Warden Ysolde')
eq(who, 'Ysolde', 'Warden Ysolde'); eq(title, 'Warden', 'Warden')
who, title = L.splitName('  Elder   Bramwyn ')
eq(who, 'Bramwyn', 'spaces'); eq(title, 'Elder', 'Elder')
who, title = L.splitName('Archivist')
eq(who, 'Archivist', 'a lone word'); eq(title, nil, 'is no title')
who, title = L.splitName(nil)
eq(who, '', 'nil'); eq(title, nil, 'nil title')

-- quest words and the chip groups
eq(L.isQuestWord('quest'), true, 'quest'); eq(L.isQuestWord('Spell Quest'), true, 'a word of the keyword')
eq(L.isQuestWord('lore'), false, 'lore'); eq(L.isQuestWord('ascension'), true, 'ascension')
eq(L.groupOf('trade'), 'trade', 'trade'); eq(L.groupOf('offers'), 'trade', 'offers')
eq(L.groupOf('portugues'), 'language', 'the pt-BR switch word'); eq(L.groupOf('english'), 'language', 'the English one')
eq(L.groupOf('portugu\195\170s'), 'language', 'with the accent')
eq(L.groupOf('ledger'), 'topics', 'ledger'); eq(L.groupOf('quest'), 'quest', 'a quest word is a quest chip')
local groups = L.groups({ 'ledger', 'tales', 'story', 'lore', 'portugues', 'quest', 'trade' })
eq(#groups, 4, 'four groups'); eq(groups[1].id, 'quest', 'quests first'); eq(groups[2].id, 'trade', 'then trade')
eq(groups[3].id, 'topics', 'then topics'); eq(groups[4].id, 'language', 'language last')
eq(join(groups[3].words), 'ledger|tales|story|lore', 'the order of the words is kept')
eq(#L.groups({}), 0, 'no words, no groups'); eq(#L.groups(nil), 0, 'nil')
eq(#L.groups({ 'lore', 'tales' }), 1, 'one group when all are topics')
-- the archivist's greeting (server data/npc/scripts/archivist_maelis.lua): the chips as the owner saw them
local archivist = 'Ash on your boots, Ash. I keep the {ledger}. Ask me for {tales}, the {story} of Cinderhold, or any {lore} you fear. (Diga {portugues} para conversar em portugues.)'
groups = L.groups(L.keywords(archivist))
eq(join(groups[1].words), 'ledger|tales|story|lore', 'topics first when there is nothing more useful'); eq(groups[2].id, 'language', 'the language switch last')
-- the chips in rows with group labels
local widths = { a = 40, b = 50, c = 60, d = 30 }
local flow = L.flowGroups({ { id = 'quest', words = { 'a', 'b' } }, { id = 'topics', words = { 'c', 'd' } } },
  function(w) return widths[w] end, 100, 20, 4, 4, 12)
eq(#flow.labels, 2, 'a label per group'); eq(flow.labels[1].y, 0, 'first label on top')
eq(flow.chips[1].y, 14, 'chips under the label'); eq(flow.chips[2].x, 44, 'second chip beside it')
eq(flow.labels[2].y, 14 + 20 + 4 + 2, 'the next label under the first group')
eq(flow.chips[3].y, flow.labels[2].y + 14, 'its chips under it'); eq(flow.chips[4].x, 64, 'beside')
eq(flow.height, flow.chips[3].y + 20, 'the height')
flow = L.flowGroups({ { id = 'topics', words = { 'a', 'b', 'c' } } }, function(w) return widths[w] end, 100, 20, 4, 4, 12)
eq(#flow.labels, 0, 'one group: no label'); eq(flow.chips[3].y, 24, 'the third wraps'); eq(flow.height, 44, 'two rows')
eq(L.flowGroups({}, function() return 1 end, 100, 20).height, 0, 'nothing, no height')
eq(L.flowGroups({ { id = 'topics', words = { 'x' } } }, function() return 500 end, 100, 20).chips[1].width, 100, 'capped')
-- the role line for a name without a title
eq(L.role({ 'Welcome. {trade} is open.' }, false), 'trade', 'spoke of its trade')
eq(L.role({ 'Ask about the {quest}.' }, false), 'quests', 'has a quest')
eq(L.role({ 'Hello.' }, true), 'trade', 'trade window open')
eq(L.role({ 'Hello {friend}.' }, false), nil, 'nothing to say'); eq(L.role(nil, false), nil, 'no history')

-- the window beside the NPC
local area = { x = 0, y = 0, width = 1200, height = 700 }
eq(select(1, L.windowSize(area)), 480, 'the usual width'); eq(select(2, L.windowSize(area)), 480, 'the usual height')
eq(select(1, L.windowSize({ x = 0, y = 0, width = 300, height = 300 })), 380, 'minimum width')
eq(select(2, L.windowSize({ x = 0, y = 0, width = 500, height = 400 })), 384, 'height less the margins')
local function covers(pl, w, h, c, tile)
  return pl.x < c.x + tile * 0.75 and c.x - tile * 0.75 < pl.x + w and pl.y < c.y + tile * 0.75 and c.y - tile * 1.25 < pl.y + h
end
-- the player stands left of the NPC: the window goes to its right
local npc, ply = { x = 500, y = 350 }, { x = 400, y = 350 }
local pl = L.windowPlace(480, 480, npc, ply, 32, area)
eq(pl.x, 532, 'right of the NPC'); eq(pl.y, 110, 'centred on it'); eq(covers(pl, 480, 480, npc, 32), false, 'not over the NPC')
eq(covers(pl, 480, 480, ply, 32), false, 'not over the player')
-- the player stands right of it: the window goes left
pl = L.windowPlace(480, 480, { x = 700, y = 350 }, { x = 800, y = 350 }, 32, area)
eq(pl.x, 700 - 32 - 480, 'left of the NPC'); eq(covers(pl, 480, 480, { x = 800, y = 350 }, 32), false, 'not over the player')
-- no room on the far side: the near side, if it does not cover the player
pl = L.windowPlace(480, 480, { x = 1000, y = 350 }, { x = 900, y = 600 }, 32, area)
eq(pl.x + 480 <= 1200 - 8, true, 'inside the area'); eq(covers(pl, 480, 480, { x = 900, y = 600 }, 32), false, 'the player is clear')
-- a small map leaves no room beside the NPC: the whole screen is tried next (a side panel may be covered, the character not)
local screen = { x = 0, y = 0, width = 1280, height = 720 }
pl = L.windowPlace(464, 340, { x = 341, y = 227 }, { x = 405, y = 227 }, 32, { x = 101, y = 51, width = 480, height = 352 }, 8, screen)
eq(covers(pl, 464, 340, { x = 341, y = 227 }, 32) or covers(pl, 464, 340, { x = 405, y = 227 }, 32), false, 'a player on the right and no room left of the NPC: a spot that covers neither')
eq(pl.x >= 8 and pl.x + 464 <= 1272, true, 'inside the screen')
pl = L.windowPlace(464, 340, { x = 341, y = 227 }, { x = 280, y = 227 }, 32, { x = 101, y = 51, width = 480, height = 352 }, 8, screen)
eq(pl.x, 341 + 32, 'a player on the left: to the right of the NPC, over the side panel')
-- a small area, no screen: corners and the middle, never over the player or the NPC when there is a way
local small = { x = 0, y = 0, width = 600, height = 500 }
pl = L.windowPlace(480, 480, { x = 300, y = 250 }, { x = 250, y = 250 }, 32, small)
eq(pl.x >= 8 and pl.x + 480 <= 592 and pl.y >= 8 and pl.y + 480 <= 492, true, 'no room at all: still inside the area')
-- an NPC at the top edge: the window is pulled down into the area
pl = L.windowPlace(480, 480, { x = 300, y = 20 }, { x = 250, y = 100 }, 32, area)
eq(pl.y >= 8, true, 'inside at the top'); eq(pl.y + 480 <= 700 - 8, true, 'inside at the bottom')
-- no player known
pl = L.windowPlace(480, 480, { x = 300, y = 350 }, nil, 32, area)
eq(pl.x, 332, 'no player: right of the NPC')
-- the window is never outside the area, whatever the spot
for _, c in ipairs({ { 5, 5 }, { 1195, 5 }, { 5, 695 }, { 1195, 695 }, { 600, 350 } }) do
  local q = L.windowPlace(480, 480, { x = c[1], y = c[2] }, { x = c[1] + 40, y = c[2] }, 32, area)
  eq(q.x >= 8 and q.x + 480 <= 1192 and q.y >= 8 and q.y + 480 <= 692, true, 'inside the area at ' .. c[1] .. ',' .. c[2])
end

-- the visible part of the map: the extended view's map is taller than the window, panels cover its sides
local va = L.visibleArea({ x = 0, y = -80, width = 1280, height = 800 }, { left = 1, right = 1102, top = 38, bottom = 514 })
eq(va.x, 1, 'visible left')
eq(va.y, 38, 'visible top')
eq(va.width, 1101, 'visible width')
eq(va.height, 476, 'visible height')
va = L.visibleArea({ x = 10, y = 10, width = 100, height = 100 }, { left = 500 })
eq(va.width, 0, 'nothing visible')
eq(L.visibleArea({ x = 10, y = 10, width = 100, height = 100 }).width, 100, 'no limits')

-- where to walk for a talk
local tiles = L.approachTiles({ x = 100, y = 100, z = 7 }, { x = 110, y = 100, z = 7 }, 3)
eq(#tiles, 48, 'a 7x7 square less the NPC')
eq(tiles[1].x .. ',' .. tiles[1].y, '103,100', 'nearest tile first, straight towards the player')
eq(tiles[2].x .. ',' .. tiles[2].y, '103,99', 'then its neighbours')
local seenNpc = false
for _, t in ipairs(tiles) do if t.x == 100 and t.y == 100 then seenNpc = true end end
eq(seenNpc, false, 'never the NPC tile')
eq(L.inRange(tiles[#tiles], { x = 100, y = 100, z = 7 }), true, 'all in range')
eq(L.approachTiles({ x = 5, y = 5, z = 7 }, { x = 5, y = 5, z = 7 }, 1)[1].y, 4, 'player on the NPC tile: fixed order')

-- range
eq(L.inRange({ x = 1, y = 1, z = 7 }, { x = 4, y = 3, z = 7 }), true, 'three away')
eq(L.inRange({ x = 1, y = 1, z = 7 }, { x = 5, y = 1, z = 7 }), false, 'four away')
eq(L.inRange({ x = 1, y = 1, z = 7 }, { x = 1, y = 1, z = 6 }), false, 'other floor')
eq(L.distance({ x = 1, y = 1, z = 7 }, { x = 3, y = 4, z = 7 }), 3, 'chebyshev')

-- which window gets an NPC line (O160: the reply never reached the bubble, which stayed at "...")
local modes = { npcFrom = 11, npcFromStartBlock = 51 }
local function route(line, st)
  st.modes = modes
  if st.enabled == nil then st.enabled = true end
  return L.routeNpcLine(line, st)
end
local lootPos = { x = 100, y = 100, z = 7 }
local open = { name = 'Loot Buyer', pos = lootPos }
eq(route({ mode = 51, name = 'Loot Buyer', text = 'Welcome.' }, { conv = open }), 'conv', 'reply of the NPC in the bubble')
eq(route({ mode = 11, name = 'Loot Buyer', text = 'Welcome.' }, { conv = open }), 'conv', 'both NPC modes')
eq(route({ mode = 51, name = 'loot  buyer ', text = 'Welcome.' }, { conv = open }), 'conv', 'case and spacing of the name')
eq(route({ mode = 51, name = 'Loot Buyer:', text = 'Welcome.' }, { conv = open }), 'conv', 'edge punctuation of the name')
eq(route({ mode = 51, name = 'Mr Buyer', text = 'Welcome.', pos = { x = 100, y = 100, z = 7 } }, { conv = open }), 'conv',
  'another name from the tile of the NPC in the bubble')
eq(route({ mode = 51, name = 'Gambler', text = 'Hello.', pos = { x = 103, y = 100, z = 7 } }, { conv = open }), 'console',
  'another NPC stays in the console')
eq(route({ mode = 51, name = 'Gambler', text = 'Hello.' }, { conv = open }), 'console', 'another NPC, no tile')
eq(route({ mode = 1, name = 'Loot Buyer', text = 'Welcome.' }, { conv = open }), 'ignore', 'public talk is no NPC line')
eq(route({ mode = nil, name = 'Loot Buyer', text = 'x' }, { conv = open }), 'ignore', 'no mode')
eq(route({ mode = 51, name = 'Loot Buyer', text = 'Welcome.' }, { conv = open, enabled = false }), 'console', 'window off')
eq(route({ mode = 51, name = '', text = 'Welcome.' }, { conv = open }), 'console', 'no name')
eq(route({ mode = 51, name = 'Loot Buyer', text = '  ' }, { conv = open }), 'console', 'no words')
eq(route({ mode = 51, name = 'Loot Buyer', text = 'Welcome.' }, {}), 'open', 'no conversation: the bubble opens')
eq(route({ mode = 51, name = 'Loot Buyer', text = 'Your loss.' }, { suppressed = true }), 'console', 'farewell after bye')
eq(L.sameName('Loot Buyer', 'Loot Buyers'), false, 'different names')
eq(L.sameName('', ''), false, 'empty names never match')
eq(L.samePos(lootPos, { x = 100, y = 100, z = 7 }), true, 'same tile')
eq(L.samePos(lootPos, { x = 100, y = 100, z = 6 }), false, 'other floor')
eq(L.samePos(nil, lootPos), false, 'no tile')

-- the hook and the talk signal bring the same line
local last = { name = 'Loot Buyer', text = 'Welcome.', at = 1000 }
eq(L.isDuplicate(last, 'Loot Buyer', 'Welcome.', 1000), true, 'same instant')
eq(L.isDuplicate(last, 'Loot Buyer', 'Welcome.', 1040), true, 'within the window')
eq(L.isDuplicate(last, 'Loot Buyer', 'Welcome.', 1400), false, 'a later repeat is a new line')
eq(L.isDuplicate(last, 'Loot Buyer', 'Anything else?', 1000), false, 'other words')
eq(L.isDuplicate(last, 'Gambler', 'Welcome.', 1000), false, 'other speaker')
eq(L.isDuplicate(nil, 'Loot Buyer', 'Welcome.', 1000), false, 'no line before')

print(string.format('npctalk_logic: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
