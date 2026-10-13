-- Rifts (roadmap item 8): consumable Rift Keys open a timed instance with random modifiers.
-- Numbers: rift_config.lua. Pure logic (tested by tests/rift_test.lua): rift_core.lua. Overview: server/README.md "Rifts".
--
-- Flow
--   use a Rift Key (item 10155 "shadow orb" + action id 47401, attributes rift_tier / rift_mods) in a protection zone, out of combat,
--   not multi-clienting -> the party within partyRange (up to 5) comes along -> a ready slot of the rift grid is taken:
--   each slot holds a generated layout (rift_layout_core.lua: a cave system, waste, ruined complex or cave with
--   chambers, one or two floors, sized by the tier), built in short steps by the slot pool below and built anew after
--   every run -> packs from the bounty pool's level window of the tier (elites through monster_tiers.lua) spread over the
--   map, the rest coming in ahead of the party
--   -> after bossAt % of the kills the boss appears -> boss dead in time: reward chest (each finisher once), maybe a
--   new key, Omen Fragments from tier 6; time up: everyone out, key lost. Shared lives (3, +1 per extra player): a
--   death inside is the normal death and costs one; the next login puts the character back at the rift's entrance;
--   the last life lost collapses the rift. Logout inside: removed from the run.
--   Omens: 60 Omen Fragments bind an Omen Key (item 32072, attribute omen_kind) that opens a guardian arena in the
--   same slot grid (the guardian's arena of a ready layout, the party at its mouth; the same lives, timer and chest).
--   The key is consumed at the start; a "run in progress" marker (storages Chaos.storage.riftRun ..+4) refunds it at
--   the next login when the server crashed during the run. A clean shutdown or a closed server (the daily restart)
--   ends every run first (RF.interrupt): everyone to the temple, the key back while the guardian lives.
--
-- Exports: ChaosRift.isInside(player), ChaosRift.lootMult(ctx) (loot_config.lua rateMult),
-- ChaosRift.onBountyPaid(player, contract) (bounty.lua), ChaosRift.createKey / giveKey.
-- Client: game_rift, extended opcode ChaosOpcodes.rift (server -> client {"action": "start"|"update"|"end", "data"}).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
dofile("data/scripts/chaos/rift_core.lua")
dofile("data/scripts/chaos/rift_layout_core.lua")
ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/lib/chaos_dark_paint.lua")

ChaosRift = ChaosRift or {}
-- pack effects (data/lib/chaos_pack_fx.lua, switch ChaosPackFx.PACK_FX, on since 2026-10-13; off: exactly the stock effect as before)
if not ChaosPackFx then
	pcall(dofile, "data/lib/chaos_pack_fx.lua")
end
local function packFx(pos, use, stock)
	if ChaosPackFx then
		return ChaosPackFx.send(pos, use, stock)
	end
	if stock then
		pos:sendMagicEffect(stock)
	end
	return false
end
local RF = ChaosRift
local R = ChaosRiftCore
local RL = ChaosRiftLayout
local OPCODE = ChaosOpcodes.rift
local ST = Chaos.storage.riftRun -- +0 tier, +1..+3 packed modifiers, +4 start time

local function C()
	return ChaosRiftConfig
end

local function rand(a, b)
	return math.random(a, b)
end

RF.runs = RF.runs or {} -- slot -> run
RF.runOf = RF.runOf or {} -- player id -> run
RF.monsterRun = RF.monsterRun or {} -- monster id -> run
RF.bad = RF.bad or {} -- slot -> reason (footprint not empty; RF.slots below has every slot's state)
RF.pending = RF.pending or {} -- guid -> list of {run data} rewards for finishers who were offline at the exit
RF.nextId = RF.nextId or 0
RF.echo = RF.echo or {} -- monster id -> true: Echoing Spoils copies its loot (set at death, used by onDropLoot)
RF.noRefund = RF.noRefund or {} -- guid -> true: the key of an interrupted run was spent (left without a logout event)
RF.revive = RF.revive or {} -- guid -> run: died inside with lives left; the next login puts the character back

-- ======================================================================== pool
local rawPool = dofile("data/scripts/chaos/bounty_pool.lua")
RF.poolLevel = {}
RF.poolHealth = {} -- the XML health (density: a kind's health relative to the run's other kinds)
for _, e in ipairs(rawPool.hunt or {}) do
	RF.poolLevel[e.name:lower()] = e.level
	RF.poolHealth[e.name:lower()] = e.health
end
RF.husk = RF.husk or {} -- monster id -> true: a density husk (no loot, no kill credit; bounty.lua, bestiary.lua ask)

-- a husk of a dense rift: experience only (bounty.lua and bestiary.lua give it no kill credit)
function RF.isHusk(creature)
	return creature ~= nil and RF.husk[creature:getId()] == true
end

local knownCache = {}
local function known(name)
	local k = name:lower()
	if knownCache[k] == nil then
		local ok = false
		local mt = MonsterType(name)
		if mt and not (ChaosTierConfig and ChaosTierConfig.skip and ChaosTierConfig.skip[k]) then
			local okBoss, isBoss = pcall(function() return mt:isBoss() end)
			ok = not (okBoss and isBoss)
		end
		knownCache[k] = ok
	end
	return knownCache[k]
end

-- ======================================================================== helpers
local function P(t)
	return Position(t.x, t.y, t.z)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
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

local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
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

local function say(run, text)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
	end
end

-- ======================================================================== keys
function RF.readKey(item)
	if not item or item:getActionId() ~= C().key.actionId then
		return nil
	end
	local tier = tonumber(item:getCustomAttribute("rift_tier"))
	if not tier then
		return nil
	end
	return {tier = R.clampTier(C(), tier), mods = R.decodeMods(C(), item:getCustomAttribute("rift_mods") or "")}
end

function RF.applyKey(item, key)
	local cfg = C()
	item:setActionId(cfg.key.actionId)
	item:setCustomAttribute("rift_tier", key.tier)
	item:setCustomAttribute("rift_mods", R.encodeMods(key.mods))
	item:setAttribute(ITEM_ATTRIBUTE_NAME, R.keyName(cfg, key.tier))
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "a")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, R.describe(cfg, key))
	return item
end

function RF.createKey(key)
	local item = Game.createItem(C().key.itemId, 1)
	if item then
		RF.applyKey(item, key)
	end
	return item
end

-- returns true when the key went to the inbox (backpack full)
function RF.giveKey(player, key, why)
	local item = RF.createKey(key)
	if not item then
		return false
	end
	local inbox = giveEx(player, item)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: %s (%s).%s", why or "You received a key",
		R.keyName(C(), key.tier), #key.mods > 0 and R.encodeMods(key.mods):gsub(",", ", ") or "no modifiers",
		inbox and " It is in your inbox." or ""))
	return inbox
end

-- ======================================================================== omen fragments and keys
local function omenItemReady(id)
	local it = id and ItemType(id)
	return it ~= nil and it:getId() ~= 0
end
RF.omenItemReady = omenItemReady

-- the kind key ("bloodmoon") of an Omen Key item, or nil
function RF.readOmenKey(item)
	local o = C().omen
	if not item or item:getId() ~= o.key.id then
		return nil
	end
	local kind = item:getCustomAttribute("omen_kind")
	return R.omenKind(C(), kind) and kind or nil
end

function RF.applyOmenKey(item, kind)
	local cfg = C()
	local d = R.omenKind(cfg, kind)
	item:setCustomAttribute("omen_kind", d.key)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, R.omenKeyName(cfg, d.key))
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "an")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format("It hums with the name %s. Opens the %s guardian's arena " ..
		"(level %d+, %d minutes). Use it in a protection zone; your party within %d sqm comes along.", d.boss, d.name,
		cfg.omen.minLevel, math.floor(cfg.omen.timeLimit / 60), cfg.partyRange))
	return item
end

-- gives an Omen Key of `kind` (nil: a random kind); returns the kind or nil
function RF.giveOmenKey(player, kind, why)
	local cfg = C()
	if not omenItemReady(cfg.omen.key.id) then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "Omen Keys are not installed on this server (tools/install_omens.py).")
		return nil
	end
	kind = kind or cfg.omen.kinds[rand(1, #cfg.omen.kinds)].key
	local item = Game.createItem(cfg.omen.key.id, 1)
	if not item then
		return nil
	end
	RF.applyOmenKey(item, kind)
	local inbox = giveEx(player, item)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: %s.%s", why or "You received an Omen Key",
		R.omenKeyName(cfg, kind), inbox and " It is in your inbox." or ""))
	return kind
end

-- ======================================================================== crash refund marker
local function setMarker(player, key)
	player:setStorageValue(ST, key.omen and R.markerTier(C(), key.omen) or key.tier)
	for i = 1, 3 do
		player:setStorageValue(ST + i, key.mods[i] and R.packMod(C(), key.mods[i]) or 0)
	end
	player:setStorageValue(ST + 4, os.time())
	player:save()
end

local function clearMarker(player)
	if player:getStorageValue(ST) > 0 then
		for i = 0, 4 do
			player:setStorageValue(ST + i, 0)
		end
		player:save()
	end
end

