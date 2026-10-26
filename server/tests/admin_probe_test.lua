-- Run from the server/ folder: luajit tests/admin_probe_test.lua (and lua5.3; CI runs both). Mock of the engine API.
-- Admin opcode from a non-admin (admin/core.lua): the catalog request every client sends at login is ignored without
-- a log line or a chaos_admin_log row; any other admin request from a non-admin is still logged as denied.
local function check(c, m) if not c then error(m, 2) end end

local events = {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
-- a tiny JSON stand-in: enough for {"action":"..."} buffers
json = {
	encode = function() return "{}" end,
	decode = function(s)
		local a = s:match('^%s*{%s*"action"%s*:%s*"([^"]*)"')
		if not a then error("bad json") end
		return {action = a}
	end,
}
local queries, printed = {}, {}
db = {asyncQuery = function(q) queries[#queries + 1] = q end, escapeString = function(s) return "'" .. s .. "'" end}
local realPrint = print
print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
local clock = 1000000
os.mtime = function() clock = clock + 10000; return clock end

dofile("data/scripts/chaos/admin/core.lua")
local ext = events.ChaosAdminExtended
check(ext and ext.onExtendedOpcode, "extended opcode event registered")

local function mkPlayer(id, group, access)
	local g = {getId = function() return group end, getAccess = function() return access end}
	return {
		getId = function() return id end, getGuid = function() return id end, getName = function() return "P" .. id end,
		isPlayer = function() return true end, getGroup = function() return g end,
		getAccountId = function() return id end, getIp = function() return 0 end,
	}
end

local player = mkPlayer(1, 1, false)
ext.onExtendedOpcode(player, CHAOS_ADMIN_OPCODE, '{"action":"catalog"}')
check(#printed == 0 and #queries == 0, "login catalog probe of a player: no log line, no row")
ext.onExtendedOpcode(player, 99, '{"action":"run"}')
check(#printed == 0 and #queries == 0, "other opcodes are not ours")

ext.onExtendedOpcode(player, CHAOS_ADMIN_OPCODE, '{"action":"run","data":{"id":"server.shutdown"}}')
check(#printed == 1 and printed[1]:find("denied", 1, true), "a real admin request of a player is logged")
check(#queries == 1 and queries[1]:find("chaos_admin_log", 1, true), "and stored in chaos_admin_log")
ext.onExtendedOpcode(player, CHAOS_ADMIN_OPCODE, "not json")
check(#printed == 1, "garbage on the admin opcode from the same sender in the window: not logged again")

-- one row per sender per 10 minutes, not one per 5 s
local nq = #queries
for i = 1, 5 do
	clock = clock + 6000
	ext.onExtendedOpcode(player, CHAOS_ADMIN_OPCODE, '{"action":"run"}')
end
check(#queries == nq, "repeat attempts within 10 minutes: no new row")
clock = clock + 11 * 60 * 1000
ext.onExtendedOpcode(player, CHAOS_ADMIN_OPCODE, '{"action":"run"}')
check(#queries == nq + 1, "after 10 minutes the sender is logged again")
nq = #queries
local other = mkPlayer(2, 1, false)
ext.onExtendedOpcode(other, CHAOS_ADMIN_OPCODE, '{"action":"run"}')
check(#queries == nq + 1, "another sender has its own window")

-- bounded table: many senders never grow it past the cap, expired entries are cleaned up
ChaosAdmin.deniedAt, ChaosAdmin.deniedCount = {}, 0
local t0 = 5000000
for id = 1, ChaosAdmin.deniedLogMax do check(ChaosAdmin.shouldLogDenied(1000 + id, t0), "fill " .. id) end
check(not ChaosAdmin.shouldLogDenied(9999, t0 + 1000), "full of recent senders: new sender not logged, table not grown")
check(ChaosAdmin.deniedCount == ChaosAdmin.deniedLogMax, "count stays at the cap")
check(ChaosAdmin.shouldLogDenied(9999, t0 + ChaosAdmin.deniedLogMs + 1), "expired entries are purged, new sender fits")
check(ChaosAdmin.deniedCount == 1, "purged to the one live entry")

check(ChaosAdmin.isCatalogProbe('{"action":"catalog"}') and not ChaosAdmin.isCatalogProbe('{"action":"run"}')
	and not ChaosAdmin.isCatalogProbe(('x'):rep(300)) and not ChaosAdmin.isCatalogProbe(nil), "isCatalogProbe")

print = realPrint
print("admin_probe_test: OK")
