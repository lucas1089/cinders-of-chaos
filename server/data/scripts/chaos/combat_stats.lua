-- combat_stats.lua: the combat stat rows of the client's Skills window (client game_skillstats; rules:
-- combat_stats_core.lua, numbers: combat_stats_config.lua; server/README.md "Combat stat rows of the Skills window").
--
-- Protocol (extended opcode ChaosOpcodes.combatStats = 119, JSON {action, data}):
--   client -> server  get                         the numbers again (at most one answer per getEveryMs)
--   server -> client  stats {damage?, attack?, defense, armor, mitigation}
--     damage      the average auto attack hit (display scale applied); absent for a wand, a rod, a fist
--     attack      the equipped weapon's attack; absent with no attack weapon
--     defense     Defence Value, whole number
--     armor       Armor Value, whole number
--     mitigation  share 0 .. 1 of a physical monster hit that never lands
-- Sent at login, after an equip change, a level or skill advance and a passive tree change (one message for a burst, and
-- only when a number changed). Assumed engine API (TFS 1.4 with the Chaos patches): Player:getSlotItem, getLevel,
-- getEffectiveSkillLevel, getStorageValue, ItemType getters, EventCallback onItemMoved, CreatureEvent login / advance /
-- logout / extendedopcode, addEvent. Lua 5.1 / LuaJIT and 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCombatStats or not ChaosCombatStats.build then
	dofile("data/scripts/chaos/combat_stats_core.lua")
end
ChaosCombatStatsConfig = dofile("data/scripts/chaos/combat_stats_config.lua")
for _, file in ipairs({"weapon_dps_core.lua"}) do
	if not ChaosWeaponDps then
		dofile("data/scripts/chaos/" .. file)
	end
end

local S = ChaosCombatStats
local OPCODE = ChaosOpcodes.combatStats or 119
local cfg = ChaosCombatStatsConfig

S.last = S.last or {}    -- player id -> signature of the last message
S.pending = S.pending or {} -- player id -> true while a message is waiting for its debounce
S.getState = S.getState or {} -- player id -> {at}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function g(name)
	return rawget(_G, name)
end

local function call(obj, method, ...)
	if not obj then
		return nil
	end
	local fn = obj[method]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, v = pcall(fn, obj, ...)
	if ok then
		return v
	end
	return nil
end

local function attrOr(item, attr, fallback)
	if attr and call(item, "hasAttribute", attr) then
		return tonumber(call(item, "getAttribute", attr)) or 0
	end
	return tonumber(fallback) or 0
end

-- the slots whose armour the engine adds (Player::getArmor)
local ARMOUR_SLOTS = {"CONST_SLOT_HEAD", "CONST_SLOT_NECKLACE", "CONST_SLOT_ARMOR", "CONST_SLOT_LEGS", "CONST_SLOT_FEET",
	"CONST_SLOT_RING", "CONST_SLOT_AMMO", "CONST_SLOT_DECK", "CONST_SLOT_BADGE", "CONST_SLOT_SHIP", "CONST_SLOT_BELT",
	"CONST_SLOT_GLOVES"}

-- items.xml weapon type -> the kinds of combat_stats_core.lua
local function weaponKind(wt)
	local map = {
		[g("WEAPON_SWORD") or 1] = "sword", [g("WEAPON_CLUB") or 2] = "club", [g("WEAPON_AXE") or 3] = "axe",
		[g("WEAPON_DISTANCE") or 5] = "distance", [g("WEAPON_SHIELD") or 4] = "shield", [g("WEAPON_WAND") or 6] = "wand"}
	return map[tonumber(wt) or -1]
end

