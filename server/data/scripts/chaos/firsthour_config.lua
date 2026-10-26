-- The first hours (firsthour.lua, firsthour_core.lua; docs/CONTENT.md "First hour"): one-time hints at the levels where
-- a new character used to be left without a next step, in English and Brazilian Portuguese, and the hunting grounds of
-- its level nearest its temple put on its map (the hidden hunting marks of poi.lua, revealed as if it had walked there).
-- Lua 5.1 / LuaJIT and 5.3.
return {
	enabled = true,

	-- player storages: block 7101550-7101559 (server/README.md "Storage keys"): +0 the hints given (bits, by index),
	-- +1 the reveals done (bits, by index of revealAt), +2 how many hints the character knows of, +3 how many reveals
	-- (a hint or reveal added later at a level the character already passed is marked given, silently)
	storage = {base = 7101550, hints = 0, reveals = 1, hintsKnown = 2, revealsKnown = 3, last = 7101559},
	-- what a character without +2 / +3 knew of: the lists before the levels above 100 were added (2026-10-15)
	legacy = {hints = 8, reveals = 6},

	-- a character first seen above this level (it played before this module) gets every hint marked as given, silently
	quietAbove = 20,

	-- the hunting marks revealed at these levels: up to `count` hunts whose band starts at most `slack` levels above
	-- the character and ends at or above it, nearest the temple of its town (same floor counts 1, each floor apart
	-- adds `floorCost` squares), within `range` squares
	-- NEVER reorder or insert: the bits are by index; add new levels at the end (up to 31)
	revealAt = {1, 8, 20, 35, 50, 80, 120, 160, 200, 300, 400, 500, 700, 800, 1000, 1150, 1300, 1500, 1750},
	reveal = {count = 3, slack = 5, range = 700, floorCost = 40},
	-- the content hunts of the teleport room of Cinderhold (hunt_teleports_config.lua, levels from goals_config.lua
	-- hunts) are named with the hunts near the temple: up to `count` whose band starts at most `slack` above the level
	plans = {count = 3, slack = 40},

	-- staggering (O240): one hint per run, the next after gapMs while hints are still due. A character starts at level 8
	-- with three hints due; they used to come at once, beside the welcome and the Helper
	pace = {perRun = 1, gapMs = 75000},

	-- the toast and the message after the welcome (newplayer.lua shows it 2.5 s after the kit)
	delayMs = 9000,

	-- %s in a hint: the names of the hunts just revealed ("" when none). NEVER reorder or insert: the bits are by index;
	-- add new hints at the end (up to 31)
	hints = {
		{key = "start", level = 1,
			en = "First hunts: %s. They are on your map now. Monsters drop gear with a rarity; your kit carries you to level 20. "
				.. "In Cinderhold, the main city, the two great teleports north of the temple lead to the teleport room: a portal to a hunt of every level.",
			pt = "Primeiras caçadas: %s. Elas estão no seu mapa agora. Monstros soltam equipamentos com raridade; seu kit leva você até o nível 20. "
				.. "Em Cinderhold, a cidade principal, os dois grandes teleportes ao norte do templo levam à sala de teleportes: um portal para uma caçada de cada nível."},
		{key = "gear", level = 4,
			en = "Better gear: the shops in town sell weapons and armour for gold, and the Loot Buyer in the teleport room's market buys what you find. "
				.. "Economy > Item Finder tells where any item drops or who sells it.",
			pt = "Equipamento melhor: as lojas da cidade vendem armas e armaduras por ouro, e o Comprador de Saque no mercado "
				.. "da sala de teleportes compra o que você encontrar. Economy > Item Finder mostra onde cada item cai ou quem o vende."},
		{key = "bounty", level = 8,
			en = "The Bounty Board is open to you (Adventure > Bounty Board): daily contracts at your level for gold and orbs. "
				.. "Archivist Maelis, in the teleport room's market, has her first tale for you: ask her for \"tales\". New hunts: %s.",
			pt = "O Bounty Board está aberto (Adventure > Bounty Board): contratos diários do seu nível por ouro e orbes. "
				.. "A Arquivista Maelis, no mercado da sala de teleportes, tem a primeira história para você: peça \"histórias\". Novas caçadas: %s."},
		{key = "passive", level = 12,
			en = "Your first passive point: Character > Passive Tree. Start next to the centre and press Apply Plan.",
			pt = "Seu primeiro ponto passivo: Personagem > Árvore Passiva. Comece perto do centro e clique em Aplicar Plano."},
		{key = "twenty", level = 20,
			en = "Level 20: a milestone gift is in your backpack. Hunts for your level: %s. The Bestiary (Hunt > Bestiary) shows where every creature lives.",
			pt = "Nível 20: um presente de marco está na sua mochila. Caçadas do seu nível: %s. O Bestiário (Hunt > Bestiário) mostra onde cada criatura vive."},
		{key = "invasion", level = 30,
			en = "From now on you can defend the towns in invasions and earn their rewards. Party Finder (Social) helps you find a group.",
			pt = "A partir de agora você pode defender as cidades nas invasões e ganhar as recompensas. O Party Finder (Social) ajuda a achar um grupo."},
		{key = "arena", level = 50,
			en = "The Arena is open from level 50. Hunts for your level: %s.",
			pt = "A Arena abre a partir do nível 50. Caçadas do seu nível: %s."},
		{key = "ascension", level = 100,
			en = "Level 100: the Ascendant Oracle in the teleport room's market starts your ascension, and rifts, the Ember Descent and the Vocation Trials "
				.. "are open. Archivist Maelis has a new tale at almost every level.",
			pt = "Nível 100: o Oráculo Ascendente no mercado da sala de teleportes começa sua ascensão, e as fendas, a Descida de Brasa e as Provas de Vocação "
				.. "estão abertas. A Arquivista Maelis tem uma história nova em quase todo nível."},
		-- from here on: every band where the next system unlocks (2026-10-15); Adventure > Next Goals lists the goals
		{key = "goals", level = 120,
			en = "Lost? Adventure > Next Goals shows what to do at your level, why, where, and the gear path of your band. "
				.. "Hunts for your level: %s.",
			pt = "Perdido? Adventure > Próximos objetivos mostra o que fazer no seu nível, por quê, onde, e o caminho de equipamento "
				.. "da sua faixa. Caçadas do seu nível: %s."},
		{key = "pocket", level = 150,
			en = "Level 150: pocket bosses open in the Boss Spawns window (Adventure menu): a private copy of a boss with daily charges. "
				.. "Guild bosses and the Scorched Marches are open too.",
			pt = "Nível 150: os chefes de bolso abrem na janela Boss Spawns (menu Adventure): uma cópia privada de um chefe com cargas "
				.. "diárias. Chefes de guilda e as Scorched Marches também estão abertos."},
		{key = "teleports", level = 200,
			en = "Level 200: the hunt teleports of Cinderhold open: %s. Archivist Maelis has tales for this band too.",
			pt = "Nível 200: os teleportes de caça de Cinderhold se abrem: %s. A Arquivista Maelis tem histórias para esta faixa também."},
		{key = "cruel", level = 250,
			en = "Level 250: the Cruel Vocation Trial and the island pocket bosses. Conquest Tokens from every boss buy the uniques "
				.. "you have seen.",
			pt = "Nível 250: a Prova de Vocação Cruel e os chefes de bolso das ilhas. Os Conquest Tokens de cada chefe compram os "
				.. "únicos que você já viu."},
		{key = "worldboss", level = 300,
			en = "Level 300: world bosses every 6 hours, portals by the temples. The first kill of each major boss gives a passive "
				.. "point. Hunts for your level: %s.",
			pt = "Nível 300: chefes mundiais a cada 6 horas, portais perto dos templos. A primeira morte de cada grande chefe dá um "
				.. "ponto passivo. Caçadas do seu nível: %s."},
		{key = "merciless", level = 400,
			en = "Level 400: the Merciless Vocation Trial; clear the Ember Descent and use your first Orb of Grafting.",
			pt = "Nível 400: a Prova de Vocação Impiedosa; conclua a Ember Descent e use seu primeiro Orb of Grafting."},
		{key = "hardened", level = 500,
			en = "Level 500: new hunts in the teleport room: %s. Faction gear waits at Revered.",
			pt = "Nível 500: novas caçadas na sala de teleportes: %s. O equipamento de facção espera em Reverenciado."},
		{key = "seven", level = 700,
			en = "Level 700: hunts for your level: %s. Seal tier 8 rifts: at 800 the Omen guardians wake.",
			pt = "Nível 700: caçadas do seu nível: %s. Sele fendas de nível 8: no 800 os guardiões Omen despertam."},
		{key = "raid", level = 800,
			en = "Level 800: the Ashen Sepulchre raid, the Omen guardians and The Hollow Vault are open. Hunts: %s.",
			pt = "Nível 800: a raide do Ashen Sepulchre, os guardiões Omen e o Hollow Vault estão abertos. Caçadas: %s."},
		{key = "ascendedomens", level = 900,
			en = "Level 900: the Ascended Omens wake; they alone drop the Ascended uniques.",
			pt = "Nível 900: os Ascended Omens despertam; só eles soltam os únicos ascendidos."},
		{key = "cinderheart", level = 1000,
			en = "Level 1000: the Cinderheart and The Marrow Crypts. From level 1001 every level is a Paragon point. Hunts: %s.",
			pt = "Nível 1000: o Cinderheart e as Marrow Crypts. A partir do nível 1001 cada nível é um ponto Paragon. "
				.. "Caçadas: %s."},
		{key = "crucible", level = 1300,
			en = "Level 1300: The Iron Crucible is open. Hunts for your level: %s.",
			pt = "Nível 1300: o Iron Crucible está aberto. Caçadas do seu nível: %s."},
		{key = "sanctum", level = 1600,
			en = "Level 1600: The Fallen Sanctum is open. Hunts for your level: %s.",
			pt = "Nível 1600: o Fallen Sanctum está aberto. Caçadas do seu nível: %s."},
		{key = "throne", level = 2000,
			en = "Level 2000: The Pyre Throne, the last dungeon, is open. Its best chest is at difficulty 6.",
			pt = "Nível 2000: o Pyre Throne, a última masmorra, está aberto. O melhor baú é na dificuldade 6."},
		-- O240: the first levels had no next step between the bounty (8) and the passive point (12), and no new spell
		-- between level 8 and 25. These two sit at lower levels than the entries before them (the bits are by index);
		-- dueHints orders by level
		{key = "upgrade", level = 10,
			en = "Time for a weapon upgrade: the town shops sell a stronger weapon for your class, and the Loot Buyer pays for "
				.. "what you found. Economy > Item Finder shows who sells any item. Hunts for your level: %s.",
			pt = "Hora de melhorar a arma: as lojas da cidade vendem uma arma mais forte para a sua classe, e o Comprador de "
				.. "Saque paga pelo que você achou. Economy > Item Finder mostra quem vende cada item. Caçadas do seu nível: %s."},
		{key = "nextspells", level = 16,
			en = "Your class learns new spells around levels 12-14 and 20, and more at levels 25, 30 and 35: Character > Spellbook lists every spell with its level. Meanwhile, "
				.. "spend the passive points (levels 12, 16 and 20) and take a bounty: Adventure > Next Goals shows the next step.",
			pt = "Sua classe aprende novas magias por volta dos níveis 12-14 e 20, e mais nos níveis 25, 30 e 35: Personagem > Spellbook lista cada magia com o seu nível. "
				.. "Enquanto isso, gaste os pontos passivos (níveis 12, 16 e 20) e aceite uma recompensa: Adventure > Próximos objetivos mostra o próximo passo."}
	},

	none = {en = "none near your temple yet, ask the Bestiary", pt = "nenhuma perto do seu templo ainda, consulte o Bestiário"}
}
