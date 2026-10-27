-- vigils_core.lua: the pure rules of the vigils (ChaosVigilsCore): which vigils are on, what they reserve, whom they
-- cover and what they do. No engine calls, so server/tests/vigils_test.lua covers every rule. Numbers:
-- vigils_config.lua. Engine glue: vigils.lua (scripts) and the toggle spells (data/spells/chaos/shared/vigil_*.lua).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- mods = what a player has for the vigils: {keystone = bool (Covenant of Vigils), tithe = bool (Iron Tithe),
-- choirmaster = bool, oathkeeper = bool (the uniques), multiClient = bool}

ChaosVigilsConfig = ChaosVigilsConfig or dofile("data/scripts/chaos/vigils_config.lua")

ChaosVigilsCore = ChaosVigilsCore or {}
local V = ChaosVigilsCore
V.cfg = ChaosVigilsConfig
local function cfg()
	return V.cfg
end

V.byKey, V.bySpell = {}, {}
for i, v in ipairs(ChaosVigilsConfig.list) do
	V.byKey[v.key] = {index = i, def = v}
	V.bySpell[v.spell] = v.key
end

-- the mods of a player from its archetype flags ({arVigils = true, ...}) and worn archetype uniques ({choirmaster = true}).
-- Iron Tithe has no effect next to Hollow Vessel (both would set the maximum health): the vigils then work as without it.
function V.modsOf(flags, uniques, multiClient)
	flags, uniques = flags or {}, uniques or {}
	return {keystone = flags.arVigils == true, tithe = flags.arIronTithe == true and not flags.arHollowVessel,
		choirmaster = uniques.choirmaster == true, oathkeeper = uniques.oathkeeper == true, multiClient = multiClient == true}
end

-- ------------------------------------------------------------------------------------------------ the mask
function V.has(mask, key)
	local e = V.byKey[key]
	mask = tonumber(mask) or 0
	return e ~= nil and mask > 0 and math.floor(mask / 2 ^ (e.index - 1)) % 2 == 1
end

function V.keys(mask)
	local out = {}
	for _, v in ipairs(cfg().list) do
		if V.has(mask, v.key) then
			out[#out + 1] = v.key
		end
	end
	return out
end

function V.with(mask, key, on)
	mask = math.max(0, tonumber(mask) or 0)
	local e = V.byKey[key]
	if not e then
		return mask
	end
	local bit = math.floor(2 ^ (e.index - 1))
	if on and not V.has(mask, key) then
		return mask + bit
	elseif not on and V.has(mask, key) then
		return mask - bit
	end
	return mask
end

-- ------------------------------------------------------------------------------------------------ reservation
-- the share of the maximum (mana, or health with Iron Tithe) one vigil reserves
function V.reserve(key, mods)
	local c = cfg()
	local e = V.byKey[key]
	if not e then
		return 0
	end
	mods = mods or {}
	local r = e.def.reserve
	if mods.keystone then
		r = r * c.keystone.reserve
	end
	if mods.choirmaster then
		r = r * c.uniques.choirmaster.reserve
	end
	if mods.oathkeeper then
		r = r * c.uniques.oathkeeper.reserve
	end
	if mods.tithe then
		r = r * c.tithe.healthShare
	end
	return r
end

function V.totalReserve(mask, mods)
	local sum = 0
	for _, key in ipairs(V.keys(mask)) do
		sum = sum + V.reserve(key, mods)
	end
	return sum
end

-- switch a vigil: returns the new mask, the total share reserved after it and nil, or the old mask, the total and
-- "full" when it would reserve more than maxReserve
function V.toggle(mask, key, mods)
	if V.has(mask, key) then
		local m = V.with(mask, key, false)
		return m, V.totalReserve(m, mods), nil
	end
	local m = V.with(mask, key, true)
	local total = V.totalReserve(m, mods)
	if total > cfg().maxReserve + 1e-9 then
		return mask, V.totalReserve(mask, mods), "full"
	end
	return m, total, nil
end

-- the flat amount reserved of a maximum (the unreserved maximum: what the player would have without the vigils)
function V.reserved(maximum, share)
	return math.max(0, math.floor((maximum or 0) * math.min(share or 0, cfg().maxReserve) + 1e-9))
end

-- the vigils that do not fit any more (the reservation grew past maxReserve, e.g. a unique taken off): switched off
-- from the last in bit order. Returns the mask that fits.
function V.fit(mask, mods)
	local keys = V.keys(mask)
	local m = mask
	for i = #keys, 1, -1 do
		if V.totalReserve(m, mods) <= cfg().maxReserve + 1e-9 then
			break
		end
		m = V.with(m, keys[i], false)
	end
	return m
end

-- ------------------------------------------------------------------------------------------------ coverage
function V.radius(mods)
	local c = cfg()
	mods = mods or {}
	return c.radius + (mods.keystone and c.keystone.radius or 0) + (mods.oathkeeper and c.uniques.oathkeeper.radius or 0)
end

-- the strength of one vigil of a holder on a member (self = the holder itself)
function V.effect(key, mods, self)
	local c = cfg()
	local e = V.byKey[key]
	if not e then
		return 0
	end
	local d = e.def
	local value = d.damage or d.taken or d.speed or d.manaShare or 0
	mods = mods or {}
	if mods.tithe then
		return self and value * c.tithe.self or 0
	end
	if not self and mods.keystone then
		value = value * (1 + c.keystone.party)
	end
	return value
end

local function distance(a, b)
	if not a or not b or a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end
V.distance = distance

-- who is covered by what. holders = {{id, pos, party (any value shared by a party, nil alone), mask, mods}};
-- players = {{id, pos, party, dead}}. Returns covered[playerId] = {wrath, iron, haste, clarity} (the strongest of each).
function V.coverage(holders, players)
	local covered = {}
	for _, h in ipairs(holders or {}) do
		local keys = V.keys(h.mask)
		if #keys > 0 then
			local alone = h.mods and (h.mods.tithe or h.mods.multiClient)
			local r = V.radius(h.mods)
			for _, p in ipairs(players or {}) do
				local self = p.id == h.id
				local member = self or (not alone and h.party ~= nil and p.party == h.party and not p.dead
					and distance(p.pos, h.pos) <= r)
				if member then
					local entry = covered[p.id] or {}
					covered[p.id] = entry
					for _, key in ipairs(keys) do
						local v = V.effect(key, h.mods, self)
						if v > (entry[key] or 0) then
							entry[key] = v
						end
					end
				end
			end
		end
	end
	return covered
end

-- ------------------------------------------------------------------------------------------------ effects
-- the damage multiplier of a covered attacker's hit; inspire = the Inspiring Illusion bonus that hit gets (0 or 0.08)
function V.dealtFactor(entry, inspire)
	local w = entry and entry.wrath or 0
	if w <= 0 then
		return 1
	end
	inspire = inspire or 0
	return (1 + math.max(w, inspire)) / (1 + inspire)
end

-- the damage-taken multiplier of a covered player; templar = the Templar defence aura's reduction it is under (0 ..)
function V.takenFactor(entry, templar)
	local i = entry and entry.iron or 0
	if i <= 0 then
		return 1
	end
	templar = math.max(0, math.min(0.95, templar or 0))
	return (1 - math.max(i, templar)) / (1 - templar)
end

-- the mana a covered member gets each second from Clarity (0 under Parched Veins)
function V.clarityMana(entry, maxMana, parched)
	if parched or not entry or not entry.clarity then
		return 0
	end
	return math.floor((maxMana or 0) * entry.clarity)
end

-- the haste of a covered member, as the condition's percent of the base speed (0 = none)
function V.haste(entry)
	return entry and entry.haste or 0
end

-- ------------------------------------------------------------------------------------------------ the buff bar
-- One row of the buff bar (data/lib/chaos_buffs.lua, source "vigils"). key: a vigil's key, or "tithe" (Iron Tithe's
-- health reservation). entry: what covers the player now (V.coverage, nil: nothing); mask / mods: the player's own
-- vigils and mods (nil: it holds none); parched: its rift run has Parched Veins. Returns {name, desc, stacks} or nil;
-- stacks = the effect (or the health reserved) in whole percent. No timer: a vigil lasts while it is on and in range.
local EFFECT_TEXT = {
	wrath = "+%s%% damage dealt",
	iron = "-%s%% damage taken",
	haste = "+%s%% speed",
	clarity = "%s%% of your maximum mana back every second",
}

