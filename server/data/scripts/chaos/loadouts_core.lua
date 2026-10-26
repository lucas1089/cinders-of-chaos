-- Loadouts / Armory: the rules without engine calls (loadouts.lua, server/tests/loadouts_test.lua). Numbers in
-- loadouts_config.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The model (server/README.md "Loadouts"): a loadout is a saved copy of the character's build: passive tree nodes,
-- Paragon allocation, the support runes socketed in the spells, and an equipment set (references to items, never
-- copies). Exactly one loadout is "active": the live build IS that loadout. Switching parks the live build into the
-- active loadout and puts the target's build live. Nothing is priced on a switch, and nothing can be gained by one:
--   * Save copies the live build (the server reads it; the client never sends nodes) into a slot. A copy of a tree the
--     character already has costs nothing and creates no new shape.
--   * A tree only changes while it is live, in the passive tree window, at the normal prices (adding is free, taking
--     nodes back is a priced refund or reset: respec.lua). A parked tree never loses a node.
--   * A switch never drops the live build: without an active loadout it is refused while the live build holds anything.
--   * The support runes belong to the loadout they were socketed in: a switch moves them between the live sockets and
--     that loadout's own storages, never into the backpack. Taking a rune out stays the normal priced removal.
--   * Validation refunds for free only what the game took away (nodes that left the tree or moved, nodes of another
--     class, more nodes / Paragon points than the character owns now), as the passive tree does at login.

ChaosLoadoutsCore = ChaosLoadoutsCore or {}
local C = ChaosLoadoutsCore

local function cfgOf(cfg)
	return cfg or ChaosLoadoutsConfig
end

-- the text in `lang` (ChaosI18n when it is loaded, English otherwise); loadouts.lua passes the language of the reader
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local function msg(cfg, key, ...)
	local text = (cfgOf(cfg).messages or {})[key] or key
	if select("#", ...) > 0 then
		return string.format(text, ...)
	end
	return text
end
C.msg = msg

-- ------------------------------------------------------------------------------------------------ slots
-- usable slots at this level: baseSlots + one per reached `earned` level (+ pactSlots while the Chaos Pact is active:
-- pact = true or a number of slots), at most maxSlots
function C.slotLimit(level, cfg, pact)
	cfg = cfgOf(cfg)
	local n = cfg.baseSlots
	if pact == true then
		n = n + (cfg.pactSlots or 0)
	elseif tonumber(pact) then
		n = n + math.max(0, math.floor(tonumber(pact)))
	end
	for _, e in ipairs(cfg.earned or {}) do
		if (tonumber(level) or 0) >= e.level then
			n = n + 1
		end
	end
	return math.min(n, cfg.maxSlots)
end

-- the level of the next slot, or nil
function C.nextUnlock(level, cfg)
	cfg = cfgOf(cfg)
	local best
	for _, e in ipairs(cfg.earned or {}) do
		if (tonumber(level) or 0) < e.level and (not best or e.level < best) then
			best = e.level
		end
	end
	return best
end

-- "ok" | "locked" | "invalid"
function C.slotState(slot, limit, cfg)
	cfg = cfgOf(cfg)
	slot = tonumber(slot)
	if not slot or slot ~= math.floor(slot) or slot < 1 or slot > cfg.maxSlots then
		return "invalid"
	end
	if slot > (limit or 0) then
		return "locked"
	end
	return "ok"
end

function C.lockedText(level, cfg)
	local nextLevel = C.nextUnlock(level, cfg)
	if nextLevel then
		return msg(cfg, "locked", C.slotLimit(level, cfg), nextLevel)
	end
	return msg(cfg, "lockedMax")
end

