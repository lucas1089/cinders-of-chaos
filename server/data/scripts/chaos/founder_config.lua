-- founder_config.lua: the Founder Pack (O322, owner approval 2026-10-29). Plain table, loaded with
--     ChaosFounderConfig = dofile("data/scripts/chaos/founder_config.lua")
-- No engine calls here. Rules: founder_core.lua; store category: shop_config.lua (`store.pack` below); engine file:
-- founder.lua (the title); tests: server/tests/founder_test.lua, shop_test.lua; limits: store_balance_config.lua `founder`;
-- numbers and reasons: docs/PRICES.md "Founder Pack (O322)"; overview: server/README.md "Founder Pack".
--
-- A time-limited sale of two packs, one per account and tier, sold only from `start` to `end` (server time), then never again.
-- Cosmetic and convenience only: no power, no luck orbs, no finished items. What a tier gives:
--   exclusives  pieces of exclusives_config.lua with source "founder" (never dropped, never sold apart, never again)
--   pactDays    days of the Chaos Pact (pact_config.lua; the part is `required`: no Pact system, no sale)
--   title       a name plate title held while the account owns the tier's first exclusive (titles.lua source "founder")
-- Prices are in Chaos Coins (one coin is about R$ 0,10): 499 is about R$ 50 and 999 about R$ 100. The window is shown in the
-- offer ("Available until ..." / "Disponivel ate ...", shop_core.lua windowNote). A tier is bought once (oncePerAccount).
-- The two tiers are independent: the Grand Founder Pack does not hold the first pack's pieces.

local START = "2026-11-20 15:00" -- launch, server time
local END = "2026-12-18 15:00" -- four weeks later; nothing is sold from this moment on

-- the Pact's own list price per day sets the value shown for the Pact days of a pack
local okPact, pact = pcall(dofile, "data/scripts/chaos/pact_config.lua")
local PACT_PRICE = okPact and type(pact) == "table" and pact.store and pact.store.pact.offers[1].cost or 299
local function pactCost(days)
	return math.floor(PACT_PRICE * days / 30 + 0.5)
end

local cfg = {
	start = START,
	["end"] = END,
	-- the "how" text of the pieces in the wardrobe's Collection tab
	how = "Founder Pack, on sale 2026-11-20 to 2026-12-18 only",

	tiers = {
		{key = "founder:pack", name = "Founder Pack", cost = 499, icon = 2160,
			exclusives = {"wings_gold_peacock", "head_royal_coronet"}, pactDays = 14,
			title = {key = "founder", text = "Founder", color = "#e8b04a"},
			description = "Once per account, never sold again. Gold Peacock Wings, the Royal Coronet and the Founder title, yours for good."},
		{key = "founder:grand", name = "Grand Founder Pack", cost = 999, icon = 2353,
			exclusives = {"wings_pyre_seraph", "cape_phoenix_plume_cape", "head_double_halo", "frame_founder"}, pactDays = 30,
			title = {key = "founder_grand", text = "Grand Founder", color = "#f0cf7a"},
			description = "Once per account, never sold again. Pyre Seraph Wings, the Phoenix Plume Cape, the Double Halo, the Founder plate frame and the Grand Founder title, yours for good."}
	}
}

-- the store category (shop_config.lua puts it second, after the Starter packs): a bundle per tier with a fixed price and
-- the window; the exclusive parts have no list price (they are never sold apart)
local offers = {}
for _, t in ipairs(cfg.tiers) do
	local parts = {}
	for _, key in ipairs(t.exclusives) do
		parts[#parts + 1] = {kind = "exclusive", exclusive = key}
	end
	parts[#parts + 1] = {kind = "pact", days = t.pactDays, cost = pactCost(t.pactDays), required = true,
		name = t.pactDays .. " days of the Chaos Pact"}
	offers[#offers + 1] = {kind = "bundle", key = t.key, oncePerAccount = true, gift = false, cost = t.cost, name = t.name,
		icon = t.icon, description = t.description, parts = parts, availableFrom = START, availableUntil = END}
end
cfg.store = {pack = {name = "Founder Pack", icon = {item = 2160}, offers = offers}}

return cfg
