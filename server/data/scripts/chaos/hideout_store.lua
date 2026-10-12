-- hideout_store.lua: the store category of the hideout decorations (hideout.lua), built from hideout_config.lua so
-- the offers, names and prices live in one place. Used by the Hideouts hunk of shop_config.lua:
--     dofile("data/scripts/chaos/hideout_store.lua")()
-- returns one category {name, icon, offers} with an offer {kind = "unlock", unlock = "hideout_<key>", icon, cost, name,
-- description, gift = true} per decoration whose source is the store. Cosmetic only (a look in your own hideout), per
-- account, giftable (shop.lua lets an unlock offer with gift = true be gifted; the receiver's account gets it).
-- Earned decorations (achievements, factions, trophies, events, the season journey) are never sold.
-- No engine calls (server/tests/hideout_test.lua and shop_test.lua read it with plain Lua).

local cfg = dofile("data/scripts/chaos/hideout_config.lua")

local CAT = {}
for _, c in ipairs(cfg.categories) do
	CAT[c.key] = c.name
end

return function()
	local category = {name = "Hideout Decorations", icon = {item = 9439}, offers = {}}
	for _, d in ipairs(cfg.decorations) do
		if d.source and d.source.type == "store" then
			local icon = d.icon or (d.layer == "wall" and d.wall.n) or (d.ids and d.ids[1]) or (d.rots and d.rots[1][1][3])
			category.offers[#category.offers + 1] = {kind = "unlock", unlock = "hideout_" .. d.key, icon = icon,
				cost = d.source.price, name = d.name, gift = true,
				description = string.format("Hideout decoration (%s), for every character of your account. Cosmetic only: " ..
					"it changes how your hideout looks and nothing else. Character > Hideout.", CAT[d.cat] or d.cat)}
		end
	end
	return category
end
