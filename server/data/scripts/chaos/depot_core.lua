-- The depot, retired: the rules that remain, without engine calls (depot.lua; server/tests/depot_test.lua). Config:
-- depot_config.lua. See server/README.md "Depot (retired)".
--
-- The depot chest and its boxes take no new items (the stash is the storage); what is in them can be taken out, and
-- the stash migration (stash.lua) moves it. The rules keep two things:
--   D.tabOf(cfg, id)                          the number of an old box item id, or nil (the stash migration walks the boxes)
--   D.isChest(cfg, id)                        true for the depot chest
--   D.maxTabs(cfg)                            the number of old boxes
--   D.destination(node, slot, acc)            where the engine puts an item dropped on `slot` of container `node`
--                                             (mirrors Container::queryDestination: 254 = up, 255 / past the end =
--                                             anywhere, a slot holding a container = into it)
--   D.locate(cfg, node, acc)                  {kind = "tab", tab, box, chest} | {kind = "chest", chest} |
--                                             {kind = "loose", chest} (in a container loose in the chest) | {kind = "other"}
--   D.decide(cfg, m)                          nil = allowed, else {code = "closed", text}
--   D.lockerOpen(cfg, transition)             {text, stash}: the locker line, and whether the stash window opens
--
-- acc (engine accessors, depot.lua; tests pass tables): id(node), parent(node) (a container or nil), isContainer(node),
-- itemAt(node, slot) (0-based), capacity(node), same(a, b).
--
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosDepotCore = ChaosDepotCore or {}
local D = ChaosDepotCore

local function int(v)
	v = tonumber(v) or 0
	if v ~= v then
		return 0
	end
	return math.floor(v)
end

local tabCache = setmetatable({}, {__mode = "k"})
local function tabsById(cfg)
	local t = tabCache[cfg]
	if not t then
		t = {}
		for i, id in ipairs(cfg.boxIds) do
			t[id] = i
		end
		tabCache[cfg] = t
	end
	return t
end

function D.tabOf(cfg, id)
	return tabsById(cfg)[int(id)]
end

function D.isChest(cfg, id)
	id = int(id)
	for _, c in ipairs(cfg.chestIds) do
		if c == id then
			return true
		end
	end
	return false
end

function D.maxTabs(cfg)
	return #cfg.boxIds
end

-- ---------------------------------------------------------------- where an item goes
function D.destination(node, slot, acc)
	if not node or not acc.isContainer(node) then
		return node
	end
	slot = int(slot)
	if slot == 254 then
		local up = acc.parent(node)
		return up or node
	end
	if slot == 255 or slot < 0 or slot >= int(acc.capacity(node)) then
		return node
	end
	local at = acc.itemAt(node, slot)
	if at and acc.isContainer(at) then
		return at
	end
	return node
end

function D.locate(cfg, node, acc)
	if not node or not acc.isContainer(node) then
		return {kind = "other"}
	end
	if D.isChest(cfg, acc.id(node)) then
		return {kind = "chest", chest = node}
	end
	local prev, cur = node, acc.parent(node)
	local guard = 0
	while cur and guard < 64 do
		if D.isChest(cfg, acc.id(cur)) then
			local tab = D.tabOf(cfg, acc.id(prev))
			if tab then
				return {kind = "tab", tab = tab, box = prev, chest = cur}
			end
			return {kind = "loose", chest = cur} -- inside a container loose in the chest: not a box
		end
		prev, cur = cur, acc.parent(cur)
		guard = guard + 1
	end
	return {kind = "other"}
end

-- ---------------------------------------------------------------- the move rule
-- m = {to = locate(...), from = locate(...) of where the item is now, sameTab = bool, sameChest = bool, split = part of
-- a stack}. Nothing new goes into the chest or a box; moving inside the same box (or loose inside the same chest) stays
-- possible, so a player can still tidy what the migration has not moved yet.
function D.decide(cfg, m)
	local to, from = m.to or {kind = "other"}, m.from or {kind = "other"}
	if to.kind == "other" then
		return nil
	end
	local same = (from.kind == "tab" and m.sameTab) or ((from.kind == "chest" or from.kind == "loose") and
		(to.kind == "chest" or to.kind == "loose") and m.sameChest)
	if same and not m.split then
		return nil
	end
	return {code = "closed", text = cfg.messages.closed}
end

-- what a locker opening shows: {text, stash}. stash: true when stash_config.lua depot.openStash asks for the stash
-- window (O316: it does; the locker window itself is closed by the client)
function D.lockerOpen(cfg, transition)
	local tr = type(transition) == "table" and transition or {}
	return {text = cfg.messages.locker, stash = tr.openStash == true}
end

return D
