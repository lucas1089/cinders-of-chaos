-- Guild levels and guild halls: pure logic (no engine calls), shared by guild.lua, guild_hall.lua and
-- server/tests/guild_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible (integers through math.floor).
--
-- Level curve
--   C.levelNeed(level, cfg)            GXP from `level` to level + 1 (nil at the max level)
--   C.totalFor(level, cfg)             GXP from level 1 to `level`
--   C.levelOf(xp, cfg)                 level, GXP into the level, GXP the level needs (0 at the max), percent
-- Contributions
--   C.expForLevel(level)               the engine's experience formula (total experience of a level)
--   C.expShare(exp, level, carry, used, cfg)   GXP of a member's experience: gxp, new carry, capped
--   C.boardAmount(board, value, cfg)   GXP for one ChaosLeaderboard.record call (nil: the board gives none)
--   C.capAmount(amount, used, cap)     how much of `amount` still fits under a daily cap
-- Perks
--   C.perksAt(level, cfg)              {xp, loot, respec, depotSlots, scroll, aura, hall} (clamped by cfg.caps)
--   C.perkList(level, cfg)             every perk step with its text and whether it is reached
--   C.perkText(perk)                   "+1% experience, guild hall scroll"
-- Hall
--   C.hallBuyError(info, cfg)          nil or why a hall cannot be bought
--   C.upgradeDef(key, cfg)             the upgrade entry of cfg.hall.upgrades
--   C.upgradeError(key, info, cfg)     nil, next tier or the reason it cannot be bought
--   C.upgradeView(upgrades, level, cfg)   list for the window (tier, max, next cost / level, reason)
--   C.rentAmount(upgrades, cfg)        weekly rent
--   C.rentState(paidUntil, now, cfg)   "paid" | "grace" | "locked", seconds until due (negative: overdue)
--   C.activeUpgrades(upgrades, state)  upgrades that work now (none while locked)
--   C.allocSlot(used, unusable, max)   lowest free slot (1-based) or nil
--   C.slotOrigin(slot, cfg), C.layout(slot, cfg), C.footprint(slot, cfg), C.slotAt(pos, cfg)
-- Depot
--   C.depotCapacity(level, cfg), C.depotPutError(info, cfg), C.depotTakeError(info, cfg)
--   C.encodeAttrs(list), C.decodeAttrs(text)   item attributes <-> text ("s:key=value;n:key=12")
--   C.logLine(entry)                   one depot / bank log line for the window
-- Weekly board
--   C.weekKey(t, hour)                 YYYYMMDD of the Monday that starts t's week (the week starts at `hour`)
--   C.rankGuilds(rows)                 sorted copy with rank (points, then level, then guild id)
-- Texts
--   C.money(n)                         "1,250,000"

ChaosGuildCore = ChaosGuildCore or {}
local C = ChaosGuildCore

local floor = math.floor

local function round(x)
	return floor(x + 0.5)
end

-- ---------------------------------------------------------------- level curve
function C.levelNeed(level, cfg)
	level = floor(tonumber(level) or 1)
	if level < 1 or level >= (cfg.maxLevel or 20) then
		return nil
	end
	local c = cfg.curve or {}
	local r = c.round or 10
	return round((c.base or 300) * level ^ (c.power or 1.5) / r) * r
end

function C.totalFor(level, cfg)
	local total = 0
	for l = 1, floor(level) - 1 do
		total = total + (C.levelNeed(l, cfg) or 0)
	end
	return total
end

function C.levelOf(xp, cfg)
	xp = math.max(0, floor(tonumber(xp) or 0))
	local level = 1
	while true do
		local need = C.levelNeed(level, cfg)
		if not need then
			return level, 0, 0, 100
		end
		if xp < need then
			return level, xp, need, floor(xp * 100 / need)
		end
		xp = xp - need
		level = level + 1
	end
end

-- ---------------------------------------------------------------- contributions
-- total experience of a level (TFS: Player::getExpForLevel)
function C.expForLevel(level)
	local l = floor(level) - 1
	return floor((50 * l * l * l - 150 * l * l + 400 * l) / 3)
end

