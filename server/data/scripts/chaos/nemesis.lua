-- Nemesis: a regular monster that kills a character may become that character's personal Nemesis. It gets a name
-- with an epithet ("Varkh, Bane of Varek"), a level bump, a trait, a black skull and the Heartblood outfit shader, comes
-- back while its victim hunts its kind, grows when it kills the victim again, and pays out when it finally falls.
--
-- * Birth: the victim's death event (registered at login). A regular killer (nemesis_core.lua K.eligible: no boss,
--   summon, treasure goblin, renamed event / instance monster, no PvP, outside every instance) rolls
--   cfg.birth.chance percent, lower above the server-wide soft cap. One row in chaos_nemesis.
-- * Appearing: a kill event registered ONLY on characters with a nemesis (no cost for anyone else). A kill of the same
--   type or of a monster near its base level rolls cfg.appear.chance; a warning, then the nemesis 3-6 tiles away.
--   It vanishes after cfg.appear.lifetimeSeconds, when its victim logs out, changes floor or runs off.
-- * No griefing: it only appears for its victim; its damage (health and mana) to anybody but the victim and the
--   victim's party is cancelled, and so is damage dealt to it by anybody else (nobody steals a revenge).
-- * Growth: it kills its victim again: one more kill (epithet "Twice-Slayer of ..."), more level, a second trait.
-- * Rewards: nemesis_core.lua K.reward (trophy once per nemesis, title, loot bonus with a cooldown; the party's
--   Nemesis Hunter bounty with the anti-farm rules). Hardcore characters: the trophy only.
-- * Tiers: the nemesis is a monster_tiers.lua tier of its own ("nemesis", label "Nemesis" in the monster bar): this
--   file sets ChaosTiers.nemesis and the ChaosTierState entry, so the tier's damage, experience and modifier hooks
--   (berserker, reflective, regenerating, swift) do the work. monster_tiers.lua is not edited.
--
-- Client (game_nemesis, extended opcode ChaosOpcodes.nemesis = 163, JSON {action, data}):
--   client -> server  get
--   server -> client  state {has, name, shown, monster, level, kills, traits = [{key, name, desc}], lastSeen, created,
--                     expiresIn, avenged, hunted}
-- Config: nemesis_config.lua. Pure logic: nemesis_core.lua (tests: server/tests/nemesis_test.lua). Overview:
-- server/README.md "Nemesis". Optional hooks, all guarded: Chaos.t / Chaos.langOf (localization), ChaosTitles,
-- ChaosNameplate.refresh, ChaosAchievements.progress, ChaosLeaderboard.record, ChaosSeason.modesOf (Hardcore),
-- ChaosLoot.monsterLevel, ChaosTreasureGoblin.isGoblinName, Chaos.inAnyInstance.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ChaosNemesisConfig = dofile("data/scripts/chaos/nemesis_config.lua")
dofile("data/scripts/chaos/nemesis_core.lua")

ChaosNemesis = ChaosNemesis or {}
local NE = ChaosNemesis
local K = ChaosNemesisCore
local OPCODE = ChaosOpcodes.nemesis or ChaosNemesisConfig.opcode

NE.records = NE.records or {} -- victim guid -> record (online characters only)
NE.alive = NE.alive or {} -- creature id -> {victim = guid, pid = player id, bornAt, nextStalk}
NE.byVictim = NE.byVictim or {} -- victim guid -> creature id of the nemesis in the world
NE.pending = NE.pending or {} -- victim guid -> true while the warning runs
NE.lastAppear = NE.lastAppear or {} -- victim guid -> os.time of the last appearance
NE.serverActive = NE.serverActive or 0 -- rows in chaos_nemesis (startup count, then kept up to date)

local function cfg()
	return ChaosNemesisConfig
end

local function T()
	return Chaos.tables and Chaos.tables.nemesis or cfg().table
end

