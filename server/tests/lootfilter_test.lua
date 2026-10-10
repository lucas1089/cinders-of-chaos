-- Run from the server/ folder: luajit tests/lootfilter_test.lua (and lua5.3; CI runs both)
-- Pure logic of the loot filter (lootfilter_core.lua): settings packing and sanitizing, presets, the highlight / dim
-- rules, the Rarity Autoloot decisions, the ray choice with the real lootfilter_config.lua, the corpse reconcile used
-- to grey the loot channel, the reach rule and the labels.
dofile("data/scripts/chaos/lootfilter_core.lua")
local F = ChaosLootFilter
local cfg = dofile("data/scripts/chaos/lootfilter_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function sameSettings(a, b, m)
	for _, k in ipairs({"highlight", "dim", "lootMin", "lootFrom", "icons", "notify", "tier"}) do
		eq(a[k], b[k], m .. " " .. k)
	end
	for _, c in ipairs(F.CATEGORIES) do
		eq(a.show[c], b.show[c], m .. " show." .. c)
	end
end

-- ---------------------------------------------------------------- rarity table
eq(F.MAX_RARITY, 15, "15 rarities like the base server")
eq(F.RARITY[1].name, "Common", "1 = Common")
eq(F.RARITY[5].name, "Legendary", "5 = Legendary")
eq(F.RARITY[15].name, "Transcendent", "15 = Transcendent")

-- ---------------------------------------------------------------- packing
local d = F.defaults()
sameSettings(F.unpack(-1), d, "unset storage = defaults")
sameSettings(F.unpack(nil), d, "nil = defaults")
sameSettings(F.unpack(F.pack(d)), d, "defaults round trip")
local s = {highlight = 15, dim = 7, lootMin = 4, lootFrom = 12, show = {equipment = false, currency = true, supplies = false,
	other = true}, icons = false, notify = true, tier = 8}
sameSettings(F.unpack(F.pack(s)), F.sanitize(s), "full round trip")
assert(F.pack(s) < 2 ^ 31, "fits an int32 storage")
eq(F.unpack(F.pack(s)).tier, 8, "the tier rule round trip")
eq(F.unpack(2097152 + 1048576 + 3).tier, 0, "settings saved before the tier rule: off")
eq(F.sanitize({tier = 12}).tier, 8, "clamped")
-- the tier rule: gear with a modifier of that tier or better glows
local tierS = F.sanitize({highlight = 9, tier = 6})
eq(F.classify({rarity = 2, bestTier = 6, category = "equipment"}, tierS), "highlight", "T6 on Uncommon gear glows")
eq(F.classify({rarity = 2, bestTier = 5, category = "equipment"}, tierS), "normal", "T5 does not")
eq(F.classify({rarity = 2, category = "equipment"}, F.sanitize({highlight = 9})), "normal", "rule off")
eq(F.classify({rarity = 5, power = true, category = "equipment"}, F.sanitize({highlight = 9})), "highlight", "a legendary power always glows")
for _, p in ipairs(F.PRESETS) do
	local ps = F.applyPreset(p.key)
	assert(ps, "preset " .. p.key)
	sameSettings(F.unpack(F.pack(ps)), ps, "preset round trip " .. p.key)
end
eq(F.applyPreset("nope"), nil, "unknown preset")

-- ---------------------------------------------------------------- sanitize
local z = F.sanitize({highlight = 99, dim = -3, lootMin = "4", lootFrom = 2.7, show = {supplies = false, bogus = true}, icons = 0})
eq(z.highlight, 15, "clamped high")
eq(z.dim, 0, "clamped low")
eq(z.lootMin, 4, "string number")
eq(z.lootFrom, 2, "floored")
eq(z.show.supplies, false, "category off")
eq(z.show.equipment, true, "missing category = shown")
eq(z.show.bogus, nil, "unknown category dropped")
eq(z.icons, false, "0 = false")
eq(z.notify, true, "missing = default")
sameSettings(F.sanitize("garbage"), d, "non-table = defaults")

-- ---------------------------------------------------------------- classify
local function gear(r) return {id = 2400, rarity = r, category = "equipment", name = "Sword"} end
local hunter = F.applyPreset("hunter") -- highlight 4, dim 2
eq(F.classify(gear(4), hunter), "highlight", "Epic glows under hunter")
eq(F.classify(gear(9), hunter), "highlight", "higher glows")
eq(F.classify(gear(3), hunter), "normal", "Rare is plain")
eq(F.classify(gear(2), hunter), "normal", "Uncommon at the dim line is plain")
eq(F.classify(gear(1), hunter), "dim", "Common dimmed")
eq(F.classify(gear(0), hunter), "dim", "no rarity dimmed")
eq(F.classify({id = 1, unique = true, category = "equipment"}, F.applyPreset("strict")), "highlight", "uniques always glow")
eq(F.classify({id = 29856, orb = true, category = "currency"}, {highlight = 0, dim = 15, show = {currency = false}}),
	"highlight", "orbs always glow, even with currency off")
local strict = F.applyPreset("strict")
eq(F.classify({id = 7618, category = "supplies"}, strict), "dim", "strict dims supplies")
eq(F.classify({id = 2148, category = "currency"}, strict), "normal", "coins shown under strict")
eq(F.classify({id = 1, category = "other"}, strict), "dim", "strict dims other")
local off = F.defaults(); off.show.equipment = false; off.highlight = 5
eq(F.classify(gear(6), off), "highlight", "equipment hidden but Legendary+ still glows")
eq(F.classify(gear(4), off), "dim", "equipment hidden dims the rest")
local noGlow = F.defaults(); noGlow.highlight = 0
eq(F.classify(gear(15), noGlow), "normal", "highlight 0 = no rarity glow")
eq(F.color(gear(5)), "#ffd040", "Legendary colour")
eq(F.color({unique = true, rarity = 5}), F.UNIQUE_COLOR, "unique colour wins")
eq(F.color({orb = true}), F.ORB_COLOR, "orb colour")
eq(F.color(gear(0)), nil, "no colour without rarity")

-- ---------------------------------------------------------------- Rarity Autoloot (store unlock)
eq(F.autoloot(gear(1), strict, true, false), nil, "locked: never changes the stock autoloot")
eq(F.autoloot(gear(9), strict, false, false), nil, "locked: no pickup")
eq(F.autoloot(gear(1), strict, true, true), "keep", "on the list but below lootMin 4: stays in the corpse")
eq(F.autoloot(gear(0), strict, true, true), "keep", "no rarity counts as below")
eq(F.autoloot(gear(4), strict, true, true), nil, "on the list at lootMin: the stock autoloot takes it")
eq(F.autoloot({id = 2148, category = "currency"}, strict, true, true), nil, "list coins are never held back")
eq(F.autoloot({id = 9, unique = true, category = "equipment"}, strict, true, true), nil, "list uniques are never held back")
eq(F.autoloot(gear(5), strict, false, true), "take", "off the list, Legendary >= lootFrom 5: picked up")
eq(F.autoloot(gear(4), strict, false, true), nil, "off the list below lootFrom: left")
eq(F.autoloot({id = 9, unique = true, category = "equipment"}, strict, false, true), "take", "uniques picked up when lootFrom is on")
eq(F.autoloot({id = 7618, category = "supplies"}, strict, false, true), nil, "pickup is for gear only")
eq(F.autoloot(gear(9), F.defaults(), false, true), nil, "lootFrom 0 = off")

-- ---------------------------------------------------------------- rays (real config)
eq(cfg.rayMinRarity, 5, "rays from Legendary")
eq(F.rayEffect(gear(4), cfg), nil, "Epic: no ray")
eq(F.rayEffect(gear(0), cfg), nil, "no rarity: no ray")
eq(F.rayEffect(gear(5), cfg), "loot_ray_legendary", "Legendary ray")
eq(F.rayEffect(gear(6), cfg), "loot_ray_legendary", "Exotic shares the band")
eq(F.rayEffect(gear(7), cfg), "loot_ray_mythic", "Mythic band")
eq(F.rayEffect(gear(12), cfg), "loot_ray_divine", "Celestial band")
eq(F.rayEffect(gear(15), cfg), "loot_ray_cosmic", "Transcendent band")
eq(F.rayEffect({unique = true, rarity = 0}, cfg), "loot_ray_unique", "unique ray")
eq(F.rayEffect({unique = true}, {rayUniques = false, rayMinRarity = 5, rayBands = cfg.rayBands}), nil, "uniques switched off")
eq(F.rayEffect(gear(5), {rayMinRarity = 8, rayBands = cfg.rayBands}), nil, "threshold is one value")
eq(F.rayEffect({id = 29856, orb = true, rarity = 0}, cfg), nil, "orbs: no ray")

-- ---------------------------------------------------------------- reconcile (greying the loot channel)
local a = {sig = "2148:0:", count = 50}
local b = {sig = "2400:3:", count = 1}
local c = {sig = "2400:3:", count = 1}
local u = {sig = F.signature({id = 2400, rarity = 0, unique = true, name = "Soulreaper"}), count = 1}
local left = F.reconcile({a, b, c, u}, {["2148:0:"] = 50, ["2400:3:"] = 2, [u.sig] = 1})
eq(table.concat(left, ","), "50,1,1,1", "all there")
left = F.reconcile({a, b, c, u}, {["2148:0:"] = 20, ["2400:3:"] = 1})
eq(table.concat(left, ","), "20,1,0,0", "partial stack, one of two identical swords, unique gone")
left = F.reconcile({a, b}, {})
eq(table.concat(left, ","), "0,0", "corpse empty")
left = F.reconcile({a}, {["2148:0:"] = 80})
eq(left[1], 50, "never more than dropped")
assert(F.signature({id = 2400, rarity = 3}) ~= F.signature({id = 2400, rarity = 4}), "rarity is part of the key")
assert(F.signature({id = 2400, unique = true, name = "A"}) ~= F.signature({id = 2400}), "unique differs from plain")

-- ---------------------------------------------------------------- reach, labels, drop lines
local r = cfg.reach
eq(F.inReach({x = 100, y = 100, z = 7}, {x = 107, y = 95, z = 7}, r), true, "edge of the screen")
eq(F.inReach({x = 100, y = 100, z = 7}, {x = 108, y = 100, z = 7}, r), false, "too far east")
eq(F.inReach({x = 100, y = 100, z = 7}, {x = 100, y = 106, z = 7}, r), false, "too far south")
eq(F.inReach({x = 100, y = 100, z = 7}, {x = 100, y = 100, z = 6}, r), false, "other floor")
eq(F.label({name = "Dawnforged Helmet", rarity = 5}), "[Legendary] Dawnforged Helmet", "label")
eq(F.label({name = "Soulreaper", rarity = 5, unique = true}), "[Unique] Soulreaper", "unique label")
eq(F.label({name = "gold coin"}), "gold coin", "plain label")
eq(F.dropLine({name = "Dawnforged Helmet", rarity = 5, category = "equipment"}, hunter), "Rare drop: [Legendary] Dawnforged Helmet",
	"rare drop line")
eq(F.dropLine({name = "Sword", rarity = 3, category = "equipment"}, hunter), nil, "below the highlight: no line")
eq(F.dropLine({name = "Orb of Upheaval", orb = true, count = 2, category = "currency"}, hunter), nil, "orbs: no line")
eq(F.dropLine({name = "Soulreaper", unique = true, category = "equipment"}, hunter), "Unique drop: [Unique] Soulreaper", "unique line")
local quiet = F.applyPreset("hunter"); quiet.notify = false
eq(F.dropLine({name = "X", rarity = 9, category = "equipment"}, quiet), nil, "notify off")

-- ---------------------------------------------------------------- rule counters and sounds
local rs = F.sanitize({highlight = 5, tier = 6})
local function hitList(info, set)
	return table.concat(F.ruleHits(info, set or rs), ",")
end
eq(hitList({unique = true, rarity = 9, power = true, category = "equipment"}), "unique", "a unique counts once, as unique")
eq(hitList({rarity = 6, power = true, bestTier = 7, category = "equipment"}), "power,rarity,tier", "every rule it matches")
eq(hitList({rarity = 4, bestTier = 5, category = "equipment"}), "", "below both thresholds")
eq(hitList({rarity = 9, category = "equipment"}, F.sanitize({highlight = 0, tier = 0})), "", "rarity and tier rules off")
eq(hitList({orb = true, count = 3, category = "currency"}), "orb", "orb")
eq(hitList({rarity = 9, category = "supplies"}), "", "only gear counts for rarity")
local hits = F.countHits({{orb = true, count = 3, category = "currency"}, {rarity = 5, category = "equipment"},
	{unique = true, category = "equipment"}, {rarity = 1, category = "equipment"}, {orb = true, category = "currency"}}, rs)
eq(hits.orb, 4, "orbs counted as items (a stack of 3 and one)")
eq(hits.rarity, 1, "one Legendary")
eq(hits.unique, 1, "one unique")
eq(hits.tier, nil, "no tier hit")
local c = F.addCounts(F.counts(nil), hits)
eq(c.orb .. "/" .. c.rarity .. "/" .. c.power, "4/1/0", "added")
F.addCounts(c, {orb = 2, bogus = 9})
eq(c.orb, 6, "added again")
eq(c.bogus, nil, "unknown rule ignored")
eq(F.addCounts({orb = 1999999999}, {orb = 5}).orb, 2000000000, "capped below the int32 limit")
eq(F.counts({orb = -4, tier = 2.6}).orb .. "/" .. F.counts({tier = 2.6}).tier, "0/2", "counts read clean")

local sd = F.soundDefaults()
local snd = F.unpackSound(F.packSound(sd))
eq(snd.rules.unique .. snd.rules.power .. snd.rules.rarity .. "/" .. snd.vol .. "/" .. tostring(snd.mute) .. tostring(snd.hunt),
	"510/70/falsetrue", "defaults round trip")
eq(F.unpackSound(-1).vol, 70, "unset storage = defaults")
local full = {rules = {unique = 5, power = 4, rarity = 3, tier = 2, orb = 1}, vol = 100, mute = true, hunt = false}
local back = F.unpackSound(F.packSound(full))
eq(back.rules.unique .. back.rules.power .. back.rules.rarity .. back.rules.tier .. back.rules.orb, "54321", "every rule round trip")
eq(back.vol .. tostring(back.mute) .. tostring(back.hunt), "100truefalse", "volume, mute, hunt")
assert(F.packSound(full) < 2 ^ 31, "sound settings fit an int32 storage")
local bad = F.sanitizeSound({rules = {unique = 99, orb = -1, tier = "x", bogus = 3}, vol = 400, mute = "1"})
eq(bad.rules.unique .. bad.rules.orb .. bad.rules.tier .. "/" .. bad.vol .. tostring(bad.mute), "000/100true", "client input clamped")
eq(bad.rules.bogus, nil, "unknown rule dropped")

eq(F.pickSound({orb = 2, unique = 1}, sd), "fanfare", "the first rule in priority order with a sound")
eq(select(2, F.pickSound({orb = 2, unique = 1}, sd)), "unique", "and its rule")
eq(F.pickSound({orb = 2}, sd), nil, "orbs have no sound by default")
eq(F.pickSound({power = 1, rarity = 1}, F.sanitizeSound({rules = {power = 0, rarity = 3}})), "ping", "a rule without sound is skipped")
eq(F.pickSound({unique = 1}, F.sanitizeSound({mute = true})), nil, "mute all")
eq(F.pickSound({unique = 1}, F.sanitizeSound({vol = 0})), nil, "volume 0")
eq(F.pickSound({}, sd), nil, "nothing matched")

local plan = F.resetPlan("session")
eq(#plan.rules .. tostring(plan.session) .. tostring(plan.total), "5truefalse", "reset the session of every rule")
plan = F.resetPlan("all", "orb")
eq(plan.rules[1] .. #plan.rules .. tostring(plan.session) .. tostring(plan.total), "orb1truetrue", "reset one rule")
eq(F.resetPlan("total").total, true, "reset totals")
eq(F.resetPlan("everything"), nil, "unknown scope")
eq(F.resetPlan("all", "bogus"), nil, "unknown rule")
eq(cfg.soundStorage >= 7100500 and cfg.soundStorage <= 7100509 and cfg.totalStorageBase + #F.RULES - 1 <= 7100509, true,
	"storages inside the loot filter's reserved range")
eq(cfg.totalStorageBase > cfg.soundStorage, true, "no overlap")

print("lootfilter tests OK")
