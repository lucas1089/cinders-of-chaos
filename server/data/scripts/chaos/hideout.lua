-- Hideouts: a personal room for every character, built at runtime (Game.createTile, like the guild halls) in a pooled
-- slot of hideout_config.lua `grid` when someone enters and torn down (its items removed, the slot back in the pool)
-- when it has been empty for `emptySeconds`. The engine cannot remove tiles: built tiles stay and are reused.
-- Settings: hideout_config.lua. Pure rules: hideout_core.lua (tests: server/tests/hideout_test.lua). Overview:
-- server/README.md "Hideouts". Client: game_hideout (Character > Hideout).
--
--   entry      Character > Hideout (Enter), or the forcefield next to every temple (aid.enter): your own hideout.
--              Visits: the window's Visit tab (friends, party, guild, the public showcase, recent visits). Refused
--              in a fight (pz-lock or the fight icon), with a skull, and where the Town Portal is refused (arena,
--              world boss, siege, rifts, dungeons, the tower, the tutorial). The exit forcefield leads back to the
--              spot you entered from (storages, also after a logout inside), else the temple.
--   decorate   the owner, inside the own hideout: place / move (with rotation) / remove decorations of the unlocked
--              catalogue; hideout_core.lua K.placeProblem keeps one object per tile, a rug under it, wall decorations
--              on the north / west wall, the fixture tiles free, a path to every fixture, and the limits.
--   utilities  the owner's depot of their home town (a locker; its depot id is set with engine patch 0017's
--              item:unserializeAttributes, else the locker refuses and says to use a town depot), the supply stash,
--              two exercise dummies, the base server's waystone device in the middle of the room (its portal pads on
--              the four diagonal tiles; patch_waystone_hideout.py lets the base action accept the own hideout).
--              No buffs, nothing that changes a fight.
--   access     permission private / friends (VIP list, party) / guild / public; season and standard characters never
--              mix while a season runs; staff (group cfg.staffGroup+) may enter any. A visitor who loses access (the
--              owner changed it) is sent out at once. No player may attack another inside; items dropped inside go
--              back to the player; decorations and fixtures cannot be moved.
--   social     unique visits per day, likes (one per account and hideout, inside it, cfg.likes.perDay a day), the
--              showcase of public hideouts by likes and by visits.
--   unlocks    hideout_config.lua sources; an earned unlock is kept (chaos_hideout_unlocks) even if the source fades
--              (a faction rank lost to a rival); store decorations per account (ChaosHideout.storeUnlock, giftable).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.hideout (192); server -> client through Chaos.sendChunked:
--   client -> server  open | get | enter | leave | visit {guid} | place {key, x, y, r} | move {id, x, y, r} |
--                     remove {id} | clear | theme {key} | perm {level} | kick | visits | like {owner}
--   server -> client  state {open, me, hideout, inside, layout, themes, catalogue, placed, permissions, categories}
--                     visits {friends, showcase = {likes, visits}, recent}   result {ok, text}
-- API: ChaosHideout.isInside(pos), .isOwnRoomTile(player, pos), .isFixture(item), .waystoneDevice(player), .enter(player, ownerGuid), .leave(player),
--      .storeUnlock(name),
--      .sourceProbes.journey = fn(player) -> chapters done (the season journey sets it; else probed by name)
-- Staff: /hideout <character> (enter that character's hideout)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/hideout_core.lua")
ChaosHideoutConfig = dofile("data/scripts/chaos/hideout_config.lua")
if not ChaosCityPortals then
	dofile("data/scripts/chaos/cityportals.lua")
end
if not ChaosDarkTiles then
	pcall(dofile, "data/lib/chaos_dark_tiles.lua")
end

ChaosHideout = ChaosHideout or {}
local M = ChaosHideout
local K = ChaosHideoutCore
local cfg = ChaosHideoutConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.hideout) or cfg.opcode
local T = cfg.tables
local ST = cfg.storage
local A = cfg.aid

M.pool = M.pool or K.poolNew(cfg)
M.rooms = M.rooms or {} -- slot -> {owner, theme, emptySince, parts = {[decor id] = {{pos, id}}}, town}
M.data = M.data or {} -- owner guid -> {theme, perm, visits, likes, decor = {{id, key, x, y, rot}}}
M.built = M.built or {} -- slot -> true once its tiles exist
M.sourceProbes = M.sourceProbes or {}

local function log(text)
	print("[Chaos hideout] " .. text)
end

local function now()
	return os.time()
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function try(fn)
	local ok, res = pcall(fn)
	return ok and res or nil
end

local function exec(q)
	return db.query(q)
end

-- ---------------------------------------------------------------- tables
local TABLES = {
	"CREATE TABLE IF NOT EXISTS `%s` (`player_id` int(11) NOT NULL, `theme` varchar(32) NOT NULL DEFAULT '', " ..
		"`permission` tinyint(3) unsigned NOT NULL DEFAULT 1, `visits` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`likes` int(10) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`), KEY `chaos_hideouts_perm` (`permission`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`player_id` int(11) NOT NULL, `decor_id` smallint(5) unsigned NOT NULL, " ..
		"`decor` varchar(32) NOT NULL, `x` tinyint(3) unsigned NOT NULL, `y` tinyint(3) unsigned NOT NULL, " ..
		"`rot` tinyint(3) unsigned NOT NULL DEFAULT 1, PRIMARY KEY (`player_id`, `decor_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`account_id` int(11) NOT NULL, `player_id` int(11) NOT NULL, " ..
		"`unlock_key` varchar(40) NOT NULL, `source` varchar(16) NOT NULL DEFAULT '', `created_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`account_id`, `player_id`, `unlock_key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`owner_id` int(11) NOT NULL, `visitor_id` int(11) NOT NULL, " ..
		"`day` int(10) unsigned NOT NULL DEFAULT 0, `visited_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`owner_id`, `visitor_id`), KEY `chaos_hideout_visits_visitor` (`visitor_id`, `visited_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`owner_id` int(11) NOT NULL, `account_id` int(11) NOT NULL, " ..
		"`liked_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`owner_id`, `account_id`), " ..
		"KEY `chaos_hideout_likes_account` (`account_id`, `liked_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
}

function M.ensureTables()
	local names = {T.hideouts, T.decor, T.unlocks, T.visits, T.likes}
	for i, q in ipairs(TABLES) do
		db.query(string.format(q, names[i]))
	end
end

