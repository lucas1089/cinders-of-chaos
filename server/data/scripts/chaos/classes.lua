-- classes.lua: the class rules that need no engine (ChaosClasses). Phase 1 of the class rework: the Thief line
-- (Thief -> Ninja | Samurai, docs/CLASSES.md). Tunables: Chaos.classes in chaos_constants.lua.
--
-- Used by ascension.lua (!ascend), thief_combat.lua (stealth, evasion, poison blades, dual wield, counter stance,
-- bushido), shop_services.lua (!changevocation) and the spells in data/spells/chaos/thief|ninja|samurai (they run in
-- the spell Lua state and load this file themselves). Unit tests: server/tests/classes_test.lua.
--
-- Times are milliseconds from whatever clock the caller passes (os.mtime on the server), so the state machines
-- can be tested without an engine. State is per creature id and lives in memory: it does not survive a relog
-- or a /reload, which is fine for buffs of a few seconds.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosClasses = ChaosClasses or {}
local M = ChaosClasses

local function cfg()
	return Chaos.classes
end

M.now = os.mtime or function() return os.time() * 1000 end

-- ------------------------------------------------------------------------------------------------ vocations
function M.isThiefLine(vocId)
	local ids = cfg().ids
	return vocId == ids.thief or vocId == ids.ninja or vocId == ids.samurai
end

function M.isNinja(vocId)
	return vocId == cfg().ids.ninja
end

function M.isSamurai(vocId)
	return vocId == cfg().ids.samurai
end

