-- luajit autosellerview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'autosellerview.lua')
local V = AutoSellerView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- an empty or broken state: locked, the default tiers (Common and Uncommon on)
local s = V.normalize(nil)
eq(s.unlocked, false, 'locked without data') eq(#s.tiers, 5, 'five rarities')
eq(s.tiers[1].on, true, 'Common on by default') eq(s.tiers[2].on, true, 'Uncommon on by default')
eq(s.tiers[3].on, false, 'Rare off') eq(s.tiers[4].on, false, 'Epic off') eq(s.tiers[5].on, false, 'Legendary+ off')
eq(s.tiers[3].color, '#4a90ff', 'rarity colour') eq(s.tiers[5].name, 'Legendary+', 'names')
eq(V.normalize({ tiers = 'x', list = 3, last = 'y' }).last, nil, 'broken fields ignored')

-- the server's state
s = V.normalize({ unlocked = true, paused = false, slots = 40, cooldown = 12, cooldownMax = 30,
  tiers = { { key = 'common', on = false }, { key = 'rare', on = true }, { key = 'bogus', on = true } },
  list = { { id = 2400, name = 'dagger', price = 1500 }, { name = 'rope', price = 5 }, 'junk' },
  last = { gold = 1234567, count = 22, at = 5 }, notice = 'hi' })
eq(s.tiers[1].on, false, 'Common off as sent') eq(s.tiers[2].on, true, 'Uncommon default when not sent')
eq(s.tiers[3].on, true, 'Rare on as sent') eq(#s.list, 2, 'list entries') eq(s.notice, 'hi', 'notice')

-- Sell all and its cooldown
eq(V.sellText(0), 'Sell all', 'ready') eq(V.sellText(23), 'Sell all (23 s)', 'counting down')
eq(V.cooldownLeft(12, 5), 7, 'seconds since the state came') eq(V.cooldownLeft(12, 40), 0, 'never below 0')
eq(V.sellEnabled(s, 0), true, 'ready and unlocked') eq(V.sellEnabled(s, 3), false, 'cooling down')
eq(V.sellEnabled(V.normalize({}), 0), false, 'locked: never')

-- the last sale and the list
eq(V.lastSaleText(nil), 'Last sale: none yet.', 'no sale yet')
eq(V.lastSaleText(s.last), 'Last sale: 1,234,567 gold (22 items).', 'last sale')
eq(V.lastSaleText({ gold = 5, count = 1 }), 'Last sale: 5 gold (1 item).', 'one item')
eq(V.gold(100), '100', 'no comma') eq(V.gold(1000), '1,000', 'comma')
eq(V.listText(s.list, 40), '2/40 items: dagger (1,500), rope (5)', 'list text')
eq(V.listText({}, 40):find('none') ~= nil, true, 'empty list')

-- greyed out without the unlock
eq(V.lockedTooltip(s), nil, 'usable')
eq(V.lockedTooltip(V.normalize({})), V.NEEDS, 'locked: the reason')
eq(V.lockedTooltip(V.normalize({ needs = 'Buy it.' })), 'Buy it.', 'the server reason')

-- requests
local r = V.rarityRequest('epic', true)
eq(r.tier, 'epic', 'tier') eq(r.on, true, 'on')
eq(V.rarityRequest('epic', nil).on, false, 'only true counts')
eq(V.rarityRequest('unique', true), nil, 'no unique choice')
eq(V.listRequest('add', '  dagger ').item, 'dagger', 'trimmed name')
eq(V.listRequest('add', '   '), nil, 'empty name')
eq(V.listRequest('clear').op, 'clear', 'clear')
eq(V.listRequest('drop', 'x'), nil, 'unknown op')
eq(#V.listRequest('add', string.rep('a', 200)).item, 80, 'name cut to 80')
print('autosellerview_test: ' .. n .. ' checks OK')