-- ---------------------------------------------------------------- data of a hideout
function M.load(guid)
	local d = M.data[guid]
	if d then
		return d
	end
	d = {theme = K.defaultTheme(cfg).key, perm = cfg.defaultPermission, visits = 0, likes = 0, decor = {}}
	local row = Chaos.select(string.format("SELECT `theme`, `permission`, `visits`, `likes` FROM `%s` WHERE `player_id` = %d",
		T.hideouts, guid), {{"theme", "s"}, {"permission", "n"}, {"visits", "n"}, {"likes", "n"}})[1]
	if row then
		d.theme = K.theme(cfg, row.theme) and row.theme or d.theme
		d.perm, d.visits, d.likes = row.permission, row.visits, row.likes
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `decor_id`, `decor`, `x`, `y`, `rot` FROM `%s` WHERE `player_id` = %d " ..
			"ORDER BY `decor_id`", T.decor, guid), {{"decor_id", "n"}, {"decor", "s"}, {"x", "n"}, {"y", "n"}, {"rot", "n"}})) do
		if K.deco(cfg, r.decor) then
			d.decor[#d.decor + 1] = {id = r.decor_id, key = r.decor, x = r.x, y = r.y, rot = r.rot}
		end
	end
	M.data[guid] = d
	return d
end

local function saveMeta(guid)
	local d = M.load(guid)
	exec(string.format("INSERT INTO `%s` (`player_id`, `theme`, `permission`, `updated_at`) VALUES (%d, %s, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `theme` = VALUES(`theme`), `permission` = VALUES(`permission`), `updated_at` = VALUES(`updated_at`)",
		T.hideouts, guid, db.escapeString(d.theme), d.perm, now()))
end

local function bump(guid, column)
	exec(string.format("INSERT INTO `%s` (`player_id`, `theme`, `permission`, `%s`, `updated_at`) VALUES (%d, %s, %d, 1, %d) " ..
		"ON DUPLICATE KEY UPDATE `%s` = `%s` + 1", T.hideouts, column, guid, db.escapeString(M.load(guid).theme),
		M.load(guid).perm, now(), column, column))
	local d = M.load(guid)
	d[column] = (d[column] or 0) + 1
end

local function nameOf(guid)
	local p = Player(guid)
	if p then
		return p:getName()
	end
	local r = Chaos.select("SELECT `name` FROM `players` WHERE `id` = " .. math.floor(guid), {{"name", "s"}})[1]
	return r and r.name or nil
end

local function accountOf(guid)
	local p = Player(guid)
	if p then
		return p:getAccountId()
	end
	local r = Chaos.select("SELECT `account_id` FROM `players` WHERE `id` = " .. math.floor(guid), {{"account_id", "n"}})[1]
	return r and r.account_id or 0
end

-- ---------------------------------------------------------------- unlocks
local factionsCfg
local function factionNames(player)
	factionsCfg = factionsCfg or Chaos.factionsConfig or try(function()
		return dofile("data/scripts/chaos/factions_config.lua")
	end)
	local names = {faction = {}, rank = {}, achievement = {}}
	for _, f in ipairs((factionsCfg or {}).factions or {}) do
		names.faction[f.key] = f.name
	end
	for _, r in ipairs((factionsCfg or {}).ranks or {}) do
		names.rank[r.key] = r.name
	end
	local data = ChaosAchievements and ChaosAchievements.data
	for _, a in ipairs(data and data.list or {}) do
		names.achievement[a.id] = a.name
	end
	if player then
		names.tr = function(key, ...)
			return Chaos.t(player, key, ...)
		end
	end
	return names
end

local function statOf(guid, name)
	local A2 = ChaosAchievements
	local live = A2 and A2.stats and A2.stats[guid]
	if live then
		return live[name] or 0
	end
	local r = Chaos.select(string.format("SELECT `value` FROM `chaos_achievement_stats` WHERE `player_id` = %d AND `stat` = %s",
		guid, db.escapeString(name)), {{"value", "n"}})[1]
	return r and r.value or 0
end

-- chapters of a season journey the character finished (best season); nil while no journey system is loaded.
-- ChaosHideout.sourceProbes.journey = fn(player) -> number replaces the default (season_journey.lua's table)
local function journeyChapters(player)
	local probe = M.sourceProbes.journey
	if probe then
		local ok, n = pcall(probe, player)
		return ok and tonumber(n) or nil
	end
	if not ChaosSeasonJourney then
		return nil
	end
	local r = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `chaos_season_journey` WHERE `player_id` = %d AND " ..
		"`entry` LIKE 'c:%%' GROUP BY `season` ORDER BY `n` DESC LIMIT 1", player:getGuid()), {{"n", "n"}})[1]
	return r and r.n or 0
end

-- the facts of hideout_core.lua K.sourceMet / K.owned for an online character
function M.factsOf(player)
	local guid, acc = player:getGuid(), player:getAccountId()
	local facts = {earned = {}, store = {}}
	for _, r in ipairs(Chaos.select(string.format("SELECT `player_id`, `unlock_key` FROM `%s` WHERE `account_id` = %d AND " ..
			"`player_id` IN (0, %d)", T.unlocks, acc, guid), {{"player_id", "n"}, {"unlock_key", "s"}})) do
		if r.player_id == 0 then
			facts.store[r.unlock_key] = true
		else
			facts.earned[r.unlock_key] = true
		end
	end
	facts.achievement = function(id)
		return ChaosAchievements ~= nil and ChaosAchievements.has ~= nil and ChaosAchievements.has(player, id) == true
	end
	facts.stat = function(name)
		return statOf(guid, name)
	end
	facts.factionRank = function(fkey)
		local F, FK = ChaosFactions, ChaosFactionsCore
		if not (F and F.stateOf and FK and FK.rankAt) then
			return nil
		end
		factionsCfg = factionsCfg or Chaos.factionsConfig
		local P2 = F.stateOf(player)
		local e = P2 and P2.st and P2.st[fkey]
		return (FK.rankAt(factionsCfg, e and e.rep or 0))
	end
	local dsc = Chaos.select(string.format("SELECT `best_depth`, `best_clear` FROM `chaos_descent_players` WHERE `player_id` = %d", guid),
		{{"best_depth", "n"}, {"best_clear", "n"}})[1]
	facts.descent = {best = dsc and dsc.best_depth or 0, clear = dsc ~= nil and dsc.best_clear > 0}
	facts.journey = journeyChapters(player)
	return facts
end

-- keep every source met now as an earned unlock (it stays when the source fades)
function M.syncUnlocks(player, facts)
	local guid, acc = player:getGuid(), player:getAccountId()
	local function keep(entry, isTheme)
		local k = K.unlockKey(entry, isTheme)
		local src = entry.source or {type = "default"}
		if src.type ~= "default" and src.type ~= "store" and not facts.earned[k] and K.sourceMet(cfg, src, facts) then
			facts.earned[k] = true
			exec(string.format("INSERT IGNORE INTO `%s` (`account_id`, `player_id`, `unlock_key`, `source`, `created_at`) " ..
				"VALUES (%d, %d, %s, %s, %d)", T.unlocks, acc, guid, db.escapeString(k), db.escapeString(src.type), now()))
		end
	end
	for _, t in ipairs(cfg.themes) do
		keep(t, true)
	end
	for _, d in ipairs(cfg.decorations) do
		keep(d)
	end
end

local function storeOwned(accountId, decoKey)
	return Chaos.select(string.format("SELECT `unlock_key` FROM `%s` WHERE `account_id` = %d AND `player_id` = 0 AND `unlock_key` = %s",
		T.unlocks, accountId, db.escapeString(decoKey)), {{"unlock_key", "s"}})[1] ~= nil
