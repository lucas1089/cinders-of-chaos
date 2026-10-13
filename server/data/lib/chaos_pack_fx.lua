-- Pack effects for procs, snares, rift modifiers, world bosses and the reflect: which use sends which animated effect
-- instead of the stock one it sent before. Effects only: no damage, chance, timing or target changes.
-- Two kinds of names:
--   * full pack effects already in the pair since effects 429-558 (data/lib/chaos_vfx.lua, vfx_catalog.csv);
--   * short cuts of the same art set for things sent on every proc or tick (reflect_bubble, tick_*): strips from
--     client/tools/sprites/gen_pack_fx.py (art_import/pack_fx.csv), appended to the next pair by import_fx_art.py,
--     which writes their ids to data/lib/chaos_pack_fx_ids.lua (absent until that pair exists).
--
-- Switch (C.PACK_FX): off. Off, nothing changes: every call site sends exactly the stock effect it sent before. On,
-- a use sends its effect at its offset tile (Vfx); a name the server does not know yet (a cut before its pair, or no
-- chaos_vfx.lua) falls back to the stock effect. Flip step: server/README.md "Pack effects for procs and bosses".
-- Lua 5.1 / LuaJIT / 5.3.

ChaosPackFx = ChaosPackFx or {}
local C = ChaosPackFx

C.PACK_FX = false

-- use key -> effect name (ChaosVfx). Call sites: ChaosPackFx.send(pos, use, stockEffect).
C.uses = {
	-- combat feedback (combat_fx.lua): the reflect; crit and dodge keep crit_burst / dodge_whoosh
	reflect = "reflect_bubble",
	-- item powers (item_mods.lua): ailment procs and the execute
	item_shock = "lightning_hit",
	item_bleed = "tick_bleed",
	item_ignite = "tick_burn",
	item_poison = "tick_poison",
	item_chill = "tick_chill",
	item_execute = "shadow_eruption",
	-- snares (data/spells/chaos/_snares.lua): the burst by element (physical keeps the stock burst), the holy heal
	snare_fire = "fire_explosion",
	snare_ice = "frost_nova",
	snare_energy = "lightning_strike",
	snare_earth = "toxic_burst",
	snare_death = "shadow_eruption",
	snare_holy = "holy_hit",
	snare_holy_heal = "tick_regen",
	-- rift modifiers (rift.lua)
	rift_boss_arrives = "void_maw",
	rift_cinder_mark = "tick_burn",
	rift_cinder_burst = "fire_explosion",
	rift_strike_fire = "fire_explosion",
	rift_strike_ice = "frost_nova",
	rift_strike_energy = "lightning_strike",
	rift_strike_death = "shadow_eruption",
	rift_crit_wound = "tick_bleed",
	rift_fester = "tick_poison",
	-- world bosses (worldboss.lua)
	wb_arrives = "void_maw",
	wb_enrage = "blood_pact",
	wb_adds = "teleport_in",
}

-- the cuts: in the next pair only (their ids come from chaos_pack_fx_ids.lua)
C.cuts = {"reflect_bubble", "tick_bleed", "tick_burn", "tick_poison", "tick_chill", "tick_curse", "tick_regen"}

-- the effect name of a use, or nil (pure: no switch, no ids)
function C.pick(use)
	return type(use) == "string" and C.uses[use] or nil
end

-- the switch on and the pack names known (chaos_vfx.lua, and the cuts' ids when that file exists; loaded once)
function C.live()
	if not C.PACK_FX then
		return false
	end
	if C.loaded == nil then
		if not ChaosVfx then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if ChaosVfx and not ChaosVfx.reflect_bubble then
			pcall(dofile, "data/lib/chaos_pack_fx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and Vfx ~= nil
	end
	return C.loaded
end

-- send the use's effect at its offset tile; else the stock `fallback` (switch off, unknown use or name)
function C.send(pos, use, fallback)
	local name = C.live() and C.pick(use)
	if name and ChaosVfx[name] and Vfx(pos, name) then
		return true
	end
	if fallback and pos then
		if pos.sendMagicEffect then
			pos:sendMagicEffect(fallback)    -- the same call the site made before
		else
			Position(pos.x, pos.y, pos.z):sendMagicEffect(fallback)
		end
	end
	return false
end
