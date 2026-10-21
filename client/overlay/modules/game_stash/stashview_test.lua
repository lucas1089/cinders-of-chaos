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
eq(V.tabLabel({ id = 3, name = '3' }), '3', 'a general tab: its number')
eq(V.tabLabel({ id = 104, name = 'Supplies', affinity = 'supplies' }), 'Supplies', 'an affinity tab: its name')
eq(V.tabLabel({ id = 200, name = 'Old depot', old = true }), 'Old depot', 'the Old depot tab')
has(V.tabTooltip({ id = 104, name = 'Supplies', affinity = 'supplies', used = 3, size = 100, source = 'free' }), 'goes here first',
  'affinity tooltip')
has(V.tabTooltip({ id = 104, name = 'Supplies', affinity = 'supplies', used = 3, size = 100, source = 'free' }), 'free for everybody',
  'affinity source')
has(V.tabTooltip({ id = 105, name = 'Weapons', affinity = 'weapons', used = 3, size = 100, locked = true }), 'does not own',
  'a lost affinity tab')
has(V.tabTooltip({ id = 5, name = '5', used = 10, size = 100, locked = true }, false), 'Chaos Pact is inactive', 'a locked general tab')
has(V.tabTooltip({ id = 5, name = '5', used = 10, size = 100, locked = true }, true), 'beyond your tabs', 'beyond the tabs')
has(V.tabTooltip({ id = 200, old = true, used = 7 }), 'Withdraw-only', 'Old depot tooltip')
eq(V.tabTooltip(nil), '', 'no tab')

-- the line under the list
local d = { tabs = { { id = 1, name = '1', used = 40, size = 100 }, { id = 5, name = '5', used = 2, size = 100, locked = true },
  { id = 104, name = 'Supplies', affinity = 'supplies', used = 3, size = 100 } }, limit = 4, tabSize = 100, pact = true }
local info = V.infoText(d, 0, true)
has(info, '45 entries', 'every entry counted')
has(info, 'General tabs: 4 (100 entries each)', 'the general tabs')
has(info, 'Withdraw-only tabs: 1', 'the withdraw-only count')
has(V.infoText(d, 104, true), 'Supplies: 3 / 100 entries', 'one tab selected')
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
eq(V.canDeposit({ closed = true, canDeposit = false }, 0), false, 'closed: no deposit, not even in a protection zone')
has(V.depositLockedText({ closed = true }), 'your depot', 'closed: the line names the depot')
has(V.stowTooltip(false, { closed = true }), 'closed to new items', 'closed: Stow Everything says so')
has(V.infoText({ tabs = {}, limit = 1, tabSize = 100, closed = true }, 0, true, false), 'use your depot', 'closed: the line under the list')
has(V.stowTooltip(true, { remote = 'pact' }), 'lent by your Chaos Pact', 'Stow Everything: the unlock source')
has(V.infoText(d, 0, false, false), 'remote deposit', 'the line under the list when locked')

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

print('stashview_test: ' .. n .. ' checks OK')