-- the text in `lang` (ChaosI18n when it is loaded, English otherwise)
local function TT(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local function wholePct(share)
	return math.floor((share or 0) * 100 + 0.5)
end

-- a share as a percent with at most one decimal ("5", "7.5")
local function pctText(share)
	local tenths = math.floor((share or 0) * 1000 + 0.5)
	if tenths % 10 == 0 then
		return string.format("%d", math.floor(tenths / 10))
	end
	return string.format("%d.%d", math.floor(tenths / 10), tenths % 10)
end
V.pctText = pctText

function V.buffItem(key, entry, mask, mods, parched, lang)
	mods = mods or {}
	if key == "tithe" then
		if not mods.tithe or not mask or mask <= 0 then
			return nil
		end
		local reserved = wholePct(math.min(V.totalReserve(mask, mods), cfg().maxReserve))
		return {name = "Iron Tithe", stacks = reserved, desc = TT(lang, "Your vigils reserve %d%% of your maximum health instead of mana. They cover you alone, %d%% stronger.",
			reserved, wholePct(cfg().tithe.self - 1))}
	end
	local e = V.byKey[key]
	local value = e and entry and entry[key] or 0
	if value <= 0 then
		return nil
	end
	local text = TT(lang, EFFECT_TEXT[key], pctText(value))
	if key == "clarity" and parched then
		text = text .. " " .. TT(lang, "(none under Parched Veins)")
	end
	local tail
	if mask and V.has(mask, key) then
		tail = TT(lang, "Your own: it reserves %d%% of your maximum %s.", wholePct(V.reserve(key, mods)),
			TT(lang, mods.tithe and "health" or "mana"))
	else
		tail = TT(lang, "From a party member's vigil.")
	end
	return {name = e.def.name, stacks = math.max(1, wholePct(value)), desc = text .. ". " .. tail}
end

-- the text of a toggle (the spell's message)
function V.toggleText(key, on, total, mods, lang)
	local e = V.byKey[key]
	local what = TT(lang, (mods and mods.tithe) and "health" or "mana")
	if not on then
		return TT(lang, "%s ends. Reserved: %d%% of your %s.", e.def.name, math.floor(total * 100 + 0.5), what)
	end
	return TT(lang, "%s: on. It reserves %d%% of your maximum %s; %d%% in all.", e.def.name,
		math.floor(V.reserve(key, mods) * 100 + 0.5), what, math.floor(total * 100 + 0.5))
end

return V
