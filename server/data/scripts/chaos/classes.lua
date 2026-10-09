-- classes.lua: the class rules that need no engine (ChaosClasses). Four base classes with two ascended classes each
-- (docs/CLASSES.md): Warrior -> Juggernaut | Berserker, Ranger -> Deadeye | Beastmaster, Mystic -> Elementalist |
-- Illusionist, Thief -> Ninja | Samurai. Tunables: Chaos.classes in chaos_constants.lua.
--
-- Used by ascension.lua (!ascend), class_migration.lua (the old vocations), thief_combat.lua (stealth, evasion, poison
-- blades, dual wield, counter stance, bushido), berserker_combat.lua (Rage, Bloodrage), beastmaster.lua (the
-- companion), passivetree.lua (keystone variants), shop_services.lua (!changevocation) and the class spells in
-- data/spells/chaos/<class> (they run in the spell Lua state and load this file themselves). Unit tests:
-- server/tests/classes_test.lua.
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
	return cfg().baseOf[vocId] == cfg().ids.thief
end

function M.isNinja(vocId)
	return vocId == cfg().ids.ninja
end

function M.isSamurai(vocId)
	return vocId == cfg().ids.samurai
end

function M.isBerserker(vocId)
	return vocId == cfg().ids.berserker
end

function M.isBeastmaster(vocId)
	return vocId == cfg().ids.beastmaster
end

-- the base class of a class (itself for a base class), nil for no class (0, retired ids)
function M.baseOf(vocId)
	return cfg().baseOf[vocId]
end

function M.isAscended(vocId)
	local base = cfg().baseOf[vocId]
	return base ~= nil and base ~= vocId
end

-- which per-vocation variant of the passive tree's keystones (nodes 621 / 624, passivetree_data.lua) a class gets:
-- the Warrior line the knight's (Cleaving Arc, Bulwark), the Ranger line the paladin's (Ricochet, Deadeye), Mystic
-- and Elementalist the sorcerer's (Arcane Echo, Overload), the Illusionist the illusionist's support keystones
-- (Shared Phantasm, Inspiring Illusion). The Thief line has no tree entry yet (nil).
local KEYSTONE_KEY = {[4] = "knight", [8] = "knight", [14] = "knight", [3] = "paladin", [7] = "paladin",
	[15] = "paladin", [1] = "sorcerer", [5] = "sorcerer", [10] = "illusionist"}
function M.keystoneKey(vocId)
	return KEYSTONE_KEY[vocId]
end

