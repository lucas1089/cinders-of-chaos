-- Go to NPC (server: server/data/scripts/chaos/npc_travel.lua, extended opcode 121, JSON {action, data}).
--   client -> server  travel {k}   (k: a key of npc_travel_config.lua; the server checks combat, instances, the cooldown)
-- The server answers with a game message (a status line, or a cancel message with the reason): there is nothing to read here.
-- A panel that fronts an NPC's service adds one button:
--     ChaosButton
--       id: goNpcButton
--       !text: tr('Go to NPC')
--       !tooltip: tr('Takes you in front of ...')
--       @onClick: modules.game_npctravel.travel('stash')
-- (the keys are in npctravellogic.lua KEYS). Panels that build the key at run time call
-- modules.game_npctravel.travel(key) the same way.

local OPCODE = 121
local L = NpcTravelLogic
local lastAt

local function now() return g_clock.seconds() end

function travel(key)
  local msg = L.message(key)
  if not msg then return false end
  if L.tooSoon(now(), lastAt) then return false end
  if not g_game.isOnline() then return false end
  local protocol = g_game.getProtocolGame()
  if not protocol then return false end
  lastAt = now()
  protocol:sendExtendedOpcode(OPCODE, json.encode(msg))
  return true
end

function init()
  lastAt = nil
end

function terminate()
  lastAt = nil
end
