-- Build sharing: the passive tree build code, without engine calls (buildshare.lua, server/tests/buildshare_test.lua).
--
--   ChaosBuildShare.encode(build)            code string of {classId, nodes = {ids}, paragon = {statKey = points} | nil}
--   ChaosBuildShare.decode(code)             build, or nil + error text (bad format, old/unknown version, checksum)
--   ChaosBuildShare.extract(text)            the first code inside any text (a chat line, a "build link"), or nil
--   ChaosBuildShare.plan(tree, build, ctx)   what an import would do for a character (see below), or nil + error text
--
-- Code format, version 1:  "CB1-" .. base64url(payload)   (CB = Chaos Build, 1 = format version)
--   payload = classId (1 byte: index of the class line in CLASS_LINES, 0 = no class; never a vocation id)
--             flags   (1 byte: 1 = a Paragon part follows)
--             [Paragon: count (1 byte), then count x (stat index 1 byte, points 1 byte); stat index into PARAGON_KEYS]
--             bitset of the allocated node ids: bit (id % 8) of byte floor(id / 8), trailing zero bytes dropped
--             checksum (3 bytes): h = (h * 257 + x) % 16777213 over the characters of "CB1" and every byte before it
-- Typical size: a 248 node level 1000 build ~110 characters, a 40 node build ~20-80.
--
-- The class byte is a class line, not a vocation id, so the vocation ids can change without breaking codes.
-- Stability rule: the bitset is indexed by the node ids of passivetree_data.lua (the client's nodes.lua ids), not by
-- array positions. New nodes are appended with new ids, existing ids are never renumbered or reused; a retired id makes
-- the codes that use it invalid ("unknown node"), every other code stays valid. Paragon stats are indexed by
-- PARAGON_KEYS: append new stat keys at the end, never reorder. A new format gets a new version number; decode keeps
-- reading every version that was ever handed out (only version 1 exists).

ChaosBuildShare = ChaosBuildShare or {}
local B = ChaosBuildShare

B.PREFIX = "CB"
B.VERSION = 1
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

function B.encode(build)
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
	bytes[2] = #stats > 0 and 1 or 0
	if #stats > 0 then
		bytes[#bytes + 1] = #stats
		for _, s in ipairs(stats) do
			bytes[#bytes + 1] = s[1]
			bytes[#bytes + 1] = s[2]
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
	local head = B.PREFIX .. B.VERSION
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
	if version ~= B.VERSION then
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
--   current = {ids allocated now}, points = passive points owned,
--   paragon = nil (no Paragon part handled) or {unlocked, total, current = {key = n}, max = {key = maxPoints}}
-- Returns plan {nodes (to save, path order), wanted, applied, skipped, added, removed, treeChange, treeReset,
--   paragon (allocation to save or nil), paragonChange, paragonReset, paragonSkipped, notes = {texts}} or nil, error.
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
	for _, id in ipairs(build.nodes) do
		local node = tree.nodes[id]
		if not node then
			return nil, string.format("This build uses node %d, which is not in the passive tree (the tree changed).", id)
		end
		if id ~= tree.root and not set[id] then
			set[id] = true
			wanted = wanted + 1
			if node.v and not node.s and not (ctx.keystoneKey and node.v[ctx.keystoneKey]) then
				return nil, string.format("This build takes keystone node %d, which your class has no version of.", id)
			end
		end
	end
	if wanted == 0 and not build.paragon then
		return nil, "This build code has no allocated nodes."
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
			return nil, string.format("This build is broken: node %d is not connected to the start.", id)
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
	local plan = {
		nodes = nodes, wanted = wanted, applied = #nodes, skipped = wanted - #nodes, added = added, removed = removed,
		treeChange = added > 0 or removed > 0, treeReset = removed > 0, notes = {}
	}
	if wanted == 0 then
		-- a Paragon-only code leaves the tree alone
		plan.nodes, plan.applied, plan.added, plan.removed, plan.treeChange, plan.treeReset = ctx.current or {}, 0, 0, 0, false, false
	end
	if plan.skipped > 0 then
		plan.notes[#plan.notes + 1] = string.format(
			"You own %d passive points; the build needs %d. The first %d nodes along the path are applied, %d are left out.",
			points, wanted, #nodes, plan.skipped)
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
