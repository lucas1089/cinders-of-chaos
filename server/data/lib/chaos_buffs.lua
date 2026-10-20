-- chaos_buffs.lua: the buff / debuff registry and the rules of the buff bar (client game_buffbar, extended opcode
-- ChaosOpcodes.buffs; the glue is data/scripts/chaos/buffbar.lua, tests/buffs_test.lua).
--
-- What the bar shows is looked up here, never decided by the client:
--   * conditions     engine conditions (haste, poison, mana shield, in fight ...) and the Chaos class buffs, which are
--                    conditions with a sub id (the spells and the combat scripts run in different Lua states; the
--                    condition is what everybody sees). {cond = {type = "CONDITION_HASTE", sub = 0, ids = {...}}}
--                    (cond.subs = {a, b ...} looks for several sub ids; the first one found is the buff)
--   * sources        everything else, a function B.sources[name](player, nowMs, def) that returns a list of items: skull
--                    timers, world buffs, the Victory buff, the Golden Hour / Chaos Storm world events, the day's events,
--                    the double experience potion, Vocation Trials kill stacks (Bloodlust and the like), the Monk's
--                    chi, the Berserker's Rage, Reprisal, the Iron Palm stun on a player, the Templar aura, the vigils. A source reads the other modules' globals guarded (a module
--                    that is not loaded simply adds nothing).
--   Item ailments (bleed / ignite / poison / chill / shock of item_mods.lua) are only ever put on monsters, so they
--   never show here; what a monster does to a player (poison, burning, slow ...) is an engine condition above.
--   Hex and Brand marks sit on monsters, not on the player: not here (optional extra, not done).
--
-- An item (what collect returns): {key, name, desc, icon, kind = "buff" | "debuff", leftMs = ms or nil (no timer),
-- stacks = n or nil, prio}. The wire entry (B.wire): {k, n, d, i, t = 0 | 1, l = ms left or nil, s = stacks or nil}.
-- icon: "buff:<name>", our own 26 px pixel-art icon (client/overlay/data/images/game/buffs/<name>.png, drawn by
-- client/tools/gen_buff_icons.py: one for every key of the registry; a class buff shows its spell's art in the buff
-- frame). The client still reads the older "spell:<words>" / "cond:<NN>" forms, but draws the key's own icon for them.
--
-- Messages (server -> client, JSON {action, data}):
--   full  {list = [entry ...]}                          the whole bar (login, `sync`, every cfg.resyncMs)
--   diff  {add = [entry ...], upd = [{k, l, s} ...], del = [key ...]}
-- A time is the milliseconds left when the message is built; the client counts down from the moment it arrives.
-- An update is sent only when the stacks changed or the end moved by more than cfg.toleranceMs (a recast), so a
-- quiet bar costs no traffic. Lua 5.1 / LuaJIT and 5.3.

ChaosBuffs = ChaosBuffs or {}
local B = ChaosBuffs

B.cfg = {
	tickMs = 1000, -- how often a character's bar is looked at
	resyncMs = 30000, -- a full list this often, whatever the diffs said (a lost packet heals itself)
	requestMs = 2000, -- the client may ask for a full list this often at most
	toleranceMs = 1500, -- an end time that moved less than this is the same buff (the client counts down by itself)
	maxEntries = 24, -- at most this many on one bar
	maxName = 40, -- text limits of what goes on the wire
	maxDesc = 200,
	partyEntries = 5 -- the buffs shown under a party frame
}

function B.nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ------------------------------------------------------------------------------------------------ the registry
-- Rows are listed by prio inside a kind: world / events first, then the character's own, then the engine's.
B.entries = {}
B.byKey = {}

