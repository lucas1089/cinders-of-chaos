-- In-game notice for accounts without the acceptance of the current Terms of Use and Privacy Policy: pure logic.
-- Engine file: legal_notice.lua; numbers: legal_notice_config.lua; tests: tests/legal_notice_test.lua; overview:
-- server/README.md "Terms acceptance notice".
--
-- The website records each acceptance in chaos_legal_acceptance (account, version, time; no IP): at sign-up and, for
-- accounts made before the checkbox, on its accept page at the next website login. The game client logs in through the
-- game server, which cannot hold a login for a web form cleanly, so at login an account without a row for the current
-- version (server_config chaos_legal_version, written by website/setup/chaos_setup.php) gets this notice with the link.
-- No version in server_config (the site not installed): no notice.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosLegalNoticeCore = ChaosLegalNoticeCore or {}
local L = ChaosLegalNoticeCore

L.SERVER_CONFIG = "chaos_legal_version"
L.TABLE = "chaos_legal_acceptance"

-- a version as legal_lib.php chaos_legal_version() makes it: 16 hex digits; anything else = none
function L.cleanVersion(v)
	v = tostring(v or ""):lower():match("^%s*(.-)%s*$")
	if v:match("^[0-9a-f]+$") and #v == 16 then
		return v
	end
	return nil
end

function L.versionSql()
	return string.format("SELECT `value` FROM `server_config` WHERE `config` = '%s'", L.SERVER_CONFIG)
end

-- nil for a bad version or account
function L.acceptedSql(accountId, version)
	accountId = math.floor(tonumber(accountId) or 0)
	version = L.cleanVersion(version)
	if accountId <= 0 or not version then
		return nil
	end
	return string.format("SELECT `id` FROM `%s` WHERE `account_id` = %d AND `version` = '%s' LIMIT 1", L.TABLE, accountId, version)
end

-- show the notice? version = the current one (nil = none), accepted = a row for it exists
function L.needsNotice(cfg, version, accepted)
	return cfg.enabled ~= false and L.cleanVersion(version) ~= nil and not accepted
end

-- the text message (English, then Portuguese), and the popup text
function L.message(cfg)
	local en = "Please accept our updated Terms of Use and Privacy Policy on the website: log in there and open " .. cfg.url ..
		" (it opens by itself at your next website login)."
	local pt = "Aceite os nossos Termos de Uso e a Política de Privacidade atualizados no site: entre na sua conta lá e abra " ..
		cfg.url .. " (a página abre sozinha no seu próximo login no site)."
	return en, pt
end

function L.popup(cfg)
	local en, pt = L.message(cfg)
	return "Terms of Use / Termos de Uso\n\n" .. en .. "\n\n" .. pt
end

-- the cached version is still good?
function L.cacheFresh(cache, now, cfg)
	return cache ~= nil and cache.at ~= nil and now - cache.at < (cfg.cacheSeconds or 300) and now >= cache.at
end

return L
