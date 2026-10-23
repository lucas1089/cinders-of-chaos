-- game_targetguard: who the player's own targeting may pick (client/MANIFEST.md "Target guard"). Global
-- ChaosTargetGuard, pure (no UI, no engine calls beyond the creature passed in), so base patch 0112 can call it from
-- modules/game_helper/classes/auto_target.lua and modules/game_battle/battle.lua. Tests: targetguard_test.lua.
--
-- Owner report 2026-10-21: "the Necromancer's risen warriors do not attack, they get targeted and block the way".
-- The 10.98 creature packet sends no master id, so the helper's `getMasterId() ~= 0` test never matched a summon.
-- Base patch 0076 made the Auto Target's own pick skip summon creature types, but two paths still reached the
-- player's own minions: the battle list's attack next / previous (the own summon stands closest, so it is first in
-- the list) and a click on it in the battle list or the map. Each sets the helper's locked target, and the lock path
-- re-sent the attack whenever the player was not attacking it. The server refuses the own summon (summons.lua:
-- "You may not attack this creature." and a cancel), so the helper sent it again on its next tick, without end: the
-- player never held a real target, and the minions, which go for their owner's target, stood idle next to it.
--   * keepLock: a lock on the player's own summon (creature type 3, CreatureTypeSummonOwn) is dropped at once;
--   * lockAction: a lock the server keeps cancelling (a party member's summon, a protection zone) is dropped after
--     `maxSends` re-sends within `windowMs`, instead of one refused attack per helper tick;
--   * attackCycle: the battle list's attack next / previous skips the player's own summons.
ChaosTargetGuard = ChaosTargetGuard or {}
local G = ChaosTargetGuard

G.SUMMON_OWN, G.SUMMON_OTHER = 3, 4 -- Proto::CreatureTypeSummonOwn / CreatureTypeSummonOther (modules/gamelib/creature.lua)
G.maxSends = 3
G.windowMs = 3000
G.lockState = G.lockState or {id = 0, sends = {}}

local function typeOf(creature)
  if not creature or not creature.getType then
    return nil
  end
  local ok, t = pcall(creature.getType, creature)
  return ok and t or nil
end

-- the player's own summon (the server sends type 3 to its master only)
function G.isOwnSummon(creature)
  return typeOf(creature) == G.SUMMON_OWN
end

-- any player's summon
function G.isSummon(creature)
  local t = typeOf(creature)
  return t == G.SUMMON_OWN or t == G.SUMMON_OTHER
end

-- may the helper keep its locked target on `creature`
function G.keepLock(creature)
  return creature ~= nil and not G.isOwnSummon(creature)
end

-- The helper's locked target `lockId` is not the creature being attacked (`attackingId`, 0 for none) at time `now`
-- (ms): "keep" (it is), "attack" (send the attack again) or "drop" (the server refused it maxSends times within
-- windowMs: forget the lock). `state` keeps the re-sends of the current lock (G.lockState by default).
function G.lockAction(state, lockId, attackingId, now)
  state = state or G.lockState
  if lockId == nil or lockId == 0 then
    return "keep"
  end
  if attackingId == lockId then
    return "keep"
  end
  if state.id ~= lockId then
    state.id, state.sends = lockId, {}
  end
  local kept = {}
  for _, t in ipairs(state.sends) do
    if now - t < G.windowMs then
      kept[#kept + 1] = t
    end
  end
  state.sends = kept
  if #kept >= G.maxSends then
    state.id, state.sends = 0, {}
    return "drop"
  end
  kept[#kept + 1] = now
  return "attack"
end

-- the creatures of the battle list that attack next / previous may pick: every one but the player's own summons
function G.attackCycle(creatures)
  local list = {}
  for _, c in ipairs(creatures or {}) do
    if not G.isOwnSummon(c) then
      list[#list + 1] = c
    end
  end
  return list
end

return G
