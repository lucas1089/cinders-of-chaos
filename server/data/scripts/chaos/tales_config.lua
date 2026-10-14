-- The tales: short quests with a story for the level bands that had none (docs/CONTENT.md "Tales"). Logic:
-- tales_core.lua (pure, tests/tales_test.lua); engine: tales.lua (kill credit, the modal windows, rewards, the NPC);
-- the NPC: Archivist Maelis (data/npc/Archivist Maelis.xml, data/npc/scripts/archivist_maelis.lua).
-- Every text is in English (en) and Brazilian Portuguese (pt). A character reads pt when Chaos.lang(player) says "pt"
-- (the localization work's hook, when it exists) or after telling the Archivist "portugues"; "english" switches back.
-- Lua 5.1 / LuaJIT and 5.3.
local UPHEAVAL, FATE, GRAFTING, SHARD = 29856, 29857, 29855, 32051

return {
	enabled = true,

	-- player storages: block 7101500-7101549 (server/README.md "Storage keys"). +0 language (1 en, 2 pt), quest slot s:
	-- base + 1 + s = state (0 or -1 not taken, 1..n the step in progress, 100 done), base + 21 + s = the step's count
	storage = {base = 7101500, lang = 0, state = 1, count = 21, last = 7101549},
	done = 100,

	-- modal windows (answered in tales.lua): the list of tales, one tale
	modal = {list = 7170, tale = 7171},

	-- the NPC, placed next to the temples at startup like the Ascendant Oracle (a ring further out)
	npc = {
		name = "Archivist Maelis",
		spawn = true,
		townIds = {1},
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

	-- the tales. slot: the storage slot (never reuse one). minLevel: who may take it. steps: kill (any of `monsters`
	-- by type or shown name, `count` of them), deliver (items handed over at the Archivist), report (talk). rewards:
	-- xpLevels (that share of the experience of the character's next level), gold (to the bank), items, faction
	-- reputation, the lore book (lore_data.lua id).
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
				pt = "Ysgrath. Diga uma vez, e nunca perto do fogo."}}
	}
}
