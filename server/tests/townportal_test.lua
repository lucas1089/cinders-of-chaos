-- Run from the server/ folder: luajit tests/townportal_test.lua (and lua5.3; CI runs both)
-- Town Portal (townportal_core.lua) with the real townportal_config.lua, shop_config.lua and achievements_data.lua:
-- the styles and their single route (store XOR achievement), the effect names, the refusal rules, spots, the
-- channel (move / hit / done), the cooldown, who may use a pair and the Portal Style window rows.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/townportal_core.lua")
local K = ChaosTownPortalCore
local cfg = dofile("data/scripts/chaos/townportal_config.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")
local data = dofile("data/scripts/chaos/achievements_data.lua")
dofile("data/lib/chaos_fx.lua")
-- chaos_vfx.lua defines functions that call the engine only when used
dofile("data/lib/chaos_vfx.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- styles, routes, store and achievements
local problems = K.validate(cfg, data, shop)
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
eq(#problems, 0, "validate")

local routes = {default = 0, store = 0, achievement = 0, season = 0, boss = 0}
for _, s in ipairs(cfg.styles) do
	routes[s.route] = routes[s.route] + 1
	for _, field in ipairs({"open", "close", "loop", "travel"}) do
		for _, e in ipairs(s[field] or {}) do
			assert(type(e) == "number" or ChaosVfx[e] or ChaosFx[e], s.key .. "." .. field .. ": unknown effect " .. tostring(e))
		end
		local list = s[field]
		if list then
			assert(type(list[#list]) == "number", s.key .. "." .. field .. ": the last fallback must be a stock effect")
		end
	end
	local a = K.achievementOf(data, s.key)
	local _, count = K.storePrices(shop)
	-- exactly one route: never both
	assert(not (a and count[K.unlockName(s)]), s.key .. " is both sold and an achievement reward")
end
eq(routes.default, 1, "one default style")
eq(routes.store, 6, "six store styles")
eq(routes.achievement, 6, "six achievement styles")
eq(routes.season, 2, "two season pass styles (seasonpass_config.lua; checked in seasonpass_test.lua)")
eq(routes.boss, 2, "two boss drop styles (exclusives_config.lua; checked in exclusives_test.lua)")
-- a boss style: owned only through the exclusives (account-wide), never sold, never an achievement reward
local drowned = K.styleByKey(cfg, "drowned")
eq(K.owns(drowned, {bossOwned = function(key) return key == "drowned" end}), true, "boss style owned through the exclusives")
eq(K.owns(drowned, {bossOwned = function() return false end}), false, "not owned without the drop")
eq(K.owns(drowned, {}), false, "no exclusives loaded: not owned")
eq(K.styleOfUnlock(cfg, "portal_drowned"), nil, "a boss style is never a store unlock")
for _, e in ipairs(cfg.castEffect) do
	assert(type(e) == "number" or ChaosVfx[e] or ChaosFx[e], "cast effect " .. tostring(e))
end

-- the validator catches a style on both routes and a missing offer
do
	local bad = {list = {}}
	for _, a in ipairs(data.list) do
		bad.list[#bad.list + 1] = a
	end
	bad.list[#bad.list + 1] = {id = "x", reward = {portal = {key = "emberforge", name = "Emberforge Gate"}}}
	assert(#K.validate(cfg, bad, shop) > 0, "a store style as an achievement reward is refused")
	local noShop = {categories = {}}
	assert(#K.validate(cfg, data, noShop) >= 6, "store styles without offers are refused")
end

-- prices in the range of the auras (150..300)
local prices = K.storePrices(shop)
for name, cost in pairs(prices) do
	assert(cost >= 150 and cost <= 300, name .. " price " .. cost)
end

-- lookups
eq(K.style(cfg, nil).key, "waygate", "default for nil")
eq(K.style(cfg, -1).key, "waygate", "default for an unset storage")
eq(K.style(cfg, 999).key, "waygate", "default for an unknown id")
eq(K.style(cfg, 3).key, "gilded", "style by id")
eq(K.styleOfUnlock(cfg, "portal_gilded").id, 3, "unlock name -> store style")
eq(K.styleOfUnlock(cfg, "portal_abyssal"), nil, "an achievement style is never a store unlock")
eq(K.styleOfUnlock(cfg, "lootPouch"), nil, "other unlocks are not portal styles")
eq(K.achievementOf(data, "abyssal").id, "wb_all", "Abyssal Maw from Colossus Hunter")

-- ownership
local owned, has = {}, {}
local facts = {
	storeOwned = function(id) return owned[id] end,
	hasAchievement = function(id) return has[id] end,
	achievementOf = function(k) return K.achievementOf(data, k) end
}
eq(K.owns(K.style(cfg, 0), facts), true, "default owned")
eq(K.owns(K.style(cfg, 1), facts), false, "store style not bought")
owned[1] = true
eq(K.owns(K.style(cfg, 1), facts), true, "store style bought")
eq(K.owns(K.styleByKey(cfg, "abyssal"), facts), false, "achievement missing")
has.wb_all = true
eq(K.owns(K.styleByKey(cfg, "abyssal"), facts), true, "achievement unlocked (also an older unlock)")
-- buying cannot give an achievement style, an achievement cannot give a store style
owned[31] = true
eq(K.owns(K.styleByKey(cfg, "abyssal"), {storeOwned = function() return true end,
	hasAchievement = function() return false end, achievementOf = facts.achievementOf}), false, "store flag ignored")

-- ---------------------------------------------------------------- refusals
eq(K.blockReason({}), nil, "open field: allowed")
for _, f in ipairs({"tutorial", "arena", "worldBoss", "siege", "rift", "dungeon", "tower", "pzLocked", "skull", "pz",
	"casting", "noTown"}) do
	assert(K.blockReason({[f] = true}), f .. " refused")
end
-- inside a hideout the Town Portal is a way out (townportal.lua sends the character through ChaosHideout.leave)
eq(K.hideoutExit({hideout = true}), true, "hideout: a way out")
eq(K.hideoutExit({hideout = true, cooldownLeft = 30, pz = true, instance = "a hideout"}), true,
	"hideout: no cooldown, protection zone or instance refusal")
eq(K.hideoutExit({hideout = true, casting = true}), false, "hideout: not while a cast runs")
eq(K.hideoutExit({hideout = true, tutorial = true}), false, "hideout: not on the tutorial island")
eq(K.hideoutExit({}), false, "elsewhere: the normal portal")
eq(K.hideoutExit({instance = "a raid"}), false, "another instance: refused as before")
assert(K.blockReason({hideout = true}):find("Leave", 1, true), "without the hideout system: points to the exit")
do -- townportal.lua: the hideout case comes before every refusal and goes through ChaosHideout.leave
	local h = io.open("data/scripts/chaos/townportal.lua", "r")
	local src = h:read("*a")
	h:close()
	local cast = src:find("function T.cast", 1, true)
	local exit = src:find("K.hideoutExit(bf) and ChaosHideout and ChaosHideout.leave", cast, true)
	local block = src:find("K.blockReason(bf)", cast, true)
	assert(exit and block and exit < block, "T.cast: the hideout way out before the refusals")
	assert(src:find("ChaosHideout.leave(player,", cast, true), "T.cast: through the hideout's exit logic")
end
assert(K.blockReason({cooldownLeft = 12}):find("12 seconds"), "cooldown text")
assert(K.blockReason({cooldownLeft = 1}):find("1 second%."), "one second")
eq(K.blockReason({cooldownLeft = 0}), nil, "cooldown over")

-- ---------------------------------------------------------------- spots
local rings = K.ringOffsets(2)
eq(#rings, 8 + 16, "two rings")
eq(math.max(math.abs(rings[1][1]), math.abs(rings[1][2])), 1, "nearest ring first")
eq(rings[1][1] == 0 or rings[1][2] == 0, true, "straight before diagonal")
local spot = K.pickSpot({x = 10, y = 10, z = 7}, cfg.fieldOffsets, function(p) return p.x == 9 and p.y == 10 end)
eq(spot.x .. "," .. spot.y, "9,10", "first free spot")
eq(K.pickSpot({x = 1, y = 1, z = 7}, cfg.fieldOffsets, function() return false end), nil, "no room")
-- many return portals share a temple: radius 4 gives 80 spots
eq(#K.ringOffsets(cfg.templeRadius), 80, "temple spots")

-- ---------------------------------------------------------------- channel and cooldown
local at = {x = 5, y = 5, z = 7}
local cast = K.castStart(1000, at, cfg.castMs)
eq(K.castStep(cast, 1500, at, false), "wait", "channelling")
eq(K.castStep(cast, 1500, {x = 6, y = 5, z = 7}, false), "moved", "a step interrupts")
eq(K.castStep(cast, 1500, at, true), "hit", "damage interrupts")
eq(K.castStep(cast, 1000 + cfg.castMs, at, false), "done", "done after castMs")
eq(cfg.castMs, 3000, "3 s channel")
eq(cfg.cooldownSeconds, 60, "60 s cooldown")
eq(cfg.portalMinutes, 5, "5 minute portals")
eq(K.cooldownLeft(100, 160), 60, "cooldown left")
eq(K.cooldownLeft(200, 160), 0, "cooldown over")
eq(K.cooldownLeft(200, -1), 0, "unset storage")

-- ---------------------------------------------------------------- who may use a pair
local party = {[1] = "A", [2] = "A", [3] = "B"}
local partyOf = function(g) return party[g] end
local pair = {owner = 1}
eq(K.mayUse(pair, 1, partyOf, true), true, "owner")
eq(K.mayUse(pair, 2, partyOf, true), true, "party member")
eq(K.mayUse(pair, 3, partyOf, true), false, "other party")
eq(K.mayUse(pair, 4, partyOf, true), false, "stranger")
eq(K.mayUse(pair, 2, partyOf, false), false, "party off")
eq(K.mayUse(nil, 1, partyOf, true), false, "no pair")

-- ---------------------------------------------------------------- the window rows
local rows = K.view(cfg, facts, 1, prices, data)
eq(#rows, #cfg.styles, "a row per style")
local byKey = {}
for _, r in ipairs(rows) do
	byKey[cfg.styles[_].key] = r
end
eq(byKey.emberforge.selected, true, "selected row")
assert(byKey.emberforge.how:find("250 Chaos Coins"), "price shown")
assert(byKey.abyssal.how:find("Colossus Hunter"), "achievement shown")
has.deaths_50 = nil
assert(byKey.gravecall.how:find("%?%?%?"), "a hidden achievement stays hidden until owned")

print(string.format("townportal_test: OK (%d styles: %d store, %d achievement)", #cfg.styles, routes.store, routes.achievement))