end

-- the store side (shop_services.lua unlockEntry): offer {kind = "unlock", unlock = "hideout_<key>"}
function M.storeUnlock(unlockName)
	if type(unlockName) ~= "string" or unlockName:sub(1, 8) ~= "hideout_" then
		return nil
	end
	local d = K.deco(cfg, unlockName:sub(9))
	if not d or not d.source or d.source.type ~= "store" then
		return nil
	end
	return {
		name = d.name .. " (hideout decoration)",
		done = "Place it in your hideout: Character > Hideout (every character of your account, cosmetic only).",
		owned = function(player)
			return storeOwned(player:getAccountId(), d.key)
		end,
		grant = function(player)
			exec(string.format("INSERT IGNORE INTO `%s` (`account_id`, `player_id`, `unlock_key`, `source`, `created_at`) " ..
				"VALUES (%d, 0, %s, 'store', %d)", T.unlocks, player:getAccountId(), db.escapeString(d.key), now()))
			if storeOwned(player:getAccountId(), d.key) then
				log(string.format("%s unlocked %s (store)", player:getName(), d.key))
				return true
			end
			return false, "The decoration could not be saved. Your coins were refunded."
		end
	}
end

-- ---------------------------------------------------------------- building
-- the ground of a theme (the dark tile set's when installed)
local function groundOf(t)
	if t.dark and t.dark.ground and ChaosDarkTiles and ChaosDarkTiles.id then
		return ChaosDarkTiles.id(t.dark.ground, t.ground)
	end
	return t.ground
end

-- the wall item of a theme at a wall tile: the family piece, or the dark set's tall wall on the north / west walls
local function wallOf(t, gx, gy)
	local piece, back = K.wallPiece(cfg, gx, gy)
	if not piece then
		return nil
	end
	if back and t.dark and t.dark.wall and ChaosDarkTiles and ChaosDarkTiles.id then
		local dark = ChaosDarkTiles.id(t.dark.wall, nil)
		if dark then
			return dark
		end
	end
	return t.walls[piece]
end

local OUR_GROUNDS, OUR_WALLS = {}, {}
for _, t in ipairs(cfg.themes) do
	OUR_GROUNDS[t.ground], OUR_GROUNDS[groundOf(t)] = true, true
	for _, id in pairs(t.walls) do
		OUR_WALLS[id] = true
	end
	local dark = t.dark and t.dark.wall and ChaosDarkTiles and ChaosDarkTiles.id and ChaosDarkTiles.id(t.dark.wall, nil)
	if dark then
		OUR_WALLS[dark] = true
	end
end

local function groundIdOf(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

-- create the tiles of a slot once; false when a map tile is in the way (the pool skips that slot for good)
function M.buildTiles(slot)
	if M.built[slot] then
		return true
	end
	local foot = K.footprint(cfg, slot)
	for _, t in ipairs(foot) do
		local tile = Tile(P(t))
		if tile and (not OUR_GROUNDS[groundIdOf(tile)] or (tile.getHouse and tile:getHouse())) then
			log(string.format("slot %d unusable: tile %d,%d,%d is in the map", slot, t.x, t.y, t.z))
			return false
		end
	end
	local t0 = K.defaultTheme(cfg)
	local g0 = groundOf(t0)
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Tile(pos) or Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(g0, 1, pos)
			end
			if t.wall then
				local has = false
				for id in pairs(OUR_WALLS) do
					if tile:getItemById(id) then
						has = true
					end
				end
				if not has then
					Game.createItem(wallOf(t0, t.gx, t.gy), 1, pos)
				end
			end
		end
	end
	M.built[slot] = true
	return true
end

local function applyTheme(slot, themeKey)
	local t = K.theme(cfg, themeKey) or K.defaultTheme(cfg)
	local g = groundOf(t)
	for _, f in ipairs(K.footprint(cfg, slot)) do
		local tile = Tile(P(f))
		if tile then
			local gr = tile:getGround()
			if gr and type(gr) ~= "number" and gr:getId() ~= g and OUR_GROUNDS[gr:getId()] then
				gr:transform(g)
			end
			if f.wall then
				local w = wallOf(t, f.gx, f.gy)
				for id in pairs(OUR_WALLS) do
					local it = tile:getItemById(id)
					if it and id ~= w then
						it:transform(w)
					end
				end
			end
		end
	end
	return t
end

-- remove every item of the room except the ground and the walls
local function clearRoom(slot)
	for _, f in ipairs(K.footprint(cfg, slot)) do
		local tile = Tile(P(f))
		if tile then
			local list = {}
			for _, it in ipairs(tile:getItems() or {}) do
				if not (f.wall and OUR_WALLS[it:getId()]) then
					list[#list + 1] = it
				end
			end
			for _, it in ipairs(list) do
				it:remove()
			end
		end
	end
end

local function removeAt(pos, id)
	local tile = Tile(P(pos))
	local it = tile and tile:getItemById(id)
	if it then
		it:remove()
	end
end

local function trophyText(d, ownerGuid)
	if not d.trophy then
		return nil
	end
	local n = statOf(ownerGuid, d.trophy.stat)
	-- one key per form (pt-BR has no "s" to add): the look of the item translates it (itemdesc_i18n.lua)
	if n == 1 then
		return string.format("A trophy of %s: %s, slain once.", nameOf(ownerGuid) or "its owner", d.trophy.boss)
	end
	return string.format("A trophy of %s: %s, slain %d times.", nameOf(ownerGuid) or "its owner", d.trophy.boss, n)
end

local function placeItems(slot, room, p)
	local d = K.deco(cfg, p.key)
	if not d then
		return
	end
	local side = d.layer == "wall" and K.wallSide(cfg, p.x, p.y) or nil
	local list = {}
	local text = trophyText(d, room.owner)
	for _, part in ipairs(K.parts(d, p.rot, side) or {}) do
		local pos = K.toWorld(cfg, slot, p.x + part[1], p.y + part[2])
		local it = part[3] and Game.createItem(part[3], 1, P(pos))
		if it then
			it:setActionId(A.decor)
			if text then
				it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
			end
			list[#list + 1] = {pos = pos, id = part[3]}
		end
	end
	room.parts[p.id] = list
end

local function unplaceItems(room, id)
	for _, e in ipairs(room.parts[id] or {}) do
		removeAt(e.pos, e.id)
	end
	room.parts[id] = nil
end

local function townOf(guid)
	local p = Player(guid)
	if p then
		local t = p:getTown()
		return t and t:getId() or 0
	end
	local r = Chaos.select("SELECT `town_id` FROM `players` WHERE `id` = " .. math.floor(guid), {{"town_id", "n"}})[1]
	return r and r.town_id or 0
end

-- the locker opens the owner's depot of `town` (ATTR_DEPOT_ID = 10, u16, read by DepotLocker::readAttr)
local function placeLocker(pos, town)
	local it = Game.createItem(cfg.ids.depot, 1)
	if not it then
		return false
	end
	local ok = false
	if it.unserializeAttributes and town and town > 0 then
		ok = it:unserializeAttributes(string.char(10, town % 256, math.floor(town / 256) % 256)) == true
	end
	local tile = Tile(P(pos))
	if not tile or not tile.addItemEx then
		return false
	end
	tile:addItemEx(it)
	it:setActionId(A.depot)
	it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, ok and "The depot of your home town." or
		"This depot cannot open here (the server lacks engine patch 0017). Use a town depot.")
	return ok
end

local function fixtureItem(pos, id, aid, text)
	local it = Game.createItem(id, 1, P(pos))
	if it then
		if aid then
			it:setActionId(aid)
		end
		if text then
			it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
		end
	end
	return it
end

-- build the room of `owner` in `slot`: theme, fixtures, decorations
function M.furnish(slot, owner)
	if not M.buildTiles(slot) then
		return false
	end
	local d = M.load(owner)
	clearRoom(slot)
	local theme = applyTheme(slot, d.theme)
	local room = {owner = owner, theme = theme.key, parts = {}, town = townOf(owner)}
	M.rooms[slot] = room
	local f = cfg.fixtures
	local function at(p)
		return K.toWorld(cfg, slot, p[1], p[2])
	end
	fixtureItem(at(f.exit), cfg.ids.portal, A.exit, "The way back to where you came from.")
	room.depotOk = placeLocker(at(f.depot), room.town)
	fixtureItem(at(f.stash), cfg.ids.stash, A.stash, "Your supply stash. Use it to open the stash window.")
	for i, p in ipairs(f.dummies) do
		fixtureItem(at(p), cfg.ids.dummies[(i - 1) % #cfg.ids.dummies + 1], A.fixture)
	end
	for _, p in ipairs(f.lights) do
		fixtureItem(at(p), theme.light, A.fixture)
	end
	if f.waystone and cfg.ids.waystone then
		-- the base server's waystone device: its own action id (the base action opens the waystone window) and
		-- the hideout accepts it through ChaosHideout.isOwnRoomTile (patch_waystone_hideout.py)
		fixtureItem(at(f.waystone), cfg.ids.waystone, A.waystone, "The waystone device of your hideout. Use it to open the waystone window.")
	end
	for _, p in ipairs(d.decor) do
		placeItems(slot, room, p)
	end
	return true
end

-- tear a room down: its items go, the slot goes back to the pool (tiles, ground and walls stay for the next owner)
function M.teardown(slot)
	clearRoom(slot)
	M.rooms[slot] = nil
	K.poolRelease(M.pool, slot)
end

-- ---------------------------------------------------------------- where
function M.isInside(pos)
	local slot = pos and K.fromWorld(cfg, pos)
	return slot ~= nil and M.built[slot] == true
end

Chaos.registerInstance("hideout", {label = "a hideout", at = M.isInside})

-- slot, room of the hideout a position is in
function M.roomAt(pos)
	local slot = pos and K.fromWorld(cfg, pos)
	if not slot then
		return nil
	end
	return slot, M.rooms[slot]
end

local function center(slot)
	return K.toWorld(cfg, slot, math.floor(cfg.inner.w / 2) + 1, math.floor(cfg.inner.h / 2) + 1)
end

local function playersIn(slot)
	local c = center(slot)
	local rx, ry = math.floor(cfg.inner.w / 2) + 2, math.floor(cfg.inner.h / 2) + 2
	local out = {}
	for _, cr in ipairs(Game.getSpectators(P(c), false, true, rx, rx, ry, ry) or {}) do
		local p = cr:getPlayer()
		if p and K.fromWorld(cfg, p:getPosition()) == slot then
			out[#out + 1] = p
		end
	end
	return out
end

-- may a character be put on this tile now (the exit's destination): ground, walkable, no portal or stairs, not in an
-- instance area (a raid, a battleground, ...: its run may belong to another group now)
local function usableSpot(p)
	local tile = Tile(P(p))
	if not tile or not tile:getGround() then
		return false
	end
	if tile.hasProperty and CONST_PROP_BLOCKSOLID and tile:hasProperty(CONST_PROP_BLOCKSOLID) then
		return false
	end
	if tile.hasFlag and ((TILESTATE_TELEPORT and tile:hasFlag(TILESTATE_TELEPORT)) or
			(TILESTATE_FLOORCHANGE and tile:hasFlag(TILESTATE_FLOORCHANGE))) then
		return false
	end
	if (ITEM_TYPE_TELEPORT and tile.getItemByType and tile:getItemByType(ITEM_TYPE_TELEPORT)) or tile:getItemById(cfg.ids.portal) then
		return false
	end
	if Chaos.instanceAt and Chaos.instanceAt(p, "hideout") then
		return false
	end
	return true
end

local function templeOfTown(id)
	local town = id and Town and Town(id)
	local t = town and town:getTemplePosition()
	return t and t.x > 0 and t or nil
end

-- ---------------------------------------------------------------- access
local function isStaff(player)
	local g = player:getGroup()
	return g ~= nil and g:getId() >= (cfg.staffGroup or 4)
end

local function guildIdOf(guid)
	local p = Player(guid)
	if p then
		local g = p:getGuild()
		return g and g:getId() or 0
	end
	local r = Chaos.select("SELECT `guild_id` FROM `guild_membership` WHERE `player_id` = " .. math.floor(guid), {{"guild_id", "n"}})[1]
	return r and r.guild_id or 0
end

local function partyLeader(player)
	local party = player and player:getParty()
	local leader = party and party:getLeader()
	return leader and leader:getId() or nil
end

local function realmOf(guid)
	if ChaosSeason and ChaosSeason.realmOfGuid then
		return try(function()
			return ChaosSeason.realmOfGuid(guid)
		end) or 0
	end
	return 0
end

-- relation of a visitor to a hideout owner (hideout_core.lua K.mayVisit)
function M.relation(ownerGuid, visitor)
	local vg = visitor:getGuid()
	local rel = {self = vg == ownerGuid, staff = isStaff(visitor)}
	if rel.self then
		return rel
	end
	local acc = accountOf(ownerGuid)
	rel.vip = Chaos.select(string.format("SELECT `player_id` FROM `account_viplist` WHERE `account_id` = %d AND `player_id` = %d",
		acc, vg), {{"player_id", "n"}})[1] ~= nil
	local owner = Player(ownerGuid)
	local l1, l2 = partyLeader(owner), partyLeader(visitor)
	rel.party = l1 ~= nil and l1 == l2
	local g = guildIdOf(ownerGuid)
	rel.guild = g > 0 and g == guildIdOf(vg)
	rel.realmMismatch = realmOf(ownerGuid) ~= realmOf(vg)
	return rel
end

local function enterFacts(player)
	local pos = player:getPosition()
	local skull = player:getSkull()
	return {
		tutorial = try(function() return ChaosNewPlayer and ChaosNewPlayer.onIsland and ChaosNewPlayer.onIsland(pos) end),
		arena = try(function() return ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) end),
		worldBoss = try(function() return ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(pos) end),
		siege = try(function() return ChaosSiege and ChaosSiege.locate and ChaosSiege.locate(pos) ~= nil end),
		rift = try(function()
			return ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player)
				or (ChaosRiftCore and ChaosRiftConfig and ChaosRiftCore.slotOfPos(ChaosRiftConfig, pos) ~= nil)
		end),
		dungeon = try(function() return ChaosDungeonIsInside and ChaosDungeonIsInside(player) end),
		tower = try(function() return ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player) end),
		-- every registered instance (raid, Ember Descent, Ascended, guild boss, battleground, trials, the Marches, ...);
		-- the hideout itself is left out: moving from one hideout to another is allowed (M.enter)
		instance = Chaos.inAnyInstance and Chaos.inAnyInstance(player, "hideout") ~= nil or false,
		pzLocked = player:isPzLocked(),
		inFight = CONDITION_INFIGHT ~= nil and player:getCondition(CONDITION_INFIGHT) ~= nil,
		skull = skull == SKULL_WHITE or skull == SKULL_RED or skull == SKULL_BLACK
	}
end

local function result(player, ok, text)
	text = Chaos.t(player, text) -- the core's refusals are English keys
	Chaos.send(player, OPCODE, "result", {ok = ok, text = text})
	if not ok then
		player:sendCancelMessage(text)
	end
end

local function countVisit(owner, visitor)
	if accountOf(owner) == visitor:getAccountId() then
		return
	end
	local today = Chaos.dayKey()
	local r = Chaos.select(string.format("SELECT `day` FROM `%s` WHERE `owner_id` = %d AND `visitor_id` = %d", T.visits, owner,
		visitor:getGuid()), {{"day", "n"}})[1]
	exec(string.format("INSERT INTO `%s` (`owner_id`, `visitor_id`, `day`, `visited_at`) VALUES (%d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `day` = VALUES(`day`), `visited_at` = VALUES(`visited_at`)", T.visits, owner, visitor:getGuid(),
		today, now()))
	if K.countsVisit(r and r.day or nil, today) then
		bump(owner, "visits")
	end
end

-- send `player` to the hideout of `owner` (a guid); false + text when refused. `back`: the spot the exit leads to
-- (the Hideout Portal passes the tile the character stepped from, never the portal itself); default: where they stand
function M.enter(player, owner, back)
	owner = tonumber(owner) or player:getGuid()
	local here = player:getPosition()
	back = back or here
	local fromSlot = K.fromWorld(cfg, here)
	local inside = fromSlot ~= nil
	if not inside then
		local problem = K.enterProblem(enterFacts(player))
		if problem then
			return false, problem
		end
	end
	local name = nameOf(owner)
	if not name then
		return false, "There is no such character."
	end
	local d = M.load(owner)
	local ok, why = K.mayVisit(d.perm, M.relation(owner, player))
	if not ok then
		return false, why
	end
	local slot, fresh = K.poolAcquire(M.pool, owner, M.buildTiles)
	if not slot then
		return false, K.enterProblem({full = true})
	end
	if fresh or not M.rooms[slot] then
		if not M.furnish(slot, owner) then
			K.poolRelease(M.pool, slot)
			return false, "This hideout cannot be built right now. Tell a gamemaster."
		end
	end
	if not inside then
		player:setStorageValue(ST.returnX, back.x)
		player:setStorageValue(ST.returnY, back.y)
		player:setStorageValue(ST.returnZ, back.z)
		player:setStorageValue(ST.returnSet, 1)
	end
	M.rooms[slot].emptySince = nil
	local arrival = K.toWorld(cfg, slot, cfg.fixtures.arrival[1], cfg.fixtures.arrival[2])
	here:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(P(arrival))
	P(arrival):sendMagicEffect(CONST_ME_TELEPORT)
	-- the Town Portal is a way out from inside (townportal.lua); the engine refuses its spell while the 60 s cooldown
	-- condition of the last portal runs ("You are exhausted."), so that condition is lifted here (playtest 2026-10-16)
	if ChaosTownPortal and ChaosTownPortal.liftSpellCooldown then
		ChaosTownPortal.liftSpellCooldown(player)
	end
	if owner == player:getGuid() then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Welcome home. Character > Hideout to decorate. The portal south of you, or Leave in that window, takes you back."))
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You visit the hideout of %s.", name))
		countVisit(owner, player)
	end
	return true
end

-- where leaving sends `player` (hideout_core.lua K.exitDestination): the spot they entered from, a free tile next
-- to it, the home temple, Cinderhold's temple
function M.exitDestination(player)
	local stored
	if player:getStorageValue(ST.returnSet) == 1 then
		stored = {x = player:getStorageValue(ST.returnX), y = player:getStorageValue(ST.returnY),
			z = player:getStorageValue(ST.returnZ)}
	end
	local town = player:getTown()
	local home = town and town:getTemplePosition()
	if home and home.x <= 0 then
		home = nil
	end
	local dest, why = K.exitDestination(cfg, {stored = stored, usable = usableSpot, home = home,
		fallback = templeOfTown(cfg.mainTown)})
	return dest and P(dest) or nil, why
end

-- back to the spot the player entered from (or the temple)
function M.leave(player, text)
	local dest = M.exitDestination(player)
	if not dest then
		-- no temple on this map at all: stay put rather than loop (cannot happen on a map with towns)
		log("no way out of the hideout for " .. player:getName())
		return false
	end
	player:setStorageValue(ST.returnSet, 0)
	player:teleportTo(dest)
	dest:sendMagicEffect(CONST_ME_TELEPORT)
	if ChaosTownPortal and ChaosTownPortal.restoreSpellCooldown then
		ChaosTownPortal.restoreSpellCooldown(player) -- the action bar shows what is left of the portal's cooldown again
	end
	if text then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, text))
	end
	return true
end

-- visitors who may no longer be in a hideout leave it
local function recheckVisitors(slot)
	local room = M.rooms[slot]
	if not room then
		return
	end
	local d = M.load(room.owner)
	for _, p in ipairs(playersIn(slot)) do
		if not K.mayVisit(d.perm, M.relation(room.owner, p)) then
			M.leave(p, "The owner closed this hideout to you.")
		end
	end
end

-- ---------------------------------------------------------------- the window
-- true when pos is a tile of the hideout that `player` owns (the base waystone device asks this instead of "is it a
-- house", server/tools/patch_waystone_hideout.py)
function M.isOwnRoomTile(player, pos)
	if not player or not pos then
		return false
	end
	local _, room = M.roomAt(pos)
	return room ~= nil and room.owner == player:getGuid()
end

-- true when `item` is the waystone device built into a hideout (it is never wrapped or moved)
function M.isFixture(item)
	if not item or not item.getActionId or item:getActionId() ~= A.waystone then
		return false
	end
	local _, room = M.roomAt(item:getPosition())
	return room ~= nil
end

local function inOwnRoom(player)
	local slot, room = M.roomAt(player:getPosition())
	if room and room.owner == player:getGuid() then
		return slot, room
	end
	return nil
end

-- the waystone device of the hideout the player stands in, when it is the player's own (nil elsewhere, or while the
-- device is busy: the base script swaps it for its lit look for a minute). A Waystone Tier used there opens the
-- device's window (patch_waystone_hideout.py part 2: the tier item's own action).
function M.waystoneDevice(player)
	local f = cfg.fixtures.waystone
	if not player or not f or not cfg.ids.waystone then
		return nil
	end
	local slot = inOwnRoom(player)
	if not slot then
		return nil
	end
	local tile = Tile(P(K.toWorld(cfg, slot, f[1], f[2])))
	local it = tile and tile:getItemById(cfg.ids.waystone)
	if it and it:getActionId() == A.waystone then
		return it
	end
	return nil
end

local function clientId(id)
	local it = id and ItemType(id)
	local c = it and it:getClientId() or 0
	return c > 0 and c or id
end

function M.sendState(player, open)
	local guid = player:getGuid()
	local d = M.load(guid)
	local facts = M.factsOf(player)
	M.syncUnlocks(player, facts)
	local names = factionNames(player)
	local theme = K.theme(cfg, d.theme) or K.defaultTheme(cfg)
	local inside
	local slot, room = M.roomAt(player:getPosition())
	if room then
		local o = K.slotOrigin(cfg, slot)
		inside = {owner = room.owner, ownerName = nameOf(room.owner), isOwner = room.owner == guid, origin = o}
	end
	local placed = {}
	for i, p in ipairs(d.decor) do
		placed[i] = {id = p.id, key = p.key, x = p.x, y = p.y, r = p.rot}
	end
	local cats = {}
	for i, c in ipairs(cfg.categories) do
		cats[i] = {key = c.key, name = c.name}
	end
	local perms = {}
	for i, p in ipairs(cfg.permissions) do
		perms[i] = {id = p.id, name = p.name, desc = p.desc}
	end
	local themes = K.themesView(cfg, facts, names, theme.key, clientId)
	local catalogue = K.catalogueView(cfg, facts, d.decor, names, clientId)
	-- the window's texts (descriptions, how to unlock) in the player's language; names stay as they are
	for _, t in ipairs(themes) do
		t.desc = Chaos.tx(player, t.desc)
	end
	for _, p in ipairs(perms) do
		p.name, p.desc = Chaos.tx(player, p.name), Chaos.tx(player, p.desc)
	end
	local data = {open = open == true, me = guid, inside = inside, layout = K.layoutView(cfg),
		hideout = {theme = theme.key, themeName = theme.name, perm = d.perm, likes = d.likes, visits = d.visits,
			count = #d.decor, max = theme.maxDecor},
		themes = themes,
		catalogue = catalogue, placed = placed, permissions = perms,
		categories = cats}
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = data}))
end

