-- luajit npctalk_logic_test.lua && lua5.3 npctalk_logic_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'npctalk_logic.lua')
dofile(dir .. '../game_spellsupports/supportstext.lua')
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

-- transcript (wrapped with SupportsText.wrap)
local lines = { { who = 'You', text = 'hi' }, { who = 'Dove', text = 'Be greeted, noble traveller, and welcome to the {post office}.' } }
local tt = L.transcript(lines, 30, 16, SupportsText.wrap)
eq(tt, 'You: hi\nDove: Be greeted, noble\n   traveller, and welcome to\n   the post office.', 'transcript wrapped')
eq(L.transcript(lines, 30, 1), 'Dove: Be greeted, noble traveller, and welcome to the post office.', 'transcript last line, no wrap')
for _, line in ipairs({ tt:match('([^\n]*)\n'), 'x' }) do eq(#line <= 30, true, 'wrapped width') end

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

-- placing the bubble
local area = { x = 0, y = 0, width = 800, height = 600 }
local pl = L.place(300, 120, { x = 400, y = 300 }, { x = 400, y = 340 }, area, 22, 12, 4)
eq(pl.below, false, 'room above')
eq(pl.x, 250, 'centred on the npc')
eq(pl.y + 120 + 12 - 3, 300, 'tail tip at the anchor')
eq(pl.tailX, 389, 'tail under the anchor')
eq(pl.tailY, pl.y + 117, 'tail joins the bottom rim')
pl = L.place(300, 120, { x = 20, y = 300 }, { x = 20, y = 340 }, area, 22, 12, 4)
eq(pl.x, 4, 'clamped left')
eq(pl.tailX, 12, 'tail stays on the bubble')
pl = L.place(300, 120, { x = 790, y = 300 }, { x = 790, y = 340 }, area, 22, 12, 4)
eq(pl.x, 496, 'clamped right')
eq(pl.tailX, 496 + 300 - 8 - 22, 'tail at the right end')
pl = L.place(300, 120, { x = 400, y = 60 }, { x = 400, y = 100 }, area, 22, 12, 4)
eq(pl.below, true, 'no room above: below')
eq(pl.y, 100 + 9, 'below the feet')
eq(pl.tailY, 100, 'tail tip at the feet')
pl = L.place(300, 580, { x = 400, y = 100 }, { x = 400, y = 140 }, area, 22, 12, 4)
eq(pl.y >= 4 and pl.y + 580 <= 596, true, 'too tall: inside the map')
pl = L.place(300, 120, { x = 400, y = 300 }, { x = 400, y = 340 }, { x = 10, y = 10, width = 200, height = 100 }, 22, 12, 4)
eq(pl.x, 14, 'map narrower than the bubble: left edge')

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
