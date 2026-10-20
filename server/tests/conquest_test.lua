-- Run from the server/ folder: luajit tests/conquest_test.lua (and lua5.3; CI runs both)
-- Conquest Tokens (server/README.md "Conquest Tokens, the Conquest vendor and bad-luck protection"):
--   the pure rules (conquest_core.lua): config check, source amounts by content (rift tier, dungeon difficulty, Descent
--   depth, invasion share), daily caps and the day turn, boss sources by category / name / the boss flag, the pity
--   curve with a deterministic roll sequence (a miss raises the chance, a hit resets it, the cap), the catalog over
--   the real uniques, sets and raid uniques (every unique and set piece priced once, the Monk's fist weapon always on
--   sale), visibility (seen, level band, bestiary), purchase refusals, refinement, conversions, salvage tokens, the
--   design targets (a chosen item in 1-3 weeks of dedicated play, 3-6 weeks casual);
--   the engine part (conquest.lua) on a mocked engine: grant + cap + log, the API's safety (unknown source, nil player,
--   spam), pity storages, buying a unique (tokens, the item made as a drop, refusals), Omen Keys of a chosen kind,
--   shard and relic conversions, refinement of a worn item, the window state, the rate limit;
--   the opcode and storage block are free; every reason text has a pt-BR entry.

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function has(text, part, label)
	check(type(text) == "string" and text:find(part, 1, true) ~= nil, label .. " (" .. tostring(text) .. ")")
end

-- ---------------------------------------------------------------- engine stubs needed to load the data libraries
ITEM_ATTRIBUTE_ATTACK, ITEM_ATTRIBUTE_DEFENSE, ITEM_ATTRIBUTE_EXTRADEFENSE, ITEM_ATTRIBUTE_ARMOR = 1, 2, 3, 4
ITEM_ATTRIBUTE_HITCHANCE, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ARTICLE, ITEM_ATTRIBUTE_DESCRIPTION = 5, 6, 7, 8
ITEM_ATTRIBUTE_SHOOTRANGE, ITEM_ATTRIBUTE_ATTACK_SPEED = 9, 10
dofile("data/lib/chaos_unique_items.lua")

local cfg = dofile("data/scripts/chaos/conquest_config.lua")
dofile("data/scripts/chaos/conquest_core.lua")
local K = ChaosConquestCore
local raidCfg = dofile("data/scripts/chaos/raid_config.lua")

