-- Tester bots, pure rules (testers.lua, server/README.md "Tester bots"; tests/testers_test.lua).
--
-- A tester is a character with the player storage Chaos.storage.tester = 1, written only by server/tools/testers.py
-- setup, named "Tester Xxx", in group 1 on an account of type 1. These rules keep the testers apart from the players:
--   K.safetyProblem(group, accountType)   why a tester may not enter (staff group or staff account), or nil
--   K.isTesterName(name)                  the name pattern of testers.py ("Tester " and three letters)
--   K.mentions(text, names)               a text names one of these testers (broadcasts, Discord events are dropped)
--   K.mixed(aTester, bTester)             a tester and a player together (combat, trade, party: refused)
--   K.marketBlocked(action)               the market actions that move items or gold between characters
--   K.mailBlocked(fromTester, receiver)   a parcel or letter a tester sends, or one sent to a tester's name: the text
--   K.receiverOf(text)                    the receiver of a label or letter text (its first line, trimmed)
--   K.lookLine(isSelf)                    the line every look at a tester adds
-- Closed test mode (O582, server/README.md "Closed test mode"): the bots play arena, battleground, PvP, guild, guild war,
-- market, bazaar, the raid, the dungeons, the group queue and the party finder among themselves, never with a player. The switch is the file data/chaos_testers_closed
-- (chaos-ctl.sh testers closed on | off); anything but the word "on" in it, no file or a read that fails is OFF. Rules:
--   K.parseClosed(text)                   true only for the word "on" (trimmed, any case)
--   K.closedOn()                          the file, read at most every K.CLOSED_TTL seconds (K.reader / K.clock replace io / os.time)
--   K.sideOf(flags)                       "tester" when every party is a tester, "player" when none is, nil when mixed or empty
--   K.sameSide(system, closedOn, a, b)    ok, why: two sides of one match / war / trade, THE guard of every closed-mode pairing
--   K.joinRefusal(system, closedOn, flags) the reason a group of parties may not enter a queue, or nil
--   K.guildSide(name, anyTester, allTester) the side of a guild: "tester" (name starts "Tester ", every member a tester),
--                                         "player" (no tester member), nil (mixed, empty, or a tester in a player's guild)
--   K.guildBlocked(isTester, name, anyTester, allTester, closedOn)  a character may not use this guild (reason) or nil
--   K.marketRealm(isTester, realm)        a tester trades in its own book (K.REALM), a player in its own realm
--   K.marketRefusal(action, isTester, closedOn)  the refusal of a market action of a tester, or nil
--   K.marketCoinsOk(realm)                the tester book trades gold only
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosTestersCore = ChaosTestersCore or {}
local K = ChaosTestersCore

K.PREFIX = "Tester "
K.TITLE = "TESTER"
K.TITLE_COLOR = "#ff5a3c"
K.TITLE_PRIORITY = 1000 -- above every other title: the plate always says TESTER
K.MARKET_BLOCKED = {buy = true, list = true, orderPost = true, fill = true}
K.REALM = 900000001 -- the market, battleground and guild war realm of the testers: no season has this id
K.CLOSED_FILE = "data/chaos_testers_closed"
K.CLOSED_TTL = 5 -- seconds a read of the file is kept
K.GUILD_PREFIX = "Tester " -- a tester guild's name starts with it
K.GUILD_MARK = "Tester Guild " -- the names of the guilds testers.py makes ("Tester Guild Alfa"): never in a broadcast or Discord event
K.CLOSED_SYSTEMS = {arena = true, battleground = true, pvp = true, guild = true, guildwar = true, market = true, bazaar = true, raid = true, dungeon = true,
	groupqueue = true, partyfinder = true}

function K.safetyProblem(group, accountType)
	group, accountType = tonumber(group) or 0, tonumber(accountType) or 0
	if group ~= 1 then
		return string.format("group %d (a tester is always group 1, never staff)", group)
	end
	if accountType > 1 then
		return string.format("account type %d (a tester's account is always type 1)", accountType)
	end
	return nil
end

function K.isTesterName(name)
	return type(name) == "string" and name:match("^Tester [A-Z][a-z][a-z]$") ~= nil
end

-- names: a set {name = true} or a list of names
function K.mentions(text, names)
	if type(text) ~= "string" or text == "" or type(names) ~= "table" then
		return false
	end
	if not text:find(K.PREFIX, 1, true) then
		return false
	end
	if text:find(K.GUILD_MARK, 1, true) then
		return true
	end
	for k, v in pairs(names) do
		local name = type(k) == "string" and k or v
		if type(name) == "string" and name ~= "" and text:find(name, 1, true) then
			return true
		end
	end
	return false
end

-- every string of a table (a Discord event: kind, title, text, fields ...), one level of nesting
function K.mentionsAny(value, names, depth)
	if type(value) == "string" then
		return K.mentions(value, names)
	end
	if type(value) ~= "table" or (depth or 0) > 3 then
		return false
	end
	for _, v in pairs(value) do
		if K.mentionsAny(v, names, (depth or 0) + 1) then
			return true
		end
	end
	return false
end

function K.mixed(aTester, bTester)
	return (aTester and true or false) ~= (bTester and true or false)
end

function K.marketBlocked(action)
	return K.MARKET_BLOCKED[action] == true
end

-- the base mailboxes (items.xml type "mailbox"), parcels and letters (stamped or not) and the parcel label
K.MAILBOXES = {[2593] = true, [3981] = true, [26055] = true, [26056] = true, [26057] = true}
K.MAIL_ITEMS = {[2595] = "parcel", [2596] = "parcel", [2597] = "letter", [2598] = "letter"}
K.LABEL = 2599

function K.receiverOf(text)
	if type(text) ~= "string" then
		return nil
	end
	local line = text:match("^[^\n]*")
	line = line and line:match("^%s*(.-)%s*$")
	return line ~= "" and line or nil
end

function K.mailBlocked(fromTester, receiver)
	if fromTester then
		return "Tester characters cannot send mail."
	end
	if receiver and K.isTesterName(receiver) then
		return "Mail to tester characters is not delivered."
	end
	return nil
end

-- ------------------------------------------------------------------ closed test mode (O582)
function K.parseClosed(text)
	if type(text) ~= "string" then
		return false
	end
	local word = text:match("^%s*(%a+)%s*$")
	return word ~= nil and word:lower() == "on"
end

K.reader = nil -- tests: function() return text end
K.clock = nil -- tests: function() return seconds end
local cache = {at = nil, value = false}

function K.closedOn()
	local now = (K.clock or os.time)()
	if cache.at and now - cache.at < K.CLOSED_TTL and now >= cache.at then
		return cache.value
	end
	local ok, text = pcall(function()
		if K.reader then
			return K.reader()
		end
		local f = io.open(K.CLOSED_FILE, "r")
		if not f then
			return nil
		end
		local t = f:read(64)
		f:close()
		return t
	end)
	cache.value = ok and K.parseClosed(text) or false
	cache.at = now
	return cache.value
end

function K.resetClosedCache()
	cache.at, cache.value = nil, false
end

-- flags: a list of booleans (true = a tester); a non-boolean entry is unknown and makes the side nil
function K.sideOf(flags)
	if type(flags) ~= "table" or #flags == 0 then
		return nil
	end
	local testers, players = 0, 0
	for i = 1, #flags do
		if flags[i] == true then
			testers = testers + 1
		elseif flags[i] == false then
			players = players + 1
		else
			return nil
		end
	end
	if testers > 0 and players > 0 then
		return nil
	end
	return testers > 0 and "tester" or "player"
end

local function sideRefusal(system, closedOn, side)
	if side == nil then
		return "mixed"
	end
	if side == "tester" and not (closedOn == true and K.CLOSED_SYSTEMS[system]) then
		return "closed-off"
	end
	return nil
end

-- the two sides of one pairing: both known, equal, and a tester pairing only in closed mode
function K.sameSide(system, closedOn, a, b)
	local why = sideRefusal(system, closedOn, a) or sideRefusal(system, closedOn, b)
	if why then
		return false, why
	end
	if a ~= b then
		return false, "apart"
	end
	return true
end

function K.joinRefusal(system, closedOn, flags)
	return sideRefusal(system, closedOn, K.sideOf(flags))
end

K.CLOSED_TEXT = {
	["closed-off"] = "Closed test mode is off: the testers do not play this.",
	mixed = "Testers and players are never mixed.",
	apart = "Testers and players are never mixed."
}

function K.guildSide(name, anyTester, allTester)
	local prefixed = type(name) == "string" and name:sub(1, #K.GUILD_PREFIX) == K.GUILD_PREFIX
	if allTester == true and anyTester == true then
		return prefixed and "tester" or nil
	end
	if anyTester == false then
		return "player"
	end
	return nil
end

-- why a character may not use a guild, or nil: a tester only in a tester guild (and only in closed mode), a player never in one
function K.guildBlocked(isTester, name, anyTester, allTester, closedOn)
	local side = K.guildSide(name, anyTester, allTester)
	if side == nil then
		if isTester then
			return "mixed"
		end
		local prefixed = type(name) == "string" and name:sub(1, #K.GUILD_PREFIX) == K.GUILD_PREFIX
		return (prefixed and anyTester ~= false) and "mixed" or nil
	end
	if isTester then
		if side ~= "tester" then
			return "apart"
		end
		if closedOn == true then
			return nil
		end
		return "closed-off"
	end
	return side == "tester" and "apart" or nil
end

function K.marketRealm(isTester, realm)
	if isTester then
		return K.REALM
	end
	return realm
end

function K.marketRefusal(action, isTester, closedOn)
	if isTester and K.marketBlocked(action) and closedOn ~= true then
		return "Tester characters cannot trade on the market."
	end
	return nil
end

function K.marketCoinsOk(realm)
	return realm ~= K.REALM
end

function K.lookLine(isSelf)
	if isSelf then
		return "You are a TESTER: an automatic test character of the staff."
	end
	return "TESTER: an automatic test character of the staff. It plays to find bugs and is not a player."
end

return K
