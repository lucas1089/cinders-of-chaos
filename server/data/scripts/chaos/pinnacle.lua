-- Pinnacle bosses (O667): four Ascended versions of existing key bosses (Malgrath, Vhoss the Hexmaw, Talath, Varkhul the Ashen
-- Sovereign), shown at level 1900 / 2100 / 2300 / 2500 (the player cap, O672). A private fight in a runtime-built arena (the pocket boss grid layout),
-- alone or with a party of up to 5, opened by a whole set of four fragments at the Keeper of the Pinnacle.
-- Settings: pinnacle_config.lua (Chaos.pinnacleConfig). Pure logic: pinnacle_core.lua (tests/pinnacle_test.lua). Balance:
-- tools/pinnacle_model.py. Overview: server/README.md "Pinnacle bosses (O667)".
--
--   fragments   four kinds a boss, stored per character (storage block 7106400-7106459, pinnacle_config.lua `storage`): kind 1
--               drops from a waystone map of tier 12+ (ChaosWaystoneTiers.onRunCleared, a guarded wrap: nothing happens while
--               it does not exist), kind 2 from a rift of tier 15 and kind 3 from an Omen guardian (rift.lua's call of
--               ChaosAscended.onRiftSealed is wrapped, so rift.lua stays as it is), kind 4 (the keystone) from any of the three.
--               The focus (chosen at the Keeper) names the boss the fragments drop for.
--   the Keeper  an NPC (data/npc/Keeper of the Pinnacle.xml and its script) next to the temples: its modal window lists the
--               bosses with the fragments held; Open spends one of each kind and takes the party within range into the arena.
--               The set is written before anyone moves: a logout, a death or a crash never gives it back, except a restart
--               (shutdown) or a boss that did not come (and the run marker, which gives it back at the next login after a crash).
--   the fight   the boss's own monster type at the level of its row, health = the row's x the party curve, its hits x the damage
--               curve; boss_mechanics.lua attaches the profile of its name (boss_mechanics_config.lua). A lethal hit is caught:
--               the player goes back out, healed, and the fight is no longer deathless.
--   rewards     Conquest Tokens, orbs, a roll of the boss's exclusive unique (chance + a bad-luck count), a title for the first kill
--               of each season and a "deathless" title (titles.lua).
-- Exports: ChaosPinnacle.bosses(), .have(player, idx), .grant(player, idx, kind), .onRiftSealed(info), .onWaystoneCleared(...),
-- .enter(player, key), .isInside(player), .actions (none: no opcode). Staff: /pinnacle. Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosUberCore then
	dofile("data/scripts/chaos/uber_core.lua")
end
if not ChaosPocketBossCore then
	dofile("data/scripts/chaos/pocketboss_core.lua") -- K.arenaGate, the way out inside the arena
end
dofile("data/scripts/chaos/pinnacle_core.lua")
Chaos.pinnacleConfig = dofile("data/scripts/chaos/pinnacle_config.lua")
pcall(dofile, "data/lib/chaos_dark_paint.lua")
if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end

ChaosPinnacle = ChaosPinnacle or {}
local PN = ChaosPinnacle
local K = ChaosPinnacleCore
local U = ChaosUberCore
local HUD = ChaosOpcodes and ChaosOpcodes.rift
local unpack = table.unpack or unpack

local function C()
	return Chaos.pinnacleConfig
end

local function now()
	return os.time()
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function rand(a, b)
	return math.random(a, b)
end

local function log(text)
	print("[Chaos pinnacle] " .. text)
end

local function try(name, fn, ...)
	local ok, res, b = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res, b
end

-- a reason from the core ({key, args...}) in the player's language
local function say(player, why)
	if type(why) ~= "table" then
		return tostring(why or "")
	end
	return Chaos.t(player, why[1], unpack(why, 2))
end

PN.runs = PN.runs or {} -- slot -> run
PN.runOf = PN.runOf or {} -- player id -> run
PN.monsterRun = PN.monsterRun or {} -- monster id -> run
PN.built = PN.built or {}
PN.gates = PN.gates or {}
PN.bad = PN.bad or {}
PN.nextId = PN.nextId or 0
PN.lastEnter = PN.lastEnter or {} -- guid -> time

function PN.index()
	if not PN._index then
		PN._index = K.index(C())
	end
	return PN._index
end

function PN.bosses()
	return PN.index().list
end

-- ======================================================================== storage: fragments, focus, counts
local function S()
	return C().storage
end

local function readOf(player)
	return function(key)
		return player:getStorageValue(key)
	end
end

local function sget(player, off)
	local v = tonumber(player:getStorageValue(S().base + off)) or 0
	return v < 0 and 0 or v
end

local function sset(player, off, value)
	player:setStorageValue(S().base + off, value)
end

function PN.have(player, bossIdx)
	return K.have(C(), readOf(player), bossIdx)
end

function PN.focus(player)
	return sget(player, S().focus)
end

function PN.setFocus(player, bossIdx)
	sset(player, S().focus, bossIdx or 0)
end

-- one fragment of boss `bossIdx` and kind `kind` to a character (the cap holds). Returns true when it was added.
function PN.grant(player, bossIdx, kind, quiet)
	local boss = PN.index().list[bossIdx]
	if not player or not boss or kind < 1 or kind > 4 then
		return false
	end
	local key = K.fragKey(C(), bossIdx, kind)
	local count, added = K.addFragment(C(), math.max(0, tonumber(player:getStorageValue(key)) or 0), kind)
	if not added then
		if not quiet then
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You found a %s of %s, but you hold %d of them already.",
				boss.fragments[kind], boss.name, count))
		end
		return false
	end
	player:setStorageValue(key, count)
	if not quiet then
		local have = K.have(C(), readOf(player), bossIdx)
		local held = 0
		for k = 1, 4 do
			if have[k] > 0 then
				held = held + 1
			end
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You found a %s of %s: %d of 4 kinds held.",
			boss.fragments[kind], boss.name, held))
	end
	return true
end

-- the set is spent (one of each kind) and written before anyone moves
local function spendSet(player, bossIdx)
	for kind = 1, 4 do
		local key = K.fragKey(C(), bossIdx, kind)
		player:setStorageValue(key, math.max(0, (tonumber(player:getStorageValue(key)) or 0) - 1))
	end
end

