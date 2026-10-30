-- Loadouts / Armory: save whole builds and switch between them (client game_loadouts, extended opcode 206).
-- Rules in loadouts_core.lua (pure, tests/loadouts_test.lua), numbers in loadouts_config.lua, README "Loadouts".
--
-- A loadout holds: the passive tree nodes, the Paragon allocation, the support runes socketed in the spells (the
-- runes themselves: storages per loadout), the class / vocation it was saved with, and an equipment set (item
-- references: the per-item id "chaos_iid", or the item type for plain items; never copies). The client adds its own
-- action bar profile per slot (client-side only).
--
-- One loadout is active: the live build is that loadout. A switch (load) parks the live tree, Paragon and runes into
-- the active loadout and puts the target's live; it costs nothing. Editing a tree is only possible while it is live,
-- in the passive tree window, at the normal respec prices (respec.lua): so every tree a loadout holds was paid for
-- once, and switching between them is free. Save copies the live build (read here, never sent by the client).
--
-- Switching: level cfg.minLevel+, out of combat, not inside an instance (arena, rift, trial, raid, descent, tower,
-- ascended run, siege), cfg.cooldownSeconds after the last switch; in a protection zone at once, elsewhere after a
-- cfg.castMs channel (standing still, no combat; the cast bar of game_castbar shows it).
-- Gear: equipped items, the backpack (all containers in it) and, in a protection zone, the store inbox. Items in a
-- depot or in the stash are only named ("in your stash", O316; "in your depot" for what the retired depot still holds):
-- the engine saves depot chests only after the depot was opened in that session, so taking an item out of an unopened
-- depot could duplicate it after a crash, and the stash gives items out only in a protection zone through its own
-- journal. Missing items are reported.
--
-- Crash safety: the switch writes the database first (slot 0 row: serial + 1 and an undo record), then the player
-- storages (runes, active slot, serial) and saves the player at once. A login with the database one serial ahead
-- undoes the database part (Core.recoverAction).
--
-- Protocol (JSON {action, data}; state goes through Chaos.sendChunked):
--   client -> server  open | save {slot, name?, icon?} | load {slot} | rename {slot, name, icon?} | delete {slot} |
--                     cancel
--   server -> client  state {slots = [...], limit, max, active, cooldown, castMs, inPz, level, nextUnlock, busy}
--                     result {ok, text, lines = [...]}   cast {ms, slot}   castEnd {result}
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosLoadoutsConfig then
	dofile("data/scripts/chaos/loadouts_config.lua")
end
if not ChaosLoadoutsCore then
	dofile("data/scripts/chaos/loadouts_core.lua")
end

ChaosLoadouts = ChaosLoadouts or {}
local L = ChaosLoadouts
local Core = ChaosLoadoutsCore
local cfg = ChaosLoadoutsConfig
local OPCODE = ChaosOpcodes.loadouts or 206
local TBL = Chaos.tables.loadouts or "chaos_loadouts"
local ST = cfg.storage

L.casts = L.casts or {} -- player id -> channel in progress
L.token = L.token or 0

