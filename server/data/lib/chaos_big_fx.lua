-- Large soft spell effects (5x5 to 9x9 tiles): boss telegraph circles, boss hits, world boss and rift guardian moments
-- and the strongest area spells of each class line. Effects only: no damage, area, timing or target changes.
-- The art: client/tools/sprites/gen_big_fx.py (art_import/big_fx.csv), appended to things_custom24 (effects
-- 635-655) by import_fx_art.py --merge, which wrote the ids to data/lib/chaos_big_fx_ids.lua.
--
-- Switch (C.BIG_FX): on since 2026-10-13 (pair 24 at 407ad9b6, effects 635-655). Off, nothing changes: every call site sends exactly what it sent before. On:
--   * spells: during a cast (the supports wrapper knows the spell, also in the cast's addEvent callbacks) an effect
--     name in C.spells for that spell is sent as the big effect instead (ChaosSpell.vfx in
--     data/spells/chaos/_common.lua; a cosmetic spell skin the player chose wins, the big effect wins over the class
--     effect of chaos_class_fx.lua);
--   * uses: ChaosPackFx.send (data/lib/chaos_pack_fx.lua) sends the big effect of a use in C.uses first (world boss,
--     rift guardian), whether the pack switch is on or not;
--   * boss telegraphs (uber.lua, guildboss.lua, raid.lua): a round telegraph of 5x5, 7x7 or 9x9 tiles also gets the big
--     warning circle on its first mark, and in the Ascended and guild boss fights the hit gets the big effect of the
--     boss's element. The stock warning marks and hit effects stay: the big ones are drawn on top.
-- A name the pair does not have yet (no ids file) sends nothing big: the stock effect goes out as before.
-- Flip step: server/README.md "Large spell effects". Lua 5.1 / LuaJIT / 5.3.

ChaosBigFx = ChaosBigFx or {}
local C = ChaosBigFx

C.BIG_FX = true

-- the effects, in the spec's order (client art_import/big_fx.csv; checked by tests/big_fx_test.lua)
C.effects = {
	"big_telegraph_5", "big_telegraph_7", "big_telegraph_9",
	"big_shock_fire_7", "big_shock_frost_7", "big_shock_lightning_7", "big_shock_holy_5", "big_shock_blood_9",
	"big_nova_fire_9", "big_nova_frost_7", "big_nova_poison_7", "big_nova_holy_7", "big_nova_void_7",
	"big_nova_arcane_7", "big_pillar_holy_5", "big_pillar_arcane_5", "big_meteor_fire_7", "big_lightning_burst_7",
	"big_sanctum_holy_5", "big_rift_void_7", "big_geyser_blood_5",
}

-- spell id -> {effect name the spell sends at the centre of its area = the big effect}
C.spells = {
	-- Mystic line
	[206] = {dome_blast_fire = "big_nova_fire_9", storm_ring = "big_shock_lightning_7",
		fire_explosion = "big_shock_fire_7"},                            -- Doomtide (Elementalist), its three waves
	[213] = {earth_spikes = "big_nova_poison_7", frost_nova = "big_nova_frost_7"}, -- Primordial Squall, its waves
	[204] = {meteor_strike = "big_meteor_fire_7"},                         -- Falling Pyre: lands on the impact
	[202] = {lightning_hit = "big_lightning_burst_7"},                     -- Forked Storm, each jump
	[231] = {void_rift = "big_rift_void_7", arcane_circle = "big_nova_arcane_7"}, -- Tear in the Weave: the rift under
	                                                                       -- its pair 27 core, each implosion
	[230] = {shadow_smoke = "big_nova_void_7"},                            -- Nightburst: the eruption (void_maw, the
	                                                                       -- gather, stays the pack effect)
	-- Warrior line
	[225] = {earth_spikes = "big_shock_fire_7"},                           -- Colossus Fall
	-- Ranger line
	[216] = {holy_seal = "big_sanctum_holy_5"},                            -- Blessed Earth
	[218] = {holy_smite = "big_pillar_holy_5"},                            -- Final Verdict (Deadeye)
	-- Necromancer line
	[185] = {px633_indigo = "big_geyser_blood_5"},                         -- Corpse Explosion (Lich), each corpse
	[188] = {px633_indigo = "big_geyser_blood_5"},                         -- Bone Offering (Bone Lord)
	-- Monk line
	[65] = {whirlwind = "big_shock_holy_5"},                               -- Whirling Heel
	-- Templar line
	[199] = {dome_blast_holy = "big_nova_holy_7"},                         -- Purging Nova (Inquisitor)
	[190] = {holy_seal = "big_sanctum_holy_5"},                            -- Consecration
	[198] = {holy_smite = "big_pillar_holy_5"},                            -- Judgement (Inquisitor)
}

-- ChaosPackFx use -> big effect (sent before the pack / stock effect of that use)
C.uses = {
	wb_arrives = "big_rift_void_7",          -- a world boss arrives (worldboss.lua)
	wb_enrage = "big_shock_blood_9",         -- a world boss enrages
	rift_boss_arrives = "big_pillar_arcane_5", -- a rift guardian appears (rift.lua)
	rift_strike_death = "big_nova_void_7",   -- the Wrathful Guardian's nova lands (radius 3, rift.lua markedStrike)
}

-- the boss's element -> the big effect of a telegraphed hit (round telegraphs only)
C.hits = {
	fire = "big_shock_fire_7", energy = "big_lightning_burst_7", death = "big_nova_void_7",
	physical = "big_shock_blood_9", ice = "big_shock_frost_7", holy = "big_nova_holy_7", earth = "big_nova_poison_7",
}

-- in the pair, sent by nothing yet
C.unwired = {}

-- the big effect of a spell's effect name, or nil (pure: no switch, no ids)
function C.pick(spellId, name)
	local s = spellId and C.spells[spellId]
	return s and type(name) == "string" and s[name] or nil
end

-- the big effect of a use, or nil (pure)
function C.pickUse(use)
	return type(use) == "string" and C.uses[use] or nil
end

-- a telegraph's tiles -> the centre {x, y, z} and size (5, 7 or 9) when they make a round area: a square bounding box
-- of an odd side 5..9 that the tiles fill at least 45% of (a tile circle of radius 2..4 fills 52-60%), reaching the
-- middle of every side and holding the centre tile; nil for cones, lines, rings with a safe middle, marks round
-- several players, and anything bigger or smaller (pure)
function C.circleOf(tiles)
	if type(tiles) ~= "table" or #tiles == 0 then
		return nil
	end
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
	local z = tiles[1].z
	for _, t in ipairs(tiles) do
		if t.z ~= z then
			return nil
		end
		x1, y1 = math.min(x1, t.x), math.min(y1, t.y)
		x2, y2 = math.max(x2, t.x), math.max(y2, t.y)
	end
	local w, h = x2 - x1 + 1, y2 - y1 + 1
	if w ~= h or w % 2 ~= 1 or w < 5 or w > 9 then
		return nil
	end
	if #tiles < 0.45 * w * h then
		return nil
	end
	local cx, cy = math.floor((x1 + x2) / 2), math.floor((y1 + y2) / 2) -- integers in Lua 5.3 too
	local seen, edges = {}, 0
	for _, t in ipairs(tiles) do
		local k = t.x .. ":" .. t.y
		if seen[k] then
			return nil -- the same tile twice: not one area
		end
		seen[k] = true
		-- the four mid-edge tiles must be in it (a round shape reaches its box on every side)
		if (t.x == cx and (t.y == y1 or t.y == y2)) or (t.y == cy and (t.x == x1 or t.x == x2)) then
			edges = edges + 1
		end
	end
	if edges ~= 4 or not seen[cx .. ":" .. cy] then
		return nil -- not round, or a ring with a safe middle: no filled warning circle over it
	end
	return {x = cx, y = cy, z = z}, w
end

-- the switch on and the big effects known (chaos_big_fx_ids.lua loaded once into ChaosVfx)
function C.live()
	if not C.BIG_FX then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosVfx then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if not (ChaosVfx and ChaosVfx.big_telegraph_5) then
			pcall(dofile, "data/lib/chaos_big_fx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and ChaosVfx.big_telegraph_5 ~= nil and Vfx ~= nil
	end
	return C.loaded
end

local function known(name)
	return name and ChaosVfx and ChaosVfx[name] and name or nil
end

-- the big effect for spell `spellId` sending `name`, or nil (switch off, no swap, not in the pair)
function C.swapFor(spellId, name)
	if not C.live() then
		return nil
	end
	return known(C.pick(spellId, name))
end

-- send a big effect at its offset tile (Vfx centres it on pos); false when off or unknown
function C.send(pos, name)
	if not pos or not C.live() or not known(name) then
		return false
	end
	return Vfx(Position(pos.x, pos.y, pos.z), name) and true or false
end

-- the big effect of a use (ChaosPackFx.send calls this first); false when off, no use or not in the pair
function C.sendUse(pos, use)
	return C.send(pos, C.pickUse(use))
end

-- the warning circle over a round telegraph (on its first mark)
function C.telegraph(tiles)
	if not C.live() then
		return false
	end
	local centre, size = C.circleOf(tiles)
	return centre ~= nil and C.send(centre, "big_telegraph_" .. size)
end

-- the boss's hit over a round telegraph
function C.bossHit(tiles, element)
	if not C.live() then
		return false
	end
	local centre = C.circleOf(tiles)
	return centre ~= nil and C.send(centre, C.hits[element or "physical"])
end