local function refundSet(player, bossIdx)
	for kind = 1, 4 do
		local key = K.fragKey(C(), bossIdx, kind)
		player:setStorageValue(key, math.min(C().fragments.cap or 6, math.max(0, tonumber(player:getStorageValue(key)) or 0) + 1))
	end
end

local function setMarker(player, bossIdx)
	sset(player, S().marker, K.marker(bossIdx))
	sset(player, S().markerAt, bossIdx > 0 and now() or 0)
	if bossIdx > 0 and player.save then
		player:save()
	end
end

-- ======================================================================== where the fragments come from
-- one clear of a source for one character: the rolls of the source, each fragment given
function PN.grantClear(player, source, info)
	local cfg = C()
	if not cfg.enabled or not player then
		return 0
	end
	local got = 0
	for _, f in ipairs(K.rollClear(cfg, source, info, player:getLevel(), PN.focus(player), rand)) do
		if PN.grant(player, f.boss, f.kind) then
			got = got + 1
		end
	end
	return got
end

-- one fragment already rolled by its source (the Greater Rift, O668: greater_ladder.lua rolls its own chance): the keystone kind
-- of the focus boss, or of an open boss. Returns true when it was added.
function PN.grantFragment(player, source, info)
	local cfg = C()
	if not cfg.enabled or not player then
		return false
	end
	local boss = K.dropBoss(cfg, player:getLevel(), PN.focus(player), rand)
	if not boss then
		return false
	end
	return PN.grant(player, boss, 4)
end

local function playerOfFinisher(f)
	if type(f) == "userdata" or (type(f) == "table" and f.getStorageValue) then
		return f
	end
	if type(f) == "number" then
		return Player(f)
	end
	return nil
end

-- rift.lua: a sealed rift or a slain Omen guardian, through the wrap of ChaosAscended.onRiftSealed (same info table:
-- tier, omen = the omen kind or nil, finishers = {[guid] = {name}}, players)
function PN.onRiftSealed(info)
	if type(info) ~= "table" then
		return
	end
	local source = info.omen and "omen" or "rift"
	for guid, f in pairs(info.finishers or {}) do
		local p = type(f) == "table" and f.name and Player(f.name)
		if p and p:getGuid() == guid then
			try("grant clear", PN.grantClear, p, source, {tier = info.tier, omen = info.omen and true or false})
		end
	end
end

-- the waystone tiers' hook (O666): ChaosWaystoneTiers.onRunCleared(...). The arguments are read as they come: a table with `tier`
-- (and `players` / `finishers`: a list of players, of ids or {[guid] = {name}}), or a tier number then a list. A call it cannot
-- read gives nothing.
function PN.onWaystoneCleared(...)
	local args = {...}
	local tier, list = nil, nil
	for _, a in ipairs(args) do
		if type(a) == "table" and not a.getStorageValue then
			tier = tier or tonumber(a.tier) or tonumber(a.level and a.tierIndex)
			list = list or a.players or a.finishers or a.party
		elseif type(a) == "number" and not tier then
			tier = a
		elseif a and not list and (type(a) == "userdata") then
			list = {a}
		end
	end
	-- O671: the real call (ChaosWaystoneEndgame `fire`, O666) also carries `fragmentChance`, the opener's Endgame Atlas rank in percent points:
	-- it adds to the chance of the waystone's own kind (K.rollClear)
	local info = type(args[1]) == "table" and not args[1].getStorageValue and args[1] or nil
	if not tier or type(list) ~= "table" then
		return 0
	end
	local n = 0
	for k, f in pairs(list) do
		local p
		if type(f) == "table" and f.name and not f.getStorageValue then
			p = Player(f.name)
		else
			p = playerOfFinisher(f)
		end
		if p then
			n = n + (try("grant clear", PN.grantClear, p, "waystone", {tier = tier, fragmentChance = info and tonumber(info.fragmentChance) or nil}) or 0)
		end
	end
	return n
end

local function wrapHook(owner, field, handler, flag)
	if type(owner) ~= "table" or type(owner[field]) ~= "function" or PN[flag] == owner[field] then
		return false
	end
	local original = owner[field]
	local wrapped
	wrapped = function(...)
		local res = {original(...)}
		pcall(handler, ...)
		return unpack(res)
	end
	owner[field] = wrapped
	PN[flag] = wrapped
	return true
end

function PN.wrapHooks()
	local a = wrapHook(ChaosAscended, "onRiftSealed", PN.onRiftSealed, "_wrapRift")
	local w = false
	local name = C().fragments.hook and C().fragments.hook.waystone
	if name and ChaosWaystoneTiers then
		w = wrapHook(ChaosWaystoneTiers, name, PN.onWaystoneCleared, "_wrapWaystone")
	end
	return a, w
end

-- ======================================================================== titles
local function seasonId()
	local ok, s = pcall(function() return ChaosSeason and ChaosSeason.current and ChaosSeason.current() end)
	return ok and type(s) == "table" and tonumber(s.id) or 0
end

