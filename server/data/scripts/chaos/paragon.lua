-- paragon.lua: the Paragon track, the long-term goal past the passive tree's point budget.
--
-- Rules (numbers in Chaos.paragon, chaos_constants.lua):
--   * points = (level - startLevel) x pointsPerLevel, so from level 1001 on (the tree budget ends at level 1000)
--   * four categories of two small stats each; a stat takes at most maxPoints, its cap is perPoint x maxPoints
--   * allocations only go up; taking points back is a reset: level x Chaos.passive.resetCostPerLevel gold (the tree's
--     rule), or the store's Passive Tree Reset service (shop_services.lua), which resets the tree and Paragon for free
--   * a character whose level fell below what it has spent is refunded for free at login (like the tree)
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
--                     paragonReset                            -> costs level x 250 gold, then paragonState
--   server -> client  {"action":"paragonState","data":{unlocked, level, startLevel, total, spent, free, resetCost,
--                      categories = [{key, name, stats = [{key, name, desc, perPoint, maxPoints, points}]}]}}
--                     errors use the tree's {"action":"sendMessage"} box

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
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

-- bonus key in the passive tree's bonus table: damage -> paragonDamage
function P.bonusKey(statKey)
	return "paragon" .. statKey:sub(1, 1):upper() .. statKey:sub(2)
end

-- ---------------------------------------------------------------- pure part (server/tests/paragon_test.lua)
function P.totalPoints(level)
	return math.max(0, math.floor(((level or 0) - cfg.startLevel) * (cfg.pointsPerLevel or 1)))
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

-- {paragonDamage = 2.5, ...} for an allocation
function P.bonusesOf(alloc)
	local out = {}
	for key, points in pairs(alloc or {}) do
		local v = P.value(key, points)
		if v > 0 then
			out[P.bonusKey(key)] = v
		end
	end
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
		end
	end
	return alloc
end

function P.save(guid, alloc)
	db.query("DELETE FROM `" .. T .. "` WHERE `player_id` = " .. guid)
	local values = {}
	for _, key in ipairs(P.order) do
		if (alloc[key] or 0) > 0 then
			values[#values + 1] = string.format("(%d, %s, %d)", guid, db.escapeString(key), alloc[key])
		end
	end
	if #values > 0 then
		db.query("INSERT INTO `" .. T .. "` (`player_id`, `stat`, `points`) VALUES " .. table.concat(values, ", "))
	end
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
	local total = P.totalPoints(player:getLevel())
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
	return {
		unlocked = P.unlocked(player:getLevel()) or spent > 0, level = player:getLevel(), startLevel = cfg.startLevel,
		total = total, spent = spent, free = math.max(0, total - spent),
		resetCost = player:getLevel() * Chaos.passive.resetCostPerLevel, categories = categories
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
			P.totalPoints(player:getLevel()), player:getLevel())
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

	paragonReset = function(player)
		if not P.hasAllocation(player) then
			message(player, "Paragon", "There is nothing to reset.")
			P.sendState(player)
			return
		end
		local cost = player:getLevel() * Chaos.passive.resetCostPerLevel
		if not player:removeMoney(cost) then
			message(player, "Paragon", string.format("You need %d gold coins to reset your Paragon points.", cost))
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
	local alloc = P.allocation(player)
	local total = P.totalPoints(player:getLevel())
	if P.spent(alloc) > total then
		P.save(player:getGuid(), {})
		P.cache[player:getId()] = {}
		reapply(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
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
		local free = P.totalPoints(newLevel) - P.spent(P.allocation(player))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
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
