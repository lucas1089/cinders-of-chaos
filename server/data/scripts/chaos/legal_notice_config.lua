-- In-game notice for accounts that have not accepted the current Terms of Use and Privacy Policy (legal_notice.lua,
-- legal_notice_core.lua). Returned as a table, loaded as Chaos.legalNoticeConfig (and by tests/legal_notice_test.lua).
-- See server/README.md "Terms acceptance notice". Data only.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	enabled = true,
	delayMs = 2500, -- after login, so the notice comes after the login messages
	cacheSeconds = 300, -- the current version (server_config chaos_legal_version, written by the website setup) is read again after this
	-- the website page that asks for the acceptance (website plugins/chaos/pages/accept.php); shown as text, like the
	-- Donation Terms in shop_payments_core.lua
	url = "page?plugin=chaos&p=accept",
	popup = true -- also a window the player closes (Player:popupFYI), not only the text in the server log
}
