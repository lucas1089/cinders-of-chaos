-- Health and mana globes: a kill may drop a glowing orb that the killer or the killer's party restores itself from by
-- walking over it. Rules: globes_core.lua, numbers: globes_config.lua, framework: pickups.lua (items 32088 / 32089),
-- tests: tests/globes_test.lua, overview: server/README.md "Ground pickups and globes".
--
--   the drop     EventCallback onDropLoot: one roll per kind for the corpse owner (the player who dealt the most damage, or
--                the master of the summon that did), on the lowest health / mana share of the owner and the party
--                members near it. No drop for a summon's death, a trivial monster, without stamina for loot, or in
--                a place of pickups_config.lua `blocked` (arena, battleground, siege, the Infinity Tower, PvP places ...).
--   the take     the owner and the owner's party (ChaosPickups): health through the heal event (the tree's Healing and
--                the PvP rules apply as to a potion), mana with the stored Healing percent. A full bar does not take it.
-- State is in memory (the per-killer cooldowns and the pickups): a restart forgets it all. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
ChaosGlobesConfig = dofile("data/scripts/chaos/globes_config.lua")
dofile("data/scripts/chaos/globes_core.lua")

ChaosGlobes = ChaosGlobes or {}
local X = ChaosGlobes
local K = ChaosGlobesCore
X.cool = X.cool or {} -- "ownerId:kind" -> ms of the last drop

local function cfg()
	return ChaosGlobesConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
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

-- the owner and the party members near it (same floor, within partyRange), alive
local function candidates(owner)
	local out = {owner}
	local party = owner:getParty()
	if not party then
		return out
	end
	local pos, range = owner:getPosition(), cfg().partyRange or 12
	local members = party:getMembers() or {}
	members[#members + 1] = party:getLeader()
	for _, m in ipairs(members) do
		if m and m:getId() ~= owner:getId() and m:getHealth() > 0 then
			local p = m:getPosition()
			if p.z == pos.z and math.abs(p.x - pos.x) <= range and math.abs(p.y - pos.y) <= range then
				out[#out + 1] = m
			end
		end
	end
	return out
end

-- {health = lowest share, mana = lowest share} of a list of players
function X.shares(list)
	local h, m = {}, {}
	for _, p in ipairs(list) do
		local mh = p:getMaxHealth()
		if mh > 0 then
			h[#h + 1] = p:getHealth() / mh
		end
		local mm = p:getMaxMana()
		if mm >= (cfg().minMaxMana or 0) and mm > 0 then
			m[#m + 1] = p:getMana() / mm
		end
	end
	return {health = K.lowest(h), mana = K.lowest(m)}
end

local function treeHealingPct(player)
	local c = cfg()
	local key = c.healingStorage
	local PC = rawget(_G, "ChaosPotionsConfig")
	if PC and PC.storage and PC.storage.healingPct then
		key = PC.storage.healingPct
	end
	local v = key and player:getStorageValue(key) or 0
	return math.max(0, tonumber(v) or 0)
end

-- the take: restore and tell. false: nothing to restore, the globe stays for someone who needs it
local function takeGlobe(kind)
	return function(player, entry)
		local c = cfg()
		local label = kind == "mana" and "mana" or "health"
		if kind == "mana" then
			if player:getMana() >= player:getMaxMana() then
				return false
			end
			local v = K.amount(c, "mana", player:getMaxMana(), treeHealingPct(player))
			doTargetCombat(0, player, COMBAT_MANADRAIN, v, v)
			player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, Chaos.t(player, "A mana globe restores %d mana.", v))
		else
			if player:getHealth() >= player:getMaxHealth() then
				return false
			end
			local v = K.amount(c, "health", player:getMaxHealth(), 0)
			doTargetCombat(0, player, COMBAT_HEALING, v, v) -- through the heal event: the tree's Healing applies
			player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, Chaos.t(player, "A health globe restores %d health.", v))
		end
		return true
	end
end

-- one kill: returns the kinds dropped (for the tests)
function X.onKill(monster, corpse, owner, rand)
	local c = cfg()
	local P = rawget(_G, "ChaosPickups")
	if c.enabled == false or not P or monster:getMaster() then
		return {}
	end
	if c.requireStamina ~= false then
		local minStamina = ChaosLootConfig and ChaosLootConfig.minStamina or 0
		if owner:getStamina() <= minStamina then
			return {}
		end
	end
	if P.blocked(owner) then
		return {}
	end
	if not K.levelOk(c, owner:getLevel(), monsterLevel(monster)) then
		return {}
	end
	local tier = type(ChaosTierOf) == "function" and ChaosTierOf(monster) or "normal"
	local hits = K.rollKinds(c, X.shares(candidates(owner)), tier, rand or math.random)
	local now, ownerId, dropped = nowMs(), owner:getId(), {}
	local pos = corpse:getPosition()
	for _, kind in ipairs({"health", "mana"}) do
		if hits[kind] and K.cooldownOk(X.cool, ownerId, kind, c, now)
				and P.countOf(ownerId, kind .. "_globe") < (c.maxAlive or 1) then
			local entry = P.drop({itemKey = kind .. "_globe", kind = kind .. "_globe", pos = pos, ownerId = ownerId,
				ttlMs = c.lifetimeMs, ownerWindowMs = c.ownerWindowMs, onTake = takeGlobe(kind)})
			if entry then
				K.noteDrop(X.cool, ownerId, kind, now)
				dropped[#dropped + 1] = kind
			end
		end
	end
	return dropped
end

local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	local owner = corpse and Player(corpse:getCorpseOwner())
	if not owner then
		return
	end
	local ok, err = pcall(X.onKill, self, corpse, owner)
	if not ok then
		print("[Chaos globes] kill: " .. tostring(err))
	end
end
drop:register(8) -- after the loot layer, the blessings and autoloot
