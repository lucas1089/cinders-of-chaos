-- chaos_spell_vfx.lua: the spell effects and projectiles of the purchased effect packs (O596, client pair 73; the art is in
-- the sprite pair only, client/tools/sprites/gen_spell_vfx.py, docs/CREDITS.md). Which spell sends which piece, by element:
-- fire spells the fire pieces, death, curse and poison spells the death pieces, heals and the Templar line the holy pieces,
-- energy and arcane spells the storm pieces. Looks only: no damage, no timing, no area changes.
--
-- Gate: config.lua `chaosClientPair` (README "Client pair guard") is 73 or more, read from the file at load (C.ON). A client
-- on pair 72 has no effect 4743+ and blank projectiles 43, 46, 47 and 52, so below 73 nothing here answers and every spell
-- keeps today's effects. The owner raises the record when pair 73 ships.
--
-- How: data/spells/chaos/_common.lua asks C.swapFor(spellId, kind, name) first, before the effects pass (chaos_fx_pass.lua),
-- pair 29, pair 36 and pair 27, for every name a spell sends through ChaosSpell.fx / vfx / vfxOr / shoot / vshoot / pshoot.
-- kind is "fx" (an effect name), "send" (an effect the Mystic helper sends, chaos_mystic_fx.lua M.alt) or "missile"; the names are the ones the scripts ask, before any swap.
-- The ids, send offsets and elements are the generated data/lib/chaos_spell_vfx_ids.lua. Plain Lua, no engine call at load
-- (server/tests/spell_vfx_test.lua).

local C = {}

C.PAIR = 73

function C.parsePair(text)
	if type(text) ~= "string" then
		return nil
	end
	local v = text:match("^%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*$") or text:match("\n%s*chaosClientPair%s*=%s*(%d+)%s*%-?%-?[^\n]*")
	return v and tonumber(v) or nil
end

function C.recordedPair(path)
	local f = io.open(path or "config.lua", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return C.parsePair(text)
end

-- the gate, read once at load; tests set it by hand
C.ON = (C.recordedPair() or 0) >= C.PAIR

-- [spell id] = {fx = {asked name = piece}, missile = {asked name = piece}}
C.spells = {
	-- fire
	[201] = {missile = {fireball = "sv_fire_bolt"}, send = {fire_explosion = "sv_fire_bolt_hit"}, fx = {fireball_hit = "sv_fire_bolt_hit"}}, -- Witchfire Bolt: bolt and its burst
	[204] = {fx = {meteor_strike = "sv_fire_crater"}}, -- Falling Pyre: the crater (its comet 163 is rebuilt in place)
	[206] = {fx = {dome_blast_fire = "sv_fire_nova"}}, -- Doomtide: its first wave
	[127] = {fx = {fire_ring = "sv_fire_charge"}}, -- Martyr's Pyre
	[177] = {fx = {fire_ring = "sv_fire_charge"}}, -- Pyre of Absolution
	-- death
	[106] = {missile = {skull_orb = "sv_death_skull"}, fx = {necro_skull = "sv_death_wail"}}, -- Marrow Bolt: skull and its wail
	[183] = {fx = {toxic_burst = "sv_death_decay"}}, -- Soul Rot
	[184] = {fx = {lich_soul_drain = "sv_death_lifesteal"}}, -- Life Siphon
	[203] = {fx = {blood_nova = "sv_death_blood_splash"}}, -- Crimson Covenant
	[42] = {fx = {bone_burst = "sv_death_nova"}}, -- Grave Nova
	[160] = {fx = {bone_burst = "sv_death_nova"}}, -- Funeral of Kings
	[185] = {fx = {px448_green = "sv_death_corpse_burst", bone_burst = "sv_death_corpse_burst"}}, -- Corpse Explosion
	[119] = {fx = {bone_burst = "sv_death_bone_prison"}}, -- Crypt Collapse
	[120] = {fx = {bone_aura = "sv_death_bone_spikes"}}, -- Ossuary Surge
	[193] = {fx = {bone_burst = "sv_death_bone_shatter"}}, -- Splinter Volley
	[197] = {fx = {bone_burst = "sv_death_bone_shatter"}}, -- Bone Shrapnel
	[180] = {fx = {necro_seal = "sv_death_raise"}}, -- Raise Dead
	[192] = {fx = {necro_seal = "sv_death_raise"}}, -- Raise Bone Warrior
	[40] = {fx = {necro_seal = "sv_death_raise"}}, -- Raise Bone Archer
	[176] = {fx = {necro_seal = "sv_death_raise"}}, -- Raise Bone Mage
	[182] = {fx = {cursed = "sv_death_mark", necro_skull = "sv_curse_strike"}}, -- Withering Curse (its bolt 132 is rebuilt in place)
	[112] = {fx = {necro_seal = "sv_curse_nova"}}, -- Gravewail
	[43] = {fx = {shadow_smoke = "sv_shadow_burst"}}, -- Dreamrot
	-- poison
	[113] = {fx = {poison_flame = "sv_venom_splash"}}, -- Blightbrand
	[57] = {missile = {venom_glob = "sv_venom_glob"}, fx = {poison_ring = "sv_poison_cloud"}}, -- Venom Spiral
	[23] = {fx = {poison_burst = "sv_venom_splash"}}, -- Packhunter's Dart
	[207] = {fx = {toxic_burst = "sv_plague_burst"}}, -- Blightswarm
	-- holy: the lance and its hit
	[214] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_hit = "sv_holy_lance_hit"}}, -- Dawnpiercer
	[19] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_hit = "sv_holy_lance_hit"}}, -- Sunspear
	[129] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_hit = "sv_holy_lance_hit"}}, -- Lance of Vigil
	[138] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_hit = "sv_holy_lance_hit"}}, -- Heretic's Brand
	[151] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_hit = "sv_holy_lance_hit"}}, -- Dawnbreaker Shot
	[144] = {missile = {holy_spear = "sv_holy_lance"}}, -- Twin Verdict
	[198] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_smite = "sv_holy_sword"}}, -- Judgement
	[218] = {missile = {holy_spear = "sv_holy_lance"}, fx = {holy_smite = "sv_holy_pillar"}}, -- Final Verdict
	[189] = {fx = {px652_white = "sv_holy_bolt_hit"}}, -- Radiant Smite
	-- holy: ground, wards, heals
	[190] = {fx = {holy_seal = "sv_holy_consecration"}}, -- Consecration
	[216] = {fx = {holy_seal = "sv_holy_consecration"}}, -- Blessed Earth
	[137] = {fx = {holy_seal = "sv_holy_ground"}}, -- Sanctified Ground
	[128] = {fx = {dome_blast_holy = "sv_holy_nova"}}, -- Bell of Reckoning
	[237] = {fx = {dome_blast_holy = "sv_holy_nova"}}, -- Hammer of Ember Dawn
	[252] = {fx = {dawn_aegis = "sv_holy_shield"}}, -- Aegis of Faith
	[217] = {fx = {dawn_aegis = "sv_holy_shield"}}, -- Lightward
	[178] = {fx = {big_sanctum_holy_5 = "sv_holy_blessing"}}, -- Mantle of Dawn
	[253] = {fx = {healing_bloom = "sv_heal_splash"}}, -- Lay on Hands
	[191] = {fx = {healing_bloom = "sv_heal_burst", holy_spiral = "sv_heal_regen"}}, -- Vow of Mending
	[208] = {fx = {healing_bloom = "sv_heal_burst"}}, -- Purifying Wellspring
	[96] = {fx = {regenerating = "sv_heal_regen", heal_sparkle = "sv_heal_ribbon"}}, -- Mirror Mend: the caster, then the mirror image
	-- energy and arcane
	[24] = {fx = {blast_lightning = "sv_storm_spark", arcane_burst = "sv_arcane_implosion"}}, -- Phantom Needles
	[152] = {fx = {arcane_burst = "sv_arcane_implosion", arcane_hit = "sv_storm_strike"}}, -- Prismatic Rupture
	[231] = {fx = {arcane_circle = "sv_arcane_sigil", void_rift = "sv_arcane_rift"}}, -- Tear in the Weave
	[234] = {fx = {shield_bubble = "sv_arcane_bubble"}}, -- Soulward
}

