-- Pack combat ("pace"): monsters with less health in bigger packs, experience and loot per kill cut by the kill ratio,
-- a multikill bonus. server/README.md "Pack combat (pace)". Numbers: pace_config.lua; pure logic: pace_core.lua
-- (tests: server/tests/pace_test.lua).
--
-- * Which monsters: natural map spawns (EventCallback onSpawn with artificial = false), generated area and dungeon
--   monsters (areagen.lua: ChaosAreaGen.pointOf, its boss never), and the monsters other scripts mark with
--   ChaosPace.mark(monster) (base dungeons, ambush copies of a paced monster). Never a boss (isboss / rewardboss / the
--   tier list), a summon, or a monster of the instanced modes (rifts, Descent, tower, invasions, arena, battleground,
--   raid, world and guild bosses): those are created from scripts and are not marked.
-- * Health: at the monster's first think (the engine gives it its id at the placement; generated areas scale their
--   monsters right after the creation), max health x the curve, full health. The monster tier (monster_tiers.lua, also
--   at the first think) multiplies on top, in either order.
-- * Experience: onGainExperience at index -10 (after the xpcap recorder at -1000, before every bonus): x the curve
--   with random rounding, then the multikill chain (pace_core.lua P.multikill). xpcap.lua multiplies its base by the
--   same curve.
-- * Loot (loot.lua), ambush (monster_tiers.lua), treasure goblins (treasure_goblin.lua), damage to players
--   (monster_damage.lua) and kill goals read the factors through ChaosPace.lootMultOf / damageMultOf / goalMultOf.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosPaceCore or not ChaosPaceCore.multikill then
	dofile("data/scripts/chaos/pace_core.lua")
end
ChaosPaceConfig = dofile("data/scripts/chaos/pace_config.lua")

ChaosPace = ChaosPace or {}
local PC = ChaosPace
local P = ChaosPaceCore

local function cfg()
	return ChaosPaceConfig
end

-- monster id -> {level =, scaled =, f = factors}; kept 10 s after the death for the loot callback and the experience
PC.paced = PC.paced or {}
local paced = PC.paced
-- player id -> multikill chain state; player id -> kill credit accumulators by counter
local chains, credits = {}, {}

local INIT, PROBE, DEATH, CLEAVE = "ChaosPaceInit", "ChaosPaceProbe", "ChaosPaceDeath", "ChaosPaceCleave"

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function typeName(m)
	return Chaos and Chaos.monsterTypeName and Chaos.monsterTypeName(m) or m:getName()
end

local function isBoss(m)
	local tc = ChaosTierConfig
	if tc and tc.bosses and tc.bosses[tostring(typeName(m)):lower()] then
		return true
	end
	local mt = m:getType()
	if not mt then
		return false
	end
	for _, fn in ipairs({"isBoss", "isRewardBoss"}) do
		local ok, res = pcall(function() return mt[fn] and mt[fn](mt) end)
		if ok and res then
			return true
		end
	end
	return false
end

-- the monster's hunting level and curve set (pace_core.lua P.levelOf)
function PC.levelOf(m)
	local id = m:getId()
	local point = ChaosAreaGen and ChaosAreaGen.pointOf and ChaosAreaGen.pointOf[id]
	local native = 0
	pcall(function() native = tonumber(m:getMonsterLevel()) or 0 end)
	local pool = 0
	if native <= 0 and not point and ChaosLoot and ChaosLoot.monsterLevel then
		local ok, lvl = pcall(ChaosLoot.monsterLevel, m)
		pool = ok and tonumber(lvl) or 0
	end
	return P.levelOf(cfg(), {point = point and point.level, native = native, pool = pool})
end

