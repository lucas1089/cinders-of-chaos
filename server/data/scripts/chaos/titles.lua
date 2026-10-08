-- Titles: one registry every system adds its titles to; the active one is shown on the name plate (nameplate.lua).
--
--   ChaosTitles.register(source, fn)   fn(player) -> list of titles the player holds now (or one, or nil)
--       a title: {text, key?, color?, at?, frame?, priority?}
--         text      what the plate shows ("Bossbane"); at most 24 characters
--         key       stable id, used by !title and stored as the player's choice; default "<source>:<text in lower case>"
--         color     "#RRGGBB"; default ChaosNameplate.COLORS[source] (staff red, leaderboard gold, champion orange,
--                   season violet, arena steel blue, streak green, achievement teal)
--         at        os.time the title was earned: the default active title is the newest (staff titles come first)
--         frame     plate frame while the title is active ("gold", "crimson", "violet", "frost"; see N.FRAMES)
--       Registering the same source again replaces it, so a script reloaded with /reload does not add it twice.
--       Call ChaosNameplate.refresh(player) after granting a title to show it at once (otherwise within a few seconds).
--   ChaosTitles.unregister(source)
--   ChaosTitles.registerFrame(source, fn)  cosmetic plate frames: fn(player) -> frame id or nil (store, seasons);
--                                          the first source that answers wins over the title's frame
--   ChaosTitles.of(player)             every title the player holds, sorted (staff first, then newest)
--   ChaosTitles.frameOf(player)        cosmetic frame id or nil
--
-- Sources registered here (each reads the other system's tables at call time and does nothing while it is not loaded):
--   staff        the player's group: Tutor, Senior Tutor, Game Master, Community Manager, Administrator
--   leaderboard  weekly top 3 titles held this week (ChaosLeaderboard.titlesOf, leaderboard.lua)
--   champion     "Siege Champions" while the player's guild holds the title (ChaosSiege.champions, siege.lua)
--   season       season title rewards of the account (ChaosSeason.titlesOf, season.lua)
--   streak       the login-streak milestone title of the account (ChaosDaily.accounts, ChaosDailyCore.titleFor, daily.lua)
-- Arena titles and achievements register themselves the same way.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosNameplate or not ChaosNameplate.collect then
	dofile("data/scripts/chaos/nameplate_core.lua")
end

ChaosTitles = ChaosTitles or {}
local T = ChaosTitles
local N = ChaosNameplate

T.sources = T.sources or {} -- ordered list of {name, fn}
T.frames = T.frames or {} -- ordered list of {name, fn}

-- staff group id -> title (groups.xml: 2 tutor, 3 senior tutor, 4 gamemaster, 5 community manager, 6 god)
T.staffTitles = {[2] = "Tutor", [3] = "Senior Tutor", [4] = "Game Master", [5] = "Community Manager", [6] = "Administrator"}

local function put(list, name, fn)
	for _, s in ipairs(list) do
		if s.name == name then
			s.fn = fn
			return
		end
	end
	list[#list + 1] = {name = name, fn = fn}
end

local function drop(list, name)
	for i = #list, 1, -1 do
		if list[i].name == name then
			table.remove(list, i)
		end
	end
end

function T.register(source, fn)
	assert(type(source) == "string" and type(fn) == "function", "ChaosTitles.register(source, fn)")
	put(T.sources, source, fn)
end

function T.unregister(source)
	drop(T.sources, source)
end

function T.registerFrame(source, fn)
	assert(type(source) == "string" and type(fn) == "function", "ChaosTitles.registerFrame(source, fn)")
	put(T.frames, source, fn)
end

local function logError(name, err)
	print(string.format("[ChaosTitles] source %s failed: %s", tostring(name), tostring(err)))
end

function T.of(player)
	return N.collect(T.sources, player, logError)
end

function T.frameOf(player)
	for _, s in ipairs(T.frames) do
		local ok, id = pcall(s.fn, player)
		if ok and id and N.FRAMES[id] then
			return id
		end
	end
	return nil
end

-- ---------------------------------------------------------------- built-in sources
T.register("staff", function(player)
	local text = T.staffTitles[player:getGroup():getId()]
	return text and {key = "staff", text = text} or nil
end)

T.register("leaderboard", function(player)
	local LB = ChaosLeaderboard
	local held = LB and LB.titlesOf and LB.titlesOf(player:getGuid())
	if not held then
		return nil
	end
	-- earned at the weekly reset that started the current week
	local at = 0
	local cfg = Chaos.leaderboardConfig
	if LB.held and LB.weekStart and cfg then
		at = LB.weekStart(LB.held.week, cfg.resetHour) + 7 * 86400
	end
	local out = {}
	for _, t in ipairs(held) do
		out[#out + 1] = {key = "leaderboard:" .. tostring(t.board), text = t.title, at = at}
	end
	return out
end)

T.register("champion", function(player)
	local S = ChaosSiege
	local guild = player:getGuild()
	if not (S and S.champions and S.championOf and guild) then
		return nil
	end
	local c = S.championOf(S.champions, guild:getId(), os.time())
	if not c then
		return nil
	end
	local cfg = Chaos.siegeConfig or {}
	return {key = "champion:siege", text = cfg.title or "Siege Champions", at = (c.untilAt or 0) - (cfg.titleDays or 7) * 86400}
end)

T.register("season", function(player)
	local S = ChaosSeason
	if not (S and S.titlesOf) then
		return nil
	end
	local out = {}
	for _, t in ipairs(S.titlesOf(player:getAccountId()) or {}) do
		out[#out + 1] = {text = t.title, at = t.at}
	end
	return out
end)

T.register("streak", function(player)
	local DY, DC, cfg = ChaosDaily, ChaosDailyCore, Chaos.dailyStreak
	if not (DY and DY.accounts and DC and DC.titleFor and cfg) then
		return nil
	end
	local rec = DY.accounts[player:getAccountId()]
	local text, days = DC.titleFor(cfg, rec and rec.best or 0)
	return text and {key = "streak:" .. tostring(days), text = text} or nil
end)
