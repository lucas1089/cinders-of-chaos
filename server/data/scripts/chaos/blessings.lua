-- Ember Blessings: a monster kill may bless its loot owner for one minute (more experience, gold, damage, speed ...).
-- Rules: blessings_core.lua, numbers: blessings_config.lua, tests: tests/blessings_test.lua, overview: server/README.md
-- "Ember Blessings".
--
--   the proc       EventCallback onDropLoot: one roll per kill, for the corpse owner only (the player who dealt the
--                  most damage, or the master of the summon that did: the same player the Chaos loot is for). Party
--                  members do not share the roll. No roll in PvP places (battleground, arena, siege, PvP-zone tiles),
--                  for a summon's death or without stamina for loot.
--   experience     EventCallback onGainExperience (index 6, after the world buff), monster experience only
--   gold           EventCallback onDropLoot (index 2, as the Gold Find modifier): more coins in the corpse
--   Chaos loot     loot_config.lua rateMult (extra rolls, currency, gems, runes), loot.lua rarity find and orb chances
--                  read ChaosBlessings.mult / .value
--   damage dealt   onHealthChange on the monster (registered by onTargetCombat), hits of the player and its summons
--   damage taken   onHealthChange / onManaChange on the player, hits of monsters only
--   speed, regeneration, critical hits   a condition each (sub ids cfg.subIds) that ends by itself
-- State lives in memory (ChaosBlessings.state, per player id) and ends with the session: logout, death and login clear
-- it, and nothing is saved. Entering a PvP place takes every blessing away. Staff: /blessing.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ChaosBlessingsConfig = dofile("data/scripts/chaos/blessings_config.lua")
dofile("data/scripts/chaos/blessings_core.lua")

ChaosBlessings = ChaosBlessings or {}
local X = ChaosBlessings
local K = ChaosBlessingsCore
X.state = X.state or {} -- player id -> core state

local function cfg()
	return ChaosBlessingsConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function try(what, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		print("[Chaos blessings] " .. what .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function stateOf(player, create)
	local ok, id = pcall(function() return player:getId() end)
	if not ok or not id then
		return nil
	end
	local st = X.state[id]
	if not st and create then
		st = K.newState()
		X.state[id] = st
	end
	return st
end

-- ---------------------------------------------------------------- public reads (loot.lua, loot_config.lua, buffs)
-- 1 + value% while the blessing runs (ward: 1 - value%), else 1
function X.mult(player, key)
	local st = player and stateOf(player)
	return st and K.mult(cfg(), st, key, nowMs()) or 1
end

-- the blessing's value while it runs, else 0
function X.value(player, key)
	local st = player and stateOf(player)
	return st and K.value(cfg(), st, key, nowMs()) or 0
end

-- the buff bar item of one kind (data/lib/chaos_buffs.lua source "blessings"): {leftMs, name, desc} or nil
function X.buffItem(player, key)
	local st = stateOf(player)
	if not st then
		return nil
	end
	for _, it in ipairs(K.list(cfg(), st, nowMs())) do
		if it.key == key then
			return it
		end
	end
	return nil
end

-- ---------------------------------------------------------------- PvP places
function X.pvpPlace(player)
	local pos = player:getPosition()
	local function check(fn)
		local ok, v = pcall(fn)
		return ok and v and true or false
	end
	if check(function() return ChaosBattleground and ChaosBattleground.isInside(player) end) then
		return "battleground"
	end
	if check(function() return ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) end) then
		return "arena"
	end
	if check(function() return ChaosSiege and ChaosSiege.locate and ChaosSiege.locate(pos) ~= nil end) then
		return "siege"
	end
	if check(function()
		local tile = Tile(pos)
		return TILESTATE_PVPZONE and tile and tile:hasFlag(TILESTATE_PVPZONE)
	end) then
		return "pvp zone"
	end
	-- the open PvP zone module, when it is installed
	if check(function()
		local Z = rawget(_G, "ChaosPvpZone")
		return Z and ((Z.isInside and Z.isInside(player)) or (Z.inZone and Z.inZone(pos)))
	end) then
		return "pvp zone"
	end
	return nil
end

-- ---------------------------------------------------------------- conditions (speed, regeneration, critical hits)
local CONDITION_OF = {speed = "CONDITION_HASTE", regen = "CONDITION_REGENERATION", crit = "CONDITION_ATTRIBUTES"}

local function removeCondition(player, key)
	local sub = cfg().subIds[key]
	local ctype = rawget(_G, CONDITION_OF[key] or "")
	if sub and ctype then
		player:removeCondition(ctype, CONDITIONID_DEFAULT, sub, true)
	end
end

local function addCondition(player, key, ms)
	local c = cfg()
	local sub, ctype = c.subIds[key], rawget(_G, CONDITION_OF[key] or "")
	if not sub or not ctype or ms <= 0 then
		return
	end
	removeCondition(player, key)
	local cond = Condition(ctype, CONDITIONID_DEFAULT)
	cond:setParameter(CONDITION_PARAM_SUBID, sub)
	cond:setParameter(CONDITION_PARAM_TICKS, ms)
	local e = K.entry(c, key)
	if key == "speed" then
		cond:setParameter(CONDITION_PARAM_SPEED, K.speedDelta(c, player:getBaseSpeed()))
	elseif key == "regen" then
		local hp, mp = K.regenAmounts(c, player:getMaxHealth(), player:getMaxMana())
		cond:setParameter(CONDITION_PARAM_HEALTHGAIN, hp)
		cond:setParameter(CONDITION_PARAM_HEALTHTICKS, c.regenTicksMs)
		cond:setParameter(CONDITION_PARAM_MANAGAIN, mp)
		cond:setParameter(CONDITION_PARAM_MANATICKS, c.regenTicksMs)
	elseif key == "crit" then
		cond:setParameter(CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE, e.value or 0)
		cond:setParameter(CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT, e.critAmount or 0)
	end
	player:addCondition(cond)
end

-- the engine side of a blessing that starts, is refreshed or ends
local function applyEffect(player, key, untilMs)
	if CONDITION_OF[key] then
		addCondition(player, key, untilMs - nowMs())
	end
end

local function removeEffect(player, key)
	if CONDITION_OF[key] then
		removeCondition(player, key)
	end
end

-- every blessing gone (PvP place, staff, logout)
function X.clear(player)
	for key in pairs(CONDITION_OF) do
		removeCondition(player, key)
	end
	X.state[player:getId()] = nil
end

-- ---------------------------------------------------------------- the proc
local function feedback(player, grant)
	local c = cfg()
	local e = K.entry(c, grant.key)
	local pos = player:getPosition()
	local effect = rawget(_G, e.effect or "")
	if effect then
		pos:sendMagicEffect(effect)
	end
	if ChaosCombatFx and ChaosCombatFx.label then
		ChaosCombatFx.label(pos, e.label or e.name, e.color)
	end
	if c.message then
		local text
		if grant.action == "refresh" then
			text = string.format("%s burns again: %ds.", e.name, math.floor((c.durationMs or 60000) / 1000))
		else
			text = string.format("A dying ember blesses you: %s, %s", e.name, string.format(e.desc or "", e.value or 0))
			if grant.replaced then
				local old = K.entry(c, grant.replaced)
				text = text .. string.format(" (%s fades)", old and old.name or grant.replaced)
			end
		end
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, text)
	end
