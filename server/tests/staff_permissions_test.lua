-- Run from the server/ folder: luajit tests/staff_permissions_test.lua (and lua5.3; CI runs both). Mock engine API.
-- Economy-creating staff tools need an administrator (group >= 5): the admin panel's players.give_item and
-- world.create_item (like economy.*), and the talkactions /coins, /charm give, /pact days|extra (Chaos.staffCommand in
-- chaos_constants.lua). Every staff use of /coins, /charm, /pact, /market and /orbx is written to the audit log.
-- Staff never give value (docs/GM_HANDBOOK.md section 2): /rift key|omen|fragments, /ascended sigil|relic|shards,
-- /newplayerkit (kit, milestone, reset), /guild bank|xp|rent paid, /classunlock, /cosmetic, /exclusive, /transmog
-- grants and /pet give need an administrator too; their guards are read from the files and evaluated per subcommand.
-- The staff ladder of docs/GM_HANDBOOK.md section 4: mutes up to 24 h, bans of 30 days or more by an administrator.
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
function CreatureEvent() local o = {}; function o:type() end; function o:register() end; return o end
json = {encode = function() return "{}" end, decode = function() return {} end}
db = {asyncQuery = function() end, escapeString = function(s) return "'" .. s .. "'" end}

local function mkPlayer(group)
	local p = {cancel = nil}
	function p:getGroup() return {getId = function() return group end, getAccess = function() return group >= 4 end} end
	function p:isPlayer() return true end
	function p:getName() return "Staff" .. group end
	function p:getId() return group end
	function p:getGuid() return group end
	function p:getAccountId() return group end
	function p:getIp() return 0 end
	function p:sendCancelMessage(t) self.cancel = t end
	return p
end
local gm, god, player = mkPlayer(4), mkPlayer(5), mkPlayer(1)

-- ---------------------------------------------------------------- admin panel actions
dofile("data/scripts/chaos/admin/core.lua")
dofile("data/scripts/chaos/admin/actions_players.lua")
dofile("data/scripts/chaos/admin/actions_world.lua")
local give, create = ChaosAdminPending["players.give_item"], ChaosAdminPending["world.create_item"]
eq(ChaosAdmin.requiredGroup(give), 5, "players.give_item needs an administrator")
eq(ChaosAdmin.requiredGroup(create), 5, "world.create_item needs an administrator")
eq(ChaosAdmin.canUse(gm, give), false, "a gamemaster cannot give items")
eq(ChaosAdmin.canUse(gm, create), false, "a gamemaster cannot create items")
eq(ChaosAdmin.canUse(god, give), true, "an administrator can")
eq(ChaosAdmin.requiredGroup(ChaosAdminPending["players.kick"]), 4, "other players.* actions stay at group 4")
eq(ChaosAdmin.requiredGroup(ChaosAdminPending["world.spawn_monster"]), 4, "other world.* actions stay at group 4")

-- the staff ladder (docs/GM_HANDBOOK.md section 4): mutes up to 24 h; bans of 30 days or more by an administrator
local function param(def, name)
	for _, q in ipairs(def.params) do
		if q.name == name then return q end
	end
