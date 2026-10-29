-- luajit pactview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'pactview.lua')
local V = PactView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

local head, line = V.status(nil)
eq(head, 'Loading...', 'no data yet')
head, line = V.status({ active = true, ends = '2026-11-09 12:00', daysLeft = 1, title = 'Pactbound' })
eq(head, 'Chaos Pact active', 'active headline')
eq(line:find('1 day left', 1, true) ~= nil, true, 'singular day')
eq(line:find('Pactbound', 1, true) ~= nil, true, 'title shown')
head, line = V.status({ active = false, endsAt = 5, ends = '2026-10-01 10:00' })
eq(head, 'Chaos Pact ended', 'ended headline')
eq(line:find('withdraw-only', 1, true) ~= nil, true, 'ended: nothing lost')
head = V.status({ active = false, endsAt = 0, dailyMarks = 5 })
eq(head, 'No Chaos Pact', 'never bought')
eq(select(2, V.status({ active = false, endsAt = 0, dailyMarks = 5 })):find('remote stash deposit', 1, true) ~= nil, true,
  'the perks name remote stash deposit')

eq(select(2, V.status({ active = false, endsAt = 0, dailyMarks = 5 })):find('5 Pact Marks a day', 1, true) ~= nil, true,
  'the perks name the Marks, not coins')
local text, on = V.claim({ active = true, canClaim = true, dailyMarks = 5 })
eq(text, 'Claim 5 Pact Marks', 'claim text') eq(on, true, 'claim on')
text, on = V.claim({ active = true, canClaim = false })
eq(text, 'Claimed today', 'claimed') eq(on, false, 'claimed off')
text, on = V.claim({ active = false })
eq(on, false, 'no Pact no claim')

local r = V.limitRow({ label = 'Stash tabs', free = 2, pact = 2, extra = 1, maxExtra = 6, total = 5, pactActive = true })
eq(r[1], 'Stash tabs', 'label') eq(r[3], '+2', 'pact bonus') eq(r[4], '1 / 6', 'bought') eq(r[5], '5', 'total')
r = V.limitRow({ label = 'Listings', free = 20, pact = 10, extra = 0, maxExtra = 0, total = 20, pactActive = false })
eq(r[3], '+10 (off)', 'inactive bonus') eq(r[4], '-', 'not sold')
r = V.limitRow({ label = 'Slots', free = 5, pact = 0, extra = 3, maxExtra = 10, total = 8 })
eq(r[3], '-', 'no Pact bonus')
eq(#V.limitRows({ limits = { {}, {} } }), 2, 'rows')
eq(V.limitRows({ active = false, limits = { { pact = 10, pactActive = true } } })[1][3], '+10 (premium)', 'premium bonus without the Pact')

eq(V.specialText({ special = { { name = 'Orbs', owned = true }, { name = 'Gems' } }, tabSize = 100 }):find('Orbs (owned), Gems (store)', 1, true) ~= nil,
  true, 'affinity tabs')
eq(V.specialText({ special = { { name = 'Supplies', owned = true } }, tabSize = 30 }):find('30 entries', 1, true) ~= nil, true,
  'general tab size in entries')
eq(V.specialText({}), '', 'no special tabs sent')

local rows = V.buildRows({ buildLimit = 2, builds = { { slot = 1, name = 'Bleed', nodes = 40, cls = 'warrior' }, { slot = 4, name = 'Old', nodes = 1 } } })
eq(#rows, 4, 'rows up to the highest saved slot')
eq(rows[1].sub, 'Warrior line, 40 nodes', 'saved row') eq(rows[1].editable, true, 'editable')
eq(rows[2].saved, false, 'empty slot') eq(rows[2].editable, true, 'empty editable slot')
eq(rows[3].editable, false, 'slot over the limit') eq(rows[3].sub, '', 'empty locked slot')
eq(rows[4].sub:find('read-only', 1, true) ~= nil, true, 'kept build read-only')
eq(rows[4].sub:find('1 node,', 1, true) == nil, true, 'singular node')
eq(V.buildHeader({ buildLimit = 2, builds = { {} } }), 'Saved builds: 1 of 2 slots (account-wide)', 'header')
-- Pact Marks (O317): the balance line, the shelf, the monthly experience
eq(V.thousands(0), '0', 'zero') eq(V.thousands(999), '999', 'three digits') eq(V.thousands(1000), '1,000', 'a thousand')
eq(V.thousands(1234567), '1,234,567', 'millions') eq(V.thousands(nil), '0', 'no value') eq(V.thousands('12500'), '12,500', 'a string')
eq(V.marksLine({ marks = 1250, marksEarned = 3000 }), 'Pact Marks: 1,250 (earned so far: 3,000). They buy only the cosmetics below.', 'balance line')
eq(V.marksLine(nil), '', 'no status')
eq(V.monthLine({ monthExp = 0, monthExpAccount = 0 }), 'This month the Pact has given you no extra experience yet.', 'nothing yet')
eq(V.monthLine({ monthExp = 1234567, monthExpAccount = 1234567 }), 'This month the Pact gave you 1,234,567 extra experience.', 'this character')
eq(V.monthLine({ monthExp = 5000, monthExpAccount = 90000 }),
  'This month the Pact gave you 5,000 extra experience (90,000 on all your characters).', 'and the account')
eq(V.monthLine({ monthExp = 0, monthExpAccount = 700 }), 'This month the Pact gave you 0 extra experience (700 on all your characters).',
  'only another character earned it')
local shelf = V.shelfRows({ marks = 160, shelf = {
  { key = 'loot_ember', name = 'Ember Labels', marks = 150 },
  { key = 'chat_cinder', name = 'Cinder Name', marks = 200 },
  { key = 'loot_azure', name = 'Azure Labels', marks = 150, owned = true } } })
eq(#shelf, 3, 'three rows')
eq(shelf[1].canBuy, true, 'enough Marks') eq(shelf[1].price, '150 Marks', 'price text') eq(shelf[1].button, 'Buy', 'buy button')
eq(shelf[2].canBuy, false, 'not enough Marks') eq(shelf[2].button, 'Buy', 'still says Buy, disabled')
eq(shelf[3].canBuy, false, 'owned: no buy') eq(shelf[3].button, 'Owned', 'owned button') eq(shelf[3].owned, true, 'owned flag')
eq(shelf[1].name, 'Ember Labels', 'name') eq(#V.shelfRows({}), 0, 'no shelf') eq(#V.shelfRows(nil), 0, 'no status')
eq(V.shelfRows({ shelf = { { key = 'x', marks = 1 } } })[1].name, 'x', 'the key when the name is missing')
print('pactview_test: ' .. n .. ' checks OK')