-- exp gained by a member at `level`; carry = the fraction kept from earlier gains; used = GXP from experience the
-- member already gave today. Returns gxp (integer), new carry, capped (true when the daily cap cut it)
function C.expShare(exp, level, carry, used, cfg)
	local s = cfg.sources and cfg.sources.exp or {}
	exp = tonumber(exp) or 0
	carry = tonumber(carry) or 0
	used = tonumber(used) or 0
	local cap = s.dailyCap or 0
	if exp <= 0 then
		return 0, carry, false
	end
	if cap > 0 and used >= cap then
		return 0, 0, true
	end
	level = math.max(1, floor(tonumber(level) or 1))
	local levelExp = C.expForLevel(level + 1) - C.expForLevel(level)
	if levelExp <= 0 then
		levelExp = 100
	end
	local value = carry + exp / levelExp * (s.levelUnit or 1000) * (s.share or 0.01)
	local gxp = floor(value)
	local rest = value - gxp
	if cap > 0 and used + gxp >= cap then
		return cap - used, 0, true
	end
	return gxp, rest, false
end

function C.boardDef(board, cfg)
	local boards = cfg.sources and cfg.sources.boards or {}
	if type(board) ~= "string" then
		return nil
	end
	if boards[board] then
		return boards[board]
	end
	for key, def in pairs(boards) do
		if def.prefix and board:sub(1, #key) == key then
			return def
		end
	end
	return nil
end

function C.boardAmount(board, value, cfg)
	local def = C.boardDef(board, cfg)
	if not def then
		return nil
	end
	value = math.max(0, tonumber(value) or 0)
	local amount = floor((def.flat or 0) + (def.perValue or 0) * value)
	if def.max and amount > def.max then
		amount = def.max
	end
	return math.max(0, amount)
end

function C.capAmount(amount, used, cap)
	amount = math.max(0, floor(tonumber(amount) or 0))
	if not cap or cap <= 0 then
		return amount
	end
	return math.max(0, math.min(amount, cap - (tonumber(used) or 0)))
end

-- ---------------------------------------------------------------- perks
local NUMBER_PERKS = {"xp", "loot", "respec", "depotSlots"}
local FLAG_PERKS = {"scroll", "aura", "hall"}

function C.perksAt(level, cfg)
	local p = {xp = 0, loot = 0, respec = 0, depotSlots = 0, scroll = false, aura = false, hall = false}
	for _, step in ipairs(cfg.perks or {}) do
		if (level or 0) >= step.level then
			for _, k in ipairs(NUMBER_PERKS) do
				p[k] = p[k] + (step[k] or 0)
			end
			for _, k in ipairs(FLAG_PERKS) do
				if step[k] then
					p[k] = true
				end
			end
		end
	end
	local caps = cfg.caps or {}
	for _, k in ipairs(NUMBER_PERKS) do
		if caps[k] and p[k] > caps[k] then
			p[k] = caps[k]
		end
	end
	return p
end

function C.perkText(step)
	local parts = {}
	if step.xp then
		parts[#parts + 1] = string.format("+%d%% experience", step.xp)
	end
	if step.loot then
		parts[#parts + 1] = string.format("+%d%% loot", step.loot)
	end
	if step.respec then
		parts[#parts + 1] = string.format("respec %d%% cheaper", step.respec)
	end
	if step.depotSlots then
		parts[#parts + 1] = string.format("+%d guild depot slots", step.depotSlots)
	end
	if step.scroll then
		parts[#parts + 1] = "a guild hall scroll every day"
	end
	if step.aura then
		parts[#parts + 1] = "the guild aura"
	end
	if step.hall then
		parts[#parts + 1] = "a guild hall can be bought"
	end
	return table.concat(parts, ", ")
end

function C.perkList(level, cfg)
	local list = {}
	for _, step in ipairs(cfg.perks or {}) do
		list[#list + 1] = {level = step.level, text = C.perkText(step), active = (level or 0) >= step.level}
	end
	return list
end

-- ---------------------------------------------------------------- hall: buying and upgrades
-- info = {guildId, rank, level, hasHall, from ("bank" | "self"), bank, money}
function C.hallBuyError(info, cfg)
	local h = cfg.hall
	if not info.guildId or info.guildId == 0 then
		return "You are not in a guild."
	end
	if (info.rank or 0) < (h.buyRank or 3) then
		return "Only the guild leader can buy the guild hall."
	end
	if info.hasHall then
		return "Your guild already owns a guild hall."
	end
	if (info.level or 1) < h.level then
		return string.format("Your guild needs guild level %d for a guild hall.", h.level)
	end
	if info.from == "bank" then
		if (info.bank or 0) < h.cost then
			return string.format("The guild bank holds %s gold; the hall costs %s.", C.money(info.bank or 0), C.money(h.cost))
		end
	elseif info.from == "self" then
		if (info.money or 0) < h.cost then
			return string.format("You have %s gold; the hall costs %s.", C.money(info.money or 0), C.money(h.cost))
		end
	else
		return "Pay from the guild bank or with your own gold."
	end
	return nil
end

function C.upgradeDef(key, cfg)
	for _, u in ipairs(cfg.hall.upgrades or {}) do
		if u.key == key then
			return u
		end
	end
	return nil
end

-- info = {rank, level, hasHall, upgrades = {key = tier}, rentState, bank}; returns reason (or nil), next tier def, tier no.
function C.upgradeError(key, info, cfg)
	local def = C.upgradeDef(key, cfg)
	if not def then
		return "Unknown upgrade."
	end
	if not info.hasHall then
		return "Your guild has no guild hall."
	end
	if (info.rank or 0) < (cfg.hall.upgradeRank or 2) then
		return "Only the guild leader or a vice-leader can buy upgrades."
	end
	local ups = info.upgrades or {}
	local cur = ups[key] or 0
	local nextTier = def.tiers[cur + 1]
	if not nextTier then
		return def.name .. " is already at its highest tier.", nil, cur
	end
	if info.rentState == "locked" then
		return "Pay the hall's rent first.", nextTier, cur + 1
	end
	if (info.level or 1) < nextTier.level then
		return string.format("%s needs guild level %d.", def.name, nextTier.level), nextTier, cur + 1
	end
	for _, req in ipairs(nextTier.requires or {}) do
		if (ups[req] or 0) < 1 then
			local rd = C.upgradeDef(req, cfg)
			return string.format("%s needs the %s first.", def.name, rd and rd.name or req), nextTier, cur + 1
		end
	end
	if info.bank and info.bank < nextTier.cost then
		return string.format("The guild bank holds %s gold; %s costs %s.", C.money(info.bank), def.name,
			C.money(nextTier.cost)), nextTier, cur + 1
	end
	return nil, nextTier, cur + 1
end

function C.upgradeView(info, cfg)
	local list = {}
	for _, def in ipairs(cfg.hall.upgrades or {}) do
		local reason, nextTier = C.upgradeError(def.key, info, cfg)
		local tier = (info.upgrades or {})[def.key] or 0
		list[#list + 1] = {key = def.key, name = def.name, info = def.info, tier = tier, max = #def.tiers,
			cost = nextTier and nextTier.cost or 0, level = nextTier and nextTier.level or 0,
			canBuy = reason == nil, reason = reason or ""}
	end
	return list
end

function C.tierCount(upgrades)
	local n = 0
	for _, tier in pairs(upgrades or {}) do
		n = n + (tonumber(tier) or 0)
	end
	return n
end

function C.rentAmount(upgrades, cfg)
	local r = cfg.hall.rent
	return (r.base or 0) + (r.perTier or 0) * C.tierCount(upgrades)
end

function C.rentState(paidUntil, now, cfg)
	paidUntil = tonumber(paidUntil) or 0
	local left = paidUntil - now
	if left > 0 then
		return "paid", left
	end
	if -left < (cfg.hall.rent.graceHours or 0) * 3600 then
		return "grace", left
	end
	return "locked", left
end

-- when rent is paid at `now` for a hall paid until `paidUntil`: the new paid-until time. A hall in its grace time
-- continues its period; a locked hall starts a new period now (the weeks it was locked are not charged).
function C.rentPaidUntil(paidUntil, now, cfg)
	local period = (cfg.hall.rent.periodDays or 7) * 86400
	local state = C.rentState(paidUntil, now, cfg)
	if state == "locked" then
		return now + period
	end
	return math.max(paidUntil, now - period) + period
end

function C.activeUpgrades(upgrades, state)
	local active = {}
	if state == "locked" then
		return active
	end
	for k, tier in pairs(upgrades or {}) do
		if (tonumber(tier) or 0) > 0 then
			active[k] = tier
		end
	end
	return active
end

-- ---------------------------------------------------------------- hall: slots and layout
function C.allocSlot(used, unusable, max)
	for slot = 1, max do
		if not (used and used[slot]) and not (unusable and unusable[slot]) then
			return slot
		end
	end
	return nil
end

function C.slotOrigin(slot, cfg)
	local h = cfg.hall
	local i = slot - 1
	return {x = h.origin.x + (i % h.columns) * h.stride, y = h.origin.y + floor(i / h.columns) * h.stride, z = h.origin.z}
end

-- every position of one hall slot. Walls at x 0..w+1 / y 0..h+1 of the origin; floor inside.
function C.layout(slot, cfg)
	local o = C.slotOrigin(slot, cfg)
	local W, H = cfg.hall.inner.w, cfg.hall.inner.h
	local function at(dx, dy)
		return {x = o.x + dx, y = o.y + dy, z = o.z}
	end
	local cx = floor((W + 1) / 2) -- centre column (11 for 21)
	local L = {slot = slot, origin = o, w = W, h = H,
		box = {x1 = o.x, y1 = o.y, x2 = o.x + W + 1, y2 = o.y + H + 1, z = o.z},
		exit = at(cx, H), -- forcefield in the south, back to the temple
		arrival = at(cx, H - 2),
		hub = {}, dummies = {}, trophies = {}, basins = {at(1, 1), at(W, 1), at(1, H), at(W, H)},
		flags = {at(cx - 2, 1), at(cx + 2, 1)},
		bench = at(W - 1, 4),
		depot = at(W - 1, 8),
		dummyMonster = at(4, 7)}
	for i = 1, 4 do
		L.hub[i] = at(cx - 7 + 3 * i + (i > 2 and 2 or 0), 2) -- 4 portals along the north wall, a gap in the middle
	end
	for i = 1, 3 do
		L.dummies[i] = at(1, 3 + 3 * i) -- along the west wall
	end
	for i = 1, 4 do
		L.trophies[i] = at(cx - 6 + 2 * i + (i > 2 and 4 or 0), H - 3) -- two either side of the way to the exit
	end
	return L
end

-- teleport hub (guild_hall.lua). The portal's look text announces "level N+": a player below it is refused.
-- Returns nil when the player may go, else the text for the refusal ("nowhere" for no destination).
function C.hubGate(dest, level)
	if not dest then
		return "nowhere"
	end
	local need = tonumber(dest.level) or 0
	if (tonumber(level) or 0) < need then
		return string.format("%s needs level %d.", tostring(dest.name or "This portal"), need)
	end
	return nil
end

-- the nearest free tile around pos, within `radius` tiles (3), square rings outwards; isFree(x, y, z) -> boolean
-- (the engine: ground, nothing blocking, no creature, no house). nil when there is none.
function C.landingSpot(pos, isFree, radius)
	for r = 0, radius or 3 do
		for dy = -r, r do
			for dx = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r and isFree(pos.x + dx, pos.y + dy, pos.z) then
					return {x = pos.x + dx, y = pos.y + dy, z = pos.z}
				end
			end
		end
	end
	return nil
end

-- the indexes of the destinations that would answer "This portal leads nowhere right now." (no landing tile)
function C.hubDeadEnds(hub, isFree)
	local out = {}
	for i, d in ipairs(hub or {}) do
		if not C.landingSpot(d.pos, isFree) then
			out[#out + 1] = i
		end
	end
	return out
end

function C.footprint(slot, cfg)
	local L = C.layout(slot, cfg)
	local b = L.box
	local list = {}
	for y = b.y1, b.y2 do
		for x = b.x1, b.x2 do
			list[#list + 1] = {x = x, y = y, z = b.z, wall = x == b.x1 or x == b.x2 or y == b.y1 or y == b.y2}
		end
	end
	return list
end

-- the slot a position is in (inside the walls' box), or nil
function C.slotAt(pos, cfg)
	local h = cfg.hall
	if not pos or pos.z ~= h.origin.z then
		return nil
	end
	local dx, dy = pos.x - h.origin.x, pos.y - h.origin.y
	if dx < 0 or dy < 0 then
		return nil
	end
	local col, row = floor(dx / h.stride), floor(dy / h.stride)
	if col >= h.columns then
		return nil
	end
	local slot = row * h.columns + col + 1
	if slot > h.maxSlots then
		return nil
	end
	local b = C.layout(slot, cfg).box
	if pos.x <= b.x2 and pos.y <= b.y2 then
		return slot
	end
	return nil
end

-- ---------------------------------------------------------------- depot
function C.depotCapacity(level, cfg)
	return (cfg.depot.slots or 30) + C.perksAt(level, cfg).depotSlots
end

-- info = {member, active (depot upgrade working), used, capacity, container, pickupable, count, stackable}
function C.depotPutError(info, cfg)
	if not info.member then
		return "Only members of this guild can use its depot."
	end
	if not info.active then
		return "The guild depot is locked (no depot upgrade, or the rent is unpaid)."
	end
	if info.container then
		return "Containers cannot go into the guild depot; put the items in one by one."
	end
	if not info.pickupable then
		return "That cannot go into the guild depot."
	end
	-- the depot gives back a plain copy that keeps only the attributes of cfg.depot.customKeys: a store item, a
	-- store-bound one (pouches, Everfull Ration, Nemesis items), a locked one or a quest item would come out
	-- tradable (the player market refuses all of these, market_core.lua C.itemRefusal)
	if info.store or info.storeBound then
		return "That cannot go into the guild depot."
	end
	if info.locked then
		return "The item is locked. Unlock it first."
	end
	if (info.uniqueId or 0) > 0 or info.decaying then
		return "That cannot go into the guild depot."
	end
	if (info.count or 1) > (cfg.depot.maxStack or 100) then
		return "That stack is too large."
	end
	if (info.used or 0) >= (info.capacity or 0) then
		return string.format("The guild depot is full (%d / %d).", info.used or 0, info.capacity or 0)
	end
	return nil
end

-- info = {member, active, rank, takenToday, exists}
function C.depotTakeError(info, cfg)
	if not info.member then
		return "Only members of this guild can use its depot."
	end
	if not info.active then
		return "The guild depot is locked (no depot upgrade, or the rent is unpaid)."
	end
	if (info.rank or 0) < (cfg.depot.takeRank or 1) then
		return "Your rank may not take items from the guild depot."
	end
	if not info.exists then
		return "That item is no longer in the guild depot."
	end
	local limit = cfg.depot.takePerDay or 0
	if limit > 0 and (info.rank or 0) < 2 and (info.takenToday or 0) >= limit then
		return string.format("You took %d items from the guild depot today, the most a member may.", limit)
	end
	return nil
end

local function escape(s)
	return (tostring(s):gsub("[%%;=:]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function unescape(s)
	return (s:gsub("%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

-- list = {{key, value}} (value a number or a string; key a string or a number for standard attributes)
function C.encodeAttrs(list)
	local parts = {}
	for _, a in ipairs(list or {}) do
		local v = a[2]
		if type(v) == "number" then
			parts[#parts + 1] = "n:" .. escape(a[1]) .. "=" .. (v == floor(v) and string.format("%d", v) or tostring(v))
		elseif type(v) == "string" then
			parts[#parts + 1] = "s:" .. escape(a[1]) .. "=" .. escape(v)
		end
	end
	return table.concat(parts, ";")
end

function C.decodeAttrs(text)
	local list = {}
	if type(text) ~= "string" or text == "" then
		return list
	end
	for part in text:gmatch("[^;]+") do
		local kind, key, value = part:match("^([ns]):([^=]*)=(.*)$")
		if kind then
			key = unescape(key)
			if kind == "n" then
				list[#list + 1] = {key, tonumber(value) or 0}
			else
				list[#list + 1] = {key, unescape(value)}
			end
		end
	end
	return list
end

-- The text a log row stores is English (written once, whoever reads it). At display time it is matched against these
-- patterns (numbers and names taken out) and told in the reader's language: {Lua pattern, key, kinds of the captures}
-- ("n" a number, "t" a short English word that has its own pt-BR entry, "s" a name that stays as it is). A text that
-- matches nothing (staff rows, free text) is shown as stored. Every key needs a pt-BR entry (i18n_strings.lua).
C.LOG_TEXTS = {
	{"^level (%d+) %-> (%d+)$", "level %d -> %d", "nn"},
	{"^deposit failed, gold returned to the bank balance$", "deposit failed, gold returned to the bank balance", ""},
	{"^hall purchase failed$", "hall purchase failed", ""},
	{"^rent payment failed$", "rent payment failed", ""},
	{"^(.-) purchase failed$", "%s purchase failed", "s"},
	{"^bought the guild hall %(slot (%d+), (.-)%)$", "bought the guild hall (slot %d, %s)", "nt"},
	{"^(.-) tier (%d+)$", "%s tier %d", "sn"},
	{"^rent paid until (.+)$", "rent paid until %s", "s"},
	{"^staff set the rent to (.+)$", "staff set the rent to %s", "s"},
	{"^fed the Summoning Stone (%d+) embers$", "fed the Summoning Stone %d embers", "n"},
	{"^fed the Summoning Stone (%d+) x (.-) %((%d+) embers%)$", "fed the Summoning Stone %d x %s (%d embers)", "nsn"},
	{"^stake of the war offer to (.-) %(held%)$", "stake of the war offer to %s (held)", "s"},
	{"^war stake returned %(offer (.-)%)$", "war stake returned (offer %s)", "t"},
	{"^stake of the war with (.-) %(held%)$", "stake of the war with %s (held)", "s"},
	{"^war with (.-): stake returned %(draw%)$", "war with %s: stake returned (draw)", "s"},
	{"^war with (.-): both stakes won, minus the fee$", "war with %s: both stakes won, minus the fee", "s"},
}

-- the texts of the names a row can carry for the server itself
C.LOG_WORDS = {"Guild", "Guild bank", "Staff", "guild bank", "own gold", "declined", "cancelled", "expired"}

-- t(key, ...): the text in the reader's language (nil: English)
function C.logText(text, t)
	if not t or type(text) ~= "string" then
		return text
	end
	for _, rule in ipairs(C.LOG_TEXTS) do
		if rule[3] == "" then
			if text:find(rule[1]) then
				return t(rule[2])
			end
		else
			local caps = {text:match(rule[1])}
			if #caps > 0 then
				for i = 1, #caps do
					local kind = rule[3]:sub(i, i)
					if kind == "n" then
						caps[i] = tonumber(caps[i])
					elseif kind == "t" then
						caps[i] = t(caps[i])
					end
				end
				return t(rule[2], (table.unpack or unpack)(caps))
			end
		end
	end
	return text
end

-- entry = {at, name, action ("put" | "take" | "deposit" | "withdraw" | "hall" | "upgrade" | "rent"), count, item, amount}
-- t: optional translator, t(key, ...) -> the text in the reader's language (default: English)
function C.logLine(entry, t)
	t = t or function(key, ...) return select("#", ...) > 0 and string.format(key, ...) or key end
	local when = os.date("%d.%m %H:%M", entry.at or 0)
	local who = entry.name or "?"
	if who == "Guild" or who == "Guild bank" or who == "Staff" then
		who = t(who)
	end
	if entry.action == "put" then
		return t("%s %s put in %d x %s", when, who, entry.count or 1, entry.item or "?")
	elseif entry.action == "take" then
		return t("%s %s took out %d x %s", when, who, entry.count or 1, entry.item or "?")
	elseif entry.action == "deposit" then
		return t("%s %s deposited %s gold", when, who, C.money(entry.amount or 0))
	elseif entry.action == "withdraw" then
		return t("%s %s withdrew %s gold", when, who, C.money(entry.amount or 0))
	end
	return string.format("%s %s: %s", when, who, C.logText(entry.text or entry.action or "", t))
end

-- ---------------------------------------------------------------- weekly board
function C.weekKey(t, hour)
	t = t - (hour or 0) * 3600
	local d = os.date("*t", t)
	local back = (d.wday + 5) % 7 -- days since Monday (wday: 1 = Sunday)
	local monday = os.time({year = d.year, month = d.month, day = d.day - back, hour = 12})
	return tonumber(os.date("%Y%m%d", monday))
end

-- unix time the week of `week` (a weekKey) starts and ends
function C.weekBounds(week, hour)
	local y, m, d = floor(week / 10000), floor(week / 100) % 100, week % 100
	local start = os.time({year = y, month = m, day = d, hour = hour or 0, min = 0, sec = 0})
	local finish = os.time({year = y, month = m, day = d + 7, hour = hour or 0, min = 0, sec = 0})
	return start, finish
end

function C.rankGuilds(rows)
	local list = {}
	for _, r in ipairs(rows or {}) do
		list[#list + 1] = r
	end
	table.sort(list, function(a, b)
		if (a.points or 0) ~= (b.points or 0) then
			return (a.points or 0) > (b.points or 0)
		end
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) > (b.level or 0)
		end
		return (a.id or 0) < (b.id or 0)
	end)
	local out = {}
	for i, r in ipairs(list) do
		local c = {}
		for k, v in pairs(r) do
			c[k] = v
		end
		c.rank = i
		out[i] = c
	end
	return out
end

-- ---------------------------------------------------------------- texts
function C.money(n)
	n = floor(tonumber(n) or 0)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (n < 0 and "-" or "") .. out
end

function C.durationText(s)
	s = math.max(0, floor(s or 0))
	local d, h, m = floor(s / 86400), floor(s % 86400 / 3600), floor(s % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

return C
