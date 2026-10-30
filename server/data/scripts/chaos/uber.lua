-- The Ascended Omens and the Cinderheart (roadmap item 57): the top challenge above the Omen Keys.
-- ("uber" in the file names only; players read "Ascended" and "Cinderheart".)
-- Numbers: uber_config.lua. Pure logic (tests/uber_test.lua): uber_core.lua. Overview: server/README.md "Ascended Omens
-- and the Cinderheart". Monsters: data/monster/monsters/chaos/ascended/. Items: tools/install_ascended.py.
--
-- Flow
--   Omen guardian kills and sealed rifts of tier 13-15 give Ascended Shards (rift.lua calls ChaosAscended.onRiftSealed)
--   -> use one: 4 shards of one omen bind an Ascended Sigil of that omen -> use the sigil in a protection zone, out of
--   combat: the party within partyRange (up to 5) comes along into a runtime-built arena (a slot of the grid of
--   uber_config.lua) -> the Ascended Omen appears after startDelay seconds: phases at health thresholds (yell, adds,
--   arena hazards), telegraphed hits (warning effects on the tiles one and two turns before the hit; a share of max
--   health to whoever still stands there), the enrage at enrageAt (harder hits, faster telegraphs, a pulse on everyone),
--   the time limit at `limit`. Shared lives: a lethal hit is caught, the player lands in the antechamber and the Ember
--   Gate (a portal tile) lets them back after reenterSeconds; the fall that takes the last life ends the run.
--   Kill: every finisher gets the spoils (gold to the bank, orbs, gear, Ascended unique rolls) and the omen's relic;
--   one relic of each omen binds a Cinderheart Sigil -> the Cinderheart (Ysgrath), the same fight in four phases.
--   Cinderheart kills go on the weekly leaderboards (fastest kill per party size, class tabs) and give the title.
--   The sigil is spent at the start; a "run in progress" marker (storages Chaos.storage.ascendedRun ..+1) gives it back
--   at the next login after a crash, and a clean shutdown ends every run first (the sigil back while the boss lives).
--
-- HUD: the rift HUD (client game_rift, opcode ChaosOpcodes.rift 228): title, timer, lives and the boss state in the
-- note lines (phase, health, enrage). No opcode of its own.
-- Exports: ChaosAscended.isInside(player), ChaosAscended.onRiftSealed(info), ChaosAscended.giveSigil / giveShard /
-- giveRelic (staff, tests). Staff: /ascended (see onCommand).

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/uber_core.lua")
ChaosUberConfig = dofile("data/scripts/chaos/uber_config.lua")
dofile("data/lib/chaos_dark_paint.lua")
if not ChaosArenaLook then
	dofile("data/scripts/chaos/arenalook_core.lua")
end

ChaosAscended = ChaosAscended or {}
local A = ChaosAscended
local U = ChaosUberCore
local ST = Chaos.storage.ascendedRun -- +0 the sigil's kind index of a run in progress, +1 its start, +2 the use exhaust
local OPCODE = ChaosOpcodes.rift

local function C()
	return ChaosUberConfig
end

local function rand(a, b)
	return math.random(a, b)
end

local function mnow()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function log(text)
	print("[Chaos ascended] " .. text)
end

A.runs = A.runs or {} -- slot -> run
A.runOf = A.runOf or {} -- player id -> run
A.monsterRun = A.monsterRun or {} -- monster id -> run (boss and adds)
A.built = A.built or {} -- slot -> true
A.bad = A.bad or {} -- slot -> reason
A.noRefund = A.noRefund or {} -- guid -> true: the opener left without a logout event
A.nextId = A.nextId or 0

-- bosses and adds keep their tuned stats: no random tier, no boss modifiers (monster_tiers.lua)
local function tierSkip()
	local tc = ChaosTierConfig
	if not tc then
		return
	end
	for _, d in ipairs(C().kinds) do
		tc.skip[d.boss:lower()] = true
		tc.bosses[d.boss:lower()] = true
		tc.skip[d.add:lower()] = true
	end
end
tierSkip()

-- ======================================================================== helpers
local function itemReady(id)
	local it = id and ItemType(id)
	return it ~= nil and it:getId() ~= 0
end
A.itemReady = itemReady

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

local function giveEx(player, item)
	if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		return true
	end
	return false
end

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

local function say(run, text, kind)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			-- English text, a deferred text, or a function(lang) -> text
			p:sendTextMessage(kind or MESSAGE_EVENT_ADVANCE, type(text) == "function" and text(Chaos.lang(p)) or Chaos.tx(p, text))
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

local COMBAT = {physical = "COMBAT_PHYSICALDAMAGE", death = "COMBAT_DEATHDAMAGE", energy = "COMBAT_ENERGYDAMAGE",
	fire = "COMBAT_FIREDAMAGE"}
local function combatOf(def)
	return _G[COMBAT[def.element] or "COMBAT_PHYSICALDAMAGE"] or COMBAT_PHYSICALDAMAGE
end

local hitFn = doTargetCombat or doTargetCombatHealth

-- ======================================================================== sigils, relics, shards
function A.applySigil(item, kind)
	local cfg = C()
	local d = U.kind(cfg, kind)
	item:setCustomAttribute("ascended_kind", d.key)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, U.sigilName(cfg, d.key))
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, d.final and "a" or "an")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format(
		"It opens the arena of %s. Use it in a protection zone; your party within %d sqm comes along (up to %d). " ..
		"Level %d, %d minutes, shared lives.", d.boss, cfg.partyRange, cfg.maxPlayers, d.minLevel, math.floor(d.limit / 60)))
	return item
end

function A.applyRelic(item, kind)
	local cfg = C()
	local d = U.kind(cfg, kind)
	item:setCustomAttribute("ascended_kind", d.key)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, U.relicName(cfg, d.key))
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "an")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format(
		"Torn from %s. One relic of each Ascended Omen binds a Cinderheart Sigil: use one while you carry all three.", d.boss))
	return item
end

local function kindOf(item)
	local k = item and item:getCustomAttribute("ascended_kind")
	return k and U.kind(C(), k) and k or nil
end

-- gives a sigil of `kind`; true when it went to the inbox
function A.giveSigil(player, kind, why)
	local cfg = C()
	if not itemReady(cfg.items.sigil.id) or not U.kind(cfg, kind) then
		return nil
	end
	local item = Game.createItem(cfg.items.sigil.id, 1)
	if not item then
		return nil
	end
	A.applySigil(item, kind)
	local inbox = giveEx(player, item)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s: %s.%s", Chaos.t(player, why or "You received a sigil"),
		U.sigilName(cfg, kind), inbox and Chaos.t(player, " It is in your inbox.") or ""))
	return inbox
end