local function add(def)
	assert(def.key and not B.byKey[def.key], "buff key twice: " .. tostring(def.key))
	def.prio = def.prio or 50
	B.entries[#B.entries + 1] = def
	B.byKey[def.key] = def
end

-- a condition-backed buff: cond = {type, sub, ids}; ids defaults to the combat id (what Condition(type) makes)
local function cond(key, ctype, sub, kind, name, icon, desc, prio, extra)
	local def = {key = key, kind = kind, name = name, icon = icon, desc = desc, prio = prio,
		cond = {type = ctype, sub = sub or 0, ids = {"CONDITIONID_COMBAT"}}}
	for k, v in pairs(extra or {}) do
		def[k] = v
	end
	add(def)
	return def
end

-- a source-backed buff: the source returns the items itself; the entry here is the default look and the listing
local function source(key, src, kind, name, icon, desc, prio, extra)
	local def = {key = key, kind = kind, name = name, icon = icon, desc = desc, prio = prio, source = src}
	for k, v in pairs(extra or {}) do
		def[k] = v
	end
	add(def)
	return def
end

-- ---- the world: shared buffs and events (sources below)
source("world_xp", "worldBuff", "buff", "World Experience", "buff:world_xp", "Experience from monsters is increased for everyone.", 10, {world = "xp"})
source("world_loot", "worldBuff", "buff", "World Loot", "buff:world_loot", "More Chaos loot from monsters for everyone.", 11, {world = "loot"})
source("world_skill", "worldBuff", "buff", "World Training", "buff:world_skill", "Skill and magic level training is faster for everyone.", 12, {world = "skill"})
source("victory", "victory", "buff", "Victory", "buff:victory", "A held invasion rewards extra experience.", 13)
source("golden_hour", "worldEvent", "buff", "Golden Hour", "buff:golden_hour", "More Chaos loot from every monster in this area.", 14, {event = "golden"})
source("chaos_storm", "worldEvent", "buff", "Chaos Storm", "buff:chaos_storm", "Magic, rare and legendary monsters appear far more often in this area.", 15, {event = "storm"})
source("calendar_event", "calendar", "buff", "Event", "buff:event", "A scheduled event is running.", 16)
source("double_xp", "doubleXp", "buff", "Double Experience", "buff:double_xp", "A double experience potion doubles the experience you get.", 17)
-- community goals (data/scripts/chaos/community.lua): an open stage window ("buff:community_<stage>") and the week's
-- world modifiers ("buff:wmod_<key>"), each with its own icon (client/tools/gen_community_icons.py)
source("community_goal", "community", "buff", "Community Goal", "buff:community_goal", "A community goal stage blesses everyone online.", 18)
source("wmod_week", "community", "buff", "World Modifier", "buff:wmod_week", "This week's world modifier.", 19, {week = true})

-- ---- Chaos buffs: class spells (sub ids of ChaosSpell.SUBID, Chaos.classes.subId, necro_config, monk_chi_core, templar_aura_core)
cond("blood_pact", "CONDITION_ATTRIBUTES", 71001, "buff", "Crimson Covenant", "buff:blood_pact", "A short magic level boost, paid for in health.", 30)
cond("red_frenzy", "CONDITION_ATTRIBUTES", 71002, "buff", "Red Frenzy", "buff:red_frenzy", "More melee skill, less shielding.", 30)
cond("rally", "CONDITION_ATTRIBUTES", 71003, "buff", "Banner Call", "buff:rally", "Melee, distance and magic are stronger, and you are faster.", 30)
cond("barkskin", "CONDITION_ATTRIBUTES", 71004, "buff", "Ironbark Hide", "buff:barkskin", "More maximum health and steady regeneration.", 30)
cond("divine_ward", "CONDITION_REGENERATION", 71005, "buff", "Lightward", "buff:divine_ward", "Strong health and mana regeneration.", 30)
cond("soul_aegis", "CONDITION_MANASHIELD", 71006, "buff", "Soulward", "buff:soul_aegis", "Damage is taken from mana first, and mana regenerates.", 30)
cond("phantom_veil", "CONDITION_INVISIBLE", 71007, "buff", "Wraithshroud", "buff:phantom_veil", "You are invisible and faster.", 30)
cond("dash", "CONDITION_HASTE", 71008, "buff", "Flickerdash", "buff:dash", "A short burst of speed.", 31)
cond("iron_will", "CONDITION_ATTRIBUTES", 71009, "buff", "Iron Will", "buff:iron_will", "Less damage taken and more shielding.", 30)
cond("stealth", "CONDITION_INVISIBLE", 71010, "buff", "Shadow Veil", "buff:stealth", "Monsters lose you. Your first weapon hit out of it is a critical hit.", 30)
cond("poison_blades", "CONDITION_ATTRIBUTES", 71011, "buff", "Poison Blades", "buff:poison_blades", "Your weapon hits poison the target.", 30)
cond("counter", "CONDITION_ATTRIBUTES", 71012, "buff", "Counter Stance", "buff:counter", "The next melee hit you take is parried and answered.", 30)
cond("bushido", "CONDITION_ATTRIBUTES", 71013, "buff", "Bushido Focus", "buff:bushido",
	"Critical chance grows every second you take no damage. A hit taken starts the stacks again.", 29,
	{stacks = "bushido"})
cond("bloodrage", "CONDITION_ATTRIBUTES", 71014, "buff", "Bloodrage", "buff:bloodrage", "More Rage, and every melee hit also strikes enemies next to you.", 29)
cond("bone_aura", "CONDITION_ATTRIBUTES", 71022, "buff", "Banner of Bones", "buff:bone_aura", "Your bone minions are empowered.", 30)
cond("bone_shield", "CONDITION_ATTRIBUTES", 71023, "buff", "Bone Offering", "buff:bone_shield", "A shield of bone guards you.", 30)
cond("focus", "CONDITION_ATTRIBUTES", 71030, "buff", "Focus", "buff:focus", "Critical chance from the chi your last finisher spent.", 30)
cond("chi_ward", "CONDITION_ATTRIBUTES", 71031, "buff", "Chi Ward", "buff:chi_ward", "A ward absorbs damage.", 30)
-- 71037 is the Iron Sage's stronger timer of the same spell (Deep Mantra of the passive tree): one row for both
cond("mantra", "CONDITION_ATTRIBUTES", 71032, "buff", "Mantra of Stone", "buff:mantra",
	"Damage taken is reduced while you stay near the Sage (refreshed every pulse of the 12 second chant).", 30,
	{cond = {type = "CONDITION_ATTRIBUTES", sub = 71032, subs = {71032, 71037}, ids = {"CONDITIONID_COMBAT"}}})
cond("roll", "CONDITION_ATTRIBUTES", 71033, "buff", "Mistborne Step", "buff:roll", "You may slip the next blow.", 30)
cond("breath", "CONDITION_REGENERATION", 71036, "buff", "Kindled Breath", "buff:breath", "Heals you over time.", 30)
cond("moonfang_pack", "CONDITION_ATTRIBUTES", 71070, "buff", "Moonfang Pack", "buff:moonfang_pack", "Your summoned wolves fight for you. They vanish after 40 seconds.", 30)
cond("mirror_image", "CONDITION_ATTRIBUTES", 71071, "buff", "Hall of Mirrors", "buff:mirror_image", "Mirror images of you distract monsters. They vanish after 10 seconds.", 30)
cond("zealotry", "CONDITION_ATTRIBUTES", 71051, "buff", "Zealotry", "buff:zealotry", "A fervour that strengthens your strikes.", 30)
cond("aegis_faith", "CONDITION_ATTRIBUTES", 71052, "buff", "Aegis of Faith", "buff:aegis_faith", "Faith shields you.", 30)

-- ---- Chaos counters and windows (sources)
source("trial_stacks", "trialStacks", "buff", "Kill Stacks", "buff:trial_stacks", "Each kill adds damage for a short time.", 20)
source("chi", "chi", "buff", "Chi", "buff:chi", "Your strikes build chi, finishers spend it.", 21)
source("rage", "rage", "buff", "Rage", "buff:rage", "You hit harder the lower your health.", 22)
source("reprisal", "reprisal", "buff", "Reprisal", "buff:reprisal", "Monsters that hit you may be struck back.", 23)
source("templar_aura", "templarAura", "buff", "Templar Aura", "buff:templar_aura", "A Templar's aura shields you.", 24)
-- the vigils (vigils.lua): one row per vigil that covers you, yours or a party member's (stacks = the effect in percent,
-- no timer), and Iron Tithe's health reservation for its holder; the four vigils show their spell's icon
source("vigil_wrath", "vigils", "buff", "Vigil of Wrath", "buff:vigil_wrath", "A vigil covers you: more damage dealt.", 24, {vigil = "wrath"})
source("vigil_iron", "vigils", "buff", "Vigil of Iron", "buff:vigil_iron", "A vigil covers you: less damage taken.", 24, {vigil = "iron"})
source("vigil_haste", "vigils", "buff", "Vigil of Haste", "buff:vigil_haste", "A vigil covers you: you move faster.", 24, {vigil = "haste"})
source("vigil_clarity", "vigils", "buff", "Vigil of Clarity", "buff:vigil_clarity", "A vigil covers you: mana comes back every second.", 24, {vigil = "clarity"})
source("vigil_tithe", "vigils", "buff", "Iron Tithe", "buff:vigil_tithe", "Your vigils reserve maximum health instead of mana.", 24, {vigil = "tithe"})
source("stunned", "stun", "debuff", "Stunned", "buff:stunned", "You cannot move, attack or cast attack spells. Healing still works.", 40)
cond("stun_immune", "CONDITION_ATTRIBUTES", 71035, "buff", "Stun Immunity", "buff:stun_immune",
	"You were stunned: no stun can hold you until this ends, and the next one is shorter.", 25)
