-- Charms: the pure rules (no engine calls). Numbers: charms_config.lua; engine part: charms.lua; tests:
-- tests/charms_test.lua (LuaJIT and Lua 5.3). Overview: server/README.md "Charms".
--
--   the grid       C.unlockState (open cells and why the others are locked), C.footprint, C.placeRefusal (inside the
--                  grid, open cells, no overlap), C.activeOf (a charm counts only while all its cells are open)
--   rolls          C.rollCharm (shape, rarity, item level, 1-2 modifiers of the pool), C.rollValue, C.maxRoll,
--                  C.rollDrop (the drop chance of a source and the charm), C.reforge (same modifiers, new values)
--   totals         C.totals: per key the sum of the active charms, each key under its charm cap; the keys of the gear
--                  catalogue go to item_mods.lua as an extra source (and meet the gear caps there too)
--   item           C.toAttrs / C.fromAttrs (custom attributes of a charm item), C.describe (its look text)
--   safety         C.place / C.take run a place or a take-out step by step against an `env` (the engine in charms.lua,
--                  a simulated world in the test); C.recoverAction decides a row a crash left pending
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosCharmsCore = ChaosCharmsCore or {}
local C = ChaosCharmsCore

local floor = math.floor

C.STATE_PLACED = 0
C.STATE_TAKING = 8
C.STATE_PLACING = 9

-- custom attribute keys of a charm item
C.ATTR = {rarity = "charm_r", ilvl = "chaos_ilvl", key1 = "charm_k1", value1 = "charm_v1", key2 = "charm_k2", value2 = "charm_v2"}

function C.attributeKeys()
	local A = C.ATTR
	return {A.rarity, A.ilvl, A.key1, A.value1, A.key2, A.value2}
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function int(v)
	v = tonumber(v)
	if not v or v ~= v then
		return nil
	end
	return floor(v)
end
C.int = int