function A.giveRelic(player, kind)
	local cfg = C()
	if not itemReady(cfg.items.relic.id) then
		return nil
	end
	local item = Game.createItem(cfg.items.relic.id, 1)
	if not item then
		return nil
	end
	A.applyRelic(item, kind)
	return giveEx(player, item)
end

function A.giveShard(player, kind, why)
	local s = C().items.shards[kind]
	if not s or not itemReady(s.id) then
		return nil
	end
	local inbox = giveStack(player, s.id, 1)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s: an %s.%s", Chaos.t(player, why or "You found"),
		ItemType(s.id):getName(), inbox and Chaos.t(player, " It is in your inbox.") or ""))
	return inbox
end

-- rift.lua: a sealed rift or a slain Omen guardian. info = {tier, omen = kind key or nil, finishers = {[guid] = {name}},
-- players = who entered (the party bonus on the shard chance)}
function A.onRiftSealed(info)
	local cfg = C()
	if not cfg.enabled then
		return
	end
	for guid, f in pairs(info.finishers or {}) do
		local p = f.name and Player(f.name)
		if p and p:getGuid() == guid then
			local kind
			if info.omen then
				kind = U.shardFromOmen(cfg, info.omen, rand, info.players)
			else
				kind = U.shardFromRift(cfg, info.tier, rand, info.players)
			end
			if kind then
				A.giveShard(p, kind, info.omen and "The guardian's death leaves something behind" or "The sealed rift leaves something behind")
			end
		end
	end
end

-- ======================================================================== the crash refund marker
local function setMarker(player, kind)
	player:setStorageValue(ST, U.marker(C(), kind))
	player:setStorageValue(ST + 1, os.time())
	player:save()
end

local function clearMarker(player)
	if player:getStorageValue(ST) > 0 then
		player:setStorageValue(ST, 0)
		player:setStorageValue(ST + 1, 0)
		player:save()
	end
end

-- the sigil back (a crash or a clean shutdown); why = the shutdown's text, nil at a login
local function refundMarker(player, why)
	local kind = U.markerKind(C(), player:getStorageValue(ST))
	if not kind then
		return false
	end
	if not why and (A.noRefund[player:getGuid()] or A.runOf[player:getId()]) then
		A.noRefund[player:getGuid()] = nil
		clearMarker(player)
		return false
	end
	player:setStorageValue(ST, 0)
	player:setStorageValue(ST + 1, 0)
	A.noRefund[player:getGuid()] = nil
	A.giveSigil(player, kind, why or "Your last arena was interrupted by a server restart, so its sigil is returned")
	player:save()
	return true
end

-- ======================================================================== the arena
local function groundId(tile)
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

-- the dark tile set: walls, lights and a painted floor when installed; else the stock ids of the config
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
			cfg.stockWallId, cfg.stockBasinId = cfg.wallId, cfg.basinId
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
	ChaosArenaLook.dressBossArena("uber", L, cfg, bossKey)
	for _, t in ipairs(L.basins) do
		placeItem(P(ChaosArenaLook.fixtureSpot(t, {L.rect}, ChaosArenaLook.wallSizeOf(cfg.wallId))), cfg.basinId)
	end
end

local function buildSlot(slot, bossKey)
	local cfg = C()
	local isDark = dark()
	local L = U.layout(cfg, slot)
	if A.built[slot] then
		dressSlot(L, bossKey)
		return L
	end
	if A.bad[slot] then
		return nil, A.bad[slot]
	end
	if not Game.createTile then
		return nil, "Game.createTile is missing"
	end
	local lists = {L.floorList, L.anteList, L.wallList}
	for _, list in ipairs(lists) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			local gid = tile and groundId(tile)
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
	A.built[slot] = true
	return L
end

-- monsters and loose items (corpses, fields) of the slot
local function cleanSlot(L)
	local cfg = C()
	local keep = {[cfg.groundId] = true, [cfg.wallId] = true, [cfg.basinId] = true, [cfg.portalId] = true}
	for _, list in ipairs({L.floorList, L.anteList}) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						A.monsterRun[c:getId()] = nil
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

-- seconds until the run's time limit (the boss's limit after it appears, plus the wait before it)
local function timeLeft(run, nowMs)
	local def = run.def
	if run.bossAt then
		local _, _, toLimit = U.clock(def, (nowMs - run.bossAt) / 1000)
		return math.max(0, math.floor(toLimit))
	end
	return def.limit + math.max(0, math.ceil(((run.bossDueAt or nowMs) - nowMs) / 1000))
end
A.timeLeft = timeLeft

