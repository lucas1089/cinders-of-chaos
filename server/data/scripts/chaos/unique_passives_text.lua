-- unique_passives_text.lua: the tooltip line of every unique passive family, English and pt-BR (O278). Each function
-- builds the sentence from the merged entry (family defaults + the item's own numbers), so a number changed in
-- unique_passives_config.lua changes the line too (tools/gen_unique_specs.py writes it into the unique's description).
-- `i` is 1 for English and 2 for pt-BR. The numbers must come in the same order in both languages (the Codex looks the
-- pt-BR line up by its English text with the numbers as %s; tests/unique_passives_test.lua checks every unique).

ChaosUniquePassivesText = {}
local T = ChaosUniquePassivesText

T.elem = {
	physical = {"physical", "físico"}, fire = {"fire", "fogo"}, ice = {"ice", "gelo"}, energy = {"energy", "energia"},
	earth = {"earth", "terra"}, poison = {"poison", "veneno"}, death = {"death", "morte"}, holy = {"holy", "sagrado"},
	drown = {"drowning", "afogamento"}, bleed = {"bleeding", "sangramento"},
}
T.lineName = {
	warrior = {"Warrior", "Guerreiro"}, ranger = {"Ranger", "Ranger"}, mystic = {"Mystic", "Místico"},
	thief = {"Thief", "Gatuno"}, necromancer = {"Necromancer", "Necromante"}, monk = {"Monk", "Monge"},
	templar = {"Templar", "Templário"},
}

local function el(e, key, i)
	local v = T.elem[e[key or "elem"]]
	return v and v[i] or tostring(e[key or "elem"])
end
local function pick(i, en, pt)
	return i == 1 and en or pt
end
-- a sentence only when `n` is set (a price of 0 is left out)
local function opt(n, en, pt, i)
	if n and n > 0 then
		return (i == 1 and en or pt)
	end
	return ""
end
local STAT = {
	maxMana = {"maximum mana", "mana máxima"}, maxHealth = {"maximum health", "vida máxima"},
	magicLevel = {"magic level", "nível mágico"}, speed = {"speed", "velocidade"},
	shield = {"shielding skill", "escudo"}, level = {"level", "nível"},
}
local ORIGIN = {
	any = {"hits", "golpes"}, melee = {"melee hits", "golpes corpo a corpo"}, ranged = {"ranged hits", "golpes à distância"},
	spell = {"spells", "magias"},
}
local KIND = {
	fire = {"burning", "queimadura"}, poison = {"poison", "veneno"}, bleed = {"bleeding", "sangramento"},
	energy = {"energy damage over time", "dano de energia contínuo"}, ice = {"freezing", "congelamento"},
	drown = {"drowning", "afogamento"}, death = {"death damage over time", "dano de morte contínuo"},
}
local function f(x)
	return (tostring(x):gsub("%.0$", ""))
end

-- O473: the "more damage" part of a passive is raw percent of the one additive damage pool: at most `each` for one passive, `cap` for
-- all (damage_pool_config.lua sources.uniques). The sentences say "increased damage" and name the cap.
local function poolNumbers()
	local c = rawget(_G, "ChaosDamagePoolConfig")
	if not c and dofile then
		local ok, loaded = pcall(dofile, "data/scripts/chaos/damage_pool_config.lua")
		c = ok and loaded or nil
	end
	local u = c and c.sources and c.sources.uniques
	return u and u.each or 10, u and u.cap or 40
end
-- "+10% increased damage (at most 10 for one unique power, 40 for all)" for a bonus of `v` percent
local function inc(v, i)
	local each, cap = poolNumbers()
	return pick(i, string.format("+%s%% increased damage (at most %s for one unique power, %s for all)", f(math.min(v, each)), f(each), f(cap)),
		string.format("+%s%% de dano aumentado (no máximo %s por poder único, %s no total)", f(math.min(v, each)), f(each), f(cap)))
end

T.family = {}
local F = T.family

function F.convert(e, _, i)
	return pick(i, string.format("%s%% of your physical damage is dealt as %s and deals %s%% more. Other elements deal %s%% less.",
		f(e.share), el(e, "elem", 1), f(e.bonus), f(e.other)),
		string.format("%s%% do seu dano físico é causado como %s e causa %s%% a mais. Outros elementos causam %s%% a menos.",
		f(e.share), el(e, "elem", 2), f(e.bonus), f(e.other)))
end

function F.lowlife(e, _, i)
	return pick(i, string.format("Below %s%% health you deal %s.", f(e.at), inc(e.bonus, 1)),
		string.format("Abaixo de %s%% de vida você causa %s.", f(e.at), inc(e.bonus, 2)))
		.. (e.malus > 0 and pick(i, string.format(" Above %s%% health you deal %s%% less.", f(e.malusAt), f(e.malus)),
		string.format(" Acima de %s%% de vida você causa %s%% a menos.", f(e.malusAt), f(e.malus))) or "")
end

function F.overflow(e, _, i)
	return pick(i, string.format("At %s%% mana or more you deal %s.", f(e.at), inc(e.bonus, 1)),
		string.format("Com %s%% de mana ou mais você causa %s.", f(e.at), inc(e.bonus, 2)))
		.. (e.malus > 0 and pick(i, string.format(" At %s%% mana or less you deal %s%% less.", f(e.malusAt), f(e.malus)),
		string.format(" Com %s%% de mana ou menos você causa %s%% a menos.", f(e.malusAt), f(e.malus))) or "")
end

function F.opener(e, _, i)
	if e.side == "above" then
		return pick(i, string.format("Against targets at %s%% health or more you deal %s.", f(e.at), inc(e.bonus, 1)),
			string.format("Contra alvos com %s%% de vida ou mais você causa %s.", f(e.at), inc(e.bonus, 2)))
			.. (e.malus > 0 and pick(i, string.format(" Targets at %s%% or less take %s%% less.", f(e.malusAt), f(e.malus)),
			string.format(" Alvos com %s%% ou menos sofrem %s%% a menos.", f(e.malusAt), f(e.malus))) or "")
	end
	return pick(i, string.format("Against targets at %s%% health or less you deal %s.", f(e.at), inc(e.bonus, 1)),
		string.format("Contra alvos com %s%% de vida ou menos você causa %s.", f(e.at), inc(e.bonus, 2)))
		.. (e.malus > 0 and pick(i, string.format(" Targets at %s%% or more take %s%% less.", f(e.malusAt), f(e.malus)),
		string.format(" Alvos com %s%% ou mais sofrem %s%% a menos.", f(e.malusAt), f(e.malus))) or "")
end

function F.focus(e, _, i)
	return pick(i, string.format("Each hit in a row on one target adds %s%% increased damage, up to %s hits, %s. The first hit on a new target deals %s%% less.",
		f(e.perStack), f(e.max), inc(e.perStack * e.max, 1), f(e.first)),
		string.format("Cada golpe seguido no mesmo alvo soma %s%% de dano aumentado, até %s golpes, %s. O primeiro golpe em um alvo novo causa %s%% a menos.",
		f(e.perStack), f(e.max), inc(e.perStack * e.max, 2), f(e.first)))
end

function F.statscale(e, _, i)
	local s, o = STAT[e.stat] or {e.stat, e.stat}, ORIGIN[e.origin] or ORIGIN.any
	return pick(i, string.format("Your %s deal %s%% increased damage per %s %s%s, up to %s%%: %s.", o[1], f(e.bonusPer), f(e.per), s[1],
		e.from > 0 and (" above " .. f(e.from)) or "", f(e.cap), inc(e.cap, 1)),
		string.format("Seus %s causam %s%% de dano aumentado a cada %s de %s%s, até %s%%: %s.", o[2], f(e.bonusPer), f(e.per), s[2],
		e.from > 0 and (" acima de " .. f(e.from)) or "", f(e.cap), inc(e.cap, 2)))
end

function F.critrule(e, _, i)
	return pick(i, string.format("Critical hits deal %s%% more damage. Other hits deal %s%% less.", f(e.crit), f(e.plain)),
		string.format("Golpes críticos causam %s%% a mais de dano. Outros golpes causam %s%% a menos.", f(e.crit), f(e.plain)))
		.. opt(e.heal, string.format(" A critical hit heals %s%% of its damage.", f(e.heal)),
		string.format(" Um golpe crítico cura %s%% do seu dano.", f(e.heal)), i)
end

function F.crowd(e, _, i)
	if e.mode == "pack" then
		return pick(i, string.format("You deal %s%% increased damage per other monster within %s tiles, up to %s, %s. Alone you deal %s%% less.",
			f(e.per), f(e.radius), f(e.max), inc(e.per * e.max, 1), f(e.alone)),
			string.format("Você causa %s%% de dano aumentado por outro monstro a %s passos, até %s, %s. Sozinho você causa %s%% a menos.",
			f(e.per), f(e.radius), f(e.max), inc(e.per * e.max, 2), f(e.alone)))
	end
	return pick(i, string.format("Against one target alone you deal %s. Among %s or more monsters you deal %s%% less.",
		inc(e.bonus, 1), f(e.many), f(e.malus)),
		string.format("Contra um único alvo você causa %s. Entre %s ou mais monstros você causa %s%% a menos.",
		inc(e.bonus, 2), f(e.many), f(e.malus)))
end

function F.extra(e, _, i)
	local o = ORIGIN[e.origin] or ORIGIN.any
	local cost = ""
	if e.cost == "health" then
		cost = pick(i, string.format(" Costs %s%% health, never below %s%%.", f(e.costPct), f(e.minHealth)),
			string.format(" Custa %s%% de vida, nunca abaixo de %s%%.", f(e.costPct), f(e.minHealth)))
	elseif e.cost == "mana" then
		cost = pick(i, string.format(" Costs %s%% mana.", f(e.costPct)), string.format(" Custa %s%% de mana.", f(e.costPct)))
	end
	return pick(i, string.format("Your %s send %s%% of their damage at %s more monsters within %s tiles of the target.",
		o[1], f(e.pct), f(e.targets), f(e.radius)),
		string.format("Seus %s enviam %s%% do dano a mais %s monstros a %s passos do alvo.", o[2], f(e.pct), f(e.targets), f(e.radius)))
		.. cost
end

function F.ward(e, _, i)
	return pick(i, string.format("%s%% of the damage you deal and %s%% of your health per kill become a ward, up to %s%% of your health. It absorbs damage and fades after %s s.",
		f(e.onHit), f(e.onKill), f(e.cap), f(e.decayAfterMs / 1000)),
		string.format("%s%% do dano que você causa e %s%% da sua vida por morte viram uma proteção, até %s%% da sua vida. Ela absorve dano e some após %s s.",
		f(e.onHit), f(e.onKill), f(e.cap), f(e.decayAfterMs / 1000)))
		.. opt(e.reflect, string.format(" %s%% of what it absorbs is dealt back.", f(e.reflect)),
		string.format(" %s%% do que ela absorve volta ao atacante.", f(e.reflect)), i)
		.. opt(e.healLess, string.format(" Healing on you is %s%% lower.", f(e.healLess)),
		string.format(" A cura que você recebe é %s%% menor.", f(e.healLess)), i)
end

function F.spread(e, _, i)
	return pick(i, string.format("A monster that dies with your %s damage on it passes it to %s monsters within %s tiles: %s%% of the last tick for %s ticks.",
		el(e, "elem", 1), f(e.targets), f(e.radius), f(e.share), f(e.ticks)),
		string.format("Um monstro que morre com seu dano de %s passa o efeito a %s monstros a %s passos: %s%% do último golpe por %s vezes.",
		el(e, "elem", 2), f(e.targets), f(e.radius), f(e.share), f(e.ticks)))
		.. opt(e.dealtLess, string.format(" Your direct hits deal %s%% less.", f(e.dealtLess)),
		string.format(" Seus golpes diretos causam %s%% a menos.", f(e.dealtLess)), i)
end

function F.stacks(e, _, i)
	local trig = e.trigger == "crit" and pick(i, "critical hit", "golpe crítico") or pick(i, "kill", "morte")
	return pick(i, string.format("Each %s adds a stack for %s s, up to %s: %s%% increased damage dealt per stack, %s.",
		trig, f(e.windowMs / 1000), f(e.max), f(e.perStack), inc(e.perStack * e.max, 1)),
		string.format("Cada %s dá um acúmulo por %s s, até %s: %s%% de dano aumentado causado por acúmulo, %s.",
		trig, f(e.windowMs / 1000), f(e.max), f(e.perStack), inc(e.perStack * e.max, 2)))
		.. opt(e.takenPerStack, string.format(" Each stack also adds %s%% damage taken.", f(e.takenPerStack)),
		string.format(" Cada acúmulo também soma %s%% de dano recebido.", f(e.takenPerStack)), i)
end

function F.feast(e, _, i)
	local r = e.res == "mana" and pick(i, "mana", "mana") or pick(i, "health", "vida")
	return pick(i, string.format("Each kill restores %s%% of your maximum %s, at most %s%% per second.", f(e.onKill), r, f(e.capPerSec)),
		string.format("Cada morte restaura %s%% da sua %s máxima, no máximo %s%% por segundo.", f(e.onKill), r, f(e.capPerSec)))
		.. opt(e.healLess, string.format(" Healing on you is %s%% lower.", f(e.healLess)),
		string.format(" A cura que você recebe é %s%% menor.", f(e.healLess)), i)
end

function F.hitcap(e, _, i)
	return pick(i, string.format("A single hit from a monster takes at most %s%% of your maximum health.", f(e.cap)),
		string.format("Um único golpe de monstro tira no máximo %s%% da sua vida máxima.", f(e.cap)))
		.. opt(e.healLess, string.format(" Healing on you is %s%% lower.", f(e.healLess)),
		string.format(" A cura que você recebe é %s%% menor.", f(e.healLess)), i)
end

function F.immunity(e, _, i)
	local k = KIND[e.kind] or {e.kind, e.kind}
	return pick(i, string.format("Immune to %s. Direct %s damage you take is %s%% higher.", k[1], el(e, "kind", 1), f(e.more)),
		string.format("Imune a %s. O dano direto de %s que você recebe é %s%% maior.", k[2], el(e, "kind", 2), f(e.more)))
end

function F.riposte(e, _, i)
	return pick(i, string.format("A monster hit of %s%% of your health or more is answered with %s%% of it as %s damage, every %s s.",
		f(e.minHit), f(e.pct), el(e, "elem", 1), f(e.icdMs / 1000)),
		string.format("Um golpe de monstro de %s%% da sua vida ou mais é respondido com %s%% dele como dano de %s, a cada %s s.",
		f(e.minHit), f(e.pct), el(e, "elem", 2), f(e.icdMs / 1000)))
end

function F.panic(e, _, i)
	return pick(i, string.format("A hit that leaves you under %s%% health makes you take %s%% less damage for %s s, but blocks your healing meanwhile. Once per %s s.",
		f(e.below), f(e.reduce), f(e.ms / 1000), f(e.icdMs / 1000)),
		string.format("Um golpe que deixa você abaixo de %s%% de vida faz você receber %s%% a menos de dano por %s s, mas bloqueia sua cura nesse tempo. Uma vez a cada %s s.",
		f(e.below), f(e.reduce), f(e.ms / 1000), f(e.icdMs / 1000)))
end

function F.manashield(e, _, i)
	return pick(i, string.format("%s%% of the damage monsters deal is paid from your mana instead, never below %s%% mana.",
		f(e.share), f(e.reserve)),
		string.format("%s%% do dano dos monstros é pago com sua mana, nunca abaixo de %s%% de mana.", f(e.share), f(e.reserve)))
		.. opt(e.dealtLess, string.format(" Your direct hits deal %s%% less.", f(e.dealtLess)),
		string.format(" Seus golpes diretos causam %s%% a menos.", f(e.dealtLess)), i)
end

function F.mend(e, _, i)
	return pick(i, string.format("While you fight, you and your party within %s tiles heal %s%% of their health every %s s.",
		f(e.radius), f(e.heal), f(e.tickMs / 1000)),
		string.format("Enquanto você luta, você e seu grupo a %s passos curam %s%% da vida a cada %s s.",
		f(e.radius), f(e.heal), f(e.tickMs / 1000)))
		.. opt(e.healLess, string.format(" Other healing on you is %s%% lower.", f(e.healLess)),
		string.format(" Outra cura que você recebe é %s%% menor.", f(e.healLess)), i)
end

function F.mark(e, _, i)
	return pick(i, string.format("Your hits mark the target for %s s, up to %s at once. Against marked monsters you deal %s.",
		f(e.ms / 1000), f(e.max), inc(e.bonus, 1)),
		string.format("Seus golpes marcam o alvo por %s s, até %s ao mesmo tempo. Contra monstros marcados você causa %s.",
		f(e.ms / 1000), f(e.max), inc(e.bonus, 2)))
		.. opt(e.unmarked, string.format(" Others take %s%% less.", f(e.unmarked)),
		string.format(" Os demais sofrem %s%% a menos.", f(e.unmarked)), i)
end

function F.nova(e, _, i)
	local on = pick(i, e.on == "kill" and "a kill" or (e.on == "crit" and "a critical hit" or "a monster hit of " .. f(e.minHit) .. "% of your health or more"),
		e.on == "kill" and "uma morte" or (e.on == "crit" and "um golpe crítico" or "um golpe de monstro de " .. f(e.minHit) .. "% da sua vida ou mais"))
	return pick(i, string.format("On %s, a %s nova hits up to %s monsters within %s tiles for %s plus %s per level, every %s s.",
		on, el(e, "elem", 1), f(e.targets), f(e.radius), f(e.base), f(e.perLevel), f(e.icdMs / 1000)),
		string.format("Em %s, uma nova de %s atinge até %s monstros a %s passos com %s mais %s por nível, a cada %s s.",
		on, el(e, "elem", 2), f(e.targets), f(e.radius), f(e.base), f(e.perLevel), f(e.icdMs / 1000)))
		.. opt(e.selfCost, string.format(" Costs %s%% health, never below %s%%.", f(e.selfCost), f(e.minHealth)),
		string.format(" Custa %s%% de vida, nunca abaixo de %s%%.", f(e.selfCost), f(e.minHealth)), i)
end

function F.minionPact(e, _, i)
	return pick(i, string.format("Your minions deal %s%% more damage and have %s%% more health. Your own spells deal %s%% less.",
		f(e.hit), f(e.health), f(e.own)),
		string.format("Seus lacaios causam %s%% a mais de dano e têm %s%% a mais de vida. Suas próprias magias causam %s%% a menos.",
		f(e.hit), f(e.health), f(e.own)))
end

return ChaosUniquePassivesText