-- the Ember Descent (data/scripts/chaos/descent.lua): one entry per boon / curse a player holds in a run, each with its
-- own icon "buff:descent_b_<key>" / "buff:descent_c_<key>" (client/tools/gen_descent_icons.py)
source("descent_boon", "descent", "buff", "Descent Boon", "buff:descent_boon", "A boon of the Ember Descent, for this run only.", 26)
source("descent_curse", "descent", "debuff", "Descent Curse", "buff:descent_curse", "A curse of the Ember Descent: more rewards, a harder run.", 39)
-- season modes (data/scripts/chaos/season_modes.lua): the Self-Found loot bonus, and a Hardcore character's protection
-- (login, lost connection, restart) while it holds
source("self_found", "seasonMode", "buff", "Self-Found", "buff:self_found", "No trading; more and better loot.", 27, {mode = "ssf"})
source("hardcore_ward", "seasonMode", "buff", "Hardcore Ward", "buff:hardcore_ward", "You cannot be hurt for now.", 28, {mode = "ward"})
-- Ember Blessings (data/scripts/chaos/blessings.lua): one row per kind, 60 s from a kill; the same kind never stacks
source("blessing_xp", "blessings", "buff", "Ember of Insight", "buff:blessing_xp", "More experience from monsters.", 25, {blessing = "xp"})
source("blessing_gold", "blessings", "buff", "Ember of Avarice", "buff:blessing_gold", "More gold coins in your kills' corpses.", 25, {blessing = "gold"})
source("blessing_damage", "blessings", "buff", "Ember of Fury", "buff:blessing_damage", "More damage dealt to monsters.", 25, {blessing = "damage"})
source("blessing_ward", "blessings", "buff", "Ember of Warding", "buff:blessing_ward", "Less damage taken from monsters.", 25, {blessing = "ward"})
source("blessing_speed", "blessings", "buff", "Ember of Haste", "buff:blessing_speed", "You move faster.", 25, {blessing = "speed"})
source("blessing_regen", "blessings", "buff", "Ember of Renewal", "buff:blessing_regen", "Health and mana come back every 2 seconds.", 25, {blessing = "regen"})
source("blessing_crit", "blessings", "buff", "Ember of Precision", "buff:blessing_crit", "More critical hits, and harder ones.", 25, {blessing = "crit"})
source("blessing_loot", "blessings", "buff", "Ember of Plenty", "buff:blessing_loot", "More Chaos loot from your kills.", 25, {blessing = "loot"})
source("blessing_rarity", "blessings", "buff", "Ember of Fortune", "buff:blessing_rarity", "Gear drops roll a higher rarity more often.", 25, {blessing = "rarity"})
source("blessing_orb", "blessings", "buff", "Ember of the Forge", "buff:blessing_orb", "Orbs drop more often from your kills.", 25, {blessing = "orb"})
-- Professions (data/scripts/chaos/professions.lua): the passive experience bonus of the profession levels, no timer
source("professions", "professions", "buff", "Profession Mastery", "buff:professions", "Your profession levels add experience from monsters.", 29)
-- time-friendly progression (data/scripts/chaos/catchup.lua): the rested pool (stacks = minutes of hunting left), the
-- returning player boost (timer), the alt catch-up (stacks = percent) and low stamina (a debuff, no timer)
source("rested", "catchup", "buff", "Rested", "buff:rested", "More experience from monsters until your rest is spent.", 26, {part = "rested"})
source("returning", "catchup", "buff", "Welcome Back", "buff:returning", "More experience, loot and token drops for returning players.", 26, {part = "returning"})
source("catchup", "catchup", "buff", "Catch-up", "buff:catchup", "More experience from monsters below your account's best level.", 26, {part = "alt"})
source("low_stamina", "catchup", "debuff", "Low Stamina", "buff:low_stamina", "Less experience and loot until your stamina comes back.", 42, {part = "low"})

