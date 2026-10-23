-- Waystone modifiers (server/README.md "Waystone modifiers"): the maps of Path of Exile. A waystone is Normal, Magic or
-- Rare by its modifiers (custom attribute "ws_mods"); prefixes make the map's monsters stronger, suffixes make it worse
-- for the players, every modifier adds item quantity, item rarity, experience and waystone drop chance. Numbers:
-- waystone_mods_config.lua; pure logic: waystone_mods_core.lua (tests/waystone_mods_test.lua). The modifiers are the
-- rift keys' and do what they do in a rift (rift_core.lua R.effects, R.monsterHit, R.monsterTaken).
--
-- * Items: WM.read / WM.write (name "Rare Waystone Tier IV", the look text lists the modifiers and rewards). A waystone
--   with modifiers is one item: a crafted one comes off its stack first (WM.single).
-- * Crafting: data/lib/chaos_crafting.lua sends the orbs on a waystone to waystone_mods_core.lua W.orbApply.
-- * Runs: tools/patch_waystone_hideout.py part 4: the device takes the waystone that was used (else the one of that
--   tier with the fewest modifiers: WM.take) and waystone_tiers.lua WT.startRun calls WM.begin with its modifiers: the
--   map's run carries them until the next waystone opens it or runSeconds pass.
-- * Monsters of the map (waystone_tiers.lua calls WM.applyMonster after its level rescale): Vitality / Dread health,
--   Haste speed, Elites (a magic or rare roll), the damage they deal (Brutality, Dread, Keen Fangs, the brands, the
--   hexes, Festering Wounds) and take (Warding, Ironhide, Sapping Hex, Reflection, Spiteglass), Cinderdeath and
--   Veilbreach at their death.
-- * Players in the map: Withering / Parched Veins (no regeneration), Blighted Mending (less healing), Scorched Earth /
--   Rimefloor (burning or freezing ground), Veilstorm (marked strikes): a tick every tickMs while a run has players.
-- * Rewards: loot_config.lua rateMult x WM.lootMult (quantity), loot.lua rarity find + WM.rarityFind, waystone_tiers.lua
--   experience x WM.expMult and its drops (WM.extraWaystone, WM.rollDrop).
-- Assumed engine API (TFS 1.4.2): CreatureEvent healthchange / manachange / death / login, Item custom attributes,
-- Game.getSpectators, Game.createMonster, doTargetCombatHealth, Condition.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/waystone_mods_core.lua")
if not ChaosWaystoneTiersCore then
	dofile("data/scripts/chaos/waystone_tiers_core.lua")
end

ChaosWaystoneMods = ChaosWaystoneMods or {}
local WM = ChaosWaystoneMods
local W = ChaosWaystoneModsCore
local R = ChaosRiftCore
local K = ChaosWaystoneTiersCore
WM.config = dofile("data/scripts/chaos/waystone_mods_config.lua")
WM.runs = WM.runs or {} -- map index -> {tier, mods, fx, bonus, untilAt, players = {id = entry}}
WM.mon = WM.mon or {} -- monster id -> {map, hp = health mult applied, speed = speed added, boss, extra}

local function C()
	return WM.config
end

local function tiersCfg()
	return ChaosWaystoneTiers and ChaosWaystoneTiers.config or dofile("data/scripts/chaos/waystone_tiers_config.lua")
end

local function rand(a, b)
	return math.random(a, b)
end

-- ======================================================================== items
function WM.tierOf(item)
	if not item then
		return nil
	end
	local ok, id = pcall(function() return item:getId() end)
	return ok and K.tierOfItem(tiersCfg(), id) or nil
end

function WM.isWaystone(item)
	return WM.tierOf(item) ~= nil
end

function WM.read(item)
	local t = WM.tierOf(item)
	if not t then
		return nil
	end
	local ok, text = pcall(function() return item:getCustomAttribute(C().attribute) end)
	return {tier = t, mods = W.decode(C(), ok and text or "")}
end

