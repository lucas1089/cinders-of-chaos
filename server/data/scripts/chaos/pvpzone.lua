-- The Scorched Marches: an open-world PvP zone with risk and reward (client game_pvpzone, extended opcode 193).
-- Settings: pvpzone_config.lua. Pure part (layout, entry rules, embers, anti-farming, reputation, the shrine contest,
-- the vendor, PvP scaling): pvpzone_core.lua, tested by tests/pvpzone_test.lua. Overview: server/README.md
-- "The Scorched Marches (open-world PvP zone)".
--
-- Flow
--   Adventure > Scorched Marches: the window shows the rules; Enter opens the confirmation (every rule, the risk to the
--   carried embers; Hardcore characters are refused). Level 150+, from a protection zone, out of combat, not
--   multi-clienting, not inside another instance, no defeat cooldown.
--   -> the instance of the player's realm (standard / the running season) is built at runtime if needed; the player
--      arrives next to a safe exit with a short protection.
--   -> inside: open PvP whatever the world type allows through the scripts (the target's secure mode and white skulls
--      do not apply here; party members stay allies), PvP damage scaled like the battleground, stronger monsters that
--      give more experience, loot and embers; the Cinder Shrine contest every two hours.
--   -> a lethal hit is cancelled (nobody dies: no item, experience or blessing loss, no frag): the player is
--      "defeated", thrown out to where he entered, and his carried embers fall as a pile; the killer may take it
--      (bounded) if the defeat passes the anti-farming rules, else it burns.
--   -> leaving: stand in a safe exit circle for a few seconds without fighting: the carried embers are banked.
--      Leaving any other way (a teleport, a GM) burns the carried embers. Logging out inside: the next login holds the
--      character for a moment and puts it at the nearest safe exit, protected.
-- Season realms: one instance per realm, so season and standard characters never meet here (embers never cross).
--
-- Protocol (JSON {action, data}; server -> client through Chaos.sendChunked):
--   client -> server  open | query | enter {accept, hcAccept} | pledge {faction} | buy {key}
--   server -> client  state {...window...} | hud {...} | hide {} | enter {marks = [{kind exit|shrine, x, y, z, name}]} | msg {text, ok}
--   (the client puts the marks on the minimap while the player is inside; floating text over the shrine and the exits
--   every few seconds: beacons())
-- Exports: ChaosPvpZone.isInside(player), .inZone(pos), .targetCombat(creature, target) (the base Creature:onTargetCombat
-- asks it first: tools/patch_base_events.py step 11), .canAttack(caster, target) (ChaosSpell.canAttack),
-- .lootMult(ctx) (loot_config.lua rateMult), .holderOf(realm). Staff: /marches. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
Chaos.pvpZoneConfig = dofile("data/scripts/chaos/pvpzone_config.lua")
dofile("data/scripts/chaos/pvpzone_core.lua")

ChaosPvpZone = ChaosPvpZone or {}
local Z = ChaosPvpZone
local K = ChaosPvpZoneCore
local OPCODE = (ChaosOpcodes and ChaosOpcodes.pvpZone) or 193

local function C()
	return Chaos.pvpZoneConfig
end

local function ST()
	return C().storage
end

Z.inst = Z.inst or {} -- slot -> instance {slot, realm, L, built, points, contest, piles, wardenCid}
Z.state = Z.state or {} -- creature id -> {guid, slot, since, exitSince, lastCombat, hudAt, moveAt, lastHit}
Z.rows = Z.rows or {} -- guid -> player row (K.newRow)
Z.control = Z.control or {} -- realm -> {faction, at, untilAt}
Z.counted = Z.counted or {} -- "killer:victim" guid pair -> time of the last counted defeat
Z.cooldown = Z.cooldown or {} -- guid -> end of the defeat cooldown
Z.scaled = Z.scaled or {} -- monster id -> slot (scaled zone monsters)
Z.pileSeq = Z.pileSeq or 0
Z.test = Z.test or {} -- staff test switches (memory only): sameIp = false lets two clients of one IP count

local function now()
	return os.time()
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos marches] " .. text)
end

-- every text of this file is English (the core's refusals and the formatted lines): Chaos.tx finds its pt-BR entry
local function msg(player, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.tx(player, text))
end

local function note(player, text)
	player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_EVENT_ADVANCE, Chaos.tx(player, text))
end

local function send(player, action, data)
	if type(data) == "table" and type(data.text) == "string" then
		data.text = Chaos.tx(player, data.text)
	end
	return Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data or {}}))
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

