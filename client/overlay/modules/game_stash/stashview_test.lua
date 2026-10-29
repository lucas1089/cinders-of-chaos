-- luajit stashview_test.lua (CI runs every client *_test.lua)
dofile((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'stashview.lua')
local V = StashView
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function has(s, part, m) eq(type(s) == 'string' and s:find(part, 1, true) ~= nil, true, (m or '') .. ' (' .. tostring(s) .. ')') end

-- withdrawing: the live protection zone state, or the server's hideout answer
eq(V.hasFlag(16384 + 4, V.PZ_FLAG), true, 'in a protection zone')
eq(V.hasFlag(4, V.PZ_FLAG), false, 'not')
eq(V.canWithdraw(nil, 16384), true, 'protection zone: yes')
eq(V.canWithdraw({ canWithdraw = true, withdrawWhy = 'pz' }, 0), false, 'left the protection zone: the stale answer does not count')
eq(V.canWithdraw({ canWithdraw = true, withdrawWhy = 'hideout' }, 0), true, 'inside a hideout')
eq(V.canWithdraw({ canWithdraw = false }, 0), false, 'outside')

-- tab buttons
eq(V.tabLabel({ id = 1, name = '1' }), 'Stash', 'the one general tab is the Stash')
eq(V.tabLabel({ id = 3, name = '3' }), 'Old tab 3', 'an old general tab')
eq(V.tabLabel({ id = 104, name = 'Supplies', affinity = 'supplies' }), 'Supplies', 'an affinity tab: its name')
eq(V.tabLabel({ id = 200, name = 'Old depot', old = true }), 'Old depot', 'the Old depot tab')
has(V.tabTooltip({ id = 104, name = 'Supplies', affinity = 'supplies', used = 3, size = 100, source = 'bought' }), 'goes here first',
  'affinity tooltip')
has(V.tabTooltip({ id = 104, name = 'Supplies', affinity = 'supplies', used = 3, size = 100, source = 'bought' }), 'bought',
  'affinity source')
has(V.tabTooltip({ id = 105, name = 'Weapons', affinity = 'weapons', used = 3, size = 100, locked = true }), 'does not own',
  'a lost affinity tab')
has(V.tabTooltip({ id = 5, name = '5', used = 10, size = 100, locked = true }, false), 'an old tab', 'a locked old tab')
has(V.tabTooltip({ id = 1, name = '1', used = 12, size = 55 }), '12 of 55 slots', 'the stash tab: its slots')
has(V.tabTooltip({ id = 1, name = '1', used = 100, size = 30 }), 'Over the limit', 'more entries than slots: take out only')
has(V.tabTooltip({ id = 200, old = true, used = 7 }), 'Withdraw-only', 'Old depot tooltip')
eq(V.tabTooltip(nil), '', 'no tab')

-- the line under the list
local d = { tabs = { { id = 1, name = '1', used = 40, size = 55 }, { id = 5, name = '5', used = 2, size = 100, locked = true },
  { id = 104, name = 'Supplies', affinity = 'supplies', used = 3, size = 100 } }, limit = 1, tabSize = 100, pact = true,
  slots = 55, freeSlots = 30, perPack = 25, packs = 1, maxPacks = 20, store = 'Storage & Slots', inbox = 3 }
local info = V.infoText(d, 0, true)
has(info, '45 entries', 'every entry counted')
has(info, 'Stash: 40 of 55 slots (30 free + 1 expansions of 25)', 'the slots of the one general tab')
has(info, 'Chaos Pact active', 'the Pact')
has(info, 'Withdraw-only tabs: 1', 'the withdraw-only count')
has(V.infoText(d, 104, true), 'Supplies: 3 / 100 entries', 'one tab selected')
eq(V.slotsText({ slots = 30, packs = 0, tabs = { { id = 1, used = 7 } } }), 'Stash: 7 of 30 slots', 'free room only')
eq(V.slotsText(nil), '', 'no slots')
has(V.infoText(d, 5, true), 'withdraw-only', 'a locked tab selected')
has(V.infoText(d, 0, false), 'Withdraw in a protection zone', 'outside a protection zone')
eq(V.infoText(nil, 0, true), '', 'no tabs yet')

-- items
has(V.itemTooltip({ tooltip = 'You see a sword.' }, false), 'protection zone', 'a greyed item says why')
eq(V.itemTooltip({ tooltip = 'You see a sword.' }, true), 'You see a sword.', 'the server text')
eq(V.isWhole({ row = 5 }), true, 'a stored item is whole')
eq(V.isWhole({ id = 2148 }), false, 'a plain stack is not')

-- the Stow Everything report
local text = V.reportText({ stowed = 131, kept = 3, reasons = { { reason = 'container', label = 'containers', count = 2, names = { 'bag' } },
  { reason = 'locked', label = 'locked', count = 1, names = {} } } })
has(text, 'Stowed 131 item(s)', 'stowed')
has(text, 'Kept 3 item(s):', 'kept')
has(text, '- containers: 2 (bag)', 'a reason with names')
has(text, '- locked: 1', 'a reason without names')
eq(V.reportText({ stowed = 0, kept = 0 }), 'Nothing to stow.', 'nothing')
eq(V.reportText(nil), '', 'no report')

-- deposit (owner 2026-10-15): town for everybody, anywhere with the remote unlock
eq(V.canDeposit(nil, 16384), true, 'free, in a protection zone')
eq(V.canDeposit({ canDeposit = false }, 0), false, 'free, outside: locked')
eq(V.canDeposit({ remote = 'bought' }, 0), true, 'bought unlock, outside')
eq(V.canDeposit({ remote = 'pact' }, 0), true, 'the Pact, outside')
eq(V.canDeposit({ canDeposit = true, depositWhy = 'pz' }, 0), false, 'left the zone: the stale answer does not count')
eq(V.canDeposit({ canDeposit = true, depositWhy = 'hideout' }, 0), true, 'inside a hideout')
has(V.depositLockedText(), 'Storage & Slots', 'the locked state says where to unlock')
has(V.stowTooltip(false, {}), 'Chaos Pact', 'Stow Everything locked: where to unlock')
has(V.stowTooltip(true, { remote = 'pact' }), 'lent by your Chaos Pact', 'Stow Everything: the unlock source')
has(V.infoText(d, 0, false, false), 'remote deposit', 'the line under the list when locked')

-- O316: the buy and inbox buttons
eq(V.canBuy(d), true, 'the server names the store category: the Buy Slots button shows')
eq(V.canBuy({ store = '' }), false, 'no category: no button')
has(V.buyTooltip(d), '+25 slots', 'the tooltip names the pack')
has(V.buyTooltip(d), 'Storage & Slots', 'and the category')
eq(V.inboxLabel(d), 'Inbox (3)', 'the inbox count')
eq(V.inboxLabel({ inbox = 0 }), 'Inbox', 'an empty inbox')
has(V.inboxTooltip(d, false), 'protection zone', 'the inbox is collected in town')
eq(V.inboxTooltip(d, true):find('protection zone', 1, true), nil, 'in town: no warning')

-- a deposit names the dragged item, and the drop is handled once (player report 2026-10-22: one drag took the item
-- to the right too)
local dd = V.depositData({ x = 65535, y = 64, z = 3 }, 3, 3031, 25, true, 1)
eq(dd.make, 'Stash', 'deposit request')
eq(dd.Pos.x, 65535, 'container position x') eq(dd.Pos.y, 64, 'container id') eq(dd.Pos.z, 3, 'slot')
eq(dd.Pos.stackpos, 3, 'stack position')
eq(dd.ItemId, 3031, 'the client id goes along')
eq(dd.Count, 25, 'and the count')
eq(dd.UpdateList, true, 'the list is echoed when the window is open')
eq(V.depositData(nil, 0, 1, 1), nil, 'no position: no request')
eq(V.DROP_HANDLED, true, 'the drop handler stops the drop at the stash (no second deposit from the window below)')
-- the handler in stash.lua returns it on every path that sent something
local src = io.open((arg and arg[0] and arg[0]:match('^(.*[/\\])') or '') .. 'stash.lua'):read('*a')
local body = src:match('Stash%.OnDrop = function%(.-\nend\n')
eq(body ~= nil, true, 'Stash.OnDrop found')
eq(select(2, body:gsub('return StashView%.DROP_HANDLED', '')), 2, 'deposit and refusal both end the drop')
eq(body:find('Stash.StashItem(item, 1)', 1, true) ~= nil, true, 'the deposit is sent')

-- opening without a flash (O316): the window waits for the drawn list
eq(V.revealReady(false, 0), false, 'nothing drawn yet: hidden') eq(V.revealReady(true, 0), true, 'the list is drawn: shown')
eq(V.revealReady(false, V.REVEAL_MS - 1), false, 'still waiting') eq(V.revealReady(false, V.REVEAL_MS), true, 'no answer in time: shown anyway')
eq(V.revealReady(nil, nil), false, 'junk') eq(V.REVEAL_MS >= 500 and V.REVEAL_MS <= 3000, true, 'a short wait')
local lk = V.lockerSet({ 2589, '2590', 0, -3, 'x', 2591.0 })
eq(V.isLocker(lk, 2589), true, 'a locker') eq(V.isLocker(lk, 2590), true, 'a locker sent as text') eq(V.isLocker(lk, 2591), true, 'a float')
eq(V.isLocker(lk, 2400), false, 'a backpack') eq(V.isLocker(lk, 0), false, 'zero') eq(V.isLocker(lk, nil), false, 'nil')
eq(next(V.lockerSet(nil)), nil, 'no list: no locker') eq(V.isLocker(nil, 2589), false, 'no set')
-- stash.lua: Toggle shows nothing itself, only Reveal does, the last item packet reveals, the locker window is closed at once
local tog = src:match('Stash%.Toggle = function%(%).-\nend\n')
eq(tog ~= nil, true, 'Stash.Toggle found')
eq(tog:find('Stash.UI:show()', 1, true), nil, 'Toggle does not show the empty window')
eq(tog:find('Stash.opening = true', 1, true) ~= nil, true, 'Toggle marks the window as opening')
local rev = src:match('Stash%.Reveal = function%(%).-\nend\n')
eq(rev ~= nil and rev:find('Stash.UI:show()', 1, true) ~= nil, true, 'Reveal shows the window')
local dm = src:match('Stash%.DataManager = function.-\nend\n')
eq(dm:find('Stash.Reveal()', 1, true) ~= nil, true, 'the last item packet reveals the window')
eq(dm:find('Stash.LockerIds = V.lockerSet(buffer.lockers)', 1, true) ~= nil, true, 'the lockers come with the categories')
eq(src:find('connect(Container, { onOpen = Stash.OnContainerOpen })', 1, true) ~= nil, true, 'locker windows are watched')
eq(src:find('disconnect(Container, { onOpen = Stash.OnContainerOpen })', 1, true) ~= nil, true, 'and released')

print('stashview_test: ' .. n .. ' checks OK')