local function trimWord(word)
	return (tostring(word or "")):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function choiceNames(choices)
	local names = {}
	for k in pairs(choices) do
		names[#names + 1] = k
	end
	table.sort(names)
	return names
end

-- The ascension (!ascend <word>): returns the new vocation id, or nil and the reason.
-- vocId = current vocation, inPz = standing in a protection zone, inFight = has a fight condition,
-- freeSwitchTo = the ascended vocation id a migrated character may still switch to for free (class_migration.lua),
-- or nil. The free switch has no level rule (the character is ascended already).
function M.ascensionFor(vocId, level, word, inPz, inFight, freeSwitchTo)
	local a = cfg().ascension
	local choices = a.choices[vocId]
	local free = false
	if not choices then
		local base = cfg().baseOf[vocId]
		local own = base and base ~= vocId and a.choices[base]
		if not own then
			return nil, "Your vocation has no ascension."
		end
		local id = own[trimWord(word)]
		if freeSwitchTo and freeSwitchTo > 0 then
			local freeWord
			for k, v in pairs(own) do
				if v == freeSwitchTo then
					freeWord = k
				end
			end
			if id == vocId then
				return nil, "You already are of that class. Your free switch (to " .. tostring(freeWord) .. ") stays."
			end
			if not id or id ~= freeSwitchTo then
				return nil, "You may switch once, for free, to " .. tostring(freeWord) .. " (Character > Services)."
			end
			free = true
		else
			return nil, "You have already ascended. Only the store's Vocation Change can change that."
		end
		choices = {[trimWord(word)] = id}
	end
	local id = choices[trimWord(word)]
	if not id then
		return nil, "Choose your ascension: " .. table.concat(choiceNames(choices), " or ") .. ". The choice is final."
	end
	if not free and level < a.minLevel then
		return nil, string.format("You need level %d to ascend.", a.minLevel)
	end
	if a.needProtectionZone and not inPz then
		return nil, "Ascend in a protection zone (a temple or a depot)."
	end
	if inFight then
		return nil, "You cannot ascend in combat."
	end
	return id, free
end

-- ------------------------------------------------------------------------------------------------ migration
-- What the one-time migration does to a character of vocation `oldVoc` (an id of the old vocations, 1-10):
-- {to = new vocation id, freeSwitch = ascended id it may switch to for free or nil, resetTree = bool}.
-- nil for vocations it leaves alone (0, the Thief line, the new ids).
function M.migrationFor(oldVoc)
	local m = cfg().migration
	if type(oldVoc) ~= "number" or oldVoc < 1 or oldVoc > 10 then
		return nil
	end
	local reset = false
	for _, v in ipairs(m.resetTree) do
		if v == oldVoc then
			reset = true
		end
	end
	return {to = m.map[oldVoc] or oldVoc, freeSwitch = m.freeSwitch[oldVoc], resetTree = reset}
end

-- the login message: oldName / newName = vocation names, freeWord = the class word of the free switch or nil
function M.migrationMessage(oldName, newName, freeWord, treeReset)
	local text = string.format("The classes were reworked: your %s is now %s.", oldName, newName)
	if treeReset then
		text = text .. " Your passive tree was reset for free; allocate your points again."
	end
	if freeWord then
		text = text .. string.format(" You may switch to the other ascended class once, for free (%s): Character > Services, "
			.. "in a protection zone.", freeWord)
	end
	return text
end

-- The SQL of the one-time migration (class_migration.lua runs it at startup, before anyone can log in), in order:
-- 1. remember every old character's vocation in a storage (the login message reads it), 2. the free switch for the
-- old Elite Knights / Royal Paladins, 3. empty their passive trees, 4. move the retired ids. `tree` = the passive tree
-- table. Running it twice is harmless (storages are upserts, the retired ids are gone after the first run), but
-- class_migration.lua runs it once per migration version anyway.
function M.migrationSql(tree)
	local m, st = cfg().migration, cfg().storage
	local old = table.concat(m.resetTree, ", ")
	local q = {}
	q[#q + 1] = string.format("INSERT INTO `player_storage` (`player_id`, `key`, `value`) SELECT `id`, %d, `vocation` "
		.. "FROM `players` WHERE `vocation` BETWEEN 1 AND 10 ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)", st.migratedFrom)
	local from = {}
	for k in pairs(m.freeSwitch) do
		from[#from + 1] = k
	end
	table.sort(from)
	for _, k in ipairs(from) do
		q[#q + 1] = string.format("INSERT INTO `player_storage` (`player_id`, `key`, `value`) SELECT `id`, %d, %d "
			.. "FROM `players` WHERE `vocation` = %d ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)", st.freeSwitch,
			m.freeSwitch[k], k)
	end
	q[#q + 1] = string.format("UPDATE `%s` SET `nodes` = '' WHERE `player_id` IN (SELECT `id` FROM `players` WHERE "
		.. "`vocation` IN (%s))", tree, old)
	local ids = {}
	for k in pairs(m.map) do
		ids[#ids + 1] = k
	end
	table.sort(ids)
	for _, k in ipairs(ids) do
		q[#q + 1] = string.format("UPDATE `players` SET `vocation` = %d WHERE `vocation` = %d", m.map[k], k)
	end
	return q
end

-- ------------------------------------------------------------------------------------------------ berserker
-- Rage: the damage multiplier at `health` of `maxHealth` (1 at full health, 1 + maxBonus at fullBelow and below),
-- plus the Bloodrage bonus while that buff is up
function M.rageMultiplier(health, maxHealth, bloodrage)
	local r = cfg().rage
	local bonus = 0
	if (maxHealth or 0) > 0 then
		local missing = 1 - math.max(0, math.min(1, health / maxHealth))
		bonus = r.maxBonus * math.min(1, missing / (1 - r.fullBelow))
	end
	if bloodrage then
		bonus = bonus + cfg().bloodrage.bonus
	end
	return 1 + bonus
end

-- Bloodrage cleave: damage to each other enemy next to the Berserker for a weapon hit of `hit`
function M.bloodrageCleave(hit)
	return math.floor(math.abs(hit or 0) * cfg().bloodrage.cleave)
end

-- health the Bloodrage cast costs (never the last point)
function M.bloodrageCost(health)
	return math.max(0, math.min(health - 1, math.floor(health * cfg().bloodrage.healthCost)))
end

-- ------------------------------------------------------------------------------------------------ beastmaster
-- how many companions a Beastmaster of `level` may have out
function M.companionCap(level)
	local count = 0
	for _, step in ipairs(cfg().companion.caps) do
		if level >= step.level then
			count = step.count
		end
	end
	return count
end

function M.companionHealth(level)
	local h = cfg().companion.health
	return math.floor(h.base + h.perLevel * level)
end

-- a bite: positive min, max from the owner's level and distance skill
function M.biteValues(level, distanceSkill)
	local c = cfg().companion
	local avg = level * c.biteLevel + (distanceSkill or 0) * c.biteSkill
	return math.floor(avg * (1 - c.spread)), math.floor(avg * (1 + c.spread))
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
