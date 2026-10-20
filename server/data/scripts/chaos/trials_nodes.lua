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

local function n(name, fx, lore)
	return {name = name, fx = fx, cost = {}, lore = lore}
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
		{n("Reckless Blows", {dealMelee = 15}, "Swing first, bleed later."),
			n("Steady Guard", {takeMelee = -12}, "A wall does not hurry.")},
		{n("Second Wind", {killHeal = 2.5}, "Every felled foe is a breath of air."),
			n("Iron Hide", {absorbPhysical = 6}, "Scars that turn the next blade.")},
		{n("Warlord's Rage", STACK(3, 8, 8000), "The more that fall, the louder you roar."),
			n("Last Bastion", {lastStandCd = 90}, "You do not fall while the line holds.")}
	},
	[8] = { -- Juggernaut
		{n("Bulwark of Ages", {takeAll = -10}, "Let them break themselves on you."),
			n("Thornwall", {reflect = 18}, "Every blow comes home.")},
		{n("Rallying Roar", {killHeal = 3}, "Your shout mends what is torn."),
			n("Steelblood", {vitality = 8}, "Too dense to be patched.")},
		{n("Immortal Stand", {lastStandCd = 75}, "One more breath, one more step."),
			n("Wall Unbroken", {takeLowHp = -30}, "Wounded, you only grow harder to break.")}
	},
	[14] = { -- Berserker
		{n("Bloodlust", STACK(4, 6, 6000), "The scent of it drives you on."),
			n("Cleaver's Hunger", {leechMelee = 4}, "The axe drinks and shares.")},
		{n("Frenzy", {dealLowHp = 35}, "Pain is only a louder drum."),
			n("Rend Flesh", {dealDot = 30}, "Wounds that keep opening.")},
		{n("Avatar of Iron", {dealLowHp = 20, takeLowHp = -25}, "Wounded, you become the wall."),
			n("Deathless Fury", {lastStandCd = 100, dealLowHp = 20}, "Dead, and not yet told.")}
	},
	-- ------------------------------------------------------------------ Ranger line
	[3] = { -- Ranger
		{n("Steady Aim", {dealRanged = 14}, "Breathe out, loose."),
			n("Quick Draw", ECHO(15, 50), "The second arrow is already nocked.")},
		{n("Hunter's Instinct", {dealFirst = 25}, "The first shot is the true shot."),
			n("Fleet Footed", {evade = 8}, "Never where the claws land.")},
		{n("Death From Afar", {dealExecute = 30}, "A wounded beast is a finished beast."),
			n("Pack Leader", NOVA(12, 40, 2), "Your volley finds the herd.")}
	},
	[7] = { -- Deadeye
		{n("Dead Center", {criticalHitChance = 4, criticalHitAmount = 25}, "Aim small, miss small."),
			n("Called Shot", {dealFirst = 30}, "Name the spot before the arrow leaves.")},
		{n("Marksman's Patience", {dealHighHp = 22}, "Stillness is a weapon."),
			n("Hair Trigger", ECHO(18, 60), "Two bolts in one breath.")},
		{n("Final Verdict", {dealExecute = 40}, "The sentence is read at the end."),
			n("Ghost Quiver", {killHeal = 3, killMana = 3}, "The dead pay for the next shot.")}
	},
	[15] = { -- Beastmaster
		{n("Alpha Bond", {dealMinion = 25}, "Your beasts fight as you would."),
			n("Wild Volley", NOVA(14, 45, 2), "Arrows that scatter like a pack.")},
		{n("Pack Hide", {takeAll = -8}, "You wear the herd's hide."),
			n("Feral Surge", STACK(3, 6, 8000), "Each kill feeds the hunt.")},
		{n("Apex Predator", {dealMinion = 40}, "Your beasts hunt without leash."),
			n("Spirit Hunter", {leechAll = 3}, "You eat what you slay.")}
	},
	-- ------------------------------------------------------------------ Mystic line
	[1] = { -- Mystic
		{n("Overchannel", {dealSpell = 15}, "Pour in more than the vessel holds."),
			n("Thrifty Weave", {spellCost = -20}, "Nothing wasted, nothing wild.")},
		{n("Mana Ward", {manaShield = 25}, "Your spirit takes the blow first."),
			n("Arcane Haste", {spellCd = -15}, "Cast again before the echo fades.")},
		{n("Elemental Surge", ECHO(15, 50), "The spell answers itself."),
			n("Archmage's Poise", {dealHighHp = 25}, "Unhurt, you are unmatched.")}
	},
	[5] = { -- Elementalist
		{n("Pyromania", {dealFire = 22}, "Burn it all."),
			n("Glacial Focus", {dealIce = 22}, "Stillness that cracks mountains.")},
		{n("Stormcaller", {dealEnergy = 22}, "Let the sky choose."),
			n("Chain Reaction", NOVA(15, 45, 2), "Every blast has a child.")},
		{n("Cataclysm", {dealSpell = 25}, "A storm paid for in full."),
			n("Prismatic Ward", {absorbFire = 10, absorbIce = 10, absorbEnergy = 10}, "Wear the weather.")}
	},
	[10] = { -- Illusionist
		{n("Mender's Gift", {healOut = 20}, "Hands that would rather mend."),
			n("Lucid Mind", {spellCost = -25}, "Clear thought is cheap.")},
		{n("Warding Veil", {takeAll = -10}, "What they hit is not quite there."),
			n("Phantom Strike", {dealSpell = 20}, "Even a mirror can cut.")},
		{n("Wellspring", {killHeal = 3, killMana = 3}, "Each ending feeds the next scene."),
			n("Grand Illusion", {lastStandCd = 80}, "You were never where they struck.")}
	},
	-- ------------------------------------------------------------------ Thief line
	[11] = { -- Thief
		{n("Cutpurse's Edge", {dealMelee = 14}, "Quick, close, cruel."),
			n("Slippery", {evade = 10}, "A shadow cannot be held.")},
		{n("Opportunist", {dealFirst = 28}, "The first cut is the deepest."),
			n("Poison Craft", {dealDot = 30}, "Patience on a blade.")},
		{n("Kingpin's Backstab", {criticalHitChance = 4, criticalHitAmount = 30}, "Take the whole purse."),
			n("Vanishing Act", {lastStandCd = 80}, "Where did he go?")}
	},
	[12] = { -- Ninja
		{n("Twin Fangs", ECHO(20, 50), "Two blades, one thought."),
			n("Shadow Flurry", {dealMelee = 20}, "Too fast to guard.")},
		{n("Smoke Cloak", {evade = 12}, "Nothing to hit but smoke."),
			n("Venom Dance", {dealDot = 40}, "Poison keeps the rhythm.")},
		{n("Shadow Clones", NOVA(15, 50, 2), "Where one stands, three strike."),
			n("Assassinate", {dealExecute = 40, dealFirst = 20}, "One strike, no second.")}
	},
	[13] = { -- Samurai
		{n("Iaijutsu Edge", {dealFirst = 35}, "The draw is the duel."),
			n("Way of the Counter", {reflect = 22}, "Their strength, returned.")},
		{n("Bushido Resolve", {criticalHitChance = 4, criticalHitAmount = 25}, "A calm mind cuts clean."),
			n("Parry Master", {evade = 12}, "The blade finds only steel.")},
		{n("Heavenly Strike", {dealMelee = 28}, "One stroke, all in."),
			n("Last Honour", {dealLowHp = 40, lastStandCd = 100}, "Death is only a door.")}
	},
	-- ------------------------------------------------------------------ Monk line
	[17] = { -- Monk
		{n("Quick Palm", {dealMelee = 14}, "Hands before thought."),
			n("Flowing Water", {evade = 10}, "Be where the strike is not.")},
		{n("Inner Fire", {killMana = 3, killHeal = 2}, "Breath from the fallen."),
			n("Stone Breath", {takeAll = -8}, "Settle, and endure.")},
		{n("Hundred Fists", ECHO(20, 50), "The blow that arrives twice."),
			n("Enlightened", {criticalHitChance = 4, leechMelee = 3}, "Strike at the centre.")}
	},
	[18] = { -- Shadowfist
		{n("Pressure Point", {dealFirst = 25, dealExecute = 20}, "Find the knot, press."),
			n("Focus Break", {criticalHitChance = 5, criticalHitAmount = 25}, "Spent chi, spent foe.")},
		{n("Flurry Master", ECHO(22, 55), "Strikes that cannot be counted."),
			n("Ghost Step", {evade = 14}, "Gone before the answer.")},
		{n("Killing Touch", {dealMelee = 30}, "It only needs to touch."),
			n("Soul Siphon", {leechMelee = 6, killMana = 3}, "Take the spark from them.")}
	},
	[19] = { -- Iron Sage
		{n("Mantra of Stone", {takeAll = -10}, "Repeat until the mountain answers."),
			n("Iron Palm Echo", NOVA(14, 40, 2), "A shock that rolls outward.")},
		{n("Chi Reservoir", {manaShield = 30}, "A deep well takes the fall."),
			n("Warden's Breath", {healOut = 25}, "Your calm becomes theirs.")},
		{n("Mountain Stance", {lastStandCd = 70}, "Planted, unmoved."),
			n("Avatar of Calm", {takeLowHp = -30}, "At the edge, you are still.")}
	},
	-- ------------------------------------------------------------------ Necromancer line
	[20] = { -- Necromancer
		{n("Grave Pact", {dealMinion = 22}, "The dead work for their keep."),
			n("Bone Spear Mastery", {dealSpell = 18, dealDeath = 10}, "Take up the spear yourself.")},
		{n("Corpse Harvest", {killHeal = 3, killMana = 3}, "Nothing is wasted."),
			n("Withering Aura", {dealDot = 30}, "Everything near you rots.")},
		{n("Lord of Rot", {dealDeath = 25}, "Decay answers to you."),
			n("Deathless Servant", {manaShield = 25}, "Your death is borrowed.")}
	},
	[21] = { -- Lich
		{n("Soul Rot", {dealDot = 40}, "It spreads while you wait."),
			n("Phylactery", {lastStandCd = 80}, "Death has already been bargained for.")},
		{n("Siphon Spirit", {leechSpell = 5}, "Their life, your cup."),
			n("Doom Whisper", {dealDeath = 25}, "Alone, you are enough.")},
		{n("Corpse Cascade", NOVA(18, 55, 2), "Bodies burst into more bodies."),
			n("Eternal Hunger", STACK(3, 8, 8000), "Every death makes room.")}
	},
	[22] = { -- Bone Lord
		{n("Marrow Banner", {dealMinion = 30}, "The army marches under your name."),
			n("Ossified Plate", {takeAll = -8}, "Bone armour, stitched on.")},
		{n("Bone Shrapnel", NOVA(15, 40, 2), "Splinters find the next one."),
			n("Grave Tithe", {killHeal = 3, killMana = 2}, "The fallen pay what they owe.")},
		{n("Colossus Slam", {dealMinion = 45}, "The golem does not ask."),
			n("Sacrifice Rite", {manaShield = 30, lastStandCd = 100}, "A servant dies in your place.")}
	},
	-- ------------------------------------------------------------------ Templar line
	[23] = { -- Templar
		{n("Radiant Strikes", {dealHoly = 18}, "Every blow carries a prayer."),
			n("Shieldbearer", {takeAll = -8}, "The faithful stand behind you.")},
		{n("Vow of Mending", {healOut = 15, killHeal = 2}, "A promise that heals."),
			n("Zeal", STACK(3, 8, 8000), "Faith grows with every victory.")},
		{n("Consecrated Ground", NOVA(15, 45, 2), "Where you stood is holy."),
			n("Martyr's Grace", merge({lastStandCd = 80}, {absorbHoly = 10}), "Suffer, and be spared.")}
	},
	[24] = { -- Inquisitor
		{n("Judgement", {dealHoly = 25}, "The verdict is already written."),
			n("Purging Fire", merge({dealHoly = 12}, NOVA(12, 40, 2)), "Cleanse by burning.")},
		{n("Zealotry", STACK(4, 6, 6000), "Fervour is a stacking sin."),
			n("Penance", {reflect = 20}, "Every blow against you is paid back.")},
		{n("Wrath of Dawn", {dealExecute = 40}, "At the last, the light falls."),
			n("Light's Retribution", ECHO(20, 55), "The strike is answered twice.")}
	},
	[25] = { -- Sentinel
		{n("Aegis of Faith", {takeAll = -12}, "Faith as a shield wall."),
			n("Rebuke", {reflect = 25}, "Strike me, and be struck.")},
		{n("Lay on Hands", {healOut = 25}, "The kindest thing is to mend."),
			n("Vigil", {manaShield = 25}, "You watch, and the watch holds.")},
		{n("Unyielding Faith", {lastStandCd = 70}, "You do not fall while others stand."),
			n("Beacon", {absorbHoly = 12, absorbAllElements = 6}, "A light that turns aside harm.")}
	}
}