function PN.titlesOf(player)
	local out = {}
	local cfg = C()
	for i, boss in ipairs(PN.index().list) do
		local first = sget(player, S().first + i - 1)
		local dl = sget(player, S().deathless + i - 1)
		for _, t in ipairs(K.titleList(cfg, boss, first, dl, nil, 0)) do
			out[#out + 1] = t
		end
	end
	return out
end

local function registerTitles()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register(C().titles.source, PN.titlesOf)
	end
end
registerTitles()

-- ======================================================================== arena slots (uber_core.lua layout, as the pocket bosses)
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

local function dressSlot(L, bossKey, arenaGate)
	local cfg = C()
	ChaosArenaLook.dressBossArena("pinnacle", L, cfg, bossKey, arenaGate)
	for _, t in ipairs(L.basins) do
		placeItem(P(ChaosArenaLook.fixtureSpot(t, {L.rect}, ChaosArenaLook.wallSizeOf(cfg.wallId))), cfg.basinId)
	end
end

local function buildSlot(slot, bossKey)
	local cfg = C()
	local isDark = dark()
	local L = U.layout(cfg, slot)
	if PN.built[slot] then
		L.arenaGate = PN.gates[slot]
		dressSlot(L, bossKey, L.arenaGate)
		return L
	end
	if PN.bad[slot] then
		return nil, PN.bad[slot]
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
	local wallAt = ChaosArenaLook.wallPlacer(cfg.wallId, L.wallList)
	for _, t in ipairs(L.wallList) do
		placeItem(P(t), wallAt(t.x, t.y))
	end
	-- a second way out inside the arena, next to where the players arrive (as the pocket bosses: K.arenaGate of the pocket core)
	local taken = {[L.bossSpawn.x .. "," .. L.bossSpawn.y] = true, [L.portal.x .. "," .. L.portal.y] = true}
	for _, b in ipairs(L.basins) do
		taken[b.x .. "," .. b.y] = true
	end
	for _, st in ipairs(L.starts or {}) do
		taken[st.x .. "," .. st.y] = true
	end
	local best = ChaosPocketBossCore and ChaosPocketBossCore.arenaGate and ChaosPocketBossCore.arenaGate(L.floorList,
		(L.starts and L.starts[1]) or L.entry, taken) or nil
	L.arenaGate = best
	dressSlot(L, bossKey, best)
	local gate = placeItem(P(L.portal), cfg.portalId)
	if gate then
		gate:setActionId(cfg.portalActionId)
	end
	if best then
		local arenaGate = placeItem(P(best), cfg.portalId)
		if arenaGate then
			arenaGate:setActionId(cfg.portalActionId)
		end
	end
	PN.built[slot] = true
	PN.gates[slot] = best
	return L
end

local function cleanSlot(L)
	local cfg = C()
	local keep = ChaosArenaLook.wallIds(cfg.wallId, {[cfg.groundId] = true, [cfg.basinId] = true, [cfg.portalId] = true})
	for _, list in ipairs({L.floorList, L.anteList}) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						PN.monsterRun[c:getId()] = nil
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					local id = item:getId()
					if not keep[id] and not (cfg.darkActive and ChaosDarkPaint and ChaosDarkPaint.isDark(id)) and not ChaosArenaLook.isOwned(id) then
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
		local slot = U.allocSlot(cfg, PN.runs, PN.bad)
		if not slot then
			return nil
		end
		local L, why = buildSlot(slot, bossKey)
		if L then
			return slot, L
		end
		PN.bad[slot] = why
		log(string.format("slot %d not usable: %s", slot, tostring(why)))
	end
end

-- a monster of a fight: created by it, or standing in the grid (adds of boss mechanics)
function PN.isPinnacleMonster(monster)
	if not monster then
		return nil
	end
	local run = PN.monsterRun[monster:getId()]
	if run then
		return run
	end
	local ok, pos = pcall(function() return monster:getPosition() end)
	local slot = ok and U.slotAt(C(), pos)
	return slot and PN.runs[slot] or nil
end

-- ======================================================================== the run
local function tell(run, text, ...)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, text, ...))
		end
	end
end

local function bossOf(run)
	return run.bossId and Monster(run.bossId) or nil
end

local function timeLeft(run, t)
	local limit = (C().minutes or 20) * 60
	if run.bossAt then
		return math.max(0, math.floor(limit - (t - run.bossAt) / 1000))
	end
	return limit + math.max(0, math.ceil(((run.bossDueAt or t) - t) / 1000))
end
PN.timeLeft = timeLeft

