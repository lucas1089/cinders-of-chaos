-- In-game notice for accounts without the acceptance of the current Terms of Use and Privacy Policy (website
-- chaos_legal_acceptance). At login such an account gets a message (and a window) with the website page to accept on.
-- Pure logic: legal_notice_core.lua (tests/legal_notice_test.lua); numbers: legal_notice_config.lua; overview:
-- server/README.md "Terms acceptance notice". Nothing is blocked: the website asks for the acceptance at its next login.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosLegalNoticeCore then
	dofile("data/scripts/chaos/legal_notice_core.lua")
end

Chaos.legalNoticeConfig = dofile("data/scripts/chaos/legal_notice_config.lua")
local cfg = Chaos.legalNoticeConfig
local L = ChaosLegalNoticeCore
ChaosLegalNotice = ChaosLegalNotice or {}
local LN = ChaosLegalNotice

-- the current version (cached), or nil
function LN.version(now)
	now = now or os.time()
	if not L.cacheFresh(LN.cache, now, cfg) then
		local r = Chaos.select(L.versionSql(), {{"value", "s"}})[1]
		LN.cache = {at = now, v = r and L.cleanVersion(r.value) or nil}
	end
	return LN.cache.v
end

function LN.accepted(accountId, version)
	local q = L.acceptedSql(accountId, version)
	if not q then
		return true
	end
	local id = db.storeQuery(q)
	if id then
		result.free(id)
		return true
	end
	return false
end

-- the check for one character, by creature id (after the login delay)
function LN.check(pid)
	local player = Player(pid)
	if not player then
		return false
	end
	local version = LN.version()
	if not L.needsNotice(cfg, version, version and LN.accepted(player:getAccountId(), version)) then
		return false
	end
	local en, pt = L.message(cfg)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, en)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, pt)
	if cfg.popup and player.popupFYI then
		player:popupFYI(L.popup(cfg))
	end
	return true
end

local login = CreatureEvent("ChaosLegalNoticeLogin")
function login.onLogin(player)
	if cfg.enabled then
		addEvent(function(pid)
			local ok, err = pcall(LN.check, pid)
			if not ok then
				print("[Chaos legal notice] " .. tostring(err))
			end
		end, cfg.delayMs, player:getId())
	end
	return true
end
login:type("login")
login:register()

return LN
