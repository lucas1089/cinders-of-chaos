-- Charms: a per-character grid of small charms (client game_charms, extended opcode ChaosOpcodes.charms = 198).
-- Rules: charms_core.lua (pure, tests/charms_test.lua); numbers: charms_config.lua; table: sql/chaos_charms.sql (also
-- created here); items: tools/install_charms.py. Overview: server/README.md "Charms".
--
-- A charm is an item (server ids 32301..32308; the charm shard 32309): it drops, trades on the market and sits in the
-- backpack like any item. Placed into the grid it leaves the character: its attributes are copied into its
-- chaos_charms row (with engine patch 0017 the engine's own binary form, item:serializeAttributes(), else the charm's
-- attribute list) and the item is removed. Taken out, the item is made again from the row (a new per-item id) and the
-- row is deleted. A placed charm exists only as its row, never as an item too, so it cannot be traded, dropped or
-- copied while placed. Moving a charm inside the grid changes only the row's x, y.
--
-- Crash safety (charms_core.lua C.place / C.take / C.recoverAction; the market's listing method): the row is written
-- "pending" with the next serial of storage 7100470 BEFORE the item changes in memory; the item, the storage and the
-- character are then saved in ONE player:save(); then the row is marked done. At login a pending row is settled by the
-- saved serial (placing: placed or dropped; taking: dropped or back in the grid). Characters with players.save = 0
-- cannot place charms (nothing of theirs would be saved).
--
-- Effects (the placed charms whose cells are all open):
--   gear catalogue keys (Life on Kill, Gold Find, Treasure Goblin Chance, Mana on Kill)  ChaosCharms.extra(player): an
--       extra source of item_mods.lua M.refresh, summed with the items' under the gear caps (after the charm caps)
--   Damage to <family>   onHealthChange on the monster (registered by onTargetCombat); the family is the bestiary
--                        category of the monster's type name (bestiary_core.lua categoryOf)
--   <element> Resistance onHealthChange on the player: that element's hits are reduced
--   Orb Find             loot.lua: the currency layer's chances (ChaosCharms.orbFindMult)
--   Movement Speed out of combat   a 1 s think: no fight condition and not PZ-locked -> +N% of the base speed
--   Reputation           factions.lua F.gain (ChaosCharms.repPct)
--   Rift Time            rift.lua: the opener's charms lengthen a new run (ChaosCharms.riftSeconds)
--   signatures           Last Ember (lethal hit -> 1 health, 10 min), Wayfarer's Rest (out of combat 1% health and
--                        mana per 2 s), Hoard Sense (goblin chance), Harvester (mana on kill)
-- Drops: ChaosCharms.onSource(player, source, ctx) from rift.lua (a sealed rift of tier 6+), bounty.lua (a completed
-- contract), invasion.lua (a rewarded defender), dungeons.lua (a cleared dungeon), descent.lua (a cleared room).
--
-- Protocol (JSON {action, data}; the state goes through Chaos.sendChunked):
--   client -> server  open | place {ref | pos, sid, iid, x, y} | move {id, x, y} | take {id} | salvage {ref, sid, iid} |
--                     reforge {ref, sid, iid}
--   server -> client  state {grid, cells, placed, bag, totals, level, shards} | result {ok, text}
-- Staff: /charm give <small|tall|wide|grand|gravewarden|compass|hoard|tally> [rarity 1-3] [item level]
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosCharmsCore then
	dofile("data/scripts/chaos/charms_core.lua")
end
ChaosCharmsConfig = ChaosCharmsConfig or dofile("data/scripts/chaos/charms_config.lua")

ChaosCharms = ChaosCharms or {}
local CH = ChaosCharms
local Core = ChaosCharmsCore
local cfg = ChaosCharmsConfig
local OPCODE = ChaosOpcodes.charms or cfg.opcode
local TBL = (Chaos.tables and Chaos.tables.charms) or cfg.table
local S_SEQ, S_EMBER = cfg.storage.seq, cfg.storage.emberUntil

CH.players = CH.players or {} -- guid -> {rows = {row...}, own = totals, gear = gear keys, sig = signatures, sigText}
CH.speed = CH.speed or {} -- player id -> applied out-of-combat speed
CH.saveFlag = CH.saveFlag or {}

