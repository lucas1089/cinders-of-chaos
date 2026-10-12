-- Vocation Trials: the special nodes of every vocation (trials_core.lua reads this; design and the full table in
-- TRIALS.md). Returned as {[vocation id] = {pair1, pair2, pair3}}, a pair = {a, b}, a node = {name, fx, cost}.
--
--   pair 1 is unlocked by clearing the vocation's trial on Normal, pair 2 on Cruel, pair 3 on Merciless; a character
--   holds one node of each unlocked pair (a "choice"), never both.
--   fx    what the node gives; cost   what it takes (the trade-off). Both are summed into the passive bonus table
--         under these keys (trials_core.lua KEYS says what each key means, its unit and which sign is good).
--         A cost uses the bad sign of a key (+ damage taken, - damage dealt, ...). Keys of the passive tree
--         (criticalHitChance, vitality, absorbX ...) are positive and applied by passivetree_effects.lua; the others
--         (deal*, take*, echo*, nova*, kill*, leech*, ...) are applied by trials_effects.lua.
--   Keys that need the spell events of engine patch 0008 (spellCost, spellCd) are marked by the core
--   (ChaosTrialsCore.needsSpellEvents); without the patch the node still works but that part does nothing.
-- Numbers are first-pass balance: see TRIALS.md "Balance caveats".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible; no engine calls.

local function n(name, fx, cost, lore)
	return {name = name, fx = fx, cost = cost or {}, lore = lore}
end

local STACK = function(pct, max, ms)
	return {killStackPct = pct, killStackMax = max, killStackMs = ms}
end
local ECHO = function(chance, pct)
	return {echoChance = chance, echoPct = pct}
end
local NOVA = function(chance, pct, radius)
	return {novaChance = chance, novaPct = pct, novaRadius = radius or 2}
end
local function merge(...)
	local out = {}
	for _, t in ipairs({...}) do
		for k, v in pairs(t) do
			out[k] = v
		end
	end
	return out
end

