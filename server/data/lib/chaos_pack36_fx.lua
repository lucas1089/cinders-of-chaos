-- Pair 36 effects: the purchased effect packs (docs/CREDITS.md: Grid Magic 500, Mega VFX 500, the spell, aura, field,
-- projectile and game feel packs, the loot beams) in the game, as the owner asked on 2026-10-22 ("Use as spells, level
-- up e loot beams", "use everything"). Effects only: no damage, area, timing, target or reward changes.
-- The art: client/tools/sprites/gen_pack36_fx.py (art_import/pack36_<group>.csv), imported into pair 36 by
-- import_fx_art.py:
--   * in place: our procedural effects and missiles of gen_effects.py (fx_custom.csv: the stock ids it redrew, 372-428,
--     the stock and procedural missiles) and the combat feedback 415-417 and 628 now draw the pack art AT THEIR IDS. Every
--     engine hit, monster attack (areaEffect / shootEffect of the monster files), ChaosFx / ChaosFxMissile name and
--     script sends what it sent before and shows the new art; nothing here is needed for that.
--   * appended: every other effect of the packs (effects 855 and on, missiles 189 and on), named in
--     data/lib/chaos_pack36_fx_ids.lua (written by import_fx_art.py), loaded into ChaosVfx / ChaosVfxMissile by C.live().
-- This file sends some of the appended ones: per spell (C.spells, the spells pair 27 has no swap for; the same kinds
-- as chaos_pack27_fx.lua: fx also through vfx / vfxOr, missile, dir, fxdir), checked by tests/pack36_fx_test.lua.
-- The loot beams and the level-up effect are sent by the client (game_lootbeams, game_levelwings) by id.
--
-- Switch (C.PAIR36_FX): ON since pair 36 is on windows-assets (2026-10-22). A client on a pair older than 36 logs
-- "invalid effect id" for the appended ids and draws our old art for the replaced ones. Off: the ids file is not
-- loaded and every spell sends exactly what it sent before (the replaced ids still show the pack art on pair 36).
-- Lua 5.1 / LuaJIT / 5.3.

ChaosPack36Fx = ChaosPack36Fx or {}
local C = ChaosPack36Fx

C.PAIR36_FX = true

-- spell id -> kind -> {name the spell sends = the pair 36 name}. Only spells chaos_pack27_fx.lua has no entry for
-- (the test checks it), so the two tables never fight.
C.spells = {
	-- Sorcerer, Druid
	[205] = {fx = {frost_glyph = "w_circle_frost_field"}},                     -- Frozen Crypt
	[207] = {fx = {toxic_burst = "mega_venom_wasps"}},                         -- Blightswarm
	[208] = {fx = {healing_bloom = "w_circle_healing_spring"}},                -- Purifying Wellspring
	[209] = {fx = {stone_ward = "mega_bark_skin"}},                            -- Ironbark Hide
	[211] = {fx = {summon_portal = "mega_summon_star_gate"}},                  -- Moonfang Pack
	[212] = {fx = {grove_glyph = "mega_circle_lotus_pad"}},                    -- Verdant Sanctuary
	-- Paladin, Templar, Inquisitor, Sentinel
	[214] = {fx = {holy_hit = "w_impact_holy_strike"}},                        -- Dawnpiercer
	[216] = {fx = {holy_seal = "w_circle_consecration"}},                      -- Blessed Earth
	[217] = {fx = {dawn_aegis = "w_aura_radiant_halo"}},                       -- Lightward
	[218] = {fx = {holy_smite = "w_impact_divine_judgment"}},                  -- Final Verdict
	[144] = {fx = {holy_smite = "w_impact_holy_smite"}},                       -- Twin Verdict
	[135] = {fx = {aura_burst_gold = "w_status_eagle_eye"}},                   -- Tautstring
	[190] = {fx = {holy_seal = "w_circle_prayer_circle"}},                     -- Consecration
	[251] = {fx = {solar_flash = "w_impact_holy_nova"}},                       -- Rebuke
	[253] = {fx = {healing_bloom = "w_impact_holy_heal"}},                     -- Lay on Hands
	-- Knight, Samurai, Berserker
	[132] = {fx = {shield_bubble = "w_status_fortified"}},                     -- Ironhold
	[58] = {fx = {earth_spikes = "w_impact_terra_strike"}},                    -- Anvil Fall
	[244] = {dir = {sword_slash = "cone_steel_crescent"}},                     -- Iaijutsu
	[245] = {fx = {aura_burst_gold = "w_status_might"}},                       -- Bushido Focus
	-- Illusionist, shared
	[226] = {fx = {arcane_sigil = "mega_mirror_hex", summon_portal = "mega_summon_mirror_step"}}, -- Hall of Mirrors
	[227] = {fx = {shade_vanish = "w_fx_shadow_step", shade_appear = "mega_summon_void_fold"}}, -- Umbral Stride
	[229] = {fx = {shadow_shroud = "w_aura_shadow_veil"}},                     -- Wraithshroud
	[230] = {fx = {void_maw = "mega_umbral_maws"}},                            -- Nightburst
	[232] = {fx = {blink_vanish = "w_fx_teleport_out", blink_appear = "w_fx_teleport_in"}}, -- Flickerdash
	[233] = {fx = {aura_burst_gold = "w_aura_war_banner"}},                    -- Banner Call
	[96] = {fx = {regenerating = "w_status_regeneration"}},                    -- Mirror Mend
	[97] = {fx = {starfall_crown = "w_aura_starfall"}},                        -- Lucid Reverie
	-- Ninja, Beastmaster
	[248] = {fx = {summon_portal = "mega_summon_totem_drop"}},                 -- Wild Bond
	-- Lich, Bonelord
	[185] = {fx = {bone_burst = "w_impact_corpse_explosion"}},                 -- Corpse Explosion
	[186] = {fx = {necro_seal = "w_circle_necropolis"}},                       -- Bone Golem
	[187] = {fx = {necro_seal = "mega_bone_pentacle"}},                        -- Banner of Bones
	[188] = {fx = {bone_burst = "mega_burst_bone_cage_burst"}},                -- Bone Offering
	-- Monk, Shadowfist, Ironsage
	[64] = {fx = {punch_hit_red = "w_impact_punch"}},                          -- Sundering Palm
	[65] = {fx = {whirlwind = "w_impact_whirlwind"}},                          -- Whirling Heel
	[68] = {fxdir = {punch_hit_violet = "mega_wraith_palm"}},                  -- Pressure Points (turned from the caster)
	[70] = {fx = {shield_bubble = "w_status_shielded"}},                       -- Chi Ward
	[72] = {fx = {stone_rise = "mega_stone_shelves"}},                         -- Mantra of Stone
}

-- spell id -> the spell's name in spells_chaos.xml (tests/pack36_fx_test.lua: an id that moves fails it)
C.names = {
	[205] = "Frozen Crypt", [207] = "Blightswarm", [208] = "Purifying Wellspring",
	[209] = "Ironbark Hide", [211] = "Moonfang Pack", [212] = "Verdant Sanctuary", [214] = "Dawnpiercer",
	[216] = "Blessed Earth", [217] = "Lightward", [218] = "Final Verdict", [144] = "Twin Verdict",
	[135] = "Tautstring", [190] = "Consecration", [251] = "Rebuke", [253] = "Lay on Hands",
	[132] = "Ironhold", [58] = "Anvil Fall", [244] = "Iaijutsu", [245] = "Bushido Focus",
	[226] = "Hall of Mirrors", [227] = "Umbral Stride", [229] = "Wraithshroud", [230] = "Nightburst",
	[232] = "Flickerdash", [233] = "Banner Call", [96] = "Mirror Mend", [97] = "Lucid Reverie", 
	[248] = "Wild Bond", [185] = "Corpse Explosion", [186] = "Bone Golem", [187] = "Banner of Bones",
	[188] = "Bone Offering", [64] = "Sundering Palm", [65] = "Whirling Heel", 
	[68] = "Pressure Points", [70] = "Chi Ward", [72] = "Mantra of Stone",
}

-- the pair 36 name for a spell id, kind and name, or nil (pure: no switch, no ids)
function C.pick(spellId, kind, name)
	local s = spellId and C.spells[spellId]
	local k = s and s[kind]
	return k and type(name) == "string" and k[name] or nil
end

-- the switch on and the ids known (chaos_pack36_fx_ids.lua loaded once into ChaosVfx / ChaosVfxMissile)
function C.live()
	if not C.PAIR36_FX then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosVfx and dofile then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if not (ChaosVfx and ChaosVfx.w_impact_holy_strike) and dofile then
			pcall(dofile, "data/lib/chaos_pack36_fx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and ChaosVfx.w_impact_holy_strike ~= nil
		-- pair 41: the three missiles appended after pair 36's (ids 251-253), named for later spells; nothing sends them yet
		if C.loaded and ChaosVfxMissile and not ChaosVfxMissile.proj_arrow_fire and dofile then
			pcall(dofile, "data/lib/chaos_pack41_fx_ids.lua")
		end
	end
	return C.loaded
end

-- the pair 36 name for spell `spellId` sending `name` of `kind`, or nil (switch off, no swap, the id not known)
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
	if kind == "dir" or kind == "fxdir" then
		return ChaosVfx and ChaosVfx[alt .. "_s"] and alt or nil
	end
	return ChaosVfx and ChaosVfx[alt] and alt or nil
end
