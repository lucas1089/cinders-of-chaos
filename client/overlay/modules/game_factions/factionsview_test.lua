-- luajit factionsview_test.lua && lua5.3 factionsview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'factionsview.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = FactionsView

eq(V.fmt(1234567), '1,234,567', 'thousands')
eq(V.fmt(950), '950', 'small')
eq(V.fmt(-2500), '-2,500', 'negative')
eq(V.fmt(5250.0), '5,250', 'float input')
eq(V.fmt(nil), '0', 'nil')
eq(V.countdown(93784), '1d 2h', 'days')
eq(V.countdown(4980), '1h 23m', 'hours')
eq(V.countdown(125), '2m', 'minutes')
eq(V.countdown(5), '1m', 'never 0m')

-- a payload shaped like the server's (factions_core.lua K.payload)
local data = {
  now = 0, nextDay = 3600 * 5 + 60 * 12, nextWeek = 86400 * 2 + 3600, weekCap = 7500,
  ranks = { { k = 'hostile', n = 'Hostile', min = -6000 }, { k = 'wary', n = 'Wary', min = -2000 },
    { k = 'neutral', n = 'Neutral', min = 0 }, { k = 'trusted', n = 'Trusted', min = 2500 },
    { k = 'honored', n = 'Honored', min = 8000 }, { k = 'revered', n = 'Revered', min = 18000 },
    { k = 'exalted', n = 'Exalted', min = 36000 } },
  factions = {
    { k = 'vigil', n = 'The Ashen Vigil', s = 'Vigil', rival = 'choir', rep = 5250, rank = 4, rn = 'Trusted', lo = 2500,
      hi = 8000, pct = 50, nx = 'Honored', wk = 1200, dr = 1, npc = 'Warden Ysolde', near = true, tok = 7, tn = 'pyre ash sigils' },
    { k = 'choir', n = 'The Veiled Choir', s = 'Choir', rival = 'vigil', rep = -1300, rank = 2, rn = 'Wary', lo = -2000,
      hi = 0, pct = 35, nx = 'Neutral', wk = 0, dr = 0.5, npc = 'Cantor Velith', tok = 0, tn = 'veiled eyes' },
    { k = 'circle', n = 'The Thornbound Circle', s = 'Circle', rival = 'compact', rep = 36000, rank = 7, rn = 'Exalted',
      lo = 36000, hi = 36000, pct = 100, ex = true, wk = 7500, dr = 0.2, npc = 'Elder Bramwyn', near = true, tok = 3,
      tn = 'thornbound leaves' },
  },
  contracts = {
    { key = 'w:20261005:vigil:1', f = 'vigil', per = 'w', kind = 'invasion', label = 'Stand against an invasion', p = 0, n = 1, rep = 1200 },
    { key = 'd:20261010:vigil:2', f = 'vigil', per = 'd', kind = 'deliver', label = 'Deliver', p = 0, n = 1, rep = 300, give = true },
    { key = 'd:20261010:vigil:1', f = 'vigil', per = 'd', kind = 'kill', label = 'Slay 150 Undead', p = 45, n = 150, rep = 300 },
    { key = 'd:20261010:choir:1', f = 'choir', per = 'd', kind = 'rift', label = 'Seal', p = 1, n = 1, rep = 300, done = true },
  },
  offers = {
    { key = 'vigil_plate', f = 'vigil', kind = 'gear', n = 'Vigil Pyreplate', rank = 6, rn = 'Revered', price = 600000,
      tokens = 20, st = 'locked', why = 'Needs Revered with The Ashen Vigil.', lv = 115, rar = 4, mods = { 'T6 Thorns +60' } },
    { key = 'vigil_ash5', f = 'vigil', kind = 'orbs', n = 'Ash-Blessed Orbs', rank = 4, rn = 'Trusted', price = 150000,
      tokens = 0, st = 'ok', wl = 3, wb = 1, desc = '5 Orbs of Upheaval' },
    { key = 'vigil_recipe', f = 'vigil', kind = 'recipe', n = 'Recipe: Pyre Distillation', rank = 5, rn = 'Honored',
      price = 100000, tokens = 0, st = 'owned', desc = '40 rune shards -> 1 Orb of Fate', craft = true },
    { key = 'vigil_mount', f = 'vigil', kind = 'mount', n = 'Vigil Mount', rank = 7, rn = 'Exalted', price = 2000000,
      tokens = 60, st = 'locked', why = 'Needs Exalted.' },
    { key = 'choir_fate2', f = 'choir', kind = 'orbs', n = 'Fate', rank = 6, rn = 'Revered', price = 300000, st = 'soldout',
      wl = 2, wb = 2, why = 'Bought 2 of 2 this week.' },
  },
}

eq(V.select(data, nil), 'vigil', 'first faction')
eq(V.select(data, 'choir'), 'choir', 'keeps the shown one')
eq(V.select(data, 'nope'), 'vigil', 'unknown -> first')
data.sel = 'circle'
eq(V.select(data, 'choir'), 'circle', 'the NPC asked for one')
data.sel = nil