local function ownedNow(player, entry, isTheme)
	local facts = M.factsOf(player)
	M.syncUnlocks(player, facts)
	return K.owned(cfg, entry, facts, isTheme)
end

local function persistDecor(guid, p, isNew)
	if isNew then
		exec(string.format("INSERT INTO `%s` (`player_id`, `decor_id`, `decor`, `x`, `y`, `rot`) VALUES (%d, %d, %s, %d, %d, %d)",
			T.decor, guid, p.id, db.escapeString(p.key), p.x, p.y, p.rot))
	else
		exec(string.format("UPDATE `%s` SET `x` = %d, `y` = %d, `rot` = %d WHERE `player_id` = %d AND `decor_id` = %d",
			T.decor, p.x, p.y, p.rot, guid, p.id))
	end
end

function M.place(player, key, x, y, rot)
	local slot, room = inOwnRoom(player)
	if not slot then
		return false, "Decorate inside your own hideout."
	end
	local d = K.deco(cfg, tostring(key or ""))
	if not d then
		return false, "Unknown decoration."
	end
	if not ownedNow(player, d) then
		return false, Chaos.t(player, "%s is locked: %s.", d.name, K.sourceText(cfg, d.source, factionNames(player)))
	end
	local data = M.load(player:getGuid())
	local cand = {key = d.key, x = Chaos.toInt(x, 0, 64) or -1, y = Chaos.toInt(y, 0, 64) or -1, rot = K.rot(d, rot)}
	local problem = K.placeProblem(cfg, data.theme, data.decor, cand)
	if problem then
		return false, problem
	end
	cand.id = K.nextId(data.decor)
	data.decor[#data.decor + 1] = cand
	persistDecor(player:getGuid(), cand, true)
	placeItems(slot, room, cand)
	return true, Chaos.t(player, "%s placed.", d.name)
end

local function findDecor(data, id)
	id = tonumber(id)
	for i, p in ipairs(data.decor) do
		if p.id == id then
			return p, i
		end
	end
	return nil
end

function M.move(player, id, x, y, rot)
	local slot, room = inOwnRoom(player)
	if not slot then
		return false, "Decorate inside your own hideout."
	end
	local data = M.load(player:getGuid())
	local p = findDecor(data, id)
	if not p then
		return false, "That decoration is gone."
	end
	local d = K.deco(cfg, p.key)
	local cand = {key = p.key, x = Chaos.toInt(x, 0, 64) or -1, y = Chaos.toInt(y, 0, 64) or -1, rot = K.rot(d, rot)}
	local problem = K.placeProblem(cfg, data.theme, data.decor, cand, p.id)
	if problem then
		return false, problem
	end
	unplaceItems(room, p.id)
	p.x, p.y, p.rot = cand.x, cand.y, cand.rot
	persistDecor(player:getGuid(), p, false)
	placeItems(slot, room, p)
	return true, Chaos.t(player, "%s moved.", d.name)
end

function M.remove(player, id)
	local guid = player:getGuid()
	local data = M.load(guid)
	local p, i = findDecor(data, id)
	if not p then
		return false, "That decoration is gone."
	end
	table.remove(data.decor, i)
	exec(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `decor_id` = %d", T.decor, guid, p.id))
	local slot = K.poolSlotOf(M.pool, guid)
	if slot and M.rooms[slot] then
		unplaceItems(M.rooms[slot], p.id)
	end
	local d = K.deco(cfg, p.key)
	return true, d and Chaos.t(player, "%s removed.", d.name) or Chaos.t(player, "The decoration was removed.")
end

function M.clear(player)
	local guid = player:getGuid()
	local data = M.load(guid)
	local slot = K.poolSlotOf(M.pool, guid)
	for _, p in ipairs(data.decor) do
		if slot and M.rooms[slot] then
			unplaceItems(M.rooms[slot], p.id)
		end
	end
	data.decor = {}
	exec(string.format("DELETE FROM `%s` WHERE `player_id` = %d", T.decor, guid))
	return true, "Every decoration was put away."
end

function M.setTheme(player, key)
	local t = K.theme(cfg, tostring(key or ""))
	if not t then
		return false, "Unknown theme."
	end
	if not ownedNow(player, t, true) then
		return false, Chaos.t(player, "%s is locked: %s.", t.name, K.sourceText(cfg, t.source, factionNames(player)))
	end
	local guid = player:getGuid()
	local data = M.load(guid)
	if #data.decor > t.maxDecor then
		return false, Chaos.t(player, "%s holds %d decorations; put %d away first.", t.name, t.maxDecor, #data.decor - t.maxDecor)
	end
	data.theme = t.key
	saveMeta(guid)
	local slot = K.poolSlotOf(M.pool, guid)
	local room = slot and M.rooms[slot]
	if room then
		applyTheme(slot, t.key)
		room.theme = t.key
		local f = cfg.fixtures
		for _, p in ipairs(f.lights) do
			local pos = K.toWorld(cfg, slot, p[1], p[2])
			local tile = Tile(P(pos))
			for _, it in ipairs(tile and tile:getItems() or {}) do
				if it:getActionId() == A.fixture then
					it:remove()
				end
			end
			fixtureItem(pos, t.light, A.fixture)
		end
	end
	return true, Chaos.t(player, "Your hideout is now the %s.", t.name)
end

function M.setPermission(player, level)
	level = Chaos.toInt(level, 0, 3)
	if not level then
		return false, "Unknown permission."
	end
	local guid = player:getGuid()
	M.load(guid).perm = level
	saveMeta(guid)
	local slot = K.poolSlotOf(M.pool, guid)
	if slot then
		recheckVisitors(slot)
	end
	return true, Chaos.t(player, "Visitors: %s.", Chaos.tx(player, cfg.permissions[level + 1].name))
end

function M.kick(player)
	local slot = K.poolSlotOf(M.pool, player:getGuid())
	local n = 0
	if slot then
		for _, p in ipairs(playersIn(slot)) do
			if p:getGuid() ~= player:getGuid() and not isStaff(p) then
				M.leave(p, "The owner asked visitors to leave.")
				n = n + 1
			end
		end
	end
	return true, n == 0 and "No visitors are inside." or string.format("%d visitor%s sent out.", n, n == 1 and "" or "s")
end

function M.like(player, owner)
	owner = Chaos.toInt(owner, 1)
	local _, room = M.roomAt(player:getPosition())
	local acc = player:getAccountId()
	local today = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `account_id` = %d AND `liked_at` >= %d",
		T.likes, acc, now() - 86400), {{"n", "n"}})[1]
	local already = owner and Chaos.select(string.format("SELECT `owner_id` FROM `%s` WHERE `owner_id` = %d AND `account_id` = %d",
		T.likes, owner, acc), {{"owner_id", "n"}})[1] ~= nil
	local problem = K.likeProblem({self = owner ~= nil and accountOf(owner) == acc, inside = room ~= nil and room.owner == owner,
		already = already, today = today and today.n or 0, perDay = cfg.likes.perDay})
	if problem then
		return false, problem
	end
	exec(string.format("INSERT IGNORE INTO `%s` (`owner_id`, `account_id`, `liked_at`) VALUES (%d, %d, %d)", T.likes, owner, acc, now()))
	bump(owner, "likes")
	local o = Player(owner)
	if o then
		o:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(o, "%s likes your hideout.", player:getName()))
	end
	return true, "You like this hideout."
