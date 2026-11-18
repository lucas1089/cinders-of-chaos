-- Tester bots on the live server (server/README.md "Tester bots"; rules in testers_core.lua).
--
-- A tester is a character with the storage Chaos.storage.tester = 1 (written only by server/tools/testers.py setup).
-- The engine never counts it online (src-patch 0059). This script keeps it apart from the players:
--   * login: a tester in a staff group or on a staff account is refused (testers never get rights); its guid joins
--     Chaos.testerGuids, so rankings, records, the chronicle and Discord leave it out
--   * the name plate shows the title TESTER (top priority); every look at it says it is a test character
--   * no combat, trade or party between a tester and a player (summons count as their master)
--   * Game.broadcastMessage drops a broadcast that names a tester (level, achievement, record, prize broadcasts)
--   * closed test mode (O582, data/chaos_testers_closed, chaos-ctl.sh testers closed on): two testers may fight, queue and trade
--     with each other only while it is on; a tester and a player never meet in any of those, on or off. The guards of the
--     systems (arena, battleground, pvpzone, guild, guildwar, market) ask the rules of testers_core.lua
--   * no mail: a tester's parcel or letter, or one to a tester's name, is refused at the mailbox (through
--     ChaosDepot.onMoveItem, the move hook patch_base_depot.py puts first in Player:onMoveItem)
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout, EventCallback onLook / onTargetCombat / onTradeRequest /
-- onTradeAccept / Party onJoin, GlobalEvent onStartup, db.storeQuery, Player:getGroup / getAccountType.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosTestersCore or not ChaosTestersCore.safetyProblem then
	dofile("data/scripts/chaos/testers_core.lua")
end

local K = ChaosTestersCore

ChaosTesters = ChaosTesters or {}
local X = ChaosTesters

local function log(text)
	print("[Chaos testers] " .. text)
end

local function testerOf(creature)
	if not creature then
		return nil
	end
	local p = creature
	if not creature:isPlayer() then
		local master = creature:getMaster()
		if not master or not master:isPlayer() then
			return nil
		end
		p = master
	end
	return p
end

local function isTester(creature)
	local p = testerOf(creature)
	return p ~= nil and Chaos.isTester(p)
end

local function isPlayerSide(creature)
	return testerOf(creature) ~= nil
end

-- every tester guid and name, from the database (startup and /reload)
function X.load()
	local id = db.storeQuery(string.format(
		"SELECT `p`.`id`, `p`.`name` FROM `players` `p` JOIN `player_storage` `s` ON `s`.`player_id` = `p`.`id` " ..
		"WHERE `s`.`key` = %d AND `s`.`value` = 1", Chaos.storage.tester))
	local n = 0
	if id then
		repeat
			Chaos.testerGuids[result.getNumber(id, "id")] = result.getString(id, "name")
			n = n + 1
		until not result.next(id)
		result.free(id)
	end
	return n
end

-- ---------------------------------------------------------------- login safety
local login = CreatureEvent("ChaosTestersLogin")
function login.onLogin(player)
	if not Chaos.isTester(player) then
		return true
	end
	local group = player:getGroup()
	local problem = K.safetyProblem(group and group:getId() or 0, player:getAccountType())
	if not problem and not K.isTesterName(player:getName()) then
		problem = "name is not \"Tester Xxx\""
	end
	if problem then
		log(string.format("refused tester %s (guid %d): %s", player:getName(), player:getGuid(), problem))
		return false
	end
	Chaos.testerGuids[player:getGuid()] = player:getName()
	return true
end
login:type("login")
login:register()

local startup = GlobalEvent("ChaosTestersStartup")
function startup.onStartup()
	local n = X.load()
	if n > 0 then
		log(string.format("%d tester character(s) known", n))
	end
	return true
end
startup:register()

