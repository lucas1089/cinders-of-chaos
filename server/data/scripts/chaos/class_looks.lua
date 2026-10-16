-- class_looks.lua: the class's default look (rules and the list: class_looks_core.lua, docs/CLASSES.md "Class looks").
--   first login (character creation): the looks of the class are given and the class's look is put on, in the
--   class's start colours (L.startColors)
--   every later login: looks of the class the character does not own yet are given, both addons with each; the worn
--   look stays, except a class look of the character that just got its addons (worn with them from now) or a look the
--   pair switch replaced (ChaosClassLooks.PAIR19_LOOKS, PAIR20_LOOKS: the new look of its sex is put on)
--   a class change (ascension.lua ChaosClasses.afterVocationChange calls ChaosClassLooks.apply(player, true)): the new
--   class's look is given and put on
-- Nothing is ever taken away. Colours, mount and the other outfit parts stay the player's. A class look is worn
-- with both addons (ChaosClassLooks.ADDONS).
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosClassLooks or not ChaosClassLooks.looks then
	dofile("data/scripts/chaos/class_looks_core.lua")
end
local L = ChaosClassLooks

-- gives the class's looks with both addons (only these looks' addons); with wear, puts the class's look on; at
-- other logins a worn class look of the character gets its addons once, and a look a pair switch replaced
-- becomes the new one (ChaosClassLooks.loginOutfit). Returns the number of looks added.
function L.apply(player, wear, first)
	local voc, sex = player:getVocation():getId(), player:getSex()
	local added, granted = 0, {}
	for _, look in ipairs(L.unlocksFor(voc, sex)) do
		local had = player:hasOutfit(look)
		if not player:hasOutfit(look, L.ADDONS) then
			player:addOutfitAddon(look, L.ADDONS)
			granted[look] = player:hasOutfit(look, L.ADDONS) or nil
		end
		if not had and player:hasOutfit(look) then
			added = added + 1
		end
	end
	-- first: a new character's first login: the class look in the class's start colours (L.startOutfit)
	local outfit = first and L.startOutfit(player:getOutfit(), voc, sex) or L.loginOutfit(player:getOutfit(), voc, sex, wear, granted)
	-- only a look the engine lets the character wear with these addons (outfits.xml knows it for this sex)
	if outfit and player:hasOutfit(outfit.lookType, outfit.lookAddons) then
		player:setOutfit(outfit)
	end
	return added
end

local login = CreatureEvent("ChaosClassLooksLogin")
function login.onLogin(player)
	local first = L.isFirstLogin(player:getLastLoginSaved())
	local ok, err = pcall(L.apply, player, first, first)
	if not ok then
		print("[Chaos class looks] " .. tostring(err))
	end
	return true
end
login:register()
