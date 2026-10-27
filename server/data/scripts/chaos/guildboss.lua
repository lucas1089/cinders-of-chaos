-- The weekly guild boss: Gorvath the Banner-Eater, a guild-only instanced boss summoned at the Summoning Stone of the
-- guild hall. During the week the members fuel the stone with gold and materials (embers; a gold sink); with the stone
-- full, the leader or a vice-leader summons the boss and every member of the guild standing in the hall (level
-- minLevel+, up to maxPlayers) comes along into a runtime-built arena. One kill per guild and week.
-- Settings: guildboss_config.lua (Chaos.guildBossConfig). Pure logic: guildboss_core.lua (tests/guildboss_test.lua);
-- the arena, telegraphs, phases, shared lives and the lethal-hit catch reuse uber_core.lua (the Ascended arenas) with
-- this config. Overview: server/README.md "The weekly guild boss".
--
--   the stone   an obelisk (stoneId, action id stoneActionId) placed in every guild hall next to the depot spot (east
--               wall); using it opens the Guild Boss tab of the window (client game_guildwar). guild_hall.lua's
--               G.furnish is wrapped (no edit there): the stone, the banner tier on the hall flags, the guild boss line
--               on the trophy statue.
--   fuel        chaos_guildboss_week (guild, week): fuel, attempts, the kill. Donations: gold (carried, then the bank
--               balance) and materials (every one of that kind carried, up to maxPerDonation); logged per member in
--               chaos_guildboss_contrib and in the guild log. A summon takes the need in one conditional UPDATE (fuel >=
--               need, not killed, attempts < max); a failed attempt gives back failKeep of the need.
--   the fight   uber.lua's model: telegraphs, phases, adds, hazards, enrage and time limit, shared lives (a lethal hit
--               sends the player to the antechamber's Ember Gate), health x (1 + healthPerExtraPlayer x (players - 1)).
--   rewards     every participant present at the kill with minDamageShare of the damage (or who healed): a share of
--               the kill's gold pool (B.goldPool, split by damage + healing with a floor, B.splitGold) to the bank
--               balance, and the orbs each; the split is kept in chaos_guildboss_week.pool and
--               chaos_guildboss_contrib.spoils / contribution (the tab's "This week's spoils") and the guild log.
--               The guild: guild XP (guild levels), the kill counter (banner tier, trophy room),
--               the lockout (storage Chaos.storage.guildBossLockout = the next reset, the Boss Spawns cooldown).
--   board       this week's guilds: kills first (fastest), then the damage of their attempts.
-- Exports: ChaosGuildBoss.view(player), ChaosGuildBoss.handle(player, action, data) (guildwar.lua routes the boss*
-- actions of opcode 197 here), ChaosGuildBoss.isInside(player). Staff: /guildboss. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosUberCore then
	dofile("data/scripts/chaos/uber_core.lua")
end
dofile("data/scripts/chaos/guildboss_core.lua")
if not ChaosGuildCore then
	dofile("data/scripts/chaos/guild_core.lua")
end
Chaos.guildBossConfig = dofile("data/scripts/chaos/guildboss_config.lua")
dofile("data/lib/chaos_dark_paint.lua")
if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end

ChaosGuildBoss = ChaosGuildBoss or {}
local GB = ChaosGuildBoss
local B = ChaosGuildBossCore
local U = ChaosUberCore
local HUD = ChaosOpcodes.rift
local OPCODE = ChaosOpcodes.guildWar or 197

local function C()
	return Chaos.guildBossConfig
end

local function T()
	return C().tables
end

local function G()
	return ChaosGuild
end

local function now()
	return os.time()
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function rand(a, b)
	return math.random(a, b)
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos guildboss] " .. text)
end

GB.runs = GB.runs or {} -- slot -> run
GB.runOf = GB.runOf or {} -- player id -> run
GB.guildRun = GB.guildRun or {} -- guild id -> run
GB.monsterRun = GB.monsterRun or {} -- monster id -> run
GB.built = GB.built or {}
GB.bad = GB.bad or {}
GB.nextId = GB.nextId or 0

local function weekNow()
	return B.weekKey(C(), now())
end

-- the boss and its adds keep their tuned stats (monster_tiers.lua)
local function tierSkip()
	local tc = ChaosTierConfig
	if tc and tc.skip then
		local b = C().boss
		tc.skip[b.boss:lower()] = true
		tc.skip[b.add:lower()] = true
		if tc.bosses then
			tc.bosses[b.boss:lower()] = true
		end
	end
end
tierSkip()

-- ======================================================================== database
local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_guildboss_week` (`guild_id` int(11) NOT NULL, `week` int(10) unsigned NOT NULL,
	`fuel` int(10) unsigned NOT NULL DEFAULT 0, `attempts` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`killed_at` int(10) unsigned NOT NULL DEFAULT 0, `best_seconds` int(10) unsigned NOT NULL DEFAULT 0,
	`damage` bigint(20) unsigned NOT NULL DEFAULT 0, `players` smallint(5) unsigned NOT NULL DEFAULT 0,
	`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`guild_id`, `week`), KEY `chaos_guildboss_week_week` (`week`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guildboss_contrib` (`guild_id` int(11) NOT NULL, `week` int(10) unsigned NOT NULL,
	`player_id` int(11) NOT NULL, `name` varchar(255) NOT NULL DEFAULT '', `gold` bigint(20) unsigned NOT NULL DEFAULT 0,
	`embers` int(10) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0,
	PRIMARY KEY (`guild_id`, `week`, `player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_guildboss_runs` (`id` int(11) NOT NULL AUTO_INCREMENT, `guild_id` int(11) NOT NULL,
	`week` int(10) unsigned NOT NULL, `started_at` int(10) unsigned NOT NULL DEFAULT 0, `ended_at` int(10) unsigned NOT NULL DEFAULT 0,
	`players` smallint(5) unsigned NOT NULL DEFAULT 0, `result` varchar(12) NOT NULL DEFAULT '', `seconds` int(10) unsigned NOT NULL DEFAULT 0,
	`damage` bigint(20) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_guildboss_runs_guild` (`guild_id`, `week`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	-- the gold pool of the kill and each member's share of it (a database of the first version gets the columns)
	[[ALTER TABLE `chaos_guildboss_week` ADD COLUMN IF NOT EXISTS `pool` bigint(20) unsigned NOT NULL DEFAULT 0]],
	[[ALTER TABLE `chaos_guildboss_contrib` ADD COLUMN IF NOT EXISTS `spoils` bigint(20) unsigned NOT NULL DEFAULT 0,
	ADD COLUMN IF NOT EXISTS `contribution` bigint(20) unsigned NOT NULL DEFAULT 0]]
}

function GB.ensureTables()
	for _, q in ipairs(SCHEMA) do
		db.query((q:gsub("%s+", " ")))
	end
end

-- this week's row of a guild (created when missing)
function GB.weekRow(gid, week)
	week = week or weekNow()
	local cols = {{"fuel", "n"}, {"attempts", "n"}, {"killed_at", "n"}, {"best_seconds", "n"}, {"damage", "n"}, {"players", "n"},
		{"pool", "n"}}
	local q = string.format("SELECT `fuel`, `attempts`, `killed_at`, `best_seconds`, `damage`, `players`, `pool` FROM `%s` " ..
		"WHERE `guild_id` = %d AND `week` = %d", T().week, gid, week)
	local r = Chaos.select(q, cols)[1]
	if not r then
		db.query(string.format("INSERT IGNORE INTO `%s` (`guild_id`, `week`, `updated_at`) VALUES (%d, %d, %d)", T().week, gid, week, now()))
		r = {fuel = 0, attempts = 0, killed_at = 0, best_seconds = 0, damage = 0, players = 0, pool = 0}
	end
	r.pool = r.pool or 0
	return r
end

local function addFuel(gid, embers)
	db.query(string.format("INSERT INTO `%s` (`guild_id`, `week`, `fuel`, `updated_at`) VALUES (%d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `fuel` = `fuel` + %d, `updated_at` = %d", T().week, gid, weekNow(), embers, now(), embers, now()))
end

local function addContrib(gid, player, gold, embers)
	db.query(string.format("INSERT INTO `%s` (`guild_id`, `week`, `player_id`, `name`, `gold`, `embers`, `updated_at`) VALUES " ..
		"(%d, %d, %d, %s, %d, %d, %d) ON DUPLICATE KEY UPDATE `gold` = `gold` + %d, `embers` = `embers` + %d, `name` = VALUES(`name`), " ..
		"`updated_at` = %d", T().contrib, gid, weekNow(), player:getGuid(), db.escapeString(player:getName()), gold, embers, now(),
		gold, embers, now()))
end

function GB.killsOf(gid)
	local s = G().statsOf and G().statsOf(gid) or {}
	return s.guildBoss or 0
end

-- ======================================================================== the stone, the banner and the trophy line
local function stonePos(slot)
	local L = ChaosGuildCore.layout(slot, Chaos.guildConfig)
	return {x = L.origin.x + L.w - 1, y = L.origin.y + 11, z = L.origin.z}, L
end
GB.stonePos = stonePos

function GB.bannerText(gid)
	local kills = GB.killsOf(gid)
	local tier, name, nextAt = B.banner(kills, C())
	if tier == 0 then
		return string.format("The banner of %s.", G().nameOf(gid))
	end
	-- one key per form (the look of the banner translates it, itemdesc_i18n.lua)
	if kills == 1 then
		if nextAt then
			return string.format("The %s of %s: Gorvath the Banner-Eater slain once (next tier at %d).", name, G().nameOf(gid), nextAt)
		end
		return string.format("The %s of %s: Gorvath the Banner-Eater slain once.", name, G().nameOf(gid))
	end
	if nextAt then
		return string.format("The %s of %s: Gorvath the Banner-Eater slain %d times (next tier at %d).", name, G().nameOf(gid), kills, nextAt)
	end
	return string.format("The %s of %s: Gorvath the Banner-Eater slain %d times.", name, G().nameOf(gid), kills)
end

-- after guild_hall.lua's G.furnish: the stone, the banner text, the trophy line
function GB.decorate(gid)
	local h = G().hallOf and G().hallOf(gid)
	if not h then
		return
	end
	local cfg = C()
	local pos, L = stonePos(h.slot)
	local tile = Tile(P(pos))
	if tile then
		local stone = tile:getItemById(cfg.stoneId) or Game.createItem(cfg.stoneId, 1, P(pos))
		if stone then
			stone:setActionId(cfg.stoneActionId)
			stone:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "The Summoning Stone. Feed it embers (gold and materials) during the " ..
				"week; when it is full, the guild leader or a vice-leader wakes the guild boss here. Use it to see the fuel.")
		end
	end
	local text = GB.bannerText(gid)
	for _, f in ipairs(L.flags) do
		local ft = Tile(P(f))
		local flag = ft and ft:getItemById(Chaos.guildConfig.hall.ids.flag)
		if flag then
			flag:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
		end
	end
	local kills = GB.killsOf(gid)
	if kills > 0 then
		local t2 = L.trophies[2] and Tile(P(L.trophies[2]))
		local statue = t2 and t2:getItemById(Chaos.guildConfig.hall.ids.trophies[2])
		if statue then
			local d = statue:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION) or ""
			if not d:find("Banner-Eater", 1, true) then
				statue:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, d .. (kills == 1 and " Gorvath the Banner-Eater: slain once." or
					string.format(" Gorvath the Banner-Eater: slain %d times.", kills)))
			end
		end
	end