end

-- give one blessing (the proc and /blessing): refresh, a new one or the replacement of the weakest
function X.give(player, key, now)
	now = now or nowMs()
	local st = stateOf(player, true)
	local grant = K.grant(cfg(), st, key, now)
	if grant.replaced then
		removeEffect(player, grant.replaced)
	end
	applyEffect(player, key, grant.untilMs)
	feedback(player, grant)
	return grant
end

local function monsterLevel(monster)
	if ChaosLoot and ChaosLoot.monsterLevel then
		local ok, lvl = pcall(ChaosLoot.monsterLevel, monster)
		if ok and tonumber(lvl) then
			return tonumber(lvl)
		end
	end
	local ok, lvl = pcall(function() return monster:getMonsterLevel() end)
	return ok and tonumber(lvl) or 0
end

function X.onKill(monster, owner)
	local c = cfg()
	if c.enabled == false or monster:getMaster() then
		return nil
	end
	local minStamina = ChaosLootConfig and ChaosLootConfig.minStamina or 0
	if owner:getStamina() <= minStamina then
		return nil
	end
	local st = stateOf(owner, true)
	local now = nowMs()
	local info = {
		tier = type(ChaosTierOf) == "function" and ChaosTierOf(monster) or "normal",
		playerLevel = owner:getLevel(),
		monsterLevel = monsterLevel(monster),
		blocked = X.pvpPlace(owner)
	}
	local grant = K.roll(c, st, info, now, math.random)
	if not grant then
		return nil
	end
	if grant.replaced then
		removeEffect(owner, grant.replaced)
	end
	applyEffect(owner, grant.key, grant.untilMs)
	feedback(owner, grant)
	return grant
end

-- ---------------------------------------------------------------- engine hooks
local COINS = {{2160, 10000}, {2152, 100}, {2148, 1}} -- crystal, platinum, gold coin

local function addGold(corpse, pct)
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

local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	local owner = corpse and Player(corpse:getCorpseOwner())
	if not owner then
		return
	end
	local pct = X.value(owner, "gold")
	if pct > 0 then
		try("gold", addGold, corpse, pct)
	end
	try("kill", X.onKill, self, owner)
end
-- after the stock loot (0) and the Chaos loot layer (1), before autoloot (3): autoloot takes the extra coins too
drop:register(2)

local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if source and source.isMonster and source:isMonster() and not source:getMaster() then
		local m = X.mult(self, "xp")
		if m ~= 1 then
			return math.floor(exp * m)
		end
	end
	return exp
end
xpCb:register(6) -- after the world experience buff (5), before the dungeon / rift caps (90, 100)

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