-- ------------------------------------------------------------------------------------------------ names and icons
function C.cleanName(name, slot, cfg)
	cfg = cfgOf(cfg)
	local s = tostring(name or "")
	s = s:gsub("[^%w %-_'%.!%+]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	s = s:sub(1, cfg.nameMax or 20):gsub(" $", "")
	if s == "" then
		s = "Loadout " .. tostring(slot or 1)
	end
	return s
end

function C.cleanIcon(icon, cfg)
	cfg = cfgOf(cfg)
	for _, known in ipairs(cfg.icons or {}) do
		if icon == known then
			return icon
		end
	end
	return (cfg.icons or {})[1] or ""
end

-- ------------------------------------------------------------------------------------------------ node lists
-- A saved tree text is "2,3,9" or, with mastery nodes, "2,3,9,665|665:2" (the chosen effect of each mastery node after
-- "|"; the passive tree's own format, passivetree_core.lua parseAlloc / formatAlloc).
function C.parseNodes(text)
	local out, seen = {}, {}
	text = tostring(text or "")
	text = text:match("^([^|]*)") or text
	for token in text:gmatch("%d+") do
		local id = tonumber(token)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

-- the chosen mastery effects of a tree text: {[id] = choice} (only ids of the text)
function C.parseMasteries(text)
	text = tostring(text or "")
	local ids = {}
	for _, id in ipairs(C.parseNodes(text)) do
		ids[id] = true
	end
	local out = {}
	for id, choice in (text:match("|(.*)$") or ""):gmatch("(%d+):(%d+)") do
		id, choice = tonumber(id), tonumber(choice)
		if ids[id] and choice > 0 then
			out[id] = choice
		end
	end
	return out
end

-- masteries: optional {[id] = choice}; only the listed ids' choices are written
function C.formatNodes(ids, masteries)
	local copy, set = {}, {}
	for i, id in ipairs(ids or {}) do
		copy[i] = id
		set[id] = true
	end
	table.sort(copy)
	local text = table.concat(copy, ",")
	local keys = {}
	for id, choice in pairs(masteries or {}) do
		if set[id] and tonumber(choice) and choice > 0 then
			keys[#keys + 1] = id
		end
	end
	if #keys == 0 then
		return text
	end
	table.sort(keys)
	local parts = {}
	for i, id in ipairs(keys) do
		parts[i] = id .. ":" .. math.floor(masteries[id])
	end
	return text .. "|" .. table.concat(parts, ",")
end

-- the choices of `masteries` that are still valid for the kept ids (a mastery node of the tree, an effect it has)
function C.cleanMasteries(tree, ids, masteries)
	local out = {}
	for _, id in ipairs(ids or {}) do
		local node, choice = tree.nodes[id], masteries and tonumber(masteries[id])
		if node and type(node.m) == "table" and choice and choice >= 1 and choice <= #node.m and choice == math.floor(choice) then
			out[id] = choice
		end
	end
	return out
end

function C.sameSet(a, b)
	if #(a or {}) ~= #(b or {}) then
		return false
	end
	local set = {}
	for _, id in ipairs(a) do
		set[id] = true
	end
	for _, id in ipairs(b) do
		if not set[id] then
			return false
		end
	end
	return true
end

-- breadth-first depth of every node of `set` reachable from the root through `set`
local function depths(tree, set)
	local depth, queue, head = {[tree.root] = 0}, {tree.root}, 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		local node = tree.nodes[current]
		for _, neighbour in ipairs(node and node.n or {}) do
			if set[neighbour] and depth[neighbour] == nil then
				depth[neighbour] = depth[current] + 1
				queue[#queue + 1] = neighbour
			end
		end
	end
	return depth
end

-- A saved tree against the tree data and the character now. opts = {classKey, points, allowed = fn(node, classKey)}.
-- Returns kept (sorted ids) and removed ({id, why}: "unknown" (left the tree), "class" (another class's node),
-- "disconnected" (no longer connected: nodes moved), "budget" (more nodes than points; the farthest ones go)).
-- Removing the deepest nodes first keeps every other node connected: each kept node's parent is less deep.
function C.validateTree(tree, ids, opts)
	opts = opts or {}
	local allowed = opts.allowed or function()
		return true
	end
	local removed, set, order = {}, {}, {}
	for _, raw in ipairs(ids or {}) do
		local id = tonumber(raw)
		local node = id and tree.nodes[id]
		if id and id ~= tree.root and not set[id] then
			if not node then
				removed[#removed + 1] = {id = id, why = "unknown"}
			elseif not allowed(node, opts.classKey) then
				removed[#removed + 1] = {id = id, why = "class"}
			else
				set[id] = true
				order[#order + 1] = id
			end
		end
	end
	local depth = depths(tree, set)
	local kept = {}
	for _, id in ipairs(order) do
		if depth[id] then
			kept[#kept + 1] = id
		else
			set[id] = nil
			removed[#removed + 1] = {id = id, why = "disconnected"}
		end
	end
	local points = opts.points
	if points and #kept > points then
		table.sort(kept, function(a, b)
			if depth[a] ~= depth[b] then
				return depth[a] > depth[b]
			end
			return a > b
		end)
		local over = #kept - math.max(0, points)
		for i = 1, over do
			removed[#removed + 1] = {id = kept[i], why = "budget"}
		end
		local rest = {}
		for i = over + 1, #kept do
			rest[#rest + 1] = kept[i]
		end
		kept = rest
	end
	table.sort(kept)
	return kept, removed
end

-- {unknown = n, class = n, disconnected = n, budget = n}
function C.countWhy(removed)
	local out = {}
	for _, r in ipairs(removed or {}) do
		out[r.why] = (out[r.why] or 0) + 1
	end
	return out
end

-- the player's text for free refunds of a validation; nil when nothing was removed
function C.refundText(removed, paragonRemoved, lang)
	local why = C.countWhy(removed)
	local parts = {}
	local function add(n, one, many)
		if n and n > 0 then
			parts[#parts + 1] = T(lang, n == 1 and one or many, n)
		end
	end
	add(why.unknown, "%d node that left the tree", "%d nodes that left the tree")
	add(why.disconnected, "%d node that no longer connects (the tree changed)", "%d nodes that no longer connect (the tree changed)")
	add(why.class, "%d node your class cannot hold", "%d nodes your class cannot hold")
	add(why.budget, "%d node over your passive points", "%d nodes over your passive points")
	if paragonRemoved and paragonRemoved > 0 then
		parts[#parts + 1] = T(lang, paragonRemoved == 1 and "%d Paragon point over what you own" or "%d Paragon points over what you own", paragonRemoved)
	end
	if #parts == 0 then
		return nil
	end
	return T(lang, "Refunded for free: %s.", table.concat(parts, ", "))
end

-- ------------------------------------------------------------------------------------------------ Paragon
function C.paragonSpent(alloc)
	local n = 0
	for _, points in pairs(alloc or {}) do
		n = n + (tonumber(points) or 0)
	end
	return n
end

-- "damage=3,health=4" (keys sorted) <-> {damage = 3, health = 4}
function C.encodeParagon(alloc)
	local keys = {}
	for key, points in pairs(alloc or {}) do
		if type(key) == "string" and key:match("^%w+$") and (tonumber(points) or 0) > 0 then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	local parts = {}
	for i, key in ipairs(keys) do
		parts[i] = key .. "=" .. math.floor(tonumber(alloc[key]))
	end
	return table.concat(parts, ",")
end

function C.decodeParagon(text)
	local out = {}
	for key, points in tostring(text or ""):gmatch("(%w+)=(%d+)") do
		local n = tonumber(points)
		if n and n > 0 then
			out[key] = n
		end
	end
	return out
end

-- defs = {[key] = {maxPoints}}; total = Paragon points owned now. Returns cleaned, removed points (count), all (bool:
-- the whole allocation was refunded because it is over the budget, as paragon.lua does at login)
function C.validateParagon(alloc, defs, total)
	local out, removed = {}, 0
	for key, points in pairs(alloc or {}) do
		local d = defs and defs[key]
		points = math.floor(tonumber(points) or 0)
		if not d then
			removed = removed + math.max(0, points)
		elseif points > 0 then
			local capped = math.min(points, d.maxPoints or points)
			removed = removed + (points - capped)
			out[key] = capped
		end
	end
	local spent = C.paragonSpent(out)
	if spent > (tonumber(total) or 0) then
		return {}, removed + spent, true
	end
	return out, removed, false
end

-- ------------------------------------------------------------------------------------------------ keystones
-- "ksArcaneEcho" -> "Arcane Echo"
function C.keystoneName(stat)
	local s = tostring(stat or ""):gsub("^ks", "")
	s = s:gsub("(%l)(%u)", "%1 %2")
	return s
end

-- names of the keystones among ids (stats starting "ks"; the per-class variant when the node has one), by node id
function C.keystones(tree, ids, variantKey)
	local sorted = {}
	for i, id in ipairs(ids or {}) do
		sorted[i] = id
	end
	table.sort(sorted)
	local out = {}
	for _, id in ipairs(sorted) do
		local node = tree.nodes[id]
		local stats = node and ((node.v and variantKey and node.v[variantKey]) or node.s)
		local names = {}
		for stat in pairs(stats or {}) do
			if type(stat) == "string" and stat:match("^ks%u") then
				names[#names + 1] = C.keystoneName(stat)
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			out[#out + 1] = name
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ switching gate
function C.cooldownLeft(lastSwitch, now, cfg)
	lastSwitch = tonumber(lastSwitch) or 0
	if lastSwitch <= 0 then
		return 0
	end
	return math.max(0, lastSwitch + cfgOf(cfg).cooldownSeconds - (tonumber(now) or 0))
end

-- ctx = {level, inCombat, busy (text of the instance or nil), inPz, cooldownLeft, casting}
-- Returns "instant" (protection zone) or "cast" (a castMs channel elsewhere), or nil and the reason.
function C.switchGate(ctx, cfg)
	cfg = cfgOf(cfg)
	if (ctx.level or 0) < cfg.minLevel then
		return nil, msg(cfg, "lowLevel", cfg.minLevel)
	end
	if ctx.casting then
		return nil, msg(cfg, "casting")
	end
	if ctx.busy then
		return nil, msg(cfg, "busy", ctx.busy)
	end
	if ctx.inCombat then
		return nil, msg(cfg, "combat")
	end
	if (ctx.cooldownLeft or 0) > 0 then
		return nil, msg(cfg, "cooldown", ctx.cooldownLeft)
	end
	return ctx.inPz and "instant" or "cast"
end

-- a channel in progress: "wait" | "done" | "moved" | "hit"
function C.castStep(cast, now, pos, inCombat)
	if inCombat then
		return "hit"
	end
	if pos and (pos.x ~= cast.pos.x or pos.y ~= cast.pos.y or pos.z ~= cast.pos.z) then
		return "moved"
	end
	if now >= cast.endMs then
		return "done"
	end
	return "wait"
end

-- ------------------------------------------------------------------------------------------------ the anti-dodge plans
-- arm = {active = slot or 0, limit, slots = {[slot] = {runes = n}} (saved slots only),
--        live = {nodes = n, paragon = n, runes = n}}
local function liveHolds(arm)
	local live = arm.live or {}
	return (live.nodes or 0) > 0 or (live.paragon or 0) > 0 or (live.runes or 0) > 0
end

-- load (switch to) `target`: plan {park = slot the live build goes into (or nil), load = target}
function C.planLoad(arm, target, cfg)
	local state = C.slotState(target, arm.limit, cfg)
	if state == "invalid" then
		return nil, msg(cfg, "noSlot")
	end
	if state == "locked" then
		return nil, "locked"
	end
	if not (arm.slots or {})[target] then
		return nil, msg(cfg, "empty")
	end
	local active = arm.active or 0
	if active == target then
		return nil, msg(cfg, "alreadyActive")
	end
	if active == 0 or not arm.slots[active] then
		-- the live build is not saved anywhere: a switch would drop it (a free reset). Only an empty build may go.
		if liveHolds(arm) then
			return nil, msg(cfg, "saveFirst")
		end
		return {park = nil, load = target, cost = 0}
	end
	return {park = active, load = target, cost = 0}
end

-- save the live build into `slot`: plan {slot, copy (a slot other than the active one), activate (no loadout was
-- active: the live build is now this loadout)}. Supports are never copied (the runes stay where they are).
function C.planSave(arm, slot, cfg)
	local state = C.slotState(slot, arm.limit, cfg)
	if state == "invalid" then
		return nil, msg(cfg, "noSlot")
	end
	if state == "locked" then
		return nil, "locked"
	end
	local active = arm.active or 0
	local hasActive = active ~= 0 and (arm.slots or {})[active] ~= nil
	local row = (arm.slots or {})[slot]
	if not hasActive and row and (row.runes or 0) > 0 then
		-- it would become the live build: its parked runes would have nowhere to go
		return nil, msg(cfg, "holdsRunesSave", row.runes, row.runes == 1 and "" or "s")
	end
	return {slot = slot, copy = hasActive and active ~= slot, activate = not hasActive, cost = 0}
end

-- delete `slot`: refused while it holds support runes (they would be lost); deleting the active loadout keeps the
-- live build as it is (it is just not saved any more)
function C.planDelete(arm, slot, cfg)
	if C.slotState(slot, (cfgOf(cfg)).maxSlots, cfg) ~= "ok" then
		return nil, msg(cfg, "noSlot")
	end
	local row = (arm.slots or {})[slot]
	if not row then
		return nil, msg(cfg, "empty")
	end
	local active = arm.active or 0
	if slot ~= active and (row.runes or 0) > 0 then
		return nil, msg(cfg, "holdsRunes", row.runes, row.runes == 1 and "" or "s")
	end
	return {slot = slot, deactivate = slot == active}
end

-- crash recovery at login: the switch writes the database first (with an undo record and serial + 1), then the player
-- storages (runes, active slot, serial) and saves the player. "ok" | "rollback" (database ahead by one: undo it) |
-- "adopt" (anything else, e.g. a restored backup: take the database serial)
function C.recoverAction(storageSerial, sqlSerial)
	storageSerial, sqlSerial = math.max(0, tonumber(storageSerial) or 0), math.max(0, tonumber(sqlSerial) or 0)
	if storageSerial == sqlSerial then
		return "ok"
	end
	if sqlSerial == storageSerial + 1 then
		return "rollback"
	end
	return "adopt"
end

-- ------------------------------------------------------------------------------------------------ support runes
-- layout = {[spellId] = {[1..3] = rune id or 0}}
function C.mirrorSpan(maxSpellId)
	return ((tonumber(maxSpellId) or 499) + 1) * 4
end

function C.mirrorKey(slot, spellId, socket, cfg, maxSpellId)
	cfg = cfgOf(cfg)
	return cfg.runeMirrorBase + (slot - 1) * C.mirrorSpan(maxSpellId) + spellId * 4 + socket
end

function C.runeCount(layout)
	local n = 0
	for _, sockets in pairs(layout or {}) do
		for _, id in pairs(sockets) do
			if (tonumber(id) or 0) > 0 then
				n = n + 1
			end
		end
	end
	return n
end

-- the runes of a parked layout that go live: kept (spell still exists, rune still a rune), giveBack (the spell is gone:
-- the rune returns as an item, free) and dropped (the rune type is gone: nothing to give)
function C.planRestore(layout, spellExists, isRune)
	local keep, giveBack, dropped = {}, {}, {}
	local spells = {}
	for spellId in pairs(layout or {}) do
		spells[#spells + 1] = spellId
	end
	table.sort(spells)
	for _, spellId in ipairs(spells) do
		for socket = 1, 3 do
			local id = tonumber(layout[spellId][socket]) or 0
			if id > 0 then
				if not isRune(id) then
					dropped[#dropped + 1] = {spell = spellId, socket = socket, rune = id}
				elseif not spellExists(spellId) then
					giveBack[#giveBack + 1] = {spell = spellId, socket = socket, rune = id}
				else
					keep[spellId] = keep[spellId] or {0, 0, 0}
					keep[spellId][socket] = id
				end
			end
		end
	end
	return keep, giveBack, dropped
end

-- "spell:r1/r2/r3;spell:..." <-> layout (the summary column of chaos_loadouts; the storages are the truth)
function C.encodeRunes(layout)
	local spells = {}
	for spellId, sockets in pairs(layout or {}) do
		local any = false
		for socket = 1, 3 do
			if (tonumber(sockets[socket]) or 0) > 0 then
				any = true
			end
		end
		if any then
			spells[#spells + 1] = spellId
		end
	end
	table.sort(spells)
	local parts = {}
	for i, spellId in ipairs(spells) do
		local s = layout[spellId]
		parts[i] = string.format("%d:%d/%d/%d", spellId, tonumber(s[1]) or 0, tonumber(s[2]) or 0, tonumber(s[3]) or 0)
	end
	return table.concat(parts, ";")
end

function C.decodeRunes(text)
	local out = {}
	for spell, a, b, c in tostring(text or ""):gmatch("(%d+):(%d+)/(%d+)/(%d+)") do
		out[tonumber(spell)] = {tonumber(a), tonumber(b), tonumber(c)}
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ gear
-- an item as the gear planner sees it: {id = type id (de-equipped form), iid = per-item id as a decimal string or "",
-- name, ref (engine object), where = "slot" | "backpack" | "inbox", slot (when equipped)}
-- A reference matches by its per-item id when it has one; an item without one (no rarity, no modifiers) matches any
-- other plain item of the same type, never an item that has one (that would be another item).
function C.matches(want, item)
	if not want or not item or want.empty then
		return false
	end
	if (want.iid or "") ~= "" then
		return item.iid == want.iid
	end
	return (item.iid or "") == "" and item.id == want.id
end

function C.iidString(v)
	local n = tonumber(v)
	if not n or n <= 0 then
		return ""
	end
	return string.format("%.0f", math.floor(n))
end

-- set = {[slot] = {id, iid, name} | {empty = true}} (a slot without an entry is not part of the set)
-- equipped = {[slot] = item}; pool = {items in the backpack (and the inbox)}; slots = order of the slots.
-- Returns steps {slot, action = "keep" | "equip" | "clear" | "missing", item, want}; an item is used once.
function C.planGear(set, equipped, pool, slots)
	local steps, used, settled = {}, {}, {}
	for _, slot in ipairs(slots) do
		local want, cur = set[slot], equipped[slot]
		if want and ((want.empty and not cur) or (cur and C.matches(want, cur))) then
			steps[slot] = {slot = slot, action = "keep", item = cur, want = want}
			settled[slot] = true
			if cur then
				used[cur] = true
			end
		end
	end
	for _, slot in ipairs(slots) do
		local want = set[slot]
		if want and not settled[slot] then
			if want.empty then
				steps[slot] = {slot = slot, action = "clear", item = equipped[slot], want = want}
			else
				local found
				for _, other in ipairs(slots) do
					local item = equipped[other]
					if not found and other ~= slot and not settled[other] and item and not used[item] and C.matches(want, item) then
						found = item
					end
				end
				for _, item in ipairs(pool or {}) do
					if not found and not used[item] and C.matches(want, item) then
						found = item
					end
				end
				if found then
					used[found] = true
					steps[slot] = {slot = slot, action = "equip", item = found, want = want}
				else
					steps[slot] = {slot = slot, action = "missing", want = want}
				end
			end
		end
	end
	local out = {}
	for _, slot in ipairs(slots) do
		if steps[slot] then
			out[#out + 1] = steps[slot]
		end
	end
	return out
end

-- {total = items in the set, ready = equipped or carried (or in the inbox), missing = {{slot, name}}}
function C.gearSummary(steps)
	local total, ready, missing = 0, 0, {}
	for _, s in ipairs(steps or {}) do
		if not s.want.empty then
			total = total + 1
			if s.action == "missing" then
				missing[#missing + 1] = {slot = s.slot, name = s.want.name or "?"}
			else
				ready = ready + 1
			end
		end
	end
	return {total = total, ready = ready, missing = missing}
end

-- the gear set column: "slot=id:iid:name|slot=empty" (names without | = :)
function C.encodeGear(set, slots)
	local parts = {}
	for _, slot in ipairs(slots) do
		local w = set[slot]
		if w then
			if w.empty then
				parts[#parts + 1] = slot .. "=empty"
			else
				local name = tostring(w.name or ""):gsub("[|=:]", "")
				parts[#parts + 1] = string.format("%d=%d:%s:%s", slot, tonumber(w.id) or 0, w.iid or "", name)
			end
		end
	end
	return table.concat(parts, "|")
end

-- a set saved before the quiver went to the off-hand (engine patch 0023) or while slot 10, the old ammunition slot, was
-- the second ring slot (0023 until 0058): a quiver in slot 10 is the set's off-hand item (slot 5) when the set leaves
-- that hand empty. Slot 10 is never part of a set any more (it takes nothing since 0058): a ring saved there is
-- dropped from the set. isQuiver(id): ChaosArchery.isQuiverId by default.
C.OFF_HAND, C.AMMO_SLOT = 5, 10
function C.legacyGear(set, isQuiver)
	isQuiver = isQuiver or (ChaosArchery and ChaosArchery.isQuiverId)
	local q = set[C.AMMO_SLOT]
	if q and not q.empty and isQuiver and isQuiver(q.id) then
		local off = set[C.OFF_HAND]
		if off == nil or off.empty then
			set[C.OFF_HAND] = q
		end
	end
	set[C.AMMO_SLOT] = nil
	return set
end

function C.decodeGear(text, isQuiver)
	local out = {}
	for part in tostring(text or ""):gmatch("[^|]+") do
		local slot, rest = part:match("^(%d+)=(.*)$")
		slot = tonumber(slot)
		if slot then
			if rest == "empty" then
				out[slot] = {empty = true}
			else
				local id, iid, name = rest:match("^(%d+):(%d*):(.*)$")
				if id and tonumber(id) > 0 then
					out[slot] = {id = tonumber(id), iid = iid or "", name = name or ""}
				end
			end
		end
	end
	return C.legacyGear(out, isQuiver)
end

return ChaosLoadoutsCore
