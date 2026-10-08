-- shop_config.lua: offers of the Chaos store (shop.lua). Plain table, loaded with
--     ChaosShopConfig = dofile("data/scripts/chaos/shop_config.lua")
-- Prices are in Chaos Coins (table chaos_shop_coins, per account).
-- Offer kinds:
--   {kind = "item", id = <server id>, count = n}            item(s) into the backpack
--   {kind = "wings" | "aura", id = <id in data/XML/wings.xml / auras.xml>}   cosmetic, bought once
--   {kind = "shader", id = <id in data/XML/shaders.xml>}     outfit shader, bought once
--   {kind = "outfit", looktype = male, lookfemale = female, addons = 0..3}   bought once
--   {kind = "mount", id = <mount id>, clientid = <look type>}               bought once
--   {kind = "premium", days = n}
-- Names, descriptions and the category icon are what the client shows. Cosmetics without a name take
-- the one from their XML file.

-- outfit the cosmetics are previewed on
local PREVIEW = {type = 128, head = 114, body = 94, legs = 94, feet = 114, addons = 3}

local function preview(extra)
	local o = {}
	for k, v in pairs(PREVIEW) do
		o[k] = v
	end
	for k, v in pairs(extra or {}) do
		o[k] = v
	end
	o.rotating = true
	return o
end