end

-- the Visit tab: hideouts this character may enter (VIP list, party, guild), the public showcase, recent visits
function M.sendVisits(player)
	local guid, acc = player:getGuid(), player:getAccountId()
	local cand, order = {}, {}
	local function add(g, why)
		if g and g ~= guid and not cand[g] and #order < cfg.visitListSize then
			cand[g] = why
			order[#order + 1] = g
		end
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `player_id` FROM `account_viplist` WHERE `account_id` = %d LIMIT 50", acc),
			{{"player_id", "n"}})) do
		add(r.player_id, "friend")
	end
	local party = player:getParty()
	if party then
		local leader = party:getLeader()
		add(leader and leader:getGuid(), "party")
		for _, m in ipairs(party:getMembers() or {}) do
			add(m:getGuid(), "party")
		end
	end
	local gid = guildIdOf(guid)
	if gid > 0 then
		for _, r in ipairs(Chaos.select(string.format("SELECT `player_id` FROM `guild_membership` WHERE `guild_id` = %d LIMIT 40", gid),
				{{"player_id", "n"}})) do
			add(r.player_id, "guild")
		end
	end
	local friends = {}
	for _, g in ipairs(order) do
		local d = M.load(g)
		if K.mayVisit(d.perm, M.relation(g, player)) then
			local t = K.theme(cfg, d.theme) or K.defaultTheme(cfg)
			friends[#friends + 1] = {guid = g, name = nameOf(g) or "?", why = cand[g], theme = t.name, likes = d.likes,
				visits = d.visits, online = Player(g) ~= nil}
		end
	end
	local rows = Chaos.select(string.format("SELECT h.`player_id`, p.`name`, h.`theme`, h.`likes`, h.`visits` FROM `%s` h " ..
		"JOIN `players` p ON p.`id` = h.`player_id` WHERE h.`permission` = 3 ORDER BY h.`likes` + h.`visits` DESC LIMIT 100", T.hideouts),
		{{"player_id", "n"}, {"name", "s"}, {"theme", "s"}, {"likes", "n"}, {"visits", "n"}})
	local list = {}
	for _, r in ipairs(rows) do
		local t = K.theme(cfg, r.theme) or K.defaultTheme(cfg)
		list[#list + 1] = {guid = r.player_id, name = r.name, theme = t.name, likes = r.likes, visits = r.visits,
			online = Player(r.player_id) ~= nil}
	end
	local recent = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT v.`owner_id`, p.`name`, v.`visited_at` FROM `%s` v JOIN `players` p ON " ..
			"p.`id` = v.`owner_id` WHERE v.`visitor_id` = %d ORDER BY v.`visited_at` DESC LIMIT 10", T.visits, guid),
			{{"owner_id", "n"}, {"name", "s"}, {"visited_at", "n"}})) do
		recent[#recent + 1] = {guid = r.owner_id, name = r.name, at = os.date("%d.%m %H:%M", r.visited_at)}
	end
	Chaos.sendChunked(player, OPCODE, json.encode({action = "visits", data = {friends = friends,
		showcase = {likes = K.showcase(list, "likes", cfg.showcaseSize), visits = K.showcase(list, "visits", cfg.showcaseSize)},
		recent = recent}}))
end

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosHideoutOpcode")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return true
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.action) ~= "string" then
		return true
	end
	local a, data = msg.action, type(msg.data) == "table" and msg.data or {}
	local R = cfg.requestMs
	local limit = ({open = R.list, get = R.list, visits = R.list, enter = R.visit, visit = R.visit, leave = R.visit,
		like = cfg.likes.cooldownMs})[a] or R.edit
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "hideout." .. a, limit) then
		return true
	end
	local ok, text
	if a == "open" or a == "get" then
		M.sendState(player, a == "open")
		return true
	elseif a == "visits" then
		M.sendVisits(player)
		return true
	elseif a == "enter" then
		ok, text = M.enter(player, player:getGuid())
	elseif a == "visit" then
		ok, text = M.enter(player, Chaos.toInt(data.guid, 1))
	elseif a == "leave" then
		if not K.fromWorld(cfg, player:getPosition()) then
			ok, text = false, "You are not in a hideout."
		else
			ok = M.leave(player)
		end
	elseif a == "place" then
		ok, text = M.place(player, data.key, data.x, data.y, data.r)
	elseif a == "move" then
		ok, text = M.move(player, data.id, data.x, data.y, data.r)
	elseif a == "remove" then
		ok, text = M.remove(player, data.id)
	elseif a == "clear" then
		ok, text = M.clear(player)
	elseif a == "theme" then
		ok, text = M.setTheme(player, data.key)
	elseif a == "perm" then
		ok, text = M.setPermission(player, data.level)
	elseif a == "kick" then
		ok, text = M.kick(player)
	elseif a == "like" then
		ok, text = M.like(player, data.owner)
	else
		return true
	end
	if text then
		result(player, ok == true, text)
	end
	M.sendState(player, false)
	return true
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosHideoutLogin")
function login.onLogin(player)
	player:registerEvent("ChaosHideoutOpcode")
	-- a character that logged out inside a hideout starts outside it (the room may be gone)
	-- (after a server restart the engine already put them at the temple: the room's tiles are gone)
	if K.fromWorld(cfg, player:getPosition()) then
		M.leave(player)
	elseif player:getStorageValue(ST.returnSet) == 1 then
		player:setStorageValue(ST.returnSet, 0) -- left by a death or a restart: the next entry stores a fresh spot
	end
	return true
end
login:type("login")
login:register()

-- the exit forcefield and the temple entry
local exitStep = MoveEvent()
function exitStep.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if player then
		M.leave(player)
	end
	return true
end
exitStep:type("stepin")
exitStep:aid(A.exit)
exitStep:register()

local enterStep = MoveEvent()
function enterStep.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	-- put here by a teleport out of a hideout (an exit, a login inside): never straight back in
	if fromPosition and K.fromWorld(cfg, fromPosition) then
		return true
	end
	-- the exit leads back to the tile stepped from, not onto this portal (that sent the character straight back in)
	local back = fromPosition
	if not back or back.x == 0 or (back.x == position.x and back.y == position.y and back.z == position.z) then
		back = nil
	end
	local ok, text = M.enter(player, player:getGuid(), back)
	if not ok then
		player:sendCancelMessage(Chaos.t(player, text))
		player:teleportTo(fromPosition, true)
		fromPosition:sendMagicEffect(CONST_ME_POFF)
	end
	return true
end
enterStep:type("stepin")
enterStep:aid(A.enter)
enterStep:register()

-- the depot locker: the owner's depot of their home town (the engine opens it when this returns false; it is withdraw-only
-- and its content moves into the stash, depot.lua)
local depotUse = Action()
function depotUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local _, room = M.roomAt(item:getPosition())
	if not room or room.owner ~= player:getGuid() then
		player:sendCancelMessage(Chaos.t(player, "Only the owner of this hideout may open its depot."))
		return true
	end
	if not room.depotOk then
		player:sendCancelMessage(Chaos.t(player, "This depot cannot open here. Use a town depot."))
		return true
	end
	-- the depot is retired (O316): its content moves into the stash and the stash opens (depot.lua)
	if ChaosDepot and ChaosDepot.onOpenLocker and room.town and room.town > 0 then
		ChaosDepot.onOpenLocker(player, item, room.town)
	end
	return false
