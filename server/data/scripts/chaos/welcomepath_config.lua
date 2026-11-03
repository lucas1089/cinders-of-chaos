-- The welcome path (O370; welcomepath.lua, welcomepath_core.lua; docs/CONTENT.md "Welcome path"): a short chain of first
-- steps for a new character, one at a time, each with a small reward. It shows in the Next Goals tracker (client
-- game_goals, the "Welcome Path" section) and is skippable there. Texts in English (en) and Brazilian Portuguese (pt).
-- Data only, no engine calls (tests/welcomepath_test.lua reads it). Lua 5.1 / LuaJIT and 5.3.
--
-- A step: {key, check, title, hint, where?, reward, target?, stat?, level?}
--   check    how the step is seen done (welcomepath_core.lua M.progress; the engine side gathers the facts):
--              "spell"  a spell group cooldown on the character (attack, healing or support: a spell was cast, by
--                       hand or by the Helper after Auto setup); looked at every sweepMs while the step is open
--              "kills"  monsters killed while the step is open (a kill event of this module), `target` of them
--              "gear"   a worn item that is not part of the character's starter kit (newplayer_config.lua kits): loot,
--                       a shop or the Gambler
--              "stat"   a counter of the Next Goals (own stats) or of the achievements (`stat`, at least `target`)
--              "goals"  the Next Goals window was opened (goals.lua "open")
--   level    the step's counter starts at this level (the first passive point comes at level 12, the Crafting Bench
--            opens at 20): below it the row shows the level as its progress
--   where    what a click on the tracker row does (the Next Goals "where" forms, goals_config.lua header); a "hunts" or
--            "npc" form is resolved to a mark on the map by goals.lua's resolver
--   reward   {gold = to the bank, items = {{id, count}}, potions = true (the role potions below)}
-- NEVER reorder or insert steps of a live server without care: the stored step is an index (a character on step 3
-- stays on step 3). Add new steps at the end.
--
-- Rewards are a nudge: the whole path pays 4,600 gold, 2 Orbs of Awakening (for the orb step), 2 Orbs of Upheaval and
-- two potion packs; the kit gives 500 gold and the level 20 gift 50 potions and an orb.

local function T(en, pt)
	return {en = en, pt = pt}
end

local function win(m, f)
	return {k = "window", m = m, f = f or "toggle"}
end

local AWAKENING, UPHEAVAL = 29851, 29856 -- chaos_crafting.lua orbs: transmutation, chaos

