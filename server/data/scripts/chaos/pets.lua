-- Pets (client game_pets, extended opcode ChaosOpcodes.pets). Numbers and species: pets_config.lua. Pure logic:
-- pets_core.lua (tests: server/tests/pets_test.lua). Table chaos_pets (server/sql/chaos_pets.sql; created at startup).
-- Overview and numbers: server/README.md "Pets".
--
-- A pet is a small companion that cannot fight and cannot be fought: one out at a time, it follows its owner as the
-- owner's summon (monster types in data/monster/monsters/chaos/pets/: not attackable, no attacks, passable: players and
-- monsters walk through it, server/src-patches), levels
-- from the owner's kills and has two small abilities (pets_config.lua `abilities`). Everything it does is done here:
--   think (cfg.thinkMs)   leash, rest (protection zone, banned zone, other summons), Mend, Ward, Spark Aura
--   kill event            pet XP; pet drops (rolled for every kill of the character, pet out or not)
--   onDropLoot 2          Gold Sniffer (more coins in the corpse)        } corpses the owner owns
--   onDropLoot 2.45       Fetch (coins of corpses near the pet -> bank)  } (hunt tracker reads at 1.9 / 2.4)
--   loot.lua              Treasure Sense: ChaosPets.itemFind(player) is added to the item find of the Chaos loot layer
--   healthchange          Ward: less damage from monsters while it lasts
--   death                 the pet flees: dismissed, cfg.deathCooldown before it can be called again
--   login / logout        rows loaded / saved; the pet that was out at logout comes back after the login
-- Class companions (Beastmaster wolves, Necromancer minions) count only their own monster types, so a pet never lowers
-- their caps. Any other summon of the owner (stock summon spells, Moonfang Pack, the base server's familiars) makes the
-- pet rest while it is out, so the stock limit of two summons is never reduced by a pet.
--
-- Obtaining: drops (pets_core K.rollDrop), the store (offer kind "unlock", shop_services.lua asks ChaosPets.storeUnlock),
-- boss drops (source.boss: exclusives.lua unlocks the pet for the account and calls ChaosPets.grant on its characters),
-- achievements (account-wide, checked at login, when the window opens and every flush; a season character only gets
-- the pets of achievements it earned itself). A second copy of an owned species becomes cfg.duplicateXp pet XP.
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.pets:
--   client -> server  open | get | close | summon {species} | dismiss | rename {species, name}
--   server -> client  state {open, pets = [K.view + {canSummon}], active, out, rest, zone, cooldowns = {summon, death,
--                     rename}, catalog = [{key, name, look, how, owned, abilities = [name]}], maxLevel, secondAt}
--                     xp {species, level, xp, into, need, pct}    (after a kill while the window is open)
-- Commands: !pet [summon <name>|dismiss|rename <name>|list]; staff: /pet give <species>[, character] | xp <n> | level <n>
--           | reset | species
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
dofile("data/scripts/chaos/pets_core.lua")

ChaosPetsConfig = dofile("data/scripts/chaos/pets_config.lua")
ChaosPets = ChaosPets or {}
local P = ChaosPets
local K = ChaosPetsCore
local cfg = ChaosPetsConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.pets) or 254
local TABLE = cfg.tables.pets

P.rows = P.rows or {} -- guid -> {[species] = row}; row = {id, species, name, xp, active, source, obtained, dirty}
P.live = P.live or {} -- player id -> live state of the pet that is out (see callOut)
P.cool = P.cool or {} -- guid -> {summon, death, rename} (os.time when ready; kept over a relog)
P.window = P.window or {} -- player id -> true while the window is open
P.killed = P.killed or {} -- "<player id>:<monster id>" -> true (the kill event may run twice for one kill)

local COINS = {[2148] = 1, [2152] = 100, [2160] = 10000}
local COIN_ID = {crystal = 2160, platinum = 2152, gold = 2148}
local ELEMENT = {
	fire = {COMBAT_FIREDAMAGE, CONST_ME_FIREATTACK},
	ice = {COMBAT_ICEDAMAGE, CONST_ME_ICEATTACK},
	death = {COMBAT_DEATHDAMAGE, CONST_ME_MORTAREA},
	holy = {COMBAT_HOLYDAMAGE, CONST_ME_HOLYDAMAGE},
	earth = {COMBAT_EARTHDAMAGE, CONST_ME_SMALLPLANTS},
	energy = {COMBAT_ENERGYDAMAGE, CONST_ME_ENERGYHIT},
	physical = {COMBAT_PHYSICALDAMAGE, CONST_ME_HITAREA}
}

