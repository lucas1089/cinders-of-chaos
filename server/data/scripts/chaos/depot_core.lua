-- Depot tabs: the rules, without engine calls (depot.lua; server/tests/depot_test.lua). Config: depot_config.lua.
--
-- The depot chest holds one box per tab (cfg.boxIds; tab n = boxIds[n]). An account may fill tabs 1..tabs; higher tabs
-- are withdraw-only. A tab holds cfg.tabSize items: every item inside it counts once, a container counts as 1 plus
-- everything inside it, a stack counts as 1. Nothing is ever deleted: contents above a limit stay, only adding is refused.
--
--   D.tabOf(cfg, id)                          tab number of a box item id, or nil
--   D.isChest(cfg, id)                        true for the depot chest
--   D.maxTabs(cfg)                            the number of boxes
--   D.tabCount(cfg, pactLimit, achievementTabs)  tabs the account may fill (0..maxTabs)
--   D.holding(node, children)                 items inside node, nested (children(node) -> list | nil)
--   D.weight(node, children)                  what moving node adds to a tab: 1 + holding
--   D.destination(node, slot, acc)            where the engine puts an item dropped on `slot` of container `node`
--                                             (mirrors Container::queryDestination: 254 = up, 255 / past the end =
--                                             anywhere, a slot holding a container = into it)
--   D.locate(cfg, node, acc)                  {kind = "tab", tab, box, chest} | {kind = "chest", chest} |
--                                             {kind = "loose", chest} (in a container loose in the chest) | {kind = "other"}
--   D.decide(cfg, m)                          nil = allowed, else {code = "locked" | "full" | "chest", text}
--   D.layout(cfg, tabs, used, items)          places loose chest items into tabs (migration)
--   D.tabsView(cfg, tabs, used)               {{tab, used, size, locked}} for the client and the texts
--   D.description(cfg, tab, tabs, used)       the look text of a box
--   D.openText(cfg, tabs)                     the line shown when a locker opens
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

function D.tabCount(cfg, pactLimit, achievementTabs)
	return math.max(0, math.min(D.maxTabs(cfg), int(pactLimit) + int(achievementTabs)))
end

-- ---------------------------------------------------------------- counting
function D.holding(node, children)
	local n = 0
	local list = children(node)
	if list then
		for _, child in ipairs(list) do
			n = n + 1 + D.holding(child, children)
		end
	end
	return n
end

function D.weight(node, children)
	return 1 + D.holding(node, children)
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
			return {kind = "loose", chest = cur} -- inside a container loose in the chest (from before tabs): not a tab
		end
		prev, cur = cur, acc.parent(cur)
		guard = guard + 1
	end
	return {kind = "other"}
end

-- ---------------------------------------------------------------- the move rule
-- m = {to = locate(...), from = locate(...) of where the item is now, sameTab = bool, sameChest = bool,
--      tabs = n, used = items in the target tab now, weight = what the move adds, split = part of a stack}
function D.decide(cfg, m)
	local to, from = m.to or {kind = "other"}, m.from or {kind = "other"}
	local M = cfg.messages
	local tabs = int(m.tabs)
	if to.kind == "chest" or to.kind == "loose" then
		-- the chest itself (and what lies loose in it from before tabs) takes no new items; loose items already there
		-- may be moved around in it
		if (from.kind == "chest" or from.kind == "loose") and m.sameChest and not m.split then
			return nil
		end
		return {code = "chest", text = string.format(M.chest, tabs)}
	end
	if to.kind ~= "tab" then
		return nil
	end
	local size = int(cfg.tabSize)
	local used = int(m.used)
	local add = int(m.weight)
	if from.kind == "tab" and m.sameTab then
		if not m.split then
			return nil -- moved inside the same tab: the count does not change
		end
		add = 1 -- part of a stack moved inside the tab may make one more stack
		if used + add <= size then
			return nil
		end
		return {code = "full", text = string.format(M.full, to.tab, used, size, add)}
	end
	if to.tab > tabs then
		return {code = "locked", text = string.format(M.locked, to.tab, tabs)}
	end
	if used + add > size then
		return {code = "full", text = string.format(M.full, to.tab, used, size, add)}
	end
	return nil
end

-- ---------------------------------------------------------------- migration
-- items = {{key, weight}} loose in the chest, in chest order; used = {[tab] = items now}. Open tabs first, then the
-- locked ones (withdraw-only, as the stash does); an item that fits no tab stays loose. Returns
-- moves = {{key, tab}}, counts = {open = n, locked = n, loose = n} (in items moved, by top-level item).
function D.layout(cfg, tabs, used, items)
	local size = int(cfg.tabSize)
	local max = D.maxTabs(cfg)
	tabs = math.max(0, math.min(max, int(tabs)))
	local room = {}
	for t = 1, max do
		room[t] = size - int(used and used[t])
	end
	local order = {}
	for t = 1, tabs do
		order[#order + 1] = t
	end
	for t = tabs + 1, max do
		order[#order + 1] = t
	end
	local moves, counts = {}, {open = 0, locked = 0, loose = 0}
	for _, it in ipairs(items) do
		local w = math.max(1, int(it.weight))
		local placed
		for _, t in ipairs(order) do
			if room[t] >= w then
				placed = t
				break
			end
		end
		if placed then
			room[placed] = room[placed] - w
			moves[#moves + 1] = {key = it.key, tab = placed}
			if placed <= tabs then
				counts.open = counts.open + 1
			else
				counts.locked = counts.locked + 1
			end
		else
			counts.loose = counts.loose + 1
		end
	end
	return moves, counts
end

-- ---------------------------------------------------------------- views and texts
function D.tabsView(cfg, tabs, used)
	local view = {}
	for t = 1, D.maxTabs(cfg) do
		view[t] = {tab = t, used = int(used and used[t]), size = int(cfg.tabSize), locked = t > int(tabs)}
	end
	return view
end

function D.description(cfg, tab, tabs, used)
	local M = cfg.messages
	if int(tab) <= int(tabs) then
		return string.format(M.descOpen, int(used), int(cfg.tabSize))
	end
	if int(used) > 0 then
		return string.format(M.descLocked, int(used), int(tabs))
	end
	return string.format(M.descLockedEmpty, int(tabs))
end

function D.openText(cfg, tabs)
	local M = cfg.messages
	local max = D.maxTabs(cfg)
	return string.format(M.open, int(tabs), max, int(cfg.tabSize), int(tabs) < max and M.hint or M.allOpen)
end

function D.sortedText(cfg, counts)
	local M = cfg.messages
	local text = string.format(M.sorted, int(counts.open), int(counts.locked))
	if int(counts.loose) > 0 then
		text = text .. string.format(M.leftLoose, int(counts.loose))
	end
	return text
end

return D