-- a spell of one element that is given a piece of another, with the reason (server/tests/spell_vfx_test.lua holds every other
-- spell to its element; tools/ci/check_spell_fx.py measures with the gate off, so these rows cannot live in spell_fx_allow.csv)
C.allow = {
	[127] = {sv_fire_charge = "a holy fire: the martyr burns in gold-white flame"}, -- Martyr's Pyre
	[177] = {sv_fire_charge = "a holy fire: the pyre of the absolved"}, -- Pyre of Absolution
	[113] = {sv_venom_splash = "a brand of blight: the death spell poisons"}, -- Blightbrand
	[24] = {sv_arcane_implosion = "the energy line is drawn as arcane light"}, -- Phantom Needles
	[152] = {sv_arcane_implosion = "the energy line is drawn as arcane light"}, -- Prismatic Rupture
	[231] = {sv_arcane_sigil = "the weave is arcane: the sigil the tear opens on", sv_arcane_rift = "the weave is arcane: the tear itself"}, -- Tear in the Weave
}

-- the piece for a spell id, kind and asked name, or nil (pure: no gate, no ids)
function C.pick(spellId, kind, name)
	local s = spellId and C.spells[spellId]
	local k = s and s[kind]
	return k and type(name) == "string" and k[name] or nil
end

-- the gate on and the ids known: the generated table is merged once into ChaosVfx / ChaosVfxMissile
function C.live()
	if not C.ON then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if not ChaosSpellVfxIds and dofile then
			pcall(dofile, "data/lib/chaos_spell_vfx_ids.lua")
		end
		local I = ChaosSpellVfxIds
		if I and ChaosVfx and ChaosVfxMissile then
			for name, e in pairs(I.effects) do
				ChaosVfx[name] = {id = e.id, dx = e.dx, dy = e.dy, ms = e.ms}
			end
			for name, e in pairs(I.missiles) do
				ChaosVfxMissile[name] = {id = e.id, dx = e.dx, dy = e.dy}
			end
			C.loaded = true
		end
	end
	return C.loaded
end

-- the piece spell `spellId` sends in place of `name` of `kind`, or nil (gate off, no entry, the id not known)
function C.swapFor(spellId, kind, name)
	local alt = C.pick(spellId, kind, name)
	if not alt or not C.live() then
		return nil
	end
	if kind == "missile" then
		return ChaosVfxMissile[alt] and alt or nil
	end
	return ChaosVfx[alt] and alt or nil
end

ChaosSpellVfx = C
return C