function WM.write(item, ws)
	local cfg = C()
	if #ws.mods == 0 then
		pcall(function() item:removeCustomAttribute(cfg.attribute) end)
		pcall(function() item:removeAttribute(ITEM_ATTRIBUTE_NAME) end)
		pcall(function() item:removeAttribute(ITEM_ATTRIBUTE_DESCRIPTION) end)
		return item
	end
	item:setCustomAttribute(cfg.attribute, W.encode(ws.mods))
	item:setAttribute(ITEM_ATTRIBUTE_NAME, W.itemName(cfg, ws))
	if ITEM_ATTRIBUTE_ARTICLE then
		item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "a")
	end
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, W.describe(cfg, ws, K.tierLevel(tiersCfg(), ws.tier)))
	return item
end

-- a waystone of a stack of several comes off it as one item (in the same container, else with the player); returns it
function WM.single(item, player)
	local ok, count = pcall(function() return item:getCount() end)
	if not ok or (tonumber(count) or 1) <= 1 then
		return item
	end
	local one = Game.createItem(item:getId(), 1)
	if not one then
		return item
	end
	local parent = item:getParent()
	item:remove(1)
	local added = false
	if parent and parent.isContainer and parent:isContainer() then
		added = parent:addItemEx(one) == (RETURNVALUE_NOERROR or 0)
	end
	if not added and player then
		added = player:addItemEx(one, true) == (RETURNVALUE_NOERROR or 0)
	end
	if not added then
		local pos = player and player:getPosition() or item:getPosition()
		one:moveTo(pos)
	end
	return one
end

