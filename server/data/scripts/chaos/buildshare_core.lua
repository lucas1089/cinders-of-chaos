-- Build sharing: the passive tree build code, without engine calls (buildshare.lua, server/tests/buildshare_test.lua).
--
--   ChaosBuildShare.encode(build[, version])  code string of {classId, nodes = {ids}, paragon = {statKey = points} | nil,
--                                            masteries = {[id] = choice} | nil}; version 5 unless asked (1: no masteries)
--   ChaosBuildShare.decode(code)             build, or nil + error text (bad format, old/unknown version, checksum)
--   ChaosBuildShare.extract(text)            the first code inside any text (a chat line, a "build link"), or nil
--   ChaosBuildShare.plan(tree, build, ctx)   what an import would do for a character (see below), or nil + error text
--
-- Code format, version 5:  "CB5-" .. base64url(payload)   (CB = Chaos Build, 5 = format version)
--   payload = classId (1 byte: index of the class line in CLASS_LINES, 0 = no class; never a vocation id)
--             flags   (1 byte: 1 = a Paragon part follows, 2 = a mastery part follows)
--             [Paragon: count (1 byte), then count x (stat index 1 byte, points 1 byte); stat index into PARAGON_KEYS]
--             [masteries: count (1 byte), then count x (node id 2 bytes, high first, chosen effect 1 byte)]
--             bitset of the allocated node ids: bit (id % 8) of byte floor(id / 8), trailing zero bytes dropped
--             checksum (3 bytes): h = (h * 257 + x) % 16777213 over the characters of "CB5" and every byte before it
-- Version 4 ("CB4-") has the same layout; it was handed out before the four other elemental cluster ends (96, 99, 102,
-- 105) became the second round's keystones, so an import of it leaves those out (B.REWORKED).
-- Version 3 ("CB3-") has the same layout; it was handed out before twelve small leaves became the build archetype
-- keystones (77, 78, 81, 82, 106-109, 253, 262, 355, 362), so an import of it leaves those out (B.REWORKED).
-- Version 2 ("CB2-") has the same layout too; it was handed out before nodes 369, 376, 383 and 390 became keystones, so
-- an import of it leaves those nodes out (B.REWORKED). Version 1 ("CB1-", handed out before the mastery nodes) is the
-- same without the mastery part (flag 2 unused) and is still read: such a code has no mastery choices (an import keeps
-- the character's own, else takes the first effect) and leaves the reworked nodes out too.
-- Typical size: a 248 node level 1000 build ~110 characters, a 40 node build ~20-80.
--
-- The class byte is a class line, not a vocation id, so the vocation ids can change without breaking codes.
-- Stability rule: the bitset is indexed by the node ids of passivetree_data.lua (the client's nodes.lua ids), not by
-- array positions. New nodes are appended with new ids, existing ids are never renumbered or reused; a retired id makes
-- the codes that use it invalid ("unknown node"), every other code stays valid. Paragon stats are indexed by
-- PARAGON_KEYS: append new stat keys at the end, never reorder. A mastery's effects are indexed by their position in the
-- node's list: append new effects, never reorder. A new format gets a new version number; decode keeps reading every
-- version that was ever handed out (B.READS: 1 to 5). A node whose meaning changes gets a new version and a
-- B.REWORKED entry, so the older codes leave it out instead of granting the new meaning.

ChaosBuildShare = ChaosBuildShare or {}
local B = ChaosBuildShare

B.PREFIX = "CB"
B.VERSION = 5
B.READS = {[1] = true, [2] = true, [3] = true, [4] = true, [5] = true} -- every version ever handed out
-- Nodes whose meaning changed (passivetree_config.lua `reworked`): id -> the first code version made with the new
-- meaning. An older code that holds such a node leaves it out on import (with a note), and the nodes only connected
-- through it. Append only. Version 3 (2026-10): 369, 376, 383, 390 became the line keystones (they were mythic leaves).
-- Version 4 (2026-10): twelve small leaves became the build archetype keystones (archetypes_config.lua nodes).
-- Version 5 (2026-10-12): 96, 99, 102, 105 became the second round's keystones (snares, vigils, Hollow Vessel).
B.REWORKED = {[369] = 3, [376] = 3, [383] = 3, [390] = 3,
	[77] = 4, [78] = 4, [81] = 4, [82] = 4, [106] = 4, [107] = 4, [108] = 4, [109] = 4, [253] = 4, [262] = 4, [355] = 4,
	[362] = 4,
	[96] = 5, [99] = 5, [102] = 5, [105] = 5}
-- Nodes taken out of the tree (2026-10, owner: no drown nodes; they are hidden in the client's nodes.lua and not in
-- passivetree_data.lua). A code that holds one leaves it out on import, in any version, with a note.
B.REMOVED = {}
for _, id in ipairs({8, 10, 167, 212, 213, 237, 322, 325, 486, 487, 488, 489, 490, 491, 493, 494, 497, 498, 499, 500, 501,
	502, 503}) do
	B.REMOVED[id] = true
end
-- class lines (the base classes of Chaos.classes.ids); index = the code's class byte. Append only, never reorder.
B.CLASS_LINES = {"warrior", "ranger", "mystic", "thief"}
B.PARAGON_KEYS = {"damage", "critDamage", "health", "reduction", "speed", "mana", "goldFind", "itemFind"}
B.MAX_CODE = 600 -- characters; a full 1024-id bitset is ~180

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local DECODE = {}
for i = 1, #ALPHABET do
	DECODE[ALPHABET:sub(i, i)] = i - 1
end
local MOD = 16777213

local function checksum(head, bytes, count)
	local h = 0
	for i = 1, #head do
		h = (h * 257 + head:byte(i)) % MOD
	end
	for i = 1, count do
		h = (h * 257 + bytes[i]) % MOD
	end
	return h
end

local function toBase64(bytes)
	local out = {}
	for i = 1, #bytes, 3 do
		local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local chars = 2 + (b and 1 or 0) + (c and 1 or 0)
		for k = 1, chars do
			local index = math.floor(n / 64 ^ (4 - k)) % 64
			out[#out + 1] = ALPHABET:sub(index + 1, index + 1)
		end
	end
	return table.concat(out)
end

local function fromBase64(text)
	local bytes = {}
	if #text % 4 == 1 then
		return nil
	end
	for i = 1, #text, 4 do
		local chunk = text:sub(i, i + 3)
		local n = 0
		for k = 1, 4 do
			local ch = chunk:sub(k, k)
			local v = 0
			if ch ~= "" then
				v = DECODE[ch]
				if not v then
					return nil
				end
			end
			n = n * 64 + v
		end
		local count = #chunk - 1
		for k = 1, count do
			bytes[#bytes + 1] = math.floor(n / 256 ^ (3 - k)) % 256
		end
	end
	return bytes
end

local function paragonIndex()
	local index = {}
	for i, key in ipairs(B.PARAGON_KEYS) do
		index[key] = i
	end
	return index
end

-- class line index of a line name ("warrior"), 0 for none / unknown
function B.lineIndex(name)
	for i, line in ipairs(B.CLASS_LINES) do
		if line == name then
			return i
		end
	end
	return 0
end

-- "Warrior" for index 1, nil for 0 / unknown
function B.lineName(index)
	local line = B.CLASS_LINES[index or 0]
	return line and (line:sub(1, 1):upper() .. line:sub(2)) or nil
end

function B.encode(build, version)
	version = version or B.VERSION
	local bytes = {math.max(0, math.min(255, math.floor(tonumber(build.classId) or 0)))}
	local stats = {}
	if build.paragon then
		local index = paragonIndex()
		for _, key in ipairs(B.PARAGON_KEYS) do
			local points = math.floor(tonumber(build.paragon[key]) or 0)
			if points > 0 and index[key] then
				stats[#stats + 1] = {index[key], math.min(points, 255)}
			end
		end
	end
	local mastery = {}
	if version >= 2 and type(build.masteries) == "table" then
		for id, choice in pairs(build.masteries) do
			id, choice = math.floor(tonumber(id) or 0), math.floor(tonumber(choice) or 0)
			if id > 0 and id < 65536 and choice > 0 and choice < 256 then
				mastery[#mastery + 1] = {id, choice}
			end
		end
		table.sort(mastery, function(a, b)
			return a[1] < b[1]
		end)
		while #mastery > 255 do
			table.remove(mastery)
		end
	end
	bytes[2] = (#stats > 0 and 1 or 0) + (#mastery > 0 and 2 or 0)
	if #stats > 0 then
		bytes[#bytes + 1] = #stats
		for _, s in ipairs(stats) do
			bytes[#bytes + 1] = s[1]
			bytes[#bytes + 1] = s[2]
		end
	end
	if #mastery > 0 then
		bytes[#bytes + 1] = #mastery
		for _, m in ipairs(mastery) do
			bytes[#bytes + 1] = math.floor(m[1] / 256)
			bytes[#bytes + 1] = m[1] % 256
			bytes[#bytes + 1] = m[2]
		end
	end
	local bits, maxByte = {}, -1
	for _, raw in ipairs(build.nodes or {}) do
		local id = math.floor(tonumber(raw) or -1)
		if id >= 0 then
			local byte = math.floor(id / 8)
			local bit = 2 ^ (id % 8)
			local current = bits[byte] or 0
			if math.floor(current / bit) % 2 == 0 then
				bits[byte] = current + bit
			end
			maxByte = math.max(maxByte, byte)
		end
	end
	for byte = 0, maxByte do
		bytes[#bytes + 1] = bits[byte] or 0
	end
	local head = B.PREFIX .. version
	local h = checksum(head, bytes, #bytes)
	bytes[#bytes + 1] = math.floor(h / 65536) % 256
	bytes[#bytes + 1] = math.floor(h / 256) % 256
	bytes[#bytes + 1] = h % 256
	return head .. "-" .. toBase64(bytes)
end

function B.extract(text)
	if type(text) ~= "string" then
		return nil
	end
	return text:match("(" .. B.PREFIX .. "%d+%-[%w_%-]+)")
end

function B.decode(code)
	if type(code) ~= "string" then
		return nil, "That is not a build code."
	end
	code = code:gsub("^%s+", ""):gsub("%s+$", "")
	if #code > B.MAX_CODE then
		return nil, "That build code is too long."
	end
	local version, body = code:match("^" .. B.PREFIX .. "(%d+)%-([%w_%-]*)$")
	if not version then
		return nil, "That is not a build code (codes start with " .. B.PREFIX .. B.VERSION .. "-)."
	end
	version = tonumber(version)
	if not B.READS[version] then
		if version < B.VERSION then
			return nil, string.format("That build code is from an old format (version %d) that is no longer read.", version)
		end
		return nil, string.format("That build code is from a newer format (version %d) than this server reads (%d).",
			version, B.VERSION)
	end
	local bytes = fromBase64(body)
	-- canonical form only: the unused low bits of the last character must be zero (else a typo there would pass)
	if not bytes or #bytes < 5 or toBase64(bytes) ~= body then
		return nil, "That build code is damaged (check for a typo or a missing part)."
	end
	local n = #bytes
	local stored = bytes[n - 2] * 65536 + bytes[n - 1] * 256 + bytes[n]
	if checksum(B.PREFIX .. version, bytes, n - 3) ~= stored then
		return nil, "That build code is damaged: the checksum does not match (check for a typo)."
	end
	local build = {classId = bytes[1], nodes = {}}
	local pos = 3
	if bytes[2] % 2 == 1 then
		local count = bytes[pos] or 0
		pos = pos + 1
		build.paragon = {}
		for _ = 1, count do
			local index, points = bytes[pos], bytes[pos + 1]
			if not points or pos + 1 > n - 3 then
				return nil, "That build code is damaged."
			end
			local key = B.PARAGON_KEYS[index]
			if not key then
				return nil, "That build code has a Paragon stat this server does not know."
			end
			build.paragon[key] = points
			pos = pos + 2
		end
	end
	if version >= 2 and math.floor(bytes[2] / 2) % 2 == 1 then
		local count = bytes[pos] or 0
		pos = pos + 1
		build.masteries = {}
		for _ = 1, count do
			local hi, lo, choice = bytes[pos], bytes[pos + 1], bytes[pos + 2]
			if not choice or pos + 2 > n - 3 then
				return nil, "That build code is damaged."
			end
			build.masteries[hi * 256 + lo] = choice
			pos = pos + 3
		end
	end
	build.version = version
	for i = pos, n - 3 do
		local value = bytes[i]
		local base = (i - pos) * 8
		for bit = 0, 7 do
			if math.floor(value / 2 ^ bit) % 2 == 1 then
				build.nodes[#build.nodes + 1] = base + bit
			end
		end
	end
	return build
end

-- ------------------------------------------------------------------------------------------------ import plan
-- tree: passivetree_data.lua; build: decode(); ctx:
--   classId, className (function(id) -> name, optional), keystoneKey (the importer's variant key, nil = none),
--   classKey (the importer's class key: nodes marked for other classes are refused; nil = only unmarked nodes),
--   current = {ids allocated now}, points = passive points owned,
--   paragon = nil (no Paragon part handled) or {unlocked, total, current = {key = n}, max = {key = maxPoints}}
--   currentMasteries = {[id] = choice} of the current tree (the chosen effects of its mastery nodes)
-- Returns plan {nodes (to save, path order), masteries ({[id] = choice} of the saved mastery nodes), wanted, applied,
--   skipped, added, removed, masteryChanged, treeChange, treeReset, paragon (allocation to save or nil), paragonChange,
--   paragonReset, paragonSkipped, notes = {texts}} or nil, error.
-- Mastery nodes take the code's effect; a code without one (version 1) keeps the character's own, else the first effect
-- (with a note). Changing the effect of a mastery the character holds is a respec: it counts as taking points back.
-- Rule when the code needs more points than the character owns: the first N nodes in path order are applied
-- (nodes the character already has first, then nearest to the start, then lowest id), the rest is listed as skipped.
function B.plan(tree, build, ctx)
	local name = ctx.className or function(id)
		return "class " .. tostring(id)
	end
	if (build.classId or 0) ~= (ctx.classId or 0) then
		return nil, string.format("This build is for a %s; you are a %s. Builds can only be imported by the same class line.",
			name(build.classId or 0), name(ctx.classId or 0))
	end
	local set, wanted = {}, 0
	local reworked = 0
	local codeVersion = build.version or B.VERSION
	for _, id in ipairs(build.nodes) do
		local node = tree.nodes[id]
		if not node and B.REMOVED[id] then
			reworked = reworked + 1
		elseif not node then
			return nil, string.format("This build uses node %d, which is not in the passive tree (the tree changed).", id)
		elseif B.REWORKED[id] and codeVersion < B.REWORKED[id] then
			-- made before the node changed its meaning: left out (a free refund at login did the same to saved trees)
			reworked = reworked + 1
		elseif id ~= tree.root and not set[id] then
			set[id] = true
			wanted = wanted + 1
			if node.v and not node.s and not (ctx.keystoneKey and node.v[ctx.keystoneKey]) then
				return nil, string.format("This build takes keystone node %d, which your class has no version of.", id)
			end
			if node.c and not (ctx.classKey and node.c[ctx.classKey]) then
				return nil, string.format("This build takes node %d of another class's path.", id)
			end
		end
	end
	if wanted == 0 and not build.paragon then
		return nil, "This build code has no allocated nodes."
	end
	for id, choice in pairs(build.masteries or {}) do
		local node = tree.nodes[id]
		local count = node and type(node.m) == "table" and #node.m or 0
		if count == 0 then
			return nil, string.format("This build code has a mastery effect for node %d, which is not a mastery node.", id)
		end
		if choice < 1 or choice > count then
			return nil, string.format("This build code picks effect %d of mastery node %d, which has %d.", choice, id, count)
		end
	end

	-- depth from the root through the build's own nodes; a node never reached is disconnected
	local depth, queue, head = {[tree.root] = 0}, {tree.root}, 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		for _, neighbour in ipairs(tree.nodes[current].n or {}) do
			if set[neighbour] and not depth[neighbour] then
				depth[neighbour] = depth[current] + 1
				queue[#queue + 1] = neighbour
			end
		end
	end
	for id in pairs(set) do
		if not depth[id] then
			if reworked == 0 then
				return nil, string.format("This build is broken: node %d is not connected to the start.", id)
			end
			-- it hung on a reworked node that was left out
			set[id] = nil
			wanted = wanted - 1
			reworked = reworked + 1
		end
	end

	local current = {}
	for _, id in ipairs(ctx.current or {}) do
		current[id] = true
	end
	-- path order: grow from the root, always taking the best reachable node
	local order, taken = {}, {[tree.root] = true}
	local frontier = {}
	local function open(id)
		for _, neighbour in ipairs(tree.nodes[id].n or {}) do
			if set[neighbour] and not taken[neighbour] then
				frontier[neighbour] = true
			end
		end
	end
	open(tree.root)
	while true do
		local best
		for id in pairs(frontier) do
			if not best then
				best = id
			else
				local ca, cb = current[id] and 0 or 1, current[best] and 0 or 1
				if ca < cb or (ca == cb and (depth[id] < depth[best] or (depth[id] == depth[best] and id < best))) then
					best = id
				end
			end
		end
		if not best then
			break
		end
		frontier[best] = nil
		taken[best] = true
		order[#order + 1] = best
		open(best)
	end

	local points = math.max(0, math.floor(tonumber(ctx.points) or 0))
	if wanted > 0 and points == 0 then
		return nil, "You have no passive points yet."
	end
	local nodes = {}
	for i = 1, math.min(points, #order) do
		nodes[i] = order[i]
	end
	local final = {}
	for _, id in ipairs(nodes) do
		final[id] = true
	end
	local added, removed, currentCount = 0, 0, 0
	for id in pairs(final) do
		if not current[id] then
			added = added + 1
		end
	end
	for id in pairs(current) do
		currentCount = currentCount + 1
		if not final[id] then
			removed = removed + 1
		end
	end
	-- the effects of the mastery nodes saved
	local masteries, masteryChanged, defaulted = {}, 0, 0
	local held = ctx.currentMasteries or {}
	for _, id in ipairs(nodes) do
		local node = tree.nodes[id]
		if type(node.m) == "table" and #node.m > 0 then
			local choice = build.masteries and build.masteries[id]
			if not choice then
				choice = (current[id] and held[id] and held[id] >= 1 and held[id] <= #node.m) and held[id] or nil
				if not choice then
					choice, defaulted = 1, defaulted + 1
				end
			end
			masteries[id] = choice
			if current[id] and held[id] ~= choice then
				masteryChanged = masteryChanged + 1
			end
		end
	end
	local plan = {
		nodes = nodes, masteries = masteries, wanted = wanted, applied = #nodes, skipped = wanted - #nodes, added = added,
		removed = removed, masteryChanged = masteryChanged,
		treeChange = added > 0 or removed > 0 or masteryChanged > 0, treeReset = removed > 0 or masteryChanged > 0, notes = {}
	}
	if wanted == 0 then
		-- a Paragon-only code leaves the tree alone
		plan.nodes, plan.applied, plan.added, plan.removed, plan.treeChange, plan.treeReset = ctx.current or {}, 0, 0, 0, false, false
		plan.masteries, plan.masteryChanged = held, 0
	end
	if masteryChanged > 0 and wanted > 0 then
		plan.notes[#plan.notes + 1] = string.format("%d mastery node%s you hold change%s effect (a respec).", masteryChanged,
			masteryChanged == 1 and "" or "s", masteryChanged == 1 and "s its" or " their")
	end
	if defaulted > 0 and wanted > 0 then
		plan.notes[#plan.notes + 1] = string.format(
			"The code names no effect for %d mastery node%s: the first effect is taken (change it in the tree).", defaulted,
			defaulted == 1 and "" or "s")
	end
	if plan.skipped > 0 then
		plan.notes[#plan.notes + 1] = string.format(
			"You own %d passive points; the build needs %d. The first %d nodes along the path are applied, %d are left out.",
			points, wanted, #nodes, plan.skipped)
	end
	plan.reworked = reworked
	if reworked > 0 then
		plan.notes[#plan.notes + 1] = string.format(
			"The code is older than a tree change: %d node%s whose effect changed %s left out.", reworked,
			reworked == 1 and "" or "s", reworked == 1 and "is" or "are")
	end

	-- Paragon part
	plan.paragonSkipped = 0
	if build.paragon and ctx.paragon then
		local p = ctx.paragon
		if not p.unlocked then
			plan.notes[#plan.notes + 1] = "The Paragon part of the build is skipped: the Paragon track is not unlocked yet."
		else
			local alloc, left, want = {}, math.max(0, p.total or 0), 0
			for _, key in ipairs(B.PARAGON_KEYS) do
				local requested = build.paragon[key] or 0
				if requested > 0 and p.max and p.max[key] then
					local n = math.min(requested, p.max[key], left)
					want = want + math.min(requested, p.max[key])
					if n > 0 then
						alloc[key] = n
						left = left - n
					end
				end
			end
			local change, reset = false, false
			for _, key in ipairs(B.PARAGON_KEYS) do
				local a, c = alloc[key] or 0, (p.current or {})[key] or 0
				if a ~= c then
					change = true
				end
				if a < c then
					reset = true
				end
			end
			for key, c in pairs(p.current or {}) do
				if c > 0 and not alloc[key] then
					change, reset = true, true
				end
			end
			plan.paragon = alloc
			plan.paragonChange, plan.paragonReset = change, reset
			local applied = 0
			for _, n in pairs(alloc) do
				applied = applied + n
			end
			plan.paragonSkipped = want - applied
			if plan.paragonSkipped > 0 then
				plan.notes[#plan.notes + 1] = string.format(
					"The Paragon part needs %d points, you own %d: %d are left out (in stat order).", want, p.total or 0,
					plan.paragonSkipped)
			end
		end
	end
	return plan
end

return ChaosBuildShare