end
depotUse:aid(A.depot)
depotUse:register()

local stashUse = Action()
function stashUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if ChaosOpcodes.stash then
		Chaos.send(player, ChaosOpcodes.stash, "Stash", {make = "Toggle", remote = true})
	end
	return true
end
stashUse:aid(A.stash)
stashUse:register()

-- decorations do nothing when used (no lamp switching, no transforms)
local decorUse = Action()
function decorUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	return true
end
decorUse:aid(A.decor)
decorUse:register()

-- no player-versus-player inside a hideout
local pvp = EventCallback
pvp.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and target:isPlayer() and
			(M.isInside(target:getPosition()) or M.isInside(creature:getPosition())) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
pvp:register(61)

-- decorations and fixtures stay where they are; anything dropped inside goes back to the player
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item or not player then
		return
	end
	local aid = item:getActionId()
	if aid == A.decor or aid == A.fixture or aid == A.depot or aid == A.stash or aid == A.exit or
		(aid == A.waystone and M.isFixture(item)) then
		if fromPosition and K.fromWorld(cfg, fromPosition) and fromPosition.x ~= (CONTAINER_POSITION or 0xFFFF) then
			item:moveTo(fromPosition)
		end
		return
	end
	if toPosition and toPosition.x ~= (CONTAINER_POSITION or 0xFFFF) and K.fromWorld(cfg, toPosition) then
		if item:getTopParent() ~= player then
			item:moveTo(player)
			player:sendCancelMessage(Chaos.t(player, "Nothing can be left on a hideout's floor."))
		end
	end