local function log(text)
	print("[ChaosPets] " .. text)
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ---------------------------------------------------------------- database
local tableReady = false
local function ensureTable()
	if tableReady then
		return true
	end
	tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. TABLE .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, " ..
		"`player_id` int(11) NOT NULL, `species` varchar(32) NOT NULL, `name` varchar(32) NOT NULL DEFAULT '', " ..
		"`xp` int(10) unsigned NOT NULL DEFAULT 0, `active` tinyint(1) NOT NULL DEFAULT 0, " ..
		"`source` varchar(16) NOT NULL DEFAULT '', `obtained_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`id`), UNIQUE KEY `player_species` (`player_id`, `species`)) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true
	return tableReady
end

local function loadRows(guid)
	ensureTable()
	local rows = {}
	local list = Chaos.select(string.format("SELECT `id`, `species`, `name`, `xp`, `active`, `source`, `obtained_at` " ..
		"FROM `%s` WHERE `player_id` = %d", TABLE, guid), {{"id", "n"}, {"species", "s"}, {"name", "s"}, {"xp", "n"},
		{"active", "n"}, {"source", "s"}, {"obtained_at", "n"}})
	for _, r in ipairs(list) do
		r.xp = K.capXp(r.xp, cfg)
		r.obtained = r.obtained_at
		rows[r.species] = r
	end
	P.rows[guid] = rows
	return rows
end

local function rowsOf(player)
	local guid = player:getGuid()
	return P.rows[guid] or loadRows(guid)
end

local function saveRow(guid, row)
	db.query(string.format("UPDATE `%s` SET `name` = %s, `xp` = %d, `active` = %d WHERE `player_id` = %d AND `species` = %s",
		TABLE, db.escapeString(row.name or ""), K.capXp(row.xp, cfg), row.active == 1 and 1 or 0, guid,
		db.escapeString(row.species)))
	row.dirty = nil
end

local function flush(guid)
	for _, row in pairs(P.rows[guid] or {}) do
		if row.dirty then
			saveRow(guid, row)
		end
	end
end

local function coolOf(guid)
	local c = P.cool[guid]
	if not c then
		c = {summon = 0, death = 0, rename = 0}
		P.cool[guid] = c
	end
	return c
end

-- ---------------------------------------------------------------- helpers
local function activeRow(player)
	for _, row in pairs(rowsOf(player)) do
		if row.active == 1 then
			return row
		end
	end
	return nil
end

local function displayName(row, species)
	return (row.name and row.name ~= "") and row.name or species.name
end

local function petCreature(player)
	local live = P.live[player:getId()]
	local c = live and live.cid and Creature(live.cid)
	if c and not c:isRemoved() then
		return c, live
	end
	return nil, live
end

-- monster type names that are class companions (they never make the pet rest)
local classNames
local function isClassSummon(name)
	if not classNames then
		classNames = {}
		for _, n in ipairs(cfg.classSummons or {}) do
			classNames[n:lower()] = true
		end
		for _, n in ipairs(Chaos.classes and Chaos.classes.companion and Chaos.classes.companion.monsters or {}) do
			classNames[n:lower()] = true
		end
		for _, m in pairs(ChaosNecroConfig and ChaosNecroConfig.minions or {}) do
			if type(m) == "table" and m.monster then
				classNames[m.monster:lower()] = true
			end
		end
	end
	return classNames[(name or ""):lower()] == true
end

local function otherSummons(player, pet)
	for _, s in ipairs(player:getSummons() or {}) do
		if s ~= pet and not (pet and s:getId() == pet:getId()) and not isClassSummon(s:getName()) then
			return true
		end
	end
	return false
end

local function inPz(pos)
	local tile = Tile(pos)
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

-- the zone flags of pets_core K.zoneRule for a player
local function zoneFlags(player)
	local pos = player:getPosition()
	local f = {}
	local function try(key, fn)
		local ok, v = pcall(fn)
		if ok and v then
			f[key] = true
		end
	end
	try("arena", function() return ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) end)
	try("siege", function() return ChaosSiege and ChaosSiege.locate and ChaosSiege.locate(pos) ~= nil end)
	try("pvpZone", function()
		local tile = Tile(pos)
		return TILESTATE_PVPZONE and tile and tile:hasFlag(TILESTATE_PVPZONE)
	end)
	try("rift", function() return ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player) end)
	try("worldBoss", function()
		return ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.layout and ChaosWorldBoss.inside(pos)
	end)
	try("tower", function() return ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player) end)
	try("dungeon", function() return ChaosDungeonIsInside and ChaosDungeonIsInside(player) end)
	return f
end