-- ---- engine conditions: buffs
-- the stock support spells (Haste, Strong Haste, Charge, Swift Foot) are haste conditions; the base scripts may give them
-- a small sub id, so cond.subs lists the ones to look for (the first found is shown)
cond("haste", "CONDITION_HASTE", 0, "buff", "Haste", "buff:haste", "You move faster.", 50,
	{cond = {type = "CONDITION_HASTE", sub = 0, subs = {0, 1, 2, 3}, ids = {"CONDITIONID_COMBAT"}}})
cond("regen", "CONDITION_REGENERATION", 0, "buff", "Regeneration", "buff:regen", "Health and mana come back faster.", 51)
cond("fed", "CONDITION_REGENERATION", 0, "buff", "Well Fed", "buff:fed", "Food makes health and mana regenerate.", 52,
	{cond = {type = "CONDITION_REGENERATION", sub = 0, ids = {"CONDITIONID_DEFAULT"}}})
cond("manashield", "CONDITION_MANASHIELD", 0, "buff", "Magic Shield", "buff:manashield", "Damage is taken from mana first.", 50)
cond("invisible", "CONDITION_INVISIBLE", 0, "buff", "Invisible", "buff:invisible", "Monsters cannot see you.", 50)
cond("light", "CONDITION_LIGHT", 0, "buff", "Light", "buff:light", "You carry a light.", 55)
-- the stock attribute buffs (Bloodlust, Bulwark, Hawkeye, the party Communions) and the potions: sub ids 0-9 of the base
cond("spellbuff", "CONDITION_ATTRIBUTES", 0, "buff", "Spell Buff", "buff:spellbuff",
	"A support spell or potion boosts your skills for a short time.", 50,
	{cond = {type = "CONDITION_ATTRIBUTES", sub = 0, subs = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}, ids = {"CONDITIONID_COMBAT"}}})

-- the Ashen Sepulchre (data/scripts/chaos/raid.lua): a raid boss's debuffs on the player in a fight, each with its own
-- icon: Sundered (the tank swap stacks, "buff:raid_sunder"), Hexed (effigy stacks, "buff:raid_hexed") and Withering Hex
-- (to cleanse, "buff:raid_hex"); client/tools/gen_raid_icons.py
source("raid_debuff", "raid", "debuff", "Raid Debuff", "buff:raid_debuff", "A raid boss's mark on you.", 38)

-- ---- engine conditions: debuffs
cond("poison", "CONDITION_POISON", 0, "debuff", "Poisoned", "buff:poison", "Poison hurts you every few seconds.", 50)
cond("burning", "CONDITION_FIRE", 0, "debuff", "Burning", "buff:burning", "Fire burns you every few seconds.", 50)
cond("energy", "CONDITION_ENERGY", 0, "debuff", "Electrified", "buff:energy", "Energy hurts you every few seconds.", 50)
cond("bleeding", "CONDITION_BLEEDING", 0, "debuff", "Bleeding", "buff:bleeding", "You bleed, taking damage over time.", 50)
cond("drowning", "CONDITION_DROWN", 0, "debuff", "Drowning", "buff:drowning", "You are drowning and take damage.", 49)
cond("freezing", "CONDITION_FREEZING", 0, "debuff", "Freezing", "buff:freezing", "Cold hurts you every few seconds.", 50)
cond("dazzled", "CONDITION_DAZZLED", 0, "debuff", "Dazzled", "buff:dazzled", "Holy light hurts you every few seconds.", 50)
cond("cursed", "CONDITION_CURSED", 0, "debuff", "Cursed", "buff:cursed", "A curse drains your health.", 50)
cond("paralyze", "CONDITION_PARALYZE", 0, "debuff", "Slowed", "buff:paralyze", "Your movement is slowed.", 48)
cond("drunk", "CONDITION_DRUNK", 0, "debuff", "Drunk", "buff:drunk", "You stumble when you walk.", 55)
cond("pacified", "CONDITION_PACIFIED", 0, "debuff", "Pacified", "buff:pacified", "You cannot attack.", 48)
cond("muted", "CONDITION_MUTED", 0, "debuff", "Silenced", "buff:muted", "You cannot cast spells.", 48)
cond("infight", "CONDITION_INFIGHT", 0, "debuff", "In Fight", "buff:infight",
	"You cannot log out or enter a protection zone until the timer ends.", 40,
	{cond = {type = "CONDITION_INFIGHT", sub = 0, ids = {"CONDITIONID_DEFAULT", "CONDITIONID_COMBAT"}}})
