-- Boss mechanics (boss_mechanics.lua, boss_mechanics_core.lua): every number. Plain data, no engine calls
-- (tests/boss_mechanics_test.lua and tools/gen_wiki_data.lua read it). Lua 5.1 / LuaJIT and Lua 5.3.
-- Overview and the per-boss table: server/README.md "Boss mechanics".
--
-- A profile (key = the boss's shown name in lower case, or a role key such as "rift_guardian"):
--   label       the short name in the warnings ("%s" of a text)
--   size        the boss's footprint (1, 2 or 4 tiles a side): the shapes grow with it (boss_mechanics_core G.scaleShape)
--   difficulty  0..1: the warning time 3.0 s at 0 down to 1.5 s at 1 (0-0.33: the default 2.5-3 s); enraged +0.3
--   fair        refLevel: the walking speed the fairness check assumes (a player of that level, vocation base 220, no
--               haste, normal ground: data/lib/chaos_speed.lua); reactionMs: the time to see a mark and start moving
--   every       ms between two telegraphs (x (1 - 0.25 x difficulty)), never less than the warning + gapMs
--   telegraphs  {key, label, kind (G.SHAPES), sizes, share (of max health, to whoever stands on a marked tile at the
--               hit), hit (effect name), fallback (stock effect), tip (counterplay, for the wiki and the README)}
--   adds        phases at health fractions: mode immune (no damage while they live) | shield (reduce) | empower (the
--               boss hits perAdd harder per living add) | heal (perAdd of max health per living add every 5 s);
--               type = the monster type spawned (renamed to `name`), count + perPlayer x (players - 1), health
--   timed       channel (a cast of channelMs; a totem appears; kill it to stop the hit), soak (a circle: stand in it to
--               split total share; nobody in it: everyone takes missShare), los (a room-wide blast after hideMs; hide
--               behind a pillar); every = ms between two, below = from this health fraction on
--   softEnrage  from `at` seconds on the boss hits +perMin per minute harder, at most maxMult
--   debuff      stacks on the boss's target with each hit (at most one per everyMs): +perStack damage taken from the
--               boss each, one falls off per decayMs
--   ref         the balance reference (G.balance): health, heal per second, dps, uptime, players, limit (seconds);
--               solo = true: content meant for one player (no mechanic may need two); weakDps: the weakest damage that
--               must keep its old time too (the weakest class at level 1000, 1,950)
--
-- Stock monster types used for the adds and totems (renamed with Chaos.createMonsterNamed): Hex Effigy (immobile,
-- health set here). The effect names are data/lib/chaos_vfx.lua, chaos_pack_fx_ids.lua and chaos_big_fx_ids.lua
-- (pair 24, effects 628-655); a missing one falls back to the stock effect.

local WARD = "Hex Effigy" -- the immobile totem of the raid, reused (its own scripts are the raid's; here it only stands)

return {
	enabled = true,
	tickMs = 250,
	opcodeAction = "mech", -- on ChaosOpcodes.monsterbar (125): the cast bar of game_monsterbar
	warnEffect = "warning_zone", -- the danger pulse
	fillEffect = "warning_fill", -- the last pulse before the hit
	pulseMs = 600, fillMs = 900,
	soakEffect = "holy_seal", losEffect = "big_shock_frost_7", pillarId = 1514, totemEffect = "teleport_in",
	-- the default fairness: a level 300 player, half a second to react
	fair = {refLevel = 300, reactionMs = 500, pulseMs = 600, fillMs = 900},

	profiles = {
		-- ================================================================ world bosses (group, 45 minutes)
		["kaelgor the infernal warlord"] = {
			label = "Kaelgor", size = 2, element = "fire", difficulty = 0.2, every = 10000,
			fair = {refLevel = 300},
			telegraphs = {
				{key = "meteor_rain", label = "Meteor Rain", kind = "puddles", count = 3, perPlayer = 0.4, maxCount = 12,
					onPlayers = 4, radius = 1, share = 0.35, hit = "meteor_strike", fallback = "CONST_ME_FIREAREA",
					tip = "Red circles land under four players and around the arena: step off them."},
				{key = "hellfire_breath", label = "Hellfire Breath", kind = "cone", length = 8, spread = 3, share = 0.5,
					hit = "fire_explosion", fallback = "CONST_ME_FIREAREA",
					tip = "A cone towards his target: tank to the side, everyone else behind him."}
			},
			adds = {
				{at = 0.55, mode = "immune", type = WARD, name = "Infernal Wardstone", count = 3, health = 400000,
					healthPerExtra = 0.05, text = "%s is shielded by 3 Infernal Wardstones! Break them!",
					doneText = "The wards are broken: %s can be hurt again!",
					tip = "At 55% he takes no damage until the 3 Infernal Wardstones die."}
			},
			softEnrage = {at = 1800, perMin = 0.08, maxMult = 2.0, text = "%s burns hotter with every minute!"},
			ref = {health = 18000000, heal = 1200, dps = 26000, uptime = 1, players = 10, limit = 2700}
		},
		["skaldra the rime queen"] = {
			label = "Skaldra", size = 2, element = "ice", difficulty = 0.2, every = 10000,
			fair = {refLevel = 300},
			telegraphs = {
				{key = "rime_breath", label = "Rime Breath", kind = "line", halfWidth = 1, length = 14, share = 0.5,
					hit = "frost_nova", fallback = "CONST_ME_ICEAREA",
					tip = "A three-wide beam towards her target, wall to wall: step out sideways."},
				{key = "glacial_ring", label = "Glacial Ring", kind = "ring", inner = 3, outer = 8, share = 0.45,
					hit = "ice_shatter", fallback = "CONST_ME_ICEAREA",
					tip = "A ring of ice: hug her (inside 3 sqm) or run far out."}
			},
			timed = {
				{key = "absolute_zero", label = "Absolute Zero", kind = "los", hideMs = 3500, every = 50000, below = 0.8,
					share = 0.7, pillars = {{-4, -4}, {4, -4}, {-4, 4}, {4, 4}}, hit = "big_shock_frost_7",
					fallback = "CONST_ME_ICEAREA", text = "%s draws the cold into her! Hide behind a pillar!",
					tip = "Ice pillars rise round her: break line of sight behind one before the blast."}
			},
			ref = {health = 16000000, heal = 1200, dps = 26000, uptime = 1, players = 10, limit = 2700}
		},
		["the rotmother"] = {
			label = "The Rotmother", size = 2, element = "earth", difficulty = 0.2, every = 10000,
			fair = {refLevel = 300},
			telegraphs = {
				{key = "creeping_bile", label = "Creeping Bile", kind = "follow", radius = 2, followMs = 1500, share = 0.45,
					hit = "toxic_burst", fallback = "CONST_ME_GREEN_RINGS",
					tip = "A circle follows her target, then stops: walk out once it stops moving."},
				{key = "spore_field", label = "Spore Field", kind = "puddles", count = 5, perPlayer = 0.3, maxCount = 12,
					radius = 1, share = 0.3, hit = "venom_splash", fallback = "CONST_ME_GREEN_RINGS",
					tip = "Spore patches all over the arena: find a clear tile."}
			},
			adds = {
				{at = 0.6, mode = "heal", perAdd = 0.004, type = WARD, name = "Plague Heart", count = 3, health = 300000,
					healthPerExtra = 0.05, text = "Plague Hearts pulse: they feed %s while they beat!",
					doneText = "The Plague Hearts are still.",
					tip = "At 60% three Plague Hearts heal her 0.4% each per 5 s: kill them first."}
			},
			debuff = {key = "festering", label = "Festering", perStack = 0.05, max = 8, everyMs = 2000, decayMs = 6000,
				tip = "Her hits stack Festering (+5% damage taken each): swap tanks or step away for a few seconds."},
			ref = {health = 22000000, heal = 2500, dps = 26000, uptime = 1, players = 10, limit = 2700}
		},
		["nyxareth the void archon"] = {
			label = "Nyxareth", size = 2, element = "death", difficulty = 0.25, every = 10000,
			fair = {refLevel = 300},
			telegraphs = {
				{key = "void_cross", label = "Void Cross", kind = "cross", halfWidth = 1, share = 0.5,
					hit = "shadow_eruption", fallback = "CONST_ME_MORTAREA",
					tip = "Two beams through him, wall to wall: stand on a diagonal."}
			},
			timed = {
				{key = "event_horizon", label = "Event Horizon", kind = "soak", radius = 2, total = 1.6, min = 3,
					missShare = 0.6, every = 40000, below = 0.9, hit = "big_rift_void_7", fallback = "CONST_ME_MORTAREA",
					groupOnly = true, text = "%s opens an Event Horizon! Stand in the circle together!",
					tip = "A circle opens: at least three players stand in it to split the hit; nobody in it hurts everyone."},
				{key = "oblivion", label = "Oblivion", kind = "channel", channelMs = 9000, every = 55000, below = 0.6,
					totemType = WARD, totemName = "Void Anchor", totemHealth = 120000, totemPerExtra = 0.05, share = 0.6,
					hit = "big_nova_void_7", fallback = "CONST_ME_MORTAREA",
					text = "%s channels Oblivion! Destroy the Void Anchor!",
					tip = "A Void Anchor appears while he channels: kill it before the cast bar ends."}
			},
			ref = {health = 15000000, heal = 1200, dps = 26000, uptime = 1, players = 10, limit = 2700}
		},
		["vharok the blood colossus"] = {
			label = "Vharok", size = 2, element = "physical", difficulty = 0.2, every = 10000,
			fair = {refLevel = 300},
			telegraphs = {
				{key = "crimson_cleave", label = "Crimson Cleave", kind = "cone", length = 6, spread = 4, share = 0.5,
					hit = "blunt_smash", fallback = "CONST_ME_DRAWBLOOD",
					tip = "A wide cone in front: only his target and those beside it should be there, and then step aside."},
				{key = "quake", label = "Quake", kind = "circle", radius = 4, share = 0.4, hit = "big_shock_blood_9",
					fallback = "CONST_ME_GROUNDSHAKER", tip = "Everything within 4 sqm of him: back off."}
			},
			adds = {
				{at = 0.5, mode = "empower", perAdd = 0.15, type = WARD, name = "Blood Idol", count = 3, health = 350000,
					healthPerExtra = 0.05, text = "Blood Idols rise: %s grows stronger while they stand!",
					doneText = "The Blood Idols crumble.",
					tip = "At 50% three Blood Idols give him +15% damage each: kill them."}
			},
			debuff = {key = "hemorrhage", label = "Hemorrhage", perStack = 0.04, max = 10, everyMs = 2000, decayMs = 6000,
				tip = "His hits stack Hemorrhage (+4% damage taken each): swap tanks."},
			ref = {health = 24000000, heal = 3200, dps = 26000, uptime = 1, players = 10, limit = 2700}
		},

		-- ================================================================ Omen guardians (solo-able, 12 minutes)
		["sangrith the bloodmoon herald"] = {
			label = "Sangrith", size = 4, element = "physical", difficulty = 0.25, every = 9000,
			fair = {refLevel = 800},
			telegraphs = {
				{key = "red_crescent", label = "Red Crescent", kind = "cone", length = 6, spread = 3, share = 0.4,
					hit = "px197_crimson", fallback = "CONST_ME_DRAWBLOOD",
					tip = "A cone towards you: step around him."},
				{key = "blood_moon", label = "Blood Moon", kind = "follow", radius = 2, followMs = 1500, share = 0.35,
					hit = "bleeding", fallback = "CONST_ME_DRAWBLOOD",
					tip = "The red moon follows you, then stops: walk out of it."}
			},
			adds = {
				{at = 0.5, mode = "immune", type = WARD, name = "Bloodmoon Wardstone", count = 2, health = 25000,
					healthPerExtra = 1.0, text = "%s hides behind 2 Bloodmoon Wardstones!",
					doneText = "The wardstones crack: %s bleeds again!",
					tip = "At 50% he is immune until his 2 Wardstones die (about 10 s each alone)."}
			},
			ref = {health = 500000, heal = 355, dps = 2600, uptime = 0.75, players = 1, limit = 720, solo = true, weakDps = 1950}
		},
		["morvane the hollow crown"] = {
			label = "Morvane", size = 4, element = "death", difficulty = 0.25, every = 9000,
			fair = {refLevel = 800},
			telegraphs = {
				{key = "crown_cross", label = "Crown's Cross", kind = "cross", halfWidth = 1, share = 0.4,
					hit = "shadow_eruption", fallback = "CONST_ME_MORTAREA", tip = "Beams through him: stand on a diagonal."},
				{key = "hollow_ring", label = "Hollow Ring", kind = "ring", inner = 2, outer = 6, share = 0.4,
					hit = "shadow_hit", fallback = "CONST_ME_MORTAREA", tip = "A ring: hug him or run out past it."}
			},
			timed = {
				{key = "dirge", label = "Dirge of the Empty Throne", kind = "channel", channelMs = 10000, every = 60000,
					below = 0.75, totemType = WARD, totemName = "Hollow Totem", totemHealth = 12000, totemPerExtra = 1.0,
					share = 0.5, hit = "big_nova_void_7", fallback = "CONST_ME_MORTAREA",
					text = "%s sings the Dirge! Destroy the Hollow Totem!",
					tip = "A Hollow Totem rises while he sings: kill it (about 8 s alone) before the cast ends."}
			},
			ref = {health = 500000, heal = 355, dps = 2600, uptime = 0.75, players = 1, limit = 720, solo = true, weakDps = 1950}
		},
		["thalcyra the stormbound seer"] = {
			label = "Thalcyra", size = 4, element = "energy", difficulty = 0.25, every = 9000,
			fair = {refLevel = 800},
			telegraphs = {
				{key = "storm_marks", label = "Storm Marks", kind = "puddles", count = 3, onPlayers = 5, radius = 1,
					share = 0.35, hit = "lightning_strike", fallback = "CONST_ME_ENERGYAREA",
					tip = "Bolts on you and around: step off the marks."},
				{key = "sky_lance", label = "Sky Lance", kind = "line", halfWidth = 0, length = 12, share = 0.45,
					hit = "lightning_hit", fallback = "CONST_ME_ENERGYAREA", tip = "A line towards you: one step sideways."}
			},
			timed = {
				{key = "skyfall", label = "Skyfall", kind = "los", hideMs = 3500, every = 55000, below = 0.7, share = 0.6,
					pillars = {{-4, 0}, {4, 0}, {0, 4}}, hit = "big_lightning_burst_7", fallback = "CONST_ME_ENERGYAREA",
					text = "%s calls down the sky! Hide behind a pillar!",
					tip = "Stone pillars rise: put one between you and her before the sky falls."}
			},
			ref = {health = 500000, heal = 355, dps = 2600, uptime = 0.75, players = 1, limit = 720, solo = true, weakDps = 1950}
		},

		-- ================================================================ Ascended Omens and the Cinderheart (uber.lua)
		-- Their telegraphs, hazards, adds and Harvest stay uber.lua's (the shapes and pulses now come from the core);
		-- these profiles add the mechanics below. uber.lua's own enrage stays the hard one.
		["ascended sangrith"] = {
			label = "Sangrith", size = 4, element = "physical", difficulty = 0.4, ownTelegraphs = true,
			fair = {refLevel = 900},
			adds = {
				{at = 0.5, mode = "immune", type = WARD, name = "Sanguine Wardstone", count = 2, health = 45000,
					healthPerExtra = 1.0, text = "%s is warded by 2 Sanguine Wardstones!", doneText = "The wards fall!",
					tip = "At 50% he is immune until the 2 Sanguine Wardstones die."}
			},
			debuff = {key = "blood_price", label = "Blood Price", perStack = 0.04, max = 8, everyMs = 2500, decayMs = 6000,
				tip = "Every hit stacks Blood Price (+4% damage taken): step out for a few seconds to let it fall off."},
			ref = {health = 1200000, dps = 3000, uptime = 0.75, players = 1, limit = 840, solo = true, weakDps = 1950}
		},
		["ascended morvane"] = {
			label = "Morvane", size = 4, element = "death", difficulty = 0.4, ownTelegraphs = true,
			fair = {refLevel = 900},
			timed = {
				{key = "dirge", label = "Dirge of the Empty Throne", kind = "channel", channelMs = 9000, every = 60000,
					below = 0.8, totemType = WARD, totemName = "Hollow Totem", totemHealth = 15000, totemPerExtra = 1.0,
					share = 0.6, hit = "big_nova_void_7", fallback = "CONST_ME_MORTAREA",
					text = "%s sings the Dirge! Destroy the Hollow Totem!", tip = "Kill the Hollow Totem before the cast ends."},
				{key = "crown_of_night", label = "Crown of Night", kind = "los", hideMs = 3500, every = 70000, below = 0.5,
					share = 0.6, pillars = {{-4, 0}, {4, 0}, {0, 5}}, hit = "big_nova_void_7", fallback = "CONST_ME_MORTAREA",
					text = "%s raises the Crown of Night! Hide behind a pillar!", tip = "Hide behind a pillar."}
			},
			ref = {health = 1200000, dps = 3000, uptime = 0.75, players = 1, limit = 840, solo = true, weakDps = 1950}
		},
		["ascended thalcyra"] = {
			label = "Thalcyra", size = 4, element = "energy", difficulty = 0.4, ownTelegraphs = true,
			fair = {refLevel = 900},
			timed = {
				{key = "skyfall", label = "Skyfall", kind = "los", hideMs = 3500, every = 60000, below = 0.8, share = 0.6,
					pillars = {{-4, 0}, {4, 0}, {0, 5}}, hit = "big_lightning_burst_7", fallback = "CONST_ME_ENERGYAREA",
					text = "%s calls down the sky! Hide behind a pillar!", tip = "Hide behind a pillar."},
				{key = "conduit", label = "Conduit", kind = "soak", radius = 2, total = 0.6, min = 1, missShare = 0.45,
					every = 45000, below = 0.6, hit = "big_lightning_burst_7", fallback = "CONST_ME_ENERGYAREA",
					text = "%s charges a Conduit! Stand in the circle!",
					tip = "Stand in the circle: alone you take 60% of your health, a party splits it; nobody in it: 45% to all."}
			},
			ref = {health = 1200000, dps = 3000, uptime = 0.75, players = 1, limit = 840, solo = true, weakDps = 1950}
		},
		["ysgrath the cinderheart"] = {
			label = "Ysgrath", size = 4, element = "fire", difficulty = 0.45, ownTelegraphs = true,
			fair = {refLevel = 1000},
			adds = {
				{at = 0.6, mode = "immune", type = WARD, name = "Cinder Wardstone", count = 3, health = 40000,
					healthPerExtra = 1.0, text = "%s draws 3 Cinder Wardstones about it!", doneText = "The Cinder Wardstones shatter!",
					tip = "At 60% it is immune until the 3 Cinder Wardstones die."}
			},
			timed = {
				{key = "last_light", label = "The Last Light", kind = "channel", channelMs = 9000, every = 60000, below = 0.3,
					totemType = WARD, totemName = "Ember Totem", totemHealth = 15000, totemPerExtra = 1.0, share = 0.7,
					hit = "big_nova_fire_9", fallback = "CONST_ME_FIREAREA",
					text = "%s is gathering flame! Destroy the Ember Totem!", tip = "Kill the Ember Totem before the cast ends."}
			},
			debuff = {key = "cinderburn", label = "Cinderburn", perStack = 0.04, max = 8, everyMs = 2500, decayMs = 6000,
				tip = "Its hits stack Cinderburn (+4% damage taken): let it fall off between pulls."},
			ref = {health = 1650000, dps = 3000, uptime = 0.75, players = 1, limit = 1200, solo = true, weakDps = 1950}
		},

		-- ================================================================ rift guardians (light, by tier)
		-- one profile for every rift guardian (rift.lua attaches it with the rift's tier): circles and cones from tier
		-- 1, puddles from tier 8, a shield phase from tier 12. The difficulty is 0.04 x (tier - 1) x 0.5 (3.0 s at tier 1,
		-- 2.6 s at tier 15).
		rift_guardian = {
			label = "The guardian", size = 4, element = "physical", difficulty = 0, tierDifficulty = 0.02, every = 11000,
			fair = {refLevel = 300},
			telegraphs = {
				{key = "guardian_slam", label = "Guardian Slam", kind = "circle", radius = 2, share = 0.3,
					hit = "blunt_smash", fallback = "CONST_ME_GROUNDSHAKER", tip = "Back away from the guardian."},
				{key = "guardian_sweep", label = "Guardian Sweep", kind = "cone", length = 5, spread = 2, share = 0.3,
					hit = "blunt_smash", fallback = "CONST_ME_GROUNDSHAKER", tip = "Step to its side."},
				{key = "rift_scatter", label = "Rift Scatter", kind = "puddles", count = 2, onPlayers = 5, radius = 1,
					share = 0.25, minTier = 8, hit = "shadow_hit", fallback = "CONST_ME_MORTAREA",
					tip = "Tier 8+: marks under you: step off."}
			},
			adds = {
				{at = 0.5, mode = "shield", reduce = 0.6, minTier = 12, type = WARD, name = "Rift Anchor", count = 2,
					health = 30000, healthPerExtra = 1.0, text = "%s anchors itself: kill the 2 Rift Anchors!",
					doneText = "The anchors break!", tip = "Tier 12+: at 50% it takes 60% less damage until 2 Rift Anchors die."}
			},
			ref = {health = 300000, dps = 2180, uptime = 0.8, players = 1, solo = true, tier = 15}
		},

		-- ================================================================ the Hollow Vault (dungeon, solo, 30 minutes)
		["vault keeper ossrim"] = {
			label = "Ossrim", size = 2, element = "physical", difficulty = 0.1, every = 10000,
			fair = {refLevel = 800},
			telegraphs = {
				{key = "vault_slam", label = "Vault Slam", kind = "circle", radius = 3, share = 0.4, hit = "big_shock_blood_9",
					fallback = "CONST_ME_GROUNDSHAKER", tip = "Everything within 3 sqm: back off."},
				{key = "rolling_stones", label = "Rolling Stones", kind = "line", halfWidth = 1, length = 10, share = 0.35,
					hit = "earth_spikes", fallback = "CONST_ME_STONES", tip = "A three-wide line towards you: sidestep."}
			},
			adds = {
				{at = 0.5, mode = "shield", reduce = 0.75, type = WARD, name = "Vault Warden", count = 2, health = 40000,
					healthPerExtra = 0, text = "%s seals the vault: break the 2 Vault Wardens!", doneText = "The seal breaks!",
					tip = "At 50% he takes 75% less damage until the 2 Vault Wardens die."}
			},
			ref = {health = 1130000, dps = 2180, uptime = 1, players = 1, limit = 1800, solo = true}
		},

		-- ================================================================ generated areas' bosses (open world)
		["the emberdeep maw"] = {
			label = "The Maw", size = 2, element = "fire", difficulty = 0.15, every = 10000,
			fair = {refLevel = 1000},
			telegraphs = {
				{key = "magma_cone", label = "Magma Spew", kind = "cone", length = 6, spread = 3, share = 0.4,
					hit = "fire_explosion", fallback = "CONST_ME_FIREAREA", tip = "Step to its side."},
				{key = "ember_rain", label = "Ember Rain", kind = "puddles", count = 4, onPlayers = 4, radius = 1, share = 0.3,
					hit = "meteor_strike", fallback = "CONST_ME_FIREAREA", tip = "Step off the circles."}
			},
			ref = {health = 1640000, dps = 2600, uptime = 1, players = 1, solo = true}
		},
		["the ossuary warden"] = {
			label = "The Warden", size = 2, element = "death", difficulty = 0.15, every = 10000,
			fair = {refLevel = 1100},
			telegraphs = {
				{key = "bone_ring", label = "Bone Ring", kind = "ring", inner = 2, outer = 6, share = 0.4,
					hit = "shadow_eruption", fallback = "CONST_ME_MORTAREA", tip = "Hug it or run out past the ring."}
			},
			timed = {
				{key = "bone_requiem", label = "Bone Requiem", kind = "channel", channelMs = 9000, every = 60000, below = 0.7,
					totemType = WARD, totemName = "Bone Totem", totemHealth = 12000, totemPerExtra = 1.0, share = 0.5,
					hit = "big_nova_void_7", fallback = "CONST_ME_MORTAREA",
					text = "%s chants the Bone Requiem! Destroy the Bone Totem!", tip = "Kill the Bone Totem in time."}
			},
			ref = {health = 1730000, dps = 2600, uptime = 1, players = 1, solo = true}
		},
		["cinderwing"] = {
			label = "Cinderwing", size = 2, element = "fire", difficulty = 0.15, every = 10000,
			fair = {refLevel = 1200},
			telegraphs = {
				{key = "cinder_breath", label = "Cinder Breath", kind = "line", halfWidth = 1, length = 12, share = 0.45,
					hit = "fire_explosion", fallback = "CONST_ME_FIREAREA", tip = "A beam towards you: sidestep."},
				{key = "falling_ash", label = "Falling Ash", kind = "follow", radius = 2, followMs = 1500, share = 0.35,
					hit = "big_meteor_fire_7", fallback = "CONST_ME_FIREAREA", tip = "It follows you, then stops: walk out."}
			},
			ref = {health = 1700000, dps = 2600, uptime = 1, players = 1, solo = true}
		},

		-- ================================================================ the weekly guild boss (guildboss.lua, 2-20)
		["gorvath the banner-eater"] = {
			label = "Gorvath", size = 2, element = "death", difficulty = 0.3, ownTelegraphs = true,
			fair = {refLevel = 300},
			timed = {
				{key = "devour_standard", label = "Devour the Standard", kind = "channel", channelMs = 9000, every = 55000,
					below = 0.8, totemType = WARD, totemName = "Gnawed Standard", totemHealth = 15000, totemPerExtra = 0.5,
					share = 0.5, hit = "shadow_eruption", fallback = "CONST_ME_MORTAREA",
					text = "%s starts to devour the standard! Destroy it!", tip = "Kill the Gnawed Standard before the cast ends."},
				{key = "shared_oath", label = "Shared Oath", kind = "soak", radius = 2, total = 1.2, min = 2, missShare = 0.5,
					every = 45000, below = 0.6, hit = "holy_hit", fallback = "CONST_ME_HOLYAREA",
					text = "%s demands a Shared Oath! Stand in the circle together!",
					tip = "Two or more stand in the circle to split the hit."}
			},
			debuff = {key = "gnawed", label = "Gnawed", perStack = 0.03, max = 10, everyMs = 2000, decayMs = 6000,
				tip = "His bites stack Gnawed (+3% damage taken): swap tanks."},
			ref = {health = 2210000, dps = 7000, uptime = 0.75, players = 5, limit = 780}
		},

		-- ================================================================ donor bosses (dormant: no spawn yet)
		["ormathulak"] = {
			label = "Ormathulak", size = 2, element = "fire", difficulty = 0.25, every = 10000, fair = {refLevel = 650},
			telegraphs = {
				{key = "cataclysm", label = "Cataclysm", kind = "circle", radius = 4, share = 0.45, hit = "big_nova_fire_9",
					fallback = "CONST_ME_FIREAREA", tip = "Back off 4 sqm."},
				{key = "rain_of_fire", label = "Rain of Fire", kind = "puddles", count = 6, onPlayers = 6, radius = 1,
					share = 0.3, hit = "meteor_strike", fallback = "CONST_ME_FIREAREA", tip = "Step off the circles."}
			},
			adds = {{at = 0.5, mode = "immune", type = WARD, name = "Infernal Seal", count = 3, health = 400000,
				healthPerExtra = 0.05, text = "%s is sealed: break the 3 Infernal Seals!", doneText = "The seals break!",
				tip = "At 50% immune until 3 Infernal Seals die."}},
			ref = {health = 22000000, heal = 1200, dps = 52000, uptime = 1, players = 20}
		},
		["talath"] = {
			label = "Talath", size = 2, element = "ice", difficulty = 0.25, every = 10000, fair = {refLevel = 650},
			telegraphs = {
				{key = "frost_lance", label = "Frost Lance", kind = "line", halfWidth = 1, length = 12, share = 0.45,
					hit = "frost_nova", fallback = "CONST_ME_ICEAREA", tip = "Sidestep the beam."},
				{key = "winter_ring", label = "Winter Ring", kind = "ring", inner = 3, outer = 7, share = 0.4,
					hit = "ice_shatter", fallback = "CONST_ME_ICEAREA", tip = "Hug him or run out."}
			},
			timed = {{key = "deep_freeze", label = "Deep Freeze", kind = "los", hideMs = 3500, every = 55000, below = 0.8,
				share = 0.6, pillars = {{-4, -4}, {4, -4}, {-4, 4}, {4, 4}}, hit = "big_shock_frost_7",
				fallback = "CONST_ME_ICEAREA", text = "%s calls the Deep Freeze! Hide behind a pillar!", tip = "Hide behind a pillar."}},
			ref = {health = 21000000, heal = 1200, dps = 52000, uptime = 1, players = 20}
		},
		["gloomfire"] = {
			label = "Gloomfire", size = 2, element = "death", difficulty = 0.25, every = 10000, fair = {refLevel = 650},
			telegraphs = {
				{key = "gloom_cross", label = "Gloom Cross", kind = "cross", halfWidth = 1, share = 0.45,
					hit = "shadow_eruption", fallback = "CONST_ME_MORTAREA", tip = "Stand on a diagonal."},
				{key = "shadow_pursuit", label = "Shadow Pursuit", kind = "follow", radius = 2, followMs = 1500, share = 0.35,
					hit = "shadow_hit", fallback = "CONST_ME_MORTAREA", tip = "Walk out once it stops."}
			},
			timed = {{key = "eclipse", label = "Eclipse", kind = "channel", channelMs = 9000, every = 55000, below = 0.7,
				totemType = WARD, totemName = "Gloom Totem", totemHealth = 150000, totemPerExtra = 0.05, share = 0.6,
				hit = "big_nova_void_7", fallback = "CONST_ME_MORTAREA", text = "%s channels the Eclipse! Destroy the Gloom Totem!",
				tip = "Kill the Gloom Totem in time."}},
			ref = {health = 20000000, heal = 1200, dps = 52000, uptime = 1, players = 20}
		},
		["saga"] = {
			label = "Saga", size = 2, element = "energy", difficulty = 0.25, every = 10000, fair = {refLevel = 650},
			telegraphs = {
				{key = "storm_verse", label = "Storm Verse", kind = "puddles", count = 6, onPlayers = 6, radius = 1, share = 0.3,
					hit = "lightning_strike", fallback = "CONST_ME_ENERGYAREA", tip = "Step off the marks."},
				{key = "thunder_cone", label = "Thunder Cone", kind = "cone", length = 7, spread = 3, share = 0.45,
					hit = "lightning_hit", fallback = "CONST_ME_ENERGYAREA", tip = "Step to her side."}
			},
			timed = {{key = "chorus", label = "Chorus", kind = "soak", radius = 2, total = 1.6, min = 3, missShare = 0.6,
				every = 45000, below = 0.8, groupOnly = true, hit = "big_lightning_burst_7", fallback = "CONST_ME_ENERGYAREA",
				text = "%s begins the Chorus! Stand in the circle together!", tip = "Three or more stand in the circle."}},
			ref = {health = 18000000, heal = 1200, dps = 52000, uptime = 1, players = 20}
		},
		["legendary warrior"] = {
			label = "The Legendary Warrior", size = 1, element = "physical", difficulty = 0.15, every = 10000,
			fair = {refLevel = 650},
			telegraphs = {
				{key = "whirlwind", label = "Whirlwind", kind = "circle", radius = 2, share = 0.35, hit = "big_shock_blood_9",
					fallback = "CONST_ME_GROUNDSHAKER", tip = "Back off 2 sqm."},
				{key = "charge", label = "Charge", kind = "line", halfWidth = 0, length = 10, share = 0.35, hit = "blunt_smash",
					fallback = "CONST_ME_GROUNDSHAKER", tip = "Sidestep the line."}
			},
			debuff = {key = "sundered", label = "Sundered", perStack = 0.03, max = 8, everyMs = 2500, decayMs = 6000,
				tip = "His hits stack Sundered (+3% damage taken): step away now and then."},
			ref = {health = 1000000, heal = 450, dps = 2600, uptime = 1, players = 1, solo = true}
		}
	}
}
