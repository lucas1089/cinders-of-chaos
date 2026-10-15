-- Run from the server/ folder: luajit tests/itemsets_test.lua (and lua5.3; CI runs both)
-- Item sets: data/lib/chaos_item_sets.lua (+ _config.lua) and data/scripts/chaos/itemsets.lua against a mocked engine:
-- the data (pieces = unique specs, families, bonuses, sources), counting (duplicates once, two-handed twice, the
-- piece's level, swaps), the bonuses through item_mods.lua (caps) and the condition, every signature effect with and
-- without the set, the tooltip block and the look text, the chase drops, salvage of a piece and transmog.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end

-- ---------------------------------------------------------------- the world boss and rift names (real files)
dofile("data/scripts/chaos/chaos_constants.lua")
local worldBosses = {}
for _, b in ipairs(Chaos.worldBoss.bosses) do
	worldBosses[b.name] = true
end
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")
local raidCfg = dofile("data/scripts/chaos/raid_config.lua")
Chaos = {heal = nil} -- the scripts skip chaos_constants.lua from here on

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ARTICLE = 1, 2, 3
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE = 10, 11, 12
ITEM_ATTRIBUTE_ARMOR, ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_SHOOTRANGE = 13, 14, 15
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 1, 2, 3, 4, 5, 6
CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 7, 8, 9, 10
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_BACKPACK, SLOTP_ARMOR, SLOTP_RIGHT, SLOTP_LEFT = 1, 2, 4, 8, 16, 32
SLOTP_LEGS, SLOTP_FEET, SLOTP_RING, SLOTP_AMMO, SLOTP_TWO_HAND = 64, 128, 256, 512, 2048
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND, WEAPON_AMMO = 0, 1, 2, 3, 4, 5, 6, 7
COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 1, 2, 4, 8
COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE, COMBAT_HEALING = 16, 32, 64, 128
ORIGIN_NONE, ORIGIN_CONDITION, ORIGIN_SPELL, ORIGIN_MELEE, ORIGIN_RANGED = 0, 1, 2, 3, 4
CONST_ME_BLOCKHIT, CONST_ME_NONE, CONST_ME_DRAWBLOOD, CONST_ME_HITBYFIRE = 9, 0, 1, 2
RETURNVALUE_NOERROR, RETURNVALUE_NOTPOSSIBLE = 0, 1
SKILL_LEVEL = 8
CONDITION_ATTRIBUTES, CONDITION_HASTE, CONDITION_BLEEDING, CONDITION_FIRE, CONDITION_PARALYZE = 1, 2, 3, 4, 5
CONDITIONID_DEFAULT, CONDITIONID_COMBAT = 0, 1
CONDITION_PARAM_TICKS, CONDITION_PARAM_SPEED, CONDITION_PARAM_SUBID, CONDITION_PARAM_OWNER, CONDITION_PARAM_DELAYED = 1, 2, 3, 4, 5
CONDITION_PARAM_SKILL_AXE, CONDITION_PARAM_STAT_MAGICPOINTS, CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT = 20, 21, 22
CONDITION_PARAM_SKILL_DISTANCE, CONDITION_PARAM_STAT_MAXMANAPOINTSPERCENT = 23, 24
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 1, 2
CONTAINER_POSITION = 0xFFFF

-- item types: the set pieces' base items as the engine sees them (slot position, weapon type)
local TYPES = {
	[27658] = {name = "eldritch greataxe", weaponType = WEAPON_AXE, slot = 48 + SLOTP_TWO_HAND}, -- two-handed
	[25410] = {name = "visage of the end days", slot = SLOTP_HEAD}, [25175] = {name = "fireheart hauberk", slot = SLOTP_ARMOR},

	[7404] = {name = "assassin dagger", weaponType = WEAPON_SWORD, slot = 48},
	[7418] = {name = "nightmare blade", weaponType = WEAPON_SWORD, slot = 48},
	[28112] = {name = "shadewalker helmet", slot = SLOTP_HEAD}, [11301] = {name = "Jadefen armor", slot = SLOTP_ARMOR},
	[11304] = {name = "Jadefen legs", slot = SLOTP_LEGS}, [27249] = {name = "winged boots", slot = SLOTP_FEET},
	[24637] = {name = "oriental shoes", slot = SLOTP_FEET}, [18406] = {name = "prismatic boots", slot = SLOTP_FEET},
	[28691] = {name = "ring of temptation", slot = SLOTP_RING}, [28100] = {name = "embersage legs", slot = SLOTP_LEGS},
	[27474] = {name = "grand sanguine crossbow", weaponType = WEAPON_DISTANCE, slot = 48 + SLOTP_TWO_HAND},
	[29470] = {name = "hellstalker visor", slot = SLOTP_HEAD}, [15407] = {name = "depth lorica", slot = SLOTP_ARMOR},
	[28114] = {name = "shadewalker legs", slot = SLOTP_LEGS},
	[2496] = {name = "horned helmet", slot = SLOTP_HEAD}, [8892] = {name = "ethno coat", slot = SLOTP_ARMOR},
	[27692] = {name = "dawnfire pantaloons", slot = SLOTP_LEGS}, [27647] = {name = "makeshift boots", slot = SLOTP_FEET},
	[3975] = {name = "salamander shield", weaponType = WEAPON_SHIELD, slot = 48},
	[10314] = {name = "claw", slot = SLOTP_RING},
	[29560] = {name = "Deathlord Headguard", slot = SLOTP_HEAD}, [29561] = {name = "Deathlord Cuirass", slot = SLOTP_ARMOR},
	[29559] = {name = "Deathlord Shield", weaponType = WEAPON_SHIELD, slot = 48},
	[27403] = {name = "lion amulet", slot = SLOTP_NECKLACE},
	[29573] = {name = "Soulbinder Mask", slot = SLOTP_HEAD}, [8890] = {name = "robe of the underworld", slot = SLOTP_ARMOR},
	[29575] = {name = "Soulbinder Kilt", slot = SLOTP_LEGS}, [28126] = {name = "forbidden pendant", slot = SLOTP_NECKLACE},
	[28111] = {name = "vigils spellbook", weaponType = WEAPON_SHIELD, slot = 48},
	[28106] = {name = "vigils helmet", slot = SLOTP_HEAD}, [28107] = {name = "vigils armor", slot = SLOTP_ARMOR},
	[28108] = {name = "vigils legs", slot = SLOTP_LEGS}, [28109] = {name = "vigils boots", slot = SLOTP_FEET},
	[28125] = {name = "forbidden ring", slot = SLOTP_RING},
	[24718] = {name = "werewolf helmet", slot = SLOTP_HEAD}, [24741] = {name = "fur armor", slot = SLOTP_ARMOR},
	[2129] = {name = "wolf tooth chain", slot = SLOTP_NECKLACE}, [26808] = {name = "butterfly ring", slot = SLOTP_RING},
	[27666] = {name = "gilded eldritch wand", weaponType = WEAPON_WAND, slot = 48},
	[29471] = {name = "dreadfire headpiece", slot = SLOTP_HEAD}, [7899] = {name = "magma coat", slot = SLOTP_ARMOR},
	[7894] = {name = "magma legs", slot = SLOTP_LEGS}, [28101] = {name = "embersage boots", slot = SLOTP_FEET},
	[28041] = {name = "Astro Ring", slot = SLOTP_RING},
	[27646] = {name = "jungle bow", weaponType = WEAPON_DISTANCE, slot = 48 + SLOTP_TWO_HAND},
	[2500] = {name = "amazon armor", slot = SLOTP_ARMOR},
	[2400] = {name = "magic sword", weaponType = WEAPON_SWORD, slot = 48}
}
function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return TYPES[id] and id or 0 end, getName = function() return t.name or "" end,
		isContainer = function() return false end, isStackable = function() return false end,
		getWeaponType = function() return t.weaponType or 0 end, getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return 0 end, getAttack = function() return 0 end, getDefense = function() return 0 end,
		getExtraDefense = function() return 0 end, getHitChance = function() return 0 end,
		getShootRange = function() return 1 end, getElementDamage = function() return 0 end,
		getAttackSpeed = function() return 0 end, getAbilities = function() return {} end, getClientId = function() return id end,
		getMinReqLevel = function() return 0 end, getMinReqMagicLevel = function() return 0 end,
		getVocationString = function() return "" end, getDescription = function() return "" end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id)
	return setmetatable({id = id, count = 1, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getType() return ItemType(self.id) end
function Item:getCount() return 1 end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] end
function Item:hasAttribute(k) return self.attrs[k] ~= nil end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getActionId() return 0 end
function Item:isItem() return true end
function Item:getWeight() return 1000 end

local events, callbacks = {}, {}
local function registry(kind)
	return function(name)
		local obj = {name = name, kind = kind}
		obj.register = function(self) events[name] = self return true end
		obj.type = function() end
		obj.interval = function() end
		return obj
	end
end
CreatureEvent, GlobalEvent = registry("creature"), registry("global")
EventCallback = setmetatable({}, {
	__newindex = function(self, k, v) rawset(self, "_pending", {k, v}) end,
	__index = function(self, k)
		if k == "register" then
			return function(this)
				local p = rawget(this, "_pending")
				callbacks[p[1]] = callbacks[p[1]] or {}
				table.insert(callbacks[p[1]], p[2])
				rawset(this, "_pending", nil)
			end
		end
	end
})
function addEvent() end

local clock = 1000000
os.mtime = function() return clock end

local hits, messages, broadcasts = {}, {}, {}
function doTargetCombatHealth(cid, target, ctype, min, max, effect)
	hits[#hits + 1] = {from = cid, to = target, type = ctype, amount = -min}
end

local Creature_ = {}
Creature_.__index = Creature_
local nextId, all = 1, {}
local function newCreature(kind, t)
	t = t or {}
	nextId = nextId + 1
	local c = setmetatable({cid = 0x10000000 + nextId, kind = kind, slots = {}, health = t.health or 1000,
		maxHealth = t.maxHealth or 1000, registered = {}, level = t.level or 100, storage = {},
		pos = t.pos or {x = 100, y = 100, z = 7}, conditions = {}, master = t.master, backpack = {}, mana = 0}, Creature_)
	all[c.cid] = c
	return c
end
function Creature(id) return all[id] end
function Player(id) local c = all[id] return c and c.kind == "player" and c or nil end
function Creature_:getId() return self.cid end
function Creature_:getName() return "Tester" end
function Creature_:isPlayer() return self.kind == "player" end
function Creature_:isMonster() return self.kind == "monster" end
function Creature_:getMaster() return self.master end
function Creature_:getSlotItem(slot) return self.slots[slot] end
function Creature_:getBaseSpeed() return 400 end
function Creature_:changeSpeed() end
function Creature_:getHealth() return self.health end
function Creature_:getMaxHealth() return self.maxHealth end
function Creature_:getLevel() return self.level end
function Creature_:addHealth(a, b)
	if type(a) == "string" then self.health = math.min(self.maxHealth, self.health + b) end
end
function Creature_:addMana(n) self.mana = self.mana + n end
function Creature_:registerEvent(name) self.registered[name] = true end
function Creature_:getStorageValue(k) return self.storage[k] or -1 end
function Creature_:setStorageValue(k, v) self.storage[k] = v end
function Creature_:addCondition(c) self.conditions[#self.conditions + 1] = c end
function Creature_:removeCondition(kind, id, sub)
	for i = #self.conditions, 1, -1 do
		local c = self.conditions[i]
		if c.kind == kind and c.params[CONDITION_PARAM_SUBID] == sub then table.remove(self.conditions, i) end
	end
end
function Creature_:getPosition()
	local pos = self.pos
	return setmetatable({sendMagicEffect = function() end}, {__index = pos})
end
function Creature_:getType() return {isBoss = function() return false end, getElementList = function() return {} end} end
function Creature_:getParty() return self.party end
function Creature_:sendTextMessage(kind, text) messages[#messages + 1] = text end
function Creature_:addItemEx(item) self.backpack[#self.backpack + 1] = item return RETURNVALUE_NOERROR end
function Creature_:getEnergyShield() return 0 end
function ChaosTierOf() return "normal" end
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
Condition = function(kind, id)
	return {kind = kind, params = {}, damage = nil, setParameter = function(self, k, v) self.params[k] = v end,
		setTicks = function(self, t) self.ticks = t end, setFormula = function() end,
		addDamage = function(self, rounds, interval, value) self.damage = {rounds, interval, value} end}
end

local online, nearby = {}, {}
Game = {getPlayers = function() return online end,
	getSpectators = function() local out = {} for _, m in ipairs(nearby) do out[#out + 1] = m end return out end,
	createItem = function(id) return newItem(id) end,
	broadcastMessage = function(text) broadcasts[#broadcasts + 1] = text end}

-- the open sets of pair 28 stay out of the data checks below (their own section further down)
ChaosGearSets = dofile("data/lib/chaos_gear_sets.lua")
ChaosGearSets.PAIR28 = false
dofile("data/scripts/chaos/item_mods.lua")
dofile("data/lib/chaos_unique_specs.lua")
dofile("data/lib/chaos_unique_items.lua")
dofile("data/scripts/chaos/itemsets.lua")
local S, M = ChaosItemSets, ChaosItemMods
local cache = ChaosItemModsCache

-- ---------------------------------------------------------------- the data
local families, ids = {}, {}
for _, set in ipairs(S.sets) do
	families[set.family] = (families[set.family] or 0) + 1
	ok(#set.pieces >= 4 and #set.pieces <= 6, set.key .. ": 4-6 pieces")
	local last = 0
	for _, b in ipairs(set.bonuses) do
		ok(b.n > last and b.n <= set.total, set.key .. ": bonus thresholds rise and can be reached")
		last = b.n
		for k in pairs(b.stats or {}) do
			ok(S.COND[k] or S.RES[k] or M.byKey[k], set.key .. ": a known stat " .. k)
		end
		ok(not b.effect or S.config.effects[b.effect], set.key .. ": a known effect")
		ok(#S.bonusLines(b) > 0, set.key .. ": the bonus says something")
	end
	ok(set.bonuses[1].n == 2, set.key .. ": the first bonus at 2")
	for _, p in ipairs(set.pieces) do
		ok(not ids[p.id], "one base item per piece: " .. p.id)
		ids[p.id] = true
		local spec = ChaosUniqueSpecs[p.id]
		ok(spec ~= nil, "a unique spec for " .. p.name)
		eq(spec.name, p.name, "the piece's name is the XML name")
		eq(spec.set, set.key, p.name .. ": the XML set key")
		-- the description names the level; the older Embers uniques name theirs, below their base item's equip level
		local named = tonumber(spec.description:match("Requires level (%d+)"))
		ok(named and named <= p.level and (set.key == "embers" or named == p.level), p.name .. ": the description's level")
	end
	local src = set.sources
	if src.rift then
		local found = false
		for _, th in ipairs(riftCfg.themes) do found = found or th.name == src.rift.theme end
		ok(found, set.key .. ": a real rift theme")
	end
	for _, key in ipairs(src.raid or {}) do
		local found = false
		for _, b in ipairs(raidCfg.bosses) do found = found or b.key == key end
		ok(found, set.key .. ": a real raid boss " .. key)
	end
	if src.uniques and src.uniques.bossOnly then
		for _, m in ipairs(src.uniques.monsters) do
			ok(worldBosses[m], set.key .. ": a real world boss " .. m)
		end
	end
	ok(next(src) ~= nil or set.key == "embers", set.key .. ": drops somewhere")
end
eq(#S.sets, 10, "ten sets")
for _, f in ipairs({"melee", "ranged", "caster", "support", "hybrid"}) do
	ok((families[f] or 0) >= 2 and families[f] <= 4, "2-4 sets of the family " .. f)
end
-- every spec with a set key is a piece of that set
for id, spec in pairs(ChaosUniqueSpecs) do
	if spec.set then
		ok(S.pieceById[id] and S.pieceById[id].set.key == spec.set, "spec " .. id .. " is a listed piece")
	end
end
-- the monster / world boss pieces are uniques (set = key); the raid and Descent pieces are not
eq(ChaosUniqueById[27658].set, "bloodsworn", "a world boss piece is a unique entry")
eq(ChaosUniqueById[27658].bossOnly, true)
eq(ChaosUniqueById[27658].monsters[1], "Vharok the Blood Colossus")
eq(ChaosUniqueById[2496].set, "embers", "the old Embers uniques know their set")
eq(ChaosUniqueById[29560], nil, "a raid piece never drops from monsters")
eq(ChaosUniqueById[29573], nil, "a Descent piece never drops from monsters")
eq(ChaosUniqueByName["bloodsworn greataxe"].id, 27658, "found by name")
eq(ChaosSets.embers.name, "Embers of Aranoth", "ChaosSets keeps the old global")

-- ---------------------------------------------------------------- pieces
local function piece(id)
	local it = newItem(id)
	eq(ChaosMakeUnique(it), true, "spec for " .. id)
	return it
end
local axe = piece(27658)
eq(axe.custom.chaos_set, "bloodsworn", "ChaosMakeUnique writes the set key")
eq(axe.custom.chaos_unique, 1)
eq(S.pieceOf(axe).key, "bloodsworn")
eq(S.pieceOf(newItem(27658)), nil, "a stock eldritch greataxe is no piece")
local legacy = newItem(2496)
legacy.custom.chaos_unique = 1
eq(S.pieceOf(legacy).key, "embers", "a Hornsworn Helm made before the sets is a piece by its spec")
local forged = newItem(2400)
forged.custom.chaos_set = "bloodsworn"
eq(S.pieceOf(forged), nil, "a set key on an item that is no piece of that set counts for nothing")

-- ---------------------------------------------------------------- counting (pure)
local st = S.count({{id = 7404, set = "duskstalker"}, {id = 7404, set = "duskstalker"}, {id = 28112, set = "duskstalker"}}, 300)
eq(st.sets.duskstalker.count, 2, "two copies of the Fang count once")
st = S.count({{id = 27658, set = "bloodsworn"}, {id = 25410, set = "bloodsworn"}, {id = 25175, set = "bloodsworn"}}, 300)
eq(st.sets.bloodsworn.count, 4, "the two-handed greataxe counts twice")
eq(#S.active(S.byKey.bloodsworn, 4), 2, "two bonuses at 4")
st = S.count({{id = 27658, set = "bloodsworn"}, {id = 25410, set = "bloodsworn"}}, 299)
eq(st.sets.bloodsworn.count, 0, "below the pieces' level nothing counts")
eq(st.sets.bloodsworn.low[27658], 300, "the tooltip knows why")
st = S.count({{id = 27658, set = "gallows"}}, 300)
eq(st.sets.gallows, nil, "an entry with the wrong set key counts for nothing")
local t = S.totals(S.count({{id = 27658, set = "bloodsworn"}, {id = 25410, set = "bloodsworn"}, {id = 25175, set = "bloodsworn"},
	{id = 28100, set = "bloodsworn"}, {id = 28101, set = "bloodsworn"}}, 300))
eq(t.mods.bleedchance, 10) eq(t.mods.dot, 15) eq(t.cond.skill_axe, 3)
eq(t.effects.hemorrhage, true) eq(t.effects.redharvest, true)
eq(S.signature(S.count({}, 300)), "", "nothing worn")
eq(S.statText("bleedchance", 10), "Chance to Bleed +10%")
eq(S.statText("res_fire", 6), "Fire Resistance +6%")
eq(S.statText("deathblast", 15), "Death Blast: 15% chance on kill to explode")
eq(S.effectText("hangingverdict"), "Hanging Verdict: your ranged hits deal 20% more to monsters below 35% health")
eq(S.bonusText(S.byKey.embers.bonuses[1]), "Magic Level +1, Fire Resistance +6%", "condition / resistance stats in their order")
eq(S.bonusText(S.byKey.thornwake.bonuses[1]), "Movement Speed +4%, Life on Kill +40", "modifiers in the catalogue's order")

-- ---------------------------------------------------------------- a character
local function newPlayer(level)
	local p = newCreature("player", {health = 1000, maxHealth = 1000, level = level or 400})
	online[#online + 1] = p
	events.ChaosItemModsLogin.onLogin(p)
	events.ChaosItemSetsLogin.onLogin(p)
	return p
end
local function wear(p, slots)
	for slot, item in pairs(slots) do
		p.slots[slot] = item or nil
	end
	M.refresh(p)
end
local function monster(health, maxHealth, master)
	return newCreature("monster", {health = health or 1000, maxHealth = maxHealth or health or 1000, master = master})
end
local function cond(p)
	for _, c in ipairs(p.conditions) do
		if c.kind == CONDITION_ATTRIBUTES and c.params[CONDITION_PARAM_SUBID] == S.config.conditionSubId then return c end
	end
	return nil
end
local function reset()
	hits, messages, broadcasts = {}, {}, {}
	nearby = {}
	clock = clock + 100000
end
local function dealt(target, attacker, amount, origin, critical, ctype)
	return events.ChaosItemSetsDealt.onHealthChange(target, attacker, -amount, ctype or COMBAT_PHYSICALDAMAGE, 0,
		COMBAT_PHYSICALDAMAGE, origin or ORIGIN_MELEE, critical or false)
end

-- swaps: equip, more pieces, take one off; the totals follow through item_mods.lua
local p = newPlayer(400)
wear(p, {[CONST_SLOT_LEFT] = piece(27658)})
eq(cache[p:getId()].bleedchance, 10, "the greataxe alone is two pieces: the 2-piece bonus")
eq(cache[p:getId()].dot, 15)
eq(cond(p), nil, "no condition stat yet")
wear(p, {[CONST_SLOT_HEAD] = piece(25410), [CONST_SLOT_ARMOR] = piece(25175), [CONST_SLOT_LEGS] = piece(28100),
	[CONST_SLOT_FEET] = piece(28101)})
eq(S.stateOf(p).sets.bloodsworn.count, 6, "five items, six pieces")
eq(cond(p).params[CONDITION_PARAM_SKILL_AXE], 3, "the 6-piece axe skill as a condition")
wear(p, {[CONST_SLOT_LEFT] = false})
eq(S.stateOf(p).sets.bloodsworn.count, 4, "the axe off: four")
eq(cond(p), nil, "the condition goes with the 6-piece bonus")
eq(cache[p:getId()].bleedchance, 10, "the 2-piece bonus stays")
wear(p, {[CONST_SLOT_HEAD] = false, [CONST_SLOT_ARMOR] = false, [CONST_SLOT_LEGS] = false, [CONST_SLOT_FEET] = false})
eq(cache[p:getId()].bleedchance, 0, "everything off: nothing")
-- a piece in the wrong slot does not count: a helmet held in the hand
wear(p, {[CONST_SLOT_RIGHT] = piece(25410), [CONST_SLOT_ARMOR] = piece(25175)})
eq(S.stateOf(p).sets.bloodsworn.count, 1, "a helmet in the hand is not worn")
wear(p, {[CONST_SLOT_RIGHT] = false, [CONST_SLOT_ARMOR] = false})
-- the caps hold: a set's bleed chance on top of items' never goes above the modifier's cap
local rolled = newItem(2400)
rolled.custom.rarity = 5
rolled.custom.chaos_mod_bleedchance = 28
wear(p, {[CONST_SLOT_RIGHT] = rolled, [CONST_SLOT_LEFT] = piece(27658)})
eq(cache[p:getId()].bleedchance, M.byKey.bleedchance.cap, "items 28 + set 10 capped at 30")
wear(p, {[CONST_SLOT_RIGHT] = false, [CONST_SLOT_LEFT] = false})
-- level: a level 250 character wearing level 300 pieces gets nothing, at 300 it does (the 3 s check)
local low = newPlayer(250)
wear(low, {[CONST_SLOT_LEFT] = piece(27658)})
eq(cache[low:getId()].bleedchance, 0, "below the level")
low.level = 300
M.refresh(low)
eq(cache[low:getId()].bleedchance, 10, "the level reached: it counts")
-- percent health
local ash = newPlayer(800)
wear(ash, {[CONST_SLOT_HEAD] = piece(29560), [CONST_SLOT_ARMOR] = piece(29561)})
eq(cond(ash).params[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 104, "+4% health is the engine's 104")
eq(cache[ash:getId()].block, 5)
-- Cinderstorm's 6-piece Death Blast is a legendary power on the totals (item_powers.lua reads them)
local mage = newPlayer(400)
wear(mage, {[CONST_SLOT_LEFT] = piece(27666), [CONST_SLOT_HEAD] = piece(29471), [CONST_SLOT_ARMOR] = piece(7899),
	[CONST_SLOT_LEGS] = piece(7894), [CONST_SLOT_FEET] = piece(24637), [CONST_SLOT_RING] = piece(28041)})
eq(cache[mage:getId()].deathblast, 15, "Death Blast 15%")
eq(cache[mage:getId()].cdr, 6) eq(cache[mage:getId()].manacost, 8)
eq(cond(mage).params[CONDITION_PARAM_STAT_MAGICPOINTS], 2)

-- ---------------------------------------------------------------- the effects, with and without the set
local function fullSet(level, key, slots)
	local pl = newPlayer(level)
	local s = {}
	for slot, id in pairs(slots) do s[slot] = piece(id) end
	wear(pl, s)
	return pl
end
local bare = newPlayer(800) -- wears nothing

-- the hit event goes on the target only for a wearer
local reaver = fullSet(400, "bloodsworn", {[CONST_SLOT_LEFT] = 27658, [CONST_SLOT_HEAD] = 25410, [CONST_SLOT_ARMOR] = 25175,
	[CONST_SLOT_LEGS] = 28100, [CONST_SLOT_FEET] = 28101})
local m1 = monster(5000)
for _, cb in ipairs(callbacks.onTargetCombat) do cb(reaver, m1) end
eq(m1.registered.ChaosItemSetsDealt, true, "a wearer's target gets the event")
local m0 = monster(5000)
for _, cb in ipairs(callbacks.onTargetCombat) do cb(bare, m0) end
eq(m0.registered.ChaosItemSetsDealt, nil, "nobody else's")

-- Red Harvest: a critical hit opens a bleed; a plain hit or no set does not
reset()
local m2 = monster(5000)
dealt(m2, reaver, 400, ORIGIN_MELEE, true)
eq(#m2.conditions, 1, "a crit: a bleed") eq(m2.conditions[1].kind, CONDITION_BLEEDING)
eq(m2.conditions[1].params[CONDITION_PARAM_OWNER], reaver:getId(), "the wearer's bleed")
eq(m2.conditions[1].damage[3], -S.dotTick(400, M.config.ailment.share, M.config.ailment.rounds), "the ailment share")
local m3 = monster(5000)
dealt(m3, reaver, 400, ORIGIN_MELEE, false)
eq(#m3.conditions, 0, "no crit, no bleed")
dealt(m3, bare, 400, ORIGIN_MELEE, true)
eq(#m3.conditions, 0, "without the set a crit opens nothing")

-- Hemorrhage: a monster that dies bleeding from the wearer passes it on
reset()
local dying, n1, n2, n3, n4 = monster(300, 5000), monster(), monster(), monster(), monster()
nearby = {dying, n1, n2, n3, n4}
dealt(dying, reaver, 50, ORIGIN_CONDITION) -- a bleed tick marks it
dealt(dying, reaver, 280, ORIGIN_MELEE) -- the killing blow (recorded)
events.ChaosItemSetsKill.onKill(reaver, dying)
eq(#n1.conditions + #n2.conditions + #n3.conditions, 3, "three monsters bleed")
eq(#n4.conditions, 0, "no more than three")
eq(n1.conditions[1].damage[3], -S.dotTick(280, M.config.ailment.share, M.config.ailment.rounds), "sized by the last hit")
local d2, b1 = monster(300, 5000), monster()
nearby = {d2, b1}
dealt(d2, bare, 50, ORIGIN_CONDITION)
events.ChaosItemSetsKill.onKill(bare, d2)
eq(#b1.conditions, 0, "without the set: nothing spreads")
local d3, b2 = monster(300, 5000), monster()
nearby = {d3, b2}
events.ChaosItemSetsKill.onKill(reaver, d3)
eq(#b2.conditions, 0, "a monster that was not bleeding spreads nothing")

-- Hanging Verdict: ranged hits on a low monster deal 20% more
reset()
local marksman = fullSet(600, "gallows", {[CONST_SLOT_LEFT] = 27474, [CONST_SLOT_HEAD] = 29470, [CONST_SLOT_ARMOR] = 15407})
eq(S.stateOf(marksman).sets.gallows.count, 4, "crossbow twice + 2")
eq(cache[marksman:getId()].bossdamage, 8, "4-piece elite damage")
local lowMon, highMon = monster(300, 1000), monster(900, 1000)
eq(dealt(lowMon, marksman, 1000, ORIGIN_RANGED), -1200, "below 35%: +20%")
eq(dealt(highMon, marksman, 1000, ORIGIN_RANGED), -1000, "above: plain")
eq(dealt(lowMon, marksman, 1000, ORIGIN_MELEE), -1000, "melee: plain")
eq(dealt(lowMon, bare, 1000, ORIGIN_RANGED), -1000, "without the set: plain")

-- Umbral Recoil: a dodge empowers the next hit once, with a cooldown
reset()
local ninja = fullSet(300, "duskstalker", {[CONST_SLOT_LEFT] = 7404, [CONST_SLOT_RIGHT] = 7418, [CONST_SLOT_HEAD] = 28112,
	[CONST_SLOT_ARMOR] = 11301, [CONST_SLOT_LEGS] = 11304, [CONST_SLOT_FEET] = 27249})
eq(S.stateOf(ninja).sets.duskstalker.count, 6, "Fang and Sting are two pieces")
eq(cache[ninja:getId()].dodge, 4)
local foe = monster(100000)
M.onAvoid(ninja, foe, "dodge", 500)
local haste = ninja.conditions[#ninja.conditions]
eq(haste.kind, CONDITION_HASTE, "a dodge: haste")
eq(dealt(foe, ninja, 1000, ORIGIN_MELEE), -1400, "the next hit +40%")
eq(dealt(foe, ninja, 1000, ORIGIN_MELEE), -1000, "only the next one")
local nc = #ninja.conditions
M.onAvoid(ninja, foe, "dodge", 500)
eq(#ninja.conditions, nc, "cooldown: no second haste at once")
M.onAvoid(bare, foe, "dodge", 500)
eq(dealt(foe, bare, 1000, ORIGIN_MELEE), -1000, "without the set: nothing")

-- Pyre Bulwark: a dodged or blocked hit ignites the attacker (Embers, level 90 pieces)
reset()
local warden = fullSet(250, "embers", {[CONST_SLOT_HEAD] = 2496, [CONST_SLOT_ARMOR] = 8892, [CONST_SLOT_LEGS] = 27692,
	[CONST_SLOT_FEET] = 27647, [CONST_SLOT_LEFT] = 3975, [CONST_SLOT_RING] = 10314})
eq(S.stateOf(warden).sets.embers.count, 6, "all six Embers pieces")
eq(cache[warden:getId()].block, 4) eq(cache[warden:getId()].monsterreduction, 5)
eq(cond(warden).params[CONDITION_PARAM_STAT_MAGICPOINTS], 1, "the 2-piece magic level")
local brute = monster(5000)
M.onAvoid(warden, brute, "block", 600)
eq(brute.conditions[1].kind, CONDITION_FIRE, "ablaze")
eq(brute.conditions[1].damage[3], -S.dotTick(600, 40, 6), "40% of the hit over 6 s")
local brute2 = monster(5000)
M.onAvoid(bare, brute2, "block", 600)
eq(#brute2.conditions, 0, "without the set: nothing")
-- the 2-piece fire resistance on the hits the wearer takes
local hitBack = events.ChaosItemSetsTaken.onHealthChange(warden, brute, -1000, COMBAT_FIREDAMAGE, -500, COMBAT_PHYSICALDAMAGE,
	ORIGIN_MELEE)
eq(hitBack, -940, "fire -6%")
eq(select(3, events.ChaosItemSetsTaken.onHealthChange(warden, brute, -1000, COMBAT_FIREDAMAGE, -500, COMBAT_PHYSICALDAMAGE,
	ORIGIN_MELEE)), -500, "the physical part as it was")
eq(events.ChaosItemSetsTaken.onHealthChange(bare, brute, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE, ORIGIN_MELEE), -1000,
	"without the set: plain")

-- Ashen Oath: a block heals the party around the wearer
reset()
local tank = fullSet(800, "ashwarden", {[CONST_SLOT_HEAD] = 29560, [CONST_SLOT_ARMOR] = 29561, [CONST_SLOT_LEFT] = 29559,
	[CONST_SLOT_NECKLACE] = 27403})
local friend, far = newPlayer(800), newPlayer(800)
friend.health, far.health, tank.health = 500, 500, 500
far.pos = {x = 120, y = 100, z = 7}
local party = {getMembers = function() return {friend, far} end, getLeader = function() return tank end}
tank.party = party
M.onAvoid(tank, brute, "block", 100)
eq(friend.health, 520, "2% of 1000") eq(tank.health, 520, "the wearer too") eq(far.health, 500, "out of range")
M.onAvoid(tank, brute, "block", 100)
eq(friend.health, 520, "2 s cooldown")
M.onAvoid(tank, brute, "dodge", 100)
eq(friend.health, 520, "a dodge is no block")

-- Soul Siphon: damage over time heals the wearer (Lichbound, from the Descent)
reset()
local lich = fullSet(400, "lichbound", {[CONST_SLOT_HEAD] = 29573, [CONST_SLOT_ARMOR] = 8890, [CONST_SLOT_LEGS] = 29575,
	[CONST_SLOT_NECKLACE] = 28126})
lich.health = 500
dealt(monster(5000), lich, 1000, ORIGIN_CONDITION, false, COMBAT_EARTHDAMAGE)
eq(lich.health, 560, "6% of a 1000 tick")
dealt(monster(5000), lich, 1000, ORIGIN_MELEE)
eq(lich.health, 560, "only damage over time")
bare.health = 500
dealt(monster(5000), bare, 1000, ORIGIN_CONDITION)
eq(bare.health, 500, "without the set: nothing")
bare.health = 1000

-- Mirror Grace: heals on another player heal the healer
reset()
local healer = fullSet(400, "mirrorweave", {[CONST_SLOT_LEFT] = 28111, [CONST_SLOT_HEAD] = 28106, [CONST_SLOT_ARMOR] = 28107,
	[CONST_SLOT_LEGS] = 28108, [CONST_SLOT_FEET] = 28109, [CONST_SLOT_RING] = 28125})
eq(cache[healer:getId()].healing, 10, "6 + 4 healing done")
healer.health = 500
events.ChaosItemSetsTaken.onHealthChange(friend, healer, 400, COMBAT_HEALING, 0, COMBAT_HEALING, ORIGIN_SPELL)
eq(healer.health, 600, "25% of a 400 heal")
events.ChaosItemSetsTaken.onHealthChange(healer, healer, 400, COMBAT_HEALING, 0, COMBAT_HEALING, ORIGIN_SPELL)
eq(healer.health, 600, "not on itself")
bare.health = 500
events.ChaosItemSetsTaken.onHealthChange(friend, bare, 400, COMBAT_HEALING, 0, COMBAT_HEALING, ORIGIN_SPELL)
eq(bare.health, 500, "without the set: nothing")
bare.health = 1000

-- Pack Bond: summons hit harder; their kills heal the master
reset()
local tamer = fullSet(300, "hollowpack", {[CONST_SLOT_HEAD] = 24718, [CONST_SLOT_ARMOR] = 24741, [CONST_SLOT_NECKLACE] = 2129,
	[CONST_SLOT_RING] = 26808})
eq(cache[tamer:getId()].regen, 20)
local wolf = monster(1000, 1000, tamer)
local prey = monster(100, 5000)
eq(dealt(monster(5000), wolf, 1000, ORIGIN_MELEE), -1200, "the summon +20%")
eq(dealt(monster(5000), tamer, 1000, ORIGIN_MELEE), -1000, "the master's own hits: plain")
tamer.health = 500
dealt(prey, wolf, 200, ORIGIN_MELEE)
events.ChaosItemSetsKill.onKill(tamer, prey)
eq(tamer.health, 520, "the summon's kill heals 2%")
local stray = monster(1000, 1000, bare)
eq(dealt(monster(5000), stray, 1000, ORIGIN_MELEE), -1000, "without the set: plain")

-- Thorn Volley: a ranged hit splinters onto another monster, with a cooldown
reset()
local archer = fullSet(200, "thornwake", {[CONST_SLOT_LEFT] = 27646, [CONST_SLOT_ARMOR] = 2500, [CONST_SLOT_FEET] = 18406,
	[CONST_SLOT_RING] = 28691})
eq(S.stateOf(archer).sets.thornwake.count, 5, "bow twice + 3")
eq(cache[archer:getId()].movespeed, 4)
local mark, other = monster(5000), monster(5000)
nearby = {mark, other}
dealt(mark, archer, 1000, ORIGIN_RANGED)
eq(#hits, 1, "one splinter") eq(hits[1].to, other:getId(), "on the other monster") eq(hits[1].amount, 300, "30%")
dealt(mark, archer, 1000, ORIGIN_RANGED)
eq(#hits, 1, "1.5 s cooldown")
dealt(mark, bare, 1000, ORIGIN_RANGED)
eq(#hits, 1, "without the set: nothing")

-- ---------------------------------------------------------------- tooltip, look text
local tip = S.tooltip("bloodsworn", S.stateOf(reaver))
eq(tip.name, "Bloodsworn Reaver") eq(tip.have, 6) eq(tip.total, 6)
eq(tip.pieces[1].n, "Bloodsworn Greataxe") eq(tip.pieces[1].eq, true) eq(tip.pieces[1].h, 2, "two-handed")
eq(tip.bonuses[3].on, true)
local partial = S.tooltip("bloodsworn", S.count({{id = 25410, set = "bloodsworn"}, {id = 25175, set = "bloodsworn"}}, 400))
eq(partial.have, 2) eq(partial.pieces[2].eq, true) eq(partial.pieces[1].eq, nil, "the axe not worn")
eq(partial.bonuses[1].on, true) eq(partial.bonuses[2].on, nil) eq(partial.bonuses[3].on, nil)
eq(partial.bonuses[1].t, "Chance to Bleed +10%, Damage over Time +15%")
local lowTip = S.tooltip("bloodsworn", S.count({{id = 25410, set = "bloodsworn"}}, 200))
eq(lowTip.pieces[2].low, true, "worn below its level")
local lines = S.lookLines("bloodsworn", S.count({{id = 25410, set = "bloodsworn"}, {id = 25175, set = "bloodsworn"}}, 400))
eq(lines[1], "Set: Bloodsworn Reaver (2/6).")
eq(lines[2], "(2) Chance to Bleed +10%, Damage over Time +15% [active]")
ok(lines[3]:find("Hemorrhage", 1, true) and not lines[3]:find("active", 1, true), "the 4-piece line not active")
local looked = callbacks.onLook[#callbacks.onLook](reaver, piece(25410), nil, 1, "You see a helmet.")
ok(looked:find("Set: Bloodsworn Reaver (6/6).", 1, true), "the look text names the set")
eq(callbacks.onLook[#callbacks.onLook](reaver, newItem(25410), nil, 1, "You see a helmet."), "You see a helmet.",
	"a stock copy: nothing")
-- through the rich tooltip (item_tooltip_core.lua)
dofile("data/lib/chaos_crafting.lua")
dofile("data/scripts/chaos/item_tooltip_core.lua")
local tt = ChaosItemTooltip.build(piece(25410), {setState = S.stateOf(reaver)})
eq(tt.unique.set.name, "Bloodsworn Reaver") eq(tt.unique.set.have, 6)
tt = ChaosItemTooltip.build(piece(25410), {equippedIds = {[25175] = true, [27658] = true}})
eq(tt.unique.set.have, 3, "from the equipped ids: hauberk + greataxe (twice)")
eq(ChaosItemTooltip.build(newItem(25410), {}).unique, nil, "a stock copy is no unique")

-- the Character Info page's "sets" command
eq(S.summaryLines(S.stateOf(reaver))[1], "Bloodsworn Reaver: 6/6, bonuses (2) (4) (6) active", "the summary line")
eq(S.summaryLines(S.count({}, 1))[1], "No item set pieces worn.")
eq(S.summaryLines(S.count({{id = 25410, set = "bloodsworn"}}, 10))[1], "Bloodsworn Reaver: 0/6, no bonus yet (1 worn below their level)")
messages = {}
ChaosCommands.handlers.sets(reaver, "")
eq(messages[1], "Item sets: Bloodsworn Reaver: 6/6, bonuses (2) (4) (6) active", "the command answers")

-- ---------------------------------------------------------------- chase drops
local seq
local function scripted(list)
	local i = 0
	return function(a, b)
		i = i + 1
		local v = list[i] or a
		return math.max(a, math.min(b, v))
	end
end
local abyss = S.byKey.duskstalker
eq(S.chaseChance(abyss, "rift", "Abyssal Rift", {tier = 3}), 0, "below the set's tier")
eq(S.chaseChance(abyss, "rift", "Abyssal Rift", {tier = 4}), 250)
eq(S.chaseChance(abyss, "rift", "Abyssal Rift", {tier = 15}), 525, "+25 per tier")
eq(S.chaseChance(abyss, "rift", "Obsidian Hall", {tier = 9}), 0, "another theme")
eq(S.chaseChance(abyss, "rift", "Abyssal Rift", {tier = 9, level = 240}), 0, "a character far below the set's level")
eq(S.chaseChance(S.byKey.ashwarden, "raid", "ulthar", {}), 200)
eq(S.chaseChance(S.byKey.ashwarden, "raid", "sovereign", {final = true}), 500)
eq(S.chaseChance(S.byKey.ashwarden, "raid", "morwen", {}), 0, "not this boss")
eq(S.chaseChance(S.byKey.lichbound, "descent", nil, {depth = 7}), 0)
eq(S.chaseChance(S.byKey.lichbound, "descent", nil, {depth = 10, cleared = true}), 1000)
eq(S.chaseChance(S.byKey.thornwake, "dungeon", nil, {difficulty = 2}), 250)
eq(S.chaseChance(S.byKey.lichbound, "dungeon", nil, {difficulty = 2}), 0, "not a dungeon set")
-- Abyssal Rift tier 6: Cinderstorm (t6) and Duskstalker (t3) roll; the second hits, then piece 2 of it
local hit = S.rollChase("rift", "Abyssal Rift", {tier = 6, level = 400}, scripted({10000, 1, 1, 2}))
eq(hit.set.key, "duskstalker") eq(hit.piece.name, "Duskstalker Sting")
eq(S.rollChase("rift", "Abyssal Rift", {tier = 6, level = 400}, scripted({10000, 10000})), nil, "both miss")
-- the item: a real piece in the backpack, announced
reset()
local finder = newPlayer(800)
eq(S.grantChase(finder, "raid", "sovereign", {final = true, itemFind = 1}, scripted({1, 1, 3})), "Ashwarden Bulwark")
local got = finder.backpack[1]
eq(got.id, 29559) eq(got.custom.chaos_set, "ashwarden") eq(got.custom.chaos_unique, 1)
eq(got.attrs[ITEM_ATTRIBUTE_NAME], "Ashwarden Bulwark")
ok(messages[1]:find("Oath of the Ashen Warden", 1, true), "the finder is told the set") eq(#broadcasts, 1)
eq(S.grantChase(finder, "raid", "sovereign", {final = true, itemFind = 1}, scripted({10000})), nil, "a miss gives nothing")
-- bad-luck protection (conquest.lua, group "set"): x3 turns a roll of twice the chance into a hit; misses and hits recorded
do
	local recs = {}
	ChaosConquest = {pityMult = function() return 3 end,
		pityRecord = function(_, g, hit, id) recs[#recs + 1] = {g = g, hit = hit, id = id} end}
	local c = S.chaseChance(S.byKey.ashwarden, "raid", "sovereign", {final = true, level = 800})
	eq(S.grantChase(finder, "raid", "sovereign", {final = true, itemFind = 1}, scripted({c * 2, 1, 3})), "Ashwarden Bulwark",
		"pity x3 turns the roll into a drop")
	eq(recs[1].g, "set") eq(recs[1].hit, true) eq(recs[1].id, 29559)
	ChaosConquest.pityMult = function() return 1 end
	eq(S.grantChase(finder, "raid", "sovereign", {final = true, itemFind = 1}, scripted({c * 2})), nil, "without pity a miss")
	eq(recs[2].hit, false, "the miss is recorded")
	local n = #recs
	S.grantChase(finder, "raid", "morwen", {itemFind = 1}, scripted({1}))
	eq(#recs, n, "a source without a set roll records nothing")
	ChaosConquest = nil
end

-- ---------------------------------------------------------------- salvage and transmog
local SC = dofile("data/scripts/chaos/salvage_core.lua")
local scfg = dofile("data/scripts/chaos/salvage_config.lua")
local info = {gear = true, unique = true, setPiece = true, rarity = 0, level = 0, inBackpack = true}
eq(SC.check(info, scfg), nil, "a set piece may be salvaged")
eq(SC.shards(info, scfg), scfg.setPieceShards)
eq(SC.check({gear = true, unique = true, rarity = 0, inBackpack = true}, scfg), "unique", "other uniques still not")
local batch = SC.batch({info}, 15, scfg)
eq(batch.count, 0, "salvage all never takes a set piece")
-- a transmogged piece (transmog.lua: the look is a custom attribute) still counts
local styled = piece(29470)
styled.custom.chaos_tmog = 2493
eq(S.pieceOf(styled).key, "gallows", "the look does not change the piece")

-- ---------------------------------------------------------------- the open sets of pair 28 (switch forced on)
-- data/lib/chaos_gear_sets.lua: plain items counted by base id, bonuses at 2 / 4 / 6, PvP share of the resistances,
-- equip / unequip / swap / re-equip / level / logout / login / death / reload, the tooltip and look text
local G = dofile("data/lib/chaos_gear_sets.lua")
eq(G.PAIR28, true, "pair 28 switch on as shipped")
G.PAIR28 = false
S.load()
eq(S.byKey.bloodmoon, nil, "off: no open set")
ChaosGearSets = G
G.PAIR28 = true
S.load()
local open = 0
for _, set in ipairs(S.sets) do
	if set.open then
		open = open + 1
		eq(set.total, 6, set.key .. ": six pieces reach the last bonus")
		eq(#set.bonuses, 3, set.key .. ": tiers 2, 4, 6")
		eq(#set.pieces, 64, set.key .. ": every piece of the set counts")
		for i, b in ipairs(set.bonuses) do
			eq(b.n, 2 * i, set.key .. ": thresholds")
			for k, v in pairs(b.stats) do
				ok(S.COND[k] or S.RES[k] or M.byKey[k], set.key .. ": a known stat " .. k)
				local def = M.byKey[k]
				ok(not def or not def.cap or v * 2 <= def.cap, set.key .. ": " .. k .. " well under its cap")
			end
		end
	end
end
eq(open, 7, "seven open sets")
-- the engine's view of the pieces used below
local SLOTP = {helmet = SLOTP_HEAD, armor = SLOTP_ARMOR, legs = SLOTP_LEGS, boots = SLOTP_FEET, amulet = SLOTP_NECKLACE,
	ring = SLOTP_RING, shield = 48}
local function gearPiece(set, kind, fit)
	for _, p in ipairs(G.items.pieces) do
		if p.set == set and p.kind == kind and (fit == nil or p.fit == fit) then
			TYPES[p.id] = {name = p.name, slot = SLOTP[kind] or (48 + (p.fit == "2" and SLOTP_TWO_HAND or 0)),
				weaponType = SLOTP[kind] == nil and WEAPON_SWORD or (kind == "shield" and WEAPON_SHIELD or nil)}
			return newItem(p.id), p
		end
	end
end
local bm = {}
for _, k in ipairs({{"helmet", "H"}, {"armor", "H"}, {"legs", "H"}, {"boots"}, {"amulet"}, {"ring"}, {"shield"},
		{"sword", "1"}, {"sword", "2"}}) do
	bm[k[1] .. (k[2] or "")] = gearPiece("bloodmoon", k[1], k[2])
end
local knight = newPlayer(700)
local life = function() return cache[knight:getId()].lifeonhit or 0 end
wear(knight, {[CONST_SLOT_HEAD] = bm.helmetH})
eq(S.stateOf(knight).sets.bloodmoon.count, 1, "one plain piece counts by its base id")
eq(life(), 0, "one piece: nothing")
wear(knight, {[CONST_SLOT_ARMOR] = bm.armorH})
eq(life(), 8, "two pieces: tier 1")
wear(knight, {[CONST_SLOT_LEGS] = bm.legsH, [CONST_SLOT_FEET] = bm.boots})
eq(cache[knight:getId()].lifeonkill, 40, "four pieces: tier 2")
wear(knight, {[CONST_SLOT_NECKLACE] = bm.amulet, [CONST_SLOT_RING] = bm.ring})
eq(life(), 16, "six pieces: tier 3 adds to tier 1")
eq(cache[knight:getId()].regen, 10)
M.refresh(knight) M.refresh(knight)
eq(life(), 16, "refreshing again stacks nothing")
-- the same piece twice (two copies of one blade, one in each hand) counts once; weapons and shields count
local blade = bm.sword1
local twin = newItem(blade:getId())
wear(knight, {[CONST_SLOT_NECKLACE] = false, [CONST_SLOT_RING] = false, [CONST_SLOT_RIGHT] = blade, [CONST_SLOT_LEFT] = twin})
eq(S.stateOf(knight).sets.bloodmoon.count, 5, "a duplicate in the hands counts once")
wear(knight, {[CONST_SLOT_LEFT] = bm.shield})
eq(S.stateOf(knight).sets.bloodmoon.count, 6, "a shield counts")
-- swap: a two-handed blade for blade and shield counts two
wear(knight, {[CONST_SLOT_LEFT] = false, [CONST_SLOT_RIGHT] = bm.sword2})
eq(S.stateOf(knight).sets.bloodmoon.count, 6, "a two-handed piece counts two")
wear(knight, {[CONST_SLOT_RIGHT] = false, [CONST_SLOT_FEET] = false})
eq(life(), 8, "unequip: back to tier 1")
eq(cache[knight:getId()].lifeonkill or 0, 0, "tier 2 gone")
-- below a piece's level it does not count
local low = newPlayer(1)
wear(low, {[CONST_SLOT_HEAD] = gearPiece("bloodmoon", "helmet", "H"), [CONST_SLOT_ARMOR] = gearPiece("bloodmoon", "armor", "H")})
eq(S.stateOf(low).sets.bloodmoon.count, 0, "below the pieces' level: nothing")
-- the condition (Wyrmscale 4: maximum health +3%) and the resistances (2: fire 5%, players half)
local wy = newPlayer(700)
local wyItems = {}
for i, k in ipairs({{"helmet", "H"}, {"armor", "H"}, {"legs", "H"}, {"amulet"}}) do
	wyItems[i] = gearPiece("wyrmscale", k[1], k[2])
end
wear(wy, {[CONST_SLOT_HEAD] = wyItems[1], [CONST_SLOT_ARMOR] = wyItems[2], [CONST_SLOT_LEGS] = wyItems[3],
	[CONST_SLOT_NECKLACE] = wyItems[4]})
eq(cond(wy).params[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT], 103, "four pieces: maximum health +3%")
local function nConds(p)
	local n = 0
	for _, c in ipairs(p.conditions) do
		if c.kind == CONDITION_ATTRIBUTES and c.params[CONDITION_PARAM_SUBID] == S.config.conditionSubId then n = n + 1 end
	end
	return n
end
wear(wy, {[CONST_SLOT_NECKLACE] = false}) wear(wy, {[CONST_SLOT_NECKLACE] = wyItems[4]})
eq(nConds(wy), 1, "re-equip: one condition")
local drake = monster(5000)
eq(events.ChaosItemSetsTaken.onHealthChange(wy, drake, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE, ORIGIN_MELEE), -950,
	"fire -5% from a monster")
local foe = newPlayer(700)
eq(events.ChaosItemSetsTaken.onHealthChange(wy, foe, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE, ORIGIN_MELEE), -980,
	"from a player: half of it (2%)")
eq(events.ChaosItemSetsTaken.onHealthChange(wy, monster(100, 100, foe), -1000, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE,
	ORIGIN_MELEE), -980, "from a player's summon: half")
-- logout, login, death, reload
events.ChaosItemSetsLogout.onLogout(wy)
eq(ChaosItemSetsCache[wy:getId()], nil, "logout: nothing kept")
wy.conditions = {} -- the engine drops the endless condition; a death does the same without a logout event
events.ChaosItemSetsLogin.onLogin(wy)
eq(nConds(wy), 1, "login: the condition again")
wy.conditions = {}
events.ChaosItemSetsLogin.onLogin(wy) -- a death: the cache was still there
eq(nConds(wy), 1, "after a death: the condition again")
dofile("data/scripts/chaos/itemsets.lua") -- /reload
M.refresh(wy)
eq(nConds(wy), 1, "reload: still one condition")
eq(events.ChaosItemSetsTaken.onHealthChange(wy, drake, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE, ORIGIN_MELEE), -950,
	"reload: the resistance holds")
wear(wy, {[CONST_SLOT_HEAD] = false, [CONST_SLOT_ARMOR] = false, [CONST_SLOT_LEGS] = false, [CONST_SLOT_NECKLACE] = false})
eq(nConds(wy), 0, "all off: no condition")
eq(events.ChaosItemSetsTaken.onHealthChange(wy, drake, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_FIREDAMAGE, ORIGIN_MELEE), -1000,
	"all off: no resistance")
-- tooltip and look text: the active tier, only the worn pieces listed
local st = S.count({{id = wyItems[1]:getId(), set = "wyrmscale"}, {id = wyItems[2]:getId(), set = "wyrmscale"},
	{id = wyItems[3]:getId(), set = "wyrmscale"}, {id = wyItems[4]:getId(), set = "wyrmscale"}}, 1000)
local tip = S.tooltip("wyrmscale", st)
eq(tip.have .. "/" .. tip.total .. " " .. tip.tier .. "/" .. tip.tiers, "4/6 2/3", "tooltip counts and tier")
eq(#tip.pieces, 4, "only the worn pieces listed")
eq(S.lookLines("wyrmscale", st)[1], "Set: Wyrmscale (4/6), tier 2 of 3.", "look text header")
eq(S.lookLines("wyrmscale", st)[3], "(4) Maximum Health +3% [active]", "look text: an active bonus")
eq(S.tooltip("embers", st).tier, nil, "the old sets keep their block")
-- back off: the plain items are no pieces any more
G.PAIR28 = false
S.load()
eq(S.pieceOf(wyItems[1]), nil, "off: no piece")
ChaosGearSets = nil

print(string.format("itemsets_test: %d checks passed", checks))
