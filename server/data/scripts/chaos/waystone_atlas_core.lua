-- Waystone Atlas: the pure part (no engine calls), shared by waystone_atlas.lua and tests/waystone_atlas_test.lua.
-- The tree rules (index, allocate, refund, sanitize, text, respec) are the Rift Atlas's (atlas_core.lua) on this
-- atlas's own config; this file adds the grid (map x tier, Rare per tier), the effects on a waystone run and the
-- payloads of the client window (game_riftatlas, waystone mode).
--   grid     WC.cells / earned / runCells / credit / cellName
--   effects  WC.resolve: the map opener's summed nodes for one run (band, modifiers), capped, keystone on top
--   drops    WC.dropRows (Normal weight cut by `rarer`), WC.dropTier (tier step and tierUp)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not (ChaosAtlasCore and ChaosAtlasCore.canAllocate) then
	dofile("data/scripts/chaos/atlas_core.lua")
end

ChaosWaystoneAtlasCore = ChaosWaystoneAtlasCore or {}
local WC = ChaosWaystoneAtlasCore
local A = ChaosAtlasCore

local floor = math.floor
local ROMAN = {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV"}
WC.ROMAN = ROMAN

-- ===================================================================== grid
-- the maps of each band in order: {[band] = {map index, ...}} (tcfg = waystone_tiers_config.lua)
function WC.bandMaps(tcfg)
	local out = {}
	for bi, b in ipairs(tcfg.bands or {}) do
		out[bi] = {}
		for i, m in ipairs(tcfg.maps or {}) do
			for _, bt in ipairs(b.maps or {}) do
				if bt == m.tier then
					out[bi][#out[bi] + 1] = i
				end
			end
		end
	end
	return out
end

-- the band index of map i
function WC.bandOfMap(tcfg, i)
	for bi, list in ipairs(WC.bandMaps(tcfg)) do
		for _, m in ipairs(list) do
			if m == i then
				return bi
			end
		end
	end
	return nil
end

-- every cell: {key, kind = "map"|"rare", map, slot (1-4 in its band), tier, points}. Keys: m<map>.<tier>, r<tier>.
function WC.cells(cfg, tcfg)
	local list = {}
	local P = cfg.points
	local bm = WC.bandMaps(tcfg)
	for bi, b in ipairs(tcfg.bands or {}) do
		for t = b.first, b.last do
			for slot, i in ipairs(bm[bi]) do
				list[#list + 1] = {key = "m" .. i .. "." .. t, kind = "map", map = i, slot = slot, tier = t, points = P.map}
			end
		end
	end
	for t = 1, cfg.tiers do
		list[#list + 1] = {key = "r" .. t, kind = "rare", tier = t, points = P.rare}
	end
	return list
end

function WC.cellMap(cfg, tcfg)
	local map = {}
	for _, c in ipairs(WC.cells(cfg, tcfg)) do
		map[c.key] = c
	end
	return map
end

function WC.maxPoints(cfg, tcfg)
	local n = 0
	for _, c in ipairs(WC.cells(cfg, tcfg)) do
		n = n + c.points
	end
	return n
end

function WC.earned(cfg, tcfg, done)
	local map, n = WC.cellMap(cfg, tcfg), 0
	for k, v in pairs(done or {}) do
		if v and map[k] then
			n = n + map[k].points
		end
	end
	return n
end

-- the cells a completed run earns. info = {map, tier, rare = true when opened from a Rare waystone}
function WC.runCells(cfg, tcfg, info)
	local out = {}
	local t, i = floor(tonumber(info.tier) or 0), floor(tonumber(info.map) or 0)
	if t < 1 or t > cfg.tiers then
		return out
	end
	local key = "m" .. i .. "." .. t
	if WC.cellMap(cfg, tcfg)[key] then
		out[#out + 1] = key
	end
	if info.rare then
		out[#out + 1] = "r" .. t
	end
	return out
end

function WC.credit(cfg, tcfg, done, keys)
	local map = WC.cellMap(cfg, tcfg)
	local new, pts = {}, 0
	for _, k in ipairs(keys) do
		local c = map[k]
		if c and not done[k] then
			done[k] = true
			new[#new + 1] = c
			pts = pts + c.points
		end
	end
	return new, pts
end

-- "Ashen Plain, Tier VI" / "Rare, Tier VI"
function WC.cellName(cfg, c)
	if c.kind == "map" then
		return string.format("%s, Tier %s", tostring(cfg.mapNames[c.map] or ("Map " .. c.map)), ROMAN[c.tier] or c.tier)
	end
	return string.format("Rare, Tier %s", ROMAN[c.tier] or c.tier)
end

function WC.sanitize(cfg, tcfg, alloc, done)
	return A.sanitize(cfg, nil, alloc, done, WC.earned(cfg, tcfg, done))
end

-- ===================================================================== effects
local KEYS = {"quantity", "rarity", "experience", "waystone", "modReward", "tierUp", "rarer", "bossExtra"}
WC.STATS = KEYS

-- the effects of the opener's atlas on one run. ctx = {theme = the map's band theme, mods = number of modifiers}.
-- A stat with a theme counts only in maps of that band. Returns the final numbers the hooks read:
--   quantity, rarity, experience (percent), waystone (percent chance), modRewardMult (x the modifiers' bonuses),
--   tierUp (percent), tierStep, rarer (percent; 100 = never Normal), bossExtra (percent), bossExtraFlat, dropLoss,
--   noBossDrop, keystone (name)
function WC.resolve(cfg, alloc, ctx)
	ctx = ctx or {}
	local am = {}
	for _, k in ipairs(KEYS) do
		am[k] = 0
	end
	for _, e in ipairs(A.entries(cfg, alloc or {})) do
		if not e.theme or e.theme == ctx.theme then
			am[e.stat] = (am[e.stat] or 0) + e.value
		end
	end
	for k, cap in pairs(cfg.caps or {}) do
		if type(am[k]) == "number" and am[k] > cap then
			am[k] = cap
		end
	end
	am.modRewardMult = 1 + am.modReward / 100
	am.tierStep, am.bossExtraFlat, am.dropLoss = 0, 0, 0
	for _, n in ipairs(A.index(cfg).list) do
		local ks = alloc and alloc[n.id] and n.keystone and cfg.keystones[n.keystone]
		if ks then
			am.keystone = n.name
			if (tonumber(ctx.mods) or 0) == 0 then
				am.quantity = am.quantity + (ks.pureQuantity or 0)
				am.experience = am.experience + (ks.pureExperience or 0)
			end
			am.modRewardMult = am.modRewardMult * (ks.modRewardMult or 1)
			am.bossExtraFlat = am.bossExtraFlat + (ks.bossExtraFlat or 0)
			am.dropLoss = math.max(am.dropLoss, ks.dropLoss or 0)
			am.tierStep = am.tierStep + (ks.tierStep or 0)
			if ks.noBossDrop then
				am.noBossDrop = true
			end
			if ks.neverNormal then
				am.rarer = 100
			end
			am.quantity = am.quantity + (ks.quantity or 0)
		end
	end
	return am
end

-- the drop rarity rows {{name, weight}} with the Normal weight cut by `rarer` percent (100: no Normal). Weights x 100,
-- whole numbers (W.weighted rolls rand(1, total))
function WC.dropRows(rows, rarer)
	rarer = math.max(0, math.min(100, floor(tonumber(rarer) or 0)))
	local out = {}
	for _, r in ipairs(rows or {}) do
		local w = floor(r[2] * 100)
		if r[1] == "Normal" then
			w = floor(r[2] * (100 - rarer))
		end
		out[#out + 1] = {r[1], w}
	end
	return out
end

-- the tier of a dropped waystone after the atlas: + tierStep, + 1 more with tierUp percent (roll = 1..100), at most max
function WC.dropTier(am, t, maxTier, roll)
	if not am or not t then
		return t
	end
	t = t + (am.tierStep or 0)
	if (am.tierUp or 0) > 0 and roll and roll <= am.tierUp then
		t = t + 1
	end
	return math.min(t, maxTier or t)
end

-- ===================================================================== payloads (client game_riftatlas, waystone mode)
-- the grid as rows for the window: four map rows (the n-th map of each band, cells at their tier's column) and Rare
function WC.gridRows(cfg, tcfg)
	local rows = {}
	for slot = 1, 4 do
		rows[slot] = {label = "Map " .. ROMAN[slot], color = "#d6c9ae", cells = {}}
	end
	local rare = {label = "Rare", color = "#f6cf72", cells = {}}
	for _, c in ipairs(WC.cells(cfg, tcfg)) do
		local cell = {k = c.key, n = WC.cellName(cfg, c), c = c.tier, p = c.points}
		if c.kind == "map" then
			local row = rows[c.slot]
			if row then
				local bi = WC.bandOfMap(tcfg, c.map)
				local b = cfg.branches[bi]
				cell.co = b and b.color or nil
				row.cells[#row.cells + 1] = cell
			end
		else
			rare.cells[#rare.cells + 1] = cell
		end
	end
	rows[#rows + 1] = rare
	return rows
end

function WC.treePayload(cfg, tcfg)
	local nodes = {}
	for _, n in ipairs(A.index(cfg).list) do
		local links = {}
		for _, l in ipairs(n.links or {}) do
			links[#links + 1] = l
		end
		nodes[#nodes + 1] = {i = n.id, n = n.name, k = n.kind or "small", b = n.branch or "", x = n.x, y = n.y,
			c = A.cost(cfg, n), l = links, t = A.nodeLines(cfg, n), g = n.glyph or "rolls"}
	end
	local branches = {}
	for _, b in ipairs(cfg.branches) do
		branches[#branches + 1] = {k = b.key, n = b.name, th = b.theme, d = b.dir, c = b.color}
	end
	return {kind = "waystone", nodes = nodes, branches = branches, start = cfg.startId, keystoneMax = cfg.keystoneMax,
		grid = {tiers = cfg.tiers, rows = WC.gridRows(cfg, tcfg)}, max = WC.maxPoints(cfg, tcfg)}
end

function WC.statePayload(cfg, tcfg, st, msg)
	local alloc, done = {}, {}
	for id, v in pairs(st.alloc) do
		if v then
			alloc[#alloc + 1] = id
		end
	end
	table.sort(alloc)
	for k, v in pairs(st.done) do
		if v then
			done[#done + 1] = k
		end
	end
	table.sort(done)
	local earned, spent = WC.earned(cfg, tcfg, st.done), A.spent(cfg, st.alloc)
	return {earned = earned, spent = spent, points = earned - spent, max = WC.maxPoints(cfg, tcfg), alloc = alloc,
		done = done, refund = A.refundPrice(cfg, 1), reset = A.resetPrice(cfg, st.alloc), orb = cfg.respec.orbName,
		totals = A.totals(cfg, st.alloc), msg = msg}
end

return WC