local ZONE_NAMES = {arena = "the arena", siege = "the siege", pvpZone = "a PvP zone", rift = "a rift",
	worldBoss = "the world boss arena", tower = "the Infinity Tower", dungeon = "a dungeon"}

local function inPvp(player)
	local ok, v = pcall(function() return ChaosHealing and ChaosHealing.inPvp and ChaosHealing.inPvp(player) end)
	return ok and v and true or false
end

-- a free walkable tile next to `pos` outside protection zones, or nil
local function freeSpot(pos)
	local order = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1}}
	for _, d in ipairs(order) do
		local p = Position(pos.x + d[1], pos.y + d[2], pos.z)
		local tile = Tile(p)
		if tile and tile:getGround() and not tile:getTopCreature() and not tile:hasFlag(TILESTATE_PROTECTIONZONE)
				and not tile:hasProperty(CONST_PROP_BLOCKSOLID) and not tile:hasProperty(CONST_PROP_IMMOVABLEBLOCKSOLID)
				and not (TILESTATE_FLOORCHANGE and tile:hasFlag(TILESTATE_FLOORCHANGE))
				and not (TILESTATE_TELEPORT and tile:hasFlag(TILESTATE_TELEPORT)) then
			return p
		end
	end
	return nil
end

local function send(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

-- ---------------------------------------------------------------- the creature
local function despawn(player, effect)
	local pet, live = petCreature(player)
	if pet then
		if effect ~= false then
			pet:getPosition():sendMagicEffect(CONST_ME_POFF)
		end
		pet:remove()
	end
	if live then
		live.cid = nil
	end
end

local function spawn(player, live)
	local species = K.species(live.species, cfg)
	local row = rowsOf(player)[live.species]
	if not species or not row then
		return nil
	end
	local spot = freeSpot(player:getPosition())
	if not spot then
		return nil
	end
	local pet = Game.createMonster(species.monster, spot, false, false)
	if not pet then
		return nil
	end
	if ChaosSummonsCore then
		ChaosSummonsCore.bind(player, pet)
	else
		pet:setMaster(player)
	end
	pcall(function()
		local name = displayName(row, species)
		pet:rename(name, string.format("%s, the %s of %s", name, species.name:lower(), player:getName()))
	end)
	spot:sendMagicEffect(CONST_ME_MAGIC_BLUE)
	live.cid = pet:getId()
	return pet
end

-- ---------------------------------------------------------------- state for the window
function P.stateOf(player, open)
	local rows = rowsOf(player)
	local guid = player:getGuid()
	local live = P.live[player:getId()]
	local level = player:getLevel()
	local t = os.time()
	local cool = coolOf(guid)
	local pets = {}
	for _, row in pairs(rows) do
		local v = K.view(row, level, t, cfg)
		if v then
			pets[#pets + 1] = v
		end
	end
	table.sort(pets, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.speciesName < b.speciesName
	end)
	local catalog = {}
	for _, s in ipairs(cfg.species) do
		local names = {}
		for _, a in ipairs(s.abilities) do
			names[#names + 1] = cfg.abilities[a].name
		end
		catalog[#catalog + 1] = {key = s.key, name = s.name, look = s.look, how = s.how, owned = rows[s.key] ~= nil,
			abilities = names}
	end
	local rule, zone = K.zoneRule(zoneFlags(player), cfg)
	return {
		open = open and 1 or nil, pets = pets, catalog = catalog, active = live and live.species or nil,
		out = live and live.cid ~= nil and Creature(live.cid) ~= nil or false,
		rest = live and live.rest and K.restText(live.rest) or nil,
		zone = rule ~= "full" and (rule .. (zone and (" (" .. (ZONE_NAMES[zone] or zone) .. ")") or "")) or nil,
		cooldowns = {summon = K.cooldownLeft(cool.summon, t), death = K.cooldownLeft(cool.death, t),
			rename = K.cooldownLeft(cool.rename, t)},
		maxLevel = cfg.maxLevel, secondAt = cfg.secondAt
	}
end

function P.sendState(player, open)
	if open then
		P.window[player:getId()] = true
	end
	send(player, "state", P.stateOf(player, open))
end

local function refresh(player)
	if P.window[player:getId()] then
		P.sendState(player, false)
	end
end

-- ---------------------------------------------------------------- XP
function P.addXp(player, key, amount, quiet)
	local row = rowsOf(player)[key]
	if not row or amount <= 0 then
		return false
	end
	local species = K.species(key, cfg)
	local before = K.levelOf(row.xp, cfg)
	row.xp = K.capXp(row.xp + amount, cfg)
	row.dirty = true
	local after, into, need, pct = K.levelOf(row.xp, cfg)
	if after > before and species then
		local name = displayName(row, species)
		local text = string.format("%s reached level %d.", name, after)
		if before < cfg.secondAt and after >= cfg.secondAt then
			local second = cfg.abilities[species.abilities[2]]
			text = text .. string.format(" New ability: %s.", second and second.name or "?")
		end
		if not quiet then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
		local pet = petCreature(player)
		if pet then
			pet:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
		end
		saveRow(player:getGuid(), row)
		refresh(player)
	elseif P.window[player:getId()] then
		send(player, "xp", {species = key, level = after, xp = row.xp, into = into, need = need, pct = pct})
	end
	return true
end

-- ---------------------------------------------------------------- obtaining
-- does the character have the pet `key` (exclusives.lua: a boss pet is given to every character of the account)
function P.owns(player, key)
	return rowsOf(player)[key or ""] ~= nil
end

-- give `key` to the player (source: "drop", "store", "achievement", "boss", "staff"); a duplicate becomes pet XP
function P.grant(player, key, source, quiet)
	local species = K.species(key, cfg)
	if not species then
		return false, "Unknown pet."
	end
	local rows = rowsOf(player)
	local guid = player:getGuid()
	if K.grantKind(rows, key) == "xp" then
		P.addXp(player, key, cfg.duplicateXp, quiet)
		if not quiet then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Another %s! Yours gains %d pet experience.",
				species.name, cfg.duplicateXp))
		end
		return true, "xp"
	end
	ensureTable()
	local t = os.time()
	if not db.query(string.format("INSERT IGNORE INTO `%s` (`player_id`, `species`, `source`, `obtained_at`) VALUES " ..
			"(%d, %s, %s, %d)", TABLE, guid, db.escapeString(key), db.escapeString(source or ""), t)) then
		return false, "Could not save the pet. Try again."
	end
	local got = Chaos.select(string.format("SELECT `id`, `xp`, `name`, `active` FROM `%s` WHERE `player_id` = %d AND " ..
		"`species` = %s", TABLE, guid, db.escapeString(key)), {{"id", "n"}, {"xp", "n"}, {"name", "s"}, {"active", "n"}})[1]
	if not got then
		return false, "Could not save the pet. Try again."
	end
	rows[key] = {id = got.id, species = key, name = got.name, xp = K.capXp(got.xp, cfg), active = got.active,
		source = source or "", obtained = t}
	if not quiet then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "New pet: %s! Open Character > Pets to call it.",
			species.name))
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_BLUE or CONST_ME_MAGIC_BLUE)
	end
	refresh(player)
	return true, "new"
