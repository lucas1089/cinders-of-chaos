-- ChaosEverfullHeld: which Everfull potion each slot carries (extended opcode 116, server potions_helper.lua; tests:
-- everfullheld_test.lua; client/MANIFEST.md "Helper"). The Everfull potions show under the stock potions' looks (tier 1 as the
-- Health / Mana Potion, the upgrades as the great, ultimate and supreme potions), so the helper cannot tell them from stock
-- potions by the item. The server tells it, per slot (health, mana): { look, tier, level, line, ready } -- the stock look the
-- Everfull shows under, the line (health | mana | spirit), and `ready` when the charges a drink needs are there. The helper
-- (game_helper/helper_potions.lua P.resolve) follows an upgrade with it and Auto setup (autosetup.lua) picks it. Nothing here
-- changes what the server does: a drink is a use by look, and the server's engine finds the Everfull of that look and
-- checks level and charges itself. A message that does not fit is dropped; before the first message, or without a server
-- that sends it, nothing is held and the helper behaves as before.
ChaosEverfullHeld = ChaosEverfullHeld or {}
local E = ChaosEverfullHeld

E.OPCODE = 116
E.LINES = { health = true, mana = true, spirit = true }

local held = {}
local received = false

local function whole(v, lo, hi)
  v = tonumber(v)
  if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
  return v
end

-- one slot of a message, or nil when it does not fit (a slot the character has no Everfull in is left out by the server)
function E.clean(slot, x)
  if type(x) ~= 'table' then return nil end
  local look, tier, level = whole(x.look, 1, 65535), whole(x.tier, 1, 9), whole(x.level, 0, 99999)
  if not (look and tier and level) or not E.LINES[x.line] then return nil end
  -- the line must belong to the slot: a mana slot is a mana flask, the health slot a health or spirit flask
  if (slot == 'mana') ~= (x.line == 'mana') then return nil end
  return { look = look, tier = tier, level = level, line = x.line, ready = x.ready == true }
end

-- a `held` message's data -> the new view (replaces the old one: a slot that is absent is not carried)
function E.apply(data)
  if type(data) ~= 'table' then return false end
  held = { health = E.clean('health', data.health), mana = E.clean('mana', data.mana) }
  received = true
  return true
end

-- the view: { health = {...}|nil, mana = {...}|nil }; a fresh table, so a caller cannot change what is held
function E.get()
  local out = {}
  for slot, x in pairs(held) do
    out[slot] = { look = x.look, tier = x.tier, level = x.level, line = x.line, ready = x.ready }
  end
  return out
end

function E.reset()
  held = {}
  received = false
end

-- has a `held` message arrived this session? (Auto setup asks with E.ask() and waits a moment when not)
function E.received()
  return received
end

-- ---------------------------------------------------------------- the connection (not run by the test)
local handlers = {}

function E.ask()
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then
    protocol:sendExtendedOpcode(E.OPCODE, json.encode({ action = 'sync' }))
  end
end

local function onMessage(protocol, opcode, msg)
  if type(msg) == 'table' and msg.action == 'held' then E.apply(msg.data) end
end

local function onGameStart()
  E.reset()
  E.ask() -- the server also sends at login, which may come before this module listens
end

local function onGameEnd()
  E.reset()
end

function E.init()
  handlers.opcode = onMessage
  handlers.game = { onGameStart = onGameStart, onGameEnd = onGameEnd }
  ProtocolGame.registerExtendedJSONOpcode(E.OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  if g_game.isOnline() then onGameStart() end
end

function E.terminate()
  pcall(ProtocolGame.unregisterExtendedJSONOpcode, E.OPCODE)
  if handlers.game then disconnect(g_game, handlers.game) end
  handlers = {}
  E.reset()
end

return ChaosEverfullHeld
