-- Next Goals (goals.lua, goals_core.lua; client game_goals; server/README.md "Next Goals"): what a character should do
-- next, for EVERY character, from level 1 to 2000 and beyond. Data only, no engine calls (tests/goals_test.lua reads it
-- with plain Lua). Texts in English (en) and Brazilian Portuguese (pt).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Bands: the level ranges of the panel's header ("Level 300-499: World bosses"). Each band has hunts (where to level),
-- a gear path (where the next gear comes from) and goals.
--
-- A goal: {key, level, title, why, where, stat, target, effort, reward?, requires?}
--   key      stable id (stored in chaos_goals as "g:<key>"); never rename a live one
--   level    the level that unlocks it (shown as "unlocks at level N" before)
--   stat     "level", an own stat of `own` below, or any achievement counter (ChaosAchievements.stats: kills_magic,
--            rift_tier, wb_kills, dungeon_vault, ...); progress = min(value, target)
--   flag     true: progress shows as done / not done (a rank)
--   where    how the panel's button helps (goals_core.lua K.WHERE):
--              {k = "window", m = module, f = function}   opens a client window
--              {k = "info", page = "rift"}                the Info & Services page (game_chaosinfo)
--              {k = "tasks"}                              the Bestiary's kill tasks
--              {k = "finder", id = serverId}              the Item Finder on that item
--              {k = "npc", name = "..."}                  a mark on the map at that NPC (else the temple)
--              {k = "temple"}                             a mark at the character's temple
--              {k = "hunts"}                              a mark at the nearest hunting ground of its level
--              {k = "plan", id = "..."}                   a mark at the teleport of that content hunt
--              {k = "room"}                               a mark at the teleport room of Cinderhold
--   effort   expected effort, a short text
--   reward   {xpPct, gold, tokens}: overrides of `reward` below (xpPct = percent of the experience the character needs
--            for its next level; gold = gold coins to the bank; tokens = Conquest Tokens when that system runs)
--   requires a global the goal needs (hidden while it is missing): "ChaosConquest", "ChaosPocketBoss", ...
--
-- Rewards are small on purpose: a nudge, not a source of income. A goal is rewarded once per character; a character
-- that already did a goal of a band below its own when the panel first loads gets it marked done without a reward
-- (goals_core.lua K.retro).

local function T(en, pt)
	return {en = en, pt = pt}
end

local function W(k, extra)
	local w = {k = k}
	for key, v in pairs(extra or {}) do
		w[key] = v
	end
	return w
end

local function win(m, f)
	return W("window", {m = m, f = f or "toggle"})
end

