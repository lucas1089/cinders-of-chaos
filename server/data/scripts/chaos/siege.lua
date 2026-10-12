-- Guild siege: a weekly scheduled war between signed-up guilds for the Chaos Obelisk.
-- Settings: siege_config.lua (Chaos.siegeConfig). Pure logic: siege_core.lua (tested in tests/siege_test.lua).
-- Client: game_siege (HUD + sign-up window), extended opcode ChaosOpcodes.siege. Overview: server/README.md "Guild siege".
--
-- Flow
--   during the week   guild leaders / vice-leaders sign up with !siege join (minMembers members, first come, the
--                     sign-ups are rows of chaos_siege_signups for the start time they belong to)
--   warnings          warnMinutes before the start (broadcast; the first and last also as a toast)
--   start             (schedule, or /siege start) the signed-up guilds are split into brackets of 2..perBracket guilds;
--                     every bracket gets its own arena, built with Game.createTile like the world-boss arena (refused if
--                     a footprint tile already exists and is not ours): walls, a Chaos Obelisk in the middle with a
--                     capture area of white marble around it, pillars for cover, and one base room per guild outside
--                     each side of the arena. Entry portals (forcefield, action id aid.enter) appear next to the temples.
--   gathering         members step into a portal and arrive in their guild's base; the gates are shut for gatherSeconds
--   match             matchMinutes. Gates (forcefield in each base, aid.gate) lead into the arena. Kills and the
--                     obelisk score; the HUD shows scores, time left and who holds the point
--   end               standings, rewards, the champion title and buff, results in chaos_siege_results, broadcast and
--                     toast; after exitDelaySeconds everyone inside goes to their temple and the arena is cleaned
--                     (monsters, corpses, loose items; walls, obelisk and decoration stay)
--
-- PvP inside (the arena of the player's own bracket, during the match):
--   * members of different signed-up guilds can always attack each other: skulls, secure mode of the target and
--     party do not matter (ChaosSiege.targetCombat; the base server's Creature:onTargetCombat rules run after it once
--     tools/patch_base_events.py added the hook, and ChaosSpell.canAttack asks ChaosSiege.canAttack). Guild mates,
--     the bases, a downed player and anyone who is not a participant cannot be attacked. Your OWN secure mode still
--     has to be off to attack (the engine checks it before any script).
--   * nobody really dies: onPrepareDeath cancels the lethal hit (no death, so no frag, no unjustified kill, no
--     experience or item loss, no blessing used). The player is "downed" for downedSeconds (cannot attack or be
--     attacked, slowed) and wakes up in the guild's base with full health and mana.
--   * white skulls that attacks give inside are taken back every second, and on leaving the in-fight condition (pz
--     lock) is removed when the player came in without a skull.
-- Multi-client (Chaos.isMultiClient): refused at the portal; a participant who becomes one is sent out.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/siege_core.lua")

Chaos.siegeConfig = dofile("data/scripts/chaos/siege_config.lua")
local cfg = Chaos.siegeConfig
local S = ChaosSiege
local OPCODE = ChaosOpcodes.siege or 233
local T_SIGNUPS, T_RESULTS = cfg.tables.signups, cfg.tables.results

local function log(text)
	print("[Chaos siege] " .. text)
end

-- the calendar on the login screen and !events (events_schedule.lua reads Chaos.events.list)
if Chaos.events and Chaos.events.list then
	local found = false
	for i, e in ipairs(Chaos.events.list) do
		if e.id == "guildsiege" then
			Chaos.events.list[i] = S.calendarEvent(cfg)
			found = true
		end
	end
	if not found then
		table.insert(Chaos.events.list, S.calendarEvent(cfg))
	end
end

-- ======================================================================== state
S.state = S.state or {phase = "idle", token = 0}
S.pending = S.pending or {} -- guid -> rewards of players offline at the end
S.champions = S.champions or {} -- guild id -> {name, untilAt}
local state = S.state

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local function announce(text, toast)
	if Game.broadcastMessage then
		Game.broadcastMessage(text, MESSAGE_EVENT_ADVANCE)
	else
		for _, p in ipairs(Game.getPlayers()) do
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
	end
	if toast and ChaosNotify and ChaosNotify.gmBroadcast then
		ChaosNotify.gmBroadcast(nil, text)
	end
	log(text)
end

local function layoutOf(b)
	return S.layout(cfg.arena, b)
end

local function active()
	return state.phase ~= "idle"
end

-- participant record of a player (or nil)
local function part(player)
	return player and state.players and state.players[player:getGuid()] or nil
end

-- "arena" | "base", slot, bracket for a position inside any built bracket (or nil)
local function locate(pos)
	if not pos then
		return nil
	end
	local L1 = layoutOf(1)
	if pos.z ~= L1.z or pos.y < L1.box.y1 or pos.y > L1.box.y2 or pos.x < L1.box.x1 then
		return nil
	end
	local b = math.floor((pos.x - L1.box.x1) / L1.stride) + 1
	if b < 1 or b > (cfg.maxBrackets or 1) then
		return nil
	end
	local where, slot = S.where(pos, layoutOf(b))
	if where then
		return where, slot, b
	end
	return nil
end
S.locate = locate

-- a player (or a position) inside any built bracket of the siege: guild.lua, arena.lua, treasure_goblin.lua and the
-- instance registry (chaos_constants.lua) ask
function S.isInsidePos(pos)
	return locate(pos) ~= nil
end
function S.isInside(player)
	return player ~= nil and locate(player:getPosition()) ~= nil
end
Chaos.registerInstance("siege", {label = "a guild siege", at = S.isInsidePos, runs = function() -- /instances
	if not S.state or S.state.phase == "idle" then
		return {}
	end
	local n = 0
	for _, p in pairs(S.state.players or {}) do
		if p.inside then
			n = n + 1
		end
	end
	return {{id = "siege", what = S.state.phase, left = S.state.endAt and math.max(0, S.state.endAt - os.time()) or nil, players = n}}
end, close = function() -- as /siege stop (no rewards)
	if not S.state or S.state.phase == "idle" then
		return false, "No guild siege is running."
	end
	S.stop()
	return true, "Guild siege stopped."
end})

local function team(p)
	local br = state.brackets and state.brackets[p.bracket]
	return br and br.teams[p.slot] or nil
end

local function guildOf(player)
	local g = player:getGuild()
	if not g then
		return nil
	end
	return g:getId(), g:getName()
end

local function templeOf(player)
	if cfg.exitPosition then
		return P(cfg.exitPosition)
	end
	local town = player:getTown()
	return town and town:getTemplePosition() or player:getPosition()
end

-- ======================================================================== database
local function signupsFor(at)
	return Chaos.select(string.format(
		"SELECT `guild_id`, `guild_name`, `signed_at` FROM `%s` WHERE `siege_at` = %d ORDER BY `signed_at`, `guild_id`",
		T_SIGNUPS, at), {{"guild_id", "n"}, {"guild_name", "s"}, {"signed_at", "n"}})
end

local function memberCount(guildId)
	local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM `guild_membership` WHERE `guild_id` = " .. guildId, {{"n", "n"}})
	return rows[1] and rows[1].n or 0
end

local function loadChampions()
	S.champions = {}
	local since = os.time() - (cfg.titleDays or 7) * 86400
	for _, r in ipairs(Chaos.select(string.format(
			"SELECT `guild_id`, `guild_name`, `ended_at` FROM `%s` WHERE `winner` = 1 AND `ended_at` > %d", T_RESULTS, since),
			{{"guild_id", "n"}, {"guild_name", "s"}, {"ended_at", "n"}})) do
		local untilAt = r.ended_at + (cfg.titleDays or 7) * 86400
		local c = S.champions[r.guild_id]
		if not c or c.untilAt < untilAt then
			S.champions[r.guild_id] = {name = r.guild_name, untilAt = untilAt}
		end
	end
end

-- ======================================================================== schedule helpers
function S.upcoming()
	S.nextAt = S.nextAt or S.nextStart(os.time(), cfg)
	return S.nextAt
end

local function signupInfo(player)
	local at = S.upcoming()
	local guildId, guildName = guildOf(player)
	local list = signupsFor(at)
	local signed = false
	for _, r in ipairs(list) do
		if r.guild_id == guildId then
			signed = true
		end
	end
	return {guildId = guildId, guildName = guildName, rank = guildId and player:getGuildLevel() or 0,
		members = guildId and memberCount(guildId) or 0, signed = signed, count = #list,
		open = S.signupsOpen(os.time(), at, cfg), running = active()}, list, at
end

function S.join(player)
	local info, _, at = signupInfo(player)
	local err = S.signupError(info, cfg)
	if err then
		return false, err
	end
	db.query(string.format("INSERT INTO `%s` (`siege_at`, `guild_id`, `guild_name`, `signed_by`, `signed_at`) VALUES (%d, %d, %s, %d, %d)",
		T_SIGNUPS, at, info.guildId, db.escapeString(info.guildName), player:getGuid(), os.time()))
	log(string.format("%s signed up %s for %s", player:getName(), info.guildName, S.whenText(at)))
	return true, string.format("%s is signed up for the guild siege on %s (%d guild(s) so far). Members enter through the portals next to the temples when it starts.",
		info.guildName, S.whenText(at), info.count + 1)
end

function S.leave(player)
	local info, _, at = signupInfo(player)
	local err = S.leaveError(info, cfg)
	if err then
		return false, err
	end
	db.query(string.format("DELETE FROM `%s` WHERE `siege_at` = %d AND `guild_id` = %d", T_SIGNUPS, at, info.guildId))
	log(string.format("%s withdrew %s from %s", player:getName(), info.guildName, S.whenText(at)))
	return true, info.guildName .. " is no longer signed up for the guild siege."
end

-- ======================================================================== arena
local function groundIdOf(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function fixedItemIds()
	local a = cfg.arena
	return {[a.wallId] = true, [a.obeliskId] = true, [a.pillarId] = true, [a.basinId] = true, [a.flagId] = true,
		[a.portalId] = true}
end

local function placeItem(pos, id, aid)
	local tile = Tile(pos)
	if not tile then
		return nil
	end
	local item = tile:getItemById(id)
	if not item then
		item = Game.createItem(id, 1, pos)
	end
	if item and aid and item.setActionId then
		item:setActionId(aid)
	end
	return item
end

local function groundFor(t)
	local a = cfg.arena
	return t.ground == "point" and a.pointGroundId or (t.ground == "base" and a.baseGroundId or a.groundId)
end

-- returns true, or false + reason (nothing is built then)
function S.buildArena(b)
	local a = cfg.arena
	local L = layoutOf(b)
	local foot = S.footprint(L, cfg.capture.radius)
	local ours = {[a.groundId] = true, [a.pointGroundId] = true, [a.baseGroundId] = true}
	for _, t in ipairs(foot) do
		local tile = Tile(P(t))
		if tile then
			local gid = groundIdOf(tile)
			if not ours[gid] or (tile.getHouse and tile:getHouse()) then
				return false, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
			end
		end
	end
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(groundFor(t), 1, pos)
			end
			if t.wall and not tile:getItemById(a.wallId) then
				Game.createItem(a.wallId, 1, pos)
			end
		end
	end
	placeItem(P(L.center), a.obeliskId)
	for _, p in ipairs(L.pillars) do
		placeItem(P(p), a.pillarId)
	end
	for _, p in ipairs(L.basins) do
		placeItem(P(p), a.basinId)
	end
	for _, base in ipairs(L.bases) do
		placeItem(P(base.gate), a.portalId, cfg.aid.gate)
		placeItem(P(base.exit), a.portalId, cfg.aid.exit)
		for _, p in ipairs(base.basins) do
			placeItem(P(p), a.basinId)
		end
		for _, p in ipairs(base.flags) do
			placeItem(P(p), a.flagId)
		end
	end
	return true
end

local function cleanArena(b)
	local keep = fixedItemIds()
	for _, t in ipairs(S.footprint(layoutOf(b), cfg.capture.radius)) do
		if not t.wall then
			local tile = Tile(P(t))
			if tile then
				for _, c in ipairs(tile:getCreatures() or {}) do
					if c:isMonster() then
						c:remove()
					end
				end
				for _, item in ipairs(tile:getItems() or {}) do
					if not keep[item:getId()] then
						item:remove()
					end
				end
			end
		end
	end
end

-- ======================================================================== town portals
local function spotFree(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile.getHouse and tile:getHouse() then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH) then
		return false
	end
	if ITEM_TYPE_TELEPORT and tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return false
	end
	return true
end

local function portalSpots()
	local spots = {}
	if cfg.portalPositions and #cfg.portalPositions > 0 then
		for _, p in ipairs(cfg.portalPositions) do
			spots[#spots + 1] = P(p)
		end
		return spots
	end
	local seen = {}
	for _, town in ipairs(Game.getTowns()) do
		local t = town:getTemplePosition()
		local key = t.x .. "," .. t.y .. "," .. t.z
		if t.x > 0 and not seen[key] then
			seen[key] = true
			for _, off in ipairs(cfg.portalOffsets) do
				local p = Position(t.x + off[1], t.y + off[2], t.z)
				if spotFree(p) then
					spots[#spots + 1] = p
					break
				end
			end
		end
	end
	return spots
end

local function addPortal(pos)
	local item = Game.createItem(cfg.arena.portalId, 1, pos)
	if item then
		item:setActionId(cfg.aid.enter)
		state.portals[#state.portals + 1] = pos
		pos:sendMagicEffect(CONST_ME_TELEPORT)
		return true
	end
	return false
end

local function openPortals()
	state.portals = {}
	for _, pos in ipairs(portalSpots()) do
		addPortal(pos)
	end
	state.portalsOpen = true
	return #state.portals
end

local function closePortals()
	for _, pos in ipairs(state.portals or {}) do
		local tile = Tile(pos)
		local item = tile and tile:getItemById(cfg.arena.portalId)
		if item and item:getActionId() == cfg.aid.enter then
			item:remove()
			pos:sendMagicEffect(CONST_ME_POFF)
		end
	end
	state.portals = {}
	state.portalsOpen = false
end

-- ======================================================================== HUD
local function bracketTeams(br)
	local list = {}
	for slot = 1, 4 do
		local t = br.teams[slot]
		if t then
			list[#list + 1] = t
		end
	end
	return list
end

local function insideCount(b, guildId)
	local n = 0
	for _, p in pairs(state.players or {}) do
		if p.bracket == b and p.guildId == guildId and p.inside then
			n = n + 1
		end
	end
	return n
end

local function hudData(b, p)
	local br = state.brackets[b]
	local now = os.time()
	local left
	if state.phase == "gather" then
		left = (state.matchAt or now) - now
	elseif state.phase == "match" then
		left = (state.endAt or now) - now
	else
		left = 0
	end
	local teams = {}
	for _, t in ipairs(bracketTeams(br)) do
		teams[#teams + 1] = {name = t.name, score = t.score, kills = t.kills, color = t.color, side = t.side,
			own = p and p.guildId == t.id or false, members = insideCount(b, t.id)}
	end
	local holder = br.holder and br.teams[br.byGuild[br.holder]]
	return {phase = state.phase, left = math.max(0, left), bracket = b, brackets = #state.brackets, teams = teams,
		holder = holder and holder.name or "", holderColor = holder and holder.color or "", contested = br.contested or false,
		you = p and {kills = p.kills, deaths = p.deaths, points = p.points} or nil, result = br.result}
end

local function sendHud(player, p)
	Chaos.send(player, OPCODE, "hud", hudData(p.bracket, p))
end

local function hideHud(player)
	Chaos.send(player, OPCODE, "hide", {})
end

-- ======================================================================== participants
local function setSkullBack(player, p)
	if SKULL_WHITE and player:getSkull() == SKULL_WHITE and p.entrySkull ~= SKULL_WHITE then
		player:setSkull(p.entrySkull or SKULL_NONE)
	end
end

local function leaveCleanup(player, p)
	player:setTarget(nil)
	setSkullBack(player, p)
	if (p.entrySkull or SKULL_NONE) == SKULL_NONE and CONDITION_INFIGHT and CONDITIONID_DEFAULT then
		-- the in-fight condition has CONDITIONID_DEFAULT (removeCondition defaults to CONDITIONID_COMBAT)
		player:removeCondition(CONDITION_INFIGHT, CONDITIONID_DEFAULT)
	end
	player:unregisterEvent("ChaosSiegeDeath")
	player:unregisterEvent("ChaosSiegeHealth")
	p.inside = false
	p.downedUntil = nil
	hideHud(player)
end

local function sendOut(player, p, text)
	player:teleportTo(templeOf(player))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	if p then
		leaveCleanup(player, p)
	end
	if text then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	end
end

local function toBase(player, p)
	local base = layoutOf(p.bracket).bases[p.slot]
	player:teleportTo(P(base.spawn))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
end

local BAD_CONDITIONS = {"CONDITION_POISON", "CONDITION_FIRE", "CONDITION_ENERGY", "CONDITION_BLEEDING",
	"CONDITION_PARALYZE", "CONDITION_DROWN", "CONDITION_FREEZING", "CONDITION_DAZZLED", "CONDITION_CURSED"}

local function restore(player)
	for _, name in ipairs(BAD_CONDITIONS) do
		local c = _G[name]
		if c then
			player:removeCondition(c)
		end
	end
	-- setHealth stops at the base maximum; this engine's addHealth takes (damage type, amount) (see shop_services.lua)
	player:setHealth(player:getMaxHealth())
	local missing = player:getMaxHealth() - player:getHealth()
	if missing > 0 then
		pcall(player.addHealth, player, "healing", missing)
	end
	player:addMana(player:getMaxMana() - player:getMana())
end

local downedSlow = Condition(CONDITION_PARALYZE)
downedSlow:setParameter(CONDITION_PARAM_TICKS, (cfg.downedSeconds or 3) * 1000)
downedSlow:setFormula(-0.9, 0, -0.9, 0)

local function respawn(guid, token)
	if state.token ~= token then
		return
	end
	local p = state.players[guid]
	if not p or not p.downedUntil then
		return
	end
	p.downedUntil = nil
	local player = Player(p.name)
	if not player or player:getGuid() ~= guid then
		return
	end
	if not locate(player:getPosition()) then
		return
	end
	restore(player)
	toBase(player, p)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You wake up in your guild's base. The gate leads back into the fight.")
end

-- a lethal hit inside: no death, the player is downed and wakes up in the base
local function downed(player, p, killer)
	local now = os.time()
	p.deaths = p.deaths + 1
	p.downedUntil = now + (cfg.downedSeconds or 3)
	local pos = player:getPosition()
	pos:sendMagicEffect(CONST_ME_MORTAREA)
	player:addCondition(downedSlow)
	local k = playerOf(killer)
	local kp = k and part(k)
	if kp and kp.guildId ~= p.guildId and kp.bracket == p.bracket and state.phase == "match" then
		local kt = team(kp)
		kt.score = kt.score + cfg.points.kill
		kt.kills = kt.kills + 1
		kp.kills = kp.kills + 1
		kp.points = kp.points + cfg.points.kill
		k:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You struck down %s: +%d points for %s.", player:getName(), cfg.points.kill, kt.name))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s struck you down. You wake up in your base in %d seconds.", k:getName(), cfg.downedSeconds or 3))
		for _, q in pairs(state.players) do
			if q.bracket == p.bracket and q.inside and q.guid ~= kp.guid and q.guid ~= p.guid then
				local other = Player(q.name)
				if other then
					other:sendTextMessage(MESSAGE_STATUS_SMALL, string.format("%s (%s) struck down %s.", k:getName(), kt.name, player:getName()))
				end
			end
		end
	else
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You were struck down. You wake up in your base in %d seconds.", cfg.downedSeconds or 3))
	end
	addEvent(respawn, (cfg.downedSeconds or 3) * 1000, p.guid, state.token)
end

-- ======================================================================== combat rules
-- nil = not the siege's business (the normal rules apply), else a RETURNVALUE_*. Used by the EventCallback below, by
-- the hook tools/patch_base_events.py puts in front of the base server's Creature:onTargetCombat rules, and by
-- ChaosSpell.canAttack (through ChaosSiege.canAttack).
function S.targetCombat(creature, target)
	if not creature or not target or not active() or not target:isPlayer() then
		return nil
	end
	local twhere = locate(target:getPosition())
	local attacker = playerOf(creature)
	if not attacker then
		-- monsters and fields: no harm to players in a base or downed
		local tp = twhere and part(target)
		if tp and (twhere == "base" or tp.downedUntil) then
			return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
		end
		return nil
	end
	local awhere = locate(attacker:getPosition())
	if not twhere and not awhere then
		return nil
	end
	if attacker == target then
		return nil
	end
	local ap, tp = part(attacker), part(target)
	if not ap or not tp then
		if attacker:getGroup():getAccess() then
			return nil
		end
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if ap.bracket ~= tp.bracket or ap.guildId == tp.guildId then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if state.phase ~= "match" or awhere ~= "arena" or twhere ~= "arena" then
		return RETURNVALUE_ACTIONNOTPERMITTEDINPROTECTIONZONE
	end
	if ap.downedUntil or tp.downedUntil then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	if Chaos.isMultiClient(attacker) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end

-- for ChaosSpell.canAttack: true / false, or nil when the siege has no say
function S.canAttack(caster, target)
	local r = S.targetCombat(caster, target)
	if r == nil then
		return nil
	end
	return r == RETURNVALUE_NOERROR
end

local guard = EventCallback
guard.onTargetCombat = function(creature, target)
	return S.targetCombat(creature, target) or RETURNVALUE_NOERROR
end
guard:register(-10) -- before the other callbacks (the multi-client and world boss guards)

-- ======================================================================== rewards
local function giveStack(player, id, count)
	local added = Chaos.giveItem(player, id, count)
	local rest = count - added
	if rest > 0 then
		local inbox = player:getInbox()
		while inbox and rest > 0 do
			local n = math.min(rest, 100)
			inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			rest = rest - n
		end
		return true
	end
	return false
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

function S.deliver(player, r)
	local inboxUsed = false
	if (r.bankGold or 0) > 0 then
		player:setBankBalance(player:getBankBalance() + r.bankGold)
	end
	local parts = {}
	for _, it in ipairs(r.items or {}) do
		inboxUsed = giveStack(player, it.id, it.count) or inboxUsed
		parts[#parts + 1] = it.count .. "x " .. itemName(it.id)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Guild siege reward (%s): %d gold to your bank%s%s.%s",
		r.kind == "winner" and "winner" or "participant", r.bankGold or 0, #parts > 0 and ", " or "", table.concat(parts, ", "),
		inboxUsed and " Your backpack was full: the rest is in your inbox." or ""))
	player:getPosition():sendMagicEffect(r.kind == "winner" and CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
end

-- ======================================================================== event flow
local finish

local function tick(token)
	if state.token ~= token or not active() then
		return
	end
	local now = os.time()
	local match = state.phase == "match"
	local counts = {}
	for b = 1, #state.brackets do
		counts[b] = {}
	end
	for guid, p in pairs(state.players) do
		local player = Player(p.name)
		if player and player:getGuid() == guid then
			local where, slot, b = locate(player:getPosition())
			p.inside = where ~= nil and b == p.bracket
			if p.inside then
				if match then
					p.presence = p.presence + 1
				end
				setSkullBack(player, p)
				if Chaos.isMultiClient(player) then
					sendOut(player, p, "Another character from your connection is online: you were sent out of the siege.")
				elseif match and where == "arena" and not p.downedUntil
						and S.onPoint(player:getPosition(), layoutOf(b), cfg.capture.radius) then
					counts[b][p.guildId] = (counts[b][p.guildId] or 0) + 1
					p.onPoint = true
				else
					p.onPoint = false
				end
			end
		else
			p.inside = false
		end
	end
	if match then
		for b, br in ipairs(state.brackets) do
			local holder, contested = S.control(counts[b], cfg.capture.exclusive)
			if holder ~= br.holder and holder then
				local t = br.teams[br.byGuild[holder]]
				for _, q in pairs(state.players) do
					local pl = q.bracket == b and q.inside and Player(q.name)
					if pl then
						pl:sendTextMessage(MESSAGE_STATUS_WARNING, t.name .. " took the Chaos Obelisk!")
					end
				end
				P(layoutOf(b).center):sendMagicEffect(CONST_ME_MAGIC_RED)
			end
			br.holder, br.contested = holder, contested
			if holder then
				local t = br.teams[br.byGuild[holder]]
				t.score = t.score + cfg.points.holdPerSecond
				t.hold = (t.hold or 0) + 1
				for _, q in pairs(state.players) do
					if q.bracket == b and q.guildId == holder and q.onPoint then
						q.points = q.points + cfg.points.holdPerSecond
					end
				end
			end
		end
	end
	for guid, p in pairs(state.players) do
		if p.inside then
			local player = Player(p.name)
			if player then
				sendHud(player, p)
			end
		end
	end
	if match and now >= state.endAt then
		finish("time")
		return
	end
	if match and ChaosInstanceLimits then -- warnings before the end (instance_limits.lua)
		local inside = {}
		for guid, p in pairs(state.players) do
			local player = p.inside and Player(p.name)
			if player and player:getGuid() == guid then
				inside[#inside + 1] = player
			end
		end
		ChaosInstanceLimits.warn(state, state.endAt - now, inside, "Guild siege", cfg.limits)
	end
	addEvent(tick, 1000, token)
end

local function beginMatch(token)
	if state.token ~= token or state.phase ~= "gather" then
		return
	end
	state.phase = "match"
	state.matchAt = os.time()
	state.endAt = os.time() + cfg.matchMinutes * 60
	if not cfg.lateJoin then
		closePortals()
	end
	for _, br in ipairs(state.brackets) do
		local L = br.L
		for slot in pairs(br.teams) do
			P(L.bases[slot].gate):sendMagicEffect(CONST_ME_MAGIC_BLUE)
		end
	end
	announce(string.format("GUILD SIEGE: the gates are open! %d minutes to hold the Chaos Obelisk and strike down your enemies.%s",
		cfg.matchMinutes, cfg.lateJoin and " The portals next to the temples stay open." or ""), true)
end

local function bracketText(br)
	local parts = {}
	for _, t in ipairs(br.standings or {}) do
		parts[#parts + 1] = string.format("%d. %s %d (%d kills)", t.place, t.name, t.score, t.kills)
	end
	return table.concat(parts, ", ")
end

local function closeOut(token)
	if state.token ~= token then
		return
	end
	for guid, p in pairs(state.players or {}) do
		local player = Player(p.name)
		if player and player:getGuid() == guid then
			if locate(player:getPosition()) then
				restore(player)
				sendOut(player, p)
			else
				leaveCleanup(player, p)
			end
		end
	end
	-- anyone else left inside (staff, people who logged in there)
	for _, player in ipairs(Game.getPlayers()) do
		if locate(player:getPosition()) then
			player:teleportTo(templeOf(player))
		end
	end
	for b = 1, #(state.brackets or {}) do
		cleanArena(b)
	end
	S.state = {phase = "idle", token = token + 1}
	state = S.state
	S.nextAt = S.nextStart(os.time(), cfg)
end

-- reason: "time" (normal end), "end" (staff: end now with results), "stop" (staff: cancel, no results)
finish = function(reason)
	if state.phase == "idle" or state.phase == "ending" then
		return false
	end
	state.phase = "ending"
	state.token = state.token + 1
	local token = state.token
	closePortals()
	local now = os.time()
	local delay = cfg.exitDelaySeconds
	if reason == "stop" then
		announce("The guild siege was cancelled by the staff.", true)
		delay = math.min(delay, 5)
	else
		local lines = {}
		local rewards = {}
		for b, br in ipairs(state.brackets) do
			br.standings = S.standings(bracketTeams(br))
			local win = S.winner(br.standings)
			br.winner = win and win.id or nil
			br.result = {winner = win and win.name or "", standings = {}}
			for _, t in ipairs(br.standings) do
				br.result.standings[#br.result.standings + 1] = {place = t.place, name = t.name, score = t.score, kills = t.kills, color = t.color}
				db.query(string.format("INSERT INTO `%s` (`siege_at`, `ended_at`, `bracket`, `guild_id`, `guild_name`, `place`, `winner`, `score`, `kills`, `hold_seconds`, `members`) VALUES (%d, %d, %d, %d, %s, %d, %d, %d, %d, %d, %d)",
					T_RESULTS, state.at, now, b, t.id, db.escapeString(t.name), t.place, (win and win.id == t.id) and 1 or 0,
					t.score, t.kills, t.hold or 0, t.joined or 0))
			end
			if win then
				S.champions[win.id] = {name = win.name, untilAt = now + (cfg.titleDays or 7) * 86400}
			end
			lines[#lines + 1] = (#state.brackets > 1 and ("Arena " .. b .. ": ") or "")
				.. (win and (win.name .. " wins! ") or "No winner. ") .. bracketText(br)
		end
		for guid, p in pairs(state.players) do
			local br = state.brackets[p.bracket]
			local kind, r = S.rewardFor(br.winner == p.guildId, p.presence, cfg)
			if kind then
				rewards[#rewards + 1] = {guid = guid, name = p.name, kind = kind, bankGold = r.bankGold, items = r.items}
			else
				local player = Player(p.name)
				if player then
					player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
						"No guild siege reward: you need %d seconds in the siege while the match runs (you had %d).",
						cfg.minPresenceSeconds or 0, p.presence))
				end
			end
			if ChaosLeaderboard and ChaosLeaderboard.record and cfg.leaderboard and (p.points > 0 or p.kills > 0) then
				pcall(ChaosLeaderboard.record, cfg.leaderboard, {guid = guid, name = p.name}, p.points, "add")
			end
		end
		for _, r in ipairs(rewards) do
			local player = Player(r.name)
			if player and player:getGuid() == r.guid then
				S.deliver(player, r)
			else
				S.pending[r.guid] = S.pending[r.guid] or {}
				table.insert(S.pending[r.guid], r)
			end
		end
		announce("GUILD SIEGE OVER" .. (reason == "end" and " (ended by the staff)" or "") .. ": " .. table.concat(lines, " | ")
			.. string.format(" Everyone inside returns home in %d seconds.", delay), true)
		db.query(string.format("DELETE FROM `%s` WHERE `siege_at` = %d", T_SIGNUPS, state.at))
		for guid, p in pairs(state.players) do
			local player = Player(p.name)
			if player and player:getGuid() == guid and p.inside then
				sendHud(player, p)
			end
		end
	end
	addEvent(closeOut, delay * 1000, token)
	return true
end

-- forced = staff start (uses the sign-ups of the upcoming siege). Returns true or false + reason.
function S.start(forced)
	if active() then
		return false, "a siege is already running"
	end
	local at = S.upcoming()
	local signups = signupsFor(at)
	local guilds = {}
	for i, r in ipairs(signups) do
		guilds[#guilds + 1] = {id = r.guild_id, name = r.guild_name, order = i}
	end
	local brackets, waiting = S.brackets(guilds, cfg)
	if #brackets == 0 then
		return false, string.format("not enough guilds signed up (%d, at least %d needed)", #guilds, cfg.minGuilds or 2)
	end
	for b = 1, #brackets do
		local ok, err = S.buildArena(b)
		if not ok then
			return false, "arena " .. b .. " not built: " .. err
		end
	end
	local token = state.token + 1
	S.state = {phase = "gather", token = token, at = at, forced = forced or false, startedAt = os.time(),
		matchAt = os.time() + cfg.gatherSeconds, brackets = {}, players = {}, guildBracket = {}, portals = {}}
	state = S.state
	for b, list in ipairs(brackets) do
		local br = {L = layoutOf(b), teams = {}, byGuild = {}}
		for slot, g in ipairs(list) do
			br.teams[slot] = {id = g.id, name = g.name, order = g.order, slot = slot, score = 0, kills = 0, hold = 0, joined = 0,
				color = cfg.colors[slot], side = cfg.sides[slot]}
			br.byGuild[g.id] = slot
			state.guildBracket[g.id] = b
		end
		state.brackets[b] = br
	end
	local n = openPortals()
	if n == 0 then
		log("no portal spot found (Game.getTowns / portalPositions); staff can place one with /siege portal")
	end
	local names = {}
	for _, g in ipairs(guilds) do
		if state.guildBracket[g.id] then
			names[#names + 1] = g.name
		end
	end
	announce(string.format("GUILD SIEGE: %s march on the Chaos Obelisk! Members (level %d+): enter through the portals next to the temples. The gates open in %d seconds.",
		table.concat(names, ", "), cfg.minLevel, cfg.gatherSeconds), true)
	if #waiting > 0 then
		local w = {}
		for _, g in ipairs(waiting) do
			w[#w + 1] = g.name
		end
		announce("No room in this siege for: " .. table.concat(w, ", ") .. ".", false)
	end
	addEvent(beginMatch, cfg.gatherSeconds * 1000, token)
	addEvent(tick, 1000, token)
	return true
end

function S.stop()
	return finish("stop")
end

function S.endNow()
	if state.phase == "gather" then
		state.matchAt = os.time()
		state.phase = "match"
		state.endAt = os.time()
	end
	return finish("end")
end

function S.matchNow()
	if state.phase ~= "gather" then
		return false
	end
	beginMatch(state.token)
	return true
end

function S.status()
	if state.phase == "idle" then
		local at = S.upcoming()
		local list = signupsFor(at)
		local names = {}
		for _, r in ipairs(list) do
			names[#names + 1] = r.guild_name
		end
		return string.format("Next guild siege: %s (in %s). Signed up (%d/%d): %s.%s", S.whenText(at),
			S.durationText(at - os.time()), #list, S.capacity(cfg), #names > 0 and table.concat(names, ", ") or "nobody yet",
			S.signupsOpen(os.time(), at, cfg) and "" or " Sign-ups are closed.")
	end
	if state.phase == "gather" then
		return string.format("The guild siege is gathering: the gates open in %d seconds. Portals are next to the temples.",
			math.max(0, state.matchAt - os.time()))
	elseif state.phase == "match" then
		local parts = {}
		for b, br in ipairs(state.brackets) do
			local list = S.standings(bracketTeams(br))
			local t = {}
			for _, x in ipairs(list) do
				t[#t + 1] = x.name .. " " .. x.score
			end
			parts[#parts + 1] = table.concat(t, ", ")
		end
		return string.format("The guild siege is on (%s left): %s.", S.clock(state.endAt - os.time()), table.concat(parts, " | "))
	end
	return "The guild siege is ending."
end

-- ======================================================================== the window (client game_siege)
function S.sendInfo(player, open)
	local info, list, at = signupInfo(player)
	local signups = {}
	for _, r in ipairs(list) do
		signups[#signups + 1] = {name = r.guild_name, own = r.guild_id == info.guildId}
	end
	local champions = {}
	local now = os.time()
	for id, c in pairs(S.champions) do
		if c.untilAt > now then
			champions[#champions + 1] = {name = c.name, untilText = os.date("%a %d %b %H:%M", c.untilAt)}
		end
	end
	local joinErr = S.signupError(info, cfg)
	local leaveErr = S.leaveError(info, cfg)
	Chaos.send(player, OPCODE, "info", {
		open = open or false, phase = state.phase, at = at, whenText = S.whenText(at), inSeconds = math.max(0, at - now),
		signupsOpen = info.open and not info.running, signups = signups, capacity = S.capacity(cfg),
		guild = info.guildName or "", rank = info.rank, signed = info.signed, members = info.members,
		canJoin = joinErr == nil, joinReason = joinErr or "", canLeave = leaveErr == nil and info.signed,
		champions = champions, status = S.status(),
		rules = {
			string.format("Every %s at %02d:%02d server time: %s of gathering, then a %d-minute war for the Chaos Obelisk.",
				S.WEEKDAYS[cfg.weekday], cfg.hour, cfg.minute, cfg.gatherSeconds >= 120 and (math.floor(cfg.gatherSeconds / 60) .. " minutes")
				or (cfg.gatherSeconds .. " seconds"), cfg.matchMinutes),
			string.format("The guild leader or a vice-leader signs up in the Guild Siege window; the guild needs %d members. Up to %d guilds per arena, %d arenas.",
				cfg.minMembers, cfg.perBracket, cfg.maxBrackets),
			string.format("Members (level %d+) enter through the portals next to the temples. Multi-clienting characters cannot take part.", cfg.minLevel),
			string.format("%d points per enemy struck down, %d per second for the guild with the most members on the obelisk (a tie contests it).",
				cfg.points.kill, cfg.points.holdPerSecond),
			"No real deaths: no skulls, frags, experience or item loss. A downed player wakes up in the guild's base.",
			string.format("Winners: %s for %d days (look text, +%d%% experience from monsters) and %d gold + orbs each; everyone else who fought gets %d gold + orbs.",
				cfg.title, cfg.titleDays, math.floor(cfg.buff.xp * 100 + 0.5), cfg.reward.winner.bankGold, cfg.reward.others.bankGold)
		}
	})
end

local ext = CreatureEvent("ChaosSiegeExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return true
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return true
	end
	-- per action (ratelimit.lua): requests that hit the database cannot be flooded
	if Chaos.limited and Chaos.limited(player, "siege." .. tostring(msg.action), 300) then
		return true
	end
	if msg.action == "open" then
		S.sendInfo(player, true)
	elseif msg.action == "join" or msg.action == "leave" then
		local ok, text = (msg.action == "join" and S.join or S.leave)(player)
		player:sendTextMessage(ok and MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL, text)
		S.sendInfo(player, false)
	end
	return true
end
ext:register()

-- ======================================================================== engine hooks
local death = CreatureEvent("ChaosSiegeDeath")
function death.onPrepareDeath(creature, killer)
	local player = creature:getPlayer()
	local p = player and part(player)
	if not p or not active() then
		return true
	end
	local where, _, b = locate(player:getPosition())
	if not where or b ~= p.bracket then
		return true
	end
	if p.downedUntil then
		return false
	end
	downed(player, p, killer)
	return false
end
death:register()

-- the engine gives the attacker a white skull on every hit on an unmarked player (Player::onAttackedCreature, before
-- the target's health changes); it is taken back here at once, and every second by the tick
local hit = CreatureEvent("ChaosSiegeHealth")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local a = playerOf(attacker)
	local ap = a and part(a)
	if ap and ap.inside then
		setSkullBack(a, ap)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

local login = CreatureEvent("ChaosSiegeLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSiegeExtended")
	local guid = player:getGuid()
	local list = S.pending[guid]
	if list then
		S.pending[guid] = nil
		addEvent(function(name, rewards)
			local p = Player(name)
			if p then
				for _, r in ipairs(rewards) do
					S.deliver(p, r)
				end
			else
				S.pending[guid] = rewards
			end
		end, 2000, player:getName(), list)
	end
	local p = part(player)
	if active() and p and state.phase ~= "ending" and locate(player:getPosition()) then
		player:registerEvent("ChaosSiegeDeath")
		player:registerEvent("ChaosSiegeHealth")
		toBase(player, p)
		p.inside = true
		sendHud(player, p)
	elseif locate(player:getPosition()) then
		player:teleportTo(templeOf(player))
	end
	return true
end
login:register()

-- champion title in the look text (after the base server's default_onLook, index 0)
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() then
		local guild = thing:getGuild()
		local c = guild and S.championOf(S.champions, guild:getId(), os.time())
		if c then
			local you = thing:getId() == self:getId()
			local pronoun = you and "You" or (thing:getSex() == PLAYERSEX_FEMALE and "She" or "He")
			description = (description or "") .. string.format("\n%s %s one of the %s (%s).", pronoun, you and "are" or "is", cfg.title, c.name)
		end
	end
	return description
end
look:register(110)

-- champion guild buff: experience from monsters
local xp = EventCallback
xp.onGainExperience = function(self, source, exp, rawExp)
	if (cfg.buff.xp or 0) > 0 and source and source:isMonster() then
		local guild = self:getGuild()
		if guild and S.championOf(S.champions, guild:getId(), os.time()) then
			return math.floor(exp * (1 + cfg.buff.xp))
		end
	end
	return exp
end
xp:register()

-- ======================================================================== forcefields
local function pushBack(player, fromPosition, text)
	player:sendCancelMessage(text)
	player:teleportTo(fromPosition, true)
end

local enter = MoveEvent()
function enter.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	if not (state.phase == "gather" or state.phase == "match") or not state.portalsOpen then
		pushBack(player, fromPosition, "The siege portal is closed.")
		return true
	end
	local guildId, guildName = guildOf(player)
	local b = guildId and state.guildBracket[guildId]
	if not b then
		pushBack(player, fromPosition, guildId and (guildName .. " is not signed up for this siege.") or "Only members of a signed-up guild can enter the siege.")
		return true
	end
	if player:getLevel() < cfg.minLevel then
		pushBack(player, fromPosition, string.format("You need level %d to join the siege.", cfg.minLevel))
		return true
	end
	if Chaos.isMultiClient(player) then
		pushBack(player, fromPosition, "Multi-client: another character from your connection is online. Log it out to join the siege.")
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You cannot join the guild siege while another character from your connection is online (multi-client). Log the other character out first.")
		return true
	end
	local br = state.brackets[b]
	local slot = br.byGuild[guildId]
	if (cfg.maxPerGuild or 0) > 0 and insideCount(b, guildId) >= cfg.maxPerGuild then
		pushBack(player, fromPosition, string.format("%s already has %d members inside.", guildName, cfg.maxPerGuild))
		return true
	end
	local guid = player:getGuid()
	local p = state.players[guid]
	if not p then
		p = {guid = guid, name = player:getName(), guildId = guildId, bracket = b, slot = slot, presence = 0, kills = 0,
			deaths = 0, points = 0}
		state.players[guid] = p
		br.teams[slot].joined = br.teams[slot].joined + 1
	elseif p.guildId ~= guildId then
		pushBack(player, fromPosition, "You fought for another guild in this siege.")
		return true
	end
	p.entrySkull = player:getSkull()
	p.inside = true
	player:registerEvent("ChaosSiegeDeath")
	player:registerEvent("ChaosSiegeHealth")
	toBase(player, p)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"Guild siege: this is the %s base of %s. %s Turn your secure mode off to attack. The forcefield at the back of the room leads home.",
		cfg.sides[slot]:lower(), guildName, state.phase == "gather" and string.format("The gate opens in %d seconds.", math.max(0, state.matchAt - os.time()))
			or "The gate leads into the arena."))
	sendHud(player, p)
	return true
end
enter:type("stepin")
enter:aid(cfg.aid.enter)
enter:register()

local gate = MoveEvent()
function gate.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local p = part(player)
	local where, slot, b = locate(position)
	-- refused: back to the player's own base, else to the base of this gate (fromPosition is not reliable after a
	-- teleport onto the gate)
	local back = fromPosition
	if p and p.bracket then
		back = P(layoutOf(p.bracket).bases[p.slot].spawn)
	elseif where == "base" and b then
		back = P(layoutOf(b).bases[slot].spawn)
	end
	if not p or not active() or p.bracket ~= b or p.slot ~= slot then
		pushBack(player, back, "This gate is not yours.")
		return true
	end
	if state.phase == "gather" then
		pushBack(player, back, string.format("The gate opens in %d seconds.", math.max(0, state.matchAt - os.time())))
		return true
	end
	if p.downedUntil then
		pushBack(player, back, "You are still recovering.")
		return true
	end
	if state.phase ~= "match" then
		pushBack(player, back, "The siege is over.")
		return true
	end
	player:teleportTo(P(layoutOf(b).bases[slot].out))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
gate:type("stepin")
gate:aid(cfg.aid.gate)
gate:register()

local exit = MoveEvent()
function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	sendOut(player, part(player), active() and "You left the siege. A portal next to the temple takes you back while it is open." or nil)
	return true
end
exit:type("stepin")
exit:aid(cfg.aid.exit)
exit:register()

-- ======================================================================== schedule
local warned = {}
local schedule = GlobalEvent("ChaosSiegeSchedule")
function schedule.onThink(interval)
	if not cfg.enabled then
		return true
	end
	local now = os.time()
	local at = S.upcoming()
	if active() then
		return true
	end
	for i, m in ipairs(cfg.warnMinutes or {}) do
		local key = at .. ":" .. m
		if not warned[key] and now >= at - m * 60 and now < at then
			warned[key] = true
			local list = signupsFor(at)
			local names = {}
			for _, r in ipairs(list) do
				names[#names + 1] = r.guild_name
			end
			announce(string.format("The guild siege begins in %d minute(s)! Signed up: %s.%s", m,
				#names > 0 and table.concat(names, ", ") or "nobody",
				#names < (cfg.minGuilds or 2) and string.format(" At least %d guilds are needed: leaders, sign up in Adventure > Guild Siege.", cfg.minGuilds or 2) or ""),
				i == 1 or i == #cfg.warnMinutes)
		end
	end
	if now >= at then
		local ok, err = S.start(false)
		if not ok then
			announce("The guild siege of " .. S.whenText(at) .. " is cancelled: " .. tostring(err) .. ".", false)
			db.query(string.format("DELETE FROM `%s` WHERE `siege_at` = %d", T_SIGNUPS, at))
			S.nextAt = S.nextStart(now, cfg)
		end
	end
	return true
end
schedule:interval(10000)
schedule:register()

local startup = GlobalEvent("ChaosSiegeStartup")
function startup.onStartup()
	S.nextAt = S.nextStart(os.time(), cfg)
	-- sign-ups of a siege that passed while the server was down are dropped
	db.query(string.format("DELETE FROM `%s` WHERE `siege_at` < %d", T_SIGNUPS, os.time() - 3600))
	loadChampions()
	local n = 0
	for _ in pairs(S.champions) do
		n = n + 1
	end
	log(string.format("next siege %s, %d champion guild(s)", os.date("%Y-%m-%d %H:%M", S.nextAt), n))
	return true
end
startup:register()

-- ======================================================================== commands

local gm = TalkAction("/siege")
function gm.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local cmd, arg = param:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	local function say(text)
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
	if cmd == "start" then
		local ok, err = S.start(true)
		say(ok and "Guild siege started (gathering)." or ("Not started: " .. tostring(err)))
	elseif cmd == "match" then
		say(S.matchNow() and "The gates are open." or "The siege is not gathering.")
	elseif cmd == "end" then
		say(S.endNow() and "Guild siege ended with results." or "No guild siege is running.")
	elseif cmd == "stop" then
		say(S.stop() and "Guild siege cancelled." or "No guild siege is running.")
	elseif cmd == "portal" then
		if not active() then
			say("No guild siege is running.")
		else
			local pos = player:getPosition()
			local spot = Position(pos.x + 2, pos.y, pos.z)
			say(addPortal(spot) and "Siege portal placed two tiles east of you." or "No portal placed.")
			state.portalsOpen = true
		end
	elseif cmd == "arena" then
		local b = tonumber(arg) or 1
		local ok, err = S.buildArena(b)
		if not ok then
			say("Arena not built: " .. tostring(err))
		else
			local c = layoutOf(b).center
			player:teleportTo(Position(c.x, c.y + 3, c.z))
		end
	elseif cmd == "signup" then
		local name = arg
		local rows = Chaos.select("SELECT `id`, `name` FROM `guilds` WHERE `name` = " .. db.escapeString(name), {{"id", "n"}, {"name", "s"}})
		if not rows[1] then
			say("No guild named " .. name .. ".")
		else
			local at = S.upcoming()
			db.query(string.format("INSERT IGNORE INTO `%s` (`siege_at`, `guild_id`, `guild_name`, `signed_by`, `signed_at`) VALUES (%d, %d, %s, %d, %d)",
				T_SIGNUPS, at, rows[1].id, db.escapeString(rows[1].name), player:getGuid(), os.time()))
			say(rows[1].name .. " signed up for " .. S.whenText(at) .. " (staff, no rule checks).")
		end
	elseif cmd == "clear" then
		db.query(string.format("DELETE FROM `%s` WHERE `siege_at` = %d", T_SIGNUPS, S.upcoming()))
		say("Sign-ups for " .. S.whenText(S.upcoming()) .. " cleared.")
	else
		say(S.status() .. "\nUsage: /siege start | match | end | stop | portal | arena [n] | signup <guild> | clear")
	end
	return false
end
gm:separator(" ")
gm:register()
