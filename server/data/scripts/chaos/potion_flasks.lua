-- Flask charges of the Everfull potions (README "Potions", "Flask charges"; owner 2026-10-25, O242: "do what PoE does,
-- where potions refill as players kill monsters"). Rules: potions_core.lua; numbers: potions_config.lua `flask`; the
-- charge helpers: data/lib/chaos_potions.lua; the drink itself: potions.lua.
--
--   * A monster's death refills the health and the mana flask of the killers (last hit, most damage, everybody in the
--     damage map) and of their party members within `partyRange` tiles on the same floor, by the monster's tier
--     (monster_tiers.lua: normal < magic < rare < legendary, boss) and its type's base experience, at most `killCap`.
--     Only monsters carry the death event: a player's death never refills anything (no PvP refill). A summon of a
--     player, a rift husk and a training dummy refill nothing.
--   * In a protection zone (a temple, a town) both flasks fill to full within `safeMs`, unless the character is in a fight.
--   * The charges are the character's storage: a relog, a trade, a moved or split flask item changes nothing.
--   * Look at your own flask shows its charges. A refill message (a whole charge more) comes at most every `noticeMs`.
-- Not verified on a running server. Assumed engine API: CreatureEvent "death" on a monster (as bestiary.lua),
-- Creature:getDamageMap, EventCallback onSpawn / onLook, GlobalEvent onThink, Tile:hasFlag(TILESTATE_PROTECTIONZONE).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosBounty or not ChaosBounty.credit then
	dofile("data/scripts/chaos/bounty_core.lua")
end
dofile("data/scripts/chaos/potions_core.lua")
dofile("data/scripts/chaos/potions_config.lua")
dofile("data/lib/chaos_potions.lua")

local PT = ChaosPotions
local K = ChaosPotionsCore
ChaosPotionFlasks = ChaosPotionFlasks or {}
local F = ChaosPotionFlasks
F.lastNotice = F.lastNotice or {} -- player id -> ms of the last refill message

local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

local function tierOf(monster)
	if ChaosTierOf then
		local ok, tier = pcall(ChaosTierOf, monster)
		if ok and type(tier) == "string" then
			return tier
		end
	end
	return "normal"
end

local function baseExperience(monster)
	local ok, xp = pcall(function() return monster:getType():getExperience() end)
	return ok and tonumber(xp) or 0
end

-- the refill message: one line with both flasks, when a flask gained a whole charge, at most every noticeMs
local function notice(player, gained)
	local gotOne = false
	for _, n in pairs(gained) do
		if n > 0 then
			gotOne = true
		end
	end
	if not gotOne then
		return
	end
	local id, now = player:getId(), nowMs()
	if not K.noticeDue(PT.cfg(), F.lastNotice[id], now) then
		return
	end
	F.lastNotice[id] = now
	player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "Flasks: health %s, mana %s",
		PT.label(player, "health"), PT.label(player, "mana")))
end

-- the players a kill refills: last hit, most damage, the damage map, and the party members near a killer
function F.credited(creature, killer, mostDamageKiller)
	local killers, seen = {}, {}
	local function add(p)
		if p and not seen[p:getId()] then
			seen[p:getId()] = true
			killers[#killers + 1] = p
		end
	end
	local ids = {}
	for id in pairs(creature:getDamageMap() or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		add(playerOf(Creature(id)))
	end
	add(playerOf(killer))
	add(playerOf(mostDamageKiller))
	if #killers == 0 then
		return {}
	end
	return ChaosBounty.credit(killers, function(p)
		local party = p:getParty()
		if not party then
			return nil
		end
		local members = party:getMembers() or {}
		members[#members + 1] = party:getLeader()
		return members
	end, function(p) return p:getPosition() end, PT.cfg().flask.partyRange or 30, function(p) return p:getId() end)
end

function F.onKill(creature, killer, mostDamageKiller)
	if not creature:isMonster() then
		return
	end
	local cfg = PT.cfg()
	local husk = ChaosRift and ChaosRift.isHusk and ChaosRift.isHusk(creature) or false
	local name = Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
	if not K.eligibleKill(cfg, {name = name, summon = creature:getMaster() ~= nil, husk = husk}) then
		return
	end
	local tier, xp = tierOf(creature), baseExperience(creature)
	for _, p in ipairs(F.credited(creature, killer, mostDamageKiller)) do
		local gained, any = PT.addKill(p, tier, xp)
		if any then
			notice(p, gained)
		end
	end
end

local death = CreatureEvent("ChaosFlaskDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local ok, err = pcall(F.onKill, creature, killer, mostDamageKiller)
	if not ok then
		print("[potion flasks] kill: " .. tostring(err))
	end
	return true
end
death:register()

-- every spawned monster except a summon carries the death event (as bestiary.lua)
local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if not self:getMaster() then
		self:registerEvent("ChaosFlaskDeath")
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- town: a protection zone fills the flasks
local function inFight(player)
	if not (CONDITION_INFIGHT and CONDITIONID_DEFAULT) then
		return false
	end
	local ok, c = pcall(function() return player:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT) end)
	return ok and c ~= nil
end

local function inSafeZone(player)
	local ok, res = pcall(function()
		local tile = player:getTile()
		return tile ~= nil and TILESTATE_PROTECTIONZONE ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
	end)
	return ok and res == true
end

-- one pass over the online players (the think and the tests); returns how many were filled
function F.safePass(players)
	local cfg, n = PT.cfg(), 0
	for _, p in ipairs(players) do
		local needs = false
		for _, pool in ipairs(cfg.pools) do
			if PT.charges(p, pool) < PT.maxCharges(p, pool) * 100 then
				needs = true
			end
		end
		if needs and K.safeRefill(cfg, {safe = inSafeZone(p), fighting = inFight(p)}) and PT.fill(p) then
			n = n + 1
			p:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(p, "Your flasks are full again."))
		end
	end
	return n
end

local think = GlobalEvent("ChaosFlaskSafeThink")
function think.onThink(interval)
	local ok, err = pcall(function()
		F.safePass(Game.getPlayers())
	end)
	if not ok then
		print("[potion flasks] safe zone: " .. tostring(err))
	end
	return true
end
think:interval(PT.cfg().flask.safeMs or 2000)
think:register()

-- a logged-out player's notice clock goes
local logout = CreatureEvent("ChaosFlaskLogout")
function logout.onLogout(player)
	F.lastNotice[player:getId()] = nil
	return true
end
logout:register()
local login = CreatureEvent("ChaosFlaskLogin")
function login.onLogin(player)
	player:registerEvent("ChaosFlaskLogout")
	return true
end
login:type("login")
login:register()

-- ---------------------------------------------------------------- look: your own flask says how many charges it has
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing.isItem and thing:isItem() and self and self.isPlayer and self:isPlayer() then
		local ok, text = pcall(function()
			local entry = PT.everfull(thing:getId())
			if not entry then
				return description
			end
			local top = thing:getTopParent()
			if top ~= self then -- somebody else's flask (or one on the floor) shows none of ours
				return description
			end
			return description .. "\n" .. Chaos.t(self, "Charges: %s", PT.labelOf(self, entry))
		end)
		if ok then
			description = text
		end
	end
	return description
end
-- after the base default_onLook (0), the salvage line (120) and the charges line (125)
look:register(130)
