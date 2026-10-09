-- The use-with action of the crafting orbs and the crafting bench (client game_crafting, extended opcode
-- ChaosOpcodes.crafting). The orb rules live in data/lib/chaos_crafting.lua (ChaosCrafting); see server/README.md
-- "Crafting". Every orb is used directly on an item ("Use with", then click the item); the bench is optional (it shows
-- an item's modifiers and what each orb would do). Both paths run the same craft() below. Rift Keys are craftable too.
--
-- Orbs and the bench work on items inside the backpack only (never equipped ones, never the ground). An item is addressed by
-- its path from the backpack ("3" = slot 3 of the backpack, "3.0" = slot 0 of the bag in slot 3) plus its id and the
-- signature of its modifiers, so an orb is never applied to an item that moved or changed after the player picked it.
-- Every check is done here: the player owns the orb, the item is in the backpack, the orb fits the item, no uniques.
--
-- Protocol (JSON {action, data}):
--   client -> server  open | select {path, id} | select {pos = {x, y, z}, clientId} (dragged from a container) |
--                     apply {orb, path, id, sig, mod} (mod = the attribute key of the modifier the orb is aimed at: Binding,
--                     Excision, Reforging; none = a random one) | gem {op = "remove"|"shatter", socket, path, id, sig} | clear
--   server -> client  info {orbs = [{key, id, clientId, name, text, keyText}], reasons = {code -> text}}   sent when the bench
--                            opens (an extended opcode message above 8192 bytes is dropped by the engine, so what never
--                            changes is sent once)
--                     state {open, counts = {orb key -> how many the player has}, item = {path, clientId,
--                            name, kind ("riftkey" for a key), rarity, rarityName, level, mods = [{group, key, text, tier, side,
--                            lo, hi, bound, power}], maxMods, quality, qualityCap, ruined, binds = {n, max}, pick = {orb key
--                            -> [modifier keys it may be aimed at]}, rewards (keys), unique, orbs = {key -> ""|reason code},
--                            preview = {key -> text},
--                            sockets = {count, max, list = [{index, id, clientId, name, text, color, cost}]}, sig} | nil,
--                            items = [{path, id, clientId, name, rarity, rarityName, unique, key}],
--                            history = [{time, orb, item, text}]}
--                     result {ok, orb, text}
--   salvage | lock | salvageScope | salvageBatch | combine are handed to salvage.lua (the bench's Salvage mode)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end

local C = ChaosCrafting
local cfg = C.config
local OPCODE = ChaosOpcodes.crafting or 232
local MAX_LIST = 64 -- items listed from the backpack
local MAX_DEPTH = 4 -- bags inside bags
local lastAction = {} -- player id -> time in ms of the last apply (anti spam)
local MIN_INTERVAL = 250 -- ms between two orbs

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end
local selected = {} -- player id -> {path, id}

-- ---------------------------------------------------------------- backpack paths
local function backpackOf(player)
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if bp and bp:isContainer() then
		return bp
	end
	return nil
end

local function itemAt(player, path)
	if type(path) ~= "string" or #path > 32 or not path:match("^%d+[%.%d]*$") then
		return nil
	end
	local c = backpackOf(player)
	local item
	for index in path:gmatch("%d+") do
		if not c then
			return nil
		end
		item = c:getItem(tonumber(index))
		if not item then
			return nil
		end
		c = item:isContainer() and item or nil
	end
	return item
end

-- walk the backpack: fn(item, path) for every item, depth first
local function walk(player, fn)
	local count = 0
	local function visit(container, prefix, depth)
		for i = 0, container:getSize() - 1 do
			local item = container:getItem(i)
			if item then
				count = count + 1
				if count > 2000 then
					return
				end
				local path = prefix == "" and tostring(i) or (prefix .. "." .. i)
				if fn(item, path) then
					return true
				end
				if item:isContainer() and depth < MAX_DEPTH and visit(item, path, depth + 1) then
					return true
				end
			end
		end
	end
	local bp = backpackOf(player)
	if bp then
		visit(bp, "", 1)
	end
end

local function pathOf(player, target)
	local found
	walk(player, function(item, path)
		if item == target then
			found = path
			return true
		end
	end)
	return found
end

local function clientIdOf(id)
	local ok, cid = pcall(function() return ItemType(id):getClientId() end)
	return ok and cid or id
end

-- ---------------------------------------------------------------- history (table chaos_crafting_log)
-- at most `max` characters (the state message must stay small): a longer text is cut at a word and ends with "..."
local function shortText(text, max)
	text = tostring(text or "")
	if #text <= max then
		return text
	end
	local cut = text:sub(1, max - 3)
	local word = cut:match("^(.*%S)%s") -- up to the last whole word
	return ((word or cut):gsub("[%s,;:%.%(]+$", "")) .. "..."
end

local function history(player)
	local rows = Chaos.select(string.format(
		"SELECT `created_at`, `orb`, `item`, `result` FROM `%s` WHERE `player_id` = %d ORDER BY `id` DESC LIMIT %d",
		cfg.historyTable, player:getGuid(), cfg.historySize),
		{{"created_at", "n"}, {"orb", "s"}, {"item", "s"}, {"result", "s"}})
	local out = {}
	for _, r in ipairs(rows) do
		out[#out + 1] = {time = r.created_at, orb = r.orb, item = r.item, text = shortText(r.result, 110)}
	end
	return out
end

local function logCraft(player, orb, itemName, text)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `created_at`, `orb`, `item`, `result`) VALUES (%d, %d, %s, %s, %s)",
		cfg.historyTable, player:getGuid(), os.time(), db.escapeString(orb.name), db.escapeString(itemName:sub(1, 80)),
		db.escapeString(text:sub(1, 255))))