local function takeSlot(player, bossKey)
	local cfg = C()
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(A.runs) do
		running = running + 1
	end
	while true do
		local slot = not (IL and IL.capped("ascended", running, cfg.limits)) and U.allocSlot(cfg, A.runs, A.bad) or nil
		if not slot then
			local text = "Every Ascended arena is in use. Try again in a moment."
			if IL then
				local lefts = {}
				for _, r in pairs(A.runs) do
					lefts[#lefts + 1] = r.state == "running" and timeLeft(r, mnow()) or cfg.exitDelay
				end
				text = IL.busy(player, "ascended", "Ascended arenas", lefts, cfg.limits)
			end
			player:sendCancelMessage(Chaos.tx(player, text))
			return nil
		end
		local L, why = buildSlot(slot, bossKey)
		if L then
			return slot, L
		end
		A.bad[slot] = why
		log(string.format("slot %d not usable: %s", slot, tostring(why)))
	end
end

-- ======================================================================== HUD
local function bossOf(run)
	return run.bossId and Monster(run.bossId) or nil
end

local function hudData(run, lang)
	local now = mnow()
	local boss = bossOf(run)
	local def = run.def
	local left, toEnrage = def.limit, def.enrageAt
	if run.bossAt then
		local _, te, tl = U.clock(def, (now - run.bossAt) / 1000)
		left, toEnrage = tl, te
	else
		left = def.limit + math.max(0, math.ceil(((run.bossDueAt or now) - now) / 1000))
	end
	local adds = 0
	for mid in pairs(run.adds) do
		if Monster(mid) then
			adds = adds + 1
		end
	end
	local waiting = 0
	for _, e in pairs(run.players) do
		if e.down then
			waiting = waiting + 1
		end
	end
	local phase = def.phases[run.phase or 1] or def.phases[1]
	return U.hud({def = def, phase = run.phase or 1, phases = #def.phases, phaseName = phase.name, left = math.floor(left),
		limit = def.limit, enraged = run.enraged, toEnrage = toEnrage, lives = run.lives, livesMax = run.livesMax,
		boss = run.boss, state = run.state, adds = adds, waiting = waiting,
		hp = boss and math.max(0, math.floor(boss:getHealth() * 100 / math.max(1, boss:getMaxHealth()))) or 100}, lang)
end

local function sendHud(run, action, player)
	if not OPCODE or not Chaos.send then
		return
	end
	if player then
		Chaos.send(player, OPCODE, action, hudData(run, Chaos.lang(player)))
		return
	end
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			Chaos.send(p, OPCODE, action, hudData(run, Chaos.lang(p)))
		end
	end
end

-- ======================================================================== leaving and the end of a run
local finishExit

local function eventsOn(player)
	player:registerEvent("ChaosAscendedPlayerHit")
	player:registerEvent("ChaosAscendedPlayerMana")
	player:registerEvent("ChaosAscendedPrepareDeath")
end

local function eventsOff(player)
	player:unregisterEvent("ChaosAscendedPlayerHit")
	player:unregisterEvent("ChaosAscendedPlayerMana")
	player:unregisterEvent("ChaosAscendedPrepareDeath")
end

-- mode: "out" (sent back to where the player came from) | "logout" | "temple"
local function removePlayer(run, id, mode)
	local entry = run.players[id]
	if not entry then
		return
	end
	run.players[id] = nil
	A.runOf[id] = nil
	local player = Player(id)
	if player then
		eventsOff(player)
		local dest = (run.restart or mode == "temple") and player:getTown():getTemplePosition() or entry.entry
		if mode ~= "stay" then
			player:teleportTo(dest)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		player:removeCondition(CONDITION_INFIGHT)
		if mode ~= "logout" and OPCODE and Chaos.send then
			local running = run.state == "running"
			Chaos.send(player, OPCODE, "end", {result = running and "left" or run.state,
				text = Chaos.tx(player, running and "You left the arena." or (run.endText or ""))})
		end
		if entry.guid == run.openerGuid then
			clearMarker(player)
		end
	elseif entry.guid == run.openerGuid then
		A.noRefund[entry.guid] = true
		if db and db.query then
			db.query(string.format("DELETE FROM `player_storage` WHERE `player_id` = %d AND `key` >= %d AND `key` <= %d",
				entry.guid, ST, ST + 1))
		end
	end
	if next(run.players) == nil and not run.ended then
		if run.state == "running" then
			run.state = "failed"
			run.endText = "Everyone left the arena."
		end
		finishExit(run)
	end
end
A._removePlayer = removePlayer

local function removeMonsters(run)
	for mid, r in pairs(A.monsterRun) do
		if r == run then
			A.monsterRun[mid] = nil
			local m = Monster(mid)
			if m then
				m:getPosition():sendMagicEffect(CONST_ME_POFF)
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
	if A.runs[run.slot] == run then
		A.runs[run.slot] = nil
		if ChaosInstanceLimits and not run.restart then
			ChaosInstanceLimits.freed("ascended", "the Ascended arenas")
		end
	end
	log(string.format("run %d (slot %d, %s) ended: %s", run.id, run.slot, run.def.key, run.state))
end

local function fail(run, text)
	if run.ended or run.state ~= "running" then
		return
	end
	run.state = "failed"
	run.endText = ChaosI18n.msg("%s The arena collapses and the sigil is spent.", ChaosI18n.isMsg(text) and text or ChaosI18n.msg(text))
	say(run, run.endText)
	sendHud(run, "update")
	finishExit(run)
end
A._fail = fail

-- a clean shutdown: everyone to the temple; the opener gets the sigil back while the boss lives
function A.interrupt(run)
	if run.ended then
		return false
	end
	run.restart = true
	if run.state == "running" then
		for id, e in pairs(run.players) do
			local p = Player(id)
			if p and e.guid == run.openerGuid then
				refundMarker(p, "The server is restarting: your arena closes and its sigil is returned")
			end
		end
		run.state = "interrupted"
		run.endText = "The server is restarting: the arena closes."
		say(run, run.endText)
	end
	finishExit(run)
	return true
end

function A.interruptAll()
	local n = 0
	for _, run in pairs(A.runs) do
		if A.interrupt(run) then
			n = n + 1
		end
	end
	return n
end

local function serverClosing()
	local state = Game.getGameState and Game.getGameState()
	return state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED)
end