end

local function hasAchievement(player, id)
	local A = ChaosAchievements
	if not (A and A.has) then
		return false
	end
	-- a season character only gets the pets of achievements it earned itself
	local seasonal = false
	pcall(function() seasonal = ChaosSeason and ChaosSeason.realmOf and ChaosSeason.realmOf(player) > 0 end)
	if seasonal then
		local own = A.unlockedOf and A.unlockedOf(player) or {}
		return own[id] ~= nil
	end
	local ok, v = pcall(A.has, player, id)
	return ok and v and true or false
end

-- achievement pets the character does not have yet (quiet: no message, e.g. old achievements at the first login)
function P.checkAchievements(player, quiet)
	local rows = rowsOf(player)
	for _, s in ipairs(cfg.species) do
		local id = s.source and s.source.achievement
		if id and not rows[s.key] and hasAchievement(player, id) then
			P.grant(player, s.key, "achievement", quiet)
		end
	end
end

-- the store: an entry for an offer {kind = "unlock", unlock = <cfg.store key>} (shop_services.lua unlockEntry)
function P.storeUnlock(unlockName)
	local key = cfg.store[unlockName or ""]
	local species = key and K.species(key, cfg)
	if not species then
		return nil
	end
	return {
		name = "the pet " .. species.name,
		done = "Call it in Character > Pets.",
		owned = function(player)
			return rowsOf(player)[key] ~= nil
		end,
		grant = function(player)
			local ok, err = P.grant(player, key, "store", true)
			return ok, err
		end
	}
end

-- ---------------------------------------------------------------- summon / dismiss / rename
function P.callOut(player, key, silent)
	local rows = rowsOf(player)
	local row = rows[key]
	local guid = player:getGuid()
	local cool = coolOf(guid)
	local t = os.time()
	local rule, zone = K.zoneRule(zoneFlags(player), cfg)
	if not silent then
		local err = K.summonError({owned = row ~= nil, now = t, summonReady = cool.summon, deathReady = cool.death,
			zone = rule, zoneName = zone and ZONE_NAMES[zone]}, cfg)
		if err then
			return false, err
		end
	elseif not row then
		return false, "You do not own that pet."
	end
	despawn(player)
	for _, r in pairs(rows) do
		if r.active == 1 and r ~= row then
			r.active = 0
			saveRow(guid, r)
		end
	end
	row.active = 1
	saveRow(guid, row)
	cool.summon = t + cfg.summonCooldown
	P.live[player:getId()] = {species = key, nextMend = 0, nextWard = 0, wardUntil = 0, nextAura = 0}
	P.think(player)
	refresh(player)
	return true
