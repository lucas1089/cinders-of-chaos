-- Trending builds without engine calls (O409; build_trends.lua, tests/build_trends_test.lua). Lua 5.1 / LuaJIT and 5.3.
--
--   K.isKeystoneFlag(key)                      a keystone's flag: "ks" or "ar" and a capital (passivetree_data.lua stats)
--   K.keystones(tree, nodes, variantKey)       the sorted keystone flags a tree takes (a node's variant for the class)
--   K.signature(flags)                         "ksBulwark+ksCleavingArc" ("" = no keystone): the build's bucket
--   K.group(chars, cfg)                        per class the builds of a snapshot, most played first (see there)
--   K.representative(members)                  the member whose tree is closest to the bucket's majority
--   K.classIndex(vocId)                        the full build code's class byte of a vocation (client buildcode.lua)
--   K.encodeFull(vocId, level, treeCode)       a full build code "CC1-..." of class, level and tree (no spells, no gear)
--   K.keystoneNames(flags, names)              "Bulwark, Cleaving Arc" ("" for none)
--   K.schemaSql(tbl)                           CREATE TABLE IF NOT EXISTS (sql/chaos_build_trends.sql)
--
-- Privacy: a character's id and level go in, only counts, averages and one anonymous tree come out; a build with fewer
-- than cfg.minCount characters is never listed.

ChaosBuildTrendsCore = ChaosBuildTrendsCore or {}
local K = ChaosBuildTrendsCore

local floor = math.floor

-- the full build code's classes (client game_passivetree/buildcode.lua C.CLASSES; append only, never reorder):
-- index = the code's class byte, {class key, vocation id}
K.CLASSES = {
	{"warrior", 4}, {"juggernaut", 8}, {"berserker", 14},
	{"ranger", 3}, {"deadeye", 7}, {"beastmaster", 15},
	{"mystic", 1}, {"elementalist", 5}, {"illusionist", 10},
	{"thief", 11}, {"ninja", 12}, {"samurai", 13},
	{"monk", 17}, {"shadowfist", 18}, {"ironsage", 19},
	{"necromancer", 20}, {"lich", 21}, {"bonelord", 22},
	{"templar", 23}, {"inquisitor", 24}, {"sentinel", 25}
}

function K.isKeystoneFlag(key)
	return type(key) == "string" and (key:match("^ks%u") ~= nil or key:match("^ar%u") ~= nil)
end

-- the stats a keystone node gives the class: its variant for variantKey, else its own
local function nodeStats(node, variantKey)
	if not node then
		return nil
	end
	return (node.v and variantKey and node.v[variantKey]) or node.s
end

function K.keystones(tree, nodes, variantKey)
	local flags, seen = {}, {}
	for _, id in ipairs(nodes or {}) do
		local stats = nodeStats(tree.nodes[id], variantKey)
		for key in pairs(stats or {}) do
			if K.isKeystoneFlag(key) and not seen[key] then
				seen[key] = true
				flags[#flags + 1] = key
			end
		end
	end
	table.sort(flags)
	return flags
end

function K.signature(flags)
	return table.concat(flags or {}, "+")
end

function K.keystoneNames(flags, names)
	local out = {}
	for i, f in ipairs(flags or {}) do
		out[i] = (names or {})[f] or f
	end
	return table.concat(out, ", ")
end

-- members = {{id, level, nodes}}: the one with the highest sum over its nodes of (2 x taken by - members), i.e. the most
-- nodes most members took and the fewest nodes few took; ties: the higher level, then the lower id
function K.representative(members)
	local freq = {}
	for _, m in ipairs(members) do
		for _, id in ipairs(m.nodes or {}) do
			freq[id] = (freq[id] or 0) + 1
		end
	end
	local c = #members
	local best, bestScore
	for _, m in ipairs(members) do
		local score = 0
		for _, id in ipairs(m.nodes or {}) do
			score = score + 2 * freq[id] - c
		end
		local better = not best or score > bestScore
			or (score == bestScore and ((m.level or 0) > (best.level or 0)
				or ((m.level or 0) == (best.level or 0) and (m.id or 0) < (best.id or 0))))
		if better then
			best, bestScore = m, score
		end
	end
	return best
end

-- chars = {{id, class (the class tab key: base class id), level, nodes, flags}} -> {[class] = {total, builds = {{signature,
-- flags, count, share (per mille of the class), level (average, rounded), rep (the representative member)}}}}; builds
-- sorted most played first (then the higher average level, then the signature); only cfg.top builds of at least
-- cfg.minCount characters
function K.group(chars, cfg)
	cfg = cfg or {}
	local byClass = {}
	for _, ch in ipairs(chars or {}) do
		local key = ch.class
		if key ~= nil then
			local cl = byClass[key]
			if not cl then
				cl = {total = 0, buckets = {}, order = {}}
				byClass[key] = cl
			end
			cl.total = cl.total + 1
			local sig = K.signature(ch.flags)
			local b = cl.buckets[sig]
			if not b then
				b = {signature = sig, flags = ch.flags or {}, members = {}, levelSum = 0}
				cl.buckets[sig] = b
				cl.order[#cl.order + 1] = sig
			end
			b.members[#b.members + 1] = ch
			b.levelSum = b.levelSum + (tonumber(ch.level) or 0)
		end
	end
	local out = {}
	for key, cl in pairs(byClass) do
		local list = {}
		for _, sig in ipairs(cl.order) do
			local b = cl.buckets[sig]
			local count = #b.members
			if count >= (cfg.minCount or 3) then
				list[#list + 1] = {signature = sig, flags = b.flags, count = count,
					share = floor(count * 1000 / cl.total + 0.5), level = floor(b.levelSum / count + 0.5),
					rep = K.representative(b.members)}
			end
		end
		table.sort(list, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			if a.level ~= b.level then
				return a.level > b.level
			end
			return a.signature < b.signature
		end)
		while #list > (cfg.top or 5) do
			table.remove(list)
		end
		out[key] = {total = cl.total, builds = list}
	end
	return out
end

-- ---------------------------------------------------------------- the full build code (client buildcode.lua, format 1)
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local DECODE = {}
for i = 1, #ALPHABET do
	DECODE[ALPHABET:sub(i, i)] = i - 1
end
local MOD = 16777213

local function checksum(head, bytes)
	local h = 0
	for i = 1, #head do
		h = (h * 257 + head:byte(i)) % MOD
	end
	for i = 1, #bytes do
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
			local index = floor(n / 64 ^ (4 - k)) % 64
			out[#out + 1] = ALPHABET:sub(index + 1, index + 1)
		end
	end
	return table.concat(out)
end

local function fromBase64(text)
	if #text % 4 == 1 then
		return nil
	end
	local bytes = {}
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
		for k = 1, #chunk - 1 do
			bytes[#bytes + 1] = floor(n / 256 ^ (3 - k)) % 256
		end
	end
	return bytes
end

function K.classIndex(vocId)
	for i, c in ipairs(K.CLASSES) do
		if c[2] == vocId then
			return i
		end
	end
	return nil
end

local function push16(out, v)
	out[#out + 1] = floor(v / 256) % 256
	out[#out + 1] = v % 256
end

-- a full build code of class (vocation id; unknown = left out), level and the tree code; nil when the tree code is bad
function K.encodeFull(vocId, level, treeCode)
	local version, body = tostring(treeCode or ""):match("^CB(%d+)%-([%w_%-]+)$")
	local treeBytes = body and fromBase64(body)
	if not treeBytes or #treeBytes < 5 then
		return nil
	end
	local bytes = {}
	local index = K.classIndex(vocId)
	if index then
		bytes[#bytes + 1] = 1
		push16(bytes, 1)
		bytes[#bytes + 1] = index
	end
	level = floor(tonumber(level) or 0)
	if level >= 1 and level <= 65535 then
		bytes[#bytes + 1] = 2
		push16(bytes, 2)
		push16(bytes, level)
	end
	bytes[#bytes + 1] = 3
	push16(bytes, #treeBytes + 1)
	bytes[#bytes + 1] = tonumber(version)
	for _, b in ipairs(treeBytes) do
		bytes[#bytes + 1] = b
	end
	local head = "CC1"
	local h = checksum(head, bytes)
	bytes[#bytes + 1] = floor(h / 65536) % 256
	bytes[#bytes + 1] = floor(h / 256) % 256
	bytes[#bytes + 1] = h % 256
	return head .. "-" .. toBase64(bytes)
end

-- ---------------------------------------------------------------- SQL
function K.schemaSql(tbl)
	return string.format("CREATE TABLE IF NOT EXISTS `%s` (`snapshot` int unsigned NOT NULL, " ..
		"`class_base` smallint unsigned NOT NULL, `rank` tinyint unsigned NOT NULL, `class_name` varchar(32) NOT NULL " ..
		"DEFAULT '', `signature` varchar(255) NOT NULL DEFAULT '', `keystones` varchar(512) NOT NULL DEFAULT '', " ..
		"`count` int unsigned NOT NULL DEFAULT 0, `total` int unsigned NOT NULL DEFAULT 0, " ..
		"`share` smallint unsigned NOT NULL DEFAULT 0, `avg_level` int unsigned NOT NULL DEFAULT 0, " ..
		"`tree_code` varchar(600) NOT NULL DEFAULT '', `code` varchar(1000) NOT NULL DEFAULT '', " ..
		"PRIMARY KEY (`snapshot`, `class_base`, `rank`)) ENGINE=InnoDB DEFAULT CHARSET=utf8", tbl)
end

return K
