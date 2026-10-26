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
-- NEVER reorder or insert: the storage bits are by index; add new entries at the end (up to 30).
return {
	enabled = true,

	opcode = 115, -- ChaosOpcodes.unlocks (chaos_constants.lua); client client_chaos_topbar

	-- player storages: block 7103000-7103009 (server/README.md "Storage keys"): +0 the unlocked entries (bits, by index),
	-- +1 the entries the player has opened since (bits: the "New" badge goes), +2 how many entries the character knows of
	-- (an entry added later at a level the character already passed is marked unlocked and seen, silently)
	storage = {base = 7103000, unlocked = 0, seen = 1, known = 2, last = 7103009},

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
			why = {{"Climb floor after floor; a boss every fifth.", "Suba andar após andar; um chefe a cada cinco."},
				{"Go alone or with a party of up to four.", "Vá sozinho ou com um grupo de até quatro."}},
			go = {open = "game_infinitytower"}},
		{key = "dungeons", level = 150, menu = "Dungeons", source = "bossspawns_config.lua dungeons.defaults[1].level",
			title = {"Dungeons", "Masmorras"},
			why = {{"Boss dungeons with chests; the item level rises with the difficulty.", "Masmorras com chefes e baús; o nível do item sobe com a dificuldade."},
				{"Enter alone or queue with a group.", "Entre sozinho ou na fila com um grupo."}},
			go = {open = "game_dungeons"}}
	}
}