end

function P.dismiss(player, reason)
	local row = activeRow(player)
	despawn(player)
	P.live[player:getId()] = nil
	if row then
		row.active = 0
		saveRow(player:getGuid(), row)
	end
	if reason ~= "death" and reason ~= "silent" then
		coolOf(player:getGuid()).summon = os.time() + cfg.summonCooldown
	end
	refresh(player)
	return row ~= nil
end

local function reservedName(name)
	local ok, mt = pcall(MonsterType, name)
	return ok and mt ~= nil
end

function P.rename(player, key, raw)
	local row = rowsOf(player)[key or ""]
	if not row then
		return false, "You do not own that pet."
	end
	local cool = coolOf(player:getGuid())
	local left = K.cooldownLeft(cool.rename, os.time())
	if left > 0 then
		return false, string.format("Wait %d s before renaming again.", left)
	end
	local name, why = K.validName(raw, cfg, reservedName)
	if not name then
		return false, why
	end
	row.name = name
	saveRow(player:getGuid(), row)
	cool.rename = os.time() + cfg.renameCooldown
	local pet, live = petCreature(player)
	if pet and live and live.species == key then
		local species = K.species(key, cfg)
		pcall(function()
			pet:rename(name, string.format("%s, the %s of %s", name, species.name:lower(), player:getName()))
		end)
		-- the client only learns a creature's name when it appears: show it again under its new name
		despawn(player, false)
	end
	refresh(player)
	return true, name
end

-- ---------------------------------------------------------------- abilities
local function abilityOn(live, key, rule, pvp)
	local row = live.row
	local species = live.speciesEntry
	if not row or not species or not K.hasAbility(species, key, live.level, cfg) then
		return false
	end
	return K.abilityActive(cfg.abilities[key].kind, rule, pvp)
end

-- monsters around `center` (no summons) that target the owner; withTarget: also the owner's own target
local function threatsOf(owner, center, radius, withTarget)
	local list = {}
	local ok, specs = pcall(Game.getSpectators, center, false, false, radius, radius, radius, radius)
	if not ok or type(specs) ~= "table" then
		return list
	end
	for _, c in ipairs(specs) do
		if c:isMonster() and not c:getMaster() and c:getHealth() > 0 then
			local target = c:getTarget()
			local ownTarget = withTarget and owner:getTarget()
			if (target and target:getId() == owner:getId()) or (ownTarget and ownTarget:getId() == c:getId()) then
				list[#list + 1] = {pos = c:getPosition(), creature = c}
			end
		end
	end
	return list
end

local function runAbilities(player, live, pet, rule, pvp, ms)
	local hp, maxHp = player:getHealth(), player:getMaxHealth()
	local pct = maxHp > 0 and hp * 100 / maxHp or 100
	local level = live.level
	if abilityOn(live, "mend", rule, pvp) and ms >= live.nextMend and pct < cfg.abilities.mend.below and hp > 0 then
		local healed = Chaos.heal(player, K.mendAmount(level, maxHp, cfg))
		if healed > 0 then
			live.nextMend = ms + cfg.abilities.mend.cooldown * 1000
			player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
			-- the shown amount in the player's display scale (display_scale_core.lua)
			local shown = ChaosDisplayScale and ChaosDisplayScale.scale(healed, ChaosDisplayScale.forPlayer(player)) or healed
			player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, Chaos.t(player, "Your pet mends you (+%.0f).", shown))
		end
	end
	if abilityOn(live, "ward", rule, pvp) and ms >= live.nextWard and pct < cfg.abilities.ward.below and hp > 0 then
		live.nextWard = ms + cfg.abilities.ward.cooldown * 1000
		live.wardUntil = ms + cfg.abilities.ward.duration * 1000
		live.wardPct = K.abilityValue("ward", level, player:getLevel(), cfg)
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
		player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR,
			Chaos.t(player, "Your pet wards you: %s%% less damage from monsters.", K.number(live.wardPct)))
	end
	if pet and abilityOn(live, "aura", rule, pvp) and ms >= live.nextAura then
		local a = cfg.abilities.aura
		local lo, hi = K.auraDamage(player:getLevel(), level, cfg)
		local el = ELEMENT[live.speciesEntry.element] or ELEMENT.physical
		local hits = 0
		for _, t in ipairs(threatsOf(player, pet:getPosition(), 1, true)) do
			if hits >= a.targets then
				break
			end
			local ok, err = pcall(doTargetCombat, player, t.creature, el[1], -lo, -hi, el[2], ORIGIN_NONE)
			if not ok then
				log("aura: " .. tostring(err))
			end
			hits = hits + 1
		end
		if hits > 0 then
			live.nextAura = ms + a.interval * 1000
		end
	end