end
local mute, ban = ChaosAdminPending["players.mute"], ChaosAdminPending["players.ban"]
eq(param(mute, "minutes").max, 1440, "the longest mute is 24 h")
eq(param(mute, "minutes").default, 60, "the first mute of the ladder is 60 min")
eq(param(ban, "days").max, 3650, "permanent = 3650 days")
eq(param(ban, "days").default, 7, "the first ban of the ladder is 7 days")
eq(ChaosAdmin.requiredGroup(ban), 4, "a gamemaster may ban")
local banned = {}
local realDbPlayer = ChaosAdmin.dbPlayer
ChaosAdmin.dbPlayer = function(name) return {id = 100, account_id = 200, group_id = 1, name = name} end
db.storeQuery = function() return nil end
db.query = function(q) banned[#banned + 1] = q; return true end
Player = function() return nil end
local okBan, msg = ban.handler(gm, {player = "Bob", days = 30})
eq(okBan, false, "a gamemaster cannot ban for 30 days")
eq(msg:find("administrator", 1, true) ~= nil, true, "told why")
eq(#banned, 0, "nothing written")
okBan = ban.handler(gm, {player = "Bob", days = 3650})
eq(okBan, false, "nor permanently")
okBan = ban.handler(gm, {player = "Bob", days = 7})
eq(okBan, true, "a gamemaster bans for 7 days")
eq(#banned, 1, "the ban row")
okBan = ban.handler(god, {player = "Bob", days = 3650})
eq(okBan, true, "an administrator bans permanently")
ChaosAdmin.dbPlayer = realDbPlayer

-- ---------------------------------------------------------------- talkactions
dofile("data/scripts/chaos/chaos_constants.lua")
local logged = {}
local realLog = ChaosAdmin.log
ChaosAdmin.log = function(p, action, target, params, status, text) logged[#logged + 1] = {action = action, status = status} end
local ok, staff = Chaos.staffCommand(gm, "/coins", "X, 5", true)
eq(ok, false, "economy command: a gamemaster is refused")
eq(staff, true, "but is staff (the words are swallowed)")
eq(gm.cancel ~= nil, true, "told why")
eq(logged[1].status, "denied", "the refusal is logged")
ok = Chaos.staffCommand(gm, "/market", "sweep", false)
eq(ok, true, "a report command: staff may")
eq(logged[2].action, "talk/market", "logged")
ok = Chaos.staffCommand(god, "/coins", "X, 5", true)
eq(ok, true, "an administrator may")
ok, staff = Chaos.staffCommand(player, "/coins", "X, 5", true)
eq(ok, false, "a player may not")
eq(staff, false, "a player's words are chat")
eq(#logged, 3, "players are not logged")
ChaosAdmin.log = realLog

local function src(f)
	local h = assert(io.open("data/scripts/chaos/" .. f, "r"))
	local s = h:read("*a")
	h:close()
	return s
end
for f, economy in pairs({["shop.lua"] = "true", ["charms.lua"] = "true", ["market.lua"] = "false", ["orbexchange.lua"] = "false"}) do
	eq(src(f):find("Chaos.staffCommand(player, words, param, " .. economy .. ")", 1, true) ~= nil, true, f .. " uses Chaos.staffCommand")
end
eq(src("pact.lua"):find('Chaos.staffCommand(player, words, param, sub ~= nil and sub ~= "info")', 1, true) ~= nil, true,
	"pact.lua: days / extra / end / claimreset need an administrator")

-- staff never give value (docs/GM_HANDBOOK.md section 2, decided): every staff command that hands something out needs
-- an administrator; what only looks, tests or takes away stays at group 4
local valueGuards = {
	["rift.lua"] = 'if gm and (args[1] == "key" or args[1] == "omen" or args[1] == "fragments")\n\t\t\tand not Chaos.staffCommand(player, words, param, true) then',
	["uber.lua"] = 'Chaos.staffCommand(player, words, param, cmd == "sigil" or cmd == "relic" or cmd == "shards")',
	["newplayer.lua"] = 'local value = what == "" or what == "kit" or what:match("^milestone") ~= nil or what == "reset"\n\tif not Chaos.staffCommand(player, words, param, value) then',
	["guild.lua"] = 'local value = sub == "bank" or sub == "xp" or (sub == "rent" and (arg or ""):lower():match("^%s*paid") ~= nil)\n\tif not Chaos.staffCommand(player, words, param, value) then',
	["class_unlocks.lua"] = 'Chaos.staffCommand(player, words, param, mode ~= "revoke")',
	["cosmetics.lua"] = 'Chaos.staffCommand(player, words, param, what ~= "sync" and mode ~= "revoke")',
	["exclusives.lua"] = 'Chaos.staffCommand(player, words, param, mode ~= "revoke")',
	["transmog.lua"] = 'local value = not (mode == "revoke" and what ~= "all" and not tonumber(what))\n\tif not Chaos.staffCommand(player, words, param, value) then',
	["pets.lua"] = 'Chaos.staffCommand(player, words, param, cmd == "give")',
	["daily.lua"] = 'local value = cmd == "shift" or cmd == "set"\n\tif not Chaos.staffCommand(player, words, param, value) then',
	["leaderboard.lua"] = 'local value = cmd == "shift"\n\tif not Chaos.staffCommand(player, words, param, value) then',
	["descent.lua"] = 'if cmd == "sigil" and not Chaos.staffCommand(player, words, param, true) then',
	["raid.lua"] = 'if cmd == "marks" and not Chaos.staffCommand(player, "/raid", param, true) then',
	["pvpzone.lua"] = 'if cmd == "embers" and not Chaos.staffCommand(player, words, param, true) then',
	["trials.lua"] = 'if args[1] == "tokens" and not Chaos.staffCommand(player, words, param, true) then',
	["achievements.lua"] = 'if not Chaos.staffCommand(player, words, param, cmd == "grant" or cmd == "add") then',
	["atlas.lua"] = 'if cmd == "grant" and not Chaos.staffCommand(player, words, param, true) then',
	["community.lua"] = 'if cmd == "add" and not Chaos.staffCommand(player, words, param, true) then',
}
for f, guard in pairs(valueGuards) do
	eq(src(f):find(guard, 1, true) ~= nil, true, f .. ": the value it hands out needs an administrator")
end
-- the guards' conditions as written in the files, evaluated for each subcommand: value -> administrator, the rest not
local function cond(f, pattern)
	local e = src(f):match(pattern)
	assert(e, f .. ": guard not found")
	return function(env)
		env.tonumber = tonumber
		local chunk
		if setfenv then
			chunk = assert(loadstring("return " .. e))
			setfenv(chunk, env)
		else
			chunk = assert(load("return " .. e, f, "t", env))
		end
		return chunk() == true
	end
end
local checksOf = {
	{cond("uber.lua", "Chaos%.staffCommand%(player, words, param, (cmd == .-)%) then"),
		{{{cmd = "sigil"}, true}, {{cmd = "relic"}, true}, {{cmd = "shards"}, true}, {{cmd = "phase"}, false}, {{cmd = "end"}, false}}},
	{cond("newplayer.lua", "local value = (.-)\n"),
		{{{what = ""}, true}, {{what = "kit"}, true}, {{what = "milestone 2"}, true}, {{what = "reset"}, true},
		{{what = "welcome"}, false}, {{what = "tutorial"}, false}}},
	{cond("guild.lua", "local value = (.-)\n"),
		{{{sub = "bank", arg = "1000"}, true}, {{sub = "xp", arg = "50"}, true}, {{sub = "rent", arg = "paid"}, true},
		{{sub = "rent", arg = "due"}, false}, {{sub = "info"}, false}, {{sub = "hall"}, false}}},
	{cond("class_unlocks.lua", "Chaos%.staffCommand%(player, words, param, (.-)%) then"),
		{{{mode = ""}, true}, {{mode = "revoke"}, false}}},
	{cond("cosmetics.lua", "Chaos%.staffCommand%(player, words, param, (.-)%) then"),
		{{{what = "all", mode = ""}, true}, {{what = "kill_sunring", mode = ""}, true}, {{what = "sync", mode = ""}, false},
		{{what = "kill_sunring", mode = "revoke"}, false}}},
	{cond("exclusives.lua", "Chaos%.staffCommand%(player, words, param, (.-)%) then"),
		{{{what = "roll", mode = "raid_sovereign"}, true}, {{what = "all", mode = ""}, true}, {{what = "x", mode = "revoke"}, false}}},
	{cond("transmog.lua", "local value = (.-)\n"),
		{{{what = "all", mode = ""}, true}, {{what = "all", mode = "revoke"}, true}, {{what = "3456", mode = "revoke"}, true},
		{{what = "falconer", mode = ""}, true}, {{what = "falconer", mode = "revoke"}, false}}},
	{cond("pets.lua", "Chaos%.staffCommand%(player, words, param, (.-)%) then"),
		{{{cmd = "give"}, true}, {{cmd = "xp"}, false}, {{cmd = "species"}, false}}},
	-- /daily shift moves the day of every account (all claim again), /daily set writes a streak (milestone rewards)
	{cond("daily.lua", "local value = (.-)\n"),
		{{{cmd = "shift"}, true}, {{cmd = "set"}, true}, {{cmd = ""}, false}, {{cmd = "status"}, false}}},
	-- /achievements grant|add pay achievement rewards; stat and reset only set or take away
	{cond("achievements.lua", "Chaos%.staffCommand%(player, words, param, (.-)%) then"),
		{{{cmd = "grant"}, true}, {{cmd = "add"}, true}, {{cmd = "stat"}, false}, {{cmd = "reset"}, false}}},
	-- /leaderboard shift: each shift past a week end awards that week's titles and orbs
	{cond("leaderboard.lua", "local value = (.-)\n"),
		{{{cmd = "shift"}, true}, {{cmd = "reset"}, false}, {{cmd = ""}, false}}},
}
for i, c in ipairs(checksOf) do
	for _, case in ipairs(c[2]) do
		local words = {}
		for k, v in pairs(case[1]) do words[#words + 1] = k .. "=" .. v end
		table.sort(words)
		eq(c[1](case[1]), case[2], "guard " .. i .. " (" .. table.concat(words, " ") .. ")")
	end
end

print(string.format("staff_permissions_test: %d checks OK", checks))
