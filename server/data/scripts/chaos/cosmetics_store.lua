-- cosmetics_store.lua: the store categories of the cosmetics (cosmetics.lua), built from cosmetics_config.lua so the
-- offers, names and prices live in one place. Used by the Cosmetics hunk of shop_config.lua:
--     dofile("data/scripts/chaos/cosmetics_store.lua")("killfx")
-- returns one category {name, icon, offers} with an offer {kind = "unlock", unlock = "cosmetic_<key>", icon, cost,
-- name, description, gift = false} per store cosmetic of that kind (achievement cosmetics are never sold).
-- No engine calls (server/tests/cosmetics_test.lua and shop_test.lua read it with plain Lua).

local cfg = dofile("data/scripts/chaos/cosmetics_config.lua")

local ICONS = {spellskin = 7762, killfx = 5944, lootbeam = 18418, chatcolor = 2146, footprint = 2187, outline = 2154}
local NOTES = {
	spellskin = " Seen by all. Character > Cosmetics.",
	killfx = " Seen by all. Character > Cosmetics.",
	lootbeam = " Character > Cosmetics.",
	chatcolor = " Character > Cosmetics.",
	footprint = " Seen by all. Character > Cosmetics.",
	outline = " Seen by all. Character > Cosmetics."
}

return function(kind)
	local category
	for _, k in ipairs(cfg.kinds) do
		if k.key == kind then
			category = {name = k.store or k.name, icon = {item = ICONS[kind] or 2160}, offers = {}}
		end
	end
	if not category then
		error("cosmetics_store.lua: unknown kind " .. tostring(kind))
	end
	for _, c in ipairs(cfg.cosmetics) do
		if c.kind == kind and c.source == "store" then
			category.offers[#category.offers + 1] = {kind = "unlock", unlock = "cosmetic_" .. c.key, icon = c.icon,
				cost = c.price, name = c.name, description = c.desc .. (NOTES[kind] or ""), gift = false}
		end
	end
	return category
end