L.SCHEMA = [[CREATE TABLE IF NOT EXISTS `chaos_loadouts` (`player_id` int(11) NOT NULL, `slot` tinyint(3) unsigned NOT NULL,
`name` varchar(32) NOT NULL DEFAULT '', `icon` varchar(16) NOT NULL DEFAULT '', `voc` int(11) NOT NULL DEFAULT 0,
`tree` text NOT NULL, `paragon` varchar(255) NOT NULL DEFAULT '', `supports` text NOT NULL, `gear` text NOT NULL,
`serial` int(11) NOT NULL DEFAULT 0, `undo` text NOT NULL, `updated` bigint(20) NOT NULL DEFAULT 0,
PRIMARY KEY (`player_id`, `slot`), CONSTRAINT `chaos_loadouts_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8]]

local function q(text)
	return db.escapeString(tostring(text or ""))
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function storage(player, key)
	local v = tonumber(player:getStorageValue(key)) or -1
	return v
end

local function send(player, action, data)
	return Chaos.send(player, OPCODE, action, data)
end

local function result(player, ok, text, lines)
	local out = {}
	for i, line in ipairs(lines or {}) do
		out[i] = Chaos.tx(player, line)
	end
	send(player, "result", {ok = ok and true or false, text = text and Chaos.tx(player, text) or "", lines = out})
end

-- ------------------------------------------------------------------------------------------------ other systems
local function treeApi()
	return ChaosPassiveTree and ChaosPassiveTree.internal
end

local function treeData()
	local T = treeApi()
	return T and T.getTree() or {root = 1, nodes = {[1] = {n = {}}}}
end

local function classKey(player)
	return ChaosPassiveTree and ChaosPassiveTree.classKey and ChaosPassiveTree.classKey(player) or nil
end

local function allowedFn()
	return ChaosClassTree and ChaosClassTree.allowed or nil
end

local function totalPoints(player)
	local T = treeApi()
	return T and T.totalPoints(player) or 0
end

local function vocationId(player)
	local v = player:getVocation()
	return v and v:getId() or 0
end

local function vocationName(id)
	local ok, name = pcall(function()
		return Vocation(id):getName()
	end)
	return ok and name or ""
end

local function supports()
	return ChaosSupports
end

-- the loadout slots the Chaos Pact (VIP) adds while active (pact_perks.lua; 0 without it)
local function pactSlots(player)
	local PP = ChaosPactPerks
	if not (PP and PP.loadoutBonus) then
		return 0
	end
	local ok, n = pcall(PP.loadoutBonus, player)
	return ok and tonumber(n) or 0
end

local function maxSpellId()
	local S = supports()
	return S and S.config and S.config.maxSpellId or 499
end

-- ------------------------------------------------------------------------------------------------ rows
local COLS = {{"slot", "n"}, {"name", "s"}, {"icon", "s"}, {"voc", "n"}, {"tree", "s"}, {"paragon", "s"}, {"supports", "s"},
	{"gear", "s"}, {"serial", "n"}, {"undo", "s"}, {"updated", "n"}}

-- slot -> row (slot 0 = the character's armory state: switch serial and undo record)
function L.rows(guid)
	local out = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `slot`, `name`, `icon`, `voc`, `tree`, `paragon`, `supports`, `gear`, " ..
			"`serial`, `undo`, `updated` FROM `%s` WHERE `player_id` = %d", TBL, guid), COLS)) do
		out[r.slot] = r
	end
	return out
end

local function writeRow(guid, slot, r)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `slot`, `name`, `icon`, `voc`, `tree`, `paragon`, `supports`, `gear`, " ..
		"`serial`, `undo`, `updated`) VALUES (%d, %d, %s, %s, %d, %s, %s, %s, %s, %d, %s, %d) ON DUPLICATE KEY UPDATE " ..
		"`name` = VALUES(`name`), `icon` = VALUES(`icon`), `voc` = VALUES(`voc`), `tree` = VALUES(`tree`), " ..
		"`paragon` = VALUES(`paragon`), `supports` = VALUES(`supports`), `gear` = VALUES(`gear`), `serial` = VALUES(`serial`), " ..
		"`undo` = VALUES(`undo`), `updated` = VALUES(`updated`)", TBL, guid, slot, q(r.name), q(r.icon), tonumber(r.voc) or 0,
		q(r.tree), q(r.paragon), q(r.supports), q(r.gear), tonumber(r.serial) or 0, q(r.undo), tonumber(r.updated) or os.time()))
end
L.writeRow = writeRow

local function deleteRow(guid, slot)
	db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `slot` = %d", TBL, guid, slot))
end

local function writeState(guid, serial, undo)
	writeRow(guid, 0, {name = "", icon = "", voc = 0, tree = "", paragon = "", supports = "", gear = "", serial = serial,
		undo = undo or "", updated = os.time()})
end

-- ------------------------------------------------------------------------------------------------ live build
local function liveTree(player)
	local T = treeApi()
	if not T then
		return {}, nil
	end
	local active = T.loadPresets(player:getGuid())[1]
	return active and active.nodes or {}, active
end

local function setLiveTree(player, ids, presetRow, masteries)
	local T = treeApi()
	if not T then
		return
	end
	local active = presetRow or T.loadPresets(player:getGuid())[1]
	local copy = {}
	for i, id in ipairs(ids) do
		copy[i] = id
	end
	T.savePreset(player:getGuid(), active and active.preset or 1, active and active.name or "Preset 1", copy, masteries)
end

local function liveParagon(player)
	local P = ChaosParagon
	local out = {}
	if P and P.allocation then
		for key, n in pairs(P.allocation(player)) do
			out[key] = n
		end
	end
	return out
end

local function setLiveParagon(player, alloc)
	local P = ChaosParagon
	if P and P.save then
		P.save(player:getGuid(), alloc)
		P.cache[player:getId()] = alloc
	end
end

local function paragonCheck(player, alloc)
	local P = ChaosParagon
	if not (P and P.defs) then
		return {}, 0, false
	end
	-- the categories and the masteries (O146); the points are the level's plus the exchanged tree points
	return Core.validateParagon(alloc, P.allDefs or P.defs, P.pointsOf and P.pointsOf(player) or P.totalPoints(player:getLevel()))
end

-- ------------------------------------------------------------------------------------------------ support runes
local function mirrorKey(slot, spellId, socket)
	return Core.mirrorKey(slot, spellId, socket, cfg, maxSpellId())
end

local function liveLayout(player)
	local S = supports()
	local out = {}
	if not S then
		return out
	end
	for spellId = 0, maxSpellId() do
		local sock = S.read(player, spellId)
		if sock and (sock.runes[1] > 0 or sock.runes[2] > 0 or sock.runes[3] > 0) then
			out[spellId] = {sock.runes[1], sock.runes[2], sock.runes[3]}
		end
	end
	return out
end
L.liveLayout = liveLayout

local function mirrorLayout(player, slot)
	local out = {}
	if slot < 1 or slot > cfg.runeMirrorSlots then
		return out
	end
	for spellId = 0, maxSpellId() do
		local a, b, c = storage(player, mirrorKey(slot, spellId, 1)), storage(player, mirrorKey(slot, spellId, 2)),
			storage(player, mirrorKey(slot, spellId, 3))
		if a > 0 or b > 0 or c > 0 then
			out[spellId] = {math.max(0, a), math.max(0, b), math.max(0, c)}
		end
	end
	return out
end
L.mirrorLayout = mirrorLayout

local function setMirror(player, slot, layout)
	for spellId, sockets in pairs(mirrorLayout(player, slot)) do
		for socket = 1, 3 do
			if sockets[socket] > 0 then
				player:setStorageValue(mirrorKey(slot, spellId, socket), -1)
			end
		end
	end
	for spellId, sockets in pairs(layout or {}) do
		for socket = 1, 3 do
			local id = tonumber(sockets[socket]) or 0
			if id > 0 then
				player:setStorageValue(mirrorKey(slot, spellId, socket), id)
			end
		end
	end
end

local function setLive(player, old, new)
	local S = supports()
	if not S then
		return
	end
	for spellId, sockets in pairs(old or {}) do
		for socket = 1, 3 do
			if sockets[socket] > 0 then
				S.setRune(player, spellId, socket, 0)
			end
		end
	end
	for spellId, sockets in pairs(new or {}) do
		for socket = 1, 3 do
			if (sockets[socket] or 0) > 0 then
				S.setRune(player, spellId, socket, sockets[socket])
			end
		end
	end
end

local function spellExists(spellId)
	local S = supports()
	return S ~= nil and S.spellInfo(spellId) ~= nil
end

local function isRune(id)
	local S = supports()
	return S ~= nil and S.isRune(id)
end

local function runeSummary(layout)
	local S = supports()
	local spells = {}
	for spellId, sockets in pairs(layout or {}) do
		local info = S and S.spellInfo(spellId)
		local runes = {}
		for socket = 1, 3 do
			local id = tonumber(sockets[socket]) or 0
			if id > 0 then
				runes[#runes + 1] = S and S.isRune(id) and S.runeName(id) or "?"
			end
		end
		if #runes > 0 then
			spells[#spells + 1] = {id = spellId, name = info and info.name or ("spell " .. spellId), runes = runes}
		end
	end
	table.sort(spells, function(a, b)
		return a.id < b.id
	end)
	return {count = Core.runeCount(layout), spells = spells}
end

local function giveRune(player, id)
	if ChaosGems and ChaosGems.give then
		return ChaosGems.give(player, id, 1)
	end
	player:addItem(id, 1)
end

-- ------------------------------------------------------------------------------------------------ gear
local function iidOf(item)
	local ok, v = pcall(function()
		return item:getCustomAttribute("chaos_iid")
	end)
	return Core.iidString(ok and v or 0)
end

local function normalId(id)
	local ok, de = pcall(function()
		return ItemType(id):getTransformDeEquipId()
	end)
	if ok and tonumber(de) and de > 0 then
		return de
	end
	return id
end

local function clientId(id)
	local ok, cid = pcall(function()
		return ItemType(id):getClientId()
	end)
	return ok and cid or 0
end

local function movable(item)
	if item:isContainer() then
		return false
	end
	if ITEM_ATTRIBUTE_UNIQUEID and item:hasAttribute(ITEM_ATTRIBUTE_UNIQUEID) then
		return false
	end
	return true
end

local function info(item, where, slot)
	return {ref = item, id = normalId(item:getId()), iid = iidOf(item), name = item:getName(), where = where, slot = slot}
end

local function equippedItems(player)
	local out = {}
	for _, slot in ipairs(cfg.gearSlots) do
		local item = player:getSlotItem(slot)
		if item then
			out[slot] = info(item, "slot", slot)
		end
	end
	return out
end

local function containerItems(container, where, out)
	local ok, items = pcall(function()
		return container:getItems(true)
	end)
	for _, item in ipairs(ok and items or {}) do
		if movable(item) then
			out[#out + 1] = info(item, where)
		end
	end
	return out
end

local function poolItems(player, withInbox)
	local out = {}
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if bp and bp:isContainer() then
		containerItems(bp, "backpack", out)
	end
	if withInbox then
		local inbox = player:getInbox()
		if inbox then
			containerItems(inbox, "inbox", out)
		end
	end
	return out
end

-- {town name = {items}} of the depot chests (only to name where a missing item is)
local function depotItems(player)
	local out = {}
	local okT, towns = pcall(Game.getTowns)
	for _, town in ipairs(okT and towns or {}) do
		local ok, chest = pcall(function()
			return player:getDepotChest(town:getId(), false)
		end)
		if ok and chest then
			out[#out + 1] = {town = town:getName(), items = containerItems(chest, "depot", {})}
		end
	end
	return out
end

local function depotWhere(depots, want)
	for _, d in ipairs(depots) do
		for _, item in ipairs(d.items) do
			if Core.matches(want, item) then
				return "in your depot (" .. d.town .. ")"
			end
		end
	end
	return nil
end

-- the stash holds the item (by item id): "in your stash" (O316: the stash is the storage)
local function stashWhere(player, want)
	local S = ChaosStash
	if not (S and S.staffFind and want and tonumber(want.id)) then
		return nil
	end
	local ok, plain, rows = pcall(S.staffFind, player:getGuid(), want.id)
	if ok and ((plain and plain.count or 0) > 0 or (rows and #rows > 0)) then
		return "in your stash"
	end
	return nil
end

-- the set of what is equipped now: {[slot] = {id, iid, name} | {empty = true}}
local function snapshotGear(player)
	local set = {}
	for _, slot in ipairs(cfg.gearSlots) do
		local item = player:getSlotItem(slot)
		if item then
			set[slot] = {id = normalId(item:getId()), iid = iidOf(item), name = item:getName()}
		else
			set[slot] = {empty = true}
		end
	end
	return set
end

-- move an equipped item into the backpack or a container in it (never merged into a stack: the reference stays valid)
local function stowAway(player, item)
	local flags = FLAG_IGNOREAUTOSTACK or 0
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bp or not bp:isContainer() then
		return false
	end
	if item:moveTo(bp, flags) then
		return true
	end
	local ok, items = pcall(function()
		return bp:getItems(true)
	end)
	for _, c in ipairs(ok and items or {}) do
		if c:isContainer() and item:moveTo(c, flags) then
			return true
		end
	end
	return false
end

-- equip a set: returns {equipped = n, lines = {texts}, missing = n}
local function applyGear(player, set, withInbox)
	local report = {equipped = 0, missing = 0, lines = {}}
	if not next(set or {}) then
		return report
	end
	local equipped = equippedItems(player)
	local steps = Core.planGear(set, equipped, poolItems(player, withInbox), cfg.gearSlots)
	local depots
	-- phase 1: empty every slot that changes (a two-handed weapon needs both hands free)
	local blocked = {}
	for _, step in ipairs(steps) do
		local cur = equipped[step.slot]
		if (step.action == "equip" or step.action == "clear") and cur then
			if not stowAway(player, cur.ref) then
				blocked[step.slot] = true
				report.lines[#report.lines + 1] = string.format("No room in your backpack for %s: it stays equipped.", cur.name)
			end
		end
	end
	local bySlot = {}
	for _, step in ipairs(steps) do
		bySlot[step.slot] = step
	end
	local function place(src, slot)
		local copy = src:clone()
		return copy and player:addItemEx(copy, false, slot, 0)
	end
	-- phase 2: put the set's items on (a copy is placed, then the item itself is removed: one item, moved)
	for _, step in ipairs(steps) do
		if step.action == "equip" and not blocked[step.slot] then
			local src = step.item.ref
			local rv = place(src, step.slot)
			-- a two-handed weapon the set does not want (its own item for that hand is missing) blocks the other hand:
			-- it goes into the backpack and the hand is tried again
			local other = (step.slot == CONST_SLOT_LEFT and CONST_SLOT_RIGHT) or (step.slot == CONST_SLOT_RIGHT and CONST_SLOT_LEFT) or nil
			local otherStep = other and bySlot[other]
			local blocker = other and player:getSlotItem(other)
			if rv ~= RETURNVALUE_NOERROR and blocker and otherStep and otherStep.action == "missing" and stowAway(player, blocker) then
				rv = place(src, step.slot)
			end
			if rv == RETURNVALUE_NOERROR then
				src:remove()
				report.equipped = report.equipped + 1
			else
				local why = Game.getReturnMessage and Game.getReturnMessage(rv) or "it cannot be worn now"
				report.lines[#report.lines + 1] = string.format("%s was not equipped: %s", step.item.name, tostring(why))
			end
		elseif step.action == "missing" then
			depots = depots or depotItems(player)
			report.missing = report.missing + 1
			local where = depotWhere(depots, step.want) or stashWhere(player, step.want) or (not withInbox and "not carried (the store inbox is only searched in a protection zone)") or "not found"
			report.lines[#report.lines + 1] = string.format("%s: %s.", step.want.name or "?", where)
		end
	end
	return report
end

-- ------------------------------------------------------------------------------------------------ state
local function tile(player)
	return Tile(player:getPosition())
end

local function inPz(player)
	local t = tile(player)
	return t ~= nil and t:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	if Chaos.inCombat then
		return Chaos.inCombat(player)
	end
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

-- the instance the player is in (text) or nil
local BUSY = {
	{"ChaosArena", "the arena"}, {"ChaosRift", "a rift"}, {"ChaosDescent", "the Ember Descent"}, {"ChaosRaid", "a raid"},
	{"ChaosAscended", "an Ascended Omen"}, {"ChaosSiege", "a siege"}, {"ChaosTowerRun", "the Infinity Tower"}
}
function L.busy(player)
	for _, b in ipairs(BUSY) do
		local sys = rawget(_G, b[1])
		if type(sys) == "table" and type(sys.isInside) == "function" then
			local ok, inside = pcall(sys.isInside, player)
			if ok and inside then
				return b[2]
			end
		end
	end
	if ChaosTrials and ChaosTrials.runs and ChaosTrials.runs[player:getId()] then
		return "a Vocation Trial"
	end
	return nil
end

local function activeSlot(player)
	return math.max(0, storage(player, ST.active))
end

local function armOf(player, rows)
	local slots = {}
	for slot = 1, cfg.maxSlots do
		if rows[slot] then
			slots[slot] = {runes = Core.runeCount(mirrorLayout(player, slot))}
		end
	end
	local active = activeSlot(player)
	local live = {nodes = #liveTree(player), paragon = Core.paragonSpent(liveParagon(player)), runes = Core.runeCount(liveLayout(player))}
	return {active = active, limit = Core.slotLimit(player:getLevel(), nil, pactSlots(player)), slots = slots, live = live}
end

-- one slot for the window
local function slotView(player, slot, row, ctx)
	local view = {slot = slot, locked = slot > ctx.limit, active = slot == ctx.active}
	if not row then
		view.empty = true
		return view
	end
	view.name, view.icon, view.updated = row.name, Core.cleanIcon(row.icon), row.updated
	local nodes, paragon, layout, warnings = {}, {}, {}, {}
	if view.active then
		nodes, paragon, layout = ctx.liveNodes, ctx.liveParagon, ctx.liveRunes
	else
		local kept, removed = Core.validateTree(ctx.tree, Core.parseNodes(row.tree),
			{classKey = ctx.classKey, points = ctx.points, allowed = allowedFn()})
		local par, parRemoved = paragonCheck(player, Core.decodeParagon(row.paragon))
		nodes, paragon, layout = kept, par, mirrorLayout(player, slot)
		local text = Core.refundText(removed, parRemoved, Chaos.lang(player))
		if text then
			warnings[#warnings + 1] = Chaos.t(player, "When loaded: %s", text)
		end
		local _, giveBack, dropped = Core.planRestore(layout, spellExists, isRune)
		if #giveBack + #dropped > 0 then
			warnings[#warnings + 1] = Chaos.t(player, #giveBack + #dropped == 1
				and "%d support rune of spells that left the game returns to you when loaded."
				or "%d support runes of spells that left the game return to you when loaded.", #giveBack + #dropped)
		end
	end
	if (row.voc or 0) > 0 and row.voc ~= ctx.voc then
		warnings[#warnings + 1] = Chaos.t(player, "Saved as %s.", vocationName(row.voc))
	end
	view.voc = vocationName(row.voc)
	view.cls = ChaosClasses and ChaosClasses.classKey and ChaosClasses.classKey(row.voc) or ""
	view.points, view.pointsTotal = #nodes, ctx.points
	view.keystones = Core.keystones(ctx.tree, nodes, ctx.variantKey)
	view.paragon = Core.paragonSpent(paragon)
	view.supports = runeSummary(layout)
	local steps = Core.planGear(Core.decodeGear(row.gear), ctx.equipped, ctx.pool, cfg.gearSlots)
	local summary = Core.gearSummary(steps)
	for _, m in ipairs(summary.missing) do
		ctx.depots = ctx.depots or depotItems(player)
		local want
		for _, s in ipairs(steps) do
			if s.slot == m.slot then
				want = s.want
			end
		end
		m.where = depotWhere(ctx.depots, want) or stashWhere(player, want) or "missing"
	end
	view.gear = summary
	view.warnings = warnings
	return view
end

function L.state(player)
	local guid = player:getGuid()
	local rows = L.rows(guid)
	local level = player:getLevel()
	local pz = inPz(player)
	local ctx = {
		limit = Core.slotLimit(level, nil, pactSlots(player)), active = activeSlot(player), tree = treeData(), classKey = classKey(player),
		variantKey = ChaosPassiveTree and ChaosPassiveTree.vocationKey and ChaosPassiveTree.vocationKey(player) or nil,
		points = totalPoints(player), voc = vocationId(player), liveNodes = liveTree(player), liveParagon = liveParagon(player),
		liveRunes = liveLayout(player), equipped = equippedItems(player), pool = poolItems(player, pz or not cfg.inboxOnlyInPz)
	}
	local slots = {}
	for slot = 1, cfg.maxSlots do
		slots[#slots + 1] = slotView(player, slot, rows[slot], ctx)
	end
	return {
		slots = slots, limit = ctx.limit, max = cfg.maxSlots, active = ctx.active, level = level, minLevel = cfg.minLevel,
		cooldown = Core.cooldownLeft(storage(player, ST.lastSwitch), os.time()), cooldownSeconds = cfg.cooldownSeconds,
		castMs = cfg.castMs, inPz = pz, nextUnlock = Core.nextUnlock(level), busy = L.busy(player),
		casting = L.casts[player:getId()] ~= nil, nameMax = cfg.nameMax, icons = cfg.icons, baseSlots = cfg.baseSlots,
		unlockLevels = (function()
			local out = {}
			for i, e in ipairs(cfg.earned or {}) do
				out[i] = e.level
			end
			return out
		end)(),
		live = {points = #ctx.liveNodes, pointsTotal = ctx.points, paragon = Core.paragonSpent(ctx.liveParagon),
			runes = Core.runeCount(ctx.liveRunes)}
	}
end

function L.sendState(player)
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = L.state(player)}))
end

-- ------------------------------------------------------------------------------------------------ the switch
local function refreshOthers(player)
	if ChaosPassiveTree and ChaosPassiveTree.apply then
		ChaosPassiveTree.apply(player)
	end
	local T = treeApi()
	if T then
		T.sendNodes(player)
		T.sendPoints(player)
	end
	if ChaosParagon and ChaosParagon.sendState then
		ChaosParagon.sendState(player)
	end
	local S = supports()
	if S and S.refreshActive then
		S.refreshActive(player)
		if S.sendBar then
			S.sendBar(player)
		end
	end
end

-- do the switch now (the checks were made; made again here for a channel that just ended)
function L.switch(player, target)
	local guid = player:getGuid()
	local rows = L.rows(guid)
	local plan, why = Core.planLoad(armOf(player, rows), target)
	if not plan then
		return false, why == "locked" and Core.lockedText(player:getLevel()) or why
	end
	local targetRow = rows[target]
	local liveIds, presetRow = liveTree(player)
	local liveMasteries = presetRow and presetRow.masteries or {}
	local livePar = liveParagon(player)
	local liveRunes = liveLayout(player)
	local vocId = vocationId(player)

	-- the target, against the tree and the character now (free refunds of what the game took away)
	local kept, removed = Core.validateTree(treeData(), Core.parseNodes(targetRow.tree),
		{classKey = classKey(player), points = totalPoints(player), allowed = allowedFn()})
	local keptMasteries = Core.cleanMasteries(treeData(), kept, Core.parseMasteries(targetRow.tree))
	local par, parRemoved = paragonCheck(player, Core.decodeParagon(targetRow.paragon))

	-- database first, with the undo record
	local state = rows[0]
	local serial = math.max(math.max(0, storage(player, ST.serial)), state and state.serial or 0) + 1
	local parked = plan.park and rows[plan.park]
	local undo = {
		live = {nodes = Core.formatNodes(liveIds, liveMasteries), preset = presetRow and presetRow.preset or 1, name = presetRow and presetRow.name or "Preset 1"},
		paragon = Core.encodeParagon(livePar), slot = plan.park,
		row = parked and {tree = parked.tree, paragon = parked.paragon, supports = parked.supports, voc = parked.voc} or nil,
		target = target, targetTree = targetRow.tree, targetParagon = targetRow.paragon
	}
	writeState(guid, serial, json.encode(undo))
	if parked then
		parked.tree, parked.paragon, parked.voc = Core.formatNodes(liveIds, liveMasteries), Core.encodeParagon(livePar), vocId
		parked.supports, parked.updated = Core.encodeRunes(liveRunes), os.time()
		writeRow(guid, plan.park, parked)
	end
	setLiveTree(player, kept, presetRow, keptMasteries)
	setLiveParagon(player, par)
	targetRow.tree, targetRow.paragon = Core.formatNodes(kept, keptMasteries), Core.encodeParagon(par)
	writeRow(guid, target, targetRow)

	-- then the storages: the runes move between the live sockets and the loadouts' own storages
	local incoming = mirrorLayout(player, target)
	local keep, giveBack, dropped = Core.planRestore(incoming, spellExists, isRune)
	if plan.park then
		setMirror(player, plan.park, liveRunes)
	end
	setLive(player, liveRunes, keep)
	setMirror(player, target, {})
	for _, g in ipairs(giveBack) do
		giveRune(player, g.rune)
	end
	player:setStorageValue(ST.active, target)
	player:setStorageValue(ST.serial, serial)
	player:setStorageValue(ST.lastSwitch, os.time())

	refreshOthers(player)
	local gear = applyGear(player, Core.decodeGear(targetRow.gear), inPz(player) or not cfg.inboxOnlyInPz)
	pcall(function()
		player:save()
	end)

	local lines = {}
	local refund = Core.refundText(removed, parRemoved, Chaos.lang(player))
	if refund then
		lines[#lines + 1] = refund
	end
	if #giveBack + #dropped > 0 then
		lines[#lines + 1] = ChaosI18n.msg(#giveBack == 1 and "%d support rune of spells that left the game is back to you."
			or "%d support runes of spells that left the game are back to you.", #giveBack)
	end
	for _, line in ipairs(gear.lines) do
		lines[#lines + 1] = line
	end
	local text = ChaosI18n.msg(gear.equipped == 1 and "Loadout %s is active: %d passive nodes, %d support runes, %d item equipped."
		or "Loadout %s is active: %d passive nodes, %d support runes, %d items equipped.", targetRow.name,
		#kept, Core.runeCount(keep), gear.equipped)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.tx(player, text))
	for _, line in ipairs(lines) do
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_EVENT_ADVANCE, Chaos.tx(player, line))
	end
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
	return true, text, lines
end

-- ------------------------------------------------------------------------------------------------ the channel
local function castbar(player, action, data)
	if ChaosOpcodes.castbar then
		Chaos.send(player, ChaosOpcodes.castbar, action, data)
	end
end

local function endCast(player, cast, res, text)
	L.casts[player:getId()] = nil
	castbar(player, "end", {s = cast.serial, r = res, t = text and Chaos.tx(player, text) or nil})
	send(player, "castEnd", {result = res})
	if text then
		player:sendCancelMessage(Chaos.tx(player, text))
		result(player, false, text)
	end
end

local function poll(pid, token)
	local cast = L.casts[pid]
	if not cast or cast.token ~= token then
		return
	end
	local player = Player(pid)
	if not player then
		L.casts[pid] = nil
		return
	end
	local step = Core.castStep(cast, nowMs(), player:getPosition(), inCombat(player))
	if step == "wait" then
		addEvent(poll, cfg.pollMs, pid, token)
		return
	end
	if step == "moved" or step == "hit" then
		endCast(player, cast, step == "moved" and "moved" or "cancel", Core.msg(nil, step))
		return
	end
	L.casts[pid] = nil
	castbar(player, "end", {s = cast.serial, r = "done"})
	send(player, "castEnd", {result = "done"})
	local ok, text, lines = L.switch(player, cast.target)
	result(player, ok, text, lines)
	L.sendState(player)
end

-- checks, then the switch at once (protection zone) or a channel
function L.load(player, target)
	local rows = L.rows(player:getGuid())
	local plan, why = Core.planLoad(armOf(player, rows), target)
	if not plan then
		return false, why == "locked" and Core.lockedText(player:getLevel()) or why
	end
	local mode, reason = Core.switchGate({
		level = player:getLevel(), inCombat = inCombat(player), busy = L.busy(player), inPz = inPz(player),
		cooldownLeft = Core.cooldownLeft(storage(player, ST.lastSwitch), os.time()), casting = L.casts[player:getId()] ~= nil
	})
	if not mode then
		return false, reason
	end
	if mode == "instant" then
		return L.switch(player, target)
	end
	if ChaosCasting and ChaosCasting.interrupt then
		ChaosCasting.interrupt(player, "spell")
	end
	L.token = L.token + 1
	local pos = player:getPosition()
	local cast = {token = L.token, target = target, pos = {x = pos.x, y = pos.y, z = pos.z}, endMs = nowMs() + cfg.castMs,
		serial = cfg.castSerialBase + L.token}
	L.casts[player:getId()] = cast
	castbar(player, "start", {s = cast.serial, n = Chaos.t(player, "Switching loadout"), ms = cfg.castMs, id = 0})
	send(player, "cast", {ms = cfg.castMs, slot = target})
	player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "Switching loadout... stand still."))
	addEvent(poll, cfg.pollMs, player:getId(), cast.token)
	return true, nil
end

-- ------------------------------------------------------------------------------------------------ save / rename / delete
function L.save(player, slot, name, icon)
	local guid = player:getGuid()
	local rows = L.rows(guid)
	local arm = armOf(player, rows)
	local plan, why = Core.planSave(arm, slot)
	if not plan then
		return false, why == "locked" and Core.lockedText(player:getLevel()) or why
	end
	if player:getLevel() < cfg.minLevel then
		return false, Core.msg(nil, "lowLevel", cfg.minLevel)
	end
	local old = rows[slot]
	local liveIds, liveRow = liveTree(player)
	local liveRunes = liveLayout(player)
	local set = snapshotGear(player)
	local row = {
		name = Core.cleanName(name or (old and old.name), slot), icon = Core.cleanIcon(icon or (old and old.icon)),
		voc = vocationId(player), tree = Core.formatNodes(liveIds, liveRow and liveRow.masteries), paragon = Core.encodeParagon(liveParagon(player)),
		-- a copy keeps the slot's own runes (runes are never duplicated); the active loadout's runes are the live ones
		supports = plan.copy and (old and old.supports or "") or Core.encodeRunes(liveRunes),
		gear = Core.encodeGear(set, cfg.gearSlots), serial = 0, undo = "", updated = os.time()
	}
	writeRow(guid, slot, row)
	if plan.activate then
		player:setStorageValue(ST.active, slot)
	end
	local items = 0
	for _, w in pairs(set) do
		if not w.empty then
			items = items + 1
		end
	end
	local text = ChaosI18n.msg(items == 1 and "Saved %s: %d passive nodes, %d Paragon points, %d item in the set."
		or "Saved %s: %d passive nodes, %d Paragon points, %d items in the set.", row.name, #liveIds,
		Core.paragonSpent(liveParagon(player)), items)
	local lines = {}
	if plan.copy and Core.runeCount(liveRunes) > 0 then
		lines[#lines + 1] = ChaosI18n.msg("Support runes stay with the loadout they are socketed in: this copy keeps its own.")
	end
	if plan.activate then
		lines[#lines + 1] = "This loadout is now active: your current build is saved in it."
	end
	return true, text, lines
end

function L.rename(player, slot, name, icon)
	local rows = L.rows(player:getGuid())
	local row = rows[slot]
	if Core.slotState(slot, cfg.maxSlots) ~= "ok" then
		return false, Core.msg(nil, "noSlot")
	end
	if not row then
		return false, Core.msg(nil, "empty")
	end
	row.name = Core.cleanName(name or row.name, slot)
	row.icon = Core.cleanIcon(icon or row.icon)
	writeRow(player:getGuid(), slot, row)
	return true, ChaosI18n.msg("Renamed to %s.", row.name)
end

function L.delete(player, slot)
	local guid = player:getGuid()
	local rows = L.rows(guid)
	local plan, why = Core.planDelete(armOf(player, rows), slot)
	if not plan then
		return false, why
	end
	local name = rows[slot].name
	deleteRow(guid, slot)
	setMirror(player, slot, {})
	if plan.deactivate then
		player:setStorageValue(ST.active, 0)
	end
	return true, ChaosI18n.msg("Loadout %s deleted.%s", name, plan.deactivate and ChaosI18n.msg(" Your current build stays as it is.") or "")
end

-- ------------------------------------------------------------------------------------------------ login: crash recovery
-- the passive tree's free refund of reworked nodes (passivetree.lua refundReworked, passivetree_config.lua reworked):
-- every saved loadout tree loses the nodes of `drop` (a set of ids) and the ones only connected through them.
-- Returns how many nodes were taken out.
function L.dropNodes(player, drop)
	local PC = ChaosPassiveTreeCore
	if not PC or not PC.dropNodes then
		return 0
	end
	local guid, tree, total = player:getGuid(), treeData(), 0
	for slot, r in pairs(L.rows(guid)) do
		if slot > 0 and (r.tree or "") ~= "" then
			local kept, removed = PC.dropNodes(tree, Core.parseNodes(r.tree), drop)
			if #removed > 0 then
				r.tree = Core.formatNodes(kept, Core.parseMasteries(r.tree))
				writeRow(guid, slot, r)
				total = total + #removed
			end
		end
	end
	return total
end

function L.recover(player)
	local guid = player:getGuid()
	local rows = L.rows(guid)
	local state = rows[0]
	local st = math.max(0, storage(player, ST.serial))
	local action = Core.recoverAction(st, state and state.serial or 0)
	if action == "rollback" then
		local ok, undo = pcall(json.decode, state.undo or "")
		if ok and type(undo) == "table" and type(undo.live) == "table" then
			local T = treeApi()
			if T then
				T.savePreset(guid, tonumber(undo.live.preset) or 1, tostring(undo.live.name or "Preset 1"), Core.parseNodes(undo.live.nodes),
					Core.parseMasteries(undo.live.nodes))
			end
			setLiveParagon(player, Core.decodeParagon(undo.paragon))
			local slot = tonumber(undo.slot)
			if slot and rows[slot] then
				if type(undo.row) == "table" then
					local r = rows[slot]
					r.tree, r.paragon, r.supports, r.voc = undo.row.tree or "", undo.row.paragon or "", undo.row.supports or "",
						tonumber(undo.row.voc) or 0
					writeRow(guid, slot, r)
				end
			end
			local target = tonumber(undo.target)
			if target and rows[target] then
				rows[target].tree, rows[target].paragon = undo.targetTree or rows[target].tree, undo.targetParagon or rows[target].paragon
				writeRow(guid, target, rows[target])
			end
		end
		writeState(guid, st, "")
		print(string.format("[Chaos loadouts] %s: the last switch did not reach the player save; undone", player:getName()))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your last loadout switch was interrupted by a server restart and was undone."))
		if ChaosPassiveTree and ChaosPassiveTree.apply then
			ChaosPassiveTree.apply(player)
		end
	elseif action == "adopt" then
		local serial = math.max(st, state and state.serial or 0)
		player:setStorageValue(ST.serial, serial)
		writeState(guid, serial, "")
	end
	local active = activeSlot(player)
	if active > 0 and not rows[active] then
		player:setStorageValue(ST.active, 0)
	end
end

-- ------------------------------------------------------------------------------------------------ protocol
local RATE = cfg.rate

local function allowed(player, key)
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "loadouts." .. key, RATE[key] or 1000)
end

local function slotOf(data)
	return Chaos.toInt(type(data) == "table" and data.slot or data, 1, cfg.maxSlots)
end

local actions = {}

actions.open = function(player)
	L.sendState(player)
end

actions.save = function(player, data)
	local slot = slotOf(data)
	if not slot then
		return result(player, false, Core.msg(nil, "noSlot"))
	end
	local ok, text, lines = L.save(player, slot, type(data) == "table" and data.name or nil, type(data) == "table" and data.icon or nil)
	result(player, ok, text, lines)
	L.sendState(player)
end

actions.load = function(player, data)
	local slot = slotOf(data)
	if not slot then
		return result(player, false, Core.msg(nil, "noSlot"))
	end
	local ok, text, lines = L.load(player, slot)
	if not ok or text then
		result(player, ok, text, lines)
	end
	L.sendState(player)
end

actions.rename = function(player, data)
	local slot = slotOf(data)
	if not slot then
		return result(player, false, Core.msg(nil, "noSlot"))
	end
	local ok, text = L.rename(player, slot, type(data) == "table" and data.name or nil, type(data) == "table" and data.icon or nil)
	result(player, ok, text)
	L.sendState(player)
end

actions.delete = function(player, data)
	local slot = slotOf(data)
	if not slot then
		return result(player, false, Core.msg(nil, "noSlot"))
	end
	local ok, text = L.delete(player, slot)
	result(player, ok, text)
	L.sendState(player)
end

actions.cancel = function(player)
	local cast = L.casts[player:getId()]
	if cast then
		endCast(player, cast, "cancel", Core.msg(nil, "cancelled"))
	end
end
L.actions = actions

local ext = CreatureEvent("ChaosLoadoutsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	local fn = actions[m.action]
	if fn and allowed(player, m.action) then
		fn(player, m.data)
	end
end
ext:register()

local login = CreatureEvent("ChaosLoadoutsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosLoadoutsExtended")
	player:registerEvent("ChaosLoadoutsLogout")
	local ok, err = pcall(L.recover, player)
	if not ok then
		print("[Chaos loadouts] recover failed for " .. player:getName() .. ": " .. tostring(err))
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosLoadoutsLogout")
function logout.onLogout(player)
	L.casts[player:getId()] = nil
	return true
end
logout:register()

local startup = GlobalEvent("ChaosLoadoutsStartup")
function startup.onStartup()
	db.query(L.SCHEMA)
	return true
end
startup:register()