source("skull_white", "skull", "debuff", "White Skull", "buff:skull_white", "You attacked a player. Others may attack you freely.", 41, {skull = "SKULL_WHITE"})
source("skull_red", "skull", "debuff", "Red Skull", "buff:skull_red", "You killed too many players. Your skull fades when the timer ends.", 41, {skull = "SKULL_RED"})
source("skull_black", "skull", "debuff", "Black Skull", "buff:skull_black", "You killed far too many players. Your skull fades when the timer ends.", 41, {skull = "SKULL_BLACK"})

-- ------------------------------------------------------------------------------------------------ small helpers
local function constant(name)
	local v = rawget(_G, name)
	return type(v) == "number" and v or nil
end

local function clip(text, max)
	text = tostring(text or "")
	if #text > max then
		text = text:sub(1, max)
	end
	return text
end

local function item(def, leftMs, stacks)
	return {key = def.key, name = def.name, desc = def.desc, icon = def.icon, kind = def.kind, prio = def.prio,
		leftMs = leftMs, stacks = stacks}
end

local function secondsLeft(untilSec)
	local left = (tonumber(untilSec) or 0) - os.time()
	return left > 0 and left * 1000 or nil
end

local function safe(fn, ...)
	local ok, a = pcall(fn, ...)
	if ok then
		return a
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ sources
B.sources = {}
local S = B.sources

-- skull timers: the character's skull and the time the engine still keeps it
function S.skull(player, now, def)
	local skull = constant(def.skull)
	if not skull or player:getSkull() ~= skull then
		return nil
	end
	local ms = tonumber(player:getSkullTime()) or 0
	if ms <= 0 then
		return nil
	end
	return {item(def, ms)}
end

-- world buffs: global storages (shop_services.lua), the expiry in os.time seconds
function S.worldBuff(player, now, def)
	local C = Chaos and Chaos.shopServices
	if not C or not Game or not Game.getStorageValue then
		return nil
	end
	for i, buff in ipairs(C.worldBuffs or {}) do
		if buff.id == def.world then
			local left = secondsLeft(Game.getStorageValue((C.worldBuffStorage or 0) + i))
			if left then
				local it = item(def, left)
				it.name = buff.name or def.name
				it.desc = buff.text or def.desc
				return {it}
			end
		end
	end
	return nil
end

-- the Victory buff of a held invasion (invasion.lua): everyone, or only inside the area
function S.victory(player, now, def)
	local V, I = ChaosInvasion, ChaosInvasionCore
	local b = V and V.buff
	if not b or not I or not I.buffActive or not I.buffActive(b, os.time()) then
		return nil
	end
	if b.scope == "area" and not I.inArea(player:getPosition(), b.area) then
		return nil
	end
	local it = item(def, secondsLeft(b.endsAt))
	local pct = math.floor(((tonumber(b.xp) or 1) - 1) * 100 + 0.5)
	it.name = "Victory"
	it.desc = string.format("+%d%% experience%s for holding the line.", pct, b.scope == "area" and (" in " .. tostring(b.name)) or "")
	return it.leftMs and {it} or nil
end

-- Golden Hour / Chaos Storm (worldevents.lua): only for the player standing in the area
function S.worldEvent(player, now, def)
	local W, I = ChaosWorldEvents, ChaosInvasionCore
	local a = W and W.active
	if not a or a.kind ~= def.event or os.time() >= (a.endsAt or 0) or not I or not I.inArea(player:getPosition(), a.area) then
		return nil
	end
	local it = item(def, secondsLeft(a.endsAt))
	if a.area and a.area.name then
		it.desc = def.desc:gsub("this area", a.area.name)
	end
	return it.leftMs and {it} or nil
end

