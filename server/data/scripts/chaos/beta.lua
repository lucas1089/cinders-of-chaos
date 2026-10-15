-- The beta switch (Chaos.beta, beta_config.lua): beta starter coins. While the beta is on, an account gets
-- Chaos.beta.starterCoins Chaos Coins once, at the first login of a new character, so testers can try every store
-- feature. Pure logic: beta_core.lua (tests/beta_test.lua); overview: server/README.md "Beta starter coins".
-- Turn the switch off at launch (docs/LAUNCH.md); the wipe removes the coins (docs/BETA.md section 9).
-- Assumed engine API (TFS 1.4): Player:getLastLoginSaved, getAccountId, getGuid, sendTextMessage; db.query.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosBetaCore then
	dofile("data/scripts/chaos/beta_core.lua")
end

Chaos.beta = dofile("data/scripts/chaos/beta_config.lua")
local cfg = Chaos.beta
local B = ChaosBetaCore
ChaosBeta = ChaosBeta or {}
local Beta = ChaosBeta

local function log(text)
	print("[Chaos beta] " .. text)
end

-- also in server/sql/chaos_beta.sql
db.query(B.SCHEMA)

-- the account's grant: true when this call gave the coins
function Beta.grantStarter(player)
	local coins = B.starterCoins(cfg)
	if coins <= 0 or not player then
		return false
	end
	if not ChaosShop or not ChaosShop.addCoins then
		log("the store is not loaded: no starter coins")
		return false
	end
	local accountId = player:getAccountId()
	local sql = B.claimSql(accountId, player:getGuid(), coins, os.time())
	if not sql or not db.query(sql) then
		return false
	end
	local r = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	if not B.claimed(r and r.n) then
		return false -- the account had its grant
	end
	ChaosShop.addCoins(accountId, coins)
	log(string.format("account %d: %d starter coins (character %s)", accountId, coins, player:getName()))
	return true
end

-- the message to the player (later than the login lines)
function Beta.tell(pid, coins)
	local p = Player(pid)
	if p then
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "Beta: your account received %d Chaos Coins to try the store. They are beta test coins: they and everything bought with them are wiped at launch.", coins))
	end
end

local login = CreatureEvent("ChaosBetaLogin")
-- the claim runs at once (a character that logs out within the message delay keeps nothing pending); the message later
function login.onLogin(player)
	if B.dueAtLogin(cfg, player:getLastLoginSaved()) then
		local ok, given = pcall(Beta.grantStarter, player)
		if not ok then
			log(tostring(given))
		elseif given then
			addEvent(Beta.tell, cfg.delayMs or 3000, player:getId(), B.starterCoins(cfg))
		end
	end
	return true
end
login:type("login")
login:register()

return Beta