local function try(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

local function staff(player)
	return player:getGroup():getId() >= C().staffGroup
end

-- the config the anti-farming rules see (the staff test switch for the same-IP rule)
local function farmCfg()
	if Z.test.sameIp == false then
		local cfg = {}
		for k, v in pairs(C()) do
			cfg[k] = v
		end
		cfg.antiFarm = {}
		for k, v in pairs(C().antiFarm) do
			cfg.antiFarm[k] = v
		end
		cfg.antiFarm.sameIp = false
		cfg.antiFarm.minSecondsInside = 0
		return cfg
	end
	return C()
end

local function dayKey(t)
	return K.dayKey(t or now(), 6)
end

local function weekKey(t)
	return K.weekKey(t or now(), 6)
end

-- ======================================================================== factions (factions.lua)
local function factionCfg()
	return Chaos.factionsConfig
end

local function factionOf(key)
	local fc = factionCfg()
	for _, f in ipairs(fc and fc.factions or {}) do
		if f.key == key then
			return f
		end
	end
	return nil
end

local function rivals()
	local out = {}
	local fc = factionCfg()
	for _, f in ipairs(fc and fc.factions or {}) do
		out[f.key] = f.rival
	end
	return out
end

local function repWith(player, key)
	local F = ChaosFactions
	if not F or not F.stateOf then
		return 0
	end
	local P = try(F.stateOf, player)
	local e = P and P.st and P.st[key]
	return e and e.rep or (factionCfg() and factionCfg().rep.start or 0)
end

local function factionView(key)
	local f = key and factionOf(key)
	if not f then
		return nil
	end
	return {key = f.key, name = f.name, short = f.short, color = f.color}
end

-- ======================================================================== season realm and modes
local function realmOf(player)
	local S = ChaosSeason
	if not S or not S.current or not S.realmOf then
		return 0
	end
	local ok, realm = pcall(function()
		return S.current() and S.realmOf(player) or 0
	end)
	return ok and tonumber(realm) or 0
end

local function modesOf(player)
	local S = ChaosSeason
	if not S or not S.current or not S.modesOf then
		return {}
	end
	local ok, f = pcall(function()
		return S.current() and S.modesOf(player) or nil
	end)
	return ok and f or {}
end

-- ======================================================================== the player rows (DB)
local function T(k)
	return C().tables[k]
end

local SQL = {
	"CREATE TABLE IF NOT EXISTS `%s` (`player_id` int(11) NOT NULL, `banked` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`banked_total` int(10) unsigned NOT NULL DEFAULT 0, `kills` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`defeats` int(10) unsigned NOT NULL DEFAULT 0, `captures` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`haul` int(10) unsigned NOT NULL DEFAULT 0, `pledge` varchar(16) NOT NULL DEFAULT '', " ..
		"`pledge_at` int(10) unsigned NOT NULL DEFAULT 0, `day` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`day_rep` int(10) unsigned NOT NULL DEFAULT 0, `day_picked` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`week` int(10) unsigned NOT NULL DEFAULT 0, `week_banked` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`realm` int(11) NOT NULL, `faction` varchar(16) NOT NULL DEFAULT '', " ..
		"`at` int(10) unsigned NOT NULL DEFAULT 0, `until_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`realm`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `%s` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL, " ..
		"`offer` varchar(16) NOT NULL, `week` int(10) unsigned NOT NULL DEFAULT 0, `cost` int(10) unsigned NOT NULL, " ..
		"`at` int(10) unsigned NOT NULL, PRIMARY KEY (`id`), KEY `chaos_pvpzone_purchases_player` (`player_id`, `week`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8"
}

function Z.ensureTables()
	local names = {T("players"), T("control"), T("purchases")}
	for i, q in ipairs(SQL) do
		db.query(string.format(q, names[i]))
	end
end

local COLS = {{"banked", "n"}, {"banked_total", "n"}, {"kills", "n"}, {"defeats", "n"}, {"captures", "n"}, {"haul", "n"},
	{"pledge", "s"}, {"pledge_at", "n"}, {"day", "n"}, {"day_rep", "n"}, {"day_picked", "n"}, {"week", "n"},
	{"week_banked", "n"}}

function Z.rowOf(guid)
	local r = Z.rows[guid]
	if not r then
		r = K.newRow()
		local rows = Chaos.select(string.format("SELECT `banked`, `banked_total`, `kills`, `defeats`, `captures`, `haul`, " ..
			"`pledge`, `pledge_at`, `day`, `day_rep`, `day_picked`, `week`, `week_banked` FROM `%s` WHERE `player_id` = %d",
			T("players"), guid), COLS)
		local d = rows[1]
		if d then
			r.banked, r.total, r.kills, r.defeats, r.captures, r.haul = d.banked, d.banked_total, d.kills, d.defeats,
				d.captures, d.haul
			r.pledge, r.pledgeAt, r.day, r.dayRep, r.dayPicked = d.pledge or "", d.pledge_at, d.day, d.day_rep, d.day_picked
			r.week, r.weekBanked = d.week, d.week_banked
		end
		r.bought = {}
		local wk = weekKey()
		for _, b in ipairs(Chaos.select(string.format("SELECT `offer`, COUNT(*) AS `n` FROM `%s` WHERE `player_id` = %d " ..
				"AND `week` = %d GROUP BY `offer`", T("purchases"), guid, wk), {{"offer", "s"}, {"n", "n"}})) do
			r.bought[b.offer] = b.n
		end
		r.boughtWeek = wk
		Z.rows[guid] = r
		-- what the database gives back (rolled the same way at the next load): saveRow skips a row still equal to it
		K.roll(r, dayKey(), weekKey())
		r.savedSig = K.rowSig(r)
	end
	K.roll(r, dayKey(), weekKey())
	if r.boughtWeek ~= r.week then
		r.bought, r.boughtWeek = {}, r.week
	end
	return r
end

function Z.saveRow(guid)
	local r = Z.rows[guid]
	if not r then
		return
	end
	local sig = K.rowSig(r)
	if sig == r.savedSig then
		return -- unchanged since loaded or last written
	end
	local ok = db.query(string.format("INSERT INTO `%s` (`player_id`, `banked`, `banked_total`, `kills`, `defeats`, `captures`, `haul`, " ..
		"`pledge`, `pledge_at`, `day`, `day_rep`, `day_picked`, `week`, `week_banked`, `updated_at`) VALUES (%d, %d, %d, %d, %d, " ..
		"%d, %d, %s, %d, %d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `banked` = VALUES(`banked`), " ..
		"`banked_total` = VALUES(`banked_total`), `kills` = VALUES(`kills`), `defeats` = VALUES(`defeats`), " ..
		"`captures` = VALUES(`captures`), `haul` = VALUES(`haul`), `pledge` = VALUES(`pledge`), `pledge_at` = VALUES(`pledge_at`), " ..
		"`day` = VALUES(`day`), `day_rep` = VALUES(`day_rep`), `day_picked` = VALUES(`day_picked`), `week` = VALUES(`week`), " ..
		"`week_banked` = VALUES(`week_banked`), `updated_at` = VALUES(`updated_at`)", T("players"), guid, r.banked, r.total,
		r.kills, r.defeats, r.captures, r.haul, db.escapeString(r.pledge or ""), r.pledgeAt or 0, r.day, r.dayRep, r.dayPicked,
		r.week, r.weekBanked, now()))
	if ok ~= false then
		r.savedSig = sig
	end
end

local function getCarried(player)
	return math.max(0, player:getStorageValue(ST().carried))
end

local function setCarried(player, n)
	player:setStorageValue(ST().carried, math.max(0, math.floor(n)))
end

-- ======================================================================== the instances (the map)
local function layoutOf(slot)
	if C().mode == "map" then
		return K.mapLayout(C())
	end
	return K.layout(C(), slot)
end

-- slot of a position (or of a player's position) when that instance exists; nil outside (blessings.lua asks it)
function Z.inZone(pos)
	if type(pos) == "userdata" or (type(pos) == "table" and pos.getPosition) then
		pos = pos:getPosition()
	end
	local slot = K.slotOfPos(C(), pos)
	if slot ~= nil and Z.inst[slot] and Z.inst[slot].built then
		return slot
	end
	return nil
end

function Z.isInside(player)
	return player ~= nil and Z.state[player:getId()] ~= nil
end

Chaos.registerInstance("marches", {label = "the Scorched Marches", inside = Z.isInside, at = function(pos)
	return Z.inZone(pos) ~= nil
end})

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
end

-- one item at a tile; a failed placement never stops the build (the field plays without a decoration)
local function putItem(pos, id)
	local ok, item = pcall(Game.createItem, id, 1, pos)
	return ok and item or nil
end

local function buildTiles(slot)
	local cfg = C()
	local L = K.layout(cfg, slot)
	local foot = K.footprint(cfg, L)
	for _, t in ipairs(foot) do
		if Tile(P(t)) then
			return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
		end
	end
	local ids = cfg.ids
	local fallback = cfg.look and cfg.look.rock[1] or ids.ground
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(t.gid or fallback, 1, pos)
			end
			for _, edge in ipairs(t.edges or {}) do
				putItem(pos, edge)
			end
			if t.wall and not tile:getItemById(ids.wall) then
				Game.createItem(ids.wall, 1, pos)
			end
		end
	end
	-- decoration under the things that block, then cover, lights and landmarks
	for _, d in ipairs(L.decor or {}) do
		putItem(P(d), d.id)
	end
	for _, c in ipairs(L.cover or {}) do
		putItem(P(c), c.id)
	end
	for _, f in ipairs(L.fixtures or {}) do
		putItem(P(f), f.id)
	end
	for _, p in ipairs(L.pillars) do
		placeItem(P(p), ids.pillar)
	end
	for _, p in ipairs(L.flags) do
		placeItem(P(p), ids.exitMark)
	end
	placeItem(P(L.shrine), ids.shrine)
	return true
end

-- the instance of a slot, built when needed. realm: the realm it serves.
function Z.instance(slot, realm)
	local inst = Z.inst[slot]
	if inst and inst.built then
		return inst
	end
	if inst and inst.bad then
		return nil, inst.bad
	end
	local cfg = C()
	inst = {slot = slot, realm = realm or 0, points = {}, piles = {}, contest = K.newContest(cfg, now())}
	if cfg.mode == "map" then
		inst.L = K.mapLayout(cfg)
		if not inst.L then
			return nil, "pvpzone_config.lua area is not set"
		end
		inst.realm = cfg.area.realm or 0
	else
		local ok, err = buildTiles(slot)
		if not ok then
			inst.bad = err
			Z.inst[slot] = inst
			log(string.format("slot %d not usable: %s", slot, tostring(err)))
			return nil, err
		end
		inst.L = K.layout(cfg, slot)
	end
	local list = cfg.monsters.list
	for i, p in ipairs(inst.L.spawns or {}) do
		inst.points[i] = {pos = p, name = list[(i - 1) % #list + 1], cid = nil, deadAt = 0}
	end
	inst.built = true
	Z.inst[slot] = inst
	log(string.format("%s instance %d ready (realm %d, %d spawn points)", cfg.name, slot, inst.realm, #inst.points))
	return inst
end

-- ======================================================================== zone monsters
local function scaleMonster(m, slot, hpMult)
	local max = m:getMaxHealth()
	local want = math.floor(max * (hpMult or C().monsters.hpMult))
	if want > max then
		m:setMaxHealth(want)
		Chaos.heal(m, want)
	end
	m:registerEvent("ChaosMarchesMonsterDeath")
	m:registerEvent("ChaosMarchesMonsterHealth")
	Z.scaled[m:getId()] = slot
end

local function tileFree(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:getTopCreature() then
		return false
	end
	return true
end

local function spawnPoint(inst, i)
	local pt = inst.points[i]
	local pos = P(pt.pos)
	if not tileFree(pos) then
		return
	end
	local m = Game.createMonster(pt.name, pos, false, true)
	if m then
		scaleMonster(m, inst.slot)
		pt.cid = m:getId()
	end
end

local function refill(inst, t)
	if C().mode == "map" then
		return -- the map's own spawns
	end
	for i, pt in ipairs(inst.points) do
		if pt.cid and not Creature(pt.cid) then
			pt.cid, pt.deadAt = nil, t
		end
		if not pt.cid and t - (pt.deadAt or 0) >= C().monsters.respawnSeconds then
			spawnPoint(inst, i)
		end
	end
end

-- ======================================================================== messages to everyone of an instance / realm
local function eachInside(slot, fn)
	for cid, st in pairs(Z.state) do
		if st.slot == slot then
			local p = Player(cid)
			if p then
				fn(p, st)
			end
		end
	end
end

local function announceRealm(realm, slot, text)
	for _, p in ipairs(Game.getPlayers()) do
		local st = Z.state[p:getId()]
		if (st and st.slot == slot) or (realmOf(p) == realm and (Z.rows[p:getGuid()] and Z.rows[p:getGuid()].pledge or "") ~= "") then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.tx(p, text))
		end
	end
end

-- ======================================================================== the shrine control and the buff
function Z.holderOf(realm)
	return K.holder(Z.control[tonumber(realm) or 0], now())
end

local function saveControl(realm)
	local c = Z.control[realm]
	db.query(string.format("REPLACE INTO `%s` (`realm`, `faction`, `at`, `until_at`) VALUES (%d, %s, %d, %d)", T("control"),
		realm, db.escapeString(c and c.faction or ""), c and c.at or 0, c and c.untilAt or 0))
end

local function loadControl()
	for _, r in ipairs(Chaos.select(string.format("SELECT `realm`, `faction`, `at`, `until_at` FROM `%s`", T("control")),
			{{"realm", "n"}, {"faction", "s"}, {"at", "n"}, {"until_at", "n"}})) do
		Z.control[r.realm] = {faction = r.faction, at = r.at, untilAt = r.until_at}
	end
end

local function pledgeOf(player)
	local r = Z.rows[player:getGuid()]
	return r and r.pledge ~= "" and r.pledge or nil
end

local function buffMult(player, kind)
	if not player then
		return 1
	end
	local pledge = pledgeOf(player)
	if not pledge then
		return 1
	end
	return K.buffMult(C(), Z.control[realmOf(player)], pledge, now(), kind)
end

local function zoneMonster(creature)
	if not creature or not creature:isMonster() or creature:getMaster() then
		return false
	end
	if Z.scaled[creature:getId()] then
		return true
	end
	return Z.inZone(creature:getPosition()) ~= nil
end

-- loot_config.lua rateMult: zone monsters drop more; the shrine holder's faction-wide loot buff
function Z.lootMult(ctx)
	local m = 1
	if ctx and ctx.monster and try(zoneMonster, ctx.monster) then
		m = m * C().monsters.lootMult
	end
	if ctx and ctx.player then
		m = m * (try(buffMult, ctx.player, "loot") or 1)
	end
	return m
end

-- ======================================================================== protection, release, entering
local function protectedUntil(player)
	return player:getStorageValue(ST().protect)
end

local function isProtected(player, st)
	return (st and st.moveAt ~= nil) or K.protected(protectedUntil(player), now())
end

local HARMFUL = {"CONDITION_POISON", "CONDITION_FIRE", "CONDITION_ENERGY", "CONDITION_BLEEDING", "CONDITION_CURSED",
	"CONDITION_DROWN", "CONDITION_FREEZING", "CONDITION_DAZZLED", "CONDITION_PARALYZE"}

local function cleanse(player)
	for _, name in ipairs(HARMFUL) do
		local t = _G[name]
		if t then
			player:removeCondition(t)
		end
	end
end

local function heal(player)
	Chaos.heal(player, player:getMaxHealth() - player:getHealth())
	player:addMana(player:getMaxMana() - player:getMana())
end

local function clearSkull(player)
	local s = player:getSkull()
	if s == SKULL_WHITE or s == SKULL_YELLOW then
		player:setSkull(SKULL_NONE)
	end
end

-- where the player goes out: where he entered (or the temple when that place is gone); a defeat follows
-- death.respawn (K.defeatDestination: the temple by default)
local function returnPos(player, why)
	local st = ST()
	local x, y, z = player:getStorageValue(st.retX), player:getStorageValue(st.retY), player:getStorageValue(st.retZ)
	local entryOk = x > 0 and y > 0 and z >= 0 and Tile(Position(x, y, z)) ~= nil and not Z.inZone({x = x, y = y, z = z})
	if why == "defeat" and K.defeatDestination(C(), entryOk) == "temple" then
		return player:getTown():getTemplePosition()
	end
	if entryOk then
		return Position(x, y, z)
	end
	return player:getTown():getTemplePosition()
end

-- the battle lock and its white skull off, now and again a moment later (combatLock.clearAfterMs): the engine still
-- runs its attack bookkeeping after a cancelled lethal hit (onPrepareDeath) and would put the lock back for the
-- server's whole pzLocked time. Only once the player is outside the zone.
local function dropLock(player)
	clearSkull(player)
	player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
end

local function dropLockLater(player)
	local cid = player:getId()
	for _, ms in ipairs((C().combatLock or {}).clearAfterMs or {}) do
		addEvent(function()
			local p = Player(cid)
			if p and not Z.state[cid] and Z.inZone(p:getPosition()) == nil then
				dropLock(p)
				cleanse(p)
			end
		end, ms)
	end
end

local function clearMarkers(player)
	local st = ST()
	player:setStorageValue(st.inside, 0)
	player:setStorageValue(st.protect, 0)
end

-- out of the zone to where the player entered (or the temple): healed, no fight lock, no white skull
local function release(player, why)
	local cid = player:getId()
	Z.state[cid] = nil
	player:setTarget(nil)
	cleanse(player)
	clearSkull(player)
	player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
	heal(player)
	local dest = returnPos(player, why)
	clearMarkers(player)
	player:teleportTo(dest)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	dropLock(player)
	dropLockLater(player)
	send(player, "hide", {why = why})
end

-- ChaosHideout.isInside takes a position, not a player (given the player it never matched)
local function inHideout(player)
	return ChaosHideout ~= nil and ChaosHideout.isInside ~= nil and ChaosHideout.isInside(player:getPosition())
end

local function insideOther(player)
	local checks = {
		{ChaosDungeonIsInside, "a dungeon", true},
		{ChaosTowerRun, "the Infinity Tower"}, {ChaosRift, "a rift"}, {ChaosSiege, "a siege"},
		{ChaosDescent, "the Ember Descent"}, {ChaosRaid, "a raid"}, {ChaosAscended, "an Ascended Omen"},
		{ChaosBattleground, "the battleground"}, {inHideout, "a hideout", true}
	}
	for _, c in ipairs(checks) do
		local mod, what, plain = c[1], c[2], c[3]
		if plain and mod and try(mod, player) then
			return what
		elseif not plain and mod and mod.isInside and try(mod.isInside, player) then
			return what
		end
	end
	local A = ChaosArena
	if A and ((A.isInside and try(A.isInside, player)) or (A.isQueued and try(A.isQueued, player))) then
		return "the arena (queue or match)"
	end
	return nil
end

local function cooldownLeft(guid)
	return math.max(0, (Z.cooldown[guid] or 0) - now())
end

local function entryFacts(player, data)
	local cfg = C()
	local tile = Tile(player:getPosition())
	local modes = modesOf(player)
	local realm = realmOf(player)
	local facts = {
		level = player:getLevel(), inside = Z.isInside(player) or Z.inZone(player:getPosition()) ~= nil,
		hc = modes.hc == true, staff = staff(player), hcAccept = data and data.hcAccept == true,
		accept = data and data.accept == true,
		inPz = tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE),
		inCombat = player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT),
		elsewhere = insideOther(player), multiClient = Chaos.isMultiClient and Chaos.isMultiClient(player) or false,
		cooldown = cooldownLeft(player:getGuid())
	}
	if cfg.mode == "map" then
		facts.realmOk = realm == ((cfg.area and cfg.area.realm) or 0)
	end
	if Z.testNoPz then
		facts.inPz = true -- TEST ONLY (/marches nopz): test maps without a protection zone
	end
	return facts
end

local function arrivalSpot(L, exitIndex)
	local spots = L.entrySpots[exitIndex] or {}
	local start = math.random(math.max(1, #spots))
	for k = 0, #spots - 1 do
		local p = spots[(start - 1 + k) % #spots + 1]
		if tileFree(P(p)) then
			return P(p)
		end
	end
	return P(L.exits[exitIndex])
end

-- the places a player is sent to, for the client's minimap flags: every safe exit and the Cinder Shrine, named in the
-- player's language (the client draws them on the map while the player is inside)
local function marksOf(player, inst)
	local out = {}
	for _, e in ipairs(inst.L.exits) do
		out[#out + 1] = {kind = "exit", x = e.x, y = e.y, z = e.z, name = Chaos.t(player, "Safe exit: bank your embers")}
	end
	local s = inst.L.shrine
	if s then
		out[#out + 1] = {kind = "shrine", x = s.x, y = s.y, z = s.z,
			name = Chaos.t(player, "Cinder Shrine: slay the Warden, hold the circle")}
	end
	return out
end

-- the goal, in two plain messages: what the player is here to do, and what he carries now
local function goalMessages(player)
	msg(player, Chaos.t(player, "Goal: earn embers from monsters and rival players, then bank them at a safe exit before you are defeated."))
	msg(player, Chaos.t(player, "Embers carried: %d. Bank them at a safe exit (the white circles by the banners, marked on your map) before you die.",
		getCarried(player)))
end

local function newState(player, slot)
	local st = {guid = player:getGuid(), slot = slot, since = now(), lastCombat = 0, hudAt = 0}
	Z.state[player:getId()] = st
	return st
end

function Z.enter(player, data)
	local cfg = C()
	local why = K.entryRefusal(cfg, entryFacts(player, data))
	if why then
		send(player, "msg", {text = why})
		msg(player, why)
		return false, why
	end
	local realm = realmOf(player)
	local slot = K.slotForRealm(cfg, realm)
	local inst, err = Z.instance(slot, realm)
	if not inst then
		local text = "The Marches cannot be reached right now."
		log("enter refused: " .. tostring(err))
		send(player, "msg", {text = text})
		return false, text
	end
	local st = ST()
	local here = player:getPosition()
	player:setStorageValue(st.retX, here.x)
	player:setStorageValue(st.retY, here.y)
	player:setStorageValue(st.retZ, here.z)
	player:setStorageValue(st.inside, 1)
	player:setStorageValue(st.enteredAt, now())
	player:setStorageValue(st.protect, now() + cfg.entry.protectSeconds)
	Z.rowOf(player:getGuid())
	local s = newState(player, slot)
	s.enteredAt = now()
	here:sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(arrivalSpot(inst.L, math.random(math.max(1, #inst.L.exits))))
	player:getPosition():sendMagicEffect(CONST_ME_FIREAREA)
	msg(player, Chaos.t(player, "You enter %s. Protected for %d seconds.", cfg.name, cfg.entry.protectSeconds))
	goalMessages(player)
	send(player, "enter", {marks = marksOf(player, inst)})
	Z.sendHud(player, s)
	return true
end

-- logged in (or found) inside: hold, then the nearest safe exit
function Z.adopt(player, slot)
	local inst = Z.inst[slot]
	local s = newState(player, slot)
	local moveAt, protectUntil = K.loginTimes(C(), now())
	s.moveAt = moveAt
	s.enteredAt = player:getStorageValue(ST().enteredAt)
	player:setStorageValue(ST().inside, 1)
	player:setStorageValue(ST().protect, protectUntil)
	msg(player, string.format("You wake in %s. You are protected while you are brought to a safe exit.", C().name))
	goalMessages(player)
	send(player, "enter", {marks = inst and marksOf(player, inst) or {}})
	return s, inst
end

-- inside without having entered (a walk-in in map mode, a teleport): out again, and the confirmation
local function reject(player)
	local cfg = C()
	local dest = (cfg.mode == "map" and cfg.area and cfg.area.outside) and P(cfg.area.outside)
		or player:getTown():getTemplePosition()
	player:teleportTo(dest)
	dest:sendMagicEffect(CONST_ME_TELEPORT)
	msg(player, string.format("%s are a PvP zone: enter through Adventure > Scorched Marches and accept the rules first.",
		cfg.name))
	Z.sendState(player, true, true)
end

-- left without a safe exit (a teleport, a staff move): the carried embers burn. Moved out while still held after a
-- login (another login script placed the character elsewhere): nothing burns, the embers stay carried.
local function lost(player, st)
	Z.state[player:getId()] = nil
	clearMarkers(player)
	if st and st.moveAt then
		send(player, "hide", {why = "moved"})
		return
	end
	local carried = getCarried(player)
	setCarried(player, 0)
	dropLock(player)
	dropLockLater(player)
	send(player, "hide", {why = "lost"})
	if carried > 0 then
		msg(player, string.format("You left the Marches without a safe exit: your %d carried embers burned.", carried))
	end
end

-- ======================================================================== banking at a safe exit
local function achievement(player, stat, n, set)
	local A = ChaosAchievements
	if not A then
		return
	end
	if set and A.set then
		try(A.set, player, stat, n)
	elseif A.progress then
		try(A.progress, player, stat, n)
	end
end

local function leaveSafe(player, st)
	local cfg = C()
	local guid = player:getGuid()
	local r = Z.rowOf(guid)
	local carried = getCarried(player)
	local banked, moved, lostN = K.bank(cfg, r.banked, carried)
	r.banked = banked
	r.total = r.total + moved
	r.weekBanked = r.weekBanked + moved
	r.haul = math.max(r.haul, moved)
	setCarried(player, 0)
	Z.saveRow(guid)
	if moved > 0 then
		achievement(player, "pvpzone_banked", moved)
		achievement(player, "pvpzone_haul", moved, true)
		if ChaosLeaderboard and ChaosLeaderboard.record then
			try(ChaosLeaderboard.record, cfg.leaderboard, player, moved, "add")
		end
	end
	release(player, "exit")
	if moved > 0 or lostN > 0 then
		msg(player, Chaos.t(player, "You leave %s. %d embers banked (%d in total)%s. Spend them at the vendor: Adventure > Scorched Marches.",
			cfg.name, moved, r.banked, lostN > 0 and Chaos.t(player, ", %d lost over the bank limit", lostN) or ""))
	else
		msg(player, string.format("You leave %s.", cfg.name))
	end
	Z.sendState(player, false)
end

-- ======================================================================== ember piles
local function pileMarker(pos, on)
	local id = C().ids.pile
	local tile = Tile(pos)
	if on then
		placeItem(pos, id)
	elseif tile then
		local item = tile:getItemById(id)
		if item then
			item:remove()
		end
	end
end

local function dropPile(slot, pos, pile)
	local inst = Z.inst[slot]
	if not inst or pile.amount <= 0 then
		return
	end
	Z.pileSeq = Z.pileSeq + 1
	pile.id = Z.pileSeq
	pile.pos = {x = pos.x, y = pos.y, z = pos.z}
	inst.piles[pile.id] = pile
	pileMarker(pos, true)
	pos:sendMagicEffect(CONST_ME_FIREAREA)
end

local function pilesTick(inst, t)
	local cfg = C()
	local range = cfg.death.pickupRange
	for id, pile in pairs(inst.piles) do
		local pos = P(pile.pos)
		if pile.amount <= 0 or t >= pile.expiresAt then
			inst.piles[id] = nil
			pileMarker(pos, false)
			if pile.amount > 0 then
				pos:sendMagicEffect(CONST_ME_POFF)
			end
		else
			if t % 2 == 0 then
				pos:sendMagicEffect(CONST_ME_HITBYFIRE)
			end
			for cid, st in pairs(Z.state) do
				if st.slot == inst.slot and pile.amount > 0 then
					local p = Player(cid)
					local pp = p and p:getPosition()
					if pp and pp.z == pos.z and math.max(math.abs(pp.x - pos.x), math.abs(pp.y - pos.y)) <= range
							and not st.moveAt then
						local r = Z.rowOf(st.guid)
						local carried = getCarried(p)
						local take, why, counts = K.pickup(cfg, pile, {guid = st.guid, carried = carried,
							dayPicked = r.dayPicked, ssf = modesOf(p).ssf == true}, t)
						if take > 0 then
							K.takeFrom(pile, st.guid, take)
							setCarried(p, carried + take)
							if counts then
								r.dayPicked = r.dayPicked + take
							end
							pp:sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_FIREAREA)
							note(p, string.format("You take %d embers (carrying %d).", take, carried + take))
							Z.sendHud(p, st, true)
						elseif why and why ~= "gone" and (st.pileNote or 0) + 10 <= t then
							st.pileNote = t
							local texts = {owner = "These embers belong to the victor for a few more seconds.",
								ssf = "Self-Found characters do not take the embers of others.",
								["kill cap"] = "You took all you may from this pile.",
								["daily cap"] = "You took all the embers you may from other players today.",
								full = "You cannot carry more embers. Bank them at a safe exit."}
							note(p, texts[why] or why)
						end
					end
				end
			end
		end
	end
end

-- ======================================================================== a defeat (the lethal hit is cancelled)
local function defeat(player, st, killer)
	local cfg = C()
	local t = now()
	local victimGuid = player:getGuid()
	local pos = player:getPosition()
	local kp = playerOf(killer)
	if kp and kp:getId() == player:getId() then
		kp = nil
	end
	if not kp and st.lastHit and t - st.lastHit.at <= cfg.assistSeconds then
		local p = Player(st.lastHit.cid)
		if p and Z.state[p:getId()] and Z.state[p:getId()].slot == st.slot then
			kp = p -- a monster landed the last blow on a player's prey
		end
	end
	local carried = getCarried(player)
	local amount, burned = K.deathPile(cfg, carried)
	setCarried(player, 0)
	local vr = Z.rowOf(victimGuid)
	vr.defeats = vr.defeats + 1
	local counted, reason
	local killerGuid = kp and kp:getGuid() or nil
	if kp then
		local pairKey = killerGuid .. ":" .. victimGuid
		counted, reason = K.killVerdict(farmCfg(), {killerAccount = kp:getAccountId(), victimAccount = player:getAccountId(),
			killerIp = kp:getIp(), victimIp = player:getIp(), killerLevel = kp:getLevel(), victimLevel = player:getLevel(),
			enteredAt = st.enteredAt, at = t, lastCounted = Z.counted[pairKey]})
		if counted then
			Z.counted[pairKey] = t
		end
	end
	local verdictArg = nil -- nil: a monster's victim; false: the defeat does not count (the pile burns)
	if kp then
		verdictArg = counted and true or false
	end
	local pile = K.newPile(cfg, amount, victimGuid, killerGuid, verdictArg, t)
	dropPile(st.slot, pos, pile)
	-- the killer: stats, reputation
	if kp then
		local kr = Z.rowOf(killerGuid)
		if counted then
			kr.kills = kr.kills + 1
			achievement(kp, "pvpzone_kills", 1)
			local rep, why = K.repFor(cfg, kr.pledge, vr.pledge, rivals(), kr.dayRep)
			if rep > 0 and ChaosFactions and ChaosFactions.gain then
				kr.dayRep = kr.dayRep + rep
				try(ChaosFactions.gain, kp, kr.pledge, rep, "pvpzone")
			elseif why == "daily cap" then
				note(kp, "You have earned all the reputation the Marches give today.")
			end
			msg(kp, Chaos.t(kp, "You defeated %s.%s", player:getName(), pile.amount > 0 and Chaos.t(kp,
				" %d embers fell: yours alone for %d seconds.", pile.amount, cfg.death.ownerSeconds) or ""))
		else
			msg(kp, Chaos.t(kp, "You defeated %s, but it does not count (%s): the embers burn.", player:getName(), Chaos.tx(kp, reason)))
		end
		Z.saveRow(killerGuid)
	end
	Z.saveRow(victimGuid)
	Z.cooldown[victimGuid] = t + cfg.entry.cooldownSeconds
	release(player, "defeat")
	local by = kp and kp:getName() or (killer and killer:getName()) or "the Marches"
	local fell = ""
	if carried > 0 then
		fell = pile.amount > 0 and Chaos.t(player, " Your %d carried embers fell where you stood: your killer may take them, the rest burns out in %d seconds.",
			carried, cfg.death.pileSeconds) or Chaos.t(player, " Your %d carried embers burned.", carried)
	end
	msg(player, Chaos.t(player, "You were defeated by %s in %s.%s You can enter again in %d seconds.", by, cfg.name, fell,
		cfg.entry.cooldownSeconds))
	if burned > 0 then
		log(string.format("%d embers of %s burned", burned, player:getName()))
	end
	Z.sendState(player, false)
end

-- ======================================================================== the Cinder Shrine contest
local function spawnWarden(inst)
	local cfg = C()
	local w = cfg.contest.warden
	local s = inst.L.shrine
	for _, d in ipairs({{0, 1}, {1, 0}, {0, -1}, {-1, 0}, {1, 1}, {-1, -1}}) do
		local pos = Position(s.x + d[1], s.y + d[2], s.z)
		if tileFree(pos) then
			local m = Game.createMonster(w.name, pos, false, true)
			if m then
				try(function() m:rename(w.title, "the " .. w.title:lower()) end)
				scaleMonster(m, inst.slot, w.hpMult * cfg.monsters.hpMult)
				inst.wardenCid = m:getId()
				pos:sendMagicEffect(CONST_ME_MORTAREA)
				return m
			end
		end
	end
	return nil
end

local function contestCounts(inst)
	local counts = {}
	eachInside(inst.slot, function(p, st)
		local pledge = pledgeOf(p)
		if pledge and not st.moveAt and K.inShrine(C(), inst.L, p:getPosition()) then
			counts[pledge] = (counts[pledge] or 0) + 1
		end
	end)
	return counts
end

local function contestTick(inst, t)
	local cfg = C()
	local c = inst.contest
	local ev = K.contestTick(cfg, c, t, {counts = contestCounts(inst), dt = 1,
		wardenAlive = inst.wardenCid ~= nil and Creature(inst.wardenCid) ~= nil})
	for _, e in ipairs(ev) do
		if e.kind == "start" then
			spawnWarden(inst)
			announceRealm(inst.realm, inst.slot, string.format("The Cinder Shrine stirs in %s: its Warden has risen. Slay it and hold the circle for your faction.",
				cfg.name))
		elseif e.kind == "warden" then
			inst.wardenCid = nil
			eachInside(inst.slot, function(p)
				msg(p, "The Shrine Warden has fallen: the Cinder Shrine can be taken. Stand in its circle with your faction.")
			end)
		elseif e.kind == "captured" then
			Z.control[inst.realm] = K.newControl(cfg, e.faction, t)
			saveControl(inst.realm)
			local f = factionOf(e.faction)
			local name = f and f.name or e.faction
			eachInside(inst.slot, function(p, st)
				if pledgeOf(p) == e.faction and K.inShrine(cfg, inst.L, p:getPosition()) then
					local carried = getCarried(p)
					local nc = K.addCarried(cfg, carried, cfg.contest.embers.capture)
					setCarried(p, nc)
					local r = Z.rowOf(st.guid)
					r.captures = r.captures + 1
					Z.saveRow(st.guid)
					achievement(p, "pvpzone_captures", 1)
				end
			end)
			announceRealm(inst.realm, inst.slot, string.format("%s took the Cinder Shrine in %s: everyone sworn to it gains +%d%% experience and +%d%% loot for %d minutes.",
				name, cfg.name, cfg.contest.buff.exp, cfg.contest.buff.loot, cfg.contest.holdMinutes))
		elseif e.kind == "expired" then
			if inst.wardenCid then
				local m = Creature(inst.wardenCid)
				if m then
					m:remove()
				end
				inst.wardenCid = nil
			end
			eachInside(inst.slot, function(p)
				msg(p, "The Cinder Shrine falls silent: nobody took it in time.")
			end)
		end
	end
end

-- ======================================================================== the HUD and the window
local function contestView(inst, t, realm)
	local cfg = C()
	local c = inst and inst.contest
	local out = {}
	if c then
		out.phase = c.phase
		if c.phase == "idle" then
			out.left = math.max(0, c.nextAt - t)
		else
			out.left = math.max(0, (c.endsAt or t) - t)
		end
		out.contested = c.contested or nil
		if c.phase == "warden" and inst.wardenCid then
			local m = Creature(inst.wardenCid)
			if m then
				out.warden = math.floor(m:getHealth() * 100 / math.max(1, m:getMaxHealth()) + 0.5)
			end
		end
		if c.phase == "capture" then
			out.progress = {}
			for key, v in pairs(c.progress) do
				local f = factionView(key)
				if f and v > 0 then
					f.pct = math.floor(v + 0.5)
					out.progress[#out.progress + 1] = f
				end
			end
			table.sort(out.progress, function(a, b)
				return a.pct > b.pct
			end)
		end
	end
	local h = K.holder(Z.control[realm], t)
	if h then
		out.holder = factionView(h)
		out.holder.left = math.max(0, Z.control[realm].untilAt - t)
	end
	return out
end

function Z.sendHud(player, st, force)
	local cfg = C()
	local t = now()
	if not force and t - (st.hudAt or 0) < cfg.hudSeconds then
		return
	end
	st.hudAt = t
	local inst = Z.inst[st.slot]
	local r = Z.rowOf(st.guid)
	local d = {name = cfg.name, embers = getCarried(player), cap = cfg.carry.max, banked = r.banked,
		pledge = factionView(r.pledge ~= "" and r.pledge or nil), contest = contestView(inst, t, inst and inst.realm or 0)}
	if st.moveAt then
		d.protect = math.max(0, st.moveAt - t) + cfg.login.protectSeconds
	elseif K.protected(protectedUntil(player), t) then
		d.protect = protectedUntil(player) - t
	end
	if st.exitSince then
		local share = K.exitProgress(cfg, st.exitSince, st.lastCombat, t)
		d.exit = math.floor((share or 0) * 100 + 0.5)
	end
	local near = 0
	if inst then
		for _, pile in pairs(inst.piles) do
			near = near + pile.amount
		end
	end
	d.piles = near
	send(player, "hud", d)
end

local function vendorView(player, r)
	local cfg = C()
	local out = {}
	local owns = function(key)
		local CM = ChaosCosmetics
		return CM and CM.owns and CM.owns(player:getAccountId(), key) or false
	end
	for _, o in ipairs(cfg.vendor) do
		local ok, why = K.vendorCheck(cfg, o.key, r.banked, r.bought[o.key], owns)
		out[#out + 1] = {key = o.key, name = o.name, cost = o.cost, kind = o.kind, id = o.id, count = o.count,
			weekly = o.weekly, bought = r.bought[o.key] or 0, owned = o.kind == "cosmetic" and owns(o.cosmetic) or nil,
			can = ok, why = Chaos.tx(player, why)}
	end
	return out
end

function Z.stateOf(player, confirm)
	local cfg = C()
	local t = now()
	local guid = player:getGuid()
	local r = Z.rowOf(guid)
	local realm = realmOf(player)
	local slot = K.slotForRealm(cfg, realm)
	local fc = factionCfg()
	local factions = {}
	for _, f in ipairs(fc and fc.factions or {}) do
		local why = K.pledgeRefusal(cfg, fc.factions, fc.ranks, f.key, repWith(player, f.key), r.pledge, r.pledgeAt, t)
		local rf = factionOf(f.rival)
		factions[#factions + 1] = {key = f.key, name = f.name, short = f.short, color = f.color, rival = f.rival,
			rivalName = rf and rf.name or nil,
			pledged = r.pledge == f.key or nil, can = why == nil, why = Chaos.tx(player, why)}
	end
	local facts = entryFacts(player, {accept = true, hcAccept = true})
	local why = K.entryRefusal(cfg, facts)
	local modes = modesOf(player)
	return {
		open = nil, confirm = confirm or nil, name = cfg.name, minLevel = cfg.minLevel, level = player:getLevel(),
		inside = Z.isInside(player), carried = getCarried(player), carryMax = cfg.carry.max, banked = r.banked,
		bankMax = cfg.bankMax, weekBanked = r.weekBanked, total = r.total, kills = r.kills, defeats = r.defeats,
		captures = r.captures, cooldown = cooldownLeft(guid), pledge = r.pledge ~= "" and r.pledge or nil,
		pledgeChangeIn = r.pledge ~= "" and math.max(0, r.pledgeAt + cfg.reputation.changeHours * 3600 - t) or 0,
		factions = factions, contest = contestView(Z.inst[slot], t, realm), rules = cfg.entry.rules,
		hc = {isHc = modes.hc == true, allow = cfg.hardcore.allow == true}, ssf = modes.ssf == true,
		canEnter = why == nil, why = Chaos.tx(player, why), vendor = vendorView(player, r),
		monsters = {hp = cfg.monsters.hpMult, damage = cfg.monsters.damageMult, exp = cfg.monsters.expMult,
			loot = cfg.monsters.lootMult},
		pickup = {perKill = cfg.pickup.perKillMax, perDay = cfg.pickup.perDayMax, ownerSeconds = cfg.death.ownerSeconds},
		buff = cfg.contest.buff, holdMinutes = cfg.contest.holdMinutes, everyMinutes = cfg.contest.everyMinutes,
		repPerKill = cfg.reputation.perKill, repDailyCap = cfg.reputation.dailyCap, repToday = r.dayRep,
		exitSeconds = cfg.exit.channelSeconds
	}
end

function Z.sendState(player, open, confirm)
	local s = Z.stateOf(player, confirm)
	s.open = open or nil
	send(player, "state", s)
end

-- ======================================================================== pledge and vendor
function Z.pledge(player, key)
	local cfg = C()
	local fc = factionCfg()
	if not fc then
		send(player, "msg", {text = "The factions are not available."})
		return false
	end
	local r = Z.rowOf(player:getGuid())
	if Z.isInside(player) then
		send(player, "msg", {text = "Pledge before you enter the Marches."})
		return false
	end
	local why = K.pledgeRefusal(cfg, fc.factions, fc.ranks, key, repWith(player, key), r.pledge, r.pledgeAt, now())
	if why then
		send(player, "msg", {text = why})
		return false
	end
	r.pledge, r.pledgeAt = key, now()
	Z.saveRow(player:getGuid())
	local f = factionOf(key)
	send(player, "msg", {text = string.format("You fight for %s in the Marches.", f.name), ok = true})
	return true
end

local function giveStack(player, id, count)
	local added = Chaos.giveItem(player, id, count)
	local rest = count - added
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return added < count
end

function Z.buy(player, key)
	local cfg = C()
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "marches.buy", 500) then
		return false
	end
	if Z.isInside(player) or Z.inZone(player:getPosition()) ~= nil then
		-- 50 ultimate health potions in the middle of a fight would make a defeat a choice: the vendor is outside only
		send(player, "msg", {text = "Leave the Marches to use the vendor."})
		return false
	end
	local guid = player:getGuid()
	local r = Z.rowOf(guid)
	local owns = function(k)
		local CM = ChaosCosmetics
		return CM and CM.owns and CM.owns(player:getAccountId(), k) or false
	end
	local ok, why, o = K.vendorCheck(cfg, key, r.banked, r.bought[key], owns)
	if not ok then
		send(player, "msg", {text = why})
		return false
	end
	if o.kind == "cosmetic" then
		local CM = ChaosCosmetics
		if not (CM and CM.grant) then
			send(player, "msg", {text = "Cosmetics are not available."})
			return false
		end
		local done = CM.grant(player:getAccountId(), o.cosmetic, "pvp")
		if not done then
			send(player, "msg", {text = "That cosmetic could not be granted."})
			return false
		end
	end
	r.banked = r.banked - o.cost
	r.bought[key] = (r.bought[key] or 0) + 1
	local inbox = false
	if o.kind == "item" then
		inbox = giveStack(player, o.id, o.count)
	end
	Z.saveRow(guid)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `offer`, `week`, `cost`, `at`) VALUES (%d, %s, %d, %d, %d)",
		T("purchases"), guid, db.escapeString(o.key), r.week, o.cost, now()))
	send(player, "msg", {text = Chaos.t(player, "Bought %s for %d embers.%s", o.name, o.cost,
		inbox and Chaos.t(player, " Part of it went to your inbox.") or ""), ok = true})
	return true
end

-- ======================================================================== the tick
local tickAt = 0

-- floating text over the objectives, for everyone who sees them: the shrine says what to do with it now, the safe exits
-- say what they are for. Every few seconds, and only while somebody is inside.
local function beacons(inst)
	local Fx = ChaosCombatFx
	if not (Fx and Fx.label) then
		return
	end
	local anyone = false
	eachInside(inst.slot, function()
		anyone = true
	end)
	if not anyone then
		return
	end
	local phase = inst.contest and inst.contest.phase
	local shrineText = phase == "warden" and "Slay the Warden!" or (phase == "capture" and "Take the Shrine!" or "Cinder Shrine")
	local sp = P(inst.L.shrine)
	Fx.label(sp, function(pl)
		return Chaos.tx(pl, shrineText)
	end, "#ff7a2a")
	sp:sendMagicEffect(CONST_ME_FIREAREA)
	for _, e in ipairs(inst.L.exits) do
		Fx.label(P(e), function(pl)
			return Chaos.tx(pl, "Safe exit: bank your embers")
		end, "#9fd89f")
	end
end
Z.beacons = beacons

function Z.tick()
	local cfg = C()
	if not cfg.enabled then
		return
	end
	local t = now()
	local slow = t - tickAt >= 5
	if slow then
		tickAt = t
	end
	for _, player in ipairs(Game.getPlayers()) do
		local cid = player:getId()
		local pos = player:getPosition()
		local slot = Z.inZone(pos)
		local st = Z.state[cid]
		if slot ~= nil and not st then
			if player:getStorageValue(ST().inside) == 1 then
				st = Z.adopt(player, slot)
			elseif not staff(player) then
				reject(player)
			end
		elseif slot == nil and st then
			lost(player, st)
			st = nil
		end
		if st and slot ~= nil then
			st.slot = slot
			if st.moveAt and t >= st.moveAt then
				st.moveAt = nil
				local inst = Z.inst[slot]
				player:teleportTo(arrivalSpot(inst.L, K.nearestExit(inst.L, pos)))
				player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
				player:setStorageValue(ST().protect, t + cfg.login.protectSeconds)
				msg(player, string.format("You are at a safe exit, protected for %d seconds. Stand in the circle to leave and bank your embers.",
					cfg.login.protectSeconds))
			end
			clearSkull(player)
			-- the battle lock never runs longer than combatLock.maxSeconds in here (each player hit renews it with the
			-- server's whole pzLocked time)
			local cond = player:getCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
			local cut = cond and K.lockTicks(cfg, cond:getTicks())
			if cut then
				cond:setTicks(cut)
			end
			local inst = Z.inst[slot]
			if not st.moveAt and K.exitAt(cfg, inst.L, player:getPosition()) then
				-- burning, poison and the like would keep resetting the channel (beta report 2026-10-20: a 3 minute debuff
				-- held a player in the circle)
				if ChaosTempleCleanse and not player:isPzLocked() then
					ChaosTempleCleanse.clear(player)
				end
				st.exitSince = st.exitSince or t
				local _, done = K.exitProgress(cfg, st.exitSince, st.lastCombat, t)
				if done then
					leaveSafe(player, st)
					st = nil
				elseif not st.exitNoted then
					st.exitNoted = true
					note(player, string.format("Leaving in %d seconds: do not fight.", cfg.exit.channelSeconds))
				end
			else
				st.exitSince, st.exitNoted = nil, nil
			end
			if st then
				Z.sendHud(player, st, st.exitSince ~= nil)
			end
		end
	end
	for _, inst in pairs(Z.inst) do
		if inst.built then
			pilesTick(inst, t)
			contestTick(inst, t)
			if slow then
				refill(inst, t)
				pcall(beacons, inst)
			end
		end
	end
end

local tick = GlobalEvent("ChaosMarchesTick")
function tick.onThink(interval)
	local ok, err = pcall(Z.tick)
	if not ok then
		log("tick: " .. tostring(err))
	end
	return true
end
tick:interval(C().tickMs)
tick:register()

-- ======================================================================== combat hooks
local function damageScale(a, target)
	if not C().pvpScale then
		return 1
	end
	return K.pvpFactor(Chaos.battlegroundConfig, a:getLevel(), target:getLevel())
end

-- the attack rules inside (nil = not the zone's business)
function Z.targetCombat(creature, target)
	if not creature or not target or not target:isPlayer() then
		return nil
	end
	local tst = Z.state[target:getId()]
	local a = playerOf(creature)
	if not a then
		if tst and isProtected(target, tst) then
			return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
		end
		return nil
	end
	local ast = Z.state[a:getId()]
	if not tst and not ast then
		return nil
	end
	if a:getId() == target:getId() then
		return nil
	end
	if not tst or not ast or tst.slot ~= ast.slot then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if isProtected(target, tst) then
		a:sendCancelMessage(Chaos.t(a, "That player is protected for a moment."))
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if ast.moveAt then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	local party = a:getParty()
	if party and party == target:getParty() then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(a) then
		a:sendCancelMessage(Chaos.t(a, Chaos.multiClient and Chaos.multiClient.msgPvp or "You cannot attack players now."))
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if K.protected(protectedUntil(a), now()) then
		a:setStorageValue(ST().protect, 0) -- attacking a player ends the own entry protection
		note(a, "Your protection ends: you attacked.")
	end
	return RETURNVALUE_NOERROR
end

-- ChaosSpell.canAttack: true / false, or nil when the zone has no say
function Z.canAttack(caster, target)
	local r = Z.targetCombat(caster, target)
	if r == nil then
		return nil
	end
	return r == RETURNVALUE_NOERROR
end

local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	return Z.targetCombat(creature, target) or RETURNVALUE_NOERROR
end
guard:register(-9)

local health = CreatureEvent("ChaosMarchesHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local tst = Z.state[creature:getId()]
	if not tst or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local t = now()
	if isProtected(creature, tst) then
		return 0, primaryType, 0, secondaryType
	end
	local a = playerOf(attacker)
	local mult = 1
	if a and a:getId() ~= creature:getId() then
		local ast = Z.state[a:getId()]
		if not ast or ast.slot ~= tst.slot or isProtected(a, ast) then
			return 0, primaryType, 0, secondaryType
		end
		mult = damageScale(a, creature)
		tst.lastHit = {cid = a:getId(), at = t}
		ast.lastCombat = t
	elseif attacker and zoneMonster(attacker) then
		mult = C().monsters.damageMult
	end
	tst.lastCombat = t
	if mult == 1 then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = math.floor(math.abs(primaryDamage) * mult + 0.5)
	local s = secondaryDamage
	if secondaryType ~= COMBAT_HEALING then
		s = math.floor(math.abs(secondaryDamage) * mult + 0.5)
	end
	return p, primaryType, s, secondaryType
end
health:register()

local mana = CreatureEvent("ChaosMarchesMana")
function mana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local tst = Z.state[creature:getId()]
	if not tst or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if isProtected(creature, tst) then
		return 0, primaryType, 0, secondaryType
	end
	local a = playerOf(attacker)
	if a and a:getId() ~= creature:getId() then
		local ast = Z.state[a:getId()]
		if not ast or ast.slot ~= tst.slot or isProtected(a, ast) then
			return 0, primaryType, 0, secondaryType
		end
		tst.lastHit = {cid = a:getId(), at = now()}
		ast.lastCombat = now()
	end
	tst.lastCombat = now()
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
mana:register()

local prepare = CreatureEvent("ChaosMarchesPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local st = Z.state[creature:getId()]
	if not st then
		return true
	end
	local ok, err = pcall(defeat, creature, st, killer)
	if not ok then
		log("defeat: " .. tostring(err))
		Z.state[creature:getId()] = nil
		pcall(release, creature, "defeat")
	end
	return false -- nobody dies in the Marches
end
prepare:register()

-- zone monsters: the attacker's last fight (the exit channel) and the embers of the kill
local mhealth = CreatureEvent("ChaosMarchesMonsterHealth")
function mhealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local a = playerOf(attacker)
	local ast = a and Z.state[a:getId()]
	if ast and primaryType ~= COMBAT_HEALING then
		ast.lastCombat = now()
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
mhealth:register()

local mdeath = CreatureEvent("ChaosMarchesMonsterDeath")
function mdeath.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local id = creature:getId()
	local slot = Z.scaled[id]
	-- the loot and experience callbacks run after this event: keep the mark a few seconds
	addEvent(function(cid) Z.scaled[cid] = nil end, 10000, id)
	local inst = slot ~= nil and Z.inst[slot] or nil
	local p = playerOf(mostDamageKiller) or playerOf(killer)
	local st = p and Z.state[p:getId()]
	if not st then
		return true
	end
	local cfg = C()
	local tier = (ChaosTierDead and ChaosTierDead[id] and ChaosTierDead[id].tier) or (ChaosTierOf and try(ChaosTierOf, creature))
		or "normal"
	local n = K.monsterEmbers(cfg, tier)
	if inst and inst.wardenCid == id then
		n = n + cfg.contest.embers.warden
	end
	local carried = getCarried(p)
	local nc, added, lostN = K.addCarried(cfg, carried, n)
	setCarried(p, nc)
	if lostN > 0 and (st.fullNote or 0) + 30 <= now() then
		st.fullNote = now()
		note(p, string.format("You cannot carry more than %d embers. Bank them at a safe exit.", cfg.carry.max))
	end
	if added > 0 then
		note(p, Chaos.t(p, "+%d embers (carrying %d). Bank them at a safe exit before you are defeated.", added, nc))
		Z.sendHud(p, st, true)
	end
	return true
end
mdeath:register()

-- map mode: the map's own monsters inside the rectangle are scaled at their first think (the engine gives a monster
-- its id only at the placement, after onSpawn; as monster_tiers.lua)
local scaleEv = CreatureEvent("ChaosMarchesMonsterScale")
function scaleEv.onThink(creature, interval)
	creature:unregisterEvent("ChaosMarchesMonsterScale")
	if creature:isMonster() and creature:getId() ~= 0 and not Z.scaled[creature:getId()] then
		local slot = Z.inZone(creature:getPosition())
		if slot ~= nil then
			scaleMonster(creature, slot)
		end
	end
	return true
end
scaleEv:register()

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if C().mode == "map" and not artificial and not self:getMaster() and K.slotOfPos(C(), position or self:getPosition()) == 0 then
		self:registerEvent("ChaosMarchesMonsterScale")
	end
	return true
end
spawnCb:register(8)

-- experience: zone monsters give more; the shrine holder's faction-wide buff
local xp = EventCallback
xp.onGainExperience = function(self, source, exp, rawExp)
	if not source or not source:isMonster() then
		return exp
	end
	local mult = 1
	if try(zoneMonster, source) then
		mult = mult * C().monsters.expMult
	end
	mult = mult * (try(buffMult, self, "exp") or 1)
	if mult == 1 then
		return exp
	end
	return math.floor(exp * mult)
end
xp:register(7)

-- ======================================================================== login / logout / opcode
local login = CreatureEvent("ChaosMarchesLogin")
function login.onLogin(player)
	for _, name in ipairs({"ChaosMarchesHealth", "ChaosMarchesMana", "ChaosMarchesPrepareDeath", "ChaosMarchesLogout",
			"ChaosMarchesExtended"}) do
		player:registerEvent(name)
	end
	Z.rowOf(player:getGuid())
	local slot = Z.inZone(player:getPosition())
	if slot ~= nil then
		Z.adopt(player, slot)
	elseif player:getStorageValue(ST().inside) == 1 then
		clearMarkers(player) -- the instance is gone (a restart without the season's instance): the embers stay carried
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosMarchesLogout")
function logout.onLogout(player)
	Z.state[player:getId()] = nil
	Z.saveRow(player:getGuid())
	Z.rows[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosMarchesStartup")
function startup.onStartup()
	Z.ensureTables()
	loadControl()
	if C().enabled then
		local cfg = C()
		if cfg.mode == "map" then
			Z.instance(0, cfg.area and cfg.area.realm or 0)
		else
			Z.instance(0, 0)
			local S = ChaosSeason
			local season = S and S.current and try(S.current)
			if season and season.id then
				Z.instance(K.slotForRealm(cfg, season.id), season.id)
			end
		end
	end
	local wt = Game.getWorldType and Game.getWorldType()
	if wt == WORLD_TYPE_NO_PVP then
		log("WARNING: world type no-pvp: the engine refuses every player attack before any script is asked, so the Marches " ..
			"have no PvP on this world (monsters, embers and the shrine still work).")
	end
	local f = io.open("data/events/scripts/creature.lua", "r")
	if f then
		local text = f:read("*a")
		f:close()
		if not text:find("ChaosPvpZone", 1, true) then
			log("WARNING: data/events/scripts/creature.lua does not ask ChaosPvpZone.targetCombat (run " ..
				"tools/patch_base_events.py): players with secure mode on cannot be attacked in the Marches.")
		end
	end
	return true
end
startup:register()

local ext = CreatureEvent("ChaosMarchesExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "marches." .. tostring(m.action), 300) then
		return
	end
	local data = type(m.data) == "table" and m.data or {}
	if m.action == "open" then
		Z.sendState(player, true)
	elseif m.action == "query" then
		Z.sendState(player, false)
		local st = Z.state[player:getId()]
		if st then
			Z.sendHud(player, st, true)
		end
	elseif m.action == "enter" then
		Z.enter(player, data)
		Z.sendState(player, false)
	elseif m.action == "pledge" then
		Z.pledge(player, tostring(data.faction or ""))
		Z.sendState(player, false)
	elseif m.action == "buy" then
		Z.buy(player, tostring(data.key or ""))
		Z.sendState(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

-- ======================================================================== staff: /marches
local talk = TalkAction("/marches")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getGroup():getId() < C().staffGroup then
		return false
	end
	local cmd, arg = tostring(param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	-- embers are spent in the Marches shop: an administrator only, logged (docs/GM_HANDBOOK.md section 2)
	if cmd == "embers" and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	local function info(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Marches: " .. text)
	end
	local slot = Z.inZone(player:getPosition()) or 0
	local inst = Z.inst[slot]
	if cmd == "status" or cmd == "" then
		local n = 0
		for _ in pairs(Z.state) do
			n = n + 1
		end
		local parts = {}
		for s, i in pairs(Z.inst) do
			parts[#parts + 1] = string.format("slot %d realm %d %s %s", s, i.realm or 0, i.built and "built" or ("bad: " ..
				tostring(i.bad)), i.contest and i.contest.phase or "-")
		end
		info(string.format("%d inside; %s; holder of realm 0: %s", n, table.concat(parts, "; "), tostring(Z.holderOf(0))))
	elseif cmd == "contest" and inst then
		inst.contest.nextAt = now()
		info("the contest starts now in slot " .. slot)
	elseif cmd == "window" and inst and inst.contest.phase ~= "idle" then
		inst.contest.endsAt = now() + (tonumber(arg) or 60)
		info("the contest window ends in " .. (tonumber(arg) or 60) .. " seconds")
	elseif cmd == "hold" then
		Z.control[inst and inst.realm or 0] = arg ~= "" and K.newControl(C(), arg, now()) or nil
		saveControl(inst and inst.realm or 0)
		info("holder now " .. tostring(arg))
	elseif cmd == "embers" then
		local n = tonumber(arg) or 0
		setCarried(player, getCarried(player) + n)
		info("carried " .. getCarried(player))
	elseif cmd == "testip" then
		Z.test.sameIp = arg == "on" and nil or false
		info("same-IP rule " .. (Z.test.sameIp == false and "OFF (TEST ONLY, memory)" or "on"))
	elseif cmd == "nopz" then
		Z.testNoPz = arg == "on" or nil
		info("protection zone rule " .. (Z.testNoPz and "OFF (TEST ONLY, memory)" or "on"))
	elseif cmd == "cooldown" then
		Z.cooldown = {}
		info("defeat cooldowns cleared")
	else
		info("/marches status | contest | window <s> | hold <faction|> | embers <n> | testip on|off | nopz on|off | cooldown")
	end
	return false
end
talk:separator(" ")
talk:register()
