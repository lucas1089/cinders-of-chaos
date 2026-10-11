-- Depot tabs: the logic without client API (tested by depottabsview_test.lua).
-- The server (data/scripts/chaos/depot.lua) sends on extended opcode 111:
--   tabs {tabs, max, size, used = [n per tab] (missing: keep the last counts), ids = [client id per tab],
--         chest = [client ids of the depot chest], hint}
-- Tab n is the box with client id ids[n]; tabs above `tabs` are locked (withdraw-only).

DepotTabsView = {}
local V = DepotTabsView

V.LOCKED_OPACITY = 0.4

local function int(v)
  v = tonumber(v) or 0
  if v ~= v then return 0 end
  return math.floor(v)
end

function V.newState()
  return { tabs = 0, max = 0, size = 100, used = {}, byId = {}, chest = {}, hint = '' }
end

-- merges one server message into the state (a message without `used` keeps the last counts)
function V.apply(state, d)
  state = state or V.newState()
  if type(d) ~= 'table' then return state end
  state.tabs = int(d.tabs)
  state.max = int(d.max)
  state.size = int(d.size) > 0 and int(d.size) or state.size
  if type(d.hint) == 'string' then state.hint = d.hint end
  if type(d.ids) == 'table' then
    state.byId = {}
    for i, id in ipairs(d.ids) do state.byId[int(id)] = i end
  end
  if type(d.chest) == 'table' then
    state.chest = {}
    for _, id in ipairs(d.chest) do state.chest[int(id)] = true end
  end
  if type(d.used) == 'table' then
    state.used = {}
    for i, n in ipairs(d.used) do state.used[i] = int(n) end
  end
  return state
end

function V.tabOf(state, clientId)
  return state and state.byId[int(clientId)] or nil
end

function V.isChest(state, clientId)
  return state ~= nil and state.chest[int(clientId)] == true
end

function V.isLocked(state, tab)
  return int(tab) > int(state.tabs)
end

-- the window title of a tab: "Tab 3 (87/100)", "Tab 7 (locked)"
function V.title(state, tab)
  if V.isLocked(state, tab) then
    return string.format('Tab %d (locked)', int(tab))
  end
  local used = state.used[int(tab)]
  if used == nil then
    return string.format('Tab %d', int(tab))
  end
  return string.format('Tab %d (%d/%d)', int(tab), used, state.size)
end

-- the tooltip of a tab in the depot chest window
function V.tooltip(state, tab)
  local used = state.used[int(tab)]
  if V.isLocked(state, tab) then
    local inside = (used and used > 0) and string.format('%d items inside: you can take them out.\n', used) or ''
    return string.format('Tab %d is locked (your account has %d of %d tabs).\n%s%s', int(tab), state.tabs, state.max,
      inside, state.hint ~= '' and state.hint or 'Buy more tabs in the Store.')
  end
  if used == nil then
    return string.format('Tab %d: up to %d items (a bag counts with its contents).', int(tab), state.size)
  end
  return string.format('Tab %d: %d of %d items (a bag counts with its contents).', int(tab), used, state.size)
end

-- the title colour of a full or locked tab window (nil: leave the default)
function V.titleColor(state, tab)
  if V.isLocked(state, tab) then return '#8a8a8a' end
  local used = state.used[int(tab)]
  if used and used >= state.size then return '#d08040' end
  return nil
end
