-- paragon.lua: the Paragon track, the long-term goal past the passive tree's point budget.
--
-- Rules (numbers in Chaos.paragon, chaos_constants.lua):
--   * points = (level - startLevel) x pointsPerLevel up to slowFrom, then 1 per levelsPerPointSlow levels (O135), so from
--     level 1001 on (the tree budget ends at level 1000)
--   * four categories of two small stats each; a stat takes at most maxPoints, its cap is perPoint x maxPoints
--   * allocations only go up; taking points back is a reset: level x Chaos.passive.resetCostPerLevel gold (the tree's
--     rule), or the store's Passive Tree Reset service (shop_services.lua), which resets the tree and Paragon for free
--   * a character whose level fell below what it has spent is refunded for free at login (like the tree)
--
-- O146 (beta: "300 Paragon points with nothing to spend them on"):
--   * Paragon Mastery (Chaos.paragon.mastery): an endless sink. A rank costs 1 point, `ranks` ranks of a mastery give
--     scale x ln(1 + ranks / h) percent to the same bonus key as the category stat of that name. Never zero gain, no maximum.
--   * Exchange (Chaos.paragon.exchange): free passive tree points become Paragon points for good, `ratio` for 1; the
--     tree's point total drops by the same count (passivetree.lua totalPoints reads Chaos.storage.paragonConverted).
--   * client -> server  paragonMastery {key, n}   spend n free points on ranks of a mastery at once -> paragonState
--                       paragonConvert {n}        exchange n free tree points -> paragonState (+ sendPoints)
--   paragonState also carries mastery = {maxRanks, rows = [{key, name, desc, category, ranks, value, next, scale, h}]}
--   and exchange = {ratio, treeFree, converted}.
--
-- Applying: ChaosParagon.addBonuses puts the Paragon percentages into the passive tree's bonus table
-- (ChaosPassiveTree.apply in passivetree.lua calls it), under the keys paragonDamage, paragonCritDamage, paragonHealth,
-- paragonReduction, paragonSpeed, paragonMana, paragonGoldFind and paragonItemFind. passivetree_effects.lua adds them to
-- the tree's own bonuses (one health / mana condition, one absorb storage per type, one item-find storage), so the two
-- never overwrite each other. Gold find is the onDropLoot callback at the end of this file.
--
-- Protocol (extended opcode 65, dispatched by passivetree.lua, same {"action":..,"data":..} JSON):
--   client -> server  paragonRequest                          -> paragonState
--                     paragonApply {alloc = {statKey = n}}    -> absolute allocation; validated, saved, applied, paragonState
--                     paragonReset                            -> priced by respec.lua (respec_config.lua), then paragonState
--   server -> client  {"action":"paragonState","data":{unlocked, level, startLevel, total, spent, free, resetCost,
--                      categories = [{key, name, stats = [{key, name, desc, perPoint, maxPoints, points}]}]}}
--                     errors use the tree's {"action":"sendMessage"} box

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

ChaosParagon = ChaosParagon or {}
local P = ChaosParagon
local cfg = Chaos.paragon
local T = Chaos.tables.paragon
local OPCODE = ChaosOpcodes.passivetree