end

-- other crafting actions (gems.lua: socketing, combining, taking gems out) write the same log
function ChaosCraftingLog(player, what, itemName, text)
	logCraft(player, {name = what}, itemName or "", text or "")
end

-- ---------------------------------------------------------------- state
-- An extended opcode message above 8192 bytes is dropped by the engine (NetworkMessage::addString), so the bench sends what
-- never changes once ("info": the orbs with their texts, the reason texts) when it opens, and every state carries only
-- counts, reason codes and the item. sendState also trims the lists until the JSON fits (STATE_LIMIT).
local STATE_LIMIT = 7600
local function orbCounts(player)
	local out = {}
	for _, orb in ipairs(cfg.orbs) do
		out[orb.key] = player:getItemCount(orb.id)
	end
	return out
end

local function sendInfo(player)
	local orbs = {}
	for _, orb in ipairs(cfg.orbs) do
		orbs[#orbs + 1] = {key = orb.key, id = orb.id, clientId = clientIdOf(orb.id), name = orb.name, text = orb.text,
			keyText = orb.keyText}
	end
	Chaos.send(player, OPCODE, "info", {orbs = orbs, reasons = C.reasons})
end

-- gear and Rift Keys
local function craftable(item)
	return C.isGear(item) or C.isRiftKey(item)
end

local function itemList(player)
	local out = {}
	walk(player, function(item, path)
		if #out < MAX_LIST and not item:isContainer() and C.isRiftKey(item) then
			local view = C.describeKey(item)
			out[#out + 1] = {path = path, id = item:getId(), clientId = clientIdOf(item:getId()), name = view.name,
				rarity = 0, rarityName = "Rift Key", key = true}
		elseif #out < MAX_LIST and not item:isContainer() and C.isGear(item) then
			out[#out + 1] = {path = path, id = item:getId(), clientId = clientIdOf(item:getId()), name = C.itemName(item),
				rarity = C.rarityOf(item), rarityName = C.rarityOf(item) > 0 and C.rarityName(C.rarityOf(item)) or nil,
				unique = C.isUnique(item) or nil}
		end
	end)
	return out
end

local function sendState(player, open)
	local pid = player:getId()
	if open then
		sendInfo(player)
	end
	local data = {open = open and true or false, counts = orbCounts(player), items = itemList(player),
		history = history(player)}
	local sel = selected[pid]
	if sel then
		local item = itemAt(player, sel.path)
		if item and item:getId() == sel.id and craftable(item) then
			local view = C.describe(item, {codes = true})
			view.path = sel.path
			view.clientId = clientIdOf(item:getId())
			data.item = view
		else
			selected[pid] = nil
		end
	end
	if ChaosSalvage and ChaosSalvage.benchState then
		ChaosSalvage.benchState(player, data) -- salvage.lua: shards, recipes, lock marks, the "salvage all" preview
	end
	-- keep the message under the engine's string limit: history first, then the end of the item list
	while #json.encode({action = "state", data = data}) > STATE_LIMIT do
		if #data.history > 0 then
			data.history = {}
		elseif #data.items > 8 then
			table.remove(data.items)
		else
			break
		end
	end
	Chaos.send(player, OPCODE, "state", data)
end

local function sendResult(player, ok, orbKey, text)
	Chaos.send(player, OPCODE, "result", {ok = ok, orb = orbKey, text = text})
end

