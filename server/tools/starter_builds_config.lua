-- The hand-written part of the Starter Builds guide (O448; tools/gen_starter_builds.lua -> website guide/starter_builds_data.json).
-- The generator takes everything that is a fact from the game: the build names, the one-line "what it does" (the Recommended
-- build's own text up to its price), the keystones with the point each one arrives at, the import codes and the point cuts.
-- This file holds the words only: how a build plays, its price, the spells to lean on, what to wear and a card set.
--
-- OWNER RULE (2026-11-10): the guide is qualitative. No DPS, no percent, no "x more damage", no survivability figure. Words
-- only. Level and point thresholds that are plain facts of the game (a keystone arrives at point 25, a spell opens at level
-- 130) are allowed. The generator and tests/starter_builds_test.lua stop on a percent sign or the letters DPS in any text.
--
-- Every text is {english, brazilian portuguese}. Proper names (builds, keystones, spells, items) stay in English in pt-BR as
-- everywhere in the game. A style is at most 240 characters. Short sentences, no em-dash, no other game named.
-- Lua 5.1 / LuaJIT and Lua 5.3, no engine calls.

local S = {}

-- the page: intro, how to use a code, the headings, the labels
S.intro = {"Three builds for every class: what each one does, how it plays, what it costs, which keystones it walks to, which spells to lean on, what to wear and an import code. Words only: no damage figures. Every build is also in the game, in the Auto build list of the passive tree.",
	"Três builds para cada classe: o que cada uma faz, como se joga, quanto custa, a quais keystones ela vai, quais magias usar, o que vestir e um código de importação. Só palavras: sem números de dano. Toda build também está no jogo, na lista Auto build da árvore passiva."}

S.howTo = {
	{"Pick the code of the size you need. Each code is the same build cut at a point budget: the first nodes of the build, in order, so every cut is a legal tree.",
		"Escolha o código do tamanho que você precisa. Cada código é a mesma build cortada em um orçamento de pontos: os primeiros nós da build, em ordem, então todo corte é uma árvore válida."},
	{"In the game open the passive tree, press Build Code, paste the code and press Import. The preview shows what changes and what it costs. Apply Build writes it. Adding nodes is free; taking nodes back costs a respec.",
		"No jogo abra a árvore passiva, clique em Build Code, cole o código e clique em Import. A prévia mostra o que muda e quanto custa. Apply Build grava. Adicionar nós é grátis; devolver nós custa um respec."},
	{"The same builds are in the passive tree under Auto build. There, Save to a loadout slot keeps a build in a loadout slot without touching your live tree: only the tree of the slot is written, its gear and runes stay.",
		"As mesmas builds estão na árvore passiva em Auto build. Lá, Save to a loadout slot guarda uma build em um slot de loadout sem mexer na sua árvore atual: só a árvore do slot é gravada, o equipamento e as runas ficam."},
	{"A code of another class is refused. Monk, Necromancer and Templar lines share one class mark in the code: the game still stops nodes your class cannot hold.",
		"O código de outra classe é recusado. As linhas Monk, Necromancer e Templar compartilham uma só marca de classe no código: o jogo ainda barra os nós que a sua classe não pode ter."}
}

S.headings = {
	builds = {"Builds", "Builds"}, what = {"What it does", "O que faz"}, plays = {"How it plays", "Como se joga"},
	price = {"Price", "Preço"}, keystones = {"Keystones", "Keystones"}, cast = {"Cast", "Lance"}, wear = {"Wear", "Vista"},
	cards = {"Cards", "Cartas"}, codes = {"Import codes", "Códigos de importação"},
	point = {"point", "ponto"}, points = {"points", "pontos"}, level = {"level", "nível"},
	noKeystone = {"No keystone: the walls and the aura are the build.", "Sem keystone: as muralhas e a aura são a build."},
	cardRule = {"A set needs three cards of one element, one for each spell line your class casts. It takes three of your five card slots and locks those lines to that element.",
		"Um conjunto pede três cartas de um elemento, uma para cada linha de magia que a sua classe lança. Ele ocupa três dos seus cinco slots de carta e prende essas linhas a esse elemento."},
	keystoneNote = {"The point is the order of the build: the keystone arrives with that point.", "O ponto é a ordem da build: a keystone chega com esse ponto."}
}

-- the kind of a Recommended build, one word
S.kinds = {
	area = {"Area", "Área"}, tank = {"Tank", "Tank"}, sustain = {"Sustain", "Sustento"}, single = {"Single target", "Alvo único"},
	crit = {"Critical strikes", "Golpes críticos"}, dot = {"Damage over time", "Dano ao longo do tempo"}, summons = {"Summons", "Invocações"},
	support = {"Support", "Suporte"}, mobility = {"Speed", "Velocidade"}, snares = {"Traps and mines", "Armadilhas e minas"},
	retaliation = {"Retaliation", "Retaliação"}, damage = {"Damage", "Dano"}
}

-- the classes in page order, with the one line under the name
S.classes = {
	{key = "warrior", name = "Warrior", line = {"Melee, heavy armour, the most health. Ascends to Juggernaut or Berserker.", "Corpo a corpo, armadura pesada, a maior vida. Ascende a Juggernaut ou Berserker."}},
	{key = "juggernaut", name = "Juggernaut", line = {"The Warrior who stands: the toughest class.", "O Warrior que aguenta: a classe mais resistente."}},
	{key = "berserker", name = "Berserker", line = {"The Warrior who hits: two-handers, rage and leech.", "O Warrior que bate: duas mãos, fúria e roubo de vida."}},
	{key = "ranger", name = "Ranger", line = {"Bows and crossbows from range. Ascends to Deadeye or Beastmaster.", "Arcos e bestas à distância. Ascende a Deadeye ou Beastmaster."}},
	{key = "deadeye", name = "Deadeye", line = {"The Ranger who aims: crossbows, one target at a time.", "O Ranger que mira: bestas, um alvo de cada vez."}},
	{key = "beastmaster", name = "Beastmaster", line = {"The Ranger with wolves: a companion fights beside you.", "O Ranger com lobos: um companheiro luta ao seu lado."}},
	{key = "mystic", name = "Mystic", line = {"Spells and mana. Ascends to Elementalist or Illusionist.", "Magias e mana. Ascende a Elementalist ou Illusionist."}},
	{key = "elementalist", name = "Elementalist", line = {"The Mystic of fire, ice and energy.", "O Mystic do fogo, do gelo e da energia."}},
	{key = "illusionist", name = "Illusionist", line = {"The Mystic of curses, illusions and the party.", "O Mystic das maldições, das ilusões e do grupo."}},
	{key = "thief", name = "Thief", line = {"Fast blades, poison, traps. Ascends to Ninja or Samurai.", "Lâminas rápidas, veneno, armadilhas. Ascende a Ninja ou Samurai."}},
	{key = "ninja", name = "Ninja", line = {"The Thief of shadows and dodging.", "O Thief das sombras e da esquiva."}},
	{key = "samurai", name = "Samurai", line = {"The Thief of the duel and the parry.", "O Thief do duelo e da defesa."}},
	{key = "monk", name = "Monk", line = {"Fists and chi. Ascends to Shadowfist or Iron Sage.", "Punhos e chi. Ascende a Shadowfist ou Iron Sage."}},
	{key = "shadowfist", name = "Shadowfist", line = {"The Monk of crits and speed.", "O Monk dos críticos e da velocidade."}},
	{key = "ironsage", name = "Iron Sage", line = {"The Monk of healing and stone.", "O Monk da cura e da pedra."}},
	{key = "necromancer", name = "Necromancer", line = {"Minions, curses and corpses. Ascends to Lich or Bone Lord.", "Lacaios, maldições e cadáveres. Ascende a Lich ou Bone Lord."}},
	{key = "lich", name = "Lich", line = {"The Necromancer of curses and the shade.", "O Necromancer das maldições e da sombra."}},
	{key = "bonelord", name = "Bone Lord", line = {"The Necromancer of the great army.", "O Necromancer do grande exército."}},
	{key = "templar", name = "Templar", line = {"Holy melee and an aura. Ascends to Inquisitor or Sentinel.", "Corpo a corpo sagrado e uma aura. Ascende a Inquisitor ou Sentinel."}},
	{key = "inquisitor", name = "Inquisitor", line = {"The Templar who judges and burns.", "O Templar que julga e queima."}},
	{key = "sentinel", name = "Sentinel", line = {"The Templar who guards the party.", "O Templar que guarda o grupo."}}
}

-- the elements of a card set, one line each (the numbers are in docs/BUILDS.md "Card sets (O453)")
S.sets = {
	Fire = {name = {"Fire", "Fogo"}, text = {"Fire hits deal a little more.", "Os golpes de Fogo causam um pouco mais de dano."}},
	Earth = {name = {"Earth", "Terra"}, text = {"Earth hits poison the target.", "Os golpes de Terra envenenam o alvo."}},
	Death = {name = {"Death", "Morte"}, text = {"Death hits heal you a little.", "Os golpes de Morte curam você um pouco."}},
	Holy = {name = {"Holy", "Sagrado"}, text = {"Holy hits heal you a little, now and then.", "Os golpes Sagrados curam você um pouco, de vez em quando."}},
	Energy = {name = {"Energy", "Energia"}, text = {"Energy hits slow the target.", "Os golpes de Energia atrasam o alvo."}}
}

-- the prices, in words (the build's own price line has figures; the guide has none). A build names one by key.
S.prices = {
	otherMeleeWeaker = {"Your ordinary melee hits are weaker.", "Seus golpes corpo a corpo comuns ficam mais fracos."},
	slowKillsShield = {"You need a shield, and kills come slowly.", "Você precisa de um escudo, e as mortes demoram."},
	lessHealingMoreDamage = {"Healing from others is weaker, and every kill stack makes you take more damage.", "A cura vinda de outros fica mais fraca, e cada acúmulo de mortes faz você levar mais dano."},
	slowKills = {"Kills come slowly.", "As mortes demoram."},
	pyreCost = {"Your other damage is weaker, and you burn along with the pack.", "Seu outro dano fica mais fraco, e você queima junto com o bando."},
	heavyCost = {"Most of your hits are weaker, and you hold no tank keystone.", "A maioria dos seus golpes fica mais fraca, e você não tem keystone de tank."},
	needsTwoHander = {"Cleaving Arc works only with a two-handed weapon.", "O Cleaving Arc só funciona com arma de duas mãos."},
	lessHealing = {"Healing from others is weaker.", "A cura vinda de outros fica mais fraca."},
	crusherCost = {"Your other melee hits are weaker, and so are hits that are not critical.", "Seus outros golpes corpo a corpo ficam mais fracos, e os que não são críticos também."},
	closeHitsWeaker = {"Hits from close range are weaker.", "Os golpes de perto ficam mais fracos."},
	mainHitWeaker = {"The shot that hits your target is a little weaker.", "O tiro que atinge o seu alvo fica um pouco mais fraco."},
	hitItselfWeaker = {"The hit itself is weaker; the bleed makes up for it only in long fights.", "O golpe em si fica mais fraco; o sangramento compensa só nas lutas longas."},
	slowOnPacks = {"Slow on packs.", "Lento contra bandos."},
	nonCritWeaker = {"Hits that are not critical are weaker.", "Os golpes que não são críticos ficam mais fracos."},
	wildVolleyCost = {"Close hits are weaker, and the wolves only hold monsters off.", "Os golpes de perto ficam mais fracos, e os lobos só seguram os monstros."},
	needsElementChange = {"It pays only if you change element on every cast.", "Só compensa se você trocar de elemento a cada magia."},
	ownDamageWeaker = {"Your own damage is a little weaker.", "Seu próprio dano fica um pouco mais fraco."},
	lowDamage = {"Low damage.", "Pouco dano."},
	littleDamage = {"Little damage of your own.", "Pouco dano próprio."},
	effigyCost = {"Your own spells are weaker, and a single target gains nothing.", "Suas próprias magias ficam mais fracas, e um alvo só não ganha nada."},
	needsParty = {"You need a party; alone you do little.", "Você precisa de um grupo; sozinho você faz pouco."},
	venomCost = {"Your evasion is cut in half, and your weapon hits are weaker.", "Sua esquiva cai pela metade, e seus golpes de arma ficam mais fracos."},
	takeMoreNonCrit = {"You take more damage, and hits that are not critical are weaker.", "Você leva mais dano, e os golpes que não são críticos ficam mais fracos."},
	mineCost = {"Your other hits are weaker, and it needs set-up.", "Seus outros golpes ficam mais fracos, e ela pede preparo."},
	takeMoreDamage = {"You take more damage.", "Você leva mais dano."},
	noDodge = {"You can no longer dodge.", "Você não pode mais se esquivar."},
	otherHitsWeaker = {"Your other hits are weaker.", "Seus outros golpes ficam mais fracos."},
	palmCost = {"You cannot dodge, and each hit is a little weaker.", "Você não se esquiva, e cada golpe fica um pouco mais fraco."},
	healthReserved = {"Part of your health is reserved.", "Parte da sua vida fica reservada."},
	ownSpellsWeaker = {"Your own spells are weaker.", "Suas próprias magias ficam mais fracas."},
	healthyWeaker = {"Your hits are weaker on healthy monsters.", "Seus golpes ficam mais fracos contra monstros com a vida cheia."},
	slowStart = {"A slow start.", "Um começo lento."},
	zealotCost = {"Your spells are weaker, and your aura protects you less.", "Suas magias ficam mais fracas, e sua aura protege menos."},
	spellsWeaker = {"Your spells are weaker.", "Suas magias ficam mais fracas."},
	notFireHoly = {"Damage that is not fire or holy is weaker.", "O dano que não é de fogo nem sagrado fica mais fraco."},
	weaponHitsWeaker = {"Your weapon hits are weaker.", "Seus golpes de arma ficam mais fracos."},
	retributorCost = {"Your damage is weaker, and your aura protects you less.", "Seu dano fica mais fraco, e sua aura protege menos."}
}

-- the builds, by the id of the Recommended build (class key and role id of passive_builds_config.lua):
--   style   how it plays, 2 or 3 short sentences, at most 240 characters
--   price   a key of S.prices
--   spells  2 to 4 spell names of the class (checked against the client spell list)
--   gear    what to wear, with the weapon type or family (Warrior, Thief and Templar lines: sword, axe or club, O454)
--   cards   a key of S.sets the class can reach (checked against cards_config.lua), or {english, portuguese} when no set fits
S.builds = {
	-- ------------------------------------------------------------------------------------------------ Warrior line
	warrior_slayer = {
		style = {"A two-hander build for packs. Every swing cleaves the monsters beside you, and every fourth hit slams the ground around the target. Walk into the pack and keep swinging.",
			"Build de duas mãos para bandos. Cada golpe atinge os monstros ao seu lado, e o quarto golpe faz o chão tremer ao redor do alvo. Entre no bando e continue batendo."},
		price = "otherMeleeWeaker", spells = {"Reaping Gyre", "Colossus Fall", "Keepfall"}, cards = "Earth",
		gear = {"A two-handed axe: Cleaving Arc needs a two-hander and the axe splits part of each hit among the neighbours. Heavy armour.",
			"Um machado de duas mãos: o Cleaving Arc exige arma de duas mãos e o machado divide parte de cada golpe entre os vizinhos. Armadura pesada."}},
	warrior_bulwark = {
		style = {"The shield build. Health, resistances and the shielding skill keep you up, and Bulwark blocks some attacks outright and sends part of the melee damage back. You win slowly and you do not fall.",
			"A build do escudo. Vida, resistências e o skill de escudo mantêm você de pé, e o Bulwark bloqueia alguns ataques por completo e devolve parte do dano corpo a corpo. Você vence devagar e não cai."},
		price = "slowKillsShield", spells = {"Ironhold", "Vigil of Iron", "Iron Bellow", "Bastion Cry"}, cards = "Death",
		gear = {"A club and a shield: Bulwark only works with a shield, and the club can daze the monster in front of you. Heavy armour.",
			"Uma clava e um escudo: o Bulwark só funciona com escudo, e a clava pode atordoar o monstro à sua frente. Armadura pesada."}},
	warrior_bloodied = {
		style = {"You heal by hitting. Sanguine Covenant turns every blow into health, and Rampage grows stronger with each kill in a row, at the price of taking more damage. Keep killing to keep the stack and to stay alive.",
			"Você se cura batendo. O Sanguine Covenant transforma cada golpe em vida, e o Rampage fica mais forte a cada morte seguida, ao preço de levar mais dano. Continue matando para manter o acúmulo e continuar vivo."},
		price = "lessHealingMoreDamage", spells = {"Gorehook", "Red Frenzy", "Vaulting Cleave"}, cards = "Death",
		gear = {"A sword: its Tempo speeds up your swing on the same target, and every hit feeds the leech. Heavy armour, shield if you like.",
			"Uma espada: o Tempo dela acelera seu golpe no mesmo alvo, e cada golpe alimenta o roubo de vida. Armadura pesada, escudo se quiser."}},
	juggernaut_unbreakable = {
		style = {"The toughest way to stand. Immovable cuts the damage you take, more when your health is low, and Bulwark blocks and reflects. Hold the door for the party and let the monsters break against you.",
			"O jeito mais resistente de ficar de pé. O Immovable corta o dano que você leva, mais ainda com a vida baixa, e o Bulwark bloqueia e reflete. Segure a porta para o grupo e deixe os monstros se quebrarem em você."},
		price = "slowKills", spells = {"Ironhold", "Vigil of Iron", "Iron Bellow", "Anvil Fall"}, cards = "Death",
		gear = {"A shield and a club or a sword, in the heaviest armour you can find. Bulwark needs the shield.",
			"Um escudo e uma clava ou espada, na armadura mais pesada que você achar. O Bulwark exige o escudo."}},
	juggernaut_pyre_walker = {
		style = {"Walk into the pack and stand there. Pyre Oath burns every enemy around you while you burn a little yourself, and health and resistances keep you standing. Not for a single target.",
			"Entre no bando e fique parado. O Pyre Oath queima todos os inimigos ao seu redor enquanto você queima um pouco, e vida e resistências mantêm você de pé. Não serve para um alvo só."},
		price = "pyreCost", spells = {"Colossus Fall", "Ironhold", "Vigil of Iron"}, cards = "Death",
		gear = {"A shield and a sword or club, with fire resistance on your armour: you burn along with the pack. Heavy armour.",
			"Um escudo e uma espada ou clava, com resistência a fogo na armadura: você queima junto com o bando. Armadura pesada."}},
	juggernaut_heavy_hitter = {
		style = {"Slow, heavy blows. Earthbreaker slams the ground every fourth hit, and Executioner's Verdict finishes monsters that are nearly dead, bosses excepted. It hits hard and gives up the tank keystones.",
			"Golpes lentos e pesados. O Earthbreaker faz o chão tremer a cada quarto golpe, e o Executioner's Verdict termina monstros quase mortos, exceto chefes. Bate forte e abre mão das keystones de tank."},
		price = "heavyCost", spells = {"Gorehook", "Rift Cleaver", "Anvil Fall"}, cards = "Earth",
		gear = {"A two-handed axe or club: the axe cleaves into the neighbours, the club can daze. Heavy armour.",
			"Um machado ou clava de duas mãos: o machado divide o golpe com os vizinhos, a clava pode atordoar. Armadura pesada."}},
	berserker_rage_engine = {
		style = {"Cleave the pack and heal as you go. A two-hander hits the monsters next to you with every blow, and Undying Rage returns health from the damage you deal, more when you are low. Stay in the middle of the fight.",
			"Corte o bando e se cure pelo caminho. A arma de duas mãos atinge os monstros ao seu lado a cada golpe, e o Undying Rage devolve vida do dano que você causa, mais ainda com a vida baixa. Fique no meio da luta."},
		price = "needsTwoHander", spells = {"Skyfall Cleave", "Colossus Fall", "Bloodrage"}, cards = "Earth",
		gear = {"A two-handed axe: Cleaving Arc needs a two-hander and the axe's cleave adds to it. Heavy armour.",
			"Um machado de duas mãos: o Cleaving Arc exige arma de duas mãos e o corte do machado soma a ele. Armadura pesada."}},
	berserker_bloodrunner = {
		style = {"A double leech. Sanguine Covenant and Undying Rage both turn your hits into health, so the more you hit, the less you need a healer. Healing from others is weaker, so this build looks after itself.",
			"Roubo de vida em dobro. O Sanguine Covenant e o Undying Rage transformam seus golpes em vida, então quanto mais você bate, menos precisa de curandeiro. A cura de outros é mais fraca, então esta build se cuida sozinha."},
		price = "lessHealing", spells = {"Gorehook", "Red Frenzy", "Bloodrage"}, cards = "Death",
		gear = {"A two-handed sword: Tempo speeds up your swing while you stay on one target, and every hit feeds the leech.",
			"Uma espada de duas mãos: o Tempo acelera seu golpe enquanto você fica em um alvo, e cada golpe alimenta o roubo de vida."}},
	berserker_crusher = {
		style = {"Slams and crits. Earthbreaker slams the ground every fourth hit, and when you crit, Cascade Edge bursts on the monsters around the target. Build crit chance and crit amount and let the pack pop.",
			"Pancadas e críticos. O Earthbreaker faz o chão tremer a cada quarto golpe, e quando você acerta um crítico o Cascade Edge explode nos monstros ao redor do alvo. Invista em chance e dano de crítico e veja o bando estourar."},
		price = "crusherCost", spells = {"Skyfall Cleave", "Rampage Leap", "Keepfall"}, cards = "Earth",
		gear = {"A two-handed club or axe with a high critical chance: the club can daze, the axe cleaves. Heavy armour.",
			"Uma clava ou machado de duas mãos com boa chance de crítico: a clava pode atordoar, o machado corta em área. Armadura pesada."}},

	-- ------------------------------------------------------------------------------------------------ Ranger line
	ranger_sharpshooter = {
		style = {"A crossbow build for one big target. Deadeye gives some shots double damage and Longshot rewards distance, so stay far back and keep shooting. Health and resistances keep you alive when something reaches you.",
			"Build de besta para um alvo grande. O Deadeye dá dano dobrado a alguns tiros e o Longshot premia a distância, então fique bem longe e continue atirando. Vida e resistências mantêm você vivo quando algo chega perto."},
		price = "closeHitsWeaker", spells = {"Sunspear", "Hail of Dawn", "Skewering Line"}, cards = "Fire",
		gear = {"A crossbow and bolts: Deadeye only works with them. Light armour with health and resistances.",
			"Uma besta e virotes: o Deadeye só funciona com eles. Armadura leve com vida e resistências."}},
	ranger_stormquiver = {
		style = {"Lightning and bounces for packs. Stormstring arcs every shot into other monsters, and Ricochet bounces it again from monster to monster. Shoot from range and let the pack carry the chain.",
			"Raios e ricochetes para bandos. O Stormstring faz cada tiro saltar para outros monstros, e o Ricochet salta de novo de monstro em monstro. Atire de longe e deixe o bando carregar a corrente."},
		price = "mainHitWeaker", spells = {"Arrowstorm", "Gale Volley", "Moonshard Rain"}, cards = "Fire",
		gear = {"A bow or a crossbow with energy damage: both keystones work with either. Light armour.",
			"Um arco ou uma besta com dano de energia: as duas keystones funcionam com qualquer um. Armadura leve."}},
	ranger_barbed_hunter = {
		style = {"Every shot leaves a bleed. Barbed Quiver makes bow, crossbow and thrown weapon hits bleed, so a long fight grows deadlier the longer a monster lives. Shoot, back away and let the bleed work.",
			"Todo tiro deixa um sangramento. O Barbed Quiver faz os golpes de arco, besta e arremesso sangrarem, então uma luta longa fica mais mortal quanto mais o monstro vive. Atire, recue e deixe o sangramento trabalhar."},
		price = "hitItselfWeaker", spells = {"Skewering Line", "Gale Volley", "Seeker Mine"}, cards = "Earth",
		gear = {"A bow, a crossbow or thrown weapons: all of them bleed. Light armour.",
			"Um arco, uma besta ou armas de arremesso: todos sangram. Armadura leve."}},
	deadeye_marked_target = {
		style = {"One target, three keystones. Deadeye's double-damage shots, Hunter's Focus that grows with every hit on the same target, and Longshot's distance bonus. Pick a boss, stand far and keep shooting it.",
			"Um alvo, três keystones. Os tiros de dano dobrado do Deadeye, o Hunter's Focus que cresce a cada golpe no mesmo alvo e o bônus de distância do Longshot. Escolha um chefe, fique longe e continue atirando nele."},
		price = "slowOnPacks", spells = {"Final Verdict", "Twin Verdict", "Hail of Dawn", "Sunspear"}, cards = "Fire",
		gear = {"A crossbow and bolts: Deadeye needs them, and Hunter's Focus works with them too. Light armour.",
			"Uma besta e virotes: o Deadeye exige os dois, e o Hunter's Focus funciona com eles também. Armadura leve."}},
	deadeye_stormquiver = {
		style = {"Stormstring arcs lightning from every shot into the monsters around the target. A simple pack build: aim at the middle of the pack and let the chain do the rest.",
			"O Stormstring faz cada tiro soltar raios nos monstros ao redor do alvo. Uma build de bando simples: mire no meio do bando e deixe a corrente fazer o resto."},
		price = "mainHitWeaker", spells = {"Gale Volley", "Moonshard Rain", "Blessed Earth"}, cards = "Fire",
		gear = {"A bow or a crossbow with energy damage. Light armour.", "Um arco ou uma besta com dano de energia. Armadura leve."}},
	deadeye_cascade_hunter = {
		style = {"A crit build. Cascade Edge makes every critical hit burst on the monsters next to the target, so build crit chance and crit amount and aim at the centre of the pack.",
			"Uma build de crítico. O Cascade Edge faz cada golpe crítico explodir nos monstros ao lado do alvo, então invista em chance e dano de crítico e mire no centro do bando."},
		price = "nonCritWeaker", spells = {"Final Verdict", "Twin Verdict", "Gale Volley"}, cards = "Fire",
		gear = {"A crossbow or bow with a high critical chance. Light armour.", "Uma besta ou arco com boa chance de crítico. Armadura leve."}},
	beastmaster_pack_leader = {
		style = {"Your companions do the biting. Pack Alpha makes your wolves and wolf spells hit harder and take less, and Stormstring arcs your shots into the pack. Keep the wolves alive and shoot beside them.",
			"Seus companheiros fazem a mordida. O Pack Alpha faz seus lobos e as magias de lobo baterem mais forte e sofrerem menos, e o Stormstring faz seus tiros saltarem no bando. Mantenha os lobos vivos e atire ao lado deles."},
		price = "mainHitWeaker", spells = {"Feral Command", "Pack Howl", "Pack Frenzy", "Rending Pounce"}, cards = "Earth",
		gear = {"A bow with health and spirit on your armour: the wolves need you alive. Light armour.",
			"Um arco, com vida e spirit na armadura: os lobos precisam de você vivo. Armadura leve."}},
	beastmaster_wild_volley = {
		style = {"A bow build that leaves the wolves in the back. Ricochet bounces every shot through the pack, and Longshot pays for distance. Keep your range and use the wolves to hold monsters off.",
			"Uma build de arco que deixa os lobos para trás. O Ricochet faz cada tiro saltar pelo bando, e o Longshot paga pela distância. Mantenha o alcance e use os lobos para segurar os monstros."},
		price = "wildVolleyCost", spells = {"Moonshard Rain", "Sunspear", "Feral Command"}, cards = "Fire",
		gear = {"A bow or a crossbow: both keystones work with either. Light armour.", "Um arco ou uma besta: as duas keystones funcionam com qualquer um. Armadura leve."}},
	beastmaster_hardy_warden = {
		style = {"A safe way to hunt alone. Pack Alpha makes your wolves stronger and tougher, while the health and resistance nodes keep you alive beside them. Slow and steady, for hunts where you cannot afford to die.",
			"Um jeito seguro de caçar sozinho. O Pack Alpha deixa seus lobos mais fortes e resistentes, enquanto os nós de vida e resistência mantêm você vivo ao lado deles. Devagar e sempre, para caçadas em que você não pode morrer."},
		price = "lowDamage", spells = {"Wild Bond", "Feral Command", "Pack Howl", "Soulward"}, cards = "Death",
		gear = {"A bow, and armour with health and resistances.", "Um arco, e armadura com vida e resistências."}},

	-- ------------------------------------------------------------------------------------------------ Mystic line
	mystic_arcanist = {
		style = {"An area caster. Arcane Echo makes spells that hit several enemies echo a moment later, and Elemental Overload makes the next spell of a new element hit harder. Cast area spells and change element on every cast.",
			"Um conjurador de área. O Arcane Echo faz as magias que atingem vários inimigos ecoarem um instante depois, e o Elemental Overload faz a próxima magia de outro elemento bater mais forte. Lance magias de área e troque de elemento a cada uma."},
		price = "needsElementChange", spells = {"Rime Bloom", "Falling Pyre", "Prismatic Rupture"},
		cards = {"None: Elemental Overload wants a new element on every cast, and a card set locks your lines to one element.",
			"Nenhum: o Elemental Overload quer um elemento novo a cada magia, e um conjunto de cartas prende suas linhas a um só elemento."},
		gear = {"A wand or rod with spell damage, and robes with mana and energy shield.", "Uma varinha ou cajado com dano de magia, e vestes com mana e escudo de energia."}},
	mystic_mana_weaver = {
		style = {"A support caster. Covenant of Vigils makes your vigils cheaper, wider and stronger for the party, and the mana nodes give you the pool to keep them on. Turn the vigils on, stand with the group and cast between pulses.",
			"Um conjurador de suporte. O Covenant of Vigils deixa suas vigílias mais baratas, mais largas e mais fortes para o grupo, e os nós de mana dão a reserva para mantê-las. Ligue as vigílias, fique com o grupo e lance entre os pulsos."},
		price = "ownDamageWeaker", spells = {"Vigil of Clarity", "Vigil of Iron", "Vigil of Wrath", "Purifying Wellspring"}, cards = "Energy",
		gear = {"A rod with mana and spirit, and robes with mana. The vigils reserve mana, so a deep pool is the gear.",
			"Um cajado com mana e spirit, e vestes com mana. As vigílias reservam mana, então uma reserva grande é o equipamento."}},
	mystic_warded_mage = {
		style = {"A careful caster. Elemental Overload still rewards a new element on every cast, while health and resistances let you survive a mistake. The damage is low, but you stay in the fight.",
			"Um conjurador cuidadoso. O Elemental Overload ainda premia um elemento novo a cada magia, enquanto vida e resistências deixam você sobreviver a um erro. O dano é baixo, mas você continua na luta."},
		price = "lowDamage", spells = {"Witchfire Bolt", "Rime Bloom", "Soulward", "Ironbark Hide"}, cards = "Death",
		gear = {"A wand or rod, and robes with health, resistances and energy shield.", "Uma varinha ou cajado, e vestes com vida, resistências e escudo de energia."}},
	elementalist_overloaded = {
		style = {"A one-target caster who plays the elements like keys. A spell of a new element within a few seconds hits harder, so rotate fire, ice and energy and never cast the same element twice in a row.",
			"Um conjurador de alvo único que toca os elementos como teclas. Uma magia de elemento novo em poucos segundos bate mais forte, então alterne fogo, gelo e energia e nunca lance o mesmo elemento duas vezes seguidas."},
		price = "needsElementChange", spells = {"Witchfire Bolt", "Forked Storm", "Rime Bloom", "Falling Pyre"},
		cards = {"None: Elemental Overload wants a new element on every cast, and a card set locks your lines to one element.",
			"Nenhum: o Elemental Overload quer um elemento novo a cada magia, e um conjunto de cartas prende suas linhas a um só elemento."},
		gear = {"A wand or rod with spell damage, and robes with mana and energy shield.", "Uma varinha ou cajado com dano de magia, e vestes com mana e escudo de energia."}},
	elementalist_effigy_caller = {
		style = {"Leave the pack to your effigies. An area spell raises a Cinder Effigy on your tile that repeats the cast every few seconds. Cast a big area spell, step away and cast again. A single target gains nothing.",
			"Deixe o bando para as suas efígies. Uma magia de área ergue uma Cinder Effigy no seu quadrado que repete a magia a cada poucos segundos. Lance uma magia de área grande, saia de perto e lance de novo. Um alvo só não ganha nada."},
		price = "effigyCost", spells = {"Doomtide", "Glacial Doom", "Frozen Crypt", "Falling Pyre"}, cards = "Fire",
		gear = {"A wand or rod with area damage, and robes with health and energy shield.", "Uma varinha ou cajado com dano de área, e vestes com vida e escudo de energia."}},
	elementalist_vigil_keeper = {
		style = {"Vigils for the group. Covenant of Vigils makes them cheaper, wider and stronger for the party, and the mana nodes pay for them. You still hold spells of every element for when the group needs damage.",
			"Vigílias para o grupo. O Covenant of Vigils as deixa mais baratas, mais largas e mais fortes para o grupo, e os nós de mana pagam por elas. Você ainda tem magias de todos os elementos para quando o grupo precisar de dano."},
		price = "ownDamageWeaker", spells = {"Vigil of Clarity", "Vigil of Haste", "Vigil of Wrath", "Forked Storm"}, cards = "Energy",
		gear = {"A rod with mana and spirit, and robes with mana. A deep pool carries the vigils.", "Um cajado com mana e spirit, e vestes com mana. Uma reserva grande sustenta as vigílias."}},
	illusionist_support_weaver = {
		style = {"Make the party stronger. Shared Phantasm marks the enemy so your party hits it harder and heals from it, and Inspiring Illusion adds damage to everyone near you. You need a party; alone you do little.",
			"Deixe o grupo mais forte. O Shared Phantasm marca o inimigo para o grupo bater mais forte e se curar, e o Inspiring Illusion soma dano a todos perto de você. Você precisa de um grupo; sozinho você faz pouco."},
		price = "needsParty", spells = {"Hall of Mirrors", "Lucid Reverie", "Mirror Mend", "Verdant Sanctuary"}, cards = "Death",
		gear = {"A wand or rod, and robes with mana and magic level: your heals and marks are the build.", "Uma varinha ou cajado, e vestes com mana e magic level: suas curas e marcas são a build."}},
	illusionist_vigil_keeper = {
		style = {"Vigils for the group. Covenant of Vigils makes them cheaper, wider and stronger for the party, and the mana nodes pay for them. Turn them on, stay close to your friends and cast between pulses.",
			"Vigílias para o grupo. O Covenant of Vigils as deixa mais baratas, mais largas e mais fortes para o grupo, e os nós de mana pagam por elas. Ligue, fique perto dos amigos e lance entre os pulsos."},
		price = "ownDamageWeaker", spells = {"Vigil of Clarity", "Vigil of Iron", "Vigil of Wrath", "Mirror Mend"}, cards = "Death",
		gear = {"A rod with mana and spirit, and robes with mana.", "Um cajado com mana e spirit, e vestes com mana."}},
	illusionist_illusory_striker = {
		style = {"An area caster. Cinder Effigies repeat each area spell, so cast Nightburst or Tear in the Weave in the middle of the pack, step away and cast again.",
			"Um conjurador de área. As Cinder Effigies repetem cada magia de área, então lance Nightburst ou Tear in the Weave no meio do bando, saia de perto e lance de novo."},
		price = "effigyCost", spells = {"Nightburst", "Tear in the Weave", "Mirror Shards", "Primordial Squall"}, cards = "Death",
		gear = {"A wand or rod with area damage, and robes with health and energy shield.", "Uma varinha ou cajado com dano de área, e vestes com vida e escudo de energia."}},

	-- ------------------------------------------------------------------------------------------------ Thief line
	thief_venomblade = {
		style = {"Poison on every strike. Blackblood Creed poisons with every attack, Contagion Rite spreads the poison to the monsters around when one dies, and Viper's Verdict strikes vitals on poisoned targets. Start a poison and let it kill the pack.",
			"Veneno em cada golpe. O Blackblood Creed envenena todo ataque, o Contagion Rite espalha o veneno aos monstros ao redor quando um morre, e o Viper's Verdict acerta pontos vitais de alvos envenenados. Comece um veneno e deixe-o matar."},
		price = "venomCost", spells = {"Poison Blades", "Venom Spiral", "Smoke Bomb", "Fan of Knives"}, cards = "Death",
		gear = {"A sword: Tempo speeds up your swing on one target, so poison goes on fast. Light armour.", "Uma espada: o Tempo acelera seu golpe em um alvo, então o veneno entra rápido. Armadura leve."}},
	thief_cutthroat = {
		style = {"Two blows for one. Shadow Twin sometimes sends your shadow to hit the same target again, and Cascade Edge bursts on the monsters around every critical hit. Build crit and strike fast.",
			"Dois golpes por um. O Shadow Twin às vezes manda sua sombra bater de novo no mesmo alvo, e o Cascade Edge explode nos monstros ao redor de cada crítico. Invista em crítico e golpeie rápido."},
		price = "takeMoreNonCrit", spells = {"Gutting Slash", "Last Breath", "Eclipse Edge"}, cards = "Death",
		gear = {"A sword with a high critical chance: Tempo speeds up the swing. Light armour.", "Uma espada com boa chance de crítico: o Tempo acelera o golpe. Armadura leve."}},
	thief_mine_layer = {
		style = {"Set the field, then fire it. Snarewright's Creed lets you hold more traps and mines, armed sooner and hitting harder. Lay Snare Traps and Seeker Mines in the path of the pack and set them off with Detonate Mines.",
			"Arme o campo e depois dispare. O Snarewright's Creed deixa você ter mais armadilhas e minas, armadas mais cedo e mais fortes. Coloque Snare Traps e Seeker Mines no caminho do bando e detone com Detonate Mines."},
		price = "mineCost", spells = {"Snare Trap", "Seeker Mine", "Detonate Mines"}, cards = "Death",
		gear = {"A sword: the traps and mines do the work, so the weapon matters little. Light armour, so you can move and re-set.", "Uma espada: as armadilhas e minas fazem o trabalho, então a arma importa pouco. Armadura leve, para você se mover e rearmar."}},
	ninja_twin_fangs = {
		style = {"Dodge, then strike. Living Shadow opens a window after a dodge or after Shadow Veil in which your weapon hits deal more, and Cascade Edge bursts on every crit. Stay light, dodge and hit inside the window.",
			"Esquive e golpeie. O Living Shadow abre uma janela depois de uma esquiva ou do Shadow Veil em que seus golpes de arma causam mais dano, e o Cascade Edge explode a cada crítico. Fique leve, esquive e bata dentro da janela."},
		price = "nonCritWeaker", spells = {"Shadow Veil", "Shadow Step", "Gutting Slash", "Death Between Heartbeats"}, cards = "Death",
		gear = {"A fast sword with a high critical chance, and light armour with evasion.", "Uma espada rápida com boa chance de crítico, e armadura leve com esquiva."}},
	ninja_phantom = {
		style = {"A duelist's shadow. Shadow Twin sometimes strikes the same target twice, and the Fleet Shadow notable adds dodge. Quick, single target and fragile when hit: dodge and finish.",
			"A sombra do duelista. O Shadow Twin às vezes golpeia o mesmo alvo duas vezes, e o notável Fleet Shadow soma esquiva. Rápido, alvo único e frágil quando atingido: esquive e termine."},
		price = "takeMoreDamage", spells = {"Shadow Step", "Gutting Slash", "Razor Rain"}, cards = "Death",
		gear = {"A sword and light armour with evasion.", "Uma espada e armadura leve com esquiva."}},
	ninja_plaguebearer = {
		style = {"Poison on every strike. Blackblood Creed poisons with every attack, Contagion Rite spreads the poison to the monsters around when one dies, and Viper's Verdict strikes vitals on poisoned targets. Start a poison and let it clear the pack.",
			"Veneno em cada golpe. O Blackblood Creed envenena todo ataque, o Contagion Rite espalha o veneno aos monstros ao redor quando um morre, e o Viper's Verdict acerta pontos vitais de alvos envenenados. Comece um veneno e deixe-o limpar."},
		price = "venomCost", spells = {"Poison Blades", "Venom Spiral", "Smoke Bomb", "Shuriken Tempest"}, cards = "Death",
		gear = {"A sword: Tempo speeds up your swing on one target, so poison goes on fast. Light armour.", "Uma espada: o Tempo acelera seu golpe em um alvo, então o veneno entra rápido. Armadura leve."}},
	samurai_duelist = {
		style = {"The patient swordsman. Counter Stance parries every melee hit while it lasts, not only the first, so stand your ground and let monsters strike at your blade. Health and resistances cover what you cannot parry.",
			"O espadachim paciente. O Counter Stance apara todo golpe corpo a corpo enquanto dura, não só o primeiro, então fique firme e deixe os monstros baterem na sua lâmina. Vida e resistências cobrem o que você não consegue aparar."},
		price = "lowDamage", spells = {"Counter Stance", "Bushido Focus", "Iaijutsu", "Iaido Sweep"}, cards = "Death",
		gear = {"A sword and armour with health and resistances: the parry needs you standing in front.", "Uma espada e armadura com vida e resistências: a defesa pede que você fique na frente."}},
	samurai_iaido_striker = {
		style = {"Crit duels. Shadow Twin sometimes strikes twice and Cascade Edge bursts on every crit. Iaijutsu and Iaido Sweep open the fight, and a high crit chance makes every duel short.",
			"Duelos de crítico. O Shadow Twin às vezes golpeia duas vezes e o Cascade Edge explode a cada crítico. Iaijutsu e Iaido Sweep abrem a luta, e uma chance alta de crítico deixa cada duelo curto."},
		price = "takeMoreNonCrit", spells = {"Iaijutsu", "Iaido Sweep", "Last Breath", "Crescent Cut"}, cards = "Death",
		gear = {"A sword with a high critical chance, and light armour.", "Uma espada com boa chance de crítico, e armadura leve."}},
	samurai_bloodblade = {
		style = {"Parry and heal. Way of the Blade parries every melee hit during Counter Stance, and Sanguine Covenant returns health from the hits you land. A swordsman who looks after himself.",
			"Defenda e se cure. O Way of the Blade apara todo golpe corpo a corpo durante o Counter Stance, e o Sanguine Covenant devolve vida dos golpes que você acerta. Um espadachim que se cuida sozinho."},
		price = "lessHealing", spells = {"Counter Stance", "Bushido Focus", "Gutting Slash", "Shadow Mend"}, cards = "Death",
		gear = {"A sword: Tempo speeds up the swing and every hit feeds the leech. Light or medium armour.", "Uma espada: o Tempo acelera o golpe e cada golpe alimenta o roubo de vida. Armadura leve ou média."}},

	-- ------------------------------------------------------------------------------------------------ Monk line
	monk_iron_body = {
		style = {"Take hits, build chi. Scarred Discipline gives you chi every time you are hit and cuts the damage you take while your chi is high. You lose your dodge, so stand firm and let health and resistances work.",
			"Leve golpes, ganhe chi. O Scarred Discipline dá chi toda vez que você é atingido e corta o dano que você leva enquanto o chi está alto. Você perde a esquiva, então fique firme e deixe vida e resistências trabalharem."},
		price = "noDodge", spells = {"Lotus Stance", "Quaking Stomp", "Whirling Heel"}, cards = "Death",
		gear = {"Bare fists or fist weapons, and armour with health and resistances.", "Punhos limpos ou armas de punho, e armadura com vida e resistências."}},
	monk_fist_flurry = {
		style = {"Count your hits. Every fifth melee hit is a finisher that hits far harder and shocks the monsters next to the target. Chain fast blows and use Chi Lance and Skysplitter Fist to keep the count going.",
			"Conte seus golpes. Todo quinto golpe corpo a corpo é um finalizador que bate bem mais forte e dá choque nos monstros ao lado do alvo. Encadeie golpes rápidos e use Chi Lance e Skysplitter Fist para manter a contagem."},
		price = "otherHitsWeaker", spells = {"Ashen Fist", "Chi Lance", "Skysplitter Fist"}, cards = "Fire",
		gear = {"Fist weapons or bare fists with a high attack speed, and light armour.", "Armas de punho ou punhos limpos com boa velocidade de ataque, e armadura leve."}},
	monk_palm_piercer = {
		style = {"Hit the line. Piercing Palm lets your blows pass through to the two enemies behind the target, and Scarred Discipline cuts the damage you take once you have chi. Fight in a corridor where monsters line up.",
			"Acerte a fila. O Piercing Palm faz seus golpes atravessarem até os dois inimigos atrás do alvo, e o Scarred Discipline corta o dano que você leva quando tem chi. Lute em corredores onde os monstros ficam em fila."},
		price = "palmCost", spells = {"Thousand-Echo Palm", "Mistborne Strike", "Chi Lance"}, cards = "Fire",
		gear = {"Fist weapons or bare fists, and armour with health and resistances.", "Armas de punho ou punhos limpos, e armadura com vida e resistências."}},
	shadowfist_hundred_fists = {
		style = {"Crits feed your chi. Hundred Hands gives you chi from focus critical hits, and Cascade Edge bursts on every crit. Build crit chance and keep your fists moving.",
			"Os críticos alimentam seu chi. O Hundred Hands dá chi dos críticos de foco, e o Cascade Edge explode a cada crítico. Invista em chance de crítico e mantenha os punhos em movimento."},
		price = "nonCritWeaker", spells = {"Shadowfist Flurry", "Pressure Points", "Shadow Ricochet"}, cards = "Fire",
		gear = {"Fist weapons with a high critical chance, and light armour.", "Armas de punho com boa chance de crítico, e armadura leve."}},
	shadowfist_pressure_points = {
		style = {"One target, counted hits. Seventh Palm makes every fifth hit a finisher, and Pressure Points and Shadowfist Flurry keep the count high. Good against bosses and big monsters.",
			"Um alvo, golpes contados. O Seventh Palm faz todo quinto golpe ser um finalizador, e Pressure Points e Shadowfist Flurry mantêm a contagem alta. Bom contra chefes e monstros grandes."},
		price = "otherHitsWeaker", spells = {"Pressure Points", "Shadowfist Flurry", "Skysplitter Fist"}, cards = "Fire",
		gear = {"Fist weapons or bare fists with a high attack speed, and light armour.", "Armas de punho ou punhos limpos com boa velocidade de ataque, e armadura leve."}},
	shadowfist_shadow_step = {
		style = {"Fast and light. Iron Tithe lets your vigils be paid in health instead of mana and makes them stronger on you, and Hundred Hands feeds chi from crits. Vigil of Haste and the speed nodes carry you across the hunt.",
			"Rápido e leve. O Iron Tithe deixa suas vigílias serem pagas em vida em vez de mana e as torna mais fortes em você, e o Hundred Hands alimenta o chi dos críticos. Vigil of Haste e os nós de velocidade levam você pela caçada."},
		price = "healthReserved", spells = {"Vigil of Haste", "Vigil of Iron", "Shadow Ricochet", "Flickerdash"}, cards = "Fire",
		gear = {"Fist weapons and light armour with speed. Your vigils are paid in health, so keep your health high.", "Armas de punho e armadura leve com velocidade. Suas vigílias são pagas em vida, então mantenha a vida alta."}},
	ironsage_chi_healer = {
		style = {"A healer with a fist. Flowing Mercy makes Kindled Breath also heal the next most hurt ally, and Overgrowth plants a regrowth on every heal you cast on others. Keep the party alive and fight when nobody needs you.",
			"Um curandeiro com punhos. O Flowing Mercy faz o Kindled Breath curar também o próximo aliado mais ferido, e o Overgrowth planta uma regeneração em cada cura nos outros. Mantenha o grupo vivo e lute quando ninguém precisar de você."},
		price = "littleDamage", spells = {"Kindled Breath", "Chi Ward", "Mantra of Stone", "Iron Chain"}, cards = "Death",
		gear = {"Bare fists or fist weapons, and armour with health, spirit and magic level for your heals.", "Punhos limpos ou armas de punho, e armadura com vida, spirit e magic level para as suas curas."}},
	ironsage_stone_sage = {
		style = {"The mountain. Scarred Discipline gives chi when you are hit and cuts the damage while your chi is high, and Mantra of Stone and Chi Ward cover the party. You cannot dodge, so you stand and take it.",
			"A montanha. O Scarred Discipline dá chi quando você é atingido e corta o dano enquanto o chi está alto, e Mantra of Stone e Chi Ward protegem o grupo. Você não se esquiva, então fica e aguenta."},
		price = "noDodge", spells = {"Mantra of Stone", "Chi Ward", "Iron Palm", "Quaking Stomp"}, cards = "Death",
		gear = {"Fist weapons or bare fists, and armour with health and resistances.", "Armas de punho ou punhos limpos, e armadura com vida e resistências."}},
	ironsage_healing_fist = {
		style = {"A healer that fights. Sanguine Covenant turns your fist hits into health, and Flowing Mercy lets Kindled Breath reach a second ally. You heal yourself and the group while you hit.",
			"Um curandeiro que luta. O Sanguine Covenant transforma seus golpes de punho em vida, e o Flowing Mercy faz o Kindled Breath alcançar um segundo aliado. Você cura a si mesmo e o grupo enquanto bate."},
		price = "lessHealing", spells = {"Kindled Breath", "Iron Palm", "Cleaving Heel", "Tidal Palm"}, cards = "Death",
		gear = {"Fist weapons with a high attack speed: every hit feeds the leech. Armour with health.", "Armas de punho com boa velocidade de ataque: cada golpe alimenta o roubo de vida. Armadura com vida."}},

	-- ------------------------------------------------------------------------------------------------ Necromancer line
	necromancer_grave_caller = {
		style = {"Let the dead fight. Covenant of the Grave makes your minions hit harder and last longer, at the cost of your own spells. Raise Bone Warrior, Bone Archer and Bone Mage, and stay behind them.",
			"Deixe os mortos lutarem. O Covenant of the Grave faz seus lacaios baterem mais forte e durarem mais, ao custo das suas próprias magias. Levante Bone Warrior, Bone Archer e Bone Mage, e fique atrás deles."},
		price = "ownSpellsWeaker", spells = {"Raise Bone Warrior", "Raise Bone Archer", "Raise Bone Mage", "Raise Dead"}, cards = "Death",
		gear = {"A wand or rod, and robes with mana and spirit. You stay behind your minions.", "Uma varinha ou cajado, e vestes com mana e spirit. Você fica atrás dos seus lacaios."}},
	necromancer_death_mage = {
		style = {"Finish the weak, blow up the dead. Reaper's Toll doubles the damage of your hits on monsters that are low on health, and Corpse Detonation makes every kill explode on the monsters around it. Soften the pack, then chain the kills.",
			"Termine os fracos, exploda os mortos. O Reaper's Toll dobra o dano dos seus golpes em monstros com a vida baixa, e o Corpse Detonation faz cada morte explodir nos monstros ao redor. Enfraqueça o bando e depois encadeie as mortes."},
		price = "healthyWeaker", spells = {"Marrow Bolt", "Wraithwind", "Gravewail", "Soulrend Beam"}, cards = "Death",
		gear = {"A wand or rod with death damage, and robes with mana and energy shield.", "Uma varinha ou cajado com dano de morte, e vestes com mana e escudo de energia."}},
	necromancer_grave_effigies = {
		style = {"Let the effigies repeat your area spell. An area spell raises a Cinder Effigy on your tile that casts it again every few seconds. Cast, step away and cast again, with minions to hold the line. A single target gains nothing.",
			"Deixe as efígies repetirem sua magia de área. Ela ergue uma Cinder Effigy no seu quadrado que a lança de novo a cada poucos segundos. Lance, saia de perto e lance outra vez. Um alvo só não ganha nada."},
		price = "effigyCost", spells = {"Grave Nova", "Gravewail", "Crypt Collapse", "Splinter Volley"}, cards = "Fire",
		gear = {"A wand or rod with area damage, and robes with health and energy shield.", "Uma varinha ou cajado com dano de área, e vestes com vida e escudo de energia."}},
	lich_rot_curser = {
		style = {"Curses and slow rot. Hoarded Souls makes your spells hit harder for every empty shade slot, and the rot and curse nodes add damage over time. Start your curses early and keep them running. The first minutes are slow.",
			"Maldições e podridão lenta. O Hoarded Souls faz suas magias baterem mais forte a cada espaço de sombra vazio, e os nós de podridão e maldição somam dano ao longo do tempo. Comece as maldições cedo e mantenha-as ativas."},
		price = "slowStart", spells = {"Withering Curse", "Soul Rot", "Blightbrand", "Wraithwind"}, cards = "Death",
		gear = {"A wand or rod, and robes with mana and spirit.", "Uma varinha ou cajado, e vestes com mana e spirit."}},
	lich_soul_reaper = {
		style = {"Finish the weak, blow up the dead. Reaper's Toll doubles the damage of your hits on monsters that are low on health, and Corpse Detonation makes every kill explode on the monsters around it. Health and resistances let you stay in the pack.",
			"Termine os fracos, exploda os mortos. O Reaper's Toll dobra o dano dos seus golpes em monstros com a vida baixa, e o Corpse Detonation faz cada morte explodir nos monstros ao redor. Vida e resistências deixam você ficar no bando."},
		price = "healthyWeaker", spells = {"Marrow Bolt", "Corpse Explosion", "Gravewail", "Soulrend Beam"}, cards = "Death",
		gear = {"A wand or rod with death damage, and robes with health, mana and energy shield.", "Uma varinha ou cajado com dano de morte, e vestes com vida, mana e escudo de energia."}},
	lich_lifedrinker = {
		style = {"Drink your enemies. Sanguine Covenant returns health from every hit, and Life Siphon does the same on one target. Pick a single monster, siphon it and live off the fight.",
			"Beba seus inimigos. O Sanguine Covenant devolve vida de cada golpe, e o Life Siphon faz o mesmo em um alvo. Escolha um monstro, sugue-o e viva da luta."},
		price = "lessHealing", spells = {"Life Siphon", "Soul Rot", "Marrow Bolt", "Withering Curse"}, cards = "Death",
		gear = {"A wand or rod, and robes with health and mana leech.", "Uma varinha ou cajado, e vestes com vida e roubo de mana."}},
	bonelord_bone_army = {
		style = {"A big army. Bone Colossus makes your Bone Golem hit harder and last longer, and Covenant of the Grave strengthens every other minion. Your own spells are weaker, so let the dead do the work.",
			"Um grande exército. O Bone Colossus faz seu Bone Golem bater mais forte e durar mais, e o Covenant of the Grave fortalece todos os outros lacaios. Suas próprias magias são mais fracas, então deixe os mortos trabalharem."},
		price = "ownSpellsWeaker", spells = {"Bone Golem", "Banner of Bones", "Raise Bone Warrior", "Raise Dead"}, cards = "Death",
		gear = {"A wand or rod, and robes with mana and spirit. You stay behind the army.", "Uma varinha ou cajado, e vestes com mana e spirit. Você fica atrás do exército."}},
	bonelord_bone_warden = {
		style = {"A safe master of the dead. Bone Colossus makes your Bone Golem a real wall, and health and resistances keep you alive behind it. Slow, but hard to kill.",
			"Um mestre seguro dos mortos. O Bone Colossus faz do seu Bone Golem uma muralha de verdade, e vida e resistências mantêm você vivo atrás dele. Lento, mas difícil de matar."},
		price = "lowDamage", spells = {"Bone Golem", "Banner of Bones", "Soulward", "Raise Bone Warrior"}, cards = "Death",
		gear = {"A wand or rod, and robes with health, resistances and spirit.", "Uma varinha ou cajado, e vestes com vida, resistências e spirit."}},
	bonelord_ossuary_fury = {
		style = {"The dead blow up too. Reaper's Toll doubles hits on weak monsters, and Corpse Detonation makes every kill by you or your minions explode. Let the minions soften the pack and the corpses finish it.",
			"Os mortos também explodem. O Reaper's Toll dobra os golpes em monstros fracos, e o Corpse Detonation faz cada morte sua ou dos seus lacaios explodir. Deixe os lacaios enfraquecerem o bando e os cadáveres terminarem."},
		price = "healthyWeaker", spells = {"Ossuary Surge", "Bone Offering", "Crypt Collapse", "Raise Bone Warrior"}, cards = "Death",
		gear = {"A wand or rod with death damage, and robes with mana and energy shield.", "Uma varinha ou cajado com dano de morte, e vestes com mana e escudo de energia."}},

	-- ------------------------------------------------------------------------------------------------ Templar line
	templar_zealot = {
		style = {"Holy light that chains. Dawnchain sends your melee hits on to the nearest other enemies, and Penitent's Wrath answers every hit you take with a holy strike. You pay with weaker spells and a weaker aura.",
			"Luz sagrada que encadeia. O Dawnchain manda seus golpes corpo a corpo para os inimigos mais próximos, e o Penitent's Wrath responde a cada golpe que você leva com um golpe sagrado. Você paga com magias e aura mais fracas."},
		price = "zealotCost", spells = {"Hallowed Cut", "Penitent Lash", "Crusader's Sweep"}, cards = "Death",
		gear = {"A sword and a shield: Dawnchain reads melee hits, and the sword's Tempo suits a chain on one target after another. Heavy armour.",
			"Uma espada e um escudo: o Dawnchain lê golpes corpo a corpo, e o Tempo da espada combina com uma corrente de um alvo após o outro. Armadura pesada."}},
	templar_shield_wall = {
		style = {"No keystone, only walls. A shield, health, resistances and the Templar aura make a Templar who does not fall. There is little damage, so it suits a party that needs someone to stand in front.",
			"Sem keystone, só muralhas. Um escudo, vida, resistências e a aura do Templar fazem um Templar que não cai. O dano é pouco, então serve a um grupo que precisa de alguém na frente."},
		price = "littleDamage", spells = {"Mantle of Dawn", "Vow of Mending", "Consecration", "Sanctified Ground"}, cards = "Death",
		gear = {"A club and a shield: the club's Impact can daze the monster in front of you. The heaviest armour you can find.",
			"Uma clava e um escudo: o Impact da clava pode atordoar o monstro à sua frente. A armadura mais pesada que você achar."}},
	templar_pyre_walker = {
		style = {"Stand in the pack and burn it. Pyre Oath burns every enemy around you while you burn a little yourself, and the defense nodes keep you alive. Poor on a single target.",
			"Fique no bando e queime-o. O Pyre Oath queima todos os inimigos ao seu redor enquanto você queima um pouco, e os nós de defesa mantêm você vivo. Fraco contra um alvo só."},
		price = "pyreCost", spells = {"Consecration", "Censer Swing", "Sanctified Ground", "Vow of Mending"}, cards = "Fire",
		gear = {"A shield and a sword or club, with fire resistance: you burn along with the pack. Heavy armour.",
			"Um escudo e uma espada ou clava, com resistência a fogo: você queima junto com o bando. Armadura pesada."}},
	inquisitor_judge = {
		style = {"Judge the pack. Divine Verdict lets your Radiant Strikes judge their target, so everyone deals more holy damage to it, and Dawnchain chains your hits through the pack. Judgement does the same by hand.",
			"Julgue o bando. O Divine Verdict faz seus Radiant Strikes julgarem o alvo, então todos causam mais dano sagrado nele, e o Dawnchain encadeia seus golpes pelo bando. O Judgement faz o mesmo à mão."},
		price = "spellsWeaker", spells = {"Judgement", "Purging Nova", "Penitent Lash", "Zealot's Wrath"}, cards = "Fire",
		gear = {"A sword and a shield: both keystones read melee hits. Heavy armour.",
			"Uma espada e um escudo: as duas keystones leem golpes corpo a corpo. Armadura pesada."}},
	inquisitor_ember_brand = {
		style = {"Brand one, burn the rest. Sigil of Cinders brands a single target; the brand burns the monsters beside it and jumps on when its bearer dies. Fire and holy spells ignite. Pick a target, brand it and cast.",
			"Marque um, queime o resto. O Sigil of Cinders marca um alvo; a marca queima os monstros ao lado dele e salta adiante quando o portador morre. Magias de fogo e sagradas incendeiam. Escolha um alvo, marque e lance."},
		price = "notFireHoly", spells = {"Heretic's Brand", "Bell of Reckoning", "Pyre of Absolution", "Zealot's Wrath"}, cards = "Fire",
		gear = {"A sword or club, and gear of fire or holy damage: anything that is not fire or holy is weaker. Medium armour with health.",
			"Uma espada ou clava, e equipamento de dano de fogo ou sagrado: o que não é fogo nem sagrado fica mais fraco. Armadura média com vida."}},
	inquisitor_rebuker = {
		style = {"A shield that strikes back. Radiant Rebuke blocks some attacks completely, and each block sends a holy nova at the monsters around you. Stand in front, hold a shield and let them hit you.",
			"Um escudo que revida. O Radiant Rebuke bloqueia alguns ataques por completo, e cada bloqueio manda uma nova sagrada nos monstros ao seu redor. Fique na frente, segure um escudo e deixe que batam em você."},
		price = "weaponHitsWeaker", spells = {"Mantle of Dawn", "Vow of Mending", "Zealot's Wrath", "Purging Nova"}, cards = "Death",
		gear = {"A club and a shield: Radiant Rebuke needs the shield and the club can daze. Heavy armour with magic level.",
			"Uma clava e um escudo: o Radiant Rebuke exige o escudo e a clava pode atordoar. Armadura pesada com magic level."}},
	sentinel_bastion = {
		style = {"The wall of the party. Bastion widens your aura and lets Aegis of Faith cover the party members under it. Stand between your friends and the monsters. Very little damage of your own.",
			"A muralha do grupo. O Bastion alarga sua aura e faz o Aegis of Faith cobrir os membros do grupo sob ela. Fique entre seus amigos e os monstros. Muito pouco dano próprio."},
		price = "littleDamage", spells = {"Aegis of Faith", "Rebuke", "Shield Wave", "Rampart Quake"}, cards = "Death",
		gear = {"A club and a shield, in the heaviest armour: the club can daze the monster in front of you.", "Uma clava e um escudo, na armadura mais pesada: a clava pode atordoar o monstro à sua frente."}},
	sentinel_reliquary_keeper = {
		style = {"A warden for the party. Reliquary Vow sends a Reliquary Warden after you that heals and buffs the group and burns enemies. Walk with your party and let the warden work.",
			"Um guardião para o grupo. O Reliquary Vow manda um Reliquary Warden atrás de você que cura e fortalece o grupo e queima inimigos. Ande com o grupo e deixe o guardião trabalhar."},
		price = "ownDamageWeaker", spells = {"Lay on Hands", "Vow of Mending", "Aegis of Faith", "Mantle of Dawn"}, cards = "Death",
		gear = {"A sword or club and a shield, with magic level on your armour: the warden heals better for it.", "Uma espada ou clava e um escudo, com magic level na armadura: o guardião cura melhor assim."}},
	sentinel_retributor = {
		style = {"Make them pay. Thorns, Thornbound Oath and Penitent's Wrath send damage back at everyone who hits you, in melee or at range. Hold a shield, take the hits and let the monsters kill themselves.",
			"Faça-os pagar. O Thorns, o Thornbound Oath e o Penitent's Wrath devolvem dano a todo mundo que bate em você, de perto ou de longe. Segure um escudo, aguente os golpes e deixe os monstros se matarem."},
		price = "retributorCost", spells = {"Rebuke", "Aegis of Faith", "Bulwark Slam", "Rampart Quake"}, cards = "Death",
		gear = {"A club and a shield, with reflect on your gear: the club can daze. The heaviest armour you can find.", "Uma clava e um escudo, com reflexão no equipamento: a clava pode atordoar. A armadura mais pesada que você achar."}}
}

return S