-- every waystone of server id `sid` the player carries (equipment and containers, nested)
local function carried(player, sid)
	local out = {}
	local function walk(c, depth)
		if depth > 8 then
			return
		end
		for _, it in ipairs(c:getItems(false) or {}) do
			if it:getId() == sid then
				out[#out + 1] = it
			end
			if it:isContainer() then
				walk(it, depth + 1)
			end
		end
	end
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local it = player:getSlotItem(slot)
		if it then
			if it:getId() == sid then
				out[#out + 1] = it
			end
			if it:isContainer() then
				walk(it, 1)
			end
		end
	end
	return out
end

local function heldBy(player, item)
	local ok, top = pcall(function() return item:getTopParent() end)
	return ok and top and top.isPlayer and top:isPlayer() and top:getId() == player:getId()
end

WM.chosen = WM.chosen or {} -- player guid -> {item, at}: the waystone used on the device (patch part 4)

-- tier_maps.lua (patch part 4): the player used this waystone to open the device's window
function WM.choose(player, item)
	WM.chosen[player:getGuid()] = {item = item, at = os.time()}
end

-- the tier_maps.lua device takes one waystone of server id `sid` (patch part 4): the one the player used if it is still
-- carried, else the carried one with the fewest modifiers. Returns true and its modifiers, or false (none carried).
function WM.take(player, sid)
	local guid = player:getGuid()
	local chosen = WM.chosen[guid]
	WM.chosen[guid] = nil
	local pick
	if chosen and os.time() - (chosen.at or 0) <= (C().chosenSeconds or 300) then
		local item = chosen.item
		local ok, same = pcall(function() return item:getId() == sid end)
		if ok and same and heldBy(player, item) then
			pick = item
		end
	end
	if not pick then
		local best
		for _, it in ipairs(carried(player, sid)) do
			local n = #(WM.read(it) or {mods = {}}).mods
			if not best or n < best then
				pick, best = it, n
			end
		end
	end
	if not pick then
		return false, {}
	end
	local ws = WM.read(pick) or {mods = {}}
	if not pick:remove(1) then
		return false, {}
	end
	ws.mods.opener = guid -- the map's opener (waystone_atlas.lua: their atlas shapes the run)
	return true, ws.mods
end

-- ======================================================================== runs
local function mapCentre(m)
	local cx, cy = math.floor((m.from.x + m.to.x) / 2), math.floor((m.from.y + m.to.y) / 2)
	local hx, hy = math.ceil(math.abs(m.to.x - m.from.x) / 2), math.ceil(math.abs(m.to.y - m.from.y) / 2)
	return Position(cx, cy, m.from.z), hx, hy
end

local function liveRun(i)
	local run = i and WM.runs[i]
	if run and run.untilAt <= os.time() then
		WM.finish(i)
		return nil
	end
	return run
end
WM.runOf = liveRun

function WM.runAt(pos)
	local i = K.mapAt(tiersCfg(), pos)
	return liveRun(i), i
end

local ticking = false
local tick

-- a waystone opened map i at tier t with these modifiers (waystone_tiers.lua WT.startRun); a run without modifiers
-- clears the map's old ones
function WM.begin(i, t, mods)
	if WM.runs[i] then
		WM.finish(i)
	end
	mods = mods or {}
	if #mods == 0 or C().enabled == false then
		return nil
	end
	local cfg = C()
	local run = {map = i, tier = t, mods = mods, fx = W.effects(cfg, mods, t), bonus = W.bonuses(cfg, mods, t),
		untilAt = os.time() + (cfg.runSeconds or 1860), players = {}, hazards = {}, breachAlive = 0}
	-- the opener's Waystone Atlas (waystone_atlas.lua, begun before this): x its modifier reward bonus
	local am = ChaosWaystoneAtlas and ChaosWaystoneAtlas.fxOfMap and ChaosWaystoneAtlas.fxOfMap(i)
	local mult = am and tonumber(am.modRewardMult) or 1
	if mult ~= 1 then
		for _, k in ipairs({"quantity", "rarity", "experience", "waystone"}) do
			run.bonus[k] = math.floor((run.bonus[k] or 0) * mult + 0.5)
		end
	end
	WM.runs[i] = run
	if not ticking then
		ticking = true
		addEvent(tick, cfg.tickMs or 1000)
	end
	return run
end

local unwither

function WM.finish(i)
	local run = WM.runs[i]
	if not run then
		return
	end
	WM.runs[i] = nil
	for id, entry in pairs(run.players) do
		local p = Player(id)
		if p then
			unwither(p, entry)
		end
	end
end

-- the run a classified waystone monster's map carries (waystone_tiers.lua entry), or nil
function WM.runOfEntry(e)
	return e and liveRun(e.map) or nil
end

-- ======================================================================== monsters
-- after waystone_tiers.lua set the level: the run's health (Vitality, Dread for the boss) and speed (Haste); `first`:
-- the monster's first think (Elites may make it magic or rare). Monsters of a map without modifiers lose earlier ones.
function WM.applyMonster(monster, e, first)
	if not e then
		return
	end
	local id = monster:getId()
	local run = WM.runOfEntry(e)
	local st = WM.mon[id] or {map = e and e.map, hp = 1, speed = 0, boss = e and e.boss}
	local wantHp = run and run.fx.health * (e.boss and run.fx.boss or 1) or 1
	local wantSpeed = run and run.fx.speed or 0
	if wantHp ~= st.hp then
		local max = monster:getMaxHealth()
		local hp = math.max(1, math.floor(max * wantHp / st.hp + 0.5))
		local now = monster:getHealth()
		monster:setMaxHealth(hp)
		monster:setHealth(math.max(1, math.floor(now * hp / max + 0.5)))
		st.hp = wantHp
	end
	if wantSpeed ~= st.speed then
		monster:changeSpeed(wantSpeed - st.speed)
		st.speed = wantSpeed
	end
	if run and first and not e.boss and ChaosApplyTier then
		-- every run has magic and rare monsters (names and looks of the loot tiers), the Elites modifier adds more
		local c = math.min(100, W.eliteChance(C(), run.fx.elite) + (C().elites.runBase or 0))
		if c > 0 and math.random(10000) <= c * 100 then
			pcall(ChaosApplyTier, monster, math.random(100) <= (C().elites.rareShare or 30) and "rare" or "magic")
		end
	end
	if run and not WM.mon[id] then
		pcall(function()
			monster:registerEvent("ChaosWaystoneModsHealth")
			monster:registerEvent("ChaosWaystoneModsDeath")
		end)
	end
	if run or WM.mon[id] then
		WM.mon[id] = st
	end
end

local typesCache
local function hitTypes()
	if not typesCache then
		typesCache = {physical = COMBAT_PHYSICALDAMAGE, none = COMBAT_NONE,
			brand = {fire = COMBAT_FIREDAMAGE, ice = COMBAT_ICEDAMAGE, energy = COMBAT_ENERGYDAMAGE}}
	end
	return typesCache
end

local function combatOf(element)
	return ({fire = COMBAT_FIREDAMAGE, ice = COMBAT_ICEDAMAGE, energy = COMBAT_ENERGYDAMAGE, earth = COMBAT_EARTHDAMAGE,
		death = COMBAT_DEATHDAMAGE})[element] or COMBAT_PHYSICALDAMAGE
end

local function effectOf(element)
	return ({fire = CONST_ME_FIREAREA, ice = CONST_ME_ICEAREA, energy = CONST_ME_ENERGYAREA,
		death = CONST_ME_MORTAREA})[element] or CONST_ME_POFF
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local m = creature:getMaster()
	return m and m:isPlayer() and m or nil
end

local function runOfMonsterId(id)
	local st = WM.mon[id]
	return st and liveRun(st.map) or nil, st
end

-- damage a map monster takes: Warding, Ironhide, Sapping Hex, Reflection, Spiteglass (as rift.lua)
local reflecting = false
function WM.monsterTaken(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local run = runOfMonsterId(creature:getId())
	if not run or not attacker or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local fx = run.fx
	local p = playerOf(attacker)
	local elemental
	primaryDamage, secondaryDamage, elemental = R.monsterTaken(fx, {primary = primaryDamage, ptype = primaryType,
		secondary = secondaryDamage, stype = secondaryType, fromPlayer = p ~= nil}, hitTypes())
	if p and not reflecting then
		local health = creature:getHealth()
		local landed = math.min(math.abs(primaryDamage) + math.abs(secondaryDamage), health)
		local amount = math.floor(landed * (fx.reflect or 0) + math.min(elemental, health) * (fx.spite or 0))
		if amount > 0 then
			reflecting = true
			doTargetCombatHealth(creature:getId(), p, (fx.spite or 0) > 0 and COMBAT_ENERGYDAMAGE or COMBAT_PHYSICALDAMAGE,
				-amount, -amount, CONST_ME_NONE)
			reflecting = false
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

-- damage a player takes from a map monster: Brutality, Dread (the boss), Keen Fangs, brands, hexes, Festering Wounds
function WM.playerHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	if reflecting or not attacker or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local run, st = runOfMonsterId(attacker:getId())
	if not run then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local info
	primaryDamage, primaryType, secondaryDamage, secondaryType, info = W.hit(C(), run.fx,
		{primary = primaryDamage, ptype = primaryType, secondary = secondaryDamage, stype = secondaryType,
			boss = st.boss and true or false}, hitTypes(), rand)
	if info.crit then
		creature:getPosition():sendMagicEffect(CONST_ME_DRAWBLOOD or CONST_ME_HITAREA)
	end
	if info.fester and CONDITION_POISON and Condition then
		local f = C().festering
		local c = Condition(CONDITION_POISON)
		c:setParameter(CONDITION_PARAM_DELAYED, true)
		c:addDamage(f.rounds, f.intervalMs, -math.max(1, math.floor(info.fester / f.rounds)))
		creature:addCondition(c)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

-- Blighted Mending: a heal of a player in a run's map with it
function WM.healMult(player)
	local run = WM.runAt(player:getPosition())
	return run and run.fx.healMult or 1
end

local function cinder(run, pos, maxHealth)
	local cfg = C()
	local dmg = W.cinderDamage(cfg, maxHealth, run.fx.cinder, run.tier)
	if dmg <= 0 then
		return
	end
	pos:sendMagicEffect(CONST_ME_HITBYFIRE)
	addEvent(function(p, amount)
		local at = Position(p.x, p.y, p.z)
		at:sendMagicEffect(CONST_ME_FIREAREA)
		local rad = cfg.cinder.radius
		for _, pl in ipairs(Game.getSpectators(at, false, true, rad, rad, rad, rad)) do
			doTargetCombatHealth(0, pl, COMBAT_FIREDAMAGE, -amount, -amount, CONST_ME_FIREAREA)
		end
	end, cfg.cinder.delayMs, {x = pos.x, y = pos.y, z = pos.z}, dmg)
end

-- Veilbreach: two more of the slain monster's kind (they cannot breach again; maxAlive a map)
local function breach(run, name, pos)
	local b = C().breach
	if run.breachAlive >= (b.maxAlive or 40) then
		return
	end
	pos:sendMagicEffect(CONST_ME_PURPLEENERGY or CONST_ME_TELEPORT)
	addEvent(function(p, i, n)
		local r = liveRun(i)
		if not r then
			return
		end
		for _ = 1, b.count do
			local at = Position(p.x + math.random(-b.spread, b.spread), p.y + math.random(-b.spread, b.spread), p.z)
			local m = Game.createMonster(n, at, true, false)
			if m then
				r.breachAlive = r.breachAlive + 1
				WM.breachIds = WM.breachIds or {}
				WM.breachIds[m:getId()] = i
			end
		end
	end, b.delayMs, {x = pos.x, y = pos.y, z = pos.z}, run.map, name)
end

function WM.onDeath(creature)
	local id = creature:getId()
	local run = runOfMonsterId(id)
	local wasBreach = WM.breachIds and WM.breachIds[id]
	WM.mon[id] = nil
	if wasBreach then
		WM.breachIds[id] = nil
		local r = WM.runs[wasBreach]
		if r then
			r.breachAlive = math.max(0, r.breachAlive - 1)
		end
	end
	if not run then
		return
	end
	local pos = creature:getPosition()
	if (run.fx.cinder or 0) > 0 then
		cinder(run, pos, creature:getMaxHealth())
	end
	if not wasBreach and (run.fx.breach or 0) > 0 and math.random(100) <= run.fx.breach then
		breach(run, creature:getName(), pos)
	end
end

-- ======================================================================== players (the tick)
-- Withering / Parched Veins: the regeneration condition swapped for one without health (or mana) gain (as rift.lua)
local function wither(player, entry, fx)
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if not cond then
		entry.withered = false
		return
	end
	if entry.withered then
		return
	end
	local ticks = cond:getTicks()
	player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	local voc = player:getVocation()
	local c = Condition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	c:setTicks(ticks)
	c:setParameter(CONDITION_PARAM_HEALTHGAIN, fx.noRegen and 0 or voc:getHealthGainAmount())
	c:setParameter(CONDITION_PARAM_HEALTHTICKS, fx.noRegen and 60000 or voc:getHealthGainTicks() * 1000)
	c:setParameter(CONDITION_PARAM_MANAGAIN, fx.noMana and 0 or voc:getManaGainAmount())
	c:setParameter(CONDITION_PARAM_MANATICKS, fx.noMana and 60000 or voc:getManaGainTicks() * 1000)
	player:addCondition(c)
	entry.withered = true
end

function unwither(player, entry)
	if not entry.withered then
		return
	end
	entry.withered = false
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if cond then
		local seconds = math.floor(cond:getTicks() / 1000)
		player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
		if seconds > 0 then
			player:feed(seconds)
		end
	end
end

local function percentHit(p, share, element)
	local base = Chaos.percentBase and Chaos.percentBase(p) or p:getMaxHealth()
	local amount = R.percentHit(base, share)
	doTargetCombatHealth(0, p, combatOf(element), -amount, -amount, effectOf(element))
end

local function groundTick(run, players, now)
	local cfg = C()
	local g = run.fx.ground
	if now >= (run.groundAt or 0) then
		run.groundAt = now + cfg.ground.every
		for _, p in ipairs(players) do
			for _, t in ipairs(R.plus(R.nearTile(p:getPosition(), cfg.ground.near, rand))) do
				local tile = Tile(Position(t.x, t.y, t.z))
				if tile and tile:getGround() and not tile:hasFlag(TILESTATE_PROTECTIONZONE or 0) then
					run.hazards[t.x .. "," .. t.y .. "," .. t.z] = {x = t.x, y = t.y, z = t.z,
						untilAt = now + cfg.ground.lastSeconds}
				end
			end
		end
	end
	local eff = effectOf(g.element)
	for k, h in pairs(run.hazards) do
		if h.untilAt <= now then
			run.hazards[k] = nil
		else
			Position(h.x, h.y, h.z):sendMagicEffect(eff)
		end
	end
	for _, p in ipairs(players) do
		local at = p:getPosition()
		if run.hazards[at.x .. "," .. at.y .. "," .. at.z] then
			percentHit(p, g.percent / 100, g.element)
			if g.kind == "rimefloor" and CONDITION_PARALYZE then
				local c = Condition(CONDITION_PARALYZE)
				c:setParameter(CONDITION_PARAM_TICKS, cfg.ground.slowMs)
				c:setFormula(-cfg.ground.slowPercent / 100, 0, -cfg.ground.slowPercent / 100, 0)
				p:addCondition(c)
			end
		end
	end
end

local function stormTick(run, players, now)
	local s = C().veilstorm
	if now < (run.stormAt or 0) then
		return
	end
	run.stormAt = now + s.every
	for _, p in ipairs(players) do
		local at = R.nearTile(p:getPosition(), s.near, rand)
		for dx = -s.radius, s.radius do
			for dy = -s.radius, s.radius do
				Position(at.x + dx, at.y + dy, at.z):sendMagicEffect(CONST_ME_PURPLEENERGY or CONST_ME_POFF)
			end
		end
		addEvent(function(p0, i)
			local r = liveRun(i)
			if not r then
				return
			end
			local c = Position(p0.x, p0.y, p0.z)
			c:sendMagicEffect(CONST_ME_ENERGYAREA)
			for _, pl in ipairs(Game.getSpectators(c, false, true, s.radius, s.radius, s.radius, s.radius)) do
				percentHit(pl, r.fx.storm, "energy")
			end
		end, s.warnMs, {x = at.x, y = at.y, z = at.z}, run.map)
	end
end

function tick()
	local any = false
	local now = os.time()
	local cfgT = tiersCfg()
	for i in pairs(WM.runs) do
		local run = liveRun(i)
		if run then
			any = true
			local centre, hx, hy = mapCentre(cfgT.maps[i])
			local players, seen = {}, {}
			local okS, specs = pcall(Game.getSpectators, centre, false, true, hx, hx, hy, hy)
			for _, p in ipairs(okS and specs or {}) do
				if K.mapAt(cfgT, p:getPosition()) == i then
					players[#players + 1] = p
					seen[p:getId()] = true
					local entry = run.players[p:getId()] or {}
					run.players[p:getId()] = entry
					if run.fx.noRegen or run.fx.noMana then
						wither(p, entry, run.fx)
					end
				end
			end
			for id, entry in pairs(run.players) do
				if not seen[id] then
					local p = Player(id)
					if p then
						unwither(p, entry)
					end
					run.players[id] = nil
				end
			end
			if #players > 0 then
				if run.fx.ground then
					pcall(groundTick, run, players, now)
				end
				if (run.fx.storm or 0) > 0 then
					pcall(stormTick, run, players, now)
				end
			end
		end
	end
	if any then
		addEvent(tick, C().tickMs or 1000)
	else
		ticking = false
	end
end

-- ======================================================================== rewards
local function runOfMonster(monster)
	if not monster then
		return nil
	end
	local run = runOfMonsterId(monster:getId())
	if run then
		return run
	end
	local ok, pos = pcall(function() return monster:getPosition() end)
	return ok and WM.runAt(pos) or nil
end
WM.runOfMonster = runOfMonster

-- the map opener's Waystone Atlas where the monster died (waystone_atlas.lua): one stat, 0 without
local function atlas(monster, key)
	local WA = ChaosWaystoneAtlas
	if not (WA and WA.stat and monster) then
		return 0
	end
	local ok, v = pcall(WA.stat, monster, key)
	return ok and tonumber(v) or 0
end

-- loot_config.lua rateMult: the quantity bonus of the run the corpse's monster died in, x the atlas's
function WM.lootMult(ctx)
	local monster = ctx and ctx.monster
	local run = monster and runOfMonster(monster)
	local m = run and (1 + (run.bonus.quantity or 0) / 100) or 1
	-- the run tier's own bonus (content_rewards_config.lua waystone.quantity)
	local CR = ChaosContentRewards
	local own = run and CR and CR.waystoneQuantity and CR.waystoneQuantity(monster) or 1
	return m * own * math.max(0, 1 + atlas(monster, "quantity") / 100)
end

-- loot.lua: rarity find (percent) of the run the monster died in, + the atlas's
function WM.rarityFind(monster)
	local run = runOfMonster(monster)
	local CR = ChaosContentRewards
	local own = run and CR and CR.waystoneRarityFind and CR.waystoneRarityFind(monster) or 0
	return (run and run.bonus.rarity or 0) + own + atlas(monster, "rarity")
end

-- waystone_tiers.lua: experience x this for a kill in the run's map (x the atlas's)
function WM.expMult(monster)
	local run = runOfMonster(monster)
	return (run and (1 + (run.bonus.experience or 0) / 100) or 1) * (1 + atlas(monster, "experience") / 100)
end

-- waystone_tiers.lua retierDrops: true when a dropped waystone brings one more (the waystone bonus as a chance, + the
-- atlas's)
function WM.extraWaystone(monster)
	local run = runOfMonster(monster)
	local c = (run and run.bonus.waystone or 0) + atlas(monster, "waystone")
	return c > 0 and math.random(100) <= c
end

-- a waystone that dropped in a run's map (tier t) gets its rarity and modifiers (dropRarity, the Normal share cut by
-- the atlas's `rarer`); outside: Normal
function WM.rollDrop(item, t, inside, monster)
	if not inside or C().enabled == false then
		return item
	end
	local cfg = C()
	local rarer = atlas(monster, "rarer")
	if rarer > 0 and ChaosWaystoneAtlasCore then
		cfg = setmetatable({dropRarity = ChaosWaystoneAtlasCore.dropRows(cfg.dropRarity, rarer)}, {__index = cfg})
	end
	local ws = W.rollDrop(cfg, t, rand)
	if #ws.mods > 0 then
		WM.write(item, ws)
	end
	return item
end

-- ======================================================================== events
if CreatureEvent then
	local mh = CreatureEvent("ChaosWaystoneModsHealth")
	function mh.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
		return WM.monsterTaken(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	end
	mh:type("healthchange")
	mh:register()

	local md = CreatureEvent("ChaosWaystoneModsDeath")
	function md.onDeath(creature)
		pcall(WM.onDeath, creature)
		return true
	end
	md:type("death")
	md:register()

	local ph = CreatureEvent("ChaosWaystoneModsPlayerHit")
	function ph.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
		if primaryType == COMBAT_HEALING then
			if next(WM.runs) then
				local mult = WM.healMult(creature)
				if mult < 1 then
					primaryDamage = math.floor(primaryDamage * mult)
				end
			end
			return primaryDamage, primaryType, secondaryDamage, secondaryType
		end
		return WM.playerHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	end
	ph:type("healthchange")
	ph:register()

	local pm = CreatureEvent("ChaosWaystoneModsPlayerMana")
	function pm.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
		return WM.playerHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	end
	pm:type("manachange")
	pm:register()

	local login = CreatureEvent("ChaosWaystoneModsLogin")
	function login.onLogin(player)
		player:registerEvent("ChaosWaystoneModsPlayerHit")
		player:registerEvent("ChaosWaystoneModsPlayerMana")
		return true
	end
	login:type("login")
	login:register()

	local logout = CreatureEvent("ChaosWaystoneModsLogout")
	function logout.onLogout(player)
		WM.chosen[player:getGuid()] = nil
		for _, run in pairs(WM.runs) do
			local entry = run.players[player:getId()]
			if entry then
				unwither(player, entry)
				run.players[player:getId()] = nil
			end
		end
		return true
	end
	logout:type("logout")
	logout:register()
end
