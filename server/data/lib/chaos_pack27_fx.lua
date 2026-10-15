-- Pack farming spell effects (pair 27 trial): the nine pack farming spells get effects and missiles of their own
-- instead of the ones they borrow from other spells. Effects only: no damage, area, timing or target changes.
-- The art: client/tools/sprites/gen_pack27_fx.py (art_import/pack27_fx.csv), appended to things_custom26 (effects
-- 674-687, missiles 154-157 of a local trial pair) by import_fx_art.py, which wrote the ids to
-- data/lib/chaos_pack27_fx_ids.lua.
--
-- Switch (C.PAIR27_FX): OFF. No published pair has these ids; a client on pair 26 would log "invalid effect id".
-- Off, nothing changes: the ids file is not loaded and every spell sends exactly what it sent before. On, during a
-- cast (the supports wrapper knows the spell, also in the cast's addEvent callbacks) an effect, missile or
-- directional effect name in C.spells for that spell is sent as the pair 27 one instead (ChaosSpell.fx / vfx / vfxDir /
-- shoot / vshoot in data/spells/chaos/_common.lua). A cosmetic skin, a large effect and a class signature effect win
-- over it, so the classes that already have their own (Blade Flurry of the Ninja and Samurai) keep it.
-- Lua 5.1 / LuaJIT / 5.3.

ChaosPack27Fx = ChaosPack27Fx or {}
local C = ChaosPack27Fx

C.PAIR27_FX = false

-- spell id -> kind -> {name the spell sends = the pair 27 name}; kinds: fx (an effect, also through vfx / vfxOr),
-- missile (ChaosSpell.shoot / vshoot), dir (the base name of a directional effect, VfxDir)
C.spells = {
	[194] = {fx = {aura_burst_gold = "palm_quake"}},                            -- Palm Shockwave
	[73] = {fx = {whirlwind = "flurry_petals"}},                                -- Blade Flurry
	[74] = {dir = {heavy_cleave = "iaido_dash"}},                               -- Iaido Sweep
	[195] = {fx = {void_eye = "ricochet_burst"}, missile = {shadow_bolt = "ricochet_bolt"}}, -- Shadow Ricochet
	[196] = {fx = {stone_rise = "chain_sparks"}, missile = {lightning_orb = "chain_disc"}},  -- Iron Chain
	[197] = {missile = {bone_spear = "shrapnel_shards"}},                       -- Bone Shrapnel
	[137] = {fx = {holy_seal = "sanctified_seal"}},                             -- Sanctified Ground
	[170] = {fx = {dome_blast_holy = "shieldwave_wall"}},                       -- Shield Wave
	[136] = {missile = {razor_disc = "fan_knife"}},                             -- Fan of Knives
}

-- spell id -> the spell's name in spells_chaos.xml (checked by tests/pack27_fx_test.lua: an id that moves fails it)
C.names = {
	[194] = "Palm Shockwave", [73] = "Blade Flurry", [74] = "Iaido Sweep", [195] = "Shadow Ricochet",
	[196] = "Iron Chain", [197] = "Bone Shrapnel", [137] = "Sanctified Ground", [170] = "Shield Wave",
	[136] = "Fan of Knives",
}

-- the pair 27 name for a spell id, kind and name, or nil (pure: no switch, no ids)
function C.pick(spellId, kind, name)
	local s = spellId and C.spells[spellId]
	local k = s and s[kind]
	return k and type(name) == "string" and k[name] or nil
end

-- the switch on and the ids known (chaos_pack27_fx_ids.lua loaded once into ChaosVfx / ChaosVfxMissile)
function C.live()
	if not C.PAIR27_FX then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosVfx then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if not (ChaosVfx and ChaosVfx.palm_quake) then
			pcall(dofile, "data/lib/chaos_pack27_fx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and ChaosVfx.palm_quake ~= nil
	end
	return C.loaded
end

-- the pair 27 name for spell `spellId` sending `name` of `kind`, or nil (switch off, no swap, the id not known)
function C.swapFor(spellId, kind, name)
	if not C.live() then
		return nil
	end
	local alt = C.pick(spellId, kind, name)
	if not alt then
		return nil
	end
	if kind == "missile" then
		return ChaosVfxMissile and ChaosVfxMissile[alt] and alt or nil
	end
	if kind == "dir" then
		return ChaosVfx and ChaosVfx[alt .. "_s"] and alt or nil
	end
	return ChaosVfx and ChaosVfx[alt] and alt or nil
end
