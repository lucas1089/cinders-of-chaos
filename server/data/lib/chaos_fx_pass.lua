-- Spell effects pass (O457): a spell that showed an effect of the wrong element, a long still picture on a quick hit,
-- a speck for a big move or the same picture twice shows another effect that is already in the client pair. Effects
-- only: no damage, area, timing, target or reward changes. Nothing here needs a new pair.
-- The eye work (contact sheets of the old and the new picture on dark and on green ground): server/README.md
-- "Spell effects pass (O457)", with the table of every change and the rows of the review that were not changed.
--
-- spell id -> kind -> {name the spell sends = the ChaosVfx name that takes its place}. Kinds as chaos_pack27_fx.lua:
-- fx (ChaosSpell.fx / vfx / vfxOr, so a name a kit spell sends on every tile of a wave or a line keeps that shape) and
-- ChaosSpell.passFx (the Berserker's own landing effect). The new name is any ChaosVfx name (chaos_vfx.lua, the pair 36
-- ids, the pair 50 p50_ ids); the registry holds its send offset. This table is asked FIRST (ChaosSpell.pack29 in
-- data/spells/chaos/_common.lua), before the Mystic pair 29 table, the element blasts of pair 29, the pair 36 table,
-- the large, the class and the pair 27 effects; a cosmetic skin still wins. A spell not listed is untouched.
-- Checked by tests/fx_pass_test.lua (names, ids, the element table of tools/ci/check_spell_fx.py) and the rule of
-- that script: a spell does not send an effect of another element unless the allowlist says why.
-- Lua 5.1 / LuaJIT / 5.3.

ChaosFxPass = ChaosFxPass or {}
local C = ChaosFxPass

C.ON = true