-- ---------------------------------------------------------------- world event monsters (O650)
-- X.markWorld(monster, side) puts a monster of a shared world event under the rule of ChaosTestersCore.worldBlocked: a tester's damage to a
-- monster of the players is cancelled, a player's damage to a monster of the testers' own is cancelled. The guard event must come BEFORE the
-- event's own health event (treasure_goblin.lua, invasion.lua call it first), so a cancelled hit wakes nothing and credits nobody.
X.world = X.world or {} -- creature id -> "players" | "testers"
X.worldCancelled = X.worldCancelled or {} -- tester player id -> hits cancelled (the bots' probe: the rule held)

function X.markWorld(monster, side)
	if not monster or not K.WORLD_SIDES[side] then
		return false
	end
	X.world[monster:getId()] = side
	monster:registerEvent("ChaosTestersWorldTaken")
	return true
end

function X.worldSide(creature)
	return creature and X.world[creature:getId()] or nil
end

-- true when a hit of `attacker` (a creature; a summon counts as its master) on a monster of `side` is cancelled (ChaosTestersCore.worldBlocked);
-- a tester's cancelled hits are counted for the bots' probe. Monsters of a world event that is not marked (the Harvest King) ask it directly.
function X.worldHit(attacker, side)
	local who = testerOf(attacker)
	if not who then
		return false
	end
	local t = Chaos.isTester(who)
	if not K.worldBlocked(side, t) then
		return false
	end
	if t then
		X.worldCancelled[who:getId()] = (X.worldCancelled[who:getId()] or 0) + 1
	end
	return true
end

local worldTaken = CreatureEvent("ChaosTestersWorldTaken")
function worldTaken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local side = X.world[creature:getId()]
	if side and primaryType ~= COMBAT_HEALING and X.worldHit(attacker, side) then
		return 0, primaryType, 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
worldTaken:register()

-- ---------------------------------------------------------------- closed test mode (O582)
X.closed = K.closedOn

-- every tester guild member flag of a guild from the database (kept GUILD_TTL seconds): any, all (nil, nil when unknown)
local GUILD_TTL = 10
X.guildCache = X.guildCache or {}
function X.guildFlags(gid)
	local now = os.time()
	local c = X.guildCache[gid]
	if c and now - c.at < GUILD_TTL and now >= c.at then
		return c.any, c.all
	end
	local any, all
	local ok, id = pcall(db.storeQuery, string.format(
		"SELECT COUNT(*) AS `n`, SUM(EXISTS(SELECT 1 FROM `player_storage` `s` WHERE `s`.`player_id` = `m`.`player_id` " ..
		"AND `s`.`key` = %d AND `s`.`value` = 1)) AS `t` FROM `guild_membership` `m` WHERE `m`.`guild_id` = %d",
		Chaos.storage.tester, tonumber(gid) or 0))
	if ok and id then
		local n, t = result.getNumber(id, "n"), result.getNumber(id, "t")
		result.free(id)
		if n and n > 0 then
			any, all = (t or 0) > 0, (t or 0) == n
		end
	end
	X.guildCache[gid] = {at = now, any = any, all = all}
	return any, all
end

-- the side of a guild: "tester", "player" or nil (mixed, empty, unknown)
function X.guildSide(gid, name)
	local any, all = X.guildFlags(gid)
	return K.guildSide(name, any, all)
end

-- the reason a character may not use its guild (a tester outside a tester guild or with closed mode off, a player in a
-- tester guild), or nil. Fast for a player in a guild not named like a tester guild: no query
function X.guildBlocked(player, gid, name)
	local isT = Chaos.isTester(player)
	local prefixed = type(name) == "string" and name:sub(1, #K.GUILD_PREFIX) == K.GUILD_PREFIX
	if not isT and not prefixed then
		return nil
	end
	local any, all = X.guildFlags(gid)
	return K.guildBlocked(isT, name, any, all, K.closedOn())
end

-- may this viewer see this guild on a board (O592)? a player never sees a tester guild, a tester only tester guilds. Fast for a
-- player and a guild not named like a tester guild: no query
function X.guildVisible(player, gid, name)
	local isT = Chaos.isTester(player)
	local prefixed = type(name) == "string" and name:sub(1, #K.GUILD_PREFIX) == K.GUILD_PREFIX
	if not isT and not prefixed then
		return true
	end
	return K.guildVisible(isT, name, X.guildSide(gid, name))
end

-- a group of characters that wants a hall of solo content (the Infinity Tower, the Ember Descent, O595): the refusal text, or nil.
-- `free` halls are free now, `reserve` of them stay the players'. Fast for a group of players: no tester, no refusal
function X.soloRefusal(players, free, reserve)
	local flags, any = {}, false
	for i, p in ipairs(players or {}) do
		flags[i] = Chaos.isTester(p)
		any = any or flags[i]
	end
	if not any then
		return nil
	end
	local why = K.soloRefusal(flags, free, reserve)
	return why and (K.CLOSED_TEXT[why] or K.CLOSED_TEXT.mixed) or nil
end

-- a war between guilds a and b (ids and names): ok, reason. Both sides known and equal, tester wars in closed mode only
function X.warAllowed(gidA, nameA, gidB, nameB)
	return K.sameSide("guildwar", K.closedOn(), X.guildSide(gidA, nameA), X.guildSide(gidB, nameB))
end

-- ---------------------------------------------------------------- the TESTER tag
if ChaosTitles and ChaosTitles.register then
	ChaosTitles.register("tester", function(player)
		if not Chaos.isTester(player) then
			return nil
		end
		return {text = K.TITLE, key = "tester:tester", color = K.TITLE_COLOR, priority = K.TITLE_PRIORITY, at = 0}
	end)
end

local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() and Chaos.isTester(thing) then
		description = (description or "") .. "\n" .. K.lookLine(thing:getId() == self:getId())
	end
	return description
end
look:register(103)

-- ---------------------------------------------------------------- apart from the players
-- PvP among testers (O652): the name of the PvP place a character stands in ("arena", "battleground", "siege", "pvp zone": blessings.lua
-- pvpPlace, the same list the other systems use) or nil. Asked only when two testers face each other (a rare call, not every hit).
function X.pvpPlace(creature)
	local p = testerOf(creature)
	local B = rawget(_G, "ChaosBlessings")
	if not p or not B or not B.pvpPlace then
		return nil
	end
	local ok, place = pcall(B.pvpPlace, p)
	return ok and place or nil
end

-- what the bots' probe reads (`!tester pvp`): per tester player id, the hits a rule cancelled
X.pvpStats = X.pvpStats or {} -- id -> {player = n (a hit on a player), outside = n (on a tester outside a place), off = n (closed mode off)}
local function pvpCount(creature, what)
	local p = testerOf(creature)
	if p and Chaos.isTester(p) then
		local row = X.pvpStats[p:getId()] or {player = 0, outside = 0, off = 0}
		row[what] = row[what] + 1
		X.pvpStats[p:getId()] = row
	end
end

-- may tester `a` hit tester `b` now (the bots' own targeting rule: `player:setTarget` skips the callback below, so the helper asks it before it
-- aims)? Both testers, closed mode on, one PvP place and that place's own rule (the arena / battleground foe, the Marches, the siege arena).
-- -> true, place | false, why
function X.pvpFoe(a, b)
	if not a or not b or a:getId() == b:getId() or not Chaos.isTester(a) or not Chaos.isTester(b) then
		return false, "not two testers"
	end
	if not K.closedOn() then
		return false, "closed-off"
	end
	local place = X.pvpPlace(a)
	if not place or place ~= X.pvpPlace(b) then
		return false, "no-place"
	end
	local function ask(name, fn)
		local sys = rawget(_G, name)
		if not (sys and sys[fn]) then
			return false
		end
		local ok, res = pcall(sys[fn], a, b)
		return ok and res == true
	end
	local foe
	if place == "arena" then
		foe = ask("ChaosArena", "foe")
	elseif place == "battleground" then
		foe = ask("ChaosBattleground", "foe")
	elseif place == "pvp zone" then
		foe = ask("ChaosPvpZone", "foe")
	elseif place == "siege" then
		local S = rawget(_G, "ChaosSiege")
		local ok, res = pcall(function() return S.targetCombat(a, b) end)
		foe = ok and res == RETURNVALUE_NOERROR
	end
	return foe and true or false, place
end

X.PVP_SIGHT = 12 -- tiles within which the bot's targeting loop looks for a foe
X.PVP_REACH = 5 -- tiles within which the guide says fight

-- the nearest foe of a tester (X.pvpFoe): {x, y, z, name, id, dist, seen = true} among the characters in sight, else (seen = false) the nearest of
-- the lists the PvP systems give (`foes` of their probes: a match is wider than the screen). nil when there is none.
function X.pvpNearestFoe(player, lists)
	local pos = player:getPosition()
	local best
	local range = X.PVP_SIGHT
	for _, c in ipairs(Game.getSpectators(pos, false, true, range, range, range, range) or {}) do
		if c:isPlayer() and c:getId() ~= player:getId() and X.pvpFoe(player, c) then
			local cp = c:getPosition()
			local d = math.max(math.abs(cp.x - pos.x), math.abs(cp.y - pos.y))
			if cp.z == pos.z and (not best or d < best.dist) then
				best = {x = cp.x, y = cp.y, z = cp.z, name = c:getName(), id = c:getId(), dist = d, seen = true,
					hp = math.floor(c:getHealth() * 100 / math.max(1, c:getMaxHealth()))}
			end
		end
	end
	if best then
		return best
	end
	for _, list in ipairs(lists or {}) do
		for _, f in ipairs(list or {}) do
			local d = math.max(math.abs(f.x - pos.x), math.abs(f.y - pos.y))
			if f.z == pos.z and (not best or d < best.dist) then
				best = {x = f.x, y = f.y, z = f.z, name = f.name, dist = d, seen = false, hp = f.hp}
			end
		end
	end
	return best
end

-- what the bots' probe reads (`!tester pvp`): the place, the switch, the hits the rules cancelled, and the PvP systems' own view
function X.pvpProbe(player)
	local pos = player:getPosition()
	local out = {closed = K.closedOn() and true or false, place = X.pvpPlace(player), level = player:getLevel(), pos = {x = pos.x, y = pos.y, z = pos.z}}
	local row = X.pvpStats[player:getId()] or {player = 0, outside = 0, off = 0}
	out.cancelledPlayer, out.cancelledOutside, out.cancelledOff = row.player, row.outside, row.off
	local PS = rawget(_G, "ChaosPvpSeason")
	if PS and PS.listedTesters then
		local ok, n = pcall(PS.listedTesters)
		out.seasonListed = ok and n or nil -- testers with a row in the season ratings: 0
	end
	local lists = {}
	for _, sys in ipairs({{"arena", "ChaosArena"}, {"battleground", "ChaosBattleground"}, {"zone", "ChaosPvpZone"}}) do
		local S = rawget(_G, sys[2])
		if S and S.probe then
			local ok, got = pcall(S.probe, player)
			out[sys[1]] = ok and got or nil
			if ok and type(got) == "table" and got.foes then
				lists[#lists + 1] = got.foes
			end
		end
	end
	-- the guide: a foe the rules allow in sight (what the bot's targeting loop aims at), else the nearest foe a system lists, else (battleground) a
	-- brazier the team does not hold, else wait. Outside a PvP place the bot has no foe at all: it never aims at a tester there.
	out.foe = out.place and X.pvpNearestFoe(player, lists) or nil
	if out.foe then
		local near = out.foe.seen and out.foe.dist <= X.PVP_REACH
		out.guide = {mode = near and "fight" or "walk", goal = {x = out.foe.x, y = out.foe.y, z = out.foe.z}, reach = {1, X.PVP_REACH}, area = "foe"}
	elseif out.battleground and out.battleground.phase == "fight" and out.battleground.braziers then
		local me = out.battleground.team
		local pos = player:getPosition()
		local best
		for _, b in ipairs(out.battleground.braziers) do
			local d = math.max(math.abs(b.x - pos.x), math.abs(b.y - pos.y))
			if b.owner ~= me and b.z == pos.z and (not best or d < best.d) then
				best = {x = b.x, y = b.y, z = b.z, d = d}
			end
		end
		out.guide = best and {mode = "walk", goal = {x = best.x, y = best.y, z = best.z}, reach = {0, 1}, area = "brazier"}
			or {mode = "wait", why = "the braziers are held"}
	else
		out.guide = {mode = "wait", why = out.place and "no foe in reach" or "not in a PvP place"}
	end
	return out
end

local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	if not creature or not target or not isPlayerSide(creature) or not isPlayerSide(target) then
		return RETURNVALUE_NOERROR
	end
	-- their own summon or themselves: the engine's rules
	if testerOf(creature) == testerOf(target) then
		return RETURNVALUE_NOERROR
	end
	local aT, bT = isTester(creature), isTester(target)
	if not aT and not bT then
		return RETURNVALUE_NOERROR
	end
	if K.mixed(aT, bT) then
		pvpCount(creature, "player")
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	-- two testers: the closed switch and a PvP place on both sides (K.pvpRefusal)
	local why = K.pvpRefusal(aT, bT, K.closedOn(), nil, nil)
	if why == "closed-off" then
		pvpCount(creature, "off")
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	why = K.pvpRefusal(aT, bT, true, X.pvpPlace(creature), X.pvpPlace(target))
	if why then
		pvpCount(creature, "outside")
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
guard:register()

local trade = EventCallback
trade.onTradeRequest = function(player, target, item)
	if target and K.mixed(Chaos.isTester(player), Chaos.isTester(target)) then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return false
	end
	return true
end
trade:register()

local accept = EventCallback
accept.onTradeAccept = function(player, target, item, targetItem)
	return not (target and K.mixed(Chaos.isTester(player), Chaos.isTester(target)))
end
accept:register()

local partyJoin = EventCallback
partyJoin.onJoin = function(party, player)
	local leader = party:getLeader()
	if leader and K.mixed(Chaos.isTester(leader), Chaos.isTester(player)) then
		player:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
		return false
	end
	return true
end
partyJoin:register()

-- ---------------------------------------------------------------- broadcasts
-- mail: a tester sends none, a player's parcel or letter to a tester's name stays (depot.lua's move hook runs this first)
local function mailboxAt(pos)
	if not pos or pos.x == CONTAINER_POSITION then
		return false
	end
	local tile = Tile(pos)
	if not tile then
		return false
	end
	for id in pairs(K.MAILBOXES) do
		if tile:getItemById(id) then
			return true
		end
	end
	return false
end

local function receiverOf(item)
	local kind = K.MAIL_ITEMS[item:getId()]
	if kind == "letter" then
		return K.receiverOf(item:getAttribute(ITEM_ATTRIBUTE_TEXT))
	end
	if kind == "parcel" and item:isContainer() then
		for i = 0, item:getSize() - 1 do
			local inner = item:getItem(i)
			if inner and inner:getId() == K.LABEL then
				return K.receiverOf(inner:getAttribute(ITEM_ATTRIBUTE_TEXT))
			end
		end
	end
	return nil
end

function X.mailRefusal(player, item, toPosition)
	if not K.MAIL_ITEMS[item:getId()] or not mailboxAt(toPosition) then
		return nil
	end
	return K.mailBlocked(Chaos.isTester(player), receiverOf(item))
end

if ChaosDepot and ChaosDepot.onMoveItem and not X.rawDepotMove then
	X.rawDepotMove = ChaosDepot.onMoveItem
	ChaosDepot.onMoveItem = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
		local ok, why = pcall(X.mailRefusal, player, item, toPosition)
		if ok and why then
			player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t and Chaos.t(player, why) or why)
			return RETURNVALUE_NOTPOSSIBLE
		end
		return X.rawDepotMove(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	end
end

if Game and Game.broadcastMessage and not X.rawBroadcast then
	X.rawBroadcast = Game.broadcastMessage
	Game.broadcastMessage = function(text, kind)
		if next(Chaos.testerGuids) ~= nil and K.mentions(text, Chaos.testerGuids) then
			return true
		end
		return X.rawBroadcast(text, kind)
	end
end