-- ---------------------------------------------------------------- shared apply (bench and use-with)
-- true when the item sits in the player's backpack (or a bag inside it), not equipped and not on the ground
local function inBackpack(player, item)
	local bp = backpackOf(player)
	if not bp or item == bp then
		return false
	end
	local p, depth = item:getParent(), 0
	while p and depth <= MAX_DEPTH + 1 do
		if not (p.isItem and p:isItem()) then
			return false
		end
		if p == bp then
			return true
		end
		p, depth = p:getParent(), depth + 1
	end
	return false
end

-- apply orbKey to item for player; orbItem = the used orb (use-with) or nil (bench: take one from the player).
-- returns ok, text, newItem
local function craft(player, orbKey, item, orbItem, opts)
	local orb = C.orbByKey[orbKey]
	if not orb then
		return false, C.reasons.unknownOrb
	end
	if not inBackpack(player, item) then
		return false, "Put the item in your backpack first (equipped items cannot be crafted)."
	end
	if not orbItem and player:getItemCount(orb.id) < 1 then
		return false, string.format("You have no %s.", orb.name)
	end
	local name = C.itemName(item)
	local ok, res = C.apply(orbKey, item, opts)
	if not ok then
		return false, res
	end
	if orbItem then
		orbItem:remove(1)
	else
		player:removeItem(orb.id, 1)
	end
	logCraft(player, orb, name, res.text)
	local pos = player:getPosition()
	local red = orbKey == "annulment" or orbKey == "scouring" or orbKey == "excision" or res.outcome == "ruin"
	pos:sendMagicEffect(red and CONST_ME_MAGIC_RED or CONST_ME_MAGIC_GREEN)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s: %s", orb.name, res.text))
	return true, res.text, res.item
end

-- ---------------------------------------------------------------- bench actions
local function selectItem(player, data)
	local pid = player:getId()
	local id = Chaos.toInt(data.id, 1, 65535)
	local item, path
	if type(data.path) == "string" then
		path = data.path
		item = itemAt(player, path)
	elseif type(data.pos) == "table" then
		-- dragged from an open container: x = 0xFFFF, y = 0x40 | container id, z = slot
		local x, y, z = Chaos.toInt(data.pos.x), Chaos.toInt(data.pos.y), Chaos.toInt(data.pos.z)
		if x == 65535 and y and z and y >= 64 then
			local container = player:getContainerById(y - 64)
			item = container and container:getItem(z)
			path = item and pathOf(player, item)
			-- the client knows client ids only
			local cid = Chaos.toInt(data.clientId, 1, 65535)
			if item and cid and clientIdOf(item:getId()) ~= cid then
				item = nil
			end
			id = nil
		elseif x == 65535 and y and y < 64 then
			sendResult(player, false, nil, "Take the item off first: the bench works on items in your backpack.")
			return
		end
	end
	if not item or not path or (id and item:getId() ~= id) then
		sendResult(player, false, nil, "Put an item from your backpack on the bench.")
		return
	end
	if not craftable(item) then
		sendResult(player, false, nil, C.reasons.notGear)
		return
	end
	selected[pid] = {path = path, id = item:getId()}
	sendState(player, false)
end

-- take a gem out of the item on the bench ("remove": it comes back for gold, "shatter": it is destroyed)
local function gemAction(player, data)
	local pid = player:getId()
	local now = nowMs()
	if lastAction[pid] and now - lastAction[pid] < MIN_INTERVAL then
		sendState(player, false)
		return
	end
	lastAction[pid] = now
	local item = itemAt(player, data.path)
	local id = Chaos.toInt(data.id, 1, 65535)
	if not item or item:getId() ~= id or (data.sig and C.signature(item) ~= data.sig) then
		selected[pid] = nil
		sendResult(player, false, "gem", "The item moved or changed. Put it on the bench again.")
		sendState(player, false)
		return
	end
	if not ChaosGems or not ChaosGems.unsocket then
		return
	end
	local ok, text = ChaosGems.unsocket(player, item, Chaos.toInt(data.socket, 1, 3), data.op == "remove")
	sendResult(player, ok, "gem", text)
	sendState(player, false)
end

