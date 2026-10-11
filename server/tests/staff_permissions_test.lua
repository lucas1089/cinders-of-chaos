-- Run from the server/ folder: luajit tests/staff_permissions_test.lua (and lua5.3; CI runs both). Mock engine API.
-- Economy-creating staff tools need an administrator (group >= 5): the admin panel's players.give_item and
-- world.create_item (like economy.*), and the talkactions /coins, /charm give, /pact days|extra (Chaos.staffCommand in
-- chaos_constants.lua). Every staff use of /coins, /charm, /pact, /market and /orbx is written to the audit log.
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

print(string.format("staff_permissions_test: %d checks OK", checks))
