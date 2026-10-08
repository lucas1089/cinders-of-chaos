-- New players: the pure part (no engine calls), shared by newplayer.lua, newplayer_tutorial.lua and
-- tests/newplayer_test.lua.
--   kits        kitFor(vocationId): the kit of a vocation (own row, base class, engine demotion, default), merged
--               with the common backpack items; setKit to add or change rows (the class rework)
--   flags       one-time flags in storages (kit, welcome, milestones), bit helpers
--   milestones  which gifts a level-up from old to new level earns
--   tutorial    island layout and footprint, the station state machine (gates, exit, resume spot)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosNewPlayer = ChaosNewPlayer or {}
local NP = ChaosNewPlayer

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
-- Geometry, all derived from cfg.tutorial: rooms side by side west to east, each roomW x roomH, divider walls between
-- them with a gate in the middle row, water around (the island's coast) and waterRing more rows of water outside.
function NP.layout(t)
	t = t or NP.cfg().tutorial
	local o = t.origin
	local L = {z = o.z, rooms = {}, gates = {}}
	local W = t.rooms * (t.roomW + 1) -- x offset of the east coast
	local H = t.roomH + 1 -- y offset of the south coast
	L.coast = {x1 = o.x, y1 = o.y, x2 = o.x + W, y2 = o.y + H}
	L.outer = {x1 = o.x - t.waterRing, y1 = o.y - t.waterRing, x2 = o.x + W + t.waterRing, y2 = o.y + H + t.waterRing}
	local cy = o.y + floor((t.roomH + 1) / 2)
	for i = 1, t.rooms do
		local x1 = o.x + (i - 1) * (t.roomW + 1) + 1
		local x2 = x1 + t.roomW - 1
		local cx = x1 + floor(t.roomW / 2)
		L.rooms[i] = {
			x1 = x1, y1 = o.y + 1, x2 = x2, y2 = o.y + t.roomH,
			statue = {x = cx, y = o.y + 2, z = o.z},
			marker = {x = cx, y = o.y + 3, z = o.z},
			arrival = {x = x1 + 1, y = cy, z = o.z},
			basins = {{x = x1, y = o.y + 1, z = o.z}, {x = x2, y = o.y + t.roomH, z = o.z}},
			decor = {{x = x2, y = o.y + 1, z = o.z}, {x = x1, y = o.y + t.roomH, z = o.z}}
		}
		if i < t.rooms then
			L.gates[i] = {x = x2 + 1, y = cy, z = o.z}
		end
	end
	local r1 = L.rooms[1]
	L.skipStatue = {x = r1.x1 + 1, y = r1.y1, z = o.z}
	L.spawns = {{x = r1.x2 - 1, y = r1.y2 - 1, z = o.z}, {x = r1.x2 - 2, y = r1.y2 - 2, z = o.z}, {x = r1.x2, y = r1.y2 - 3, z = o.z}}
	local r5 = L.rooms[t.rooms]
	L.exit = {x = r5.x2 - 1, y = cy, z = o.z}
	return L
end

local function inRect(r, z, pos)
	return pos and pos.z == z and pos.x >= r.x1 and pos.x <= r.x2 and pos.y >= r.y1 and pos.y <= r.y2
end

-- inside the island (coast included)
function NP.onIsland(pos, L)
	L = L or NP.layout()
	return inRect(L.coast, L.z, pos)
end

-- the room (1..rooms) a position is in, or nil (walls, gates, coast)
function NP.roomOf(pos, L)
	L = L or NP.layout()
	for i, r in ipairs(L.rooms) do
		if inRect(r, L.z, pos) then
			return i
		end
	end
	return nil
end

-- every tile: {x, y, z, kind} with kind water | ground | wall | gate | marker
function NP.footprint(L, t)
	t = t or NP.cfg().tutorial
	L = L or NP.layout(t)
	local special = {}
	local function mark(p, kind)
		special[p.x .. ":" .. p.y] = kind
	end
	for _, g in ipairs(L.gates) do
		mark(g, "gate")
	end
	for _, r in ipairs(L.rooms) do
		mark(r.marker, "marker")
	end
	local list = {}
	for y = L.outer.y1, L.outer.y2 do
		for x = L.outer.x1, L.outer.x2 do
			local kind
			if x <= L.coast.x1 or x >= L.coast.x2 or y <= L.coast.y1 or y >= L.coast.y2 then
				kind = "water"
			else
				kind = special[x .. ":" .. y]
				if not kind then
					kind = "ground"
					for i = 1, #L.rooms - 1 do
						if x == L.rooms[i].x2 + 1 then
							kind = "wall"
						end
					end
				end
			end
			list[#list + 1] = {x = x, y = y, z = L.z, kind = kind}
		end
	end
	return list
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