local function apply(player, data)
	local pid = player:getId()
	local now = nowMs()
	if lastAction[pid] and now - lastAction[pid] < MIN_INTERVAL then
		sendState(player, false) -- the client disabled the button; give it back
		return
	end
	lastAction[pid] = now
	local orbKey = type(data.orb) == "string" and data.orb or ""
	local item = itemAt(player, data.path)
	local id = Chaos.toInt(data.id, 1, 65535)
	if not item or item:getId() ~= id or (data.sig and C.signature(item) ~= data.sig) then
		selected[pid] = nil
		sendResult(player, false, orbKey, "The item moved or changed. Put it on the bench again.")
		sendState(player, false)
		return
	end
	local opts
	if type(data.mod) == "string" and #data.mod <= 64 and data.mod:match("^[%w_%.]+$") then
		opts = {mod = data.mod}
	end
	local ok, text, newItem = craft(player, orbKey, item, nil, opts)
	if ok and newItem then
		local path = pathOf(player, newItem)
		selected[pid] = path and {path = path, id = newItem:getId()} or nil
	end
	sendResult(player, ok, orbKey, text)
	sendState(player, false)
end

-- the bench's Salvage mode (salvage.lua) works on the same backpack paths, selection and answers
ChaosCraftingBench = {itemAt = itemAt, walk = walk, pathOf = pathOf, inBackpack = inBackpack, backpackOf = backpackOf,
	sendState = sendState, sendResult = sendResult,
	select = function(player, sel) selected[player:getId()] = sel end}

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosCraftingExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	-- every answer walks the backpack and reads the history from the database; "apply" has its own MIN_INTERVAL
	if ChaosSalvage and ChaosSalvage.actions and ChaosSalvage.actions[msg.action] then
		ChaosSalvage.onAction(player, msg.action, data) -- salvage.lua, with its own rate limits
		return
	end
	if msg.action ~= "apply" and msg.action ~= "gem" and ChaosRateLimit and not ChaosRateLimit.allow(player, "crafting.state", 150) then
		return
	end
	if msg.action == "open" then
		sendState(player, true)
	elseif msg.action == "select" then
		selectItem(player, data)
	elseif msg.action == "apply" then
		apply(player, data)
	elseif msg.action == "gem" then
		gemAction(player, data)
	elseif msg.action == "clear" then
		selected[player:getId()] = nil
		sendState(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosCraftingLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCraftingExtended")
	player:registerEvent("ChaosCraftingLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCraftingLogout")
function logout.onLogout(player)
	selected[player:getId()] = nil
	lastAction[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()


-- ---------------------------------------------------------------- use-with on every orb
-- Every orb (the seven crafting orbs, the Orb of Sockets and the orbs v2 of data/lib/chaos_orbs.lua) is a "use with"
-- item: "Use with" on the orb, then click the item (or the Rift Key) in the backpack. An orb that is aimed at one
-- modifier (Binding, Excision, Reforging) takes a random one that way; the bench lets you choose.
-- The Orb of Awakening and the Orb of Grafting are made use-with by server/tools/install_crafting.py (items.otb flag
-- "useable") and client/tools/sprites/set_multiuse.py (the client dat's multi-use flag). The Orbs of Upheaval and Fate are
-- registered here too, so they follow the same rules and logging (crafting.lua loads before the base server's
-- customs/rarity/reroll_rarity_stats.lua; install_crafting.py makes that script skip its own registration).
-- Using an orb without a target (a plain "use", e.g. from a hotkey) only explains how to use it.
local function useHint(player, orb, prefix)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
		"%sUse the %s on an item: choose \"Use with\" on the orb, then click an item or a Rift Key in your backpack. "
		.. "The crafting bench (Economy > Crafting Bench) shows a preview first.", prefix or "", orb.name))
end

function ChaosCraftingUseOrb(player, orbItem, target, orbKey)
	local orb = C.orbByKey[orbKey]
	if not orb then
		return false
	end
	-- no target, a creature, the floor, or anything else that can never carry modifiers: explain the orb
	if not target or type(target) ~= "userdata" or not target.isItem or not target:isItem() or target == orbItem then
		useHint(player, orb)
		return true
	end
	if not craftable(target) then
		useHint(player, orb, "That cannot carry modifiers. ")
		return true
	end
	local ok, text = craft(player, orbKey, target, orbItem)
	if not ok then
		player:sendCancelMessage(text)
	else
		sendState(player, false) -- an open bench shows the new counts (a closed one stays closed)
	end
	return true
end

for _, orb in ipairs(cfg.orbs) do
	local action = Action()
	local key = orb.key
	function action.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		return ChaosCraftingUseOrb(player, item, target, key)
	end
	action:id(orb.id)
	action:allowFarUse(false)
	action:register()
end
C.ownsStockOrbs = true -- read by the patched reroll_rarity_stats.lua (install_crafting.py)

-- old rows go at startup
local startup = GlobalEvent("ChaosCraftingStartup")
function startup.onStartup()
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `created_at` < %d", cfg.historyTable,
		os.time() - cfg.historyKeepDays * 86400))
	return true
end
startup:register()