-- The ascension (!ascend <word>): returns the new vocation id, or nil and the reason.
-- vocId = current vocation, inPz = standing in a protection zone, inFight = has a fight condition.
function M.ascensionFor(vocId, level, word, inPz, inFight)
	local a = cfg().ascension
	local choices = a.choices[vocId]
	if not choices then
		for _, list in pairs(a.choices) do
			for _, id in pairs(list) do
				if id == vocId then
					return nil, "You have already ascended. Only the store's Vocation Change can change that."
				end
			end
		end
		return nil, "Your vocation has no ascension yet."
	end
	local names = {}
	for k in pairs(choices) do
		names[#names + 1] = k
	end
	table.sort(names)
	local id = choices[(tostring(word or "")):lower():gsub("^%s+", ""):gsub("%s+$", "")]
	if not id then
		return nil, "Choose your ascension: !ascend " .. table.concat(names, "|") .. ". The choice is final."
	end
	if level < a.minLevel then
		return nil, string.format("You need level %d to ascend.", a.minLevel)
	end
	if a.needProtectionZone and not inPz then
		return nil, "Ascend in a protection zone (a temple or a depot)."
	end
	if inFight then
		return nil, "You cannot ascend in combat."
	end
	return id
end

-- ------------------------------------------------------------------------------------------------ weapons
-- A "dagger-type" weapon for the dual wield: any one-handed sword (daggers and light blades).
-- weaponType / slotPosition as ItemType:getWeaponType() / getSlotPosition() return them.
function M.isLightBlade(weaponType, slotPosition)
	if weaponType == nil or weaponType ~= WEAPON_SWORD then
		return false
	end
	local twoHand = SLOTP_TWO_HAND or 2048
	return math.floor((slotPosition or 0) / twoHand) % 2 == 0
end

-- Damage of the off-hand strike that follows a main-hand weapon hit of `hit` (positive).
-- The engine halves damage between players before onHealthChange sees it and halves the scripted strike again,
-- so against a player the strike is computed from the unhalved hit.
function M.offhandDamage(hit, mainAttack, offAttack, targetIsPlayer)
	local d = cfg().dualWield
	hit = math.abs(hit or 0)
	if hit <= 0 then
		return 0
	end
	local ratio = 1
	if (mainAttack or 0) > 0 then
		ratio = (offAttack or 0) / mainAttack
	end
	ratio = math.max(d.minRatio, math.min(d.maxRatio, ratio))
	local value = hit * d.share * ratio
	if targetIsPlayer then
		value = value * 2
	end
	return math.floor(value + 0.5)
end

-- Poison Blades: damage per tick for a weapon hit of `hit`.
function M.poisonTick(hit)
	local p = cfg().poisonBlades
	return math.max(1, math.floor(math.abs(hit or 0) * p.share / p.ticks + 0.5))
end

function M.dodgeChance(vocId)
	return cfg().evasion[vocId] or 0
end

-- `roll` in [0, 1) (math.random()); only weapon-style attacks (melee or ranged origin) can be dodged
function M.dodges(vocId, isWeaponAttack, roll)
	if not isWeaponAttack then
		return false
	end
	return roll < M.dodgeChance(vocId)
end

-- ------------------------------------------------------------------------------------------------ stealth
-- Shadow Veil is a condition on the player (the spell adds it; the spell and this file run in different Lua
-- states, so the condition is the state both can see). These decide what an event does to it.

-- the stealthed player deals damage: returns the damage multiplier and whether the stealth ends.
-- Any damage ends it; the first weapon hit out of it is a critical hit (ambushMultiplier).
function M.stealthOnAttack(active, isWeaponHit, amount)
	if not active or (amount or 0) == 0 then
		return 1, false
	end
	if isWeaponHit then
		return cfg().stealth.ambushMultiplier, true
	end
	return 1, true
end

-- the stealthed player is hit by a creature: true when the stealth ends (a dodged or parried hit does not count)
function M.stealthOnHit(active, amount, fromCreature)
	return active and fromCreature and (amount or 0) ~= 0 or false
end

-- a monster may keep (or pick) this player as its target
function M.monsterMayTarget(stealthActive, isPlayerTarget)
	return not (stealthActive and isPlayerTarget)
end

-- ------------------------------------------------------------------------------------------------ dual wield
-- An off-hand strike follows a main-hand hit when: the attacker is a Ninja, the hit is a melee weapon hit (not a
-- scripted strike: `scripted` is the guard flag thief_combat.lua sets around its own strikes), and both hands hold
-- a light blade.
function M.dualWieldProc(vocId, isMeleeWeaponHit, mainIsBlade, offIsBlade, scripted, amount)
	return M.isNinja(vocId) and isMeleeWeaponHit and mainIsBlade and offIsBlade and not scripted
		and math.abs(amount or 0) > 0 or false
end

-- ------------------------------------------------------------------------------------------------ counter stance
-- The stance is a condition of windowMs; `ticksLeft` is what is left of it (0 or nil = no stance).
-- A melee hit inside the window is parried (the caller removes the condition: one parry per stance).
function M.counterTake(ticksLeft, isMelee, fromCreature)
	return (ticksLeft or 0) > 0 and isMelee and fromCreature and true or false
end

function M.counterDamage(parried)
	return math.floor(math.abs(parried or 0) * cfg().counter.multiplier + 0.5)
end

-- ------------------------------------------------------------------------------------------------ bushido
-- state[id] = {untilMs = , base = stacks at `since`, since = ms}
M.bushidoState = M.bushidoState or {}

function M.bushidoStart(id, now)
	local b = cfg().bushido
	local old = M.bushidoState[id]
	local keep = old and now < old.untilMs and M.bushidoStacks(id, now) or 0
	M.bushidoState[id] = {untilMs = now + b.durationMs, base = math.max(keep, b.startStacks), since = now}
end

function M.bushidoStacks(id, now)
	local s = M.bushidoState[id]
	if not s then
		return 0
	end
	if now >= s.untilMs then
		M.bushidoState[id] = nil
		return 0
	end
	local b = cfg().bushido
	return math.min(b.maxStacks, s.base + math.floor((now - s.since) / b.stackMs))
end

-- damage taken: the stacks start again from zero (the buff itself stays)
function M.bushidoOnDamaged(id, now)
	local s = M.bushidoState[id]
	if s and now < s.untilMs then
		s.base, s.since = 0, now
	end
end

function M.bushidoCritChance(id, now)
	return M.bushidoStacks(id, now) * cfg().bushido.perStack
end

-- `roll` in [0, 1): multiplier for this hit (critMultiplier on a crit, else 1) and whether it was a crit
function M.bushidoRoll(id, now, roll)
	local chance = M.bushidoCritChance(id, now)
	if chance > 0 and roll < chance then
		return cfg().bushido.critMultiplier, true
	end
	return 1, false
end

-- keep the dual-wield storage (read by server/src-patches/0002) in line with the vocation: login, ascension,
-- vocation change
function M.syncDualWield(player)
	local key = cfg().storage.dualWield
	local want = M.isNinja(player:getVocation():getId()) and 1 or -1
	if player:getStorageValue(key) ~= want then
		player:setStorageValue(key, want)
	end
end

-- forget everything about a creature (logout, death)
function M.clear(id)
	M.bushidoState[id] = nil
end

return M