-- ======================================================================== rewards
-- the Ascended uniques of a boss (ChaosUniqueItems entries with ascended = true that list it)
local function ascendedUniques()
	local out = {}
	for _, e in pairs(ChaosUniqueItems or {}) do
		if type(e) == "table" and e.ascended then
			out[#out + 1] = e
		end
	end
	return out
end
A.ascendedUniques = ascendedUniques

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

local function bossLevel(def)
	local M = ChaosItemMods
	if not M or not M.sourceLevel then
		return nil
	end
	return M.sourceLevel({monsterLevel = def.final and 1100 or 1000, tier = "boss", riftTier = 15, omen = true})
end

function A.deliver(player, run)
	local cfg = C()
	local def = run.def
	local r = U.reward(cfg, def, run.size, rand) -- x the party bonus (uber_config.lua party)
	local inbox = false
	if r.gold > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	inbox = giveStack(player, cfg.orbs.chaos, r.chaos) or inbox
	inbox = giveStack(player, cfg.orbs.divine, r.divine) or inbox
	if r.exalted > 0 and itemReady(cfg.orbs.exalted) then
		inbox = giveStack(player, cfg.orbs.exalted, r.exalted) or inbox
	end
	local found = {}
	local L = ChaosLoot
	if L then
		local itemFind = L.itemFindMult(player)
		local mt = MonsterType(def.boss)
		local rows = {}
		for _, e in ipairs(mt and mt:getLoot() or {}) do
			if e.itemId and (e.chance or 0) > 0 and L.isGearId(e.itemId) then
				rows[#rows + 1] = {e, e.chance}
			end
		end
		for _ = 1, r.gearRolls do
			local total, roll, pick = 0, 0, nil
			for _, row in ipairs(rows) do
				total = total + row[2]
			end
			if total > 0 then
				roll = rand(1, total)
				for _, row in ipairs(rows) do
					roll = roll - row[2]
					if roll <= 0 then
						pick = row[1]
						break
					end
				end
			end
			if pick then
				local rarity = L.upgradeRarity("boss", L.stockRarity(), itemFind * 1.5)
				local item = ChaosCrafting and ChaosCrafting.createItem and ChaosCrafting.createItem(pick.itemId, rarity,
					bossLevel(def)) or Game.createItem(pick.itemId, 1)
				if item and ChaosVeiled and ChaosVeiled.rollReward then
					ChaosVeiled.rollReward(item, {ascended = true}) -- veiled.lua
				end
				if item then
					inbox = giveEx(player, item) or inbox
					found[#found + 1] = (rarity > 0 and ("[" .. (ChaosRarity.name(rarity) or rarity) .. "] ") or "") .. itemName(pick.itemId)
				end
			end
		end
		for _ = 1, r.uniqueRolls do
			for _, e in ipairs(L.rollUniques("boss", def.boss, 0, itemFind * r.uniqueFind, ascendedUniques(), player)) do
				local item = Game.createItem(e.id, 1)
				if item then
					if ChaosMakeUnique then
						ChaosMakeUnique(item)
					end
					inbox = giveEx(player, item) or inbox
					found[#found + 1] = "{" .. e.name .. "}"
				end
			end
		end
	end
	if r.relic then
		local relicInbox = A.giveRelic(player, r.relic)
		if relicInbox ~= nil then
			inbox = relicInbox or inbox
			found[#found + 1] = U.relicName(cfg, r.relic)
		end
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
		"Spoils of %s: %d gold to your bank, %d Orbs of Upheaval, %d Orbs of Fate%s%s%s.%s", def.boss, r.gold, r.chaos,
		r.divine, r.exalted > 0 and string.format(", %d Exalted Orb%s", r.exalted, r.exalted == 1 and "" or "s") or "",
		#found > 0 and ", " or "", table.concat(found, ", "),
		inbox and Chaos.t(player, " Your backpack was full: the rest is in your inbox.") or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	return r, found
end

local function success(run)
	local cfg = C()
	local def = run.def
	run.state = "success"
	run.boss = "dead"
	local secs = math.floor((mnow() - (run.bossAt or mnow())) / 1000)
	run.secs = secs
	removeMonsters(run)
	run.hazard = nil
	local count = 0
	for _ in pairs(run.players) do
		count = count + 1
	end
	local size = math.max(run.size, count)
	run.endText = ChaosI18n.msg("%s falls in %s. You leave the arena in %d seconds.", def.boss, U.clockText(secs), cfg.exitDelay)
	say(run, run.endText)
	for id, e in pairs(run.players) do
		local p = Player(id)
		if p then
			pcall(A.deliver, p, run)
			-- exclusives.lua: the rare personal drop of a visual exclusive ("cinder" or "ascended_<kind>")
			if ChaosExclusives and ChaosExclusives.bossKill then
				pcall(ChaosExclusives.bossKill, p, def.final and "cinder" or ("ascended_" .. def.key))
			end
			if ChaosAchievements and ChaosAchievements.progress then
				for _, s in ipairs(U.killStats(def, {players = size, deaths = run.deaths or 0})) do
					pcall(ChaosAchievements.progress, p, s[1], s[2])
				end
			end
			if def.final and ChaosLeaderboard and ChaosLeaderboard.record then
				pcall(ChaosLeaderboard.record, U.boardFor(cfg, size), p, math.max(1, secs))
			end
			if e.guid == run.openerGuid then
				clearMarker(p)
			end
		end
	end
	if def.final then
		local names = {}
		for _, e in pairs(run.players) do
			names[#names + 1] = e.name
		end
		table.sort(names)
		Chaos.broadcast(MESSAGE_EVENT_ADVANCE, #names == 1 and "%s has extinguished the Cinderheart in %s!" or
			"%s have extinguished the Cinderheart in %s!", table.concat(names, ", "), U.clockText(secs))
	end
	sendHud(run, "update")
	for id in pairs(run.players) do
		local p = Player(id)
		if p and OPCODE and Chaos.send then
			Chaos.send(p, OPCODE, "end", {result = "success", text = Chaos.tx(p, run.endText), exitIn = cfg.exitDelay})
		end
	end
	log(string.format("run %d: %s slain in %d s by %d player(s), %d deaths", run.id, def.boss, secs, size, run.deaths or 0))
	addEvent(function(slot, rid)
		local r = A.runs[slot]
		if r and r.id == rid and not r.ended then
			finishExit(r)
		end
	end, cfg.exitDelay * 1000, run.slot, run.id)
end

-- ======================================================================== the fight
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

-- a share of max health as one scripted hit of the boss (not scaled again by the enrage); a Hollow Vessel counts health +
-- maximum energy shield (Chaos.percentBase)
local function shareHit(run, player, share, effect)
	local boss = bossOf(run)
	local dmg = U.shareDamage(Chaos.percentBase(player), share)
	run.scripted = true
	if hitFn then
		pcall(hitFn, boss and boss:getId() or 0, player, combatOf(run.def), -dmg, -dmg, effect or CONST_ME_NONE, ORIGIN_SPELL)
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
	local n = U.addCount(adds, run.size)
	if n <= 0 then
		return
	end
	local boss = bossOf(run)
	local at = boss and boss:getPosition() or P(run.L.center)
	local hp
	local made = 0
	for _ = 1, n do
		local m = Game.createMonster(run.def.add, freeArenaTile(run, at, 4), false, true)
		if m then
			hp = hp or math.floor(m:getMaxHealth() * U.addHealthMult(C(), run.size))
			setHealth(m, hp)
			A.monsterRun[m:getId()] = run
			run.adds[m:getId()] = true
			m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
			made = made + 1
		end
	end
	if made > 0 then
		say(run, ChaosI18n.msg(made == 1 and "%s calls %d %s!" or "%s calls %d %ss!", run.def.boss, made, run.def.add),
			MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR)
	end
end

-- the telegraph of `name`: the warning marks now and one turn later, the hit at warnMs
local function telegraph(run, name)
	local cfg = C()
	local boss = bossOf(run)
	if not boss then
		return
	end
	local players = arenaPlayers(run)
	local ppos = {}
	for _, p in ipairs(players) do
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
		size = ChaosBossMech and ChaosBossMech.sizeOf and ChaosBossMech.sizeOf(run.def.boss) or 1})
	if #tiles == 0 then
		return
	end
	local timing = U.telegraphTiming(cfg, run.enraged)
	-- fairness (boss_mechanics_core.lua): every player keeps a safe tile in walking reach of the warning
	local G = ChaosBossMechCore
	if G and #ppos > 0 then
		run.mechGrid = run.mechGrid or G.grid(run.L.floorList)
		local fair = ChaosBossMech and ChaosBossMech.fairOf and ChaosBossMech.fairOf(run.def.boss) or {refLevel = 300}
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
		local r = A.runs[slot]
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
				fx(P(t), r.def.hitEffect, CONST_ME_EXPLOSIONAREA)
			end
		end
		bigFx("bossHit", tiles, r.def.element)
		local now = os.time()
		for _, p in ipairs(arenaPlayers(r)) do
			local pp = p:getPosition()
			local e = r.players[p:getId()]
			if set[U.key(pp.x, pp.y)] and not (e and (e.shieldUntil or 0) > now) then
				shareHit(r, p, timing.share, CONST_ME_NONE)
			end
		end
	end, timing.hitMs)
end

-- hazards of a phase: placed at the phase start; pools vanish after lastMs, columns move every moveMs, the edge grows
-- one ring every stepMs up to maxDepth
local function placeHazard(run, h, depth)
	local tiles = U.hazardTiles(h, {L = run.L, rand = rand, playerCount = run.size, depth = depth})
	run.hazard = {h = h, tiles = tiles, set = U.tileSet(tiles), depth = depth, placedAt = mnow()}
end

local function startPhase(run, idx)
	local def = run.def
	local ph = def.phases[idx]
	if not ph then
		return
	end
	local boss = bossOf(run)
	if idx > 1 and boss then
		Chaos.yell(boss, ph.yell or "")
		fx(boss:getPosition(), "dome_blast_fire", CONST_ME_FIREAREA)
		say(run, ChaosI18n.msg("%s enters phase %d of %d: %s.", def.boss, idx, #def.phases, ph.name),
			MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR)
	elseif boss and ph.yell then
		Chaos.yell(boss, ph.yell)
	end
	run.hazard = nil
	if ph.hazard then
		placeHazard(run, ph.hazard, ph.hazard.kind == "edge" and 1 or nil)
	end
	if ph.adds then
		spawnAdds(run, ph.adds)
		run.nextAdds = ph.adds.every > 0 and (mnow() + ph.adds.every) or nil
	else
		run.nextAdds = nil
	end
	run.nextHeal = mnow() + 5000
	-- the first telegraph of a phase comes a little later, so the phase change can be read first
	run.nextPattern = mnow() + 3000
	sendHud(run, "update")
end

local function hazardStep(run, now)
	local hz = run.hazard
	if not hz then
		return
	end
	local cfg = C()
	local h = hz.h
	-- pools dry up after lastMs and open elsewhere; columns move every moveMs
	local every = h.moveMs or h.lastMs
	if every and now - hz.placedAt >= every then
		placeHazard(run, h, nil)
		hz = run.hazard
	end
	if h.kind == "edge" and h.stepMs and now - hz.placedAt >= h.stepMs and (hz.depth or 1) < (h.maxDepth or 1) then
		placeHazard(run, h, (hz.depth or 1) + 1)
		say(run, "The dark creeps closer.", MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR)
		hz = run.hazard
	end
	if now < (run.nextHazardPulse or 0) then
		return
	end
	run.nextHazardPulse = now + cfg.hazard.pulseMs
	for i, t in ipairs(hz.tiles) do
		if h.kind ~= "edge" or i % 2 == 0 then
			fx(P(t), h.effect, CONST_ME_HITBYFIRE)
		end
	end
	local nowS = os.time()
	for _, p in ipairs(arenaPlayers(run)) do
		local pp = p:getPosition()
		local e = run.players[p:getId()]
		if hz.set[U.key(pp.x, pp.y)] and not (e and (e.shieldUntil or 0) > nowS) then
			shareHit(run, p, cfg.hazard.share, CONST_ME_NONE)
		end
	end
end

local function spawnBoss(run)
	local def = run.def
	local L = run.L
	-- O177: the boss shows the level the fight is for (def.minLevel), not the species' experience / health estimate
	local m = Chaos.createMonsterNamed(def.boss, P(L.bossSpawn), false, true, nil, def.minLevel)
	if not m then
		log("cannot create " .. def.boss .. " (is data/monster/monsters/chaos/ascended registered?); the sigil is returned")
		for id, e in pairs(run.players) do
			local p = Player(id)
			if p and e.guid == run.openerGuid then
				clearMarker(p)
				A.giveSigil(p, def.key, "The arena did not answer, so your sigil is returned")
			end
		end
		run.state = "failed"
		run.endText = "The arena did not answer."
		finishExit(run)
		return
	end
	setHealth(m, math.floor(m:getMaxHealth() * U.healthMult(def, run.size)))
	m:registerEvent("ChaosAscendedBossDeath")
	A.monsterRun[m:getId()] = run
	run.bossId = m:getId()
	-- boss mechanics (boss_mechanics.lua): wardstones, channels, blasts behind pillars, debuffs on top of the phases;
	-- their hits go through shareHit (the lethal-hit catch)
	if ChaosBossMech and ChaosBossMech.attach then
		local rid, slot = run.id, run.slot
		pcall(ChaosBossMech.attach, m, def.boss, {tiles = L.floorList, solo = run.size == 1,
			players = function()
				local r = A.runs[slot]
				return (r and r.id == rid) and arenaPlayers(r) or {}
			end,
			hit = function(p, share)
				local r = A.runs[slot]
				if r and r.id == rid then
					shareHit(r, p, share, CONST_ME_NONE)
				end
			end})
	end
	run.boss = "alive"
	run.bossAt = mnow()
	run.phase = 0
	fx(m:getPosition(), "shadow_eruption", CONST_ME_MORTAREA)
	U.advancePhase(run, def, 1)
	startPhase(run, 1)
	say(run, ChaosI18n.msg("%s answers the sigil! Enrage in %s, the arena closes in %s.", def.boss,
		U.clockText(def.enrageAt), U.clockText(def.limit)))
	sendHud(run, "update")
end

local function tick(slot, rid)
	local run = A.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local cfg = C()
	local now = mnow()
	-- players who are gone or left the slot by other means
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
	if run.ended or A.runs[slot] ~= run then
		return
	end
	-- strangers in this slot (a town portal or a stored hideout spot let them in): out (chaos_constants.lua)
	if Chaos.sweepDue and Chaos.sweepDue(run, now) then
		Chaos.sweepIntruders(function(pos) return U.slotAt(cfg, pos) == slot end,
			function(p) return run.players[p:getId()] ~= nil end, "You are not part of this Ascended Omen: you were sent to your temple.")
	end
	if run.state == "running" and run.boss == "waiting" and now >= (run.bossDueAt or 0) then
		spawnBoss(run)
	end
	if run.ended then
		return
	end
	if run.state == "running" and run.boss == "alive" then
		local def = run.def
		local enraged, _, toLimit = U.clock(def, (now - run.bossAt) / 1000)
		if toLimit <= 0 then
			fail(run, ChaosI18n.msg("Time is up: %s still stands.", def.boss))
			return
		end
		if enraged and not run.enraged then
			run.enraged = true
			run.nextPulse = now + cfg.enrage.pulseMs
			local boss = bossOf(run)
			if boss then
				Chaos.yell(boss, "ENOUGH! BURN!")
				fx(boss:getPosition(), "aura_burst_red", CONST_ME_FIREAREA)
			end
			say(run, ChaosI18n.msg("%s is ENRAGED: every hit is far stronger and the telegraphs come twice as fast.", def.boss))
		end
		local boss = bossOf(run)
		if boss then
			local frac = boss:getHealth() / math.max(1, boss:getMaxHealth())
			for _, idx in ipairs(U.advancePhase(run, def, frac)) do
				startPhase(run, idx)
			end
			local ph = def.phases[run.phase] or def.phases[1]
			if now >= (run.nextPattern or 0) then
				run.nextPattern = now + U.patternEvery(cfg, ph, run.enraged)
				telegraph(run, ph.patterns[rand(1, #ph.patterns)])
			end
			if run.nextAdds and now >= run.nextAdds and ph.adds then
				run.nextAdds = now + ph.adds.every
				spawnAdds(run, ph.adds)
			end
			if ph.heal and now >= (run.nextHeal or 0) then
				run.nextHeal = now + 5000
				local live = 0
				for mid in pairs(run.adds) do
					if Monster(mid) then
						live = live + 1
					else
						run.adds[mid] = nil
					end
				end
				local amount = U.harvestHeal(ph.heal, live, boss:getMaxHealth())
				if amount > 0 then
					Chaos.heal(boss, amount)
					fx(boss:getPosition(), "blood_pact", CONST_ME_MAGIC_RED)
				end
			end
			if run.enraged and now >= (run.nextPulse or 0) then
				run.nextPulse = now + cfg.enrage.pulseMs
				for _, p in ipairs(arenaPlayers(run)) do
					shareHit(run, p, cfg.enrage.pulseShare, CONST_ME_NONE)
					fx(p:getPosition(), "fire_explosion", CONST_ME_FIREAREA)
				end
			end
			hazardStep(run, now)
			-- a boss without a target (everyone at the gate) walks back to the middle
			if not boss:getTarget() and #arenaPlayers(run) == 0 then
				boss:teleportTo(P(run.L.bossSpawn))
			end
		end
	end
	if run.ended then
		return
	end
	if run.state == "running" and ChaosInstanceLimits then -- warnings before the end (instance_limits.lua)
		ChaosInstanceLimits.warn(run, timeLeft(run, now), ChaosInstanceLimits.playersOf(run.players), run.def.boss, cfg.limits)
	end
	if now >= (run.nextHud or 0) then
		run.nextHud = now + cfg.hudEvery * 1000
		sendHud(run, "update")
	end
	addEvent(tick, cfg.tickMs, slot, rid)
end

-- ======================================================================== opening
local function insideOther(player)
	return (ChaosRift and ChaosRift.isInside and ChaosRift.isInside(player))
		or (ChaosDungeonIsInside and ChaosDungeonIsInside(player))
		or (ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player))
		or (ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(player:getPosition()))
end

local function memberProblem(m, def)
	if A.runOf[m:getId()] then
		return ChaosI18n.msg("is already inside an Ascended arena")
	end
	if m:getLevel() < def.minLevel then
		return ChaosI18n.msg("needs level %d", def.minLevel)
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(m) then
		return ChaosI18n.msg("has another character from the same connection online")
	end
	if inCombat(m) then
		return ChaosI18n.msg("is in a fight")
	end
	if insideOther(m) then
		return ChaosI18n.msg("is inside a rift, a dungeon, the tower or the world boss arena")
	end
	return nil
end

local function groupOf(player)
	local cfg = C()
	local members = {player}
	local party = player:getParty()
	if not party then
		return members
	end
	local list = {party:getLeader()}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	local pos = player:getPosition()
	for _, m in ipairs(list) do
		if m and m:getId() ~= player:getId() and #members < cfg.maxPlayers then
			local mp = m:getPosition()
			if mp.z == pos.z and mp:getDistance(pos) <= cfg.partyRange then
				members[#members + 1] = m
			end
		end
	end
	return members
end

local function openerOk(player, def)
	local cfg = C()
	if not cfg.enabled then
		player:sendCancelMessage(Chaos.t(player, "The Ascended arenas are closed."))
		return false
	end
	if A.runOf[player:getId()] then
		player:sendCancelMessage(Chaos.t(player, "You are already inside an Ascended arena."))
		return false
	end
	if cfg.needProtectionZone and not inProtectionZone(player) then
		player:sendCancelMessage(Chaos.t(player, "You must stand in a protection zone to use a sigil."))
		return false
	end
	if inCombat(player) then
		player:sendCancelMessage(Chaos.t(player, "You cannot use a sigil while you are in a fight."))
		return false
	end
	if Chaos.isMultiClient and Chaos.isMultiClient(player) then
		player:sendCancelMessage(Chaos.t(player, Chaos.multiClient and Chaos.multiClient.msgDungeon or "Not with a second character online."))
		return false
	end
	if insideOther(player) then
		player:sendCancelMessage(Chaos.t(player, "You cannot use a sigil from here."))
		return false
	end
	if player:getLevel() < def.minLevel then
		player:sendCancelMessage(Chaos.t(player, "You need level %d to face %s.", def.minLevel, def.boss))
		return false
	end
	local last = player:getStorageValue(ST + 2)
	if last > 0 and os.time() - last < cfg.useCooldown then
		player:sendCancelMessage(Chaos.t(player, "Wait a moment."))
		return false
	end
	player:setStorageValue(ST + 2, os.time())
	return true
end

local function gather(player, def)
	local group = {player}
	for i, m in ipairs(groupOf(player)) do
		if i > 1 then
			local why = memberProblem(m, def)
			if why then
				player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s stays behind: %s.", m:getName(), why))
				m:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(m, "You stay behind from %s's arena: you %s.",
					player:getName(), ChaosI18n.you(why)))
			else
				group[#group + 1] = m
			end
		end
	end
	return group
end

function A.open(player, item)
	local cfg = C()
	local kind = kindOf(item)
	local def = kind and U.kind(cfg, kind)
	if not def then
		player:sendCancelMessage(Chaos.t(player, "This sigil is silent."))
		return false
	end
	if not openerOk(player, def) then
		return false
	end
	local group = gather(player, def)
	local slot, L = takeSlot(player, def.key)
	if not slot then
		return false
	end
	if not item:remove(1) then
		player:sendCancelMessage(Chaos.t(player, "The sigil cannot be used now."))
		return false
	end
	cleanSlot(L)
	A.nextId = A.nextId + 1
	local run = {id = A.nextId, slot = slot, L = L, def = def, players = {}, adds = {}, state = "running", boss = "waiting",
		size = #group, openerGuid = player:getGuid(), startedAt = mnow(), bossDueAt = mnow() + cfg.startDelay * 1000,
		deaths = 0}
	run.lives = U.livesFor(def, #group)
	run.livesMax = run.lives
	A.runs[slot] = run
	setMarker(player, def.key)
	for i, m in ipairs(group) do
		local from = m:getPosition()
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), name = m:getName(), entry = from,
			voc = m:getVocation():getId()}
		A.runOf[m:getId()] = run
		eventsOn(m)
		from:sendMagicEffect(CONST_ME_TELEPORT)
		m:teleportTo(P(L.starts[i] or L.entry))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
	say(run, ChaosI18n.msg(run.lives == 1 and "%s: %s comes in %d seconds. %s, %d shared life. Lethal hits send you to the Ember Gate." or
		"%s: %s comes in %d seconds. %s, %d shared lives. Lethal hits send you to the Ember Gate.",
		def.final and "The Cinderheart" or ChaosI18n.msg("Ascended Omen of the %s", def.name), def.boss, cfg.startDelay,
		U.clockText(def.limit), run.lives))
	if U.partyNote(cfg, def, run.size) then
		say(run, function(lang) return U.partyNote(cfg, def, run.size, lang) end)
	end
	sendHud(run, "start")
	log(string.format("%s opened run %d (%s): slot %d, %d player(s)", player:getName(), run.id, def.key, slot, #group))
	addEvent(tick, cfg.tickMs, slot, run.id)
	return true
end

function A.isInside(player)
	return A.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("ascended", {label = "an Ascended Omen", inside = A.isInside, at = function(pos)
	return U.slotAt(C(), pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out = {}
	for slot, run in pairs(A.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.id, what = string.format("%s, slot %d, %s", run.def.boss, slot, run.state),
			left = run.state == "running" and timeLeft(run, mnow()) or nil, players = n}
	end
	return out
end, close = function(id) -- the failure rule of a time-out: everyone out, the sigil is spent
	for _, run in pairs(A.runs) do
		if run.id == id and not run.ended then
			if run.state == "running" then
				fail(run, "A gamemaster closed the arena.")
			else
				finishExit(run)
			end
			return true, "Ascended run " .. id .. " closed."
		end
	end
	return false, "No running Ascended arena " .. tostring(id) .. "."
end})

-- a caught lethal hit: to the antechamber, one life less (the last one ends the run)
local function fall(run, pid)
	local cfg = C()
	local entry = run.players[pid]
	local p = Player(pid)
	if not entry or entry.down or not p or run.state ~= "running" then
		return
	end
	local left = U.loseLife(run)
	if left <= 0 then
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
	say(run, ChaosI18n.msg(left == 1 and "%s falls: %d shared life left. The Ember Gate lets them back in %d seconds." or
		"%s falls: %d shared lives left. The Ember Gate lets them back in %d seconds.", p:getName(), left, cfg.lives.reenterSeconds))
	sendHud(run, "update")
end
A._fall = fall

-- the Ember Gate: back into the arena once the wait is over
function A.gate(player)
	local cfg = C()
	local run = A.runOf[player:getId()]
	local entry = run and run.players[player:getId()]
	if not entry or run.state ~= "running" then
		return false
	end
	local now = os.time()
	if not entry.down then
		player:teleportTo(P(run.L.entry))
		return true
	end
	if now < (entry.reenterAt or 0) then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "The Ember Gate opens for you in %d seconds.",
			entry.reenterAt - now))
		player:teleportTo(P(run.L.anteStart))
		return false
	end
	entry.down = false
	entry.shieldUntil = now + cfg.lives.shieldSeconds
	player:teleportTo(P(run.L.entry))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	say(run, ChaosI18n.msg("%s steps back through the Ember Gate.", player:getName()), MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR)
	sendHud(run, "update")
	return true
end

-- ======================================================================== items: shards, sigils, relics
function A.useShards(player, item)
	local cfg = C()
	local kind = U.shardKind(cfg, item:getId())
	if not kind then
		return false
	end
	local have = player:getItemCount(item:getId())
	local n, cost = U.bindShards(cfg, have)
	if n < 1 then
		player:sendCancelMessage(Chaos.t(player, "You need %d of these shards to bind an Ascended Sigil (you carry %d).",
			cfg.shardCost, have))
		return false
	end
	if not itemReady(cfg.items.sigil.id) then
		player:sendCancelMessage(Chaos.t(player, "Ascended Sigils are not installed on this server."))
		return false
	end
	if not player:removeItem(item:getId(), cost) then
		return false
	end
	A.giveSigil(player, kind, ChaosI18n.msg("%d shards bind together", cost))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
	return true
end

-- every relic the player carries (backpack, containers inside, the hands): {{item, kind}, ...}
local function relicsOf(player)
	local id = C().items.relic.id
	local out = {}
	local function scan(container)
		for _, it in ipairs(container:getItems(true) or {}) do
			if it:getId() == id then
				local k = kindOf(it)
				if k then
					out[#out + 1] = {it, k}
				end
			end
		end
	end
	for _, slot in ipairs({1, 2, 3, 4, 5, 6, 7, 8, 9, 13}) do -- worn: head .. ring and the badge slot (engine patch 0058)
		local it = player:getSlotItem(slot)
		if it then
			if it:getId() == id and kindOf(it) then
				out[#out + 1] = {it, kindOf(it)}
			elseif it:isContainer() then
				scan(it)
			end
		end
	end
	return out
end

A.relicsOf = relicsOf -- conquest.lua: the relic conversion

function A.useRelic(player)
	local cfg = C()
	local found = relicsOf(player)
	local kinds = {}
	for _, f in ipairs(found) do
		kinds[#kinds + 1] = f[2]
	end
	local ok, list = U.relicsComplete(cfg, kinds)
	if not ok then
		local names = {}
		for _, k in ipairs(list) do
			names[#names + 1] = U.kind(cfg, k).name
		end
		player:sendCancelMessage(Chaos.t(player, "The Cinderheart needs one relic of each Ascended Omen. Missing: %s.", table.concat(names, ", ")))
		return false
	end
	local final = U.finalKind(cfg)
	for _, k in ipairs(list) do
		for i, f in ipairs(found) do
			if f[2] == k then
				f[1]:remove(1)
				table.remove(found, i)
				break
			end
		end
	end
	A.giveSigil(player, final.key, "Three relics burn into one")
	player:getPosition():sendMagicEffect(CONST_ME_FIREAREA)
	return true
end

if itemReady(C().items.sigil.id) then
	local sigilAction = Action()
	function sigilAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		A.open(player, item)
		return true
	end
	sigilAction:id(C().items.sigil.id)
	sigilAction:register()

	local relicAction = Action()
	function relicAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		A.useRelic(player)
		return true
	end
	relicAction:id(C().items.relic.id)
	relicAction:register()

	local shardAction = Action()
	function shardAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		A.useShards(player, item)
		return true
	end
	for _, s in pairs(C().items.shards) do
		shardAction:id(s.id)
	end
	shardAction:register()
else
	log("the Ascended items (" .. C().items.sigil.id .. "...) are not in items.otb: run tools/install_ascended.py; " ..
		"the Ascended arenas are off")
end

local gate = MoveEvent()
function gate.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if player then
		A.gate(player)
	end
	return true
end
gate:type("stepin")
gate:aid(C().portalActionId)
gate:register()

-- ======================================================================== creature events
local bossDeath = CreatureEvent("ChaosAscendedBossDeath")
function bossDeath.onDeath(creature)
	local run = A.monsterRun[creature:getId()]
	A.monsterRun[creature:getId()] = nil
	if run and run.bossId == creature:getId() and run.state == "running" and not run.ended then
		run.bossId = nil
		addEvent(function(slot, rid)
			local r = A.runs[slot]
			if r and r.id == rid and r.state == "running" and not r.ended then
				success(r)
			end
		end, 0, run.slot, run.id)
	end
	return true
end
bossDeath:register()

-- the player's side: the boss's and the adds' hits x the enrage and the party's damage, a lethal hit caught (the fall)
local function scaled(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local run = A.runOf[creature:getId()]
	if not run or primaryType == COMBAT_HEALING or run.state ~= "running" then
		return primaryDamage, primaryType, secondaryDamage, secondaryType, nil
	end
	local entry = run.players[creature:getId()]
	local fromRun = attacker and A.monsterRun[attacker:getId()] == run
	if entry and (entry.down or (entry.shieldUntil or 0) > os.time()) and (fromRun or run.scripted) then
		return 0, primaryType, 0, secondaryType, run
	end
	local mult = fromRun and not run.scripted and U.damageMult(C(), run.enraged, run.size) or 1 -- enrage x party
	if mult ~= 1 then
		primaryDamage = math.floor(primaryDamage * mult)
		if secondaryType ~= COMBAT_HEALING then
			secondaryDamage = math.floor(secondaryDamage * mult)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType, run
end

local playerHit = CreatureEvent("ChaosAscendedPlayerHit")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
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
			local r = A.runs[slot]
			if r and r.id == rid then
				fall(r, pid)
			end
		end, 0, run.slot, run.id, creature:getId())
	end
	return sign * p, primaryType, healSecondary and secondaryDamage or sign * s, secondaryType
end
playerHit:register()

local playerMana = CreatureEvent("ChaosAscendedPlayerMana")
function playerMana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local p, pt, s, st = scaled(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	return p, pt, s, st
end
playerMana:register()

-- the safety net: whatever got past the health event
local prepare = CreatureEvent("ChaosAscendedPrepareDeath")
function prepare.onPrepareDeath(creature, killer)
	local run = A.runOf[creature:getId()]
	if not run or run.state ~= "running" then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	addEvent(function(slot, rid, pid)
		local r = A.runs[slot]
		if r and r.id == rid then
			fall(r, pid)
		end
	end, 0, run.slot, run.id, creature:getId())
	return false
end
prepare:register()

local logout = CreatureEvent("ChaosAscendedLogout")
function logout.onLogout(player)
	if next(A.runs) ~= nil and serverClosing() then
		A.interruptAll()
	end
	local run = A.runOf[player:getId()]
	if run then
		say(run, ChaosI18n.msg("%s left the arena.", player:getName()))
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:register()

local shutdown = GlobalEvent("ChaosAscendedShutdown")
function shutdown.onShutdown()
	A.interruptAll()
	return true
end
shutdown:register()

local login = CreatureEvent("ChaosAscendedLogin")
function login.onLogin(player)
	player:registerEvent("ChaosAscendedLogout")
	if U.slotAt(C(), player:getPosition()) and not A.runOf[player:getId()] then
		player:teleportTo(player:getTown():getTemplePosition())
	end
	refundMarker(player)
	return true
end
login:register()

local startup = GlobalEvent("ChaosAscendedStartup")
function startup.onStartup()
	tierSkip()
	return true
end
startup:register()

-- ======================================================================== staff: /ascended
-- /ascended                         the runs
-- /ascended sigil, <kind>           a sigil (bloodmoon, hollow, storm, cinder) for yourself
-- /ascended shards, <kind>[, n]     shards; /ascended relic, <kind>
-- /ascended phase, <n>              the boss of your run to the start of phase n (its health)
-- /ascended enrage                  your run's boss enrages now; /ascended end: your run fails
local function onCommand(player, param)
	local cfg = C()
	local args = {}
	for a in (param or ""):gmatch("[^,]+") do
		args[#args + 1] = a:gsub("^%s+", ""):gsub("%s+$", "")
	end
	local cmd = (args[1] or ""):lower()
	local run = A.runOf[player:getId()]
	if cmd == "sigil" or cmd == "relic" or cmd == "shards" then
		local def = U.kind(cfg, (args[2] or ""):lower())
		if not def then
			player:sendCancelMessage(Chaos.t(player, "Kinds: bloodmoon, hollow, storm, cinder."))
			return
		end
		if cmd == "sigil" then
			A.giveSigil(player, def.key, "Staff")
		elseif cmd == "relic" and not def.final then
			A.giveRelic(player, def.key)
		elseif cmd == "shards" and not def.final then
			for _ = 1, math.max(1, math.min(100, tonumber(args[3]) or cfg.shardCost)) do
				giveStack(player, cfg.items.shards[def.key].id, 1)
			end
		end
	elseif cmd == "phase" and run and bossOf(run) then
		local ph = run.def.phases[tonumber(args[2]) or 2]
		local boss = bossOf(run)
		if ph then
			local cut = boss:getHealth() - (math.floor(boss:getMaxHealth() * ph.at) - 1)
			if cut > 0 and hitFn then
				-- untyped damage: no resistances (a negative addHealth is ignored by this engine)
				pcall(hitFn, 0, boss, COMBAT_UNDEFINEDDAMAGE, -cut, -cut, CONST_ME_NONE, ORIGIN_NONE)
			end
		end
	elseif cmd == "enrage" and run and run.bossAt then
		run.bossAt = mnow() - run.def.enrageAt * 1000
	elseif cmd == "end" and run then
		fail(run, "Ended by the staff.")
	else
		local lines = {}
		for slot, r in pairs(A.runs) do
			local n = 0
			for _ in pairs(r.players) do
				n = n + 1
			end
			lines[#lines + 1] = string.format("slot %d: %s, %s, %d player(s), lives %d/%d, phase %d%s", slot, r.def.boss, r.state, n,
				r.lives, r.livesMax, r.phase or 0, r.enraged and ", enraged" or "")
		end
		player:showTextDialog(cfg.items.sigil.id, #lines > 0 and table.concat(lines, "\n") or "No Ascended arena is open.")
	end
end

local talk = TalkAction("/ascended")
function talk.onSay(player, words, param)
	local g = player:getGroup()
	if not g or g:getId() < C().staffGroup then
		return true
	end
	-- staff never give value (docs/GM_HANDBOOK.md section 2): sigils, relics and shards need an administrator
	local cmd = ((param or ""):match("^%s*([^,%s]+)") or ""):lower()
	if not Chaos.staffCommand(player, words, param, cmd == "sigil" or cmd == "relic" or cmd == "shards") then
		return false
	end
	onCommand(player, param)
	return false
end
talk:separator(" ")
talk:register()
