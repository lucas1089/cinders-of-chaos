-- spellbook_areas_config.lua: the area the Spellbook shows for the Chaos attack spells that hit more than their target
-- but whose script has no createCombatArea (a scripted pack hit: enemiesAround, a jump chain, a trap burst). Without a
-- row here the window said "Single target" and drew one tile (owner report 2026-10-24, Shuriken Tempest).
--
-- One row per spell name: shape circle (round, centred on the target), around (round, centred on you), wave (rows in
-- front of you, `depth` deep, up to `halfWidth` tiles each side) or line (`length` tiles in front of you); radius for
-- the round shapes. The attack kit's spells (attack_kit_config.lua) are not listed: the Spellbook reads their shape,
-- radius, length, depth and halfWidth from there. The radius is the one the spell script's description states;
-- tests/spellbook_areas_test.lua checks that every Chaos attack spell the rotation model counts as a pack hit has an area.
ChaosSpellbookAreas = {
	["Forked Storm"] = {shape = "circle", radius = 3},        -- jumps to up to 3 more monsters within 3 sqm
	["Blade Flurry"] = {shape = "around", radius = 1},        -- every monster in the 3x3 around you
	["Fan of Knives"] = {shape = "around", radius = 4},       -- the target and the nearest 5 within 4 sqm of you
	["Shuriken Barrage"] = {shape = "circle", radius = 3},    -- the target and 4 more within 3 sqm of it
	["Shuriken Tempest"] = {shape = "circle", radius = 4},    -- the target and 8 more within 4 sqm of it
	["Iaido Sweep"] = {shape = "wave", depth = 2, halfWidth = 1}, -- the 3 x 2 tiles in front of you
	["Grave Nova"] = {shape = "around", radius = 3},          -- every enemy within 3 sqm of you
	["Bone Shrapnel"] = {shape = "circle", radius = 1},       -- the target and every monster next to it
	["Corpse Explosion"] = {shape = "circle", radius = 3},    -- corpses within 3 sqm of the target burst
	["Bone Offering"] = {shape = "circle", radius = 2},       -- every enemy within 2 sqm of the skeleton
	["Palm Shockwave"] = {shape = "circle", radius = 2},      -- every monster within 2 sqm of the target
	["Shadow Ricochet"] = {shape = "circle", radius = 3},     -- jumps within 3 sqm of the last one hit
	["Iron Chain"] = {shape = "circle", radius = 2},          -- links within 2 sqm of the last one hit
	["Sanctified Ground"] = {shape = "around", radius = 2},   -- everything within 2 sqm of you
	["Shield Wave"] = {shape = "wave", depth = 3, halfWidth = 1}, -- the 3 x 3 tiles in front of you
	["Snare Trap"] = {shape = "circle", radius = 2},          -- the burst within 2 sqm of the trap
	["Seeker Mine"] = {shape = "circle", radius = 2}          -- the burst within 2 sqm of the mine
}
