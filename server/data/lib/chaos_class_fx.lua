-- Class signature effects (ROADMAP C4 "effects"): which spell of which class sends which effect of its own.
-- The art: client/tools/sprites/gen_class_fx.py (art_import/class_fx.csv), appended to the client pair things_custom22
-- by import_fx_art.py, which writes the ids to data/lib/chaos_class_fx_ids.lua.
--
-- Pair switch (C.PAIR22_FX): on since 2026-10-12 (things_custom22 on windows-assets, 13e289c7). Off, nothing
-- changes: the ids file is not loaded and every spell sends the effects it sent before. On, during a cast (the
-- supports wrapper knows the caster and the spell, also in the cast's addEvent callbacks) an effect name in C.swaps
-- for the caster's class and spell is sent as the class effect instead (ChaosSpell.fx / vfx and the wrapped Fx in
-- data/spells/chaos/_common.lua). A cosmetic spell skin the player chose wins over the class effect.
-- Lua 5.1 / LuaJIT / 5.3.

ChaosClassFx = ChaosClassFx or {}
local C = ChaosClassFx

C.PAIR22_FX = true

-- vocation id -> class key (Chaos.classes.ids in chaos_constants.lua; checked by tests/class_fx_test.lua)
C.vocations = {
	[4] = "warrior", [8] = "juggernaut", [14] = "berserker",
	[3] = "ranger", [7] = "deadeye", [15] = "beastmaster",
	[1] = "mystic", [5] = "elementalist", [10] = "illusionist",
	[11] = "thief", [12] = "ninja", [13] = "samurai",
	[20] = "necromancer", [21] = "lich", [22] = "bonelord",
	[17] = "monk", [18] = "shadowfist", [19] = "ironsage",
	[23] = "templar", [24] = "inquisitor", [25] = "sentinel",
}
-- class key -> its line (the base class): a class takes its line's swaps, its own ones win
C.lineOf = {
	warrior = "warrior", juggernaut = "warrior", berserker = "warrior",
	ranger = "ranger", deadeye = "ranger", beastmaster = "ranger",
	mystic = "mystic", elementalist = "mystic", illusionist = "mystic",
	thief = "thief", ninja = "thief", samurai = "thief",
	necromancer = "necromancer", lich = "necromancer", bonelord = "necromancer",
	monk = "monk", shadowfist = "monk", ironsage = "monk",
	templar = "templar", inquisitor = "templar", sentinel = "templar",
}

