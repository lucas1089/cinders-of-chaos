-- New players: the pure part (no engine calls), shared by newplayer.lua, newplayer_tutorial.lua and
-- tests/newplayer_test.lua.
--   kits        kitFor(vocationId): the kit of a vocation (own row, base class, engine demotion, default), merged
--               with the common backpack items; setKit to add or change rows (the class rework)
--   flags       one-time flags in storages (kit, welcome, milestones), bit helpers
--   milestones  which gifts a level-up from old to new level earns
--   tutorial    island layout and footprint, the station state machine (gates, exit, resume spot)
--   reset       the snapshot at the island's start and the reset at its end (NP.takeSnapshot, NP.tutorialReset)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosNewPlayer = ChaosNewPlayer or {}
local NP = ChaosNewPlayer

-- a text in `lang` through ChaosI18n (i18n_core.lua) when it is loaded, else English (giftLine)
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local floor = math.floor

-- the config table: newplayer_config.lua, loaded once (tests may set NP.config themselves)
function NP.cfg()
	if not NP.config then
		NP.config = dofile("data/scripts/chaos/newplayer_config.lua")
	end
	return NP.config
end

-- ------------------------------------------------------------------------------------------------ kits
-- base class of a vocation: Chaos.classes.baseOf (classes.lua), else the engine's demotion (Vocation(id)), else nil.
-- NP.demotionOf may be replaced (the engine glue sets it; tests set a fake).
NP.demotionOf = NP.demotionOf or function(vocId)
	if rawget(_G, "Vocation") then
		local ok, voc = pcall(Vocation, vocId)
		if ok and voc then
			local demotion = voc:getDemotion()
			if demotion and demotion:getId() ~= vocId then
				return demotion:getId()
			end
		end
	end
	return nil
end

local function baseClassOf(vocId)
	local classes = rawget(_G, "Chaos") and Chaos.classes
	local base = classes and classes.baseOf and classes.baseOf[vocId]
	if base and base ~= vocId then
		return base
	end
	return NP.demotionOf(vocId)
end

-- kit name of a vocation and how it was found ("vocation", "base", "default"); nil for a skipped vocation
function NP.kitNameFor(vocId, c)
	c = c or NP.cfg()
	vocId = tonumber(vocId) or 0
	if c.skipVocations and c.skipVocations[vocId] then
		return nil
	end
	local name = c.vocations[vocId]
	if name and c.kits[name] then
		return name, "vocation"
	end
	local base = baseClassOf(vocId)
	name = base and c.vocations[base]
	if name and c.kits[name] then
		return name, "base"
	end
	return "default", "default"
end

