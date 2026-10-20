-- Pair 27 effects (trial): the nine pack farming spells get effects and missiles of their own instead of the ones they
-- borrow from other spells; spell impacts, circles and buff looks for every class line; buff, vigil and stun states;
-- game feel moments (level up, loot beams, Ember Cache and Candlemarks rewards, the Town Portal, the boss danger
-- circle). Effects only: no damage, area, timing, target or reward changes.
-- The art: client/tools/sprites/gen_pack27_fx.py (art_import/pack27_fx.csv), appended to things_custom26 (effects
-- 674-758, missiles 154-160) by import_fx_art.py, which wrote the ids to data/lib/chaos_pack27_fx_ids.lua. In the
-- published pairs since pair 27 (windows-assets 51a26d26, 2026-10-15; pair 28 keeps them).
--
-- Switch (C.PAIR27_FX): ON since 2026-10-15 (ROADMAP 179). A client on a pair older than 27 would log "invalid effect
-- id". Off, nothing changes: the ids file is not loaded and every spell sends exactly what it sent before. On, during a
-- cast (the supports wrapper knows the spell, also in the cast's addEvent callbacks) an effect, missile or
-- directional effect name in C.spells for that spell is sent as the pair 27 one instead (ChaosSpell.fx / vfx / vfxDir /
-- shoot / vshoot in data/spells/chaos/_common.lua). A cosmetic skin always wins; a large effect and a class signature
-- effect win too, unless the spell lists the name in `first` (so Blade Flurry of the Ninja and Samurai keeps its own).
-- Lua 5.1 / LuaJIT / 5.3.

ChaosPack27Fx = ChaosPack27Fx or {}
local C = ChaosPack27Fx

C.PAIR27_FX = true

-- spell id -> kind -> {name the spell sends = the pair 27 name}; kinds: fx (an effect, also through vfx / vfxOr),
-- missile (ChaosSpell.shoot / vshoot), dir (the base name of a directional effect, VfxDir), fxdir (an effect the spell
-- sends without a direction, sent as the directional pair 27 effect turned from the caster towards its tile).
-- first = {name = true}: that fx swap wins over the large and the class effect of the spell (a skin still wins).
C.spells = {
	-- the nine pack farming spells and Hunter's Instinct
	[194] = {fx = {aura_burst_gold = "palm_quake"}},                            -- Palm Shockwave
	[73] = {fx = {whirlwind = "flurry_petals"}},                                -- Blade Flurry
	[74] = {dir = {heavy_cleave = "iaido_dash"}},                               -- Iaido Sweep
	[195] = {fx = {void_eye = "ricochet_burst"}, missile = {shadow_bolt = "ricochet_bolt"}}, -- Shadow Ricochet
	[196] = {fx = {stone_rise = "chain_sparks"}, missile = {lightning_orb = "chain_disc"}},  -- Iron Chain
	[197] = {fx = {bone_burst = "shrapnel_burst"}, missile = {bone_spear = "shrapnel_shards"}}, -- Bone Shrapnel
	[137] = {fx = {holy_seal = "sanctified_seal"}},                             -- Sanctified Ground
	[170] = {fxdir = {dome_blast_holy = "shieldwave_bash"}},                    -- Shield Wave
	[136] = {missile = {razor_disc = "fan_knife"}},                             -- Fan of Knives
	[235] = {fx = {gale_ring = "hunter_focus"}},                                -- Hunter's Instinct
	-- Mystic line
	[200] = {fx = {frost_nova = "nova_frost"}},                                 -- Rime Bloom
	[204] = {fx = {meteor_strike = "meteor_fall"}, first = {meteor_strike = true}}, -- Falling Pyre
	[202] = {fx = {lightning_hit = "storm_chain"}, first = {lightning_hit = true}}, -- Forked Storm, each jump
	[231] = {fx = {void_rift = "rift_void"}},                                   -- Tear in the Weave (the large
	                                                                            -- rift wins; the script adds this core)
	-- Templar line
	[189] = {fx = {holy_smite = "smite_radiant"}, missile = {holy_arrow = "holy_orb"}}, -- Radiant Smite
	[198] = {fx = {holy_smite = "judgment_holy"}, first = {holy_smite = true}}, -- Judgement
	[199] = {fx = {dome_blast_holy = "nova_radiant"}, first = {dome_blast_holy = true}}, -- Purging Nova
	[191] = {fx = {healing_bloom = "mend_holy"}, first = {healing_bloom = true}}, -- Vow of Mending
	[250] = {fx = {aura_burst_gold = "zeal_oath"}, first = {aura_burst_gold = true}}, -- Zealotry
	[252] = {fx = {dawn_aegis = "aegis_radiant"}, first = {dawn_aegis = true}}, -- Aegis of Faith
	-- Warrior line
	[220] = {fx = {whirlwind = "gyre_steel"}, first = {whirlwind = true}},      -- Reaping Gyre
	[221] = {fx = {earth_spikes = "slam_earth"}, first = {earth_spikes = true}}, -- Earthbreaker
	[225] = {fx = {earth_spikes = "terra_strike"}, first = {earth_spikes = true}}, -- Colossus Fall
	[223] = {fx = {aura_burst_gold = "bellow_cry"}, first = {aura_burst_gold = true}}, -- Iron Bellow
	[222] = {fx = {aura_burst_red = "berserk_blood"}, first = {aura_burst_red = true}}, -- Red Frenzy
	[247] = {fx = {aura_burst_red = "berserk_blood"}, first = {aura_burst_red = true}}, -- Bloodrage
	[246] = {dir = {heavy_cleave = "cleave_blood"}},                            -- Skyfall Cleave
	[224] = {dir = {heavy_cleave = "cleave_blood"}},                            -- Vaulting Cleave
	-- Thief line
	[240] = {fx = {shade_appear = "backstab_shadow"}, first = {shade_appear = true}}, -- Shadow Step (the strike)
	[243] = {fx = {shield_bubble = "parry_steel"}, first = {shield_bubble = true}}, -- Counter Stance
	[239] = {fx = {poisoned = "venom_flurry"}},                                 -- Poison Blades
	[238] = {fx = {shade_vanish = "veil_stealth"}, first = {shade_vanish = true}}, -- Shadow Veil
	[236] = {missile = {shuriken = "shuriken_steel"}},                          -- Shuriken Toss
	[242] = {missile = {shuriken = "shuriken_steel"}},                          -- Shuriken Barrage
	-- Necromancer line
	[184] = {fx = {lich_soul_drain = "drain_blood"}},                           -- Life Siphon
	[180] = {fx = {necro_seal = "summon_necro"}, missile = {skull_orb = "soul_skull"}}, -- Raise Dead
	[182] = {fx = {cursed = "curse_mark"}, missile = {skull_orb = "soul_skull"}, first = {cursed = true}}, -- Withering Curse
	[183] = {missile = {skull_orb = "soul_skull"}},                             -- Soul Rot
	-- Monk line
	[69] = {fxdir = {punch_hit_violet = "claws_shadow"}},                       -- Shadowfist Flurry
	[63] = {fx = {punch_hit_gold = "punch_fire"}},                              -- Ashen Fist
	[71] = {fx = {punch_hit_gold = "hammer_steel"}},                            -- Iron Palm
	[66] = {fx = {chi_charge = "healing_burst"}},                               -- Kindled Breath
	-- shared
	[234] = {fx = {shield_bubble = "ward_shield"}},                             -- Soulward
}

-- use -> effect name, sent on a player or tile by C.send (call sites: catchup.lua, embercache.lua, candlemarks.lua,
-- _vigils.lua, ironsage/iron_palm.lua)
C.uses = {
	rested = "buff_rested",            -- the rested pool grew while offline (login)
	returning = "buff_returning",      -- the returning player boost starts (login)
	catchup = "buff_catchup",          -- the alt catch-up bonus is active (login)
	low_stamina = "buff_low_stamina",  -- the daily low stamina notice
	level_up = "levelup_rise",         -- a new level (no words baked into the art)
	embercache = "embercache_coins",   -- an Ember Cache reward toast
	candlemarks = "candlemark_glow",   -- Candlemarks earned
	vigil_wrath = "vigil_wrath",       -- a vigil switched on (_vigils.lua)
	vigil_iron = "vigil_iron",
	vigil_haste = "vigil_haste",
	vigil_clarity = "vigil_clarity",
	stun = "stun_stars",               -- Iron Palm: a monster really stunned
}

-- loot ray effect (lootfilter_config.lua: Legendary, Divine and uniques) -> the pair 27 beam
C.rays = {
	loot_ray_legendary = "loot_beam_gold",
	loot_ray_divine = "loot_beam_steel",
	loot_ray_unique = "loot_beam_emerald",
}

-- Town Portal effect name (townportal_config.lua lists) -> the pair 27 effect, tried first (townportal.lua fx)
C.portals = {
	arcane_circle = "portal_pad",  -- the channel, once a second on the caster
	teleport_in = "portal_in",     -- the Waygate opens
	teleport_out = "portal_out",   -- the Waygate closes
}

-- the boss danger circle (boss_mechanics.lua): sent at the centre of a round telegraph of this size (tiles)
C.telegraphName, C.telegraphSize = "boss_telegraph", 5

-- spell id -> the spell's name in spells_chaos.xml (checked by tests/pack27_fx_test.lua: an id that moves fails it)
C.names = {
	[194] = "Palm Shockwave", [73] = "Blade Flurry", [74] = "Iaido Sweep", [195] = "Shadow Ricochet",
	[196] = "Iron Chain", [197] = "Bone Shrapnel", [137] = "Sanctified Ground", [170] = "Shield Wave",
	[136] = "Fan of Knives", [235] = "Hunter's Instinct", [200] = "Rime Bloom", [204] = "Falling Pyre",
	[202] = "Forked Storm", [231] = "Tear in the Weave", [189] = "Radiant Smite", [198] = "Judgement",
	[199] = "Purging Nova", [191] = "Vow of Mending", [250] = "Zealotry", [252] = "Aegis of Faith",
	[220] = "Reaping Gyre", [221] = "Earthbreaker", [225] = "Colossus Fall", [223] = "Iron Bellow",
	[222] = "Red Frenzy", [247] = "Bloodrage", [246] = "Skyfall Cleave", [224] = "Vaulting Cleave",
	[240] = "Shadow Step", [243] = "Counter Stance", [239] = "Poison Blades", [238] = "Shadow Veil",
	[236] = "Shuriken Toss", [242] = "Shuriken Barrage", [184] = "Life Siphon", [180] = "Raise Dead",
	[182] = "Withering Curse", [183] = "Soul Rot", [69] = "Shadowfist Flurry", [63] = "Ashen Fist",
	[71] = "Iron Palm", [66] = "Kindled Breath", [234] = "Soulward",
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

-- the pair 27 name for spell `spellId` sending `name` of `kind`, or nil (switch off, no swap, the id not known); for an
-- fx swap also true when it wins over the large and the class effect (C.spells first)
function C.swapFor(spellId, kind, name)
	if not C.live() then
		return nil
	end
	local alt = C.pick(spellId, kind, name)
	if not alt then
		return nil
	end
	if kind == "fx" then
		local first = C.spells[spellId].first
		return ChaosVfx and ChaosVfx[alt] and alt or nil, first ~= nil and first[name] == true
	end
	if kind == "missile" then
		return ChaosVfxMissile and ChaosVfxMissile[alt] and alt or nil
	end
	if kind == "dir" or kind == "fxdir" then
		return ChaosVfx and ChaosVfx[alt .. "_s"] and alt or nil
	end
	return ChaosVfx and ChaosVfx[alt] and alt or nil
end

-- send the effect of a use at pos (its offset tile); false when the switch is off or the name is unknown
function C.send(pos, use)
	local name = type(use) == "string" and C.uses[use]
	if not name or not pos or not C.live() or not Vfx then
		return false
	end
	local ok, sent = pcall(Vfx, pos, name)
	return ok and sent and true or false
end

-- the pair 27 beam for a loot ray effect name: {id, dx, dy} (send it at pos + (dx, dy)), or nil
function C.ray(effect)
	local name = type(effect) == "string" and C.rays[effect]
	if not name or not C.live() then
		return nil
	end
	return ChaosVfx and ChaosVfx[name] or nil
end

-- the pair 27 effect for a Town Portal effect name, or nil (switch off, no swap, the id not known)
function C.portal(name)
	local alt = type(name) == "string" and C.portals[name]
	if not alt or not C.live() then
		return nil
	end
	return ChaosVfx and ChaosVfx[alt] and alt or nil
end

-- the centre tile of a round telegraph of C.telegraphSize tiles (ChaosBigFx.circleOf), or nil (pure)
function C.telegraphCentre(tiles)
	local B = ChaosBigFx
	if not B or not B.circleOf then
		return nil
	end
	local centre, size = B.circleOf(tiles)
	return size == C.telegraphSize and centre or nil
end

-- the boss danger circle at the centre of a round telegraph; false when the switch is off or the shape does not fit
function C.telegraph(tiles)
	if not C.live() or not Vfx then
		return false
	end
	local centre = C.telegraphCentre(tiles)
	if not centre then
		return false
	end
	local ok, sent = pcall(Vfx, centre, C.telegraphName)
	return ok and sent and true or false
end
