-- Character Bazaar, the game server's part: pure logic (no engine calls), shared by bazaar.lua and
-- server/tests/bazaar_test.lua. The auction itself (bids, escrow, fee, transfer) is the website's
-- (website/overlay/plugins/chaos/bazaar_lib.php); its numbers mirror bazaar_config.lua and are tested there.
--   B.locks(rows, cfg)            the listing that locks the character (a row whose status is in cfg.lockStatuses), or nil
--   B.lockMessage(row, cfg)       the text a locked character's owner reads
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

function B.lockMessage(row, cfg)
	local ends = tonumber(row and row.ends_at) or 0
	return string.format(cfg.messages.locked, ends > 0 and os.date("%Y-%m-%d %H:%M", ends) or "the auction ends")
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
