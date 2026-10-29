-- The stash window's texts and rules, without client API (tested by stashview_test.lua). The server
-- (data/scripts/chaos/stash.lua) decides everything; this formats its messages:
--   tabs {tabs = [{id, name, used, size, locked, affinity, icon, old, source}], limit, pact, tabSize, canWithdraw,
--         withdrawWhy = 'pz' | 'hideout' | nil, slots, freeSlots, perPack, packs, maxPacks, store, inbox}
-- O316: one general tab of `slots` entries (30 free, Stash Slot Expansions from the store), the affinity tabs are bought,
-- the depot is retired.
--   StowReport {stowed, kept, reasons = [{reason, label, count, names}]}
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

StashView = {}
local V = StashView

V.PZ_FLAG = 16384 -- PlayerStates.Pz of the local player

local function n(v)
  return math.floor(tonumber(v) or 0)
end

function V.hasFlag(states, flag)
  states, flag = n(states), n(flag)
  if flag <= 0 then return false end
  return math.floor(states / flag) % 2 == 1
end

-- withdrawing: in a protection zone (the client's own state, live while walking) or where the server said so for
-- another reason (inside a hideout). The server checks again on every request.
function V.canWithdraw(tabs, states)
  if V.hasFlag(states, V.PZ_FLAG) then return true end
  return type(tabs) == 'table' and tabs.canWithdraw == true and tabs.withdrawWhy == 'hideout'
end

-- depositing: in town for everybody (the live protection zone state, or the server's hideout answer); anywhere with the
-- remote deposit unlock (the server's `remote`: bought, or lent by an active Chaos Pact). The server checks again.
function V.canDeposit(tabs, states)
  if V.hasFlag(states, V.PZ_FLAG) then return true end
  if type(tabs) ~= 'table' then return false end
  if tabs.remote then return true end
  return tabs.canDeposit == true and tabs.depositWhy == 'hideout'
end

-- the locked state of depositing: where to unlock it
function V.depositLockedText(tabs)
  return tr('Deposit only in a protection zone. Remote deposit from anywhere: Store > Storage & Slots, or an active Chaos Pact.')
end

-- the slot counts of the one general tab: "Stash: 12 of 55 slots (30 free + 1 expansion of 25)"
function V.slotsText(d)
  if type(d) ~= 'table' or n(d.slots) <= 0 then return '' end
  local used = 0
  for _, t in ipairs(type(d.tabs) == 'table' and d.tabs or {}) do
    if t.id == 1 then used = n(t.used) end
  end
  local text = tr('Stash: %d of %d slots', used, n(d.slots))
  local packs = n(d.packs)
  if packs > 0 and n(d.perPack) > 0 then
    text = text .. ' ' .. tr('(%d free + %d expansions of %d)', n(d.freeSlots), packs, n(d.perPack))
  end
  return text
end

-- the Buy Slots button: shown when the server names the store category
function V.canBuy(d)
  return type(d) == 'table' and type(d.store) == 'string' and d.store ~= ''
end

function V.buyTooltip(d)
  if type(d) ~= 'table' then return '' end
  return tr('Stash Slot Expansion: +%d slots on your stash tab for good, up to %d expansions. Store > %s. Affinity tabs for orbs, gems, keys, supplies and more are sold there too.',
    n(d.perPack), n(d.maxPacks), tostring(d.store or ''))
end

-- the Inbox button: what waits in the inbox (mail, market, house transfers). It moves into the stash in a protection zone.
function V.inboxLabel(d)
  local c = type(d) == 'table' and n(d.inbox) or 0
  if c > 0 then return tr('Inbox (%d)', c) end
  return tr('Inbox')
end

function V.inboxTooltip(d, canWithdraw)
  local text = tr('Move what waits in your inbox (mail, market, house transfers) into your stash, or your backpack when it cannot be stashed.')
  if not canWithdraw then
    text = text .. '\n' .. tr('Collect it in a protection zone.')
  end
  return text
end

-- the Stow Everything button's tooltip
function V.stowTooltip(canDeposit, tabs)
  if not canDeposit then
    return V.depositLockedText(tabs)
  end
  local text = tr('Put everything in your backpack, through its bags, into the stash: each item into its tab. Equipped, locked, store-bound and quest items stay.')
  if type(tabs) == 'table' and tabs.remote then
    text = text .. '\n' .. (tabs.remote == 'pact' and tr('Remote deposit: lent by your Chaos Pact.') or tr('Remote deposit: unlocked.'))
  end
  return text
end

-- the text of a tab button: the number of a general tab, the (translated) name of an affinity tab
function V.tabLabel(t)
  if type(t) ~= 'table' then return '' end
  if t.old then return tr('Old depot') end
  if t.affinity then return tr(t.name or '') end
  if n(t.id) == 1 then return tr('Stash') end
  return tr('Old tab %d', n(t.id))
end

local SOURCES = { pact = 'lent by your Chaos Pact', bought = 'bought', achievement = 'earned' }

function V.tabTooltip(t, pact)
  if type(t) ~= 'table' then return '' end
  if t.old then
    return tr('Old depot: %d entries from your retired depot that fit no tab. Withdraw-only.', n(t.used))
  end
  local text
  if t.affinity then
    text = tr('%s tab: %d of %d entries. Every %s item you deposit goes here first.', tr(t.name or ''), n(t.used), n(t.size),
      tr(t.name or ''))
    if t.source and SOURCES[t.source] then
      text = text .. '\n' .. tr(SOURCES[t.source])
    end
  elseif n(t.id) == 1 then
    text = tr('Stash tab: %d of %d slots. Slot Expansions in the Store make it bigger.', n(t.used), n(t.size))
  else
    text = tr('Old tab %d: %d entries', n(t.id), n(t.used))
  end
  if t.locked then
    if t.affinity then
      text = text .. '\n' .. tr('Withdraw-only: your account does not own this tab now. Nothing is lost.')
    else
      text = text .. '\n' .. tr('Withdraw-only: an old tab. Nothing is lost.')
    end
  elseif n(t.used) > n(t.size) and not t.affinity then
    text = text .. '\n' .. tr('Over the limit: you can take items out, and put none in until you are under it.')
  end
  return text
end

-- the line under the list
function V.infoText(d, selected, canWithdraw, canDeposit)
  if type(d) ~= 'table' or type(d.tabs) ~= 'table' then return '' end
  local text
  if n(selected) ~= 0 then
    for _, t in ipairs(d.tabs) do
      if t.id == selected then
        if t.old then
          text = tr('Old depot: %d entries, withdraw-only', n(t.used))
        else
          text = tr('%s: %d / %d entries%s', V.tabLabel(t), n(t.used), n(t.size), t.locked and tr(', withdraw-only') or '')
        end
      end
    end
  end
  if not text then
    local used, locked = 0, 0
    for _, t in ipairs(d.tabs) do
      used = used + n(t.used)
      if t.locked then locked = locked + 1 end
    end
    text = tr('%d entries.', used)
    local slots = V.slotsText(d)
    if slots ~= '' then text = text .. ' ' .. slots end
    if d.pact then text = text .. tr(', Chaos Pact active') end
    if locked > 0 then
      text = text .. tr('. Withdraw-only tabs: %d', locked)
    end
  end
  if canDeposit == false then
    text = text .. tr('. Deposit and withdraw in a protection zone (remote deposit: Store > Storage & Slots).')
  elseif not canWithdraw then
    text = text .. tr('. Withdraw in a protection zone.')
  end
  return text
end

-- an item's tooltip: the server's look text, and why it cannot come out here
function V.itemTooltip(data, canWithdraw)
  local text = type(data) == 'table' and tostring(data.tooltip or data.name or '') or ''
  if not canWithdraw then
    text = text .. '\n' .. tr('Withdraw in a protection zone.')
  end
  return text
end

-- may the withdraw dialog take more than one (a plain stack) or is it one whole item (a row)
function V.isWhole(data)
  return type(data) == 'table' and data.row ~= nil
end

-- the Stow Everything report: a title and the text of the box
function V.reportText(rep)
  if type(rep) ~= 'table' then return '' end
  local lines = {}
  if n(rep.stowed) == 0 and n(rep.kept) == 0 then
    return tr('Nothing to stow.')
  end
  lines[#lines + 1] = tr('Stowed %d item(s) into your stash.', n(rep.stowed))
  if n(rep.kept) > 0 then
    lines[#lines + 1] = tr('Kept %d item(s):', n(rep.kept))
    for _, r in ipairs(type(rep.reasons) == 'table' and rep.reasons or {}) do
      local names = {}
      for _, nm in ipairs(type(r.names) == 'table' and r.names or {}) do
        names[#names + 1] = tostring(nm)
      end
      local line = string.format('- %s: %d', tr(tostring(r.label or r.reason or '')), n(r.count))
      if #names > 0 then
        line = line .. ' (' .. table.concat(names, ', ') .. ')'
      end
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, '\n')
end

-- The deposit request of one dragged item (server stash.lua "Stash"): where it lies, and which item it is (its client
-- id and count), so the server takes nothing else when that slot holds another item by then. pos = the item's
-- position (a container slot: x 65535, y 64 + container, z slot).
function V.depositData(pos, stackpos, clientId, count, visible, typed)
  if type(pos) ~= 'table' then return nil end
  return {
    make = 'Stash',
    UpdateList = visible == true,
    Typed = typed,
    Pos = { x = n(pos.x), y = n(pos.y), z = n(pos.z), stackpos = n(stackpos) },
    ItemId = clientId and n(clientId) or nil,
    Count = count and n(count) or nil,
  }
end

-- What a drop handler returns once it sent the deposit: true. The base client offers a drop to every widget under the
-- mouse, deepest first, until one returns true; the stash list and its window both had the handler and returned false,
-- so one drag sent two deposits of the same slot, and the second took the item to the right of the dragged one
-- (player report 2026-10-22).
V.DROP_HANDLED = true

return V