-- class key -> spell id -> {effect name the spell sends = the class effect}
C.swaps = {
	warrior = {
		[220] = {whirlwind = "warrior_gyre"},            -- Reaping Gyre
		[221] = {earth_spikes = "warrior_quake"},        -- Earthbreaker
		[223] = {aura_burst_gold = "warrior_bellow"},    -- Iron Bellow
		[225] = {earth_spikes = "warrior_quake"},        -- Colossus Fall
	},
	juggernaut = {
		[223] = {aura_burst_gold = "juggernaut_bulwark"}, -- Iron Bellow
	},
	berserker = {
		[222] = {aura_burst_red = "berserker_rage"},     -- Red Frenzy
		[246] = {ground_slam = "berserker_cleave"},      -- Skyfall Cleave (the landing spot)
		[247] = {aura_burst_red = "berserker_rage"},     -- Bloodrage
	},
	ranger = {
		[214] = {holy_hit = "ranger_pierce"},            -- Dawnpiercer
		[216] = {holy_seal = "ranger_thornseal"},        -- Blessed Earth
		[217] = {dawn_aegis = "ranger_canopy"},          -- Lightward
		[219] = {holy_smite = "ranger_arrowfall"},       -- Hail of Dawn (each tile)
	},
	deadeye = {
		[218] = {holy_smite = "deadeye_mark"},           -- Final Verdict (the impact; the hit effect stays)
	},
	beastmaster = {
		[248] = {teleport_in = "beast_spirit"},          -- Wild Bond (each companion)
	},
	mystic = {
		[208] = {heal_sparkle = "mystic_mend"},          -- Purifying Wellspring (each healed ally; the caster keeps
		                                                 -- the pack healing_bloom)
		[226] = {arcane_sigil = "illusion_mirror"},      -- Hall of Mirrors
		[227] = {shade_vanish = "illusion_shatter", shade_appear = "illusion_shatter"}, -- Umbral Stride
	},
	elementalist = {
		[204] = {infernal_seal = "elementalist_glyph"},  -- Falling Pyre (the mark)
	},
	illusionist = {
		[96] = {heal_sparkle = "mystic_mend"},           -- Mirror Mend (the mirror heal; the healed ally gets the
		                                                 -- pack regenerating)
	},
	thief = {
		[98] = {shade_vanish = "thief_vanish"},          -- Shadow Mend
		[238] = {shade_vanish = "thief_vanish"},         -- Shadow Veil
	},
	ninja = {
		[240] = {shade_vanish = "ninja_vanish", shade_appear = "ninja_vanish"}, -- Shadow Step
		[73] = {whirlwind = "ninja_vanish"},            -- Blade Flurry (an ink slash through the spin)
		[241] = {shadow_smoke = "ninja_smoke"},          -- Smoke Bomb (each tile)
	},
	samurai = {
		[243] = {shield_bubble = "samurai_parry"},       -- Counter Stance
		[73] = {whirlwind = "samurai_parry"},           -- Blade Flurry (a crescent of steel)
		[245] = {aura_burst_gold = "samurai_focus"},     -- Bushido Focus
	},
	necromancer = {
		[182] = {cursed = "necro_curse"},                -- Withering Curse
	},
	lich = {
		[183] = {toxic_burst = "lich_rot"},              -- Soul Rot
	},
	monk = {
		[65] = {whirlwind = "monk_heel"},                -- Whirling Heel
	},
	shadowfist = {
		[68] = {void_eye = "shadowfist_mark"},           -- Pressure Points
	},
	ironsage = {
		[70] = {shield_bubble = "ironsage_ward"},        -- Chi Ward
	},
	templar = {
		[191] = {healing_bloom = "templar_mend"},        -- Vow of Mending
	},
	inquisitor = {
		[250] = {aura_burst_gold = "inquisitor_zeal"},   -- Zealotry
	},
	sentinel = {
		[252] = {dawn_aegis = "sentinel_aegis"},         -- Aegis of Faith
		[253] = {healing_bloom = "templar_mend"},        -- Lay on Hands
	},
}

-- effects drawn for the snares and vigils (art in the pair, sent by nothing yet: their scripts send stock effects).
-- C.send(pos, name, fallback) is the call for them once the switch is on.
C.unwired = {"snare_jaws", "snare_blast", "vigil_wrath", "vigil_iron", "vigil_haste", "vigil_clarity"}

-- the class effect for a class key, spell id and effect name, or nil (pure: no switch, no ids)
function C.pick(classKey, spellId, name)
	if not classKey or not spellId or type(name) ~= "string" then
		return nil
	end
	local own = C.swaps[classKey]
	local alt = own and own[spellId] and own[spellId][name]
	if alt then
		return alt
	end
	local line = C.lineOf[classKey]
	local base = line and line ~= classKey and C.swaps[line]
	return base and base[spellId] and base[spellId][name] or nil
end

-- the switch on and the ids known (chaos_class_fx_ids.lua loaded once into ChaosVfx)
function C.live()
	if not C.PAIR22_FX then
		return false
	end
	if C.loaded == nil then
		C.loaded = false
		if ChaosVfx and ChaosVfx.warrior_quake then
			C.loaded = true
		else
			local ok = pcall(dofile, "data/lib/chaos_class_fx_ids.lua")
			C.loaded = ok and ChaosVfx ~= nil and ChaosVfx.warrior_quake ~= nil
		end
	end
	return C.loaded
end

-- the class effect for player id `pid` casting spell `spellId`, or nil (switch off, no player, no swap, no id)
function C.swapFor(pid, spellId, name)
	if not C.live() then
		return nil
	end
	local player = Player and Player(pid)
	local voc = player and player:getVocation()
	local key = voc and C.vocations[voc:getId()]
	local alt = C.pick(key, spellId, name)
	return alt and ChaosVfx and ChaosVfx[alt] and alt or nil
end

-- send a class effect at its offset tile; the stock `fallback` when the switch is off or the name is unknown
function C.send(pos, name, fallback)
	if C.live() and Vfx and Vfx(pos, name) then
		return true
	end
	if fallback and pos then
		Position(pos):sendMagicEffect(fallback)
	end
	return false
end