-- statKey -> definition (with .category), and the list in display order
P.defs, P.order = {}, {}
for _, category in ipairs(cfg.categories) do
	for _, stat in ipairs(category.stats) do
		stat.category = category.key
		P.defs[stat.key] = stat
		P.order[#P.order + 1] = stat.key
	end
end

-- Paragon Mastery: key -> definition (with .category, .bonus), and the list in display order
P.mastery, P.masteryOrder = {}, {}
for _, stat in ipairs((cfg.mastery or {}).stats or {}) do
	P.mastery[stat.key] = stat
	P.masteryOrder[#P.masteryOrder + 1] = stat.key
end

-- every key an allocation may hold, with its maximum points (loadouts.lua parks the whole allocation, masteries too)
P.allDefs = {}
for key, d in pairs(P.defs) do
	P.allDefs[key] = {maxPoints = d.maxPoints}
end
for key in pairs(P.mastery) do
	P.allDefs[key] = {maxPoints = cfg.mastery.maxRanks}
end

-- ranks in the masteries of an allocation
function P.masterySpent(alloc)
	local n = 0
	for key, points in pairs(alloc or {}) do
		if P.mastery[key] then
			n = n + points
		end
	end
	return n
end

-- the category part of an allocation (build codes carry only these) and the mastery part
function P.split(alloc)
	local base, mastery = {}, {}
	for key, points in pairs(alloc or {}) do
		if P.mastery[key] then
			mastery[key] = points
		else
			base[key] = points
		end
	end
	return base, mastery
end

-- bonus key in the passive tree's bonus table: damage -> paragonDamage
function P.bonusKey(statKey)
	return "paragon" .. statKey:sub(1, 1):upper() .. statKey:sub(2)
end

-- ---------------------------------------------------------------- pure part (server/tests/paragon_test.lua)
-- `converted`: free passive tree points exchanged for Paragon points (Chaos.storage.paragonConverted, cfg.exchange.ratio each)
-- `legacy`: points kept from the old 1-per-level track (Chaos.storage.paragonLegacy, P.legacyPoints)
function P.totalPoints(level, converted, legacy)
	level = level or 0
	local first = math.max(0, math.min(level, cfg.slowFrom or math.huge) - cfg.startLevel) * (cfg.pointsPerLevel or 1)
	local slow = 0
	if cfg.slowFrom and level > cfg.slowFrom then
		slow = (level - cfg.slowFrom) / (cfg.levelsPerPointSlow or 1)
	end
	return math.floor(first + slow) + math.max(0, math.floor(converted or 0)) * ((cfg.exchange or {}).ratio or 1)
		+ math.max(0, math.floor(legacy or 0))
end

-- Before O135 (2026-10-23) the track gave 1 point per level above startLevel without the slow part. The cut took points
-- from every character above slowFrom, and the login refund then wiped their allocation (beta 2026-10-24: "the reset did
-- not give all points back"). A character keeps the difference at its level of the first login after the fix, for good.
function P.legacyPoints(level)
	local old = math.max(0, (level or 0) - cfg.startLevel) * (cfg.pointsPerLevel or 1)
	return math.max(0, math.floor(old) - P.totalPoints(level))
end

function P.spent(alloc)
	local n = 0
	for _, points in pairs(alloc or {}) do
		n = n + points
	end
	return n
end

function P.cap(statKey)
	local d = P.defs[statKey]
	return d and d.perPoint * d.maxPoints or 0
end

-- percent value of a stat with `points` points (capped)
function P.value(statKey, points)
	local d = P.defs[statKey]
	if not d then
		return 0
	end
	return d.perPoint * math.max(0, math.min(points or 0, d.maxPoints))
end

-- percent of a mastery with `ranks` ranks: scale x ln(1 + ranks / h) (strictly increasing, concave, unbounded)
function P.masteryValue(key, ranks)
	local d = P.mastery[key]
	if not d then
		return 0
	end
	return d.scale * math.log(1 + math.max(0, ranks or 0) / d.h)
end

-- {paragonDamage = 2.5, ...} for an allocation: the category stats and the masteries add up under one key
function P.bonusesOf(alloc)
	local out = {}
	for key, points in pairs(alloc or {}) do
		local v, bonus = 0, nil
		if P.defs[key] then
			v, bonus = P.value(key, points), P.bonusKey(key)
		elseif P.mastery[key] then
			v, bonus = P.masteryValue(key, math.min(points, cfg.mastery.maxRanks)), P.bonusKey(P.mastery[key].bonus)
		end
		if v > 0 then
			out[bonus] = (out[bonus] or 0) + v
		end
	end
	return out
end

-- Spend n points on ranks of a mastery. Returns the new allocation or nil, error text.
function P.validateMastery(key, n, current, total, level)
	if not P.unlocked(level) then
		return nil, string.format("The Paragon track unlocks at level %d.", cfg.startLevel)
	end
	local d = type(key) == "string" and P.mastery[key]
	if not d then
		return nil, "Unknown Paragon mastery in request."
	end
	n = tonumber(n)
	if not n or n ~= math.floor(n) or n < 1 or n > cfg.mastery.maxRanks then
		return nil, "Malformed request."
	end
	current = current or {}
	if (current[key] or 0) + n > cfg.mastery.maxRanks then
		return nil, "That mastery cannot take that many ranks."
	end
	if P.spent(current) + n > total then
		return nil, "You do not own enough Paragon points for that."
	end
	local out = {}
	for k, v in pairs(current) do
		out[k] = v
	end
	out[key] = (current[key] or 0) + n
	return out
end

-- Validate a requested absolute allocation against the current one and the points owned.
-- Returns the cleaned allocation {key = n} or nil, error text.
function P.unlocked(level)
	return (level or 0) >= cfg.startLevel
end

function P.validate(requested, current, total, level)
	if not P.unlocked(level) then
		return nil, string.format("The Paragon track unlocks at level %d.", cfg.startLevel)
	end
	if type(requested) ~= "table" then
		return nil, "Malformed request."
	end
	current = current or {}
	local out = {}
	for key, points in pairs(current) do
		out[key] = points
	end
	for key, raw in pairs(requested) do
		local d = type(key) == "string" and P.defs[key]
		if not d then
			return nil, "Unknown Paragon stat in request."
		end
		local n = Chaos.toInt(raw, 0, d.maxPoints)
		if not n or n ~= tonumber(raw) then
			return nil, string.format("%s takes 0 to %d points.", d.name, d.maxPoints)
		end
		if n < (current[key] or 0) then
			return nil, "Paragon points can only be taken back with a reset."
		end
		out[key] = n > 0 and n or nil
	end
	if P.spent(out) > total then
		return nil, "You do not own enough Paragon points for that allocation."
	end
	return out
end

-- ---------------------------------------------------------------- storage
P.cache = P.cache or {} -- player id -> allocation

function P.load(guid)
	local alloc = {}
	for _, row in ipairs(Chaos.select("SELECT `stat`, `points` FROM `" .. T .. "` WHERE `player_id` = " .. guid,
			{{"stat", "s"}, {"points", "n"}})) do
		if P.defs[row.stat] and row.points > 0 then
			alloc[row.stat] = math.min(row.points, P.defs[row.stat].maxPoints)
		elseif P.mastery[row.stat] and row.points > 0 then
			alloc[row.stat] = math.min(row.points, cfg.mastery.maxRanks)
		end
	end
	return alloc
end

function P.save(guid, alloc)
	db.query("DELETE FROM `" .. T .. "` WHERE `player_id` = " .. guid)
	local values = {}
	for _, list in ipairs({P.order, P.masteryOrder}) do
		for _, key in ipairs(list) do
			if (alloc[key] or 0) > 0 then
				values[#values + 1] = string.format("(%d, %s, %d)", guid, db.escapeString(key), alloc[key])
			end
		end
	end
	if #values > 0 then
		db.query("INSERT INTO `" .. T .. "` (`player_id`, `stat`, `points`) VALUES " .. table.concat(values, ", "))
	end
end

-- free passive tree points the character exchanged for Paragon points
function P.converted(player)
	local key = Chaos.storage.paragonConverted
	return key and math.max(0, player:getStorageValue(key)) or 0
end

-- Paragon points kept from the old track (0 before P.grantLegacy ran)
function P.legacy(player)
	local key = Chaos.storage.paragonLegacy
	return key and math.max(0, player:getStorageValue(key)) or 0
end

-- once per character: store the points the O135 cut took (0 for a character at or below slowFrom). Returns the grant.
function P.grantLegacy(player)
	local key = Chaos.storage.paragonLegacy
	if not key or player:getStorageValue(key) >= 0 then
		return 0
	end
	local n = P.legacyPoints(player:getLevel())
	player:setStorageValue(key, n)
	return n
end

-- the Paragon points a player owns (levels + exchanged tree points + the old track's points); `level` defaults to the player's
function P.pointsOf(player, level)
	return P.totalPoints(level or player:getLevel(), P.converted(player), P.legacy(player))
end

-- free passive tree points (owned minus the nodes of the active preset), 0 without the tree module
function P.treeFree(player)
	local T = ChaosPassiveTree and ChaosPassiveTree.internal
	if not T or not T.totalPoints or not T.loadPresets then
		return 0
	end
	local rows = T.loadPresets(player:getGuid())
	local active = rows[1]
	return math.max(0, T.totalPoints(player) - (active and #active.nodes or 0))
end

function P.allocation(player)
	local id = player:getId()
	if not P.cache[id] then
		P.cache[id] = P.load(player:getGuid())
	end
	return P.cache[id]
end

-- called by ChaosPassiveTree.apply: adds the Paragon percentages to the tree's summed bonuses
function P.addBonuses(player, bonuses)
	for key, value in pairs(P.bonusesOf(P.allocation(player))) do
		bonuses[key] = (bonuses[key] or 0) + value
	end
	return bonuses
end

local function reapply(player)
	if ChaosPassiveTree and ChaosPassiveTree.apply then
		ChaosPassiveTree.apply(player)
	end
end

-- ---------------------------------------------------------------- protocol
local function message(player, title, text)
	Chaos.send(player, OPCODE, "sendMessage", {title = title, message = text})
end

function P.state(player)
	local alloc = P.allocation(player)
	local total = P.pointsOf(player)
	local spent = P.spent(alloc)
	local categories = {}
	for i, category in ipairs(cfg.categories) do
		local stats = {}
		for j, stat in ipairs(category.stats) do
			stats[j] = {key = stat.key, name = stat.name, desc = stat.desc, perPoint = stat.perPoint,
				maxPoints = stat.maxPoints, points = alloc[stat.key] or 0}
		end
		categories[i] = {key = category.key, name = category.name, stats = stats}
	end
	local masteryRows = {}
	for i, key in ipairs(P.masteryOrder) do
		local d = P.mastery[key]
		local ranks = alloc[key] or 0
		masteryRows[i] = {key = key, name = d.name, desc = d.desc, category = d.category, ranks = ranks, scale = d.scale, h = d.h,
			value = P.masteryValue(key, ranks), next = P.masteryValue(key, ranks + 1) - P.masteryValue(key, ranks)}
	end
	return {
		unlocked = P.unlocked(player:getLevel()) or spent > 0, level = player:getLevel(), startLevel = cfg.startLevel,
		total = total, spent = spent, free = math.max(0, total - spent),
		mastery = {maxRanks = cfg.mastery and cfg.mastery.maxRanks or 0, rows = masteryRows},
		exchange = {ratio = (cfg.exchange or {}).ratio or 1, treeFree = P.treeFree(player), converted = P.converted(player)},
		-- respec.lua prices the reset (respec_config.lua); the old rule if it is not loaded
		resetCost = ChaosRespec and ChaosRespec.fullCost(player, "paragon") or player:getLevel() * Chaos.passive.resetCostPerLevel,
		categories = categories
	}
end

function P.sendState(player)
	Chaos.send(player, OPCODE, "paragonState", P.state(player))
end

function P.hasAllocation(player)
	return P.spent(P.allocation(player)) > 0
end

-- free reset (store service); reapply = false when the caller reapplies itself
function P.resetAll(player, noReapply)
	P.save(player:getGuid(), {})
	P.cache[player:getId()] = {}
	if not noReapply then
		reapply(player)
	end
	P.sendState(player)
end

P.actions = {
	paragonRequest = function(player)
		P.sendState(player)
	end,

	paragonApply = function(player, data)
		local current = P.allocation(player)
		local alloc, err = P.validate(type(data) == "table" and data.alloc, current,
			P.pointsOf(player), player:getLevel())
		if not alloc then
			message(player, "Paragon", err)
			P.sendState(player)
			return
		end
		if P.spent(alloc) == P.spent(current) then
			P.sendState(player)
			return
		end
		P.save(player:getGuid(), alloc)
		P.cache[player:getId()] = alloc
		reapply(player)
		P.sendState(player)
	end,

	paragonMastery = function(player, data)
		data = type(data) == "table" and data or {}
		local alloc, err = P.validateMastery(data.key, data.n, P.allocation(player), P.pointsOf(player), player:getLevel())
		if not alloc then
			message(player, "Paragon", err)
			P.sendState(player)
			return
		end
		P.save(player:getGuid(), alloc)
		P.cache[player:getId()] = alloc
		reapply(player)
		P.sendState(player)
	end,

	-- free passive tree points -> Paragon points, for good (Chaos.paragon.exchange)
	paragonConvert = function(player, data)
		data = type(data) == "table" and data or {}
		local n = tonumber(data.n)
		if not P.unlocked(player:getLevel()) then
			message(player, "Paragon", string.format("The Paragon track unlocks at level %d.", cfg.startLevel))
			return
		end
		local free = P.treeFree(player)
		if not n or n ~= math.floor(n) or n < 1 or n > free then
			message(player, "Paragon", "You do not have that many free passive points.")
			P.sendState(player)
			return
		end
		local gained = n * ((cfg.exchange or {}).ratio or 1)
		player:setStorageValue(Chaos.storage.paragonConverted, P.converted(player) + n)
		local T = ChaosPassiveTree and ChaosPassiveTree.internal
		if T and T.sendPoints then
			T.sendPoints(player)
		end
		P.sendState(player)
		message(player, "Paragon", string.format("%d passive point%s became %d Paragon point%s.", n, n == 1 and "" or "s",
			gained, gained == 1 and "" or "s"))
	end,

	paragonReset = function(player)
		if not P.hasAllocation(player) then
			message(player, "Paragon", "There is nothing to reset.")
			P.sendState(player)
			return
		end
		local cost = player:getLevel() * Chaos.passive.resetCostPerLevel
		if not Chaos.pay(player, cost) then
			message(player, "Paragon", string.format("You need %d gold coins (carried or in the bank) to reset your Paragon points.", cost))
			return
		end
		P.resetAll(player)
		message(player, "Paragon", string.format("Your Paragon points were reset for %d gold coins.", cost))
	end
}

-- ---------------------------------------------------------------- gold find (pure part tested)
local COINS = {{2160, 10000}, {2152, 100}, {2148, 1}} -- crystal, platinum, gold coin

-- extra gold for `value` gold in the corpse at `pct` percent; random(0..1) decides the fraction
function P.goldBonus(value, pct, random)
	if value <= 0 or pct <= 0 then
		return 0
	end
	local exact = value * pct / 100
	local whole = math.floor(exact)
	if (random or math.random)() < exact - whole then
		whole = whole + 1
	end
	return whole
end

-- coin stacks for an amount: {{id, count}, ...}
function P.coins(amount)
	local out = {}
	for _, coin in ipairs(COINS) do
		local n = math.floor(amount / coin[2])
		amount = amount - n * coin[2]
		while n > 0 do
			local stack = math.min(n, 100)
			out[#out + 1] = {coin[1], stack}
			n = n - stack
		end
	end
	return out
end

local function corpseGold(corpse)
	local value = 0
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item then
			for _, coin in ipairs(COINS) do
				if item:getId() == coin[1] then
					value = value + item:getCount() * coin[2]
				end
			end
		end
	end
	return value
end

local goldCb = EventCallback
goldCb.onDropLoot = function(self, corpse)
	local owner = corpse and Player(corpse:getCorpseOwner())
	local bonuses = owner and ChaosPassiveCache and ChaosPassiveCache[owner:getId()]
	local pct = bonuses and bonuses.paragonGoldFind or 0
	if pct <= 0 then
		return
	end
	local extra = P.goldBonus(corpseGold(corpse), pct)
	for _, stack in ipairs(P.coins(extra)) do
		corpse:addItem(stack[1], stack[2])
	end
end
-- after the stock loot (0) and the Chaos loot layer (1), before autoloot (3), so autoloot picks the extra coins up
goldCb:register(2)

-- ---------------------------------------------------------------- login / level / logout
local login = CreatureEvent("ChaosParagonLogin")
function login.onLogin(player)
	player:registerEvent("ChaosParagonAdvance")
	player:registerEvent("ChaosParagonLogout")
	-- refund over budget (the level dropped below what was spent); runs before or after the tree's login, either way
	-- the tree's apply reads the allocation from the cache
	local granted = P.grantLegacy(player)
	if granted > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"%d Paragon points came back: the points the track change of 2026-10-23 took. Open the passive tree and press Paragon.",
			granted))
	end
	local alloc = P.allocation(player)
	local total = P.pointsOf(player)
	if P.spent(alloc) > total then
		P.save(player:getGuid(), {})
		P.cache[player:getId()] = {}
		reapply(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"Your Paragon points were refunded for free: you had spent more than your %d points.", total))
	end
	return true
end
login:register()

local advance = CreatureEvent("ChaosParagonAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill ~= SKILL_LEVEL then
		return true
	end
	-- speed % follows the base speed, which grows with the level
	if ChaosPassiveRefreshSpeed then
		ChaosPassiveRefreshSpeed(player)
	end
	if newLevel > oldLevel and newLevel > cfg.startLevel then
		local free = P.pointsOf(player, newLevel) - P.spent(P.allocation(player))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"You have %d unspent Paragon point%s. Open the passive tree and press Paragon.", free, free == 1 and "" or "s"))
	end
	return true
end
advance:register()

local logout = CreatureEvent("ChaosParagonLogout")
function logout.onLogout(player)
	P.cache[player:getId()] = nil
	return true
end
logout:register()