end
moved:register(71)

-- empty rooms are torn down after emptySeconds
local think = GlobalEvent("ChaosHideoutThink")
function think.onThink(interval)
	local t = now()
	-- the temple entries: placed at startup and checked again once a minute (like the guild hall's)
	if not M.portalsAt or t - M.portalsAt >= 60 then
		M.portalsAt = t
		pcall(M.placePortals)
	end
	for slot, room in pairs(M.rooms) do
		if #playersIn(slot) > 0 then
			room.emptySince = nil
		elseif not room.emptySince then
			room.emptySince = t
		elseif t - room.emptySince >= cfg.emptySeconds then
			M.teardown(slot)
		end
	end
	return true
end
think:interval(cfg.thinkMs)
think:register()

-- the Hideout Portal of every town (cityportals.lua: the portal gallery at Cinderhold's temple, a fixed spot next to
-- every other temple, labelled and marked by cityportals_fx.lua)
function M.placePortals(say)
	return (ChaosCityPortals.place({kind = "hideout", aid = A.enter, item = cfg.ids.portal, offsets = cfg.portalOffsets,
		log = say and log or nil}))
end

local startup = GlobalEvent("ChaosHideoutStartup")
function startup.onStartup()
	M.ensureTables()
	local n = M.placePortals(true)
	log(string.format("%d Hideout Portal(s) placed; grid %d,%d (%d slots)", n, cfg.grid.origin.x, cfg.grid.origin.y, cfg.grid.maxSlots))
	return true
end
startup:register()

-- staff: /hideout <character>
local staff = TalkAction("/hideout")
function staff.onSay(player, words, param)
	if not isStaff(player) then
		return true
	end
	local guid = Chaos.findPlayer((param or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if not guid then
		player:sendCancelMessage(Chaos.t(player, "No such character."))
		return false
	end
	local ok, text = M.enter(player, guid)
	if not ok then
		player:sendCancelMessage(Chaos.t(player, text))
	end
	return false
end
staff:separator(" ")
staff:register()
