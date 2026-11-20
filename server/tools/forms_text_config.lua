-- The plain English sentence of every Form kind (O686 phase 4), for the client's Form picker (phase 5). tools/gen_forms_data.lua writes it
-- into client/overlay/modules/game_spellranks/forms_data.lua with the numbers of the kind (spell_forms_core.lua `numbers`, a forms.csv
-- row's overrides applied): {name} is a key of the kind's numbers, {sec} is `ms` in seconds, {ticksSec} is `ticks` x `every` in seconds.
-- The pt-BR sentence of each is below (same {names}); pt_br.lua holds the English sentence as a key with that text ("Run-time keys" of
-- game_spellranks); the generator's --check fails when it is missing or differs. Plain words, no names of other games. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
local en = {
	SPLIT = "The hit splits into {count} hits of {pct}% on the nearest enemies in {radius} sqm.",
	CHAIN = "The hit is {main}% and jumps to 2 more enemies within {radius} sqm for {pct1}% and {pct2}% of it.",
	PIERCE = "The hit goes through along the line: {pct}% on each of up to {count} enemies behind the target.",
	REND = "{main}% of the hit now, {dot}% more as damage over {ticks} seconds.",
	DELAY = "No hit now. A marked burst lands after {sec} seconds for {pct}% of the hit, with a warning circle.",
	PULL = "Enemies in the area are pulled to within {pullTo} sqm of the centre; the hit is {main}%.",
	GROUND = "The area leaves ground for {seconds} seconds: enemies in it take {pct}% of the hit a second.",
	ECHO = "The hit is {main}%, and a second hit of {pct}% lands on the same place after {sec} second.",
	SHIFT = "The spell changes element, with a status of that element worth {pct}% of the hit over {ticks} seconds.",
	TWIN = "The first cast is {main}%; a second cast {sec} seconds later hits for {pct}%, no extra mana. The cooldown starts after it.",
	CASCADE = "A kill by the spell gives a free hit of {pct}% on the nearest enemy, once per cast.",
	AFTERMATH = "When the spell ends, a burst of {pct}% of the hit lands where it was.",
	OVERCHARGE = "{sec} seconds of cast delay with a warning circle, then {pct}% of the hit.",
	SIPHON = "Heals {heal}% of the damage done (at most {healCap}% of your health a cast) and returns {mana}% of it as mana.",
	SEEK = "The spell picks the weakest enemy in reach and ignores cover; the hit is {pct}%.",
	SPREAD = "A status of the spell jumps to up to {count} enemies within {radius} sqm for {pct}% of the hit over {ticks} seconds.",
	ASCEND = "A second conversion: the spell changes element, with a stronger status; the hit is {hit}%.",
	RIPPLE = "The heal is {main}% and jumps to {count} allies for {pct}% of it.",
	BLOOM = "{main}% of the heal now, {over}% more over {ticks} seconds.",
	WARD = "A heal that goes over full health becomes a shield of at most {cap}% of max health.",
	PULSE = "The heal is {main}%, and {pct}% of it also heals up to {count} allies within {radius} sqm.",
	SECONDWIND = "A target under {below}% health gets {pct}% more heal, and the cooldown is cut {cdcut}%.",
	LINK = "After {sec} seconds a second heal of {pct}% lands if the target is under {below}% health.",
	SANCTUARY = "A ground for {seconds} seconds that heals {pct}% of the heal a second.",
	CLEANSE = "Removes one debuff and gives a shield of {shield}% of the heal.",
}

local pt = {
	SPLIT = "O golpe se divide em {count} golpes de {pct}% nos inimigos mais próximos em {radius} sqm.",
	CHAIN = "O golpe é de {main}% e salta para mais 2 inimigos em até {radius} sqm com {pct1}% e {pct2}% dele.",
	PIERCE = "O golpe atravessa em linha: {pct}% em cada um de até {count} inimigos atrás do alvo.",
	REND = "{main}% do golpe agora, mais {dot}% como dano ao longo de {ticks} segundos.",
	DELAY = "Sem golpe agora. Uma explosão marcada cai depois de {sec} segundos com {pct}% do golpe, com um círculo de aviso.",
	PULL = "Os inimigos na área são puxados para até {pullTo} sqm do centro; o golpe é de {main}%.",
	GROUND = "A área deixa o chão marcado por {seconds} segundos: quem está nele leva {pct}% do golpe por segundo.",
	ECHO = "O golpe é de {main}%, e um segundo golpe de {pct}% cai no mesmo lugar depois de {sec} segundo.",
	SHIFT = "A magia muda de elemento, com um status desse elemento que vale {pct}% do golpe em {ticks} segundos.",
	TWIN = "A primeira conjuração é de {main}%; uma segunda, {sec} segundos depois, acerta com {pct}%, sem mana extra. O recarregamento começa depois dela.",
	CASCADE = "Uma morte causada pela magia dá um golpe grátis de {pct}% no inimigo mais próximo, uma vez por conjuração.",
	AFTERMATH = "Quando a magia termina, uma explosão de {pct}% do golpe cai onde ela estava.",
	OVERCHARGE = "{sec} segundos de atraso na conjuração com um círculo de aviso, depois {pct}% do golpe.",
	SIPHON = "Cura {heal}% do dano causado (no máximo {healCap}% da sua vida por conjuração) e devolve {mana}% dele como mana.",
	SEEK = "A magia escolhe o inimigo mais fraco ao alcance e ignora obstáculos; o golpe é de {pct}%.",
	SPREAD = "Um status da magia salta para até {count} inimigos em {radius} sqm com {pct}% do golpe em {ticks} segundos.",
	ASCEND = "Uma segunda conversão: a magia muda de elemento, com um status mais forte; o golpe é de {hit}%.",
	RIPPLE = "A cura é de {main}% e salta para {count} aliados com {pct}% dela.",
	BLOOM = "{main}% da cura agora, mais {over}% ao longo de {ticks} segundos.",
	WARD = "Uma cura que passa da vida cheia vira um escudo de no máximo {cap}% da vida máxima.",
	PULSE = "A cura é de {main}%, e {pct}% dela também cura até {count} aliados em {radius} sqm.",
	SECONDWIND = "Um alvo com menos de {below}% de vida recebe {pct}% a mais de cura, e o recarregamento cai {cdcut}%.",
	LINK = "Depois de {sec} segundos, uma segunda cura de {pct}% cai se o alvo estiver com menos de {below}% de vida.",
	SANCTUARY = "Um chão por {seconds} segundos que cura {pct}% da cura por segundo.",
	CLEANSE = "Remove um efeito negativo e dá um escudo de {shield}% da cura.",
}

-- the pt-BR of spell_forms_core.lua `utility` (the English is the core's)
local ptUtility = {
	PULL = "controle: os inimigos na área são puxados para perto",
	SIPHON = "sustento: vida e mana a partir do dano",
	SEEK = "mira: o inimigo mais fraco ao alcance, mesmo atrás de obstáculos",
	CLEANSE = "purificação: um efeito negativo removido e um escudo",
	WARD = "segurança: uma cura em excesso vira um escudo",
	SECONDWIND = "segurança: uma cura mais forte e um recarregamento menor para um alvo com pouca vida",
	LINK = "segurança: uma segunda cura para um alvo com pouca vida",
	SHIFT = "elemento: a magia muda de elemento, com um status",
	ASCEND = "elemento: uma segunda conversão, com um status mais forte",
}

return {en = en, pt = pt, ptUtility = ptUtility}
