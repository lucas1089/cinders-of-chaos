-- The beta switch: pure logic. Engine file: beta.lua; numbers: beta_config.lua (Chaos.beta); tests: tests/beta_test.lua;
-- overview: server/README.md "Beta starter coins".
--
-- While the beta is on, an account gets cfg.starterCoins Chaos Coins once, at the first login of a new character.
-- Chaos Coins belong to the account (chaos_shop_coins), so the grant is per account: a row in chaos_beta_grants
-- (primary key account_id) is written with INSERT IGNORE before the coins are added, and only the login whose insert
-- made the row (ROW_COUNT() = 1) adds them. A second character, a restart, two characters logging in at once: no
-- second grant. Season characters get the same account grant; what they may buy is season_config.lua `store`.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosBetaCore = ChaosBetaCore or {}
local B = ChaosBetaCore

B.TABLE = "chaos_beta_grants"
B.KIND_STARTER = "starter"

B.SCHEMA = "CREATE TABLE IF NOT EXISTS `chaos_beta_grants` (`account_id` int(11) NOT NULL, " ..
	"`kind` varchar(16) NOT NULL DEFAULT 'starter', `coins` int(11) NOT NULL DEFAULT 0, " ..
	"`player_id` int(11) NOT NULL DEFAULT 0, `granted_at` bigint(20) NOT NULL DEFAULT 0, " ..
	"PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"

-- the beta is on?
function B.enabled(cfg)
	return type(cfg) == "table" and cfg.enabled == true
end

-- the starter grant in coins (0 = none)
function B.starterCoins(cfg)
	if not B.enabled(cfg) then
		return 0
	end
	local n = math.floor(tonumber(cfg.starterCoins) or 0)
	return n > 0 and n or 0
end

-- try the grant at this login? lastLoginSaved = the character's last login before this one (0 = first login)
function B.dueAtLogin(cfg, lastLoginSaved)
	if B.starterCoins(cfg) <= 0 then
		return false
	end
	if cfg.firstLoginOnly ~= false and (tonumber(lastLoginSaved) or 0) > 0 then
		return false
	end
	return true
end

local function id(n)
	n = math.floor(tonumber(n) or 0)
	return n > 0 and n or nil
end

-- the claim: makes the account's row if it has none (nil for a bad account)
function B.claimSql(accountId, playerId, coins, now)
	accountId = id(accountId)
	if not accountId then
		return nil
	end
	return string.format("INSERT IGNORE INTO `%s` (`account_id`, `kind`, `coins`, `player_id`, `granted_at`) " ..
		"VALUES (%d, '%s', %d, %d, %d)", B.TABLE, accountId, B.KIND_STARTER, math.max(0, math.floor(tonumber(coins) or 0)),
		id(playerId) or 0, math.floor(tonumber(now) or 0))
end

function B.grantedSql(accountId)
	accountId = id(accountId)
	if not accountId then
		return nil
	end
	return string.format("SELECT `coins` FROM `%s` WHERE `account_id` = %d LIMIT 1", B.TABLE, accountId)
end

-- the claim made the row? (rowCount = ROW_COUNT() after the INSERT IGNORE)
function B.claimed(rowCount)
	return tonumber(rowCount) == 1
end

return B
