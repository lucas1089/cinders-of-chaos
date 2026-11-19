-- TEST ONLY: never ship this file. It is not under server/data, so install_all.py never copies it.
-- Pure rules of the tester bots' helper (tester_helper.lua; server/README.md "Tester bots"; tests/tester_helper_test.lua).
-- chaos-ctl.sh testers start copies both files into data/scripts as zz_tester_helper.lua and zz_tester_helper_core.lua
-- and removes them at stop. The engine loads this one as a script too: it only sets a table.
--
--   H.eligible(name, storageValue)     the helper acts ONLY on a character that has BOTH the tester storage (= 1) and a
--                                       "Tester Xxx" name. Anything else (every real player) is never touched.
--   H.nearest(origin, list, range)     the nearest live, unowned monster on the same floor within range
--   H.directionTo(from, to)            the direction to face a target (0 north, 1 east, 2 south, 3 west)
--   H.parseCommand(param)              "!tester <command> [arg] [#N]" -> command, arg, N (unknown -> nil; N: the bot's command number, O579)
--   H.encode(kind, data)               one helper line: "[tester-helper] <kind> <json>" (the bot reads it)
--   H.hitAnomaly(hit)                  a hit taken or dealt far out of range for the level, or a one-shot from full
--   H.pushHit(list, now, hit)          remember a hit a tester took (the last 10 seconds)
--   H.deathRecord(list, now, d)        the death event: hits, damage and the biggest hit of the last 5 seconds, as % of max health
--   H.xpAnomaly(level, gained)         an experience gain that is negative or absurd for the level
--   H.itemAnomaly(item)                an item with an impossible count or stat
--   H.parsePlace(arg)                  "enter <kind> [N]" / "enter npc <name>" / "enter rift [tier]" -> a place, or nil
--   H.parseSpellQuest(arg)             "spellquest <sub> ..." -> {sub, quest, step, kills, fragments, n, boss} (state | reset | set Q STEP
--                                       [KILLS [FRAGMENTS]] | kill [N] [boss] | trial | leave | complete), or nil and the reason
--   H.pickMark(marks, kind, n)         the n-th map mark of a kind (data/chaos_poi.lua marks; wraps), and the count
--   H.placeCounts(marks)               {kind = count} of the marks the helper can bring a tester to
--   H.bagPlan(items, want, held)       the backpack clean-up: which top-level items to remove (every id not in `want`) and which
--                                       supplies to add (an id of `want` held under half of its number, up to the number)
--   H.targetKind(owner, target)       what a creature's target is, seen from `owner`: "none", "owner", "summon" (a summon of the
--                                       owner or of its party), "ally" (a party member), "monster" (wild), "player" (a stranger)
--   H.summonAnomalies(snap, now, seen) O86: the rules summon_targets_owner / summon_targets_ally / owner_targets_summon over a
--                                       snapshot {who, ownerTarget, summons = {{name, id, target}}}, once per 30 s per rule
--   H.closedGuards(rules)              O582: what the deployed testers_core.lua rules answer for a tester against a player and for
--                                       testers with the mode off, per closed system: {system = {mixed = refused, off = refused, together = allowed}}
--   H.parseRaid(arg)                   O588: "raid [state | path | portal | close]" -> the word (state when empty), or nil and the usage
--   H.pathDirections(path)             O588: a path of Creature:getPathTo cut to the directions 0-7 the bot can walk (at most H.RAID_PATH_MAX)
--   H.raidAnswer(probe, extra)         O588: the answer of `raid`: ChaosRaid.probe of the tester, cut down to what the bot reads (the
--                                       position, the entrance, the guide's goal and mode, the run's counts), `extra` merged in
--   H.parseDungeon(arg)                O589: "dungeon [state | path | close]" -> the word (state when empty), or nil and the usage
--   H.dungeonAnswer(probe, extra)      O589: the answer of `dungeon`: ChaosDungeons.probe of the tester cut down to what the bot reads
--   H.parseSiege(arg)                  O592: "siege [state | start | path | portal | close]" -> the word (state when empty), or nil and the usage
--   H.siegeAnswer(probe, extra)        O592: the answer of `siege`: ChaosSiege.probe of the tester cut down to what the bot reads
--   H.parseGuildBoss(arg)              O592: "guildboss [state | path | hall | close]" -> the word (state when empty), or nil and the usage
--   H.guildBossAnswer(probe, extra)    O592: the answer of `guildboss`: ChaosGuildBoss.probe of the tester cut down to what the bot reads
--   H.parseTower(arg)                  O595: "tower [state | path | close]" -> the word (state when empty), or nil and the usage
--   H.towerAnswer(probe, extra)        O595: the answer of `tower`: ChaosTowerRun.probe of the tester cut down to what the bot reads
--   H.parseTrial(arg)                  O595: "trial [state | path | close]" -> the word (state when empty), or nil and the usage
--   H.trialAnswer(probe, extra)        O595: the answer of `trial`: ChaosTrials.probe of the tester cut down to what the bot reads
--   H.parseDescent(arg)                O595: "descent [state | path | close | sigil]" -> the word, or nil and the usage
--   H.descentAnswer(probe, extra)      O595: the answer of `descent`: ChaosDescent.probe of the tester cut down to what the bot reads
--   H.parseRift(arg)                   O592: "rift [state | key | path | close]" -> {what, tier?}, or nil and the usage
--   H.riftAnswer(probe, extra)         O592: the answer of `rift`: ChaosRift.probe of the tester cut down to what the bot reads
--   H.parsePath(arg)                   O589: "path <kind> [N]" / "path npc <name>" / "path pos X Y Z" -> the destination, or nil and the usage
--   H.pathAnswer(from, dest, dirs, extra)  O589: the answer of `path`: the engine directions, the destination and the distance left
--   H.onlineLine(count, last, minute)  the console line "[tester-helper] testers online: N" when the count changed
--                                       since the last line, or every 5 minutes; nil otherwise
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosTesterHelperCore = ChaosTesterHelperCore or {}
local H = ChaosTesterHelperCore

H.STORAGE = 7102900 -- Chaos.storage.tester (chaos_constants.lua; the test checks they agree)
H.MARK = "[tester-helper]"
H.ANOMALY = "[tester-anomaly]"
H.COMMANDS = {town = true, depot = true, summons = true, party = true, chest = true, shop = true, hunt = true, info = true, enter = true, places = true, bag = true, spellquest = true, waystone = true, riftrun = true, pet = true, unique = true, fists = true, blades = true, give = true, closed = true, raid = true, dungeon = true, path = true, siege = true, guildboss = true, rift = true, tower = true, descent = true, trial = true, ascended = true, omen = true, bounty = true, mainquest = true, nemesis = true, daily = true, chronicle = true, vael = true, goblin = true, invasion = true, journey = true, pvp = true, boss = true, pocket = true, wsmap = true, ascend = true, gather = true}

-- numbers of the anomaly rules (a hit is "absurd" far above anything the game should do; tune with the report)
H.limits = {
	takenOverMaxHealth = 3, -- a single hit taken larger than 3x the tester's max health
	dealtBase = 5000, -- a single hit dealt larger than dealtBase + dealtPerLevel * level
	dealtPerLevel = 400,
	xpPerLevel = 2000000, -- one experience gain larger than xpPerLevel * level (the cap rules allow far less)
	maxStack = 100,
	maxAttr = 10000000, -- a numeric item attribute beyond this is impossible
}

function H.eligible(name, storageValue)
	return type(name) == "string" and name:match("^Tester [A-Z][a-z][a-z]$") ~= nil and storageValue == 1
end

