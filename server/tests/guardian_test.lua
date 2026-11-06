-- guardian_test.lua (O427): guardian_core.lua (the damage curve, summon hits, the kit, its profile), the rift hit rule
-- (R.monsterHit with fx.guardian), the config and the boss mechanics fight with the kit. Run from server/:
-- luajit tests/guardian_test.lua
dofile("data/scripts/chaos/guardian_core.lua")
dofile("data/scripts/chaos/rift_core.lua")
dofile("data/lib/chaos_speed.lua")
dofile("data/scripts/chaos/boss_mechanics_core.lua")

local cfg = dofile("data/scripts/chaos/rift_config.lua")
local mech = dofile("data/scripts/chaos/boss_mechanics_config.lua")
local G, R, B = ChaosGuardianCore, ChaosRiftCore, ChaosBossMechCore or ChaosBossMech
local checks, fails = 0, 0
local function ok(c, msg)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- 1. the damage curve: falls with the tier (the low tiers' guardians are weak stock monsters), never under min; Omen
-- guardians hit harder than any rift guardian
local g = cfg.guardian
eq(G.damageMult(cfg, 1, false), g.damage.base, "tier 1")
for t = 2, cfg.maxTier do
	ok(G.damageMult(cfg, t, false) <= G.damageMult(cfg, t - 1, false), "the curve does not rise at tier " .. t)
	ok(G.damageMult(cfg, t, false) >= g.damage.min, "never under min at tier " .. t)
	ok(G.damageMult(cfg, t, false) >= 1, "a guardian never hits softer than its monster at tier " .. t)
end
eq(G.damageMult(cfg, cfg.maxTier, false), g.damage.min, "the last tier sits on the floor")
eq(G.damageMult(cfg, nil, true), g.damage.omen, "the Omen number")
ok(G.damageMult(cfg, 1, true) > G.damageMult(cfg, 1, false), "an Omen guardian hits harder than the hardest rift guardian")
eq(G.damageMult({}, 5, false), 1, "no config: 1")
eq(G.damageMult(cfg, 0, false), g.damage.base, "tier under 1 counts as 1")

-- 2. a guardian's hit on a summon: x factor, part of it to the owner, sign and the minimum of 1 kept
local own, splash = G.minionHit(cfg, -1000)
eq(own, -math.floor(1000 * g.minion.factor + 0.5), "summon takes the factor")
eq(splash, math.floor(1000 * g.minion.splash + 0.5), "the owner takes the splash")
own, splash = G.minionHit(cfg, 1000)
ok(own > 0 and splash > 0, "positive damage keeps its sign")
own, splash = G.minionHit(cfg, 0)
eq(own, 0, "no damage stays none")
eq(splash, 0, "no splash of nothing")
own = G.minionHit(cfg, -1)
eq(own, -1, "a hit is at least 1")
own, splash = G.minionHit({}, -500)
eq(own, -500, "no config: as it was")
eq(splash, 0, "no config: no splash")
ok(g.minion.factor > 0.25, "a summon is no longer a wall (the Necromancer incoming factor is 0.25)")
ok((1 - 0.7) + 0.7 * g.minion.splash >= 0.6, "the owner takes 60% of a lone player's damage while the summons stand")

-- 3. how many extra attacks
eq(G.kitCount(cfg, 1, false), 1, "tier 1: one")
eq(G.kitCount(cfg, 5, false), 2, "tier 5: two")
eq(G.kitCount(cfg, 10, false), 3, "tier 10: three")
eq(G.kitCount(cfg, 15, false), 4, "tier 15: four")
eq(G.kitCount(cfg, 15, true), g.kit.omenCount, "an Omen guardian: its own count")

-- 4. the draw: deterministic, distinct, by seed, themed
local a1 = G.pickKit(cfg, 4242, "Abyssal Rift", 15, false)
local a2 = G.pickKit(cfg, 4242, "Abyssal Rift", 15, false)
eq(table.concat(a1, ","), table.concat(a2, ","), "the same seed gives the same kit")
eq(#a1, 4, "tier 15: four abilities")
local seen = {}
for _, k in ipairs(a1) do
	ok(not seen[k], "no ability twice: " .. k)
	seen[k] = true
end
local kits = {}
local count = {}
for seed = 1, 400 do
	local kit = G.pickKit(cfg, seed, "Obsidian Hall", 1, false)
	eq(#kit, 1, "tier 1: one")
	kits[kit[1]] = true
	count[kit[1]] = (count[kit[1]] or 0) + 1
end
local distinct = 0
for _ in pairs(kits) do
	distinct = distinct + 1
end
ok(distinct >= 4, "guardians differ by seed (" .. distinct .. " different tier 1 kits)")
-- the theme's own abilities weigh themeWeight x: Obsidian Hall lists rift_lance and rift_wave
ok(count.rift_lance > count.rift_nova * 1.5 and count.rift_wave > count.rift_hunt * 1.2, "the theme's abilities come up more often")
local skipped = G.pickKit(cfg, 7, "Abyssal Rift", 15, true, {rift_nova = true, rift_cross = true})
for _, k in ipairs(skipped) do
	ok(k ~= "rift_nova" and k ~= "rift_cross", "a skipped ability is not drawn")
end
eq(#skipped, g.kit.omenCount, "an Omen guardian draws omenCount")
eq(#G.pickKit(cfg, 1, "x", 15, false, {rift_nova = true, rift_cross = true, rift_wave = true, rift_lance = true}), 1, "the pool bounds the count")

-- 5. the config: every ability is a telegraph the engine draws, with a unique key
local kinds = {circle = true, cone = true, line = true, ring = true, cross = true, follow = true, puddles = true}
local keys = {}
for _, p in pairs(mech.profiles) do
	for _, t in ipairs(p.telegraphs or {}) do
		keys[t.key] = true
	end
end
for _, a in ipairs(g.abilities) do
	ok(kinds[a.kind], a.key .. ": a telegraph kind the engine draws")
	ok(not keys[a.key], a.key .. ": no clash with a boss_mechanics telegraph key")
	ok(a.share > 0 and a.share <= g.kit.shareCap, a.key .. ": share")
	ok(a.hit and a.fallback and a.tip and a.label, a.key .. ": hit, fallback, tip and label (the cast bar)")
	local themeOk = false
	for _, th in ipairs(cfg.themes) do
		for _, name in ipairs(a.themes or {}) do
			themeOk = themeOk or th.name == name
		end
	end
	ok(themeOk, a.key .. ": a real theme name")
end
local themeUsed = {}
for _, a in ipairs(g.abilities) do
	for _, name in ipairs(a.themes or {}) do
		themeUsed[name] = true
	end
end
for _, th in ipairs(cfg.themes) do
	ok(themeUsed[th.name], th.name .. " has abilities of its own")
end

-- 6. the profile: the kit added, shares grow by tier, capped, the base untouched, faster cadence
local base = mech.profiles.rift_guardian
local n0 = #base.telegraphs
local every0 = base.every
local p1 = G.profile(cfg, base, {"rift_nova"}, 1, false)
local p15 = G.profile(cfg, base, {"rift_nova", "rift_lance", "rift_hunt"}, 15, false)
eq(#base.telegraphs, n0, "the base profile is not changed")
eq(base.every, every0, "the base cadence is not changed")
eq(#p1.telegraphs, n0 + 1, "one added")
eq(#p15.telegraphs, n0 + 3, "three added")
eq(p1.label, base.label, "the other fields read through")
local function shareOf(p, key)
	for _, t in ipairs(p.telegraphs) do
		if t.key == key then
			return t.share
		end
	end
end
ok(shareOf(p15, "rift_nova") > shareOf(p1, "rift_nova"), "the share grows by tier")
ok(shareOf(p15, "rift_nova") <= g.kit.shareCap, "the share is capped")
ok(p15.every < p1.every and p1.every < base.every, "more abilities, a faster cadence")
local po = G.profile(cfg, base, {"rift_nova"}, 1, true)
ok(shareOf(po, "rift_nova") > shareOf(p1, "rift_nova"), "an Omen mark hits harder")
ok(shareOf(po, "rift_nova") <= g.kit.shareCap * g.kit.omenShareMult, "an Omen mark is capped too")
eq(G.spec(cfg, "nope", 1, false), nil, "an unknown ability")
ok(G.markShare(p15, 0.3, 15) > G.markShare(base, 0.3, 15), "the kit adds marked damage per second")
eq(G.markShare({telegraphs = {}}, 0.2, 1), 0, "no telegraphs, no marks")

-- 7. the fight with the kit: the engine draws every kit ability over time
local fight = B.newFight(p15, {now = 0, tier = 15, difficulty = 0.3})
local drawn = {}
for t = 1, 400 do
	for _, act in ipairs(B.update(fight, t * 3000, 0.9, 0)) do
		if act.kind == "telegraph" then
			drawn[act.spec.key] = true
		end
	end
end
ok(drawn.rift_nova and drawn.rift_lance and drawn.rift_hunt, "nova, lance and mark are all drawn in a fight")
ok(drawn.guardian_slam and drawn.guardian_sweep, "the guardian keeps its own slam and sweep")

-- 8. the hit rule: the guardian's own hits x fx.guardian (and the party's), its marked attacks only the party's
local T = {physical = 1, none = 0, brand = {fire = 2, ice = 3, energy = 4}}
local never = function(_, b) return b end
local fx = R.applyParty(cfg, R.effects(cfg, {}, 1), 1, 1)
eq(fx.guardian, g.damage.base, "applyParty: the tier's guardian number")
local hit = {primary = -1000, ptype = 1, secondary = 0, stype = 0, boss = true}
local p = R.monsterHit(cfg, fx, hit, T, never)
eq(p, math.floor(-1000 * g.damage.base), "a guardian hit at tier 1")
hit.scripted = true
p = R.monsterHit(cfg, fx, hit, T, never)
eq(p, -1000, "a marked attack is a share of health: not multiplied again")
local fx5 = R.applyParty(cfg, R.effects(cfg, {}, 1), 5, 1)
hit.scripted = false
p = R.monsterHit(cfg, fx5, hit, T, never)
eq(p, math.floor(-1000 * g.damage.base * (1 + cfg.party.damagePerExtraPlayer * 4)), "a party of 5: +40% on top")
local fxo = R.applyParty(cfg, R.effects(cfg, {}, 1), 1, nil, true)
eq(fxo.guardian, g.damage.omen, "an Omen run carries the Omen number")
p = R.monsterHit(cfg, R.effects(cfg, {}, 1), {primary = -1000, ptype = 1, secondary = 0, stype = 0}, T, never)
eq(p, math.floor(-1000 * R.packDamage(cfg, 1)), "a pack monster: the pack curve only")
-- a Dread Guardian still multiplies on top
local fxd = R.applyParty(cfg, R.effects(cfg, {{key = "dread", value = 100}}, 1), 1, 1)
p = R.monsterHit(cfg, fxd, {primary = -1000, ptype = 1, secondary = 0, stype = 0, boss = true}, T, never)
eq(p, math.floor(-1000 * 2 * g.damage.base), "Dread Guardian +100% on top")

-- 9. the pack curve: falls from base to min, every tier at least min, never under the old 0.6
eq(R.packDamage(cfg, 1), cfg.density.damage.base, "pack tier 1")
for t = 1, cfg.maxTier do
	ok(R.packDamage(cfg, t) >= 0.6, "a pack never hits softer than before at tier " .. t)
	ok(R.packDamage(cfg, t) >= cfg.density.damage.min, "pack min at tier " .. t)
end
eq(R.packDamage({density = {enabled = true, damage = 0.6}, tiers = cfg.tiers, maxTier = cfg.maxTier, beyond = cfg.beyond}, 3), 0.6, "a number still works")

-- 10. the wiring (source checks, as necro_summon_test.lua does for the guard): the summon's hit rule, the kit at spawn
local function src(path)
	local f = assert(io.open(path, "rb"))
	local t = f:read("*a")
	f:close()
	return t
end
local necro = src("data/scripts/chaos/necro_minions.lua")
ok(necro:find("ChaosRift.guardianHitMult(attacker)", 1, true) and necro:find("ChaosGuardianCore.minionHit", 1, true),
	"a guardian's hit on a minion goes through the guardian rule")
ok(necro:find("M.splashing", 1, true), "the splash cannot recurse")
local rift = src("data/scripts/chaos/rift.lua")
ok(rift:find("ChaosGuardianCore.pickKit", 1, true) and rift:find("profile = profile", 1, true), "a guardian gets its kit at spawn")
ok(rift:find("scripted = ChaosBossMech", 1, true), "a marked attack is told from the guardian's own hit")
ok(rift:find("function RF.guardianHitMult", 1, true), "RF.guardianHitMult exists")
ok(src("data/scripts/chaos/boss_mechanics.lua"):find("opts and opts.profile", 1, true), "attach takes a profile of its own")

print(string.format("guardian_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