-- why: set by a clean shutdown (RF.interrupt), which refunds the key of a run the player is still in; without it (the
-- next login) a player who is in a run, may return to one or left one without a logout event gets nothing.
-- The marker is the record: it is cleared in the same step the key is given and saved with it, so a key comes back once.
local function refundMarker(player, why)
	local tier = player:getStorageValue(ST)
	if tier <= 0 then
		return false
	end
	if not why and (RF.noRefund[player:getGuid()] or RF.runOf[player:getId()] or RF.revive[player:getGuid()]) then
		RF.noRefund[player:getGuid()] = nil
		clearMarker(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You left your rift: its key is spent.")
		return false
	end
	local mods = {}
	for i = 1, 3 do
		local m = R.unpackMod(C(), player:getStorageValue(ST + i))
		if m then
			mods[#mods + 1] = m
		end
	end
	for i = 0, 4 do
		player:setStorageValue(ST + i, 0)
	end
	RF.noRefund[player:getGuid()] = nil
	local omen = R.markerOmen(C(), tier)
	if omen then
		RF.giveOmenKey(player, omen, why or "Your last omen arena was interrupted by a server restart, so its key is returned")
	else
		RF.giveKey(player, {tier = R.clampTier(C(), tier), mods = mods},
			why or "Your last rift was interrupted by a server restart, so its key is returned")
	end
	player:save()
	return true
end
RF.refundMarker = refundMarker

-- ======================================================================== instance: the slot pool
-- Every run gets a generated layout (rift_layout_core.lua). A slot holds one built layout at a time:
--   empty     never built since the start
--   building  a job is clearing the old layout and building a new one (RF.job)
--   ready     built, nobody inside: the next key of its theme and band takes it at once
--   busy      a run
--   dirty     a run ended there; the builder clears it and builds a new layout next
--   bad       its footprint holds a tile of the real map (never used)
-- One job at a time: the generator runs in a coroutine that yields every build.sliceMs of game loop, the clean-up
-- and the tiles go the same way, one step every build.everyMs (server/README.md "Rifts", Layouts and the slot pool).
RF.slots = RF.slots or {} -- slot -> {state, L, theme, band, why, verified}
RF.demand = RF.demand or {} -- "theme|band" -> decayed count of the keys that asked for it
RF.builds = RF.builds or 0

local function nowMs()
	return os.mtime and os.mtime() or math.floor(os.clock() * 1000)
end

local function agConfig()
	if not ChaosAreaGenConfig then
		ChaosAreaGenConfig = dofile("data/scripts/chaos/areagen_config.lua")
	end
	return ChaosAreaGenConfig
end

-- the dark tile set is used when every dark item is installed (as areagen.lua decides)
local darkCache
local function darkOpts()
	if darkCache == nil then
		darkCache = false
		if C().dark and C().dark.enabled ~= false and ChaosDarkTiles and ChaosDarkTiles.ids then
			darkCache = true
			for name in pairs(ChaosDarkTiles.ids) do
				if not ChaosDarkTiles.installed(name) then
					darkCache = false
					break
				end
			end
		end
	end
	return darkCache and {dark = true, darkIds = ChaosDarkTiles.ids} or {}
end

function RF.slotOrigin(slot)
	local g = C().grid
	return {x = g.origin.x + (slot % g.cols) * g.spacing, y = g.origin.y + math.floor(slot / g.cols) * g.spacing,
		z = g.origin.z}
end

local function slotState(slot)
	RF.slots[slot] = RF.slots[slot] or {state = "empty"}
	return RF.slots[slot]
end

local function themeNames()
	local out = {}
	for _, th in ipairs(C().themes) do
		out[#out + 1] = th.name
	end
	return out
end

local function themeByName(name)
	for _, th in ipairs(C().themes) do
		if th.name == name then
			return th
		end
	end
	return C().themes[1]
end

RF.KIND_NAMES = {cave = "a cave system", waste = "an open waste", dungeon = "a ruined complex",
	mixed = "a cave with ruined chambers"}
function RF.kindName(kind)
	return RF.KIND_NAMES[kind] or tostring(kind)
end

-- the theme and band the next layout should have: the one the keys ask for most against what is ready or building
-- (ties: the next in turn)
function RF.neededCombo()
	local cfg = C()
	local have = {}
	for _, st in pairs(RF.slots) do
		if (st.state == "ready" or st.state == "building") and st.theme then
			local k = st.theme .. "|" .. st.band
			have[k] = (have[k] or 0) + 1
		end
	end
	local combos = {}
	for b = 1, #cfg.layout.sizes do
		for _, name in ipairs(themeNames()) do
			combos[#combos + 1] = {theme = name, band = b}
		end
	end
	RF.turn = (RF.turn or 0) % #combos + 1
	local best, bs
	for i = 0, #combos - 1 do
		local c = combos[(RF.turn + i - 1) % #combos + 1]
		local k = c.theme .. "|" .. c.band
		local score = (1 + (RF.demand[k] or 0)) / (1 + (have[k] or 0))
		if not bs or score > bs then
			best, bs = c, score
		end
	end
	return best
end

local function noteDemand(theme, band)
	for k, v in pairs(RF.demand) do
		RF.demand[k] = v * 0.98
	end
	local k = theme .. "|" .. band
	RF.demand[k] = (RF.demand[k] or 0) + 1
end

-- removes everything of one tile (players inside an idle slot go to their temple)
local function clearTile(k)
	local x, y, z = RL.unkey(k)
	local tile = Tile(Position(x, y, z))
	if not tile then
		return
	end
	for _, c in ipairs(tile:getCreatures() or {}) do
		if c:isPlayer() then
			c:teleportTo(c:getTown():getTemplePosition())
		else
			c:remove()
		end
	end
	local items = tile:getItems() or {}
	for i = #items, 1, -1 do
		items[i]:remove()
	end
	local g = tile:getGround()
	if g and type(g) ~= "number" then
		g:remove()
	end
end

-- the job of one slot (run inside a coroutine): the footprint check on its first build, the old layout cleared, a
-- new one generated and built. Returns L.
local function jobBody(slot, st, theme, band, seed, yieldTick)
	local cfg = C()
	local o = RF.slotOrigin(slot)
	if not st.verified then
		-- the first build since the start: nothing of the real map may stand in the slot's square on its floors
		local g = cfg.grid
		for z = o.z, o.z + (g.floors or 1) - 1 do
			for y = o.y, o.y + g.spacing - 1 do
				yieldTick()
				for x = o.x, o.x + g.spacing - 1 do
					local t = Tile(Position(x, y, z))
					if t and t:getGround() then
						error(string.format("tile %d,%d,%d already exists in the map", x, y, z), 0)
					end
				end
			end
		end
		st.verified = true
	end
	local old = st.L
	st.L = nil
	for i, k in ipairs(old and old.tileKeys or {}) do
		clearTile(k)
		if i % 4 == 0 then
			yieldTick()
		end
	end
	local opts = darkOpts()
	local gen = {dark = opts.dark, darkIds = opts.darkIds, tick = yieldTick, noChecksum = true}
	local L = RL.generate(cfg, agConfig(), {theme = theme, band = band, seed = seed, origin = o}, gen)
	if #L.problems > 0 then
		print(string.format("[ChaosRift] slot %d: layout %s seed %d: %s", slot, theme, seed, L.problems[1]))
	end
	for i, t in ipairs(L.tiles) do
		local pos = Position(t.x, t.y, t.z)
		if Tile(pos) or Game.createTile(pos, true) then
			Game.createItem(t.ground, 1, pos)
			for _, id in ipairs(t.items) do
				Game.createItem(id, 1, pos)
			end
		end
		if i % 4 == 0 then
			yieldTick()
		end
	end
	L.tiles = nil -- built: only the keys stay (the next clean-up)
	return L
end

local keeper

local function finishJob(slot, ok, result)
	local st = slotState(slot)
	local job = RF.job
	RF.job = nil
	if ok and result then
		st.state, st.L = "ready", result
		st.builtMs = job and (nowMs() - job.started) or 0
		st.workMs = job and job.work or 0
		print(string.format("[ChaosRift] slot %d ready: %s, %s %dx%d, %d floor(s), %d tiles, %d walkable, route %d, " ..
			"%d ms of game loop in %d steps over %.1f s", slot, result.theme, result.kind, result.side, result.side,
			#result.floors, result.stats.tiles, result.walkable, result.route, math.floor(st.workMs), job and job.steps or 0,
			st.builtMs / 1000))
		if ChaosInstanceLimits and ChaosInstanceLimits.freed then
			ChaosInstanceLimits.freed("rift", "the rifts")
		end
	else
		st.state, st.why = "bad", tostring(result)
		RF.bad[slot] = st.why
		print(string.format("[ChaosRift] slot %d not usable: %s", slot, st.why))
	end
end

-- one step of the running job: resumes the coroutine for at most sliceMs
local function jobStep()
	local job = RF.job
	if not job then
		return
	end
	local b = C().build
	local t0 = nowMs()
	job.deadline = t0 + b.sliceMs
	local ok, result = coroutine.resume(job.co)
	job.work, job.steps = job.work + (nowMs() - t0), job.steps + 1
	if not ok then
		finishJob(job.slot, false, result)
		keeper()
	elseif coroutine.status(job.co) == "dead" then
		finishJob(job.slot, true, result)
		keeper()
	else
		addEvent(jobStep, b.everyMs)
	end
end

local function startJob(slot, theme, band)
	local st = slotState(slot)
	RF.builds = RF.builds + 1
	local seed = (os.time() * 7 + slot * 7919 + RF.builds * 104729) % 2147483000 + 1
	st.state, st.theme, st.band, st.seed = "building", theme, band, seed
	local job = {slot = slot, started = nowMs(), work = 0, steps = 0}
	local n = 0
	local function yieldTick()
		n = n + 1
		if nowMs() >= (job.deadline or 0) then
			coroutine.yield()
		end
	end
	job.co = coroutine.create(function()
		return jobBody(slot, st, theme, band, seed, yieldTick)
	end)
	RF.job = job
	addEvent(jobStep, 0)
end

-- what to build next: a slot a run left (dirty), else an empty one while fewer than poolReady are ready
keeper = function()
	local cfg = C()
	if RF.job or not (cfg.layout and cfg.layout.enabled) then
		return
	end
	local ready, dirty, empty = 0, nil, nil
	for slot = 0, R.slotCount(cfg) - 1 do
		local st = slotState(slot)
		if st.state == "ready" then
			ready = ready + 1
		elseif st.state == "dirty" and not dirty then
			dirty = slot
		elseif st.state == "empty" and not empty then
			empty = slot
		end
	end
	local slot = dirty or (ready < cfg.build.poolReady and empty) or nil
	if slot then
		local c = RF.neededCombo()
		startJob(slot, c.theme, c.band)
	end
end
RF.keeper = keeper

-- a run ended: its slot is built anew (the corpses and items go with the clean-up)
function RF.releaseSlot(run)
	local st = RF.slots[run.slot]
	if st and st.state == "busy" then
		st.state = "dirty"
	end
	addEvent(keeper, 1000)
end

-- a ready slot for a key: the asked theme and band, else the band with another theme, else the theme in another
-- band, else any; nil, seconds to wait when none is ready
function RF.findReady(theme, band)
	local best, rank
	for slot = 0, R.slotCount(C()) - 1 do
		local st = RF.slots[slot]
		if st and st.state == "ready" and st.L then
			local r = (st.theme == theme and st.band == band) and 1 or (st.band == band and 2)
				or (st.theme == theme and 3) or 4
			if band == nil then
				r = st.theme == theme and 1 or 2
			end
			if not rank or r < rank then
				best, rank = slot, r
			end
		end
	end
	if best then
		return best
	end
	local eta
	for _, st in pairs(RF.slots) do
		if st.state == "building" or st.state == "dirty" or st.state == "empty" then
			eta = 15
		end
	end
	return nil, eta
end

-- ======================================================================== HUD
-- the Rift Atlas's Swift time of the run's tier (atlas_core.lua A.swiftSeconds): the HUD shows it; nil for an Omen
-- arena, a tier off the grid or without the atlas
local function swiftSeconds(run)
	local A, acfg = ChaosAtlasCore, ChaosAtlasConfig
	local tier = run.key and run.key.tier
	if run.omen or not (A and A.swiftSeconds and acfg and tier) or tier < 1 or tier > (acfg.tiers or 0) then
		return nil
	end
	run.swift = run.swift or A.swiftSeconds(acfg, C(), tier)
	return run.swift
end

local function hudData(run)
	local mods = {}
	for _, m in ipairs(run.key.mods) do
		local def = R.modDef(C(), m.key)
		mods[#mods + 1] = {name = def and def.name or m.key, text = R.modText(C(), m), boon = def and def.boon or nil,
			tier = def and R.modTier(def, m.value) or nil, side = def and def.side or nil}
	end
	-- live lines of the map modifiers (coffer, goblin, twin guardians)
	local notes = {}
	local cf = run.coffer
	if cf then
		if cf.state == "closed" then
			notes[#notes + 1] = string.format("A sealed coffer waits to the %s.", cf.dir or "far side")
		elseif cf.state == "guarded" then
			notes[#notes + 1] = string.format("Coffer guards: %d left.", cf.waveLeft)
		elseif cf.state == "open" then
			notes[#notes + 1] = "The coffer is open."
		end
	end
	if run.goblin == "out" and not Monster(run.goblinId) then
		run.goblin = "gone" -- slain or escaped
	end
	if run.goblin == "out" then
		notes[#notes + 1] = "A Treasure Goblin is loose!"
	end
	if (run.guardians or 1) > 1 and run.boss == "alive" then
		notes[#notes + 1] = string.format("Guardians left: %d.", run.guardians - (run.guardiansKilled or 0))
	end
	local waiting = 0
	for _ in pairs(run.revive or {}) do
		waiting = waiting + 1
	end
	if waiting > 0 and run.state == "running" then
		notes[#notes + 1] = string.format("%d fallen player%s may still return.", waiting, waiting == 1 and "" or "s")
	end
	if run.queue and #run.queue > 0 and run.boss == "waiting" and run.state == "running" then
		notes[#notes + 1] = string.format("%d more pack%s gather.", #run.queue, #run.queue == 1 and "" or "s")
	end
	if run.atlasNote then
		notes[#notes + 1] = run.atlasNote -- Rift Atlas
	end
	return {tier = run.key.tier, theme = run.themeName, left = R.timeLeft(run, os.time()), limit = run.limit or C().timeLimit,
		total = run.total, killed = run.killed, bossAt = run.bossAt, boss = run.boss, state = run.state,
		bossName = R.nameOf(run.looks, run.plan.boss, true) or run.plan.boss, -- the name the guardian shows
		mods = mods, bonus = run.bonus, notes = notes, lives = run.lives,
		livesMax = run.livesMax, omen = run.omen and R.omenKind(C(), run.omen).name or nil,
		title = run.omen and ("Omen - " .. R.omenKind(C(), run.omen).name) or nil, swift = swiftSeconds(run)}
end

local function sendHud(run, action, player)
	local data = hudData(run)
	if player then
		Chaos.send(player, OPCODE, action, data)
		return
	end
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			Chaos.send(p, OPCODE, action, data)
		end
	end
end

-- ======================================================================== withering (no health regeneration)
-- fx.noRegen (Withering): no health; fx.noMana (Parched Veins): no mana; the other one stays the vocation's
local function wither(player, entry, fx)
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if not cond then
		entry.withered = false -- ours ran out; food eaten later creates a normal one, converted on the next tick
		return
	end
	if entry.withered then
		return
	end
	local ticks = cond:getTicks()
	player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	local voc = player:getVocation()
	local noHealth = not fx or fx.noRegen
	local noMana = fx and fx.noMana
	local c = Condition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	c:setTicks(ticks)
	c:setParameter(CONDITION_PARAM_HEALTHGAIN, noHealth and 0 or voc:getHealthGainAmount())
	c:setParameter(CONDITION_PARAM_HEALTHTICKS, noHealth and 60000 or voc:getHealthGainTicks() * 1000)
	c:setParameter(CONDITION_PARAM_MANAGAIN, noMana and 0 or voc:getManaGainAmount())
	c:setParameter(CONDITION_PARAM_MANATICKS, noMana and 60000 or voc:getManaGainTicks() * 1000)
	player:addCondition(c)
	entry.withered = true
end

local function unwither(player, entry)
	if not entry.withered then
		return
	end
	entry.withered = false
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if cond then
		local seconds = math.floor(cond:getTicks() / 1000)
		player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
		if seconds > 0 then
			player:feed(seconds)
		end
	end
end

-- ======================================================================== run end
local finishExit

local function removePlayer(run, id, mode)
	local entry = run.players[id]
	if not entry then
		return
	end
	run.players[id] = nil
	RF.runOf[id] = nil
	local player = Player(id)
	if player then
		unwither(player, entry)
		player:unregisterEvent("ChaosRiftPlayerDeath")
		player:unregisterEvent("ChaosRiftPlayerHit")
		player:unregisterEvent("ChaosRiftPlayerMana")
		player:unregisterEvent("ChaosRiftPlayerKill")
		if run.restart and mode ~= "dead" then
			-- a clean shutdown (RF.interrupt): out to the temple, where the character is saved
			player:teleportTo(player:getTown():getTemplePosition())
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		elseif mode == "out" or mode == "logout" then
			player:teleportTo(entry.entry)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		if mode ~= "logout" then
			local running = run.state == "running"
			local text = running and (mode == "dead" and "You fell in the rift." or "You left the rift.") or run.endText
			if mode == "dead" and running and RF.revive[entry.guid] == run then
				text = string.format("You fell: %d %s left. You return at the rift's entrance when you log in again.",
					run.lives, run.lives == 1 and "life" or "lives")
			end
			Chaos.send(player, OPCODE, "end", {result = running and "left" or run.state, text = text})
		end
		if entry.guid == run.openerGuid then
			clearMarker(player) -- the key is spent once its owner leaves the run (or the run ended)
		end
	elseif entry.guid == run.openerGuid then
		-- gone without a logout event (lost connection, kicked): no refund at the next login while this server runs;
		-- and none after a restart either: the character was saved with the marker when it was removed, so the marker
		-- is taken out of the database now (a restart empties this table)
		RF.noRefund[entry.guid] = true
		if db and db.query then
			db.query(string.format("DELETE FROM `player_storage` WHERE `player_id` = %d AND `key` >= %d AND `key` <= %d",
				entry.guid, ST, ST + 4))
		end
	end
	-- a fallen player who may still return keeps a running rift open (until the time runs out)
	if next(run.players) == nil and not run.ended and not (run.state == "running" and next(run.revive or {}) ~= nil) then
		if run.state == "running" then
			run.state = "failed"
			run.endText = "Everyone left the rift."
		end
		finishExit(run)
	end
end
RF._removePlayer = removePlayer

finishExit = function(run)
	if run.ended then
		return
	end
	run.ended = true
	-- unclaimed chest shares: delivered now (online) or at the next login
	if run.state == "success" then
		for guid, f in pairs(run.finishers or {}) do
			if not run.claimed[guid] then
				run.claimed[guid] = true
				local p = Player(f.name)
				if p and p:getGuid() == guid then
					RF.deliver(p, run, true)
				else
					RF.pending[guid] = RF.pending[guid] or {}
					table.insert(RF.pending[guid], {tier = run.key.tier, bonus = run.bonus, types = run.typeNames, boss = run.plan.boss,
						omen = run.omen, theme = run.themeName, atlasRun = run.atlasRun}) -- theme, atlasRun: Rift Atlas
				end
			end
		end
	end
	for guid in pairs(run.revive or {}) do
		if RF.revive[guid] == run then
			RF.revive[guid] = nil
		end
	end
	run.revive = {}
	for id in pairs(run.players) do
		removePlayer(run, id, "out")
	end
	-- the run's monsters go now (the corpses and items with the slot's next build)
	for mid, r in pairs(RF.monsterRun) do
		if r == run then
			RF.monsterRun[mid] = nil
			RF.husk[mid] = nil
			local m = Monster(mid)
			if m and m.remove then
				m:remove()
			end
		end
	end
	if RF.runs[run.slot] == run then
		RF.releaseSlot(run)
		RF.runs[run.slot] = nil
		if ChaosInstanceLimits and not run.restart then
			ChaosInstanceLimits.freed("rift", "the rifts")
		end
	end
	print(string.format("[ChaosRift] run %d (slot %d, tier %d) ended: %s", run.id, run.slot, run.key.tier, run.state))
end

local function fail(run, text)
	run.state = "failed"
	run.endText = text .. (run.omen and " The arena collapses and the key is lost." or " The rift collapses and the key is lost.")
	say(run, run.endText)
	finishExit(run)
end
RF._fail = fail

-- ======================================================================== clean shutdown / server save
-- A shutdown (onShutdown below, SIGTERM, /closeserver shutdown, the server save) or a closed server (/closeserver, the
-- server save with "close") kicks every player, which would read as "logged out inside: the key is spent". Instead every
-- open run ends here first: everyone goes to the temple; a run whose guardian is still alive gives its key back to the
-- player who used it (while that player is still in the run, like the crash refund), through the marker, so exactly once;
-- a sealed run (guardian dead, chest up) gives no key, its chest shares are handed out now as at a normal exit.
-- A crash has no event: the marker refunds the key at the next login (refundMarker).
function RF.interrupt(run)
	if run.ended then
		return false
	end
	run.restart = true
	local refunded
	if run.state == "running" then
		for id, e in pairs(run.players) do
			local p = Player(id)
			if p and e.guid == run.openerGuid then
				refunded = refundMarker(p, run.omen and "The server is restarting: your omen arena closes and its key is returned"
					or "The server is restarting: your rift closes and its key is returned") and p:getName() or nil
			end
		end
		run.state = "interrupted"
		run.endText = (run.omen and "The server is restarting: the arena closes" or "The server is restarting: the rift closes")
			.. (refunded and string.format(" and %s gets the key back.", refunded) or ".")
		say(run, run.endText)
	end
	finishExit(run)
	print(string.format("[ChaosRift] run %d interrupted by a shutdown (key %s)", run.id, refunded and ("refunded to " .. refunded)
		or "not refunded"))
	return true
end

function RF.interruptAll()
	local n = 0
	for _, run in pairs(RF.runs) do
		if RF.interrupt(run) then
			n = n + 1
		end
	end
	return n
end

local function serverClosing()
	local state = Game.getGameState and Game.getGameState()
	return state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED)
end
RF.serverClosing = serverClosing

-- ======================================================================== rewards
-- every unique of ChaosUniqueItems without its monster list (the omen guardians' pool); rebuilt when the list changes
local omenUniqueCache, omenUniqueFrom
local function omenUniques()
	if omenUniqueFrom ~= ChaosUniqueItems then
		omenUniqueFrom = ChaosUniqueItems
		omenUniqueCache = {}
		for k, e in pairs(ChaosUniqueItems or {}) do
			if type(e) == "table" and not e.ascended then -- the Ascended uniques drop only from their bosses (uber.lua)
				local c = {}
				for f, v in pairs(e) do
					c[f] = v
				end
				c.monsters = nil
				c.name = c.name or (type(k) == "string" and k) or nil
				omenUniqueCache[#omenUniqueCache + 1] = c
			end
		end
	end
	return omenUniqueCache
end

-- the item level of a rift's chest and coffer gear (chaos_item_mods.lua M.sourceLevel): the level of the rift's boss
-- (its hunting level, else the top of the tier's level window), the rift tier and the Omen bonus
function RF.itemLevel(tier, bossName, omen, kind)
	local M = ChaosItemMods
	if not M then
		return nil
	end
	local level = bossName and RF.poolLevel[tostring(bossName):lower()] or R.tierInfo(C(), tier).pick[2]
	return M.sourceLevel({monsterLevel = level, tier = kind or "boss", riftTier = tier, omen = omen and true or false})
end

local function riftGear(id, rarity, ilvl)
	if ChaosCrafting and ChaosCrafting.createItem then
		return ChaosCrafting.createItem(id, rarity, ilvl)
	end
	return Game.createItem(id, 1)
end

-- one finisher's chest. auto = true when it was not opened before the exit
function RF.deliver(player, run, auto)
	local cfg = C()
	local data = run.key and {tier = run.key.tier, bonus = run.bonus, types = run.typeNames, boss = run.plan.boss,
		omen = run.omen} or run
	local r = data.omen and R.omenReward(cfg, player:getLevel()) or R.reward(cfg, data.tier, data.bonus, rand)
	-- Rift Atlas: the finisher's own atlas (gold, orbs, rolls, fragments) and the run's keystone (shared by all)
	local atlasOwn = not data.omen and R.atlasMods(player, {theme = run.themeName or run.theme, tier = data.tier}) or nil
	if not data.omen then
		R.atlasReward(cfg, r, atlasOwn, run.atlasRun, rand)
	end
	-- the party bonus (rift_config.lua party): every finisher, by the players who entered
	R.partyReward(cfg, r, run.size, rand)
	local asTier = data.omen and cfg.omen.reward.asTier or data.tier
	local inbox = false
	if r.gold > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	inbox = giveStack(player, cfg.reward.items.chaos, r.chaos) or inbox
	inbox = giveStack(player, cfg.reward.items.divine, r.divine) or inbox
	local found = {}
	local stacks, order = {}, {} -- non-gear drops merged per item id
	local function stack(id, count)
		if not stacks[id] then
			stacks[id] = 0
			order[#order + 1] = id
		end
		stacks[id] = stacks[id] + count
	end
	local L = ChaosLoot
	if L then
		local itemFind = L.itemFindMult(player)
		local ctx = {tier = r.lootTier, player = player, level = 0, itemFind = itemFind}
		-- each roll draws ONE entry of a random rift monster's loot table, weighted by its loot chance
		for _ = 1, r.rolls do
			local name = data.types[rand(1, #data.types)]
			local mt = MonsterType(name)
			local loot = mt and mt:getLoot() or {}
			local rows = {}
			for _, e in ipairs(loot) do
				if e.itemId and (e.chance or 0) > 0 then
					rows[#rows + 1] = {e, e.chance}
				end
			end
			local e = R.weighted(rows, rand)
			if e then
				if L.isGearId(e.itemId) then
					local rarity = L.upgradeRarity(r.lootTier, L.stockRarity(), itemFind * r.rarityMult)
					local item = riftGear(e.itemId, rarity, RF.itemLevel(asTier, data.boss, data.omen))
					if item and ChaosVeiled and ChaosVeiled.rollReward then
						ChaosVeiled.rollReward(item, {riftTier = asTier, omen = data.omen ~= nil}) -- veiled.lua
					end
					if item then
						inbox = giveEx(player, item) or inbox
						local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names
						found[#found + 1] = (rarity > 0 and ("[" .. (names and names[rarity] or rarity) .. "] ") or "") .. itemName(e.itemId)
					end
				else
					local maxC = math.max(e.maxCount or 1, e.minCount or 1)
					stack(e.itemId, math.max(1, math.floor(rand(e.minCount or 1, maxC) * r.countMult)))
				end
			end
		end
		for _, c in ipairs(L.rollCurrency(r.lootTier, ctx)) do
			stack(c.id, c.count)
		end
		-- gems (data/lib/chaos_gems_config.lua rewards.rift: count and quality by the rift tier)
		for _, g in ipairs(ChaosGems and ChaosGems.rewardGems("rift", {tier = asTier}, rand) or {}) do
			stack(g.id, g.count)
		end
		-- spell support runes (data/lib/chaos_supports_config.lua rewards.rift)
		for _, g in ipairs(ChaosSupports and ChaosSupports.rewardRunes("rift", {tier = asTier}, rand) or {}) do
			stack(g.id, g.count)
		end
		local uniques = {}
		if data.omen then
			-- the guardian: uniqueRolls rolls at the boss tier over every unique, x uniqueFind
			for _ = 1, r.uniqueRolls do
				for _, e in ipairs(L.rollUniques("boss", data.boss, 0, itemFind * r.rarityMult * r.uniqueFind, omenUniques(),
						player)) do
					uniques[#uniques + 1] = e
				end
			end
		else
			uniques = L.rollUniques(r.lootTier, data.boss, 0, itemFind * r.rarityMult)
		end
		for _, e in ipairs(uniques) do
			local item = Game.createItem(e.id, 1)
			if item then
				if ChaosMakeUnique then
					ChaosMakeUnique(item)
				end
				inbox = giveEx(player, item) or inbox
				found[#found + 1] = "{" .. e.name .. "}"
			end
		end
		-- item sets (itemsets.lua): one chase roll over the sets of this rift's theme
		if not data.omen and ChaosItemSets and ChaosItemSets.grantChase then
			local piece = ChaosItemSets.grantChase(player, "rift", run.themeName or run.theme,
				{tier = data.tier, itemFind = itemFind}, rand)
			if piece then
				found[#found + 1] = "{" .. piece .. "}"
			end
		end
	end
	-- Omen Fragments from a sealed rift of omen.minTier or more
	local frags = not data.omen and R.omenFragments(cfg, data.tier, data.bonus, rand) or 0
	frags = R.atlasFragments(frags, atlasOwn, rand) -- Rift Atlas
	frags = R.partyCount(cfg, frags, run.size, rand) -- the party bonus
	if frags > 0 and omenItemReady(cfg.omen.fragment.id) then
		stack(cfg.omen.fragment.id, frags)
	end
	for _, id in ipairs(order) do
		local n = stacks[id]
		if L and not L.isStackableId(id) then
			for _ = 1, n do
				local item = Game.createItem(id, 1)
				if item then
					inbox = giveEx(player, item) or inbox
				end
			end
		else
			inbox = giveStack(player, id, n) or inbox
		end
		found[#found + 1] = (n > 1 and (n .. "x ") or "") .. itemName(id)
	end
	local list = table.concat(found, ", ", 1, math.min(#found, 25)) .. (#found > 25 and (" and " .. (#found - 25) .. " more") or "")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: %d gold to your bank, %d Orb%s of Upheaval, %d Orb%s of Fate%s%s.%s",
		auto and ((data.omen and "Guardian's reward" or "Rift reward") .. " (the chest was not opened, it was sent to you)")
			or (data.omen and "Guardian's chest" or "Rift chest"),
		r.gold, r.chaos, r.chaos == 1 and "" or "s", r.divine, r.divine == 1 and "" or "s",
		#found > 0 and ", " or "", list, inbox and " Your backpack was full: the rest is in your inbox." or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	return r, found
end

local function success(run, pos)
	local cfg = C()
	run.endText = string.format(run.omen and "The guardian falls! Open its chest within %d seconds."
		or "The rift is sealed! Open the chest within %d seconds.", cfg.exitDelay)
	-- what is left of the rift dies with it
	for mid, r in pairs(RF.monsterRun) do
		if r == run then
			RF.monsterRun[mid] = nil
			local m = Monster(mid)
			if m then
				m:getPosition():sendMagicEffect(CONST_ME_POFF)
				m:remove()
			end
		end
	end
	RF.cofferOnSeal(run)
	run.finishers, run.claimed = {}, {}
	-- fallen players who could still return count as finishers (their share comes at the exit or the next login)
	for guid, f in pairs(run.revive or {}) do
		run.finishers[guid] = {name = f.name}
	end
	for id, e in pairs(run.players) do
		run.finishers[e.guid] = {name = e.name}
		if run.omen then
			if ChaosAchievements and ChaosAchievements.progress then
				local p = Player(id)
				pcall(ChaosAchievements.progress, p, "omen_kills", 1)
				pcall(ChaosAchievements.progress, p, "omen_" .. run.omen, 1)
			end
		elseif ChaosLeaderboard and ChaosLeaderboard.record then
			pcall(ChaosLeaderboard.record, "rift", Player(id) or {guid = e.guid, name = e.name}, run.key.tier) -- weekly Rifts board
		end
		if not run.omen and ChaosCharms and ChaosCharms.onSource and Player(id) then -- a charm drop (charms.lua)
			pcall(ChaosCharms.onSource, Player(id), "rift", {tier = run.key.tier})
		end
	end
	-- the chest (on the boss's tile, or the guardian's spawn)
	local chestPos = pos or P(run.L.bossSpawn)
	run.chestPos = chestPos
	local chest = Game.createItem(cfg.chest.itemId, 1, chestPos)
	if chest then
		chest:setActionId(cfg.chest.actionId)
		chest:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, run.omen and "The guardian's hoard. Every finisher may open it once."
			or "The spoils of the rift. Every finisher may open it once.")
		chestPos:sendMagicEffect(CONST_ME_FIREWORK_RED)
	end
	-- the next key: to the player who used the key, else a random finisher
	local drop = not run.omen and R.rollKeyDrop(cfg, run.key.tier, #run.key.mods, rand, run.atlasRun) or nil
	if drop then
		local target
		for id, e in pairs(run.players) do
			if e.guid == run.openerGuid then
				target = Player(id)
			end
		end
		if not target then
			local ids = {}
			for id in pairs(run.players) do
				ids[#ids + 1] = id
			end
			target = #ids > 0 and Player(ids[rand(1, #ids)]) or nil
		end
		if target then
			RF.giveKey(target, drop, drop.tier > run.key.tier and "The rift leaves a stronger key behind" or "The rift leaves a key behind")
			if drop.tier > run.key.tier then
				say(run, string.format("%s found a %s!", target:getName(), R.keyName(cfg, drop.tier)))
			end
		end
	end
	local secs = os.time() - run.startTime
	-- Rift Atlas: first completions (theme x tier, flawless, swift, omen) for every finisher
	local atlasGuids = {}
	for guid in pairs(run.finishers) do
		atlasGuids[#atlasGuids + 1] = guid
	end
	R.atlasSealed({theme = run.themeName, tier = run.key.tier, omen = run.omen, deaths = run.deaths or 0, secs = secs,
		guids = atlasGuids})
	-- Ascended Shards (uber.lua): Omen guardian kills and rifts of tier 13+ (online finishers)
	if ChaosAscended and ChaosAscended.onRiftSealed then
		pcall(ChaosAscended.onRiftSealed, {tier = run.key.tier, omen = run.omen, finishers = run.finishers, players = run.size})
	end
	if run.omen then
		say(run, string.format("The %s guardian falls in %d:%02d. %s", R.omenKind(cfg, run.omen).name, math.floor(secs / 60),
			secs % 60, run.endText))
	else
		say(run, string.format("Rift tier %d sealed in %d:%02d. %s", run.key.tier, math.floor(secs / 60), secs % 60, run.endText))
	end
	sendHud(run, "update")
	for id, e in pairs(run.players) do
		Chaos.send(Player(id), OPCODE, "end", {result = "success", text = run.endText, exitIn = cfg.exitDelay})
		if e.guid == run.openerGuid then
			clearMarker(Player(id))
		end
	end
	addEvent(function(slot, rid)
		local r = RF.runs[slot]
		if r and r.id == rid and not r.ended then
			finishExit(r)
		end
	end, cfg.exitDelay * 1000, run.slot, run.id)
end

-- ======================================================================== spawning

-- opts (optional): {laden = false: a density husk (no loot, no kill credit); extra = true: does not count towards the
-- guardian (Veilbreach, thralls)}
local function spawnOne(run, name, pos, tier, boss, opts)
	-- the rift-exclusive name (rift_config.lua looks.names), set before the placement; credit stays with the type.
	-- A rank variant (looks.variants, with looks.variantsOn) brings its own look and name.
	local variant = R.pickVariant(run.looks, name, boss, math.random())
	local shown = variant and variant.name or R.nameOf(run.looks, name, boss)
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	local m = create(name, P(pos), true, false, shown) or create(name, P(pos), true, true, shown)
	if not m then
		return nil
	end
	local base = m:getMaxHealth()
	-- the rift-exclusive look (rift_config.lua looks), before the tier so its shader goes on that look
	local look = variant and variant.look or R.lookOf(run.looks, name, boss)
	if not look and boss and run.omen then
		-- an Omen guardian keeps its own look (its XML), or its big one (looks.bigGuardians, with looks.bigGuardiansOn)
		local own = m:getOutfit().lookType
		local big = R.bigLook(C().looks, own)
		if big ~= own then
			look = big
		end
	end
	if look then
		m:setOutfit({lookType = look})
	end
	if tier and ChaosApplyTier then
		ChaosApplyTier(m, tier)
	end
	local dense = run.density ~= nil
	local hp
	if boss and run.omen then
		hp = math.floor(base * R.omenHealthMult(C(), run.size))
	elseif boss then
		-- density: the guardian's base is the budget (rift_core.lua R.guardianBase), not the kind's own health
		local gb = dense and R.guardianBase(C(), run.key.tier) or base
		hp = math.floor(gb * R.guardianHealthMult(C(), run.fx, run.size)) -- + Dread Guardian, Twin Guardians share
	elseif dense then
		-- the budget health x the kind's share x its magic / rare / legendary tier (and random modifiers)
		local tierMult = base > 0 and m:getMaxHealth() / base or 1
		hp = math.floor(run.density.packHealth * (run.healthRatio and run.healthRatio[name:lower()] or 1) * tierMult
			* run.fx.health * (run.fx.partyHealth or 1))
	else
		hp = math.floor(m:getMaxHealth() * run.fx.health * (run.fx.partyHealth or 1)) -- + the party's share (R.applyParty)
	end
	if hp ~= m:getMaxHealth() and hp > 0 then
		m:setMaxHealth(hp)
		m:setHealth(hp)
	end
	if run.fx.speed ~= 0 then
		m:changeSpeed(run.fx.speed)
	end
	m:registerEvent("ChaosRiftMonsterDeath")
	m:registerEvent("ChaosRiftMonsterHealth")
	local id = m:getId()
	RF.monsterRun[id] = run
	if not boss then
		run.alive = (run.alive or 0) + 1
		run.aliveIds = run.aliveIds or {}
		run.aliveIds[id] = true
	end
	if opts and opts.laden == false then
		RF.husk[id] = true
		if m.setDropLoot then
			m:setDropLoot(false)
		end
	end
	if opts and opts.extra then
		run.extra = run.extra or {}
		run.extra[id] = true
	end
	return m
end

-- the section a pack stands in (a name of L.sections; an unknown one: the first section)
local function sectionOf(run, room)
	local L = run.L
	return L.byName and (L.byName[room] or L.sections[1]) or nil
end

-- one pack of the plan into a section (around a random cell of it; atCentre: around its centre, the reinforcements,
-- which must stay out of sight); returns how many came
local function spawnPack(run, pack, room, atCentre)
	local cfg = C()
	local L = run.L
	local s = sectionOf(run, room)
	local center = s and (atCentre and {x = s.x, y = s.y, z = s.z} or RL.cellIn(L, s, rand)) or L.bossSpawn
	local spread = run.density and cfg.density.spread or cfg.packs.spread
	local n = 0
	for k = 1, pack.count do
		local pos = L.walkKeys and RL.near(L, center, spread, rand) or center
		local husk = pack.laden ~= nil and pack.laden[k] == false
		if spawnOne(run, pack.name, pos, pack.elites[k] or nil, false, husk and {laden = false} or nil) then
			n = n + 1
		end
	end
	return n
end

-- monsters that could not be created leave the plan (the guardian threshold follows)
local function dropMissing(run, pack, n)
	if n < pack.count then
		run.total = math.max(0, run.total - (pack.count - n))
		run.bossAt = math.max(1, math.ceil(run.total * C().bossAt / 100))
	end
end

-- the first packs, spread over the map: density.populate.perStep monsters a step (one game loop task each), so
-- 100-250 monsters are not all made in the task that uses the key
local function populateStep(slot, rid)
	local run = RF.runs[slot]
	if not run or run.id ~= rid or run.ended or run.state ~= "running" then
		return
	end
	local p = C().density.populate
	local made = 0
	while #run.populate > 0 and made < p.perStep do
		local pack = table.remove(run.populate, 1)
		local n = spawnPack(run, pack, pack.room)
		made = made + pack.count
		dropMissing(run, pack, n)
	end
	if #run.populate > 0 then
		addEvent(populateStep, p.stepMs, slot, rid)
	end
end

-- the run's packs: all of them (density off), or as many as the live cap allows; the rest wait in run.queue. The
-- first packs come in populate steps (all at once with `now`, the tests)
local function spawnPacks(run, now)
	local spawned, planned = 0, 0
	run.queue, run.populate = {}, {}
	for i, pack in ipairs(run.plan.packs) do
		if run.density and i > 1 and planned + pack.count > run.density.live then
			run.queue[#run.queue + 1] = pack
		else
			planned = planned + pack.count
			run.populate[#run.populate + 1] = pack
		end
	end
	local p = C().density.populate
	local first = (now or not run.density or not p) and math.huge or p.perStep
	local made = 0
	while #run.populate > 0 and made < first do
		local pack = table.remove(run.populate, 1)
		local n = spawnPack(run, pack, pack.room)
		spawned, made = spawned + n, made + pack.count
		run.planMissing = (run.planMissing or 0) + (pack.count - n)
	end
	if #run.populate > 0 then
		addEvent(populateStep, p.stepMs, run.slot, run.id)
	end
	return spawned
end

local spawnBoss

local function playerPositions(run)
	local pos = {}
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			pos[#pos + 1] = p:getPosition()
		end
	end
	return pos
end

-- density: queued packs come in when there is room, in the section farthest from the players among the unvisited
-- ones just ahead of the party (RL.reinforceSection), a few a second, until the guardian appears
local function reinforce(run)
	local cfg = C()
	if not run.density or not run.queue or #run.queue == 0 or run.boss ~= "waiting" or run.state ~= "running" then
		return
	end
	local rc = cfg.density.reinforce
	local pos = playerPositions(run)
	run.visited = run.visited or {}
	RL.visit(run.L, pos, run.visited, rc.visit)
	local came = 0
	for _ = 1, rc.perTick do
		local pack = run.queue[1]
		if not pack or (run.alive or 0) + pack.count > run.density.live then
			break
		end
		local s = RL.reinforceSection(run.L, pos, run.visited, rc.minDistance, rc.window)
		if not s then
			break
		end
		table.remove(run.queue, 1)
		local n = spawnPack(run, pack, s.name, true)
		came = came + n
		dropMissing(run, pack, n)
	end
	if came > 0 then
		run.reinforced = (run.reinforced or 0) + came
	end
	if run.boss == "waiting" and run.killed >= run.bossAt and run.total > 0 then
		run.boss = "alive"
		spawnBoss(run)
	end
end
RF._reinforce = reinforce
RF._spawnPacks, RF._spawnOne = spawnPacks, spawnOne

function spawnBoss(run) -- the forward-declared local (reinforce)
	local cfg = C()
	run.bossIds = run.bossIds or {}
	local first
	for i = 1, run.guardians or 1 do
		local at = run.L.bossSpawn
		if i > 1 then
			at = {x = at.x + cfg.twin.offset, y = at.y, z = at.z}
		end
		local m = spawnOne(run, run.plan.boss, at, not run.omen and cfg.boss.tier or nil, true)
		if m then
			run.bossIds[m:getId()] = true
			run.bossId = run.bossId or m:getId()
			first = first or m
			packFx(P(at), "rift_boss_arrives", CONST_ME_MORTAREA)
		end
	end
	if not first and run.omen then
		print("[ChaosRift] omen guardian " .. tostring(run.plan.boss) .. " could not be created; the key is returned")
		for _, e in pairs(run.players) do
			if e.guid == run.openerGuid and Player(e.id) then
				RF.giveOmenKey(Player(e.id), run.omen, "The guardian did not answer, so your key is returned")
			end
		end
		run.omen = nil
		fail(run, "The guardian did not answer.")
		return
	end
	if not first then
		print("[ChaosRift] boss " .. tostring(run.plan.boss) .. " could not be created; the rift counts as sealed")
		run.boss = "alive"
		run.guardians, run.guardiansKilled = 1, 0
		if R.onBossKilled(run, os.time()) == "success" then
			success(run, nil)
		end
		return
	end
	local made = 0
	for _ in pairs(run.bossIds) do
		made = made + 1
	end
	run.guardians = made -- a twin that could not be created does not have to be killed
	if run.omen then
		say(run, string.format("%s answers the omen!", first:getName()))
	elseif made > 1 then
		say(run, string.format("Twin guardians %s tear through the veil!", first:getName()))
	else
		say(run, string.format("The rift guardian %s tears through the veil!", first:getName()))
	end
	sendHud(run, "update")
end

-- ======================================================================== map modifiers
-- a free walkable tile of a section: no creature, nothing on it (nil after a few tries)
local function freeCellIn(run, s)
	if not s then
		return nil
	end
	for _ = 1, 20 do
		local p = RL.cellIn(run.L, s, rand)
		local tile = Tile(P(p))
		if tile and tile:getGround() and tile:getCreatureCount() == 0 and tile:getTopDownItem() == nil
				and not tile:hasProperty(CONST_PROP_BLOCKSOLID) then
			return p
		end
	end
	return nil
end

-- where something is from the rift's entrance, as a compass word ("north-east")
local function compass(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	local ns = dy < -math.abs(dx) / 2 and "north" or (dy > math.abs(dx) / 2 and "south" or "")
	local ew = dx > math.abs(dy) / 2 and "east" or (dx < -math.abs(dy) / 2 and "west" or "")
	if ns ~= "" and ew ~= "" then
		return ns .. "-" .. ew
	end
	return ns ~= "" and ns or (ew ~= "" and ew or "centre")
end
RF.compass = compass

-- Gilded Trail: a Treasure Goblin in a section 12+ sqm from a player of the run (close enough to chase)
local function spawnGoblin(run)
	run.goblin = "tried"
	if not (ChaosTreasureGoblin and ChaosTreasureGoblin.spawn) then
		return
	end
	local pos = playerPositions(run)
	local s = pos[1] and RL.sectionNear(run.L, pos[1], 12) or run.L.sections[rand(1, math.max(1, #run.L.sections))]
	local at = freeCellIn(run, s)
	if not at then
		return
	end
	local level = RF.poolLevel[run.plan.boss:lower()] or R.tierInfo(C(), run.key.tier).pick[2]
	local ok, m = pcall(ChaosTreasureGoblin.spawn, P(at), {level = level, name = run.plan.boss})
	if ok and m then
		run.goblin = "out"
		run.goblinId = m:getId()
		say(run, "A Treasure Goblin slips out of the rift with its hoard. Catch it before it escapes!")
	end
end

-- Sealed Coffer: placed at the start of the run in the section the plan picked
local function placeCoffer(run)
	local cfg = C()
	local room = run.plan.coffer
	local pos = room and freeCellIn(run, sectionOf(run, room))
	if not pos then
		return
	end
	local item = Game.createItem(cfg.coffer.itemId, 1, P(pos))
	if item then
		item:setActionId(cfg.coffer.actionId)
		item:setAttribute(ITEM_ATTRIBUTE_NAME, "sealed coffer")
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "A coffer sealed by the rift. Breaking the seal wakes its guards.")
		run.coffer = {state = "closed", room = room, pos = pos, waveLeft = 0, wave = {}, dir = compass(run.L.start, pos)}
	end
end

local function cofferItem(run)
	local tile = run.coffer and Tile(P(run.coffer.pos))
	return tile and tile:getItemById(C().coffer.itemId) or nil
end

-- rolls one item of a random rift monster's loot table (as the reward chest does) into the container
local function rollInto(container, types, lootTier, itemFind, rarityMult, countMult, found, ilvl)
	local L = ChaosLoot
	if not L then
		return
	end
	local mt = MonsterType(types[rand(1, #types)])
	local rows = {}
	for _, e in ipairs(mt and mt:getLoot() or {}) do
		if e.itemId and (e.chance or 0) > 0 then
			rows[#rows + 1] = {e, e.chance}
		end
	end
	local e = R.weighted(rows, rand)
	if not e then
		return
	end
	if L.isGearId(e.itemId) then
		local rarity = L.upgradeRarity(lootTier, L.stockRarity(), itemFind * rarityMult)
		local item = riftGear(e.itemId, rarity, ilvl)
		if item and container:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT) == RETURNVALUE_NOERROR then
			found[#found + 1] = itemName(e.itemId)
		end
	else
		local maxC = math.max(e.maxCount or 1, e.minCount or 1)
		local n = math.max(1, math.floor(rand(e.minCount or 1, maxC) * countMult))
		if not L.isStackableId(e.itemId) then
			n = math.min(n, 3)
		end
		for _ = 1, L.isStackableId(e.itemId) and 1 or n do
			container:addItem(e.itemId, L.isStackableId(e.itemId) and math.min(n, 100) or 1, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		found[#found + 1] = itemName(e.itemId)
	end
end

local function openCoffer(run)
	local cfg = C()
	local cf = run.coffer
	local item = cofferItem(run)
	cf.state = "open"
	if not item or not item:isContainer() then
		return
	end
	local r = R.cofferLoot(cfg, run.key.tier, run.bonus, rand, run.size)
	for _, c in ipairs(R.coins(r.gold)) do
		item:addItem(c[1], c[2], INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	if r.chaos > 0 then
		item:addItem(cfg.reward.items.chaos, r.chaos, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	if r.divine > 0 then
		item:addItem(cfg.reward.items.divine, r.divine, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	local found = {}
	for _ = 1, r.rolls do
		rollInto(item, run.typeNames, r.lootTier, 1, r.rarityMult, r.countMult, found,
			RF.itemLevel(run.key.tier, nil, false, "legendary"))
	end
	item:setAttribute(ITEM_ATTRIBUTE_NAME, "opened coffer")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "The seal is broken. Its spoils are free for the taking.")
	P(cf.pos):sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	say(run, string.format("The coffer's seal breaks: %d gold, %d Orb%s of Upheaval, %d Orb%s of Fate and %d more item%s inside.",
		r.gold, r.chaos, r.chaos == 1 and "" or "s", r.divine, r.divine == 1 and "" or "s", #found, #found == 1 and "" or "s"))
end
RF._openCoffer = openCoffer

local function wakeCoffer(run, player)
	local cfg = C()
	local cf = run.coffer
	local n = R.cofferWaveSize(cfg, run.size)
	local spread = cfg.coffer.wave.spread
	cf.state, cf.waveLeft, cf.wave = "guarded", 0, {}
	for _ = 1, n do
		local pos = {x = cf.pos.x + rand(-spread, spread), y = cf.pos.y + rand(-spread, spread), z = cf.pos.z}
		local tierName = R.eliteTier(cfg, run.fx, run.key.tier, rand)
		if not tierName or tierName == "magic" then
			tierName = cfg.coffer.waveTier
		end
		local m = spawnOne(run, run.typeNames[rand(1, #run.typeNames)], pos, tierName, false)
		if m then
			cf.wave[m:getId()] = true
			cf.waveLeft = cf.waveLeft + 1
		end
	end
	P(cf.pos):sendMagicEffect(CONST_ME_MORTAREA)
	say(run, string.format("%s breaks the coffer's seal: %d guards answer!", player:getName(), cf.waveLeft))
	if cf.waveLeft == 0 then
		openCoffer(run)
	end
	sendHud(run, "update")
end

-- the coffer at the seal of the rift: a woken one opens (its guards vanished with the rift), an untouched one crumbles
function RF.cofferOnSeal(run)
	local cf = run.coffer
	if not cf then
		return
	end
	if cf.state == "guarded" then
		openCoffer(run)
	elseif cf.state == "closed" then
		cf.state = "gone"
		local item = cofferItem(run)
		if item then
			P(cf.pos):sendMagicEffect(CONST_ME_POFF)
			item:remove()
		end
	end
end

function RF.useCoffer(player, item)
	local slot = R.slotOfPos(C(), item:getPosition())
	local run = slot and RF.runs[slot]
	local cf = run and run.coffer
	if not cf or run.ended or not run.players[player:getId()] then
		player:sendCancelMessage("The coffer does not answer you.")
		return true
	end
	if cf.state == "closed" then
		if run.state ~= "running" then
			player:sendCancelMessage("The coffer's seal has gone cold.")
			return true
		end
		wakeCoffer(run, player)
		return true
	elseif cf.state == "guarded" then
		player:sendCancelMessage(string.format("The coffer is still sealed: %d guard%s left.", cf.waveLeft,
			cf.waveLeft == 1 and "" or "s"))
		return true
	end
	return false -- open: the engine opens the container
end

-- Cinderdeath: the burst of a slain monster hits the players next to it after a short delay
local function cinderBurst(run, pos, maxHealth)
	local cfg = C()
	local dmg = R.cinderDamage(cfg, maxHealth, run.fx.cinder, run.key.tier)
	if dmg <= 0 then
		return
	end
	packFx(pos, "rift_cinder_mark", CONST_ME_HITBYFIRE)
	local rid, slot = run.id, run.slot
	addEvent(function(p, amount)
		local r = RF.runs[slot]
		if not r or r.id ~= rid or r.ended or r.state ~= "running" then
			return
		end
		local at = Position(p.x, p.y, p.z)
		packFx(at, "rift_cinder_burst", CONST_ME_FIREAREA)
		local rad = cfg.cinder.radius
		for _, pl in ipairs(Game.getSpectators(at, false, true, rad, rad, rad, rad)) do
			if r.players[pl:getId()] then
				doTargetCombatHealth(0, pl, COMBAT_FIREDAMAGE, -amount, -amount, CONST_ME_FIREAREA)
			end
		end
	end, cfg.cinder.delayMs, {x = pos.x, y = pos.y, z = pos.z}, dmg)
end

-- ======================================================================== hazards (third set of modifiers)
local function combatOf(element)
	return ({fire = COMBAT_FIREDAMAGE, ice = COMBAT_ICEDAMAGE, energy = COMBAT_ENERGYDAMAGE, earth = COMBAT_EARTHDAMAGE,
		death = COMBAT_DEATHDAMAGE, physical = COMBAT_PHYSICALDAMAGE})[element]
end
RF.combatOf = combatOf

-- the engine's combat types for rift_core.lua R.monsterHit / R.monsterTaken
local typesCache
local function hitTypes()
	if not typesCache then
		typesCache = {physical = COMBAT_PHYSICALDAMAGE, none = COMBAT_NONE,
			brand = {fire = COMBAT_FIREDAMAGE, ice = COMBAT_ICEDAMAGE, energy = COMBAT_ENERGYDAMAGE}}
	end
	return typesCache
end

local function effectOf(element)
	return ({fire = CONST_ME_FIREAREA, ice = CONST_ME_ICEAREA, energy = CONST_ME_ENERGYAREA,
		death = CONST_ME_MORTAREA})[element] or CONST_ME_POFF
end

-- the run's players as {player, entry} (shielded ones, back from a lost life, left out)
local function targets(run, now)
	local out = {}
	for id, entry in pairs(run.players) do
		local p = Player(id)
		if p and (entry.shieldUntil or 0) <= now then
			out[#out + 1] = p
		end
	end
	return out
end

-- value share of each listed player's max health as damage of the element (no attacker: nothing scales it again).
-- A Hollow Vessel counts health + maximum energy shield, its health being fixed and low (Chaos.percentBase).
local function percentHit(p, share, element)
	local amount = R.percentHit(Chaos.percentBase(p), share)
	doTargetCombatHealth(0, p, combatOf(element), -amount, -amount, effectOf(element))
end

-- Scorched Earth / Rimefloor: patches near the players; standing in one hurts every second
local function groundTick(run, now)
	local cfg = C()
	local g = run.fx.ground
	run.hazards = run.hazards or {}
	if now >= (run.groundAt or 0) then
		run.groundAt = now + cfg.ground.every
		for _, p in ipairs(targets(run, now)) do
			for _, t in ipairs(R.plus(R.nearTile(p:getPosition(), cfg.ground.near, rand))) do
				local k = t.x .. "," .. t.y .. "," .. t.z
				if RL.isFloor(run.L, t.x, t.y, t.z) then
					run.hazards[k] = {x = t.x, y = t.y, z = t.z, untilAt = now + cfg.ground.lastSeconds}
				end
			end
		end
	end
	local eff = effectOf(g.element)
	for k, h in pairs(run.hazards) do
		if h.untilAt <= now then
			run.hazards[k] = nil
		else
			P(h):sendMagicEffect(eff)
		end
	end
	for _, p in ipairs(targets(run, now)) do
		local at = p:getPosition()
		if run.hazards[at.x .. "," .. at.y .. "," .. at.z] then
			percentHit(p, g.percent / 100, g.element)
			if g.kind == "rimefloor" and CONDITION_PARALYZE and Condition then
				local c = Condition(CONDITION_PARALYZE)
				c:setParameter(CONDITION_PARAM_TICKS, cfg.ground.slowMs)
				c:setFormula(-cfg.ground.slowPercent / 100, 0, -cfg.ground.slowPercent / 100, 0)
				p:addCondition(c)
			end
		end
	end
end

-- a marked strike: the mark now, the hit warnMs later on every run player within radius of it
local function markedStrike(run, at, radius, warnMs, share, element, markEffect)
	local rid, slot = run.id, run.slot
	for dx = -radius, radius do
		for dy = -radius, radius do
			if math.max(math.abs(dx), math.abs(dy)) == radius or radius <= 1 then
				Position(at.x + dx, at.y + dy, at.z):sendMagicEffect(markEffect or CONST_ME_MAGIC_RED or CONST_ME_POFF)
			end
		end
	end
	addEvent(function(p0)
		local r = RF.runs[slot]
		if not r or r.id ~= rid or r.ended or r.state ~= "running" then
			return
		end
		local now = os.time()
		packFx(Position(p0.x, p0.y, p0.z), "rift_strike_" .. tostring(element), effectOf(element))
		for _, p in ipairs(targets(r, now)) do
			local q = p:getPosition()
			if q.z == p0.z and math.max(math.abs(q.x - p0.x), math.abs(q.y - p0.y)) <= radius then
				percentHit(p, share, element)
			end
		end
	end, warnMs, {x = at.x, y = at.y, z = at.z})
end

-- Veilstorm: a marked strike near every player
local function stormTick(run, now)
	local s = C().veilstorm
	if now < (run.stormAt or 0) then
		return
	end
	run.stormAt = now + s.every
	for _, p in ipairs(targets(run, now)) do
		markedStrike(run, R.nearTile(p:getPosition(), s.near, rand), s.radius, s.warnMs, run.fx.storm, "energy",
			CONST_ME_PURPLEENERGY)
	end
end

-- Wrathful Guardian: the nova around each guardian, and thralls (husks of the weakest kind) now and then
local function wrathTick(run, now)
	local w = C().wrath
	if run.boss ~= "alive" or not run.bossIds then
		return
	end
	local nova = now >= (run.novaAt or 0)
	local thrall = now >= (run.thrallAt or 0)
	if run.novaAt == nil then -- first nova one period after the guardian came
		run.novaAt, run.thrallAt = now + w.novaEvery, now + w.thrallEvery
		return
	end
	for id in pairs(run.bossIds) do
		local g = Monster(id)
		if g then
			local at = g:getPosition()
			if nova then
				markedStrike(run, at, w.radius, w.warnMs, run.fx.wrath, "death", CONST_ME_MAGIC_RED)
			end
			if thrall then
				run.thrallIds = run.thrallIds or {}
				local up = 0
				for tid in pairs(run.thrallIds) do
					if Monster(tid) then
						up = up + 1
					else
						run.thrallIds[tid] = nil
					end
				end
				for _ = 1, math.min(w.thralls, w.maxThralls - up) do
					local m = spawnOne(run, run.typeNames[1], R.nearTile(at, 2, rand), nil, false, {laden = false, extra = true})
					if m then
						run.thrallIds[m:getId()] = true
					end
				end
			end
		end
	end
	if nova then
		run.novaAt = now + w.novaEvery
	end
	if thrall then
		run.thrallAt = now + w.thrallEvery
	end
end

-- Veilbreach: a slain pack monster may tear open a breach of more monsters (extra: not towards the guardian)
local function breach(run, pos)
	local cfg = C()
	local b = cfg.breach
	local cap = (run.density and run.density.live or 100) + (cfg.density and cfg.density.extraSlack or 12)
	if (run.alive or 0) >= cap then
		return
	end
	local rid, slot = run.id, run.slot
	Position(pos.x, pos.y, pos.z):sendMagicEffect(CONST_ME_PURPLEENERGY or CONST_ME_TELEPORT)
	addEvent(function(p0)
		local r = RF.runs[slot]
		if not r or r.id ~= rid or r.ended or r.state ~= "running" then
			return
		end
		for _ = 1, b.count do
			local tierName = R.eliteTier(C(), r.fx, r.key.tier, rand, r.density and r.density.share)
			local laden = true
			if r.density and not tierName then
				laden = R.chance(r.density.normalShare * 100, rand)
			end
			spawnOne(r, r.typeNames[rand(1, #r.typeNames)], R.nearTile(p0, b.spread, rand), tierName, false,
				{laden = laden, extra = true})
		end
	end, b.delayMs, {x = pos.x, y = pos.y, z = pos.z})
end

RF._groundTick, RF._stormTick, RF._wrathTick, RF._breach, RF._wither = groundTick, stormTick, wrathTick, breach, wither

-- ======================================================================== tick
local riftDeath -- below (the monsters' deaths)

local function tick(slot, rid)
	local run = RF.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local now = os.time()
	if R.tick(run, now) == "fail" then
		fail(run, "Time is up!")
		return
	end
	-- instance limits (instance_limits.lua): warnings before the end; a run kept open only for fallen players who may
	-- come back closes after the idle grace, as a failed rift
	local IL = ChaosInstanceLimits
	if IL and run.state == "running" then
		IL.warn(run, R.timeLeft(run, now), IL.playersOf(run.players), run.omen and "Omen arena" or "Rift", C().limits)
		if IL.idle(run, next(run.players) ~= nil, C().limits, now) then
			fail(run, "Nobody came back in time.")
			return
		end
	end
	-- the omen guardian comes startDelay seconds after the party arrived
	if run.omen and run.boss == "waiting" and now >= (run.bossDueAt or 0) then
		run.boss = "alive"
		spawnBoss(run)
		if run.ended then
			return
		end
	end
	-- players who left the instance some other way (GM teleport, ...) are out of the run
	for id, entry in pairs(run.players) do
		local p = Player(id)
		if not p then
			removePlayer(run, id, "none")
		elseif R.slotOfPos(C(), p:getPosition()) ~= run.slot then
			removePlayer(run, id, "none")
		elseif (run.fx.noRegen or run.fx.noMana) and run.state == "running" then
			wither(p, entry, run.fx)
		end
		if run.ended then
			return
		end
	end
	-- monsters gone without a death this script saw (a husk nobody of the run killed): counted as dead
	local gone = {}
	for mid in pairs(run.aliveIds or {}) do
		if not Monster(mid) then
			gone[#gone + 1] = mid
		end
	end
	for _, mid in ipairs(gone) do
		riftDeath(mid, nil, nil)
		if run.ended then
			return
		end
	end
	if run.state == "running" then
		reinforce(run) -- density: queued packs
		if run.ended then
			return
		end
		if run.fx.ground then
			groundTick(run, now)
		end
		if (run.fx.storm or 0) > 0 then
			stormTick(run, now)
		end
		if (run.fx.wrath or 0) > 0 then
			wrathTick(run, now)
		end
	end
	if run.state == "running" and now >= (run.hudAt or 0) then
		run.hudAt = now + C().hudEvery
		sendHud(run, "update")
	end
	addEvent(tick, 1000, slot, rid)
end
RF._tick = tick

-- ======================================================================== opening
local exhaust = {}

local function insideOther(player)
	return (ChaosDungeonIsInside and ChaosDungeonIsInside(player))
		or (ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player))
		or (ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(player:getPosition()))
end

local function memberProblem(m, t)
	if RF.runOf[m:getId()] or RF.revive[m:getGuid()] then
		return "is already inside a rift"
	end
	if m:getLevel() < t.minLevel then
		return t.omen and string.format("needs level %d for an omen arena", t.minLevel)
			or string.format("needs level %d for a tier %d rift", t.minLevel, t.tier)
	end
	if Chaos.isMultiClient(m) then
		return "has another character from the same connection online"
	end
	if inCombat(m) then
		return "is in a fight"
	end
	if insideOther(m) then
		return "is inside a dungeon, the tower or the world boss arena"
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

-- the rules of the key user; t = {minLevel, tier} or {minLevel, omen = true}. Returns true or false (message sent)
local function openerOk(player, t)
	local cfg = C()
	if RF.runOf[player:getId()] or RF.revive[player:getGuid()] then
		player:sendCancelMessage("You are already inside a rift.")
		return false
	end
	if cfg.needProtectionZone and not inProtectionZone(player) then
		player:sendCancelMessage(t.omen and "You must stand in a protection zone to open an omen arena."
			or "You must stand in a protection zone to open a rift.")
		return false
	end
	if inCombat(player) then
		player:sendCancelMessage("You cannot open a rift while you are in a fight.")
		return false
	end
	if Chaos.isMultiClient(player) then
		player:sendCancelMessage(Chaos.multiClient.msgDungeon)
		return false
	end
	if insideOther(player) then
		player:sendCancelMessage("You cannot open a rift from here.")
		return false
	end
	if player:getLevel() < t.minLevel then
		player:sendCancelMessage(t.omen and string.format("You need level %d to open an omen arena.", t.minLevel)
			or string.format("You need level %d to open a tier %d rift.", t.minLevel, t.tier))
		return false
	end
	return true
end

-- the opener and the members of the party who may come along (the others are told why not)
local function gather(player, t)
	local group = {player}
	for i, m in ipairs(groupOf(player)) do
		if i > 1 then
			local why = memberProblem(m, t)
			if why then
				player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s stays behind: %s.", m:getName(), why))
				m:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You stay behind from %s's rift: you %s.", player:getName(),
					why:gsub("^is ", "are "):gsub("^needs ", "need "):gsub("^has ", "have ")))
			else
				group[#group + 1] = m
			end
		end
	end
	return group
end

-- a free slot, built (or buildable); L or nil (message sent)
-- seconds until each running rift frees its slot (instance limits: the wait estimate)
local function slotLefts()
	local lefts, now = {}, os.time()
	for _, r in pairs(RF.runs) do
		lefts[#lefts + 1] = r.state == "running" and R.timeLeft(r, now) or C().exitDelay
	end
	return lefts
end
RF.slotLefts = slotLefts

-- a ready slot for the asked theme and band (RF.findReady), marked busy; nil when none (message sent: the wait,
-- and a place in line, told when a slot is ready again)
local function takeSlot(player, theme, band)
	local cfg = C()
	local IL = ChaosInstanceLimits
	local running = 0
	for _ in pairs(RF.runs) do
		running = running + 1
	end
	if band then
		noteDemand(theme, band)
	end
	local slot, eta
	if not (IL and IL.capped("rift", running, cfg.limits)) then
		slot, eta = RF.findReady(theme, band)
	end
	if not slot then
		local lefts = slotLefts()
		if eta then
			lefts[#lefts + 1] = eta
		end
		player:sendCancelMessage(IL and IL.busy(player, "rift", "rifts", lefts, cfg.limits)
			or (eta and "The rifts are still forming. Try again in a few seconds."
			or "Every rift is open right now. Try again in a moment."))
		addEvent(keeper, 0)
		return nil
	end
	local st = RF.slots[slot]
	st.state = "busy"
	addEvent(keeper, 1000) -- keep the pool filled
	return slot, st.L
end
RF._takeSlot = takeSlot

-- where the players of a run arrive (and come back after a lost life): the layout's arrival, an omen arena's mouth
function RF.entryOf(run)
	return run.omen and run.L.arenaStart or run.L.start
end

-- teleports the group in and registers the run's events
local function enter(run, group)
	local L = run.L
	for i, m in ipairs(group) do
		local entryPos = m:getPosition()
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), name = m:getName(), entry = entryPos, xp = {base = 0}}
		RF.runOf[m:getId()] = run
		m:registerEvent("ChaosRiftPlayerDeath")
		m:registerEvent("ChaosRiftPlayerHit")
		m:registerEvent("ChaosRiftPlayerMana")
		m:registerEvent("ChaosRiftPlayerKill")
		entryPos:sendMagicEffect(CONST_ME_TELEPORT)
		local off = ({{0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}})[i] or {0, 0}
		local at = RF.entryOf(run)
		if L.walkKeys and not RL.isFloor(L, at.x + off[1], at.y + off[2], at.z) then
			off = {0, 0}
		end
		m:teleportTo(Position(at.x + off[1], at.y + off[2], at.z))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
end

function RF.open(player, item)
	local cfg = C()
	local key = RF.readKey(item)
	if not key then
		player:sendCancelMessage("This rift key is broken.")
		return false
	end
	local t = R.tierInfo(cfg, key.tier)
	if not openerOk(player, t) then
		return false
	end
	local group = gather(player, t)
	local types = R.pickTypes(cfg, rawPool.hunt, key.tier, rand, known)
	if #types == 0 then
		player:sendCancelMessage("No monsters answer this rift. Tell a gamemaster.")
		return false
	end
	-- Rift Atlas (atlas.lua): the key user's attunements weigh the theme; the layout's size follows the tier. A ready
	-- slot of that theme and size band is taken (another theme or band when none is ready: the slot's layout decides)
	local atlasPick = R.atlasMods(player, {tier = key.tier})
	local want = R.pickTheme(cfg, rand, atlasPick and atlasPick.themeWeights)
	local slot, L = takeSlot(player, want.name, R.band(cfg, key.tier))
	if not slot then
		return false
	end
	local th = themeByName(L.theme)
	-- the sections in the order the packs fill them: the nearest to the arrival first, then spread over the map
	local rooms = RL.sectionOrder(L, rand)
	local first = table.remove(rooms, 1)

	-- the key is spent now; the marker refunds it after a crash or a restart during the run
	if not item:remove(1) then
		RF.slots[slot].state = "ready"
		player:sendCancelMessage("The key could not be used.")
		return false
	end
	setMarker(player, key)
	-- the week's world modifier (community.lua, R.hooks.world): Ember Tides adds modifiers to this run only (the refund
	-- marker above keeps the key as it was)
	R.worldKeyMods(cfg, player, key, rand)

	RF.nextId = RF.nextId + 1
	local fx = R.effects(cfg, key.mods, key.tier)
	-- Rift Atlas: the key user's atlas shapes the run (packs, time, lives, boons, guardian, reward bonuses, next key)
	local am = R.atlasMods(player, {theme = th.name, tier = key.tier})
	R.applyAtlasFx(fx, am)
	R.applyParty(cfg, fx, #group, key.tier) -- party scaling: monster health share, damage, rewards
	local plan = R.plan(cfg, key.tier, fx, #group, types, rooms, rand, {first = first, area = L.walkable})
	local baseLimit = cfg.layout.sizes[L.band] and cfg.layout.sizes[L.band][3] or cfg.timeLimit
	local run = R.newRun(cfg, os.time(), plan.total, plan.bossAt, fx, baseLimit)
	-- the Rift Time of the opener's placed charms (charms.lua)
	local charmSec = ChaosCharms and ChaosCharms.riftSeconds and ChaosCharms.riftSeconds(player) or 0
	if charmSec > 0 then
		run.limit, run.deadline = run.limit + charmSec, run.deadline + charmSec
	end
	run.id, run.slot, run.L, run.key, run.fx, run.plan = RF.nextId, slot, L, key, fx, plan
	run.bonus = R.atlasBonus(R.bonuses(cfg, key.mods, key.tier), am)
	run.atlasRun, run.atlasNote = am, R.atlasNote(am)
	run.players, run.size, run.themeName, run.rooms = {}, #group, th.name, rooms
	run.lives = R.startLives(cfg, #group, fx)
	run.livesMax, run.deaths, run.revive = run.lives, 0, {}
	run.openerGuid = player:getGuid()
	run.looks = R.lookPlan(cfg, th.name, types)
	run.typeNames = {}
	for _, e in ipairs(types) do
		run.typeNames[#run.typeNames + 1] = e.name
	end
	-- density (rift_config.lua density): the budget health of a pack monster and each kind's share of it (its XML
	-- health against the run's mean, 0.5-2)
	if plan.density then
		run.density = plan.density
		run.density.packHealth = R.packHealth(cfg, key.tier, L.walkable)
		local sum, n = 0, 0
		for _, e in ipairs(types) do
			local h = RF.poolHealth[e.name:lower()] or e.health
			if h and h > 0 then
				sum, n = sum + h, n + 1
			end
		end
		run.healthRatio = {}
		for _, e in ipairs(types) do
			local h = RF.poolHealth[e.name:lower()] or e.health
			run.healthRatio[e.name:lower()] = (n > 0 and h and h > 0) and math.max(0.5, math.min(2, h * n / sum)) or 1
		end
	end
	run.alive, run.aliveIds, run.extra, run.visited = 0, {}, {}, {}
	run.baseLimit = baseLimit
	RF.runs[slot] = run

	enter(run, group)
	local spawned = spawnPacks(run)
	-- density: the whole plan counts (the queue comes later); monsters that could not be created leave it
	run.total = run.density and math.max(0, plan.total - (run.planMissing or 0)) or spawned
	run.bossAt = math.max(1, math.ceil(run.total * cfg.bossAt / 100))
	if plan.gildedAt then
		plan.gildedAt = math.min(plan.gildedAt, math.max(1, run.total))
	end
	placeCoffer(run)
	local names = {}
	for _, m in ipairs(key.mods) do
		names[#names + 1] = R.modLabel(cfg, m) .. ": " .. R.modText(cfg, m)
	end
	say(run, string.format("Rift tier %d (%s, %s of %d x %d%s): %d monsters, the guardian waits in the %s after %d kills. %d minutes, %d shared lives. Modifiers: %s.",
		key.tier, th.name, RF.kindName(L.kind), L.side, L.side, #L.floors > 1 and ", two floors" or "", run.total,
		compass(L.start, L.bossSpawn), run.bossAt, math.floor(run.limit / 60), run.lives,
		#names > 0 and table.concat(names, "; ") or "none"))
	local partyNote = R.partyNote(fx.party, fx.party.health)
	if partyNote then
		say(run, partyNote)
	end
	if run.queue and #run.queue > 0 then
		say(run, string.format("%d more packs gather ahead of you as you advance.", #run.queue))
	end
	sendHud(run, "start")
	run.hudAt = os.time() + cfg.hudEvery
	addEvent(tick, 1000, slot, run.id)
	print(string.format("[ChaosRift] %s opened run %d: slot %d, tier %d, %s, %d player(s), %d monsters (%s), layout %s %s %dx%d seed %d",
		player:getName(), run.id, slot, key.tier, R.encodeMods(key.mods), #group, run.total,
		table.concat(run.typeNames, "/"), th.name, L.kind, L.side, L.side, L.seed))
	if run.total == 0 then
		run.killed, run.bossAt = 0, 0
		run.boss = "alive"
		spawnBoss(run)
	end
	return true
end

-- an Omen Key: the guardian arena (the arena of a ready layout; the party arrives at its mouth)
function RF.openOmen(player, item)
	local cfg = C()
	local o = cfg.omen
	local kind = RF.readOmenKey(item)
	local def = kind and R.omenKind(cfg, kind)
	if not def then
		player:sendCancelMessage("This omen key is silent.")
		return false
	end
	local t = {minLevel = o.minLevel, omen = true}
	if not openerOk(player, t) then
		return false
	end
	if not MonsterType(def.boss) then
		player:sendCancelMessage("The guardian does not answer. Tell a gamemaster.")
		return false
	end
	local group = gather(player, t)
	-- the guardian's arena of a ready layout (its theme's when one is ready, any size): the party arrives at its mouth
	local slot, L = takeSlot(player, (cfg.themes[def.theme] or cfg.themes[1]).name, nil)
	if not slot then
		return false
	end
	local th = themeByName(L.theme)
	if not item:remove(1) then
		RF.slots[slot].state = "ready"
		player:sendCancelMessage("The key could not be used.")
		return false
	end
	local key = {tier = cfg.maxTier, mods = {}, omen = def.key}
	setMarker(player, key)

	RF.nextId = RF.nextId + 1
	local fx = R.applyParty(cfg, R.effects(cfg, {}, 1), #group, nil) -- party scaling: damage, rewards
	local now = os.time()
	local run = R.newRun(cfg, now, 0, 0, fx)
	run.limit = o.timeLimit
	run.deadline = now + o.timeLimit
	run.bossDueAt = now + o.startDelay
	run.id, run.slot, run.L, run.key, run.fx = RF.nextId, slot, L, key, fx
	run.plan = {types = {}, packs = {}, total = 0, bossAt = 0, boss = def.boss, guardians = 1}
	run.omen = def.key
	run.bonus = {quantity = 0, rarity = 0, experience = 0}
	run.players, run.size, run.themeName, run.rooms = {}, #group, th.name, {}
	run.lives = R.startLives(cfg, #group, fx)
	run.livesMax, run.deaths, run.revive = run.lives, 0, {}
	run.openerGuid = player:getGuid()
	run.typeNames = {def.boss}
	RF.runs[slot] = run
	enter(run, group)
	say(run, string.format("The %s omen: %s comes in %d seconds. %d minutes, %d shared lives.", def.name, def.boss,
		o.startDelay, math.floor(run.limit / 60), run.lives))
	local partyNote = R.partyNote(fx.party, R.omenHealthMult(cfg, #group))
	if partyNote then
		say(run, partyNote)
	end
	sendHud(run, "start")
	run.hudAt = now + cfg.hudEvery
	addEvent(tick, 1000, slot, run.id)
	print(string.format("[ChaosRift] %s opened omen run %d: slot %d, %s, %d player(s)", player:getName(), run.id, slot,
		def.key, #group))
	return true
end

function RF.isInside(player)
	return player ~= nil and RF.runOf[player:getId()] ~= nil
end

Chaos.registerInstance("rift", {label = "a rift", inside = RF.isInside, at = function(pos)
	return ChaosRiftCore.slotOfPos(C(), pos) ~= nil
end, runs = function() -- /instances (instance_limits.lua)
	local out, now = {}, os.time()
	for slot, run in pairs(RF.runs) do
		local n = 0
		for _ in pairs(run.players) do
			n = n + 1
		end
		out[#out + 1] = {id = run.id, what = string.format("%s, slot %d, %s", run.omen and "omen arena" or ("tier " .. run.key.tier),
			slot, run.state), left = run.state == "running" and R.timeLeft(run, now) or nil, players = n,
			idle = ChaosInstanceLimits and ChaosInstanceLimits.idleLeft(run, C().limits, now)}
	end
	return out
end, close = function(id) -- the failure rule of a time-out: everyone out, no chest, the key is spent
	for _, run in pairs(RF.runs) do
		if run.id == id and not run.ended then
			if run.state == "running" then
				fail(run, "A gamemaster closed the rift.")
			else
				finishExit(run)
			end
			return true, "Rift " .. id .. " closed."
		end
	end
	return false, "No running rift " .. tostring(id) .. "."
end})

-- loot_config.lua rateMult: the Quantity bonus of the rift the corpse owner / chest opener is in, x the party's loot bonus
function RF.lootMult(ctx)
	local p = ctx and ctx.player
	local run = p and RF.runOf[p:getId()]
	if not run then
		return 1
	end
	return (1 + (run.bonus.quantity or 0) / 100) * (run.fx.party and run.fx.party.loot or 1) -- x the party's loot bonus
end

-- bounty.lua: a completed (paid) contract may give a tier-1 key
function RF.onBountyPaid(player, contract)
	local cfg = C()
	local p = cfg.bountyKey[contract and contract.type or "hunt"] or 0
	if player:getLevel() >= cfg.tiers[1].minLevel and math.random(100) <= p then
		RF.giveKey(player, R.rollKey(cfg, 1, rand), "Bounty bonus")
	end
end

function RF.status(player)
	local run = RF.runOf[player:getId()]
	if not run then
		return nil
	end
	local left = R.timeLeft(run, os.time())
	if run.omen then
		return string.format("Omen arena (%s): %s, %d:%02d left, guardian %s, %d / %d lives.", R.omenKind(C(), run.omen).name,
			run.state, math.floor(left / 60), left % 60, run.boss, run.lives or 0, run.livesMax or 0)
	end
	return string.format("Rift tier %d (%s): %s, %d:%02d left, %d / %d monsters, guardian %s, %d / %d lives.",
		run.key.tier, run.themeName, run.state, math.floor(left / 60), left % 60, run.killed, run.total,
		run.boss == "waiting" and ("after " .. run.bossAt .. " kills") or run.boss, run.lives or 0, run.livesMax or 0)
end

-- ======================================================================== events
local keyAction = Action()
function keyAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local now = os.time()
	if (exhaust[player:getId()] or 0) > now then
		player:sendCancelMessage("You are exhausted.")
		return true
	end
	exhaust[player:getId()] = now + C().useCooldown
	if not RF.open(player, item) then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
	end
	return true
end
keyAction:aid(C().key.actionId)
keyAction:register()

-- Omen Fragments: using them (with keyCost or more in the backpack) binds an Omen Key of a random kind
function RF.useFragments(player)
	local o = C().omen
	local have = player:getItemCount(o.fragment.id)
	if have < o.keyCost then
		player:sendCancelMessage(string.format("You need %d omen fragments to bind an Omen Key (you carry %d).", o.keyCost, have))
		return false
	end
	if not omenItemReady(o.key.id) then
		player:sendCancelMessage("Omen Keys are not installed on this server.")
		return false
	end
	if not player:removeItem(o.fragment.id, o.keyCost) then
		player:sendCancelMessage("The fragments could not be bound.")
		return false
	end
	local kind = RF.giveOmenKey(player, nil, string.format("%d omen fragments bind together", o.keyCost))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
	return kind ~= nil
end

if omenItemReady(C().omen.fragment.id) then
	local fragmentAction = Action()
	function fragmentAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		local now = os.time()
		if (exhaust[player:getId()] or 0) > now then
			player:sendCancelMessage("You are exhausted.")
			return true
		end
		exhaust[player:getId()] = now + 1
		RF.useFragments(player)
		return true
	end
	fragmentAction:id(C().omen.fragment.id)
	fragmentAction:register()
end

if omenItemReady(C().omen.key.id) then
	local omenAction = Action()
	function omenAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		local now = os.time()
		if (exhaust[player:getId()] or 0) > now then
			player:sendCancelMessage("You are exhausted.")
			return true
		end
		exhaust[player:getId()] = now + C().useCooldown
		if not RF.openOmen(player, item) then
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
		end
		return true
	end
	omenAction:id(C().omen.key.id)
	omenAction:register()
else
	print("[ChaosRift] the omen items (" .. C().omen.fragment.id .. ", " .. C().omen.key.id ..
		") are not in items.otb: run tools/install_omens.py; omens are off")
end

-- the reward chest: every finisher takes their share once
function RF.useChest(player, item)
	local slot = R.slotOfPos(C(), item:getPosition())
	local run = slot and RF.runs[slot]
	if not run or run.state ~= "success" or run.ended then
		player:sendCancelMessage("The chest is empty.")
		return true
	end
	local guid = player:getGuid()
	if not run.finishers[guid] then
		player:sendCancelMessage("This chest is not yours.")
		return true
	end
	if run.claimed[guid] then
		player:sendCancelMessage("You already took your share.")
		return true
	end
	run.claimed[guid] = true
	RF.deliver(player, run, false)
	return true
end

local chestAction = Action()
function chestAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	return RF.useChest(player, item)
end
chestAction:aid(C().chest.actionId)
chestAction:register()

-- one rift monster died: the run's bookkeeping and the per-kill effects. creature may be nil (the sweep below:
-- a monster that vanished), pos and maxHealth are then nil and the effects that need them are skipped.
-- A husk has no loot (Creature:setDropLoot(false)), and the engine then runs no death event for it (Creature::
-- dropCorpse only calls them for a monster that drops loot or has a master), so its death comes here from the
-- killer's kill event (ChaosRiftPlayerKill, the player or the master of the summon that killed it) or, for a kill
-- nobody of the run made, from the tick's sweep. Each monster is counted once (RF.dead).
RF.dead = RF.dead or {}
riftDeath = function(mid, creature, corpse)
	if RF.dead[mid] then
		return
	end
	local run = RF.monsterRun[mid]
	if not run then
		return
	end
	RF.dead[mid] = true
	addEvent(function(id) RF.dead[id] = nil end, 5000, mid)
	RF.monsterRun[mid] = nil
	if RF.husk[mid] then
		-- the other death events (bounty, bestiary) still ask RF.isHusk in this same death; gone a moment later
		addEvent(function(id) RF.husk[id] = nil end, 1000, mid)
	end
	if run.aliveIds and run.aliveIds[mid] then
		run.aliveIds[mid] = nil
		run.alive = math.max(0, (run.alive or 1) - 1)
	end
	if run.ended or run.state ~= "running" then
		return
	end
	-- Echoing Spoils: the loot is copied in the onDropLoot callback below (the engine drops loot after this event)
	if run.fx.echo > 0 and R.chance(run.fx.echo, rand) then
		RF.echo[mid] = true
	end
	if run.bossIds and run.bossIds[mid] then
		run.bossIds[mid] = nil
		local res = R.onBossKilled(run, os.time())
		if res == "success" then
			success(run, creature and creature:getPosition() or nil)
		elseif res == "twin" then
			say(run, "One guardian falls. Its twin still stands!")
			sendHud(run, "update")
		else
			fail(run, "Time is up!")
		end
		return
	end
	if run.fx.cinder > 0 and creature then
		cinderBurst(run, creature:getPosition(), creature:getMaxHealth())
	end
	-- Veilbreach and the Wrathful Guardian's thralls: extra monsters do not count towards the guardian (and never
	-- open a breach themselves)
	if run.extra and run.extra[mid] then
		run.extra[mid] = nil
		if run.thrallIds then
			run.thrallIds[mid] = nil
		end
		sendHud(run, "update")
		return
	end
	local cfMid = run.coffer and run.coffer.wave and run.coffer.wave[mid]
	if (run.fx.breach or 0) > 0 and creature and not cfMid and R.chance(run.fx.breach, rand) then
		breach(run, creature:getPosition())
	end
	-- Sealed Coffer guards do not count towards the guardian
	local cf = run.coffer
	if cf and cf.wave[mid] then
		cf.wave[mid] = nil
		cf.waveLeft = math.max(0, cf.waveLeft - 1)
		if cf.waveLeft == 0 and cf.state == "guarded" then
			openCoffer(run)
		end
		sendHud(run, "update")
		return
	end
	-- rare / legendary monsters may carry a key of the rift's tier
	local dead = ChaosTierDead and ChaosTierDead[mid]
	local tierName = dead and dead.tier or (creature and ChaosTierOf and ChaosTierOf(creature)) or "normal"
	local p = C().eliteKeyChance[tierName]
	if p and corpse and corpse.addItem and R.chance(p, rand) then
		local key = R.rollKey(C(), run.key.tier, rand)
		local item = corpse:addItem(C().key.itemId, 1)
		if item then
			RF.applyKey(item, key)
			say(run, string.format("The %s monster dropped a %s!", tierName, R.keyName(C(), key.tier)))
		end
	end
	-- rare / legendary monsters of a rift of omen.minTier or more may carry an Omen Fragment
	local o = C().omen
	local fp = run.key.tier >= o.minTier and o.eliteChance[tierName]
	if fp and corpse and corpse.addItem and omenItemReady(o.fragment.id) and R.chance(fp, rand) then
		corpse:addItem(o.fragment.id, 1)
	end
	local spawnGuardian = R.onKill(run) == "boss"
	if run.plan.gildedAt and not run.goblin and run.killed >= run.plan.gildedAt then
		spawnGoblin(run)
	end
	if spawnGuardian then
		spawnBoss(run)
	else
		sendHud(run, "update")
	end
	return
end
RF._riftDeath = riftDeath

local monsterDeath = CreatureEvent("ChaosRiftMonsterDeath")
function monsterDeath.onDeath(creature, corpse, killer, mostDamageKiller)
	riftDeath(creature:getId(), creature, corpse)
	return true
end
monsterDeath:register()

-- a husk's death: the kill event of the player who killed it (or whose summon did; registered on the run's players)
local playerKill = CreatureEvent("ChaosRiftPlayerKill")
function playerKill.onKill(player, target)
	if target and target:isMonster() and RF.husk[target:getId()] then
		riftDeath(target:getId(), target, nil)
	end
	return true
end
playerKill:register()

-- the Sealed Coffer
local cofferAction = Action()
function cofferAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	return RF.useCoffer(player, item)
end
cofferAction:aid(C().coffer.actionId)
cofferAction:register()

-- Echoing Spoils: every item in the corpse once more (after the Chaos loot layer at 1, before the auto seller at 2;
-- the engine rolls the stats of rarity items after all callbacks, so each copy gets its own). Rift Keys are not copied.
local echoCb = EventCallback
echoCb.onDropLoot = function(monster, corpse)
	local mid = monster:getId()
	if not RF.echo[mid] then
		return
	end
	RF.echo[mid] = nil
	local ok, err = pcall(function()
		if not corpse or not corpse:isContainer() then
			return
		end
		local keyAid = C().key.actionId
		local copies = {}
		for _, item in ipairs(corpse:getItems(false) or {}) do
			if item:getActionId() ~= keyAid then
				copies[#copies + 1] = item:clone()
			end
		end
		-- no effect of its own: the loot snapshot (lootfilter.lua, index 2.5) sees the copies and sends the loot rays
		for _, c in ipairs(copies) do
			corpse:addItemEx(c, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
	end)
	if not ok then
		print("[ChaosRift] echo onDropLoot failed: " .. tostring(err))
	end
end
echoCb:register(1.5)

-- damage taken by rift monsters: Warding (elemental resistance), Reflection
local reflecting = false
local monsterHealth = CreatureEvent("ChaosRiftMonsterHealth")
function monsterHealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local run = RF.monsterRun[creature:getId()]
	if not run or not attacker or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local fx = run.fx
	local p = playerOf(attacker)
	-- Warding, Ironhide, Sapping Hex (rift_core.lua R.monsterTaken)
	local elemental
	primaryDamage, secondaryDamage, elemental = R.monsterTaken(fx, {primary = primaryDamage, ptype = primaryType,
		secondary = secondaryDamage, stype = secondaryType, fromPlayer = p ~= nil}, hitTypes())
	if p and not reflecting then
		-- of the damage that lands (overkill is not reflected): Reflection all of it, Spiteglass the elemental part
		local health = creature:getHealth()
		local landed = math.min(math.abs(primaryDamage) + math.abs(secondaryDamage), health)
		local amount = math.floor(landed * (fx.reflect or 0) + math.min(elemental, health) * (fx.spite or 0))
		if amount > 0 then
			reflecting = true
			doTargetCombatHealth(creature:getId(), p, (fx.spite or 0) > 0 and COMBAT_ENERGYDAMAGE or COMBAT_PHYSICALDAMAGE,
				-amount, -amount, CONST_ME_NONE)
			reflecting = false
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
monsterHealth:register()

-- damage taken by players from rift monsters: Brutality and the tiers above the table
local function scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local run = attacker and not reflecting and RF.monsterRun[attacker:getId()]
	if run and primaryType ~= COMBAT_HEALING then
		-- a player back from a lost life: rift monsters cannot hurt it for lives.shieldSeconds
		local entry = run.players[creature:getId()]
		if entry and (entry.shieldUntil or 0) > os.time() then
			return 0, primaryType, 0, secondaryType
		end
		-- Brutality, tiers, party, Dread Guardian, density, Keen Fangs, brands, hexes (rift_core.lua R.monsterHit)
		local info
		primaryDamage, primaryType, secondaryDamage, secondaryType, info = R.monsterHit(C(), run.fx,
			{primary = primaryDamage, ptype = primaryType, secondary = secondaryDamage, stype = secondaryType,
				boss = run.bossIds and run.bossIds[attacker:getId()] or false}, hitTypes(), rand)
		if info.crit then
			packFx(creature:getPosition(), "rift_crit_wound", CONST_ME_DRAWBLOOD or CONST_ME_HITAREA)
		end
		if info.fester and CONDITION_POISON and Condition then
			-- Festering Wounds: no owner, so the ticks are not scaled again here
			local f = C().festering
			local c = Condition(CONDITION_POISON)
			c:setParameter(CONDITION_PARAM_DELAYED, true)
			c:addDamage(f.rounds, f.intervalMs, -math.max(1, math.floor(info.fester / f.rounds)))
			creature:addCondition(c)
			packFx(creature:getPosition(), "rift_fester", CONST_ME_HITBYPOISON or CONST_ME_POFF)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

local playerHit = CreatureEvent("ChaosRiftPlayerHit")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		-- Blighted Mending: less healing (spells, potions, runes; food regeneration is not a heal event)
		local run = RF.runOf[creature:getId()]
		if run and run.state == "running" and run.fx.healMult < 1 then
			primaryDamage = math.floor(primaryDamage * run.fx.healMult)
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
playerHit:register()

local playerMana = CreatureEvent("ChaosRiftPlayerMana")
function playerMana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
playerMana:register()

-- a death inside: the normal death of the engine (losses, blessings, the death window), one shared life less. With lives
-- left the character comes back at the rift's entrance at its next login (login below); the last life collapses it.
local playerDeath = CreatureEvent("ChaosRiftPlayerDeath")
function playerDeath.onDeath(player)
	local run = RF.runOf[player:getId()]
	if not run then
		return true
	end
	local left = R.loseLife(run)
	local guid = player:getGuid()
	if left and left > 0 then
		run.revive[guid] = {name = player:getName(), entry = run.players[player:getId()].entry}
		RF.revive[guid] = run
		say(run, string.format("%s has fallen: %d shared %s left.", player:getName(), left, left == 1 and "life" or "lives"))
		sendHud(run, "update") -- the fallen player too (removed next)
		removePlayer(run, player:getId(), "dead")
	elseif left == 0 then
		say(run, player:getName() .. " has fallen, and with them the rift's last life.")
		-- the dying player leaves first (no teleport inside the death event), then the rift collapses
		run.state = "failed"
		run.endText = "No lives are left!" .. (run.omen and " The arena collapses and the key is lost."
			or " The rift collapses and the key is lost.")
		say(run, run.endText)
		sendHud(run, "update")
		removePlayer(run, player:getId(), "dead")
		if not run.ended then
			finishExit(run)
		end
	else
		say(run, player:getName() .. " has fallen in the rift.")
		removePlayer(run, player:getId(), "dead") -- after the seal: normal death rules, the engine sends them to the temple
	end
	return true
end

-- the next login after a death with lives left: back at the rift's entrance
local function revive(player)
	local guid = player:getGuid()
	local run = RF.revive[guid]
	if not run then
		return false
	end
	RF.revive[guid] = nil
	local f = run.revive and run.revive[guid]
	if run.revive then
		run.revive[guid] = nil
	end
	if not f or run.ended or run.state ~= "running" or RF.runs[run.slot] ~= run then
		return false
	end
	local id = player:getId()
	run.players[id] = {id = id, guid = guid, name = player:getName(), entry = f.entry, xp = {base = 0},
		shieldUntil = os.time() + C().lives.shieldSeconds}
	RF.runOf[id] = run
	player:registerEvent("ChaosRiftPlayerDeath")
	player:registerEvent("ChaosRiftPlayerHit")
	player:registerEvent("ChaosRiftPlayerMana")
	player:registerEvent("ChaosRiftPlayerKill")
	if guid == run.openerGuid then
		-- the key's owner is back in the run: a shutdown or a crash from here on returns the key again (the death
		-- cleared the marker, so a run that ends while the owner is away returns nothing)
		setMarker(player, run.key)
	end
	local at = RF.entryOf(run)
	player:teleportTo(Position(at.x, at.y, at.z))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	say(run, string.format("%s returns to the rift (%d shared %s left).", player:getName(), run.lives,
		run.lives == 1 and "life" or "lives"))
	-- the client asks for the HUD at game start too; this one covers a client that is already loaded
	addEvent(function(cid, slot, rid)
		local p, r = Player(cid), RF.runs[slot]
		if p and r and r.id == rid and not r.ended then
			sendHud(r, "start", p)
		end
	end, 1000, id, run.slot, run.id)
	return true
end
RF._revive = revive
playerDeath:register()

local logout = CreatureEvent("ChaosRiftLogout")
function logout.onLogout(player)
	-- kicked by a closing server (no onShutdown for GAME_STATE_CLOSED): end every run as a shutdown does
	if next(RF.runs) ~= nil and serverClosing() then
		RF.interruptAll()
	end
	local run = RF.runOf[player:getId()]
	if run then
		say(run, player:getName() .. " left the rift.")
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:register()

local shutdown = GlobalEvent("ChaosRiftShutdown")
function shutdown.onShutdown()
	RF.interruptAll()
	return true
end
shutdown:register()

-- the slot pool: the first layouts are built shortly after the start (build.startDelayMs), then kept up by the keeper
local poolStart = GlobalEvent("ChaosRiftPool")
function poolStart.onStartup()
	addEvent(keeper, C().build.startDelayMs)
	return true
end
poolStart:register()

local login = CreatureEvent("ChaosRiftLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRiftLogout")
	player:registerEvent("ChaosRiftExtended")
	local back = revive(player)
	if R.slotOfPos(C(), player:getPosition()) and not RF.runOf[player:getId()] then
		local temple = player:getTown():getTemplePosition()
		player:teleportTo(temple)
	end
	if not back then -- a returning key owner carries the run's marker again (revive)
		refundMarker(player)
	end
	local list = RF.pending[player:getGuid()]
	if list then
		RF.pending[player:getGuid()] = nil
		for _, data in ipairs(list) do
			RF.deliver(player, data, true)
		end
	end
	return true
end
login:register()

-- client asks for the state (after a module reload)
local ext = CreatureEvent("ChaosRiftExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if msg and Chaos.limited and Chaos.limited(player, "rift." .. tostring(msg.action), 300) then
		return
	end
	local run = RF.runOf[player:getId()]
	if msg and msg.action == "query" and run then
		sendHud(run, "start", player)
	end
end
ext:type("extendedopcode")
ext:register()

-- experience: the cap (rift_core.lua R.capFactor) and the Experience bonus of the modifiers
local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	local run = RF.runOf[player:getId()]
	if not run or not source or not source:isMonster() or exp <= 0 then
		return exp
	end
	local base = rawExp or exp
	local okLevel, lvl = pcall(function() return source:getMonsterLevel() end)
	local bonus = okLevel and tonumber(lvl) and lvl * 0.03 or 0
	if bonus > 1 then
		base = base * bonus
	end
	base = base * (Game.getExperienceStage(player:getLevel()) or 1)
	-- magic / rare / legendary experience counts against the cap too (the tier state still exists here)
	local tier = ChaosTierOf and ChaosTierOf(source)
	if tier and ChaosTiers and ChaosTiers[tier] then
		base = base * (ChaosTiers[tier].xp or 1)
	end
	local entry = run.players[player:getId()]
	local factor = R.capFactor(C(), entry.xp, player:getLevel(), base, (os.time() - run.startTime) / 60)
	if factor < 1 and not entry.capNotice then
		entry.capNotice = true
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "The rift's experience is spent for now: kills give less until more time passes.")
	end
	return math.floor(exp * factor * (1 + (run.bonus.experience or 0) / 100))
end
xp:register(100) -- after the other experience callbacks (stages, tiers, passive tree, buffs)

-- tier-1 keys from normal level-appropriate kills (not inside a rift)
local drop = EventCallback
drop.onDropLoot = function(monster, corpse)
	local ok, err = pcall(function()
		local owner = Player(corpse:getCorpseOwner())
		if not owner or R.slotOfPos(C(), corpse:getPosition()) then
			return
		end
		local level = RF.poolLevel[typeNameOf(monster):lower()]
		if not level then
			return
		end
		local dead = ChaosTierDead and ChaosTierDead[monster:getId()]
		local tierName = dead and dead.tier or (ChaosTierOf and ChaosTierOf(monster)) or "normal"
		local chance = R.monsterKeyChance(C(), level, owner:getLevel(), tierName)
		if chance > 0 and math.random(100000) <= chance then
			local key = R.rollKey(C(), 1, rand)
			local item = corpse:addItem(C().key.itemId, 1)
			if item then
				RF.applyKey(item, key)
				owner:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("A %s drops from %s!", R.keyName(C(), 1),
					monster:getType():getNameDescription()))
			end
		end
	end)
	if not ok then
		print("[ChaosRift] onDropLoot failed: " .. tostring(err))
	end
end
drop:register(2) -- after the Chaos loot layer (1), before autoloot (3)

-- ======================================================================== commands
local function keysOf(player)
	local list = {}
	local cfg = C()
	local function scan(container)
		local okItems, items = pcall(function() return container:getItems(true) end)
		for _, it in ipairs(okItems and items or {}) do
			if it:getId() == cfg.key.itemId and it:getActionId() == cfg.key.actionId then
				list[#list + 1] = RF.readKey(it)
			end
		end
	end
	for slot = CONST_SLOT_HEAD or 1, CONST_SLOT_AMMO or 10 do
		local it = player:getSlotItem(slot)
		if it then
			if it:isContainer() then
				scan(it)
			elseif it:getId() == cfg.key.itemId and it:getActionId() == cfg.key.actionId then
				list[#list + 1] = RF.readKey(it)
			end
		end
	end
	return list
end

local function onRift(player, words, param)
	local cfg = C()
	local args = {}
	for w in (param or ""):gmatch("%S+") do
		args[#args + 1] = w:lower()
	end
	local gm = player:getGroup():getAccess()
	-- staff never give value (docs/GM_HANDBOOK.md section 2): keys, omen keys and fragments need an administrator
	if gm and (args[1] == "key" or args[1] == "omen" or args[1] == "fragments")
			and not Chaos.staffCommand(player, words, param, true) then
		return false
	end
	if gm and args[1] == "key" then
		local tier = R.clampTier(cfg, tonumber(args[2]) or 1)
		local key
		if args[3] and tonumber(args[3]) then
			key = {tier = tier, mods = R.rollMods(cfg, tonumber(args[3]), rand, tier)}
		elseif args[3] then
			key = {tier = tier, mods = R.decodeMods(cfg, args[3])}
		else
			key = R.rollKey(cfg, tier, rand)
		end
		RF.giveKey(player, key, "GM key")
		return false
	elseif gm and args[1] == "status" then
		local n = 0
		for slot, run in pairs(RF.runs) do
			n = n + 1
			local names = {}
			for _, e in pairs(run.players) do
				names[#names + 1] = e.name
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("slot %d: run %d tier %d %s, %d/%d, %ds left, players %s",
				slot, run.id, run.key.tier, run.state, run.killed, run.total, R.timeLeft(run, os.time()), table.concat(names, ", ")))
		end
		local bad = {}
		for slot, why in pairs(RF.bad) do
			bad[#bad + 1] = slot .. " (" .. why .. ")"
		end
		local states, lines = {}, {}
		for slot = 0, R.slotCount(cfg) - 1 do
			local st = RF.slots[slot] or {state = "empty"}
			states[st.state] = (states[st.state] or 0) + 1
			if st.L and st.state ~= "busy" then
				lines[#lines + 1] = string.format("%d %s %s %s %dx%d", slot, st.state, st.L.theme, st.L.kind, st.L.side, st.L.side)
			end
		end
		local parts = {}
		for k, v in pairs(states) do
			parts[#parts + 1] = v .. " " .. k
		end
		table.sort(parts)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%d rift(s) running; slots: %s; unusable: %s%s", n,
			table.concat(parts, ", "), #bad > 0 and table.concat(bad, ", ") or "none",
			RF.job and string.format("; building slot %d (%d steps so far)", RF.job.slot, RF.job.steps) or ""))
		if #lines > 0 then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "idle: " .. table.concat(lines, "; "))
		end
		return false
	elseif gm and args[1] == "fail" then
		local run = RF.runOf[player:getId()]
		if run then
			fail(run, "A gamemaster closed the rift.")
		end
		return false
	elseif gm and args[1] == "omen" then
		local kind = args[2] and (R.omenKind(cfg, tonumber(args[2]) or args[2])) or nil
		RF.giveOmenKey(player, kind and kind.key or nil, "GM omen key")
		return false
	elseif gm and args[1] == "fragments" then
		local n = math.max(1, math.min(1000, tonumber(args[2]) or cfg.omen.keyCost))
		if omenItemReady(cfg.omen.fragment.id) then
			giveStack(player, cfg.omen.fragment.id, n)
			player:sendTextMessage(MESSAGE_INFO_DESCR, n .. " omen fragments.")
		end
		return false
	elseif gm and args[1] == "lives" then
		local run = RF.runOf[player:getId()]
		if run and tonumber(args[2]) then
			run.lives = math.max(1, math.floor(tonumber(args[2])))
			sendHud(run, "update")
		end
		return false
	end
	local lines = {}
	local status = RF.status(player)
	if status then
		lines[#lines + 1] = status
	end
	local keys = keysOf(player)
	for i, k in ipairs(keys) do
		if i > 5 then
			lines[#lines + 1] = string.format("... and %d more key(s).", #keys - 5)
			break
		end
		lines[#lines + 1] = R.keyName(cfg, k.tier) .. ": " .. R.describe(cfg, k)
	end
	if #keys == 0 then
		lines[#lines + 1] = "You carry no Rift Key. Tier 1 keys drop from monsters of your level and from bounties; a sealed rift may leave a key of its tier or the next."
	end
	local o = cfg.omen
	if omenItemReady(o.fragment.id) then
		lines[#lines + 1] = string.format("Omen fragments: %d / %d (rifts of tier %d+ give them; use %d to bind an Omen Key " ..
			"that opens a guardian's arena).", player:getItemCount(o.fragment.id), o.keyCost, o.minTier, o.keyCost)
	end
	player:showTextDialog(cfg.key.itemId, table.concat(lines, "\n\n"))
	return false
end

-- staff only (players open the window from the menu)
local talk = TalkAction("/rift")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	return onRift(player, words, param)
end
talk:separator(" ")
talk:register()
-- players: the run status and the keys carried, from the menu (Info & Services, commands_ui.lua)
ChaosCommands.register("rift", function(player)
	return onRift(player, "", "")
end)
