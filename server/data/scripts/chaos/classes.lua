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

if not ChaosClassTree then
	dofile("data/scripts/chaos/class_tree.lua") -- the class nodes of the passive tree (their flags and numbers)
end

ChaosClasses = ChaosClasses or {}
local M = ChaosClasses

local function cfg()
	return Chaos.classes
end

M.now = os.mtime or function() return os.time() * 1000 end

-- ------------------------------------------------------------------ class outfits (the donor art ones)
local function replacementFor(vocId)
	local r = cfg().outfitReplacement
	if not (r and r.enabled and r.outfit and r.outfit.lookType) then
		return nil
	end
	for _, v in ipairs(r.vocations or {}) do
		if v == vocId then
			return r
		end
	end
	return nil
end

-- the replacement outfit's look for a sex (0 = female: `female` when set; else lookType, the male look)
local function replacementLook(o, sex)
	return (sex == 0 and o.female) or o.lookType
end

-- the class outfits a vocation is given (Chaos.classes.outfits, plus the replacement outfit while its switch is on:
-- {lookType = the look of `sex`, name, addons}); a fresh list, never nil. Retired outfits
-- (Chaos.classes.retiredOutfits) are never in it. sex: 0 female, 1 male (nil: male)
function M.classOutfitsFor(vocId, sex)
	local out, seen = {}, {}
	for _, o in ipairs((cfg().outfits or {})[vocId] or {}) do
		out[#out + 1] = o; seen[o.lookType] = true
	end
	local r = replacementFor(vocId)
	local look = r and replacementLook(r.outfit, sex)
	if r and not seen[look] then
		out[#out + 1] = {lookType = look, name = r.outfit.name, addons = r.outfit.addons}
	end
	return out
end

-- the look type a character of this vocation and sex wearing `worn` is moved to at login, or nil (switch off,
-- another vocation, or not wearing the replaced outfit or the other sex's replacement look)
function M.outfitSwap(vocId, worn, sex)
	local r = replacementFor(vocId)
	if not r then
		return nil
	end
	local look = replacementLook(r.outfit, sex)
	local other = replacementLook(r.outfit, sex == 0 and 1 or 0)
	if worn == r.replaces or (worn == other and other ~= look) then
		return look
	end
	return nil
end

-- true for a retired class outfit (kept wearable, never given, never sold)
function M.isRetiredOutfit(lookType)
	for _, o in ipairs(cfg().retiredOutfits or {}) do
		if o.lookType == lookType then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------------------------------------ vocations
function M.isThiefLine(vocId)
	return cfg().baseOf[vocId] == cfg().ids.thief
end

function M.isNinja(vocId)
	return vocId == cfg().ids.ninja
end

-- Thief and Ninja hold a blade in each hand (cfg.dualWield.vocations); the Samurai keeps one sword
function M.isDualWielder(vocId)
	return cfg().dualWield.vocations[vocId] == true
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

-- which per-class variant of the passive tree's keystones (nodes 621 / 624, passivetree_data.lua `v`) a class gets:
-- the Warrior the knight's (Cleaving Arc, Bulwark), the Juggernaut Immovable + Bulwark, the Berserker Cleaving Arc +
-- Undying Rage; the Ranger the paladin's (Ricochet, Deadeye), the Deadeye Hunter's Focus + Deadeye, the Beastmaster
-- Ricochet + Pack Alpha; Mystic and Elementalist the sorcerer's (Arcane Echo, Overload), the Illusionist its support
-- keystones (Shared Phantasm, Inspiring Illusion). The Thief, Necromancer, Monk and Templar lines have their keystones
-- in their class sections (class_tree.lua); their key is the class key. Since 2026-10-20 every one of them has its own
-- pair there too under that key (class_keystones_config.lua: Shadow Twin / Viper's Verdict, Corpse Detonation /
-- Reaper's Toll, Seventh Palm / Piercing Palm, Radiant Rebuke / Dawnchain); the Iron Sage keeps Overgrowth on 621
-- (since 2026-10-12) with Piercing Palm on 624, the Sentinel Thorns on 624 with Radiant Rebuke on 621.
local KEYSTONE_KEY = {[4] = "knight", [8] = "juggernaut", [14] = "berserker", [3] = "paladin", [7] = "deadeye",
	[15] = "beastmaster", [1] = "sorcerer", [5] = "sorcerer", [10] = "illusionist"}
function M.keystoneKey(vocId)
	return KEYSTONE_KEY[vocId] or M.classKey(vocId)
end

-- the class key of a vocation ("warrior", "juggernaut", ... "sentinel"; the keys of Chaos.classes.ids), nil for none.
-- The passive tree marks the nodes a class may hold with these keys (class_tree.lua).
function M.classKey(vocId)
	local c = Chaos and Chaos.classes
	if not c or not c.ids then
		return nil
	end
	for key, id in pairs(c.ids) do
		if id == vocId then
			return key
		end
	end
	return nil
end

-- the class key of the vocation's base class (its line), nil for none
function M.lineKey(vocId)
	local base = Chaos and Chaos.classes and Chaos.classes.baseOf and Chaos.classes.baseOf[vocId]
	return base and M.classKey(base) or nil
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

-- a bite: positive min, max from the owner's level and distance skill (x factor: the Pack Alpha keystone)
function M.biteValues(level, distanceSkill, factor)
	local c = cfg().companion
	local avg = (level * c.biteLevel + (distanceSkill or 0) * c.biteSkill) * (factor or 1)
	return math.floor(avg * (1 - c.spread)), math.floor(avg * (1 + c.spread))
end

-- the bite of this owner's companions: level, distance skill and the Pack Alpha keystone (class_tree.lua)
function M.biteValuesFor(player)
	return M.biteValues(player:getLevel(), player:getEffectiveSkillLevel(SKILL_DISTANCE),
		1 + ChaosClassTree.value(player, "ksPackAlpha", "bonus"))
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
function M.offhandDamage(hit, mainAttack, offAttack, targetIsPlayer, extraShare)
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
	local value = hit * (d.share + (extraShare or 0)) * ratio
	if targetIsPlayer then
		value = value * 2
	end
	return math.floor(value + 0.5)
end

-- The auto attack's speed compensation: a weapon hit of a vocation whose attack interval was shortened is cut by
-- now / was (cfg.attackSpeed), so its damage per second stays where it was balanced. 1 for every other vocation.
function M.speedComp(vocId)
	local a = cfg().attackSpeed[vocId]
	if not a then
		return 1
	end
	return a.now / a.was
end

-- The Thief's two daggers: the main hit is cut so that main + off-hand hit deal what the single hit did (the off-hand
-- tree bonus is on top). 1 for a vocation that is not `neutral` (the Ninja), or without a blade in the off hand
function M.dualNeutral(vocId, mainAttack, offAttack)
	local d = cfg().dualWield
	if not d.neutral[vocId] then
		return 1
	end
	local ratio = 1
	if (mainAttack or 0) > 0 then
		ratio = (offAttack or 0) / mainAttack
	end
	ratio = math.max(d.minRatio, math.min(d.maxRatio, ratio))
	return 1 / (1 + d.share * ratio)
end

-- What to do at login about the second dagger of a Thief made before it dual wielded. Once per character (`flag`,
-- storage offhandGranted). leftIsBlade: the main hand holds a one-handed sword. rightKind: nil = empty off hand,
-- "blade" = a one-handed sword, "other" = a shield or anything else.
--   "grant"  put a dagger in the empty off hand (and set the flag)
--   "mark"   the off hand holds a blade already: set the flag, give nothing
--   nil      nothing now (not a Thief, flag set, no main-hand blade yet, or a shield in the off hand: the grant stays
--            open until the off hand is empty, it is still one dagger at most)
function M.offhandGrant(vocId, flag, leftIsBlade, rightKind)
	if (flag or 0) > 0 or vocId ~= cfg().ids.thief then
		return nil
	end
	if rightKind == "blade" then
		return "mark"
	end
	if rightKind == nil and leftIsBlade then
		return "grant"
	end
	return nil
end

-- Poison Blades: damage per tick for a weapon hit of `hit`. bonus: Blackblood Creed's poisonBonus (0 / nil = none).
-- vocId: the attacker's vocation (cfg.poisonBlades.classScale; nil = the plain share)
function M.poisonTick(hit, bonus, vocId)
	local p = cfg().poisonBlades
	local scale = vocId and p.classScale and p.classScale[vocId] or 1
	return math.max(1, math.floor(math.abs(hit or 0) * p.share * scale * (1 + (bonus or 0)) / p.ticks + 0.5))
end

-- Blackblood Creed (the line keystone): does a weapon hit poison? With the keystone always, else while Poison Blades lasts
function M.weaponPoisons(isWeapon, bladesBuff, creed)
	return isWeapon == true and (bladesBuff == true or creed == true)
end

-- Blackblood Creed poisons EVERY attack, not only weapon hits: a spell hit (single target or area) and a wand hit too.
-- isAttack: the hit is an attack (weapon, spell or wand origin). The poison's own ticks (ORIGIN_CONDITION), scripted
-- strikes (ORIGIN_NONE) and healing are never attacks, so the poison cannot proc itself.
function M.creedPoisons(isAttack, creed)
	return isAttack == true and creed == true
end

-- scale: Blackblood Creed's evasionScale (nil = 1)
function M.dodgeChance(vocId, extra, scale)
	local base = cfg().evasion[vocId]
	if not base then
		return 0
	end
	return (base + (extra or 0)) * (scale or 1)
end

-- `roll` in [0, 1) (math.random()); only weapon-style attacks (melee or ranged origin) can be dodged.
-- extra: evasion from the passive tree (Fleet Shadow); scale: Blackblood Creed halves it
function M.dodges(vocId, isWeaponAttack, roll, extra, scale)
	if not isWeaponAttack then
		return false
	end
	return roll < M.dodgeChance(vocId, extra, scale)
end

-- Living Shadow (Ninja keystone): livingState[id] = ms the window ends
M.livingState = M.livingState or {}

function M.livingOpen(id, now)
	M.livingState[id] = now + ChaosClassTree.fx.ksLivingShadow.durationMs
end

-- the damage factor of a weapon hit or strike at `now` (1 outside the window)
function M.livingFactor(id, now)
	local untilMs = M.livingState[id]
	if untilMs and now < untilMs then
		return 1 + ChaosClassTree.fx.ksLivingShadow.bonus
	end
	return 1
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
-- An off-hand strike follows a main-hand hit when: the attacker is a Thief or Ninja, the hit is a melee weapon hit (not a
-- scripted strike: `scripted` is the guard flag thief_combat.lua sets around its own strikes), and both hands hold
-- a light blade.
function M.dualWieldProc(vocId, isMeleeWeaponHit, mainIsBlade, offIsBlade, scripted, amount)
	return M.isDualWielder(vocId) and isMeleeWeaponHit and mainIsBlade and offIsBlade and not scripted
		and math.abs(amount or 0) > 0 or false
end

-- ------------------------------------------------------------------------------------------------ counter stance
-- The stance is a condition of windowMs; `ticksLeft` is what is left of it (0 or nil = no stance).
-- A melee hit inside the window is parried (the caller removes the condition: one parry per stance).
function M.counterTake(ticksLeft, isMelee, fromCreature)
	return (ticksLeft or 0) > 0 and isMelee and fromCreature and true or false
end

-- Counter Stance guard: the damage factor of a hit the stance does not parry (1 without a stance)
function M.counterGuard(ticksLeft)
	if (ticksLeft or 0) > 0 then
		return 1 - (cfg().counter.guard or 0)
	end
	return 1
end

-- bonus: Iron Parry (+50% of the answer)
function M.counterDamage(parried, bonus)
	return math.floor(math.abs(parried or 0) * cfg().counter.multiplier * (1 + (bonus or 0)) + 0.5)
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

-- damage taken: the stacks start again from zero (the buff itself stays); keepShare: the share of the stacks a hit
-- leaves (Way of the Blade: half)
function M.bushidoOnDamaged(id, now, keepShare)
	local s = M.bushidoState[id]
	if s and now < s.untilMs then
		local keep = math.floor(M.bushidoStacks(id, now) * (keepShare or 0))
		s.base, s.since = keep, now
	end
end

function M.bushidoCritChance(id, now)
	return M.bushidoStacks(id, now) * cfg().bushido.perStack
end

-- `roll` in [0, 1): multiplier for this hit (critMultiplier on a crit, else 1) and whether it was a crit;
-- critMultiplier: Way of the Blade's (x1.8), else the buff's
function M.bushidoRoll(id, now, roll, critMultiplier)
	local chance = M.bushidoCritChance(id, now)
	if chance > 0 and roll < chance then
		return critMultiplier or cfg().bushido.critMultiplier, true
	end
	return 1, false
end

-- Shadow Mend (thief/shadow_mend.lua): min and max of the self heal, before the engine's own healing modifiers
function M.shadowMendRange(maxHealth, level, magicLevel, veiled)
	local h = cfg().shadowMend
	local avg = (level or 0) * h.perLevel + (magicLevel or 0) * h.perMagicLevel + (maxHealth or 0) * h.maxHealthShare
	if veiled then
		avg = avg * h.veiledMultiplier
	end
	return math.floor(avg * (1 - h.spread)), math.floor(avg * (1 + h.spread))
end

-- keep the dual-wield storage (read by server/src-patches/0002) in line with the vocation: login, ascension,
-- vocation change
function M.syncDualWield(player)
	local key = cfg().storage.dualWield
	local want = M.isDualWielder(player:getVocation():getId()) and 1 or -1
	if player:getStorageValue(key) ~= want then
		player:setStorageValue(key, want)
	end
end

-- The one-time second dagger of a Thief made before dual wield (M.offhandGrant): at login, after syncDualWield (the
-- engine takes a sword in the shield hand only while that storage is 1). Gives nothing to a Thief who has an off-hand
-- weapon, a shield or no main-hand dagger, and nothing twice. Returns "grant", "mark" or nil.
function M.grantOffhand(player)
	local c = cfg()
	local function bladeIn(slot)
		local item = player:getSlotItem(slot)
		if not item then
			return false, nil
		end
		local it = ItemType(item:getId())
		return M.isLightBlade(it:getWeaponType(), it:getSlotPosition()), item
	end
	local left = bladeIn(CONST_SLOT_LEFT)
	local rightBlade, rightItem = bladeIn(CONST_SLOT_RIGHT)
	local kind = rightItem and (rightBlade and "blade" or "other") or nil
	local flag = player:getStorageValue(c.storage.offhandGranted)
	local act = M.offhandGrant(player:getVocation():getId(), flag, left, kind)
	if act == "grant" then
		-- mark first: a failed add must not be retried forever, and never gives two
		player:setStorageValue(c.storage.offhandGranted, os.time())
		if player:addItem(c.offhandGrant.itemId, 1, false, 1, CONST_SLOT_RIGHT) then
			local text = "Your Thief now fights with a dagger in each hand. You received a second dagger."
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t and Chaos.t(player, text) or text)
		end
	elseif act == "mark" then
		player:setStorageValue(c.storage.offhandGranted, os.time())
	end
	return act
end

-- forget everything about a creature (logout, death)
function M.clear(id)
	M.bushidoState[id] = nil
	M.livingState[id] = nil
end

return M
