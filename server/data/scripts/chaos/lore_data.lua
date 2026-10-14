-- Lore of the world, in English and Brazilian Portuguese (docs/CONTENT.md "Lore"). Pure data: no engine calls.
-- Read by the Codex and the wiki (tools/gen_codex_data.lua "Lore" tab, tools/gen_wiki_data.lua), by the Archivist
-- Maelis (data/npc/scripts/archivist_maelis.lua: ask her a keyword) and by the tales (tales_core.lua: the book each
-- tale gives). Each entry: id, kind (world, rift, omen, raid, worldboss, deep), name, keywords (lower case, both
-- languages, what the Archivist answers to), en and pt (paragraphs; together under 900 characters per language, so a
-- book holds them). Keep it short, dark and consistent with the names the systems use.
-- Lua 5.1 / LuaJIT and 5.3.
return {
	kinds = {
		{key = "world", en = "The world", pt = "O mundo"},
		{key = "rift", en = "Rifts", pt = "Fendas"},
		{key = "omen", en = "Omens", pt = "Presságios"},
		{key = "raid", en = "The Ashen Sepulchre", pt = "O Sepulcro Cinzento"},
		{key = "worldboss", en = "World bosses", pt = "Chefes do mundo"},
		{key = "deep", en = "The deep places", pt = "Os lugares profundos"}
	},
	entries = {
		-- ------------------------------------------------------------------ the world
		{id = "cinders", kind = "world", name = "The Fall of the Cinders",
			keywords = {"cinders", "fall", "world", "brasas", "queda", "mundo"},
			en = {"No one agrees on the night it happened. The sky split, and burning stones fell like slow rain for a season. "
				.. "Where they struck, the ground remembered fire: forests turned to ash, the dead stirred in their graves, and the "
				.. "first rifts opened like wounds that would not close.",
				"The Cinders still lie where they fell. Some are cold. Some still beat."},
			pt = {"Ninguém concorda sobre a noite em que aconteceu. O céu se partiu e pedras em chamas caíram como uma chuva lenta "
				.. "por uma estação inteira. Onde tocaram, a terra lembrou o fogo: florestas viraram cinza, os mortos se agitaram nos "
				.. "túmulos e as primeiras fendas se abriram como feridas que não fecham.",
				"As Brasas ainda estão onde caíram. Algumas esfriaram. Outras ainda pulsam."}},
		{id = "first_blood", kind = "world", name = "The Isle of First Blood",
			keywords = {"isle", "first blood", "ilha", "primeiro sangue"},
			en = {"Every newcomer wakes on the same small island, among statues no one remembers carving. The Vigil says the "
				.. "island was the first place a Cinder did not burn. Whatever the truth, nothing there can kill you, and nothing "
				.. "there will follow you out."},
			pt = {"Todo recém-chegado acorda na mesma pequena ilha, entre estátuas que ninguém lembra de ter esculpido. A "
				.. "Vigília diz que a ilha foi o primeiro lugar onde uma Brasa não queimou. Seja qual for a verdade, nada ali pode "
				.. "matar você, e nada dali o seguirá."}},
		{id = "archive", kind = "world", name = "The Archivist's Ledger",
			keywords = {"ledger", "archive", "archivist", "maelis", "registro", "arquivo", "arquivista"},
			en = {"Archivist Maelis keeps a ledger of every name the fire gave back: bosses, rifts, Omens, the things in the "
				.. "deep. She pays for true accounts and burns the false ones. Her ink is mixed with ash, so that what is written "
				.. "cannot be unwritten."},
			pt = {"A Arquivista Maelis mantém um registro de cada nome que o fogo devolveu: chefes, fendas, Presságios, as "
				.. "coisas das profundezas. Ela paga por relatos verdadeiros e queima os falsos. Sua tinta é misturada com cinza, "
				.. "para que o que foi escrito não possa ser apagado."}},

		-- ------------------------------------------------------------------ rifts
		{id = "rifts", kind = "rift", name = "The Rifts",
			keywords = {"rift", "rifts", "fenda", "fendas"},
			en = {"A rift is a place that fell with a Cinder and never finished landing. Step through with a key and you walk "
				.. "a piece of somewhere else, for as long as it holds. Each one has a guardian. Seal it, and the rift closes. "
				.. "Leave it open, and it remembers your face."},
			pt = {"Uma fenda é um lugar que caiu com uma Brasa e nunca terminou de pousar. Atravesse com uma chave e você "
				.. "caminha por um pedaço de outro lugar, enquanto ele durar. Cada uma tem um guardião. Sele-a e a fenda se fecha. "
				.. "Deixe-a aberta e ela lembrará do seu rosto."}},
		{id = "rift_abyssal", kind = "rift", name = "Abyssal Rift",
			keywords = {"abyssal", "abyss", "abissal", "abismo"},
			en = {"Floors of black glass over nothing at all. The Veiled Choir hears singing down there and answers it. What "
				.. "lives in the Abyssal Rift has too many eyes, and it has learned to close the ones you are looking at."},
			pt = {"Pisos de vidro negro sobre o nada. O Coro Velado ouve um canto lá embaixo e responde. O que vive na Fenda "
				.. "Abissal tem olhos demais, e aprendeu a fechar aqueles para os quais você olha."}},
		{id = "rift_obsidian", kind = "rift", name = "Obsidian Hall",
			keywords = {"obsidian", "hall", "obsidiana", "salao", "salão"},
			en = {"A hall of black marble that was never built by hands. Magma runs in its seams like veins. The Cinderforge "
				.. "Compact mines its walls between waves of the things that guard it, and calls the losses the price of good steel."},
			pt = {"Um salão de mármore negro que nunca foi construído por mãos. O magma corre em suas juntas como veias. O Pacto "
				.. "da Forja de Brasa minera suas paredes entre as ondas de guardiões, e chama as perdas de preço do bom aço."}},
		{id = "rift_ashen", kind = "rift", name = "Ashen Crypt",
			keywords = {"ashen crypt", "crypt", "cripta"},
			en = {"Graves that burned without being opened. The dead inside woke warm and angry. The Ashen Vigil rings its bells "
				.. "at every crypt that stirs, and sends wardens with oil and torches to finish what the fire started."},
			pt = {"Túmulos que queimaram sem serem abertos. Os mortos lá dentro acordaram quentes e furiosos. A Vigília Cinzenta "
				.. "toca seus sinos em cada cripta que se agita e envia guardiões com óleo e tochas para terminar o que o fogo começou."}},
		{id = "rift_sanctum", kind = "rift", name = "Forsaken Sanctum",
			keywords = {"sanctum", "forsaken", "santuario", "santuário"},
			en = {"A gilded temple swallowed by fungus. Its priests prayed for the fire to pass them by, and something answered "
				.. "with rot instead. The Thornbound Circle cuts the blight back every season. Every season it grows faster."},
			pt = {"Um templo dourado engolido por fungos. Seus sacerdotes rezaram para que o fogo passasse longe, e algo "
				.. "respondeu com podridão. O Círculo dos Espinhos corta a praga a cada estação. A cada estação ela cresce mais rápido."}},

		-- ------------------------------------------------------------------ Omens
		{id = "omens", kind = "omen", name = "The Omens",
			keywords = {"omen", "omens", "pressagio", "presságio", "pressagios", "presságios"},
			en = {"Some rifts do not hold a guardian. They hold a herald. The fragments they leave can be pressed into a key, "
				.. "and the key opens a door to the Omen itself: Sangrith of the Bloodmoon, Morvane the Hollow Crown, Thalcyra the "
				.. "Stormbound Seer. Each one foretells the same thing in a different voice."},
			pt = {"Algumas fendas não guardam um guardião. Guardam um arauto. Os fragmentos que deixam podem ser prensados em "
				.. "uma chave, e a chave abre a porta para o próprio Presságio: Sangrith da Lua de Sangue, Morvane a Coroa Oca, "
				.. "Thalcyra a Vidente da Tempestade. Cada um prevê a mesma coisa com uma voz diferente."}},
		{id = "omen_bloodmoon", kind = "omen", name = "Sangrith the Bloodmoon Herald",
			keywords = {"sangrith", "bloodmoon", "lua de sangue"},
			en = {"Sangrith walked out of the red night that followed the first fall, carrying a sickle of moonlight. He harvests "
				.. "what the fire missed. Those who fight him say the floor fills with blood before anyone is cut."},
			pt = {"Sangrith saiu da noite vermelha que seguiu a primeira queda, carregando uma foice de luar. Ele colhe o que o "
				.. "fogo deixou para trás. Quem o enfrenta diz que o chão se enche de sangue antes que alguém seja ferido."}},
		{id = "omen_hollow", kind = "omen", name = "Morvane the Hollow Crown",
			keywords = {"morvane", "hollow crown", "coroa oca"},
			en = {"Morvane was a queen once, of a kingdom that burned in one night. She kept the crown and lost the head beneath "
				.. "it. Her court of wraiths still bows to the empty throne, and they expect you to bow as well."},
			pt = {"Morvane foi rainha um dia, de um reino que queimou em uma única noite. Ela ficou com a coroa e perdeu a cabeça "
				.. "que a usava. Sua corte de espectros ainda se curva ao trono vazio, e espera que você se curve também."}},
		{id = "omen_storm", kind = "omen", name = "Thalcyra the Stormbound Seer",
			keywords = {"thalcyra", "storm", "seer", "tempestade", "vidente"},
			en = {"Thalcyra looked into the falling sky to read what came after, and the sky looked back. Now she is the storm "
				.. "she saw. Lightning finds the ground she marks a breath before it falls. Read the marks, or join her vision."},
			pt = {"Thalcyra olhou para o céu em queda para ler o que viria depois, e o céu olhou de volta. Agora ela é a "
				.. "tempestade que viu. O raio encontra o chão que ela marca um instante antes de cair. Leia as marcas, ou entre em sua visão."}},
		{id = "omen_ascended", kind = "omen", name = "The Ascended Omens and the Ember Gate",
			keywords = {"ascended", "ember gate", "ascendidos", "portao de brasa", "portão de brasa"},
			en = {"An Omen that is slain does not stay slain. Bind three shards of its herald into a sigil and it returns, "
				.. "Ascended, behind the Ember Gate. The fallen wait in the antechamber for the Gate to let them back. It always does, "
				.. "until it does not."},
			pt = {"Um Presságio abatido não continua abatido. Una três fragmentos do seu arauto em um sigilo e ele retorna, "
				.. "Ascendido, atrás do Portão de Brasa. Os caídos esperam na antecâmara até que o Portão os deixe voltar. Ele sempre "
				.. "deixa, até o dia em que não deixa."}},
		{id = "cinderheart", kind = "omen", name = "Ysgrath the Cinderheart",
			keywords = {"ysgrath", "cinderheart", "coracao de brasa", "coração de brasa"},
			en = {"Every Omen sings of one thing: the first Cinder, the one that never cooled. It has a name now, Ysgrath, and a "
				.. "heartbeat you can feel through the soles of your boots. It remembers the red night, the hollow court and the "
				.. "storm, because it made them. Only those who have ended all three may stand before it."},
			pt = {"Todo Presságio canta sobre uma só coisa: a primeira Brasa, a que nunca esfriou. Agora ela tem um nome, "
				.. "Ysgrath, e um batimento que se sente pela sola das botas. Ela lembra a noite vermelha, a corte oca e a "
				.. "tempestade, porque foi ela que os criou. Só quem encerrou os três pode ficar diante dela."}},

		-- ------------------------------------------------------------------ the Ashen Sepulchre
		{id = "sepulchre", kind = "raid", name = "The Ashen Sepulchre",
			keywords = {"sepulchre", "varkhul", "sovereign", "sepulcro", "soberano"},
			en = {"The Sepulchre was not built to honour a king. It was built to hold one. Varkhul, the Ashen Sovereign, ruled "
				.. "until the fire made him something that would not die, and his own wardens walled him in with everything that "
				.. "served him. Gravewarden Ulthar still keeps the first gate. Morwen the Ash-Sister still sings. The last door opens "
				.. "from the inside."},
			pt = {"O Sepulcro não foi construído para honrar um rei. Foi construído para prendê-lo. Varkhul, o Soberano "
				.. "Cinzento, reinou até que o fogo o transformou em algo que não morre, e seus próprios guardiões o emparedaram "
				.. "com tudo o que o servia. O Guardião de Túmulos Ulthar ainda vigia o primeiro portão. Morwen, a Irmã das Cinzas, "
				.. "ainda canta. A última porta se abre por dentro."}},

		-- ------------------------------------------------------------------ world bosses
		{id = "wb_kaelgor", kind = "worldboss", name = "Kaelgor the Infernal Warlord",
			keywords = {"kaelgor", "warlord", "senhor da guerra"},
			en = {"Kaelgor led the first army through a burning rift and found nothing on the other side worth conquering, so "
				.. "he conquers ours, again and again. His banner is a sheet of flame. His soldiers are whoever he killed last time."},
			pt = {"Kaelgor liderou o primeiro exército através de uma fenda em chamas e não encontrou do outro lado nada que "
				.. "valesse conquistar; então conquista o nosso, de novo e de novo. Seu estandarte é uma cortina de fogo. Seus "
				.. "soldados são quem ele matou da última vez."}},
		{id = "wb_skaldra", kind = "worldboss", name = "Skaldra the Rime Queen",
			keywords = {"skaldra", "rime", "geada", "rainha"},
			en = {"Where a Cinder fell into the northern ice, the ice did not melt. It woke. Skaldra wears the cold like a gown "
				.. "and freezes the sky wherever she descends. She hates the fire more than any of us. That does not make her a friend."},
			pt = {"Onde uma Brasa caiu no gelo do norte, o gelo não derreteu. Ele despertou. Skaldra veste o frio como um "
				.. "vestido e congela o céu onde quer que desça. Ela odeia o fogo mais do que qualquer um de nós. Isso não a torna uma aliada."}},
		{id = "wb_rotmother", kind = "worldboss", name = "The Rotmother",
			keywords = {"rotmother", "rot", "mae podre", "mãe podre", "podridao", "podridão"},
			en = {"The plague pits were dug for the dead of the first fall. Something kept feeding on them after the digging "
				.. "stopped, and grew, and gave birth. The Thornbound Circle burns its brood on sight and still cannot find the pit "
				.. "it crawls out of."},
			pt = {"As covas da peste foram cavadas para os mortos da primeira queda. Algo continuou se alimentando deles depois "
				.. "que pararam de cavar, e cresceu, e deu à luz. O Círculo dos Espinhos queima sua ninhada assim que a vê e ainda "
				.. "não encontrou a cova de onde ela rasteja."}},
		{id = "wb_nyxareth", kind = "worldboss", name = "Nyxareth the Void Archon",
			keywords = {"nyxareth", "void", "archon", "vazio", "arconte"},
			en = {"The Veiled Choir sang to the void for a hundred nights. On the hundred and first, the void sang back, and "
				.. "Nyxareth stepped out of the tear. The Choir calls it a misunderstanding. The Vigil calls it a debt."},
			pt = {"O Coro Velado cantou para o vazio por cem noites. Na centésima primeira, o vazio cantou de volta, e Nyxareth "
				.. "saiu do rasgo. O Coro chama isso de mal-entendido. A Vigília chama de dívida."}},
		{id = "wb_vharok", kind = "worldboss", name = "Vharok the Blood Colossus",
			keywords = {"vharok", "colossus", "colosso", "sangue"},
			en = {"Vharok is what a battlefield becomes when no one buries the fallen. Every war since the first fall added to "
				.. "him. When the earth trembles, he is counting the new dead."},
			pt = {"Vharok é o que um campo de batalha se torna quando ninguém enterra os caídos. Cada guerra desde a primeira "
				.. "queda aumentou seu corpo. Quando a terra treme, ele está contando os novos mortos."}},

		-- ------------------------------------------------------------------ the deep places (generated areas, the Descent)
		{id = "descent", kind = "deep", name = "The Ember Descent",
			keywords = {"descent", "ember descent", "descida"},
			en = {"Under every town there is a stair that was not there before the fall. It goes down further each time someone "
				.. "walks it. The rooms change. The heat does not. No one has found the bottom, and those who claim to have found it "
				.. "do not go back."},
			pt = {"Sob cada cidade há uma escada que não existia antes da queda. Ela desce mais a cada vez que alguém a percorre. "
				.. "As salas mudam. O calor não. Ninguém encontrou o fundo, e quem diz ter encontrado não volta lá."}},
		{id = "deep_wardens", kind = "deep", name = "The Wardens of the Deep",
			keywords = {"emberdeep", "ossuary", "cinderwing", "ossrim", "vault", "maw", "warden", "guardiao", "guardião", "profundezas"},
			en = {"Past the reach of any map lie places the fire hollowed out on its own: the Emberdeep Hollows, the Sunken "
				.. "Ossuary, the Cinderfall Wastes, the Hollow Vault. Each has a keeper grown fat on Cinder heat: the Emberdeep Maw, "
				.. "the Ossuary Warden, Cinderwing, and Vault Keeper Ossrim, who still counts coins no one will spend."},
			pt = {"Além do alcance de qualquer mapa ficam lugares que o fogo escavou sozinho: Emberdeep Hollows, Sunken Ossuary, "
				.. "Cinderfall Wastes e The Hollow Vault. Cada um tem um guardião engordado pelo calor das Brasas: The Emberdeep Maw, "
				.. "The Ossuary Warden, Cinderwing e Vault Keeper Ossrim, que ainda conta moedas que ninguém vai gastar."}}
	}
}