local function now()
	return os.time()
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function rand(a, b)
	return math.random(a, b)
end

local function log(text)
	print("[Chaos nemesis] " .. text)
end

local function try(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

local function const(name, fallback)
	local v = name and rawget(_G, name)
	return v or fallback
end

-- ------------------------------------------------------------------ texts
-- the viewer's language once the localization helper tells it (Chaos.lang, chaos_constants.lua / i18n_core.lua:
-- "pt-BR" or "en"), else English
local function langOf(player)
	local fn = player and (Chaos.lang or Chaos.langOf)
	if type(fn) == "function" then
		local l = try(fn, player)
		if type(l) == "string" then
			return l
		end
	end
	return "en"
end

-- The text of key for this player. The localization helper's Chaos.t(player, english pattern, ...) wins when it has
-- a translation (its keys are the English texts of nemesis_config.lua `texts.en`); while it has none, the pt-BR text
-- of nemesis_config.lua `texts.pt` (a pt-BR player) or the English one.
local function tr(player, key, ...)
	local c = cfg()
	local lang = langOf(player)
	if type(Chaos.t) == "function" then
		local en = (c.texts.en or {})[key] or key
		local ok, s = pcall(Chaos.t, player, en, ...)
		if ok and type(s) == "string" and s ~= "" and (K.lang(lang) ~= "pt" or s ~= K.text(c, "en", key, ...)) then
			return s
		end
	end
	return K.text(c, lang, key, ...)
end
NE.tr = tr

local function tell(player, key, ...)
	if player then
		player:sendTextMessage(const("MESSAGE_EVENT_ADVANCE", 19), tr(player, key, ...))
	end
end

-- ------------------------------------------------------------------ storages
local function storage(i)
	return (Chaos.storage and Chaos.storage.nemesis or cfg().storage) + i
end
NE.S_AVENGED, NE.S_HUNTED, NE.S_BOUNTY, NE.S_AVENGE, NE.S_ENDED, NE.S_TROPHIES = 0, 1, 2, 3, 4, 5

local function getS(player, i)
	local v = tonumber(try(function() return player:getStorageValue(storage(i)) end)) or -1
	return v > 0 and v or 0
end

local function setS(player, i, v)
	pcall(function() player:setStorageValue(storage(i), v) end)
end

local function counters(player)
	return {avenged = getS(player, NE.S_AVENGED), hunted = getS(player, NE.S_HUNTED)}
end

-- ------------------------------------------------------------------ database
local tableReady = false
local function ensureTable()
	if tableReady then
		return true
	end
	if not db or not db.query then
		return false
	end
	tableReady = try(db.query, K.sqlCreate(T())) ~= nil
	return tableReady
end

local function esc(s)
	return db.escapeString(tostring(s))
end

