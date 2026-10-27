-- luajit cardborder_test.lua && lua5.3 cardborder_test.lua   (from the repo root or from this folder)
-- Rules of the card borders (cardborderlogic.lua) and their agreement with the payload the server builds
-- (server/data/scripts/chaos/cards_core.lua K.statePayload).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'cardborderlogic.lua')
local L = CardBorderLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local DECK, CARD1, CARD2, OTHER = 27632, 27482, 27483, 2160
local s = L.new()
eq(L.kind(s, DECK, CARD1), nil, 'nothing is drawn before the server spoke')
eq(L.apply(s, { on = { CARD1 }, cards = { CARD1, CARD2 }, decks = { DECK } }), true, 'first message changes')
eq(L.kind(s, DECK, CARD1), 'on', 'a card that is on')
eq(L.kind(s, DECK, CARD2), 'off', 'a card that is off')
eq(L.kind(s, DECK, OTHER), nil, 'not a card: no border')
eq(L.kind(s, 1988, CARD1), nil, 'a card in a plain backpack: no border')
eq(L.kind(s, nil, CARD1), nil, 'unknown container: no border')
eq(L.kind(s, DECK, nil), nil, 'empty slot')
eq(L.kind(s, DECK, '27482'), 'on', 'ids as text')
eq(L.apply(s, { on = { CARD1 }, cards = { CARD2, CARD1 }, decks = { DECK } }), false, 'the same set: nothing to redraw')
eq(L.apply(s, { on = { CARD1, CARD2 }, cards = { CARD1, CARD2 }, decks = { DECK } }), true, 'a card turned on')
eq(L.kind(s, DECK, CARD2), 'on', 'now on')
eq(L.apply(s, { on = {}, cards = { CARD1, CARD2 }, decks = { DECK } }), true, 'all off')
eq(L.kind(s, DECK, CARD1), 'off', 'off')
eq(L.apply(s, nil), true, 'an empty message: no card is known')
eq(L.kind(s, DECK, CARD1), nil, 'no cards known')
L.apply(s, { on = { CARD1 }, cards = { CARD1, CARD2 }, decks = { DECK } })
local plan = L.plan(s, DECK, { CARD1, CARD2, 0, OTHER }, 4)
eq(plan[1], 'on', 'plan 1') eq(plan[2], 'off', 'plan 2') eq(plan[3], false, 'plan empty') eq(plan[4], false, 'plan other')
L.reset(s)
eq(s.known, false, 'reset')
eq(L.kind(s, DECK, CARD1), nil, 'after reset nothing is drawn')
eq(L.style('on') ~= nil and L.style('off') ~= nil and L.style(nil) == nil and L.style('x') == nil, true,
  'a style for on and off only')
eq(L.style('on').color ~= L.style('off').color, true, 'on and off differ')

eq(L.needsPass(true, nil), true, 'a deck is drawn') eq(L.needsPass(false, true), true, 'a former deck window is wiped')
eq(L.needsPass(false, nil), false, 'a plain bag is left alone') eq(L.needsPass(nil, nil), false, 'nil deck')

-- the payload the server builds (the real config and core)
local base
for _, cand in ipairs({ dir .. '../../../../', './', '../' }) do
  local f = io.open(cand .. 'server/data/scripts/chaos/cards_core.lua')
  if f then f:close() base = cand break end
end
if base then
  local oldDofile = dofile
  dofile = function(p) return oldDofile((p:gsub('^data/', base .. 'server/data/'))) end
  dofile(base .. 'server/data/scripts/chaos/cards_core.lua')
  dofile = oldDofile
  local payload = ChaosCardsCore.statePayload({ active = { [27482] = {}, [27547] = {} } })
  local st = L.new()
  L.apply(st, payload)
  eq(L.kind(st, 27632, 27482), 'on', 'server payload: a common card on')
  eq(L.kind(st, 27634, 27547), 'on', 'server payload: a legendary card on in the Golden Deck')
  eq(L.kind(st, 27633, 27483), 'off', 'server payload: another card off')
  eq(L.kind(st, 27633, 2160), nil, 'server payload: gold is not a card')
  eq(L.kind(st, 1987, 27482), nil, 'server payload: a plain bag is no deck')
  local n = 0
  for _ in pairs(st.cards) do n = n + 1 end
  eq(n, 76, 'server payload: 76 cards')
else
  print('note: server files not found, agreement checks skipped')
end

print(string.format('cardborder_test: %d checks, %d failures', checks, fails))
os.exit(fails == 0 and 0 or 1)
