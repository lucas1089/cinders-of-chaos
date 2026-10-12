-- luajit pvpzoneview_test.lua && lua5.3 pvpzoneview_test.lua (CI runs it from the repository root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'pvpzoneview.lua')
local V = PvpZoneView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(V.clock(125), '2:05', 'clock'); eq(V.clock(3725), '1:02:05', 'clock hours'); eq(V.clock(-3), '0:00', 'never negative')
eq(V.number(1234567), '1,234,567', 'number'); eq(V.number(nil), '0', 'nil number'); eq(V.number(999), '999', 'small')
eq(V.span(42), '42s', 'span s'); eq(V.span(600), '10m', 'span m'); eq(V.span(3900), '1h 5m', 'span h'); eq(V.span(7200), '2h', 'span 2h')

-- HUD
eq(V.embersLine({ embers = 1250, cap = 2500 }), 'Embers 1,250 / 2,500', 'embers line')
local p, col = V.carryPercent({ embers = 1250, cap = 2500 })
eq(p, 50, 'carry percent'); eq(col, '#e8a040', 'carry colour')
p, col = V.carryPercent({ embers = 2400, cap = 2500 })
eq(col, '#ff5a2a', 'nearly full colour')
eq((V.carryPercent({ embers = 5, cap = 0 })), 0, 'no cap')
eq((V.contestLine({ phase = 'idle', left = 3600 })), 'Shrine contest in 1:00:00', 'idle')
eq((V.contestLine({ phase = 'warden', left = 600, warden = 73 })), 'Shrine Warden 73% - 10:00 left', 'warden')
eq((V.contestLine({ phase = 'capture', left = 90, contested = true })), 'Shrine: CONTESTED - 1:30 left', 'contested')
local line, c2 = V.contestLine({ phase = 'capture', left = 90, progress = { { short = 'Vigil', pct = 42, color = '#e0a050' } } })
eq(line, 'Shrine: Vigil 42% - 1:30 left', 'capture lead'); eq(c2, '#e0a050', 'lead colour')
eq((V.contestLine({ phase = 'capture', left = 5, progress = {} })), 'Shrine: open, take it! - 0:05 left', 'open')
eq((V.contestLine(nil)), 'Shrine contest in 0:00', 'nil contest')
eq((V.holderLine({ holder = { short = 'Choir', left = 3000, color = '#b07ae8' } })), 'Choir hold the shrine (50m)', 'holder')
eq((V.holderLine({})), 'Nobody holds the Cinder Shrine', 'no holder')
eq((V.pledgeLine({ name = 'The Ashen Vigil' })), 'Fighting for The Ashen Vigil', 'pledge')
eq((V.pledgeLine(nil)), 'Not pledged: no reputation, no shrine', 'no pledge')
eq((V.statusLine({ exit = 40, protect = 5 })), 'Leaving... 40% (do not fight)', 'exit first')
eq((V.statusLine({ protect = 7 })), 'Protected for 7s', 'protected')
eq((V.statusLine({ piles = 1500 })), '1,500 embers lie on the ground', 'piles')
eq((V.statusLine({})), 'Bank your embers at a safe exit', 'default status')

-- the window and the confirmation
local t, en = V.enterButton({ canEnter = true })
eq(t, 'Enter the Marches', 'enter text'); eq(en, true, 'enter enabled')
local _, en2, tip = V.enterButton({ canEnter = false, why = 'You need level 150.' })
eq(en2, false, 'refused'); eq(tip, 'You need level 150.', 'reason as tooltip')
eq(select(2, V.enterButton({ inside = true, canEnter = true })), false, 'inside: no enter')
eq(V.canConfirm({}, false), false, 'must tick the box')
eq(V.canConfirm({}, true), true, 'ticked')
eq(V.canConfirm({ hc = { isHc = true, allow = false } }, true, true), false, 'Hardcore never (decided)')
eq(V.canConfirm({ hc = { isHc = true, allow = true } }, true, false), false, 'Hardcore allowed: second box needed')
eq(V.canConfirm({ hc = { isHc = true, allow = true } }, true, true), true, 'Hardcore allowed: both boxes')
local risk = V.riskText({ rules = { 'Open PvP.', 'Embers drop.' }, carried = 1200, pickup = { perKill = 800 } })
eq(risk, '- Open PvP.\n- Embers drop.\nYou carry 1,200 embers now. A defeat drops them all; your killer may take up to 800 of them.',
  'risk text')
eq(V.riskText({ hc = { isHc = true, allow = false } }):find('cannot enter', 1, true) ~= nil, true, 'Hardcore risk line')
local name, b, ok, tt = V.factionRow({ name = 'The Veiled Choir', rival = 'vigil', rivalName = 'The Ashen Vigil', can = true }, {})
eq(name, 'The Veiled Choir', 'faction'); eq(b, 'Pledge', 'pledge button'); eq(ok, true, 'can pledge'); eq(tt, 'sworn rival: The Ashen Vigil', 'rival tip')
_, b, ok, tt = V.factionRow({ name = 'X', pledged = true }, { pledgeChangeIn = 7200 })
eq(b, 'Pledged', 'pledged'); eq(ok, false, 'pledged disabled'); eq(tt, 'You can change in 2h', 'change wait')
_, _, ok, tt = V.factionRow({ name = 'Y', can = false, why = 'Not trusted.' }, {})
eq(ok, false, 'cannot pledge'); eq(tt, 'Not trusted.', 'why')
local sub, btn, can = V.vendorRow({ cost = 300, weekly = 5, bought = 2, can = true }, 400)
eq(sub, '2 of 5 this week', 'weekly sub'); eq(btn, '300 embers', 'price'); eq(can, true, 'can buy')
_, _, can = V.vendorRow({ cost = 300, can = true }, 100)
eq(can, false, 'too poor')
_, btn, can = V.vendorRow({ cost = 4000, kind = 'cosmetic', owned = true }, 9999)
eq(btn, 'Owned', 'owned'); eq(can, false, 'owned disabled')
eq(V.recordLine({ banked = 1500, weekBanked = 300, total = 9000, kills = 3, defeats = 1, captures = 2 }),
  'Banked 1,500 (this week 300, all time 9,000)   Defeats dealt 3, taken 1   Shrines 2', 'record line')

print(string.format('pvpzoneview_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