C.spells = {
	-- Holy spells that showed the blue arcane blast (810 via the pair 29 blast of holy_hit)
	[214] = {fx = {holy_hit = "p50_gold_comet_burst_4293"}},                          -- Dawnpiercer
	[129] = {fx = {holy_hit = "p50_gold_comet_burst_4293"}},                          -- Lance of Vigil
	[19] = {fx = {holy_hit = "p50_yellow_spike_burst_4551"}},                         -- Sunspear
	[121] = {fx = {holy_hit = "p50_yellow_spike_burst_4551"}},                        -- Hallowed Cut
	[138] = {fx = {holy_hit = "holy_hit"}},                                           -- Heretic's Brand: the gold cross itself
	[151] = {fx = {holy_hit = "p50_yellow_spike_burst_4551"}},                        -- Dawnbreaker Shot
	-- Wind and volley spells that showed the red critical-hit star (415)
	[134] = {fx = {crit_burst = "p50_whirlwind_1_4147"}},                             -- Gale Volley (each tile of the line)
	[22] = {fx = {crit_burst = "p50_white_whirl_4495"}},                              -- Arrowstorm
	[149] = {fx = {crit_burst = "p50_ice_shard_sparks_4400"}},                        -- Moonshard Rain
	[56] = {fx = {crit_burst = "p50_white_arc_slash_4416"}},                          -- Razor Rain
	-- Earth fire coloured blast on a necromancer's death spell
	[119] = {fx = {ground_slam = "p50_dust_cloud_4328"}},                             -- Crypt Collapse
	-- Monk finishers that showed the fire comet 376
	[90] = {fx = {meteor_strike = "p50_white_energy_orb_4638"}},                      -- Skysplitter Fist
	[174] = {fx = {meteor_strike = "p50_gold_orbit_rings_4386"}},                     -- Heaven's Ninth Gate
	-- A long still picture on a quick hit (holy cross 404, holy seal 445, void eye 396, void rift 441, plague mist 435)
	[128] = {fx = {holy_cross = "p50_yellow_rune_ring_1_4144"}},                      -- Bell of Reckoning
	[250] = {fx = {holy_cross = "p50_gold_sparkle_burst_4190"}},                      -- Crusader's Sweep (each tile)
	[126] = {fx = {holy_cross = "p50_gold_swirl_sparks_4128"}},                       -- Penitent Lash (each tile)
	[122] = {fx = {holy_seal = "p50_yellow_spike_burst_4551"}},                       -- Censer Swing
	[118] = {fx = {void_eye = "p50_purple_spiky_ring_4584",                           -- Soulrend Beam (each tile)
		void_rift = "p50_purple_flame_ball_4574"}},
	[107] = {fx = {shadow_cloud = "p50_purple_cloud_4579",                            -- Wraithwind (each tile)
		plague_mist = "p50_pale_green_wisp_spirals_4505"}},
	[158] = {fx = {shadow_cloud = "p50_purple_cloud_4579",                            -- Soulflay Wave (each tile)
		plague_mist = "p50_pale_green_wisp_spirals_4505"}},
	[180] = {fx = {necro_seal = "p50_skull_ghost_4235"}},                             -- Raise Dead
	[192] = {fx = {necro_seal = "p50_skull_ghost_4235"}},                             -- Raise Bone Warrior
	[40] = {fx = {necro_seal = "p50_skull_ghost_4235"}},                              -- Raise Bone Archer
	[176] = {fx = {necro_seal = "p50_skull_ghost_4235"}},                             -- Raise Bone Mage
	[112] = {fx = {necro_seal = "p50_purple_spiky_ring_4584"}},                       -- Gravewail
	-- The Warrior line and friends: strong pictures for the big moves
	[221] = {fx = {earth_spikes = "p50_dust_burst_with_spark_4426"}},                 -- Earthbreaker
	[140] = {fx = {blunt_smash = "p50_yellow_spike_burst_4551",                        -- Bulwark Slam (holy shield smash)
		ground_slam = "p50_yellow_rune_ring_1_4144"}},
	[65] = {fx = {whirlwind = "w_impact_whirlwind"}},                                 -- Whirling Heel (was the holy shock 641 of chaos_big_fx.lua)
	[62] = {fx = {heavy_cleave = "p50_white_scythe_slash_4537"}},                     -- Crescent Cut
	[155] = {fx = {heavy_cleave = "p50_white_scythe_slash_4537"}},                    -- Eclipse Edge
	[142] = {fx = {heavy_cleave = "p50_white_arc_slash_4417"}},                       -- Keepfall
	[9] = {fx = {heavy_cleave = "p50_white_arc_slash_4417"}},                         -- Rift Cleaver
	[145] = {fx = {heavy_cleave = "p50_white_arc_slash_4416"}},                       -- Rampage Leap
	[246] = {fx = {ground_slam = "p50_red_claw_arc_4616"}},                   -- Skyfall Cleave (the landing spot)
	[219] = {fx = {holy_smite = "p50_gold_spark_4467"}},                              -- Hail of Dawn (each tile)
	[187] = {fx = {bonelord_rally = "p50_purple_spiky_ring_4584"}},                   -- Banner of Bones (each rallied minion)
	[170] = {fx = {dome_blast_holy = "p50_gold_ring_pulse_4260"}},                    -- Shield Wave
	-- Dark effects too dark to read on dark ground (393 shadow smoke, 394 shadow cloud)
	[43] = {fx = {shadow_smoke = "p50_purple_cloud_4579"}},                           -- Dreamrot
	[241] = {fx = {shadow_smoke = "p50_grey_smoke_ball_4573"}},                       -- Smoke Bomb
	[67] = {fx = {shadow_cloud = "p50_purple_cloud_4579"}},                           -- Mistborne Strike (each tile)
	-- The same picture twice in one cast (the cast effect and the engine's hit effect of the same id)
	[88] = {fx = {blood_slash = "monk_heel"}},                                        -- Cleaving Heel (blood_slash 391 = HITAREA 10)
	[106] = {fx = {necro_skull = "p50_skull_ghost_4235"}},                            -- Marrow Bolt (necro_skull 397 = MORTAREA 18)
	[120] = {fx = {necro_skull = "p50_purple_flame_ball_4574"}},                      -- Ossuary Surge (the same)
	[193] = {fx = {necro_skull = "p50_purple_spark_4575"}},                           -- Splinter Volley (the same)
	-- The owner's donor client effects (O525, client pair 68, data/lib/chaos_donor_fx_ids.lua): native size pictures of the
	-- element of the spell, the same role (hit stays a hit, area an area, buff a buff, heal a heal). Spells that have a class
	-- signature effect (chaos_class_fx.lua: Chi Ward, Lightward, Lay on Hands, Vow of Mending) are left alone: the pass is asked first
	[38] = {fx = {ice_shatter = "donor_ice_hit_489", ice_crystal = "donor_ice_hit_475"}}, -- Mirror Shards (shards around you, a chip on each enemy)
	[201] = {fx = {fireball_hit = "donor_fire_hit_465"}},                             -- Witchfire Bolt
	[202] = {fx = {lightning_hit = "donor_energy_strike_632", lightning_strike = "donor_energy_strike_632"}}, -- Forked Storm: the donor strike 4707 for the first hit and each jump (O532, owner choice; offset 0,0 puts its foot, at the end of the art, in the target tile)
	[199] = {fx = {dome_blast_holy = "donor_holy_ring_449"}},                         -- Purging Nova (radius 3)
	[57] = {fx = {poison_ring = "donor_earth_field_505"}},                              -- Venom Spiral (a green cloud on the target while it rots)
	[132] = {fx = {shield_bubble = "donor_physical_aura_495"}},                       -- Ironhold
	[234] = {fx = {shield_bubble = "donor_arcane_aura_494"}},                         -- Soulward
	[252] = {fx = {dawn_aegis = "donor_holy_aura_493"}},                              -- Aegis of Faith
	[96] = {fx = {regenerating = "donor_holy_aura_216"}},                             -- Mirror Mend
}

-- spell id -> the spell's name in spells_chaos.xml (tests/fx_pass_test.lua: an id that moves fails it)
C.names = {
	[214] = "Dawnpiercer", [129] = "Lance of Vigil", [19] = "Sunspear", [121] = "Hallowed Cut",
	[138] = "Heretic's Brand", [151] = "Dawnbreaker Shot", [134] = "Gale Volley", [22] = "Arrowstorm",
	[149] = "Moonshard Rain", [56] = "Razor Rain", [119] = "Crypt Collapse", [90] = "Skysplitter Fist",
	[174] = "Heaven's Ninth Gate", [128] = "Bell of Reckoning", [250] = "Crusader's Sweep", [126] = "Penitent Lash",
	[122] = "Censer Swing", [118] = "Soulrend Beam", [107] = "Wraithwind", [158] = "Soulflay Wave",
	[180] = "Raise Dead", [192] = "Raise Bone Warrior", [40] = "Raise Bone Archer", [176] = "Raise Bone Mage",
	[112] = "Gravewail", [221] = "Earthbreaker", [140] = "Bulwark Slam", [62] = "Crescent Cut",
	[155] = "Eclipse Edge", [142] = "Keepfall", [9] = "Rift Cleaver", [145] = "Rampage Leap",
	[246] = "Skyfall Cleave", [219] = "Hail of Dawn", [187] = "Banner of Bones", [170] = "Shield Wave", [65] = "Whirling Heel",
	[43] = "Dreamrot", [241] = "Smoke Bomb", [67] = "Mistborne Strike", [88] = "Cleaving Heel",
	[106] = "Marrow Bolt", [120] = "Ossuary Surge", [193] = "Splinter Volley",
	[38] = "Mirror Shards", [201] = "Witchfire Bolt", [202] = "Forked Storm",
	[199] = "Purging Nova", [57] = "Venom Spiral", [132] = "Ironhold",
	[234] = "Soulward", [252] = "Aegis of Faith", [96] = "Mirror Mend",
}

-- the new name for a spell id, kind and name, or nil (pure: no switch, no ids)
function C.pick(spellId, kind, name)
	local s = spellId and C.spells[spellId]
	local k = s and s[kind]
	return k and type(name) == "string" and k[name] or nil
end

-- the switch on and the ids known: the pair 36, 41 and 50 id files are loaded by ChaosPack36Fx.live()
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosPack36Fx and dofile then
			pcall(dofile, "data/lib/chaos_pack36_fx.lua")
		end
		local P = ChaosPack36Fx
		if P and P.live then
			local ok, live = pcall(P.live)
			C.loaded = ok and live == true and ChaosVfx ~= nil
		end
		-- the class effects (warrior_quake, monk_heel ...) are named too
		if C.loaded and not ChaosVfx.warrior_quake and dofile then
			pcall(dofile, "data/lib/chaos_class_fx_ids.lua")
		end
	end
	return C.loaded
end

-- the new name for spell `spellId` sending `name` of `kind`, or nil (switch off, no entry, the id not known)
function C.swapFor(spellId, kind, name)
	local alt = C.pick(spellId, kind, name)
	if not alt or not C.live() then
		return nil
	end
	return ChaosVfx[alt] and alt or nil
end
