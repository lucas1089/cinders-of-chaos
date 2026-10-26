-- Keystone labels of the combat log (keystone_labels.lua, combatlog.lua, server/README.md "DPS meter and combat log").
-- One entry per passive tree keystone flag whose effect shows in the DPS meter / combat log under the keystone's name.
--   name     the row's name after the prefix
--   kind     p  the keystone deals or heals something of its own (an extra hit, a reflect, a leech): the amount counts in
--               the tab like any other source (dealt, healing)
--            k  the keystone changes a hit that is already counted (a damage factor, a block, a reduction) or fires
--               without an amount: a note row, "how much it changed". It is inside the other rows and is not added to
--               the tab's total (combatlog_core.lua, source kind k)
--   tab      dealt | healing | taken: the tab the row is in
--   observe  false: a tester bot cannot make it fire in a hunt (party only, once in 90 seconds, a rare enemy), so
--            server/tools/tester_keytree.py leaves it "not observable" with `why`
-- The row key the tester bots read is "<kind>:<prefix><name>" (server/tools/tester_keytree.py reads this file).
-- Plain data, Lua 5.1 / LuaJIT and Lua 5.3. Strings in double quotes only (the Python reader).
return {
	prefix = "Keystone: ",
	flags = {
		-- passive tree keystones of the classes (passivetree_keystones.lua)
		ksCleavingArc = {name = "Cleaving Arc", kind = "p", tab = "dealt"},
		ksBulwark = {name = "Bulwark", kind = "p", tab = "dealt"},
		ksRicochet = {name = "Ricochet", kind = "p", tab = "dealt"},
		ksDeadeye = {name = "Deadeye", kind = "k", tab = "dealt"},
		ksArcaneEcho = {name = "Arcane Echo", kind = "p", tab = "dealt"},
		ksOverload = {name = "Overload", kind = "k", tab = "dealt"},
		ksOvergrowth = {name = "Overgrowth", kind = "p", tab = "healing", observe = false,
			why = "needs another player healed by the character: heals on others, bots never heal real players"},
		ksThorns = {name = "Thorns", kind = "p", tab = "dealt"},
		ksImmovable = {name = "Immovable", kind = "k", tab = "taken"},
		ksUndyingRage = {name = "Undying Rage", kind = "p", tab = "healing"},
		ksHuntersFocus = {name = "Hunter's Focus", kind = "k", tab = "dealt"},
		ksSharedPhantasm = {name = "Shared Phantasm", kind = "p", tab = "healing", observe = false,
			why = "needs a party: it buffs the other members, never the illusionist"},
		-- the Thief, Necromancer, Monk and Templar lines (class_keystones_core.lua)
		ksShadowTwin = {name = "Shadow Twin", kind = "p", tab = "dealt"},
		ksViperVerdict = {name = "Viper's Verdict", kind = "k", tab = "dealt"},
		ksCorpseBlast = {name = "Corpse Detonation", kind = "p", tab = "dealt"},
		ksReapersToll = {name = "Reaper's Toll", kind = "k", tab = "dealt"},
		ksSeventhPalm = {name = "Seventh Palm", kind = "p", tab = "dealt"},
		ksPiercingPalm = {name = "Piercing Palm", kind = "p", tab = "dealt"},
		ksRadiantRebuke = {name = "Radiant Rebuke", kind = "p", tab = "dealt"},
		ksDawnchain = {name = "Dawnchain", kind = "p", tab = "dealt"},
		-- class line keystones (class_tree.lua)
		ksPenitentWrath = {name = "Penitent's Wrath", kind = "p", tab = "dealt"},
		ksDivineVerdict = {name = "Divine Verdict", kind = "k", tab = "dealt"},
		ksScarredDiscipline = {name = "Scarred Discipline", kind = "k", tab = "taken"},
		ksHundredHands = {name = "Hundred Hands", kind = "k", tab = "dealt"},
		-- build archetype keystones (archetypes.lua)
		arAetherEdge = {name = "Aether Edge", kind = "p", tab = "dealt"},
		arBarbed = {name = "Barbed Quiver", kind = "k", tab = "dealt"},
		arCascade = {name = "Cascade Edge", kind = "p", tab = "dealt"},
		arCinderSigil = {name = "Sigil of Cinders", kind = "p", tab = "dealt"},
		arContagion = {name = "Contagion Rite", kind = "k", tab = "dealt"},
		arEarthbreaker = {name = "Earthbreaker", kind = "p", tab = "dealt"},
		arEffigy = {name = "Effigy Covenant", kind = "p", tab = "dealt"},
		arExecutioner = {name = "Executioner's Verdict", kind = "k", tab = "dealt"},
		arHobble = {name = "Hobbling Shot", kind = "k", tab = "dealt"},
		arHollowVessel = {name = "Hollow Vessel", kind = "k", tab = "taken", observe = false,
			why = "only life drain and poison ticks are absorbed: a hunt does not meet them on demand"},
		arLastStand = {name = "Last Stand", kind = "k", tab = "taken", observe = false,
			why = "fires once in 90 seconds, on a hit that would take the character below 20% health"},
		arLongshot = {name = "Longshot", kind = "k", tab = "dealt"},
		arOpenHand = {name = "Open Hand Creed", kind = "k", tab = "dealt"},
		arOpeningShot = {name = "Opening Shot", kind = "k", tab = "dealt"},
		arPyreOath = {name = "Pyre Oath", kind = "p", tab = "dealt"},
		arRampage = {name = "Rampage", kind = "k", tab = "dealt"},
		arReliquary = {name = "Reliquary Vow", kind = "p", tab = "dealt"},
		arSanguine = {name = "Sanguine Covenant", kind = "p", tab = "healing"},
		arSnarewright = {name = "Snarewright's Creed", kind = "k", tab = "dealt"},
		arStormstring = {name = "Stormstring", kind = "p", tab = "dealt"},
		arThornbound = {name = "Thornbound Oath", kind = "p", tab = "dealt"},
		arVigils = {name = "Covenant of Vigils", kind = "k", tab = "dealt"},
		arWinterLattice = {name = "Winter's Lattice", kind = "p", tab = "dealt"},
	},
}
