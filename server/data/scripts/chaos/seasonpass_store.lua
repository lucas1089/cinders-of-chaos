-- Season pass store category: the premium pass and the season packs of Chaos.seasonPassConfig.storeSeason.
-- Returned as one category table for shop_config.lua (its "season pass" hunk includes this file), so the store helper's
-- file holds only the include. Data only (shop_config.lua is read by the tests with plain Lua).
-- The offers are "unlock" offers that seasonpass.lua answers (it hooks ChaosShopServices.check / deliver): they can
-- only be bought while that season runs, once per account; an upgrade from a lower pack is bought in the Season Pass
-- window (Adventure > Season Pass), where the price is the difference. noSale: a store sale would change the price the
-- pass compares against; gift = false: gifts go through the pass window (Packs, Gift), which charges the price of the
-- receiving account.
local cfg = dofile("data/scripts/chaos/seasonpass_config.lua")
local pass = cfg.passes[cfg.storeSeason] or {packs = {}}
local offers = {}
if pass.premium then
	offers[#offers + 1] = {kind = "unlock", unlock = pass.premium.unlock, icon = pass.premium.icon or 26031,
		cost = pass.premium.price, name = "Premium " .. pass.name, description = pass.premium.description,
		noSale = true, gift = false}
end
for _, p in ipairs(pass.packs or {}) do
	offers[#offers + 1] = {kind = "unlock", unlock = p.unlock, look = p.look, icon = 26031, cost = p.price,
		name = p.name, description = p.description, noSale = true, gift = false}
end
return {name = "Season Pass", icon = {item = pass.premium and pass.premium.icon or 26031}, offers = offers}
