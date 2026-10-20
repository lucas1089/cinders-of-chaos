-- The stash window's texts and rules, without client API (tested by stashview_test.lua). The server
-- (data/scripts/chaos/stash.lua) decides everything; this formats its messages:
--   tabs {tabs = [{id, name, used, size, locked, affinity, icon, old, source}], limit, pact, tabSize, canWithdraw,
--         withdrawWhy = 'pz' | 'hideout' | nil}
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
  if type(tabs) == 'table' and tabs.closed == true then return false end -- the depot is the storage (server toDepot)
  if V.hasFlag(states, V.PZ_FLAG) then return true end
  if type(tabs) ~= 'table' then return false end
  if tabs.remote then return true end
  return tabs.canDeposit == true and tabs.depositWhy == 'hideout'
end

-- the locked state of depositing: where to unlock it
function V.depositLockedText(tabs)
  if type(tabs) == 'table' and tabs.closed == true then
    return tr('The stash is closed to new items: put them into your depot. It only gives items back.')
  end
  return tr('Deposit only in a protection zone. Remote deposit from anywhere: Store > Storage & Slots, or an active Chaos Pact.')
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
  return tostring(t.name or t.id or '')
end

local SOURCES = { free = 'free for everybody', pact = 'lent by your Chaos Pact', bought = 'bought', achievement = 'earned' }

function V.tabTooltip(t, pact)
  if type(t) ~= 'table' then return '' end
  if t.old then
    return tr('Old depot: %d entries from your depot that fit no tab. Withdraw-only.', n(t.used))
  end
  local text
  if t.affinity then
    text = tr('%s tab: %d of %d entries. Every %s item you deposit goes here first.', tr(t.name or ''), n(t.used), n(t.size),
      tr(t.name or ''))
    if t.source and SOURCES[t.source] then
      text = text .. '\n' .. tr(SOURCES[t.source])
    end
  else
    text = tr('Tab %s: %d of %d entries', tostring(t.name or t.id), n(t.used), n(t.size))
  end
  if t.locked then
    if t.affinity then
      text = text .. '\n' .. tr('Withdraw-only: your account does not own this tab now. Nothing is lost.')
    elseif pact then
      text = text .. '\n' .. tr('Withdraw-only: beyond your tabs.')
    else
      text = text .. '\n' .. tr('Withdraw-only while your Chaos Pact is inactive. Nothing is lost.')
    end
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
    text = tr('%d entries. General tabs: %d (%d entries each)%s', used, n(d.limit), n(d.tabSize),
      d.pact and tr(', Chaos Pact active') or '')
    if locked > 0 then
      text = text .. tr('. Withdraw-only tabs: %d', locked)
    end
  end
  if d.closed == true then
    text = text .. tr('. The stash is closed to new items: use your depot.')
  elseif canDeposit == false then
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

return V