-- the weapon and the shield in the hands (Player::getShieldAndWeapon)
local function hands(player)
	local weapon, shield
	for _, slot in ipairs({g("CONST_SLOT_RIGHT") or 5, g("CONST_SLOT_LEFT") or 6}) do
		local item = call(player, "getSlotItem", slot)
		local it = item and ItemType(item:getId())
		local kind = it and weaponKind(call(it, "getWeaponType"))
		if kind == "shield" then
			local def = attrOr(item, g("ITEM_ATTRIBUTE_DEFENSE"), call(it, "getDefense"))
			if not shield or def > shield.defense then
				shield = {defense = def}
			end
		elseif kind then
			local launcher = kind == "distance" and ChaosArchery and ChaosArchery.kindOfType and ChaosArchery.kindOfType(it) or nil
			local twoHanded = false
			if bit and bit.band then
				twoHanded = bit.band(tonumber(call(it, "getSlotPosition")) or 0, g("SLOTP_TWO_HAND") or 2048) ~= 0
			end
			weapon = {
				kind = kind, launcher = launcher, twoHanded = twoHanded,
				attack = attrOr(item, g("ITEM_ATTRIBUTE_ATTACK"), call(it, "getAttack")),
				defense = attrOr(item, g("ITEM_ATTRIBUTE_DEFENSE"), call(it, "getDefense")),
				extra = attrOr(item, g("ITEM_ATTRIBUTE_EXTRADEFENSE"), call(it, "getExtraDefense")),
				hitChance = attrOr(item, g("ITEM_ATTRIBUTE_HITCHANCE"), call(it, "getHitChance"))}
		end
	end
	return weapon, shield
end

