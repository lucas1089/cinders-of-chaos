-- chaos_aiss_art.lua: the creature looks of the free AI Sprite Studio sample pack (client pair 57) on the server side, behind
-- one switch. Loaded with  ChaosAissArt = dofile("data/lib/chaos_aiss_art.lua")  (server/tests/aiss_art_test.lua). Plain
-- Lua, no engine calls at load.
--
-- Pair switch (M.PAIR57, ON since 2026-10-30: pair 57 is on windows-assets; client/MANIFEST.md "Pair 57"). A client on pair
-- 56 or older has no outfits 3364..3370 (it would draw nothing, or stop on a look id past its last outfit). On: the rows of
-- client/tools/sprites/monster_looks/aiss_picks.csv are appended to picks.csv (server/tools/apply_monster_looks.py writes
-- the looks below into the monsters' files), tools/ci/check_content.py PAIR_OUTFITS follows the pair (3370 outfits) and the
-- two client files (outfit_anchors.lua, info_lifts.lua) are regenerated from it. Off: the monsters keep the stock looks named
-- below.
--
-- What it holds (art: client/tools/sprites/gen_aiss_art.py, docs/CREDITS.md "AI Sprite Studio"): seven hunt monsters, all
-- 2x2 looks of four directions, none of them placed on a map yet (the hunt plans take them later).

local M = {}

M.PAIR57 = true

-- monster name -> {look once the switch is on, stock look the file has before}
M.monsters = {
	["Gloamgeode Shellback"] = {look = 3364, stock = 197},
	["Wickstaff Hexmage"] = {look = 3365, stock = 9},
	["Bogtusk Cleaver"] = {look = 3366, stock = 7},
	["Redmane Anvilbreaker"] = {look = 3367, stock = 253},
	["Marshlight Hollowseer"] = {look = 3368, stock = 99},
	["Gravecrown Oathbreaker"] = {look = 3369, stock = 131},
	["Coralcrown Brinecaller"] = {look = 3370, stock = 47}
}

-- the look a monster should carry now
function M.lookOf(name, current)
	local m = M.monsters[name]
	if not m then
		return current
	end
	return M.PAIR57 and m.look or m.stock
end

return M