local SELECT_COLS = {}
for _, c in ipairs(K.SELECT_COLUMNS) do
	local isString = c == "monster" or c == "name" or c == "traits"
	SELECT_COLS[#SELECT_COLS + 1] = {c, isString and "s" or "n"}
end

local function loadRecord(guid)
	if not ensureTable() then
		return nil
	end
	local rows = try(Chaos.select, K.sqlSelectVictim(T(), guid), SELECT_COLS) or {}
	for _, row in ipairs(rows) do
		local rec = K.fromRow(cfg(), row)
		if rec and rec.victim == guid then
			return rec
		end
	end
	return nil
end
NE.loadRecord = loadRecord

local function insertRecord(rec)
	if not ensureTable() then
		return false
	end
	if not try(db.query, K.sqlInsert(T(), rec, esc)) then
		return false
	end
	local id = db.lastInsertId and tonumber(try(db.lastInsertId))
	if not id or id <= 0 then
		local again = loadRecord(rec.victim)
		id = again and again.id
	end
	rec.id = id
	return id ~= nil
end

local function saveRecord(rec)
	if rec.id and ensureTable() then
		db.asyncQuery(K.sqlUpdate(T(), rec, esc))
	end
end

local function deleteRecord(rec)
	if rec.id and ensureTable() then
		db.asyncQuery(K.sqlDelete(T(), rec))
	end
	NE.serverActive = math.max(0, NE.serverActive - 1)
end

function NE.countActive()
	if not ensureTable() then
		return NE.serverActive
	end
	local rows = try(Chaos.select, K.sqlCount(T()), {{"n", "n"}}) or {}
	NE.serverActive = tonumber(rows[1] and rows[1].n) or NE.serverActive
	return NE.serverActive
end

-- ------------------------------------------------------------------ client
function NE.sendState(player)
	if not player then
		return
	end
	local rec = NE.records[player:getGuid()]
	Chaos.send(player, OPCODE, "state", K.view(cfg(), rec, player:getName(), now(), langOf(player), counters(player)))
end

-- ------------------------------------------------------------------ tiers (monster_tiers.lua, wrapped, not edited)
local function installTier()
	if type(ChaosTiers) == "table" then
		local s = cfg().stats
		ChaosTiers.nemesis = {label = "Nemesis", hp = 1.0, speed = 0, damage = s.damageMult or 1, xp = s.xpMult or 1,
			effect = const(cfg().look.appearEffect, const("CONST_ME_MORTAREA", 1))}
	end
end
NE.installTier = installTier
installTier()

-- ------------------------------------------------------------------ who is who
local function isNemesis(creature)
	return creature ~= nil and NE.alive[creature:getId()] ~= nil
end
NE.isNemesis = isNemesis

local function creditOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = try(function() return creature:getMaster() end)
	if master and master:isPlayer() then
		return master
	end
	return nil
end

local function partyGuids(player)
	local out = {}
	local party = player and try(function() return player:getParty() end)
	if not party then
		return out
	end
	local members = try(function() return party:getMembers() end) or {}
	local leader = try(function() return party:getLeader() end)
	if leader then
		members[#members + 1] = leader
	end
	for _, m in ipairs(members) do
		out[#out + 1] = m:getGuid()
	end
	return out
end

local function isBossMonster(monster)
	local mt = try(function() return monster:getType() end)
	if mt and try(function() return mt:isBoss() end) then
		return true
	end
	local name = (Chaos.monsterTypeName(monster) or ""):lower()
	if ChaosTierConfig and ChaosTierConfig.bosses and ChaosTierConfig.bosses[name] then
		return true
	end
	return type(ChaosTierOf) == "function" and try(ChaosTierOf, monster) == "boss"
end

local function monsterLevel(monster)
	if ChaosLoot and ChaosLoot.monsterLevel then
		return tonumber(try(ChaosLoot.monsterLevel, monster)) or 0
	end
	return 0
end

local function isHardcore(player)
	local S = ChaosSeason
	if S and S.modesOf then
		local f = try(S.modesOf, player)
		return type(f) == "table" and f.hc == true
	end
	return false
end

-- ------------------------------------------------------------------ the monster in the world
local function despawn(cid, key)
	local st = NE.alive[cid]
	NE.alive[cid] = nil
	if st then
		NE.byVictim[st.victim] = nil
		if ChaosTierState then
			ChaosTierState[cid] = nil
		end
	end
	local monster = Monster(cid)
	if monster then
		local rec = st and NE.records[st.victim]
		local victim = st and Player(st.pid)
		monster:getPosition():sendMagicEffect(const("CONST_ME_POFF", 3))
		if key and victim and rec then
			tell(victim, key, monster:getName())
		end
		monster:remove()
	end
end
NE.despawn = despawn

local function tick(cid)
	local st = NE.alive[cid]
	local monster = Monster(cid)
	if not st then
		return
	end
	if not monster then
		NE.alive[cid] = nil
		NE.byVictim[st.victim] = nil
		return
	end
	local c = cfg()
	local a = c.appear
	local victim = Player(st.pid)
	local mpos = monster:getPosition()
	if not victim or nowMs() - st.bornAt >= a.lifetimeSeconds * 1000 then
		despawn(cid, "vanish")
		return
	end
	local vpos = victim:getPosition()
	if vpos.z ~= mpos.z or mpos:getDistance(vpos) > a.leashRange then
		despawn(cid, "vanish")
		return
	end
	local rec = NE.records[st.victim]
	-- the trait modifiers that act on a timer (Regenerating), as monster_tiers.lua's own tick does
	for _, key in ipairs(rec and K.modKeys(c, rec) or {}) do
		local mod = ChaosMods and ChaosMods[key]
		if mod and mod.onTick then
			pcall(mod.onTick, monster)
		end
	end
	-- Stalker: steps out of the shadows next to its victim
	if rec and K.hasTrait(rec, "stalker") and mpos:getDistance(vpos) > a.stalkerRange and nowMs() >= (st.nextStalk or 0) then
		st.nextStalk = nowMs() + a.stalkerEveryMs
		for _, p in ipairs(K.ringPositions({appear = {minDistance = 1, maxDistance = 2}}, vpos, rand)) do
			local pos = Position(p.x, p.y, p.z)
			local tile = Tile(pos)
			if tile and tile:getGround() and not tile:getTopCreature()
					and not tile:hasFlag(const("TILESTATE_PROTECTIONZONE", 0)) and try(function() return tile:isWalkable() end) ~= false then
				mpos:sendMagicEffect(const("CONST_ME_POFF", 3))
				monster:teleportTo(pos, true)
				pos:sendMagicEffect(const(c.look.appearEffect, 1))
				break
			end
		end
	end
	-- it hunts its victim, not bystanders
	local target = try(function() return monster:getTarget() end)
	if not target or (target:isPlayer() and not K.canHurt(st.victim, target:getGuid(), partyGuids(victim))) then
		pcall(function() monster:selectTarget(victim) end)
	end
	st.step = (st.step or 0) + 1
	if st.step % 2 == 0 then
		mpos:sendMagicEffect(const(c.look.pulseEffect, 1))
	end
	addEvent(tick, a.tickMs, cid)
end

-- the creature made for rec, set up as a nemesis; returns it or nil
local function setupMonster(monster, rec, player)
	local c = cfg()
	local cid = monster:getId()
	-- a script-made monster is never paced on its own (pace.lua onSpawn: artificial): pace it now, before the nemesis
	-- stats, so it takes the pace health and damage of its level like the type's natural spawns. Unpaced, a level 1000
	-- nemesis hit 2.5x harder than its own type (pace damage x0.40) and one-shot its victim (beta, 2026-10-21).
	if ChaosPace and ChaosPace.apply then
		pcall(ChaosPace.apply, monster, true)
	end
	local st = K.stats(c, rec, monster:getMaxHealth())
	monster:setMaxHealth(st.maxHealth)
	monster:setHealth(st.maxHealth)
	if st.speed ~= 0 then
		monster:changeSpeed(st.speed)
	end
	local outfit = monster:getOutfit()
	outfit.lookShader = c.look.shader
	pcall(function() monster:setOutfit(outfit) end)
	pcall(function() monster:setSkull(const(c.look.skull, 0)) end)
	installTier()
	if ChaosTierState then
		ChaosTierState[cid] = {tier = "nemesis", depth = (ChaosTierConfig and ChaosTierConfig.maxChain) or 99,
			mods = K.modKeys(c, rec), step = 0}
		monster:registerEvent("ChaosTierDeath")
		monster:registerEvent("ChaosModTaken")
	end
	monster:registerEvent("ChaosNemesisMonsterDeath")
	monster:registerEvent("ChaosNemesisTaken")
	NE.alive[cid] = {victim = rec.victim, pid = player:getId(), bornAt = nowMs(), step = 0}
	NE.byVictim[rec.victim] = cid
	pcall(function() monster:selectTarget(player) end)
	monster:getPosition():sendMagicEffect(const(c.look.appearEffect, 1))
	addEvent(tick, c.appear.tickMs, cid)
	return monster
end
NE.setupMonster = setupMonster

local function freeTile(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() or tile:getTopCreature() then
		return false
	end
	if tile:hasFlag(const("TILESTATE_PROTECTIONZONE", 0)) or try(function() return tile:getHouse() end) then
		return false
	end
	if Chaos.instanceAt and Chaos.instanceAt(pos) then
		return false
	end
	return try(function() return tile:isWalkable() end) ~= false
end

-- make the nemesis of this player appear now (the warning ran); returns the monster or nil
function NE.appear(pid)
	local player = Player(pid)
	if not player then
		return nil
	end
	local guid = player:getGuid()
	NE.pending[guid] = nil
	local rec = NE.records[guid]
	if not rec or NE.byVictim[guid] then
		return nil
	end
	if Chaos.inAnyInstance and Chaos.inAnyInstance(player) then
		return nil
	end
	local c = cfg()
	local shown = K.fullName(c, c.nameLang, rec, player:getName())
	local center = player:getPosition()
	local tries = 0
	for _, p in ipairs(K.ringPositions(c, center, rand)) do
		local pos = Position(p.x, p.y, p.z)
		if freeTile(pos) then
			tries = tries + 1
			local create = Chaos.createMonsterNamed or function(t, q, e, f) return Game.createMonster(t, q, e, f) end
			local monster = try(create, rec.monster, pos, false, false, shown)
			if monster then
				rec.appearances = (rec.appearances or 0) + 1
				rec.lastSeen = now()
				NE.lastAppear[guid] = now()
				saveRecord(rec)
				setupMonster(monster, rec, player)
				tell(player, "appear", shown)
				return monster
			end
			if tries >= 12 then
				break
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------------ birth and growth (the victim's death)
local function birthInfo(player, killer, mostDamageKiller)
	local k = killer or mostDamageKiller
	local info = {victimLevel = player:getLevel(), active = NE.records[player:getGuid()] and 1 or 0,
		serverActive = NE.serverActive, endedAt = getS(player, NE.S_ENDED)}
	info.pvp = creditOf(killer) ~= nil or creditOf(mostDamageKiller) ~= nil
	if k and k:isMonster() then
		local master = try(function() return k:getMaster() end)
		info.killer = {
			monster = true, master = master ~= nil, boss = isBossMonster(k), name = Chaos.monsterTypeName(k),
			shown = k:getName(), maxHealth = k:getMaxHealth(), nemesis = isNemesis(k),
			goblin = ChaosTreasureGoblin and ChaosTreasureGoblin.isGoblinName
				and try(ChaosTreasureGoblin.isGoblinName, Chaos.monsterTypeName(k)) or false
		}
	end
	info.instance = Chaos.inAnyInstance and Chaos.inAnyInstance(player) or nil
	return info, k
end
NE.birthInfo = birthInfo

local function feed(player, statKey)
	local A = ChaosAchievements
	local key = cfg().rewards.stats[statKey]
	if key and A and A.progress then
		pcall(A.progress, player, key, 1)
	end
end

function NE.onVictimDeath(player, killer, mostDamageKiller)
	local c = cfg()
	local guid = player:getGuid()
	local t = now()
	local k = killer or mostDamageKiller
	-- its own nemesis killed it again: it grows
	local st = k and NE.alive[k:getId()]
	if st and st.victim == guid then
		local rec = NE.records[guid]
		if rec and K.grow(c, rec, t, rand) then
			saveRecord(rec)
			tell(player, "grown", rec.name, K.fullName(c, langOf(player), rec, player:getName()))
		elseif rec then
			saveRecord(rec)
		end
		return "grown"
	end
	local info = birthInfo(player, killer, mostDamageKiller)
	local ok, why = K.rollBirth(c, info, t, rand)
	if not ok then
		return why
	end
	local rec = K.newRecord(c, {victim = guid, monster = info.killer.name, monsterLevel = monsterLevel(k),
		maxHealth = info.killer.maxHealth, hc = isHardcore(player)}, t, rand)
	if not insertRecord(rec) then
		return "db"
	end
	NE.records[guid] = rec
	NE.serverActive = NE.serverActive + 1
	player:registerEvent("ChaosNemesisKill")
	feed(player, "born")
	tell(player, "born", k:getName(), K.fullName(c, langOf(player), rec, player:getName()))
	return "born"
end

local death = CreatureEvent("ChaosNemesisDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if not cfg().enabled or not creature or not creature:isPlayer() then
		return true
	end
	local ok, err = pcall(NE.onVictimDeath, creature, killer, mostDamageKiller)
	if not ok then
		log("death: " .. tostring(err))
	end
	return true
end
death:register()

-- ------------------------------------------------------------------ the victim's kills call it
function NE.onVictimKill(player, target)
	local guid = player:getGuid()
	local rec = NE.records[guid]
	if not rec or not target or not target:isMonster() or isNemesis(target) then
		return false
	end
	if try(function() return target:getMaster() end) then
		return false
	end
	local c = cfg()
	local tile = Tile(player:getPosition())
	local kill = {name = Chaos.monsterTypeName(target), level = monsterLevel(target),
		instance = Chaos.inAnyInstance and Chaos.inAnyInstance(player) or nil,
		pz = tile and tile:hasFlag(const("TILESTATE_PROTECTIONZONE", 0)) or false}
	local st = {alive = NE.byVictim[guid] ~= nil, pending = NE.pending[guid], lastAppear = NE.lastAppear[guid]}
	if K.expired(c, rec, now()) or not K.appearRoll(c, rec, kill, st, now(), rand) then
		return false
	end
	NE.pending[guid] = true
	NE.lastAppear[guid] = now()
	tell(player, "warning")
	addEvent(NE.appear, c.appear.delayMs, player:getId())
	return true
end

local kill = CreatureEvent("ChaosNemesisKill")
function kill.onKill(player, target)
	if cfg().enabled and player and player:isPlayer() then
		local ok, err = pcall(NE.onVictimKill, player, target)
		if not ok then
			log("kill: " .. tostring(err))
		end
	end
	return true
end
kill:register()

-- ------------------------------------------------------------------ no griefing
-- on every player: a nemesis hurts only its victim and the victim's party
local guard = CreatureEvent("ChaosNemesisGuard")
function guard.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and creature and creature:isPlayer() then
		local st = NE.alive[attacker:getId()]
		if st and not K.canHurt(st.victim, creature:getGuid(), partyGuids(Player(st.pid))) then
			return 0, primaryType, 0, secondaryType
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
guard:register()

-- the same for mana (a mana shield takes the hit as mana)
local guardMana = CreatureEvent("ChaosNemesisGuardMana")
function guardMana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and creature and creature:isPlayer() then
		local st = NE.alive[attacker:getId()]
		if st and not K.canHurt(st.victim, creature:getGuid(), partyGuids(Player(st.pid))) then
			return 0, primaryType, 0, secondaryType
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
guardMana:register()

-- on the nemesis: only the victim and the victim's party (and their summons) hurt it
local taken = CreatureEvent("ChaosNemesisTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local st = creature and NE.alive[creature:getId()]
	local who = creditOf(attacker)
	if st and who and not K.canHurt(st.victim, who:getGuid(), partyGuids(Player(st.pid))) then
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- ------------------------------------------------------------------ the nemesis falls
local function giveTrophy(player, rec, slayerName)
	local c = cfg()
	local tc = c.rewards.trophy
	local item = try(Game.createItem, tc.id, 1)
	if not item then
		return false
	end
	local victimName = player:getName()
	local engraved = K.fullName(c, langOf(player), rec, victimName)
	pcall(function()
		if ITEM_ATTRIBUTE_NAME then
			item:setAttribute(ITEM_ATTRIBUTE_NAME, tc.name)
		end
		if ITEM_ATTRIBUTE_ARTICLE then
			item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, tc.article)
		end
		if ITEM_ATTRIBUTE_DESCRIPTION then
			item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, tr(player, "trophyDesc", engraved, slayerName))
		end
	end)
	pcall(function()
		item:setCustomAttribute(tc.nameAttr, engraved)
		item:setCustomAttribute(tc.ownerAttr, player:getGuid())
		item:setCustomAttribute(tc.storebound, 1)
		item:setCustomAttribute(tc.lock, 1)
	end)
	local NOERR = const("RETURNVALUE_NOERROR", 0)
	if player:addItemEx(item, false) == NOERR then
		return true
	end
	local inbox = try(function() return player:getInbox() end)
	if inbox and inbox:addItemEx(item, const("INDEX_WHEREEVER", -1), const("FLAG_NOLIMIT", 1)) == NOERR then
		return true
	end
	return false
end
NE.giveTrophy = giveTrophy

local function hasBoard(key)
	local lc = Chaos.leaderboardConfig
	for _, b in ipairs(lc and lc.boards or {}) do
		if b.key == key then
			return true
		end
	end
	return false
end

local function refreshPlate(player)
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
end

-- the end of a record (slain): row, caches, the victim's kill event and cooldown
local function endRecord(rec, victim)
	rec.rewarded = true
	deleteRecord(rec)
	NE.records[rec.victim] = nil
	NE.pending[rec.victim] = nil
	if victim then
		setS(victim, NE.S_ENDED, now())
		pcall(function() victim:unregisterEvent("ChaosNemesisKill") end)
	end
end

function NE.onNemesisDeath(creature, corpse, killer, mostDamageKiller)
	local cid = creature:getId()
	local st = NE.alive[cid]
	if not st then
		return "unknown"
	end
	NE.alive[cid] = nil
	NE.byVictim[st.victim] = nil
	local rec = NE.records[st.victim]
	local victim = Player(st.pid)
	if not rec or rec.rewarded or not victim then
		return "gone"
	end
	local c = cfg()
	local t = now()
	local slayer = creditOf(mostDamageKiller) or creditOf(killer)
	if not slayer then
		-- killed by the world (a field, another monster): no revenge, it comes back another time
		return "no slayer"
	end
	local isVictim = slayer:getGuid() == rec.victim
	local inParty = isVictim or K.canHurt(rec.victim, slayer:getGuid(), partyGuids(victim))
	local r = K.reward(c, rec, {guid = slayer:getGuid(), account = slayer:getAccountId(), ip = slayer:getIp(),
		isVictim = isVictim, inParty = inParty, hc = isHardcore(slayer), lastBounty = getS(slayer, NE.S_BOUNTY),
		lastAvenge = getS(slayer, NE.S_AVENGE)}, {guid = rec.victim, account = victim:getAccountId(), ip = victim:getIp()}, t)
	local shown = creature:getName()
	endRecord(rec, victim)
	if r.kind == "avenge" then
		setS(victim, NE.S_AVENGED, getS(victim, NE.S_AVENGED) + 1)
		tell(victim, "avenged", shown)
		if r.trophy then
			if giveTrophy(victim, rec, victim:getName()) then
				setS(victim, NE.S_TROPHIES, getS(victim, NE.S_TROPHIES) + 1)
				tell(victim, "trophy")
			else
				tell(victim, "trophyLost")
			end
		end
		if r.gold > 0 and corpse and corpse.addItem then
			for _, coin in ipairs(K.coins(r.gold)) do
				pcall(function() corpse:addItem(coin.id, coin.count) end)
			end
			setS(victim, NE.S_AVENGE, t)
			tell(victim, "lootBonus")
		end
		feed(victim, "avenged")
		local lb = c.rewards.leaderboard
		if lb and ChaosLeaderboard and ChaosLeaderboard.record and hasBoard(lb.board) then
			pcall(ChaosLeaderboard.record, lb.board, victim, 1, lb.mode)
		end
		refreshPlate(victim)
	elseif r.kind == "hunt" then
		setS(slayer, NE.S_HUNTED, getS(slayer, NE.S_HUNTED) + 1)
		if r.gold > 0 then
			slayer:setBankBalance(slayer:getBankBalance() + r.gold)
			setS(slayer, NE.S_BOUNTY, t)
			tell(slayer, "hunted", slayer:getName(), shown, r.gold)
		else
			tell(slayer, "noBounty")
		end
		tell(victim, "huntedVictim", slayer:getName(), shown)
		feed(slayer, "hunted")
		refreshPlate(slayer)
	end
	NE.sendState(victim)
	return r.kind, r
end

local nemesisDeath = CreatureEvent("ChaosNemesisMonsterDeath")
function nemesisDeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local ok, err = pcall(NE.onNemesisDeath, creature, corpse, killer, mostDamageKiller)
	if not ok then
		log("nemesis death: " .. tostring(err))
	end
	return true
end
nemesisDeath:register()

-- ------------------------------------------------------------------ titles (titles.lua registry)
function NE.registerTitles()
	if not (ChaosTitles and ChaosTitles.register) then
		return false
	end
	ChaosTitles.register("nemesis", function(player)
		local cn = counters(player)
		return K.titles(cfg(), cn.avenged, cn.hunted)
	end)
	return true
end
NE.registerTitles()

-- ------------------------------------------------------------------ login, logout, startup
local login = CreatureEvent("ChaosNemesisLogin")
function login.onLogin(player)
	player:registerEvent("ChaosNemesisDeath")
	player:registerEvent("ChaosNemesisGuard")
	player:registerEvent("ChaosNemesisGuardMana")
	player:registerEvent("ChaosNemesisExtended")
	player:registerEvent("ChaosNemesisLogout")
	if not cfg().enabled then
		return true
	end
	local guid = player:getGuid()
	local ok, err = pcall(function()
		local rec = loadRecord(guid)
		if rec and K.expired(cfg(), rec, now()) then
			deleteRecord(rec)
			setS(player, NE.S_ENDED, now())
			tell(player, "expired", rec.name)
			rec = nil
		end
		NE.records[guid] = rec
		if rec then
			player:registerEvent("ChaosNemesisKill")
		end
	end)
	if not ok then
		log("login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosNemesisLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	local cid = NE.byVictim[guid]
	if cid then
		despawn(cid)
	end
	NE.records[guid], NE.pending[guid], NE.lastAppear[guid] = nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosNemesisStartup")
function startup.onStartup()
	if ensureTable() then
		pcall(db.query, K.sqlExpire(cfg(), T(), now()))
		NE.countActive()
	end
	NE.registerTitles()
	installTier()
	return true
end
startup:type("startup")
startup:register()

-- every hour: expired rows go, the server-wide count is read again
local hourly = GlobalEvent("ChaosNemesisHourly")
function hourly.onThink(interval)
	if ensureTable() then
		pcall(db.query, K.sqlExpire(cfg(), T(), now()))
		NE.countActive()
	end
	NE.registerTitles()
	return true
end
hourly:interval(3600000)
hourly:register()

-- ------------------------------------------------------------------ opcode
local ext = CreatureEvent("ChaosNemesisExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "get" or Chaos.limited(player, "nemesis.get", cfg().rateLimitMs) then
		return
	end
	NE.sendState(player)
end
ext:register()
