-- Run from the server/ folder: luajit tests/collection_test.lua (and lua5.3; CI runs both)
-- The collection score (collection_core.lua, collection_config.lua, collection.lua): the shipped config against the
-- cosmetics, the store and the plate frames (milestones reachable, every reward real, the Collection cosmetics linked to
-- a milestone), points derived from prices and sources, the score with the title cap, milestones due and next, the
-- window's view, then collection.lua on a mocked engine (login sweep, claiming once, the rewards, staff, persistence
-- across characters, titles for the name plate, the hooks on a delivery and a grant).
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/collection_core.lua")
local K = ChaosCollectionCore
local cfg = dofile("data/scripts/chaos/collection_config.lua")
local cosCfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")
dofile("data/scripts/chaos/nameplate_core.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- points
eq(K.pricePoints(cfg, 0), 0, "free") eq(K.pricePoints(cfg, 1), 1, "at least one point")
eq(K.pricePoints(cfg, 50), 1, "50 coins") eq(K.pricePoints(cfg, 51), 2, "rounded up") eq(K.pricePoints(cfg, 750), 15, "750 coins")
eq(K.cosmeticPoints(cfg, {source = "store", price = 200}), 4, "a 200-coin cosmetic")
eq(K.cosmeticPoints(cfg, {source = "boss"}), 10, "a boss drop") eq(K.cosmeticPoints(cfg, {source = "achievement"}), 4, "an achievement")
eq(K.cosmeticPoints(cfg, {source = "collection"}), 0, "a collection reward is never counted")
eq(K.cosmeticPoints(cfg, {source = "unknown"}), 0, "an unknown source") eq(K.cosmeticPoints(cfg, nil), 0, "nothing")
-- the derived points never go by hand: a cosmetic of the shipped config is worth what its price or source says
local byKey, storePoints = {}, 0
for _, c in ipairs(cosCfg.cosmetics) do
	byKey[c.key] = c
	eq(K.cosmeticPoints(cfg, c) == (c.source == "store" and math.ceil(c.price / cfg.pricePerPoint) or (cfg.sourcePoints[c.source] or 0)),
		true, "points of " .. c.key)
	storePoints = storePoints + K.cosmeticPoints(cfg, c)
end
eq(storePoints > 0, true, "the cosmetics give points")

-- the catalogue: prices from the store, exclusives, the owned items of a wardrobe list
local cat = {mount = {{id = 5, look = 368}}, wings = {{id = 2, look = 1100}}, aura = {{id = 3, look = 1200}},
	shader = {{id = 7, name = "ember glow!"}}, outfit = {}}
local ix = K.lookIndex(cat)
eq(ix.mount[5], 368, "mount look") eq(ix.wings[2], 1100, "wings look") eq(ix.shader[7], "ember glow!", "shader name")
local fakeShop = {categories = {{offers = {
	{kind = "outfit", looktype = 128, lookfemale = 136, cost = 500}, {kind = "addons", looktype = 128, lookfemale = 136, cost = 150},
	{kind = "mount", id = 5, clientid = 368, cost = 450}, {kind = "wings", id = 2, cost = 250}, {kind = "aura", id = 3, cost = 150},
	{kind = "shader", id = 7, cost = 120}, {kind = "frame", frame = "ember", cost = 200}, {kind = "item", id = 1, cost = 5},
	{kind = "wings", id = 99, cost = 5}}}}}
local prices = K.priceMap(fakeShop, ix)
eq(prices["outfit:128"], 150, "the lowest price sells it") eq(prices["outfit:136"], 150, "female look")
eq(prices["mount:368"], 450, "mount by client look") eq(prices["wings:1100"], 250, "wings by XML id") eq(prices["aura:1200"], 150, "aura")
eq(prices["shader:ember_glow_"], 120, "shader by safe name") eq(prices["frame:ember"], 200, "frame") eq(prices["item:1"], nil, "items are no cosmetics")
local excl = K.exclusiveSet({{kind = "outfit", male = 300, female = 301}, {kind = "addons", male = 302, female = 303},
	{kind = "mount", id = 5}, {kind = "frame", frame = "laurel"}, {kind = "wings", id = 404}, {kind = "pet"}}, ix)
eq(excl["outfit:300"] and excl["outfit:303"] and excl["mount:368"] and excl["frame:laurel"], true, "exclusive items")
eq(excl["wings:404"], nil, "an id the catalogue lacks is left out")
local owned = K.wardrobeOwned({outfit = {{l = 128, o = 1}, {l = 130}}, mount = {{l = 368, o = 1}}, wings = {}, aura = {{l = 1200, o = 1}},
	shader = {{n = "ember glow!", o = 1}, {n = "x"}}})
eq(table.concat(owned, ","), "outfit:128,mount:368,aura:1200,shader:ember_glow_", "owned entries only")

-- the score
local ctx = {cosmetics = {kill_a = {key = "kill_a", kind = "killfx", source = "store", price = 200},
	boss_b = {key = "boss_b", kind = "footprint", source = "boss"}, reward = {key = "reward", kind = "chatcolor", source = "collection"}},
	prices = prices, exclusive = excl}
local score, groups = K.score(cfg, ctx, {"c:kill_a", "c:kill_a", "c:boss_b", "c:reward", "c:ghost", "w:outfit:128", "w:mount:368",
	"w:outfit:300", "w:outfit:999", "f:ember", "f:laurel", "m:trail"})
eq(score, 4 + 10 + 3 + 9 + 10 + 4 + 10, "kill 4, boss 10, outfit 3, mount 9, exclusive outfit 10, frame 4, exclusive frame 10")
eq(groups.killfx.p, 4, "kill effect group") eq(groups.outfit.n, 2, "two outfits count") eq(groups.frame.p, 14, "frames")
eq(groups.chatcolor, nil, "the reward is not counted") eq(groups.footprint.p, 10, "boss footprint")
local titles = {}
for i = 1, 14 do titles[i] = "t:key" .. i end
local ts, tg = K.score(cfg, ctx, titles)
eq(ts, cfg.titleMax * cfg.titlePoints, "titles stop at the cap") eq(tg.title.n, cfg.titleMax, "counted")
eq(K.maxScore(cfg, ctx) >= 4 + 10 + 150 / 50 + 10, true, "maxScore adds the catalogue")

-- milestones
local first, last = K.sorted(cfg)[1], K.sorted(cfg)[#cfg.milestones]
eq(K.nextMilestone(cfg, 0).key, first.key, "first milestone ahead") eq(K.nextMilestone(cfg, last.points), nil, "none above the last")
eq(#K.due(cfg, first.points - 1, {}), 0, "below the first") eq(#K.due(cfg, first.points, {}), 1, "the first is due")
eq(#K.due(cfg, last.points, {}), #cfg.milestones, "all due at once for a big collection")
eq(#K.due(cfg, last.points, {[first.key] = 1}), #cfg.milestones - 1, "claimed ones are not due again")
local tt = K.titlesOf(cfg, {collector = 100, connoisseur = 300})
eq(#tt, 2, "two titles held") eq(tt[1].key, "collection:collector", "key") eq(tt[2].frame, "gallery", "the Connoisseur plate frame")
eq(tt[2].at, 300, "earned at")
local view = K.view(cfg, 70, groups, {collector = 1, trail = 2}, byKey)
eq(view.score, 70, "view score") eq(view.next.points, 120, "next milestone") eq(view.next.left, 50, "points left")
eq(view.milestones[1].done, true, "done") eq(view.milestones[3].done, nil, "not done")
eq(view.milestones[2].rewards[1].k, "footprint", "the reward is a footprint") eq(view.milestones[2].rewards[1].n, "Laurel Steps", "named")
eq(view.milestones[5].rewards[1].f, "gallery", "title with a frame")
eq(K.view(cfg, 5000, {}, {}, byKey).next, nil, "no next above the last milestone")

-- the shipped config
local frames = ChaosNameplate.FRAMES
-- (the wings, auras and shaders need data/XML of the installed server: the outfits, mounts, frames and cosmetics alone
-- already give more than the last milestone)
local shipped = K.priceMap(shop, K.lookIndex({}))
local problems = K.validate(cfg, {cosmetics = cosCfg.cosmetics, frames = frames, maxScore = K.maxScore(cfg, {cosmetics = byKey,
	prices = shipped, exclusive = {}})})
eq(K.maxScore(cfg, {cosmetics = byKey, prices = shipped, exclusive = {}}) >= 2 * last.points, true, "the last milestone is far from the cap")
for _, p in ipairs(problems) do print("problem: " .. p) end
eq(#problems, 0, "shipped config validates")
eq(cfg.opcode, ChaosOpcodes.cosmetics, "the cosmetics opcode, no opcode of its own")
local function broken(change)
	local copy = {}
	for k, v in pairs(cfg) do copy[k] = v end
	copy.milestones = {}
	for i, m in ipairs(cfg.milestones) do
		local mm = {}
		for k, v in pairs(m) do mm[k] = v end
		mm.rewards = {}
		for j, r in ipairs(m.rewards) do
			mm.rewards[j] = {}
			for k, v in pairs(r) do mm.rewards[j][k] = v end
		end
		copy.milestones[i] = mm
	end
	change(copy.milestones)
	return table.concat(K.validate(copy, {cosmetics = cosCfg.cosmetics, frames = frames, maxScore = 100000}), "\n")
end
eq(broken(function(l) l[2].points = 20 end):find("used twice", 1, true) ~= nil, true, "two milestones at one score")
eq(broken(function(l) l[1].rewards[1].text = ("x"):rep(30) end):find("characters", 1, true) ~= nil, true, "a long title")
eq(broken(function(l) l[5].rewards[1].frame = "nope" end):find("no picture", 1, true) ~= nil, true, "an unknown plate frame")
eq(broken(function(l) l[2].rewards[1].key = "kill_soulspark" end):find("source collection", 1, true) ~= nil, true, "a sold cosmetic is no reward")
eq(broken(function(l) l[2].points = 61 end):find("granted at", 1, true) ~= nil, true, "the cosmetic and the milestone must agree")
eq(broken(function(l) l[1].rewards = {} end):find("at least one reward", 1, true) ~= nil, true, "a milestone without a reward")
eq(broken(function(l) l[4].rewards = {{kind = "title", text = "Gold"}} end):find("no milestone grants it", 1, true) ~= nil, true,
	"a collection cosmetic nobody grants")
eq(K.validate(cfg, {cosmetics = cosCfg.cosmetics, frames = frames, maxScore = 100})[1] ~= nil, true, "a milestone above the catalogue")
-- the rewards are cosmetic: no power fields anywhere
for _, m in ipairs(cfg.milestones) do
	for _, r in ipairs(m.rewards) do
		for k in pairs(r) do
			eq(k == "kind" or k == "text" or k == "frame" or k == "key", true, "reward field " .. k)
		end
	end
end

-- ---------------------------------------------------------------- collection.lua on a mocked engine
local sent, inbox, seq = {}, {}, 0
json = {encode = function(t) seq = seq + 1; local k = "{J" .. seq .. "}"; inbox[k] = t; return k end, decode = function(s) return inbox[s] end}
MESSAGE_INFO_DESCR = 22
local rows, queries = {}, {} -- rows[account] = {{entry, at}}
db = {query = function(q)
	queries[#queries + 1] = q
	local acc, entry, at = q:match("VALUES %((%d+), '([^']+)', (%d+)%)")
	if acc then
		rows[tonumber(acc)] = rows[tonumber(acc)] or {}
		for _, r in ipairs(rows[tonumber(acc)]) do
			if r.entry == entry then return true end
		end
		table.insert(rows[tonumber(acc)], {entry = entry, at = tonumber(at)})
	end
	return true
end, storeQuery = function(q)
	local acc = tonumber(q:match("`account_id` = (%d+)"))
	if acc and rows[acc] and #rows[acc] > 0 then return {acc = acc, i = 1} end
	return false
end}
result = {getString = function(r, col) return rows[r.acc][r.i].entry end, getNumber = function(r, col) return rows[r.acc][r.i].at end,
	next = function(r) r.i = r.i + 1; return r.i <= #rows[r.acc] end, free = function() end}
local timers = {}
addEvent = function(fn, ms, ...) timers[#timers + 1] = {fn = fn, ms = ms, args = {...}} end
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do t.fn((unpack or table.unpack)(t.args)) end
end
local registered = {}
local function event()
	return function(name)
		local e = {name = name}
		function e:register() registered[name] = self end
		return e
	end
end
CreatureEvent, GlobalEvent = event(), event()
local players = {}
Game = {getPlayers = function() return players end}
local function newPlayer(id, name, account, staff)
	local p = {id = id, name = name, account = account, st = {}, msgs = {}}
	function p:getId() return self.id end
	function p:getName() return self.name end
	function p:getAccountId() return self.account end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:getGroup() return {getAccess = function() return staff == true end} end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	players[#players + 1] = p
	return p
end
-- stand-ins for the systems collection.lua reads
local wardrobeOwned = {} -- player name -> list in ChaosWardrobeCore.list's shape
ChaosShopConfig = fakeShop
ChaosCosmeticsConfig = cosCfg
ChaosWardrobe = {catalogueOf = function() return {cat = cat} end, list = function(p) return wardrobeOwned[p.name] or {} end}
dofile("data/scripts/chaos/shop_core.lua")
local cosOwned, granted = {}, {}
ChaosCosmetics = {ownedOf = function(acc) cosOwned[acc] = cosOwned[acc] or {}; return cosOwned[acc] end,
	grant = function(acc, key, source) cosOwned[acc] = cosOwned[acc] or {}; if cosOwned[acc][key] then return false, "owned" end
		cosOwned[acc][key] = true; granted[#granted + 1] = {acc, key, source}; return true end,
	sendState = function(p) p.stateSent = (p.stateSent or 0) + 1 end}
local titleHeld = {}
local titleSources = {}
ChaosTitles = {register = function(name, fn) titleSources[name] = fn end, of = function(p) return titleHeld[p.name] or {} end}
local refreshed = 0
ChaosNameplate.refresh = function() refreshed = refreshed + 1 end
ChaosNotify = {send = function(p, title, text) p.toast = title .. ": " .. text end}
ChaosShop = {deliver = function(player, offer) return offer ~= "fail" end}

dofile("data/scripts/chaos/collection.lua")
local M = ChaosCollection
eq(type(titleSources.collection), "function", "the title source is registered")
eq(registered.ChaosCollectionStartup.onStartup(), true, "startup")
eq(queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_collection`", 1, true) ~= nil, true, "the table is created")

local ann = newPlayer(1, "Ann", 10)
eq(M.refresh(ann).score, 0, "an empty account has 0 points")
eq(titleSources.collection(ann), nil, "no titles yet")
-- Ann owns a 450-coin mount (9), an outfit (150 coins, 3) and two 200-coin cosmetics (8): 20 points = Collector
wardrobeOwned.Ann = {mount = {{l = 368, o = 1}}, outfit = {{l = 128, o = 1}}}
cosOwned[10] = {lvl_dawn = true, kill_soulspark = true}
local v = M.refresh(ann)
eq(v.score, 20, "20 points") eq(v.milestones[1].done, true, "the first milestone is reached")
eq(#ann.msgs, 1, "told once") eq(ann.msgs[1]:find("Collector", 1, true) ~= nil, true, "the reward is named")
eq(ann.toast ~= nil, true, "a toast too") eq(refreshed, 1, "the name plate is refreshed")
eq(#granted, 0, "a title grants no cosmetic")
local held = titleSources.collection(ann)
eq(#held, 1, "the title is held") eq(held[1].text, "Collector", "Collector") eq(held[1].key, "collection:collector", "key")
M.refresh(ann)
eq(#ann.msgs, 1, "claimed once, kept") eq(refreshed, 1, "no second refresh")
-- the second milestone grants the footstep trail
wardrobeOwned.Ann.mount = {{l = 368, o = 1}, {l = 1, o = 1}}
cosOwned[10].rare_gilded = true
cosOwned[10].lvl_ember = true
cosOwned[10].lvl_frost = true
cosOwned[10].emote_roar = true
for _, key in ipairs({"skin_warrior_void", "skin_warrior_storm", "skin_ranger_sunfire", "skin_mystic_voidfire", "kill_shatter",
	"kill_bloodbloom", "chat_cinder", "chat_frost", "foot_ember", "foot_frost", "glow_gold"}) do
	cosOwned[10][key] = true
end
v = M.refresh(ann)
eq(v.score >= 60, true, "past 60 points: " .. v.score)
eq(granted[1] and granted[1][2], "foot_collector", "Laurel Steps granted") eq(granted[1][3], "collection", "from the collection")
eq(v.milestones[2].done, true, "trail reached") eq(M.scoreOf(10), v.score, "scoreOf")
-- the stored rows: wardrobe items and the milestones, no cosmetics
local stored = {}
for _, r in ipairs(rows[10]) do stored[r.entry] = true end
eq(stored["w:mount:368"] and stored["w:outfit:128"] and stored["m:collector"] and stored["m:trail"], true, "items and milestones stored")
eq(stored["c:lvl_dawn"], nil, "cosmetics are read live, not stored")
-- a second character of the account adds its own items; a fresh server start reads the rows back
local ann2 = newPlayer(2, "Ann Two", 10)
wardrobeOwned["Ann Two"] = {wings = {{l = 1100, o = 1}}}
local before = v.score
eq(M.refresh(ann2).score, before + 5, "the other character's wings add 5 (250 coins)")
M.state = {}
eq(M.refresh(ann).score, before + 5, "the rows are read back (items of both characters)")
eq(#granted, 1, "and nothing is granted twice")
eq(#titleSources.collection(ann), 1, "the Collector title is still held")

-- staff count no wardrobe and hold no collection titles
local gm = newPlayer(3, "Gm", 30, true)
wardrobeOwned.Gm = {outfit = {{l = 128, o = 1}, {l = 130, o = 1}}, mount = {{l = 368, o = 1}}}
titleHeld.Gm = {{key = "staff", text = "Administrator"}}
eq(M.refresh(gm).score, 0, "a staff character with the whole wardrobe has 0 points")
-- titles of the character count; the collection's own never do
local bea = newPlayer(4, "Bea", 40)
titleHeld.Bea = {{key = "season:champion", text = "Champion"}, {key = "collection:collector", text = "Collector"},
	{key = "staff", text = "Tutor"}}
eq(M.refresh(bea).score, cfg.titlePoints, "one title counts")
-- a frame the character owns
bea.st[Chaos.storage.shopFrameBase + 3] = 1 -- slot 3 = ember
eq(M.refresh(bea).score, cfg.titlePoints + 4, "the ember plate frame adds 4 (200 coins)")

-- touching: one sweep however many touches, then the window is told
local c1 = newPlayer(5, "Cy", 50)
timers = {}
M.touch(50) M.touch(50) M.touch(50)
eq(#timers, 1, "one sweep scheduled") eq(timers[1].ms, cfg.syncDelayMs, "after the delay")
runTimers()
eq(c1.stateSent, 1, "the cosmetics window state is sent")
M.touch(50) eq(#timers, 1, "a new sweep may be scheduled after the first ran") runTimers()
registered.ChaosCollectionLogin.onLogin(c1) eq(#timers, 1, "login schedules a sweep") runTimers()
-- the hooks: a delivery and a grant touch the account, the collection's own grants do not
timers = {}
eq(ChaosShop.deliver(c1, "ok"), true, "delivery passes through") eq(#timers, 1, "a delivery schedules a sweep") runTimers()
eq(ChaosShop.deliver(c1, "fail"), false, "a failed delivery") eq(#timers, 0, "does not")
eq(ChaosCosmetics.grant(50, "kill_shatter", "store"), true, "grant passes through") eq(#timers, 1, "a store grant schedules a sweep") runTimers()
eq(ChaosCosmetics.grant(50, "kill_shatter", "store"), false, "an owned one is refused") eq(#timers, 0, "no sweep")
eq(ChaosCosmetics.grant(50, "chat_collector", "collection"), true, "a collection grant") eq(#timers, 0, "does not loop")
-- the last character of an account logging out drops the cached state
registered.ChaosCollectionLogout.onLogout(c1)
players = {ann, ann2, gm, bea}
runTimers()
eq(M.state[50], nil, "state dropped when the account has nobody online")

print(string.format("collection_test: %d checks OK", n))
