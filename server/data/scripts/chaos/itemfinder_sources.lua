-- Item finder: what the data of every system gives, as index rows (pure: no engine API). itemfinder.lua passes the
-- loaded tables and an emit(kind, serverId, row) that adds a row to the index (ChaosItemFinderCore.add); the rows
-- follow itemfinder_core.lua's format. Tests: server/tests/itemfinder_test.lua (mocked tables and the real configs).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- S.monsters      MonsterType:getLoot() of every monster (the engine reads them), chance x the loot rate
-- S.lootLayer     the Chaos loot layer: currency entries, gems, uniques (loot_config.lua, chaos_gems_config.lua,
--                 ChaosUniqueItems through ChaosLoot.uniqueList)
-- S.crafting      the base crafting tables (the global Crafting of the base crafting script)
-- S.npcs          NPC shops (the engine parses the NPC files)
-- S.store         the Chaos store (shop_config.lua)
-- S.gamble        the Gambler's pool (gamble_config.lua)
-- S.professions   gathering, the Material Broker (professions_config.lua)
-- S.salvage       salvage shards and the shard recipes (salvage_config.lua)
-- S.gemCombining  three gems of a tier make one of the next (chaos_gems_config.lua)
-- S.REWARDS       one function per reward system (daily reward, bounty, rifts, tower, world bosses, invasions, arena,
--                 battleground, guild boss, the Descent, the raid, dungeons, treasure goblins, achievements, factions,
--                 the Ascended Omens); S.rewards runs them all, each in a pcall, and returns the errors

ChaosItemFinderSources = ChaosItemFinderSources or {}
local S = ChaosItemFinderSources
local K = ChaosItemFinderCore
local floor = math.floor

S.TIERS = {"normal", "magic", "rare", "legendary", "boss"}

local function cap(s)
	s = tostring(s or "")
	return (s:gsub("^%l", string.upper))
end

local function items(list, fn)
	for _, e in ipairs(list or {}) do
		local id = tonumber(e.id or e.itemId or e[1])
		if id then
			fn(id, tonumber(e.count or e[2]) or 1, e)
		end
	end
end

