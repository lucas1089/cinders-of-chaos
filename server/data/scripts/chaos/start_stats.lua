-- New characters: the level they start at and the health, mana, capacity and soul of every class: the one source of
-- truth for new characters (server/README.md "New players", docs/CLASSES.md "Starting stats"). Data only, no engine
-- calls. Read by
--   newplayer_core.lua    NP.statsFor / NP.statsFix: the one-time login correction of characters below their class
--   the website           plugins/chaos/lib.php chaos_start_stats (character.created hook: website form and client)
--   tools/linux/server/add-account.sh and tools/windows/test_accounts.sql (checked by server/tests/start_stats_test.lua)
-- KEEP ONE ROW PER LINE in the form
--   `[id] = {health = H, mana = M, cap = C, soul = S, gainhp = GH, gainmana = GM, gaincap = GC}, -- Name`
-- and `startLevel = N,` / `startExperience = N,` on lines of their own: the website and add-account.sh read this file
-- with a pattern, not with Lua.
--
-- Owner design 2026-10-16: no tutorial island. A character is created at level `startLevel` (8) with exactly the
-- experience of that level, in the temple of Cinderhold, wearing its kit. Its stats at a level are its level 1 row plus
-- (level - 1) times its vocation gains per level (gainhp / gainmana / gaincap, the same numbers as
-- data/XML/chaos_vocations*.xml, which the test checks), as the engine adds them on a level-up: the Mystic starts level 8
-- with 150 + 7 x 5 = 185 health, 90 + 7 x 30 = 300 mana and 400 + 7 x 10 = 470 cap.
-- The level 1 values follow the gains (the more health a class gains, the more it starts with, and so on); casters
-- start with mana for their first spells many times over. An ascended class starts like its base class. cap is in
-- ounces (the players table's `cap`; the engine counts hundredths).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
return {
	stats = {
		[0] = {health = 150, mana = 0, cap = 400, soul = 100, gainhp = 5, gainmana = 5, gaincap = 10}, -- None (staff characters)
		[4] = {health = 185, mana = 35, cap = 470, soul = 100, gainhp = 15, gainmana = 5, gaincap = 25}, -- Warrior
		[8] = {health = 185, mana = 35, cap = 470, soul = 100, gainhp = 15, gainmana = 5, gaincap = 25}, -- Juggernaut
		[14] = {health = 185, mana = 35, cap = 470, soul = 100, gainhp = 14, gainmana = 6, gaincap = 25}, -- Berserker
		[3] = {health = 165, mana = 60, cap = 440, soul = 100, gainhp = 10, gainmana = 15, gaincap = 20}, -- Ranger
		[7] = {health = 165, mana = 60, cap = 440, soul = 100, gainhp = 10, gainmana = 15, gaincap = 20}, -- Deadeye
		[15] = {health = 165, mana = 60, cap = 440, soul = 100, gainhp = 11, gainmana = 14, gaincap = 21}, -- Beastmaster
		[1] = {health = 150, mana = 90, cap = 400, soul = 100, gainhp = 5, gainmana = 30, gaincap = 10}, -- Mystic
		[5] = {health = 150, mana = 90, cap = 400, soul = 100, gainhp = 5, gainmana = 30, gaincap = 10}, -- Elementalist
		[10] = {health = 150, mana = 90, cap = 400, soul = 100, gainhp = 7, gainmana = 27, gaincap = 12}, -- Illusionist
		[11] = {health = 175, mana = 45, cap = 455, soul = 100, gainhp = 12, gainmana = 10, gaincap = 22}, -- Thief
		[12] = {health = 175, mana = 45, cap = 455, soul = 100, gainhp = 12, gainmana = 10, gaincap = 22}, -- Ninja
		[13] = {health = 175, mana = 45, cap = 455, soul = 100, gainhp = 13, gainmana = 9, gaincap = 24}, -- Samurai
		[17] = {health = 175, mana = 45, cap = 455, soul = 100, gainhp = 12, gainmana = 10, gaincap = 22}, -- Monk
		[18] = {health = 175, mana = 45, cap = 455, soul = 100, gainhp = 12, gainmana = 10, gaincap = 22}, -- Shadowfist
		[19] = {health = 175, mana = 45, cap = 455, soul = 100, gainhp = 14, gainmana = 9, gaincap = 25}, -- Iron Sage
		[20] = {health = 155, mana = 80, cap = 410, soul = 100, gainhp = 8, gainmana = 26, gaincap = 13}, -- Necromancer
		[21] = {health = 155, mana = 80, cap = 410, soul = 100, gainhp = 7, gainmana = 28, gaincap = 12}, -- Lich
		[22] = {health = 155, mana = 80, cap = 410, soul = 100, gainhp = 9, gainmana = 24, gaincap = 15}, -- Bone Lord
		[23] = {health = 180, mana = 40, cap = 465, soul = 100, gainhp = 14, gainmana = 8, gaincap = 25}, -- Templar
		[24] = {health = 180, mana = 40, cap = 465, soul = 100, gainhp = 13, gainmana = 10, gaincap = 24}, -- Inquisitor
		[25] = {health = 180, mana = 40, cap = 465, soul = 100, gainhp = 14, gainmana = 7, gaincap = 25} -- Sentinel
	},
	startLevel = 8,
	startExperience = 4200,
	-- the login correction (NP.statsFix): characters up to this level whose maximum health, mana or capacity is below
	-- their class's for their level (made before this file, by an old add-account.sh, or with the website's flat 150 / 0
	-- / 400) are raised to it, once (never lowered)
	fixUpToLevel = 8
}
