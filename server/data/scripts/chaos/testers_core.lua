-- Tester bots, pure rules (testers.lua, server/README.md "Tester bots"; tests/testers_test.lua).
--
-- A tester is a character with the player storage Chaos.storage.tester = 1, written only by server/tools/testers.py
-- setup, named "Tester Xxx", in group 1 on an account of type 1. These rules keep the testers apart from the players:
--   K.safetyProblem(group, accountType)   why a tester may not enter (staff group or staff account), or nil
--   K.isTesterName(name)                  the name pattern of testers.py ("Tester " and three letters)
--   K.mentions(text, names)               a text names one of these testers (broadcasts, Discord events are dropped)
--   K.mixed(aTester, bTester)             a tester and a player together (combat, trade, party: refused)
--   K.marketBlocked(action)               the market actions that move items or gold between characters
--   K.lookLine(isSelf)                    the line every look at a tester adds
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosTestersCore = ChaosTestersCore or {}
local K = ChaosTestersCore

K.PREFIX = "Tester "
K.TITLE = "TESTER"
K.TITLE_COLOR = "#ff5a3c"
K.TITLE_PRIORITY = 1000 -- above every other title: the plate always says TESTER
K.MARKET_BLOCKED = {buy = true, list = true, orderPost = true, fill = true}

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

function K.lookLine(isSelf)
	if isSelf then
		return "You are a TESTER: an automatic test character of the staff."
	end
	return "TESTER: an automatic test character of the staff. It plays to find bugs and is not a player."
end

return K
