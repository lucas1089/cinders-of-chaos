-- chaos_eye_demon_art.lua: the Verdant Eye Demon look of the client pair 54 on the server side, behind one switch.
-- Loaded with  ChaosEyeDemonArt = dofile("data/lib/chaos_eye_demon_art.lua")  (server/tests/eye_demon_art_test.lua).
-- Plain Lua, no engine calls at load.
--
-- Pair switch (M.PAIR54, OFF: pair 54 is built but not on windows-assets yet; client/MANIFEST.md "Pair 54"). A client
-- on pair 53 or older has no outfit 3361 (it would draw nothing, or stop on a look id past its last outfit). On: the
-- row of client/tools/sprites/monster_looks/eye_demon_picks.csv is appended to picks.csv (server/tools/
-- apply_monster_looks.py writes look 3361 into Vharzul's file) and tools/ci/check_content.py PAIR_OUTFITS follows the
-- pair. Off: Vharzul keeps the stock demon look.
--
-- What it holds (art: client/tools/sprites/gen_eye_demon_art.py, our own AutoSprite render, docs/CREDITS.md):
--   * one monster look 3361 (4x4): Vharzul the Verdant Eye, boss of the Embergut Rift (server/tools/areaplan/plans/
--     embergut_rift.json, levels 560-675).

local M = {}

M.PAIR54 = false

-- monster name -> look once the switch is on (before: the stock look the file has now)
M.monsters = {
	["Vharzul the Verdant Eye"] = 3361 -- before 35
}

-- the look a monster should carry now
function M.lookOf(name, current)
	if M.PAIR54 and M.monsters[name] then
		return M.monsters[name]
	end
	return current
end

return M
