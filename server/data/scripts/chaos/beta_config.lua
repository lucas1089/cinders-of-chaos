-- The beta switch (beta.lua, beta_core.lua). Returned as a table, loaded as Chaos.beta (and by tests/beta_test.lua).
-- See server/README.md "Beta starter coins", docs/BETA.md section 4 and docs/LAUNCH.md "Before the launch".
-- Data only. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- TURN OFF AT LAUNCH: set enabled = false on the launch server (docs/LAUNCH.md). The beta coins and every purchase
-- made with them are wiped with the beta (docs/BETA.md section 9 truncates chaos_shop_coins and chaos_beta_grants).
return {
	enabled = true, -- the open beta is on; false at launch
	-- Chaos Coins given once per ACCOUNT, at the first login of a new character of that account (not per character,
	-- so alts cannot farm them). The grant is recorded in chaos_beta_grants, so a restart never gives them again.
	starterCoins = 5000,
	-- true: only a character's first login grants (a character made before this switch was on does not); the
	-- account still gets the coins once, with its next new character
	firstLoginOnly = true,
	delayMs = 3000 -- after login, so the message comes after the welcome lines
}
