-- Character Bazaar, the game server's part: pure logic (no engine calls), shared by bazaar.lua and
-- server/tests/bazaar_test.lua. The auction itself (bids, escrow, fee, transfer) is the website's
-- (website/overlay/plugins/chaos/bazaar_lib.php); its numbers mirror bazaar_config.lua and are tested there.
--   B.locks(rows, cfg)            the listing that locks the character (a row whose status is in cfg.lockStatuses), or nil
--   B.lockMessage(row, cfg, tr)   the text a locked character's owner reads (tr: a translation, default English)
--   B.refusalText(row, cfg, lang, text)   the login refusal box: the player's language, or English and pt-BR
--   B.fee(price, cfg)             the house fee of a final price (floor, at least 1 coin on a sale above 0)
--   B.minNextBid(current, minPrice, cfg)   the lowest bid allowed next
--   B.validate(cfg)               list of problems in the config (fee 5-10 %, days 1-7, prices, statuses)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosBazaarCore = ChaosBazaarCore or {}
local B = ChaosBazaarCore

local floor = math.floor

-- rows = the bazaar listings of one character (any order): {id, status, ends_at}
function B.locks(rows, cfg)
	local best
	for _, r in ipairs(rows or {}) do
		if cfg.lockStatuses[r.status] and (not best or (tonumber(r.ends_at) or 0) > (tonumber(best.ends_at) or 0)) then
			best = r
		end
	end
	return best
end

-- tr(pattern, ...) translates (Chaos.t of the player); default: English
function B.lockMessage(row, cfg, tr)
	local ends = tonumber(row and row.ends_at) or 0
	tr = tr or string.format
	return tr(cfg.messages.locked, ends > 0 and os.date("%Y-%m-%d %H:%M", ends) or "the auction ends")
end

-- the text of the login refusal box (bazaar.lua, engine patch 0039 player:refuseLogin). lang = the player's language
-- ("en" | "pt-BR"), or nil when the character never told it (a first login): then English and pt-BR together.
-- text(lang, pattern, ...) translates (ChaosI18n.text).
function B.refusalText(row, cfg, lang, text)
	local function tr(l)
		return B.lockMessage(row, cfg, function(p, ...) return text(l, p, ...) end)
	end
	if lang then
		return tr(lang)
	end
	return tr("en") .. "\n\n" .. tr("pt-BR")
end

function B.fee(price, cfg)
	price = math.max(0, floor(tonumber(price) or 0))
	if price == 0 then
		return 0
	end
	return math.max(1, floor(price * cfg.feePct / 100))
end

function B.minNextBid(current, minPrice, cfg)
	current = math.max(0, floor(tonumber(current) or 0))
	if current <= 0 then
		return math.max(cfg.minPrice, floor(tonumber(minPrice) or 0))
	end
	return current + math.max(cfg.minStep, floor(current * cfg.minStepPct / 100))
end

function B.validate(cfg)
	local p = {}
	local function bad(t)
		p[#p + 1] = t
	end
	if type(cfg.feePct) ~= "number" or cfg.feePct < 5 or cfg.feePct > 10 then
		bad("feePct must be 5..10")
	end
	if cfg.minDays ~= 1 or cfg.maxDays ~= 7 then
		bad("auctions run 1..7 days")
	end
	if not (cfg.minPrice > 0 and cfg.maxPrice > cfg.minPrice) then
		bad("prices")
	end
	if not (cfg.minStep > 0 and cfg.minStepPct > 0) then
		bad("bid steps")
	end
	if not (cfg.lockStatuses and cfg.lockStatuses.active and cfg.lockStatuses.settling) then
		bad("active and settling listings must lock the character")
	end
	for _, k in ipairs({"listings", "bids", "log"}) do
		if type(cfg.tables[k]) ~= "string" or not cfg.tables[k]:find("^chaos_bazaar_") then
			bad("table " .. k)
		end
	end
	return p
end

return B