end

-- ---------------------------------------------------------------- think
function P.think(player)
	local live = P.live[player:getId()]
	if not live then
		return
	end
	local row = rowsOf(player)[live.species]
	local species = K.species(live.species, cfg)
	if not row or not species or row.active ~= 1 then
		P.live[player:getId()] = nil
		despawn(player)
		return
	end
	live.row, live.speciesEntry, live.level = row, species, (K.levelOf(row.xp, cfg))
	local ms = nowMs()
	local pet = petCreature(player)
	local opos = player:getPosition()
	local rule, zone = K.zoneRule(zoneFlags(player), cfg)
	local reason = K.restReason({inPz = inPz(opos), zone = rule, otherSummons = otherSummons(player, pet)})
	if reason then
		if pet then
			despawn(player)
			pet = nil
		end
		if live.rest ~= reason then
			live.rest = reason
			local text = reason == "zone" and ("Pets are not allowed in " .. (ZONE_NAMES[zone] or "this place") ..
				"; yours waits until you leave.") or K.restText(reason)
			if text then
				player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, text)
			end
			refresh(player)
		end
	else
		if live.rest then
			live.rest = nil
			refresh(player)
		end
		if not pet then
			pet = spawn(player, live)
		elseif K.distance(pet:getPosition(), opos) > cfg.leashRange then
			local spot = freeSpot(opos)
			if spot then
				pet:teleportTo(spot, true)
			else
				despawn(player, false)
				pet = nil
			end
		end
	end
	runAbilities(player, live, pet, rule, inPvp(player), ms)
end

-- ---------------------------------------------------------------- ability hooks for other scripts
local function utilityValue(player, key)
	local live = player and P.live[player:getId()]
	if not live or not live.speciesEntry or not live.row then
		return 0
	end
	local rule = K.zoneRule(zoneFlags(player), cfg)
	if not K.hasAbility(live.speciesEntry, key, live.level, cfg) or not K.abilityActive("utility", rule, false) then
		return 0
	end
	return K.abilityValue(key, live.level, player:getLevel(), cfg)
end