end

-- wrap G.furnish (again after a reload of guild_hall.lua)
function GB.wrapFurnish()
	local g = G()
	if not g or not g.furnish or g.furnish == GB.wrappedFurnish then
		return
	end
	local original = g.furnish
	GB.wrappedFurnish = function(gid)
		local ok = original(gid)
		if ok then
			local fine, err = pcall(GB.decorate, gid)
			if not fine then
				log("decorate failed: " .. tostring(err))
			end
		end
		return ok
	end
	g.furnish = GB.wrappedFurnish
end

local stone = Action()
function stone.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if ChaosGuildWar and ChaosGuildWar.sendState then
		ChaosGuildWar.sendState(player, true, "boss")
	end
	return true
end
stone:aid(C().stoneActionId)
stone:register()

-- ======================================================================== the window
local function inOwnHall(player, gid)
	if not G().inHall then
		return false
	end
	local slot, owner = G().inHall(player:getPosition())
	return slot ~= nil and owner == gid
end

-- members of the guild in its hall who can come along (the summoner first)
local function hallGroup(player, gid)
	local cfg = C()
	local group = {player}
	local pslot = G().inHall and G().inHall(player:getPosition())
	for _, m in ipairs(G().onlineMembers(gid)) do
		if m:getId() ~= player:getId() and #group < cfg.maxPlayers and m:getLevel() >= cfg.minLevel and not GB.runOf[m:getId()] then
			local slot = G().inHall(m:getPosition())
			if slot and slot == pslot then
				group[#group + 1] = m
			end
		end
	end
	return group
end

local function summonInfo(player, gid, rank, row)
	local cfg = C()
	local level = G().levelOf(gid)
	local hall = G().hallOf and G().hallOf(gid)
	local inHall = hall ~= nil and inOwnHall(player, gid)
	local players = 0
	if inHall then
		players = #hallGroup(player, gid)
		if player:getLevel() < cfg.minLevel then
			players = players - 1
		end
	end
	return {enabled = cfg.enabled, guildId = gid, rank = rank, hasHall = hall ~= nil,
		rentLocked = hall ~= nil and G().rentStateOf(gid) == "locked", inHall = inHall, fuel = row.fuel, need = B.need(level, cfg),
		killed = row.killed_at > 0, attempts = row.attempts, players = players, running = GB.guildRun[gid] ~= nil}
end

function GB.board(week)
	local rows = Chaos.select(string.format("SELECT w.`guild_id` AS `id`, g.`name` AS `name`, w.`killed_at`, w.`best_seconds`, w.`damage`, " ..
		"w.`players` FROM `%s` w JOIN `guilds` g ON g.`id` = w.`guild_id` WHERE w.`week` = %d AND (w.`killed_at` > 0 OR w.`damage` > 0)",
		T().week, week or weekNow()), {{"id", "n"}, {"name", "s"}, {"killed_at", "n"}, {"best_seconds", "n"}, {"damage", "n"}, {"players", "n"}})
	for _, r in ipairs(rows) do
		r.killed = r.killed_at > 0
		r.seconds = r.best_seconds
	end
	return B.rankGuilds(rows)
end

function GB.view(player)
	local cfg = C()
	local gid, _, rank = G().guildOf(player)
	local t = now()
	local v = {enabled = cfg.enabled, boss = cfg.boss.boss, minLevel = cfg.minLevel, minPlayers = cfg.minPlayers,
		maxPlayers = cfg.maxPlayers, maxAttempts = cfg.maxAttempts, resetIn = math.max(0, B.nextReset(cfg, t) - t),
		gold = {perEmber = cfg.gold.perEmber, min = cfg.gold.min}, materials = {}, contributors = {}, spoils = {}, board = {}}
	for i, r in ipairs(GB.board()) do
		if i > cfg.board.rows then
			break
		end
		v.board[#v.board + 1] = {rank = r.rank, name = r.name, killed = r.killed, seconds = r.seconds, damage = r.damage,
			players = r.players, own = r.id == gid}
	end
	if not gid then
		return v
	end
	local row = GB.weekRow(gid)
	local info = summonInfo(player, gid, rank, row)
	local why = B.summonError(info, cfg)
	v.guild = true
	v.fuel, v.need, v.attempts, v.killed = row.fuel, info.need, row.attempts, row.killed_at > 0
	v.bestSeconds, v.damage, v.pool = row.best_seconds, row.damage, row.pool
	v.canSummon = why == nil
	v.reason = why and Chaos.tx(player, why) or ""
	v.hasHall = info.hasHall
	v.inHall = info.inHall
	v.running = info.running
	v.players = info.players
	local kills = GB.killsOf(gid)
	local tier, bname, nextAt = B.banner(kills, cfg)
	v.banner = {kills = kills, tier = tier, name = bname or "", next = nextAt or 0}
	for _, m in ipairs(cfg.materials) do
		local it = ItemType(m.id)
		if it and it:getId() ~= 0 then
			v.materials[#v.materials + 1] = {key = m.key, name = m.name, embers = m.embers, have = player:getItemCount(m.id),
				clientId = it:getClientId()}
		end
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `name`, `gold`, `embers` FROM `%s` WHERE `guild_id` = %d AND `week` = %d " ..
			"AND `embers` > 0 ORDER BY `embers` DESC, `updated_at` ASC LIMIT 10", T().contrib, gid, weekNow()),
			{{"name", "s"}, {"gold", "n"}, {"embers", "n"}})) do
		v.contributors[#v.contributors + 1] = {name = r.name, gold = r.gold, embers = r.embers}
	end
	-- this week's split of the kill's gold pool (every rewarded participant)
	if row.pool > 0 then
		for _, r in ipairs(Chaos.select(string.format("SELECT `name`, `spoils` FROM `%s` WHERE `guild_id` = %d AND `week` = %d " ..
				"AND `spoils` > 0 ORDER BY `spoils` DESC, `player_id` ASC LIMIT %d", T().contrib, gid, weekNow(), cfg.maxPlayers),
				{{"name", "s"}, {"spoils", "n"}})) do
			v.spoils[#v.spoils + 1] = {name = r.name, gold = r.spoils}
		end
	end
	return v
end

-- ======================================================================== donations
local function donateGold(player, amount)
	local gid = G().guildOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	local embers, gold = B.goldEmbers(amount, C())
	if not embers then
		return false, gold
	end
	if GB.weekRow(gid).killed_at > 0 then
		return false, "Your guild already slew the guild boss this week; the stone rests until the reset."
	end
	if not G().payFromPlayer(player, gold) then
		return false, "You do not have that much gold (carried and in the bank)."
	end
	-- saved before the fuel row is credited: a crash in between cannot keep both the gold and the embers
	if not Chaos.saveCharacter(player) then
		player:setBankBalance(player:getBankBalance() + gold)
		return false, "The stone is busy; your gold went back to your bank balance."
	end
	addFuel(gid, embers)
	addContrib(gid, player, gold, embers)
	G().logRow(gid, player, "boss", gold, 0, embers, string.format("fed the Summoning Stone %d embers", embers))
	return true, string.format("You fed the Summoning Stone %s gold: %d embers.", B.money(gold), embers)
end

local function donateItems(player, key)
	local cfg = C()
	local gid = G().guildOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	local def = B.material(cfg, tostring(key or ""))
	if not def then
		return false, "The stone does not take that."
	end
	if GB.weekRow(gid).killed_at > 0 then
		return false, "Your guild already slew the guild boss this week; the stone rests until the reset."
	end
	local take, embers = B.materialEmbers(def, player:getItemCount(def.id), cfg)
	if take <= 0 or embers <= 0 then
		return false, string.format("You carry no %s.", def.name)
	end
	if not player:removeItem(def.id, take) then
		return false, "The items could not be taken."
	end
	if not Chaos.saveCharacter(player) then -- see donateGold
		player:addItem(def.id, take)
		return false, "The stone is busy. Try again in a moment."
	end
	addFuel(gid, embers)
	addContrib(gid, player, 0, embers)
	G().logRow(gid, player, "boss", 0, def.id, embers, string.format("fed the Summoning Stone %d x %s (%d embers)", take, def.name, embers))
	return true, string.format("You fed the Summoning Stone %d x %s: %d embers.", take, def.name, embers)
end

-- ======================================================================== arena slots
local function groundIdOf(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
	return tile and tile:getItemById(id)
end

local function dark()
	local cfg = C()
	if cfg.darkActive ~= nil then
		return cfg.darkActive
	end
	cfg.darkActive = false
	local d = cfg.dark
	if d and d.enabled and ChaosDarkPaint and ChaosDarkTiles and ChaosDarkPaint.ready(d.style) then
		local wall, basin = ChaosDarkTiles.id(d.wall), ChaosDarkTiles.id(d.basin)
		if wall and basin then
			cfg.wallId, cfg.basinId, cfg.darkActive = wall, basin, true
		end
	end
	return cfg.darkActive
end

-- O276: the look of the arena (arenalook_core.lua): the theme of the boss, varied ground, mirrored cover and lights that
-- leave the lane from the entry to the boss, the arrival and the boss spot open. Repainted when the theme changes (a
-- slot serves many bosses); the fixtures are placed after it.
local function dressSlot(L, bossKey)
	local cfg = C()
	ChaosArenaLook.dressBossArena("guild", L, cfg, bossKey)
	for _, t in ipairs(L.basins) do
		placeItem(P(ChaosArenaLook.fixtureSpot(t, {L.rect}, ChaosArenaLook.wallSizeOf(cfg.wallId))), cfg.basinId)
	end
end

local function buildSlot(slot, bossKey)
	local cfg = C()
	local isDark = dark()
	local L = U.layout(cfg, slot)
	if GB.built[slot] then
		dressSlot(L, bossKey)
		return L
	end
	if GB.bad[slot] then
		return nil, GB.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local lists = {L.floorList, L.anteList, L.wallList}
	for _, list in ipairs(lists) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			local gid = tile and groundIdOf(tile)
			if tile and ((gid ~= cfg.groundId and not (isDark and ChaosDarkPaint.isDark(gid)) and not ChaosArenaLook.isOwned(gid)) or (tile.getHouse and tile:getHouse())) then
				return nil, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
			end
		end
	end
	for _, list in ipairs(lists) do
		for _, t in ipairs(list) do
			local pos = P(t)
			local tile = Tile(pos) or Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(cfg.groundId, 1, pos)
			end
		end
	end
	for _, t in ipairs(L.wallList) do
		placeItem(P(t), cfg.wallId)
	end
	dressSlot(L, bossKey)
	local gate = placeItem(P(L.portal), cfg.portalId)
	if gate then
		gate:setActionId(cfg.portalActionId)
	end
	GB.built[slot] = true
	return L
end

local function cleanSlot(L)
	local cfg = C()
	local keep = {[cfg.groundId] = true, [cfg.wallId] = true, [cfg.basinId] = true, [cfg.portalId] = true}
	for _, list in ipairs({L.floorList, L.anteList}) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						GB.monsterRun[c:getId()] = nil
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					local id = item:getId()
					if not keep[id] and not (cfg.darkActive and ChaosDarkPaint.isDark(id)) and not ChaosArenaLook.isOwned(id) then
						item:remove()
					end
				end
			end
		end
	end
end

local function takeSlot(bossKey)
	local cfg = C()
	while true do
		local slot = U.allocSlot(cfg, GB.runs, GB.bad)
		if not slot then
			return nil
		end
		local L, why = buildSlot(slot, bossKey)
		if L then
			return slot, L
		end
		GB.bad[slot] = why
		log(string.format("slot %d not usable: %s", slot, tostring(why)))
	end
end

-- ======================================================================== the run: HUD, leaving, the end
local function say(run, text, kind)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			p:sendTextMessage(kind or MESSAGE_EVENT_ADVANCE, Chaos.tx(p, text)) -- English text or a deferred text, per reader
		end
	end
end

-- large effects (data/lib/chaos_big_fx.lua, switch ChaosBigFx.BIG_FX, on since 2026-10-13; off: nothing more is sent): the big warning
-- circle over a round telegraph, the big hit of the boss's element
if not ChaosBigFx then
	pcall(dofile, "data/lib/chaos_big_fx.lua")
end
local function bigFx(fn, ...)
	if ChaosBigFx and ChaosBigFx[fn] then
		pcall(ChaosBigFx[fn], ...)
	end
end

local function fx(pos, name, fallback)
	if Vfx and ChaosVfx and ChaosVfx[name] then
		Vfx(pos, name)
	elseif fallback then
		pos:sendMagicEffect(fallback)
	end
end

local function bossOf(run)
	return run.bossId and Monster(run.bossId) or nil
end

-- seconds until the run's time limit (the boss's limit after it appears, plus the wait before it)
local function timeLeft(run, t)
	local def = C().boss
	if run.bossAt then
		local _, _, tl = U.clock(def, (t - run.bossAt) / 1000)
		return math.max(0, math.floor(tl))
	end
	return def.limit + math.max(0, math.ceil(((run.bossDueAt or t) - t) / 1000))
end
GB.timeLeft = timeLeft

local function hudData(run)
	local def = C().boss
	local t = mnow()
	local left, toEnrage = def.limit, def.enrageAt
	if run.bossAt then
		local _, te, tl = U.clock(def, (t - run.bossAt) / 1000)
		left, toEnrage = tl, te
	else
		left = def.limit + math.max(0, math.ceil(((run.bossDueAt or t) - t) / 1000))
	end
	local boss = bossOf(run)
	local notes = {}
	if run.boss == "alive" then
		local ph = def.phases[run.phase or 1] or def.phases[1]
		notes[#notes + 1] = ChaosI18n.msg("Phase %d of %d: %s", run.phase or 1, #def.phases, ph.name)
		notes[#notes + 1] = ChaosI18n.msg("Health: %d%%", boss and math.floor(boss:getHealth() * 100 / math.max(1, boss:getMaxHealth())) or 100)
		notes[#notes + 1] = run.enraged and "ENRAGED: every hit is far stronger." or ChaosI18n.msg("Enrage in %s", B.clockText(toEnrage))
	end
	local waiting = 0
	for _, e in pairs(run.players) do
		if e.down then
			waiting = waiting + 1
		end
	end
	if waiting > 0 then
		notes[#notes + 1] = ChaosI18n.msg("%d at the Ember Gate.", waiting)
	end
	return {tier = 0, theme = run.guildName, left = math.floor(left), limit = def.limit, total = 0, killed = 0, bossAt = 0,
		boss = run.boss, state = run.state, bossName = def.boss, mods = {}, notes = notes, lives = run.lives, livesMax = run.livesMax,
		title = ChaosI18n.msg("Guild Boss: %s", def.name)}
end

-- the HUD data with the notes and the title in the reader's language
local function hudIn(data, p)
	local d = {}
	for k, v in pairs(data) do
		d[k] = v
	end
	d.notes = {}
	for i, n in ipairs(data.notes) do
		d.notes[i] = Chaos.tx(p, n)
	end
	d.title = Chaos.tx(p, data.title)
	return d
end

local function sendHud(run, action, player)
	if not HUD or not Chaos.send then
		return
	end
	local data = hudData(run)
	if player then
		Chaos.send(player, HUD, action, hudIn(data, player))
		return
	end
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			Chaos.send(p, HUD, action, hudIn(data, p))
		end
	end
end

local finishExit

local function eventsOn(player)
	player:registerEvent("ChaosGuildBossPlayerHit")
	player:registerEvent("ChaosGuildBossPlayerMana")
	player:registerEvent("ChaosGuildBossPrepareDeath")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosGuildBossPlayerHit")
	player:unregisterEvent("ChaosGuildBossPlayerMana")
	player:unregisterEvent("ChaosGuildBossPrepareDeath")
end

local function removePlayer(run, id, mode)
	local entry = run.players[id]
	if not entry then
		return
	end
	run.players[id] = nil
	GB.runOf[id] = nil
	local player = Player(id)
	if player then
		eventsOff(player)
		if mode ~= "stay" and mode ~= "logout" then
			local dest = (run.restart or mode == "temple") and player:getTown():getTemplePosition() or entry.entry
			player:teleportTo(dest)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		player:removeCondition(CONDITION_INFIGHT)
		if mode ~= "logout" and HUD and Chaos.send then
			local running = run.state == "running"
			Chaos.send(player, HUD, "end", {result = running and "left" or run.state,
				text = Chaos.tx(player, running and "You left the arena." or (run.endText or ""))})
		end
	end
	if next(run.players) == nil and not run.ended then
		if run.state == "running" then
			run.state = "failed"
			run.endText = "Everyone left the arena."
			GB.recordFail(run)
		end
		finishExit(run)
	end
end

local function removeMonsters(run)
	for mid, r in pairs(GB.monsterRun) do
		if r == run then
			GB.monsterRun[mid] = nil
			local m = Monster(mid)
			if m then
				m:remove()
			end
		end
	end
end

finishExit = function(run)
	if run.ended then
		return
	end
	run.ended = true
	for id in pairs(run.players) do
		removePlayer(run, id, "out")
	end
	removeMonsters(run)
	cleanSlot(run.L)
	if GB.runs[run.slot] == run then
		GB.runs[run.slot] = nil
		if ChaosInstanceLimits and not run.restart then
			ChaosInstanceLimits.freed("guildboss", "the guild boss arenas")
		end
	end
	if GB.guildRun[run.gid] == run then
		GB.guildRun[run.gid] = nil
	end
	log(string.format("run %d (guild %d, slot %d) ended: %s", run.id, run.gid, run.slot, run.state))
	if ChaosGuildWar and ChaosGuildWar.push then
		pcall(ChaosGuildWar.push, {run.gid})
	end
end

local function totalDamage(run)
	local n = 0
	for _, d in pairs(run.damage) do
		n = n + d
	end
	return n
end

local function saveRun(run, result, secs)
	db.query(string.format("INSERT INTO `%s` (`guild_id`, `week`, `started_at`, `ended_at`, `players`, `result`, `seconds`, `damage`) " ..
		"VALUES (%d, %d, %d, %d, %d, %s, %d, %d)", T().runs, run.gid, run.week, run.startedAt, now(), run.size, db.escapeString(result),
		secs or 0, totalDamage(run)))
end

-- a failed attempt: failKeep of the need back as fuel, the damage on the board
function GB.recordFail(run)
	if run.recorded then
		return
	end
	run.recorded = true
	local keep = B.fuelAfterFail(0, run.need, C())
	db.query(string.format("UPDATE `%s` SET `fuel` = `fuel` + %d, `damage` = `damage` + %d, `updated_at` = %d WHERE `guild_id` = %d AND `week` = %d",
		T().week, keep, totalDamage(run), now(), run.gid, run.week))
	saveRun(run, run.state, run.bossAt and math.floor((mnow() - run.bossAt) / 1000) or 0)
	G().tellGuild(run.gid, ChaosI18n.msg("The guild boss attempt failed. The Summoning Stone keeps %d embers.", keep))
end

local function fail(run, text)
	if run.ended or run.state ~= "running" then
		return
	end
	run.state = "failed"
	run.endText = ChaosI18n.msg("%s The arena collapses.", ChaosI18n.isMsg(text) and text or ChaosI18n.msg(text))
	say(run, run.endText)
	GB.recordFail(run)
	sendHud(run, "update")
	finishExit(run)
end
GB._fail = fail

function GB.interruptAll()
	for _, run in pairs(GB.runs) do
		if not run.ended then
			run.restart = true
			if run.state == "running" then
				run.state = "interrupted"
				run.endText = "The server is restarting: the arena closes."
				say(run, run.endText)
				-- the fuel of an interrupted summon goes back in full, the attempt is not counted
				db.query(string.format("UPDATE `%s` SET `fuel` = `fuel` + %d, `attempts` = GREATEST(`attempts`, 1) - 1 WHERE `guild_id` = %d AND `week` = %d",
					T().week, run.need, run.gid, run.week))
				run.recorded = true
			end
			finishExit(run)
		end
	end
end

local function serverClosing()
	local state = Game.getGameState and Game.getGameState()
	return state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED)
end

-- ======================================================================== rewards
local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

-- the lockout storage of a member (the Boss Spawns cooldown): the next reset while the guild has its kill
function GB.syncLockout(player)
	local gid = G().guildOf(player)
	local untilT = 0
	if gid and GB.weekRow(gid).killed_at > 0 then
		untilT = B.nextReset(C(), now())
	end
	player:setStorageValue(Chaos.storage.guildBossLockout, untilT)
end

local function success(run)
	local cfg = C()
	run.state = "success"
	run.boss = "dead"
	run.recorded = true
	local secs = math.max(1, math.floor((mnow() - (run.bossAt or mnow())) / 1000))
	removeMonsters(run)
	run.hazard = nil
	local present = {}
	local count = 0
	for _, e in pairs(run.players) do
		present[e.guid] = true
		count = count + 1
	end
	local size = math.max(run.size, count)
	local winners = B.rewarded(run.damage, run.healers, present, cfg)
	local damage = totalDamage(run)
	db.query(string.format("UPDATE `%s` SET `killed_at` = %d, `best_seconds` = %d, `players` = %d, `damage` = `damage` + %d, `updated_at` = %d " ..
		"WHERE `guild_id` = %d AND `week` = %d", T().week, now(), secs, size, damage, now(), run.gid, run.week))
	saveRun(run, "killed", secs)
	pcall(G().addStat, run.gid, "guildBoss", 1)
	local gxp = B.gxp(size, cfg)
	pcall(G().addXp, run.gid, 0, "guildboss", gxp, true)
	-- the guild's gold pool, split by contribution (damage + healing, with a floor) among the rewarded participants
	local r = cfg.reward
	local healing = run.healing or {}
	local nWin = 0
	for _ in pairs(winners) do
		nWin = nWin + 1
	end
	local pool = B.goldPool(nWin, cfg)
	local shares = B.splitGold(pool, winners, run.damage, healing, cfg)
	db.query(string.format("UPDATE `%s` SET `pool` = %d WHERE `guild_id` = %d AND `week` = %d", T().week, pool, run.gid, run.week))
	run.endText = ChaosI18n.msg("%s falls in %s! The guild earns %d guild XP and %s gold, shared by contribution. You return to the hall in %d seconds.", cfg.boss.boss, B.clockText(secs), gxp, B.money(pool), cfg.exitDelay)
	say(run, run.endText)
	for id, e in pairs(run.players) do
		local p = Player(id)
		if winners[e.guid] then
			local gold = shares[e.guid] or 0
			local contribution = math.floor((run.damage[e.guid] or 0) + (r.healWeight or 1) * (healing[e.guid] or 0))
			if p then
				p:setBankBalance(p:getBankBalance() + gold)
			else
				-- logged out in the arena: the share still reaches the bank
				db.query(string.format("UPDATE `players` SET `balance` = `balance` + %d WHERE `id` = %d", gold, e.guid))
			end
			db.query(string.format("INSERT INTO `%s` (`guild_id`, `week`, `player_id`, `name`, `spoils`, `contribution`, `updated_at`) " ..
				"VALUES (%d, %d, %d, %s, %d, %d, %d) ON DUPLICATE KEY UPDATE `spoils` = %d, `contribution` = %d, `name` = VALUES(`name`)",
				T().contrib, run.gid, run.week, e.guid, db.escapeString(e.name or (p and p:getName()) or ""), gold, contribution, now(),
				gold, contribution))
			pcall(G().logRow, run.gid, p or e, "boss", gold, 0, 0, string.format("share of the guild boss gold: %s of %s",
				B.money(gold), B.money(pool)))
			if p then
				local inbox = false
				local parts = {string.format("%s gold to your bank (%d%% of the guild's %s)", B.money(gold),
					pool > 0 and math.floor(gold * 100 / pool + 0.5) or 0, B.money(pool))}
				for _, o in ipairs(r.orbs) do
					local it = ItemType(o.id)
					if it and it:getId() ~= 0 then
						inbox = giveStack(p, o.id, o.count) or inbox
						parts[#parts + 1] = string.format("%d %s", o.count, o.count == 1 and it:getName() or it:getPluralName())
					end
				end
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "Spoils of the guild boss: %s.", table.concat(parts, ", ")) ..
					(inbox and " " .. Chaos.t(p, "Your backpack was full: the rest is in your inbox.") or ""))
				if ChaosPack29Vfx then -- pair 29 (switch off: the stock firework)
					ChaosPack29Vfx.celebrate(p:getPosition(), "boss", CONST_ME_FIREWORK_YELLOW)
				else
					p:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
				end
				-- exclusives.lua: the rare personal drop of a visual exclusive (rewarded members online at the kill)
				if ChaosExclusives and ChaosExclusives.bossKill then pcall(ChaosExclusives.bossKill, p, "guild_" .. cfg.boss.key) end
			end
		elseif p then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "You did too little of the damage for a share of the spoils."))
		end
	end
	for _, m in ipairs(G().onlineMembers(run.gid)) do
		pcall(GB.syncLockout, m)
	end
	local tier, bname = B.banner(GB.killsOf(run.gid), cfg)
	G().tellGuild(run.gid, function(lang)
		return ChaosI18n.text(lang, "Your guild slew %s in %s with %d members!%s", cfg.boss.boss, B.clockText(secs), size,
			tier > 0 and ChaosI18n.text(lang, " The hall flies the %s.", bname) or "")
	end)
	pcall(G().furnish, run.gid)
	sendHud(run, "update")
	for id in pairs(run.players) do
		local p = Player(id)
		if p and HUD then
			Chaos.send(p, HUD, "end", {result = "success", text = Chaos.tx(p, run.endText), exitIn = cfg.exitDelay})
		end
	end
	log(string.format("run %d: guild %d slew the guild boss in %d s with %d player(s)", run.id, run.gid, secs, size))
	addEvent(function(slot, rid)
		local rr = GB.runs[slot]
		if rr and rr.id == rid and not rr.ended then
			finishExit(rr)
		end
	end, cfg.exitDelay * 1000, run.slot, run.id)
end
GB._success = success

-- ======================================================================== the fight (uber.lua's, with this config)
local COMBAT = {physical = "COMBAT_PHYSICALDAMAGE", death = "COMBAT_DEATHDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	fire = "COMBAT_FIREDAMAGE"}
local hitFn = doTargetCombat or doTargetCombatHealth

local function arenaPlayers(run)
	local out = {}
	for id, e in pairs(run.players) do
		local p = Player(id)
		if p and not e.down and U.inArena(run.L, p:getPosition()) then
			out[#out + 1] = p
		end
	end
	return out
end

local function setHealth(monster, hp)
	monster:setMaxHealth(hp)
	local missing = hp - monster:getHealth()
	if missing > 0 then
		Chaos.heal(monster, missing)
	end
end

-- a share of max health as one scripted hit of the boss; a Hollow Vessel counts health + maximum energy shield
-- (Chaos.percentBase)
local function shareHit(run, player, share)
	local boss = bossOf(run)
	local dmg = U.shareDamage(Chaos.percentBase(player), share)
	run.scripted = true
	if hitFn then
		pcall(hitFn, boss and boss:getId() or 0, player, _G[COMBAT[C().boss.element] or "COMBAT_PHYSICALDAMAGE"] or COMBAT_PHYSICALDAMAGE,
			-dmg, -dmg, CONST_ME_NONE, ORIGIN_SPELL)
	end
	run.scripted = false
end

local function freeArenaTile(run, near, spread)
	local L = run.L
	for _ = 1, 12 do
		local pos = {x = near.x + rand(-spread, spread), y = near.y + rand(-spread, spread), z = L.z}
		if U.inArena(L, pos) then
			local tile = Tile(P(pos))
			if tile and not tile:getTopCreature() then
				return P(pos)
			end
		end
	end
	return P(L.center)
end

local function spawnAdds(run, adds)
	local cfg = C()
	local n = U.addCount(adds, run.size)
	local boss = bossOf(run)
	local at = boss and boss:getPosition() or P(run.L.center)
	local hp
	local made = 0
	for _ = 1, n do
		local m = Game.createMonster(cfg.boss.add, freeArenaTile(run, at, 4), false, true)
		if m then
			hp = hp or math.floor(m:getMaxHealth() * B.addHealthMult(cfg, run.size))
			setHealth(m, hp)
			GB.monsterRun[m:getId()] = run
			run.adds[m:getId()] = true
			made = made + 1
		end
	end
	if made > 0 then
		say(run, ChaosI18n.msg(made == 1 and "%s raises %d %s!" or "%s raises %d %ss!", cfg.boss.boss, made, cfg.boss.add),
			MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR)
	end
end

local function telegraph(run, name)
	local cfg = C()
	local boss = bossOf(run)
	if not boss then
		return
	end
	local ppos = {}
	for _, p in ipairs(arenaPlayers(run)) do
		local pp = p:getPosition()
		ppos[#ppos + 1] = {x = pp.x, y = pp.y, z = pp.z}
	end
	if ChaosBossMech and ChaosBossMech.busy and ChaosBossMech.busy(boss) then
		return -- a blast, soak or channel of the shared mechanics is running (boss_mechanics.lua)
	end
	local bp = boss:getPosition()
	local target = boss:getTarget()
	local tp = target and target:getPosition() or (ppos[1] and P(ppos[1])) or nil
	local tiles, info = U.pattern(name, cfg, {L = run.L, boss = {x = bp.x, y = bp.y, z = bp.z},
		target = tp and {x = tp.x, y = tp.y, z = tp.z} or nil, players = ppos, rand = rand,
		size = ChaosBossMech and ChaosBossMech.sizeOf and ChaosBossMech.sizeOf(cfg.boss.boss) or 1})
	if #tiles == 0 then
		return
	end
	local timing = U.telegraphTiming(cfg, run.enraged)
	-- fairness (boss_mechanics_core.lua): every player keeps a safe tile in walking reach of the warning
	local G = ChaosBossMechCore
	if G and #ppos > 0 then
		run.mechGrid = run.mechGrid or G.grid(run.L.floorList)
		local fair = ChaosBossMech and ChaosBossMech.fairOf and ChaosBossMech.fairOf(cfg.boss.boss) or {refLevel = 300}
		local straight, diag = G.stepCosts(fair)
		tiles = G.makeFair(run.mechGrid, tiles, ppos, G.budget(timing.hitMs, fair), straight, diag, {x = bp.x, y = bp.y})
		if #tiles == 0 then
			return
		end
	end
	local set = U.tileSet(tiles)
	if ChaosBossMech and ChaosBossMech.cast then
		pcall(ChaosBossMech.cast, boss, name, timing.hitMs)
	end
	local rid, slot = run.id, run.slot
	local function live()
		local r = GB.runs[slot]
		return r and r.id == rid and r.state == "running" and r.boss == "alive" and r or nil
	end
	local plan = U.markPlan(tiles)
	for i, ms in ipairs(timing.marks) do
		local filling = timing.kinds and timing.kinds[i] == "fill"
		local effect = filling and cfg.telegraph.fillEffect or cfg.telegraph.warnEffect
		addEvent(function()
			if not live() then
				return
			end
			if i == 1 then
				bigFx("telegraph", tiles)
			end
			for _, t in ipairs(plan.big) do
				fx(P(t), effect, CONST_ME_MAGIC_RED)
			end
			for _, t in ipairs(plan.small) do
				P(t):sendMagicEffect(filling and CONST_ME_DRAWBLOOD or CONST_ME_MAGIC_RED)
			end
			if info.safe then
				P(info.safe):sendMagicEffect(CONST_ME_MAGIC_GREEN)
			end
		end, ms)
	end
	addEvent(function()
		local r = live()
		if not r then
			return
		end
		for i, t in ipairs(tiles) do
			if i % 2 == 1 then
				fx(P(t), cfg.boss.hitEffect, CONST_ME_MORTAREA)
			end
		end
		bigFx("bossHit", tiles, cfg.boss.element)
		local nowS = os.time()
		for _, p in ipairs(arenaPlayers(r)) do
			local pp = p:getPosition()
			local e = r.players[p:getId()]
			if set[U.key(pp.x, pp.y)] and not (e and (e.shieldUntil or 0) > nowS) then
				shareHit(r, p, timing.share)
			end
		end
	end, timing.hitMs)
end

local function placeHazard(run, h)
	local tiles = U.hazardTiles(h, {L = run.L, rand = rand, playerCount = run.size})
	run.hazard = {h = h, tiles = tiles, set = U.tileSet(tiles), placedAt = mnow()}
end

local function startPhase(run, idx)
	local def = C().boss
	local ph = def.phases[idx]
	if not ph then
		return
	end
	local boss = bossOf(run)
	if boss and ph.yell then
		Chaos.yell(boss, ph.yell)
	end
	if idx > 1 then
		say(run, ChaosI18n.msg("%s enters phase %d of %d: %s.", def.boss, idx, #def.phases, ph.name),
			MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR)
	end
	run.hazard = nil
	if ph.hazard then
		placeHazard(run, ph.hazard)
	end
	if ph.adds then
		spawnAdds(run, ph.adds)
		run.nextAdds = ph.adds.every > 0 and (mnow() + ph.adds.every) or nil
	else
		run.nextAdds = nil
	end
	run.nextHeal = mnow() + 5000
	run.nextPattern = mnow() + 3000
	sendHud(run, "update")
end

local function hazardStep(run, t)
	local hz = run.hazard
	if not hz then
		return
	end
	local cfg = C()
	local every = hz.h.moveMs or hz.h.lastMs
	if every and t - hz.placedAt >= every then
		placeHazard(run, hz.h)
		hz = run.hazard
	end
	if t < (run.nextHazardPulse or 0) then
		return
	end
	run.nextHazardPulse = t + cfg.hazard.pulseMs
	for _, tile in ipairs(hz.tiles) do
		fx(P(tile), hz.h.effect, CONST_ME_HITBYFIRE)
	end
	local nowS = os.time()
	for _, p in ipairs(arenaPlayers(run)) do
		local pp = p:getPosition()
		local e = run.players[p:getId()]
		if hz.set[U.key(pp.x, pp.y)] and not (e and (e.shieldUntil or 0) > nowS) then
			shareHit(run, p, cfg.hazard.share)
		end
	end
end

local function spawnBoss(run)
	local cfg = C()
	local def = cfg.boss
	-- O177: the boss shows the level the fight is for (minLevel), not the species' experience / health estimate
	local m = Chaos.createMonsterNamed(def.boss, P(run.L.bossSpawn), false, true, nil, cfg.minLevel)
	if not m then
		log("cannot create " .. def.boss .. " (is data/monster/monsters/chaos/guildboss registered?); the fuel is returned")
		db.query(string.format("UPDATE `%s` SET `fuel` = `fuel` + %d, `attempts` = GREATEST(`attempts`, 1) - 1 WHERE `guild_id` = %d AND `week` = %d",
			T().week, run.need, run.gid, run.week))
		run.recorded = true
		run.state = "failed"
		run.endText = "The stone did not answer; its embers are returned."
		say(run, run.endText)
		finishExit(run)
		return
	end
	setHealth(m, math.floor(m:getMaxHealth() * B.healthMult(cfg, run.size)))
	m:registerEvent("ChaosGuildBossDeath")
	m:registerEvent("ChaosGuildBossDamage")
	GB.monsterRun[m:getId()] = run
	run.bossId = m:getId()
	-- boss mechanics (boss_mechanics.lua): the standard channel, the shared oath soak and the Gnawed stacks on top of
	-- the phases; their hits go through shareHit (the lethal-hit catch)
	if ChaosBossMech and ChaosBossMech.attach then
		local rid, slot = run.id, run.slot
		pcall(ChaosBossMech.attach, m, def.boss, {tiles = run.L.floorList,
			players = function()
				local r = GB.runs[slot]
				return (r and r.id == rid) and arenaPlayers(r) or {}
			end,
			hit = function(p, share)
				local r = GB.runs[slot]
				if r and r.id == rid then
					shareHit(r, p, share)
				end
			end})
	end
	run.boss = "alive"
	run.bossAt = mnow()
	run.phase = 0
	fx(m:getPosition(), "shadow_eruption", CONST_ME_MORTAREA)
	U.advancePhase(run, def, 1)
	startPhase(run, 1)
	say(run, ChaosI18n.msg("%s answers the stone! Enrage in %s, the arena closes in %s.", def.boss, B.clockText(def.enrageAt),
		B.clockText(def.limit)))
end

local function tick(slot, rid)
	local run = GB.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local cfg = C()
	local def = cfg.boss
	local t = mnow()
	for id, e in pairs(run.players) do
		local p = Player(id)
		if not p then
			removePlayer(run, id, "logout")
		else
			local pos = p:getPosition()
			if not U.inArena(run.L, pos) and not U.inAnte(run.L, pos) then
				removePlayer(run, id, "stay")
				say(run, ChaosI18n.msg("%s left the arena.", e.name))
			end
		end
	end
	if run.ended or GB.runs[slot] ~= run then
		return
	end
	-- strangers in this slot (a town portal or a stored hideout spot let them in): out (chaos_constants.lua)
	if Chaos.sweepDue and Chaos.sweepDue(run, t) then
		Chaos.sweepIntruders(function(pos) return U.slotAt(cfg, pos) == slot end,
			function(p) return run.players[p:getId()] ~= nil end, "You are not part of this guild boss fight: you were sent to your temple.")
	end
	if run.state == "running" and run.boss == "waiting" and t >= (run.bossDueAt or 0) then
		spawnBoss(run)
	end
	if run.ended then
		return
	end
	if run.state == "running" and run.boss == "alive" then
		local enraged, _, toLimit = U.clock(def, (t - run.bossAt) / 1000)
		if toLimit <= 0 then
			fail(run, ChaosI18n.msg("Time is up: %s still stands.", def.boss))
			return
		end
		if enraged and not run.enraged then
			run.enraged = true
			run.nextPulse = t + cfg.enrage.pulseMs
			say(run, ChaosI18n.msg("%s is ENRAGED: every hit is far stronger and the telegraphs come twice as fast.", def.boss))
		end
		local boss = bossOf(run)
		if boss then
			local frac = boss:getHealth() / math.max(1, boss:getMaxHealth())
			for _, idx in ipairs(U.advancePhase(run, def, frac)) do
				startPhase(run, idx)
			end
			local ph = def.phases[run.phase] or def.phases[1]
			if t >= (run.nextPattern or 0) then
				run.nextPattern = t + U.patternEvery(cfg, ph, run.enraged)
				telegraph(run, ph.patterns[rand(1, #ph.patterns)])
			end
			if run.nextAdds and t >= run.nextAdds and ph.adds then
				run.nextAdds = t + ph.adds.every
				spawnAdds(run, ph.adds)
			end
			if ph.heal and t >= (run.nextHeal or 0) then
				run.nextHeal = t + 5000
				local liveAdds = 0
				for mid in pairs(run.adds) do
					if Monster(mid) then
						liveAdds = liveAdds + 1
					else
						run.adds[mid] = nil
					end
				end
				local amount = U.harvestHeal(ph.heal, liveAdds, boss:getMaxHealth())
				if amount > 0 then
					Chaos.heal(boss, amount)
				end
			end
			if run.enraged and t >= (run.nextPulse or 0) then
				run.nextPulse = t + cfg.enrage.pulseMs
				for _, p in ipairs(arenaPlayers(run)) do
					shareHit(run, p, cfg.enrage.pulseShare)
				end
			end
			hazardStep(run, t)
			if not boss:getTarget() and #arenaPlayers(run) == 0 then
				boss:teleportTo(P(run.L.bossSpawn))
			end
		end
	end
	if run.ended then
		return
	end
	if run.state == "running" and ChaosInstanceLimits then -- warnings before the end (instance_limits.lua)
		ChaosInstanceLimits.warn(run, timeLeft(run, t), ChaosInstanceLimits.playersOf(run.players), cfg.boss.boss, cfg.limits)
	end
	if t >= (run.nextHud or 0) then
		run.nextHud = t + cfg.hudEvery * 1000
		sendHud(run, "update")
	end
	addEvent(tick, cfg.tickMs, slot, rid)
end
GB._tick = tick

-- ======================================================================== summoning
local function insideOther(player)
	return (ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player))
		or (ChaosAscended and ChaosAscended.isInside and ChaosAscended.isInside(player))
		or (ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player))
end

function GB.summon(player)
	local cfg = C()
	local gid, gname, rank = G().guildOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	local week = weekNow()
	local row = GB.weekRow(gid, week)
	local info = summonInfo(player, gid, rank, row)
	local why = B.summonError(info, cfg)
	if why then
		return false, why
	end
	if player:getLevel() < cfg.minLevel then
		return false, string.format("You need level %d to face the guild boss.", cfg.minLevel)
	end
	local group = {}
	for _, m in ipairs(hallGroup(player, gid)) do
		if not insideOther(m) and m:getLevel() >= cfg.minLevel then
			group[#group + 1] = m
		end
	end
	if #group < cfg.minPlayers then
		return false, string.format("At least %d members (level %d+) must stand in the hall.", cfg.minPlayers, cfg.minLevel)
	end
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(GB.runs) do
		running = running + 1
	end
	local slot, L
	if not (IL and IL.capped("guildboss", running, cfg.limits)) then
		slot, L = takeSlot("guildboss")
	end
	if not slot then
		if IL then
			local lefts, t = {}, mnow()
			for _, r in pairs(GB.runs) do
				lefts[#lefts + 1] = r.state == "running" and timeLeft(r, t) or cfg.exitDelay
			end
			return false, IL.busy(player, "guildboss", "guild boss arenas", lefts, cfg.limits)
		end
		return false, "Every guild boss arena is in use. Try again in a moment."
	end
	if G().exec(string.format("UPDATE `%s` SET `fuel` = `fuel` - %d, `attempts` = `attempts` + 1, `updated_at` = %d WHERE `guild_id` = %d " ..
			"AND `week` = %d AND `fuel` >= %d AND `killed_at` = 0 AND `attempts` < %d", T().week, info.need, now(), gid, week, info.need,
			cfg.maxAttempts)) ~= 1 then
		return false, "The Summoning Stone is not ready."
	end
	cleanSlot(L)
	GB.nextId = GB.nextId + 1
	local run = {id = GB.nextId, slot = slot, L = L, gid = gid, guildName = gname, week = week, need = info.need, players = {},
		adds = {}, damage = {}, healers = {}, healing = {}, state = "running", boss = "waiting", size = #group, startedAt = now(),
		bossDueAt = mnow() + cfg.startDelay * 1000, deaths = 0}
	run.lives = B.livesFor(cfg, #group)
	run.livesMax = run.lives
	GB.runs[slot] = run
	GB.guildRun[gid] = run
	for i, m in ipairs(group) do
		local from = m:getPosition()
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), name = m:getName(), entry = from}
		GB.runOf[m:getId()] = run
		eventsOn(m)
		from:sendMagicEffect(CONST_ME_TELEPORT)
		m:teleportTo(P(L.starts[(i - 1) % #L.starts + 1] or L.entry))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
	say(run, ChaosI18n.msg(run.lives == 1 and "%s: %s comes in %d seconds. %s, %d shared life. Lethal hits send you to the Ember Gate." or
		"%s: %s comes in %d seconds. %s, %d shared lives. Lethal hits send you to the Ember Gate.",
		gname, cfg.boss.boss, cfg.startDelay, B.clockText(cfg.boss.limit), run.lives))
	G().tellGuild(gid, ChaosI18n.msg("%s woke the guild boss with %d members.", player:getName(), #group))
	sendHud(run, "start")
	log(string.format("%s summoned run %d for guild %d: slot %d, %d player(s)", player:getName(), run.id, gid, slot, #group))
	addEvent(tick, cfg.tickMs, slot, run.id)
	return true, nil
end

function GB.isInside(player)
	return GB.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("guildboss", {label = "the guild boss arena", inside = GB.isInside, at = function(pos)
	return U.slotAt(C(), pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out = {}
	for slot, run in pairs(GB.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.id, what = string.format("%s, slot %d, %s", tostring(run.guildName), slot, run.state),
			left = run.state == "running" and timeLeft(run, mnow()) or nil, players = n}
	end
	return out
end, close = function(id) -- a failed attempt, as when the time runs out (failKeep of the fuel stays)
	for _, run in pairs(GB.runs) do
		if run.id == id and not run.ended then
			if run.state == "running" then
				fail(run, "A gamemaster closed the arena.")
			else
				finishExit(run)
			end
			return true, "Guild boss run " .. id .. " closed."
		end
	end
	return false, "No running guild boss arena " .. tostring(id) .. "."
end})

local function fall(run, pid)
	local cfg = C()
	local entry = run.players[pid]
	local p = Player(pid)
	if not entry or entry.down or not p or run.state ~= "running" then
		return
	end
	run.deaths = run.deaths + 1
	run.lives = math.max(0, run.lives - 1)
	if run.lives <= 0 then
		say(run, ChaosI18n.msg("%s falls, and with them the arena's last life.", p:getName()))
		fail(run, "No lives are left!")
		return
	end
	entry.down = true
	entry.reenterAt = os.time() + cfg.lives.reenterSeconds
	p:teleportTo(P(run.L.anteStart))
	p:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	Chaos.heal(p, p:getMaxHealth() - p:getHealth())
	p:addMana(p:getMaxMana() - p:getMana())
	say(run, ChaosI18n.msg(run.lives == 1 and "%s falls: %d shared life left. The Ember Gate lets them back in %d seconds." or
		"%s falls: %d shared lives left. The Ember Gate lets them back in %d seconds.", p:getName(), run.lives, cfg.lives.reenterSeconds))
	sendHud(run, "update")
end

function GB.gate(player)
	local cfg = C()
	local run = GB.runOf[player:getId()]
	local entry = run and run.players[player:getId()]
	if not entry or run.state ~= "running" then
		return false
	end
	local t = os.time()
	if not entry.down then
		player:teleportTo(P(run.L.entry))
		return true
	end
	if t < (entry.reenterAt or 0) then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "The Ember Gate opens for you in %d seconds.", entry.reenterAt - t))
		player:teleportTo(P(run.L.anteStart))
		return false
	end
	entry.down = false
	entry.shieldUntil = t + cfg.lives.shieldSeconds
	player:teleportTo(P(run.L.entry))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	sendHud(run, "update")
	return true
end

-- ======================================================================== protocol (routed by guildwar.lua)
local function limited(player, key, ms)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, key, ms or 1000)
end

function GB.handle(player, action, data)
	if limited(player, "guildboss.act", 1000) then
		return false, "Slow down.", true -- refused: guildwar.lua answers without the state (a database read)
	end
	if action == "bossGold" then
		return donateGold(player, data.amount)
	elseif action == "bossItem" then
		return donateItems(player, data.key)
	elseif action == "bossSummon" then
		local ok, text = GB.summon(player)
		if ok then
			return true, text or ChaosI18n.msg("%s is coming.", C().boss.boss)
		end
		return false, text
	end
	return nil, nil
end

-- ======================================================================== events
local gate = MoveEvent()
function gate.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if player then
		GB.gate(player)
	end
	return true
end
gate:type("stepin")
gate:aid(C().portalActionId)
gate:register()

local bossDeath = CreatureEvent("ChaosGuildBossDeath")
function bossDeath.onDeath(creature)
	local run = GB.monsterRun[creature:getId()]
	GB.monsterRun[creature:getId()] = nil
	if run and run.bossId == creature:getId() and run.state == "running" and not run.ended then
		run.bossId = nil
		addEvent(function(slot, rid)
			local r = GB.runs[slot]
			if r and r.id == rid and r.state == "running" and not r.ended then
				success(r)
			end
		end, 0, run.slot, run.id)
	end
	return true
end
bossDeath:register()

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

-- the damage each participant deals to the boss (rewards, the board)
local bossDamage = CreatureEvent("ChaosGuildBossDamage")
function bossDamage.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local run = GB.monsterRun[creature:getId()]
	local p = playerOf(attacker)
	if run and p and run.players[p:getId()] and primaryType ~= COMBAT_HEALING then
		local guid = p:getGuid()
		local amount = math.abs(primaryDamage or 0) + (secondaryType ~= COMBAT_HEALING and math.abs(secondaryDamage or 0) or 0)
		run.damage[guid] = (run.damage[guid] or 0) + math.min(amount, creature:getHealth())
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
bossDamage:register()

local function scaled(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local run = GB.runOf[creature:getId()]
	if not run or run.state ~= "running" then
		return primaryDamage, primaryType, secondaryDamage, secondaryType, nil
	end
	if primaryType == COMBAT_HEALING then
		local healer = playerOf(attacker)
		if healer and healer:getId() ~= creature:getId() and run.players[healer:getId()] then
			run.healers[healer:getGuid()] = true
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType, nil
	end
	local entry = run.players[creature:getId()]
	local fromRun = attacker and GB.monsterRun[attacker:getId()] == run
	if entry and (entry.down or (entry.shieldUntil or 0) > os.time()) and (fromRun or run.scripted) then
		return 0, primaryType, 0, secondaryType, run
	end
	if fromRun and not run.scripted and run.enraged then
		local mult = U.damageMult(C(), true)
		primaryDamage = math.floor(primaryDamage * mult)
		if secondaryType ~= COMBAT_HEALING then
			secondaryDamage = math.floor(secondaryDamage * mult)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType, run
end

-- the healing a participant does to the others (what restores missing health): their contribution to the gold split
local function countHealing(creature, attacker, amount)
	local run = GB.runOf[creature:getId()]
	local healer = playerOf(attacker)
	if run and run.state == "running" and healer and healer:getId() ~= creature:getId() and run.players[healer:getId()] then
		local missing = math.max(0, creature:getMaxHealth() - creature:getHealth())
		local guid = healer:getGuid()
		run.healing[guid] = (run.healing[guid] or 0) + math.min(math.abs(amount or 0), missing)
	end
end
GB._countHealing = countHealing

local playerHit = CreatureEvent("ChaosGuildBossPlayerHit")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		countHealing(creature, attacker, primaryDamage)
	end
	local run
	primaryDamage, primaryType, secondaryDamage, secondaryType, run = scaled(creature, attacker, primaryDamage, primaryType,
		secondaryDamage, secondaryType)
	if not run then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local sign = primaryDamage < 0 and -1 or 1
	local pool = creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)
	local healSecondary = secondaryType == COMBAT_HEALING
	local p, s, caught = U.catchDamage(pool, primaryDamage, healSecondary and 0 or secondaryDamage)
	if caught then
		addEvent(function(slot, rid, pid)
			local r = GB.runs[slot]
			if r and r.id == rid then
				fall(r, pid)
			end
		end, 0, run.slot, run.id, creature:getId())
	end
	return sign * p, primaryType, healSecondary and secondaryDamage or sign * s, secondaryType
end
playerHit:register()

local playerMana = CreatureEvent("ChaosGuildBossPlayerMana")
function playerMana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local p, pt, s, st = scaled(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	return p, pt, s, st
end
playerMana:register()

local prepare = CreatureEvent("ChaosGuildBossPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local run = GB.runOf[creature:getId()]
	if not run or run.state ~= "running" then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	addEvent(function(slot, rid, pid)
		local r = GB.runs[slot]
		if r and r.id == rid then
			fall(r, pid)
		end
	end, 0, run.slot, run.id, creature:getId())
	return false
end
prepare:register()

local logout = CreatureEvent("ChaosGuildBossLogout")
function logout.onLogout(player)
	if next(GB.runs) ~= nil and serverClosing() then
		GB.interruptAll()
	end
	local run = GB.runOf[player:getId()]
	if run then
		say(run, ChaosI18n.msg("%s left the arena.", player:getName()))
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:register()

local login = CreatureEvent("ChaosGuildBossLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGuildBossLogout")
	GB.wrapFurnish()
	if U.slotAt(C(), player:getPosition()) and not GB.runOf[player:getId()] then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	pcall(GB.syncLockout, player)
	return true
end
login:register()

local shutdown = GlobalEvent("ChaosGuildBossShutdown")
function shutdown.onShutdown()
	GB.interruptAll()
	return true
end
shutdown:register()

local startup = GlobalEvent("ChaosGuildBossStartup")
function startup.onStartup()
	GB.ensureTables()
	tierSkip()
	GB.wrapFurnish()
	-- halls already furnished before the wrap (guild_hall.lua's startup builds nothing; halls are built on entry)
	return true
end
startup:register()

-- ======================================================================== staff: /guildboss
-- /guildboss                       the runs;  /guildboss fuel, <guild>, <embers>;  /guildboss reset, <guild>
-- /guildboss phase, <n>            your run's boss to phase n;  /guildboss end: your run fails
local function onCommand(player, param)
	local args = {}
	for a in (param or ""):gmatch("[^,]+") do
		args[#args + 1] = a:gsub("^%s+", ""):gsub("%s+$", "")
	end
	local cmd = (args[1] or ""):lower()
	local run = GB.runOf[player:getId()]
	local function guildId(name)
		local r = Chaos.select("SELECT `id` FROM `guilds` WHERE `name` = " .. db.escapeString(name or ""), {{"id", "n"}})[1]
		return r and r.id
	end
	if cmd == "fuel" then
		local gid = guildId(args[2])
		if gid then
			GB.weekRow(gid)
			addFuel(gid, math.max(0, math.floor(tonumber(args[3]) or 0)))
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: %d embers.", args[2], GB.weekRow(gid).fuel))
		end
	elseif cmd == "reset" then
		local gid = guildId(args[2])
		if gid then
			db.query(string.format("DELETE FROM `%s` WHERE `guild_id` = %d AND `week` = %d", T().week, gid, weekNow()))
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: this week's guild boss row reset.", args[2]))
		end
	elseif cmd == "phase" and run and bossOf(run) then
		local ph = C().boss.phases[tonumber(args[2]) or 2]
		local boss = bossOf(run)
		if ph and hitFn then
			local cut = boss:getHealth() - (math.floor(boss:getMaxHealth() * ph.at) - 1)
			if cut > 0 then
				pcall(hitFn, 0, boss, COMBAT_UNDEFINEDDAMAGE, -cut, -cut, CONST_ME_NONE, ORIGIN_NONE)
			end
		end
	elseif cmd == "end" and run then
		fail(run, "Ended by the staff.")
	else
		local lines = {}
		for slot, r in pairs(GB.runs) do
			local n = 0
			for _ in pairs(r.players) do
				n = n + 1
			end
			lines[#lines + 1] = string.format("slot %d: %s, %s, %d player(s), lives %d/%d, phase %d", slot, r.guildName, r.state, n,
				r.lives, r.livesMax, r.phase or 0)
		end
		player:showTextDialog(C().stoneId, #lines > 0 and table.concat(lines, "\n") or "No guild boss arena is open.")
	end
end

local talk = TalkAction("/guildboss")
function talk.onSay(player, words, param)
	local g = player:getGroup()
	if not g or g:getId() < C().staffGroup then
		return true
	end
	onCommand(player, param)
	return false
end
talk:separator(" ")
talk:register()

if db and db.query then
	pcall(GB.ensureTables)
end
