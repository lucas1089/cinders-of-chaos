-- Run from the server/ folder: luajit tests/no_player_talkactions_test.lua (and lua5.3; CI runs both).
-- Owner rule: players get no chat commands except !bless (gentledeath.lua, words in gentledeath_config.lua). Every
-- other TalkAction under data/ must be a staff command on the allowlist below, and its onSay (or the function it hands
-- the call to) must check staff rights in its first lines, so for a player the words are plain chat. A new talkaction
-- fails here until it is added to the allowlist with a guard; a player feature goes into a client window instead
-- (server/README.md "Player commands: the menu"). Static: the sources are read, nothing is loaded.
local checks, fails = 0, {}
local function check(cond, msg)
	checks = checks + 1
	if not cond then
		fails[#fails + 1] = msg
	end
end

-- word -> file (relative to data/scripts/chaos). Staff only: each one checks the group, the access flag, the account
-- type or Chaos.staffCommand first.
local STAFF = {
	["/achievements"] = "achievements.lua", ["/testkit"] = "admin/testkit.lua", ["/areagen"] = "areagen.lua",
	["/arena"] = "arena.lua", ["/ascendset"] = "ascension_quest.lua", ["/atlas"] = "atlas.lua",
	["/bg"] = "battleground.lua", ["/blessing"] = "blessings.lua", ["/botreview"] = "botreview.lua",
	["/candlemarks"] = "candlemarks.lua", ["/charm"] = "charms.lua", ["/chronicle"] = "chronicle.lua",
	["/classunlock"] = "class_unlocks.lua", ["/community"] = "community.lua", ["/conquest"] = "conquest.lua",
	["/cosmetic"] = "cosmetics.lua", ["/creatorcodes"] = "creator_codes.lua", ["/daily"] = "daily.lua",
	["/descent"] = "descent.lua", ["/exclusive"] = "exclusives.lua", ["/faction"] = "factions.lua",
	["/gamble"] = "gamble.lua", ["/guild"] = "guild.lua", ["/guildboss"] = "guildboss.lua",
	["/guildwar"] = "guildwar.lua", ["/harvest"] = "harvest_event.lua", ["/hideout"] = "hideout.lua", ["/towerrun"] = "infinitytower.lua",
	["/towerseason"] = "infinitytower.lua", ["/instances"] = "instance_limits.lua", ["/invasion"] = "invasion.lua",
	["/itemfinder"] = "itemfinder.lua", ["/leaderboard"] = "leaderboard.lua", ["/market"] = "market.lua",
	["/memorial"] = "memorial.lua", ["/mentor"] = "mentor.lua", ["/newplayerkit"] = "newplayer.lua",
	["/gmnotify"] = "notifications.lua", ["/orbx"] = "orbexchange.lua", ["/pack30gallery"] = "admin/actions_pack30_gallery.lua", ["/pact"] = "pact.lua",
	["/patchnotes"] = "patchnotes.lua", ["/pet"] = "pets.lua", ["/pocketboss"] = "pocketboss.lua",
	["/poi"] = "poi.lua", ["/professions"] = "professions.lua", ["/marches"] = "pvpzone.lua", ["/raid"] = "raid.lua",
	["/records"] = "records.lua", ["/referral"] = "referral.lua", ["/reports"] = "reports.lua", ["/rift"] = "rift.lua",
	["/season"] = "season.lua", ["/journey"] = "season_journey.lua", ["/seasonpass"] = "seasonpass.lua",
	["/coins"] = "shop.lua", ["/siege"] = "siege.lua", ["/spells"] = "spellbook.lua", ["/supports"] = "supports.lua",
	["/telemetry"] = "telemetry.lua", ["/transmog"] = "transmog.lua", ["/goblin"] = "treasure_goblin.lua",
	["/treestats"] = "treestats.lua", ["/trial"] = "trials.lua", ["/ascended"] = "uber.lua",
	["/weather"] = "weather.lua", ["/worldboss"] = "worldboss.lua",
}
local PLAYER = {["!bless"] = "gentledeath.lua"} -- the owner's one exception

-- a staff check: the access flag, a group or account type compare, the shared staff helpers
local GUARDS = {"getAccess%(%)", "Chaos%.staffCommand%(", "isStaff%(", "getAccountType%(%)%s*<",
	"ChaosAdmin%.isAdmin%(", "getId%(%)%s*<", "groupOf%(player%)%s*<"}
local GUARD_LINES = 4 -- the check must come within the first code lines of the handler

local function read(path)
	local f = assert(io.open(path, "rb"))
	local t = f:read("*a")
	f:close()
	return t
end
-- comments out (block, then line comments that start a line or follow whitespace)
local function code(text)
	text = text:gsub("%-%-%[(=*)%[.-%]%1%]", "")
	local out = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		out[#out + 1] = (line:gsub("^%-%-.*$", ""):gsub("(%s)%-%-.*$", "%1"))
	end
	return table.concat(out, "\n")
end
local function firstCodeLines(text, from, n)
	local lines = {}
	for line in text:sub(from):gmatch("([^\n]*)\n") do
		if line:match("%S") then
			lines[#lines + 1] = line
			if #lines >= n then
				break
			end
		end
	end
	return table.concat(lines, "\n")
end
local function guarded(body)
	for _, g in ipairs(GUARDS) do
		if body:find(g) then
			return true
		end
	end
	return false
end

-- the handler of talkaction variable `var`: its first code lines, following one hand-off to a local function
local function handlerGuarded(src, var)
	local esc = var:gsub("%p", "%%%0")
	local s, e = src:find("function%s+" .. esc .. "%.onSay%s*%b()")
	if not s then
		s, e = src:find(esc .. "%.onSay%s*=%s*function%s*%b()")
	end
	local body
	if s then
		body = firstCodeLines(src, e + 1, GUARD_LINES)
	else
		local fn = src:match(esc .. "%.onSay%s*=%s*([%a_][%w_]*)")
		body = fn and ("return " .. fn .. "(") or nil
	end
	if not body then
		return false, "no onSay found"
	end
	if guarded(body) then
		return true
	end
	-- a thin onSay that hands the call on: `return onCommand(player, ...)` / `onStaff(player, param)`
	local fn = body:match("^%s*return%s+([%a_][%w_]*)%s*%(") or body:match("\n?%s*([%a_][%w_]*)%s*%(player")
	if fn then
		local fs, fe = src:find("local%s+function%s+" .. fn .. "%s*%b()")
		if fs and guarded(firstCodeLines(src, fe + 1, GUARD_LINES)) then
			return true
		end
	end
	return false, "no staff check in the first lines of its onSay"
end

local function listLua(dir)
	local p = io.popen('find "' .. dir .. '" -name "*.lua" | sort')
	local out = {}
	for name in p:lines() do
		out[#out + 1] = name
	end
	p:close()
	return out
end

local blessWords = read("data/scripts/chaos/gentledeath_config.lua"):match("bless%s*=%s*{.-words%s*=%s*\"([^\"]*)\"")
check(blessWords == "!bless", "gentledeath_config.lua bless.words is !bless (got " .. tostring(blessWords) .. ")")

local seen, files = {}, listLua("data")
check(#files > 100, "the scripts were found (run from server/)")
for _, path in ipairs(files) do
	local rel = path:gsub("^data/scripts/chaos/", "")
	if not path:match("_test%.lua$") then
		local src = code(read(path))
		for s, var, args in src:gmatch("()([%a_][%w_]*)%s*=%s*TalkAction%s*(%b())") do
			args = args:sub(2, -2)
			local words = {}
			for w in args:gmatch("\"([^\"]*)\"") do
				words[#words + 1] = w
			end
			if #words == 0 and args:match("bless%.words") and rel == "gentledeath.lua" then
				words = {blessWords}
			elseif #words == 0 then
				-- a loop over a word list: for _, words in ipairs({"/arena"}) do local talk = TalkAction(words)
				local list = src:sub(1, s - 1):match("ipairs%(%{([^}]*)%}%)%s*do%s*local%s*$")
				for w in tostring(list or ""):gmatch("\"([^\"]*)\"") do
					words[#words + 1] = w
				end
			end
			check(#words > 0, path .. ": TalkAction(" .. args .. ") with words this test cannot read")
			for _, w in ipairs(words) do
				seen[w] = true
				if PLAYER[w] then
					check(PLAYER[w] == rel, w .. " belongs in " .. PLAYER[w] .. ", found in " .. path)
				else
					check(w:sub(1, 1) == "/", path .. ": " .. w .. " is a player command (owner rule: only !bless)")
					check(STAFF[w] == rel, path .. ": " .. w .. " is not on the staff allowlist of this test")
					local ok, why = handlerGuarded(src, var)
					check(ok, path .. ": " .. w .. ": " .. tostring(why))
				end
			end
		end
	end
end
for w, f in pairs(STAFF) do
	check(seen[w], "allowlist entry " .. w .. " (" .. f .. ") has no TalkAction any more: take it out")
end
check(seen["!bless"], "!bless is registered (gentledeath.lua)")

-- the test's own check: a talkaction without a staff check is caught
local bad = code('local t = TalkAction("/x")\nfunction t.onSay(player, words, param)\n\tplayer:addItem(1, 1)\n\treturn false\nend\n')
check(not handlerGuarded(bad, "t"), "an unguarded onSay is caught")
local good = code('local t = TalkAction("/x")\nt.onSay = onCmd\nlocal function onCmd(player)\n\tif player:getGroup():getId() < 4 then return true end\nend\n')
check(handlerGuarded(good, "t"), "a hand-off to a guarded local function passes")

if #fails > 0 then
	error(#fails .. " failure(s):\n" .. table.concat(fails, "\n"))
end
print(string.format("no_player_talkactions_test: OK (%d checks)", checks))