-- "magic 1.5%, rare 6%, legendary 25%, boss 40%" of a per-10000 table by monster tier (normal first when it has one)
function S.tierText(chance)
	local parts = {}
	for _, t in ipairs(S.TIERS) do
		local v = tonumber((chance or {})[t]) or 0
		if v > 0 then
			parts[#parts + 1] = t .. " " .. K.per10k(v)
		end
	end
	return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------- monsters
-- list = {{name, boss, level, band, places = {texts}, loot = MonsterType:getLoot()}}; opts.rate = the loot rate
function S.monsters(list, emit, opts)
	local rate = tonumber(opts and opts.rate) or 1
	for _, m in ipairs(list or {}) do
		local d = {} -- the boss flag is the row's b (the client marks the name)
		if m.band then
			d[#d + 1] = "level " .. m.band
		elseif (tonumber(m.level) or 0) > 0 then
			d[#d + 1] = "level " .. m.level
		end
		if m.places and #m.places > 0 then
			d[#d + 1] = table.concat(m.places, "; ")
		end
		local detail = #d > 0 and table.concat(d, ", ") or nil
		local function walk(rows, mult)
			for _, l in ipairs(rows or {}) do
				local id = tonumber(l.itemId)
				local chance = (tonumber(l.chance) or 0) * mult
				if id and chance > 0 then
					local eff = math.min(100000, chance * rate)
					emit("monster", id, {n = m.name, d = detail, v = K.pct(eff),
						c = K.countText(1, tonumber(l.maxCount) or 1), b = m.boss or nil, o = -eff})
					if type(l.childLoot) == "table" and #l.childLoot > 0 then
						walk(l.childLoot, mult * math.min(100000, chance) / 100000)
					end
				end
			end
		end
		walk(m.loot, 1)
	end
end

-- ---------------------------------------------------------------- the Chaos loot layer
-- lootCfg = loot_config.lua; gems = chaos_gems_config.lua; uniques = ChaosLoot.uniqueList(); monsterName(key) -> shown
-- name (the unique lists name monster types in lower case)
function S.lootLayer(lootCfg, gems, uniques, emit, monsterName)
	local cur = lootCfg and lootCfg.currency
	for _, e in ipairs(cur and cur.entries or {}) do
		local c = e.count or {1, 1}
		emit("drop", e.id, {n = "Any monster", d = S.tierText(e.chance) .. " a kill (x item find)",
			v = K.per10k((e.chance or {}).normal or 0), c = K.countText(c[1], c[2]),
			o = -(tonumber((e.chance or {}).legendary) or 0)})
	end
	if gems and gems.drop and gems.types and gems.tiers then
		local text = S.tierText(gems.drop.chance) .. " a kill for a gem of a random type; the quality by the monster's level"
		for t = 1, #gems.types do
			for q = 1, #gems.tiers do
				emit("drop", gems.firstId + (t - 1) * #gems.tiers + (q - 1), {n = "Any monster", d = text,
					v = K.per10k(gems.drop.chance.normal or 0), o = 0})
			end
		end
	end
	local um = lootCfg and lootCfg.unique and lootCfg.unique.tierMult or {}
	for _, u in ipairs(uniques or {}) do
		local from = u.bossOnly and "boss" or (u.minTier or "normal")
		if from == "normal" then
			from = "magic"
		end
		local best = (tonumber(u.chance) or 0) * (tonumber(um.boss) or tonumber(um.legendary) or 1)
		local where
		if type(u.monsters) == "table" and #u.monsters > 0 then
			local names = {}
			for i, key in ipairs(u.monsters) do
				if i > 3 then
					names[#names + 1] = "+" .. (#u.monsters - 3)
					break
				end
				names[#names + 1] = monsterName and monsterName(key) or cap(key)
			end
			where = table.concat(names, ", ")
		end
		local d = (where and (where .. "; ") or "any monster; ") ..
			(u.bossOnly and "bosses only" or (from .. " and better")) ..
			((tonumber(u.minMonsterLevel) or 0) > 0 and (", monster level " .. u.minMonsterLevel .. "+") or "") ..
			(u.season and ", season characters" or "")
		emit("drop", u.id, {n = "Unique drop", d = d, v = K.per10k(best), o = -best})
	end
end

-- ---------------------------------------------------------------- the base crafting tables
-- Crafting = the base script's global ({category = {{id, name, level, cost, count, storage, storageText,
-- materials = {{id, count}}}}}); cfg = itemfinder_config.lua (station names and order)
function S.crafting(Crafting, cfg, emit)
	if type(Crafting) ~= "table" then
		return
	end
	local order, seen = {}, {}
	for _, cat in ipairs(cfg.craftOrder or {}) do
		order[#order + 1] = cat
		seen[cat] = true
	end
	local rest = {}
	for cat, list in pairs(Crafting) do
		if type(cat) == "string" and type(list) == "table" and not seen[cat] then
			rest[#rest + 1] = cat
		end
	end
	table.sort(rest)
	for _, cat in ipairs(rest) do
		order[#order + 1] = cat
	end
	for _, cat in ipairs(order) do
		local station = (cfg.craftStations or {})[cat] or cap(cat)
		for _, r in ipairs(type(Crafting[cat]) == "table" and Crafting[cat] or {}) do
			local id = tonumber(r.id)
			if id and type(r.materials) == "table" then
				local d = "level " .. (tonumber(r.level) or 0)
				if (tonumber(r.cost) or 0) > 0 then
					d = d .. ", " .. K.gold(r.cost)
				end
				if (tonumber(r.storage) or 0) > 0 then
					d = d .. ", " .. ((r.storageText or "") ~= "" and r.storageText or "learned first")
				end
				local m = {}
				for _, mat in ipairs(r.materials) do
					m[#m + 1] = {mat.id, mat.count or 1}
				end
				emit("craft", id, {n = station, d = d, c = K.countText(r.count or 1), m = m, o = tonumber(r.level) or 0})
				for _, mat in ipairs(r.materials) do
					emit("usedin", mat.id, {ref = id, d = station .. ", level " .. (tonumber(r.level) or 0),
						v = "x" .. K.int(mat.count or 1), o = tonumber(r.level) or 0})
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- NPC shops
-- npcs = {{name, places = text or nil, buy = {{id, price}}, sell = {{id, price}}}}
function S.npcs(npcs, emit)
	for _, npc in ipairs(npcs or {}) do
		for _, e in ipairs(npc.buy or {}) do
			emit("shop", e.id, {n = npc.name, d = npc.places, v = K.gold(e.price), o = e.price})
		end
		for _, e in ipairs(npc.sell or {}) do
			emit("sellto", e.id, {n = npc.name, d = npc.places, v = K.gold(e.price), o = -e.price})
		end
	end
end

-- ---------------------------------------------------------------- the Chaos store
local function storeItem(part)
	if type(part) == "string" then
		local id, n = part:match("^item:(%d+)x(%d+)$")
		if not id then
			id = part:match("^item:(%d+)$")
		end
		return tonumber(id), tonumber(n) or 1
	elseif type(part) == "table" and part.kind == "item" then
		return tonumber(part.id), tonumber(part.count) or 1
	end
	return nil
end

function S.store(shopCfg, emit)
	for _, cat in ipairs(shopCfg and shopCfg.categories or {}) do
		for _, o in ipairs(cat.offers or {}) do
			local price = tonumber(o.cost) or 0
			local limits = {}
			if o.weeklyLimit then
				limits[#limits + 1] = o.weeklyLimit .. " a week"
			end
			if o.oncePerAccount then
				limits[#limits + 1] = "once per account"
			end
			if o.maxLevel then
				limits[#limits + 1] = "up to level " .. o.maxLevel
			end
			local d = (cat.name or "Store") .. (#limits > 0 and (", " .. table.concat(limits, ", ")) or "")
			local v = price > 0 and (K.int(price) .. " Chaos Coins") or nil
			if o.kind == "item" then
				local id, n = storeItem(o)
				if id then
					emit("store", id, {n = o.name or "Chaos store", d = d, v = v, c = K.countText(n), o = price})
				end
			elseif o.kind == "bundle" then
				for _, part in ipairs(o.parts or {}) do
					local id, n = storeItem(part)
					if id then
						emit("store", id, {n = o.name or "Bundle", d = d .. ", bundle", v = v, c = K.countText(n), o = price})
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- the Gambler
function S.gamble(g, emit)
	if not g or g.enabled == false then
		return
	end
	for _, slot in ipairs(g.stock and g.stock.order or {}) do
		for _, e in ipairs((g.pool or {})[slot] or {}) do
			emit("gamble", e[1], {n = "The Gambler", d = slot .. ", sealed (the rarity shows when bought), from level " .. e[2],
				o = e[2]})
		end
	end
end

-- ---------------------------------------------------------------- professions
function S.professions(P, emit)
	if not P then
		return
	end
	local profs, tiers = {}, P.tiers or {}
	for _, p in ipairs(P.professions or {}) do
		profs[p.key] = p
	end
	for _, m in ipairs(P.materials or {}) do
		local p, t = profs[m.prof] or {name = cap(m.prof)}, tiers[m.tier] or {}
		local where = {}
		for _, a in ipairs(P.areas or {}) do
			if a.tier == m.tier and (a.nodes or {})[m.prof] then
				where[#where + 1] = a.name
			end
		end
		local d = string.format("tier %d%s, %s level %d, character level %d", m.tier, t.name and (" (" .. t.name .. ")") or "",
			p.name, tonumber(t.profLevel) or 0, tonumber(t.charLevel) or 0)
		if #where > 0 then
			d = d .. "; " .. table.concat(where, ", ")
		end
		emit("gather", m.id, {n = p.name or cap(m.prof), d = d, o = m.tier})
		local b = P.broker or {}
		if t.price then
			emit("sellto", m.id, {n = b.npc or "Material Broker", d = "every town, next to the temple; the week's demand changes it",
				v = K.gold(t.price), o = -t.price})
		end
	end
	for _, tool in ipairs(P.broker and P.broker.tools or {}) do
		emit("shop", tool.id, {n = P.broker.npc or "Material Broker", d = "every town, next to the temple", v = K.gold(tool.price),
			o = tool.price})
	end
end

-- ---------------------------------------------------------------- salvage, gems, orbs
-- orbId(key) -> the server id of a crafting orb (ChaosCrafting.config.orbs)
function S.salvage(sv, orbId, emit)
	if not sv or not sv.shard then
		return
	end
	emit("craft", sv.shard.id, {n = "Salvage", d = "gear with a rarity (Economy > Salvage); more for a higher rarity",
		o = 0})
	for _, r in ipairs(sv.recipes or {}) do
		local id = orbId and orbId(r.key)
		if id then
			emit("craft", id, {n = "Salvage bench", d = "combine rune shards (Economy > Salvage)", m = {{sv.shard.id, r.cost}}, o = 1})
			emit("usedin", sv.shard.id, {ref = id, d = "Salvage bench", v = "x" .. K.int(r.cost)})
		end
	end
end

function S.gemCombining(gems, emit)
	if not gems or not gems.types or not gems.tiers then
		return
	end
	local n = #gems.tiers
	for t = 1, #gems.types do
		for q = 2, n do
			local from = gems.firstId + (t - 1) * n + (q - 2)
			local to = from + 1
			emit("craft", to, {n = "Gem combining", d = "three of the tier below (the crafting bench)", m = {{from, 3}}, o = q})
			emit("usedin", from, {ref = to, d = "Gem combining", v = "x3"})
		end
	end
end

-- ---------------------------------------------------------------- rewards
local function reward(emit, id, count, n, d, o)
	emit("reward", id, {n = n, d = d, c = K.countText(count), o = o or 0})
end

S.REWARDS = {}

-- D.daily = Chaos.daily (chaos_constants.lua), D.dailyStreak = daily_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "daily", fn = function(D, emit)
	local daily = D.daily or {}
	for day, r in ipairs(daily.rewards or {}) do
		reward(emit, r.itemId, r.count, "Daily reward", "day " .. day .. " of the 7-day cycle", day)
	end
	items(daily.weekBonus, function(id, n) reward(emit, id, n, "Daily reward", "a full week: with day 7", 8) end)
	for _, m in ipairs(D.dailyStreak and D.dailyStreak.milestones or {}) do
		items(m.items, function(id, n) reward(emit, id, n, "Login streak", m.days .. " days in a row", 10 + m.days) end)
	end
end}

S.REWARDS[#S.REWARDS + 1] = {key = "bounty", fn = function(D, emit)
	local b = D.bounty
	if not b then
		return
	end
	for _, band in ipairs(b.bands or {}) do
		local lv = band.max >= 999999 and ("level " .. band.min .. "+") or ("levels " .. band.min .. "-" .. band.max)
		for key, id in pairs(b.items or {}) do
			local n = band.reward and tonumber(band.reward[key]) or 0
			if n > 0 then
				reward(emit, id, n, "Bounty contract", lv .. ", every finished contract", band.min)
			end
			local w = band.weekly and tonumber(band.weekly[key]) or 0
			if w > 0 then
				reward(emit, id, w, "Bounty weekly chest", lv .. ", " .. (b.weeklyNeed or 7) .. " contracts in a week", band.min)
			end
		end
	end
	items(b.weeklyExtra, function(id, n) reward(emit, id, n, "Bounty weekly chest", (b.weeklyNeed or 7) .. " contracts in a week", 0) end)
end}

-- D.rift = rift_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "rift", fn = function(D, emit)
	local r = D.rift
	if not r then
		return
	end
	local rw = r.reward or {}
	for key, id in pairs(rw.items or {}) do
		local c = rw[key]
		if type(c) == "table" then
			reward(emit, id, nil, "Rift chest", string.format("every finisher: %s + %s per rift tier (more with the quantity bonus)",
				tostring(c.base or 0), tostring(c.perTier or 0)), 0)
		end
	end
	if r.key and r.key.itemId then
		local kd = r.keyDrop or {}
		reward(emit, r.key.itemId, nil, "Rift completion", string.format("the next key: %d%% + %d%% per modifier (at most %d%%)",
			kd.base or 0, kd.perMod or 0, kd.max or 0), 1)
		if r.eliteKeyChance then
			reward(emit, r.key.itemId, nil, "Rift monsters", string.format("rare %d%%, legendary %d%% a key of the rift's tier",
				r.eliteKeyChance.rare or 0, r.eliteKeyChance.legendary or 0), 2)
		end
		if r.monsterKey then
			local mk = r.monsterKey
			emit("drop", r.key.itemId, {n = "Any monster", d = string.format("tier 1 key, monster level %d+, x%d legendary, x%d boss",
				mk.minMonsterLevel or 0, (mk.tierMult or {}).legendary or 1, (mk.tierMult or {}).boss or 1), v = K.pct(mk.chance), o = 0})
		end
		if r.bountyKey then
			reward(emit, r.key.itemId, nil, "Bounty contract", string.format("a tier 1 key: hunt %d%%, elite %d%%, boss %d%%",
				r.bountyKey.hunt or 0, r.bountyKey.elite or 0, r.bountyKey.boss or 0), 3)
		end
	end
	local om = r.omen
	if om and om.fragment then
		local ch = om.chest or {}
		reward(emit, om.fragment.id, nil, "Rift chest", string.format("rifts of tier %d+: %d + %d per tier above", om.minTier or 0,
			ch.base or 0, ch.perTier or 0), 0)
		if om.eliteChance then
			emit("drop", om.fragment.id, {n = "Rift monsters", d = string.format("tier %d+ rifts: rare %d%%, legendary %d%%",
				om.minTier or 0, om.eliteChance.rare or 0, om.eliteChance.legendary or 0), o = 0})
		end
		if om.key then
			emit("craft", om.key.id, {n = "Omen binding", d = "bind omen fragments (use them)", m = {{om.fragment.id, om.keyCost or 1}}, o = 0})
			emit("usedin", om.fragment.id, {ref = om.key.id, d = "Omen binding", v = "x" .. (om.keyCost or 1), o = 0})
		end
	end
end}

-- D.tower = Chaos.tower
S.REWARDS[#S.REWARDS + 1] = {key = "tower", fn = function(D, emit)
	local t = D.tower
	if not t then
		return
	end
	for _, m in ipairs(t.milestones or {}) do
		items(m.items, function(id, n) reward(emit, id, n, "Infinity Tower", K.int(m.points) .. " season points", m.points) end)
	end
	for place, chest in ipairs(t.seasonEnd and t.seasonEnd.chests or {}) do
		items(chest.items, function(id, n) reward(emit, id, n, "Infinity Tower season", "place " .. place .. ": " .. chest.name, place) end)
	end
end}

-- D.worldBoss = Chaos.worldBoss
S.REWARDS[#S.REWARDS + 1] = {key = "worldboss", fn = function(D, emit)
	local r = D.worldBoss and D.worldBoss.reward
	if not r then
		return
	end
	items(r.base, function(id, n) reward(emit, id, n, "World boss", "every rewarded player", 0) end)
	items(r.pool, function(id, n) reward(emit, id, n, "World boss", "a pool split by contribution", 1) end)
	for _, cat in ipairs(r.podium and r.podium.categories or {}) do
		for place, list in ipairs(cat.rewards or {}) do
			items(list, function(id, n) reward(emit, id, n, "World boss", (cat.name or "") .. " place " .. place, 1 + place) end)
		end
	end
end}

-- D.invasion = invasion_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "invasion", fn = function(D, emit)
	local inv = D.invasion
	if not inv then
		return
	end
	local r = inv.rewards or {}
	items(r.base, function(id, n) reward(emit, id, n, "Invasion", "every rewarded player", 0) end)
	items(r.pool, function(id, n) reward(emit, id, n, "Invasion", "a pool split by contribution", 1) end)
	for place, list in ipairs(r.top or {}) do
		items(list, function(id, n) reward(emit, id, n, "Invasion", "place " .. place, 1 + place) end)
	end
	for _, ev in pairs(inv.events or inv.worldEvents or {}) do
		if type(ev) == "table" and type(ev.items) == "table" and ev.npc then
			for _, e in ipairs(ev.items) do
				emit("shop", e.id, {n = ev.npc, d = "during the " .. (ev.name or ev.npc) .. " world event", v = K.gold(e.price),
					o = e.price})
			end
		end
	end
end}

S.REWARDS[#S.REWARDS + 1] = {key = "arena", fn = function(D, emit)
	local r = D.arena and D.arena.reward
	if not r then
		return
	end
	items(r.win, function(id, n) reward(emit, id, n, "Arena", "every win (" .. (r.maxRewardedWinsPerDay or 10) .. " a day)", 1) end)
	items(r.firstWin, function(id, n) reward(emit, id, n, "Arena", "the first win of the day", 0) end)
end}

S.REWARDS[#S.REWARDS + 1] = {key = "battleground", fn = function(D, emit)
	local b = D.battleground
	if not b then
		return
	end
	items(b.firstWinItems, function(id, n) reward(emit, id, n, "Battleground", "the first win of the week", 0) end)
	for _, v in ipairs(b.vendor or {}) do
		if v.kind == "item" and v.id then
			emit("store", v.id, {n = "Battleground vendor", d = "honor from battleground matches", v = K.int(v.cost) .. " honor",
				c = K.countText(v.count or 1), o = v.cost})
		end
	end
end}

S.REWARDS[#S.REWARDS + 1] = {key = "guildboss", fn = function(D, emit)
	local g = D.guildboss
	if not g then
		return
	end
	items(g.reward and g.reward.orbs, function(id, n) reward(emit, id, n, "Guild boss", "every player of the kill", 0) end)
	for _, m in ipairs(g.materials or {}) do
		emit("use", m.id, {n = "Guild boss ember stone", d = "donate it to your guild's stone", v = K.int(m.embers) .. " embers",
			o = -(m.embers or 0)})
	end
end}

-- D.descent = descent_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "descent", fn = function(D, emit)
	local r = D.descent and D.descent.rewards
	if not r then
		return
	end
	for _, o in ipairs(r.orbs or {}) do
		reward(emit, o.id, nil, "The Descent", "one every " .. o.every .. " rooms cleared", o.every)
	end
	for _, u in ipairs(r.uniques or {}) do
		reward(emit, u.id, nil, "The Descent", "a unique roll from room " .. u.minDepth .. " (only there)", 100 + u.minDepth)
	end
end}

-- D.raid = raid_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "raid", fn = function(D, emit)
	local raid = D.raid
	if not raid then
		return
	end
	local names = {}
	for _, b in ipairs(raid.bosses or {}) do
		names[b.key] = b.name
	end
	for _, u in ipairs(raid.uniques or {}) do
		local list = {}
		for _, key in ipairs(u.bosses or {}) do
			list[#list + 1] = names[key] or cap(key)
		end
		reward(emit, u.id, nil, raid.name or "The raid", "a unique roll: " .. table.concat(list, ", ") .. " (only there)", 0)
	end
end}

-- D.dungeons = Chaos.dungeons (extra: the loot each dungeon's window shows for its boss)
S.REWARDS[#S.REWARDS + 1] = {key = "dungeons", fn = function(D, emit)
	local ex = D.dungeons and D.dungeons.extra
	if type(ex) ~= "table" then
		return
	end
	local ids = {}
	for id in pairs(ex) do
		ids[#ids + 1] = id
	end
	table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(ids) do
		local d = ex[k]
		items(d.loot, function(id, n)
			reward(emit, id, n, d.title or "Dungeon", d.bossName and ("dungeon boss: " .. cap(d.bossName)) or "dungeon", 0)
		end)
	end
end}

-- D.goblin = treasure_goblin_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "goblins", fn = function(D, emit)
	for _, v in ipairs(D.goblin and D.goblin.variants or {}) do
		local l = v.loot or (D.goblin.loot) or {}
		if l.chaosOrb and (l.chaosOrb.max or 0) > 0 then
			reward(emit, l.chaosOrb.id, nil, v.name, string.format("%d-%d, more with the area level (at most %d)",
				l.chaosOrb.min or 0, l.chaosOrb.max, l.chaosOrb.cap or l.chaosOrb.max), 0)
		end
		if l.divineOrb and (l.divineOrb.chance or 0) > 0 then
			reward(emit, l.divineOrb.id, nil, v.name, string.format("%d%% chance", l.divineOrb.chance), 1)
		end
		if l.shards and l.shards.id then
			reward(emit, l.shards.id, nil, v.name, "more with the area level (at most " .. (l.shards.cap or 0) .. ")", 2)
		end
	end
end}

-- D.achievements = achievements_data.lua (hidden achievements are secrets: never listed)
S.REWARDS[#S.REWARDS + 1] = {key = "achievements", fn = function(D, emit)
	for _, a in ipairs(D.achievements and D.achievements.list or {}) do
		if not a.hidden and a.reward and a.reward.items then
			items(a.reward.items, function(id, n)
				reward(emit, id, n, "Achievement: " .. a.name, a.desc, 50)
			end)
		end
	end
end}

-- D.factions = factions_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "factions", fn = function(D, emit)
	local f = D.factions
	if not f then
		return
	end
	local ranks = {}
	for _, r in ipairs(f.ranks or {}) do
		ranks[r.key] = r.name
	end
	for _, fac in ipairs(f.factions or {}) do
		local npc = fac.npc and fac.npc.name or fac.name
		for _, o in ipairs((f.offers or {})[fac.key] or {}) do
			local d = fac.name .. ", " .. (ranks[o.rank] or o.rank or "") .. (o.tokens and (", " .. o.tokens .. " tokens") or "")
			if o.kind == "orbs" then
				items(o.items, function(id, n)
					emit("shop", id, {n = npc, d = d .. (o.weekly and (", " .. o.weekly .. " a week") or ""), v = K.gold(o.price or 0),
						c = K.countText(n), o = o.price or 0})
				end)
			elseif o.kind == "gear" and o.id then
				emit("shop", o.id, {n = npc, d = d .. ", " .. (o.name or "") .. " (item level " .. (o.level or 0) .. ")",
					v = K.gold(o.price or 0), o = o.price or 0})
			elseif o.kind == "recipe" and o.craft then
				local m = {}
				for _, inp in ipairs(o.craft.inputs or {}) do
					m[#m + 1] = {inp.id, inp.count}
				end
				for _, out in ipairs(o.craft.output or {}) do
					emit("craft", out.id, {n = npc, d = (o.name or "Recipe") .. " (" .. fac.name .. ", " .. (ranks[o.rank] or "") .. ")" ..
						((o.craft.gold or 0) > 0 and (", " .. K.gold(o.craft.gold)) or ""), c = K.countText(out.count), m = m, o = 10})
					for _, inp in ipairs(o.craft.inputs or {}) do
						emit("usedin", inp.id, {ref = out.id, d = npc .. ", " .. (o.name or "Recipe"), v = "x" .. K.int(inp.count)})
					end
				end
			end
		end
		local token = (f.tokens or {})[fac.key]
		if token then
			reward(emit, token.id, nil, fac.name, "monsters, rifts and events of the faction", 0)
			emit("use", token.id, {n = npc, d = fac.name .. ": turn it in for reputation", o = 0})
		end
	end
end}

-- D.uber = uber_config.lua
S.REWARDS[#S.REWARDS + 1] = {key = "uber", fn = function(D, emit)
	local u = D.uber
	if not u or u.enabled == false or not u.items then
		return
	end
	local sc = u.shardChance or {}
	local tiers = {}
	for t, p in pairs(sc.rift or {}) do
		tiers[#tiers + 1] = {t, p}
	end
	table.sort(tiers, function(a, b) return a[1] < b[1] end)
	local riftText = {}
	for _, tp in ipairs(tiers) do
		riftText[#riftText + 1] = "tier " .. tp[1] .. " " .. tp[2] .. "%"
	end
	local keys = {}
	for k in pairs(u.items.shards or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local s = u.items.shards[k]
		reward(emit, s.id, nil, "Omen guardian", (sc.omen or 0) .. "% for every finisher (that omen)", 0)
		if #riftText > 0 then
			reward(emit, s.id, nil, "Rift chest", "sealed rifts: " .. table.concat(riftText, ", ") .. " (a random omen)", 1)
		end
		if u.items.sigil then
			emit("craft", u.items.sigil.id, {n = "Ascended binding", d = "shards of one omen (use one)", m = {{s.id, u.shardCost or 4}}, o = 0})
			emit("usedin", s.id, {ref = u.items.sigil.id, d = "Ascended binding", v = "x" .. (u.shardCost or 4), o = 0})
		end
	end
	if u.items.relic then
		reward(emit, u.items.relic.id, nil, "Ascended Omen", "every finisher of an Ascended arena", 0)
	end
end}

-- every reward function in a pcall: a broken config stops only its own rows. Returns the errors {key, message}.
function S.rewards(D, emit)
	local errors = {}
	for _, r in ipairs(S.REWARDS) do
		local ok, err = pcall(r.fn, D, emit)
		if not ok then
			errors[#errors + 1] = {key = r.key, message = tostring(err)}
		end
	end
	return errors
end

return S