return {
	enabled = true,

	-- player storages: block 7101070-7101079 (server/README.md "Storage keys", Chaos.storage.welcomePath): +0 the state
	-- (-1 never seen, 0 on the path, 1 finished, 2 skipped, 3 quiet: first seen above quietAbove), +1 the current step
	-- (index), +2 kills counted for a "kills" step, +3 flags (bit 1: the Next Goals window was opened); +4..9 free
	storage = {base = 7101070, state = 0, step = 1, kills = 2, flags = 3, last = 7101079},
	states = {fresh = -1, active = 0, done = 1, skipped = 2, quiet = 3},

	-- a character first seen above this level (it played before this module) never gets the path. A character first
	-- seen at or below it starts the path; the steps it has already done then are passed silently, without a reward.
	quietAbove = 20,
	-- a character played before when its kit (newplayer.lua, storage kit = os.time) is older than this or it is above
	-- the start level: then the spell and kills steps it surely did pass silently too at the first look
	playedAfterSec = 3600,
	startLevel = 8,
	-- the first look at a character waits for the achievements and the Next Goals to load its counters (2 s), and comes
	-- after the welcome (newplayer.lua, 2.5 s) and the first first-hour hint (firsthour.lua, 9 s), not beside them
	firstLookMs = 12000,
	-- the tracker rows and the step checks: one sweep over the characters on the path every sweepMs
	sweepMs = 1000,
	-- staff walk no path
	staffGroup = 4,
	-- the Next Goals channel (goals.lua): no new opcode
	opcode = 178,

	-- potions of a `potions = true` reward, by the kit's role (newplayer_config.lua kits role; the milestone gifts' rule)
	potions = {
		melee = {{7618, 25}}, ranged = {{7618, 15}, {7620, 15}}, caster = {{7620, 25}}, default = {{7618, 15}, {7620, 15}}
	},

	steps = {
		{key = "spell", check = "spell",
			title = T("Cast a spell", "Lance uma magia"),
			hint = T("Press Auto setup in the Helper: it puts your spells on hotkeys and casts them for you. "
				.. "Character > Spellbook (Alt+S) lists them all.",
				"Clique em Auto setup no Helper: ele põe suas magias nos atalhos e lança por você. "
				.. "Personagem > Spellbook (Alt+S) lista todas."),
			where = win("game_helper"), reward = {gold = 300}},
		{key = "kills", check = "kills", target = 20,
			title = T("Slay 20 monsters", "Mate 20 monstros"),
			hint = T("The hunts of your level are on your map. Magic (blue) and rare (yellow) monsters drop better gear.",
				"As caçadas do seu nível estão no seu mapa. Monstros mágicos (azuis) e raros (amarelos) soltam equipamento melhor."),
			where = {k = "hunts"}, reward = {gold = 500, potions = true}},
		{key = "gear", check = "gear",
			title = T("Wear a new piece of gear", "Equipe uma peça nova"),
			hint = T("Wear a weapon, armour piece or jewel that is not from your starter kit: monsters drop them, the town "
				.. "shops sell them. Economy > Item Finder tells where.",
				"Equipe uma arma, armadura ou joia que não seja do kit inicial: monstros soltam, as lojas da cidade vendem. "
				.. "Economy > Item Finder mostra onde."),
			where = {k = "npc", name = "Loot Buyer"}, reward = {gold = 500}},
		{key = "passive", check = "stat", stat = "passive_spent", target = 1, level = 12,
			title = T("Spend your first passive point", "Gaste seu primeiro ponto passivo"),
			hint = T("Level 12 gives your first point. Character > Passive Tree: pick a node next to the centre and "
				.. "press Apply Plan.",
				"O nível 12 dá o primeiro ponto. Personagem > Árvore Passiva: escolha um nó perto do centro e clique "
				.. "em Aplicar Plano."),
			where = win("game_passivetree"), reward = {gold = 800}},
		{key = "bounty", check = "stat", stat = "bounty_done", target = 1,
			title = T("Finish a Bounty contract", "Conclua um contrato do Bounty Board"),
			hint = T("Adventure > Bounty Board: take a contract of your level, hunt it down and claim the pay.",
				"Adventure > Bounty Board: aceite um contrato do seu nível, cumpra e receba o pagamento."),
			where = win("game_bounty"), reward = {gold = 1000, items = {{AWAKENING, 2}}}},
		-- the Crafting Bench opens at level 20 (data/lib/chaos_crafting.lua config.minLevel; unlocks_config.lua)
		{key = "orb", check = "stat", stat = "orbs_used", target = 1, level = 20,
			title = T("Use an orb at the Crafting Bench", "Use um orbe na Crafting Bench"),
			hint = T("From level 20, open the Crafting Bench (Alt+C) and use an Orb of Awakening on a plain piece of gear: "
				.. "it gains random modifiers.",
				"A partir do nível 20, abra a Crafting Bench (Alt+C) e use um Orb of Awakening numa peça comum: ela ganha "
				.. "modificadores aleatórios."),
			where = win("game_crafting"), reward = {gold = 500, items = {{UPHEAVAL, 2}}}},
		{key = "goals", check = "goals",
			title = T("Open Next Goals", "Abra os Próximos objetivos"),
			hint = T("Adventure > Next Goals (or a click on this row) shows what to do at every level from here on.",
				"Adventure > Next Goals (ou um clique nesta linha) mostra o que fazer em cada nível daqui em diante."),
			where = win("game_goals", "show"), reward = {gold = 1000, potions = true}}
	},

	texts = {
		title = T("Welcome Path", "Caminho de boas-vindas"),
		-- %d step, %d steps, %s title, %s reward
		stepDone = T("Welcome path %d/%d done: %s. Reward: %s.", "Caminho de boas-vindas %d/%d concluído: %s. Recompensa: %s."),
		-- %s the next step's title, %s its hint
		next = T("Next step: %s. %s", "Próximo passo: %s. %s"),
		start = T("Your welcome path starts: a few first steps, each with a small reward. They show in the goal tracker "
			.. "(left side of the screen); \"Skip welcome path\" there ends it.",
			"Seu caminho de boas-vindas começou: alguns primeiros passos, cada um com uma pequena recompensa. Eles aparecem "
			.. "no rastreador de objetivos (lado esquerdo da tela); \"Pular caminho de boas-vindas\" ali encerra."),
		finished = T("Welcome path complete! From here on, Adventure > Next Goals shows the way.",
			"Caminho de boas-vindas concluído! Daqui em diante, Adventure > Next Goals mostra o caminho."),
		skipped = T("Welcome path skipped. Adventure > Next Goals shows what to do at every level.",
			"Caminho de boas-vindas pulado. Adventure > Next Goals mostra o que fazer em cada nível."),
		reachLevel = T("%s (level %d)", "%s (nível %d)"),
		gold = T("%s gold to your bank", "%s de ouro no seu banco"),
		items = T("%d %s", "%d %s"),
		potions = T("potions", "poções"),
		none = T("nothing", "nada")
	}
}