CH.SCHEMA = [[CREATE TABLE IF NOT EXISTS `chaos_charms` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL,
`state` tinyint(3) unsigned NOT NULL DEFAULT 9, `seq` int(11) NOT NULL DEFAULT 0, `x` tinyint(3) unsigned NOT NULL DEFAULT 1,
`y` tinyint(3) unsigned NOT NULL DEFAULT 1, `item_id` int(11) NOT NULL, `codec` varchar(8) NOT NULL DEFAULT 'attrs',
`data` mediumtext NOT NULL, `charm` text NOT NULL, `placed_at` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
KEY `player_id` (`player_id`), CONSTRAINT `chaos_charms_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`)
ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8]]

local function log(text)
	print("[Chaos charms] " .. text)
end

local function sql(query, columns)
	return Chaos.select(query, columns)
end

local function exec(query)
	if not db.query(query) then
		return -1
	end
	local r = sql("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	return r and r.n or 0
end

local function esc(s)
	return db.escapeString(tostring(s))
end

local function send(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

local function result(player, ok, text)
	send(player, "result", {ok = ok and true or false, text = text})
	if text and text ~= "" then
		player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_STATUS_DEFAULT, text)
	end
	return ok
end

local function call(obj, method, ...)
	if not obj or not obj[method] then
		return nil
	end
	local ok, v = pcall(obj[method], obj, ...)
	if ok then
		return v
	end
	return nil
end

-- ------------------------------------------------------------------ the item <-> the row
local HAS_BLOB = Item ~= nil and Item.serializeAttributes ~= nil and Item.unserializeAttributes ~= nil
CH.hasBlob = HAS_BLOB

local function custom(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if not ok then
		return nil
	end
	if type(v) == "userdata" or type(v) == "table" then
		local ok2, n = pcall(function() return v.value end)
		return ok2 and n or nil
	end
	return v
end

-- the charm an item carries (nil when it is no charm)
function CH.charmOf(item)
	if not item or not Core.charmDef(cfg, item:getId()) then
		return nil
	end
	return Core.fromAttrs(cfg, item:getId(), function(k) return custom(item, k) end)
end

function CH.isCharm(item)
	return item ~= nil and Core.charmDef(cfg, item:getId()) ~= nil
end

function CH.attributeKeys()
	return Core.attributeKeys()
end

-- write a charm onto an item: its attributes, its name and its look text
function CH.stamp(item, charm)
	for _, a in ipairs(Core.toAttrs(charm)) do
		item:setCustomAttribute(a[1], a[2])
	end
	if ITEM_ATTRIBUTE_DESCRIPTION then
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, table.concat(Core.describe(cfg, charm), " "))
	end
	if ITEM_ATTRIBUTE_NAME and not charm.unique then
		item:setAttribute(ITEM_ATTRIBUTE_NAME, Core.nameOf(cfg, charm):lower())
	end
end

local function encode(item)
	if HAS_BLOB then
		local ok, blob = pcall(item.serializeAttributes, item)
		if ok and type(blob) == "string" then
			return "blob", Core.hex(blob)
		end
	end
	local list = {}
	for _, k in ipairs(Core.attributeKeys()) do
		local v = custom(item, k)
		if v ~= nil then
			list[#list + 1] = {k, v}
		end
	end
	return "attrs", json.encode(list)
end

-- a new item (not in the world) from a row; nil, why
local function decode(row)
	local item = Game.createItem(row.item_id, 1)
	if not item then
		return nil, "could not create item " .. tostring(row.item_id)
	end
	if row.codec == "blob" then
		local raw = HAS_BLOB and Core.unhex(row.data)
		if not raw or not item:unserializeAttributes(raw) then
			item:remove()
			return nil, "attributes could not be read"
		end
	else
		local ok, list = pcall(json.decode, row.data)
		for _, a in ipairs(ok and type(list) == "table" and list or {}) do
			if type(a) == "table" and type(a[1]) == "string" then
				item:setCustomAttribute(a[1], a[2])
			end
		end
		local charm = CH.charmOf(item)
		if charm then
			CH.stamp(item, charm)
		end
	end
	pcall(function() item:removeCustomAttribute("chaos_iid") end) -- a new per-item id when it is first sent
	return item
end

-- ------------------------------------------------------------------ rows and totals
local COLS = {{"id", "n"}, {"state", "n"}, {"seq", "n"}, {"x", "n"}, {"y", "n"}, {"item_id", "n"}, {"codec", "s"},
	{"data", "s"}, {"charm", "s"}}

local function charmOfRow(row)
	local ok, t = pcall(json.decode, row.charm or "")
	if ok and type(t) == "table" and t.shape then
		return t
	end
	return nil
end

local function loadRows(guid)
	local rows = sql(string.format("SELECT `id`, `state`, `seq`, `x`, `y`, `item_id`, `codec`, `data`, `charm` FROM `%s` "
		.. "WHERE `player_id` = %d AND `state` = 0 ORDER BY `id`", TBL, guid), COLS)
	local out = {}
	for _, r in ipairs(rows) do
		r.c = charmOfRow(r)
		if r.c then
			r.shape = r.c.shape
			out[#out + 1] = r
		end
	end
	return out
end

local function hasAchievement(player)
	return function(id)
		return ChaosAchievements ~= nil and ChaosAchievements.has ~= nil and ChaosAchievements.has(player, id) == true
	end
end

local function stateOf(player)
	local guid = player:getGuid()
	local st = CH.players[guid]
	if not st then
		st = {rows = loadRows(guid)}
		CH.players[guid] = st
	end
	return st
end

-- totals of the placed charms (own and gear keys), kept per character; item_mods.lua is asked to refresh after a change
function CH.recompute(player, noGear)
	local st = stateOf(player)
	local unlock = Core.unlockState(cfg, player:getLevel(), hasAchievement(player))
	local list = {}
	for _, r in ipairs(st.rows) do
		r.active = Core.activeOf(cfg, r, unlock.open)
		list[#list + 1] = {charm = r.c, active = r.active}
	end
	st.own, st.gear, st.sig = Core.totals(cfg, list)
	st.sigText = Core.signature(list)
	st.unlock = unlock
	if not noGear and ChaosItemMods and ChaosItemMods.refresh then
		pcall(ChaosItemMods.refresh, player, true)
	end
	return st
end

local function own(player, key)
	if not player then
		return 0
	end
	local ok, guid = pcall(function() return player:getGuid() end)
	local st = ok and CH.players[guid]
	return st and st.own and st.own[key] or 0
end
CH.own = own

-- item_mods.lua M.refresh: the gear-catalogue numbers of the placed charms and their signature text
function CH.extra(player)
	local ok, guid = pcall(function() return player:getGuid() end)
	local st = ok and CH.players[guid]
	if not st or not st.gear then
		return nil, ""
	end
	return st.gear, st.sigText or ""
end
CH.merge = Core.merge

-- loot.lua: the currency layer's chances x this
function CH.orbFindMult(player)
	return 1 + own(player, "orbfind") / 100
end

-- factions.lua: reputation gains + this percent
function CH.repPct(player)
	return own(player, "reputation")
end

-- rift.lua: seconds added to a new run of this opener
function CH.riftSeconds(player)
	return own(player, "rifttime")
end

local function hasSignature(player, name)
	local ok, guid = pcall(function() return player:getGuid() end)
	local st = ok and CH.players[guid]
	return st ~= nil and st.sig ~= nil and st.sig[name] == true
end

-- ------------------------------------------------------------------ the character's items
local BACKPACK = CONST_SLOT_BACKPACK or 3

local function isContainer(item)
	return call(item, "isContainer") == true
end

local function iidOf(item)
	local v = tonumber(custom(item, "chaos_iid")) or 0
	return v
end

-- every charm in the backpack (and the bags in it): {ref, item, charm}
local function bagCharms(player)
	local out = {}
	local function walk(container, ref, depth)
		for i = 0, (call(container, "getSize") or 0) - 1 do
			local item = container:getItem(i)
			if item then
				local r = ref .. "." .. i
				local charm = CH.charmOf(item)
				if charm then
					out[#out + 1] = {ref = r, item = item, charm = charm}
				end
				if isContainer(item) and depth < 4 then
					walk(item, r, depth + 1)
				end
			end
		end
	end
	local bag = player:getSlotItem(BACKPACK)
	if bag and isContainer(bag) then
		walk(bag, "s" .. BACKPACK, 1)
	end
	return out
end

-- "s3.0.5": the backpack slot, then indexes into the containers inside it
local function resolveRef(player, ref)
	if type(ref) ~= "string" or #ref > 40 then
		return nil
	end
	local slot, rest = ref:match("^s(%d+)(.*)$")
	if tonumber(slot) ~= BACKPACK then
		return nil
	end
	local item = player:getSlotItem(BACKPACK)
	local depth = 0
	for idx in rest:gmatch("%.(%d+)") do
		depth = depth + 1
		if not item or not isContainer(item) or depth > 6 then
			return nil
		end
		item = item:getItem(tonumber(idx))
	end
	if depth == 0 then
		return nil
	end
	return item
end

-- an item dragged in from an open container (client position, as the tooltip and market scripts decode it)
local function resolvePos(player, pos)
	local T2 = ChaosItemTooltip
	local p = T2 and T2.decodePos and T2.decodePos(pos)
	if not p or p.kind ~= "container" then
		return nil
	end
	local container = player:getContainerById(p.cid)
	if not container then
		return nil
	end
	local first = tonumber(player:getContainerIndex(p.cid)) or 0
	local item = container:getItem(first + p.index)
	if not item then
		return nil
	end
	local ok, top = pcall(function() return item:getTopParent() end)
	if not ok or top ~= player then
		return nil
	end
	return item
end

local function itemFrom(player, d)
	local item
	if d.ref then
		item = resolveRef(player, d.ref)
	elseif d.pos then
		item = resolvePos(player, d.pos)
	end
	if not item or (d.sid and tonumber(d.sid) ~= item:getId()) then
		return nil
	end
	if d.iid ~= nil and tostring(d.iid) ~= "0" and (tonumber(d.iid) or 0) ~= iidOf(item) then
		return nil
	end
	if not CH.isCharm(item) then
		return nil
	end
	return item
end

-- backpack, else the store inbox; true when the item went somewhere
local function giveItem(player, item)
	if player:addItemEx(item, false) == RETURNVALUE_NOERROR then
		return true, "backpack"
	end
	local box = player:getInbox()
	if box and box:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1) == RETURNVALUE_NOERROR then
		return true, "inbox"
	end
	return false
end

-- ------------------------------------------------------------------ checks
local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function canChange(player)
	if player:getLevel() < cfg.minLevel then
		return false, string.format("Charms need level %d.", cfg.minLevel)
	end
	if cfg.outOfCombat and inCombat(player) then
		return false, "Not while you are in combat."
	end
	local guid = player:getGuid()
	if CH.saveFlag[guid] == nil then
		local r = sql(string.format("SELECT `save` FROM `players` WHERE `id` = %d", guid), {{"save", "n"}})[1]
		CH.saveFlag[guid] = r and r.save or 0
	end
	if CH.saveFlag[guid] == 0 then
		return false, "This character is not saved, so it cannot use the charm grid."
	end
	return true
end

local function rate(player, key)
	return not ChaosRateLimit or ChaosRateLimit.allow(player, "charms." .. key, cfg.rate[key] or 300)
end

-- ------------------------------------------------------------------ the state the window shows
local function iconOf(charm)
	return charm.unique or (charm.mods[1] and charm.mods[1].key) or "charm"
end

function CH.state(player)
	local st = CH.recompute(player, true)
	local cells = {}
	for y = 1, cfg.grid.rows do
		for x = 1, cfg.grid.cols do
			local k = Core.cellKey(x, y)
			local lock = st.unlock.locked[k]
			cells[#cells + 1] = {x = x, y = y, open = st.unlock.open[k] or nil, why = lock and lock.text or nil}
		end
	end
	local placed = {}
	for _, r in ipairs(st.rows) do
		local v = Core.viewOf(cfg, r.c)
		v.id, v.x, v.y, v.active = r.id, r.x, r.y, r.active
		v.icon = iconOf(r.c)
		v.item = ItemType(r.item_id):getClientId()
		placed[#placed + 1] = v
	end
	local bag = {}
	for _, b in ipairs(bagCharms(player)) do
		local v = Core.viewOf(cfg, b.charm)
		v.ref, v.sid, v.iid = b.ref, b.item:getId(), string.format("%.0f", iidOf(b.item))
		v.item = ItemType(b.item:getId()):getClientId()
		bag[#bag + 1] = v
		if #bag >= 60 then
			break
		end
	end
	local groups = {}
	for _, g in ipairs(st.unlock.groups) do
		groups[#groups + 1] = {text = g.text, open = g.open, cells = #g.cells}
	end
	return {cols = cfg.grid.cols, rows = cfg.grid.rows, cells = cells, placed = placed, bag = bag, groups = groups,
		totals = Core.totalsView(cfg, st.own), level = player:getLevel(), shards = player:getItemCount(Core.shardId(cfg)),
		max = cfg.maxPlaced}
end

function CH.sendState(player)
	local ok, s = pcall(CH.state, player)
	if not ok then
		log("state for " .. player:getName() .. ": " .. tostring(s))
		return
	end
	local text = json.encode({action = "state", data = s})
	if Chaos.sendChunked then
		Chaos.sendChunked(player, OPCODE, text)
	else
		player:sendExtendedOpcode(OPCODE, text)
	end
end

-- ------------------------------------------------------------------ place, move, take
local function placedList(st)
	local list = {}
	for _, r in ipairs(st.rows) do
		list[#list + 1] = {id = r.id, shape = r.shape, x = r.x, y = r.y}
	end
	return list
end

local function engineEnv(player, item, guid)
	local itemId = item and item:getId()
	local codec, data
	local created
	local env = {}
	function env.getSeq()
		return math.max(0, player:getStorageValue(S_SEQ))
	end
	function env.setSeq(n)
		player:setStorageValue(S_SEQ, n)
	end
	function env.insertRow(rec)
		codec, data = encode(item)
		if exec(string.format("INSERT INTO `%s` (`player_id`, `state`, `seq`, `x`, `y`, `item_id`, `codec`, `data`, `charm`, "
				.. "`placed_at`) VALUES (%d, %d, %d, %d, %d, %d, %s, %s, %s, %d)", TBL, guid, rec.state, rec.seq, rec.x, rec.y,
				itemId, esc(codec), esc(data), esc(json.encode(rec.charm)), os.time())) ~= 1 then
			return nil
		end
		local r = sql("SELECT LAST_INSERT_ID() AS `id`", {{"id", "n"}})[1]
		return r and r.id > 0 and r.id or nil
	end
	function env.setRow(id, from, to, seq)
		return exec(string.format("UPDATE `%s` SET `state` = %d, `seq` = %d WHERE `id` = %d AND `player_id` = %d AND `state` = %d",
			TBL, to, seq, id, guid, from)) == 1
	end
	function env.deleteRow(id, state)
		return exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `player_id` = %d AND `state` = %d", TBL, id, guid, state)) == 1
	end
	function env.removeItem()
		return item:remove() and true or false
	end
	function env.restoreItem()
		local back = decode({item_id = itemId, codec = codec, data = data})
		if back then
			giveItem(player, back)
		end
	end
	function env.createItem(row)
		local it = decode(row)
		if not it then
			return false
		end
		local ok = giveItem(player, it)
		if not ok then
			it:remove()
			return false
		end
		created = it
		return true
	end
	function env.uncreateItem()
		if created then
			created:remove()
		end
	end
	function env.save()
		return player:save() and true or false
	end
	return env
end

function CH.place(player, d)
	local ok, why = canChange(player)
	if not ok then
		return result(player, false, why)
	end
	local item = itemFrom(player, d)
	if not item then
		return result(player, false, "That charm is not in your backpack any more.")
	end
	local charm = CH.charmOf(item)
	local st = stateOf(player)
	local unlock = Core.unlockState(cfg, player:getLevel(), hasAchievement(player))
	local x, y = Core.int(d.x), Core.int(d.y)
	local refusal = Core.placeRefusal(cfg, placedList(st), charm.shape, x, y, unlock.open)
	if refusal then
		return result(player, false, refusal)
	end
	local guid = player:getGuid()
	local done, idOrWhy = Core.place(engineEnv(player, item, guid), {x = x, y = y, charm = charm})
	if not done then
		return result(player, false, idOrWhy == "item" and "That charm could not be moved." or "The charm grid is busy; try again.")
	end
	CH.players[guid] = nil
	CH.recompute(player)
	result(player, true, Core.nameOf(cfg, charm) .. " placed.")
	CH.sendState(player)
	return true
end

local function rowById(st, id)
	id = Core.int(id)
	for i, r in ipairs(st.rows) do
		if r.id == id then
			return r, i
		end
	end
	return nil
end

function CH.move(player, d)
	local ok, why = canChange(player)
	if not ok then
		return result(player, false, why)
	end
	local st = stateOf(player)
	local row = rowById(st, d.id)
	if not row then
		return result(player, false, "That charm is not in your grid.")
	end
	local unlock = Core.unlockState(cfg, player:getLevel(), hasAchievement(player))
	local x, y = Core.int(d.x), Core.int(d.y)
	local refusal = Core.placeRefusal(cfg, placedList(st), row.shape, x, y, unlock.open, row.id)
	if refusal then
		return result(player, false, refusal)
	end
	if exec(string.format("UPDATE `%s` SET `x` = %d, `y` = %d WHERE `id` = %d AND `player_id` = %d AND `state` = 0", TBL, x, y,
			row.id, player:getGuid())) ~= 1 then
		return result(player, false, "The charm grid is busy; try again.")
	end
	row.x, row.y = x, y
	CH.recompute(player)
	CH.sendState(player)
	return true
end

function CH.take(player, d)
	local ok, why = canChange(player)
	if not ok then
		return result(player, false, why)
	end
	local st = stateOf(player)
	local row = rowById(st, d.id)
	if not row then
		return result(player, false, "That charm is not in your grid.")
	end
	local guid = player:getGuid()
	local done, reason = Core.take(engineEnv(player, nil, guid), row)
	if not done then
		return result(player, false, reason == "room" and "There is no room for the charm (backpack and inbox)."
			or "The charm grid is busy; try again.")
	end
	CH.players[guid] = nil
	CH.recompute(player)
	result(player, true, Core.nameOf(cfg, row.c) .. " taken out.")
	CH.sendState(player)
	return true
end

-- ------------------------------------------------------------------ salvage and reforge (charms in the backpack)
function CH.salvage(player, d)
	local item = itemFrom(player, d)
	if not item then
		return result(player, false, "That charm is not in your backpack any more.")
	end
	if (tonumber(custom(item, "chaos_locked")) or 0) ~= 0 then
		return result(player, false, "That charm is locked.")
	end
	local charm = CH.charmOf(item)
	local n = Core.salvageShards(cfg, charm)
	local name = Core.nameOf(cfg, charm)
	if not item:remove() then
		return result(player, false, "That charm could not be salvaged.")
	end
	local shards = Game.createItem(Core.shardId(cfg), n)
	if shards then
		giveItem(player, shards)
	end
	result(player, true, string.format("%s salvaged: %d charm shards.", name, n))
	CH.sendState(player)
	return true
end

function CH.reforge(player, d)
	local item = itemFrom(player, d)
	if not item then
		return result(player, false, "That charm is not in your backpack any more.")
	end
	local charm = CH.charmOf(item)
	local cost = Core.reforgeCost(cfg, charm)
	if not cost then
		return result(player, false, "A unique charm cannot be reforged.")
	end
	local shardId = Core.shardId(cfg)
	if player:getItemCount(shardId) < cost then
		return result(player, false, string.format("Reforging this charm needs %d charm shards.", cost))
	end
	if not player:removeItem(shardId, cost) then
		return result(player, false, "The shards could not be taken.")
	end
	local new = Core.reforge(cfg, charm, math.random)
	CH.stamp(item, new)
	if ChaosItemMods and ChaosItemMods.sendUpdate then
		ChaosItemMods.sendUpdate(item)
	end
	local parts = {}
	for _, m in ipairs(new.mods) do
		parts[#parts + 1] = Core.text(cfg, m.key, m.value)
	end
	result(player, true, string.format("%s reforged: %s.", Core.nameOf(cfg, new), table.concat(parts, ", ")))
	CH.sendState(player)
	return true
end

-- ------------------------------------------------------------------ drops
-- a new charm item (not in the world) from a charm record
function CH.makeItem(charm)
	local item = charm and charm.item and Game.createItem(charm.item, 1)
	if item then
		CH.stamp(item, charm)
	end
	return item
end

-- a content source finished for this player: roll the drop and give the charm (rift.lua, bounty.lua, invasion.lua,
-- dungeons.lua, descent.lua). ctx: see charms_core.lua C.dropChance
function CH.onSource(player, source, ctx)
	if not player or type(player.getGuid) ~= "function" then -- an offline {guid, name} gets nothing
		return nil
	end
	local charm = Core.rollDrop(cfg, source, ctx)
	if not charm then
		return nil
	end
	local item = CH.makeItem(charm)
	if not item then
		return nil
	end
	local ok, where = giveItem(player, item)
	if not ok then
		item:remove()
		return nil
	end
	local name = Core.nameOf(cfg, charm)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You found a charm: %s%s.", name,
		where == "inbox" and Chaos.t(player, " (in your inbox)") or ""))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN or 13)
	log(string.format("%s: %s from %s", player:getName(), name, source))
	return charm
end

-- ------------------------------------------------------------------ recovery
function CH.recover(player)
	local guid = player:getGuid()
	local saved = player:getStorageValue(S_SEQ)
	local rows = sql(string.format("SELECT `id`, `state`, `seq` FROM `%s` WHERE `player_id` = %d AND `state` IN (8, 9)", TBL, guid),
		{{"id", "n"}, {"state", "n"}, {"seq", "n"}})
	for _, r in ipairs(rows) do
		local action = Core.recoverAction(r.state, r.seq, saved)
		if action == "activate" or action == "restore" then
			exec(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `state` = %d", TBL, r.id, r.state))
		elseif action == "drop" then
			exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `state` = %d", TBL, r.id, r.state))
		end
		log(string.format("%s: pending row %d (state %d, serial %d, saved %d): %s", player:getName(), r.id, r.state, r.seq,
			saved, action))
	end
end

-- ------------------------------------------------------------------ effects
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

local familyCache = {}
local function familyOf(monster)
	local name = Chaos.monsterTypeName and Chaos.monsterTypeName(monster) or monster:getName()
	local key = tostring(name):lower()
	local fam = familyCache[key]
	if fam == nil then
		if not ChaosBestiaryCore then
			pcall(dofile, "data/scripts/chaos/bestiary_core.lua")
		end
		Chaos.bestiaryConfig = Chaos.bestiaryConfig or dofile("data/scripts/chaos/bestiary_config.lua")
		local races = {[1] = "venom", [2] = "blood", [3] = "undead", [4] = "fire", [5] = "energy"}
		local mt = monster:getType()
		local race = races[tonumber(call(mt, "race")) or 0]
		local ok, cat = pcall(ChaosBestiaryCore.categoryOf, name, race, false, false, Chaos.bestiaryConfig)
		fam = ok and cat or false
		familyCache[key] = fam
	end
	return fam or nil
end
CH.familyOf = familyOf

local function anyFamily(st)
	for _, def in ipairs(cfg.pool) do
		if def.family and (st.own[def.key] or 0) > 0 then
			return true
		end
	end
	return false
end

local dealt = CreatureEvent("ChaosCharmsDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not creature:isMonster() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local pct = p and Core.familyPct(CH.players[p:getGuid()] and CH.players[p:getGuid()].own, familyOf(creature)) or 0
	if pct > 0 then
		primaryDamage = ChaosItemMods and ChaosItemMods.scale and ChaosItemMods.scale(primaryDamage, pct)
			or math.floor(primaryDamage * (100 + pct) / 100)
		secondaryDamage = ChaosItemMods and ChaosItemMods.scale and ChaosItemMods.scale(secondaryDamage, pct)
			or math.floor(secondaryDamage * (100 + pct) / 100)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

-- Chaos.registerOnce / eventKnown (chaos_constants.lua): register on a monster once, not at every hit
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local function eventKnown(creature, name)
	local f = Chaos and Chaos.eventKnown
	return f ~= nil and f(creature, name)
end
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and target:isMonster() and not eventKnown(target, "ChaosCharmsDealt") then
		local p = playerOf(creature)
		local st = p and CH.players[p:getGuid()]
		if st and st.own and anyFamily(st) then
			registerOnce(target, "ChaosCharmsDealt")
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

local taken = CreatureEvent("ChaosCharmsTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not creature:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st = CH.players[creature:getGuid()]
	if not st or not st.own then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local r1 = Core.resistPct(cfg, st.own, primaryType)
	if r1 > 0 then
		primaryDamage = Core.reduce(primaryDamage, r1)
	end
	local r2 = Core.resistPct(cfg, st.own, secondaryType)
	if r2 > 0 then
		secondaryDamage = Core.reduce(secondaryDamage, r2)
	end
	if st.sig and st.sig.lastember and attacker and attacker ~= creature then
		local cap = Core.emberCap(creature:getHealth(), primaryDamage, secondaryDamage)
		if cap and os.time() >= creature:getStorageValue(S_EMBER) then
			creature:setStorageValue(S_EMBER, os.time() + cfg.signature.lastember.cooldown)
			local sign = primaryDamage < 0 and -1 or 1
			primaryDamage, secondaryDamage = sign * cap, 0
			creature:getPosition():sendMagicEffect(CONST_ME_FIREAREA or 7)
			creature:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(creature, "Last Ember: the Gravewarden's Seal kept you alive."))
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- out-of-combat movement speed and the Wayfarer's Rest
local function think()
	local now = os.mtime and os.mtime() or os.time() * 1000
	for _, player in ipairs(Game.getPlayers()) do
		local st = CH.players[player:getGuid()]
		local id = player:getId()
		local pct = st and st.own and st.own.oocspeed or 0
		local calm = not inCombat(player)
		local want = (pct > 0 and calm) and math.floor(player:getBaseSpeed() * pct / 100) or 0
		local have = CH.speed[id] or 0
		if want ~= have then
			player:changeSpeed(want - have)
			CH.speed[id] = want
		end
		if calm and st and st.sig and st.sig.wayfarer then
			local w = cfg.signature.wayfarer
			st.restAt = st.restAt or 0
			if now >= st.restAt then
				st.restAt = now + w.everyMs
				if player:getHealth() < player:getMaxHealth() then
					Chaos.heal(player, math.max(1, math.floor(player:getMaxHealth() * w.healthPct / 100)))
				end
				if player:getMana() < player:getMaxMana() then
					player:addMana(math.max(1, math.floor(player:getMaxMana() * w.manaPct / 100)))
				end
			end
		end
	end
	addEvent(think, cfg.thinkMs)
end

-- ------------------------------------------------------------------ the opcode
local actions = {
	open = function(player)
		CH.sendState(player)
	end,
	place = CH.place,
	move = CH.move,
	take = CH.take,
	salvage = CH.salvage,
	reforge = CH.reforge
}
CH.actions = actions

local ext = CreatureEvent("ChaosCharmsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	local fn = actions[m.action]
	if fn and rate(player, m.action) then
		local ok, err = pcall(fn, player, type(m.data) == "table" and m.data or {})
		if not ok then
			log(m.action .. " for " .. player:getName() .. ": " .. tostring(err))
			result(player, false, "Something went wrong.")
		end
	end
end
ext:register()

local login = CreatureEvent("ChaosCharmsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCharmsExtended")
	player:registerEvent("ChaosCharmsTaken")
	player:registerEvent("ChaosCharmsAdvance")
	player:registerEvent("ChaosCharmsLogout")
	local ok, err = pcall(CH.recover, player)
	if not ok then
		log("recover failed for " .. player:getName() .. ": " .. tostring(err))
	end
	CH.players[player:getGuid()] = nil
	ok, err = pcall(CH.recompute, player)
	if not ok then
		log("load failed for " .. player:getName() .. ": " .. tostring(err))
	end
	return true
end
login:register()

-- a level milestone opens cells
local advance = CreatureEvent("ChaosCharmsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and CH.players[player:getGuid()] then
		for _, u in ipairs(cfg.unlocks) do
			if u.level and ((oldLevel < u.level) ~= (newLevel < u.level)) then
				CH.recompute(player)
				break
			end
		end
	end
	return true
end
advance:register()

local logout = CreatureEvent("ChaosCharmsLogout")
function logout.onLogout(player)
	CH.players[player:getGuid()] = nil
	CH.speed[player:getId()] = nil
	CH.saveFlag[player:getGuid()] = nil
	return true
end
logout:register()

local startup = GlobalEvent("ChaosCharmsStartup")
function startup.onStartup()
	db.query(CH.SCHEMA)
	local errors = Core.validate(cfg)
	for _, e in ipairs(errors) do
		log("config: " .. e)
	end
	addEvent(think, cfg.thinkMs)
	return true
end
startup:register()

-- staff: /charm give <shape | unique> [rarity] [item level]
local talk = TalkAction("/charm")
function talk.onSay(player, words, param)
	-- creates items: administrators only, every use in the audit log (chaos_constants.lua)
	local allowed, staff = Chaos.staffCommand(player, words, param, true)
	if not allowed then
		return not staff
	end
	local args = {}
	for a in tostring(param or ""):gmatch("[^,%s]+") do
		args[#args + 1] = a
	end
	if args[1] ~= "give" or not args[2] then
		player:sendCancelMessage("/charm give <small|tall|wide|grand|gravewarden|compass|hoard|tally> [rarity 1-3] [item level]")
		return false
	end
	local opts = {ilvl = tonumber(args[4]) or 100}
	if cfg.uniques[args[2]] then
		opts.unique = args[2]
	elseif cfg.shapes[args[2]] then
		opts.shape, opts.rarity = args[2], tonumber(args[3]) or 3
	else
		player:sendCancelMessage(Chaos.t(player, "Unknown charm %s", args[2]))
		return false
	end
	local item = CH.makeItem(Core.rollCharm(cfg, opts))
	if item then
		giveItem(player, item)
		player:sendTextMessage(MESSAGE_INFO_DESCR or MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Charm given."))
	end
	return false
end
talk:separator(" ")
talk:register()