local vigil, choir, circle = V.faction(data, 'vigil'), V.faction(data, 'choir'), V.faction(data, 'circle')
eq(V.cardName(vigil), 'Ashen Vigil', 'card name without The')
eq(V.barText(vigil), 'Trusted  5,250 / 8,000', 'bar text')
eq(V.barPercent(vigil), 50, 'bar percent')
eq(V.barText(circle), 'Exalted  36,000', 'Exalted bar text')
eq(V.nextText(vigil), '2,750 more to Honored', 'next rank')
eq(V.nextText(circle), 'The highest rank.', 'top rank')
eq(V.weekText(vigil, data.weekCap), 'This week 1,200 / 7,500', 'week')
eq(V.weekText({wk = 9000, wc = 12500}, data.weekCap), 'This week 9,000 / 12,500', 'week with a carried cap')
eq(V.capped({wk = 9000, wc = 12500}, data.weekCap), false, 'not capped under the carried cap')
eq(V.capped({wk = 12500, wc = 12500}, data.weekCap), true, 'capped at the carried cap')
eq(V.drText(vigil), 'Kills, tokens and events at full value today', 'dr full')
eq(V.drText(choir), 'Kills, tokens and events at half value today', 'dr half')
eq(V.drText(circle), 'Kills, tokens and events at 20% today', 'dr fifth')
eq(V.capped(circle, 7500), true, 'capped')
eq(V.capped(vigil, 7500), false, 'not capped')
eq(V.rivalText(data, vigil):sub(1, 23), 'Rival: The Veiled Choir', 'rival text')
eq(V.rivalText(data, circle), '', 'rival not in the payload')
eq(V.tokenText(vigil), '7 pyre ash sigils carried', 'tokens')
local en, tip = V.tokenButton(vigil, 7500)
eq(en, true, 'turn in enabled near the NPC')
en, tip = V.tokenButton(choir, 7500)
eq(en, false, 'no tokens')
en, tip = V.tokenButton(circle, 7500)
eq(en, false, 'capped: keep them')
eq(tip, 'No more reputation this week: keep them.', 'capped tooltip')
local away = { tok = 2, npc = 'Warden Ysolde', tn = 'sigils', wk = 0, rep = 0, hi = 1 }
en, tip = V.tokenButton(away, 7500)
eq(en, false, 'away from the NPC')
eq(tip, 'Speak with Warden Ysolde to turn them in.', 'away tooltip')

local cs = V.contractsFor(data, 'vigil')
eq(#cs, 3, 'vigil contracts')
eq(cs[1].key, 'd:20261010:vigil:1', 'daily first, by key')
eq(cs[3].per, 'w', 'weekly last')
eq((V.contractTag(cs[3])), 'Weekly', 'tag')
eq(V.progressText(cs[1]), '45 / 150', 'progress')
eq(V.progressPercent(cs[1]), 30, 'percent')
eq(V.progressText(cs[2]), 'Bring it to the NPC', 'deliver progress')
local shown, enabled = V.deliverButton(cs[2], vigil)
eq(shown and enabled, true, 'deliver near the NPC')
shown, enabled = V.deliverButton(cs[2], choir)
eq(shown and not enabled, true, 'deliver away from the NPC')
shown = V.deliverButton(cs[1], vigil)
eq(shown, false, 'no deliver button on a kill contract')
local done = V.contractsFor(data, 'choir')[1]
eq(V.progressText(done), 'Done', 'done')
eq(V.progressPercent(done), 100, 'done percent')
local open, closed = V.contractsSummary(data, 'vigil')
eq(open, 3, 'open contracts')
eq(closed, 0, 'done contracts')

local os_ = V.offersFor(data, 'vigil')
eq(#os_, 4, 'vigil offers')
eq(os_[1].key, 'vigil_ash5', 'lowest rank first')
eq(os_[4].key, 'vigil_mount', 'Exalted last')
eq(V.priceText(os_[3], vigil), '600,000 gold + 20 pyre ash sigils', 'price with tokens')
eq(V.priceText(os_[1], vigil), '150,000 gold', 'price gold')
local text, on, color = V.offerButton(os_[1], vigil)
eq(text, 'Buy', 'buy')
eq(on, true, 'buy enabled near')
eq(color, V.COLORS.ok, 'buy colour')
text, on = V.offerButton(os_[1], choir)
eq(on, false, 'buy away from the NPC')
text, on = V.offerButton(os_[3], vigil)
eq(text, 'Locked', 'locked')
eq(on, false, 'locked disabled')
text, on = V.offerButton(os_[2], vigil)
eq(text, 'Craft', 'owned recipe crafts')
eq(on, true, 'craft enabled near')
text, on = V.offerButton(V.offersFor(data, 'choir')[1], choir)
eq(text, 'Sold out', 'sold out')
eq(V.offerKindText(os_[1]), '5 Orbs of Upheaval (1 of 3 this week)', 'orbs line')
eq(V.offerKindText(os_[3]), 'Item level 115, Rare', 'gear line')
local tt = V.offerTooltip(os_[3], vigil)
eq(tt:find('T6 Thorns +60', 1, true) ~= nil, true, 'tooltip modifiers')
eq(tt:find('Needs Revered', 1, true) ~= nil, true, 'tooltip rank')
local lad = V.ladder(data, vigil)
eq(#lad, 7, 'ladder')
eq(lad[4].reached, true, 'Trusted reached')
eq(lad[5].reached, false, 'Honored not')
eq(V.resetText(data), 'Daily contracts in 5h 12m, weekly in 2d 1h', 'reset text')

print(string.format('factionsview_test: %s (%d checks)', fails == 0 and 'OK' or (fails .. ' FAILED'), checks))
if fails > 0 then os.exit(1) end