-- ---------------------------------------------------------------- config
local problems = K.validate(cfg)
eq(#problems, 0, "config valid: " .. table.concat(problems, "; "))
do
	local bad = dofile("data/scripts/chaos/conquest_config.lua")
	bad.sources.rift_clear.slot = 1
	bad.pity.boss.slot = 1
	bad.boss.categories.world = "nope"
	bad.sources.salvage.cap = 0
	check(#K.validate(bad) >= 4, "a broken config is reported (" .. #K.validate(bad) .. ")")
end
eq(cfg.opcode, 167, "opcode")
eq(cfg.storage, 7102640, "storage block")
for key, s in pairs(cfg.sources) do
	check(cfg.storage + s.slot <= 7102689 and s.slot < cfg.pitySlot, "source " .. key .. " inside the block")
end
for key, g in pairs(cfg.pity) do
	check(cfg.storage + cfg.pitySlot + g.slot <= 7102689, "pity " .. key .. " inside the block")
end

-- ---------------------------------------------------------------- amounts
eq(K.amount(cfg, "boss_world"), 12, "a world boss")
eq(K.amount(cfg, "rift_clear", {tier = 1}), 4, "rift tier 1: 4 + 0.5")
eq(K.amount(cfg, "rift_clear", {tier = 10}), 9, "rift tier 10")
eq(K.amount(cfg, "rift_clear", {tier = 15}), 11, "rift tier 15")
eq(K.amount(cfg, "rift_clear", {tier = 99}), 12, "at most max")
eq(K.amount(cfg, "dungeon_clear", {difficulty = 1}), 7, "dungeon difficulty 1")
eq(K.amount(cfg, "dungeon_clear", {difficulty = 5}), 15, "dungeon difficulty 5 (max)")
eq(K.amount(cfg, "descent_clear", {depth = 8}), 8, "Descent depth 8")
eq(K.amount(cfg, "descent_clear", {depth = 8, cleared = true}), 14, "a full clear adds")
eq(K.amount(cfg, "invasion", {share = 0.5}), 10, "invasion share 50%")
eq(K.amount(cfg, "invasion", {share = 7}), 15, "share above 1 is 1")
eq(K.amount(cfg, "rift_clear", {tier = 0 / 0}), 4, "NaN tier counts as 0")
eq(K.amount(cfg, "nope"), 0, "unknown source")
-- Next Goals: tokens by the goal's band, capped daily
eq(K.amount(cfg, "goals", {tier = 1}), 5, "goal band 1")
eq(K.amount(cfg, "goals", {tier = 4}), 11, "goal band 4")
eq(K.amount(cfg, "goals", {tier = 50}), 15, "goal bands stop at 15")
eq(K.amount(cfg, "goals"), 3, "no band: the base")
eq(K.grantPlan(cfg, "goals", 15, 1, 1, 55).give, 5, "goals capped at 60 a day")

-- ---------------------------------------------------------------- daily caps
local p = K.grantPlan(cfg, "boss_world", 12, 20261015, 20261015, 60)
eq(p.give, 12, "under the cap")
eq(p.used, 72, "counter")
p = K.grantPlan(cfg, "boss_world", 12, 20261015, 20261015, 70)
eq(p.give, 2, "only up to the cap")
check(p.capped, "capped flag")
p = K.grantPlan(cfg, "boss_world", 12, 20261015, 20261015, 72)
eq(p.give, 0, "nothing past the cap")
p = K.grantPlan(cfg, "boss_world", 12, 20261014, 20261015, 72)
eq(p.give, 12, "a new day starts again")
eq(p.used, 12, "the counter starts again")
eq(K.grantPlan(cfg, "nope", 5, 1, 1, 0).give, 0, "unknown source gives nothing")
eq(K.grantPlan(cfg, "boss_world", -5, 1, 1, 0).give, 0, "negative gives nothing")

-- ---------------------------------------------------------------- boss sources
local src, n = K.bossSource(cfg, "Varkhul the Ashen Sovereign", "sepulchre", true)
eq(src, "boss_sepulchre", "the raid's final boss")
eq(n, 35, "with its own amount")
src, n = K.bossSource(cfg, "Ysgrath the Cinderheart", "ascended", true)
eq(n, 50, "the Cinderheart")
src, n = K.bossSource(cfg, "Dreadscale The Ancient", "island", true)
eq(src, "boss_island", "an island boss by its category")
eq(n, 10, "island amount")
src = K.bossSource(cfg, "Some Boss", nil, true)
eq(src, "boss_other", "a boss by its type flag")
src = K.bossSource(cfg, "Rat", nil, false)
eq(src, nil, "a plain monster gives nothing")
for cat, s in pairs(dofile("data/scripts/chaos/bossspawns_config.lua").categories) do
	check(cfg.boss.categories[s.key] ~= nil, "every Boss Spawns category has a source: " .. tostring(s.key))
end

-- ---------------------------------------------------------------- pity
eq(K.pityMult(cfg, "boss", 0), 1, "no misses: x1")
eq(K.pityMult(cfg, "boss", 10), 2, "10 misses: x2")
eq(K.pityMult(cfg, "boss", 1000), 4, "capped at x4")
eq(K.pityMult(cfg, "nope", 50), 1, "unknown group: x1")
eq(K.pityNext(cfg, "boss", 3, false), 4, "a miss counts")
eq(K.pityNext(cfg, "boss", 3, true), 0, "a hit resets")
eq(K.pityNext(cfg, "boss", 30, false), 30, "the counter stops at the cap")
eq(K.pityNext(cfg, "raid", 16, false), 16, "raid stops at 16 (x5)")
eq(K.pityChance(120, 4, 10000), 480, "chance x mult")
eq(K.pityChance(5000, 4, 10000), 10000, "chance at most max")
-- a deterministic roll sequence: a boss unique of 120 per 10000 (1.2%), rolls of 200 each: misses until the chance
-- passes 200 (after 7 misses: 120 x 1.7 = 204), then a hit and a reset
do
	local misses, hitAt = 0, nil
	for i = 1, 20 do
		local chance = K.pityChance(120, K.pityMult(cfg, "boss", misses), 10000)
		local hit = 200 <= chance
		misses = K.pityNext(cfg, "boss", misses, hit)
		if hit then
			hitAt = i
			break
		end
	end
	eq(hitAt, 8, "the eighth roll hits once bad luck has raised the chance")
	eq(misses, 0, "and the misses start again")
	-- the expected number of rolls to a raid unique (1.5% per boss loot) with and without pity
	local function expected(base, group)
		local e, alive, m = 0, 1, 0
		for i = 1, 2000 do
			local c = math.min(1, base * K.pityMult(cfg, group, m))
			e = e + i * alive * c
			alive = alive * (1 - c)
			m = K.pityNext(cfg, group, m, false)
		end
		return e
	end
	local plain = 1 / 0.015
	local withPity = expected(0.015, "raid")
	check(withPity < plain * 0.45, string.format("raid uniques: %.1f rolls on average with pity, %.1f without", withPity, plain))
	check(expected(0.012, "boss") < (1 / 0.012) * 0.5, "boss uniques at least twice as fast on average")
end

-- ---------------------------------------------------------------- the catalog
local specs = ChaosUniqueSpecs
local offers = K.catalog(cfg, {uniques = ChaosUniqueItems, sets = ChaosItemSets.sets, raid = raidCfg.uniques, specs = specs})
local byKey = K.byKey(offers)
local ids = {}
for _, o in ipairs(offers) do
	check(not ids[o.id], "offer " .. o.id .. " listed once")
	ids[o.id] = true
	check(o.price and o.price > 0 and o.price % 10 == 0, "offer " .. o.name .. " has a round price")
	check(o.level and o.level > 0, "offer " .. o.name .. " has a level")
end
for _, e in ipairs(ChaosUniqueItems) do
	check(ids[e.id], "every unique is on sale: " .. e.name)
end
for _, set in ipairs(ChaosItemSets.sets) do
	for _, piece in ipairs(set.pieces) do
		check(ids[piece.id], "every set piece is on sale: " .. piece.name)
		eq(byKey["u:" .. piece.id].group, "set", piece.name .. " is a set piece")
	end
end
for _, u in ipairs(raidCfg.uniques) do
	eq(byKey["u:" .. u.id] and byKey["u:" .. u.id].group, "raid", u.name .. " is a raid unique")
end
local grasp = byKey["u:36659"]
check(grasp ~= nil and grasp.always, "the Monk's Grasp of the Pyre Saint is always on sale")
eq(grasp.group, "monster", "as a monster unique")
eq(grasp.price, 1580, "its price")
eq(byKey["u:2498"].price, 3600, "the Crown has its own price")
eq(byKey["u:2123"].price, 5400, "the Cinderheart Signet has its own price")
eq(byKey["u:2408"].group, "ascended", "Sanguine Crescent is Ascended")
eq(K.price(cfg, "monster", 100), 750, "monster unique level 100")
eq(K.price(cfg, "boss", 120), 1360, "boss unique level 120")
eq(K.price(cfg, "set", 300), 1260, "set piece level 300")
eq(K.specLevel({description = "x. (Requires level 120.)"}), 120, "spec level")
eq(K.specLevel({description = "nothing"}), nil, "no spec level")

-- design targets (server/README.md "Conquest Tokens", the numbers): weekly income of a casual (1.5 h a day, levels
-- 100-300: dungeons and low rifts) and a dedicated player (4 h a day, endgame rifts, Omens, the raid, bosses)
do
	local casualWeek = 7 * 1.5 * 30 + 2 * K.amount(cfg, "boss_world") + 3 * K.amount(cfg, "invasion", {share = 0.3})
	local raidWeek = 4 * K.amount(cfg, "boss_sepulchre") + 35
	local dedicatedWeek = 7 * 4 * 60 + raidWeek + 3 * K.amount(cfg, "boss_world")
	local function weeks(price, income) return price / income end
	-- a casual's chosen item of its band: a level 100-300 monster unique, a boss unique, a level 300 set piece
	for _, price in ipairs({K.price(cfg, "monster", 300), K.price(cfg, "boss", 120), K.price(cfg, "set", 300)}) do
		local w = weeks(price, casualWeek)
		check(w >= 1.5 and w <= 6, string.format("casual: %d tokens take %.1f weeks", price, w))
	end
	-- a dedicated player's chosen endgame item: the Grasp, a level 800 set piece, a raid unique, an Ascended unique
	for _, price in ipairs({grasp.price, K.price(cfg, "set", 800), K.price(cfg, "raid", 130), K.price(cfg, "ascended", 1000),
			byKey["u:2123"].price}) do
		local w = weeks(price, dedicatedWeek)
		check(w >= 0.75 and w <= 3, string.format("dedicated: %d tokens take %.1f weeks", price, w))
	end
	-- the daily caps never stop the dedicated model: 4 hours of tier 12-15 rifts (about 7 an hour)
	check(4 * 7 * K.amount(cfg, "rift_clear", {tier = 13}) <= cfg.sources.rift_clear.cap, "rift cap fits 4 hours")
end

-- ---------------------------------------------------------------- visibility and purchases
local hi = byKey["u:28020"] -- Voidscale Legguards, level 130
eq(K.visible(cfg, hi, {level = 80}), true, "level 80 + band 50 sees level 130")
local ok, why = K.visible(cfg, hi, {level = 79})
eq(ok, false, "level 79 does not")
eq(why, "hidden", "reason")
eq(K.visible(cfg, hi, {level = 1, seen = {[28020] = true}}), true, "seen once: always")
eq(K.visible(cfg, hi, {level = 1, killed = {demon = true}}), true, "a monster that drops it was slain")
eq(K.visible(cfg, grasp, {level = 1}), true, "always offers")
local ctx = {balance = 5000, visible = true, pz = true}
eq(K.canBuy(cfg, hi, ctx), true, "can buy")
eq(select(2, K.canBuy(cfg, hi, {balance = 10, visible = true, pz = true})), "tokens", "too few tokens")
eq(select(2, K.canBuy(cfg, hi, {balance = 5000, visible = false, pz = true})), "hidden", "not seen")
eq(select(2, K.canBuy(cfg, hi, {balance = 5000, visible = true, pz = false})), "pz", "outside a protection zone")
eq(select(2, K.canBuy(cfg, hi, {balance = 5000, visible = true, pz = true, blocked = true})), "season", "a season item")
eq(select(2, K.canBuy(cfg, nil, ctx)), "unknown", "no offer")
local rows = K.payload(cfg, offers, {level = 100})
eq(#rows, #offers, "every offer in the window")
check(rows[1].k and rows[1].p and rows[1].n, "row fields")

-- ---------------------------------------------------------------- refinement, conversion, salvage
eq(K.refinePrice(cfg, 4), 360, "Rare to Legendary: 60 + 60 x the new place (5)")
eq(K.refinePrice(cfg, 1), 180, "Common to Uncommon")
eq(K.refinePrice(cfg, 7), nil, "an old Mythic reads as Legendary: Divine is luck")
eq(K.refinePrice(cfg, 5), nil, "never above maxRarity (Legendary)")
eq(K.refinePrice(cfg, 0), nil, "a normal item has no rarity to raise")
eq(K.refineCheck(cfg, {gear = true, rarity = 3}), true, "a Magic item")
eq(select(2, K.refineCheck(cfg, {gear = true, rarity = 3, unique = true})), "unique", "no uniques")
eq(select(2, K.refineCheck(cfg, {gear = true, rarity = 3, ruined = true})), "ruined", "no ruined items")
eq(select(2, K.refineCheck(cfg, {gear = true, rarity = 12})), "maxRarity", "the top stays luck (an old Celestial is Divine)")
eq(select(2, K.refineCheck(cfg, {gear = false, rarity = 0})), "notGear", "not gear")
local kinds = {"bloodmoon", "hollow", "storm"}
local okc, need = K.convertCheck(cfg, "shards", "bloodmoon", "storm", {bloodmoon = 2}, kinds)
eq(okc, true, "2 shards convert")
eq(need, 2, "cost 2")
eq(select(2, K.convertCheck(cfg, "shards", "bloodmoon", "storm", {bloodmoon = 1}, kinds)), "notEnough", "1 is not enough")
eq(select(2, K.convertCheck(cfg, "relics", "storm", "storm", {storm = 5}, kinds)), "sameKind", "the same kind")
eq(select(2, K.convertCheck(cfg, "relics", "storm", "cinder", {storm = 5}, kinds)), "badKind", "no such kind")
eq(select(2, K.convertCheck(cfg, "gold", "storm", "hollow", {storm = 5}, kinds)), "unknown", "only shards and relics")
eq(K.salvageTokens(cfg, 1580), 158, "10% of the price")
eq(K.salvageTokens(cfg, 100), 25, "at least 25")
for _, o in ipairs(offers) do
	check(K.salvageTokens(cfg, o.price) * 4 < o.price, "salvage never pays back a purchase: " .. o.name)
end

-- ---------------------------------------------------------------- the Cinderheart chain covers every kind
local uber = dofile("data/scripts/chaos/uber_config.lua")
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")
for _, k in ipairs(riftCfg.omen.kinds) do
	check(uber.items.shards[k.key] ~= nil, "every Omen kind has a shard kind: " .. k.key)
	check(cfg.boss.byName[k.boss:lower()] ~= nil, "every Omen guardian gives tokens: " .. k.boss)
end
for _, k in ipairs(uber.kinds) do
	check(cfg.boss.byName[k.boss:lower()] ~= nil, "every Ascended boss gives tokens: " .. k.boss)
end

-- ======================================================================== the engine part (mocked)
local storages = {}
local function deep(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = deep(v)
	end
	return o
end
local registry = {}
json = {
	encode = function(t) registry[#registry + 1] = deep(t); return "J" .. #registry end,
	decode = function(s) return deep(registry[tonumber(tostring(s):match("^J(%d+)$") or -1)]) end
}
local events = {}
CreatureEvent = function(name)
	local e = {register = function() end, type = function() end}
	events[name] = e
	return e
end
GlobalEvent = function() return {register = function() end} end
TalkAction = function() return {separator = function() end, register = function() end} end
EventCallback = setmetatable({register = function() end}, {__newindex = rawset})
addEvent = function() end
MESSAGE_LOOT, MESSAGE_INFO_DESCR, MESSAGE_EVENT_ADVANCE, MESSAGE_STATUS_SMALL = 1, 2, 3, 4
RETURNVALUE_NOERROR = 0
CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR = 1, 2, 3, 4
CONST_SLOT_RIGHT, CONST_SLOT_LEFT, CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 5, 6, 7, 8, 9, 10
TILESTATE_PROTECTIONZONE = 1
local pzOn = true
Tile = function() return {hasFlag = function() return pzOn end} end
ItemType = function(id) return {getClientId = function() return id - 1 end, getName = function() return "item " .. id end} end
Game = {getSpectators = function() return {} end, createItem = function(id, n)
	local it = {id = id, custom = {}, removed = false}
	function it:getId() return self.id end
	function it:setAttribute() end
	function it:setCustomAttribute(k, v) self.custom[k] = v end
	function it:getCustomAttribute(k) return self.custom[k] end
	function it:remove() self.removed = true return true end
	return it
end}
Player = function(x) return type(x) == "table" and x or nil end
Creature = function() return nil end

-- the database: the balance table, ROW_COUNT, the seen table, the log
local DB = {balance = {}, log = {}, seen = {}, rowCount = 0, reads = 0}
db = {escapeString = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end}
function db.query(q)
	local guid, b = q:match("^INSERT INTO `chaos_conquest` %(.-%) VALUES %((%d+), (%d+),")
	if guid then
		guid = tonumber(guid)
		DB.balance[guid] = (DB.balance[guid] or 0) + tonumber(b)
		return true
	end
	local amt, g2, need = q:match("^UPDATE `chaos_conquest` SET `balance` = `balance` %- (%d+).-`player_id` = (%d+) AND `balance` >= (%d+)")
	if amt then
		g2 = tonumber(g2)
		if (DB.balance[g2] or 0) >= tonumber(need) then
			DB.balance[g2] = DB.balance[g2] - tonumber(amt)
			DB.rowCount = 1
		else
			DB.rowCount = 0
		end
		return true
	end
	if q:find("^INSERT INTO `chaos_conquest_log`") then
		DB.log[#DB.log + 1] = q
		return true
	end
	local sg, sid = q:match("^INSERT IGNORE INTO `chaos_conquest_seen`.-VALUES %((%d+), (%d+),")
	if sg then
		DB.seen[sg .. ":" .. sid] = true
	end
	return true
end

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.select = function(q)
	DB.reads = DB.reads + 1
	local guid = q:match("FROM `chaos_conquest` WHERE `player_id` = (%d+)")
	if guid then
		local b = DB.balance[tonumber(guid)]
		return b and {{balance = b}} or {}
	end
	if q:find("ROW_COUNT") then
		return {{n = DB.rowCount}}
	end
	local sg = q:match("FROM `chaos_conquest_seen` WHERE `player_id` = (%d+)")
	if sg then
		local out = {}
		for k in pairs(DB.seen) do
			local a, b = k:match("^(%d+):(%d+)$")
			if a == sg then
				out[#out + 1] = {item_id = tonumber(b)}
			end
		end
		return out
	end
	return {}
end
local sent = {}
Chaos.send = function(player, op, action, data) sent[#sent + 1] = {op = op, action = action, data = deep(data)} end
Chaos.sendChunked = function(player, op, text)
	local m = json.decode(text)
	sent[#sent + 1] = {op = op, action = m.action, data = m.data}
end
local limited = false
ChaosRateLimit = {allow = function() return not limited end}
local saves = 0
Chaos.dayKey = function() return 20261015 end

local function newPlayer(guid, level)
	local pl = {guid = guid, level = level, storage = {}, items = {}, inbox = {}, messages = {}, carried = {}, slots = {}}
	function pl:getId() return 0x10000000 + self.guid end
	function pl:getGuid() return self.guid end
	function pl:getName() return "Hero" .. self.guid end
	function pl:getLevel() return self.level end
	function pl:isPlayer() return true end
	function pl:getPosition() return {x = 100, y = 100, z = 7} end
	function pl:getStorageValue(k) return self.storage[k] or -1 end
	function pl:setStorageValue(k, v) self.storage[k] = v end
	function pl:sendTextMessage(t, text) self.messages[#self.messages + 1] = text end
	function pl:addItemEx(item) self.items[#self.items + 1] = item return 0 end
	function pl:getInbox() local me = self return {addItemEx = function(_, it) me.inbox[#me.inbox + 1] = it end} end
	function pl:save() saves = saves + 1 return true end
	function pl:getItemCount(id) return self.carried[id] or 0 end
	function pl:removeItem(id, n)
		if (self.carried[id] or 0) < n then return false end
		self.carried[id] = self.carried[id] - n
		return true
	end
	function pl:getSlotItem(s) return self.slots[s] end
	function pl:getItemById() return self.omenKey end
	function pl:registerEvent() end
	return pl
end

local made = {}
ChaosMakeUnique = function(item) made[#made + 1] = item.id item.custom.chaos_unique = 1 return true end
-- the rift and the Ascended exports the vendor uses
local keysGiven, shardsGiven, relicsGiven = {}, {}, {}
ChaosRiftConfig = riftCfg
ChaosRift = {
	giveOmenKey = function(player, kind) keysGiven[#keysGiven + 1] = kind return kind end,
	applyOmenKey = function(item, kind) item.kind = kind end
}
ChaosUberConfig = uber
ChaosAscended = {
	giveShard = function(player, kind) shardsGiven[#shardsGiven + 1] = kind return false end,
	giveRelic = function(player, kind) relicsGiven[#relicsGiven + 1] = kind return false end,
	relicsOf = function(player) return player.relics or {} end
}
ChaosRaidConfig = raidCfg

dofile("data/scripts/chaos/conquest.lua")
local X = ChaosConquest
eq(ChaosOpcodes.conquest, 167, "ChaosOpcodes.conquest")
eq(Chaos.storage.conquest, 7102640, "Chaos.storage.conquest")
for _, taken in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(taken ~= ChaosOpcodes.conquest, "opcode free of " .. taken)
end
for name, v in pairs(ChaosOpcodes) do
	check(name == "conquest" or v ~= ChaosOpcodes.conquest, "opcode not shared with " .. name)
end
for name, v in pairs(Chaos.storage) do
	if name ~= "conquest" and type(v) == "number" then
		check(v < 7102640 or v > 7102689, "storage block not shared with " .. name)
	end
end

-- grants, caps, the log
local hero = newPlayer(1, 120)
eq(X.balance(hero), 0, "a new character has no tokens")
eq(X.grant(hero, "boss_world"), 12, "the source's own amount")
eq(X.balance(hero), 12, "balance")
eq(DB.balance[1], 12, "in the database")
eq(#DB.log, 1, "logged")
has(hero.messages[#hero.messages], "+12 Conquest Tokens", "told")
for _ = 1, 10 do
	X.grant(hero, "boss_world")
end
eq(X.balance(hero), 72, "capped at 72 a day")
eq(hero.storage[cfg.storage + cfg.sources.boss_world.slot], 72, "the daily counter")
local told = 0
for _, m in ipairs(hero.messages) do
	if m:find("limit", 1, true) then told = told + 1 end
end
eq(told, 1, "the limit is told once")
eq(X.grant(hero, "nope", 5), 0, "unknown source")
eq(X.grant(nil, "boss_world", 5), 0, "no player")
eq(X.grant(hero, "rift_clear", -3), 0, "negative")
eq(X.reward(hero, "rift_clear", {tier = 10}), 9, "a sealed rift of tier 10")
-- the returning-player bonus (ChaosCatchup.tokenMult, catch-up): x1.5 rounded, not on salvage, a bad value ignored
do
	local cb = newPlayer(7, 300)
	ChaosCatchup = {tokenMult = function() return 1.5 end}
	eq(X.grant(cb, "boss_island"), 15, "10 x 1.5")
	eq(X.grant(cb, "boss_lair"), 5, "3 x 1.5 = 4.5 rounds to 5")
	eq(X.grant(cb, "salvage", 30), 30, "no bonus on salvage")
	ChaosCatchup = {tokenMult = function() return 0 / 0 end}
	eq(X.grant(cb, "boss_island"), 10, "NaN ignored")
	ChaosCatchup = {tokenMult = function() error("boom") end}
	eq(X.grant(cb, "boss_island"), 10, "an error ignored")
	ChaosCatchup = nil
	eq(X.grant(cb, "boss_island"), 10, "without catch-up x1")
end
-- a new day
Chaos.dayKey = function() return 20261016 end
eq(X.grant(hero, "boss_world"), 12, "the next day the cap is fresh")
eq(hero.storage[cfg.storage + cfg.sources.rift_clear.slot], 0, "every counter starts again")

-- pity storages
eq(X.pityMult(hero, "raid"), 1, "no misses")
X.pityRecord(hero, "raid", false)
X.pityRecord(hero, "raid", false)
eq(X.pityMisses(hero, "raid"), 2, "two misses")
eq(X.pityMult(hero, "raid"), 1.5, "x1.5")
X.pityRecord(hero, "raid", true, 2498)
eq(X.pityMisses(hero, "raid"), 0, "a drop resets")
check(DB.seen["1:2498"], "a drop is seen")

-- buying a unique
DB.balance[1] = 1000
X.bal[1] = nil
local lowItem = byKey["u:2412"] -- Nightfang Katana, level 60
X.buy(hero, {k = "u:2412"})
eq(DB.balance[1], 1000 - lowItem.price, "the price is paid")
eq(hero.items[#hero.items].id, 2412, "the unique is given")
eq(made[#made], 2412, "made like a drop (ChaosMakeUnique)")
check(saves > 0, "the character is saved")
check(DB.seen["1:2412"], "bought is seen")
local before = DB.balance[1]
X.buy(hero, {k = "u:2123"}) -- the Cinderheart Signet: level 1000, not seen
eq(DB.balance[1], before, "a hidden item is refused")
eq(sent[#sent].data.ok, false, "refused")
has(sent[#sent].data.text, "not seen", "why")
X.buy(hero, {k = "u:36659"}) -- the Grasp: always on sale, 1580 tokens
eq(DB.balance[1], before, "too few tokens: nothing paid")
has(sent[#sent].data.text, "enough Conquest Tokens", "why")
pzOn = false
DB.balance[1] = 5000
X.bal[1] = nil
X.buy(hero, {k = "u:2412"})
eq(DB.balance[1], 5000, "outside a protection zone: refused")
pzOn = true
X.buy(hero, {k = "u:99999"})
eq(DB.balance[1], 5000, "unknown offer")
X.buy(hero, {k = 5})
X.buy(hero, "x")
eq(DB.balance[1], 5000, "garbage requests")
-- the database refuses the debit (another server spent it first): the item is taken back
X.bal[1] = 99999
DB.balance[1] = 10
local n0 = #hero.items
X.buy(hero, {k = "u:2412"})
eq(#hero.items, n0, "no item without the tokens")
eq(DB.balance[1], 10, "nothing taken")

-- Omen Keys, shards and their conversion
DB.balance[1] = 2000
X.bal[1] = nil
X.buy(hero, {k = "omen:storm"})
eq(#keysGiven, 0, "below the Omen level: refused")
hero.level = 900
X.buy(hero, {k = "omen:storm"})
eq(keysGiven[#keysGiven], "storm", "an Omen Key of the chosen kind")
eq(DB.balance[1], 2000 - cfg.cinder.omenKey, "its price")
X.buy(hero, {k = "omen:nope"})
eq(#keysGiven, 1, "no such kind")
X.buy(hero, {k = "attune:hollow"})
has(sent[#sent].data.text, "Carry an Omen Key", "attune needs a key")
hero.omenKey = {}
X.buy(hero, {k = "attune:hollow"})
eq(hero.omenKey.kind, "hollow", "a carried key takes the chosen kind")
X.buy(hero, {k = "shard:bloodmoon"})
eq(shardsGiven[#shardsGiven], "bloodmoon", "a shard of the chosen kind")
hero.carried[uber.items.shards.storm.id] = 3
X.buy(hero, {k = "conv:shards:storm:hollow"})
eq(hero.carried[uber.items.shards.storm.id], 1, "two storm shards taken")
eq(shardsGiven[#shardsGiven], "hollow", "one hollow shard given")
X.buy(hero, {k = "conv:shards:storm:hollow"})
eq(hero.carried[uber.items.shards.storm.id], 1, "one shard is not enough")
local r1 = {removed = 0}
function r1:remove() self.removed = self.removed + 1 return true end
local r2 = {removed = 0}
r2.remove = r1.remove
hero.relics = {{r1, "bloodmoon"}, {r2, "bloodmoon"}}
X.buy(hero, {k = "conv:relics:bloodmoon:storm"})
eq(r1.removed + r2.removed, 2, "two duplicate relics taken")
eq(relicsGiven[#relicsGiven], "storm", "the missing relic given")

-- refinement of a worn item (crafting mocked)
local refined = {rarity = 4, custom = {}}
function refined:getId() return 2400 end
function refined:setCustomAttribute(k, v) self.custom[k] = v if k == "rarity" then self.rarity = v end end
local added = 0
ChaosCrafting = {
	isGear = function() return true end, rarityOf = function(it) return it.rarity end, isUnique = function() return false end,
	itemName = function() return "a fine blade" end, rarityName = function(r) return "R" .. r end,
	candidates = function() return {{key = "x"}} end, random = math.random, orbLevel = function() return 100 end,
	rollAffix = function() added = added + 1 return {key = "x"} end, rewriteDescription = function() end,
	modTierText = function() return "x T5" end
}
ChaosItemMods = {isRuined = function() return false end, pick = function(list) return list[1] end, sendUpdate = function() end}
hero.slots[CONST_SLOT_LEFT] = refined
DB.balance[1] = 1000
X.bal[1] = nil
X.buy(hero, {k = "refine:" .. CONST_SLOT_LEFT})
eq(refined.rarity, 5, "one rarity up")
eq(added, 1, "one modifier added, the others kept")
eq(DB.balance[1], 1000 - K.refinePrice(cfg, 4), "its price")
refined.rarity = 12
X.buy(hero, {k = "refine:" .. CONST_SLOT_LEFT})
eq(refined.rarity, 12, "the top rarity stays luck")
X.buy(hero, {k = "refine:99"})

-- the window
sent = {}
events.ChaosConquestExtended.onExtendedOpcode(hero, 167, json.encode({action = "open", data = {}}))
local st = sent[#sent]
eq(st.action, "state", "the state is sent")
check(#st.data.offers >= #offers - 8, "the offers (season items may be hidden)")
eq(st.data.bal, DB.balance[1], "the balance")
eq(#st.data.pity, 4, "four pity groups")
check(#st.data.refine == 1 and st.data.refine[1].slot == CONST_SLOT_LEFT, "the worn item to refine")
eq(#st.data.cinder.omens, 3, "three Omen kinds")
eq(#st.data.cinder.ascended, 3, "three Ascended kinds")
check(#st.data.today >= 15, "today's income per source")
local reads = DB.reads
limited = true
events.ChaosConquestExtended.onExtendedOpcode(hero, 167, json.encode({action = "open", data = {}}))
eq(DB.reads, reads, "a rate-limited request reads nothing")
limited = false
events.ChaosConquestExtended.onExtendedOpcode(hero, 99, json.encode({action = "open", data = {}}))
eq(DB.reads, reads, "another opcode is ignored")

-- the hooks of the other systems are in place (their own tests run them with mocked ChaosConquest tables where they can)
local function src(f)
	local fh = io.open("data/scripts/chaos/" .. f, "r")
	local t = fh and fh:read("*a") or ""
	if fh then fh:close() end
	return t
end
has(src("rift.lua"), 'ChaosConquest.reward, player, "rift_clear"', "rift.lua grants a sealed rift")
has(src("dungeons.lua"), 'ChaosConquest.reward, p, "dungeon_clear"', "dungeons.lua grants a clear")
has(src("descent.lua"), 'ChaosConquest.reward, player, "descent_clear"', "descent.lua grants a run")
has(src("invasion.lua"), 'ChaosConquest.reward, player, "invasion"', "invasion.lua grants a reward")
has(src("raid.lua"), 'CQ.pityRecord(player, "raid"', "raid.lua records raid pity")
has(src("itemsets.lua"), 'CQ.pityRecord(player, "set"', "itemsets.lua records set pity")
has(src("loot.lua"), "ChaosConquest.pityRecord(owner, group", "loot.lua records unique pity")
has(src("salvage.lua"), 'ChaosConquest.grant(player, "salvage"', "salvage.lua grants salvaged uniques")
has(src("uber.lua"), "A.relicsOf = relicsOf", "uber.lua exports the relics")
has(src("rift.lua"), "itemFind * r.rarityMult, nil, player)", "the rift chest's unique roll has the finisher as owner (pity)")
has(src("worldboss.lua"), 'CQ.pityRecord(player, "boss"', "world boss participation records boss pity")
has(src("worldboss.lua"), "W.uniquePool(boss.name), nil, pityOf)", "world boss participation rolls with pity")

-- every reason text has a pt-BR entry
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
for key, text in pairs(K.reasons) do
	check(pt[text] ~= nil, "reason " .. key .. " without pt-BR")
end

print(string.format("conquest_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