return {
	opcode = 218,
	perPage = 10,
	giftMin = 10, -- smallest coin gift
	purchaseEffect = CONST_ME_FIREWORK_YELLOW,
	categories = {
		{
			name = "Chaos Currency", icon = {item = 29856},
			offers = {
				{kind = "item", id = 29856, count = 1, cost = 10, name = "Chaos Orb", description = "Rerolls the modifiers of a magic or rare item."},
				{kind = "item", id = 29856, count = 10, cost = 90, name = "10 Chaos Orbs", description = "A pouch of ten Chaos Orbs."},
				{kind = "item", id = 29856, count = 50, cost = 400, name = "50 Chaos Orbs", description = "A chest of fifty Chaos Orbs."},
				{kind = "item", id = 29857, count = 1, cost = 25, name = "Divine Orb", description = "Rerolls the values of an item's modifiers."},
				{kind = "item", id = 29857, count = 10, cost = 225, name = "10 Divine Orbs", description = "A pouch of ten Divine Orbs."}
			}
		},
		{
			name = "Supplies", icon = {item = 7590, count = 100},
			offers = {
				{kind = "item", id = 7590, count = 100, cost = 15, name = "100 Great Mana Potions", description = "Restores a large amount of mana."},
				{kind = "item", id = 8472, count = 100, cost = 15, name = "100 Great Spirit Potions", description = "Restores health and mana."},
				{kind = "item", id = 8473, count = 100, cost = 20, name = "100 Ultimate Health Potions", description = "Restores a large amount of health."},
				{kind = "item", id = 26031, count = 100, cost = 30, name = "100 Supreme Health Potions", description = "Restores a huge amount of health."},
				{kind = "item", id = 2268, count = 100, cost = 20, name = "100 Reaper's Runes", description = "Death damage to a single target."},
				{kind = "item", id = 2304, count = 100, cost = 15, name = "100 Searing Orb Runes", description = "Fire damage in an area."},
				{kind = "item", id = 2273, count = 100, cost = 15, name = "100 Grand Mending Runes", description = "Heals a large amount of health."},
				{kind = "item", id = 2365, count = 1, cost = 50, name = "Backpack of Holding", description = "A backpack with more room than any other."}
			}
		},
		{
			name = "Wings", icon = {outfit = preview({wings = 937})},
			offers = {
				{kind = "wings", id = 1, cost = 250}, {kind = "wings", id = 4, cost = 250}, {kind = "wings", id = 7, cost = 300},
				{kind = "wings", id = 8, cost = 300}, {kind = "wings", id = 9, cost = 300}, {kind = "wings", id = 12, cost = 350},
				{kind = "wings", id = 13, cost = 350}, {kind = "wings", id = 2, cost = 200}, {kind = "wings", id = 3, cost = 200},
				{kind = "wings", id = 5, cost = 200}, {kind = "wings", id = 6, cost = 250}, {kind = "wings", id = 10, cost = 250},
				{kind = "wings", id = 11, cost = 200}, {kind = "wings", id = 14, cost = 250}, {kind = "wings", id = 15, cost = 250}
			}
		},
		{
			name = "Auras", icon = {outfit = preview({aura = 932})},
			offers = {
				{kind = "aura", id = 1, cost = 200}, {kind = "aura", id = 2, cost = 200}, {kind = "aura", id = 3, cost = 200},
				{kind = "aura", id = 4, cost = 150}, {kind = "aura", id = 5, cost = 200}
			}
		},
		{
			name = "Outfit Shaders", icon = {outfit = preview({shader = "red_energizer"})},
			offers = {
				{kind = "shader", id = 11, cost = 150, name = "Blood Pulse", description = "A pulsing crimson glow."},
				{kind = "shader", id = 6, cost = 150, name = "Crimson Waves", description = "Red waves rolling over your outfit."},
				{kind = "shader", id = 3, cost = 120, name = "Ember Haze", description = "A smouldering red haze."},
				{kind = "shader", id = 14, cost = 150, name = "Infernal Pulse", description = "An orange, fiery pulse."},
				{kind = "shader", id = 9, cost = 150, name = "Void Pulse", description = "A pulsing violet glow."},
				{kind = "shader", id = 10, cost = 150, name = "Frost Pulse", description = "A pulsing icy glow."},
				{kind = "shader", id = 1, cost = 120, name = "Frost Haze", description = "A cold blue haze."},
				{kind = "shader", id = 8, cost = 150, name = "Venom Waves", description = "Green waves rolling over your outfit."},
				{kind = "shader", id = 13, cost = 150, name = "Spectral Pulse", description = "A pale, ghostly pulse."},
				{kind = "shader", id = 15, cost = 180, name = "Golden Sparks", description = "Gold sparks dancing on your outfit."},
				{kind = "shader", id = 17, cost = 180, name = "Arcane Sparks", description = "Blue sparks dancing on your outfit."}
			}
		},
		{
			name = "Outfits", icon = {outfit = {type = 909, head = 2, body = 116, legs = 114, feet = 114, addons = 3, rotating = true}},
			offers = {
				{kind = "outfit", looktype = 909, lookfemale = 909, addons = 3, cost = 750, name = "Shadowlotus Outfit", description = "Full Shadowlotus outfit with both addons."},
				{kind = "outfit", looktype = 1237, lookfemale = 1237, addons = 3, cost = 750, name = "Blade Dancer Outfit", description = "Full Blade Dancer outfit with both addons."}
			}
		},
		{
			name = "Mounts", icon = {outfit = {type = 1236, rotating = true}},
			offers = {
				{kind = "mount", id = 121, clientid = 1236, cost = 690, name = "Crimson Fang", description = "A blood-red war beast."},
				{kind = "mount", id = 119, clientid = 1234, cost = 690, name = "Glacier Wyrm", description = "A wyrm of living ice."},
				{kind = "mount", id = 120, clientid = 1235, cost = 690, name = "Bog Tyrant", description = "A tyrant of the swamps."},
				{kind = "mount", id = 104, clientid = 928, cost = 450, name = "Spirit of Purity", description = "A radiant spirit steed."}
			}
		},
		{
			name = "Premium Time", icon = {item = 16101},
			offers = {
				{kind = "premium", days = 30, cost = 250, name = "30 Days of Premium", description = "Premium account for 30 days."},
				{kind = "premium", days = 90, cost = 650, name = "90 Days of Premium", description = "Premium account for 90 days."},
				{kind = "premium", days = 180, cost = 1200, name = "180 Days of Premium", description = "Premium account for 180 days."}
			}
		}
	}
}