-- ------------------------------------------------------------------ catalogue
local indexCache = setmetatable({}, {__mode = "k"})
function C.index(cfg)
	local idx = indexCache[cfg]
	if idx then
		return idx
	end
	idx = {byId = {}, byKey = {}, pool = {}, pooled = {}, any = {}}
	for _, it in ipairs(cfg.items) do
		idx.byId[it.id] = it
		idx.byKey[it.key] = it
	end
	for _, def in ipairs(cfg.pool) do
		idx.pool[def.key] = def
		idx.pooled[#idx.pooled + 1] = def
		idx.any[def.key] = def
	end
	for key, def in pairs(cfg.extraKeys or {}) do
		def.key = key
		idx.any[key] = def
	end
	indexCache[cfg] = idx
	return idx
end

function C.itemDef(cfg, id)
	return C.index(cfg).byId[int(id) or -1]
end

-- the charm item definition (not the shard) of a server id, or nil
function C.charmDef(cfg, id)
	local it = C.itemDef(cfg, id)
	if it and it.shape then
		return it
	end
	return nil
end

function C.shardId(cfg)
	local it = C.index(cfg).byKey.shard
	return it and it.id or 0
end

function C.idOfShape(cfg, shape)
	for _, it in ipairs(cfg.items) do
		if it.shape == shape and not it.unique then
			return it.id
		end
	end
	return nil
end

function C.idOfUnique(cfg, key)
	local it = C.index(cfg).byKey[key]
	return it and it.unique and it.id or nil
end

-- ------------------------------------------------------------------ the grid
local function cellKey(x, y)
	return x .. "," .. y
end
C.cellKey = cellKey

-- {open = {["x,y"] = true}, locked = {["x,y"] = {key, text}}, groups = {{key, text, open, cells}}}
-- level: the character's level; has(achievementId) -> bool
function C.unlockState(cfg, level, has)
	level = tonumber(level) or 0
	local st = {open = {}, locked = {}, groups = {}, openCount = 0}
	for _, u in ipairs(cfg.unlocks) do
		local ok = true
		if u.level and level < u.level then
			ok = false
		end
		if u.achievement and not (has and has(u.achievement)) then
			ok = false
		end
		st.groups[#st.groups + 1] = {key = u.key, text = u.text, open = ok, cells = u.cells, level = u.level}
		for _, c in ipairs(u.cells) do
			local k = cellKey(c[1], c[2])
			if ok then
				st.open[k] = true
				st.openCount = st.openCount + 1
			else
				st.locked[k] = {key = u.key, text = u.text}
			end
		end
	end
	return st
end

-- the cells a shape covers with its top-left cell at x, y
function C.footprint(cfg, shapeKey, x, y)
	local s = cfg.shapes[shapeKey]
	if not s then
		return nil
	end
	local out = {}
	for dy = 0, s.h - 1 do
		for dx = 0, s.w - 1 do
			out[#out + 1] = {x + dx, y + dy}
		end
	end
	return out
end

-- cell key -> id of the placed charm covering it (placed: list of {id, shape, x, y})
function C.occupancy(cfg, placed, ignoreId)
	local occ = {}
	for _, p in ipairs(placed or {}) do
		if p.id ~= ignoreId then
			for _, c in ipairs(C.footprint(cfg, p.shape, p.x, p.y) or {}) do
				occ[cellKey(c[1], c[2])] = p.id
			end
		end
	end
	return occ
end

-- nil when a charm of shapeKey fits with its top-left cell at x, y; else the reason. ignoreId: the charm being moved
function C.placeRefusal(cfg, placed, shapeKey, x, y, open, ignoreId)
	x, y = int(x), int(y)
	local cells = x and y and C.footprint(cfg, shapeKey, x, y)
	if not cells then
		return "That is not a charm."
	end
	local occ = C.occupancy(cfg, placed, ignoreId)
	for _, c in ipairs(cells) do
		if c[1] < 1 or c[2] < 1 or c[1] > cfg.grid.cols or c[2] > cfg.grid.rows then
			return "The charm does not fit inside the grid there."
		end
		local k = cellKey(c[1], c[2])
		if not (open and open[k]) then
			return "That cell is locked."
		end
		if occ[k] then
			return "Another charm is in the way."
		end
	end
	local count = 0
	for _, p in ipairs(placed or {}) do
		if p.id ~= ignoreId then
			count = count + 1
		end
	end
	if count >= (cfg.maxPlaced or 20) then
		return "Your charm grid is full."
	end
	return nil
end

-- true while every cell of the placed charm is open (a closed cell: the charm stays but gives nothing)
function C.activeOf(cfg, p, open)
	for _, c in ipairs(C.footprint(cfg, p.shape, p.x, p.y) or {}) do
		if not open[cellKey(c[1], c[2])] then
			return false
		end
	end
	return true
end

-- ------------------------------------------------------------------ rolls
local function weighted(rows, rand)
	local total = 0
	for _, r in ipairs(rows) do
		total = total + r[2]
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for _, r in ipairs(rows) do
		acc = acc + r[2]
		if roll <= acc then
			return r[1]
		end
	end
	return rows[#rows][1]
end
C.weighted = weighted

function C.levelScale(cfg, ilvl)
	local il = cfg.itemLevel
	local lv = clamp(int(ilvl) or 1, 1, il.max)
	return il.minScale + (1 - il.minScale) * lv / il.max
end

-- the value of a roll u (0..1) of def on a charm of shapeKey, rarity r, item level ilvl
function C.valueOf(cfg, def, u, shapeKey, rarity, ilvl)
	local s = cfg.shapes[shapeKey]
	local rr = cfg.rarities[clamp(int(rarity) or 1, 1, #cfg.rarities)]
	local raw = def.range[1] + (def.range[2] - def.range[1]) * clamp(tonumber(u) or 0, 0, 1)
	local v = floor(raw * (s and s.mult or 1) * rr.scale * C.levelScale(cfg, ilvl) + 0.5)
	return math.max(1, v)
end

-- the best roll of def on the biggest shape at the best rarity and item level
function C.maxRoll(cfg, def, shapeKey)
	local best = 0
	for key in pairs(cfg.shapes) do
		if not shapeKey or key == shapeKey then
			best = math.max(best, C.valueOf(cfg, def, 1, key, #cfg.rarities, cfg.itemLevel.max))
		end
	end
	return best
end

function C.rollValue(cfg, def, shapeKey, rarity, ilvl, rand)
	return C.valueOf(cfg, def, (rand(0, 1000)) / 1000, shapeKey, rarity, ilvl)
end

-- a new charm: {item = server id, shape, rarity, ilvl, mods = {{key, value}, ...}}. opts: ilvl, shape, rarity, unique
-- (a unique's key), rand (math.random-like)
function C.rollCharm(cfg, opts)
	opts = opts or {}
	local rand = opts.rand or math.random
	local ilvl = clamp(int(opts.ilvl) or 1, 1, cfg.itemLevel.max)
	if opts.unique then
		local u = cfg.uniques[opts.unique]
		local it = C.index(cfg).byKey[opts.unique]
		if not u or not it then
			return nil
		end
		local mods = {}
		for _, m in ipairs(u.mods) do
			mods[#mods + 1] = {key = m[1], value = m[2]}
		end
		return {item = it.id, shape = it.shape, unique = opts.unique, rarity = 0, ilvl = ilvl, mods = mods}
	end
	local shape = opts.shape or weighted(cfg.shapeWeights, rand)
	local rows = {}
	for i, r in ipairs(cfg.rarities) do
		rows[#rows + 1] = {i, r.weight}
	end
	local rarity = clamp(int(opts.rarity) or weighted(rows, rand), 1, #cfg.rarities)
	local count = cfg.rarities[rarity].mods
	local mods, used, usedGroup = {}, {}, {}
	for _ = 1, count do
		local pick = {}
		for _, def in ipairs(C.index(cfg).pooled) do
			-- two modifiers of one charm differ, and never two of one group (two families, two elements)
			if not used[def.key] and not (def.group and usedGroup[def.group]) then
				pick[#pick + 1] = {def, def.weight or 1}
			end
		end
		local def = weighted(pick, rand)
		if not def then
			break
		end
		used[def.key] = true
		if def.group then
			usedGroup[def.group] = true
		end
		mods[#mods + 1] = {key = def.key, value = C.rollValue(cfg, def, shape, rarity, ilvl, rand)}
	end
	return {item = C.idOfShape(cfg, shape), shape = shape, rarity = rarity, ilvl = ilvl, mods = mods}
end

-- the same charm with its values rolled again (nil for a unique)
function C.reforge(cfg, charm, rand)
	if not charm or charm.unique then
		return nil
	end
	local out = {item = charm.item, shape = charm.shape, rarity = charm.rarity, ilvl = charm.ilvl, mods = {}}
	for _, m in ipairs(charm.mods) do
		local def = C.index(cfg).pool[m.key]
		out.mods[#out.mods + 1] = {key = m.key, value = def and C.rollValue(cfg, def, charm.shape, charm.rarity, charm.ilvl,
			rand or math.random) or m.value}
	end
	return out
end

function C.salvageShards(cfg, charm)
	if not charm then
		return 0
	end
	local s = cfg.salvage
	if charm.unique then
		return s.unique
	end
	return (s[charm.shape] or 1) + ((charm.rarity or 1) >= #cfg.rarities and (s.radiantBonus or 0) or 0)
end

function C.reforgeCost(cfg, charm)
	if not charm or charm.unique then
		return nil
	end
	return cfg.reforge[charm.shape]
end

-- ------------------------------------------------------------------ drops
-- source: "rift" {tier}, "bounty" {level}, "invasion" {level, rank}, "dungeon" {difficulty}, "descent" {depth, boss}
-- -> chance (percent), item level
function C.dropChance(cfg, source, ctx)
	local d = cfg.drops[source]
	ctx = ctx or {}
	if not d then
		return 0, 0
	end
	if source == "rift" then
		local tier = int(ctx.tier) or 0
		if tier < d.minTier then
			return 0, 0
		end
		return math.min(d.max, d.base + d.perTier * (tier - d.minTier)), d.ilvlBase + d.ilvlPerTier * tier
	elseif source == "bounty" then
		return d.chance, clamp(floor((tonumber(ctx.level) or 0) * d.ilvlPerLevel), d.ilvlMin, d.ilvlMax)
	elseif source == "invasion" then
		return (int(ctx.rank) == 1) and d.top or d.chance,
			clamp(floor((tonumber(ctx.level) or 0) * d.ilvlPerLevel), d.ilvlMin, d.ilvlMax)
	elseif source == "dungeon" then
		local diff = math.max(0, int(ctx.difficulty) or 0)
		return d.base + d.perDifficulty * diff, d.ilvlBase + d.ilvlPerDifficulty * diff
	elseif source == "descent" then
		local depth = math.max(1, int(ctx.depth) or 1)
		return ctx.boss and d.boss or d.room, d.ilvlBase + d.ilvlPerDepth * depth
	end
	return 0, 0
end

-- a charm for this event or nil (rand(a, b) like math.random)
function C.rollDrop(cfg, source, ctx, rand)
	rand = rand or math.random
	local chance, ilvl = C.dropChance(cfg, source, ctx)
	if chance <= 0 or rand(1, 10000) > floor(chance * 100 + 0.5) then
		return nil
	end
	ilvl = clamp(floor(ilvl), 1, cfg.itemLevel.max)
	if rand(1, 10000) <= floor((cfg.drops.uniqueChance or 0) * 100 + 0.5) then
		local keys = {}
		for key in pairs(cfg.uniques) do
			keys[#keys + 1] = key
		end
		table.sort(keys)
		return C.rollCharm(cfg, {unique = keys[rand(1, #keys)], ilvl = ilvl, rand = rand})
	end
	return C.rollCharm(cfg, {ilvl = ilvl, rand = rand})
end

-- ------------------------------------------------------------------ totals
-- charms: list of {charm = {...}, active = bool}. Returns own {key -> value} (every pool and extra key, capped by the
-- charm caps), gear {key -> value} (the gear catalogue keys among them, for item_mods.lua), signatures {name -> true}
function C.totals(cfg, charms)
	local idx = C.index(cfg)
	local sum, sig = {}, {}
	for key in pairs(idx.any) do
		sum[key] = 0
	end
	for _, e in ipairs(charms or {}) do
		local ch = e.charm
		if e.active ~= false and ch then
			for _, m in ipairs(ch.mods or {}) do
				if sum[m.key] then
					sum[m.key] = sum[m.key] + (int(m.value) or 0)
				end
			end
			local u = ch.unique and cfg.uniques[ch.unique]
			if u then
				sig[u.signature] = true
				for key, v in pairs(u.extra or {}) do
					if sum[key] then
						sum[key] = sum[key] + v
					end
				end
			end
		end
	end
	if sig.harvester then
		sum.manaonkill = sum.manaonkill + floor(math.min(sum.lifeonkill, idx.any.lifeonkill.cap) / 2)
	end
	local gear = {}
	for key, def in pairs(idx.any) do
		sum[key] = clamp(sum[key], 0, def.cap or 0)
		if def.gear and sum[key] > 0 then
			gear[key] = sum[key]
		end
	end
	return sum, gear, sig
end

-- a stable text of what the totals depend on (item_mods.lua compares it to skip work)
function C.signature(charms)
	local parts = {}
	for _, e in ipairs(charms or {}) do
		if e.active ~= false and e.charm then
			local m = {}
			for _, mm in ipairs(e.charm.mods or {}) do
				m[#m + 1] = mm.key .. "=" .. tostring(mm.value)
			end
			parts[#parts + 1] = tostring(e.charm.unique or "") .. ":" .. table.concat(m, ";")
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- sum of two {key -> number} tables in a new table (neither is changed)
function C.merge(a, b)
	if not b or next(b) == nil then
		return a
	end
	local out = {}
	for k, v in pairs(a or {}) do
		out[k] = v
	end
	for k, v in pairs(b) do
		out[k] = (out[k] or 0) + v
	end
	return out
end

-- the damage multiplier percent against a monster of `family` and the resistance percent against `combatName`
function C.familyPct(own, family)
	return own and family and own["dmg_" .. family] or 0
end

function C.resistPct(cfg, own, combat)
	if not own or not combat then
		return 0
	end
	for _, def in ipairs(cfg.pool) do
		if def.element and _G[def.element] ~= nil and _G[def.element] == combat then
			return own[def.key] or 0
		end
	end
	return 0
end

-- a hit (negative or positive number) reduced by pct percent, rounded toward zero
function C.reduce(value, pct)
	pct = clamp(tonumber(pct) or 0, 0, 100)
	local a = floor(math.abs(value) * (100 - pct) / 100 + 1e-6)
	return value < 0 and -a or a
end

-- the hit that leaves exactly 1 health (Last Ember), or nil when the hit is not lethal
function C.emberCap(health, primary, secondary)
	local total = math.abs(primary or 0) + math.abs(secondary or 0)
	health = tonumber(health) or 0
	if health <= 1 or total < health then
		return nil
	end
	return health - 1
end

-- ------------------------------------------------------------------ texts
function C.text(cfg, key, value)
	local def = C.index(cfg).any[key]
	value = int(value) or 0
	if not def then
		return tostring(key) .. " " .. value
	end
	if def.text then
		return string.format(def.text, value)
	elseif def.fmt == "flat" then
		return string.format("%s +%d", def.label, value)
	end
	return string.format("%s +%d%%", def.label, value)
end

function C.rarityName(cfg, charm)
	if charm.unique then
		return cfg.uniqueRarity.name
	end
	local r = cfg.rarities[charm.rarity or 1]
	return r and r.name or "?"
end

function C.rarityColor(cfg, charm)
	if charm.unique then
		return cfg.uniqueRarity.color
	end
	local r = cfg.rarities[charm.rarity or 1]
	return r and r.color or "#ffffff"
end

-- the charm's display name ("Radiant Grand Charm", "Gravewarden's Seal")
function C.nameOf(cfg, charm)
	if charm.unique then
		local it = C.index(cfg).byKey[charm.unique]
		return it and it.name or "Unique Charm"
	end
	local s = cfg.shapes[charm.shape]
	return C.rarityName(cfg, charm) .. " " .. (s and s.name or "Charm")
end

-- the look text lines of a charm item
function C.describe(cfg, charm)
	local s = cfg.shapes[charm.shape]
	local lines = {string.format("%s, item level %d, %dx%d cells.", C.rarityName(cfg, charm), charm.ilvl or 1,
		s and s.w or 1, s and s.h or 1)}
	for _, m in ipairs(charm.mods or {}) do
		lines[#lines + 1] = C.text(cfg, m.key, m.value) .. "."
	end
	local u = charm.unique and cfg.uniques[charm.unique]
	if u then
		lines[#lines + 1] = u.signatureText
	end
	lines[#lines + 1] = "Place it in your charm grid (Character > Charms)."
	return lines
end

-- the client's view of one charm
function C.viewOf(cfg, charm)
	local mods = {}
	for _, m in ipairs(charm.mods or {}) do
		mods[#mods + 1] = {k = m.key, v = m.value, t = C.text(cfg, m.key, m.value)}
	end
	local u = charm.unique and cfg.uniques[charm.unique]
	local s = cfg.shapes[charm.shape] or {w = 1, h = 1}
	return {name = C.nameOf(cfg, charm), shape = charm.shape, w = s.w, h = s.h, rarity = C.rarityName(cfg, charm),
		color = C.rarityColor(cfg, charm), ilvl = charm.ilvl, unique = charm.unique, mods = mods,
		signature = u and u.signatureText or nil, icon = charm.unique or (charm.mods and charm.mods[1] and charm.mods[1].key) or "charm",
		salvage = C.salvageShards(cfg, charm), reforge = C.reforgeCost(cfg, charm)}
end

-- the totals summary rows for the client: {{k, v, cap, t}} of every key above 0, in pool order
function C.totalsView(cfg, own)
	local rows = {}
	local function add(key, def)
		local v = own[key] or 0
		if v > 0 then
			rows[#rows + 1] = {k = key, v = v, cap = def.cap, t = C.text(cfg, key, v)}
		end
	end
	for _, def in ipairs(cfg.pool) do
		add(def.key, def)
	end
	local extra = {}
	for key in pairs(cfg.extraKeys or {}) do
		extra[#extra + 1] = key
	end
	table.sort(extra)
	for _, key in ipairs(extra) do
		add(key, cfg.extraKeys[key])
	end
	return rows
end

-- ------------------------------------------------------------------ item attributes
-- {{key, value}, ...} to write on the item (keys of C.ATTR; a unique has its fixed modifiers and only the item level)
function C.toAttrs(charm)
	local A = C.ATTR
	local out = {{A.ilvl, charm.ilvl or 1}}
	if charm.unique then
		return out
	end
	out[#out + 1] = {A.rarity, charm.rarity or 1}
	for i = 1, 2 do
		local m = charm.mods and charm.mods[i]
		if m then
			out[#out + 1] = {A["key" .. i], m.key}
			out[#out + 1] = {A["value" .. i], m.value}
		end
	end
	return out
end

-- the charm an item carries: itemId and get(attributeKey) -> value or nil. nil when it is no charm
function C.fromAttrs(cfg, itemId, get)
	local def = C.charmDef(cfg, itemId)
	if not def then
		return nil
	end
	local A = C.ATTR
	local ilvl = clamp(int(get(A.ilvl)) or 1, 1, cfg.itemLevel.max)
	if def.unique then
		local ch = C.rollCharm(cfg, {unique = def.key, ilvl = ilvl})
		return ch
	end
	local charm = {item = def.id, shape = def.shape, rarity = clamp(int(get(A.rarity)) or 1, 1, #cfg.rarities), ilvl = ilvl, mods = {}}
	local pool = C.index(cfg).pool
	for i = 1, 2 do
		local key, value = get(A["key" .. i]), int(get(A["value" .. i]))
		if type(key) == "string" and pool[key] and value and value > 0 then
			-- a value above the best roll of its shape (a changed config) counts as the best roll
			value = math.min(value, C.maxRoll(cfg, pool[key], def.shape))
			charm.mods[#charm.mods + 1] = {key = key, value = value}
		end
	end
	return charm
end

-- ------------------------------------------------------------------ hex (the row's copy of the item's attributes)
function C.hex(s)
	return (tostring(s):gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function C.unhex(h)
	if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then
		return nil
	end
	return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end

-- ------------------------------------------------------------------ crash safety
-- A charm in the grid lives only in its chaos_charms row (the item's attributes, copied), never as an item too. The
-- character's storage `seq` counts the place and take steps and is saved with the items (player:save() writes both in
-- one database transaction). A row is written "pending" with the next serial BEFORE the item changes in memory, so
-- whatever a crash leaves behind, the saved serial says which side is true:
--   placing (9), serial <= saved -> the item had left the character in the saved state: the row becomes placed
--                serial >  saved -> the item is still in the saved inventory: the row is dropped
--   taking (8),  serial <= saved -> the item reached the character in the saved state: the row is dropped
--                serial >  saved -> the item never reached it: the row goes back to placed
function C.recoverAction(state, seq, savedSeq)
	seq, savedSeq = int(seq) or 0, math.max(0, int(savedSeq) or 0)
	if state == C.STATE_PLACING then
		return seq <= savedSeq and "activate" or "drop"
	elseif state == C.STATE_TAKING then
		return seq <= savedSeq and "drop" or "restore"
	end
	return "keep"
end

-- env (charms.lua: the engine and the database; the test: a simulated world):
--   getSeq() / setSeq(n)          the marker storage (in memory)
--   insertRow(rec) -> id          a new row with rec.state, rec.seq (database, at once)
--   setRow(id, from, to, seq)     state from -> to (and the serial) when the row is in state from; true when it changed
--   deleteRow(id, state)          drop the row when it is in that state
--   removeItem() -> bool          the item leaves the character (in memory)
--   restoreItem()                 a removed item comes back (in memory)
--   createItem(row) -> bool       the row's item is created on the character (in memory)
--   uncreateItem()                the created item goes away again (in memory)
--   save() -> bool                player:save()
-- returns true, id | false, reason
function C.place(env, rec)
	local seq = math.max(0, int(env.getSeq()) or 0) + 1
	rec.state, rec.seq = C.STATE_PLACING, seq
	local id = env.insertRow(rec)
	if not id then
		return false, "busy"
	end
	if not env.removeItem() then
		env.deleteRow(id, C.STATE_PLACING)
		return false, "item"
	end
	local old = env.getSeq()
	env.setSeq(seq)
	if not env.save() then
		env.setSeq(old)
		env.restoreItem()
		env.deleteRow(id, C.STATE_PLACING)
		return false, "busy"
	end
	env.setRow(id, C.STATE_PLACING, C.STATE_PLACED, seq) -- a failure here leaves it pending: activated at the next login
	return true, id
end

function C.take(env, row)
	local seq = math.max(0, int(env.getSeq()) or 0) + 1
	if not env.setRow(row.id, C.STATE_PLACED, C.STATE_TAKING, seq) then
		return false, "busy"
	end
	if not env.createItem(row) then
		env.setRow(row.id, C.STATE_TAKING, C.STATE_PLACED, row.seq or 0)
		return false, "room"
	end
	local old = env.getSeq()
	env.setSeq(seq)
	if not env.save() then
		env.setSeq(old)
		env.uncreateItem()
		env.setRow(row.id, C.STATE_TAKING, C.STATE_PLACED, row.seq or 0)
		return false, "busy"
	end
	env.deleteRow(row.id, C.STATE_TAKING) -- a failure here leaves it pending: dropped at the next login
	return true
end

-- ------------------------------------------------------------------ config check
function C.validate(cfg)
	local errors = {}
	local function err(fmt, ...)
		errors[#errors + 1] = string.format(fmt, ...)
	end
	local idx = C.index(cfg)
	local seen = {}
	for _, it in ipairs(cfg.items) do
		if seen[it.id] then
			err("item id %d twice", it.id)
		end
		seen[it.id] = true
		if it.shape and not cfg.shapes[it.shape] then
			err("item %s: unknown shape %s", it.key, tostring(it.shape))
		end
		if it.unique and not cfg.uniques[it.key] then
			err("unique item %s has no entry in uniques", it.key)
		end
	end
	for key in pairs(cfg.shapes) do
		if not C.idOfShape(cfg, key) then
			err("shape %s has no item", key)
		end
	end
	for _, def in ipairs(cfg.pool) do
		if not def.range or def.range[1] < 1 or def.range[2] < def.range[1] then
			err("%s: bad range", def.key)
		end
		local best = C.maxRoll(cfg, def)
		if def.gearRef and best >= def.gearRef then
			err("%s: the best charm roll %d is not below one gear slot's %d", def.key, best, def.gearRef)
		end
		if best > def.cap then
			err("%s: the best charm roll %d is above the charm cap %d", def.key, best, def.cap)
		end
	end
	for key, u in pairs(cfg.uniques) do
		if not idx.byKey[key] then
			err("unique %s has no item", key)
		end
		for _, m in ipairs(u.mods) do
			local def = idx.any[m[1]]
			if not def then
				err("unique %s: unknown key %s", key, tostring(m[1]))
			elseif def.gearRef and m[2] >= def.gearRef then
				err("unique %s: %s %d is not below one gear slot's %d", key, m[1], m[2], def.gearRef)
			end
		end
		for k, v in pairs(u.extra or {}) do
			local def = idx.any[k]
			if not def or (def.gearRef and v >= def.gearRef) then
				err("unique %s: extra %s", key, k)
			end
		end
		if not (u.signature and u.signatureText) then
			err("unique %s: no signature", key)
		end
	end
	local cellsSeen = {}
	for _, u in ipairs(cfg.unlocks) do
		for _, c in ipairs(u.cells) do
			local k = cellKey(c[1], c[2])
			if cellsSeen[k] then
				err("cell %s in two unlocks", k)
			end
			if c[1] < 1 or c[2] < 1 or c[1] > cfg.grid.cols or c[2] > cfg.grid.rows then
				err("cell %s outside the grid", k)
			end
			cellsSeen[k] = true
		end
	end
	local n = 0
	for _ in pairs(cellsSeen) do
		n = n + 1
	end
	if n ~= cfg.grid.cols * cfg.grid.rows then
		err("the unlocks open %d of %d cells", n, cfg.grid.cols * cfg.grid.rows)
	end
	return errors
end

return C
