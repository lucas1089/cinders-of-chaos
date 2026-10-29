-- founder_core.lua: the rules of the Founder Pack without engine calls (ChaosFounderCore; server/tests/founder_test.lua).
-- Data: founder_config.lua. Engine file: founder.lua (the title). The store side (the window, one per account, the grant)
-- is shop.lua with shop_core.lua windowState; this file holds what is specific to the pack.
--
--   F.state(cfg, now)                     "early" | "open" | "late": the sale window of the pack
--   F.tier(cfg, key)                      a tier by its offer key ("founder:pack")
--   F.titles(cfg, owns)                   the titles an account holds: owns(exclusive key) -> bool; the tier's title is held
--                                         when the account owns the tier's first exclusive (only the pack gives it)
--   F.validate(cfg, opts)                 problems (see the function)
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosFounderCore = ChaosFounderCore or {}
local F = ChaosFounderCore

if not ChaosShopCore then
	dofile("data/scripts/chaos/shop_core.lua")
end

-- the sale lasts at least this long and at most this long (days); docs/PRICES.md "Founder Pack (O322)"
F.MIN_DAYS, F.MAX_DAYS = 14, 60
-- the exclusive kinds a pack may give: looks only, never power
F.COSMETIC_KINDS = {wings = true, aura = true, frame = true, outfit = true, mount = true, shader = true, addons = true}

function F.state(cfg, now)
	local from, to = ChaosShopCore.parseTime(cfg.start), ChaosShopCore.parseTime(cfg["end"])
	now = now or os.time()
	if from and now < from then
		return "early"
	end
	if to and now >= to then
		return "late"
	end
	return "open"
end

function F.tier(cfg, key)
	for _, t in ipairs(cfg.tiers or {}) do
		if t.key == key then
			return t
		end
	end
	return nil
end

function F.titles(cfg, owns)
	local out = {}
	local at = ChaosShopCore.parseTime(cfg.start) or 0
	for _, t in ipairs(cfg.tiers or {}) do
		if t.title and t.exclusives and t.exclusives[1] and owns(t.exclusives[1]) then
			out[#out + 1] = {key = t.title.key, text = t.title.text, color = t.title.color, at = at}
		end
	end
	return out
end

-- opts (each optional):
--   exclusives   exclusives_config.lua: every piece exists, has source "founder" and a cosmetic kind
--   pactPrice    the Pact's coins for 30 days (pact_config.lua): the Pact days of a tier are worth at most limits.pactSharePct
--                of its price
--   limits       store_balance_config.lua `founder`
function F.validate(cfg, opts)
	opts = opts or {}
	local problems = {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	local P = ChaosShopCore.parseTime
	local from, to = P(cfg.start), P(cfg["end"])
	if not from or not to then
		bad("start and end must be \"YYYY-MM-DD HH:MM\"")
	elseif to <= from then
		bad("the sale ends before it starts")
	else
		local days = (to - from) / 86400
		if days < F.MIN_DAYS or days > F.MAX_DAYS then
			bad("the sale lasts %.1f days (%d to %d)", days, F.MIN_DAYS, F.MAX_DAYS)
		end
	end
	if type(cfg.how) ~= "string" or cfg.how == "" then
		bad("how (the Collection tab text) needed")
	end
	local keys, titles = {}, {}
	for i, t in ipairs(cfg.tiers or {}) do
		local w = "tier " .. tostring(t.key or i)
		if type(t.key) ~= "string" or not t.key:match("^founder:[%w_]+$") then
			bad("%s: key must be founder:<name>", w)
		elseif keys[t.key] then
			bad("%s: key used twice", w)
		end
		keys[t.key or "?"] = true
		if type(t.name) ~= "string" or t.name == "" or type(t.description) ~= "string" or t.description == "" then
			bad("%s: name and description needed", w)
		end
		if type(t.cost) ~= "number" or t.cost < 1 or t.cost % 1 ~= 0 then
			bad("%s: cost must be a whole number of coins", w)
		end
		if type(t.exclusives) ~= "table" or #t.exclusives == 0 then
			bad("%s: at least one exclusive needed", w)
		end
		if type(t.pactDays) ~= "number" or t.pactDays < 0 or t.pactDays % 1 ~= 0 then
			bad("%s: pactDays must be a whole number", w)
		end
		local ti = t.title
		if type(ti) ~= "table" or type(ti.key) ~= "string" or type(ti.text) ~= "string" or ti.text == "" or #ti.text > 24 then
			bad("%s: title {key, text (24 characters at most)} needed", w)
		elseif titles[ti.key] then
			bad("%s: title key used twice", w)
		end
		if type(ti) == "table" then
			titles[ti.key or "?"] = true
		end
		for _, k in ipairs(t.exclusives or {}) do
			if opts.exclusives then
				local found
				for _, e in ipairs(opts.exclusives.exclusives or {}) do
					if e.key == k then
						found = e
					end
				end
				if not found then
					bad("%s: exclusive %s does not exist", w, k)
				else
					if found.source ~= "founder" then
						bad("%s: %s must have source founder", w, k)
					end
					if not F.COSMETIC_KINDS[found.kind] then
						bad("%s: %s is a %s, not a cosmetic", w, k, tostring(found.kind))
					end
				end
			end
		end
		local L = opts.limits
		if L and opts.pactPrice and type(t.cost) == "number" and type(t.pactDays) == "number" then
			local value = opts.pactPrice * t.pactDays / 30
			if value > t.cost * L.pactSharePct / 100 then
				bad("%s: %.0f coins of Pact days are over %d%% of the price", w, value, L.pactSharePct)
			end
			if t.pactDays > L.maxPactDays then
				bad("%s: %d Pact days (limit %d)", w, t.pactDays, L.maxPactDays)
			end
		end
	end
	return problems
end

return F