local dealt = CreatureEvent("ChaosBlessingsDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and creature:isMonster() then
		local p = playerOf(attacker)
		local m = p and X.mult(p, "damage") or 1
		if m ~= 1 then
			primaryDamage = K.scale(primaryDamage, m)
			secondaryDamage = K.scale(secondaryDamage, m)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

local target = EventCallback
target.onTargetCombat = function(creature, tgt)
	if creature and tgt and tgt:isMonster() then
		local p = playerOf(creature)
		if p and X.value(p, "damage") > 0 then
			tgt:registerEvent("ChaosBlessingsDealt")
		end
	end
	return RETURNVALUE_NOERROR
end
target:register()

-- a monster's hit on a warded player (not a player's summon: no PvP effect)
local function wardMult(creature, attacker)
	if not attacker or not attacker:isMonster() or playerOf(attacker) then
		return 1
	end
	return X.mult(creature, "ward")
end

local taken = CreatureEvent("ChaosBlessingsTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING then
		local m = wardMult(creature, attacker)
		if m ~= 1 then
			primaryDamage = K.scale(primaryDamage, m)
			secondaryDamage = K.scale(secondaryDamage, m)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

local takenMana = CreatureEvent("ChaosBlessingsTakenMana")
function takenMana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and primaryType ~= COMBAT_MANADRAIN then
		local m = wardMult(creature, attacker)
		if m ~= 1 then
			primaryDamage = K.scale(primaryDamage, m)
			secondaryDamage = K.scale(secondaryDamage, m)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
takenMana:register()

-- ends and PvP places
local function tick()
	local now = nowMs()
	for id, st in pairs(X.state) do
		local player = Player(id)
		if not player then
			X.state[id] = nil
		else
			for _, key in ipairs(K.expire(st, now)) do
				removeEffect(player, key)
			end
			if K.count(st) > 0 then
				local place = X.pvpPlace(player)
				if place then
					X.clear(player)
					player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR,
						"Your Ember Blessings fade: no blessings in the " .. place .. ".")
				end
			end
		end
	end
end

local think = GlobalEvent("ChaosBlessingsThink")
function think.onThink(interval)
	try("tick", tick)
	return true
end
think:interval(cfg().tickMs or 1000)
think:register()

local login = CreatureEvent("ChaosBlessingsLogin")
function login.onLogin(player)
	X.clear(player) -- a condition left from a crash or a death: nothing carries over
	player:registerEvent("ChaosBlessingsTaken")
	player:registerEvent("ChaosBlessingsTakenMana")
	player:registerEvent("ChaosBlessingsLogout")
	return true
end
login:register()

local logout = CreatureEvent("ChaosBlessingsLogout")
function logout.onLogout(player)
	X.clear(player)
	return true
end
logout:register()

-- ---------------------------------------------------------------- staff
-- /blessing <key>             give that blessing now (refreshes it when active; the cap applies)
-- /blessing list | clear      the active ones (and the pool) | take all away
-- /blessing roll <tier>, <monster level>[, <n>]   the chance of a kill for you and n simulated kills (no blessing given)
local talk = TalkAction("/blessing")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getAccountType() < ACCOUNT_TYPE_GOD then
		return true
	end
	local c = cfg()
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local function say(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	if param == "" or param == "list" then
		local parts = {}
		for _, it in ipairs(K.list(c, stateOf(player) or K.newState(), nowMs())) do
			parts[#parts + 1] = string.format("%s %ds", it.name, math.ceil(it.leftMs / 1000))
		end
		local keys = {}
		for _, e in ipairs(c.pool) do
			keys[#keys + 1] = e.key
		end
		say("Ember Blessings: " .. (#parts > 0 and table.concat(parts, ", ") or "none") .. ". Pool: " .. table.concat(keys, ", "))
		return false
	end
	if param == "clear" then
		X.clear(player)
		say("Ember Blessings cleared.")
		return false
	end
	local tier, level, n = param:match("^roll%s+(%a+)%s*,%s*(%d+)%s*,?%s*(%d*)$")
	if tier then
		n = math.min(tonumber(n) or 10000, 1000000)
		local pct = K.chance(c, tier, player:getLevel(), tonumber(level))
		local st, hits, t = K.newState(), 0, 0
		for _ = 1, n do
			t = t + 2000 -- one kill every 2 s
			if K.roll(c, st, {tier = tier, playerLevel = player:getLevel(), monsterLevel = tonumber(level)}, t, math.random) then
				hits = hits + 1
			end
		end
		say(string.format("Blessing chance %.2f%% per kill (%s, level %s vs %d); %d of %d kills at one kill / 2 s blessed.",
			pct, tier, level, player:getLevel(), hits, n))
		return false
	end
	if not K.entry(c, param) then
		say("Unknown blessing " .. param .. ". /blessing list shows the pool.")
		return false
	end
	local grant = X.give(player, param)
	say(string.format("Blessing %s: %s%s.", param, grant.action, grant.replaced and (" (replaced " .. grant.replaced .. ")") or ""))
	return false
end
talk:separator(" ")
talk:register()