-- item find percent of the pet (loot.lua adds it to the Chaos loot layer's item find)
function P.itemFind(player)
	return utilityValue(player, "itemFind")
end

local function corpseCoins(corpse)
	local value, items = 0, {}
	for _, item in ipairs(corpse:getItems() or {}) do
		local unit = COINS[item:getId()]
		if unit then
			value = value + unit * item:getCount()
			items[#items + 1] = item
		end
	end
	return value, items
end

local function addCoins(corpse, value)
	local c = K.coins(value)
	for kind, id in pairs(COIN_ID) do
		local n = c[kind]
		while n > 0 do
			local take = math.min(n, 100)
			corpse:addItem(id, take)
			n = n - take
		end
	end
end

local goldCb = EventCallback
goldCb.onDropLoot = function(monster, corpse)
	local ok, err = pcall(function()
		if not corpse or not corpse:getType():isContainer() then
			return
		end
		local owner = Player(corpse:getCorpseOwner())
		local pct = owner and utilityValue(owner, "goldFind") or 0
		if pct <= 0 then
			return
		end
		local value = corpseCoins(corpse)
		local extra = K.goldBonus(value, pct)
		if extra > 0 then
			addCoins(corpse, extra)
		end
	end)
	if not ok then
		log("gold find: " .. tostring(err))
	end
end
goldCb:register(2)

local fetchCb = EventCallback
fetchCb.onDropLoot = function(monster, corpse)
	local ok, err = pcall(function()
		if not corpse or not corpse:getType():isContainer() then
			return
		end
		local owner = Player(corpse:getCorpseOwner())
		local range = owner and utilityValue(owner, "fetch") or 0
		if range <= 0 then
			return
		end
		local pet = petCreature(owner)
		local from = pet and pet:getPosition() or owner:getPosition()
		if K.distance(from, corpse:getPosition()) > range then
			return
		end
		local value, items = corpseCoins(corpse)
		if value <= 0 then
			return
		end
		for _, item in ipairs(items) do
			item:remove()
		end
		owner:setBankBalance(owner:getBankBalance() + value)
		if pet then
			pet:getPosition():sendDistanceEffect(corpse:getPosition(), CONST_ANI_SMALLHOLY or 0)
		end
		owner:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR,
			Chaos.t(owner, "Your pet fetched %d gold to your bank.", value))
	end)
	if not ok then
		log("fetch: " .. tostring(err))
	end
end
fetchCb:register(2.45)

-- ---------------------------------------------------------------- events
local function afterLogin(cid)
	local player = Player(cid)
	if not player then
		return
	end
	local ok, err = pcall(function()
		P.checkAchievements(player, false)
		local row = activeRow(player)
		if row and not P.live[player:getId()] then
			P.callOut(player, row.species, true)
		end
	end)
	if not ok then
		log("login: " .. tostring(err))
	end
end

local login = CreatureEvent("ChaosPetsLogin")
function login.onLogin(player)
	for _, e in ipairs({"ChaosPetsLogout", "ChaosPetsDeath", "ChaosPetsKill", "ChaosPetsWard", "ChaosPetsExtended"}) do
		player:registerEvent(e)
	end
	local ok, err = pcall(loadRows, player:getGuid())
	if not ok then
		log("load " .. player:getName() .. ": " .. tostring(err))
		return true
	end
	addEvent(afterLogin, 2000, player:getId())
	return true
end
login:register()

local logout = CreatureEvent("ChaosPetsLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	pcall(flush, guid)
	despawn(player, false)
	P.live[player:getId()], P.window[player:getId()] = nil, nil
	P.rows[guid] = nil
	return true
end
logout:register()

local death = CreatureEvent("ChaosPetsDeath")
function death.onDeath(creature)
	local player = creature:getPlayer()
	if player and P.live[player:getId()] then
		pcall(function()
			flush(player:getGuid())
			P.dismiss(player, "death")
			coolOf(player:getGuid()).death = os.time() + cfg.deathCooldown
		end)
	end
	return true
end
death:register()

local kill = CreatureEvent("ChaosPetsKill")
function kill.onKill(player, target)
	if not player:isPlayer() or not target or not target:isMonster() or target:getMaster() then
		return true
	end
	local key = player:getId() .. ":" .. target:getId()
	if P.killed[key] then
		return true
	end
	P.killed[key] = true
	local ok, err = pcall(function()
		local mType = target:getType()
		local exp = mType and mType:experience() or 0
		if exp <= 0 then
			return
		end
		local tier = ChaosTierOf and ChaosTierOf(target) or "normal"
		local info = {tier = tier, monsterExp = exp, ownerLevel = player:getLevel()}
		local xp = K.killXp(info, cfg)
		local live = P.live[player:getId()]
		if live and xp > 0 then
			P.addXp(player, live.species, xp)
		end
		local drop = K.rollDrop(typeNameOf(target), tier, math.random, cfg, xp > 0)
		if drop then
			local species = K.species(drop, cfg)
			target:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
			log(string.format("%s found the pet %s (%s)", player:getName(), species.name, target:getName()))
			P.grant(player, drop, "drop")
		end
	end)
	if not ok then
		log("kill: " .. tostring(err))
	end
	return true
end
kill:register()

local ward = CreatureEvent("ChaosPetsWard")
function ward.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not attacker or not attacker:isMonster() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local master = attacker:getMaster()
	if master and master:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local live = P.live[creature:getId()]
	if live and (live.wardUntil or 0) > nowMs() and (live.wardPct or 0) > 0 then
		local f = 1 - live.wardPct / 100
		primaryDamage = math.floor(primaryDamage * f)
		secondaryDamage = math.floor(secondaryDamage * f)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
ward:register()

local function say(player, ok, text)
	player:sendTextMessage(ok and MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, text)
end

local ext = CreatureEvent("ChaosPetsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	local action = type(msg) == "table" and msg.action
	local data = type(msg) == "table" and type(msg.data) == "table" and msg.data or {}
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "pets." .. tostring(action), 250) then
		return
	end
	local ok, err = pcall(function()
		if action == "open" or action == "get" then
			if action == "open" then
				P.checkAchievements(player, false)
			end
			P.sendState(player, action == "open")
		elseif action == "close" then
			P.window[player:getId()] = nil
		elseif action == "summon" then
			local done, why = P.callOut(player, tostring(data.species or ""))
			if not done then
				say(player, false, why)
			end
			P.sendState(player, false)
		elseif action == "dismiss" then
			P.dismiss(player)
			P.sendState(player, false)
		elseif action == "rename" then
			local done, why = P.rename(player, tostring(data.species or ""), data.name)
			say(player, done, done and ("Your pet is now called " .. why .. ".") or why)
			P.sendState(player, false)
		end
	end)
	if not ok then
		log("opcode: " .. tostring(err))
	end
end
ext:register()

local tick = GlobalEvent("ChaosPetsThink")
function tick.onThink(interval)
	for pid in pairs(P.live) do
		local player = Player(pid)
		if player then
			local ok, err = pcall(P.think, player)
			if not ok then
				log("think: " .. tostring(err))
			end
		else
			P.live[pid] = nil
		end
	end
	return true
end
tick:interval(cfg.thinkMs)
tick:register()

local save = GlobalEvent("ChaosPetsFlush")
function save.onThink(interval)
	for guid in pairs(P.rows) do
		pcall(flush, guid)
	end
	for _, player in ipairs(Game.getPlayers()) do
		if P.rows[player:getGuid()] then
			pcall(P.checkAchievements, player, false)
		end
	end
	P.killed = {}
	return true
end
save:interval(60000)
save:register()

local shutdown = GlobalEvent("ChaosPetsShutdown")
function shutdown.onShutdown()
	for guid in pairs(P.rows) do
		pcall(flush, guid)
	end
	return true
end
shutdown:register()

local startup = GlobalEvent("ChaosPetsStartup")
function startup.onStartup()
	ensureTable()
	-- pets never get a monster tier (their health is below the tiers' minimum too)
	if ChaosTierConfig and ChaosTierConfig.skip then
		for _, s in ipairs(cfg.species) do
			ChaosTierConfig.skip[s.monster:lower()] = true
		end
	end
	local missing = {}
	for _, s in ipairs(cfg.species) do
		if not MonsterType(s.monster) then
			missing[#missing + 1] = s.monster
		end
	end
	log(string.format("%d species, opcode %d%s", #cfg.species, OPCODE,
		#missing > 0 and (", MISSING monster types: " .. table.concat(missing, ", ")) or ""))
	return true
end
startup:register()

-- ---------------------------------------------------------------- commands
local function findOwned(player, text)
	text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	for key, row in pairs(rowsOf(player)) do
		local s = K.species(key, cfg)
		if s and (key == text or s.name:lower() == text or (row.name or ""):lower() == text) then
			return key
		end
	end
	return nil
end

-- staff: /pet give <species>[, character] | xp <n> | level <n> | reset | species
local gm = TalkAction("/pet")
function gm.onSay(player, words, param)
	if not (cfg.staffAccess and player:getGroup():getAccess()) then
		return true
	end
	local cmd, rest = (param or ""):match("^%s*(%a+)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	-- staff never give value (docs/GM_HANDBOOK.md section 2): /pet give needs an administrator
	if not Chaos.staffCommand(player, words, param, cmd == "give") then
		return false
	end
	local live = P.live[player:getId()]
	if cmd == "give" then
		local key, who = rest:match("^([%w_]+)%s*,?%s*(.-)$")
		local target = (who and who ~= "") and Player(who) or player
		if not target then
			say(player, false, "Character not online.")
		elseif not K.species(key or "", cfg) then
			say(player, false, "Unknown species. /pet species lists them.")
		else
			local ok, what = P.grant(target, key, "staff")
			say(player, ok, ok and ("Given (" .. what .. ").") or what)
		end
	elseif (cmd == "xp" or cmd == "level") and tonumber(rest) then
		if not live then
			say(player, false, "Call a pet first.")
			return false
		end
		local row = rowsOf(player)[live.species]
		if cmd == "xp" then
			P.addXp(player, live.species, math.floor(tonumber(rest)))
		else
			row.xp = K.totalFor(math.max(1, math.min(cfg.maxLevel, math.floor(tonumber(rest)))), cfg)
			saveRow(player:getGuid(), row)
			refresh(player)
		end
		say(player, true, string.format("Pet level %d (%d XP).", (K.levelOf(row.xp, cfg)), row.xp))
	elseif cmd == "reset" then
		P.dismiss(player, "silent")
		db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d", TABLE, player:getGuid()))
		P.rows[player:getGuid()], P.cool[player:getGuid()] = nil, nil
		say(player, true, "All pets of this character removed.")
		refresh(player)
	elseif cmd == "species" then
		local keys = {}
		for _, s in ipairs(cfg.species) do
			keys[#keys + 1] = s.key
		end
		say(player, true, "Species: " .. table.concat(keys, ", "))
	else
		say(player, false, "Usage: /pet give <species>[, character] | xp <n> | level <n> | reset | species")
	end
	return false
end
gm:separator(" ")
gm:register()
