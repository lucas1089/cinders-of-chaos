-- quest_spell_scale_config.lua: the class factor of the line spell quest spells (server/README.md "Line spell quests",
-- server/data/spells/README.md "Line spell quests, level 1200 ultimates"). A quest spell is shared by the base class and both
-- ascensions, whose best sets differ, so one coefficient adds 3% to one class and 12% to the next. Each class has its own factor,
-- applied to the hit by the attack kit (data/spells/chaos/_attackkit.lua A.classFactor): Q1 (level 500) fitted so it adds about 4.5% to
-- the class's baseline best set at levels 500 to 800, Q3 (level 1200) so the ultimate adds about 9% on top. The spell factor
-- of spell_factor_config.lua is NOT touched: a character without the quests keeps the damage it always had.
-- Measured and checked by server/tools/rotation_sim.py --quest / --check. A class or spell not listed has factor 1.
-- A factor is a number, or a curve {{level, factor}, ...} (flat below the first point, linear between points, the last point's
-- value above it) for a class whose best set drifts away from the spell as the level grows: the Necromancer and the Bone Lord
-- (Soulflay Wave finds a slot at 500 and none from 880-900 on with one number: the Bone Lord's best set changes there) and the
-- Beastmaster (Moonshard Rain gained 3% at 500 and 10% at 1200). Class identity pass (2026-10-28): every class now gets about
-- 4.5% from Q1 at every level from 500 to 1200 (1.5-9% is checked) and 12-15% from both quests at 1200.
-- Plain table, Lua 5.1 / LuaJIT and Lua 5.3 compatible.
ChaosQuestSpellScale = {
	["Keepfall"] = {["Warrior"] = 0.95, ["Juggernaut"] = 0.89, ["Berserker"] = 0.98},
	["Judgment of Iron"] = {["Warrior"] = 0.86, ["Juggernaut"] = 0.84, ["Berserker"] = 0.85},
	["Moonshard Rain"] = {["Ranger"] = 0.77, ["Deadeye"] = 0.75, ["Beastmaster"] = {{500, 0.77}, {800, 0.67}, {1000, 0.63}, {1200, 0.58}}},
	["Dawnbreaker Shot"] = {["Ranger"] = 0.78, ["Deadeye"] = 1.08, ["Beastmaster"] = 0.39},
	["Prismatic Rupture"] = {["Mystic"] = 0.89, ["Elementalist"] = 1.06, ["Illusionist"] = 1.18},
	["Eclipse of Ruin"] = {["Mystic"] = 0.78, ["Elementalist"] = 1.29, ["Illusionist"] = 0.87},
	["Eclipse Edge"] = {["Thief"] = 1.37, ["Ninja"] = 0.58, ["Samurai"] = 0.83},
	["Death Between Heartbeats"] = {["Thief"] = 1.00, ["Ninja"] = 0.89, ["Samurai"] = 1.04},
	["Soulflay Wave"] = {["Necromancer"] = {{500, 0.29}, {800, 0.44}, {1000, 0.53}, {1200, 0.65}}, ["Lich"] = 0.86, ["Bone Lord"] = {{500, 0.17}, {800, 0.32}, {880, 0.35}, {900, 1.26}, {1000, 1.30}, {1200, 1.45}}},
	["Funeral of Kings"] = {["Necromancer"] = 0.88, ["Lich"] = 1.01, ["Bone Lord"] = 1.03},
	["Thousand-Echo Palm"] = {["Monk"] = 0.85, ["Shadowfist"] = 0.25, ["Iron Sage"] = 1.01},
	["Heaven's Ninth Gate"] = {["Monk"] = 0.82, ["Shadowfist"] = 0.81, ["Iron Sage"] = 0.82},
	["Pyre of Absolution"] = {["Templar"] = 0.85, ["Inquisitor"] = 0.69, ["Sentinel"] = 0.78},
	["Hammer of Ember Dawn"] = {["Templar"] = 0.97, ["Inquisitor"] = 0.71, ["Sentinel"] = 0.84},
}

return ChaosQuestSpellScale
