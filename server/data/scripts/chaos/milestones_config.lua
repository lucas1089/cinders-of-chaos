-- Level milestones (O378; milestones.lua, milestones_core.lua; tests/milestones_test.lua; server/README.md "Level
-- milestones (O378)"): one landmark every 100 levels from 800 to 2200, where the leveling is flat (10-14 minutes a level,
-- tools/progression_model.lua). Every number. Plain data, no engine calls; read with plain Lua by goals_config.lua and
-- the test. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- What a milestone gives, and which system gives it (nothing is duplicated):
--   achievement  "level_<L>" of achievements_data.lua (category "milestones"): points, the title on the name plate, the
--                ACHIEVEMENT UNLOCKED toast. Retroactive at login like every level achievement.
--   cosmetic     level_1000 / level_1500 / level_2000 unlock a level-up effect (cosmetics_config.lua, account wide); the
--                whole category (level 2200) a kill effect and the title "Hundredfold".
--   cache        the Milestone Cache below: crafting orbs, given once by milestones.lua (backpack, inbox when full).
--                Only for milestones reached from now on: a character already past one when the system first sees it
--                gets no cache for it (`storage` baseline).
--   broadcast    one short line to the server (`broadcast`), the LEVEL MILESTONE toast to the character.
--   challenge    a Next Goals goal unlocked at the milestone (goals_config.lua adds it): an Infinity Tower floor or a
--                number of pocket boss kills, paid by Next Goals' small default reward.
--   next goal    Next Goals shows "Reach level <next>" with the next milestone's title and cache (goals_config.lua).
local UPHEAVAL, FATE, GRAFTING = 29856, 29857, 29855 -- Orb of Upheaval, Orb of Fate, Orb of Grafting (loot_config.lua)

local C = {}

C.enabled = true
C.first, C.last, C.step = 800, 2200, 100
C.staffGroup = 4 -- staff characters get no cache and no broadcast

-- player storage, block 7101080 - 7101089 (server/README.md "Storage keys"): +0 = the highest milestone level whose cache
-- was given or skipped; -1 / unset = the system has not seen the character yet (the first login sets the baseline)
C.storage = 7101080

-- the broadcast: on (the owner's opt-in switch), short, only for a milestone reached live (never the login baseline);
-- one line per character per advance (several milestones in one advance: the highest)
C.broadcast = {enabled = true, minLevel = 800}

-- orbs of the cache. Orb drops while hunting at level 800-2200 (loot_config.lua currency, normal tier, about 840 kills
-- an hour): about 4 Upheaval, 2 Fate and 0.4 Grafting an hour. The 15 caches add up to 116 Upheaval, 48 Fate and 5
-- Grafting over the about 290 hours from 800 to 2200: under a tenth of the orbs hunted on the way. Level 500 and 700
-- give 5 + 1 and 5 + 2 (achievements_data.lua), so 800 starts there.
-- cache[i] is the count of orbs[i]; the names are the item names (for the Next Goals line, which has no ItemType)
C.orbs = {{id = UPHEAVAL, name = "Orb of Upheaval"}, {id = FATE, name = "Orb of Fate"}, {id = GRAFTING, name = "Orb of Grafting"}}

-- the milestones, in level order. cache = {upheaval, fate, grafting}; challenge = the Next Goals goal unlocked at the
-- level: {stat = "tower_floor", target = floor} (floors from tools/tower_model.py reach of the median class: L800 34,
-- L1000 44, L1500 64, L2000 93, rounded down to 5) or {stat = "pocket_kills", target = kills} (all pocket bosses, the
-- big milestones 1000 / 1500 / 2000)
C.list = {
	{level = 800, cache = {5, 2, 0}, challenge = {stat = "tower_floor", target = 30}},
	{level = 900, cache = {5, 2, 0}, challenge = {stat = "tower_floor", target = 35}},
	{level = 1000, cache = {6, 2, 1}, challenge = {stat = "pocket_kills", target = 100}},
	{level = 1100, cache = {6, 2, 0}, challenge = {stat = "tower_floor", target = 45}},
	{level = 1200, cache = {6, 3, 0}, challenge = {stat = "tower_floor", target = 50}},
	{level = 1300, cache = {7, 3, 0}, challenge = {stat = "tower_floor", target = 55}},
	{level = 1400, cache = {7, 3, 0}, challenge = {stat = "tower_floor", target = 60}},
	{level = 1500, cache = {8, 3, 1}, challenge = {stat = "pocket_kills", target = 200}},
	{level = 1600, cache = {8, 3, 0}, challenge = {stat = "tower_floor", target = 65}},
	{level = 1700, cache = {8, 4, 0}, challenge = {stat = "tower_floor", target = 75}},
	{level = 1800, cache = {9, 4, 0}, challenge = {stat = "tower_floor", target = 80}},
	{level = 1900, cache = {9, 4, 0}, challenge = {stat = "tower_floor", target = 85}},
	{level = 2000, cache = {10, 4, 1}, challenge = {stat = "pocket_kills", target = 300}},
	{level = 2100, cache = {10, 4, 0}, challenge = {stat = "tower_floor", target = 95}},
	{level = 2200, cache = {12, 5, 2}, challenge = {stat = "tower_floor", target = 100}}
}

-- the texts. Engine texts are English keys of Chaos.t (pt-BR in i18n_strings.lua); the Next Goals texts are {en, pt}
-- pairs (goals_config.lua has no Chaos.t). %s / %d in the order milestones_core.lua passes them.
C.texts = {
	toastTitle = "Level %d",
	toast = "Milestone reached. Title: %s. Milestone Cache: %s.",
	toastNext = "Next milestone: level %d.",
	inbox = "Your backpack was full: see your inbox.",
	broadcast = "%s reached level %d and earned the title %s.",
	goals = {
		why = {en = "Milestone: the title %s and a Milestone Cache (%s).", pt = "Marco: o título %s e um Milestone Cache (%s)."},
		tower = {en = "Milestone %d: clear Infinity Tower floor %d", pt = "Marco %d: conclua o andar %d da Infinity Tower"},
		pocket = {en = "Milestone %d: defeat %d pocket bosses", pt = "Marco %d: derrote %d chefes de bolso"},
		challengeWhy = {en = "The challenge of your level milestone.", pt = "O desafio do seu marco de nível."},
		towerEffort = {en = "One climb in your best gear.", pt = "Uma subida com seu melhor equipamento."},
		pocketEffort = {en = "A few weeks of charges.", pt = "Algumas semanas de cargas."}
	}
}

return C
