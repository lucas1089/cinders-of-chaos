-- The hand-written part of the beginner guide (O373; tools/gen_guide_data.lua). The cards themselves are the "How it works"
-- cards (tools/howitworks_config.lua, built by tools/gen_howitworks_data.lua); the levels come from unlocks_config.lua.
-- This file only says the ORDER for a new player and gives each first step one short tip. No number is typed here.
-- Read by the generator for two files: the client's help search (game_helpsearch/helpsearch_data.lua: the first steps are
-- what the window shows before the player types) and the website's beginner guide (plugins/chaos/guide/guide_data.json).
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible, no engine calls. Wording: plain short sentences, no other game named.

local G = {}

-- the top of the website page and of the empty help search
G.intro = {
	en = "New here? Start with these steps. Each one is a window of the game; the rest of the guide follows the level where each feature opens.",
	pt = "Chegou agora? Comece por estes passos. Cada um é uma janela do jogo; o resto do guia segue o nível em que cada recurso abre."
}

-- the first steps, in order: a card key of the How it works data and a tip {en, pt}
G.steps = {
	{card = "goals", tip = {"Lost? Open it first: it shows what to do at your level.",
		"Perdido? Abra primeiro: mostra o que fazer no seu nível."}},
	{card = "spellbook", tip = {"See your spells and put the ones you use on your hotkeys.",
		"Veja suas magias e coloque as que usa nos seus atalhos."}},
	{card = "passive", tip = {"Spend each new point here. Start next to the centre.",
		"Gaste cada ponto novo aqui. Comece perto do centro."}},
	{card = "townportal", tip = {"Your way back to town from any hunt.",
		"Seu caminho de volta para a cidade de qualquer caçada."}},
	{card = "bounty", tip = {"Take a contract before you hunt: gold and orbs for the same kills.",
		"Pegue um contrato antes de caçar: ouro e orbes pelas mesmas mortes."}},
	{card = "daily", tip = {"Claim it every day; a streak pays more.",
		"Pegue todo dia; uma sequência paga mais."}},
	{card = "autoloot", tip = {"Let the loot you want go into your backpack by itself.",
		"Deixe o saque que você quer ir sozinho para a mochila."}},
	{card = "lootfilter", tip = {"Make the good drops stand out on the ground.",
		"Faça os drops bons se destacarem no chão."}},
	{card = "stash", tip = {"Keep your items here, not in your backpack.",
		"Guarde seus itens aqui, não na mochila."}},
	{card = "partyfinder", tip = {"Hunting is faster in a party. Find one here.",
		"Caçar em grupo é mais rápido. Encontre um aqui."}},
	{card = "mentor", tip = {"A veteran can help you and you both gain from it.",
		"Um veterano pode ajudar você e os dois ganham com isso."}},
	{card = "codex", tip = {"Every rule of items, orbs and gems, with a search.",
		"Todas as regras de itens, orbes e gemas, com busca."}}
}

-- extra search words of a card for the client's help search {en, pt}: the words a new player types for it that the card's
-- own text does not hold. Matched below the title and above the text (game_helpsearch/helpcore.lua).
G.words = {
	goals = {"level up leveling what next where to hunt", "subir de nível upar o que fazer onde caçar"},
	passive = {"points build talents starter builds recommended auto build import code mastery spell modifier", "pontos build talentos builds iniciais recomendadas auto build importar código maestria modificador de magia"},
	spellbook = {"spells attack hotkeys", "magias feitiços ataque atalhos"},
	spelldamage = {"spell damage scaling magic level skill weapon attack level modifiers passive tree support runes cards charms uniques sets how strong",
		"dano das magias escala nível mágico magic level skill arma ataque nível modificadores árvore passiva runas de suporte cartas charms únicos conjuntos quão forte"},
	townportal = {"town city temple go back", "cidade templo voltar"},
	stash = {"storage depot items", "depósito guardar itens"},
	crafting = {"orbs upgrade gear modifiers gems", "orbes melhorar equipamento modificadores gemas"},
	codex = {"orbs gems modifiers rules uniques", "orbes gemas modificadores regras únicos"},
	bounty = {"contracts tasks gold orbs", "contratos tarefas ouro orbes"},
	daily = {"login reward streak", "recompensa login sequência"},
	partyfinder = {"group party team", "grupo time"},
	market = {"sell buy trade gold", "vender comprar trocar ouro"},
	shop = {"coins buy premium", "moedas comprar"},
	autoloot = {"loot pick up", "saque pegar"},
	lootfilter = {"loot drops colours", "saque drops cores"},
	tower = {"orbs floors", "orbes andares"},
	arena = {"pvp orbs", "pvp orbes"},
	mentor = {"help new player", "ajuda jogador novo"}
}

-- the headings of the website page (the client has its own tr() texts)
G.headings = {
	steps = {en = "First steps", pt = "Primeiros passos"},
	levels = {en = "As you level up", pt = "Conforme você sobe de nível"},
	anytime = {en = "Any level", pt = "Qualquer nível"},
	rows = {
		what = {en = "What it is", pt = "O que é"},
		who = {en = "Who is it for", pt = "Para quem é"},
		levels = {en = "Monster levels", pt = "Níveis dos monstros"},
		drops = {en = "What drops", pt = "O que cai"},
		death = {en = "If you die", pt = "Se você morrer"},
		often = {en = "How often", pt = "Quantas vezes"}
	}
}

return G
