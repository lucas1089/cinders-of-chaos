-- The tales: short quests with a story for the level bands that had none (docs/CONTENT.md "Tales"). Logic:
-- tales_core.lua (pure, tests/tales_test.lua); engine: tales.lua (kill credit, the modal windows, rewards, the NPC);
-- the NPC: Archivist Maelis (data/npc/Archivist Maelis.xml, data/npc/scripts/archivist_maelis.lua).
-- Every text is in English (en) and Brazilian Portuguese (pt). A character reads pt when Chaos.lang(player) says "pt"
-- (the localization work's hook, when it exists) or after telling the Archivist "portugues"; "english" switches back.
-- Lua 5.1 / LuaJIT and 5.3.
local UPHEAVAL, FATE, GRAFTING, SHARD = 29856, 29857, 29855, 32051
local AWAKENING, WHETSTONE, TEMPERING = 29851, 32256, 32251
-- the NPCs of the talk steps: the faction NPCs (factions_config.lua; their script chaos_faction_npc.lua does the step)
local YSOLDE, BRANNOC, VELITH, BRAMWYN = "Warden Ysolde", "Forgemaster Brannoc", "Cantor Velith", "Elder Bramwyn"

return {
	enabled = true,

	-- player storages (server/README.md "Storage keys"). Block 7101500-7101549: +0 language (1 en, 2 pt); slot s from 1
	-- to `slots`: base + 1 + s = state (0 or -1 not taken, 1..n the step in progress, 100 done), base + 21 + s = the
	-- step's count. Block 7101560-7101599 (`ext`) for the slots after `slots`: ext.base + n = state, ext.base +
	-- ext.count + n = count, n = s - slots - 1 (slots 20-39). A slot is never reused.
	storage = {base = 7101500, lang = 0, state = 1, count = 21, last = 7101549, slots = 19,
		ext = {base = 7101560, count = 20, last = 7101599}},
	done = 100,

	-- the visit steps: the characters waiting for one are checked this often; every visitSweep checks all online
	-- characters join the list (a talk step done in an NPC's own Lua state can start a visit)
	visitMs = 3000,
	visitSweep = 10,

	-- modal windows (answered in tales.lua): the list of tales, one tale
	modal = {list = 7170, tale = 7171},

	-- the NPC, placed next to the temples at startup like the Ascendant Oracle (a ring further out)
	npc = {
		name = "Archivist Maelis",
		spawn = true,
		townIds = {2, 1}, -- the main city (Cinderhold) first, then Mirewake (server/README.md "Main city")
		positions = {},
		offsets = {{5, 0}, {-5, 0}, {0, 5}, {0, -5}, {5, 3}, {-5, 3}, {5, -3}, {-5, -3}, {3, 5}, {-3, 5}},
		range = 6 -- accept and turn in only this close to her
	},

	-- party members this close (same floor) share a kill, like the bestiary
	partyRange = 30,

	-- the item the book of a tale is written into (a stock book: readable, not writeable)
	bookItem = 1950,

	ui = {
		listTitle = {en = "The Archivist's Ledger", pt = "O Registro da Arquivista"},
		listText = {en = "Tales the Archivist pays for. Pick one to read it.",
			pt = "Histórias pelas quais a Arquivista paga. Escolha uma para ler."},
		none = {en = "No tale for you yet. Come back at level %d.", pt = "Nenhuma história para você ainda. Volte no nível %d."},
		read = {en = "Read", pt = "Ler"}, close = {en = "Close", pt = "Fechar"},
		accept = {en = "Accept", pt = "Aceitar"}, turnin = {en = "Turn in", pt = "Entregar"},
		level = {en = "Level %d+", pt = "Nível %d+"},
		stateNew = {en = "new", pt = "nova"}, stateOn = {en = "in progress", pt = "em andamento"},
		stateDone = {en = "done", pt = "concluída"}, stateReady = {en = "ready to turn in", pt = "pronta para entregar"},
		steps = {en = "Steps", pt = "Etapas"}, rewards = {en = "Rewards", pt = "Recompensas"},
		accepted = {en = "Tale accepted: %s.", pt = "História aceita: %s."},
		progress = {en = "%s: %d / %d.", pt = "%s: %d / %d."},
		stepDone = {en = "%s: done. Return to the Archivist.", pt = "%s: concluído. Volte à Arquivista."},
		stepNext = {en = "%s: step done. Next: %s.", pt = "%s: etapa concluída. Próxima: %s."},
		finished = {en = "Tale complete: %s.", pt = "História concluída: %s."},
		tooFar = {en = "Stand next to the Archivist to do that.", pt = "Fique perto da Arquivista para fazer isso."},
		notYet = {en = "Not yet: %s", pt = "Ainda não: %s"},
		missing = {en = "You lack %d %s.", pt = "Faltam %d %s."},
		xp = {en = "%s experience", pt = "%s de experiência"},
		gold = {en = "%s gold (bank)", pt = "%s de ouro (banco)"},
		rep = {en = "%d reputation with %s", pt = "%d de reputação com %s"},
		book = {en = "the book \"%s\"", pt = "o livro \"%s\""},
		status = {en = "Tales: %s", pt = "Histórias: %s"}
	},

	factions = {vigil = "the Ashen Vigil", compact = "the Cinderforge Compact", choir = "the Veiled Choir",
		circle = "the Thornbound Circle"},

	-- the tales. slot: the storage slot (never reuse one). minLevel: who may take it; band: the levels it is written
	-- for (the experience is measured at most at band[2]). requires: a tale that must be done first (a chain). steps:
	-- kill (any of `monsters` by type or shown name, `count` of them), visit (stand within `radius` tiles of `pos`, same
	-- floor; a hunting mark of data/chaos_poi.lua, revealed on the map), talk (ask `npc` about the tale; it says
	-- `reply`), deliver (items handed over at the Archivist), report (talk to her). The last step is always deliver or
	-- report. rewards: xpLevels (that share of the experience of the next level), gold (to the bank), items, faction
	-- reputation, the lore book (lore_data.lua id; optional).
	tales = {
		{key = "bone_choir", slot = 1, minLevel = 200, band = {200, 299}, faction = "vigil",
			name = {en = "The Bone Choir", pt = "O Coro de Ossos"},
			story = {
				en = "A chapel sank into the marsh the night the Cinders fell. Its monks sang the dead asleep for a hundred "
					.. "years; now the dead sing back, and the song walks. The Ashen Vigil wants it silenced, and I want to "
					.. "know the words. Break the choir: forty of its singers.",
				pt = "Uma capela afundou no pântano na noite em que as Brasas caíram. Seus monges cantaram para os mortos "
					.. "dormirem por cem anos; agora os mortos cantam de volta, e a canção caminha. A Vigília Cinzenta quer "
					.. "silenciá-la, e eu quero saber a letra. Quebre o coro: quarenta de seus cantores."},
			steps = {
				{kind = "kill", count = 40,
					monsters = {"Deathrattle", "Skullshade", "Bonecleaver", "Doombone", "Blackblade"},
					text = {en = "Silence 40 of the choir's dead (Deathrattle, Skullshade, Bonecleaver, Doombone, Blackblade)",
						pt = "Silencie 40 mortos do coro (Deathrattle, Skullshade, Bonecleaver, Doombone, Blackblade)"}},
				{kind = "report",
					text = {en = "Tell the Archivist what they sang", pt = "Conte à Arquivista o que eles cantavam"}}
			},
			rewards = {xpLevels = 0.5, gold = 150000, items = {{id = UPHEAVAL, count = 3, name = "Orb of Upheaval"}},
				rep = 600, book = "rift_ashen"},
			outro = {en = "\"Rest, rest, the fire is coming.\" So that is what they sang. Thank you.",
				pt = "\"Descansem, descansem, o fogo está chegando.\" Então era isso que cantavam. Obrigada."}},

		{key = "wyrm_tithe", slot = 2, minLevel = 500, band = {500, 699}, faction = "compact",
			name = {en = "The Wyrm Tithe", pt = "O Dízimo dos Wyrms"},
			story = {
				en = "The wrym broods swallow Cinder shards the way birds swallow stones, and the Cinderforge Compact pays "
					.. "for every crop cut open. Their ledger is short twenty shards this season. Hunt the wrym and bring "
					.. "me the shards; I will see that the Compact remembers who paid the tithe.",
				pt = "As ninhadas de wrym engolem fragmentos de Brasa como pássaros engolem pedras, e o Pacto da Forja de "
					.. "Brasa paga por cada papo aberto. O livro deles está vinte fragmentos aquém nesta estação. Cace os "
					.. "wrym e me traga os fragmentos; farei o Pacto lembrar quem pagou o dízimo."},
			steps = {
				{kind = "kill", count = 50,
					monsters = {"Ashfang Wrym", "Shadowvein Wrym", "Stormvein Wrym", "Viridscale Wrym", "Flarevein Wyrm"},
					text = {en = "Slay 50 wrym (Ashfang, Shadowvein, Stormvein, Viridscale, Flarevein)",
						pt = "Abata 50 wrym (Ashfang, Shadowvein, Stormvein, Viridscale, Flarevein)"}},
				{kind = "deliver", items = {{id = SHARD, count = 20, name = "rune shards"}},
					text = {en = "Bring 20 rune shards to the Archivist", pt = "Leve 20 fragmentos rúnicos à Arquivista"}}
			},
			rewards = {xpLevels = 0.5, gold = 400000, items = {{id = FATE, count = 2, name = "Orb of Fate"}},
				rep = 800, book = "rift_obsidian"},
			outro = {en = "The tithe is paid. The Compact will spend it on steel, as always.",
				pt = "O dízimo está pago. O Pacto vai gastá-lo em aço, como sempre."}},

		{key = "ash_requiem", slot = 3, minLevel = 800, band = {800, 999}, faction = "vigil",
			name = {en = "Requiem for the Ash-Sister", pt = "Réquiem para a Irmã das Cinzas"},
			story = {
				en = "Morwen sang the dead to sleep inside the Sepulchre until the sleep turned to ash. Her court did not "
					.. "all stay behind the walls: some of it wanders the world, wearing other names. Thin them, then go "
					.. "in and end her song. I have kept a page for her last verse.",
				pt = "Morwen cantou para os mortos dormirem dentro do Sepulcro até o sono virar cinza. Nem toda a sua corte "
					.. "ficou atrás dos muros: parte dela vaga pelo mundo, usando outros nomes. Reduza-os, depois entre e "
					.. "encerre a canção dela. Guardei uma página para o último verso."},
			steps = {
				{kind = "kill", count = 60,
					monsters = {"Royal Man", "Golden Lord", "Frost Maiden", "Dreamgorger", "Loricate Orger", "Tundra Troll",
						"Swamp Snapper"},
					text = {en = "Thin the lost court: 60 of Royal Man, Golden Lord, Frost Maiden, Dreamgorger, Loricate Orger, "
						.. "Tundra Troll, Swamp Snapper", pt = "Reduza a corte perdida: 60 entre Royal Man, Golden Lord, Frost "
						.. "Maiden, Dreamgorger, Loricate Orger, Tundra Troll, Swamp Snapper"}},
				{kind = "kill", count = 1, monsters = {"Morwen the Ash-Sister"},
					text = {en = "Defeat Morwen the Ash-Sister in the Ashen Sepulchre",
						pt = "Derrote Morwen, a Irmã das Cinzas, no Sepulcro Cinzento"}},
				{kind = "report", text = {en = "Bring her last verse to the Archivist",
					pt = "Leve o último verso dela à Arquivista"}}
			},
			rewards = {xpLevels = 0.4, gold = 1000000, items = {{id = GRAFTING, count = 1, name = "Orb of Grafting"}},
				rep = 1200, book = "sepulchre"},
			outro = {en = "\"The last verse is yours.\" She was right, then. Write it well.",
				pt = "\"O último verso é seu.\" Ela tinha razão, então. Escreva-o bem."}},

		{key = "last_ember", slot = 4, minLevel = 1000, band = {1000, 1500}, faction = "choir",
			name = {en = "The Last Ember", pt = "A Última Brasa"},
			story = {
				en = "Every Omen sings of the first Cinder, the one that never cooled. The Veiled Choir says it has a name "
					.. "now. Before I write it, I want proof that someone can walk where it walks: end a warden of the deep "
					.. "places, then an Ascended Omen. Then come back, and I will tell you its name.",
				pt = "Todo Presságio canta sobre a primeira Brasa, a que nunca esfriou. O Coro Velado diz que ela agora "
					.. "tem um nome. Antes de escrevê-lo, quero prova de que alguém pode andar onde ela anda: derrube um "
					.. "guardião dos lugares profundos, depois um Presságio Ascendido. Então volte, e eu direi o nome dela."},
			steps = {
				{kind = "kill", count = 1, monsters = {"The Emberdeep Maw", "The Ossuary Warden", "Cinderwing"},
					text = {en = "Defeat a warden of the deep: the Emberdeep Maw, the Ossuary Warden or Cinderwing",
						pt = "Derrote um guardião das profundezas: The Emberdeep Maw, The Ossuary Warden ou Cinderwing"}},
				{kind = "kill", count = 1, monsters = {"Ascended Sangrith", "Ascended Morvane", "Ascended Thalcyra"},
					text = {en = "Defeat an Ascended Omen behind the Ember Gate",
						pt = "Derrote um Presságio Ascendido atrás do Portão de Brasa"}},
				{kind = "report", text = {en = "Hear the name from the Archivist", pt = "Ouça o nome da Arquivista"}}
			},
			rewards = {xpLevels = 0.3, gold = 2500000, items = {{id = GRAFTING, count = 2, name = "Orb of Grafting"}},
				rep = 1500, book = "cinderheart"},
			outro = {en = "Ysgrath. Say it once, and never near a fire.",
				pt = "Ysgrath. Diga uma vez, e nunca perto do fogo."}},

		-- ================================================================ 2026-10-22: 23 more tales, slots 5-27
		-- ---------------------------------------------------------------- 8-60: the Lantern Road (Vigil chain), the
		-- Compact's debts, the Circle's giants
		{key = "cellar_teeth", slot = 5, minLevel = 8, band = {8, 30}, faction = "circle",
			name = {en = "Teeth in the Cellars", pt = "Dentes nos Porões"},
			story = {
				en = "Something gnaws at the ledgers I keep below the city. The cellars under Cinderhold were dug before the "
					.. "Cinders fell, and the rats there have grown fat on ash and old paper. Go down, see the place with your "
					.. "own eyes, and thin them before they eat the year I was born.",
				pt = "Algo rói os registros que guardo debaixo da cidade. Os porões sob Cinderhold foram cavados antes da "
					.. "queda das Brasas, e os ratos de lá engordaram com cinza e papel velho. Desça, veja o lugar com seus "
					.. "próprios olhos e reduza-os antes que comam o ano em que eu nasci."},
			steps = {
				{kind = "visit", pos = {x = 32378, y = 32226, z = 8}, radius = 8,
					text = {en = "Go down into the cellars under Cinderhold (marked on your map)",
						pt = "Desça aos porões sob Cinderhold (marcado no seu mapa)"}},
				{kind = "kill", count = 25, monsters = {"Rat", "Cave Rat"},
					text = {en = "Kill 25 rats of the cellars (Rat, Cave Rat)", pt = "Mate 25 ratos dos porões (Rat, Cave Rat)"}},
				{kind = "report", text = {en = "Tell the Archivist the ledgers are safe",
					pt = "Diga à Arquivista que os registros estão a salvo"}}
			},
			rewards = {xpLevels = 1.0, gold = 1500, rep = 100, book = "cellars"},
			outro = {en = "Good. One of them had eaten half a king. I will copy him again.",
				pt = "Bom. Um deles tinha comido meio rei. Vou copiá-lo de novo."}},

		{key = "lantern_road", slot = 6, minLevel = 12, band = {12, 40}, faction = "vigil", requires = "cellar_teeth",
			name = {en = "The Lantern Road", pt = "A Estrada das Lanternas"},
			story = {
				en = "You found the cellars; now find the road. The Ashen Vigil once lit a lantern on every grave between "
					.. "the towns, so the dead would know the way to rest. The lanterns went out. Ask Warden Ysolde in "
					.. "Cinderhold where the road begins, then put down what walks it.",
				pt = "Você achou os porões; agora ache a estrada. A Vigília Cinzenta acendia uma lanterna em cada túmulo entre "
					.. "as cidades, para que os mortos soubessem o caminho do descanso. As lanternas se apagaram. Pergunte à "
					.. "Warden Ysolde, em Cinderhold, onde a estrada começa, e derrube o que caminha por ela."},
			steps = {
				{kind = "talk", npc = YSOLDE,
					text = {en = "Ask Warden Ysolde in Cinderhold about the tale", pt = "Pergunte à Warden Ysolde, em Cinderhold, sobre a história"},
					reply = {en = "The Archivist sent you? Then hear it: the road starts at every grave that lost its lantern. "
						.. "Walk it and break what rises.",
						pt = "A Arquivista mandou você? Então ouça: a estrada começa em cada túmulo que perdeu sua lanterna. "
						.. "Percorra-a e quebre o que se levantar."}},
				{kind = "kill", count = 30, monsters = {"Skeleton", "Skeleton Warrior", "Ghost", "Tarnished Spirit", "Ghoul"},
					text = {en = "Put down 30 of the restless dead (Skeleton, Skeleton Warrior, Ghost, Tarnished Spirit, Ghoul)",
						pt = "Derrube 30 mortos inquietos (Skeleton, Skeleton Warrior, Ghost, Tarnished Spirit, Ghoul)"}},
				{kind = "report", text = {en = "Tell the Archivist how far the road goes", pt = "Conte à Arquivista até onde vai a estrada"}}
			},
			rewards = {xpLevels = 1.0, gold = 3000, rep = 150, book = "lantern_road"},
			outro = {en = "Further than the Vigil admits, then. I will mark every grave you named.",
				pt = "Mais longe do que a Vigília admite, então. Vou marcar cada túmulo que você nomeou."}},

		{key = "troll_toll", slot = 7, minLevel = 15, band = {15, 40}, faction = "compact",
			name = {en = "The Troll Toll", pt = "O Pedágio dos Trolls"},
			story = {
				en = "Trolls have learned to charge a toll on the roads the Compact's wagons use, and they collect it in "
					.. "teeth. Forgemaster Brannoc in Mirewake wants the roads open and a count he can trust. Break the toll "
					.. "gangs, then tell him yourself; he believes no one's ink but his own.",
				pt = "Os trolls aprenderam a cobrar pedágio nas estradas que as carroças do Pacto usam, e cobram em dentes. "
					.. "O Forgemaster Brannoc, em Mirewake, quer as estradas livres e uma contagem em que possa confiar. "
					.. "Quebre os bandos do pedágio e conte a ele você mesmo; ele não acredita em tinta que não seja a dele."},
			steps = {
				{kind = "kill", count = 35, monsters = {"Troll", "Swamp Troll", "Mountain Troll", "Frost Troll", "Island Troll"},
					text = {en = "Break the toll gangs: 35 trolls (Troll, Swamp, Mountain, Frost or Island Troll)",
						pt = "Quebre os bandos do pedágio: 35 trolls (Troll, Swamp, Mountain, Frost ou Island Troll)"}},
				{kind = "talk", npc = BRANNOC,
					text = {en = "Tell Forgemaster Brannoc in Mirewake about the tale", pt = "Conte ao Forgemaster Brannoc, em Mirewake, sobre a história"},
					reply = {en = "Thirty-five? Then the wagons roll again. Tell the Archivist the Compact pays its debts.",
						pt = "Trinta e cinco? Então as carroças voltam a rodar. Diga à Arquivista que o Pacto paga suas dívidas."}},
				{kind = "report", text = {en = "Bring Brannoc's word to the Archivist", pt = "Leve a palavra de Brannoc à Arquivista"}}
			},
			rewards = {xpLevels = 1.0, gold = 4000, rep = 150},
			outro = {en = "He paid you in words? That is rare for him. I pay in coin.",
				pt = "Ele pagou você com palavras? Isso é raro para ele. Eu pago em moedas."}},

		{key = "anvildeep_deserters", slot = 8, minLevel = 20, band = {20, 50}, faction = "compact",
			name = {en = "The Deserters of Anvildeep", pt = "Os Desertores de Anvildeep"},
			story = {
				en = "A company of dwarves broke their oath to the obsidian forges and took a mine with them. The Compact "
					.. "calls it theft; the dwarves call it a strike. I call it a page I want written. Find their tunnels near "
					.. "Anvildeep and end the strike the way the Compact ends everything.",
				pt = "Uma companhia de anões quebrou o juramento às forjas de obsidiana e levou uma mina junto. O Pacto chama "
					.. "isso de roubo; os anões chamam de greve. Eu chamo de página que quero escrita. Encontre os túneis deles "
					.. "perto de Anvildeep e termine a greve do jeito que o Pacto termina tudo."},
			steps = {
				{kind = "visit", pos = {x = 32515, y = 31946, z = 11}, radius = 8,
					text = {en = "Find the deserters' tunnels near Anvildeep (marked on your map)",
						pt = "Encontre os túneis dos desertores perto de Anvildeep (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Dwarf Soldier", "Dwarf Guard", "Dwarf Geomancer", "Dwarf"},
					text = {en = "Defeat 40 deserters (Dwarf, Dwarf Soldier, Dwarf Guard, Dwarf Geomancer)",
						pt = "Derrote 40 desertores (Dwarf, Dwarf Soldier, Dwarf Guard, Dwarf Geomancer)"}},
				{kind = "report", text = {en = "Tell the Archivist how the strike ended", pt = "Conte à Arquivista como a greve terminou"}}
			},
			rewards = {xpLevels = 0.8, gold = 6000, items = {{id = AWAKENING, count = 2, name = "Orb of Awakening"}}, rep = 200},
			outro = {en = "Badly, as strikes against fire always do. I will write their names anyway.",
				pt = "Mal, como sempre terminam as greves contra o fogo. Vou escrever os nomes deles mesmo assim."}},

		{key = "rime_giants", slot = 9, minLevel = 25, band = {25, 60}, faction = "circle",
			name = {en = "Rime and Ruin", pt = "Geada e Ruína"},
			story = {
				en = "The frost giants of the north have come down from their halls and trampled the Thornbound Circle's "
					.. "winter groves. Elder Bramwyn asked me for someone who does not mind the cold. Walk into the giants' "
					.. "halls near Rimeholt, drive them back, then let Bramwyn in Thornmere hear it from you.",
				pt = "Os gigantes de gelo do norte desceram de seus salões e pisotearam os bosques de inverno do Círculo "
					.. "Espinhoso. O Elder Bramwyn me pediu alguém que não se importe com o frio. Entre nos salões dos gigantes "
					.. "perto de Rimeholt, faça-os recuar e deixe que Bramwyn, em Thornmere, ouça isso de você."},
			steps = {
				{kind = "visit", pos = {x = 32398, y = 31280, z = 9}, radius = 8,
					text = {en = "Enter the giants' halls near Rimeholt (marked on your map)",
						pt = "Entre nos salões dos gigantes perto de Rimeholt (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Frost Giant", "Frost Giantess"},
					text = {en = "Drive back 40 frost giants (Frost Giant, Frost Giantess)",
						pt = "Faça recuar 40 gigantes de gelo (Frost Giant, Frost Giantess)"}},
				{kind = "talk", npc = BRAMWYN,
					text = {en = "Tell Elder Bramwyn in Thornmere about the tale", pt = "Conte ao Elder Bramwyn, em Thornmere, sobre a história"},
					reply = {en = "The groves will grow back slower than the giants. Still, they will grow. Thank the Archivist for me.",
						pt = "Os bosques vão crescer mais devagar que os gigantes. Ainda assim, vão crescer. Agradeça à Arquivista por mim."}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.8, gold = 7500, items = {{id = AWAKENING, count = 2, name = "Orb of Awakening"}}, rep = 200},
			outro = {en = "Bramwyn thanked someone? Write the date down. It will not happen again.",
				pt = "Bramwyn agradeceu alguém? Anote a data. Isso não vai se repetir."}},

		{key = "stone_watchers", slot = 10, minLevel = 30, band = {30, 70}, faction = "vigil", requires = "lantern_road",
			name = {en = "The Stone Watchers", pt = "Os Vigias de Pedra"},
			story = {
				en = "The Lantern Road ends at a roost of gargoyles. The Vigil carved them to watch over the graves; the "
					.. "Cinders woke them, and now they watch for the living instead. Find the roost, break the watchers and "
					.. "the dead they guard.",
				pt = "A Estrada das Lanternas termina num poleiro de gárgulas. A Vigília as esculpiu para vigiar os túmulos; "
					.. "as Brasas as despertaram, e agora elas vigiam os vivos. Encontre o poleiro e quebre os vigias e os "
					.. "mortos que eles guardam."},
			steps = {
				{kind = "visit", pos = {x = 32240, y = 32586, z = 9}, radius = 8,
					text = {en = "Find the gargoyle roost at the road's end (marked on your map)",
						pt = "Encontre o poleiro das gárgulas no fim da estrada (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Gargoyle", "Zombie", "Stone Golem"},
					text = {en = "Break 40 watchers and their dead (Gargoyle, Zombie, Stone Golem)",
						pt = "Quebre 40 vigias e seus mortos (Gargoyle, Zombie, Stone Golem)"}},
				{kind = "report", text = {en = "Tell the Archivist what the watchers guarded", pt = "Conte à Arquivista o que os vigias guardavam"}}
			},
			rewards = {xpLevels = 0.8, gold = 10000, items = {{id = AWAKENING, count = 3, name = "Orb of Awakening"}}, rep = 250},
			outro = {en = "A circle of open graves. Someone is gathering the dead, then. The road goes on.",
				pt = "Um círculo de túmulos abertos. Alguém está reunindo os mortos, então. A estrada continua."}},

		{key = "grave_circle", slot = 11, minLevel = 40, band = {40, 90}, faction = "vigil", requires = "stone_watchers",
			name = {en = "The Grave Circle", pt = "O Círculo das Covas"},
			story = {
				en = "The open graves lead to a circle of necromancers who think the Cinders were a gift. They raise "
					.. "bonebeasts from the Vigil's own dead, and a lich and a banshee keep their books. Go to the circle, "
					.. "end its servants, then its keepers. Bring me whatever they were writing.",
				pt = "Os túmulos abertos levam a um círculo de necromantes que acham que as Brasas foram um presente. Eles "
					.. "erguem bestas de ossos dos próprios mortos da Vigília, e um lich e uma banshee guardam seus livros. Vá "
					.. "ao círculo, acabe com seus servos, depois com seus guardiões. Traga-me o que estavam escrevendo."},
			steps = {
				{kind = "visit", pos = {x = 33029, y = 31619, z = 10}, radius = 8,
					text = {en = "Find the grave circle (marked on your map)", pt = "Encontre o círculo das covas (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Necromancer", "Bonebeast"},
					text = {en = "End 40 of the circle's servants (Necromancer, Bonebeast)",
						pt = "Acabe com 40 servos do círculo (Necromancer, Bonebeast)"}},
				{kind = "kill", count = 15, monsters = {"Lich", "Banshee"},
					text = {en = "End 15 keepers of its books (Lich, Banshee)", pt = "Acabe com 15 guardiões de seus livros (Lich, Banshee)"}},
				{kind = "report", text = {en = "Bring the circle's pages to the Archivist", pt = "Leve as páginas do círculo à Arquivista"}}
			},
			rewards = {xpLevels = 0.75, gold = 15000, items = {{id = WHETSTONE, count = 2, name = "Whetstone"},
				{id = TEMPERING, count = 1, name = "Orb of Tempering"}}, rep = 300, book = "grave_circle"},
			outro = {en = "A list of names, and mine is on it. Burn nothing yet. I want to know who wrote it.",
				pt = "Uma lista de nomes, e o meu está nela. Não queime nada ainda. Quero saber quem a escreveu."}},

		-- ---------------------------------------------------------------- 50-260: the Dragon Census (Choir chain), the
		-- Moon-Sick (Circle chain), the Bone Court (Vigil chain), the Pit
		{key = "dragon_census", slot = 12, minLevel = 50, band = {50, 100}, faction = "choir",
			name = {en = "The Dragon Census", pt = "O Censo dos Dragões"},
			story = {
				en = "The Veiled Choir counts dragons the way farmers count clouds: to know what the year will bring. Their "
					.. "count is old. Find the lair near Ashstrand, thin the brood so the count means something, then tell "
					.. "Cantor Velith in Bellwatch what you saw.",
				pt = "O Coro Velado conta dragões como fazendeiros contam nuvens: para saber o que o ano trará. A contagem "
					.. "deles está velha. Encontre o covil perto de Ashstrand, reduza a ninhada para que a contagem faça "
					.. "sentido e conte ao Cantor Velith, em Bellwatch, o que você viu."},
			steps = {
				{kind = "visit", pos = {x = 33215, y = 31297, z = 7}, radius = 8,
					text = {en = "Find the dragon lair near Ashstrand (marked on your map)",
						pt = "Encontre o covil dos dragões perto de Ashstrand (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Dragon", "Dragon Hatchling"},
					text = {en = "Thin the brood: 40 dragons (Dragon, Dragon Hatchling)", pt = "Reduza a ninhada: 40 dragões (Dragon, Dragon Hatchling)"}},
				{kind = "talk", npc = VELITH,
					text = {en = "Tell Cantor Velith in Bellwatch about the tale", pt = "Conte ao Cantor Velith, em Bellwatch, sobre a história"},
					reply = {en = "Forty, and the eggs still warm. The count is worse than we sang. The Archivist will want the lords' names too.",
						pt = "Quarenta, e os ovos ainda quentes. A contagem é pior do que cantamos. A Arquivista vai querer os nomes dos senhores também."}},
				{kind = "report", text = {en = "Bring the new count to the Archivist", pt = "Leve a nova contagem à Arquivista"}}
			},
			rewards = {xpLevels = 0.75, gold = 22000, items = {{id = WHETSTONE, count = 2, name = "Whetstone"}}, rep = 300,
				book = "dragon_census"},
			outro = {en = "The census is open again. Come back when you can face the lords of the brood.",
				pt = "O censo está aberto de novo. Volte quando puder enfrentar os senhores da ninhada."}},

		{key = "moon_sick", slot = 13, minLevel = 65, band = {65, 120}, faction = "circle",
			name = {en = "The Moon-Sick", pt = "Os Enfermos da Lua"},
			story = {
				en = "Under a Cinder moon some hunters do not come home as hunters. The Thornbound Circle calls them the "
					.. "moon-sick and will not kill its own. You will. End the beasts they became, then tell Elder Bramwyn, "
					.. "so the Circle can stop setting places at its table.",
				pt = "Sob uma lua de Brasa, alguns caçadores não voltam para casa como caçadores. O Círculo Espinhoso os chama "
					.. "de enfermos da lua e não mata os seus. Você vai matar. Acabe com as feras em que eles se tornaram e "
					.. "conte ao Elder Bramwyn, para que o Círculo pare de pôr lugares à mesa."},
			steps = {
				{kind = "kill", count = 40, monsters = {"Werewolf", "Werebear", "Werebadger", "Wereboar", "Werelion", "Werelioness"},
					text = {en = "End 40 of the moon-sick (Werewolf, Werebear, Werebadger, Wereboar, Werelion, Werelioness)",
						pt = "Acabe com 40 enfermos da lua (Werewolf, Werebear, Werebadger, Wereboar, Werelion, Werelioness)"}},
				{kind = "talk", npc = BRAMWYN,
					text = {en = "Tell Elder Bramwyn in Thornmere about the tale", pt = "Conte ao Elder Bramwyn, em Thornmere, sobre a história"},
					reply = {en = "Then they rest. Something drives them toward the marsh, though. Ask the Archivist about the hundred heads.",
						pt = "Então eles descansam. Mas algo os empurra para o pântano. Pergunte à Arquivista sobre as cem cabeças."}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.7, gold = 30000, items = {{id = UPHEAVAL, count = 1, name = "Orb of Upheaval"}}, rep = 400,
				book = "moon_sick"},
			outro = {en = "The hundred heads. Yes. I hoped no one would ask me that.",
				pt = "As cem cabeças. Sim. Eu esperava que ninguém me perguntasse isso."}},

		{key = "dragon_lords", slot = 14, minLevel = 70, band = {70, 130}, faction = "choir", requires = "dragon_census",
			name = {en = "Lords of the Brood", pt = "Senhores da Ninhada"},
			story = {
				en = "The census named the lords of the brood: the great red ones and the white ones of the ice. The Choir "
					.. "wants them fewer, and I want rune shards to bind the pages, since dragon fire eats ordinary glue. "
					.. "Hunt the lords and bring me the shards.",
				pt = "O censo nomeou os senhores da ninhada: os grandes vermelhos e os brancos do gelo. O Coro os quer em menor "
					.. "número, e eu quero fragmentos rúnicos para unir as páginas, já que o fogo de dragão come cola comum. "
					.. "Cace os senhores e me traga os fragmentos."},
			steps = {
				{kind = "kill", count = 30, monsters = {"Dragon Lord", "Dragon Lord Hatchling", "Frost Dragon", "Frost Dragon Hatchling"},
					text = {en = "Hunt 30 lords of the brood (Dragon Lord, Frost Dragon and their hatchlings)",
						pt = "Cace 30 senhores da ninhada (Dragon Lord, Frost Dragon e seus filhotes)"}},
				{kind = "deliver", items = {{id = SHARD, count = 10, name = "rune shards"}},
					text = {en = "Bring 10 rune shards to the Archivist", pt = "Leve 10 fragmentos rúnicos à Arquivista"}}
			},
			rewards = {xpLevels = 0.7, gold = 35000, items = {{id = TEMPERING, count = 2, name = "Orb of Tempering"}}, rep = 400},
			outro = {en = "Bound. The census will outlive both of us now.",
				pt = "Encadernado. O censo vai durar mais que nós dois agora."}},

		{key = "hundred_heads", slot = 15, minLevel = 85, band = {85, 150}, faction = "circle", requires = "moon_sick",
			name = {en = "The Hundred Heads", pt = "As Cem Cabeças"},
			story = {
				en = "The marsh near Brassgate has a mother. Every head you cut from her children grows back as two, and "
					.. "the bog raiders feed them. The moon-sick were running from her. Go into the marsh and cut until the "
					.. "count runs the other way.",
				pt = "O pântano perto de Brassgate tem uma mãe. Cada cabeça que você corta dos filhos dela volta como duas, e "
					.. "os saqueadores do lodo os alimentam. Os enfermos da lua fugiam dela. Entre no pântano e corte até a "
					.. "conta andar para o outro lado."},
			steps = {
				{kind = "visit", pos = {x = 33480, y = 31925, z = 9}, radius = 8,
					text = {en = "Enter the hydra marsh near Brassgate (marked on your map)",
						pt = "Entre no pântano das hidras perto de Brassgate (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Hydra", "Bog Raider"},
					text = {en = "Cut down 40 of the marsh's children (Hydra, Bog Raider)", pt = "Derrube 40 filhos do pântano (Hydra, Bog Raider)"}},
				{kind = "report", text = {en = "Tell the Archivist the count", pt = "Diga à Arquivista a contagem"}}
			},
			rewards = {xpLevels = 0.7, gold = 40000, items = {{id = UPHEAVAL, count = 2, name = "Orb of Upheaval"}}, rep = 400},
			outro = {en = "Fewer heads than yesterday. In a marsh, that is what victory looks like.",
				pt = "Menos cabeças que ontem. Num pântano, é assim que a vitória se parece."}},

		{key = "lost_souls", slot = 16, minLevel = 100, band = {100, 180}, faction = "vigil",
			name = {en = "Where the Lost Souls Walk", pt = "Onde as Almas Perdidas Caminham"},
			story = {
				en = "The Vigil's bells ring by themselves now, deep under Slagdelve, where the lost souls walk in a ring "
					.. "and the betrayed follow them. Warden Ysolde wants the bells quiet. Quiet the souls, then tell her the "
					.. "bells can rest.",
				pt = "Os sinos da Vigília tocam sozinhos agora, bem fundo sob Slagdelve, onde as almas perdidas caminham em "
					.. "roda e os traídos as seguem. A Warden Ysolde quer os sinos em silêncio. Silencie as almas e diga a ela "
					.. "que os sinos podem descansar."},
			steps = {
				{kind = "kill", count = 50, monsters = {"Lost Soul", "Betrayed Wraith"},
					text = {en = "Quiet 50 souls (Lost Soul, Betrayed Wraith)", pt = "Silencie 50 almas (Lost Soul, Betrayed Wraith)"}},
				{kind = "talk", npc = YSOLDE,
					text = {en = "Tell Warden Ysolde in Cinderhold about the tale", pt = "Conte à Warden Ysolde, em Cinderhold, sobre a história"},
					reply = {en = "The bells stopped an hour ago. One of the souls wore a court's colours. Tell the Archivist: bones, and a crown.",
						pt = "Os sinos pararam há uma hora. Uma das almas usava as cores de uma corte. Diga à Arquivista: ossos, e uma coroa."}},
				{kind = "report", text = {en = "Bring Ysolde's warning to the Archivist", pt = "Leve o aviso de Ysolde à Arquivista"}}
			},
			rewards = {xpLevels = 0.6, gold = 50000, items = {{id = UPHEAVAL, count = 2, name = "Orb of Upheaval"}}, rep = 450},
			outro = {en = "Bones and a crown. I know that court. I had hoped it stayed buried.",
				pt = "Ossos e uma coroa. Eu conheço essa corte. Esperava que continuasse enterrada."}},

		{key = "bone_court", slot = 17, minLevel = 120, band = {120, 200}, faction = "vigil", requires = "lost_souls",
			name = {en = "The Bone Court", pt = "A Corte de Ossos"},
			story = {
				en = "Before the Sepulchre had its Sovereign, the Bone Court had its own: archers who never miss, "
					.. "berserkers who never tire, masters who never forget an insult. They have risen in the west. Break "
					.. "the court and bring me rune shards; I will seal its records so it cannot rise a third time.",
				pt = "Antes de o Sepulcro ter seu Soberano, a Corte de Ossos tinha o seu: arqueiros que nunca erram, berserkers "
					.. "que nunca cansam, mestres que nunca esquecem uma ofensa. Eles se ergueram no oeste. Quebre a corte e "
					.. "traga-me fragmentos rúnicos; vou selar seus registros para que não se erga uma terceira vez."},
			steps = {
				{kind = "kill", count = 50, monsters = {"Bone Archer", "Bone Berserker", "Bone Slicer", "Bone Warrior", "Bone Master"},
					text = {en = "Break 50 of the Bone Court (Bone Archer, Berserker, Slicer, Warrior, Master)",
						pt = "Quebre 50 da Corte de Ossos (Bone Archer, Berserker, Slicer, Warrior, Master)"}},
				{kind = "deliver", items = {{id = SHARD, count = 15, name = "rune shards"}},
					text = {en = "Bring 15 rune shards to seal the records", pt = "Leve 15 fragmentos rúnicos para selar os registros"}}
			},
			rewards = {xpLevels = 0.6, gold = 70000, items = {{id = UPHEAVAL, count = 3, name = "Orb of Upheaval"}}, rep = 500,
				book = "bone_court"},
			outro = {en = "Sealed. The court is a page now, and pages do not march.",
				pt = "Selado. A corte agora é uma página, e páginas não marcham."}},

		{key = "pit_outcasts", slot = 18, minLevel = 130, band = {130, 220}, faction = "compact",
			name = {en = "Outcasts of the Pit", pt = "Os Proscritos do Abismo"},
			story = {
				en = "Even demons have exiles. The outcasts near Nightwrack were thrown out of something deeper, and they "
					.. "sell what they know to anyone with steel. The Compact would rather they sold nothing. End the "
					.. "outcasts and their torturers, then tell Forgemaster Brannoc the market is closed.",
				pt = "Até demônios têm exilados. Os proscritos perto de Nightwrack foram expulsos de algo mais fundo, e vendem "
					.. "o que sabem a quem tiver aço. O Pacto prefere que não vendam nada. Acabe com os proscritos e seus "
					.. "torturadores e diga ao Forgemaster Brannoc que o mercado fechou."},
			steps = {
				{kind = "kill", count = 50, monsters = {"Demon Outcast", "Dark Torturer", "Hellspawn"},
					text = {en = "End 50 of the pit's exiles (Demon Outcast, Dark Torturer, Hellspawn)",
						pt = "Acabe com 50 exilados do abismo (Demon Outcast, Dark Torturer, Hellspawn)"}},
				{kind = "talk", npc = BRANNOC,
					text = {en = "Tell Forgemaster Brannoc in Mirewake about the tale", pt = "Conte ao Forgemaster Brannoc, em Mirewake, sobre a história"},
					reply = {en = "Closed. Good. What they sold was always half a lie, and the other half was worse.",
						pt = "Fechado. Ótimo. O que vendiam era sempre meia mentira, e a outra metade era pior."}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.6, gold = 75000, items = {{id = UPHEAVAL, count = 2, name = "Orb of Upheaval"}}, rep = 500},
			outro = {en = "I bought one of their secrets once. It was the price of the next one.",
				pt = "Comprei um segredo deles uma vez. Era o preço do próximo."}},

		{key = "unburied_wings", slot = 19, minLevel = 160, band = {160, 260}, faction = "choir", requires = "dragon_lords",
			name = {en = "Wings of the Unburied", pt = "Asas dos Insepultos"},
			story = {
				en = "The lords you hunted did not all stay dead. Under Nightwrack their bones fly again, with the flayers "
					.. "that serve them, and the black dragons come to feed on what is left. Find the boneyard, end the "
					.. "unburied, then the black ones. The census must count the dead too.",
				pt = "Os senhores que você caçou não ficaram todos mortos. Sob Nightwrack, seus ossos voam de novo, com os "
					.. "esfoladores que os servem, e os dragões negros vêm se alimentar do que sobra. Encontre o cemitério de "
					.. "ossos, acabe com os insepultos e depois com os negros. O censo precisa contar os mortos também."},
			steps = {
				{kind = "visit", pos = {x = 33397, y = 32360, z = 13}, radius = 8,
					text = {en = "Find the dragons' boneyard under Nightwrack (marked on your map)",
						pt = "Encontre o cemitério dos dragões sob Nightwrack (marcado no seu mapa)"}},
				{kind = "kill", count = 40, monsters = {"Undead Dragon", "Hellflayer"},
					text = {en = "End 40 of the unburied (Undead Dragon, Hellflayer)", pt = "Acabe com 40 insepultos (Undead Dragon, Hellflayer)"}},
				{kind = "kill", count = 15, monsters = {"Black Dragon"},
					text = {en = "End 15 Black Dragons that feed there", pt = "Acabe com 15 Black Dragons que se alimentam lá"}},
				{kind = "report", text = {en = "Bring the count of the dead to the Archivist", pt = "Leve a contagem dos mortos à Arquivista"}}
			},
			rewards = {xpLevels = 0.6, gold = 100000, items = {{id = UPHEAVAL, count = 3, name = "Orb of Upheaval"}}, rep = 550},
			outro = {en = "The census closes on a number no one will sing. Thank you for every one of them.",
				pt = "O censo fecha num número que ninguém vai cantar. Obrigada por cada um deles."}},

		-- ---------------------------------------------------------------- 340-650
		{key = "mould_gardens", slot = 20, minLevel = 340, band = {340, 480}, faction = "circle",
			name = {en = "The Mould Gardens", pt = "Os Jardins de Mofo"},
			story = {
				en = "Far east of Ashstrand, a garden grew on a fallen Cinder. Its golems are made of rot and its phantoms "
					.. "of spores, and the Thornbound Circle wants it pruned before the wind changes. Walk into the garden "
					.. "and cut it back to the stone.",
				pt = "Muito a leste de Ashstrand, um jardim cresceu sobre uma Brasa caída. Seus golens são feitos de podridão "
					.. "e seus fantasmas de esporos, e o Círculo Espinhoso quer que seja podado antes que o vento mude. Entre no "
					.. "jardim e corte-o até a pedra."},
			steps = {
				{kind = "visit", pos = {x = 33782, y = 31299, z = 13}, radius = 8,
					text = {en = "Enter the mould gardens (marked on your map)", pt = "Entre nos jardins de mofo (marcado no seu mapa)"}},
				{kind = "kill", count = 60, monsters = {"Rotten Golem", "Mould Phantom", "Branchy Crawler"},
					text = {en = "Cut back 60 of the garden (Rotten Golem, Mould Phantom, Branchy Crawler)",
						pt = "Pode 60 do jardim (Rotten Golem, Mould Phantom, Branchy Crawler)"}},
				{kind = "report", text = {en = "Tell the Archivist the garden is pruned", pt = "Diga à Arquivista que o jardim foi podado"}}
			},
			rewards = {xpLevels = 0.5, gold = 250000, items = {{id = UPHEAVAL, count = 2, name = "Orb of Upheaval"},
				{id = FATE, count = 1, name = "Orb of Fate"}}, rep = 700},
			outro = {en = "Pruned, not dead. Gardens never die. Neither, it seems, do you.",
				pt = "Podado, não morto. Jardins nunca morrem. Pelo visto, você também não."}},

		{key = "furnace_phantoms", slot = 21, minLevel = 360, band = {360, 500}, faction = "compact",
			name = {en = "Phantoms of the Furnace", pt = "Fantasmas da Fornalha"},
			story = {
				en = "The Compact dug one forge too deep, and what came up the flue was not smoke. Infernal demons and "
					.. "their phantoms now hold the old furnace. Clear it, and bring me rune shards to bind the Compact's "
					.. "confession: they asked me to write it, and I want it to last.",
				pt = "O Pacto cavou uma forja fundo demais, e o que subiu pela chaminé não era fumaça. Demônios infernais e "
					.. "seus fantasmas agora tomam a velha fornalha. Limpe-a e traga-me fragmentos rúnicos para encadernar a "
					.. "confissão do Pacto: pediram que eu a escrevesse, e quero que dure."},
			steps = {
				{kind = "kill", count = 60, monsters = {"Infernal Demon", "Infernal Phantom"},
					text = {en = "Clear 60 of the furnace (Infernal Demon, Infernal Phantom)",
						pt = "Limpe 60 da fornalha (Infernal Demon, Infernal Phantom)"}},
				{kind = "deliver", items = {{id = SHARD, count = 20, name = "rune shards"}},
					text = {en = "Bring 20 rune shards to the Archivist", pt = "Leve 20 fragmentos rúnicos à Arquivista"}}
			},
			rewards = {xpLevels = 0.5, gold = 280000, items = {{id = FATE, count = 1, name = "Orb of Fate"}}, rep = 700},
			outro = {en = "The confession is bound. The Compact will deny every word of it, in steel.",
				pt = "A confissão está encadernada. O Pacto vai negar cada palavra dela, em aço."}},

		{key = "ash_widows", slot = 22, minLevel = 470, band = {470, 650}, faction = "circle",
			name = {en = "The Ash Widows", pt = "As Viúvas de Cinza"},
			story = {
				en = "South of Dunescar the widows spin silk out of ash, and the hexers sell it as burial cloth. Whatever is "
					.. "wrapped in it does not stay buried. End the widows and the hands that trade their silk, then tell "
					.. "Elder Bramwyn the trade is cut.",
				pt = "Ao sul de Dunescar, as viúvas tecem seda com cinza, e os bruxos a vendem como mortalha. O que é "
					.. "envolvido nela não fica enterrado. Acabe com as viúvas e com as mãos que vendem sua seda e diga ao "
					.. "Elder Bramwyn que o comércio foi cortado."},
			steps = {
				{kind = "kill", count = 60, monsters = {"Nightfang Widow", "Mirethorn Hexer", "Gloomstinger", "Bloodspark Adept"},
					text = {en = "End 60 widows and traders (Nightfang Widow, Mirethorn Hexer, Gloomstinger, Bloodspark Adept)",
						pt = "Acabe com 60 viúvas e comerciantes (Nightfang Widow, Mirethorn Hexer, Gloomstinger, Bloodspark Adept)"}},
				{kind = "talk", npc = BRAMWYN,
					text = {en = "Tell Elder Bramwyn in Thornmere about the tale", pt = "Conte ao Elder Bramwyn, em Thornmere, sobre a história"},
					reply = {en = "Cut, and the cloth burned? Then the dead in the south may finally sleep.",
						pt = "Cortado, e a seda queimada? Então os mortos do sul talvez finalmente durmam."}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.5, gold = 350000, items = {{id = FATE, count = 2, name = "Orb of Fate"}}, rep = 800},
			outro = {en = "I kept one thread of it. For the ledger, only. Do not look at me like that.",
				pt = "Guardei um fio dela. Só para o registro. Não me olhe assim."}},

		-- ---------------------------------------------------------------- 800-2000: the generated dungeons; the last
		-- three are a chain (the Crucible, the Sanctum, the Throne)
		{key = "vault_keeper", slot = 23, minLevel = 800, band = {800, 1000}, faction = "compact",
			name = {en = "The Keeper's Key", pt = "A Chave do Guardião"},
			story = {
				en = "The Hollow Vault was the Compact's treasury before it was hollow. Its keeper, Ossrim, still counts "
					.. "coins that are not there and kills anyone who disagrees with the sum. End him, and bring me rune "
					.. "shards to close the Compact's oldest open account.",
				pt = "O Cofre Oco era o tesouro do Pacto antes de ficar oco. Seu guardião, Ossrim, ainda conta moedas que "
					.. "não estão lá e mata quem discorda da soma. Acabe com ele e traga-me fragmentos rúnicos para fechar a "
					.. "conta aberta mais antiga do Pacto."},
			steps = {
				{kind = "kill", count = 1, monsters = {"Vault Keeper Ossrim"},
					text = {en = "Defeat Vault Keeper Ossrim in the Hollow Vault", pt = "Derrote Vault Keeper Ossrim no Cofre Oco"}},
				{kind = "deliver", items = {{id = SHARD, count = 30, name = "rune shards"}},
					text = {en = "Bring 30 rune shards to the Archivist", pt = "Leve 30 fragmentos rúnicos à Arquivista"}}
			},
			rewards = {xpLevels = 0.4, gold = 900000, items = {{id = GRAFTING, count = 1, name = "Orb of Grafting"}}, rep = 1100,
				book = "deep_wardens"},
			outro = {en = "The account is closed. The sum was zero. It always was.",
				pt = "A conta está fechada. A soma era zero. Sempre foi."}},

		{key = "gravecage", slot = 24, minLevel = 1000, band = {1000, 1300}, faction = "vigil",
			name = {en = "The Gravecage", pt = "A Jaula das Covas"},
			story = {
				en = "In the Marrow Crypts, Ossivane keeps the dead in a cage of their own ribs, and the Vigil cannot burn "
					.. "what will not come out. Open the cage the hard way. Then tell Warden Ysolde, so the Vigil can light "
					.. "the pyres it has waited a century to light.",
				pt = "Nas Criptas de Medula, Ossivane guarda os mortos numa jaula feita das próprias costelas deles, e a "
					.. "Vigília não pode queimar o que não sai. Abra a jaula do jeito difícil. Depois conte à Warden Ysolde, para "
					.. "que a Vigília acenda as piras que espera acender há um século."},
			steps = {
				{kind = "kill", count = 1, monsters = {"Ossivane the Gravecage"},
					text = {en = "Defeat Ossivane the Gravecage in the Marrow Crypts",
						pt = "Derrote Ossivane the Gravecage nas Criptas de Medula"}},
				{kind = "talk", npc = YSOLDE,
					text = {en = "Tell Warden Ysolde in Cinderhold about the tale", pt = "Conte à Warden Ysolde, em Cinderhold, sobre a história"},
					reply = {en = "Open? Then ring every bell. Tonight the Vigil burns with a clean conscience.",
						pt = "Aberta? Então toquem todos os sinos. Esta noite a Vigília queima com a consciência limpa."}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.3, gold = 2200000, items = {{id = GRAFTING, count = 2, name = "Orb of Grafting"}}, rep = 1400,
				book = "deep_dungeons"},
			outro = {en = "The smoke from the pyres reached me here. It smelled, for once, like an ending.",
				pt = "A fumaça das piras chegou até aqui. Cheirava, desta vez, como um fim."}},

		{key = "kharzun_anvil", slot = 25, minLevel = 1300, band = {1300, 1600}, faction = "compact",
			name = {en = "Kharzun's Anvil", pt = "A Bigorna de Kharzun"},
			story = {
				en = "Forgewarden Kharzun was the Compact's finest smith until he forged himself into the Iron Crucible. "
					.. "His crystal servants still feed the fire. Break eighty of them, then the Forgewarden, and the Compact "
					.. "will stop pretending he retired.",
				pt = "O Forgewarden Kharzun era o melhor ferreiro do Pacto até forjar a si mesmo no Crisol de Ferro. Seus "
					.. "servos de cristal ainda alimentam o fogo. Quebre oitenta deles, depois o Forgewarden, e o Pacto vai "
					.. "parar de fingir que ele se aposentou."},
			steps = {
				{kind = "kill", count = 80, monsters = {"Facetis", "Thal", "Silicron", "Winterstride", "Gloamfang Ravager"},
					text = {en = "Break 80 of the Crucible's servants (Facetis, Thal, Silicron, Winterstride, Gloamfang Ravager)",
						pt = "Quebre 80 servos do Crisol (Facetis, Thal, Silicron, Winterstride, Gloamfang Ravager)"}},
				{kind = "kill", count = 1, monsters = {"Forgewarden Kharzun"},
					text = {en = "Defeat Forgewarden Kharzun in the Iron Crucible", pt = "Derrote Forgewarden Kharzun no Crisol de Ferro"}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.3, gold = 3000000, items = {{id = GRAFTING, count = 2, name = "Orb of Grafting"}}, rep = 1600},
			outro = {en = "His anvil rang once when he fell. The Compact heard it in Mirewake.",
				pt = "A bigorna dele soou uma vez quando ele caiu. O Pacto ouviu em Mirewake."}},

		{key = "fallen_seraph", slot = 26, minLevel = 1600, band = {1600, 2000}, faction = "choir", requires = "kharzun_anvil",
			name = {en = "The Fallen Seraph", pt = "A Serafim Caída"},
			story = {
				en = "Kharzun's last ledger names his buyer: Vaelith, who fell with the first Cinder and built the Fallen "
					.. "Sanctum from the wreck. Her court of antlers and skulls guards the way. Cut through it, end her, and "
					.. "tell Cantor Velith; the Choir has sung her name for an age and never knew her face.",
				pt = "O último registro de Kharzun nomeia seu comprador: Vaelith, que caiu com a primeira Brasa e ergueu o "
					.. "Santuário Caído dos destroços. Sua corte de galhadas e crânios guarda o caminho. Atravesse-a, acabe com "
					.. "ela e conte ao Cantor Velith; o Coro canta o nome dela há uma era e nunca conheceu seu rosto."},
			steps = {
				{kind = "kill", count = 80, monsters = {"Bloodantler Fiend", "Cinderskull Reaver", "Rimeshroud Revenant"},
					text = {en = "Cut through 80 of her court (Bloodantler Fiend, Cinderskull Reaver, Rimeshroud Revenant)",
						pt = "Atravesse 80 da corte dela (Bloodantler Fiend, Cinderskull Reaver, Rimeshroud Revenant)"}},
				{kind = "kill", count = 1, monsters = {"Vaelith the Fallen Seraph"},
					text = {en = "Defeat Vaelith the Fallen Seraph in the Fallen Sanctum",
						pt = "Derrote Vaelith the Fallen Seraph no Santuário Caído"}},
				{kind = "talk", npc = VELITH,
					text = {en = "Tell Cantor Velith in Bellwatch about the tale", pt = "Conte ao Cantor Velith, em Bellwatch, sobre a história"},
					reply = {en = "Her face. Describe it once, slowly, and then never again. The Choir will sing the rest.",
						pt = "O rosto dela. Descreva uma vez, devagar, e depois nunca mais. O Coro cantará o resto."}},
				{kind = "report", text = {en = "Return to the Archivist", pt = "Volte à Arquivista"}}
			},
			rewards = {xpLevels = 0.3, gold = 4000000, items = {{id = GRAFTING, count = 3, name = "Orb of Grafting"}}, rep = 1800},
			outro = {en = "She paid Kharzun in chains. I know now who wears them.",
				pt = "Ela pagou Kharzun em correntes. Agora sei quem as usa."}},

		{key = "chained_wyrm", slot = 27, minLevel = 2000, band = {2000, 2500}, faction = "vigil", requires = "fallen_seraph",
			name = {en = "The Chained Wyrm", pt = "A Wyrm Acorrentada"},
			story = {
				en = "Vaelith's chains hold Azhkarrath, mother of the pyrewings, to the Pyre Throne, and she burns everything "
					.. "that comes to free her or to end her. The Vigil says a thing chained that long has earned its pyre. "
					.. "Give her one. This is the last page I have kept blank.",
				pt = "As correntes de Vaelith prendem Azhkarrath, mãe dos pyrewings, ao Trono da Pira, e ela queima tudo o que "
					.. "vem libertá-la ou acabar com ela. A Vigília diz que algo acorrentado por tanto tempo mereceu sua pira. "
					.. "Dê uma a ela. Esta é a última página que guardei em branco."},
			steps = {
				{kind = "kill", count = 1, monsters = {"Azhkarrath the Chained Wyrm"},
					text = {en = "Defeat Azhkarrath the Chained Wyrm on the Pyre Throne",
						pt = "Derrote Azhkarrath the Chained Wyrm no Trono da Pira"}},
				{kind = "report", text = {en = "Fill the last page with the Archivist", pt = "Preencha a última página com a Arquivista"}}
			},
			rewards = {xpLevels = 0.25, gold = 5000000, items = {{id = GRAFTING, count = 3, name = "Orb of Grafting"}}, rep = 2000,
				book = "cinders"},
			outro = {en = "The ledger is full. I will need a new one. You will need new tales. We will both manage.",
				pt = "O registro está cheio. Vou precisar de um novo. Você vai precisar de novas histórias. Nós dois daremos um jeito."}}
	}
}