return {
	-- ------------------------------------------------------------------ Warrior line
	[4] = { -- Warrior
		{n("Reckless Blows", {dealMelee = 15}, {takeAll = 6}, "Swing first, bleed later."),
			n("Steady Guard", {takeMelee = -12}, {dealMelee = -6}, "A wall does not hurry.")},
		{n("Second Wind", {killHeal = 2.5}, {takeMelee = 6}, "Every felled foe is a breath of air."),
			n("Iron Hide", {absorbPhysical = 6}, {dealAll = -5}, "Scars that turn the next blade.")},
		{n("Warlord's Rage", STACK(3, 8, 8000), {takeAll = 8}, "The more that fall, the louder you roar."),
			n("Last Bastion", {lastStandCd = 90}, {dealAll = -8}, "You do not fall while the line holds.")}
	},
	[8] = { -- Juggernaut
		{n("Bulwark of Ages", {takeAll = -10}, {dealAll = -10}, "Let them break themselves on you."),
			n("Thornwall", {reflect = 18}, {dealMelee = -8}, "Every blow comes home.")},
		{n("Rallying Roar", {killHeal = 3}, {takeMagic = 8}, "Your shout mends what is torn."),
			n("Steelblood", {vitality = 8}, {healIn = -30}, "Too dense to be patched.")},
		{n("Immortal Stand", {lastStandCd = 75}, {dealAll = -12}, "One more breath, one more step."),
			n("Avatar of Iron", {dealLowHp = 20, takeLowHp = -25}, {takeAll = 5}, "Wounded, you become the wall.")}
	},
	[14] = { -- Berserker
		{n("Bloodlust", STACK(4, 6, 6000), {takeAll = 8}, "The scent of it drives you on."),
			n("Cleaver's Hunger", {leechMelee = 4}, {takeMelee = 8}, "The axe drinks and shares.")},
		{n("Frenzy", {dealLowHp = 35}, {takeLowHp = 10}, "Pain is only a louder drum."),
			n("Rend Flesh", {dealDot = 30}, {dealMelee = -8}, "Wounds that keep opening.")},
		{n("Red Mist", {dealMelee = 22}, {takeAll = 12}, "You stop guarding at all."),
			n("Deathless Fury", {lastStandCd = 100, dealLowHp = 20}, {healIn = -50}, "Dead, and not yet told.")}
	},
	-- ------------------------------------------------------------------ Ranger line
	[3] = { -- Ranger
		{n("Steady Aim", {dealRanged = 14}, {takeAll = 5}, "Breathe out, loose."),
			n("Quick Draw", ECHO(15, 50), {dealRanged = -8}, "The second arrow is already nocked.")},
		{n("Hunter's Instinct", {dealFirst = 25}, {takeMelee = 8}, "The first shot is the true shot."),
			n("Fleet Footed", {evade = 8}, {dealRanged = -6}, "Never where the claws land.")},
		{n("Death From Afar", {dealExecute = 30}, {takeAll = 8}, "A wounded beast is a finished beast."),
			n("Pack Leader", NOVA(12, 40, 2), {dealAll = -6}, "Your volley finds the herd.")}
	},
	[7] = { -- Deadeye
		{n("Dead Center", {criticalHitChance = 4, criticalHitAmount = 25}, {takeAll = 6}, "Aim small, miss small."),
			n("Called Shot", {dealFirst = 30}, {dealRanged = -6}, "Name the spot before the arrow leaves.")},
		{n("Marksman's Patience", {dealHighHp = 22}, {takeAll = 5}, "Stillness is a weapon."),
			n("Hair Trigger", ECHO(18, 60), {dealRanged = -10}, "Two bolts in one breath.")},
		{n("Final Verdict", {dealExecute = 40}, {dealRanged = -10}, "The sentence is read at the end."),
			n("Ghost Quiver", {killHeal = 3, killMana = 3}, {dealAll = -8}, "The dead pay for the next shot.")}
	},
	[15] = { -- Beastmaster
		{n("Alpha Bond", {dealMinion = 25}, {dealRanged = -10}, "Your beasts fight as you would."),
			n("Wild Volley", NOVA(14, 45, 2), {dealMinion = -15}, "Arrows that scatter like a pack.")},
		{n("Pack Hide", {takeAll = -8}, {dealRanged = -6}, "You wear the herd's hide."),
			n("Feral Surge", STACK(3, 6, 8000), {takeMelee = 6}, "Each kill feeds the hunt.")},
		{n("Apex Predator", {dealMinion = 40}, {takeAll = 10}, "Your beasts hunt without leash."),
			n("Spirit Hunter", {leechAll = 3}, {dealMinion = -20}, "You eat what you slay.")}
	},
	-- ------------------------------------------------------------------ Mystic line
	[1] = { -- Mystic
		{n("Overchannel", {dealSpell = 15}, {spellCost = 20}, "Pour in more than the vessel holds."),
			n("Thrifty Weave", {spellCost = -20}, {dealSpell = -8}, "Nothing wasted, nothing wild.")},
		{n("Mana Ward", {manaShield = 25}, {dealSpell = -6}, "Your spirit takes the blow first."),
			n("Arcane Haste", {spellCd = -15}, {spellCost = 10}, "Cast again before the echo fades.")},
		{n("Elemental Surge", ECHO(15, 50), {spellCd = 10}, "The spell answers itself."),
			n("Archmage's Poise", {dealHighHp = 25}, {takeAll = 8}, "Unhurt, you are unmatched.")}
	},
	[5] = { -- Elementalist
		{n("Pyromania", {dealFire = 22}, {dealIce = -15}, "Burn it all."),
			n("Glacial Focus", {dealIce = 22}, {dealFire = -15}, "Stillness that cracks mountains.")},
		{n("Stormcaller", {dealEnergy = 22}, {dealFire = -10, dealIce = -10}, "Let the sky choose."),
			n("Chain Reaction", NOVA(15, 45, 2), {dealSpell = -10}, "Every blast has a child.")},
		{n("Cataclysm", {dealSpell = 25}, {spellCost = 25, spellCd = 15}, "A storm paid for in full."),
			n("Prismatic Ward", {absorbFire = 10, absorbIce = 10, absorbEnergy = 10}, {dealSpell = -10}, "Wear the weather.")}
	},
	[10] = { -- Illusionist
		{n("Mender's Gift", {healOut = 20}, {dealSpell = -15}, "Hands that would rather mend."),
			n("Lucid Mind", {spellCost = -25}, {dealSpell = -10}, "Clear thought is cheap.")},
		{n("Warding Veil", {takeAll = -10}, {healOut = -8}, "What they hit is not quite there."),
			n("Phantom Strike", {dealSpell = 20}, {healOut = -20}, "Even a mirror can cut.")},
		{n("Wellspring", {killHeal = 3, killMana = 3}, {takeMagic = 10}, "Each ending feeds the next scene."),
			n("Grand Illusion", {lastStandCd = 80}, {spellCd = 12}, "You were never where they struck.")}
	},
	-- ------------------------------------------------------------------ Thief line
	[11] = { -- Thief
		{n("Cutpurse's Edge", {dealMelee = 14}, {takeAll = 6}, "Quick, close, cruel."),
			n("Slippery", {evade = 10}, {dealMelee = -8}, "A shadow cannot be held.")},
		{n("Opportunist", {dealFirst = 28}, {takeMelee = 6}, "The first cut is the deepest."),
			n("Poison Craft", {dealDot = 30}, {dealMelee = -8}, "Patience on a blade.")},
		{n("Kingpin's Backstab", {criticalHitChance = 4, criticalHitAmount = 30}, {takeAll = 8}, "Take the whole purse."),
			n("Vanishing Act", {lastStandCd = 80}, {dealAll = -6}, "Where did he go?")}
	},
	[12] = { -- Ninja
		{n("Twin Fangs", ECHO(20, 50), {takeAll = 6}, "Two blades, one thought."),
			n("Shadow Flurry", {dealMelee = 20}, {takeMelee = 10}, "Too fast to guard.")},
		{n("Smoke Cloak", {evade = 12}, {dealMelee = -10}, "Nothing to hit but smoke."),
			n("Venom Dance", {dealDot = 40}, {dealMelee = -12}, "Poison keeps the rhythm.")},
		{n("Shadow Clones", NOVA(15, 50, 2), {dealMelee = -8}, "Where one stands, three strike."),
			n("Assassinate", {dealExecute = 40, dealFirst = 20}, {takeAll = 10}, "One strike, no second.")}
	},
	[13] = { -- Samurai
		{n("Iaijutsu Edge", {dealFirst = 35}, {dealMelee = -10}, "The draw is the duel."),
			n("Way of the Counter", {reflect = 22}, {dealMelee = -8}, "Their strength, returned.")},
		{n("Bushido Resolve", {criticalHitChance = 4, criticalHitAmount = 25}, {takeAll = 8}, "A calm mind cuts clean."),
			n("Parry Master", {evade = 12}, {dealMelee = -8}, "The blade finds only steel.")},
		{n("Heavenly Strike", {dealMelee = 28}, {takeAll = 12}, "One stroke, all in."),
			n("Last Honour", {dealLowHp = 40, lastStandCd = 100}, {healIn = -40}, "Death is only a door.")}
	},
	-- ------------------------------------------------------------------ Monk line
	[17] = { -- Monk
		{n("Quick Palm", {dealMelee = 14}, {takeAll = 6}, "Hands before thought."),
			n("Flowing Water", {evade = 10}, {dealMelee = -6}, "Be where the strike is not.")},
		{n("Inner Fire", {killMana = 3, killHeal = 2}, {takeMelee = 6}, "Breath from the fallen."),
			n("Stone Breath", {takeAll = -8}, {dealMelee = -6}, "Settle, and endure.")},
		{n("Hundred Fists", ECHO(20, 50), {takeAll = 8}, "The blow that arrives twice."),
			n("Enlightened", {criticalHitChance = 4, leechMelee = 3}, {dealMelee = -8}, "Strike at the centre.")}
	},
	[18] = { -- Shadowfist
		{n("Pressure Point", {dealFirst = 25, dealExecute = 20}, {takeAll = 6}, "Find the knot, press."),
			n("Focus Break", {criticalHitChance = 5, criticalHitAmount = 25}, {takeMelee = 8}, "Spent chi, spent foe.")},
		{n("Flurry Master", ECHO(22, 55), {dealMelee = -10}, "Strikes that cannot be counted."),
			n("Ghost Step", {evade = 14}, {dealMelee = -8}, "Gone before the answer.")},
		{n("Killing Touch", {dealMelee = 30}, {takeAll = 14}, "It only needs to touch."),
			n("Soul Siphon", {leechMelee = 6, killMana = 3}, {dealMelee = -10}, "Take the spark from them.")}
	},
	[19] = { -- Iron Sage
		{n("Mantra of Stone", {takeAll = -10}, {dealMelee = -10}, "Repeat until the mountain answers."),
			n("Iron Palm Echo", NOVA(14, 40, 2), {dealMelee = -8}, "A shock that rolls outward.")},
		{n("Chi Reservoir", {manaShield = 30}, {dealAll = -6}, "A deep well takes the fall."),
			n("Warden's Breath", {healOut = 25}, {dealMelee = -12}, "Your calm becomes theirs.")},
		{n("Mountain Stance", {lastStandCd = 70}, {dealAll = -10}, "Planted, unmoved."),
			n("Avatar of Calm", {takeLowHp = -30}, {dealAll = -8}, "At the edge, you are still.")}
	},
	-- ------------------------------------------------------------------ Necromancer line
	[20] = { -- Necromancer
		{n("Grave Pact", {dealMinion = 22}, {dealSpell = -8}, "The dead work for their keep."),
			n("Bone Spear Mastery", {dealSpell = 18, dealDeath = 10}, {dealMinion = -12}, "Take up the spear yourself.")},
		{n("Corpse Harvest", {killHeal = 3, killMana = 3}, {takeAll = 6}, "Nothing is wasted."),
			n("Withering Aura", {dealDot = 30}, {dealSpell = -8}, "Everything near you rots.")},
		{n("Lord of Rot", {dealDeath = 25}, {takeAll = 8}, "Decay answers to you."),
			n("Deathless Servant", {manaShield = 25}, {dealDeath = -12}, "Your death is borrowed.")}
	},
	[21] = { -- Lich
		{n("Soul Rot", {dealDot = 40}, {dealSpell = -10}, "It spreads while you wait."),
			n("Phylactery", {lastStandCd = 80}, {spellCost = 15}, "Death has already been bargained for.")},
		{n("Siphon Spirit", {leechSpell = 5}, {takeAll = 6}, "Their life, your cup."),
			n("Doom Whisper", {dealDeath = 25}, {dealMinion = -30}, "Alone, you are enough.")},
		{n("Corpse Cascade", NOVA(18, 55, 2), {spellCd = 12}, "Bodies burst into more bodies."),
			n("Eternal Hunger", STACK(3, 8, 8000), {takeMagic = 10}, "Every death makes room.")}
	},
	[22] = { -- Bone Lord
		{n("Marrow Banner", {dealMinion = 30}, {dealSpell = -12}, "The army marches under your name."),
			n("Ossified Plate", {takeAll = -8}, {dealMinion = -10}, "Bone armour, stitched on.")},
		{n("Bone Shrapnel", NOVA(15, 40, 2), {dealSpell = -8}, "Splinters find the next one."),
			n("Grave Tithe", {killHeal = 3, killMana = 2}, {takeAll = 6}, "The fallen pay what they owe.")},
		{n("Colossus Slam", {dealMinion = 45}, {takeAll = 12}, "The golem does not ask."),
			n("Sacrifice Rite", {manaShield = 30, lastStandCd = 100}, {dealMinion = -20}, "A servant dies in your place.")}
	},
	-- ------------------------------------------------------------------ Templar line
	[23] = { -- Templar
		{n("Radiant Strikes", {dealHoly = 18}, {dealPhysical = -10}, "Every blow carries a prayer."),
			n("Shieldbearer", {takeAll = -8}, {dealMelee = -6}, "The faithful stand behind you.")},
		{n("Vow of Mending", {healOut = 15, killHeal = 2}, {dealAll = -6}, "A promise that heals."),
			n("Zeal", STACK(3, 8, 8000), {takeAll = 6}, "Faith grows with every victory.")},
		{n("Consecrated Ground", NOVA(15, 45, 2), {dealMelee = -8}, "Where you stood is holy."),
			n("Martyr's Grace", merge({lastStandCd = 80}, {absorbHoly = 10}), {dealAll = -8}, "Suffer, and be spared.")}
	},
	[24] = { -- Inquisitor
		{n("Judgement", {dealHoly = 25}, {takeAll = 8}, "The verdict is already written."),
			n("Purging Fire", merge({dealHoly = 12}, NOVA(12, 40, 2)), {spellCd = 10}, "Cleanse by burning.")},
		{n("Zealotry", STACK(4, 6, 6000), {takeAll = 8}, "Fervour is a stacking sin."),
			n("Penance", {reflect = 20}, {dealHoly = -10}, "Every blow against you is paid back.")},
		{n("Wrath of Dawn", {dealExecute = 40}, {takeAll = 10}, "At the last, the light falls."),
			n("Light's Retribution", ECHO(20, 55), {dealHoly = -10}, "The strike is answered twice.")}
	},
	[25] = { -- Sentinel
		{n("Aegis of Faith", {takeAll = -12}, {dealHoly = -10}, "Faith as a shield wall."),
			n("Rebuke", {reflect = 25}, {dealAll = -8}, "Strike me, and be struck.")},
		{n("Lay on Hands", {healOut = 25}, {dealAll = -10}, "The kindest thing is to mend."),
			n("Vigil", {manaShield = 25}, {dealAll = -6}, "You watch, and the watch holds.")},
		{n("Unyielding Faith", {lastStandCd = 70}, {dealAll = -10}, "You do not fall while others stand."),
			n("Beacon", {absorbHoly = 12, absorbAllElements = 6}, {dealAll = -12}, "A light that turns aside harm.")}
	}
}
