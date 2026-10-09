-- Settings of the boss passive points (bosspoints.lua, pure rules in bosspoints_core.lua, server/README.md "Boss
-- passive points"). The first kill of each boss below gives the character +1 passive tree point, kept for good: it is
-- part of the tree's point budget (passivetree.lua totalPoints), so it survives every reset, refund and build code.
-- Returned as a table; bosspoints_core.lua puts it in Chaos.bossPoints.
return {
	enabled = true,

	-- player storages: storageBase + 0 = retroVersion once the old kills were checked at login; storageBase + id = 1 once
	-- the point of boss `id` was given. 7101400 - 7101419 reserved (inside the Chaos storage space, see
	-- chaos_constants.lua). An id is never reused or renumbered: removing a boss takes its point back at the next login
	-- (the tree's free refund then empties a tree that holds more nodes than the points behind it).
	storageBase = 7101400,
	maxId = 19,

	-- raise to check every character's old kills once more at its next login (only adds missing points)
	retroVersion = 1,

	-- credit (as the bestiary and the bounty board): every player that hurt the boss (summons count for their master),
	-- the last hit and the most damage, and the party members of each of them within partyRange tiles on the same floor
	partyRange = 30,

	-- name = the monster type (data/monster), matched in lower case on the TYPE name, so a renamed spawn (the Trial
	-- guardian is dressed per class, invasion bosses get titles) still counts. label = what the window shows.
	-- retro: where an older kill can be found at the first login after this feature:
	--   bestiary = the chaos_bestiary row of this monster (kills > 0; the killer, the most damage and their party)
	--   stat = a chaos_achievement_stats row (> 0): the world boss reward stats of achievements.lua
	--   storage = {key, atLeast}: a player storage (the Ascension Trial's stage, ascension_quest_config.lua)
	bosses = {
		{id = 1, name = "Kaelgor the Infernal Warlord", label = "Kaelgor (world boss)", retro = {bestiary = true, stat = "wb_kaelgor"}},
		{id = 2, name = "Skaldra the Rime Queen", label = "Skaldra (world boss)", retro = {bestiary = true, stat = "wb_skaldra"}},
		{id = 3, name = "The Rotmother", label = "The Rotmother (world boss)", retro = {bestiary = true, stat = "wb_rotmother"}},
		{id = 4, name = "Nyxareth the Void Archon", label = "Nyxareth (world boss)", retro = {bestiary = true, stat = "wb_nyxareth"}},
		{id = 5, name = "Vharok the Blood Colossus", label = "Vharok (world boss)", retro = {bestiary = true, stat = "wb_vharok"}},
		-- the guardian of the Ascension Trial (every class's Warden is this type); stage 3 = Trial won, 4 = ascended
		{id = 6, name = "Ascension Warden", label = "Trial Warden (ascension)", retro = {storage = {key = 7101000, atLeast = 3}}},
		{id = 7, name = "Ghazbaran", label = "Ghazbaran (invasion, tower)", retro = {bestiary = true}},
		{id = 8, name = "Apocalypse", label = "Apocalypse", retro = {bestiary = true}},
		{id = 9, name = "Ferumbras Mortal Shell", label = "Ferumbras Mortal Shell", retro = {bestiary = true}},
		{id = 10, name = "Gaz'haragoth", label = "Gaz'haragoth", retro = {bestiary = true}}
	}
}