local function hudData(run)
	local limit = (C().minutes or 20) * 60
	local boss = bossOf(run)
	local notes = {}
	if run.state == "running" and boss then
		notes[#notes + 1] = string.format("Health: %d%%", math.floor(boss:getHealth() * 100 / math.max(1, boss:getMaxHealth())))
	end
	notes[#notes + 1] = run.falls == 0 and "Deathless so far" or string.format("Falls: %d", run.falls)
	return {tier = 0, theme = run.boss.name, left = timeLeft(run, mnow()), limit = limit, total = 0, killed = 0, bossAt = 0,
		boss = run.bossState, state = run.state, bossName = run.boss.name, mods = {}, notes = notes,
		title = "Pinnacle: " .. run.boss.name}
end

local function sendHud(run, action, player)
	if not HUD or not Chaos.send then
		return
	end
	local data = hudData(run)
	if player then
		Chaos.send(player, HUD, action, data)
		return
	end
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			Chaos.send(p, HUD, action, data)
		end
	end
end

local function eventsOn(player)
	player:registerEvent("ChaosPinnacleHit")
	player:registerEvent("ChaosPinnaclePrepareDeath")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosPinnacleHit")
	player:unregisterEvent("ChaosPinnaclePrepareDeath")
end

local finishExit

local function removePlayer(run, id, mode)
	local entry = run.players[id]
	if not entry then
		return
	end
	run.players[id] = nil
	PN.runOf[id] = nil
	local player = Player(id)
	if player then
		eventsOff(player)
		setMarker(player, 0)
		if mode ~= "stay" and mode ~= "logout" then
			local dest = entry.entry and P(entry.entry) or player:getTown():getTemplePosition()
			player:teleportTo(dest)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		player:removeCondition(CONDITION_INFIGHT)
		if mode ~= "logout" and HUD and Chaos.send then
			local running = run.state == "running"
			Chaos.send(player, HUD, "end", {result = running and "left" or run.state,
				text = Chaos.tx(player, running and "You left the fight." or (run.endText or ""))})
		end
	end
	if next(run.players) == nil and not run.ended then
		if run.state == "running" then
			run.state = "failed"
			run.endText = "Everyone left the fight."
		end
		finishExit(run)
	end
end

local function removeMonsters(run)
	for mid, r in pairs(PN.monsterRun) do
		if r == run then
			PN.monsterRun[mid] = nil
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
	if PN.runs[run.slot] == run then
		PN.runs[run.slot] = nil
		if ChaosInstanceLimits and not run.restart then
			ChaosInstanceLimits.freed("pinnacle", "the pinnacle arenas")
		end
	end
	log(string.format("run %d (%s, slot %d, %d player(s)) ended: %s", run.id, run.boss.key, run.slot, run.size, run.state))
end

local function fail(run, text, ...)
	if run.ended or run.state ~= "running" then
		return
	end
	run.state = "failed"
	tell(run, text, ...)
	run.endText = "The fight ends."
	sendHud(run, "update")
	finishExit(run)
end
PN._fail = fail

-- the opener's set comes back (a restart, a boss that did not come)
local function refundOpener(run)
	local op = run.opener and Player(run.opener)
	if op and not run.refunded then
		run.refunded = true
		refundSet(op, run.boss.index)
	elseif run.openerGuid and not run.refunded then
		run.refunded = true
		PN.pendingRefund = PN.pendingRefund or {}
		PN.pendingRefund[run.openerGuid] = run.boss.index
	end
end

function PN.interruptAll()
	for _, run in pairs(PN.runs) do
		if not run.ended then
			run.restart = true
			if run.state == "running" and C().refundOnRestart then
				refundOpener(run)
				run.state = "interrupted"
				run.endText = "The server is restarting: the fight closes and your set is given back."
				tell(run, run.endText)
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

local function giveEx(player, item)
	if player:addItemEx(item, false) == (RETURNVALUE_NOERROR or 0) then
		return false
	end
	local inbox = player:getInbox()
	if inbox then
		inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	return true
end

-- the entry of ChaosUniqueItems of the boss's unique (by name)
local function uniqueEntry(boss)
	for _, e in pairs(ChaosUniqueItems or {}) do
		if type(e) == "table" and e.name == boss.unique.name then
			return e
		end
	end
	return nil
end

local function refreshPlate(player)
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
end

-- one player's spoils and titles. Returns the list of what was found (for the message)
local function deliver(run, player)
	local cfg = C()
	local boss = run.boss
	local idx = boss.index
	local r = K.reward(cfg, boss)
	local inbox = false
	if r.tokens > 0 and ChaosConquest and ChaosConquest.grant then
		pcall(ChaosConquest.grant, player, "pinnacle", r.tokens, boss.key)
	end
	inbox = giveStack(player, cfg.orbs.chaos, r.chaos) or inbox
	inbox = giveStack(player, cfg.orbs.divine, r.divine) or inbox
	inbox = giveStack(player, cfg.orbs.exalted, r.exalted) or inbox
	local found = {}
	-- the exclusive unique
	local find = 1
	if ChaosLoot and ChaosLoot.itemFindMult then
		local okF, f = pcall(ChaosLoot.itemFindMult, player)
		find = okF and tonumber(f) or 1
	end
	local drop, pity = K.uniqueRoll(cfg, sget(player, S().pity + idx - 1), find, rand)
	sset(player, S().pity + idx - 1, pity)
	if drop then
		local e = uniqueEntry(boss)
		local item = e and Game.createItem(e.id, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			inbox = giveEx(player, item) or inbox
			if ChaosUniqueIntro then
				pcall(ChaosUniqueIntro.found, player)
			end
			found[#found + 1] = "{" .. e.name .. "}"
		else
			log("the unique " .. boss.unique.name .. " is not in ChaosUniqueItems: nothing given")
		end
	end
	-- counts and titles
	sset(player, S().kills + idx - 1, sget(player, S().kills + idx - 1) + 1)
	local bit = K.seasonBit(seasonId())
	local mask = sget(player, S().first + idx - 1)
	local title = nil
	if not K.hasBit(mask, bit) then
		sset(player, S().first + idx - 1, K.setBit(mask, bit))
		title = string.format(cfg.titles.first, boss.short, "[S" .. bit .. "]")
	end
	if run.falls == 0 and sget(player, S().deathless + idx - 1) < 1 then
		sset(player, S().deathless + idx - 1, 1)
		title = (title and (title .. ", ") or "") .. string.format(cfg.titles.deathless, boss.short)
	end
	if title then
		refreshPlate(player)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"Spoils of %s: %d Orbs of Upheaval, %d Orbs of Fate, %d Exalted Orbs, %d Conquest Tokens%s%s.%s", boss.name, r.chaos, r.divine, r.exalted,
		r.tokens, #found > 0 and ", " or "", table.concat(found, ", "),
		inbox and Chaos.t(player, " Your backpack was full: the rest is in your inbox.") or ""))
	if title then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "New title: %s.", title))
	end
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	return found
end

local function success(run)
	run.state = "success"
	run.bossState = "dead"
	local secs = math.max(1, math.floor((mnow() - (run.bossAt or mnow())) / 1000))
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			try("deliver", deliver, run, p)
			if ChaosMetrics and ChaosMetrics.firstUse then
				pcall(ChaosMetrics.firstUse, p, "pinnacle")
			end
		end
	end
	tell(run, "%s falls in %s%s. The arena closes in %d seconds: leave through the forcefield by the arrival.",
		run.boss.name, K.clockText(secs), run.falls == 0 and " (deathless)" or "", C().exitDelay)
	sendHud(run, "update")
	local slot, rid = run.slot, run.id
	addEvent(function()
		local r = PN.runs[slot]
		if r and r.id == rid then
			finishExit(r)
		end
	end, C().exitDelay * 1000)
end

