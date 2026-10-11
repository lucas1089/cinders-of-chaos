-- luajit client/overlay/modules/game_unveil/unveilview_test.lua (also lua5.3; CI runs every client *_test.lua)
-- The Unveil window's logic (unveilview.lua), the veiled block of the item tooltip (game_itemtooltip tooltiplogic.lua) and
-- the market row tag (game_market marketview.lua).
local here = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(here .. '/unveilview.lua')
dofile(here .. '/../game_itemtooltip/tooltiplogic.lua')
dofile(here .. '/../game_market/marketview.lua')
local V, L, MV = UnveilView, ItemTooltipLogic, MarketView
local fails, n = 0, 0
local function eq(a, b, name)
  n = n + 1
  if a ~= b then fails = fails + 1; print('FAIL ' .. name .. ': got ' .. tostring(a) .. ', want ' .. tostring(b)) end
end

-- a window as the server sends it (veiled.lua openDialog)
local open = { path = '3', id = 2400, clientId = 3288, name = 'magic sword', rarity = 5, rarityName = 'Legendary',
  level = 150, sig = 'abc', orbs = 2, offers = {
    { i = 1, key = 'firststrike', name = 'Veilpiercer', text = '+20% damage to monsters above 80% health', tier = 4,
      tn = 'V4', lo = 18, hi = 22, value = 20, hook = true },
    { i = 2, key = 'doombringer', name = 'Doombringer', text = 'Damage to Elites and Bosses +17%', tier = 3, tn = 'V3',
      lo = 17, hi = 20, value = 17 },
    { i = 3, key = 'sundering', name = 'Sundering', text = 'Physical and Elemental Penetration +9%', tier = 2, tn = 'V2',
      lo = 7, hi = 9, value = 9 } } }

eq(V.headerText(open), 'Magic sword  -  Legendary  -  Item Level 150', 'header')
eq(V.headerText(nil), '', 'no data')
eq(V.orbsText(2), 'Orbs of Unveiling: 2', 'orbs')
local cards = V.cards(open)
eq(#cards, 3, 'three cards')
eq(cards[1].name, 'Veilpiercer', 'card name')
eq(cards[1].tierText, 'Veiled tier V4', 'tier text')
eq(cards[1].tierColor, V.TIER_COLORS[4], 'tier colour')
eq(cards[1].rangeText, 'Range 18-22', 'range')
eq(cards[1].hookText, 'Effect of its own', 'hook')
eq(cards[2].hookText, '', 'no hook')
eq(#cards[1].lines > 1, true, 'card text wrapped')
for _, line in ipairs(cards[1].lines) do eq(#line <= V.WRAP, true, 'line fits: ' .. line) end
eq(V.cardText(cards[2]), 'Damage to Elites and Bosses +17%', 'card text')
-- malformed offers are skipped, never more than three
local odd = { offers = { { i = 1 }, 'x', { i = 2, name = 'A', text = 'b' }, { i = 3, name = 'B', text = 'c' },
  { i = 4, name = 'C', text = 'd' }, { i = 5, name = 'D', text = 'e' } } }
eq(#V.cards(odd), 3, 'at most three, malformed skipped')
eq(V.cards(odd)[1].i, 2, 'first valid')
eq(#V.cards({}), 0, 'no offers')
eq(#V.cards(nil), 0, 'nil')

-- selection, confirm and the request
eq(V.canConfirm(open, nil), false, 'nothing selected')
eq(V.canConfirm(open, 4), false, 'not a card')
eq(V.canConfirm(open, 2), true, 'card 2')
local req = V.request(open, 2)
eq(req.choice, 2, 'choice'); eq(req.path, '3', 'path'); eq(req.id, 2400, 'id'); eq(req.sig, 'abc', 'signature')
eq(V.request(open, 7), nil, 'no request for a bad choice')
local noOrb = { orbs = 0, offers = open.offers }
eq(V.canConfirm(noOrb, 1), false, 'no orb, no confirm')
eq(V.statusText(noOrb, 1), 'You have no Orb of Unveiling.', 'no orb text')
eq(V.statusText(open, nil), 'Choose one of the three modifiers. The choice is final.', 'prompt')
eq(V.statusText(open, 3), 'Reveal Sundering? The choice is final and takes one orb.', 'confirm text')
local t, c = V.resultText({ ok = true, text = 'Magic sword: the veil lifts.' })
eq(t, 'Magic sword: the veil lifts.', 'result text'); eq(c, V.COLORS.ok, 'result colour')
t = V.resultText({ ok = true, text = 'long server text', veil = { s = 'open', n = 'Blood Harvest', tn = 'V4' } })
eq(t, 'The veil lifts: Blood Harvest (V4) is yours.', 'short result with the revealed modifier')
t, c = V.resultText({ ok = false, text = 'The item moved or changed.' })
eq(c, V.COLORS.bad, 'refused colour')

-- the tooltip's veiled block
local rows = L.veilLines({ s = 'veiled' })
eq(#rows, 2, 'veiled: two rows')
eq(rows[1].text, 'Veiled modifier', 'veiled title'); eq(rows[1].color, L.COLORS.veiled, 'distinct colour')
eq(rows[1].sep, true, 'own section')
rows = L.veilLines({ s = 'open', n = 'Wraithstride', t = 'Movement Speed +10%, Dodge +5%', tr = 4, tn = 'V4', lo = 8, hi = 10 })
eq(rows[1].text, 'Veiled', 'header'); eq(rows[2].text, 'V4 Wraithstride [8-10]', 'name line')
eq(rows[2].parts[2], L.VEIL_TIER_COLORS[4], 'tier coloured'); eq(rows[3].text, '  Movement Speed +10%, Dodge +5%', 'text')
eq(rows[3].color, L.COLORS.veiledText, 'text colour')
eq(#L.veilLines(nil), 0, 'no veil'); eq(#L.veilLines({ s = 'x' }), 0, 'unknown state')
-- in a whole tooltip: after the modifiers, before the sockets
local tip = { name = 'boots', rarity = 5, rarityName = 'Legendary', level = 150,
  mods = { { k = 'chaos_mod_movespeed', t = 'Movement Speed +9%', tr = 7, sd = 's' } },
  veil = { s = 'veiled' }, sockets = { count = 1, list = { {} } } }
local lines = L.lines(tip, {})
local at, sock, mod = 0, 0, 0
for i, r in ipairs(lines) do
  if r.text == 'Veiled modifier' then at = i end
  if r.text:find('^Sockets') then sock = i end
  if r.text:find('Movement Speed') then mod = i end
end
eq(at > mod and at < sock, true, 'veil between the modifiers and the sockets')

-- market rows
local row = { rarity = 5, ilvl = 140, cat = 'boots', seller = 'Ash', left = 3600, veil = 'veiled' }
eq(MV.subLine(row):find('Veiled', 1, true) ~= nil, true, 'Veiled tag')
row.veil = 'open'
eq(MV.subLine(row):find('Unveiled', 1, true) ~= nil, true, 'Unveiled tag')
row.veil = nil
eq(MV.subLine(row):find('eiled', 1, true), nil, 'no tag')

print(string.format('unveilview_test: %d checks, %d failed', n, fails))
if fails > 0 then os.exit(1) end
