-- The level-gated top menu without client API (topbar_unlocks.lua and chaos_topbar.lua use it; topbarunlockslogic_test.lua
-- tests it). The server (unlocks.lua, extended opcode 115; server/README.md "The top menu reveals systems by level (O259)")
-- sends `state` {entries = [{key, level, menu}], unlocked = [key], seen = [key], next = {key, level}, all = true?} and
-- `new` {key, level, menu, title, why = [line1, line2]}; the client keeps no table of its own.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosTopBarUnlocksLogic = {}
local L = ChaosTopBarUnlocksLogic

-- how long the "Go" window stays when the player does nothing, and the screen text
L.WINDOW_SECONDS = 30
L.TEXT_MS = 4200

function L.newState()
  return {
    loaded = false,   -- false until the server's `state` came: the menu is whole (an older server, a login in progress)
    all = false,      -- the server says the whole menu (staff, the module off)
    showAll = false,  -- the player's option "Show the whole menu"
    entries = {},     -- key -> {key, level, menu}
    byMenu = {},      -- menu text -> entry
    unlocked = {},    -- key -> true
    seen = {},        -- key -> true
    next = nil,       -- {key, level}
  }
end

-- the server's `state` message replaces everything it says
function L.apply(state, data)
  if type(data) ~= 'table' then return state end
  state.entries, state.byMenu, state.unlocked, state.seen = {}, {}, {}, {}
  for _, e in ipairs(data.entries or {}) do
    if type(e) == 'table' and e.key and e.menu then
      local entry = { key = e.key, level = tonumber(e.level) or 0, menu = e.menu }
      state.entries[e.key] = entry
      state.byMenu[e.menu] = entry
    end
  end
  for _, k in ipairs(data.unlocked or {}) do state.unlocked[k] = true end
  for _, k in ipairs(data.seen or {}) do state.seen[k] = true end
  local nxt = data.next
  state.next = type(nxt) == 'table' and nxt.key and { key = nxt.key, level = tonumber(nxt.level) or 0 } or nil
  state.all = data.all == true
  state.loaded = true
  return state
end

-- an entry just unlocked (`new`): open at once, with its badge
function L.markUnlocked(state, key)
  if key then
    state.unlocked[key] = true
    state.seen[key] = nil
    if state.next and state.next.key == key then state.next = nil end
  end
end

-- the player opened the entry with this menu text: true when the badge went away (the server is told)
function L.markSeen(state, menu)
  local e = state.byMenu[menu]
  if e and state.unlocked[e.key] and not state.seen[e.key] then
    state.seen[e.key] = true
    return e.key
  end
  return nil
end

-- 'open' | 'locked' | 'hidden' for the entry with this menu text. An entry the table does not name is open (every other
-- entry of the menu); before the state came, or with the whole menu on (the server's `all` or the option), all are open.
-- The next one to unlock is 'locked' (grey, with its level); the others still locked are 'hidden'.
function L.status(state, menu)
  if not state.loaded or state.all or state.showAll then return 'open' end
  local e = state.byMenu[menu]
  if not e or state.unlocked[e.key] then return 'open' end
  if state.next and state.next.key == e.key then return 'locked', e.level end
  return 'hidden', e.level
end

-- the level an entry needs while the player cannot use it from the menu yet (a hotkey says "Unlocks at level N"), else nil.
-- A hotkey is blocked for 'locked' and 'hidden' alike.
function L.blockedLevel(state, menu)
  local s, level = L.status(state, menu)
  if s == 'open' then return nil end
  return level
end

-- the "New" badge: unlocked and not opened yet
function L.isNew(state, menu)
  local e = state.byMenu[menu]
  return e ~= nil and state.unlocked[e.key] == true and not state.seen[e.key]
end

-- texts (tr is the client's translation function; every key is in client_chaos_locale/pt_br.lua)
function L.levelLabel(level, tr)
  return string.format(tr('Level %d'), level)
end

function L.unlocksAt(level, tr)
  return string.format(tr('Unlocks at level %d'), level)
end

function L.screenText(title, tr)
  return string.format(tr('New: %s!'), title)
end

-- the text of a menu row: the shown name, then the badge or the level
function L.rowText(shown, status, level, isNew, tr)
  if status == 'locked' then return shown .. '  ' .. L.levelLabel(level, tr) end
  if isNew then return shown .. '  ' .. tr('New') end
  return shown
end

-- a message from the server (`new`) with the fields the window needs, or nil when it is not usable
function L.announcement(data)
  if type(data) ~= 'table' or not data.key or not data.title then return nil end
  local why = type(data.why) == 'table' and data.why or {}
  return { key = data.key, menu = data.menu, title = tostring(data.title), level = tonumber(data.level) or 0,
           line1 = tostring(why[1] or ''), line2 = tostring(why[2] or '') }
end

return L
