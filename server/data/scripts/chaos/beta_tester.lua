-- Beta testers (owner decision 2026-10-29): an account that logs in during a beta window (beta_config.lua tester.windows) is
-- recorded in chaos_beta_testers. The wipe keeps that table. At launch, with the beta switch off, the account holds the
-- cosmetic name plate title "Beta Tester" (titles.lua source "betatester"). No power, no coins. Pure logic: beta_core.lua;
-- test: tests/beta_tester_test.lua; overview: server/README.md "Beta testers". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosBetaCore then
	dofile("data/scripts/chaos/beta_core.lua")
end

local cfg = dofile("data/scripts/chaos/beta_config.lua")
local B = ChaosBetaCore
ChaosBetaTester = ChaosBetaTester or {}
local M = ChaosBetaTester
M.config = cfg
M.known = {} -- [account id] = true / false, filled at login and on the first title lookup

db.query(B.TESTERS_SCHEMA)

-- is the account recorded? (one query per account, then the answer is kept until a restart)
function M.has(accountId)
	if M.known[accountId] == nil then
		local r = Chaos.select("SELECT 1 AS `n` FROM `" .. B.TESTERS .. "` WHERE `account_id` = " .. math.floor(tonumber(accountId) or 0) .. " LIMIT 1", {{"n", "n"}})
		M.known[accountId] = r[1] ~= nil
	end
	return M.known[accountId]
end

local function source(player)
	return B.testerTitle(M.config, M.has(player:getAccountId()))
end
M.titleSource = source

-- titles.lua builds its tables when it loads (possibly after this file): put the source in at load and at every login
function M.ensureHooks()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("betatester", source)
	end
end
M.ensureHooks()

-- records the account when `now` is inside a window; returns true when this call made the row
function M.record(player, now)
	now = now or os.time()
	if not B.inTesterWindow(cfg, now) then
		return false
	end
	local accountId = player:getAccountId()
	local sql = B.testerSql(accountId, player:getGuid(), now)
	if not sql or not db.query(sql) then
		return false
	end
	M.known[accountId] = true
	return true
end

local login = CreatureEvent("ChaosBetaTesterLogin")
function login.onLogin(player)
	M.ensureHooks()
	local ok, err = pcall(M.record, player)
	if not ok then
		print("[Chaos beta] tester record failed: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

return M
