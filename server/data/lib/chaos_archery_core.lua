-- Infinite arrows and quivers, the pure part (ChaosArchery): launcher bands, the attack and hit chance a launcher gets
-- in place of its ammunition, the old items that need the new attack, the quiver bases and their implicit modifiers,
-- when a quiver counts, the extra damage of the quiver modifiers, and the ammunition sweep with its gold refund.
-- Numbers: data/lib/chaos_archery_config.lua. Engine side: data/scripts/chaos/archery.lua (sweep, old items, the
-- Distance Fighting condition, the quiver's attack speed) and weapon_styles.lua (the hit). Install side:
-- server/tools/patch_base_archery.py. Tests: server/tests/archery_test.lua. Overview: server/README.md "Infinite
-- arrows and quivers". Lua 5.1 / LuaJIT and Lua 5.3 compatible; no engine call apart from reading ItemTypes.

ChaosArchery = ChaosArchery or {}
local A = ChaosArchery
A.config = A.config or dofile("data/lib/chaos_archery_config.lua")

local floor = math.floor

local function num(v)
	return tonumber(v) or 0
end

local function hasBit(value, b)
	return floor(num(value) / b) % 2 == 1
end

local function call(obj, method)
	if not obj then
		return nil
	end
	local ok, v = pcall(function() return obj[method](obj) end)
	return ok and v or nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- launchers
-- ---------------------------------------------------------------------------------------------------------------
-- the band row of a launcher kind at a required level: {from, attack, hit, missile}
function A.band(kind, level)
	local rows = A.config.bands[kind == "crossbow" and "crossbow" or "bow"]
	local best = rows[1]
	for _, r in ipairs(rows) do
		if num(level) >= r[1] then
			best = r
		end
	end
	return best
end

function A.addedAttack(kind, level)
	return A.band(kind, level)[2]
end

-- the launcher's attack without ammunition: its own + its band's ammunition
function A.newAttack(oldAttack, kind, level)
	return num(oldAttack) + A.addedAttack(kind, level)
end

-- the launcher's hit chance without ammunition: the band's + its own bonus, 1..100
function A.newHit(oldHit, kind, level)
	return math.max(1, math.min(100, A.band(kind, level)[3] + num(oldHit)))
end

-- the missile (items.xml shootType) of a launcher: its band's, or an elemental one by its name
function A.missile(kind, level, name)
	name = tostring(name or ""):lower()
	for _, m in ipairs(A.config.missileByName) do
		if name:find(m[1], 1, true) then
			return kind == "crossbow" and m[3] or m[2]
		end
	end
	return A.band(kind, level)[4]
end

-- a two-handed distance weapon (throwing weapons are one-handed)
function A.isLauncherType(it)
	if not it then
		return false
	end
	return num(call(it, "getWeaponType")) == num(WEAPON_DISTANCE or 5)
		and hasBit(call(it, "getSlotPosition"), SLOTP_TWO_HAND or 2048)
end

-- "bow" | "crossbow" and the band level of a launcher: the config's entry, else (with its ItemType) a bow of the type's
-- required level for any other two-handed distance weapon; nil when it is no launcher
function A.launcherOf(id, it)
	local e = A.config.launchers[num(id)]
	if e then
		return e[1], e[2]
	end
	if it and A.isLauncherType(it) then
		local name = tostring(call(it, "getName") or ""):lower()
		for _, w in ipairs(A.config.crossbowWords) do
			if name:find(w, 1, true) then
				return "crossbow", num(call(it, "getMinReqLevel"))
			end
		end
		return "bow", num(call(it, "getMinReqLevel"))
	end
	return nil
end

-- the launcher kind of an ItemType ("bow" | "crossbow"), nil for anything else
function A.kindOfType(it)
	if not A.isLauncherType(it) then
		return nil
	end
	return (A.launcherOf(call(it, "getId"), it))
end

-- an item made before the patch carries the attack it had with ammunition (a rarity roll or a unique writes the attack
-- as an item attribute). Such a value is below the new type attack, because the band adds more (25 at least) than any
-- rarity bonus (19 at most); it gets the band's attack added once. Returns the new value, or nil when the value is
-- already one of the new attack (or the launcher is not in the config).
function A.legacyAttack(attrValue, typeAttack, id, it)
	local kind, level = A.launcherOf(id, it)
	if not kind or attrValue == nil then
		return nil
	end
	attrValue = num(attrValue)
	if attrValue >= num(typeAttack) then
		return nil
	end
	return attrValue + A.addedAttack(kind, level)
end

-- the engine's damage formula of a weapon hit (weapons.cpp Weapons::getMaxWeaponDamage) and the average hit:
-- normal_random(min, max) is centred, min is a fifth of the level against monsters
function A.maxWeaponDamage(level, skill, attack, factor)
	local v = (floor(num(level) / 5)) + ((((num(skill) / 4) + 1) * (num(attack) / 3)) * 1.03) / (factor or 1)
	return floor(v + 0.5)
end

function A.averageHit(level, skill, attack, hitChance)
	local maxV = A.maxWeaponDamage(level, skill, attack)
	local minV = math.ceil(num(level) * 0.2)
	if maxV < minV then
		maxV = minV
	end
	return (minV + maxV) / 2 * math.min(100, math.max(0, num(hitChance))) / 100
end

-- ---------------------------------------------------------------------------------------------------------------
-- quivers
-- ---------------------------------------------------------------------------------------------------------------
function A.isQuiverId(id)
	return A.config.quivers[num(id)] ~= nil
end

-- a quiver as the item system sees it: a quiver id of the config that is no container and no stack (an unpatched
-- base server still has them as containers: they stay out of the item system there)
function A.isQuiverType(it)
	if not it or not A.isQuiverId(call(it, "getId")) then
		return false
	end
	if call(it, "isContainer") or call(it, "isStackable") then
		return false
	end
	return true
end

function A.quiverLevel(id)
	local q = A.config.quivers[num(id)]
	return q and q[1] or 0
end

-- the implicit modifiers of a quiver base: {key -> value} (a copy)
function A.implicits(id)
	local q = A.config.quivers[num(id)]
	local out = {}
	for k, v in pairs(q and q[2] or {}) do
		out[k] = v
	end
	return out
end

-- the implicits as ordered rows {key, value} (catalogue order, for texts)
function A.implicitRows(id, M)
	local imp, rows = A.implicits(id), {}
	for _, def in ipairs(M and M.config.mods or {}) do
		if imp[def.key] then
			rows[#rows + 1] = {key = def.key, value = imp[def.key], def = def}
		end
	end
	return rows
end

-- a quiver counts only while its wearer holds a launcher: handKind = A.kindOfType of the weapon in the hands
function A.quiverActive(handKind, quiverId)
	return handKind ~= nil and A.isQuiverId(quiverId)
end

-- add `extra` {key -> value} into `into` (nil makes a new table)
function A.merge(into, extra)
	into = into or {}
	for k, v in pairs(extra or {}) do
		into[k] = (into[k] or 0) + num(v)
	end
	return into
end

-- the quiver modifiers in the item catalogue: the new ones for quivers only, and quivers added to the shared ones.
-- chaos_item_mods.lua calls it every time it loads (idempotent: M.addMod keeps a key it has)
function A.registerMods(M)
	for _, def in ipairs(A.config.mods) do
		local d = {}
		for k, v in pairs(def) do
			d[k] = v
		end
		d.kinds = {quiver = true}
		M.addMod(d)
	end
	for _, key in ipairs(A.config.sharedMods) do
		local def = M.byKey[key]
		if def and def.kinds then
			def.kinds.quiver = true
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- the hit (weapon_styles.lua): elemental share, critical strike, extra projectile
-- ---------------------------------------------------------------------------------------------------------------
A.ELEMENTS = {
	{key = "arrowfire", combat = "COMBAT_FIREDAMAGE", missile = "CONST_ANI_FIRE", effect = "CONST_ME_HITBYFIRE"},
	{key = "arrowice", combat = "COMBAT_ICEDAMAGE", missile = "CONST_ANI_SHIVERARROW", effect = "CONST_ME_ICEATTACK"},
	{key = "arrowenergy", combat = "COMBAT_ENERGYDAMAGE", missile = "CONST_ANI_FLASHARROW", effect = "CONST_ME_ENERGYHIT"},
	{key = "arrowearth", combat = "COMBAT_EARTHDAMAGE", missile = "CONST_ANI_EARTHARROW", effect = "CONST_ME_HITBYPOISON"}
}

-- the element of a character's quiver totals: the strongest one (one element per shot), or nil
function A.elementOf(totals)
	local best
	for _, e in ipairs(A.ELEMENTS) do
		local v = num(totals and totals[e.key])
		if v > 0 and (not best or v > best.pct) then
			best = {key = e.key, pct = v, combat = e.combat, missile = e.missile, effect = e.effect}
		end
	end
	return best
end

-- the elemental part of a hit of `hit` points with `pct` percent against a resistance of `resist` percent (immune at
-- 100 and above, a weakness below 0 adds)
function A.elementDamage(hit, pct, resist)
	resist = num(resist)
	if resist >= 100 then
		return 0
	end
	return floor(math.abs(num(hit)) * num(pct) / 100 * (100 - resist) / 100 + 1e-9)
end

function A.critHit(value)
	local a = floor(math.abs(num(value)) * (100 + A.config.effects.critDamage) / 100 + 1e-9)
	return num(value) < 0 and -a or a
end

function A.extraHit(hit)
	return floor(math.abs(num(hit)) * A.config.effects.multishotShare / 100 + 1e-9)
end

-- the missile of a launcher's extra projectile: the element's, else arrow / bolt
function A.extraMissile(kind, element)
	if element and element.missile and _G[element.missile] then
		return _G[element.missile]
	end
	if kind == "crossbow" then
		return CONST_ANI_BOLT or 2
	end
	return CONST_ANI_ARROW or 3
end

-- ---------------------------------------------------------------------------------------------------------------
-- the ammunition sweep
-- ---------------------------------------------------------------------------------------------------------------
-- an arrow or bolt: in the config list, or any ammunition (weapon type ammo) of ammo type arrow or bolt
function A.isAmmoId(id, it)
	if A.config.ammo[num(id)] then
		return true
	end
	if not it then
		return false
	end
	if num(call(it, "getWeaponType")) ~= num(WEAPON_AMMO or 7) then
		return false
	end
	local t = num(call(it, "getAmmoType"))
	return t ~= 0 and (t == num(AMMO_ARROW or 2) or t == num(AMMO_BOLT or 1))
end

function A.refundOf(id, count)
	local per = A.config.ammo[num(id)] or A.config.defaultRefund
	return per * math.max(0, floor(num(count)))
end

-- what a sweep over `entries` ({id, count, it}) takes: the ammo entries and the gold for them
function A.plan(entries)
	local take, gold, pieces = {}, 0, 0
	for _, e in ipairs(entries or {}) do
		if A.isAmmoId(e.id, e.it) then
			take[#take + 1] = e
			gold = gold + A.refundOf(e.id, e.count)
			pieces = pieces + math.max(0, floor(num(e.count)))
		end
	end
	return take, gold, pieces
end

function A.refundText(pieces, gold)
	return string.format("Bows and crossbows need no ammunition any more: %d arrow%s and bolt%s left your belongings "
		.. "and %d gold went to your bank account.", pieces, pieces == 1 and "" or "s", pieces == 1 and "" or "s", gold)
end

return A
