-- The Ashen Chronicle (Crônica das Cinzas): the story text of every season arc, in English (en) and Brazilian
-- Portuguese (pt). Pure data plus two pure helpers, no engine API: chronicle.lua, the client payload, the Codex and the
-- wiki generators (server/tools/gen_codex_data.lua, gen_wiki_data.lua) and NPC scripts (their own Lua state, with
-- dofile) all read this file. The numbers of each chapter (goals, world changes) are in chronicle_config.lua under the
-- same chapter keys. Overview: server/README.md "The Ashen Chronicle".
--
-- Lore notes (consistent with the README's Chronicle of the Broken World quotes and with lore_data.lua, which the lore
-- writers keep: read, not edited): the Cinders fell and still burn; Rift Keys open the rifts; the Omens (Sangrith,
-- Morvane, Thalcyra) wait behind Omen Keys and their Ascended forms behind Sigils; Ysgrath the Cinderheart is the first
-- Cinder, the one that never cooled; the Ashen Sepulchre (Varkhul the Ashen Sovereign and his wardens) lies under the
-- capital; the Five (Kaelgor, Skaldra, the Rotmother, Nyxareth, Vharok) come through the temple portals; the Great
-- Brazier burns in the main temple; the Chronicler who keeps the book is Archivist Maelis (lore_data.lua "The
-- Archivist's Ledger": her ink is mixed with ash; one name, decided 2026-10-14; Portuguese "a Cronista"). Portuguese
-- names follow lore_data.lua (fendas, Presságios, Sepulcro Cinzento, Coração de Brasa, Mãe Podre, guardiões da Vigília);
-- place names stay in English. Approved 2026-10-14 (owner delegated): docs/OWNER_TODO.md "Decided".
--
-- Shape: arcs[arcKey] = {title, intro, ending, chapters = {{key, title, text = {en = {...}, pt = {...}}, done, world,
-- npc}}}; every text field is {en = ..., pt = ...}. No em dashes, plain sentences. Lua 5.1 / LuaJIT and Lua 5.3.

local T = {}

T.arcs = {
	s1 = {
		title = {en = "The Ashen Chronicle: Season of Ash", pt = "A Crônica das Cinzas: Temporada das Cinzas"},
		intro = {
			en = "The ash has always fallen on the broken world. This season it falls heavier and warmer, and Archivist Maelis, " ..
				"the Chronicler, has opened a new book. What the whole realm does together is written in it, and the world answers.",
			pt = "As cinzas sempre caíram sobre o mundo partido. Nesta temporada elas caem mais grossas e mais quentes, e a " ..
				"Arquivista Maelis, a Cronista, abriu um livro novo. O que o reino inteiro fizer junto será escrito nele, e o " ..
				"mundo vai responder."
		},
		ending = {
			en = "The book of the Season of Ash is closed. The Chronicler has written the names of those who carried each " ..
				"chapter in ink mixed with ash, and for a while the ash falls softly.",
			pt = "O livro da Temporada das Cinzas está fechado. A Cronista escreveu, com tinta misturada à cinza, os nomes de " ..
				"quem carregou cada capítulo, e por um tempo as cinzas caem devagar."
		},
		chapters = {
			{
				key = "ash_thickens",
				title = {en = "I. The Ash Thickens", pt = "I. As Cinzas se Adensam"},
				text = {
					en = {
						"The ash falls warm to the touch now, and in the capital's streets the wind no longer carries it away. " ..
							"Beyond the walls the small rifts open faster than the Vigil's wardens can count them.",
						"The Chronicler has written one line on the first page: \"The world remembers what it does.\" Turn the keys. " ..
							"Seal the small wounds before they learn to grow, and let the new hunters find their strength."
					},
					pt = {
						"Agora as cinzas caem mornas, e nas ruas da capital o vento já não as leva embora. Além das muralhas, as " ..
							"fendas pequenas se abrem mais rápido do que os guardiões da Vigília conseguem contar.",
						"A Cronista escreveu uma única linha na primeira página: \"O mundo se lembra do que faz.\" Girem as chaves. " ..
							"Selem as feridas pequenas antes que aprendam a crescer, e deixem que os novos caçadores descubram a " ..
							"própria força."
					}
				},
				done = {
					en = "The first chapter of the Ashen Chronicle is written: the small wounds are sealed, but the ash has settled " ..
						"on the capital and will not lift.",
					pt = "O primeiro capítulo da Crônica das Cinzas está escrito: as feridas pequenas foram seladas, mas as cinzas " ..
						"assentaram sobre a capital e não vão mais sair."
				},
				world = {
					en = "Ash drifts and scorched cracks now mark the ground around the capital's temple.",
					pt = "Montes de cinza e rachaduras queimadas agora marcam o chão em volta do templo da capital."
				},
				npc = {
					en = "The ash will not lift from our streets. The first chapter is written; the next asks more of you.",
					pt = "As cinzas não saem das nossas ruas. O primeiro capítulo está escrito; o próximo vai pedir mais de vocês."
				}
			},
			{
				key = "wound_walls",
				title = {en = "II. The Wound Beside the Walls", pt = "II. A Ferida ao Lado das Muralhas"},
				text = {
					en = {
						"Where the Five last fell, the ground did not close. A seam of cinders runs beside the capital's walls, and " ..
							"Kaelgor, Skaldra, the Rotmother, Nyxareth and Vharok come back through the temple portals angrier each time.",
						"Break them, again and again. Seal the deeper rifts that feed the seam. When it is quiet enough to walk into, " ..
							"the wardens will open the way."
					},
					pt = {
						"Onde os Cinco caíram pela última vez, o chão não se fechou. Um veio de brasas corre ao lado das muralhas " ..
							"da capital, e Kaelgor, Skaldra, a Mãe Podre, Nyxareth e Vharok voltam pelos portais dos templos cada " ..
							"vez mais furiosos.",
						"Derrubem-nos quantas vezes for preciso. Selem as fendas mais fundas que alimentam o veio. Quando ele " ..
							"estiver calmo o bastante para alguém entrar, os guardiões vão abrir o caminho."
					}
				},
				done = {
					en = "The second chapter is written: the Cinderscar Breach lies open, and the ground the Five tore apart is now " ..
						"a hunting ground for the living.",
					pt = "O segundo capítulo está escrito: a Cinderscar Breach está aberta, e o chão que os Cinco rasgaram agora é " ..
						"terreno de caça para os vivos."
				},
				world = {
					en = "The Cinderscar Breach is open: its gate stands by the capital's temple. Rubble from the Five's last " ..
						"assault lies near the temple.",
					pt = "A Cinderscar Breach está aberta: o portão fica junto ao templo da capital. Escombros do último ataque " ..
						"dos Cinco estão perto do templo."
				},
				npc = {
					en = "The wardens opened the Breach. Hunt there, but do not stare into the seam for long.",
					pt = "Os guardiões abriram a Breach. Cacem lá, mas não fiquem olhando para o veio por muito tempo."
				}
			},
			{
				key = "omens_ashfall",
				title = {en = "III. Omens in the Ashfall", pt = "III. Presságios na Chuva de Cinzas"},
				text = {
					en = {
						"Sangrith's blood moon has been seen over the rifts, Morvane's hollow crown in the ash clouds, Thalcyra's storm " ..
							"in the deepest tiers. The Omens are no longer waiting behind their keys.",
						"Press the fragments into keys, walk into their arenas and put them down before what they foretell " ..
							"arrives. Light the ward-fires when they fall."
					},
					pt = {
						"A lua de sangue de Sangrith foi vista sobre as fendas, a coroa oca de Morvane nas nuvens de cinza, a " ..
							"tempestade de Thalcyra nos níveis mais profundos. Os Presságios já não esperam atrás das suas chaves.",
						"Prensem os fragmentos em chaves, entrem nas arenas deles e derrubem-nos antes que chegue o que eles " ..
							"anunciam. Acendam as fogueiras de guarda quando eles caírem."
					}
				},
				done = {
					en = "The third chapter is written: the Omens have been answered, and ward-fires burn around the capital's temple.",
					pt = "O terceiro capítulo está escrito: os Presságios foram respondidos, e fogueiras de guarda queimam em " ..
						"volta do templo da capital."
				},
				world = {
					en = "Ward-fires burn around the capital's temple.",
					pt = "Fogueiras de guarda queimam em volta do templo da capital."
				},
				npc = {
					en = "The ward-fires hold the Omens' signs away from the city. Something below it is still awake.",
					pt = "As fogueiras de guarda mantêm os sinais dos Presságios longe da cidade. Algo embaixo dela ainda está acordado."
				}
			},
			{
				key = "sepulchre_stirs",
				title = {en = "IV. The Sepulchre Stirs", pt = "IV. O Sepulcro Desperta"},
				text = {
					en = {
						"Beneath the capital, the Ashen Sepulchre breathes. What was walled in with Varkhul no longer sleeps between " ..
							"one raid and the next; at night its bones knock against a sealed stair under the city.",
						"Clear the Sepulchre, face the Ascended forms of the Omens, and the stair the old wardens walled up will be " ..
							"ours to walk."
					},
					pt = {
						"Embaixo da capital, o Sepulcro Cinzento respira. O que foi emparedado junto com Varkhul já não dorme " ..
							"entre uma incursão e outra; de noite, seus ossos batem contra uma escada selada sob a cidade.",
						"Limpem o Sepulcro, enfrentem as formas Ascendidas dos Presságios, e a escada que os antigos guardiões " ..
							"muraram será nossa para descer."
					}
				},
				done = {
					en = "The fourth chapter is written: the old wardens' wall has come down, and the Ossuary Stair is open.",
					pt = "O quarto capítulo está escrito: o muro dos antigos guardiões caiu, e a Ossuary Stair está aberta."
				},
				world = {
					en = "The Ossuary Stair below the capital is open: its gate stands by the capital's temple.",
					pt = "A Ossuary Stair, embaixo da capital, está aberta: o portão fica junto ao templo da capital."
				},
				npc = {
					en = "The Stair is open. Whatever the old wardens walled in down there, it is ours to face now.",
					pt = "A Escada está aberta. O que os antigos guardiões emparedaram lá embaixo agora é nosso para enfrentar."
				}
			},
			{
				key = "embers_rekindled",
				title = {en = "V. Embers Rekindled", pt = "V. Brasas Reacesas"},
				text = {
					en = {
						"Ysgrath the Cinderheart is the first Cinder, the one that never cooled, and while it beats the ash will never " ..
							"stop. Bind its sigil from the relics of the Ascended, gather the strong, and hold the towns when the " ..
							"invaders come.",
						"When the Cinderheart falls, carry what is left of its flame back to the Great Brazier. Let the capital " ..
							"remember that it was rebuilt, not spared."
					},
					pt = {
						"Ysgrath, o Coração de Brasa, é a primeira Brasa, a que nunca esfriou, e enquanto ela pulsar as cinzas não " ..
							"vão parar de cair. Unam o seu sigilo com as relíquias dos Ascendidos, reúnam os fortes e defendam as " ..
							"cidades quando os invasores vierem.",
						"Quando o Coração de Brasa cair, levem o que restar da sua chama de volta ao Grande Braseiro. Que a capital " ..
							"se lembre de que foi reconstruída, e não poupada."
					}
				},
				done = {
					en = "The last chapter is written: the Cinderheart is broken, the ash lifts, and the capital rebuilds.",
					pt = "O último capítulo está escrito: o Coração de Brasa foi partido, as cinzas se dissipam e a capital se reergue."
				},
				world = {
					en = "The capital is rebuilt: the ash and rubble are cleared and flowers grow where the cracks were.",
					pt = "A capital foi reconstruída: as cinzas e os escombros sumiram, e há flores onde ficavam as rachaduras."
				},
				npc = {
					en = "The streets are clean again. I have written every chapter. Go and read your names at the Memorial.",
					pt = "As ruas estão limpas de novo. Escrevi todos os capítulos. Vão ler os nomes de vocês no Memorial."
				}
			}
		}
	}
}

-- the lines of the Chronicler before any chapter is done (the NPC helper's first answer)
T.npcStart = {
	en = "I keep the Chronicle. This season's first page is still blank; it waits for the realm to write it.",
	pt = "Eu guardo a Crônica. A primeira página desta temporada ainda está em branco; ela espera o reino escrevê-la."
}

-- a text field in a language ("en" | "pt"; anything else is English)
function T.pick(field, lang)
	if type(field) ~= "table" then
		return field
	end
	if lang == "pt" or lang == "pt-BR" or lang == "pt_BR" then
		return field.pt or field.en
	end
	return field.en or field.pt
end

-- what an NPC says about the Chronicle after `done` chapters of `arcKey` (the global storages of chronicle_config.lua
-- `globalStorage`: an NPC script reads Game.getStorageValue(done) and calls this with dofile'd data)
function T.npcLine(arcKey, done, lang)
	local arc = T.arcs[arcKey or ""]
	done = math.floor(tonumber(done) or 0)
	if not arc or done <= 0 then
		return T.pick(T.npcStart, lang)
	end
	local ch = arc.chapters[math.min(done, #arc.chapters)]
	return T.pick(ch.npc, lang)
end

ChaosChronicleText = T
return T