-- "Reach level n", unlocked at `from` (the band before n: it is that band's last goal)
local function lvl(n, from)
	return {key = "lvl" .. n, level = from, stat = "level", target = n,
		title = T("Reach level " .. n, "Alcance o nível " .. n),
		why = T("New content, gear and goals unlock with every band.",
			"Novo conteúdo, equipamento e objetivos se abrem a cada faixa."),
		where = W("hunts"),
		effort = T("Hunt at your level; bounties and kill tasks add experience.",
			"Cace no seu nível; recompensas e tarefas de abate dão experiência extra.")}
end

local C = {}

C.enabled = true
C.opcode = 178 -- ChaosOpcodes.goals (chaos_constants.lua); client game_goals
C.requestMs = 400 -- one panel request per player per 400 ms (Chaos.limited)
C.staffGroup = 4 -- staff walk no goals (the panel shows them, nothing is rewarded)
C.checkMs = 250 -- a changed counter or level waits this long, so the changes of one kill are checked together
C.pushMs = 1000 -- the goals of a character are checked and pushed (tracker, open panel) at most this often
C.tracked = 3 -- goals in the on-screen tracker
C.catchUp = 6 -- open goals of bands below the character's own shown in the panel (the rest: "and N more")
C.upcoming = 3 -- locked goals shown under "Next unlocks"

-- database (server/sql/chaos_goals.sql; goals.lua also creates it): per character, "g:<key>" = a goal done
-- (value 1 rewarded, 2 found done at the first load, no reward) and "s:<stat>" = an own stat below
C.table = "chaos_goals"

-- own stats (not achievement counters): how a reported value adds up. Sources (goals.lua, no edits of the systems):
--   passive_spent    probe at login and panel open, and a ChaosPassiveTree listener (after every save):
--                    ChaosPassiveTree.hasAllocation (1 once a point is spent)
--   faction_rank     ChaosFactions.gain wrapped (the rank index after a gain; 4 Trusted, 5 Honored, 6 Revered)
--   pocket_kills     ChaosConquest.grant wrapped: a grant of a "pocketboss:<boss>" source (one per pocket boss kill)
--   conquest_earned  ChaosConquest.grant wrapped: the tokens granted
--   tower_floor      ChaosTower.recordRun wrapped (floors cleared in one run)
--   descent_*, dungeon_clears, atlas_points   ChaosSeasonJourney.emit wrapped (the lines descent.lua, dungeons.lua
--                    and atlas.lua already call for every character)
C.own = {
	passive_spent = "max", faction_rank = "max", pocket_kills = "add", conquest_earned = "add", tower_floor = "max",
	descent_runs = "add", descent_depth = "max", descent_clears = "add", dungeon_clears = "add", atlas_points = "max"
}

-- the default reward of a goal: xpPct percent of the experience to the next level, gold = goldPerLevel x level
-- (at least goldMin), tokens by band (index of the band, below); goal.reward overrides any of them
C.reward = {xpPct = 4, goldPerLevel = 25, goldMin = 200, tokens = {0, 0, 0, 2, 3, 4, 5, 6, 6, 8, 8, 10, 10}}

-- the teleport room of Cinderhold (hunt_teleports_config.lua room.back): the "room" mark without the placed hunts
C.room = {x = 31648, y = 32256, z = 6}

-- the content hunts of the teleport room (hunt_teleports_config.lua plans; level bands from
-- server/tools/areaplan/plans/<id>.json, checked by tests/goals_test.lua)
C.hunts = {
	{id = "bonechoir_catacomb", name = "Bonechoir Catacomb", level = {200, 290}},
	{id = "sulphur_gallery", name = "Sulphur Gallery", level = {215, 299}},
	{id = "hollow_crypt", name = "Hollow Crypt", level = {300, 400}},
	{id = "widowmere", name = "Widowmere", level = {480, 640}},
	{id = "wyrmspine_hollows", name = "Wyrmspine Hollows", level = {500, 640}},
	{id = "pyrarch_crucible", name = "Pyrarch Crucible", level = {520, 690}},
	{id = "hexwood_thicket", name = "Hexwood Thicket", level = {720, 840}},
	{id = "corsairs_reach", name = "Corsairs' Reach", level = {780, 900}},
	{id = "mirefang_basin", name = "Mirefang Basin", level = {880, 999}},
	{id = "rimecrown_depths", name = "Rimecrown Depths", level = {1000, 1120}},
	{id = "slagmourn_foundry", name = "Slagmourn Foundry", level = {1000, 1150}},
	{id = "cinderglass_sanctum", name = "Cinderglass Sanctum", level = {1120, 1300}},
	{id = "hollowmass_reliquary", name = "Hollowmass Reliquary", level = {1150, 1300}},
	{id = "gallowfen_mire", name = "Gallowfen Mire", level = {1300, 1450}},
	{id = "voidscar_chasm", name = "Voidscar Chasm", level = {1400, 1500}},
	{id = "gravehorn_deeps", name = "Gravehorn Deeps", level = {1500, 1750}},
	{id = "duskmarrow_crater", name = "Duskmarrow Crater", level = {1750, 2000}},
	{id = "gloomtooth_caverns", name = "Gloomtooth Caverns", level = {500, 615}},
	{id = "brackwater_sloughs", name = "Brackwater Sloughs", level = {515, 630}},
	{id = "sablemourn_ossuary", name = "Sablemourn Ossuary", level = {530, 645}},
	{id = "thornmantle_glade", name = "Thornmantle Glade", level = {545, 660}},
	{id = "embergut_rift", name = "Embergut Rift", level = {560, 675}},
	{id = "frostvein_reach", name = "Frostvein Reach", level = {575, 690}},
	{id = "ashwarden_catacombs", name = "Ashwarden Catacombs", level = {590, 705}},
	{id = "umbral_sink", name = "Umbral Sink", level = {605, 720}},
	{id = "cinderscour_barrens", name = "Cinderscour Barrens", level = {620, 735}},
	{id = "grimlock_vaults", name = "Grimlock Vaults", level = {635, 750}},
	{id = "blackmarble_halls", name = "Blackmarble Halls", level = {650, 765}},
	{id = "rotbloom_sanctum", name = "Rotbloom Sanctum", level = {665, 780}},
	{id = "hollowmaw_grotto", name = "Hollowmaw Grotto", level = {680, 795}},
	{id = "leechwater_fen", name = "Leechwater Fen", level = {695, 810}},
	{id = "dreadmourn_crypt", name = "Dreadmourn Crypt", level = {710, 825}},
	{id = "gallowroot_wilds", name = "Gallowroot Wilds", level = {725, 840}},
	{id = "scorchpit_delve", name = "Scorchpit Delve", level = {740, 855}},
	{id = "glacierfang_shelf", name = "Glacierfang Shelf", level = {755, 870}},
	{id = "bonewright_galleries", name = "Bonewright Galleries", level = {770, 885}},
	{id = "nightrend_abyss", name = "Nightrend Abyss", level = {785, 900}},
	{id = "sunderstone_wastes", name = "Sunderstone Wastes", level = {800, 915}},
	{id = "ironwick_treasury", name = "Ironwick Treasury", level = {815, 930}},
	{id = "obsidian_colonnade", name = "Obsidian Colonnade", level = {830, 945}},
	{id = "mildewveil_sanctum", name = "Mildewveil Sanctum", level = {845, 960}},
	{id = "deepgrudge_warrens", name = "Deepgrudge Warrens", level = {860, 975}},
	{id = "sorrowfen_marsh", name = "Sorrowfen Marsh", level = {875, 990}},
	{id = "shroudhallow_tomb", name = "Shroudhallow Tomb", level = {890, 1005}},
	{id = "hagthorn_weald", name = "Hagthorn Weald", level = {905, 1020}},
	{id = "pyreglass_chasm", name = "Pyreglass Chasm", level = {920, 1035}},
	{id = "rimeblood_glacier", name = "Rimeblood Glacier", level = {935, 1050}},
	{id = "lanternless_catacombs", name = "Lanternless Catacombs", level = {950, 1050}},
	{id = "scaldmoor_expanse", name = "Scaldmoor Expanse", level = {1050, 1200}},
	{id = "vespergloom_halls", name = "Vespergloom Halls", level = {1150, 1300}},
	{id = "wormcoil_depths", name = "Wormcoil Depths", level = {1250, 1400}},
	{id = "shiverspine_ridge", name = "Shiverspine Ridge", level = {1350, 1500}},
	{id = "ashen_sepulchre", name = "Ashen Sepulchre", level = {1450, 1600}},
	{id = "carrionwood", name = "Carrionwood", level = {1550, 1700}},
	{id = "dreadcoffer_vaults", name = "Dreadcoffer Vaults", level = {1625, 1775}},
	{id = "paleflame_sanctum", name = "Paleflame Sanctum", level = {1700, 1850}},
	{id = "blightmaw_bog", name = "Blightmaw Bog", level = {1775, 1925}},
	{id = "worldscar_abyss", name = "Worldscar Abyss", level = {1850, 2000}}
}

-- ------------------------------------------------------------------ bands
-- from = the first level; the last band has no end. gear = where the next gear of the band comes from, in order.
C.bands = {
	{key = "start", from = 1, name = T("First steps", "Primeiros passos"),
		text = T("Learn the basics: hunt, spend your first passive point, take a bounty.",
			"Aprenda o básico: cace, gaste seu primeiro ponto passivo, aceite uma recompensa."),
		gear = {
			{text = T("Your starter kit carries you to level 20.", "Seu kit inicial leva você até o nível 20.")},
			{text = T("Town shops sell weapons and armour for gold; the Loot Buyer at the temple (the arcade beside its entrance) buys your loot.",
				"As lojas da cidade vendem armas e armaduras por ouro; o Comprador de Saque no templo (a galeria ao lado da entrada) compra seu saque."),
				where = W("npc", {name = "Loot Buyer"})},
			{text = T("Magic (blue) monsters drop gear with a rarity: wear what is better.",
				"Monstros mágicos (azuis) soltam equipamento com raridade: use o que for melhor."), where = W("hunts")}
		}},
	{key = "rookie", from = 20, name = T("Finding your feet", "Pegando o jeito"),
		text = T("Kill tasks, crafting orbs and your first invasions.",
			"Tarefas de abate, orbes de criação e suas primeiras invasões."),
		gear = {
			{text = T("Rare (yellow) monsters drop better rolls; hunt where they spawn.",
				"Monstros raros (amarelos) soltam atributos melhores; cace onde eles aparecem."), where = W("hunts")},
			{text = T("Orbs of Upheaval reroll a piece on the Crafting Bench (Alt+C).",
				"Orbs of Upheaval rerrolam uma peça na Crafting Bench (Alt+C)."), where = win("game_crafting")},
			{text = T("Gems socket into gear; the Item Finder shows where each one drops.",
				"Gemas vão nos encaixes do equipamento; o Item Finder mostra onde cada uma cai."),
				where = win("game_itemfinder")}
		}},
	{key = "adept", from = 50, name = T("Adept", "Adepto"),
		text = T("The Arena, more bounties and rarer monsters.", "A Arena, mais recompensas e monstros mais raros."),
		gear = {
			{text = T("Bounty contracts pay gold and orbs every day.", "Contratos de recompensa pagam ouro e orbes todo dia."),
				where = win("game_bounty")},
			{text = T("The Gambler sells sealed pieces of your level.", "O Apostador vende peças lacradas do seu nível."),
				where = W("npc", {name = "Mordecai Ashwager"})},
			{text = T("Legendary (orange) monsters can drop uniques.", "Monstros lendários (laranja) podem soltar únicos."),
				where = W("hunts")}
		}},
	{key = "ascend", from = 100, name = T("Ascension", "Ascensão"),
		text = T("Ascend, open rifts, take the Vocation Trial and the Ember Descent.",
			"Ascenda, abra fendas, faça a Prova de Vocação e a Ember Descent."),
		gear = {
			{text = T("Rift chests: a unique roll at the rift's loot tier.", "Baús de fenda: uma chance de único no nível de saque da fenda."),
				where = W("info", {page = "rift"})},
			{text = T("Dungeon boss chests (Alt+J); the item level rises with the difficulty.",
				"Baús dos chefes de masmorra (Alt+J); o nível do item sobe com a dificuldade."), where = win("game_dungeons")},
			{text = T("Faction quartermasters sell fixed gear at Honored and Revered.",
				"Os intendentes das facções vendem equipamento fixo em Honrado e Reverenciado."), where = win("game_factions")}
		}},
	{key = "veteran", from = 200, name = T("Veteran", "Veterano"),
		text = T("The hunt teleports of Cinderhold, the Infinity Tower and Conquest Tokens.",
			"Os teleportes de caça de Cinderhold, a Infinity Tower e os Conquest Tokens."),
		gear = {
			{text = T("Hunt teleports in Cinderhold: Bonechoir Catacomb and Sulphur Gallery.",
				"Teleportes de caça em Cinderhold: Bonechoir Catacomb e Sulphur Gallery."), where = W("room")},
			{text = T("Conquest Tokens from every boss and clear buy any unique you have seen, at a fixed price.",
				"Conquest Tokens de cada chefe e conclusão compram qualquer único que você já viu, a preço fixo."),
				where = W("npc", {name = "Iselde Varrow"}), requires = "ChaosConquest"},
			{text = T("Archivist Maelis pays tales with gear and orbs.", "A Arquivista Maelis paga histórias com equipamento e orbes."),
				where = W("npc", {name = "Archivist Maelis"})}
		}},
	{key = "bosses", from = 300, name = T("World bosses", "Chefes mundiais"),
		text = T("World bosses every 6 hours, pocket bosses any time, the Cruel and Merciless Trials.",
			"Chefes mundiais a cada 6 horas, chefes de bolso a qualquer hora, as Provas Cruel e Impiedosa."),
		gear = {
			{text = T("World bosses roll a piece of their set and a boss unique for every helper.",
				"Chefes mundiais sorteiam uma peça do seu conjunto e um único de chefe para cada ajudante."),
				where = W("info", {page = "events"})},
			{text = T("Pocket bosses: the same bosses in a private copy, daily charges, less loot.",
				"Chefes de bolso: os mesmos chefes numa cópia privada, cargas diárias, menos saque."),
				where = win("game_bossspawns"), requires = "ChaosPocketBoss"},
			{text = T("Orbs of Fate improve one modifier; use them on your best piece.",
				"Orbs of Fate melhoram um modificador; use na sua melhor peça."), where = win("game_crafting")}
		}},
	{key = "hardened", from = 500, name = T("Hardened", "Calejado"),
		text = T("Five new hunts, faction ranks and Orbs of Grafting.", "Cinco caçadas novas, postos de facção e Orbs of Grafting."),
		gear = {
			{text = T("Hunts: Widowmere, Wyrmspine Hollows, Pyrarch Crucible, then Hexwood Thicket and Corsairs' Reach.",
				"Caçadas: Widowmere, Wyrmspine Hollows, Pyrarch Crucible, depois Hexwood Thicket e Corsairs' Reach."),
				where = W("room")},
			{text = T("Faction gear at Revered; Orbs of Grafting add a modifier.",
				"Equipamento de facção em Reverenciado; Orbs of Grafting adicionam um modificador."), where = win("game_factions")},
			{text = T("Higher rift tiers drop legendary loot.", "Fendas de nível alto soltam saque lendário."),
				where = W("info", {page = "rift"})}
		}},
	{key = "omens", from = 800, name = T("Omens and the raid", "Omens e a raide"),
		text = T("The Ashen Sepulchre, the Omen guardians and The Hollow Vault.",
			"O Ashen Sepulchre, os guardiões Omen e o Hollow Vault."),
		gear = {
			{text = T("Raid uniques drop from the bosses of the Ashen Sepulchre.", "Únicos de raide caem dos chefes do Ashen Sepulchre."),
				where = win("game_raid")},
			{text = T("Omen guardian chests: several unique rolls at the boss tier.",
				"Baús dos guardiões Omen: várias chances de único no nível de chefe."), where = W("info", {page = "rift"})},
			{text = T("The Hollow Vault (level 800) boss chest.", "O baú do chefe do Hollow Vault (nível 800)."), where = win("game_dungeons")}
		}},
	{key = "ascended", from = 900, name = T("Ascended Omens", "Ascended Omens"),
		text = T("The Ascended Omens and a full Sepulchre clear.", "Os Ascended Omens e o Sepulchre completo."),
		gear = {
			{text = T("Ascended uniques: only from the Ascended Omens and the Cinderheart.",
				"Únicos ascendidos: só dos Ascended Omens e do Cinderheart."), where = W("info", {page = "rift"})},
			{text = T("Hunt Mirefang Basin before level 1000.", "Cace na Mirefang Basin antes do nível 1000."),
				where = W("plan", {id = "mirefang_basin"})}
		}},
	{key = "cinder", from = 1000, name = T("The Cinderheart", "O Cinderheart"),
		text = T("The Cinderheart, the Marrow Crypts, Paragon levels and legendary powers.",
			"O Cinderheart, as Marrow Crypts, níveis Paragon e poderes lendários."),
		gear = {
			{text = T("The Marrow Crypts (level 1000) boss chest.", "O baú do chefe das Marrow Crypts (nível 1000)."),
				where = win("game_dungeons")},
			{text = T("Hunts: Rimecrown Depths, Slagmourn Foundry, Cinderglass Sanctum, Hollowmass Reliquary.",
				"Caçadas: Rimecrown Depths, Slagmourn Foundry, Cinderglass Sanctum, Hollowmass Reliquary."), where = W("room")},
			{text = T("Legendary powers drop on legendary items; the Codex lists every power.",
				"Poderes lendários caem em itens lendários; o Codex lista cada poder."), where = win("game_codex")}
		}},
	{key = "deep", from = 1300, name = T("The deep", "As profundezas"),
		text = T("The Iron Crucible and the hunts of the far east.", "O Iron Crucible e as caçadas do extremo leste."),
		gear = {
			{text = T("The Iron Crucible (level 1300) boss chest.", "O baú do chefe do Iron Crucible (nível 1300)."),
				where = win("game_dungeons")},
			{text = T("Hunts: Gallowfen Mire, Voidscar Chasm, Gravehorn Deeps.",
				"Caçadas: Gallowfen Mire, Voidscar Chasm, Gravehorn Deeps."), where = W("room")}
		}},
	{key = "abyss", from = 1600, name = T("The abyss", "O abismo"),
		text = T("The Fallen Sanctum and the hardest Sepulchre runs.", "O Fallen Sanctum e as raides mais difíceis do Sepulchre."),
		gear = {
			{text = T("The Fallen Sanctum (level 1600) boss chest.", "O baú do chefe do Fallen Sanctum (nível 1600)."),
				where = win("game_dungeons")},
			{text = T("Hunt Duskmarrow Crater from level 1750.", "Cace na Duskmarrow Crater a partir do nível 1750."),
				where = W("plan", {id = "duskmarrow_crater"})}
		}},
	{key = "apex", from = 2000, name = T("The apex", "O ápice"),
		text = T("The Pyre Throne, difficulty 6 and the last achievements.", "O Pyre Throne, a dificuldade 6 e as últimas conquistas."),
		gear = {
			{text = T("The Pyre Throne (level 2000) boss chest, best at difficulty 6.",
				"O baú do chefe do Pyre Throne (nível 2000), melhor na dificuldade 6."), where = win("game_dungeons")},
			{text = T("Conquest Tokens buy the uniques luck has not given you.",
				"Os Conquest Tokens compram os únicos que a sorte não deu."),
				where = W("npc", {name = "Iselde Varrow"}), requires = "ChaosConquest"}
		}}
}

-- ------------------------------------------------------------------ goals (in the order the panel lists them)
C.goals = {
	-- 1-19. Characters start at level 8 (start_stats.lua, owner design 2026-10-16): no "Reach level 8" goal; the key
	-- lvl8 is retired (a stored g:lvl8 of an older character is ignored)
	{key = "magic1", level = 1, stat = "kills_magic", target = 1,
		title = T("Slay a magic monster", "Mate um monstro mágico"),
		why = T("Magic, rare and legendary monsters drop better gear and orbs.",
			"Monstros mágicos, raros e lendários soltam equipamento e orbes melhores."),
		where = W("hunts"), effort = T("A few minutes of hunting.", "Alguns minutos de caça.")},
	{key = "bounty1", level = 8, stat = "bounty_done", target = 1,
		title = T("Finish a bounty contract", "Conclua um contrato de recompensa"),
		why = T("Daily contracts at your level pay gold and Orbs of Upheaval.",
			"Contratos diários do seu nível pagam ouro e Orbs of Upheaval."),
		where = win("game_bounty"), effort = T("About 15 minutes.", "Cerca de 15 minutos.")},
	{key = "passive1", level = 12, stat = "passive_spent", target = 1, flag = true,
		title = T("Spend a passive point", "Gaste um ponto passivo"),
		why = T("Every 4 levels past 8 give a point; the tree is your build.",
			"A cada 4 níveis depois do 8 você ganha um ponto; a árvore é a sua build."),
		where = win("game_passivetree"), effort = T("One minute: pick a node next to the centre.",
			"Um minuto: escolha um nó perto do centro.")},
	lvl(20, 1),
	-- 20-49
	{key = "task1", level = 20, stat = "bestiary_tasks", target = 1,
		title = T("Finish a bestiary kill task", "Conclua uma tarefa de abate do Bestiário"),
		why = T("Kill tasks pay gold and bestiary points.", "Tarefas de abate pagam ouro e pontos de bestiário."),
		where = W("tasks"), effort = T("20-40 minutes in one hunt.", "20-40 minutos numa caçada.")},
	{key = "orb1", level = 20, stat = "orbs_used", target = 1,
		title = T("Use a crafting orb", "Use um orbe de criação"),
		why = T("Orbs reroll and improve the modifiers of your gear.", "Orbes rerrolam e melhoram os modificadores do seu equipamento."),
		where = win("game_crafting"), effort = T("Orbs drop from tiered monsters and bounties.",
			"Orbes caem de monstros com nível e de recompensas.")},
	{key = "tiered50", level = 20, stat = "kills_tiered", target = 50,
		title = T("Slay 50 magic, rare or legendary monsters", "Mate 50 monstros mágicos, raros ou lendários"),
		why = T("They carry the best loot of every hunt.", "Eles carregam o melhor saque de cada caçada."),
		where = W("hunts"), effort = T("About an hour of hunting.", "Cerca de uma hora de caça.")},
	{key = "invasion1", level = 30, stat = "invasion_kills", target = 1,
		title = T("Fight in a city invasion", "Lute numa invasão de cidade"),
		why = T("Invasions reward every defender with gold, orbs and gear.",
			"Invasões recompensam cada defensor com ouro, orbes e equipamento."),
		where = W("info", {page = "events"}), effort = T("Several times a day; watch the toasts.",
			"Várias vezes ao dia; fique de olho nos avisos.")},
	lvl(50, 20),
	-- 50-99
	{key = "arena1", level = 50, stat = "arena1v1_wins", target = 1,
		title = T("Win an arena match", "Vença uma partida na Arena"),
		why = T("Ranked PvP with its own rewards and titles.", "PvP ranqueado com recompensas e títulos próprios."),
		where = win("game_arena"), effort = T("A queue and a few minutes.", "Uma fila e alguns minutos.")},
	{key = "bounty10", level = 50, stat = "bounty_done", target = 10,
		title = T("Finish 10 bounty contracts", "Conclua 10 contratos de recompensa"),
		why = T("The weekly bonus chest needs contracts.", "O baú de bônus semanal precisa de contratos."),
		where = win("game_bounty"), effort = T("About 3 days of dailies.", "Cerca de 3 dias de diárias.")},
	{key = "rare10", level = 50, stat = "kills_rare", target = 10,
		title = T("Slay 10 rare monsters", "Mate 10 monstros raros"),
		why = T("Rare monsters drop rare gear and more orbs.", "Monstros raros soltam equipamento raro e mais orbes."),
		where = W("hunts"), effort = T("A long hunt.", "Uma caçada longa.")},
	{key = "known25", level = 50, stat = "bestiary_known", target = 25,
		title = T("Discover 25 creatures in the Bestiary", "Descubra 25 criaturas no Bestiário"),
		why = T("The Bestiary tells where each creature lives and what it drops.",
			"O Bestiário mostra onde cada criatura vive e o que solta."),
		where = win("game_bestiary"), effort = T("Hunt in two or three places.", "Cace em dois ou três lugares.")},
	lvl(100, 50),
	-- 100-199
	{key = "ascend", level = 100, stat = "ascended", target = 1, flag = true,
		title = T("Ascend", "Ascenda"),
		why = T("One of your class's two paths: new spells and a new tree corner.",
			"Um dos dois caminhos da sua classe: novas magias e um novo canto da árvore."),
		where = W("npc", {name = "Ascendant Oracle"}), effort = T("The Ascension Trial: about 15 minutes.",
			"A Prova de Ascensão: cerca de 15 minutos.")},
	{key = "rift1", level = 100, stat = "rift_tier", target = 1,
		title = T("Seal a tier 1 rift", "Sele uma fenda de nível 1"),
		why = T("Rifts drop keys of higher tiers, orbs and uniques.", "Fendas soltam chaves de níveis maiores, orbes e únicos."),
		where = W("info", {page = "rift"}), effort = T("A run takes 5-10 minutes.", "Uma corrida leva 5-10 minutos.")},
	{key = "trial1", level = 100, stat = "trial_tier_1", target = 1,
		title = T("Clear your Vocation Trial on Normal", "Conclua sua Prova de Vocação no Normal"),
		why = T("Each tier unlocks a special node pair of your vocation.",
			"Cada nível libera um par de nós especiais da sua vocação."),
		where = W("npc", {name = "Keeper of Trials"}), effort = T("About 8 minutes.", "Cerca de 8 minutos.")},
	{key = "descent1", level = 100, stat = "descent_runs", target = 1,
		title = T("Enter the Ember Descent", "Entre na Ember Descent"),
		why = T("Room after room of rising danger and rewards.", "Sala após sala de perigo e recompensas crescentes."),
		where = win("game_descent"), effort = T("A run takes 10-20 minutes.", "Uma corrida leva 10-20 minutos.")},
	{key = "legendary1", level = 100, stat = "kills_legendary", target = 1,
		title = T("Slay a legendary monster", "Mate um monstro lendário"),
		why = T("Legendary monsters drop uniques.", "Monstros lendários soltam únicos."),
		where = W("hunts"), effort = T("They are rare: keep hunting tiered packs.", "São raros: continue caçando grupos com nível.")},
	{key = "trusted", level = 120, stat = "faction_rank", target = 4, flag = true,
		title = T("Become Trusted by a faction", "Torne-se Confiável numa facção"),
		why = T("Faction ranks unlock gear, orb bundles and titles.", "Postos de facção liberam equipamento, pacotes de orbes e títulos."),
		where = win("game_factions"), effort = T("A few days of faction contracts.", "Alguns dias de contratos de facção.")},
	{key = "dungeon1", level = 150, stat = "dungeon_clears", target = 1,
		title = T("Clear a dungeon", "Conclua uma masmorra"),
		why = T("Every finisher gets the boss chest.", "Todo finalista ganha o baú do chefe."),
		where = win("game_dungeons"), effort = T("10-15 minutes a run.", "10-15 minutos por corrida.")},
	{key = "pocket1", level = 150, stat = "pocket_kills", target = 1, requires = "ChaosPocketBoss",
		title = T("Defeat a pocket boss", "Derrote um chefe de bolso"),
		why = T("A private copy of a boss whenever you want: tokens and a boss passive point.",
			"Uma cópia privada de um chefe quando quiser: fichas e um ponto passivo de chefe."),
		where = win("game_bossspawns"), effort = T("Daily charges; about 5 minutes a fight.",
			"Cargas diárias; cerca de 5 minutos por luta.")},
	{key = "tokens100", level = 150, stat = "conquest_earned", target = 100, requires = "ChaosConquest",
		title = T("Earn 100 Conquest Tokens", "Ganhe 100 Conquest Tokens"),
		why = T("Tokens buy any unique you have seen at a fixed price: no bad luck.",
			"Fichas compram qualquer único que você já viu a preço fixo: sem azar."),
		where = W("npc", {name = "Iselde Varrow"}), effort = T("Every boss kill and clear pays tokens.",
			"Cada chefe derrotado e conclusão paga fichas.")},
	lvl(200, 100),
	-- 200-299
	{key = "rift4", level = 200, stat = "rift_tier", target = 4,
		title = T("Seal a tier 4 rift", "Sele uma fenda de nível 4"),
		why = T("Rift tiers 4-6 drop rare loot.", "Fendas de nível 4-6 soltam saque raro."),
		where = W("info", {page = "rift"}), effort = T("A key of each tier from the one before.",
			"Uma chave de cada nível vem do anterior.")},
	{key = "unique1", level = 200, stat = "unique_found", target = 1,
		title = T("Find a unique item", "Encontre um item único"),
		why = T("Uniques have fixed stats no orb can roll.", "Únicos têm atributos fixos que nenhum orbe consegue."),
		where = win("game_codex"), effort = T("Luck: about 1 in several hundred legendary kills; or buy it with Conquest Tokens.",
			"Sorte: cerca de 1 em várias centenas de abates lendários; ou compre com Conquest Tokens.")},
	{key = "tower10", level = 200, stat = "tower_floor", target = 10,
		title = T("Clear 10 floors of the Infinity Tower", "Conclua 10 andares da Infinity Tower"),
		why = T("Season ranks and milestone rewards.", "Ranking da temporada e recompensas por marcos."),
		where = win("game_infinitytower"), effort = T("One run of about 20 minutes.", "Uma corrida de cerca de 20 minutos.")},
	{key = "bounty25", level = 200, stat = "bounty_done", target = 25,
		title = T("Finish 25 bounty contracts", "Conclua 25 contratos de recompensa"),
		why = T("Steady gold and orbs every day.", "Ouro e orbes constantes todo dia."),
		where = win("game_bounty"), effort = T("About a week of dailies.", "Cerca de uma semana de diárias.")},
	{key = "trial2", level = 250, stat = "trial_tier_2", target = 1,
		title = T("Clear your Vocation Trial on Cruel", "Conclua sua Prova de Vocação no Cruel"),
		why = T("The second node pair of your vocation.", "O segundo par de nós da sua vocação."),
		where = W("npc", {name = "Keeper of Trials"}), effort = T("About 9 minutes.", "Cerca de 9 minutos.")},
	lvl(300, 200),
	-- 300-499
	{key = "wb1", level = 300, stat = "wb_kills", target = 1,
		title = T("Defeat a world boss", "Derrote um chefe mundial"),
		why = T("Set pieces, boss uniques and a passive point for each first kill.",
			"Peças de conjunto, únicos de chefe e um ponto passivo a cada primeira morte."),
		where = W("info", {page = "events"}), effort = T("Every 6 hours (portals by the temples); about 15 minutes.",
			"A cada 6 horas (portais perto dos templos); cerca de 15 minutos.")},
	{key = "pocket10", level = 300, stat = "pocket_kills", target = 10, requires = "ChaosPocketBoss",
		title = T("Defeat 10 pocket bosses", "Derrote 10 chefes de bolso"),
		why = T("Boss loot without waiting for the event.", "Saque de chefe sem esperar o evento."),
		where = win("game_bossspawns"), effort = T("A few days of charges.", "Alguns dias de cargas.")},
	{key = "honored", level = 300, stat = "faction_rank", target = 5, flag = true,
		title = T("Become Honored by a faction", "Torne-se Honrado numa facção"),
		why = T("Honored unlocks the faction's first gear.", "Honrado libera o primeiro equipamento da facção."),
		where = win("game_factions"), effort = T("One to two weeks of contracts.", "Uma a duas semanas de contratos.")},
	{key = "rift6", level = 300, stat = "rift_tier", target = 6,
		title = T("Seal a tier 6 rift", "Sele uma fenda de nível 6"),
		why = T("Better keys, better chests.", "Chaves melhores, baús melhores."),
		where = W("info", {page = "rift"}), effort = T("A few evenings of rifts.", "Algumas noites de fendas.")},
	{key = "descentclear", level = 400, stat = "descent_clears", target = 1,
		title = T("Clear the Ember Descent", "Conclua a Ember Descent"),
		why = T("The last room pays the best.", "A última sala paga melhor."),
		where = win("game_descent"), effort = T("One long run.", "Uma corrida longa.")},
	{key = "trial3", level = 400, stat = "trial_tier_3", target = 1,
		title = T("Clear your Vocation Trial on Merciless", "Conclua sua Prova de Vocação no Impiedoso"),
		why = T("The third node pair and a title.", "O terceiro par de nós e um título."),
		where = W("npc", {name = "Keeper of Trials"}), effort = T("About 10 minutes, with good gear.",
			"Cerca de 10 minutos, com bom equipamento.")},
	{key = "graft1", level = 400, stat = "orb_exalted", target = 1,
		title = T("Use an Orb of Grafting", "Use um Orb of Grafting"),
		why = T("It adds a modifier to a piece.", "Ele adiciona um modificador a uma peça."),
		where = win("game_crafting"), effort = T("Rare drops; the Orb Exchange trades them.",
			"Drops raros; a Orb Exchange os negocia.")},
	lvl(500, 300),
	-- 500-799
	{key = "wb5", level = 500, stat = "wb_kills", target = 5,
		title = T("Defeat 5 world bosses", "Derrote 5 chefes mundiais"),
		why = T("Every boss has its own set and passive point.", "Cada chefe tem seu conjunto e ponto passivo."),
		where = W("info", {page = "events"}), effort = T("About two days of events.", "Cerca de dois dias de eventos.")},
	{key = "mods5", level = 500, stat = "mods_max", target = 5,
		title = T("Own an item with 5 modifiers", "Tenha um item com 5 modificadores"),
		why = T("More modifiers, more power.", "Mais modificadores, mais poder."),
		where = win("game_crafting"), effort = T("Grafting and luck.", "Enxerto e sorte.")},
	{key = "tower25", level = 500, stat = "tower_floor", target = 25,
		title = T("Clear 25 floors of the Infinity Tower", "Conclua 25 andares da Infinity Tower"),
		why = T("Higher floors, better milestone chests.", "Andares mais altos, baús de marco melhores."),
		where = win("game_infinitytower"), effort = T("One run of about 40 minutes.", "Uma corrida de cerca de 40 minutos.")},
	{key = "completed10", level = 500, stat = "bestiary_completed", target = 10,
		title = T("Complete 10 bestiary entries", "Complete 10 entradas do Bestiário"),
		why = T("Completed entries give a permanent bonus against that creature.",
			"Entradas completas dão um bônus permanente contra aquela criatura."),
		where = win("game_bestiary"), effort = T("Long-term, while you hunt.", "A longo prazo, enquanto caça.")},
	{key = "revered", level = 600, stat = "faction_rank", target = 6, flag = true,
		title = T("Become Revered by a faction", "Torne-se Reverenciado numa facção"),
		why = T("Revered gear and the faction mount path.", "Equipamento de Reverenciado e o caminho da montaria."),
		where = win("game_factions"), effort = T("Several weeks of contracts.", "Várias semanas de contratos.")},
	{key = "rift8", level = 700, stat = "rift_tier", target = 8,
		title = T("Seal a tier 8 rift", "Sele uma fenda de nível 8"),
		why = T("Legendary rift loot and the way to the Omens.", "Saque lendário de fenda e o caminho para os Omens."),
		where = W("info", {page = "rift"}), effort = T("A week of rifts.", "Uma semana de fendas.")},
	lvl(800, 500),
	-- 800-899
	{key = "raid1", level = 800, stat = "raid_kills", target = 1,
		title = T("Defeat a boss of the Ashen Sepulchre", "Derrote um chefe do Ashen Sepulchre"),
		why = T("Raid uniques and the raid's achievements.", "Únicos de raide e as conquistas da raide."),
		where = win("game_raid"), effort = T("A group of 5-10; about an hour.", "Um grupo de 5-10; cerca de uma hora.")},
	{key = "omen1", level = 800, stat = "omen_kills", target = 1,
		title = T("Slay an Omen guardian", "Mate um guardião Omen"),
		why = T("Several unique rolls in one chest.", "Várias chances de único num só baú."),
		where = W("info", {page = "rift"}), effort = T("An Omen key from high rifts; about 10 minutes.",
			"Uma Omen Key das fendas altas; cerca de 10 minutos.")},
	{key = "vault", level = 800, stat = "dungeon_vault", target = 1,
		title = T("Clear The Hollow Vault", "Conclua o Hollow Vault"),
		why = T("The first of the late dungeons.", "A primeira das masmorras finais."),
		where = win("game_dungeons"), effort = T("10-15 minutes a run.", "10-15 minutos por corrida.")},
	{key = "pocket50", level = 800, stat = "pocket_kills", target = 50, requires = "ChaosPocketBoss",
		title = T("Defeat 50 pocket bosses", "Derrote 50 chefes de bolso"),
		why = T("Steady boss loot and tokens.", "Saque de chefe e fichas constantes."),
		where = win("game_bossspawns"), effort = T("A few weeks of charges.", "Algumas semanas de cargas.")},
	lvl(900, 800),
	-- 900-999
	{key = "ascended1", level = 900, stat = "ascended_kills", target = 1,
		title = T("Slay an Ascended Omen", "Mate um Ascended Omen"),
		why = T("The only source of the Ascended uniques.", "A única fonte dos únicos ascendidos."),
		where = W("info", {page = "rift"}), effort = T("A group and about 15 minutes.", "Um grupo e cerca de 15 minutos.")},
	{key = "raidclear", level = 900, stat = "raid_clears", target = 1,
		title = T("Clear the Ashen Sepulchre", "Conclua o Ashen Sepulchre"),
		why = T("Every boss, every chest.", "Todos os chefes, todos os baús."),
		where = win("game_raid"), effort = T("A full evening with a group.", "Uma noite inteira com um grupo.")},
	{key = "rift10", level = 900, stat = "rift_tier", target = 10,
		title = T("Seal a tier 10 rift", "Sele uma fenda de nível 10"),
		why = T("The rift's best loot tier below the bosses.", "O melhor nível de saque de fenda abaixo dos chefes."),
		where = W("info", {page = "rift"}), effort = T("Steady rift runs.", "Corridas de fenda constantes.")},
	lvl(1000, 900),
	-- 1000-1299
	{key = "cinder1", level = 1000, stat = "cinder_kills", target = 1,
		title = T("Slay the Cinderheart", "Mate o Cinderheart"),
		why = T("The hardest boss of the Omens; the best unique rolls.", "O chefe mais difícil dos Omens; as melhores chances de único."),
		where = W("info", {page = "rift"}), effort = T("A strong group; about 20 minutes.", "Um grupo forte; cerca de 20 minutos.")},
	{key = "marrow", level = 1000, stat = "dungeon_marrow", target = 1,
		title = T("Clear The Marrow Crypts", "Conclua as Marrow Crypts"),
		why = T("Its boss chest drops level 1000 gear.", "O baú do chefe solta equipamento de nível 1000."),
		where = win("game_dungeons"), effort = T("10-15 minutes a run.", "10-15 minutos por corrida.")},
	{key = "paragon1", level = 1001, stat = "paragon", target = 1,
		title = T("Earn your first Paragon level", "Ganhe seu primeiro nível Paragon"),
		why = T("Past level 1000 every level is a Paragon point.", "Depois do nível 1000 cada nível é um ponto Paragon."),
		where = win("game_passivetree"), effort = T("Your next level.", "O seu próximo nível.")},
	{key = "power1", level = 1000, stat = "power_found", target = 1, flag = true,
		title = T("Find an item with a legendary power", "Encontre um item com um poder lendário"),
		why = T("Powers change how your build plays.", "Poderes mudam como sua build joga."),
		where = win("game_codex"), effort = T("Legendary items from bosses and high rifts.",
			"Itens lendários de chefes e fendas altas.")},
	{key = "exalted", level = 1000, stat = "faction_exalted", target = 1, flag = true,
		title = T("Become Exalted by a faction", "Torne-se Exaltado numa facção"),
		why = T("The faction's mount, frame and title.", "A montaria, a moldura e o título da facção."),
		where = win("game_factions"), effort = T("Months of contracts.", "Meses de contratos.")},
	lvl(1300, 1000),
	-- 1300-1599
	{key = "crucible", level = 1300, stat = "dungeon_crucible", target = 1,
		title = T("Clear The Iron Crucible", "Conclua o Iron Crucible"),
		why = T("Its boss chest drops level 1300 gear.", "O baú do chefe solta equipamento de nível 1300."),
		where = win("game_dungeons"), effort = T("10-15 minutes a run.", "10-15 minutos por corrida.")},
	{key = "raid3", level = 1300, stat = "raid_clears", target = 3,
		title = T("Clear the Ashen Sepulchre 3 times", "Conclua o Ashen Sepulchre 3 vezes"),
		why = T("More rolls at the raid uniques.", "Mais chances nos únicos de raide."),
		where = win("game_raid"), effort = T("Three raid nights.", "Três noites de raide.")},
	{key = "ascended5", level = 1300, stat = "ascended_kills", target = 5,
		title = T("Slay 5 Ascended Omens", "Mate 5 Ascended Omens"),
		why = T("Every Ascended unique is on their list.", "Todo único ascendido está na lista deles."),
		where = W("info", {page = "rift"}), effort = T("A week with a group.", "Uma semana com um grupo.")},
	lvl(1600, 1300),
	-- 1600-1999
	{key = "sanctum", level = 1600, stat = "dungeon_sanctum", target = 1,
		title = T("Clear The Fallen Sanctum", "Conclua o Fallen Sanctum"),
		why = T("Its boss chest drops level 1600 gear.", "O baú do chefe solta equipamento de nível 1600."),
		where = win("game_dungeons"), effort = T("10-15 minutes a run.", "10-15 minutos por corrida.")},
	{key = "raidflawless", level = 1600, stat = "raid_flawless", target = 1,
		title = T("Clear the Sepulchre without a death", "Conclua o Sepulchre sem nenhuma morte"),
		why = T("A title and the respect of the server.", "Um título e o respeito do servidor."),
		where = win("game_raid"), effort = T("A practised group.", "Um grupo experiente.")},
	{key = "cinder3", level = 1600, stat = "cinder_kills", target = 3,
		title = T("Slay the Cinderheart 3 times", "Mate o Cinderheart 3 vezes"),
		why = T("More rolls at its uniques.", "Mais chances nos seus únicos."),
		where = W("info", {page = "rift"}), effort = T("A few weeks.", "Algumas semanas.")},
	lvl(2000, 1600),
	-- 2000+
	{key = "throne", level = 2000, stat = "dungeon_throne", target = 1,
		title = T("Clear The Pyre Throne", "Conclua o Pyre Throne"),
		why = T("The last dungeon; its chest drops level 2000 gear.", "A última masmorra; o baú solta equipamento de nível 2000."),
		where = win("game_dungeons"), effort = T("10-15 minutes a run.", "10-15 minutos por corrida.")},
	{key = "throne6", level = 2000, stat = "dungeon_throne_d6", target = 1, flag = true,
		title = T("Clear The Pyre Throne on difficulty 6", "Conclua o Pyre Throne na dificuldade 6"),
		why = T("The best chest of the game.", "O melhor baú do jogo."),
		where = win("game_dungeons"), effort = T("Best gear and a tight group.", "O melhor equipamento e um grupo afiado.")},
	{key = "cinderflawless", level = 2000, stat = "cinder_flawless", target = 1, flag = true,
		title = T("Slay the Cinderheart without a death", "Mate o Cinderheart sem nenhuma morte"),
		why = T("A feat few will share.", "Um feito que poucos vão dividir."),
		where = W("info", {page = "rift"}), effort = T("Practice.", "Prática.")},
	{key = "paragon100", level = 2000, stat = "paragon", target = 100,
		title = T("Reach Paragon level 100", "Alcance o nível Paragon 100"),
		why = T("The Paragon title and more stats.", "O título Paragon e mais atributos."),
		where = win("game_passivetree"), effort = T("Keep levelling.", "Continue subindo de nível.")}
}

-- ------------------------------------------------------------------ texts of the engine (goals.lua)
C.texts = {
	done = T("Goal done: %s. Reward: %s.", "Objetivo concluído: %s. Recompensa: %s."),
	doneShort = T("Goal done: %s", "Objetivo concluído: %s"),
	none = T("none", "nenhuma"),
	xp = T("%s experience", "%s de experiência"),
	gold = T("%s gold to your bank", "%s de ouro no banco"),
	tokens = T("%d Conquest Tokens", "%d Conquest Tokens"),
	marked = T("Marked on your map: %s.", "Marcado no seu mapa: %s."),
	temple = T("your temple", "seu templo"),
	room = T("the teleport room of Cinderhold", "a sala de teleportes de Cinderhold"),
	hunts = T("hunting grounds of your level", "áreas de caça do seu nível"),
	unlocks = T("Unlocks at level %d", "Abre no nível %d"),
	newBand = T("New goals at level %d: %s. Open Adventure > Next Goals.",
		"Novos objetivos no nível %d: %s. Abra Adventure > Next Goals.")
}

return C
