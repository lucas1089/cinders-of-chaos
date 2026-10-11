-- Chaos item modifiers on the character: the totals of the equipped items' Chaos modifiers (data/lib/chaos_item_mods.lua,
-- custom attributes "chaos_mod_<key>") applied to the player. Overview: server/README.md "Item modifiers".
--
-- Like customs/rarity/base_rarity.lua, the totals are worked out again when an item is put on or taken off
-- (EventCallback onItemMoved) and at login; a check every few seconds catches items that left a slot another way
-- (decay, a script). The totals are kept in memory per player (ChaosItemModsCache) and capped per modifier; nothing
-- is written to storages, so nothing can stack across logins.
--   movement speed     Creature:changeSpeed by the difference to what was applied before (% of the base speed)
--   attack speed       none here: it is the weapon's own attack interval (chaos_item_mods.lua M.syncAttackSpeed)
--   elites and bosses  damage dealt to magic / rare / legendary monsters and bosses (onHealthChange on the target,
--                      registered by onTargetCombat, like passivetree_effects.lua)
--   life / mana on kill  CreatureEvent onKill, monsters only
--   dodge, block, reflect, thorns, damage taken from monsters  onHealthChange on the player (hits from creatures)
--   healing done       onHealthChange on the healed player (the healer's bonus)
--   on your hits       onHealthChange on the target (registered by onTargetCombat): penetration (physical / elemental:
--                      the monster's resistance counts that many points lower, as the Sunder support), damage over time
--                      (hits of conditions you own), execute (a non-boss monster your hit leaves at or below N% health
--                      dies), health / mana on hit, and the ailment chances: bleeding (physical), ignite (fire), poison
--                      (earth) deal a share of the hit over a few seconds (conditions owned by you), chill slows, shock
--                      makes the monster take more damage from everyone for a few seconds
--   health regeneration  the equipment check every 3 s heals 3 x the total
--   cooldown / mana cost reduction  on the spell side (data/spells/chaos/_supports.lua, after a cast, as the
--                      Quickening and Thrift supports)
--   experience         EventCallback onGainExperience
--   gold find          EventCallback onDropLoot (priority 2, as Paragon's gold find)
--   item / rarity find read by loot.lua (ChaosItemMods.playerBonus)
-- The gems in the sockets of the same items (data/lib/chaos_gems.lua) are summed on the same path: their totals
-- (ChaosGems.totals) are worked out here with the modifiers' and handed to gems.lua (ChaosGems.applyTotals); gem
-- Movement Speed is added to the modifier's under the modifier's cap.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua") -- loads chaos_item_mods.lua
end

local M = ChaosItemMods
ChaosItemModsCache = ChaosItemModsCache or {} -- player id -> totals {key -> value}
local cache = ChaosItemModsCache
local applied = {} -- player id -> {speed = n, sig = "..."}
local CHECK_INTERVAL = 3000 -- ms between two checks of the equipment of everyone online
local guard = false -- reflect / thorns hits must not trigger more reflect / thorns

-- ---------------------------------------------------------------- equipped items
local SLOT_BITS = M.slotBits()

local function equipped(player)
	local items, sig = {}, {}
	for slot in pairs(SLOT_BITS) do
		local item = player:getSlotItem(slot)
		if item and M.fits(item, slot, SLOT_BITS) then
			local mods = M.read(item)
			local gems = ChaosGems and ChaosGems.read(item)
			local veil = ChaosVeiled and ChaosVeiled.read(item) -- an unveiled modifier counts too (veiled.lua)
			if #mods > 0 or (gems and gems.filled > 0) or (veil and veil.state == "open") then
				items[#items + 1] = item
				if veil and veil.state == "open" then
					sig[#sig + 1] = slot .. "v" .. veil.key .. veil.value
				end
				for _, m in ipairs(mods) do
					sig[#sig + 1] = slot .. m.key .. m.value
				end
				for i = 1, gems and gems.count or 0 do
					if gems.gems[i] > 0 then
						sig[#sig + 1] = slot .. "g" .. i .. ":" .. gems.gems[i]
					end
				end
			end
		end
	end
	table.sort(sig)
	return items, table.concat(sig, ",")
end

-- ---------------------------------------------------------------- totals and speed
local function applySpeed(player, state, totals)
	local want = M.speedBonus(player:getBaseSpeed(), totals.movespeed or 0)
	if want ~= state.speed then
		player:changeSpeed(want - state.speed)
		state.speed = want
	end
end

function M.refresh(player, force)
	local id = player:getId()
	local state = applied[id] or {speed = 0, sig = nil}
	applied[id] = state
	local items, sig = equipped(player)
	-- item sets (itemsets.lua): the active set bonuses' modifier numbers, added to the items' before the caps
	local setMods
	if ChaosItemSets and ChaosItemSets.refresh then
		local setSig
		setMods, setSig = ChaosItemSets.refresh(player)
		sig = sig .. "|" .. tostring(setSig or "")
	end
	if not force and sig == state.sig then
		return cache[id]
	end
	state.sig = sig
	-- veiled modifiers (chaos_veiled.lua): catalogue numbers under the catalogue's caps, their own keys capped apart
	local veilOwn
	if ChaosVeiled and ChaosVeiled.totals then
		local veilMods
		veilMods, veilOwn = ChaosVeiled.totals(items)
		setMods = ChaosVeiled.merge(setMods, veilMods)
	end
	local totals = M.totals(items, setMods)
	for k, v in pairs(veilOwn or {}) do
		totals[k] = v
	end
	if ChaosGems and ChaosGems.totals then
		local gemTotals = ChaosGems.totals(items)
		local def = M.byKey.movespeed
		totals.movespeed = math.min(def and def.cap or 12, (totals.movespeed or 0) + (gemTotals.movespeed or 0))
		if ChaosGems.applyTotals then
			ChaosGems.applyTotals(player, gemTotals)
		end
	end
	cache[id] = totals
	applySpeed(player, state, totals)
	if ChaosEnergyShield and ChaosEnergyShield.apply then
		ChaosEnergyShield.apply(player, totals) -- maximum and recharge of the energy shield (engine patch 0015)
	end
	return totals
end

-- a player's capped total of one modifier (0 when none or offline)
function M.playerBonus(player, key)
	if not player then
		return 0
	end
	local ok, id = pcall(function() return player:getId() end)
	local totals = ok and cache[id]
	return totals and totals[key] or 0
end

-- ---------------------------------------------------------------- equip / unequip
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	-- a drop that leaves its corpse before the tick that gives its rarity back as a number (C.shield)
	if ChaosCrafting and ChaosCrafting.unshield and ChaosCrafting.unshield(item) then
		M.sendUpdate(item)
	end
	local inv = CONTAINER_POSITION or 0xFFFF
	local fromSlot = fromPosition.x == inv and math.floor(fromPosition.y / 64) % 2 == 0
	local toSlot = toPosition.x == inv and math.floor(toPosition.y / 64) % 2 == 0
	if fromSlot or toSlot then
		M.refresh(player)
	end
end
moved:register(11) -- after base_rarity.lua (10)

-- this engine's Creature:addHealth takes (damage type, amount); a one-argument call heals nothing (Chaos.heal)
local function heal(creature, amount)
	if Chaos.heal then
		return Chaos.heal(creature, amount)
	end
	local before = creature:getHealth()
	amount = math.min(math.floor(amount), creature:getMaxHealth() - before)
	if amount > 0 then
		creature:addHealth("healing", amount)
		if creature:getHealth() == before then
			creature:addHealth(amount)
		end
	end
end

local function regenerate(player)
	local totals = cache[player:getId()]
	local per = totals and totals.regen or 0
	if per > 0 and player:getHealth() > 0 and player:getHealth() < player:getMaxHealth() then
		heal(player, M.regenAmount(per, CHECK_INTERVAL))
	end
end

local function checkAll()
	for _, player in ipairs(Game.getPlayers()) do
		if applied[player:getId()] then
			M.refresh(player)
			regenerate(player)
		end
	end
	addEvent(checkAll, CHECK_INTERVAL)
end

local startup = GlobalEvent("ChaosItemModsStartup")
function startup.onStartup()
	addEvent(checkAll, CHECK_INTERVAL)
	return true
end
startup:register()

-- ---------------------------------------------------------------- damage
local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function isElite(creature)
	if not creature or not creature:isMonster() then
		return false
	end
	local tier = type(ChaosTierOf) == "function" and ChaosTierOf(creature) or "normal"
	if tier ~= "normal" then
		return true
	end
	local mt = creature:getType()
	local ok, boss = pcall(function() return mt and mt:isBoss() end)
	return ok and boss or false
end

-- bosses, world bosses and rift / omen guardians are never executed
local function executeProof(creature)
	local mt = creature:getType()
	local ok, boss = pcall(function() return mt and mt:isBoss() end)
	if ok and boss then
		return true
	end
	local run = ChaosRift and ChaosRift.monsterRun and ChaosRift.monsterRun[creature:getId()]
	if run and run.bossIds and run.bossIds[creature:getId()] then
		return true
	end
	local wb = ChaosWorldBoss and ChaosWorldBoss.state
	return wb ~= nil and wb.bossId == creature:getId()
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

-- monster resistances (MonsterType:getElementList: combat type -> percent), cached by name
local resCache = {}
local function resistance(creature, ctype)
	local name = typeNameOf(creature):lower()
	local r = resCache[name]
	if r == nil then
		local ok, list = pcall(function()
			local t = creature:getType()
			return t and t:getElementList()
		end)
		r = ok and type(list) == "table" and list or false
		resCache[name] = r
	end
	return r and tonumber(r[ctype]) or 0
end

local NOT_ELEMENTAL = {}
for _, n in ipairs({"COMBAT_PHYSICALDAMAGE", "COMBAT_HEALING", "COMBAT_LIFEDRAIN", "COMBAT_MANADRAIN", "COMBAT_NONE",
		"COMBAT_UNDEFINEDDAMAGE"}) do
	if _G[n] then
		NOT_ELEMENTAL[_G[n]] = true
	end
end

local function penetrate(creature, value, ctype, totals)
	if value == 0 or not ctype then
		return value
	end
	local pen = ctype == COMBAT_PHYSICALDAMAGE and totals.physpen or (not NOT_ELEMENTAL[ctype] and totals.elepen) or 0
	if pen > 0 then
		return M.penetrate(value, resistance(creature, ctype), pen)
	end
	return value
end

-- shocked monsters: id -> until (ms)
local shocked = {}
local shockedCount = 0
local function shock(creature)
	shocked[creature:getId()] = now() + M.config.ailment.shockMs
	shockedCount = shockedCount + 1
	if shockedCount > 500 then
		shockedCount = 0
		local t = now()
		for id, untilMs in pairs(shocked) do
			if untilMs < t then
				shocked[id] = nil
			end
		end
	end
	creature:getPosition():sendMagicEffect(CONST_ME_ENERGYHIT or CONST_ME_ENERGYAREA or 12)
end
M.shocked = shocked

local function isShocked(creature)
	local untilMs = shocked[creature:getId()]
	if untilMs and untilMs >= now() then
		return true
	end
	shocked[creature:getId()] = nil
	return false
end

local DOTS = {
	bleedchance = {cond = "CONDITION_BLEEDING", effect = "CONST_ME_DRAWBLOOD"},
	ignitechance = {cond = "CONDITION_FIRE", effect = "CONST_ME_HITBYFIRE"},
	poisonchance = {cond = "CONDITION_POISON", effect = "CONST_ME_HITBYPOISON"}
}

local function addDot(target, player, key, hit)
	local d = DOTS[key]
	local ctype = _G[d.cond]
	if not ctype or not Condition then
		return
	end
	local a = M.config.ailment
	local c = Condition(ctype)
	c:setParameter(CONDITION_PARAM_OWNER, player:getId())
	c:setParameter(CONDITION_PARAM_DELAYED, true)
	c:addDamage(a.rounds, a.interval, -M.ailmentTick(hit))
	target:addCondition(c)
	if _G[d.effect] then
		target:getPosition():sendMagicEffect(_G[d.effect])
	end
end

local function chill(target)
	if not CONDITION_PARALYZE or not Condition then
		return
	end
	local a = M.config.ailment
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, a.chillMs)
	c:setFormula(-a.chillSlow / 100, 0, -a.chillSlow / 100, 0)
	target:addCondition(c)
	target:getPosition():sendMagicEffect(CONST_ME_ICEATTACK or CONST_ME_ICEAREA or 43)
end

local function roll(pct)
	return pct > 0 and math.random(1, 100) <= pct
end

-- after a hit of yours landed: health / mana on hit and the ailment rolls
local function onHit(creature, player, totals, hit)
	if (totals.lifeonhit or 0) > 0 then
		heal(player, totals.lifeonhit)
	end
	if (totals.manaonhit or 0) > 0 then
		player:addMana(totals.manaonhit)
	end
	if not creature:isMonster() then
		return -- ailments only on monsters
	end
	for key in pairs(DOTS) do
		if roll(totals[key] or 0) then
			addDot(creature, player, key, hit)
		end
	end
	if roll(totals.chillchance or 0) then
		chill(creature)
	end
	if roll(totals.shockchance or 0) then
		shock(creature)
	end
end

-- the keys that need the hit event on the target (any of them > 0)
local OFFENCE = {"bossdamage", "physpen", "elepen", "execute", "dot", "lifeonhit", "manaonhit", "bleedchance",
	"ignitechance", "poisonchance", "chillchance", "shockchance"}
local function offensive(totals)
	if not totals then
		return false
	end
	for _, k in ipairs(OFFENCE) do
		if (totals[k] or 0) > 0 then
			return true
		end
	end
	return ChaosVeiled ~= nil and ChaosVeiled.offensive(totals) -- the veiled damage hooks
end

-- your hits on a monster (and shocked monsters' hits from anyone)
local dealt = CreatureEvent("ChaosItemModsDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if guard or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local totals = p and cache[p:getId()]
	if totals then
		primaryDamage = penetrate(creature, primaryDamage, primaryType, totals)
		secondaryDamage = penetrate(creature, secondaryDamage, secondaryType, totals)
		local pct = totals.bossdamage or 0
		if pct > 0 and isElite(creature) then
			primaryDamage = M.scale(primaryDamage, pct)
			secondaryDamage = M.scale(secondaryDamage, pct)
		end
		if origin == ORIGIN_CONDITION and (totals.dot or 0) > 0 then
			primaryDamage = M.scale(primaryDamage, totals.dot)
			secondaryDamage = M.scale(secondaryDamage, totals.dot)
		end
		-- veiled hooks (chaos_veiled.lua): Veilpiercer on healthy monsters, Last Ember while you are low
		local vp = ChaosVeiled and creature:isMonster() and ChaosVeiled.dealtPct(totals, {targetHp = creature:getHealth(),
			targetMax = creature:getMaxHealth(), ownHp = p:getHealth(), ownMax = p:getMaxHealth()}) or 0
		if vp > 0 then
			primaryDamage = M.scale(primaryDamage, vp)
			secondaryDamage = M.scale(secondaryDamage, vp)
		end
	end
	if p and creature:isMonster() and isShocked(creature) then
		local s = M.config.ailment.shockPct
		primaryDamage = M.scale(primaryDamage, s)
		secondaryDamage = M.scale(secondaryDamage, s)
	end
	if totals and creature:isMonster() then
		local hit = math.abs(primaryDamage) + math.abs(secondaryDamage)
		if (totals.execute or 0) > 0 and M.executes(creature:getHealth(), creature:getMaxHealth(), hit, totals.execute)
				and not executeProof(creature) then
			primaryDamage = creature:getHealth()
			creature:getPosition():sendMagicEffect(CONST_ME_MORTAREA or 18)
		end
		if hit > 0 and origin ~= ORIGIN_CONDITION and p == attacker then
			onHit(creature, p, totals, hit)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and target:isMonster() then
		local p = playerOf(creature)
		if p and offensive(cache[p:getId()]) then
			target:registerEvent("ChaosItemModsDealt")
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- hits taken (dodge, block, damage from monsters, reflect, thorns) and heals received (the healer's Healing Done)
local taken = CreatureEvent("ChaosItemModsTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if guard then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if primaryType == COMBAT_HEALING then
		local healer = playerOf(attacker)
		local pct = healer and M.playerBonus(healer, "healing") or 0
		if pct > 0 then
			primaryDamage = M.scale(primaryDamage, pct)
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if not attacker or attacker == creature then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local totals = cache[creature:getId()]
	if not totals then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if (totals.dodge or 0) > 0 and math.random(1, 100) <= totals.dodge then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		if M.onAvoid then
			M.onAvoid(creature, attacker, "dodge", math.abs(primaryDamage) + math.abs(secondaryDamage)) -- Glacial Ward (item_powers.lua), sets
		end
		return 0, primaryType, 0, secondaryType
	end
	-- block: physical hits of a weapon or a claw (melee and ranged attacks), all of it
	if (totals.block or 0) > 0 and primaryType == COMBAT_PHYSICALDAMAGE
			and (origin == ORIGIN_MELEE or origin == ORIGIN_RANGED) and math.random(1, 100) <= totals.block then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
		if M.onAvoid then
			M.onAvoid(creature, attacker, "block", math.abs(primaryDamage) + math.abs(secondaryDamage))
		end
		return 0, primaryType, 0, secondaryType
	end
	if (totals.monsterreduction or 0) > 0 and attacker:isMonster() then
		primaryDamage = M.scale(primaryDamage, -totals.monsterreduction)
		secondaryDamage = M.scale(secondaryDamage, -totals.monsterreduction)
	end
	-- veiled hooks (chaos_veiled.lua): Gravebound while low, Hexbreaker against bosses, Ashen Ward against elements
	if ChaosVeiled then
		local mt = attacker:isMonster() and attacker:getType()
		local okB, boss = pcall(function() return mt and mt:isBoss() end)
		local vr = ChaosVeiled.takenPct(totals, {hp = creature:getHealth(), maxHp = creature:getMaxHealth(),
			monster = attacker:isMonster(), boss = okB and boss == true, elemental = primaryType ~= COMBAT_PHYSICALDAMAGE
			and not NOT_ELEMENTAL[primaryType]})
		if vr > 0 then
			primaryDamage = M.scale(primaryDamage, -vr)
			secondaryDamage = M.scale(secondaryDamage, -vr)
		end
	end
	local attackerId = attacker:getId()
	local back = 0
	if (totals.reflect or 0) > 0 then
		local landed = math.min(math.abs(primaryDamage) + math.abs(secondaryDamage), creature:getHealth()
			+ (creature.getEnergyShield and creature:getEnergyShield() or 0)) -- a hit on the energy shield counts
		back = back + M.reflected(landed, totals.reflect)
	end
	if (totals.thorns or 0) > 0 and origin == ORIGIN_MELEE then
		back = back + totals.thorns
	end
	if back > 0 then
		guard = true
		doTargetCombatHealth(creature:getId(), attackerId, COMBAT_PHYSICALDAMAGE, -back, -back, CONST_ME_NONE)
		guard = false
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- ---------------------------------------------------------------- kills
local killed = {} -- monster id -> true (onKill may run for more than one killer)
local kill = CreatureEvent("ChaosItemModsKill")
function kill.onKill(player, target)
	if not target or not target:isMonster() or target:getMaster() then
		return true
	end
	local totals = cache[player:getId()]
	if not totals then
		return true
	end
	local key = player:getId() .. ":" .. target:getId()
	if killed[key] then
		return true
	end
	killed[key] = true
	addEvent(function() killed[key] = nil end, 2000)
	if (totals.lifeonkill or 0) > 0 then
		heal(player, totals.lifeonkill)
	end
	if (totals.manaonkill or 0) > 0 then
		player:addMana(totals.manaonkill)
	end
	if ChaosVeiled and ((totals.veil_bloodharvest or 0) > 0 or (totals.veil_soulharvest or 0) > 0) then -- chaos_veiled.lua
		local h, mp = ChaosVeiled.killRestore(totals, player:getMaxHealth(), player:getMaxMana())
		if h > 0 then
			heal(player, h)
		end
		if mp > 0 then
			player:addMana(mp)
		end
	end
	return true
end
kill:register()

-- ---------------------------------------------------------------- experience and gold
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	local pct = M.playerBonus(self, "experience")
	if pct > 0 and source then
		return M.experience(exp, pct)
	end
	return exp
end
xpCb:register(1)

local COINS = {{2160, 10000}, {2152, 100}, {2148, 1}} -- crystal, platinum, gold coin
local goldCb = EventCallback
goldCb.onDropLoot = function(self, corpse)
	local owner = corpse and Player(corpse:getCorpseOwner())
	local pct = owner and M.playerBonus(owner, "goldfind") or 0
	if pct <= 0 then
		return
	end
	local value = 0
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item then
			for _, coin in ipairs(COINS) do
				if item:getId() == coin[1] then
					value = value + item:getCount() * coin[2]
				end
			end
		end
	end
	local exact = value * pct / 100
	local extra = math.floor(exact)
	if math.random() < exact - extra then
		extra = extra + 1
	end
	for _, coin in ipairs(COINS) do
		local n = math.floor(extra / coin[2])
		extra = extra - n * coin[2]
		while n > 0 do
			local stack = math.min(n, 100)
			corpse:addItem(coin[1], stack)
			n = n - stack
		end
	end
end
-- after the stock loot (0) and the Chaos loot layer (1), before autoloot (3), so autoloot picks the extra coins up
goldCb:register(2)

-- ---------------------------------------------------------------- drops
-- The engine rolls the rarity of a corpse's items in Monster::dropLoot AFTER every Lua onDropLoot callback. loot.lua
-- forges every gear drop with a rarity itself (ChaosCrafting.forgeDrop: item level, tiers, prefixes and suffixes) and
-- keeps the rarity as text meanwhile, which the engine's pass skips (ChaosCrafting.shield). Right after the engine is
-- done, this gives those rarities back as numbers (and sends the items again, so open corpses show the frames).
local PENDING = "chaos_mods_pending"
function M.afterDrop(corpse)
	local ok = pcall(function() corpse:setCustomAttribute(PENDING, 1) end)
	if ok then
		local pos = corpse:getPosition()
		addEvent(M.fixCorpses, 0, {x = pos.x, y = pos.y, z = pos.z})
	end
end

function M.fixCorpses(pos)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	for _, corpse in ipairs(tile and tile:getItems() or {}) do
		if corpse:isContainer() and corpse:getCustomAttribute(PENDING) then
			corpse:removeCustomAttribute(PENDING)
			for _, item in ipairs(corpse:getItems(true)) do
				if ChaosCrafting.unshield(item) then
					M.sendUpdate(item)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- login / level / logout
local login = CreatureEvent("ChaosItemModsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosItemModsTaken")
	player:registerEvent("ChaosItemModsKill")
	player:registerEvent("ChaosItemModsAdvance")
	player:registerEvent("ChaosItemModsLogout")
	M.refresh(player, true)
	return true
end
login:register()

-- the movement speed share follows the base speed, which grows with every level
local advance = CreatureEvent("ChaosItemModsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and applied[player:getId()] then
		applySpeed(player, applied[player:getId()], cache[player:getId()] or {})
	end
	return true
end
advance:register()

local logout = CreatureEvent("ChaosItemModsLogout")
function logout.onLogout(player)
	applied[player:getId()] = nil
	cache[player:getId()] = nil
	if ChaosGems and ChaosGems.forget then
		ChaosGems.forget(player)
	end
	return true
end
logout:register()