-- armour of the worn pieces and their physical protection (the item type's, the stock rule)
local function wornArmour(player)
	local armour, protection = {}, {}
	for _, name in ipairs(ARMOUR_SLOTS) do
		local slot = g(name)
		local item = slot and call(player, "getSlotItem", slot)
		if item then
			local it = ItemType(item:getId())
			armour[#armour + 1] = attrOr(item, g("ITEM_ATTRIBUTE_ARMOR"), call(it, "getArmor"))
		end
	end
	for _, slot in ipairs({1, 2, 4, 5, 6, 7, 8, 9, 10, 13}) do
		local item = call(player, "getSlotItem", slot)
		local ab = item and call(ItemType(item:getId()), "getAbilities")
		if type(ab) == "table" and type(ab.absorbPercent) == "table" and (tonumber(ab.absorbPercent[1]) or 0) ~= 0 then
			protection[#protection + 1] = tonumber(ab.absorbPercent[1])
		end
	end
	return armour, protection
end

-- the physical protection really in effect: worn types and the two absorb storages (gear rolls and the tree), engine
-- patch 0049's arithmetic (ChaosItemMods.effectiveAbsorb)
local function physicalAbsorb(player, protection)
	local storage = 0
	for _, key in ipairs({977545, 977563}) do
		storage = storage + math.max(0, tonumber(call(player, "getStorageValue", key)) or 0)
	end
	if ChaosItemMods and ChaosItemMods.effectiveAbsorb then
		local ok, v = pcall(ChaosItemMods.effectiveAbsorb, protection, storage)
		if ok then
			return v
		end
	end
	return math.min(75, storage)
end

-- the factor the passive tree puts on a physical weapon hit (passivetree_effects.lua dealt.onHealthChange)
local function treeFactor(player, kind)
	local bonuses = ChaosPassiveCache and ChaosPassiveCache[player:getId()]
	if not bonuses or not ChaosPassiveDamagePercent then
		return 1
	end
	local ok, m = pcall(function()
		local phys = g("COMBAT_PHYSICALDAMAGE") or 1
		local origin = kind == "distance" and (g("ORIGIN_RANGED") or 2) or (g("ORIGIN_MELEE") or 1)
		local line = ChaosPassiveLineFactor and ChaosPassiveLineFactor(player) or 1
		return (1 + ChaosPassiveDamagePercent(bonuses, phys) / 100) * ChaosPassiveStatMultiplier(bonuses, phys, origin)
			* ChaosParagonDamageMultiplier(bonuses, phys) * line
	end)
	return ok and tonumber(m) or 1
end

local function armourSetting()
	local k, cap = cfg.armorPercentConstant, cfg.armorPercentMax
	local on = true
	if configManager and configKeys then
		if configKeys.ARMOR_PERCENT then
			on = configManager.getBoolean(configKeys.ARMOR_PERCENT)
		end
		if configKeys.ARMOR_PERCENT_CONSTANT then
			k = configManager.getNumber(configKeys.ARMOR_PERCENT_CONSTANT)
		end
		if configKeys.ARMOR_PERCENT_MAX then
			cap = configManager.getNumber(configKeys.ARMOR_PERCENT_MAX)
		end
	end
	if not on then
		return nil, cap
	end
	return k, cap
end

-- everything the core needs, read from the player
function S.gather(player)
	local level = tonumber(call(player, "getLevel")) or 1
	local function skill(id)
		return tonumber(id and call(player, "getEffectiveSkillLevel", id)) or 0
	end
	local best = 0
	for _, name in ipairs({"SKILL_SWORD", "SKILL_CLUB", "SKILL_AXE"}) do
		best = math.max(best, skill(g(name)))
	end
	local weapon, shield = hands(player)
	local armour, protection = wornArmour(player)
	local k, cap = armourSetting()
	local totals = ChaosItemMods and ChaosItemMods.playerBonus
	local scale = 1
	if ChaosDisplayScale and ChaosDisplayScale.factor then
		scale = ChaosDisplayScale.factor(level)
	end
	return {
		level = level, weapon = weapon, shield = shield, armourList = armour,
		skills = {melee = best, distance = skill(g("SKILL_DISTANCE")), shielding = skill(g("SKILL_SHIELD")),
			fist = skill(g("SKILL_FIST"))},
		k = k, cap = cap, absorb = physicalAbsorb(player, protection),
		monster = totals and totals(player, "monsterreduction") or 0,
		mult = weapon and treeFactor(player, weapon.kind) or 1, scale = scale}
end

function S.compute(player)
	return S.build(S.gather(player), cfg)
end

-- send the numbers now (force: even when they did not change)
function S.send(player, force)
	local ok, data = pcall(S.compute, player)
	if not ok then
		print("[combat_stats] " .. tostring(data))
		return false
	end
	local id = player:getId()
	local sig = S.signature(data)
	if not force and S.last[id] == sig then
		return false
	end
	S.last[id] = sig
	Chaos.send(player, OPCODE, "stats", data)
	return true
end

-- ask for a message in a moment: a burst of moves, advances and tree saves makes one
function S.schedule(player, delay)
	local id = player:getId()
	if S.pending[id] then
		return
	end
	S.pending[id] = true
	addEvent(function(pid)
		S.pending[pid] = nil
		local p = Player(pid)
		if p then
			S.send(p, false)
		end
	end, delay or cfg.debounceMs, id)
end

-- ---------------------------------------------------------------- hooks
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition)
	local inv = g("CONTAINER_POSITION") or 0xFFFF
	local fromSlot = fromPosition.x == inv and math.floor(fromPosition.y / 64) % 2 == 0
	local toSlot = toPosition.x == inv and math.floor(toPosition.y / 64) % 2 == 0
	if fromSlot or toSlot then
		S.schedule(player)
	end
end
moved:register(13) -- after item_mods.lua (11), so the modifiers are totalled

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.listeners = ChaosPassiveTree.listeners or {}
ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners + 1] = function(player)
	S.schedule(player)
end

local ext = CreatureEvent("ChaosCombatStatsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "get" then
		return
	end
	local state = S.getState[player:getId()] or {}
	S.getState[player:getId()] = state
	if S.dueGet(state, nowMs(), cfg.getEveryMs) then
		S.send(player, true)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosCombatStatsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCombatStatsExtended")
	player:registerEvent("ChaosCombatStatsAdvance")
	player:registerEvent("ChaosCombatStatsLogout")
	S.last[player:getId()] = nil
	S.schedule(player, cfg.loginDelayMs)
	return true
end
login:type("login")
login:register()

-- a level or a skill (shielding, melee, distance, fist) changes the numbers
local advance = CreatureEvent("ChaosCombatStatsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	S.schedule(player)
	return true
end
advance:type("advance")
advance:register()

local logout = CreatureEvent("ChaosCombatStatsLogout")
function logout.onLogout(player)
	local id = player:getId()
	S.last[id], S.pending[id], S.getState[id] = nil, nil, nil
	return true
end
logout:type("logout")
logout:register()
