-- The top menu reveals systems by level (unlocks.lua, unlocks_core.lua; client client_chaos_topbar; server/README.md "The
-- top menu reveals systems by level (O259)"): one table, read by the server (what a character has unlocked, the next one,
-- the "New" announcements) and sent to the client in the `state` message, so the client keeps no table of its own.
-- Data only, no engine calls. Lua 5.1 / LuaJIT and 5.3 compatible.
--
-- An entry: {key, level, menu, source, title, why, go}
--   key     stable id (the client sends it back as `seen`)
--   level   the level the SYSTEM ITSELF already enforces (its own config, named in `source`). tests/unlocks_test.lua reads
--           that config and fails when the two differ, so a change in a system's gate has to change this table too
--   menu    the English text of the entry in the top menu (client_chaos_topbar CATEGORIES `entry('<text>', ...)`)
--   source  where the level lives: a file of data/scripts/chaos and the field (documentation; the test has the reader)
--   title   {en, pt}: shown in "New: <title>!" and in the small window
--   why     {{en, pt}, {en, pt}}: the two lines of the small window
--   go      {open = "<client module>"}: the "Go" button runs the entry of the top menu (the module is where it opens)
-- NEVER reorder or insert: the storage bits are by index; add new entries at the end (up to 50: bits 1-30 in +0 / +1,
-- bits 31-50 in +3 / +4, see `storage`).
return {
	enabled = true,

	opcode = 115, -- ChaosOpcodes.unlocks (chaos_constants.lua); client client_chaos_topbar

	-- player storages: block 7103000-7103009 (server/README.md "Storage keys"): +0 the unlocked entries (bits, by index),
	-- +1 the entries the player has opened since (bits: the "New" badge goes), +2 how many entries the character knows of
	-- (an entry added later at a level the character already passed is marked unlocked and seen, silently); +3 and +4 the
	-- bits of entries 31-50 (unlocked, seen: O368; a storage holds 31 bits, so each mask is split at 2^30)
	storage = {base = 7103000, unlocked = 0, seen = 1, known = 2, unlocked2 = 3, seen2 = 4, last = 7103009},

	-- a character first seen above this level (it played before this module) gets every entry of its level silently
	quietAbove = 20,

	-- staff (group id at or above this) see the whole menu
	staffGroup = 4,

	-- announcements (the first hour's pace, firsthour_config.lua `pace`): one entry per run, the next after gapMs while more
	-- are due. delayMs: the first one after a login waits for the welcome and the first hint
	pace = {perRun = 1, gapMs = 75000},
	delayMs = 20000,

	-- the state message after a login (the client may not listen yet; it also asks with `hello`)
	stateDelayMs = 1500,

	entries = {
		{key = "bounty", level = 8, menu = "Bounty Board", source = "bounty_config.lua bands[1].min",
			title = {"Bounty Board", "Bounty Board"},
			why = {{"Daily contracts at your level for gold and orbs.", "Contratos diários do seu nível por ouro e orbes."},
				{"Take one and hunt what it names.", "Aceite um e cace o que ele pede."}},
			go = {open = "game_bounty"}},
		{key = "market", level = 8, menu = "Market", source = "market_config.lua minLevel",
			title = {"Market", "Market"},
			why = {{"Sell to other players for gold or Chaos Coins.", "Venda para outros jogadores por ouro ou Chaos Coins."},
				{"Post a buy order for the gear you are after.", "Faça uma oferta de compra do equipamento que procura."}},
			go = {open = "game_market"}},
		{key = "passive", level = 12, menu = "Passive Tree", source = "chaos_constants.lua Chaos.passive startLevel + levelsPerPoint",
			title = {"Passive Tree", "Árvore Passiva"},
			why = {{"Your first passive point is ready.", "Seu primeiro ponto passivo está pronto."},
				{"Start next to the centre and press Apply Plan.", "Comece perto do centro e clique em Aplicar Plano."}},
			go = {open = "game_passivetree"}},
		{key = "events", level = 30, menu = "Events", source = "invasion_config.lua minLevel",
			title = {"Events", "Eventos"},
			why = {{"Defend the towns in invasions and earn their rewards.", "Defenda as cidades nas invasões e ganhe as recompensas."},
				{"The window lists what starts next.", "A janela mostra o que começa em seguida."}},
			go = {open = "game_chaosinfo"}},
		{key = "arena", level = 50, menu = "Arena", source = "arena_config.lua minLevel",
			title = {"Arena", "Arena"},
			why = {{"Ranked player against player matches, 1v1 to 3v3.", "Partidas ranqueadas jogador contra jogador, de 1v1 a 3v3."},
				{"Queue up from the window.", "Entre na fila pela janela."}},
			go = {open = "game_arena"}},
		{key = "rifts", level = 100, menu = "Rifts", source = "rift_config.lua tiers[1].minLevel",
			title = {"Rifts", "Fendas"},
			why = {{"Tiered rifts with packs, a boss and a chest.", "Fendas em níveis, com hordas, um chefe e um baú."},
				{"Seal a tier to open the next.", "Sele um nível para abrir o seguinte."}},
			go = {open = "game_chaosinfo"}},
		{key = "siege", level = 100, menu = "Guild Siege", source = "siege_config.lua minLevel",
			title = {"Guild Siege", "Guild Siege"},
			why = {{"Guilds fight for an arena once a week.", "Guildas lutam por uma arena uma vez por semana."},
				{"Your guild's vice-leader signs up.", "O vice-líder da sua guilda faz a inscrição."}},
			go = {open = "game_siege"}},
		{key = "tower", level = 100, menu = "Infinity Tower", source = "infinitytower_run.lua cfg.minLevel",
			title = {"Infinity Tower", "Infinity Tower"},
			why = {{"Climb floor after floor; a boss every tenth, a prize every fifth.", "Suba andar após andar; um chefe a cada dez, um prêmio a cada cinco."},
				{"Go alone or with a party of up to four.", "Vá sozinho ou com um grupo de até quatro."}},
			go = {open = "game_infinitytower"}},
		{key = "dungeons", level = 150, menu = "Dungeons", source = "bossspawns_config.lua dungeons.defaults[1].level",
			title = {"Dungeons", "Masmorras"},
			why = {{"Boss dungeons with chests; the item level rises with the difficulty.", "Masmorras com chefes e baús; o nível do item sobe com a dificuldade."},
				{"Enter alone or queue with a group.", "Entre sozinho ou na fila com um grupo."}},
			go = {open = "game_dungeons"}},
		-- O262: gates added to the systems themselves (Bank and Supply Stash stay open from level 1 on purpose)
		{key = "crafting", level = 20, menu = "Crafting Bench", source = "data/lib/chaos_crafting.lua config.minLevel",
			title = {"Crafting Bench", "Crafting Bench"},
			why = {{"Improve your gear with orbs and see a preview first.", "Melhore seu equipamento com orbes e veja uma prévia antes."},
				{"Salvage what you do not need for shards.", "Recicle o que não precisa em fragmentos."}},
			go = {open = "game_crafting"}},
		{key = "pets", level = 25, menu = "Pets", source = "pets_config.lua minLevel",
			title = {"Pets", "Pets"},
			why = {{"A small companion that follows you and levels with your kills.", "Um pequeno companheiro que te segue e sobe de nível com suas mortes."},
				{"Call one out in the window.", "Chame um pela janela."}},
			go = {open = "game_pets"}},
		-- the bench's Salvage mode has its own menu entry and the same gate as the bench
		{key = "salvage", level = 20, menu = "Salvage", source = "data/lib/chaos_crafting.lua config.minLevel",
			title = {"Salvage", "Reciclagem"},
			why = {{"Break gear you do not need into shards and orbs.", "Quebre o equipamento que não precisa em fragmentos e orbes."},
				{"Lock the pieces you want to keep first.", "Tranque antes as peças que quer guardar."}},
			go = {open = "game_crafting"}},
		-- O368: new player level gates. A new character sees few windows; each opens at a level of its own (the system
		-- refuses below it). Plain words, two short lines each.
		{key = "loadouts", level = 15, menu = "Loadouts", source = "loadouts_config.lua minLevel",
			title = {"Loadouts", "Loadouts"},
			why = {{"Save your passive tree and gear as a build.", "Salve a sua árvore passiva e o equipamento como uma build."},
				{"Switch between builds in town.", "Troque de build na cidade."}},
			go = {open = "game_loadouts"}},
		{key = "orbexchange", level = 20, menu = "Orb Exchange", source = "orbexchange_config.lua minLevel",
			title = {"Orb Exchange", "Orb Exchange"},
			why = {{"Trade crafting orbs with other players.", "Troque orbes de criação com outros jogadores."},
				{"Post the price you want and wait for a buyer.", "Coloque o preço que quer e espere um comprador."}},
			go = {open = "game_orbexchange"}},
		{key = "charms", level = 15, menu = "Charms", source = "charms_config.lua C.minLevel",
			title = {"Charms", "Charms"},
			why = {{"Place the charms you find for small bonuses.", "Coloque os charms que encontrar para pequenos bônus."},
				{"More cells open as you level.", "Mais espaços abrem conforme você sobe de nível."}},
			go = {open = "game_charms"}},
		{key = "seasonpass", level = 10, menu = "Season Pass", source = "seasonpass_config.lua minLevel",
			title = {"Season Pass", "Season Pass"},
			why = {{"Playing fills the pass; every tier has a reward.", "Jogar enche o passe; cada nível tem uma recompensa."},
				{"Claim what you earned in the window.", "Pegue o que ganhou na janela."}},
			go = {open = "game_battlepass"}},
		{key = "professions", level = 20, menu = "Professions", source = "professions_config.lua C.minLevel",
			title = {"Professions", "Profissões"},
			why = {{"Gather ore, herbs, hides and fish in the hunting grounds.", "Colete minério, ervas, couro e peixe nas áreas de caça."},
				{"Sell them to the Material Broker for gold.", "Venda para o Material Broker por ouro."}},
			go = {open = "game_professions"}},
		{key = "transmog", level = 30, menu = "Transmog", source = "transmog_config.lua minLevel",
			title = {"Transmog", "Transmog"},
			why = {{"Make your gear look like other gear you have found.", "Deixe o seu equipamento com a aparência de outro que já encontrou."},
				{"Only the look changes, never the stats.", "Só a aparência muda, nunca os atributos."}},
			go = {open = "game_transmog"}},
		{key = "hideout", level = 30, menu = "Hideout", source = "hideout_config.lua minLevel",
			title = {"Hideout", "Esconderijo"},
			why = {{"A room of your own with a depot, a stash and dummies.", "Uma sala só sua com depósito, baú e bonecos de treino."},
				{"Decorate it and invite your friends.", "Decore e convide os seus amigos."}},
			go = {open = "game_hideout"}},
		{key = "gamble", level = 40, menu = "The Gambler", source = "gamble_config.lua C.minLevel",
			title = {"The Gambler", "The Gambler"},
			why = {{"Buy sealed gear for gold; you see the rarity after.", "Compre equipamento lacrado por ouro; a raridade aparece depois."},
				{"The stock is new every few hours.", "O estoque renova a cada poucas horas."}},
			go = {open = "game_gamble"}},
		{key = "factions", level = 40, menu = "Factions", source = "factions_config.lua minLevel",
			title = {"Factions", "Facções"},
			why = {{"Four factions with contracts, ranks and rewards.", "Quatro facções com contratos, postos e recompensas."},
				{"The reputation you already earned is waiting.", "A reputação que você já ganhou está esperando."}},
			go = {open = "game_factions"}},
		{key = "conquest", level = 50, menu = "Conquest Vendor", source = "conquest_config.lua C.minLevel",
			title = {"Conquest Vendor", "Conquest Vendor"},
			why = {{"Spend Conquest Tokens on uniques and set pieces.", "Gaste Conquest Tokens em itens únicos e peças de conjunto."},
				{"Bosses and clears give the tokens.", "Chefes e conclusões dão os tokens."}},
			go = {open = "game_conquest"}},
		{key = "guildwar", level = 50, menu = "Guild Wars", source = "guildwar_config.lua minLevel",
			title = {"Guild Wars", "Guild Wars"},
			why = {{"Guild against guild: declare a war and count the kills.", "Guilda contra guilda: declare uma guerra e conte as mortes."},
				{"Leaders and vice-leaders declare it.", "Líderes e vice-líderes declaram."}},
			go = {open = "game_guildwar"}},
		{key = "nemesis", level = 50, menu = "Nemesis", source = "nemesis_config.lua birth.minLevel",
			title = {"Nemesis", "Nemesis"},
			why = {{"A monster that kills you may come back stronger.", "Um monstro que te mata pode voltar mais forte."},
				{"Hunt it down for a trophy.", "Cace-o para ganhar um troféu."}},
			go = {open = "game_nemesis"}},
		{key = "riftatlas", level = 100, menu = "Rift Atlas", source = "atlas_config.lua minLevel",
			title = {"Rift Atlas", "Rift Atlas"},
			why = {{"Sealed rifts earn points for the Rift Atlas.", "Fendas seladas dão pontos para o Rift Atlas."},
				{"Spend them to make your rifts richer.", "Gaste para deixar as suas fendas mais ricas."}},
			go = {open = "game_riftatlas"}},
		{key = "descent", level = 100, menu = "Ember Descent", source = "descent_config.lua minLevel",
			title = {"Ember Descent", "Ember Descent"},
			why = {{"Room after room, each harder than the last.", "Sala após sala, cada uma mais difícil que a anterior."},
				{"Go alone or with a party.", "Vá sozinho ou em grupo."}},
			go = {open = "game_descent"}},
		{key = "battleground", level = 100, menu = "Battleground", source = "battleground_config.lua minLevel",
			title = {"Battleground", "Campo de Batalha"},
			why = {{"Team against team, players of your level bracket.", "Time contra time, jogadores da sua faixa de nível."},
				{"No real death; win honor for the PvP vendor.", "Sem morte de verdade; ganhe honra para o vendedor de PvP."}},
			go = {open = "game_battleground"}},
		{key = "pvpzone", level = 150, menu = "Scorched Marches", source = "pvpzone_config.lua minLevel",
			title = {"Scorched Marches", "Scorched Marches"},
			why = {{"An open zone where players fight players.", "Uma zona aberta onde jogadores lutam contra jogadores."},
				{"Go in only when you are ready to be hunted.", "Entre só quando estiver pronto para ser caçado."}},
			go = {open = "game_pvpzone"}},
		{key = "raid", level = 800, menu = "Raid: Ashen Sepulchre", source = "raid_config.lua minLevel",
			title = {"Ashen Sepulchre", "Ashen Sepulchre"},
			why = {{"Several bosses in a row, once a week.", "Vários chefes em sequência, uma vez por semana."},
				{"Bring a group; the bosses scale to it.", "Leve um grupo; os chefes se ajustam a ele."}},
			go = {open = "game_raid"}},
		{key = "waystoneatlas", level = 1100, menu = "Waystone Atlas", source = "waystone_atlas_config.lua minLevel",
			title = {"Waystone Atlas", "Waystone Atlas"},
			why = {{"Waystone maps earn points for the Waystone Atlas.", "Mapas de waystone dão pontos para o Waystone Atlas."},
				{"Spend them to make your maps richer.", "Gaste para deixar os seus mapas mais ricos."}},
			go = {open = "game_riftatlas"}}
	}
}