-- ======================================================================== the fight
local function arenaPlayers(run)
	local out = {}
	for id in pairs(run.players) do
		local p = Player(id)
		if p and U.inArena(run.L, p:getPosition()) then
			out[#out + 1] = p
		end
	end
	return out
end

local function setHealth(monster, hp)
	hp = math.max(1, math.floor(hp))
	monster:setMaxHealth(hp)
	-- O681: this engine's Creature:addHealth takes (damage type, amount): the one-argument call healed nothing, so a party's boss (a maximum above the
	-- solo health the mechanics' factor left it at) stood at 27% of it in a party of five. Chaos.heal covers both signatures
	Chaos.heal(monster, hp - monster:getHealth())
end

local function spawnBoss(run)
	PN.creating = true
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	local ok, m = pcall(create, run.boss.name, P(run.L.bossSpawn), false, true, nil, run.boss.level)
	PN.creating = false
	if not ok or not m then
		log("cannot create " .. tostring(run.boss.name) .. ": " .. tostring(m))
		refundOpener(run)
		fail(run, "The boss did not answer; your set is given back.")
		return
	end
	PN.monsterRun[m:getId()] = run
	run.bossId = m:getId()
	local hpMult = 1
	if ChaosBossMech and ChaosBossMech.attach then
		local rid, slot = run.id, run.slot
		local okA, f = pcall(ChaosBossMech.attach, m, nil, {tiles = run.L.floorList, size = run.size, solo = run.size == 1,
			players = function()
				local r = PN.runs[slot]
				return (r and r.id == rid) and arenaPlayers(r) or {}
			end})
		if okA and type(f) == "table" and tonumber(f.hpMult) then
			hpMult = f.hpMult -- the mechanics' downtime: the health that keeps the planned kill time (boss_mechanics_core G.balance)
		end
	end
	setHealth(m, K.bossHealth(run.boss, run.size) * hpMult)
	m:registerEvent("ChaosPinnacleDeath")
	run.bossState = "alive"
	run.bossAt = mnow()
	tell(run, "%s appears. You have %d minutes.", run.boss.name, C().minutes or 20)
	sendHud(run, "update")
end

local function tick(slot, rid)
	local run = PN.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local cfg = C()
	local t = mnow()
	for id in pairs(run.players) do
		local p = Player(id)
		if not p then
			removePlayer(run, id, "logout")
		else
			local pos = p:getPosition()
			if not U.inArena(run.L, pos) and not U.inAnte(run.L, pos) then
				removePlayer(run, id, "stay")
			end
		end
	end
	if run.ended or PN.runs[slot] ~= run then
		return
	end
	if Chaos.sweepDue and Chaos.sweepDue(run, t) then
		Chaos.sweepIntruders(function(pos) return U.slotAt(cfg, pos) == slot end,
			function(p) return run.players[p:getId()] ~= nil end, "This arena is not yours: you were sent to your temple.")
	end
	if run.state == "running" and run.bossState == "waiting" and t >= (run.bossDueAt or 0) then
		spawnBoss(run)
	end
	if run.ended then
		return
	end
	if run.state == "running" and run.bossState == "alive" then
		if timeLeft(run, t) <= 0 then
			fail(run, "Time is up: %s still stands.", run.boss.name)
			return
		end
		local boss = bossOf(run)
		if boss and not boss:getTarget() and #arenaPlayers(run) == 0 then
			boss:teleportTo(P(run.L.bossSpawn))
		end
		if ChaosInstanceLimits then
			ChaosInstanceLimits.warn(run, timeLeft(run, t), ChaosInstanceLimits.playersOf(run.players), run.boss.name, cfg.limits)
		end
	end
	if t >= (run.nextHud or 0) then
		run.nextHud = t + (cfg.hudEvery or 2) * 1000
		sendHud(run, "update")
	end
	addEvent(tick, cfg.tickMs or 500, slot, rid)
end
PN._tick = tick

-- ======================================================================== entering
local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	if Chaos.inCombat then
		return Chaos.inCombat(player)
	end
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function instanceOf(player)
	if PN.runOf[player:getId()] then
		return "a pinnacle fight"
	end
	local _, label = Chaos.inAnyInstance and Chaos.inAnyInstance(player, "pinnacle")
	return label
end

local function partyOf(player)
	local party = player:getParty()
	if not party then
		return {player}
	end
	local out = {party:getLeader()}
	for _, m in ipairs(party:getMembers() or {}) do
		out[#out + 1] = m
	end
	return out
end

function PN.enter(player, key)
	local cfg = C()
	local boss = PN.index().byKey[key]
	local guid = player:getGuid()
	local t = now()
	local last = PN.lastEnter[guid] or 0
	local info = {enabled = cfg.enabled, boss = boss, level = player:getLevel(), needPz = cfg.needProtectionZone,
		pz = inProtectionZone(player), inFight = inCombat(player), instance = instanceOf(player),
		cooldown = math.max(0, last + (cfg.enterCooldown or 0) - t)}
	if boss then
		info.have = PN.have(player, boss.index)
	end
	local why = K.enterError(info)
	if why then
		return false, say(player, why)
	end
	local group, left = {player}, {}
	local from = player:getPosition()
	local range = (cfg.party or {}).range or 8
	for _, m in ipairs(partyOf(player)) do
		if m:getId() ~= player:getId() then
			local mp = m:getPosition()
			local mwhy = #group >= ((cfg.party or {}).max or 5) and K.T("the arena is full") or K.memberError({boss = boss,
				level = m:getLevel(), instance = instanceOf(m), inFight = inCombat(m),
				far = mp.z ~= from.z or math.max(math.abs(mp.x - from.x), math.abs(mp.y - from.y)) > range})
			if mwhy then
				left[#left + 1] = {player = m, why = mwhy}
			else
				group[#group + 1] = m
			end
		end
	end
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(PN.runs) do
		running = running + 1
	end
	if ChaosTesters and ChaosTesters.soloRefusal then
		local twhy = ChaosTesters.soloRefusal(group, (cfg.limits.maxRuns or 8) - running, (cfg.tester or {}).reserve or 2)
		if twhy then
			return false, Chaos.t(player, twhy)
		end
	end
	local slot, L
	if not (IL and IL.capped("pinnacle", running, cfg.limits)) then
		slot, L = takeSlot(boss.name)
	end
	if not slot then
		if IL then
			local lefts, mt = {}, mnow()
			for _, r in pairs(PN.runs) do
				lefts[#lefts + 1] = r.state == "running" and timeLeft(r, mt) or cfg.exitDelay
			end
			return false, IL.busy(player, "pinnacle", "pinnacle arenas", lefts, cfg.limits)
		end
		return false, Chaos.t(player, "Every pinnacle arena is in use. Try again in a moment.")
	end
	-- the set: spent and written before anyone moves; the run marker gives it back after a crash
	spendSet(player, boss.index)
	PN.lastEnter[guid] = t
	cleanSlot(L)
	PN.nextId = PN.nextId + 1
	local run = {id = PN.nextId, slot = slot, L = L, boss = boss, players = {}, state = "running", bossState = "waiting", size = 0,
		falls = 0, startedAt = t, bossDueAt = mnow() + (cfg.startDelay or 8) * 1000, opener = player:getId(), openerGuid = guid}
	PN.runs[slot] = run
	for i, m in ipairs(group) do
		local p = m:getPosition()
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), name = m:getName(), entry = {x = p.x, y = p.y, z = p.z}}
		run.size = run.size + 1
		PN.runOf[m:getId()] = run
		eventsOn(m)
		if m:getId() == player:getId() then
			setMarker(m, boss.index)
		end
		p:sendMagicEffect(CONST_ME_TELEPORT)
		m:teleportTo(P(L.starts[(i - 1) % #L.starts + 1] or L.entry))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
	for _, l in ipairs(left) do
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s stays behind: %s.", l.player:getName(), say(player, l.why)))
		l.player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(l.player, "You stay behind from the fight with %s: %s.", boss.name,
			say(l.player, l.why)))
	end
	tell(run, "%s comes in %d seconds. Deathless means nobody falls; the way out is in the room to the south.", boss.name,
		cfg.startDelay or 8)
	sendHud(run, "start")
	log(string.format("%s opened run %d (%s): slot %d, %d player(s)", player:getName(), run.id, key, slot, run.size))
	addEvent(tick, cfg.tickMs or 500, slot, run.id)
	return true
end

function PN.isInside(player)
	return PN.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("pinnacle", {label = "a pinnacle arena", inside = PN.isInside, at = function(pos)
	return U.slotAt(C(), pos) ~= nil
end, runs = function()
	local out = {}
	for slot, run in pairs(PN.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.id, what = string.format("%s, slot %d, %s", run.boss.name, slot, run.state),
			left = run.state == "running" and timeLeft(run, mnow()) or nil, players = n}
	end
	return out
end, close = function(id)
	for _, run in pairs(PN.runs) do
		if run.id == id and not run.ended then
			if run.state == "running" then
				fail(run, "A gamemaster closed the fight.")
			else
				finishExit(run)
			end
			return true, "Pinnacle run " .. id .. " closed."
		end
	end
	return false, "No pinnacle run " .. tostring(id) .. "."
end})

-- what a person sees (the tester bots, `!tester`-style checks read it): the bosses with the fragments held and what blocks. Inside a run (O678):
-- the run (boss health percent, clock, falls, who is in it) and `guide` (U.guide: the same recipe as the Ascended arenas) for the walk to the boss
function PN.probe(player)
	local cfg = C()
	local out = {level = player:getLevel(), focus = PN.focus(player), bosses = {}, enabled = cfg.enabled, pz = inProtectionZone(player),
		fight = inCombat(player) and true or false, pos = {x = player:getPosition().x, y = player:getPosition().y, z = player:getPosition().z}}
	for _, b in ipairs(PN.index().list) do
		local have = PN.have(player, b.index)
		out.bosses[#out.bosses + 1] = {key = b.key, name = b.name, minLevel = b.minLevel, have = have, ready = K.setReady(have),
			open = player:getLevel() >= b.minLevel, kills = sget(player, S().kills + b.index - 1)}
	end
	local running = 0
	for _ in pairs(PN.runs) do
		running = running + 1
	end
	out.free = (cfg.limits.maxRuns or 8) - running
	out.reserve = (cfg.tester or {}).reserve or 2
	local run = PN.runOf[player:getId()]
	out.inside = run and run.boss.key or nil
	if not run or run.ended then
		return out
	end
	local boss = bossOf(run)
	local members, testers = 0, 0
	for pid in pairs(run.players) do
		members = members + 1
		local p = Player(pid)
		if p and Chaos.isTester and Chaos.isTester(p) then
			testers = testers + 1
		end
	end
	local pos = out.pos
	local bossPos = boss and {x = boss:getPosition().x, y = boss:getPosition().y, z = boss:getPosition().z} or nil
	out.run = {id = run.id, slot = run.slot, kind = run.boss.key, boss = run.bossState, state = run.state, lives = nil, players = members,
		testers = testers, size = run.size, falls = run.falls, left = timeLeft(run, mnow()), bossPos = bossPos,
		bossHp = boss and math.floor(boss:getHealth() * 100 / math.max(1, boss:getMaxHealth())) or nil,
		bossHealth = boss and boss:getHealth() or nil, bossMax = boss and boss:getMaxHealth() or nil,
		sinceBoss = run.bossAt and math.floor((mnow() - run.bossAt) / 1000) or nil,
		gate = {x = run.L.portal and run.L.portal.x or 0, y = run.L.portal and run.L.portal.y or 0, z = run.L.portal and run.L.portal.z or 0}}
	out.guide = U.guide({inside = true, state = run.state, boss = run.bossState, down = false, pos = pos, bossPos = bossPos,
		reach = 5})
	-- O681: what a person sees of the boss's telegraphs (ChaosBossMech.dangerFor, as testers_boss.lua reads them): when a mark covers the bot's tile
	-- the guide says `dodge` to the nearest safe tile, as a player steps off the warning before the hit
	local M = rawget(_G, "ChaosBossMech")
	local dmarked
	if M and M.dangerFor and run.bossId and boss then
		local okD, danger = pcall(M.dangerFor, run.bossId, pos, player:getId())   -- O684: with the player's id: a goal no other bot of the party took
		if okD and danger then
			dmarked = danger.marked
			out.danger = {left = danger.left, labels = danger.labels, count = danger.count,
				here = danger.marked and danger.marked[pos.x .. "," .. pos.y] == true or false}
			if danger.route then
				-- O684: the way to that goal as steps (dx, dy) from the bot's tile (at most 12): the bot walks what the server planned
				local steps, px, py = {}, pos.x, pos.y
				for i = 1, math.min(#danger.route, 12) do
					local t = danger.route[i]
					steps[i] = {t.x - px, t.y - py}
					px, py = t.x, t.y
				end
				out.danger.steps = steps
			end
			if danger.goal then
				out.guide = {mode = "dodge", goal = {x = danger.goal.x, y = danger.goal.y, z = danger.goal.z}, area = "boss",
					why = "a mark of " .. tostring(danger.labels and danger.labels[1]) .. " is on the bot's tile"}
			end
		end
	end
	-- O683: what the telegraphs did so far (fired, exposed players, taken): the share of marks taken the model's `marksTaken` stands for
	if M and M.tallyFor and run.bossId and boss then
		local okT, tally = pcall(M.tallyFor, run.bossId)
		if okT and tally then
			out.tally = tally
		end
	end
	-- O681: the adds and the totem of the boss's phases (the anchors that shield it, the idols that empower it, the totem a channel is stopped by): the
	-- nearest one is what a person breaks first ("Break them!"); the guide walks to it and the helper's loop aims at it (PN.priorityTarget)
	local add = PN.nearestAdd(player)
	if add then
		local ap = add:getPosition()
		out.adds = {id = add:getId(), pos = {x = ap.x, y = ap.y, z = ap.z}}
		if out.guide.mode ~= "dodge" then
			local reach = 5
			local near = ap.z == pos.z and math.max(math.abs(ap.x - pos.x), math.abs(ap.y - pos.y)) <= reach
			out.guide = {mode = near and "fight" or "walk", goal = {x = ap.x, y = ap.y, z = ap.z}, reach = {1, reach}, area = "adds",
				why = near and "an add of the boss stands in reach" or "to the nearest add of the boss"}
		end
	end
	-- O683: a mark is up, the bot is off it and its walk would end on or next to a marked tile (the boss's feet, an add inside a ring): it holds
	-- (stays and fights from where it stands) until the hit, as a person waits for the warning to pass. The walk went back into the mark it
	-- had just left in one dodge of five
	local g = out.guide
	if dmarked and g and g.mode == "walk" and g.goal and not (out.danger and out.danger.here) then
		local near = false
		for ox = -1, 1 do
			for oy = -1, 1 do
				if dmarked[(g.goal.x + ox) .. "," .. (g.goal.y + oy)] then
					near = true
				end
			end
		end
		if near then
			out.guide = {mode = "hold", goal = g.goal, area = g.area, why = "a mark lies on the way: the bot waits for the hit"}
		end
	end
	return out
end

-- O681 (the tester bots): the nearest live add or totem of the fight the player is in (ChaosBossMech.addsFor), a Monster, or nil
function PN.nearestAdd(player)
	local run = PN.runOf[player:getId()]
	local M = rawget(_G, "ChaosBossMech")
	if not (run and not run.ended and run.bossId and M and M.addsFor) then
		return nil
	end
	local okA, ids = pcall(M.addsFor, run.bossId)
	if not (okA and ids) then
		return nil
	end
	local pos = player:getPosition()
	local best, bestD
	for _, id in ipairs(ids) do
		local m = Monster(id)
		if m then
			local mp = m:getPosition()
			local d = mp.z == pos.z and math.max(math.abs(mp.x - pos.x), math.abs(mp.y - pos.y)) or 999
			if not bestD or d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

-- the target the tester helper's loop gives a bot inside a fight before the boss: an add that shields, empowers or channels (the same as the guide's)
PN.priorityTarget = PN.nearestAdd

-- TEST ONLY (`!tester pinnacle set [boss]`, O678): a whole set of fragments (one of each kind) of the boss for a TESTER: the top content that drops them
-- (a waystone map of tier 12, a rift of tier 15, an Omen guardian) is hours of play a check cannot repeat. The boss is the named one, else the highest
-- the level opens. Never for a player, never inside a run, one console line each. -> the boss key, or nil + why
function PN.testerSet(player, want)
	if not (Chaos.isTester and Chaos.isTester(player)) then
		return nil, "not a tester"
	end
	if PN.runOf[player:getId()] then
		return nil, "already inside a pinnacle fight"
	end
	local boss
	if want and want ~= "" then
		boss = PN.index().byKey[want]
		if not boss then
			return nil, "no pinnacle boss named " .. tostring(want)
		end
		if player:getLevel() < boss.minLevel then
			return nil, string.format("level %d: %s opens from level %d", player:getLevel(), boss.name, boss.minLevel)
		end
	else
		for _, b in ipairs(PN.index().list) do
			if player:getLevel() >= b.minLevel and (not boss or b.minLevel > boss.minLevel) then
				boss = b
			end
		end
		if not boss then
			return nil, string.format("level %d opens no pinnacle boss", player:getLevel())
		end
	end
	local have = PN.have(player, boss.index)
	for kind = 1, 4 do
		if (have[kind] or 0) < 1 then
			PN.grant(player, boss.index, kind, true)
		end
	end
	log(string.format("TEST ONLY: a whole set of %s given to tester %s (level %d)", boss.key, player:getName(), player:getLevel()))
	return boss.key
end

function PN.testerClose(player)
	local run = PN.runOf[player:getId()]
	if not run then
		return false
	end
	removePlayer(run, player:getId(), "out")
	return true
end

-- a lethal hit: out, healed, no death; the set stays spent and the fight is no longer deathless
local function fall(run, pid)
	local p = Player(pid)
	if not p or not run.players[pid] then
		return
	end
	run.falls = run.falls + 1
	Chaos.heal(p, p:getMaxHealth() - p:getHealth())
	tell(run, "%s falls and is carried out of the arena.", p:getName())
	removePlayer(run, pid, "out")
end

-- ======================================================================== the Keeper's modal window
local function limited(player)
	return ChaosRateLimit and not ChaosRateLimit.allow(player, "pinnacle", C().requestMs or 1000)
end

-- Open (button 1) spends the set of the chosen boss; Focus (button 2) makes the fragments drop for it
function PN.modalAnswer(player, windowId, buttonId, choiceId)
	local m = C().modal
	if windowId ~= m.list then
		return false
	end
	if limited(player) then
		return true
	end
	local boss = PN.index().list[tonumber(choiceId) or 0]
	if not boss then
		return true
	end
	if buttonId == 1 then
		local ok, text = PN.enter(player, boss.key)
		if not ok and text then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, text)
		end
	elseif buttonId == 2 then
		if player:getLevel() < boss.minLevel then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "%s opens from level %d.", boss.name, boss.minLevel))
		else
			PN.setFocus(player, boss.index)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your fragments now drop for %s.", boss.name))
		end
	end
	return true
end

local modal = CreatureEvent("ChaosPinnacleModal")
function modal.onModalWindow(player, modalWindowId, buttonId, choiceId)
	PN.modalAnswer(player, modalWindowId, buttonId, choiceId)
	return true
end
modal:register()

-- ======================================================================== events
local gate = MoveEvent()
function gate.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local run = PN.runOf[player:getId()]
	if run then
		removePlayer(run, player:getId(), "out")
	else
		player:teleportTo(player:getTown():getTemplePosition())
	end
	return true
end
gate:type("stepin")
gate:aid(C().portalActionId)
gate:register()

local bossDeath = CreatureEvent("ChaosPinnacleDeath")
function bossDeath.onDeath(creature, corpse)
	local run = PN.monsterRun[creature:getId()]
	if run and run.bossId == creature:getId() and run.state == "running" and not run.ended then
		local slot, rid = run.slot, run.id
		addEvent(function()
			local r = PN.runs[slot]
			if r and r.id == rid and r.state == "running" and not r.ended then
				success(r)
			end
		end, 0)
	end
	return true
end
bossDeath:register()

-- the damage curve of a monster of a fight on a player of its run; nil for any other hit
local function hitMult(creature, attacker)
	local run = PN.runOf[creature:getId()]
	if not run or run.state ~= "running" or not attacker or not attacker:isMonster() or PN.isPinnacleMonster(attacker) ~= run then
		return nil
	end
	return K.scale(C().damage, run.size)
end

local playerHit = CreatureEvent("ChaosPinnacleHit")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local run = PN.runOf[creature:getId()]
	if not run or run.state ~= "running" or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local mult = hitMult(creature, attacker)
	if mult and not (ChaosManaShield and ChaosManaShield.scaled(creature, attacker, "pinnacle")) then
		primaryDamage = math.floor(primaryDamage * mult)
		if secondaryType ~= COMBAT_HEALING then
			secondaryDamage = math.floor(secondaryDamage * mult)
		end
	end
	if C().catchLethal then
		local sign = primaryDamage < 0 and -1 or 1
		local pool = creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0)
		local healSecondary = secondaryType == COMBAT_HEALING
		local p, s, caught = U.catchDamage(pool, primaryDamage, healSecondary and 0 or secondaryDamage)
		if caught then
			local slot, rid, pid = run.slot, run.id, creature:getId()
			addEvent(function()
				local r = PN.runs[slot]
				if r and r.id == rid then
					fall(r, pid)
				end
			end, 0)
		end
		return sign * p, primaryType, healSecondary and secondaryDamage or sign * s, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
playerHit:register()

if not ChaosManaShield or not ChaosManaShield.provide then
	dofile("data/scripts/chaos/manashield_core.lua")
end
ChaosManaShield.provide("pinnacle", {
	hit = function(player, attacker, amount)
		local mult = hitMult(player, attacker)
		return mult and math.floor(amount * mult) or nil
	end
})

local prepare = CreatureEvent("ChaosPinnaclePrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local run = PN.runOf[creature:getId()]
	if not run or not C().catchLethal then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	local slot, rid, pid = run.slot, run.id, creature:getId()
	addEvent(function()
		local r = PN.runs[slot]
		if r and r.id == rid then
			fall(r, pid)
		end
	end, 0)
	return false
end
prepare:register()

-- ======================================================================== login, logout, shutdown, startup
local logout = CreatureEvent("ChaosPinnacleLogout")
function logout.onLogout(player)
	if next(PN.runs) ~= nil and serverClosing() then
		PN.interruptAll()
	end
	local run = PN.runOf[player:getId()]
	if run then
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:register()

local login = CreatureEvent("ChaosPinnacleLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPinnacleLogout")
	player:registerEvent("ChaosPinnacleModal")
	PN.wrapHooks()
	-- a character that logs in inside the grid (after a crash, or a logout inside) goes to its temple
	if U.slotAt(C(), player:getPosition()) and not PN.runOf[player:getId()] then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	-- a run in progress that was lost (a crash, a restart whose refund did not reach them): the set comes back once
	local pending = PN.pendingRefund and PN.pendingRefund[player:getGuid()]
	if pending then
		PN.pendingRefund[player:getGuid()] = nil
		refundSet(player, pending)
		setMarker(player, 0)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your set of fragments is given back: the fight did not finish."))
	else
		local marked = sget(player, S().marker)
		if marked > 0 and not PN.runOf[player:getId()] then
			refundSet(player, marked)
			setMarker(player, 0)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your set of fragments is given back: the fight did not finish."))
		end
	end
	return true
end
login:type("login")
login:register()

local shutdown = GlobalEvent("ChaosPinnacleShutdown")
function shutdown.onShutdown()
	PN.interruptAll()
	return true
end
shutdown:register()

-- the Keeper next to the temples (npc_place.lua), like Osric the Chandler
function PN.placeNpcs()
	local cfg = C()
	local placed, missed = 0, {}
	for _, id in ipairs(cfg.npc.towns) do
		local town = Town(id)
		local temple = town and town:getTemplePosition()
		if temple and ChaosNpcPlace and try("place npc", ChaosNpcPlace.place, cfg.npc.name, temple, cfg.npc.offsets) then
			placed = placed + 1
		else
			missed[#missed + 1] = tostring(id)
		end
	end
	if #missed > 0 then
		log("no " .. cfg.npc.name .. " in town " .. table.concat(missed, ", ") .. " (no free tile near the temple, or data/npc/" ..
			cfg.npc.name .. ".xml is missing: tools/install_pinnacle.py)")
	end
	return placed
end

local startup = GlobalEvent("ChaosPinnacleStartup")
function startup.onStartup()
	PN._index = nil
	registerTitles() -- titles.lua loads after this file
	PN.wrapHooks()
	if C().enabled then
		addEvent(function()
			PN.wrapHooks() -- the scripts that load after this one (rift, waystones) exist by now
			log(PN.placeNpcs() .. " " .. C().npc.name .. "(s) placed")
		end, C().npc.delayMs or 4500)
	end
	log(string.format("%d pinnacle boss(es)", #PN.index().list))
	return true
end
startup:register()

-- ======================================================================== staff: /pinnacle
-- /pinnacle                         the open fights
-- /pinnacle give, <name>, <boss>, <kind|set>   a fragment (kind 1-4) or a whole set to an online player
-- /pinnacle clear, <name>           that player's fragments, focus and counts back to nothing
-- /pinnacle end                     your fight fails
local function onCommand(player, param)
	local args = {}
	for a in (param or ""):gmatch("[^,]+") do
		args[#args + 1] = (a:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	local cmd = (args[1] or ""):lower()
	if cmd == "give" then
		local target = Player(args[2] or "")
		local boss = PN.index().byKey[args[3] or ""]
		if target and boss then
			local kind = tonumber(args[4])
			if kind then
				PN.grant(target, boss.index, kind)
			else
				for k = 1, 4 do
					PN.grant(target, boss.index, k, true)
				end
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: fragments of %s given.", target:getName(), boss.name))
		end
	elseif cmd == "clear" then
		local target = Player(args[2] or "")
		if target then
			for off = 0, 38 do
				if off ~= 36 and off ~= 37 then
					sset(target, off, 0)
				end
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s: the pinnacle rows are cleared.", target:getName()))
		end
	elseif cmd == "end" then
		local run = PN.runOf[player:getId()]
		if run then
			fail(run, "Ended by the staff.")
		end
	else
		local lines = {}
		for slot, r in pairs(PN.runs) do
			local n = 0
			for _ in pairs(r.players) do
				n = n + 1
			end
			lines[#lines + 1] = string.format("slot %d: %s, %s, %d player(s), %ds left", slot, r.boss.name, r.state, n,
				timeLeft(r, mnow()))
		end
		player:showTextDialog(1387, #lines > 0 and table.concat(lines, "\n") or "No pinnacle fight is open.")
	end
end

local talk = TalkAction("/pinnacle")
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
