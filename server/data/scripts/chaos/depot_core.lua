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
--   D.decide(cfg, m)                          nil = allowed, else {code = "locked" | "full" | "chest" | "closed", text}
--   D.layout(cfg, tabs, used, items)          places loose chest items into tabs (migration)
--   D.tabsView(cfg, tabs, used)               {{tab, used, size, locked}} for the client and the texts
--   D.description(cfg, tab, tabs, used, name)  the look text of a box (a named tab: the name first)
--   D.openRefusal(cfg, m)                     nil when the depot window may switch to a tab, else the refusal text
--   D.cleanName(cfg, raw)                     a tab name as stored ("" = default), or nil, reason
--   D.colorKey(cfg, key)                      a palette key ("" = default), or nil
--   D.styleRequest(cfg, d)                    {tab, name, color} of a client request, or nil, reason
--   D.stylesFromRows(cfg, rows), D.styleLists(cfg, styles)  the stored tab styles; per-tab lists for the client
--   D.openText(cfg, tabs)                     the line shown when a locker opens
--   D.lockerOpen(cfg, transition, tabs)       {text, stash}: the locker line, and whether the stash window opens too
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
--      tabs = n, used = items in the target tab now, weight = what the move adds, split = part of a stack,
--      closed = the depot is withdraw-only (stash_config.lua depot.withdrawOnly: the stash took over)}
function D.decide(cfg, m)
	local to, from = m.to or {kind = "other"}, m.from or {kind = "other"}
	local M = cfg.messages
	local tabs = int(m.tabs)
	if m.closed and to.kind ~= "other" then
		-- nothing new goes in; moving within the same tab (or loose in the same chest) stays possible
		local same = (from.kind == "tab" and m.sameTab) or ((from.kind == "chest" or from.kind == "loose") and
			(to.kind == "chest" or to.kind == "loose") and m.sameChest)
		if not (same and not m.split) then
			return {code = "closed", text = M.closed}
		end
		return nil
	end
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

function D.description(cfg, tab, tabs, used, name)
	local M = cfg.messages
	local text
	if int(tab) <= int(tabs) then
		text = string.format(M.descOpen, int(used), int(cfg.tabSize))
	elseif int(used) > 0 then
		text = string.format(M.descLocked, int(used), int(tabs))
	else
		text = string.format(M.descLockedEmpty, int(tabs))
	end
	if type(name) == "string" and name ~= "" then
		return string.format(M.descNamed, name, text)
	end
	return text
end

-- ---------------------------------------------------------------- the depot window: switching tabs
-- m = {tab, chestOpen (the player has this town's depot chest open), near (next to the locker it was opened at),
-- hasBox (the chest holds that tab's box)}. nil = the client may open the box, else the refusal text. A locked tab opens
-- too: it is withdraw-only, the move rule keeps it so.
function D.openRefusal(cfg, m)
	local M = cfg.messages
	local tab = tonumber(m.tab)
	if not tab or tab ~= math.floor(tab) or tab < 1 or tab > D.maxTabs(cfg) then
		return M.openNoTab
	end
	if not m.chestOpen or not m.near then
		return M.openFar
	end
	if not m.hasBox then
		return M.openNoTab
	end
	return nil
end

-- ---------------------------------------------------------------- tab names and colours
-- a UTF-8 sequence of U+00A0 .. U+00FF becomes its Latin-1 byte (the client draws cp1252 / Latin-1)
local function latin1(s)
	return (s:gsub("[\194\195][\128-\191]", function(c)
		local b1, b2 = c:byte(1, 2)
		local code = (b1 - 192) * 64 + (b2 - 128)
		if code < 160 then
			return c -- U+0080 .. U+009F: control characters, refused below
		end
		return string.char(code)
	end))
end

-- the name a player typed -> the stored name ("" = the default name), or nil and the reason. Trimmed, inner runs of
-- spaces made one; printable ASCII and Latin-1 only; at most cfg.nameMax characters.
function D.cleanName(cfg, raw)
	local M = cfg.messages
	if raw == nil then
		return ""
	end
	if type(raw) ~= "string" then
		return nil, M.nameChars
	end
	local s = latin1(raw):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if s:find("\0", 1, true) or s:find("[\1-\31\127-\159]") then
		return nil, M.nameChars
	end
	if #s > int(cfg.nameMax) then
		return nil, string.format(M.nameLong, int(cfg.nameMax))
	end
	return s
end

-- palette key -> entry; "" and "default" -> "" (the default colour); anything else -> nil
function D.colorKey(cfg, key)
	if key == nil or key == "" or key == "default" then
		return ""
	end
	for _, p in ipairs(cfg.palette) do
		if p.key == key then
			return p.key, p
		end
	end
	return nil
end

-- a style request {tab, name, color} -> {tab, name, color} or nil and the reason. Any tab of the chest, locked too.
function D.styleRequest(cfg, d)
	if type(d) ~= "table" then
		return nil, cfg.messages.openNoTab
	end
	local tab = tonumber(d.tab)
	if not tab or tab ~= math.floor(tab) or tab < 1 or tab > D.maxTabs(cfg) then
		return nil, cfg.messages.openNoTab
	end
	local name, why = D.cleanName(cfg, d.name)
	if not name then
		return nil, why
	end
	local color = D.colorKey(cfg, d.color)
	if not color then
		return nil, cfg.messages.badColor
	end
	return {tab = tab, name = name, color = color}
end

-- rows {tab, name, color} of the table -> {[tab] = {name, color}}; rows out of range or with a bad value are skipped
function D.stylesFromRows(cfg, rows)
	local out = {}
	for _, r in ipairs(rows or {}) do
		local s = D.styleRequest(cfg, {tab = r.tab, name = r.name, color = r.color})
		if s and (s.name ~= "" or s.color ~= "") then
			out[s.tab] = {name = s.name, color = s.color}
		end
	end
	return out
end

-- {[tab] = {name, color}} -> names, colors: one string per tab ("" = default), for the client
function D.styleLists(cfg, styles)
	local names, colors = {}, {}
	for t = 1, D.maxTabs(cfg) do
		local s = styles and styles[t]
		names[t] = s and s.name or ""
		colors[t] = s and s.color or ""
	end
	return names, colors
end

function D.openText(cfg, tabs)
	local M = cfg.messages
	local max = D.maxTabs(cfg)
	return string.format(M.open, int(tabs), max, int(cfg.tabSize), int(tabs) < max and M.hint or M.allOpen)
end

-- what a locker opening shows besides the depot window: {text, stash}. text: the locker line (withdraw-only while the
-- stash transition runs, else the tab line). stash: true only when stash_config.lua depot.openStash asks for the stash
-- window as well. Owner report 2026-10-20: a depot chest opened the depot and the stash together; the stash opens
-- from its own entry points only (top bar, keybind, the stash keeper NPC).
function D.lockerOpen(cfg, transition, tabs)
	local tr = type(transition) == "table" and transition or {}
	return {
		text = tr.withdrawOnly == true and cfg.messages.closed or D.openText(cfg, tabs),
		stash = tr.openStash == true
	}
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
