-- The first hours (firsthour.lua, firsthour_core.lua; docs/CONTENT.md "First hour"): one-time hints at the levels where
-- a new character used to be left without a next step, in English and Brazilian Portuguese, and the hunting grounds of
-- its level nearest its temple put on its map (the hidden hunting marks of poi.lua, revealed as if it had walked there).
-- Lua 5.1 / LuaJIT and 5.3.
return {
	enabled = true,

	-- player storages: block 7101550-7101559 (server/README.md "Storage keys"): +0 the hints given (bits, by index),
	-- +1 the reveals done (bits, by index of revealAt)
	storage = {base = 7101550, hints = 0, reveals = 1, last = 7101559},

	-- a character first seen above this level (it played before this module) gets every hint marked as given, silently
	quietAbove = 20,

	-- the hunting marks revealed at these levels: up to `count` hunts whose band starts at most `slack` levels above
	-- the character and ends at or above it, nearest the temple of its town (same floor counts 1, each floor apart
	-- adds `floorCost` squares), within `range` squares
	revealAt = {1, 8, 20, 35, 50, 80},
	reveal = {count = 3, slack = 5, range = 700, floorCost = 40},

	-- the toast and the message after the welcome (newplayer.lua shows it 2.5 s after the kit)
	delayMs = 9000,

	-- %s in a hint: the names of the hunts just revealed ("" when none)
	hints = {
		{key = "start", level = 1,
			en = "First hunts: %s. They are on your map now. Monsters drop gear with a rarity; your kit carries you to level 20.",
			pt = "Primeiras caçadas: %s. Elas estão no seu mapa agora. Monstros soltam equipamentos com raridade; seu kit leva você até o nível 20."},
		{key = "gear", level = 4,
			en = "Better gear: the shops in town sell weapons and armour for gold, and the Loot Buyer by the temple buys what you find. "
				.. "Economy > Item Finder tells where any item drops or who sells it.",
			pt = "Equipamento melhor: as lojas da cidade vendem armas e armaduras por ouro, e o Comprador de Saque perto do templo compra "
				.. "o que você encontrar. Economia > Localizador de Itens mostra onde cada item cai ou quem o vende."},
		{key = "bounty", level = 8,
			en = "The Bounty Board is open to you (Adventure > Bounty Board): daily contracts at your level for gold and orbs. New hunts: %s.",
			pt = "O Quadro de Recompensas está aberto (Aventura > Quadro de Recompensas): contratos diários do seu nível por ouro e orbes. "
				.. "Novas caçadas: %s."},
		{key = "passive", level = 12,
			en = "Your first passive point: Character > Passive Tree. Start next to the centre and press Apply Plan.",
			pt = "Seu primeiro ponto passivo: Personagem > Árvore Passiva. Comece perto do centro e clique em Aplicar Plano."},
		{key = "twenty", level = 20,
			en = "Level 20: a milestone gift is in your backpack. Hunts for your level: %s. The Bestiary (Hunt > Bestiary) shows where every creature lives.",
			pt = "Nível 20: um presente de marco está na sua mochila. Caçadas do seu nível: %s. O Bestiário (Caça > Bestiário) mostra onde cada criatura vive."},
		{key = "invasion", level = 30,
			en = "From now on you can defend the towns in invasions and earn their rewards. Party Finder (Social) helps you find a group.",
			pt = "A partir de agora você pode defender as cidades nas invasões e ganhar as recompensas. O Localizador de Grupo (Social) ajuda a achar um grupo."},
		{key = "arena", level = 50,
			en = "The Arena is open from level 50. Hunts for your level: %s.",
			pt = "A Arena abre a partir do nível 50. Caçadas do seu nível: %s."},
		{key = "ascension", level = 100,
			en = "Level 100: the Ascendant Oracle in the temple starts your ascension, and rifts, the Ember Descent and the Vocation Trials "
				.. "are open. Archivist Maelis pays for tales from level 200.",
			pt = "Nível 100: o Oráculo Ascendente no templo começa sua ascensão, e as fendas, a Descida de Brasa e as Provas de Vocação "
				.. "estão abertas. A Arquivista Maelis paga por histórias a partir do nível 200."}
	},

	none = {en = "none near your temple yet, ask the Bestiary", pt = "nenhuma perto do seu templo ainda, consulte o Bestiário"}
}
