-- Pair 29 effects: the Mystic line's spells (Mystic, Elementalist, Illusionist) get new effects and missiles of the
-- owner's oblique effect sets (Tier B of the 2026-10-16 Mystic effect pass; owner: "I found the effects of the Mystic
-- spells very poor"). Effects only: no damage, area, timing, target or reward changes.
-- The art: client/tools/sprites/gen_pack29_fx.py (art_import/pack29_fx.csv), appended to pair 28 (effects 759-779,
-- missiles 161-169) by import_fx_art.py, which wrote the ids to data/lib/chaos_pack29_fx_ids.lua.
--
-- Switch (C.PAIR29): OFF until pair 29 is live on the clients (a client on pair 28 or older would log "invalid effect
-- id"). Off, nothing changes: the ids file is not loaded and every spell sends exactly what it sent before (the
-- Tier A effects, server/data/spells/README_FX.md "Mystic line effects"). On, during a cast (the supports wrapper
-- knows the spell, also in the cast's addEvent callbacks) a name in C.spells for that spell is sent as the pair 29
-- one instead. It wins over the large, the class and the pair 27 effect of the spell; a cosmetic skin still wins.
-- Kinds: fx (ChaosSpell.fx / vfx / vfxOr), missile (ChaosSpell.shoot / vshoot, ChaosMysticFx.shoot and
-- ChaosSpell.pack29Name for the scripts' own VfxShoot), send (ChaosMysticFx.send / later: the exact effects of the
-- Tier A helpers). The two base-server spells (no cast context) use C.stock.
-- Lua 5.1 / LuaJIT / 5.3.

ChaosPack29Fx = ChaosPack29Fx or {}
local C = ChaosPack29Fx

C.PAIR29 = true

-- spell id -> kind -> {name the spell sends = the pair 29 name}
C.spells = {
	-- Elementalist kit
	[201] = {missile = {fireball = "witchfire_lance"}},                                 -- Witchfire Bolt
	[202] = {missile = {lightning_orb = "storm_bolt"}, send = {lightning_strike = "storm_shock"}}, -- Forked Storm
	[204] = {fx = {infernal_seal = "pyre_rune"}, missile = {fireball = "pyre_comet"}},  -- Falling Pyre
	[205] = {missile = {ice_lance = "crypt_lance"}, send = {nova_frost = "crypt_ice_strike"}}, -- Frozen Crypt
	[206] = {fx = {storm_ring = "doom_tornado", fire_explosion = "doom_skyfall"}},      -- Doomtide (waves 2 and 3)
	-- Druid kit: the nature green stays
	[209] = {fx = {stone_ward = "ironbark_skin"}},                                      -- Ironbark Hide
	[210] = {fx = {earth_spikes = "briar_rooted"}},                                     -- Briar Prison
	[213] = {fx = {earth_spikes = "squall_spore_cloud"}},                               -- Primordial Squall (waves 1, 3)
	-- Illusionist kit
	[226] = {fx = {arcane_sigil = "mirror_glass_nova"}, send = {arcane_orbit = "mirror_ring"}}, -- Hall of Mirrors
	[227] = {missile = {shadow_orb = "umbral_raven"}, fx = {shade_appear = "umbral_step"},
		send = {shadow_eruption = "umbral_step"}},                                      -- Umbral Stride
	[228] = {missile = {arcane_bolt = "psyche_prism"}, send = {px03_arcane = "psyche_fracture"}}, -- Shattered Psyche
	[229] = {fx = {shadow_shroud = "wraith_veil"}},                                     -- Wraithshroud
	[230] = {fx = {void_maw = "night_eyelid", shadow_smoke = "night_cataclysm"}},       -- Nightburst
	[231] = {fx = {arcane_circle = "weave_crush"}},                                    -- Tear in the Weave (the
	                                                                                    -- pulled foes: weave_marble)
	[96] = {missile = {ki_blast_blue = "mend_shards", arcane_bolt = "mend_shards"},
		send = {arcane_hit = "mend_chime"}},                                            -- Mirror Mend
	[97] = {fx = {starfall_crown = "reverie_release"}, send = {tick_regen = "reverie_pop"}}, -- Lucid Reverie
}

-- the base-server spells wrapped by ChaosMysticFx.wrapStock (no cast context): stock key -> {name = pair 29 name}
C.stock = {
	bewitching_hex = {arcane_bolt = "hex_missile", tick_curse = "hex_curse"},
}

-- spell id -> the spell's name in spells_chaos.xml (checked by tests/pack29_fx_test.lua: an id that moves fails it)
C.names = {
	[201] = "Witchfire Bolt", [202] = "Forked Storm", [204] = "Falling Pyre",
	[205] = "Frozen Crypt", [206] = "Doomtide", [209] = "Ironbark Hide", [210] = "Briar Prison",
	[213] = "Primordial Squall", [226] = "Hall of Mirrors", [227] = "Umbral Stride", [228] = "Shattered Psyche",
	[229] = "Wraithshroud", [230] = "Nightburst", [231] = "Tear in the Weave", [96] = "Mirror Mend",
	[97] = "Lucid Reverie",
}

-- the pair 29 name for a spell id, kind and name, or nil (pure: no switch, no ids)
function C.pick(spellId, kind, name)
	local s = spellId and C.spells[spellId]
	local k = s and s[kind]
	return k and type(name) == "string" and k[name] or nil
end

-- the switch on and the ids known (chaos_pack29_fx_ids.lua loaded once into ChaosVfx / ChaosVfxMissile)
function C.live()
	if not C.PAIR29 then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosVfx and dofile then
			pcall(dofile, "data/lib/chaos_vfx.lua")
		end
		if not (ChaosVfx and ChaosVfx.night_cataclysm) and dofile then
			pcall(dofile, "data/lib/chaos_pack29_fx_ids.lua")
		end
		C.loaded = ChaosVfx ~= nil and ChaosVfx.night_cataclysm ~= nil
	end
	return C.loaded
end

local function known(kind, alt)
	if kind == "missile" then
		return ChaosVfxMissile ~= nil and ChaosVfxMissile[alt] ~= nil
	end
	return ChaosVfx ~= nil and ChaosVfx[alt] ~= nil
end

-- the pair 29 name for spell `spellId` sending `name` of `kind`, or nil (switch off, no swap, the id not known)
function C.swapFor(spellId, kind, name)
	if not C.live() then
		return nil
	end
	local alt = C.pick(spellId, kind, name)
	return alt and known(kind, alt) and alt or nil
end

-- the pair 29 name of a base-server spell's effect or missile, or nil
function C.stockFor(key, kind, name)
	local s = C.stock[key]
	local alt = s and type(name) == "string" and s[name]
	if not alt or not C.live() then
		return nil
	end
	return known(kind, alt) and alt or nil
end
