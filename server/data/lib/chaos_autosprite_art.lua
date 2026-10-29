-- chaos_autosprite_art.lua: the creature looks of our AutoSprite renders (client pair 54) on the server side, behind one
-- switch. Loaded with  ChaosAutospriteArt = dofile("data/lib/chaos_autosprite_art.lua")  (server/tests/
-- autosprite_art_test.lua). Plain Lua, no engine calls at load.
--
-- Pair switch (M.PAIR54, ON since 2026-10-28: pair 56, which holds pair 54, is on windows-assets; client/MANIFEST.md "Pair 54"). A client
-- on pair 53 or older has no outfits 3361..3363 (it would draw nothing, or stop on a look id past its last outfit). On:
-- the rows of client/tools/sprites/monster_looks/autosprite_picks.csv are appended to picks.csv (server/tools/
-- apply_monster_looks.py writes the looks below into the monsters' files) and tools/ci/check_content.py PAIR_OUTFITS
-- follows the pair. Off: the monsters keep the stock looks named below.
--
-- What it holds (art: client/tools/sprites/gen_autosprite_art.py, docs/CREDITS.md "AutoSprite"):
--   * look 3361 (4x4): Vharzul the Verdant Eye, boss of the Embergut Rift (server/tools/areaplan/plans/embergut_rift.json,
--     levels 560-675);
--   * looks 3362 and 3363 (2x2): the Ashbound Thrall and the Slagback Hound, hunt monsters of the same rift.

local M = {}

M.PAIR54 = true

-- monster name -> {look once the switch is on, stock look the file has before}
M.monsters = {
	["Vharzul the Verdant Eye"] = {look = 3361, stock = 35},
	["Ashbound Thrall"] = {look = 3362, stock = 40},
	["Slagback Hound"] = {look = 3363, stock = 240}
}

-- the look a monster should carry now
function M.lookOf(name, current)
	local m = M.monsters[name]
	if not m then
		return current
	end
	return M.PAIR54 and m.look or m.stock
end

return M