-- apply the layer to a monster now (full health). include: a map spawn or a marked monster; otherwise only a generated
-- area's point. Returns true when the monster is paced.
function PC.apply(m, include)
	local c = cfg()
	if not c or c.enabled == false or not m or not m:isMonster() then
		return false
	end
	local id = m:getId()
	if id == 0 or paced[id] then
		return paced[id] ~= nil
	end
	local point = ChaosAreaGen and ChaosAreaGen.pointOf and ChaosAreaGen.pointOf[id]
	if not include and not point then
		return false
	end
	if (point and point.boss) or m:getMaster() or isBoss(m) or (c.skip and c.skip[tostring(typeName(m)):lower()]) then
		return false
	end
	local level, scaled = PC.levelOf(m)
	if not level or level <= 0 then
		return false
	end
	local f = P.factors(c, level, scaled)
	if f.health ~= 1 then
		local hp = P.scaleHealth(m:getMaxHealth(), f.health)
		m:setMaxHealth(hp)
		m:setHealth(hp)
	end
	paced[id] = {level = level, scaled = scaled, f = f}
	m:registerEvent(DEATH)
	m:registerEvent(CLEAVE)
	return true
end

-- the loot factor a natural spawn will get, read in onSpawn before the placement (treasure_goblin.lua: the goblin roll
-- of a respawn). 1 when off, for a boss, a summon or an unknown level.
function PC.spawnLootMult(m)
	local c = cfg()
	if not c or c.enabled == false or not m or m:getMaster() or isBoss(m) then
		return 1
	end
	local ok, level, scaled = pcall(PC.levelOf, m)
	if not ok or not level or level <= 0 then
		return 1
	end
	return P.factors(c, level, scaled).loot
end

