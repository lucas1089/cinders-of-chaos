-- class_looks.lua: the class's default look (rules and the list: class_looks_core.lua, docs/CLASSES.md "Class looks").
--   first login (character creation): the looks of the class are given and the class's look is put on
--   every later login: looks of the class the character does not own yet are given; the worn look stays
--   a class change (ascension.lua ChaosClasses.afterVocationChange calls ChaosClassLooks.apply(player, true)): the new
--   class's look is given and put on
-- Nothing is ever taken away. Colours, mount and the other outfit parts stay the player's.
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosClassLooks or not ChaosClassLooks.looks then
	dofile("data/scripts/chaos/class_looks_core.lua")
end
local L = ChaosClassLooks

-- gives the class's looks; with wear, puts the class's look on. Returns the number of looks added.
function L.apply(player, wear)
	local voc, sex = player:getVocation():getId(), player:getSex()
	local added = 0
	for _, look in ipairs(L.unlocksFor(voc, sex)) do
		if not player:hasOutfit(look) then
			player:addOutfit(look)
			if player:hasOutfit(look) then
				added = added + 1
			end
		end
	end
	if wear then
		local look = L.lookFor(voc, sex)
		local outfit = L.wearOutfit(player:getOutfit(), voc, sex)
		-- only a look the engine lets the character wear (outfits.xml knows it for this sex)
		if outfit and player:hasOutfit(look) then
			player:setOutfit(outfit)
		end
	end
	return added
end

local login = CreatureEvent("ChaosClassLooksLogin")
function login.onLogin(player)
	local ok, err = pcall(L.apply, player, L.isFirstLogin(player:getLastLoginSaved()))
	if not ok then
		print("[Chaos class looks] " .. tostring(err))
	end
	return true
end
login:register()