local function cheb(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- list: {pos = {x, y, z}, health, owned (has a master), id}
function H.nearest(origin, list, range)
	local best, bestD
	for _, c in ipairs(list or {}) do
		if c.pos and c.pos.z == origin.z and not c.owned and (c.health or 0) > 0 then
			local d = cheb(origin, c.pos)
			if d <= range and (not bestD or d < bestD or (d == bestD and (c.id or 0) < (best.id or 0))) then
				best, bestD = c, d
			end
		end
	end
	return best, bestD
end

function H.directionTo(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	if math.abs(dx) > math.abs(dy) then
		return dx > 0 and 1 or 3
	end
	return dy > 0 and 2 or 0
end

function H.parseCommand(param)
	if type(param) ~= "string" then
		return nil
	end
	-- O579: the bots end a command with " #N" (N counts their commands): every answer of that command carries "seq": N, so an
	-- answer that arrives after its wait (a busy server) is never taken for the answer of the next command of the same kind
	local seq
	local body, n = param:match("^(.-)%s*#(%d+)%s*$")
	if body then
		param, seq = body, tonumber(n)
	end
	local cmd, arg = param:match("^%s*(%a+)%s*(.-)%s*$")
	cmd = cmd and cmd:lower()
	if not cmd or not H.COMMANDS[cmd] then
		return nil, nil, seq -- the answer "unknown command" still carries the number
	end
	return cmd, arg ~= "" and arg or nil, seq
end

-- !tester waystone <tier 1-15> [loot]: a waystone run of that tier on the game's own code; riftrun <layout | loot>
H.WAYSTONE_MAX = 15
function H.parseWaystone(arg)
	local tier, rest = tostring(arg or ""):match("^%s*(%d+)%s*(%a*)%s*$")
	tier = tonumber(tier)
	if not tier or tier < 1 or tier > H.WAYSTONE_MAX then
		return nil, "usage: waystone <1-15> [loot]"
	end
	if rest ~= "" and rest:lower() ~= "loot" then
		return nil, "usage: waystone <1-15> [loot]"
	end
	return {tier = tier, loot = rest ~= ""}
end

function H.parseRiftRun(arg)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == "" then
		what = "layout"
	end
	what = what and what:lower()
	if what ~= "layout" and what ~= "loot" then
		return nil, "usage: riftrun <layout | loot>"
	end
	return what
end

-- !tester raid [state | path | portal | close] (O588, closed test mode): the facts of the raid a tester sees, the path on foot to
-- the entrance, the step next to the portal when no path is found (the bot takes the last step itself) and the close of the
-- testers' own raid
function H.parseRaid(arg)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == "" then
		what = "state"
	end
	what = what and what:lower()
	if what ~= "state" and what ~= "path" and what ~= "portal" and what ~= "close" then
		return nil, "usage: raid [state | path | portal | close]"
	end
	return what
end

local function xyz(p)
	if type(p) ~= "table" then
		return nil
	end
	return {x = p.x, y = p.y, z = p.z}
end

-- the engine directions of a path (Creature:getPathTo) as the list the bot walks: numbers 0-7 only, at most H.RAID_PATH_MAX of them
H.RAID_PATH_MAX = 80
function H.pathDirections(path)
	local out = {}
	if type(path) ~= "table" then
		return out
	end
	for i = 1, math.min(#path, H.RAID_PATH_MAX) do
		local d = tonumber(path[i])
		if d and d >= 0 and d <= 7 and d == math.floor(d) then
			out[#out + 1] = d
		end
	end
	return out
end

function H.raidAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, minLevel = probe.minLevel, minPlayers = probe.minPlayers,
		maxPlayers = probe.maxPlayers, pos = xyz(probe.pos), pz = probe.pz and true or false, on = probe.on and true or false,
		enabled = probe.enabled ~= false, bosses = probe.bosses, portal = xyz(probe.portal)}
	local r = probe.run
	if type(r) == "table" then
		out.run = {id = r.id, slot = r.slot, side = r.side, players = r.players, killed = r.killed, trash = r.trash,
			cleared = r.cleared and true or false, kills = r.kills, endsIn = r.endsIn, fight = r.fight, phase = r.phase,
			trashLeft = r.trashLeft, monsters = r.monsters, bossHp = r.bossHp, fallen = r.fallen and true or false,
			final = xyz(r.final)}
	end
	local g = probe.guide
	if type(g) == "table" then
		out.guide = {mode = g.mode, goal = xyz(g.goal), why = g.why and tostring(g.why):sub(1, 60) or nil, idx = g.idx,
			where = g.where, wi = g.wi, area = g.area}
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester dungeon [state | path | close] (O589, closed test mode): the dungeons as a person sees them (the list with the level rule,
-- the queue, the kill counter, the nearest monster, the boss), the path on foot to the guide's goal inside a run, and the close of the
-- testers' own run
function H.parseDungeon(arg)
	local usage = "usage: dungeon [state | path | close | weekly | unlock ID N]"
	local what, id, d = tostring(arg or ""):match("^%s*(%a*)%s*(%d*)%s*(%d*)%s*$")
	if not what then
		return nil, usage
	end
	if what == "" then
		what = "state"
	end
	what = what:lower()
	if what == "unlock" then -- O651: the TEST ONLY unlocked difficulty of the bot's own progress
		if id == "" or d == "" then
			return nil, usage
		end
		return {what = "unlock", id = tonumber(id), difficulty = tonumber(d)}
	end
	if id ~= "" or (what ~= "state" and what ~= "path" and what ~= "close" and what ~= "weekly") then
		return nil, usage
	end
	return what
end

H.DUNGEON_LIST_MAX = 24
function H.dungeonAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, pos = xyz(probe.pos), on = probe.on and true or false,
		queued = probe.queued, maxDifficulty = probe.maxDifficulty, soloWait = probe.soloWait}
	if type(probe.list) == "table" then
		out.list = {}
		for i = 1, math.min(#probe.list, H.DUNGEON_LIST_MAX) do
			local d = probe.list[i]
			if type(d) == "table" then
				out.list[#out.list + 1] = {id = d.id, title = d.title and tostring(d.title):sub(1, 40) or nil, level = d.level,
					size = d.size, max = d.max, fixed = d.fixed, weekly = d.weekly}
			end
		end
	end
	local r = probe.run
	if type(r) == "table" then
		out.run = {id = r.id, dungeon = r.dungeon, title = r.title and tostring(r.title):sub(1, 40) or nil, side = r.side, size = r.size,
			members = r.members, difficulty = r.difficulty, percent = r.percent, total = r.total, left = r.left,
			unlocked = r.unlocked and true or false, ended = r.ended and true or false, deaths = r.deaths, bossHp = r.bossHp,
			endsIn = r.endsIn, scaled = r.scaled, bossScaled = r.bossScaled, weekly = r.weekly}
	end
	local g = probe.guide
	if type(g) == "table" then
		out.guide = {mode = g.mode, goal = xyz(g.goal), why = g.why and tostring(g.why):sub(1, 60) or nil, area = g.area}
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester siege [state | start | path | portal | close] (O592, closed test mode): the guild siege as a person sees it, the TEST ONLY start of the
-- testers' own siege, the path on foot to the portal or the next goal inside, the step next to the portal when no path is found, the close
function H.parseSiege(arg)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == "" then
		what = "state"
	end
	what = what and what:lower()
	if what ~= "state" and what ~= "start" and what ~= "path" and what ~= "portal" and what ~= "close" then
		return nil, "usage: siege [state | start | path | portal | close]"
	end
	return what
end

local function team(t)
	if type(t) ~= "table" then
		return nil
	end
	return {name = t.name and tostring(t.name):sub(1, 40) or nil, score = t.score, kills = t.kills}
end

function H.siegeAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, minLevel = probe.minLevel, pos = xyz(probe.pos),
		on = probe.on and true or false, running = probe.running and true or false, phase = probe.phase, side = probe.side,
		guild = probe.guild and tostring(probe.guild):sub(1, 40) or nil, signed = probe.signed and true or false, left = probe.left,
		portal = xyz(probe.portal), enabled = probe.enabled ~= false, radius = probe.radius}
	if probe.inside then
		out.where, out.bracket, out.center, out.gate = probe.where, probe.bracket, xyz(probe.center), xyz(probe.gate)
		out.onPoint, out.downed, out.members = probe.onPoint and true or false, probe.downed and true or false, probe.members
		out.team = team(probe.team)
		out.holder, out.contested = probe.holder and tostring(probe.holder):sub(1, 40) or nil, probe.contested and true or false
		if type(probe.rivals) == "table" then
			out.rivals = {}
			for i = 1, math.min(#probe.rivals, 3) do
				out.rivals[#out.rivals + 1] = team(probe.rivals[i])
			end
		end
		if type(probe.you) == "table" then
			out.you = {points = probe.you.points, kills = probe.you.kills, deaths = probe.you.deaths}
		end
	end
	local g = probe.guide
	if type(g) == "table" then
		local r = type(g.reach) == "table" and {tonumber(g.reach[1]) or 0, tonumber(g.reach[2]) or 0} or nil
		out.guide = {mode = g.mode, goal = xyz(g.goal), reach = r, why = g.why and tostring(g.why):sub(1, 60) or nil, area = g.area}
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester guildboss [state | path | hall | close] (O592, closed test mode): the weekly guild boss as a person sees it, the path on foot to the
-- hall portal, the stone or the next goal inside the arena, the step into the hall when no path is found, the close of the testers' own run
function H.parseGuildBoss(arg)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == "" then
		what = "state"
	end
	what = what and what:lower()
	if what ~= "state" and what ~= "path" and what ~= "hall" and what ~= "close" then
		return nil, "usage: guildboss [state | path | hall | close]"
	end
	return what
end

function H.guildBossAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, minLevel = probe.minLevel, pos = xyz(probe.pos),
		on = probe.on and true or false, enabled = probe.enabled ~= false, guild = probe.guild and tostring(probe.guild):sub(1, 40) or nil,
		rank = probe.rank, side = probe.side, hasHall = probe.hasHall and true or false, inHall = probe.inHall and true or false,
		fuel = probe.fuel, need = probe.need, attempts = probe.attempts, maxAttempts = probe.maxAttempts, killed = probe.killed and true or false,
		running = probe.running and true or false, canSummon = probe.canSummon and true or false,
		reason = probe.reason and tostring(probe.reason):sub(1, 90) or nil, stone = xyz(probe.stone), minPlayers = probe.minPlayers}
	if type(probe.board) == "table" then
		out.board = {}
		for i = 1, math.min(#probe.board, 8) do
			out.board[#out.board + 1] = tostring(probe.board[i]):sub(1, 40)
		end
	end
	local r = probe.run
	if type(r) == "table" then
		out.run = {state = r.state, boss = r.boss, tester = r.tester and true or false, lives = r.lives, livesMax = r.livesMax, players = r.players,
			left = r.left, down = r.down and true or false, enraged = r.enraged and true or false, phase = r.phase, bossPos = xyz(r.bossPos),
			bossHp = r.bossHp, gate = xyz(r.gate)}
	end
	local g = probe.guide
	if type(g) == "table" then
		local reach = type(g.reach) == "table" and {tonumber(g.reach[1]) or 0, tonumber(g.reach[2]) or 0} or nil
		out.guide = {mode = g.mode, goal = xyz(g.goal), reach = reach, why = g.why and tostring(g.why):sub(1, 60) or nil, area = g.area}
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester rift [state | key [tier] | path | close] (O592): a rift opened and walked like a person's. `key` puts a key of the tier (the highest the
-- level may open when none is named) into the backpack where the bot stands (it must be in a protection zone, as for a player); the bot
-- uses it itself; `state` is what the screen shows; `path` the way on foot to the guide's goal; `close` ends the bot's own run
function H.parseRift(arg)
	local usage = "usage: rift [state | key [tier] | path | close]"
	local what, rest = tostring(arg or ""):match("^%s*(%a*)%s*(%d*)%s*$")
	if not what then
		return nil, usage
	end
	if what == "" then
		what = "state"
	end
	what = what:lower()
	if what == "key" then
		local tier = tonumber(rest)
		if tier and (tier < 1 or tier > H.RIFT_MAX) then
			return nil, usage
		end
		return {what = "key", tier = tier}
	end
	if rest ~= "" or (what ~= "state" and what ~= "path" and what ~= "close") then
		return nil, usage
	end
	return {what = what}
end

function H.riftAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, pos = xyz(probe.pos), pz = probe.pz and true or false,
		held = probe.held, keyClientId = probe.keyClientId, tier = probe.tier}
	local r = probe.run
	if type(r) == "table" then
		out.run = {id = r.id, tier = r.tier, theme = r.theme and tostring(r.theme):sub(1, 30) or nil, kind = r.kind, state = r.state, boss = r.boss,
			killed = r.killed, total = r.total, bossAt = r.bossAt, left = r.left, lives = r.lives, players = r.players, floors = r.floors,
			entry = xyz(r.entry), bossPos = xyz(r.bossPos), monsters = r.monsters, bossHp = r.bossHp, links = r.links}
	end
	local g = probe.guide
	if type(g) == "table" then
		local reach = type(g.reach) == "table" and {tonumber(g.reach[1]) or 0, tonumber(g.reach[2]) or 0} or nil
		out.guide = {mode = g.mode, goal = xyz(g.goal), reach = reach, why = g.why and tostring(g.why):sub(1, 60) or nil, area = g.area, via = g.via}
		if type(g.use) == "table" then -- the ladder to use (O651): its tile, client id and place in the tile's stack
			out.guide.use = {x = g.use.x, y = g.use.y, z = g.use.z, clientId = g.use.clientId, stack = g.use.stack}
		end
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester tower [state | path | close] and !tester descent [state | path | close | sigil] (O595): the Infinity Tower and the Ember Descent as a
-- person sees them (the level rule, how a run is paid, the halls free, inside the floor or room, the monsters, the clock, who is in the run
-- and the guide), the path on foot to the guide's goal, the close of the bot's own run; `sigil` gives an Ember Sigil when the day's free
-- descent is used. The window's requests (enter, start, pick, ready, skip) are the bot's own
local function parseSolo(arg, system, words)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == "" then
		what = "state"
	end
	what = what and what:lower()
	if not (what and words[what]) then
		return nil, "usage: " .. system .. " [state | path | close" .. (words.sigil and " | sigil" or "") .. "]"
	end
	return what
end

function H.parseTower(arg)
	return parseSolo(arg, "tower", {state = true, path = true, close = true})
end

function H.parseDescent(arg)
	return parseSolo(arg, "descent", {state = true, path = true, close = true, sigil = true})
end

function H.parseTrial(arg)
	return parseSolo(arg, "trial", {state = true, path = true, close = true})
end

local function soloGuide(g)
	if type(g) ~= "table" then
		return nil
	end
	local reach = type(g.reach) == "table" and {tonumber(g.reach[1]) or 0, tonumber(g.reach[2]) or 0} or nil
	return {mode = g.mode, goal = xyz(g.goal), reach = reach, why = g.why and tostring(g.why):sub(1, 60) or nil, area = g.area, skip = g.skip,
		offer = g.offer, card = g.card}
end

function H.towerAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, minLevel = probe.minLevel, pos = xyz(probe.pos), canEnter = probe.canEnter,
		free = probe.free, reserve = probe.reserve, bank = probe.bank, floorGold = probe.floorGold, inArena = probe.inArena and true or false}
	local r = probe.run
	if type(r) == "table" then
		out.run = {slot = r.slot, floor = r.floor, cleared = r.cleared, remaining = r.remaining, total = r.total, monsters = r.monsters,
			boss = r.boss and true or false, waiting = r.waiting and true or false, nextIn = r.nextIn, left = r.left, floorLeft = r.floorLeft,
			players = r.players, testers = r.testers, canSkip = r.canSkip and true or false, nextBoss = r.nextBoss and true or false}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

function H.trialAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, minLevel = probe.minLevel, pos = xyz(probe.pos), pz = probe.pz and true or false,
		fight = probe.fight and true or false, free = probe.free, reserve = probe.reserve, bank = probe.bank, family = probe.family,
		familyName = probe.familyName and tostring(probe.familyName):sub(1, 40) or nil, cleared = probe.cleared, tier = probe.tier, maxTier = probe.maxTier,
		problem = probe.problem and tostring(probe.problem):sub(1, 90) or nil, puzzle = probe.puzzle and true or nil}
	if type(probe.kinds) == "table" then
		out.kinds = {}
		for i = 1, math.min(#probe.kinds, 12) do
			out.kinds[#out.kinds + 1] = tostring(probe.kinds[i]):sub(1, 12)
		end
	end
	local r = probe.run
	if type(r) == "table" then
		out.run = {tier = r.tier, phase = r.phase, stage = r.stage, stageIdx = r.stageIdx, stages = r.stages, killed = r.killed, total = r.total,
			lives = r.lives, livesMax = r.livesMax, left = r.left, monsters = r.monsters, boss = r.boss, bossHp = r.bossHp, bossPos = xyz(r.bossPos),
			spell = r.spell and true or false}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

function H.descentAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, minLevel = probe.minLevel, pos = xyz(probe.pos), pz = probe.pz and true or false,
		pay = probe.pay, payWhy = probe.payWhy and tostring(probe.payWhy):sub(1, 90) or nil, sigils = probe.sigils, free = probe.free,
		reserve = probe.reserve, bank = probe.bank, fight = probe.fight and true or false}
	local r = probe.run
	if type(r) == "table" then
		local offer = type(r.offer) == "table" and {id = r.offer.id, cards = r.offer.cards, curse = r.offer.curse and true or false, left = r.offer.left} or nil
		local boss = type(r.boss) == "table" and {pos = xyz(r.boss.pos), hp = r.boss.hp} or nil
		out.run = {id = r.id, slot = r.slot, room = r.room, rooms = r.rooms, kind = r.kind, state = r.state, depth = r.depth, wave = r.wave, waves = r.waves,
			monsters = r.monsters, alive = r.alive, left = r.left, weekly = r.weekly and true or false, players = r.players, testers = r.testers,
			embers = r.embers, offer = offer, ready = r.ready and true or false, boss = boss}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester ascended [state | sigil [kind] | path | close] and !tester omen [state | key [kind] | path | close] (O599): the Ascended Omen
-- arenas and the Omen Key arenas as a person sees them. `sigil` / `key` is the TEST ONLY grant (a tester only, logged); `path` the way on
-- foot to the guide's goal inside; `close` the bot's own run. The sigil / key is used by the bot itself, like a hotkey.
local function parseGrant(arg, system, word)
	local usage = "usage: " .. system .. " [state | " .. word .. " [kind] | path | close]"
	local what, rest = tostring(arg or ""):match("^%s*(%a*)%s*(%a*)%s*$")
	if not what then
		return nil, usage
	end
	what = what == "" and "state" or what:lower()
	if what == word then
		return {what = word, kind = rest ~= "" and rest:lower() or nil}
	end
	if rest ~= "" or (what ~= "state" and what ~= "path" and what ~= "close") then
		return nil, usage
	end
	return {what = what}
end

function H.parseAscended(arg)
	return parseGrant(arg, "ascended", "sigil")
end

function H.parseOmen(arg)
	return parseGrant(arg, "omen", "key")
end

function H.ascendedAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, pos = xyz(probe.pos), pz = probe.pz and true or false,
		fight = probe.fight and true or false, free = probe.free, reserve = probe.reserve, enabled = probe.enabled ~= false,
		held = probe.held and true or false, sigilKind = probe.sigilKind, sigilClientId = probe.sigilClientId}
	if type(probe.kinds) == "table" then
		out.kinds = {}
		for i = 1, math.min(#probe.kinds, 6) do
			local k = probe.kinds[i]
			out.kinds[#out.kinds + 1] = {key = tostring(k.key):sub(1, 20), minLevel = k.minLevel}
		end
	end
	local r = probe.run
	if type(r) == "table" then
		out.run = {id = r.id, kind = r.kind, boss = r.boss, state = r.state, tester = r.tester and true or false, lives = r.lives,
			livesMax = r.livesMax, players = r.players, testers = r.testers, left = r.left, down = r.down and true or false, gateIn = r.gateIn,
			enraged = r.enraged and true or false, phase = r.phase, bossPos = xyz(r.bossPos), bossHp = r.bossHp, gate = xyz(r.gate), adds = r.adds}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- the omen answer is the rift's (the arena is a rift slot) with the omen kind of the run
function H.omenAnswer(probe, extra)
	local out = H.riftAnswer(probe, extra)
	if type(probe) == "table" and type(probe.run) == "table" then
		out.run = out.run or {}
		out.run.omen = probe.run.omen
	end
	return out
end

-- !tester bounty [state | where NAME | path] (O599): the bounty board as a person sees it and "where does monster X spawn". `state` lists the
-- contracts the bot holds and the ones a hunt mark lists (the smallest first); `where NAME` the hunt marks that list a monster and the nearest;
-- `path` the way on foot to the guide's goal (the monster in sight, else the hunt). The window's requests (accept, abandon) are the bot's own.
function H.parseBounty(arg)
	local usage = "usage: bounty [state | where NAME | path]"
	local what, rest = tostring(arg or ""):match("^%s*(%a*)%s*(.-)%s*$")
	if not what then
		return nil, usage
	end
	what = what == "" and "state" or what:lower()
	if what == "where" then
		if rest == "" or #rest > 40 or not rest:match("^[%a' %-]+$") then
			return nil, usage
		end
		return {what = "where", name = rest}
	end
	if rest ~= "" or (what ~= "state" and what ~= "path") then
		return nil, usage
	end
	return {what = what}
end

function H.bountyAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {level = probe.level, pos = xyz(probe.pos), day = probe.day, maxActive = probe.maxActive, target = probe.target, active = {}, candidates = {}}
	for i = 1, math.min(#(probe.active or {}), 8) do
		local a = probe.active[i]
		out.active[#out.active + 1] = {key = tostring(a.key):sub(1, 12), name = tostring(a.name):sub(1, 40), progress = a.progress, required = a.required, status = a.status}
	end
	for i = 1, math.min(#(probe.candidates or {}), 6) do
		local c = probe.candidates[i]
		out.candidates[#out.candidates + 1] = {key = tostring(c.key):sub(1, 12), name = tostring(c.name):sub(1, 40), count = c.count, level = c.level,
			distance = c.distance, mark = c.mark and {x = c.mark.x, y = c.mark.y, z = c.mark.z, n = tostring(c.mark.n):sub(1, 70)} or nil}
	end
	local w = probe.where
	if type(w) == "table" then
		out.where = {name = tostring(w.name):sub(1, 40), marks = w.marks, distance = w.distance,
			nearest = w.nearest and {x = w.nearest.x, y = w.nearest.y, z = w.nearest.z, n = tostring(w.nearest.n):sub(1, 70)} or nil}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester mainquest [state] (O599): the main quest as a person sees it on the Next Goals tracker: the state, the open step, its first condition,
-- the progress and where to go (an NPC name or a position: the bot walks there with `path npc NAME` / `path pos X Y Z`), and what a bot can play
-- of it (`plan`: talk | visit | kill | skip with the reason)
function H.parseMainQuest(arg)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == "" then
		what = "state"
	end
	what = what and what:lower()
	if what ~= "state" then
		return nil, "usage: mainquest [state]"
	end
	return what
end

function H.mainQuestAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {enabled = probe.enabled ~= false, level = probe.level, pos = xyz(probe.pos), staff = probe.staff and true or false, state = probe.state,
		active = probe.active and true or false, done = probe.done and true or false, step = probe.step, steps = probe.steps,
		key = probe.key and tostring(probe.key):sub(1, 30) or nil, stepLevel = probe.stepLevel, running = probe.running, progress = probe.progress,
		target = probe.target, ready = probe.ready, conds = probe.conds}
	local c = probe.cond
	if type(c) == "table" then
		local mons = {}
		for i = 1, math.min(#(c.mons or {}), 4) do
			mons[i] = tostring(c.mons[i]):sub(1, 30)
		end
		out.cond = {kind = c.kind, mons = mons, target = c.target, label = c.label and tostring(c.label):sub(1, 40) or nil, radius = c.radius,
			pos = xyz(c.pos), bring = c.bring and tostring(c.bring):sub(1, 20) or nil, flag = c.flag and tostring(c.flag):sub(1, 20) or nil,
			stat = c.stat and tostring(c.stat):sub(1, 24) or nil}
	end
	local w = probe.where
	if type(w) == "table" then
		out.where = {k = w.k, name = w.name and tostring(w.name):sub(1, 40) or nil, label = w.label and tostring(w.label):sub(1, 40) or nil, pos = xyz(w.pos)}
	end
	local pl = probe.plan
	if type(pl) == "table" then
		out.plan = {action = pl.action, reason = pl.reason and tostring(pl.reason):sub(1, 90) or nil, label = pl.label and tostring(pl.label):sub(1, 40) or nil,
			target = pl.target, radius = pl.radius, flag = pl.flag and tostring(pl.flag):sub(1, 20) or nil, stat = pl.stat and tostring(pl.stat):sub(1, 24) or nil,
			cond = pl.cond}
		if type(pl.monsters) == "table" then
			out.plan.monsters = {}
			for i = 1, math.min(#pl.monsters, 4) do
				out.plan.monsters[i] = tostring(pl.monsters[i]):sub(1, 30)
			end
		end
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- O650: the Nemesis, the daily reward, the Chronicle, Vael Ashmourn, the treasure goblin and the invasions as a person sees them.
--   !tester nemesis [state | born | appear | path | close]     born / appear are the TEST ONLY grants (a tester only, logged)
--   !tester daily [state]            the account's daily (taken, slot, the value the window's `calim` sends, the reward and how many the bot holds)
--   !tester chronicle [state]        the season, the open chapter and its goals, `counted` and `testersListed` (the rule: a tester is in no book)
--   !tester vael [state | enter | path | close]   enter is the TEST ONLY door of the boss's spell trial (a tester from level 500, logged)
--   !tester goblin [state | spawn | path | close]  spawn is a treasure goblin of the bot's own (TEST ONLY, only while no player is near)
--   !tester invasion [state | path]  the running invasion, the invader nearest, `credited` (false for a tester) and the hits cancelled
-- The answers are the probes' tables cut down: scalars only (a text at most 90 characters), tables up to three levels, at most 12 rows a list.
local function parseWords(arg, system, words)
	local usage = "usage: " .. system .. " [state" .. (#words > 1 and (" | " .. table.concat(words, " | ", 2)) or "") .. "]"
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == nil then
		return nil, usage
	end
	what = what == "" and "state" or what:lower()
	for _, w in ipairs(words) do
		if w == what then
			return what
		end
	end
	return nil, usage
end

function H.parseNemesis(arg)
	return parseWords(arg, "nemesis", {"state", "born", "appear", "path", "close"})
end

function H.parseDaily(arg)
	return parseWords(arg, "daily", {"state"})
end

function H.parseChronicle(arg)
	return parseWords(arg, "chronicle", {"state"})
end

function H.parseVael(arg)
	return parseWords(arg, "vael", {"state", "enter", "path", "close"})
end

function H.parseGoblin(arg)
	return parseWords(arg, "goblin", {"state", "spawn", "path", "close"})
end

function H.parsePocket(arg)
	return parseWords(arg, "pocket", {"state", "path", "close"})
end

-- the pocket answer: the bosses the bot may open now (a charge left, the level), the ones with a boss passive point it does not hold first, then
-- by level, at most 8; inside the run and the guide as for the other boss arenas
H.POCKET_ROWS = 8
function H.pocketAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, pos = xyz(probe.pos), pz = probe.pz and true or false,
		fight = probe.fight and true or false, enabled = probe.enabled ~= false, free = probe.free, reserve = probe.reserve}
	if type(probe.points) == "table" then
		out.points = {got = probe.points.got, total = probe.points.total}
	end
	local usable = {}
	for _, b in ipairs(type(probe.bosses) == "table" and probe.bosses or {}) do
		if type(b) == "table" and b.ok and (tonumber(b.left) or 0) > 0 then
			usable[#usable + 1] = b
		end
	end
	-- O661: the boss's own level (`bl`, pocketboss.lua probe) against the bot's: a level 600 bot was sent into a level 2400 boss (the pockets of the
	-- raid category all open at 150) and was carried out by a lethal hit 10 s later. A boss at or under the bot's level first, the highest of them
	-- first (the fairest fight), then a point it lacks; a row with no `bl` (an old probe) sorts as before
	local lvl = tonumber(probe.level)
	local function over(e)
		return (lvl and tonumber(e.bl) and tonumber(e.bl) > lvl) and 1 or 0
	end
	table.sort(usable, function(a, b)
		if over(a) ~= over(b) then
			return over(a) < over(b)
		end
		local am = a.point and not a.point.got and 0 or 1
		local bm = b.point and not b.point.got and 0 or 1
		if am ~= bm then
			return am < bm
		end
		if tonumber(a.bl) and tonumber(b.bl) and a.bl ~= b.bl then
			return a.bl > b.bl
		end
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) < (b.level or 0)
		end
		return tostring(a.key) < tostring(b.key)
	end)
	out.bosses = {}
	for i = 1, math.min(#usable, H.POCKET_ROWS) do
		local b = usable[i]
		out.bosses[#out.bosses + 1] = {key = tostring(b.key):sub(1, 40), name = tostring(b.name):sub(1, 40), category = b.category, level = b.level, bl = tonumber(b.bl),
			left = b.left, point = b.point and {id = b.point.id, got = b.point.got and true or false} or nil}
	end
	out.usable = #usable
	local r = probe.run
	if type(r) == "table" then
		out.run = {id = r.id, key = r.key and tostring(r.key):sub(1, 40) or nil, name = r.name and tostring(r.name):sub(1, 40) or nil,
			category = r.category, state = r.state, boss = r.boss, left = r.left, players = r.players, testers = r.testers, slot = r.slot,
			bossPos = xyz(r.bossPos), bossHp = r.bossHp, inArena = r.inArena and true or false, tester = r.tester and true or false}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester wsmap [state | enter [tier] | path | close] (O651): a waystone map walked by a bot. `enter` is the TEST ONLY stand-in of the device's pads and
-- teleport (base code): a plain run of the tier on a free map and the bot on its arrival tile
function H.parseWsMap(arg)
	local usage = "usage: wsmap [state | enter [tier] | path | close]"
	local what, rest = tostring(arg or ""):match("^%s*(%a*)%s*(%d*)%s*$")
	if not what then
		return nil, usage
	end
	what = what == "" and "state" or what:lower()
	if what == "enter" then
		local tier = tonumber(rest)
		if tier and (tier < 1 or tier > 15) then
			return nil, usage
		end
		return {what = "enter", tier = tier}
	end
	if rest ~= "" or (what ~= "state" and what ~= "path" and what ~= "close") then
		return nil, usage
	end
	return {what = what}
end

function H.wsmapAnswer(probe, extra)
	probe = type(probe) == "table" and probe or {}
	local out = {inside = probe.inside and true or false, level = probe.level, pos = xyz(probe.pos), minLevel = probe.minLevel, kills = probe.kills,
		arrivals = probe.arrivals, free = probe.free, freeTier = probe.freeTier, freeTierLevel = probe.freeTierLevel, why = probe.why and tostring(probe.why):sub(1, 70) or nil, inMap = probe.inMap,
		enabled = probe.enabled ~= false}
	local r = probe.run
	if type(r) == "table" then
		out.run = {map = r.map, tier = r.tier, tierLevel = r.tierLevel, since = r.since, left = r.left, players = r.players, monsters = r.monsters,
			monsterLevel = r.monsterLevel, nearest = xyz(r.nearest), nearestHp = r.nearestHp, active = r.active,
			boss = type(r.boss) == "table" and {pos = xyz(r.boss.pos), hp = r.boss.hp} or nil}
	end
	out.guide = soloGuide(probe.guide)
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

function H.parseInvasion(arg)
	return parseWords(arg, "invasion", {"state", "path"})
end

-- O652: PvP among the testers and the tester copies of the key bosses.
--   !tester pvp [state | path]       the PvP place the bot stands in, the foe (only a tester, only in a place the rules allow), the hits a rule
--                                    cancelled, the arena / battleground / Marches views and the testers in the season rows (0); path: on foot to the foe
--   !tester boss [state | spawn | path | close]   spawn is a copy of a key boss for the bot (TEST ONLY, only while no player is near and no lair is
--                                    near); state gives its telegraph marks, the safe tile (guide `dodge`), the kills, the boss points, `listed`
function H.parsePvp(arg)
	return parseWords(arg, "pvp", {"state", "path"})
end

function H.parseBoss(arg)
	return parseWords(arg, "boss", {"state", "spawn", "path", "close"})
end

-- O652: the foe a tester aims at inside a PvP place. `list`: {{pos = {x, y, z}, tester = bool, foe = bool, health = n, id = n}} of the players in
-- sight, `foe` the answer of ChaosTesters.pvpFoe (both testers, the switch on, one place, the place's own rule). Only a foe is ever picked, never a
-- player: a list with no foe gives nil. The nearest on the same floor within `range`, the lowest health first among equals.
function H.pvpTarget(origin, list, range)
	local best
	for _, c in ipairs(list or {}) do
		if c.tester == true and c.foe == true and c.pos and c.pos.z == origin.z and (c.health or 1) > 0 then
			local d = math.max(math.abs(c.pos.x - origin.x), math.abs(c.pos.y - origin.y))
			if d <= range and (not best or d < best.d or (d == best.d and (c.health or 0) < (best.c.health or 0))) then
				best = {c = c, d = d}
			end
		end
	end
	return best and best.c or nil
end

-- O655: the class ascension and the gathering as a person sees them.
--   !tester ascend [state | proof | path | close]   the Ascendant Oracle's quest (stage, proof, trial, the choices and the class lock); `proof` is the TEST ONLY
--                                                   credit of the Proof of Strength (a tester only, logged), `path` the way to the guardian inside the trial,
--                                                   `close` the end of the bot's own trial
--   !tester gather [state | path]                   the gathering tools the bot carries, the nearest node that is ready for it, the way on foot next to it
function H.parseAscend(arg)
	return parseWords(arg, "ascend", {"state", "proof", "path", "close"})
end

function H.parseGather(arg)
	return parseWords(arg, "gather", {"state", "path", "corpse", "water"})
end

-- O657: the exercise dummy, the mount and the kill task as a person sees them.
--   !tester dummy [state | path | give | clear]   the exercise weapon the bot carries, the nearest training dummy, the skill the weapon trains and its tries;
--                                                 `give` is the TEST ONLY exercise weapon of the class (a tester only, logged), `clear` takes it again,
--                                                 `path` the way on foot next to the dummy
--   !tester mount [state | give | clear]          whether the bot is mounted, its speed, the mounts it owns; `give` is a TEST ONLY mount (a tester only, logged)
--                                                 with the first free one as the current mount, `clear` dismounts and takes it back
--   !tester task [state | where NAME | path]      the kill tasks of the Bestiary held (progress), the monster to hunt, the nearest living one, the hunt mark,
--                                                 the way on foot to the guide's goal (the parser is the bounty board's)
H.COMMANDS.dummy = true
H.COMMANDS.mount = true
H.COMMANDS.task = true

function H.parseDummy(arg)
	return parseWords(arg, "dummy", {"state", "path", "give", "clear"})
end

function H.parseMount(arg)
	return parseWords(arg, "mount", {"state", "give", "clear"})
end

function H.parseTask(arg)
	local what, usage = H.parseBounty(arg)
	if not what then
		return nil, (usage:gsub("^usage: bounty", "usage: task"))
	end
	return what
end

-- the cheapest mount of the store a free account may wear (shop_cosmetics.lua, generated from mounts.xml): {id, name} or nil
function H.pickMount(mounts)
	local best
	local list = type(mounts) == "table" and mounts or {}
	for _, m in ipairs(list) do
		if type(m) == "table" and tonumber(m.id) and not m.premium then
			local cost, bestCost = tonumber(m.cost) or 0, best and (tonumber(best.cost) or 0) or 0
			if not best or cost < bestCost or (cost == bestCost and m.id < best.id) then
				best = m
			end
		end
	end
	if not best then
		for _, m in ipairs(list) do
			if type(m) == "table" and tonumber(m.id) and (not best or m.id < best.id) then
				best = m
			end
		end
	end
	return best and {id = best.id, name = tostring(best.name or ""):sub(1, 30)} or nil
end

-- a value cut down for a text line: scalars only, strings at most 90 characters, tables up to `depth` levels and 12 rows a list
local function cutValue(v, depth)
	local t = type(v)
	if t == "string" then
		return v:sub(1, 90)
	elseif t == "number" or t == "boolean" then
		return v
	elseif t == "table" and depth > 0 then
		local out = {}
		if #v > 0 then
			for i = 1, math.min(#v, 12) do
				local c = cutValue(v[i], depth - 1)
				if c ~= nil then
					out[#out + 1] = c
				end
			end
		else
			for k, c in pairs(v) do
				if type(k) == "string" and #k <= 24 then
					local cc = cutValue(c, depth - 1)
					if cc ~= nil then
						out[k] = cc
					end
				end
			end
		end
		return out
	end
	return nil
end
H.cutValue = cutValue

function H.cutAnswer(probe, extra)
	local out = {}
	if type(probe) == "table" then
		for k, v in pairs(probe) do
			if type(k) == "string" and k ~= "guide" then
				local c = cutValue(v, 3)
				if c ~= nil then
					out[k] = c
				end
			end
		end
		out.pos = xyz(probe.pos) or out.pos
		out.guide = soloGuide(probe.guide)
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- !tester path <place kind> [N] | npc <name> | pos X Y Z: the way on foot to a map mark, an NPC or a position, by the engine's own
-- pathfinding (O589). A kind is one of H.PLACE_KINDS that can be walked to (a rift key is no place).
function H.parsePath(arg)
	local usage = "usage: path <kind> [N] | npc <name> | pos X Y Z"
	local x, y, z = tostring(arg or ""):match("^%s*[Pp][Oo][Ss]%s+(%d+)%s+(%d+)%s+(%d+)%s*$")
	if x then
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if x < 1 or y < 1 or x > 65535 or y > 65535 or z > 15 then
			return nil, usage
		end
		return {kind = "pos", x = x, y = y, z = z}
	end
	local place = H.parsePlace(arg)
	if not place or place.kind == "rift" then
		return nil, usage
	end
	return place
end

local function cheb(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function H.pathAnswer(from, dest, dirs, extra)
	local out = {pos = xyz(from), dest = xyz(dest), path = dirs or {}}
	if type(from) == "table" and type(dest) == "table" then
		out.dist = from.z == dest.z and cheb(from, dest) or nil
		out.floor = from.z ~= dest.z and (dest.z - from.z) or nil
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- the highest rift tier (1..maxTier) a character of `level` may open; tierMin(t) is the minLevel of tier t; nil: none
function H.riftTierFor(level, maxTier, tierMin)
	local best
	for t = 1, maxTier do
		if (tierMin(t) or math.huge) <= level then
			best = t
		end
	end
	return best
end

-- the places `!tester enter` brings a tester to: map mark kinds (poi_core.lua P.KINDS, guild halls left out: guilds
-- are out of scope), an NPC by name, and a rift (a key of the tier into the backpack, then the temple)
H.PLACE_KINDS = {temple = true, depot = true, craft = true, bank = true, bless = true, travel = true, shop = true,
	boss = true, hunt = true, npc = true, portal = true, dungeon = true}
H.RIFT_MAX = 15

-- items = {{id, count}, ...} (the backpack's own slots); want = {[itemId] = number} (the supplies a tester keeps);
-- held = {[itemId] = number} (carried in all, nested bags too). Returns the indexes of `items` to remove and the
-- {id, count} to add, by id. A tester loots and never sells, so the bag fills; the potions are used up.
function H.bagPlan(items, want, held)
	local remove, add = {}, {}
	for i, it in ipairs(items or {}) do
		if not want[it.id] then
			remove[#remove + 1] = i
		end
	end
	for id, n in pairs(want or {}) do
		local have = (held or {})[id] or 0
		if have < n / 2 then
			add[#add + 1] = {id = id, count = n - have}
		end
	end
	table.sort(add, function(a, b) return a.id < b.id end)
	return remove, add
end

function H.parsePlace(arg)
	if type(arg) ~= "string" then
		return nil
	end
	local kind, rest = arg:match("^%s*(%a+)%s*(.-)%s*$")
	kind = kind and kind:lower()
	if kind == "rift" then
		local t = tonumber(rest) or 1
		t = math.floor(t)
		if t < 1 then t = 1 end
		if t > H.RIFT_MAX then t = H.RIFT_MAX end
		return {kind = "rift", tier = t}
	end
	if kind == "npc" then
		-- an NPC name: letters, spaces, apostrophes; never a player (the engine file checks isNpc)
		if rest == "" or #rest > 40 or not rest:match("^[%a][%a '%-]*$") then
			return nil
		end
		return {kind = "npc", name = rest}
	end
	if not kind or not H.PLACE_KINDS[kind] then
		return nil
	end
	local n = tonumber(rest)
	if rest ~= "" and (not n or n < 1 or n ~= math.floor(n)) then
		return nil
	end
	return {kind = kind, n = n}
end

-- the line spell quests (spellquest.lua): what the checks of tester_checks.py ask of the helper. Numbers are whole and bounded:
-- quest 1..9, step 0..3, counters up to 100000, a run of kills up to KILL_MAX
H.KILL_MAX = 60
function H.parseSpellQuest(arg)
	local words = {}
	for w in tostring(arg or ""):gmatch("%S+") do
		words[#words + 1] = w:lower()
	end
	local sub = words[1] or "state"
	local function int(i, lo, hi)
		local v = tonumber(words[i])
		if not v or v ~= math.floor(v) or v < lo or v > hi then
			return nil
		end
		return v
	end
	if sub == "state" or sub == "reset" or sub == "trial" or sub == "leave" or sub == "complete" then
		if #words > 1 then
			return nil, sub .. " takes no argument"
		end
		return {sub = sub}
	elseif sub == "set" then
		local quest, step = int(2, 1, 9), int(3, 0, 3)
		if not quest or not step then
			return nil, "set <quest> <step 0-3> [kills [fragments]]"
		end
		local out = {sub = sub, quest = quest, step = step}
		if words[4] then
			out.kills = int(4, 0, 100000)
			if not out.kills then
				return nil, "kills must be a whole number"
			end
		end
		if words[5] then
			out.fragments = int(5, 0, 100000)
			if not out.fragments then
				return nil, "fragments must be a whole number"
			end
		end
		return out
	elseif sub == "kill" then
		local boss = words[#words] == "boss"
		local nw = #words - (boss and 1 or 0)
		local n = 1
		if nw >= 2 then
			n = int(2, 1, H.KILL_MAX)
			if not n then
				return nil, "kill [1-" .. H.KILL_MAX .. "] [boss]"
			end
		end
		return {sub = sub, n = n, boss = boss}
	end
	return nil, "unknown spellquest command"
end

function H.pickMark(marks, kind, n)
	local list = {}
	for _, m in ipairs(marks or {}) do
		if m.k == kind and m.x and m.y and m.z then
			list[#list + 1] = m
		end
	end
	if #list == 0 then
		return nil, 0
	end
	return list[((n or 1) - 1) % #list + 1], #list
end

function H.placeCounts(marks)
	local out = {}
	for _, m in ipairs(marks or {}) do
		if H.PLACE_KINDS[m.k] and m.k ~= "npc" then
			out[m.k] = (out[m.k] or 0) + 1
		end
	end
	return out
end

-- a small JSON writer (the engine's json may be missing in the tests; no functions, no cycles)
local function enc(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return (math.floor(v) == v and math.abs(v) < 1e15) and string.format("%d", v) or string.format("%.4f", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
			return map[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local out = {}
			for i = 1, #v do
				out[i] = enc(v[i])
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys, vals = {}, {}
		for k, val in pairs(v) do
			keys[#keys + 1] = tostring(k)
			vals[tostring(k)] = val
		end
		table.sort(keys)
		local out = {}
		for _, k in ipairs(keys) do
			out[#out + 1] = enc(k) .. ":" .. enc(vals[k])
		end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return "null"
end
H.json = enc

function H.encode(kind, data)
	return H.MARK .. " " .. kind .. " " .. enc(data or {})
end

-- hit: {kind = "taken" | "dealt", damage, health (before), maxHealth, level}
-- returns the rule name or nil
function H.hitAnomaly(hit)
	local L = H.limits
	local dmg = tonumber(hit.damage) or 0
	if dmg < 0 or dmg ~= dmg then
		return "negative damage"
	end
	if hit.kind == "taken" then
		local maxH = math.max(1, tonumber(hit.maxHealth) or 1)
		if dmg > L.takenOverMaxHealth * maxH then
			return "hit taken over " .. L.takenOverMaxHealth .. "x max health"
		end
		if (tonumber(hit.health) or 0) >= maxH and dmg >= maxH and maxH > 1 then
			return "one hit from full health"
		end
	elseif hit.kind == "dealt" then
		local level = math.max(1, tonumber(hit.level) or 1)
		if dmg > L.dealtBase + L.dealtPerLevel * level then
			return "hit dealt far above the level"
		end
	end
	return nil
end

-- the last hits a tester took, for its death record (the first live run, 2026-10-27: 2998 deaths and nobody could say whether one
-- hit or a pack did it). list: {{t, damage, by}}, newest last; the helper keeps one per tester.
H.HIT_WINDOW = 5 -- seconds a death record looks back

-- the size of one onHealthChange call. The engine passes damage as NEGATIVE numbers (healing positive; every other
-- onHealthChange script of the repo takes math.abs), so max(0, value) read every hit as 0: the first death records of
-- 2026-10-28 had hits > 0 but damage 0 and biggest 0. A healing part counts 0.
function H.damageOf(primary, primaryType, secondary, secondaryType)
	local function part(v, t)
		v = tonumber(v) or 0
		if t == COMBAT_HEALING or v ~= v then
			return 0
		end
		return math.abs(v)
	end
	return part(primary, primaryType) + part(secondary, secondaryType)
end
H.HIT_KEEP = 40

function H.pushHit(list, now, hit)
	list[#list + 1] = {t = now, damage = math.max(0, tonumber(hit.damage) or 0), by = hit.by}
	while #list > H.HIT_KEEP or (list[1] and now - list[1].t > 2 * H.HIT_WINDOW) do
		table.remove(list, 1)
	end
end

-- d: {who, level, killer, maxHealth, secsOnline (seconds since the login)}; the record the console line carries: how many hits
-- in the last HIT_WINDOW seconds, their sum, the biggest one and the monster that dealt it, both as a percent of the maximum
function H.deathRecord(list, now, d)
	local hits, sum, big, bigBy = 0, 0, 0, nil
	for _, h in ipairs(list or {}) do
		if now - h.t <= H.HIT_WINDOW then
			hits = hits + 1
			sum = sum + h.damage
			if h.damage > big then
				big, bigBy = h.damage, h.by
			end
		end
	end
	local maxH = math.max(1, tonumber(d.maxHealth) or 1)
	return {kind = "death", who = d.who, level = d.level, killer = d.killer or "?", t = now, maxHealth = maxH,
		hits = hits, damage = sum, damagePct = math.floor(100 * sum / maxH), biggest = big,
		biggestPct = math.floor(100 * big / maxH), biggestBy = bigBy or "?", secsOnline = d.secsOnline}
end

-- the first monster of a hunt spot above the tester: levels = {{name, level}} (hunting levels of the monsters round the spot).
-- A tester set up before the safe-spawn fix keeps its old hunt spot, so "!tester hunt" checks the spot itself.
-- a margin over the level: a tester loses levels by dying, and its own spawn (setup: at or under the level) must stay its spot
H.HOT_MARGIN = {share = 0.1, min = 25}

function H.hotSpot(level, monsters)
	local worst
	level = tonumber(level) or 0
	local limit = level + math.max(H.HOT_MARGIN.min, math.floor(level * H.HOT_MARGIN.share))
	for _, m in ipairs(monsters or {}) do
		if (tonumber(m[2]) or 0) > limit and (not worst or m[2] > worst[2]) then
			worst = m
		end
	end
	return worst
end

-- the level band of a hunt mark ("Hunting: Penguin, Mammoth (level 1-20)" -> 1, 20), or nil
function H.huntBand(name)
	local lo, hi = tostring(name or ""):match("%(level (%d+)%-(%d+)%)")
	if lo then
		return tonumber(lo), tonumber(hi)
	end
	return nil
end

-- the hunt marks a tester of this level may be moved to when its own spot is too high (O580), best first: the ones whose
-- whole band is at or under the level (the rule of tester_core.safe_hunts: the highest tops, at least 0.8 x the highest
-- top, first, then the lower ones), else the lowest bands. `seed` turns the order of the equal ones, so a hundred bots
-- do not all stand on the first mark. marks = ChaosPoi.all rows {k, x, y, z, n}.
function H.huntCandidates(marks, level, seed)
	level = tonumber(level) or 0
	local fit, all = {}, {}
	for _, m in ipairs(marks or {}) do
		if m.k == "hunt" and m.x and m.y and m.z then
			local lo, hi = H.huntBand(m.n)
			if lo then
				all[#all + 1] = {mark = m, lo = lo, hi = hi}
				if hi <= level then
					fit[#fit + 1] = all[#all]
				end
			end
		end
	end
	local list = #fit > 0 and fit or all
	if #list == 0 then
		return {}
	end
	table.sort(list, function(a, b)
		if #fit > 0 then
			if a.hi ~= b.hi then
				return a.hi > b.hi
			end
		elseif a.hi ~= b.hi then
			return a.hi < b.hi
		end
		if a.mark.x ~= b.mark.x then
			return a.mark.x < b.mark.x
		end
		return a.mark.y < b.mark.y
	end)
	-- the best group (>= 0.8 x the highest top, or the lowest top) turned by the seed, then the rest in order
	local first = list[1].hi
	local group, rest = {}, {}
	for _, e in ipairs(list) do
		if (#fit > 0 and e.hi >= first * 0.8) or (#fit == 0 and e.hi == first) then
			group[#group + 1] = e.mark
		else
			rest[#rest + 1] = e.mark
		end
	end
	local out, n = {}, #group
	local turn = n > 0 and ((tonumber(seed) or 0) % n) or 0
	for i = 1, n do
		out[#out + 1] = group[(i - 1 + turn) % n + 1]
	end
	for _, m in ipairs(rest) do
		out[#out + 1] = m
	end
	return out
end

-- the two fist weapons a `!tester fists` probe wears (O580). A fist weapon has a level (items.xml: 8, 60, 150, 300 ...) and
-- the engine refuses it below that with RETURNVALUE_NOTENOUGHLEVEL (code 33): the live run of 2026-11-15 read "weapon hand
-- code 33, shield hand code 33" for the level 30 to 100 Monks and "0 / 33" for the ones between 150 and 299, because the
-- probe always took the level 150 and level 300 pair. items = ChaosFistWeapons.items ({[id] = {level, unique}}), fallback =
-- {id, id} when the table is missing. Returns {weapon hand id, shield hand id}: the highest plain (not unique) fist weapons
-- the level may wield, the same one twice when only one fits, the fallback when none does.
function H.fistPair(level, items, fallback)
	level = tonumber(level) or 0
	local fit = {}
	for id, it in pairs(items or {}) do
		if type(it) == "table" and not it.unique and (tonumber(it.level) or 0) <= level then
			fit[#fit + 1] = {id = id, level = tonumber(it.level) or 0}
		end
	end
	table.sort(fit, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.id < b.id
	end)
	if #fit == 0 then
		return {fallback and fallback[1], fallback and fallback[2]}
	end
	return {fit[1].id, (fit[2] or fit[1]).id}
end

function H.xpAnomaly(level, gained)
	gained = tonumber(gained)
	if not gained or gained ~= gained then
		return "experience not a number"
	end
	if gained < 0 then
		return "negative experience gain"
	end
	if gained > H.limits.xpPerLevel * math.max(1, tonumber(level) or 1) then
		return "absurd experience gain"
	end
	return nil
end

-- item: {count, stackable, attrs = {name = number}}
function H.itemAnomaly(item)
	local count = tonumber(item.count) or 1
	if count < 1 or (item.stackable and count > H.limits.maxStack) then
		return "impossible count " .. count
	end
	for k, v in pairs(item.attrs or {}) do
		if type(v) == "number" and (v ~= v or v < -H.limits.maxAttr or v > H.limits.maxAttr) then
			return "impossible attribute " .. tostring(k) .. " = " .. enc(v)
		end
	end
	return nil
end

-- O86 (the Beastmaster wolf and its owner took each other for enemies; never reproduced): what a creature's target is,
-- seen from `owner`. Both are plain tables {id, isPlayer, isMonster, masterId, ownerId, partyLeaderId}; ownerId is the
-- player behind a summon. The test of the engine file builds them from creatures.
function H.targetKind(owner, target)
	if not target then
		return "none"
	end
	if target.id == owner.id then
		return "owner"
	end
	local side = target.isPlayer and target.id or target.ownerId
	if side then
		local ally = side == owner.id or (owner.partyLeaderId ~= nil and target.partyLeaderId == owner.partyLeaderId)
		if ally then
			return target.isPlayer and "ally" or "summon"
		end
		return target.isPlayer and "player" or "monster"
	end
	return "monster"
end

H.SUMMON_THROTTLE = 30 -- seconds between two lines of one rule for one tester
-- snap: {who, ownerTarget (a targetKind), summons = {{name, id, target (a targetKind)}}}; seen: {key = time}, kept by the
-- caller. Returns the list of {rule, who, summon, kind} that is new.
function H.summonAnomalies(snap, now, seen)
	local out = {}
	local function report(rule, summon, kind)
		local key = tostring(snap.who) .. "|" .. rule
		if seen and seen[key] and now - seen[key] < H.SUMMON_THROTTLE then
			return
		end
		if seen then
			seen[key] = now
		end
		out[#out + 1] = {rule = rule, who = snap.who, summon = summon and summon.name or nil, id = summon and summon.id or nil, kind = kind}
	end
	for _, sm in ipairs(snap.summons or {}) do
		if sm.target == "owner" then
			report("summon_targets_owner", sm, sm.target)
		elseif sm.target == "ally" or sm.target == "summon" then
			report("summon_targets_ally", sm, sm.target)
		end
	end
	if snap.ownerTarget == "summon" then
		report("owner_targets_summon", nil, snap.ownerTarget)
	end
	return out
end

-- once a minute the helper counts the testers in game; the server console gets a line when it changed (or every
-- ONLINE_EVERY minutes, so the log shows they are still there)
-- the live rules of the server (ChaosTestersCore) held to what closed test mode promises: a tester against a player is refused
-- (mode on), testers together are refused with the mode off and allowed with it on. `rules` = ChaosTestersCore
function H.closedGuards(rules)
	local out = {}
	if type(rules) ~= "table" or type(rules.sameSide) ~= "function" or type(rules.CLOSED_SYSTEMS) ~= "table" then
		return out
	end
	for system in pairs(rules.CLOSED_SYSTEMS) do
		out[system] = {
			mixed = not rules.sameSide(system, true, "tester", "player") and not rules.sameSide(system, true, "player", "tester"),
			off = not rules.sameSide(system, false, "tester", "tester"),
			together = rules.sameSide(system, true, "tester", "tester") and true or false}
	end
	return out
end

H.ONLINE_EVERY = 5
function H.onlineLine(count, last, minute)
	if count == last and (minute or 0) % H.ONLINE_EVERY ~= 0 then
		return nil
	end
	return string.format("%s testers online: %d", H.MARK, count)
end

-- ---------------------------------------------------------------- O584: keeping the drops like a player
-- The bag was wiped every 4 minutes, so no drop was ever sold, worn or compared. Now `!tester bag` only reports the backpack
-- (and tops the potions up); the bot sells at the Loot Buyer by the NPC trade window, wears a better piece by the move packet
-- and drops junk by the move packet. `!tester bag wipe` is the helper's last resort, counted as a failure in the report.
H.TRADERS = {"Material Broker", "Loot Buyer", "Wandering Merchant"}
H.EQUIP_MARGIN = 1 -- a piece must score this much more than the worn one
H.BAG_FULL = 0.7 -- the share of the backpack slots that sends a bot to sell
H.BAG_JAM = 0.9 -- the share left after selling that makes it drop junk
H.REPORT_MAX = 24 -- rows of the answer (a text message of the game is not a place for 60 items)

-- `shop <npc>`: a trader of the list only, any other name is no trader
function H.parseShop(arg)
	if type(arg) ~= "string" then
		return nil
	end
	local want = arg:lower():gsub("^%s+", ""):gsub("%s+$", "")
	for _, name in ipairs(H.TRADERS) do
		if name:lower() == want then
			return name
		end
	end
	return nil
end

-- `bag [wipe]`
function H.parseBag(arg)
	if arg == nil or arg == "" then
		return "report"
	end
	return tostring(arg):lower() == "wipe" and "wipe" or nil
end

-- row = {id, count, price, blocked, container, slot, score}; ctx = {want = {[id] = n}, currency = {[id] = true}}
-- kinds: supply (the potions), currency (coins), container (a bag), locked (the Loot Buyer refuses it: a unique, a locked
-- item), sell (the Loot Buyer buys it), junk (nothing buys it)
function H.itemKind(row, ctx)
	if (ctx.want or {})[row.id] then
		return "supply"
	end
	if (ctx.currency or {})[row.id] then
		return "currency"
	end
	if row.container then
		return "container"
	end
	if row.blocked then
		return "locked"
	end
	if (row.price or 0) > 0 then
		return "sell"
	end
	return "junk"
end

-- worn = {[slot] = score} (0 or nil: nothing worn); rows with `slot` and `score`. The row index of the piece that gains the
-- most over what is worn there, or nil. A piece the bot already tried and the server refused (`refused[id]`) is left out.
function H.betterPiece(worn, rows, refused)
	local best, gain = nil, H.EQUIP_MARGIN - 1
	for i, r in ipairs(rows or {}) do
		if r.slot and not (refused or {})[r.id] and r.kind ~= "supply" and r.kind ~= "currency" and r.kind ~= "container" then
			local g = (r.score or 0) - ((worn or {})[r.slot] or 0)
			if g > gain then
				best, gain = i, g
			end
		end
	end
	return best
end

-- the rows to drop when the bag has `size` slots and `used` are taken: only at BAG_JAM or more, junk first, the weakest and
-- the smallest stack first, until the used share is 0.1 under BAG_JAM. Never a supply, coins, a bag, a locked item
-- or anything the Loot Buyer buys (that is sold, not dropped). Returns row indexes.
function H.junkPlan(rows, used, size)
	local out = {}
	if size <= 0 or used / size < H.BAG_JAM then
		return out
	end
	local junk = {}
	for i, r in ipairs(rows or {}) do
		if r.kind == "junk" then
			junk[#junk + 1] = i
		end
	end
	table.sort(junk, function(a, b)
		local ra, rb = rows[a], rows[b]
		if (ra.score or 0) ~= (rb.score or 0) then
			return (ra.score or 0) < (rb.score or 0)
		end
		if (ra.count or 1) ~= (rb.count or 1) then
			return (ra.count or 1) < (rb.count or 1)
		end
		return a < b
	end)
	local left = used
	for _, i in ipairs(junk) do
		if left / size < H.BAG_JAM - 0.1 then
			break
		end
		out[#out + 1] = i
		left = left - 1
	end
	return out
end

-- the answer of `!tester bag`: rows (the backpack's own slots, each with its container index `i`), worn scores, size
-- {used, size, rows = [{i, id, cid, n, k, s, sc}], better = row index or nil, junk = [row index], sell = number of rows
-- the Loot Buyer buys, potions = {id = count}}
function H.bagReport(rows, worn, size, refused)
	local used = #rows
	local better = H.betterPiece(worn, rows, refused)
	local sells = 0
	for _, r in ipairs(rows) do
		if r.kind == "sell" then
			sells = sells + 1
		end
	end
	local out = {}
	for i, r in ipairs(rows) do
		if #out < H.REPORT_MAX or i == better then
			out[#out + 1] = {i = r.i, id = r.id, cid = r.clientId, n = r.count, k = r.kind, s = r.slot, sc = r.score}
		end
	end
	local junk = {}
	for _, idx in ipairs(H.junkPlan(rows, used, size)) do
		junk[#junk + 1] = rows[idx].i
	end
	return {used = used, size = size, rows = out, better = better and rows[better].i or nil, junk = junk, sell = sells}
end


-- ---------------------------------------------------------------- O584: `!tester give <what>`: items for the crafting checks
-- item: a plain piece of the class kit (no rarity, an item level); orb <key> [n]: crafting orbs (ChaosCrafting.config.orbs keys,
-- also whetstone and sockets); gem: the smallest gem; rune: the first support rune; charm: a small charm; card: the first card.
-- The tester gets them in its own backpack. Never another character's.
H.GIVE_WHAT = {item = true, orb = true, gem = true, rune = true, charm = true, card = true}
H.GIVE_MAX = 20
function H.parseGive(arg)
	local what, rest = tostring(arg or ""):match("^%s*(%a+)%s*(.-)%s*$")
	what = what and what:lower()
	if not what or not H.GIVE_WHAT[what] then
		return nil
	end
	local key, n
	if what == "orb" then
		key, n = rest:match("^(%a+)%s*(%d*)$")
		if not key then
			return nil
		end
		key = key:lower()
	elseif rest ~= "" then
		n = rest:match("^(%d+)$")
		if not n then
			return nil
		end
	end
	n = tonumber(n) or 1
	return {what = what, key = key, n = math.max(1, math.min(H.GIVE_MAX, n))}
end

-- ---------------------------------------------------------------- O653: `!tester found`: what the bot's own drops can do
-- The bot reads its backpack and what it wears (no grant: everything in it was dropped, bought or won by the bot) so that it can spend its orbs,
-- gems, whetstones and runes (tester_checks.py craft_found) and wear a better piece (gear_chase). Rows (built by tester_helper.lua):
--   {i, id, cid, n, slot, score, orb = KEY, gem = true, rune = true, charm = true, card = true, set = KEY, unique = true, jewelry = true}
-- worn = {[slot] = {score, set, unique}}; state = {sets = {[set key] = worn pieces}, size = {[set key] = pieces of the set}}.
H.COMMANDS.found = true
H.CHASE_SET = 40      -- a piece of a set the bot wears already: each worn piece of the set is worth this much more
H.CHASE_SET_NEW = 10  -- the first piece of a set
H.CHASE_UNIQUE = 30   -- a unique is rare: chased over a plain piece of the same score
H.CHASE_JEWELRY = 50  -- a ring or a necklace for an empty slot
H.FOUND_MAX = 16      -- rows of each list of the answer

function H.parseFound(arg)
	local what = tostring(arg or ""):match("^%s*(%a*)%s*$")
	if what == nil then
		return nil, "usage: found"
	end
	what = what:lower()
	if what == "" or what == "state" then
		return "state"
	end
	return nil, "usage: found"
end

-- the score of a piece that knows sets: the plain gain over what is worn in its slot, plus a share of the set it would join, a unique, a jewel
-- for an empty slot. A set piece that is worn already in another slot of the same set counts the pieces worn; a full set adds nothing.
function H.chaseScore(row, worn, state)
	local w = (worn or {})[row.slot] or {}
	local gain = (row.score or 0) - (w.score or 0)
	local score = gain
	if row.set then
		local have = ((state or {}).sets or {})[row.set] or 0
		local size = ((state or {}).size or {})[row.set] or 99
		if w.set == row.set then
			have = have - 1 -- it replaces a piece of the same set: no gain from the set
		end
		if have < size then
			score = score + (have > 0 and H.CHASE_SET * have or H.CHASE_SET_NEW)
		end
	end
	if row.unique and not w.unique then
		score = score + H.CHASE_UNIQUE
	end
	if row.jewelry and (w.score or 0) == 0 then
		score = score + H.CHASE_JEWELRY
	end
	return score
end

-- the answer: orbs = {key = count}, drops (what can be crafted with: orb, gem, rune, charm, card), pieces (wearable, with `chase`),
-- `best` (the backpack slot of the piece that gains the most, or nil: it must beat the worn one by EQUIP_MARGIN)
function H.foundReport(rows, worn, state)
	local orbs, drops, pieces = {}, {}, {}
	local best, gain = nil, H.EQUIP_MARGIN - 1
	for _, r in ipairs(rows or {}) do
		if r.orb then
			orbs[r.orb] = (orbs[r.orb] or 0) + (r.n or 1)
		end
		local kind = r.orb and "orb" or (r.gem and "gem") or (r.rune and "rune") or (r.charm and "charm") or (r.card and "card") or nil
		if kind and #drops < H.FOUND_MAX then
			drops[#drops + 1] = {i = r.i, id = r.id, cid = r.cid, n = r.n, k = kind, key = r.orb}
		elseif r.slot and not kind and #pieces < H.FOUND_MAX then
			local c = H.chaseScore(r, worn, state)
			pieces[#pieces + 1] = {i = r.i, id = r.id, cid = r.cid, s = r.slot, sc = r.score, set = r.set, unique = r.unique and true or nil,
				jewelry = r.jewelry and true or nil, chase = c}
			if c > gain then
				best, gain = r.i, c
			end
		end
	end
	local out = {}
	for slot, w in pairs(worn or {}) do
		out[#out + 1] = {s = slot, sc = w.score, set = w.set, unique = w.unique and true or nil}
	end
	table.sort(out, function(a, b) return a.s < b.s end)
	return {orbs = orbs, drops = drops, pieces = pieces, best = best, worn = out, sets = (state or {}).sets or {}}
end

-- ---------------------------------------------------------------- O654 the levelling journey on foot
-- `!tester journey [state | jump | hall] [keep ID] [skip ID,ID]`: what a person reads off the map and the hunt signs on the way from the
-- temple to the next hunt of the level: the hunt to go to (the teleport room's hunts, the window of progression_config.lua: hunts
-- whose middle level is within 0.8-1.1 x the level, widened by 0.05 a side until one fits), the temple's great teleport into the teleport
-- room (the gate), the stairs between its floors, the camp or town portal beside the bot, the depot locker and the nearest monster. The
-- walk, the steps onto the teleports, the fights and the trips are the bot's own; `jump` and `hall` are the helper's teleports that
-- the bot uses only as the counted fallback when the walk fails.
H.JOURNEY = {lo = 0.8, hi = 1.1, widen = 0.05, widenMax = 40, spread = 3, aim = 0.95, templeRadius = 24, sight = 15, crowd = 7}
H.HALL = {x1 = 31590, x2 = 31705, y1 = 32225, y2 = 32290, z1 = 5, z2 = 7} -- the teleport room of Cinderhold, hunt_teleports_config.lua room
H.HALL_DOOR = {x = 31648, y = 32233, z = 7} -- where the temple's great teleport leads (temple_portals_config.lua: the hub of the market)
H.PORTAL_AID = 47810 -- townportal_config.lua aid.field: the town portal beside its caster
H.JOURNEY_WORDS = {state = true, jump = true, hall = true}

function H.parseJourney(arg)
	local usage = "usage: journey [state | jump | hall] [keep ID] [skip ID,ID] [near X Y Z]"
	local out = {what = "state", skip = {}}
	local want
	for tok in tostring(arg or ""):gmatch("%S+") do
		local low = tok:lower()
		if want == "keep" then
			if not tok:match("^[%w_%.%-]+$") or #tok > 48 then
				return nil, usage
			end
			out.keep, want = tok, nil
		elseif want == "skip" then
			local n = 0
			for id in tok:gmatch("[^,]+") do
				n = n + 1
				if not id:match("^[%w_%.%-]+$") or #id > 48 or n > 24 then
					return nil, usage
				end
				out.skip[id] = true
			end
			want = nil
		elseif want == "near" then
			-- O661: near X Y Z (three numbers, one word each): the hunt whose arrival is nearest to a place (the bounty walks)
			local n = tonumber(tok)
			if not n or n ~= n or math.abs(n) > 70000 then
				return nil, usage
			end
			out.nearList = out.nearList or {}
			out.nearList[#out.nearList + 1] = math.floor(n)
			if #out.nearList == 3 then
				out.near = {x = out.nearList[1], y = out.nearList[2], z = out.nearList[3]}
				out.nearList, want = nil, nil
			end
		elseif low == "near" and not out.near then
			want = "near"
		elseif low == "keep" or low == "skip" then
			want = low
		elseif H.JOURNEY_WORDS[low] then
			out.what = low
		else
			return nil, usage
		end
	end
	if want then
		return nil, usage
	end
	return out
end

-- the middle of a hunt's band (what the progression model calls its hunting level)
function H.journeyMid(entry)
	local l = type(entry) == "table" and entry.l or nil
	if type(l) ~= "table" or type(l[1]) ~= "number" then
		return nil
	end
	local hi = (type(l[2]) == "number" and l[2] > 0) and l[2] or l[1]
	return (l[1] + hi) / 2
end

local function journeyEntry(e, k)
	return {id = e.i, n = e.n, lo = e.l[1], hi = e.l[2], t = xyz(e.t), f = xyz(e.f), a = xyz(e.a), b = xyz(e.b), widen = k}
end

-- O661: the hunt of the teleport room whose arrival is nearest to `near` {x, y, z} among the ones the level may enter (the bounty walks: a contract's
-- hunt mark is a place of the map, the way there is the temple's teleport, the hall and that hunt's teleport). -> entry (stay = true), distance `d`
-- (tiles, the larger axis; a hunt on another floor counts 1000 more), or nil when no hunt has an arrival
function H.journeyNear(ports, level, near)
	if type(near) ~= "table" then
		return nil
	end
	local best, bd
	for _, e in ipairs(ports or {}) do
		if type(e) == "table" and type(e.i) == "string" and type(e.t) == "table" and type(e.a) == "table" and type(e.l) == "table"
			and type(e.l[1]) == "number" and e.l[1] <= (tonumber(level) or 0) then
			local d = math.max(math.abs(e.a.x - near.x), math.abs(e.a.y - near.y)) + (e.a.z ~= near.z and 1000 or 0)
			if not bd or d < bd or (d == bd and e.i < best.i) then
				best, bd = e, d
			end
		end
	end
	if not best then
		return nil
	end
	local out = journeyEntry(best, 0)
	out.stay, out.d = true, bd
	return out
end

-- the hunt a character of `level` goes to next: ports = ChaosHuntTeleports.ports() rows {i, n, l = {lo, hi}, t, f, a, b}; opts = {keep = id
-- (the hunt it is at: kept while it still fits), skip = {id = true} (hunts that hurt it), seed = number (turns the choice so a hundred
-- bots do not share one hunt)}. -> entry {id, n, lo, hi, t, f, a, b, widen, stay}, or nil when the room lists no hunt; `above` is set
-- when every hunt needs more than the level (the bot cannot go in: the lowest one is returned)
function H.journeyPick(ports, level, opts)
	opts = opts or {}
	level = tonumber(level) or 0
	local J = H.JOURNEY
	if opts.near then
		local e = H.journeyNear(ports, level, opts.near)
		if e then
			return e
		end
	end
	local function pool(useSkip)
		local list = {}
		for _, e in ipairs(ports or {}) do
			if type(e) == "table" and type(e.i) == "string" and type(e.t) == "table" and H.journeyMid(e)
				and not (useSkip and opts.skip and opts.skip[e.i]) then
				list[#list + 1] = e
			end
		end
		return list
	end
	for _, useSkip in ipairs({true, false}) do
		local list = pool(useSkip)
		for k = 0, J.widenMax do
			local lo, hi = (J.lo - J.widen * k) * level, (J.hi + J.widen * k) * level
			local fit = {}
			for _, e in ipairs(list) do
				local mid = H.journeyMid(e)
				if e.l[1] <= level and mid >= lo and mid <= hi then
					fit[#fit + 1] = e
				end
			end
			if #fit > 0 then
				for _, e in ipairs(fit) do
					if opts.keep and e.i == opts.keep then
						local out = journeyEntry(e, k)
						out.stay = true
						return out
					end
				end
				local aim = J.aim * level
				table.sort(fit, function(a, b)
					local da, db = math.abs(H.journeyMid(a) - aim), math.abs(H.journeyMid(b) - aim)
					if da ~= db then
						return da < db
					end
					return a.i < b.i
				end)
				local n = math.min(#fit, J.spread)
				return journeyEntry(fit[(math.floor(tonumber(opts.seed) or 0) % n) + 1], k)
			end
		end
		-- no hunt in the widest window: the highest band the level may enter, else the lowest of all (the bot cannot go in)
		local best, lowest
		for _, e in ipairs(list) do
			if e.l[1] <= level and (not best or e.l[1] > best.l[1] or (e.l[1] == best.l[1] and e.i < best.i)) then
				best = e
			end
			if not lowest or e.l[1] < lowest.l[1] or (e.l[1] == lowest.l[1] and e.i < lowest.i) then
				lowest = e
			end
		end
		if best or lowest then
			local out = journeyEntry(best or lowest, -1)
			out.above = best == nil or nil
			return out
		end
	end
	return nil
end

function H.journeyInHall(pos)
	local h = H.HALL
	return type(pos) == "table" and pos.x >= h.x1 and pos.x <= h.x2 and pos.y >= h.y1 and pos.y <= h.y2 and pos.z >= h.z1 and pos.z <= h.z2
end

-- where the bot is: the teleport room, the temple, or elsewhere (a hunt, a street)
function H.journeyZone(pos, temple)
	if H.journeyInHall(pos) then
		return "hall"
	end
	if type(pos) == "table" and type(temple) == "table" and pos.z == temple.z and cheb(pos, temple) <= H.JOURNEY.templeRadius then
		return "temple"
	end
	return "other"
end

-- the nearest tile round `around` (same floor, within `radius`) whose facts `pred` accepts: tileAt(x, y, z) -> {dest = {x, y, z} of a
-- teleport, change = "up" | "down" for a floor change, aid = action id of an item} or nil. -> {x, y, z, info}
function H.journeyFind(tileAt, around, radius, pred)
	local best, bestD
	for dx = -radius, radius do
		for dy = -radius, radius do
			local x, y, z = around.x + dx, around.y + dy, around.z
			local info = tileAt(x, y, z)
			if info and pred(info) then
				local d = math.max(math.abs(dx), math.abs(dy)) * 10 + math.min(math.abs(dx), math.abs(dy))
				if not bestD or d < bestD then
					best, bestD = {x = x, y = y, z = z, info = info}, d
				end
			end
		end
	end
	return best
end

-- the temple's teleport into the teleport room: a teleport whose destination is the hub of the market
function H.journeyIsGate(info)
	local d, door = info and info.dest, H.HALL_DOOR
	return type(d) == "table" and d.z == door.z and cheb(d, door) <= 6
end

function H.journeyIsStairs(info, want)
	return info and info.change ~= nil and (want == nil or info.change == want)
end

function H.journeyIsPortal(info)
	return info and info.aid == H.PORTAL_AID
end

-- the answer line: the probe cut down (scalars, short lists), the places as {x, y, z}
function H.journeyAnswer(probe, extra)
	local out = {}
	if type(probe) == "table" then
		for _, k in ipairs({"level", "zone", "pz", "stay", "above", "crowd", "hot", "monster"}) do
			local c = cutValue(probe[k], 3)
			if c ~= nil then
				out[k] = c
			end
		end
		out.pos = xyz(probe.pos)
		for _, k in ipairs({"gate", "portal", "spot"}) do
			out[k] = xyz(probe[k])
		end
		local l = probe.locker
		if type(l) == "table" then
			out.locker = {x = l.x, y = l.y, z = l.z, cid = l.cid, sp = l.sp, spot = xyz(l.spot)}
		end
		if type(probe.stairs) == "table" then
			out.stairs = {up = xyz(probe.stairs.up), down = xyz(probe.stairs.down)}
		end
		local p = probe.pick
		if type(p) == "table" then
			out.pick = {id = p.id, n = type(p.n) == "string" and p.n:sub(1, 40) or nil, lo = p.lo, hi = p.hi, t = xyz(p.t), f = xyz(p.f),
				a = xyz(p.a), b = xyz(p.b), widen = p.widen, d = p.d, z = p.t and p.t.z or nil}
		end
	end
	for k, v in pairs(extra or {}) do
		out[k] = v
	end
	return out
end

-- ---------------------------------------------------------------- O658 `!tester gold [to N]`: the gold of a bot that gears up
-- `gold` reads the bank balance and the gold in the backpack. `gold to N` is a TEST ONLY top-up of the BANK to N, the fallback of the gear-up
-- of tester_checks.py (a bot that cannot pay for the potions and the basic pieces it buys at the shops): at most GOLD_STEP a call and GOLD_CAP
-- for a bot until the helper is reloaded; the bot counts every grant in its report. Only a tester character gets it (the guard of every
-- command, `eligible`); a player's words are left alone.
H.COMMANDS.gold = true
H.GOLD_STEP = 3000000
H.GOLD_CAP = 16000000

function H.parseGold(arg)
	local usage = "usage: gold [to N]"
	local s = tostring(arg or "")
	if s:match("^%s*$") then
		return {}
	end
	local n = s:match("^%s*[Tt][Oo]%s+(%d+)%s*$")
	n = tonumber(n)
	if not n or n < 1 then
		return nil, usage
	end
	return {to = math.min(n, H.GOLD_CAP)}
end

-- gold to add to the bank: -> give, reason (reason only when nothing is given for a rule)
function H.goldPlan(bank, want, given)
	bank, given = tonumber(bank) or 0, tonumber(given) or 0
	if want <= bank then
		return 0, nil
	end
	local left = H.GOLD_CAP - given
	if left <= 0 then
		return 0, "the grant limit of this bot is used up"
	end
	return math.min(want - bank, H.GOLD_STEP, left), nil
end

return H