-- other scripts: pace this monster at its first think (a base dungeon's monsters, an ambush copy of a paced monster)
function PC.mark(m)
	if m and m.registerEvent then
		pcall(function() m:registerEvent(INIT) end)
	end
	return m
end

function PC.isPaced(m)
	return m ~= nil and paced[m:getId()] ~= nil
end

function PC.factorsOf(m)
	local info = m and paced[m:getId()]
	return info and info.f or nil
end

function PC.lootMultOf(m)
	if cfg().enabled == false then
		return 1
	end
	local f = PC.factorsOf(m)
	return f and f.loot or 1
end

function PC.goalMultOf(m)
	if cfg().enabled == false then
		return 1
	end
	local f = PC.factorsOf(m)
	return f and f.goal or 1
end

function PC.xpMultOf(m)
	if cfg().enabled == false then
		return 1
	end
	local f = PC.factorsOf(m)
	return f and f.xp or 1
end

-- damage multiplier of an attacker on a player: a paced monster, or the summon of one; 1 for anything else
function PC.damageMultOf(attacker)
	if cfg().enabled == false or not attacker or not attacker:isMonster() then
		return 1
	end
	local f = PC.factorsOf(attacker)
	if not f then
		local master = attacker:getMaster()
		if master and master:isMonster() then
			f = PC.factorsOf(master)
		end
	end
	return f and f.damage or 1
end

-- generic kill counters (achievements, season pass, journey): whole kills this kill completes (1 for an unpaced
-- monster; a paced one counts 1 / its goal factor, summed per player and counter)
function PC.killCredit(player, monster, counter)
	local goal = PC.goalMultOf(monster)
	if goal <= 1 then
		return 1
	end
	local pid = player:getId()
	local acc = credits[pid]
	if not acc then
		acc = {}
		credits[pid] = acc
	end
	local key = counter or "kill"
	acc[key] = acc[key] or {}
	return P.killCredit(acc[key], goal)
end

-- first think: a map spawn or a marked monster (INIT), any other script-made monster (PROBE: a generated area point)
for _, name in ipairs({INIT, PROBE}) do
	local ev = CreatureEvent(name)
	local include = name == INIT
	function ev.onThink(creature, interval)
		creature:unregisterEvent(name)
		local ok, err = pcall(PC.apply, creature, include)
		if not ok then
			print("[ChaosPace] " .. tostring(err))
		end
		return true
	end
	ev:register()
end

local death = CreatureEvent(DEATH)
function death.onDeath(creature)
	local id = creature:getId()
	addEvent(function(cid) paced[cid] = nil end, 10000, id)
	return true
end
death:register()

-- pack cleave (pace_config.lua cleave): a direct hit of a listed class on a paced monster also hits its neighbours
local cleaving = false
local DIRECT = {}
for _, k in ipairs({"ORIGIN_MELEE", "ORIGIN_RANGED", "ORIGIN_SPELL", "ORIGIN_WAND"}) do
	if _G[k] ~= nil then
		DIRECT[_G[k]] = true
	end
end

function PC.cleave(creature, attacker, amount, combatType)
	local c = cfg()
	local voc = attacker:getVocation()
	local e = P.cleaveOf(c, voc and voc:getId())
	if not e then
		return 0
	end
	local dmg = P.cleaveDamage(amount, e.percent)
	if dmg <= 0 then
		return 0
	end
	local pos = creature:getPosition()
	local r = c.cleave.radius or 1
	local cands = {}
	for _, s in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
		if s:isMonster() and s:getId() ~= creature:getId() and s:getHealth() > 0 then
			local master = s:getMaster()
			if not (master and master:isPlayer()) and not isBoss(s) then
				local sp = s:getPosition()
				if sp.z == pos.z then
					cands[#cands + 1] = {id = s:getId(), x = sp.x, y = sp.y, m = s}
				end
			end
		end
	end
	local hit = 0
	cleaving = true
	for _, t in ipairs(P.cleaveTargets(cands, pos.x, pos.y, r, e.targets)) do
		local ok = pcall(doTargetCombatHealth, attacker, t.m, combatType, -dmg, -dmg, CONST_ME_NONE, ORIGIN_NONE)
		if ok then
			hit = hit + 1
		end
	end
	cleaving = false
	return hit
end

local cleaveEv = CreatureEvent(CLEAVE)
function cleaveEv.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if not cleaving and attacker and attacker:isPlayer() and DIRECT[origin] and primaryType ~= COMBAT_HEALING then
		local amount = math.abs(primaryDamage or 0) + math.abs(secondaryDamage or 0)
		if amount > 0 then
			local ok, err = pcall(PC.cleave, creature, attacker, amount, primaryType)
			cleaving = false
			if not ok then
				print("[ChaosPace] cleave: " .. tostring(err))
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
cleaveEv:register()

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if cfg().enabled ~= false and not self:getMaster() then
		self:registerEvent(artificial and PROBE or INIT)
	end
	return true
end
spawnCb:register()

-- experience: the curve, then the multikill chain
local xpCb = EventCallback
xpCb.onGainExperience = function(player, source, exp, rawExp)
	local c = cfg()
	if c.enabled == false or not source or not source.isMonster or not source:isMonster() then
		return exp
	end
	local info = paced[source:getId()]
	if not info or (tonumber(exp) or 0) <= 0 then
		return exp
	end
	local e = P.scaleExp(exp, info.f.xp)
	local pid = player:getId()
	local st = chains[pid]
	if not st then
		st = {}
		chains[pid] = st
	end
	local tierXp = 1
	local tier = ChaosTierOf and ChaosTierOf(source)
	if tier and ChaosTiers and ChaosTiers[tier] then
		tierXp = ChaosTiers[tier].xp or 1
	end
	local before = st.percent or 0
	local total, n, pct = P.multikill(c, st, nowMs(), e, tierXp)
	local mk = c.multikill
	if pct > before and mk and (mk.announceFrom or 0) > 0 and n >= mk.announceFrom and player.sendTextMessage then
		local text = string.format("Multikill x%d: +%d%% experience on the chain.", n, pct)
		if Chaos and Chaos.t then
			text = Chaos.t(player, "Multikill x%d: +%d%% experience on the chain.", n, pct)
		end
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, text)
	end
	return math.floor(total + 0.5)
end
xpCb:register(-10)

local logout = CreatureEvent("ChaosPaceLogout")
function logout.onLogout(player)
	chains[player:getId()] = nil
	credits[player:getId()] = nil
	return true
end
logout:register()

local login = CreatureEvent("ChaosPaceLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPaceLogout")
	return true
end
login:register()
