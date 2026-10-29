-- Pure helpers of the Go to NPC button (no client API), tested by npctravellogic_test.lua.
-- KEYS are the keys of the server's npc_travel_config.lua npcs (server/tests/npc_travel_test.lua holds the two lists equal).
NpcTravelLogic = {}
local L = NpcTravelLogic

L.GAP = 1.0 -- seconds between two requests of this client (the server also limits them)

L.KEYS = {
  'apothecary', 'banker', 'broker', 'candlemarks', 'conquest', 'faction_choir', 'faction_circle', 'faction_compact',
  'faction_vigil', 'gambler', 'lootbuyer', 'materials', 'odrenna', 'oracle', 'pocketboss', 'services', 'stash', 'tales',
  'trials'
}

local known
function L.valid(key)
  if not known then
    known = {}
    for _, k in ipairs(L.KEYS) do known[k] = true end
  end
  return type(key) == 'string' and known[key] == true
end

-- the factions window: the NPC key of a faction (server key "faction_" .. faction key)
function L.factionKey(factionKey)
  if type(factionKey) ~= 'string' or factionKey == '' then return nil end
  local key = 'faction_' .. factionKey
  return L.valid(key) and key or nil
end

-- true when a request at `now` is too soon after the one at `last` (both in seconds)
function L.tooSoon(now, last)
  return last ~= nil and now >= last and (now - last) < L.GAP
end

-- the message the server reads: nil for a key it does not know
function L.message(key)
  if not L.valid(key) then return nil end
  return { action = 'travel', data = { k = key } }
end