-- the day's scheduled events with a bonus (events_schedule.lua); no end time of their own, so no timer
function S.calendar(player, now, def)
	local E = ChaosEvents
	if not E or not E.active then
		return nil
	end
	local list = {}
	for _, ev in ipairs(safe(E.active, os.time()) or {}) do
		if ev.bonus and not (E.dynamic and E.dynamic[ev.id]) and ev.id then
			local it = item(def, nil)
			it.key = "event_" .. tostring(ev.id)
			it.name = clip(ev.name or def.name, B.cfg.maxName)
			it.desc = clip(ev.description or def.desc, B.cfg.maxDesc)
			list[#list + 1] = it
		end
	end
	return list
end

-- the double experience potion: a storage with the end time (base server, data/scripts/customs/actions)
function S.doubleXp(player, now, def)
	local left = secondsLeft(player:getStorageValue(6000))
	return left and {item(def, left)} or nil
end

-- Vocation Trials kill stacks (Bloodlust, Zeal ...): trials_effects.lua keeps the kill times; the oldest falls first
function S.trialStacks(player, now, def)
	local T, M = ChaosTrials, ChaosTrialsCore
	local cache = ChaosPassiveCache
	if not (T and T.nodeState and M and M.stackCount and cache) then
		return nil
	end
	local id = player:getId()
	local b, st = cache[id], T.nodeState[id]
	if not b or not st or (b.killStackPct or 0) <= 0 or not st.stackKills then
		return nil
	end
	local n = M.stackCount(st, b, now)
	if n <= 0 then
		return nil
	end
	local ms = b.killStackMs or 0
	local oldest = st.stackKills[1] or now
	local it = item(def, math.max(1, oldest + ms - now), n)
	-- the held node that gives the stacks names the buff
	local voc = player:getVocation() and player:getVocation():getId()
	local name = safe(function()
		for _, node in ipairs(M.heldNodes(voc, T.tierCleared(player, voc), T.picks(player, voc))) do
			if node.fx and node.fx.killStackPct then
				return node.name
			end
		end
	end)
	if name then
		it.name = clip(name, B.cfg.maxName)
	end
	it.desc = string.format("Each stack: +%d%% damage (up to %d stacks). A stack fades %d s after the kill.",
		b.killStackPct or 0, b.killStackMax or 1, math.floor(ms / 1000 + 0.5))
	return {it}
end

-- the Monk's chi: stacks = chi, the timer is the decay of chi that is not touched
function S.chi(player, now, def)
	local M = ChaosMonk
	local voc = player:getVocation() and player:getVocation():getId()
	if not (M and M.isMonkLine and M.isMonkLine(voc)) then
		return nil
	end
	local chi = M.getChi(player, os.time())
	if chi <= 0 then
		return nil
	end
	local decay = M.cfg and M.cfg.chi and M.cfg.chi.decaySec or 0
	local left
	if decay > 0 then
		left = secondsLeft(player:getStorageValue(M.ids.storage.chiTime) + decay)
	end
	local it = item(def, left, chi)
	it.desc = string.format("Strikes build chi, finishers spend it. Chi fades %d s after the last change.", decay)
	return {it}
end

-- the Berserker's Rage: the damage bonus that grows as health drops (a passive: no timer, the stacks are the percent)
function S.rage(player, now, def)
	local C = ChaosClasses
	local voc = player:getVocation() and player:getVocation():getId()
	if not (C and C.rageMultiplier and Chaos and Chaos.classes and voc == Chaos.classes.ids.berserker) then
		return nil
	end
	local blood = player:getCondition(constant("CONDITION_ATTRIBUTES") or 0, constant("CONDITIONID_COMBAT") or 0,
		Chaos.classes.subId.bloodrage) ~= nil
	local pct = math.floor((C.rageMultiplier(player:getHealth(), player:getMaxHealth(), blood) - 1) * 100 + 0.5)
	if pct <= 0 then
		return nil
	end
	local it = item(def, nil, pct)
	it.name = "Rage +" .. pct .. "%"
	return {it}
end

-- Reprisal: the window after the cast of a spell with a Reprisal rune (supports.lua keeps the end time)
function S.reprisal(player, now, def)
	local key = ChaosSupports and ChaosSupports.config and ChaosSupports.config.storageReprisalUntil or 7109992
	local left = secondsLeft(player:getStorageValue(key))
	return left and {item(def, left)} or nil
end

-- the Iron Palm stun on a player (monk_combat.lua keeps the end in ChaosMonk.pvpStun; the bar is told at once)
function S.stun(player, now, def)
	local M = ChaosMonk
	local left = M and M.pvpStunLeft and M.pvpStunLeft(player:getId(), now)
	return left and {item(def, left)} or nil
end

-- the Templar aura the player is under (templar_combat.lua, ChaosTemplar.auraState): whose, the damage it takes off
-- (also the stacks, in percent) and the Sentinel's regeneration. No timer: it lasts while the Templar is near, and the
-- text changes only when the aura does, so a quiet aura costs no traffic.
local AURA_NAMES = {[23] = "Templar", [24] = "Inquisitor", [25] = "Sentinel"}
function S.templarAura(player, now, def)
	local T = ChaosTemplar
	local aura = T and T.activeAura and T.activeAura(player:getId(), now)
	if not aura then
		return nil
	end
	local pct = math.floor((aura.reduction or 0) * 100 + 0.5)
	local own = aura.source == player:getId()
	local source = not own and Player and Player(aura.source) or nil
	local who = own and "your" or (source and (source:getName() .. "'s") or "a Templar's")
	local kind = "Templar"
	local vocOf = own and player or source
	if vocOf and vocOf.getVocation and vocOf:getVocation() then
		kind = AURA_NAMES[vocOf:getVocation():getId()] or kind
	end
	local it = item(def, nil, pct)
	it.name = clip(own and ("Your " .. kind .. " Aura") or ((source and source:getName() or "A Templar") .. "'s Aura"), B.cfg.maxName)
	local text = string.format("Under %s %s aura: %d%% less damage taken", who, kind, pct)
	if (aura.regenPct or 0) > 0 then
		text = text .. string.format(", %.1f%% of your maximum health back every second", aura.regenPct * 100)
	end
	if aura.bastion then
		text = text .. " (Bastion)"
	end
	it.desc = clip(text .. ".", B.cfg.maxDesc)
	return {it}
end

-- the vigils (vigils.lua): ChaosVigils.buffItem(player, def.vigil, now) -> {name, desc, stacks} or nil
function S.vigils(player, now, def)
	local X = ChaosVigils
	local it = X and X.buffItem and X.buffItem(player, def.vigil, now)
	if not it then
		return nil
	end
	local out = item(def, nil, it.stacks)
	out.name, out.desc = clip(it.name or def.name, B.cfg.maxName), clip(it.desc or def.desc, B.cfg.maxDesc)
	return {out}
end

-- season modes (season_modes.lua): ChaosSeason.modesBuffItem(player, def) returns the item or nil
function S.seasonMode(player, now, def)
	local X = ChaosSeason
	if not (X and X.modesBuffItem) then
		return nil
	end
	local it = X.modesBuffItem(player, def)
	if not it then
		return nil
	end
	local out = item(def, it.leftMs)
	out.name, out.desc = clip(it.name or def.name, B.cfg.maxName), clip(it.desc or def.desc, B.cfg.maxDesc)
	return {out}
end

-- community goals (community.lua): ChaosCommunity.buffItems(player, def) -> the open stage windows, or with def.week the
-- week's world modifiers
function S.community(player, now, def)
	local X = ChaosCommunity
	if not (X and X.buffItems) then
		return nil
	end
	local list = X.buffItems(player, def)
	for _, it in ipairs(list or {}) do
		it.name, it.desc = clip(it.name, B.cfg.maxName), clip(it.desc, B.cfg.maxDesc)
	end
	return list
end

-- the Ember Descent's boons (def.kind "buff") and curses ("debuff") of the run the player is in (descent.lua)
function S.descent(player, now, def)
	local X = ChaosDescent
	if not (X and X.buffItems) then
		return nil
	end
	local list = X.buffItems(player, def.kind)
	for _, it in ipairs(list or {}) do
		it.name, it.desc = clip(it.name, B.cfg.maxName), clip(it.desc, B.cfg.maxDesc)
	end
	return list
end

-- the Ember Blessings (blessings.lua): the blessing of def.blessing while it runs, with the time left
function S.blessings(player, now, def)
	local X = ChaosBlessings
	local it = X and X.buffItem and X.buffItem(player, def.blessing)
	if not it then
		return nil
	end
	local out = item(def, it.leftMs)
	out.name, out.desc = clip(it.name or def.name, B.cfg.maxName), clip(it.desc or def.desc, B.cfg.maxDesc)
	return {out}
end

-- the professions' experience bonus (professions.lua): ChaosProfessions.buffItem(player, def) -> {name, desc} or nil
function S.professions(player, now, def)
	local X = ChaosProfessions
	local it = X and X.buffItem and X.buffItem(player, def)
	if not it then
		return nil
	end
	-- the whole percent as stacks (shown on the icon, as Rage does), so a new level is sent at once
	local whole = math.floor(tonumber(it.pct) or 0)
	local out = item(def, nil, whole >= 1 and whole or nil)
	out.name, out.desc = clip(it.name or def.name, B.cfg.maxName), clip(it.desc or def.desc, B.cfg.maxDesc)
	return {out}
end

-- time-friendly progression (catchup.lua): ChaosCatchup.buffItem(player, def.part) -> {desc, leftMs, stacks} or nil
function S.catchup(player, now, def)
	local X = ChaosCatchup
	local it = X and X.buffItem and X.buffItem(player, def.part)
	if not it then
		return nil
	end
	local out = item(def, it.leftMs, it.stacks)
	out.desc = clip(it.desc or def.desc, B.cfg.maxDesc)
	return {out}
end

-- the Ashen Sepulchre's boss debuffs of the fight the player is in (raid.lua)
function S.raid(player, now, def)
	local X = ChaosRaid
	if not (X and X.buffItems) then
		return nil
	end
	local list = X.buffItems(player, def.kind)
	for _, it in ipairs(list or {}) do
		it.name, it.desc = clip(it.name, B.cfg.maxName), clip(it.desc, B.cfg.maxDesc)
	end
	return list
end

-- ------------------------------------------------------------------------------------------------ conditions
-- the stacks of a condition buff (def.stacks names the rule)
B.stackRules = {
	bushido = function(player, now)
		local C = ChaosClasses
		if C and C.bushidoStacks then
			local n = C.bushidoStacks(player:getId(), C.now and C.now() or now)
			return n > 0 and n or nil
		end
		return nil
	end
}

local function findCondition(player, def)
	local ctype = constant(def.cond.type)
	if not ctype then
		return nil
	end
	for _, idName in ipairs(def.cond.ids or {"CONDITIONID_COMBAT"}) do
		local id = constant(idName)
		if id then
			for _, sub in ipairs(def.cond.subs or {def.cond.sub or 0}) do
				local c = player:getCondition(ctype, id, sub)
				if c then
					return c
				end
			end
		end
	end
	return nil
end

-- every buff and debuff the character has now: a list of items sorted by (kind, prio, key)
function B.collect(player, nowMs)
	nowMs = nowMs or B.nowMs()
	local out, seen = {}, {}
	local function push(it)
		if it and it.key and not seen[it.key] then
			seen[it.key] = true
			out[#out + 1] = it
		end
	end
	for _, def in ipairs(B.entries) do
		if def.cond then
			local c = findCondition(player, def)
			if c then
				local ticks = tonumber(c:getTicks()) or 0
				-- -1 = no end (a permanent condition): shown without a timer; 0 or less of a timed one is over
				local it
				if ticks > 0 then
					it = item(def, ticks)
				elseif ticks == -1 then
					it = item(def, nil)
				end
				if it then
					local rule = def.stacks and B.stackRules[def.stacks]
					if rule then
						it.stacks = safe(rule, player, nowMs)
					end
					push(it)
				end
			end
		elseif def.source then
			local fn = S[def.source]
			if fn then
				local ok, list = pcall(fn, player, nowMs, def)
				if ok and list then
					for _, it in ipairs(list) do
						push(it)
					end
				elseif not ok then
					B.lastError = tostring(list)
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "buff"
		end
		if a.prio ~= b.prio then
			return a.prio < b.prio
		end
		return a.key < b.key
	end)
	while #out > B.cfg.maxEntries do
		out[#out] = nil
	end
	return out
end

-- collect, but at most once per `ttlMs` for a character (the bar and the party frames both ask): the cached list
B.cache = B.cache or {}
function B.get(player, nowMs, ttlMs)
	nowMs = nowMs or B.nowMs()
	local id = player:getId()
	local c = B.cache[id]
	if c and nowMs >= c.at and nowMs - c.at < (ttlMs or 0) then
		return c.items
	end
	local items = B.collect(player, nowMs)
	B.cache[id] = {at = nowMs, items = items}
	return items
end

function B.forget(id)
	B.cache[id] = nil
end

-- ------------------------------------------------------------------------------------------------ the wire
local function whole(ms)
	return math.max(1, math.floor(ms + 0.5))
end

-- the full wire entry of an item
function B.wire(it)
	return {k = it.key, n = clip(it.name, B.cfg.maxName), d = clip(it.desc, B.cfg.maxDesc), i = it.icon,
		t = it.kind == "debuff" and 1 or 0, l = it.leftMs and whole(it.leftMs) or nil, s = it.stacks}
end

-- the whole bar as a `full` payload; `sent` (a table, may be empty) is reset to what this message says
function B.full(sent, items, nowMs)
	for key in pairs(sent) do
		sent[key] = nil
	end
	local list = {}
	for _, it in ipairs(items) do
		list[#list + 1] = B.wire(it)
		sent[it.key] = {name = it.name, desc = it.desc, icon = it.icon, kind = it.kind, stacks = it.stacks,
			endAt = it.leftMs and (nowMs + it.leftMs) or nil}
	end
	return {list = list}
end

-- the difference between what the client holds (`sent`, updated in place) and the items now; nil when nothing changed
function B.diff(sent, items, nowMs)
	local add, upd, del, seen = {}, {}, {}, {}
	for _, it in ipairs(items) do
		seen[it.key] = true
		local p = sent[it.key]
		local endAt = it.leftMs and (nowMs + it.leftMs) or nil
		if not p or p.name ~= it.name or p.desc ~= it.desc or p.icon ~= it.icon or p.kind ~= it.kind
				or (p.endAt == nil) ~= (endAt == nil) then
			add[#add + 1] = B.wire(it)
			sent[it.key] = {name = it.name, desc = it.desc, icon = it.icon, kind = it.kind, stacks = it.stacks, endAt = endAt}
		elseif p.stacks ~= it.stacks or (endAt and math.abs(endAt - p.endAt) > B.cfg.toleranceMs) then
			upd[#upd + 1] = {k = it.key, l = it.leftMs and whole(it.leftMs) or nil, s = it.stacks}
			p.stacks, p.endAt = it.stacks, endAt
		end
	end
	for key in pairs(sent) do
		if not seen[key] then
			del[#del + 1] = key
			sent[key] = nil
		end
	end
	table.sort(del)
	if #add == 0 and #upd == 0 and #del == 0 then
		return nil
	end
	return {add = #add > 0 and add or nil, upd = #upd > 0 and upd or nil, del = #del > 0 and del or nil}
end

-- the first few buffs / debuffs, for the mini row under a party frame: {{icon, kind (0 buff / 1 debuff), leftMs, name}}
function B.brief(items, limit)
	local list = {}
	limit = limit or B.cfg.partyEntries
	-- debuffs first: what a healer needs to see
	for _, wantDebuff in ipairs({true, false}) do
		for _, it in ipairs(items) do
			if (it.kind == "debuff") == wantDebuff and #list < limit then
				list[#list + 1] = {i = it.icon, t = wantDebuff and 1 or 0, l = it.leftMs and whole(it.leftMs) or nil,
					n = clip(it.name, B.cfg.maxName)}
			end
		end
	end
	return list
end

-- registry check (tests, tools): every key unique, a known kind, an own "buff:<name>" icon, a name and a description
function B.validate()
	local problems = {}
	for _, def in ipairs(B.entries) do
		if def.kind ~= "buff" and def.kind ~= "debuff" then
			problems[#problems + 1] = def.key .. ": kind"
		end
		if not (def.icon or ""):match("^buff:[%w_]+$") then
			problems[#problems + 1] = def.key .. ": icon " .. tostring(def.icon)
		end
		if (def.name or "") == "" or (def.desc or "") == "" then
			problems[#problems + 1] = def.key .. ": text"
		end
		if not def.cond and not (def.source and B.sources[def.source]) then
			problems[#problems + 1] = def.key .. ": no source"
		end
	end
	return problems
end

return B