local function copyList(list, into)
	for _, e in ipairs(list or {}) do
		local copy = {}
		for k, v in pairs(e) do
			copy[k] = v
		end
		into[#into + 1] = copy
	end
	return into
end

-- the full kit of a kit name: {name, role, equip = {...}, backpack = {...}} (a kit with `base` inherits that kit's
-- equipment, role and backpack, and adds its own)
function NP.resolveKit(name, c)
	c = c or NP.cfg()
	local chain, seen = {}, {}
	local k = name
	while k and c.kits[k] and not seen[k] do
		seen[k] = true
		table.insert(chain, 1, c.kits[k])
		k = c.kits[k].base
	end
	if #chain == 0 then
		return nil
	end
	local kit = {name = name, equip = {}, backpack = {}}
	for _, row in ipairs(chain) do
		if row.equip then
			-- a later row replaces an equipment slot of an earlier one
			for _, e in ipairs(row.equip) do
				for i = #kit.equip, 1, -1 do
					if kit.equip[i].slot == e.slot then
						table.remove(kit.equip, i)
					end
				end
				copyList({e}, kit.equip)
			end
		end
		copyList(row.backpack, kit.backpack)
		kit.role = row.role or kit.role
	end
	kit.role = kit.role or "melee"
	local common = c.common or {}
	copyList(common.items, kit.backpack)
	kit.backpackId = common.backpackId or 1988
	kit.templeScrollUses = common.templeScrollUses or 0
	kit.gold = common.gold or 0
	return kit
end

-- the kit of a vocation (a fresh copy; changing it changes nothing), or nil when the vocation gets no kit (vocation 0,
-- which the base server's firstitems.lua equips)
function NP.kitFor(vocId, c)
	c = c or NP.cfg()
	local name, how = NP.kitNameFor(vocId, c)
	if not name then
		return nil
	end
	local kit = NP.resolveKit(name, c)
	if kit then
		kit.found = how
	end
	return kit
end

-- add or change a kit row and point vocations at it: setKit("berserker", {equip = ..., backpack = ..., role = ...},
-- {14}). kitDef may also be the name of an existing kit (only maps the vocations).
function NP.setKit(name, kitDef, vocIds, c)
	c = c or NP.cfg()
	if type(kitDef) == "table" then
		c.kits[name] = kitDef
	end
	for _, id in ipairs(vocIds or {}) do
		c.vocations[id] = name
	end
end

-- the weapon to equip at this level: entry id, or its fallback below minLevel (then the real one goes into the backpack)
function NP.equipFor(entry, level)
	if entry.minLevel and entry.fallback and (level or 1) < entry.minLevel then
		return entry.fallback, entry.id
	end
	return entry.id, nil
end

-- the two parts of a kit (newplayer_config.lua header): wear = {{slot, id, count}} (the equipment, the weapon of the
-- level: the fallback below minLevel), rest = {{id, count}} (the real weapon kept for later, the kit's backpack rows
-- and the common items). The Everfull potions come with the wearable part, the scroll and the gold with the rest.
function NP.kitParts(kit, level)
	local wear, rest = {}, {}
	for _, e in ipairs(kit.equip or {}) do
		local id, spare = NP.equipFor(e, level)
		wear[#wear + 1] = {slot = e.slot, id = id, count = e.count or 1}
		if spare then
			rest[#rest + 1] = {id = spare, count = 1}
		end
	end
	for _, b in ipairs(kit.backpack or {}) do
		rest[#rest + 1] = {id = b.id, count = b.count or 1}
	end
	return {wear = wear, rest = rest}
end

-- ------------------------------------------------------------------------------------------------ level 1 stats
-- start_stats.lua: the level 1 health, mana, capacity (oz) and soul of every class, the one source of truth of every
-- creation path. Tests may set NP.startStatsData themselves.
function NP.startStatsCfg()
	if not NP.startStatsData then
		NP.startStatsData = dofile("data/scripts/chaos/start_stats.lua")
	end
	return NP.startStatsData
end

-- {health, mana, cap (oz), soul} of a class at a level: its start row (an unknown class: its base class's, then
-- vocation 0's) plus its gains per level above 1 (gains = {hp, mana, cap}, the vocation's; none: the row's own gains)
function NP.statsFor(vocId, level, gains, S)
	S = S or NP.startStatsCfg()
	vocId = tonumber(vocId) or 0
	local row = S.stats[vocId] or S.stats[baseClassOf(vocId) or -1] or S.stats[0]
	local up = math.max(0, (tonumber(level) or 1) - 1)
	gains = gains or {hp = row.gainhp, mana = row.gainmana, cap = row.gaincap}
	return {health = row.health + up * (gains.hp or 0), mana = row.mana + up * (gains.mana or 0),
		cap = row.cap + up * (gains.cap or 0), soul = row.soul or 100}
end

-- the experience of a level (the engine's formula: level 8 = 4200)
function NP.expForLevel(level)
	local l = (tonumber(level) or 1) - 1
	return floor((50 * l * l * l - 150 * l * l + 400 * l) / 3)
end

-- the level a new character starts at (start_stats.lua startLevel) and its experience
function NP.startLevel(S)
	S = S or NP.startStatsCfg()
	local level = tonumber(S.startLevel) or 1
	return level, tonumber(S.startExperience) or NP.expForLevel(level)
end

-- should the login raise this character to the start level? Only one that never got its kit (brand new, or leaving
-- the closed tutorial island) and is below it
function NP.startLevelDue(level, hasKit, S)
	local start = NP.startLevel(S)
	return not hasKit and (tonumber(level) or 1) < start
end

-- the login correction: cur = {maxHealth, maxMana, cap (hundredths, as the engine counts)}. nil when nothing is
-- below the class's values or the level is past S.fixUpToLevel; else {maxHealth, maxMana, cap (hundredths)} with each
-- value raised to the class's (never lowered)
function NP.statsFix(vocId, level, cur, gains, S)
	S = S or NP.startStatsCfg()
	level = tonumber(level) or 1
	if level < 1 or level > (S.fixUpToLevel or 1) then
		return nil
	end
	local want = NP.statsFor(vocId, level, gains, S)
	local h, m, c = tonumber(cur.maxHealth) or 0, tonumber(cur.maxMana) or 0, tonumber(cur.cap) or 0
	if h >= want.health and m >= want.mana and c >= want.cap * 100 then
		return nil
	end
	return {maxHealth = math.max(h, want.health), maxMana = math.max(m, want.mana), cap = math.max(c, want.cap * 100)}
end

-- ------------------------------------------------------------------------------------------------ flags
function NP.key(name, c)
	c = c or NP.cfg()
	local base = (rawget(_G, "Chaos") and Chaos.storage and Chaos.storage.newPlayer) or 7100250
	return base + c.storage[name]
end

function NP.milestoneKey(index, c)
	c = c or NP.cfg()
	return NP.key("milestone", c) + index - 1
end

-- storage value -> set? (TFS returns -1 for a storage that was never written)
function NP.isSet(value)
	return (tonumber(value) or -1) > 0
end

function NP.hasBit(mask, bit)
	mask = math.max(0, tonumber(mask) or 0)
	return floor(mask / bit) % 2 == 1
end

function NP.setBit(mask, bit)
	mask = math.max(0, tonumber(mask) or 0)
	if NP.hasBit(mask, bit) then
		return mask
	end
	return mask + bit
end

-- should this login hand out the kit? only for a character that never got it and logs in for the first time ever
-- (lastLoginSaved 0): existing characters never get a kit by this path (/newplayerkit can give one)
function NP.kitDueAtLogin(kitStorage, lastLoginSaved)
	return not NP.isSet(kitStorage) and (tonumber(lastLoginSaved) or 0) <= 0
end

-- the town a brand-new character should live in, or nil to leave its town alone. currentTownId: the town it was
-- created with; hasKit: the kit storage is set (the character played already). homeTown = {id, keep = {ids}}.
function NP.homeTownFor(currentTownId, hasKit, c)
	c = c or NP.cfg()
	local h = c.homeTown
	local id = h and tonumber(h.id) or 0
	if hasKit or id <= 0 then
		return nil
	end
	local cur = tonumber(currentTownId) or 0
	if cur == id then
		return nil
	end
	for _, k in ipairs(h.keep or {}) do
		if tonumber(k) == cur then
			return nil
		end
	end
	return id
end

-- ------------------------------------------------------------------------------------------------ milestones
-- indexes of the milestones a level change from oldLevel to newLevel reaches and that are not claimed yet.
-- claimed(index) -> bool
function NP.milestonesDue(oldLevel, newLevel, claimed, c)
	c = c or NP.cfg()
	local due = {}
	if not newLevel or not oldLevel or newLevel <= oldLevel then
		return due
	end
	for i, m in ipairs(c.milestones) do
		if oldLevel < m.level and newLevel >= m.level and not claimed(i) then
			due[#due + 1] = i
		end
	end
	return due
end

-- the welcome's gift line, from the milestone levels still ahead of `level` (a character created at a high level
-- is not promised gifts it can no longer reach): "Gifts wait for you at levels 20, 50, 100 and 200." or ""
function NP.giftLine(level, c, lang)
	c = c or NP.cfg()
	local ahead = {}
	for _, m in ipairs(c.milestones) do
		if (tonumber(level) or 1) < m.level then
			ahead[#ahead + 1] = tostring(m.level)
		end
	end
	if #ahead == 0 then
		return ""
	end
	if #ahead == 1 then
		return T(lang, "A gift waits for you at level %s.", ahead[1])
	end
	local last = table.remove(ahead)
	return T(lang, "Gifts wait for you at levels %s and %s.", table.concat(ahead, ", "), last)
end

-- the items of one milestone for a kit role: list of {id, count} (potions of the role, orbs, extra items)
function NP.milestoneItems(index, role, c)
	c = c or NP.cfg()
	local m = c.milestones[index]
	local list = {}
	if not m then
		return list
	end
	local potions = m.potions and (m.potions[role] or m.potions.melee) or {}
	for _, p in ipairs(potions) do
		list[#list + 1] = {id = p[1], count = p[2]}
	end
	if (m.orbs or 0) > 0 then
		list[#list + 1] = {id = c.orbId, count = m.orbs}
	end
	for _, it in ipairs(m.items or {}) do
		list[#list + 1] = {id = it[1], count = it[2]}
	end
	return list
end

-- ------------------------------------------------------------------------------------------------ tutorial island
-- Geometry, all derived from cfg.tutorial: rooms (pens) side by side west to east, each roomW x roomH, closed by a
-- wooden fence (the coast ring and the dividers, a gap in the middle row of each divider: the gate). Around the fence a
-- strip of land landPad tiles wide (trees, bushes, lamps, a path to the dock; never reachable: the fence is closed),
-- then water out to where no view from inside a pen ends (view: the client's largest view, 29 x 21, plus one tile),
-- so a player on the island never sees an unmapped (black) tile. A dock and a boat on the west shore.
-- L.coast is the fenced rectangle (onIsland), L.land the land, L.outer every tile the island builds.
function NP.layout(t)
	t = t or NP.cfg().tutorial
	local o = t.origin
	local L = {z = o.z, rooms = {}, gates = {}}
	local W = t.rooms * (t.roomW + 1) -- x offset of the east fence
	local H = t.roomH + 1 -- y offset of the south fence
	L.coast = {x1 = o.x, y1 = o.y, x2 = o.x + W, y2 = o.y + H}
	local pad = t.landPad or 0
	L.land = {x1 = o.x - pad, y1 = o.y - pad, x2 = o.x + W + pad, y2 = o.y + H + pad}
	local cy = o.y + floor((t.roomH + 1) / 2)
	L.cy = cy
	for i = 1, t.rooms do
		local x1 = o.x + (i - 1) * (t.roomW + 1) + 1
		local x2 = x1 + t.roomW - 1
		local cx = x1 + floor(t.roomW / 2)
		L.rooms[i] = {
			x1 = x1, y1 = o.y + 1, x2 = x2, y2 = o.y + t.roomH, cx = cx,
			statue = {x = cx, y = o.y + 2, z = o.z},
			marker = {x = cx, y = o.y + 3, z = o.z},
			arrival = {x = x1 + 1, y = cy, z = o.z},
			sign = {x = x1, y = cy - 1, z = o.z}, -- the station's signpost, west of the path where the room begins
			basins = {{x = x1, y = o.y + 1, z = o.z}, {x = x2, y = o.y + t.roomH, z = o.z}},
			decor = {{x = x2, y = o.y + 1, z = o.z}, {x = x1, y = o.y + t.roomH, z = o.z},
				{x = x1 + 2, y = o.y + t.roomH, z = o.z}, {x = x2 - 1, y = o.y + 1, z = o.z},
				{x = x1, y = o.y + 3, z = o.z}, {x = x2, y = o.y + t.roomH - 4, z = o.z}}
		}
		if i < t.rooms then
			L.gates[i] = {x = x2 + 1, y = cy, z = o.z}
		end
	end
	local r1 = L.rooms[1]
	-- the goblin statue (skip) right beside the arrival tile: the first thing a new character sees
	L.skipStatue = {x = r1.x1, y = cy + 1, z = o.z}
	L.spawns = {{x = r1.x2 - 1, y = r1.y2 - 1, z = o.z}, {x = r1.x2 - 2, y = r1.y2 - 2, z = o.z}, {x = r1.x2, y = r1.y2 - 3, z = o.z}}
	local r5 = L.rooms[t.rooms]
	L.exit = {x = r5.x2 - 1, y = cy, z = o.z}
	-- every tile a player can stand on lies inside the fence: the water reaches past the view from any of them
	local view = t.view or {w = 0, h = 0}
	local mx, my = floor((view.w or 0) / 2) + 1, floor((view.h or 0) / 2) + 1
	local ring = t.waterRing or 0
	L.outer = {
		x1 = math.min(L.land.x1 - ring, r1.x1 - mx), y1 = math.min(L.land.y1 - ring, r1.y1 - my),
		x2 = math.max(L.land.x2 + ring, r5.x2 + mx), y2 = math.max(L.land.y2 + ring, r1.y2 + my)
	}
	-- the dock: wooden planks from the west shore into the water on the arrival row, a boat moored south of it
	L.dock = {}
	if pad > 0 and (t.dockLength or 0) > 0 then
		for k = 1, t.dockLength do
			L.dock[#L.dock + 1] = {x = L.land.x1 - k, y = cy, z = o.z}
			L.dock[#L.dock + 1] = {x = L.land.x1 - k, y = cy + 1, z = o.z}
		end
		L.boat = {x = L.land.x1 - t.dockLength + 1, y = cy + 2, z = o.z}
	end
	return L
end

local function inRect(r, z, pos)
	return pos and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

-- inside the island (fence included)
function NP.onIsland(pos, L)
	L = L or NP.layout()
	return inRect(L.coast, L.z, pos)
end

-- the room (1..rooms) a position is in, or nil (fences, gates, land)
function NP.roomOf(pos, L)
	L = L or NP.layout()
	for i, r in ipairs(L.rooms) do
		if inRect(r, L.z, pos) then
			return i
		end
	end
	return nil
end

-- the path tiles: the middle row from the first pen's west end to the last pen's east end (through the gates), a
-- branch up to every lesson tile, and on the land west of the fence the way to the dock
local function pathSet(L)
	local set = {}
	local r1, rn = L.rooms[1], L.rooms[#L.rooms]
	for x = r1.x1, rn.x2 do
		set[x .. ":" .. L.cy] = true
	end
	for _, r in ipairs(L.rooms) do
		for y = r.marker.y + 1, L.cy - 1 do
			set[r.cx .. ":" .. y] = true
		end
	end
	if #L.dock > 0 then
		for x = L.land.x1, L.coast.x1 - 1 do
			set[x .. ":" .. L.cy] = true
		end
	end
	return set
end

-- every tile: {x, y, z, kind} with kind water | land | trail | fence | ground | path | gate | marker | dock
function NP.footprint(L, t)
	t = t or NP.cfg().tutorial
	L = L or NP.layout(t)
	local special = {}
	local function mark(p, kind)
		special[p.x .. ":" .. p.y] = kind
	end
	for k in pairs(pathSet(L)) do
		special[k] = "path"
	end
	for _, d in ipairs(L.dock) do
		mark(d, "dock")
	end
	for _, g in ipairs(L.gates) do
		mark(g, "gate")
	end
	for _, r in ipairs(L.rooms) do
		mark(r.marker, "marker")
	end
	local dividers = {}
	for i = 1, #L.rooms - 1 do
		dividers[L.rooms[i].x2 + 1] = true
	end
	local list = {}
	for y = L.outer.y1, L.outer.y2 do
		for x = L.outer.x1, L.outer.x2 do
			local k = x .. ":" .. y
			local kind
			if not inRect(L.land, L.z, {x = x, y = y, z = L.z}) then
				kind = special[k] == "dock" and "dock" or "water"
			elseif not inRect(L.coast, L.z, {x = x, y = y, z = L.z}) then
				kind = special[k] == "path" and "trail" or "land" -- the way to the dock: looks like the path, never walked
			elseif x == L.coast.x1 or x == L.coast.x2 or y == L.coast.y1 or y == L.coast.y2 then
				kind = "fence"
			elseif special[k] == "gate" or special[k] == "marker" then
				kind = special[k]
			elseif dividers[x] then
				kind = "fence"
			else
				kind = special[k] or "ground"
			end
			list[#list + 1] = {x = x, y = y, z = L.z, kind = kind}
		end
	end
	return list
end

-- a small deterministic hash of a tile (the same island in LuaJIT and Lua 5.3, every start)
local function tileHash(x, y, salt)
	local h = (x * 73856093 + y * 19349663 + (salt or 0) * 83492791) % 2147483647
	h = (h * 48271) % 2147483647
	return h
end
NP.tileHash = tileHash

local function pick(list, x, y, salt)
	return list[tileHash(x, y, salt) % #list + 1]
end

-- the fence piece of a fence tile from which of its 4 neighbours are fences (measured on the live map with
-- tools/map/derive_borders.py: 1534 runs north-south, 1536 east-west, 1533 is the north-west post (fences east and
-- south), 1535 the south-east joint (north and west), 1538 the south end of a north-south run)
function NP.fencePiece(n, e, s, w, f)
	if e and s and not n and not w then
		return f.post
	end
	if n and w and not e and not s then
		return f.joint
	end
	if n and e and not s and not w then
		return f.vertical -- the south-west corner
	end
	if n and s and (e or w) then
		return f.joint
	end
	if e or w then
		return f.horizontal
	end
	if n and not s then
		return f.southEnd
	end
	if n or s then
		return f.vertical
	end
	return f.post
end

-- the whole island as tiles to build: {x, y, z, kind, ground, items = {id, ...}, aid, ...} in build order (items in
-- stack order: border pieces first, then the rest). Pure: newplayer_tutorial.lua builds it with Game.createTile and
-- server/tools/areagen_export.py (area "tutorial") renders it. Every id comes from cfg.tutorial.look.
function NP.islandModel(L, t)
	t = t or NP.cfg().tutorial
	L = L or NP.layout(t)
	local look = t.look or {}
	local A = rawget(_G, "ChaosAreaGenCore")
	if not (A and A.borderPieces) then
		dofile("data/scripts/chaos/areagen_core.lua")
		A = ChaosAreaGenCore
	end
	local foot = NP.footprint(L, t)
	local at = {}
	for _, f in ipairs(foot) do
		at[f.x .. ":" .. f.y] = f
	end
	local function kindAt(x, y)
		local f = at[x .. ":" .. y]
		return f and f.kind or "water"
	end
	local grassy = {land = true, ground = true, fence = true}
	local tiles = {}
	-- blocking things that must not stand on a lesson spot, the path, an arrival or a spawn
	local busy = {}
	for _, r in ipairs(L.rooms) do
		for _, p in ipairs({r.statue, r.marker, r.arrival, r.sign}) do
			busy[p.x .. ":" .. p.y] = true
		end
		for _, b in ipairs(r.basins) do
			busy[b.x .. ":" .. b.y] = true
		end
	end
	for _, p in ipairs(L.spawns) do
		busy[p.x .. ":" .. p.y] = true
	end
	busy[L.skipStatue.x .. ":" .. L.skipStatue.y] = true
	busy[L.exit.x .. ":" .. L.exit.y] = true
	-- lamps on the land north and south of the fence, beside every gate and at both ends
	local lamps = {}
	if look.lamp then
		local xs = {L.coast.x1 + 1, L.coast.x2 - 1}
		for _, g in ipairs(L.gates) do
			xs[#xs + 1] = g.x
		end
		for _, x in ipairs(xs) do
			lamps[x .. ":" .. (L.coast.y1 - 1)] = true
			lamps[x .. ":" .. (L.coast.y2 + 1)] = true
		end
		if #L.dock > 0 then
			lamps[L.land.x1 .. ":" .. (L.cy - 1)] = true
		end
	end
	for _, f in ipairs(foot) do
		local x, y = f.x, f.y
		local tile = {x = x, y = y, z = f.z, kind = f.kind, items = {}}
		local k = f.kind
		if k == "water" then
			tile.ground = pick(look.water or {t.water}, x, y, 1)
		elseif k == "dock" then
			tile.ground = look.dock or t.ground
		elseif k == "path" or k == "gate" or k == "trail" then
			tile.ground = look.path or t.gateGround
		elseif k == "marker" then
			tile.ground = t.markerGround
		else
			tile.ground = pick(look.grass or {t.ground}, x, y, 2)
		end
		-- borders: the water's shore on the land, the grass's edge on the path
		local over, pieces
		if grassy[k] and look.shore then
			over, pieces = "water", look.shore
		elseif (k == "path" or k == "gate" or k == "trail") and look.pathEdge then
			over, pieces = "grass", look.pathEdge
		end
		if over then
			local function is(dx, dy)
				local nk = kindAt(x + dx, y + dy)
				if over == "water" then
					return nk == "water"
				end
				return grassy[nk] == true
			end
			for _, name in ipairs(A.borderPieces(is(0, -1), is(1, 0), is(0, 1), is(-1, 0), is(1, -1), is(-1, -1), is(1, 1), is(-1, 1))) do
				if pieces[name] then
					tile.items[#tile.items + 1] = pieces[name]
				end
			end
		end
		local key = x .. ":" .. y
		if k == "fence" and look.fence then
			local function fence(dx, dy)
				return kindAt(x + dx, y + dy) == "fence"
			end
			tile.items[#tile.items + 1] = NP.fencePiece(fence(0, -1), fence(1, 0), fence(0, 1), fence(-1, 0), look.fence)
		elseif k == "land" then
			-- the land strip: lamps, then trees and bushes on the middle rows, grass tufts and flowers elsewhere
			local shore = kindAt(x, y - 1) == "water" or kindAt(x, y + 1) == "water" or kindAt(x - 1, y) == "water"
				or kindAt(x + 1, y) == "water"
			local h = tileHash(x, y, 3) % 100
			if lamps[key] then
				tile.items[#tile.items + 1] = look.lamp
			elseif not shore and look.trees and h < 34 then
				tile.items[#tile.items + 1] = pick(look.trees, x, y, 4)
			elseif not shore and look.bushes and h < 52 then
				tile.items[#tile.items + 1] = pick(look.bushes, x, y, 5)
			elseif look.flowers and h < 75 then
				tile.items[#tile.items + 1] = pick(look.flowers, x, y, 6)
			end
		elseif k == "ground" and not busy[key] and look.flowers then
			-- inside the pens only things that do not block: tufts and flowers along the fences
			local r = L.rooms[NP.roomOf({x = x, y = y, z = L.z}, L) or 1]
			local edge = y == r.y1 or y == r.y2 or x == r.x1 or x == r.x2
			if edge and tileHash(x, y, 7) % 100 < 45 then
				tile.items[#tile.items + 1] = pick(look.flowers, x, y, 8)
			end
		elseif k == "dock" and look.bollard and (x == L.land.x1 - (t.dockLength or 0)) then
			tile.items[#tile.items + 1] = y == L.cy and look.bollard or (look.barrel or look.bollard)
		end
		tiles[#tiles + 1] = tile
	end
	-- the boat: north to south on the water beside the dock
	local boat = {}
	if L.boat and look.boat then
		for i, id in ipairs(look.boat) do
			boat[L.boat.x .. ":" .. (L.boat.y + i - 1)] = id
		end
		for _, tile in ipairs(tiles) do
			local id = boat[tile.x .. ":" .. tile.y]
			if id and tile.kind == "water" then
				tile.items[#tile.items + 1] = id
			end
		end
	end
	return {tiles = tiles, layout = L}
end

-- state machine. stage: 1..rooms in progress, cfg.stageDone / cfg.stageSkipped final; done: bit mask of finished
-- stations.
function NP.inTutorial(stage, c)
	c = c or NP.cfg()
	stage = tonumber(stage) or -1
	return stage >= 1 and stage <= c.tutorial.rooms
end

function NP.stationBit(i)
	return math.floor(2 ^ (i - 1))
end

-- may the player walk through gate i (from room i to room i+1)? only once station i is done
function NP.gateOpen(i, done)
	return NP.hasBit(done, NP.stationBit(i))
end

-- stage after passing gate i: the next station, never back
function NP.stageAfterGate(i, stage)
	stage = tonumber(stage) or 1
	return math.max(stage, i + 1)
end

-- may the player use the exit? every station before the last done and the last one reached
function NP.exitOpen(stage, done, c)
	c = c or NP.cfg()
	local n = c.tutorial.rooms
	if (tonumber(stage) or 0) < n then
		return false
	end
	for i = 1, n - 1 do
		if not NP.hasBit(done, NP.stationBit(i)) then
			return false
		end
	end
	return true
end

-- where a player in the tutorial belongs: the arrival spot of its station's room
function NP.resumeSpot(stage, L)
	L = L or NP.layout()
	stage = math.max(1, math.min(#L.rooms, tonumber(stage) or 1))
	return L.rooms[stage].arrival
end

-- station 2: done when the spellbook was opened and, if the class has a spell for it, a spell was cast
function NP.spellTaskDone(flags, hasSpell)
	return NP.hasBit(flags, 1) and (not hasSpell or NP.hasBit(flags, 2))
end

-- ------------------------------------------------------------------------------------------------ tutorial reset
-- What the island gives is lent: when the character leaves it (exit, skip, time limit, staff close) it ends as the
-- character it was when the island began, plus the real starter kit. NP.takeSnapshot (tutorial start) stores that
-- character in the storages of Chaos.storage.tutorialSnapshot; NP.tutorialReset (tutorial end) puts it back: level and
-- experience, skills and magic level, max health / mana / capacity, full health and mana, the island's lent items
-- (tagged with tutorial.lentTag, the Orb of Upheaval), the free passive point and the island's own storages. Both are
-- written against the engine's Player API only, so tests/newplayer_reset_test.lua runs them on a mocked player.
-- Skills and magic level cannot be lowered from Lua: newplayer_tutorial.lua stops their gains on the island
-- (EventCallback onGainSkillTries, NP.skillTriesFilter); the reset only raises what a death took.

NP.SNAP = {saved = 0, level = 1, expHi = 2, expLo = 3, magic = 4, manaSpent = 5, maxHealth = 6, maxMana = 7, cap = 8,
	armorCount = 9, orbCount = 10, skillLevel = 11, skillTries = 18} -- skills 0..6: +11..+17 levels, +18..+24 tries
NP.SNAP_SIZE = 30 -- 7102750 - 7102779 reserved
NP.SKILLS = {0, 1, 2, 3, 4, 5, 6} -- SKILL_FIST .. SKILL_FISHING
local EXP_SPLIT = 1000000000 -- storages are 32-bit: experience is kept as hi x 1e9 + lo

function NP.snapKey(field, i)
	local base = (rawget(_G, "Chaos") and Chaos.storage and Chaos.storage.tutorialSnapshot) or 7102750
	return base + NP.SNAP[field] + (i or 0)
end

local function clampInt(v)
	v = floor(tonumber(v) or 0)
	return math.max(0, math.min(v, 2147483647))
end

-- the island's lent items: one tag for every item it creates (custom attribute)
function NP.lentTag(c)
	c = c or NP.cfg()
	return c.tutorial.lentTag or "chaos_tutorial"
end

-- store the character as it is now (the tutorial's start). An earlier snapshot is kept (a staff restart of the island
-- must not record what the first run gave). Returns true when a new one was written.
function NP.takeSnapshot(player, c)
	c = c or NP.cfg()
	if NP.isSet(player:getStorageValue(NP.snapKey("saved"))) then
		return false
	end
	local exp = math.max(0, floor(tonumber(player:getExperience()) or 0))
	local set = function(field, value, i)
		player:setStorageValue(NP.snapKey(field, i), clampInt(value))
	end
	set("level", player:getLevel())
	set("expHi", floor(exp / EXP_SPLIT))
	set("expLo", exp % EXP_SPLIT)
	set("magic", player:getBaseMagicLevel())
	set("manaSpent", player:getManaSpent())
	set("maxHealth", player:getMaxHealth())
	set("maxMana", player:getMaxMana())
	set("cap", player.getCapacity and player:getCapacity() or 0)
	set("armorCount", player:getItemCount(c.tutorial.orbItem.id))
	set("orbCount", player:getItemCount(c.orbId))
	for i, skill in ipairs(NP.SKILLS) do
		set("skillLevel", player:getSkillLevel(skill), i - 1)
		set("skillTries", player:getSkillTries(skill), i - 1)
	end
	set("saved", 1)
	return true
end

-- the stored snapshot, or nil
function NP.readSnapshot(player)
	if not NP.isSet(player:getStorageValue(NP.snapKey("saved"))) then
		return nil
	end
	local get = function(field, i)
		return math.max(0, tonumber(player:getStorageValue(NP.snapKey(field, i))) or 0)
	end
	local s = {level = get("level"), exp = get("expHi") * EXP_SPLIT + get("expLo"), magic = get("magic"),
		manaSpent = get("manaSpent"), maxHealth = get("maxHealth"), maxMana = get("maxMana"), cap = get("cap"),
		armorCount = get("armorCount"), orbCount = get("orbCount"), skills = {}}
	for i, skill in ipairs(NP.SKILLS) do
		s.skills[skill] = {level = get("skillLevel", i - 1), tries = get("skillTries", i - 1)}
	end
	return s
end

function NP.clearSnapshot(player)
	for offset = 0, NP.SNAP_SIZE - 1 do
		player:setStorageValue(NP.snapKey("saved") + offset, -1)
	end
end

-- a snapshot taken before the wearable kit came (a character already on the island): its item counts follow, so the
-- reset never takes the kit's leather armor for the island's
function NP.snapshotAddItems(player, c)
	c = c or NP.cfg()
	if not NP.isSet(player:getStorageValue(NP.snapKey("saved"))) then
		return false
	end
	player:setStorageValue(NP.snapKey("armorCount"), clampInt(player:getItemCount(c.tutorial.orbItem.id)))
	return true
end

-- a snapshot taken before the stats correction (NP.fixStats): the reset puts the corrected values back, not the old
function NP.snapshotSetStats(player, fix)
	if not NP.isSet(player:getStorageValue(NP.snapKey("saved"))) then
		return false
	end
	player:setStorageValue(NP.snapKey("maxHealth"), clampInt(fix.maxHealth))
	player:setStorageValue(NP.snapKey("maxMana"), clampInt(fix.maxMana))
	player:setStorageValue(NP.snapKey("cap"), clampInt(fix.cap))
	return true
end

-- skill tries / mana spent that must arrive exactly (the reset raising back what a death took): the island's
-- EventCallback onGainSkillTries returns this amount, past every multiplier (NP.skillTriesFilter)
NP.exactTries = NP.exactTries or {}

local function addTriesExact(player, skill, amount)
	if amount <= 0 then
		return
	end
	local id = player:getId()
	NP.exactTries[id] = amount
	local ok, err = pcall(function()
		if skill == "magic" then
			player:addManaSpent(amount)
		else
			player:addSkillTries(skill, amount)
		end
	end)
	NP.exactTries[id] = nil
	if not ok then
		error(err, 0)
	end
end

-- the EventCallback onGainSkillTries filter: the exact amount while the reset raises a skill, nothing while the
-- character is on the island (stage = its tutorial stage), else the tries unchanged
function NP.skillTriesFilter(playerId, stage, tries, c)
	local exact = NP.exactTries[playerId]
	if exact then
		return exact
	end
	if NP.inTutorial(stage, c) then
		return 0
	end
	return tries
end

-- raise one skill (or "magic") back to level / tries; never lowers. Returns the levels raised.
local function raiseTo(player, skill, level, tries)
	local voc = player:getVocation()
	local raised = 0
	for _ = 1, 1000 do
		local cur, have
		if skill == "magic" then
			cur, have = player:getBaseMagicLevel(), player:getManaSpent()
		else
			cur, have = player:getSkillLevel(skill), player:getSkillTries(skill)
		end
		local need
		if cur < level then
			local req = skill == "magic" and voc:getRequiredManaSpent(cur + 1) or voc:getRequiredSkillTries(skill, cur + 1)
			need = math.max(1, (tonumber(req) or 0) - have)
			raised = raised + 1
		elseif cur == level and have < tries then
			need = tries - have
		else
			break
		end
		addTriesExact(player, skill, need)
	end
	return raised
end

-- put the snapshot's character back: experience exactly (addExperience may pass bonus callbacks, so an overshoot is
-- removed again), skills and magic level raised back, max health / mana / capacity, then full health and mana
function NP.restoreStats(player, snap)
	local report = {levelFrom = player:getLevel()}
	local cur = player:getExperience()
	if cur > snap.exp then
		player:removeExperience(cur - snap.exp, false)
	elseif cur < snap.exp then
		player:addExperience(snap.exp - cur, false)
		cur = player:getExperience()
		if cur > snap.exp then
			player:removeExperience(cur - snap.exp, false)
		end
	end
	report.levelTo = player:getLevel()
	report.skillsRaised = 0
	for _, skill in ipairs(NP.SKILLS) do
		local s = snap.skills[skill]
		if s then
			report.skillsRaised = report.skillsRaised + raiseTo(player, skill, s.level, s.tries)
		end
	end
	report.skillsRaised = report.skillsRaised + raiseTo(player, "magic", snap.magic, snap.manaSpent)
	if snap.maxHealth > 0 then
		player:setMaxHealth(snap.maxHealth)
	end
	if player.setMaxMana then
		player:setMaxMana(snap.maxMana)
	end
	if snap.cap > 0 and player.setCapacity then
		player:setCapacity(snap.cap)
	end
	return report
end

-- full health and mana (a fresh character's)
function NP.fillUp(player)
	local h = player:getMaxHealth() - player:getHealth()
	if h > 0 then
		player:addHealth(h)
	end
	local m = player:getMaxMana() - player:getMana()
	if m ~= 0 then
		player:addMana(m)
	end
end

-- every item the island lent: tagged ones (equipped, in a container, in the inbox), and the Orb of Upheaval when it was
-- handed out and not used. Removed; returns how many items went.
function NP.removeLent(player, snap, flags, done, c)
	c = c or NP.cfg()
	local tag = NP.lentTag(c)
	local found, seen = {}, {}
	local function consider(item)
		if item and not seen[item] then
			seen[item] = true
			local okA, v = pcall(function() return item:getCustomAttribute(tag) end)
			if okA and v ~= nil and v ~= false and v ~= 0 and v ~= "" then
				found[#found + 1] = item
				return true
			end
			if item:isContainer() then
				for _, inner in ipairs(item:getItems(true) or {}) do
					consider(inner)
				end
			end
		end
		return false
	end
	local first = rawget(_G, "CONST_SLOT_FIRST") or 1
	local last = rawget(_G, "CONST_SLOT_LAST") or 10
	for slot = first, last do
		consider(player:getSlotItem(slot))
	end
	local inbox = player.getInbox and player:getInbox()
	if inbox then
		for _, item in ipairs(inbox:getItems(true) or {}) do
			consider(item)
		end
	end
	local removed = 0
	local armorId = c.tutorial.orbItem.id
	local armorGone = false
	for _, item in ipairs(found) do
		armorGone = armorGone or item:getId() == armorId
		item:remove()
		removed = removed + 1
	end
	-- the leather armor without its tag (an engine that dropped the attribute): one more than the character had
	if not armorGone and NP.hasBit(flags, 8) and snap and player:getItemCount(armorId) > snap.armorCount then
		if player:removeItem(armorId, 1) then
			removed = removed + 1
		end
	end
	-- the orb: lent at station 4, used (gone) once the station is done
	if NP.hasBit(flags, 8) and not NP.hasBit(done, NP.stationBit(4)) then
		local before = snap and snap.orbCount or 0
		if player:getItemCount(c.orbId) > before and player:removeItem(c.orbId, 1) then
			removed = removed + 1
		end
	end
	return removed
end

-- the whole reset at the tutorial's end (idempotent: a second call finds nothing left to undo). Returns a report:
-- {snapshot = bool, levelFrom, levelTo, skillsRaised, items, passive}
function NP.tutorialReset(player, c)
	c = c or NP.cfg()
	local flags = math.max(0, tonumber(player:getStorageValue(NP.key("flags", c))) or 0)
	local done = math.max(0, tonumber(player:getStorageValue(NP.key("done", c))) or 0)
	local snap = NP.readSnapshot(player)
	local report = {snapshot = snap ~= nil, items = 0, passive = false, skillsRaised = 0}
	-- the free passive point of station 3 (and an allocation it paid for: NP.passiveRefund, the engine's hook)
	if NP.hasBit(flags, 4) then
		local key = (rawget(_G, "Chaos") and Chaos.storage and Chaos.storage.passiveExtraPoints) or 7100020
		player:setStorageValue(key, math.max(0, math.max(0, tonumber(player:getStorageValue(key)) or 0) - 1))
		report.passive = true
		if NP.passiveRefund then
			NP.passiveRefund(player)
		end
	end
	report.items = NP.removeLent(player, snap, flags, done, c)
	if snap then
		local r = NP.restoreStats(player, snap)
		report.levelFrom, report.levelTo, report.skillsRaised = r.levelFrom, r.levelTo, r.skillsRaised
	end
	NP.fillUp(player)
	-- the island's own storages (the stage keeps its final value: done / skipped)
	for _, key in ipairs({"done", "kills", "orbBase", "flags", "islandUsed"}) do
		player:setStorageValue(NP.key(key, c), -1)
	end
	NP.clearSnapshot(player)
	return report
end

-- the kit at a login after the island: a character that left the island (done or skipped) but logged out before the
-- delayed kit arrived still gets it (kitDueAtLogin only covers the very first login)
function NP.kitDueAfterTutorial(kitStorage, stage, c)
	c = c or NP.cfg()
	stage = tonumber(stage) or -1
	return not NP.isSet(kitStorage) and (stage == c.stageDone or stage == c.stageSkipped)
end

-- the station 2 spell of a vocation (by its kit name, like the kits), or nil
function NP.tutorialSpellFor(vocId, c)
	c = c or NP.cfg()
	local name = NP.kitNameFor(vocId, c)
	if not name then
		return nil
	end
	local kitName = name
	local seen = {}
	while kitName and not seen[kitName] do
		seen[kitName] = true
		if c.tutorial.spells[kitName] then
			return c.tutorial.spells[kitName]
		end
		kitName = c.kits[kitName] and c.kits[kitName].base
	end
	return nil
end

return NP
