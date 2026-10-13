-- Loadouts / Armory (loadouts.lua, loadouts_core.lua). Every number of the system is here. server/README.md "Loadouts".
ChaosLoadoutsConfig = {
	-- slots: baseSlots for everyone; one more at each `earned` level (in game, never sold: README "Loadouts", Slots);
	-- pactSlots more while the Chaos Pact (VIP) is active (pact_config.lua perks.loadoutSlots, pact_perks.lua). A slot
	-- over the limit keeps its saved loadout; it only cannot be loaded or saved until the limit allows it again.
	baseSlots = 3,
	earned = {
		{level = 200},
		{level = 500}
	},
	pactSlots = 1,
	maxSlots = 6, -- baseSlots + #earned + pactSlots; the rune mirror below reserves room for up to runeMirrorSlots
	minLevel = 8, -- below this the window only explains (a level 1-7 character has no tree points)

	-- switching (load): out of combat, never inside an instance (arena, rift, trial, raid, ...); in a protection zone at
	-- once, elsewhere after a castMs channel (standing still, no combat). cooldownSeconds between two switches.
	cooldownSeconds = 60,
	castMs = 3000,
	pollMs = 100,
	castSerialBase = 900000000, -- cast bar serials (client game_castbar) far above the spells' own

	-- gear: the equipment slots a loadout's set covers (CONST_SLOT_*: 3, the backpack, is never part of a set)
	gearSlots = {1, 2, 4, 5, 6, 7, 8, 9, 10},
	inboxOnlyInPz = true, -- the store inbox is searched only while switching in a protection zone

	nameMax = 20,
	-- icons the client shows (client images /images/chaos/small/topbutton_<icon>.png)
	icons = {"skills", "spells", "passivetree", "pvp", "dungeons", "infinitytower", "inventory", "quests", "ranking", "vip"},

	-- player storages: 7100570 - 7100579 (chaos_constants.lua Chaos.storage.loadouts)
	storage = {active = 7100570, serial = 7100571, lastSwitch = 7100572},
	-- the support runes of the loadouts that are not active: per slot a copy of the support socket layout
	-- (base + (slot - 1) * span + spell id * 4 + socket, span = (supports maxSpellId + 1) * 4 = 2000)
	runeMirrorBase = 7112000,
	runeMirrorSlots = 8, -- 7112000 - 7127999 reserved

	-- client request limits (ratelimit.lua), ms
	rate = {open = 800, save = 2000, load = 1000, rename = 800, delete = 800, cancel = 200},

	messages = {
		noSlot = "That loadout slot does not exist.",
		locked = "That slot is locked: you have %d loadout slots (one more at level %d).",
		lockedMax = "That slot is locked.",
		empty = "That loadout slot is empty.",
		alreadyActive = "That loadout is already active.",
		saveFirst = "Save your current build in a loadout first: switching would lose it.",
		cooldown = "You can switch loadouts again in %d seconds.",
		combat = "You cannot switch loadouts in combat.",
		busy = "You cannot switch loadouts inside %s.",
		casting = "You are already switching loadouts.",
		lowLevel = "Loadouts open at level %d.",
		holdsRunes = "This loadout holds %d support rune%s: load it and take them out first.",
		holdsRunesSave = "This loadout holds %d support rune%s of its own: load it, or save into another slot.",
		moved = "You moved: the loadout switch is interrupted.",
		hit = "You entered combat: the loadout switch is interrupted.",
		cancelled = "Loadout switch cancelled."
	}
}

return ChaosLoadoutsConfig
