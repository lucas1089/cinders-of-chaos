-- Run from the server/ folder: luajit tests/buffs_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the buff bar's rules (data/lib/chaos_buffs.lua) against a mocked player: the registry (unique keys, kinds, icon
-- forms, every entry has a source), conditions found by type / id / sub id with their time left, the engine ones (haste,
-- poison, in fight ...), the Chaos class buffs by sub id, skull timers, the sources (world buffs, Victory, world events,
-- double experience, trial stacks, chi, Rage, Reprisal), sorting and the cap, the wire entries, and the diff (add,
-- update on stacks or a recast, remove, nothing when quiet, the tolerance), the party brief; and that the sub ids of the
-- registry are the ones the class spells use and the opcode is free.
dofile("data/scripts/chaos/chaos_constants.lua")

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local t = f:read("*a")
	f:close()
	return t
end

-- ------------------------------------------------------------------ engine constants and a mocked player
local n = 0
for _, name in ipairs({"CONDITION_POISON", "CONDITION_FIRE", "CONDITION_ENERGY", "CONDITION_BLEEDING", "CONDITION_HASTE",
	"CONDITION_PARALYZE", "CONDITION_INVISIBLE", "CONDITION_LIGHT", "CONDITION_MANASHIELD", "CONDITION_INFIGHT",
	"CONDITION_DRUNK", "CONDITION_REGENERATION", "CONDITION_DROWN", "CONDITION_MUTED", "CONDITION_ATTRIBUTES",
	"CONDITION_FREEZING", "CONDITION_DAZZLED", "CONDITION_CURSED", "CONDITION_PACIFIED"}) do
	n = n + 1
	_G[name] = n
end
CONDITIONID_DEFAULT, CONDITIONID_COMBAT = 0, 1
SKULL_NONE, SKULL_WHITE, SKULL_RED, SKULL_BLACK = 0, 3, 4, 5

local now = 1000000
local realTime = os.time
local function mockPlayer(id, conds, extra)
	local p = {_id = id or 1, _conds = conds or {}, _store = {}, _skull = 0, _skullTime = 0, _hp = 100, _max = 100, _voc = 4}
	for k, v in pairs(extra or {}) do
		p[k] = v
	end
	function p:getId() return self._id end
	function p:getCondition(ctype, cid, sub)
		local c = self._conds[ctype .. ":" .. cid .. ":" .. (sub or 0)]
		if not c then
			return nil
		end
		return {getTicks = function() return c end}
	end
	function p:getStorageValue(key) return self._store[key] or -1 end
	function p:getSkull() return self._skull end
	function p:getSkullTime() return self._skullTime end
	function p:getHealth() return self._hp end
	function p:getMaxHealth() return self._max end
	function p:getPosition() return {x = 100, y = 100, z = 7} end
	function p:getVocation() return {getId = function() return self._voc end} end
	return p
end
local function cond(player, ctype, cid, sub, ticks)
	player._conds[ctype .. ":" .. cid .. ":" .. (sub or 0)] = ticks
end
local function byKey(list, key)
	for _, it in ipairs(list) do
		if it.key == key then
			return it
		end
	end
	return nil
end

dofile("data/lib/chaos_buffs.lua")
local B = ChaosBuffs

-- ------------------------------------------------------------------ the registry
eq(#B.validate(), 0, "registry validates: " .. table.concat(B.validate(), "; "))
ok(#B.entries >= 55, "at least 55 entries: " .. #B.entries)
local seen = {}
for _, def in ipairs(B.entries) do
	ok(not seen[def.key], "unique key " .. def.key)
	seen[def.key] = true
	ok(def.key:match("^[%l%d_]+$") ~= nil, "key form " .. def.key)
	ok(#def.name <= B.cfg.maxName, "name length " .. def.key)
	ok(#def.desc <= B.cfg.maxDesc, "description length " .. def.key)
end
for _, key in ipairs({"haste", "regen", "fed", "poison", "burning", "freezing", "drowning", "energy", "paralyze", "drunk",
		"manashield", "invisible", "infight", "skull_white", "skull_red", "skull_black", "world_xp", "world_loot", "world_skill",
		"victory", "golden_hour", "chaos_storm", "double_xp", "trial_stacks", "reprisal", "rage", "chi", "stealth", "bloodrage",
		"bushido", "blood_pact", "bone_shield", "chi_ward", "rally"}) do
	ok(B.byKey[key] ~= nil, "registry has " .. key)
end
-- every entry draws our own icon: "buff:<name>", and that PNG (and the key's, the client's fallback) is in the client
-- overlay at the bar's cell size, 26 x 26 (client/tools/gen_buff_icons.py; the width and height sit at bytes 17..24)
local ICONS = "../client/overlay/data/images/game/buffs/"
local function pngSize(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local head = f:read(24)
	f:close()
	if not head or #head < 24 or head:sub(2, 4) ~= "PNG" then
		return nil
	end
	local function u32(i)
		local a, b, c, d = head:byte(i, i + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	return u32(17), u32(21)
end
for _, def in ipairs(B.entries) do
	local name = def.icon:match("^buff:([%w_]+)$")
	ok(name ~= nil, "own icon form " .. def.key .. ": " .. tostring(def.icon))
	for _, n in ipairs({name or "?", def.key}) do
		local w, h = pngSize(ICONS .. n .. ".png")
		ok(w == 26 and h == 26, "icon " .. n .. ".png of " .. def.key .. " exists at 26x26: " .. tostring(w) .. "x" .. tostring(h))
	end
end
eq(B.byKey.poison.kind, "debuff", "poison is a debuff"); eq(B.byKey.haste.kind, "buff", "haste is a buff")
eq(B.byKey.paralyze.name, "Slowed", "paralyze is shown as slowed")

-- the sub ids of the registry are the ones the class code uses
dofile("data/scripts/chaos/necro_config.lua")
local necro = dofile("data/scripts/chaos/necro_config.lua")
local expectSub = {
	blood_pact = 71001, red_frenzy = 71002, rally = 71003, barkskin = 71004, divine_ward = 71005, soul_aegis = 71006,
	phantom_veil = 71007, dash = 71008, iron_will = 71009,
	stealth = Chaos.classes.subId.stealth, poison_blades = Chaos.classes.subId.poisonBlades, counter = Chaos.classes.subId.counter,
	bushido = Chaos.classes.subId.bushido, bloodrage = Chaos.classes.subId.bloodrage,
	bone_aura = necro.subId.boneAura, bone_shield = necro.subId.boneShield
}
for key, sub in pairs(expectSub) do
	eq(B.byKey[key] and B.byKey[key].cond.sub, sub, "sub id of " .. key)
end
local common = readFile("data/spells/chaos/_common.lua")
if common then
	-- (the registry calls the Red Frenzy "red_frenzy"; the spell file calls its sub id crimson_fury)
	for key, sub in pairs({blood_pact = 71001, crimson_fury = 71002, rally = 71003, barkskin = 71004, divine_ward = 71005,
			soul_aegis = 71006, phantom_veil = 71007, dash = 71008, iron_will = 71009}) do
		ok(common:find(key .. " = " .. sub, 1, true) ~= nil, "ChaosSpell.SUBID has " .. key .. " = " .. sub)
	end
end
dofile("data/scripts/chaos/monk_chi_core.lua")
eq(B.byKey.focus.cond.sub, ChaosMonk.ids.subId.focus, "focus sub id"); eq(B.byKey.chi_ward.cond.sub, ChaosMonk.ids.subId.ward, "ward sub id")
eq(B.byKey.mantra.cond.sub, ChaosMonk.ids.subId.mantra, "mantra sub id"); eq(B.byKey.roll.cond.sub, ChaosMonk.ids.subId.roll, "roll sub id")
eq(B.byKey.breath.cond.sub, ChaosMonk.ids.subId.breath, "breath sub id")
local templar = readFile("data/scripts/chaos/templar_aura_core.lua")
ok(templar and templar:find("zealotry = 71051", 1, true) and templar:find("aegis = 71052", 1, true), "templar sub ids")
eq(B.byKey.zealotry.cond.sub, 71051, "zealotry"); eq(B.byKey.aegis_faith.cond.sub, 71052, "aegis")

-- the opcodes are unique and the two new ones are in the right place
local ops = {}
for name, op in pairs(ChaosOpcodes) do
	ok(ops[op] == nil, "opcode " .. op .. " used twice: " .. name .. " / " .. tostring(ops[op]))
	ops[op] = name
end
eq(ChaosOpcodes.buffs, 234, "buffs opcode"); eq(ChaosOpcodes.partyFrames, 235, "party frames opcode")

-- ------------------------------------------------------------------ conditions
local p = mockPlayer(1)
eq(#B.collect(p, now), 0, "nothing on a clean character")
cond(p, CONDITION_HASTE, CONDITIONID_COMBAT, 0, 12000)
cond(p, CONDITION_POISON, CONDITIONID_COMBAT, 0, 8000)
local list = B.collect(p, now)
eq(#list, 2, "haste and poison"); eq(list[1].key, "haste", "buffs first"); eq(list[2].key, "poison", "then debuffs")
eq(list[1].leftMs, 12000, "time left in ms"); eq(list[2].kind, "debuff", "poison kind")
-- a condition with a sub id is not the plain one
local q = mockPlayer(2)
cond(q, CONDITION_HASTE, CONDITIONID_COMBAT, 71008, 2500)
list = B.collect(q, now)
eq(#list, 1, "only the dash"); eq(list[1].key, "dash", "dash by sub id"); eq(list[1].name, "Flickerdash", "dash name")
-- food is regeneration with the default id; a spell's regeneration the combat id
local f = mockPlayer(3)
cond(f, CONDITION_REGENERATION, CONDITIONID_DEFAULT, 0, 60000)
list = B.collect(f, now)
eq(#list, 1, "food"); eq(list[1].key, "fed", "food is Well Fed")
cond(f, CONDITION_REGENERATION, CONDITIONID_COMBAT, 0, 5000)
list = B.collect(f, now)
eq(#list, 2, "food and a regeneration spell"); eq(byKey(list, "regen").leftMs, 5000, "regen time")
-- in fight: found with the default id
local fi = mockPlayer(4)
cond(fi, CONDITION_INFIGHT, CONDITIONID_DEFAULT, 0, 59000)
eq(B.collect(fi, now)[1].key, "infight", "in fight")
-- a permanent condition has no timer, an expired one is not listed
local perm = mockPlayer(5)
cond(perm, CONDITION_MANASHIELD, CONDITIONID_COMBAT, 0, -1)
cond(perm, CONDITION_DRUNK, CONDITIONID_COMBAT, 0, 0)
list = B.collect(perm, now)
eq(#list, 1, "permanent listed, expired not"); eq(list[1].key, "manashield", "mana shield"); eq(list[1].leftMs, nil, "no timer")
-- class buffs
local c = mockPlayer(6)
cond(c, CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, Chaos.classes.subId.bloodrage, 9000)
cond(c, CONDITION_INVISIBLE, CONDITIONID_COMBAT, Chaos.classes.subId.stealth, 3000)
cond(c, CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, 71031, 7000)
list = B.collect(c, now)
eq(#list, 3, "three class buffs")
ok(byKey(list, "bloodrage") and byKey(list, "stealth") and byKey(list, "chi_ward"), "bloodrage, stealth, chi ward")
-- Bushido stacks from the class module
ChaosClasses = {bushidoStacks = function(id, t) return id == 7 and 4 or 0 end, now = function() return now end}
local bu = mockPlayer(7)
cond(bu, CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, Chaos.classes.subId.bushido, 20000)
eq(byKey(B.collect(bu, now), "bushido").stacks, 4, "bushido stacks")
ChaosClasses = nil
eq(byKey(B.collect(bu, now), "bushido").stacks, nil, "no class module: no stacks, still listed")

-- ------------------------------------------------------------------ skulls
local sk = mockPlayer(8, nil, {_skull = SKULL_RED, _skullTime = 120000})
list = B.collect(sk, now)
eq(#list, 1, "red skull"); eq(list[1].key, "skull_red", "red skull key"); eq(list[1].leftMs, 120000, "skull time")
sk._skullTime = 0
eq(#B.collect(sk, now), 0, "a skull without time is not listed")
sk._skull, sk._skullTime = SKULL_WHITE, 900000
eq(B.collect(sk, now)[1].key, "skull_white", "white skull")

-- ------------------------------------------------------------------ sources
-- world buffs (global storages), the expiry in os.time seconds
local realNow = os.time()
os.time = function() return realNow end
Game = {getStorageValue = function(key)
	local list = Chaos.shopServices.worldBuffs
	for i, b in ipairs(list) do
		if key == Chaos.shopServices.worldBuffStorage + i and b.id == "loot" then
			return realNow + 1800
		end
	end
	return -1
end}
local w = mockPlayer(9)
list = B.collect(w, now)
eq(#list, 1, "one world buff"); eq(list[1].key, "world_loot", "world loot"); eq(list[1].leftMs, 1800000, "world buff time")
ok(list[1].desc:find("25%%") ~= nil, "world buff text from the store config: " .. list[1].desc)
-- the double experience potion
w._store[6000] = realNow + 3600
eq(byKey(B.collect(w, now), "double_xp").leftMs, 3600000, "double xp time")
w._store[6000] = realNow - 5
eq(byKey(B.collect(w, now), "double_xp"), nil, "double xp over")
-- Victory buff: server-wide, and area-wide only inside the area
ChaosInvasionCore = {buffActive = function(b, t) return t < b.endsAt end,
	inArea = function(pos, area) return pos.x >= area.from.x and pos.x <= area.to.x and pos.z == 7 end}
ChaosInvasion = {buff = {endsAt = realNow + 600, xp = 1.1, scope = "server", name = "the Pass"}}
local v = byKey(B.collect(w, now), "victory")
ok(v ~= nil and v.leftMs == 600000, "victory buff everywhere"); ok(v.desc:find("+10%%") ~= nil, "victory text: " .. v.desc)
ChaosInvasion.buff.scope, ChaosInvasion.buff.area = "area", {from = {x = 200}, to = {x = 300}}
eq(byKey(B.collect(w, now), "victory"), nil, "area victory buff outside the area")
ChaosInvasion.buff.area = {from = {x = 50}, to = {x = 150}}
ok(byKey(B.collect(w, now), "victory") ~= nil, "area victory buff inside the area")
ChaosInvasion.buff.endsAt = realNow - 1
eq(byKey(B.collect(w, now), "victory"), nil, "victory buff over")
-- world events: only inside the area
ChaosWorldEvents = {active = {kind = "golden", area = {from = {x = 50}, to = {x = 150}, name = "Thais fields"}, endsAt = realNow + 900}}
local g = byKey(B.collect(w, now), "golden_hour")
ok(g ~= nil and g.leftMs == 900000, "golden hour inside the area"); ok(g.desc:find("Thais fields", 1, true) ~= nil, "golden hour names the area: " .. g.desc)
ChaosWorldEvents.active.kind = "storm"
ok(byKey(B.collect(w, now), "chaos_storm") ~= nil and byKey(B.collect(w, now), "golden_hour") == nil, "chaos storm, not golden hour")
ChaosWorldEvents.active.area = {from = {x = 500}, to = {x = 600}}
eq(byKey(B.collect(w, now), "chaos_storm"), nil, "storm elsewhere")
-- the day's events with a bonus; the runtime ones are not listed twice
ChaosEvents = {dynamic = {worldEvent = {id = "worldEvent"}},
	active = function() return {{id = "doubleXp", name = "Double Experience Weekend", description = "Twice the experience.", bonus = {xp = 2}},
		{id = "worldEvent", name = "Golden Hour", bonus = {loot = 1.25}}, {id = "quiet", name = "Nothing"}} end}
list = B.collect(w, now)
ok(byKey(list, "event_doubleXp") ~= nil, "a calendar event"); eq(byKey(list, "event_worldEvent"), nil, "dynamic events are not doubled")
eq(byKey(list, "event_quiet"), nil, "an event without a bonus"); eq(byKey(list, "event_doubleXp").leftMs, nil, "calendar events have no timer")
ChaosEvents = nil
-- trial stacks (the oldest kill falls first)
ChaosPassiveCache = {[10] = {killStackPct = 4, killStackMax = 6, killStackMs = 6000}}
ChaosTrials = {nodeState = {[10] = {stackKills = {now - 4000, now - 1000}}}}
ChaosTrialsCore = {stackCount = function(s, b, t)
	local k = 0
	for _, x in ipairs(s.stackKills) do if t - x <= b.killStackMs then k = k + 1 end end
	return math.min(k, b.killStackMax)
end, heldNodes = function() return {{name = "Bloodlust", fx = {killStackPct = 4}}} end}
ChaosTrials.tierCleared = function() return 1 end
ChaosTrials.picks = function() return {} end
local t = mockPlayer(10)
local ts = byKey(B.collect(t, now), "trial_stacks")
ok(ts ~= nil, "trial stacks"); eq(ts.stacks, 2, "two stacks"); eq(ts.leftMs, 2000, "the oldest kill falls first")
eq(ts.name, "Bloodlust", "named after the node"); ok(ts.desc:find("+4%%") ~= nil, "stack text: " .. ts.desc)
ChaosTrials.nodeState[10].stackKills = {now - 7000}
eq(byKey(B.collect(t, now), "trial_stacks"), nil, "all stacks faded")
ChaosPassiveCache = nil
-- chi
dofile("data/scripts/chaos/monk_chi_core.lua")
local monk = mockPlayer(11, nil, {_voc = 17})
monk._store[ChaosMonk.ids.storage.chi] = 3
monk._store[ChaosMonk.ids.storage.chiTime] = realNow - 2
local chi = byKey(B.collect(monk, now), "chi")
ok(chi ~= nil, "chi listed for a monk"); eq(chi.stacks, 3, "chi stacks")
eq(chi.leftMs, (ChaosMonk.cfg.chi.decaySec - 2) * 1000, "chi decays")
local warrior = mockPlayer(12, nil, {_voc = 4})
warrior._store[ChaosMonk.ids.storage.chi] = 3
warrior._store[ChaosMonk.ids.storage.chiTime] = realNow
eq(byKey(B.collect(warrior, now), "chi"), nil, "chi only for the monk line")
-- Rage (Berserker): the bonus grows as health drops
dofile("data/scripts/chaos/classes.lua")
local bz = mockPlayer(13, nil, {_voc = Chaos.classes.ids.berserker})
eq(byKey(B.collect(bz, now), "rage"), nil, "no rage at full health")
bz._hp = 40
local rage = byKey(B.collect(bz, now), "rage")
ok(rage ~= nil and rage.stacks > 0 and rage.leftMs == nil, "rage at low health, no timer"); ok(rage.name:find("Rage +", 1, true) ~= nil, "rage name: " .. rage.name)
local nb = mockPlayer(14, nil, {_voc = 4}); nb._hp = 10
eq(byKey(B.collect(nb, now), "rage"), nil, "rage only for the berserker")
-- Reprisal window
local rp = mockPlayer(15)
rp._store[7109992] = realNow + 8
eq(byKey(B.collect(rp, now), "reprisal").leftMs, 8000, "reprisal window")
os.time = realTime
Game = nil
-- a failing source never breaks the bar
local savedSource = B.sources.chi
B.sources.chi = function() error("boom") end
eq(#B.collect(mockPlayer(16), now), 0, "a failing source adds nothing")
ok(B.lastError ~= nil and B.lastError:find("boom") ~= nil, "and is remembered")
B.sources.chi = savedSource
-- the Iron Palm stun on a player: shown while monk_combat.lua holds it, with the time left
local sv = mockPlayer(17)
ChaosMonk.pvpStun[17] = {untilMs = now + 800}
local st = byKey(B.collect(sv, now), "stunned")
ok(st ~= nil and st.kind == "debuff" and st.leftMs == 800, "stunned debuff with its time")
ChaosMonk.pvpStun[17] = {untilMs = now - 1}
eq(byKey(B.collect(sv, now), "stunned"), nil, "a stun that is over is not shown")
ChaosMonk.pvpStun[17] = nil
cond(sv, CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, ChaosMonk.ids.subId.stunImmune, 6000)
eq(byKey(B.collect(sv, now), "stun_immune").leftMs, 6000, "stun immunity shown")
-- the Templar aura: whose, how much, the Sentinel's regeneration; no timer
dofile("data/scripts/chaos/templar_aura_core.lua")
local named = {[30] = mockPlayer(30, nil, {_voc = 25}), [31] = mockPlayer(31, nil, {_voc = 23})}
named[30].getName = function() return "Brann" end
named[31].getName = function() return "Odo" end
Player = function(id) return named[id] end
local member = mockPlayer(18)
eq(byKey(B.collect(member, now), "templar_aura"), nil, "no aura, no entry")
ChaosTemplar.auraState = {[18] = {reduction = 0.12, regenPct = 0.004, source = 30, untilMs = now + 1500}}
local au = byKey(B.collect(member, now), "templar_aura")
ok(au ~= nil and au.kind == "buff" and au.leftMs == nil, "aura: a buff without a timer")
eq(au.stacks, 12, "aura stacks: the reduction in percent"); eq(au.name, "Brann's Aura", "whose aura")
eq(au.desc, "Under Brann's Sentinel aura: 12% less damage taken, 0.4% of your maximum health back every second.", "aura text")
ChaosTemplar.auraState = {[31] = {reduction = 0.06, regenPct = 0, source = 31, untilMs = now + 1500}}
au = byKey(B.collect(named[31], now), "templar_aura")
eq(au.name, "Your Templar Aura", "own aura"); eq(au.desc, "Under your Templar aura: 6% less damage taken.", "no regeneration text")
ChaosTemplar.auraState = {[18] = {reduction = 0.16, regenPct = 0, source = 31, untilMs = now + 1500, bastion = true}}
ok(byKey(B.collect(member, now), "templar_aura").desc:find("Bastion", 1, true) ~= nil, "Bastion named")
-- no spam: the same aura a second later is no change; another Templar's is
local sentA = {}
ChaosTemplar.auraState = {[18] = {reduction = 0.12, regenPct = 0.004, source = 30, untilMs = now + 1500}}
B.full(sentA, B.collect(member, now), now)
ChaosTemplar.auraState = {[18] = {reduction = 0.12, regenPct = 0.004, source = 30, untilMs = now + 2500}}
eq(B.diff(sentA, B.collect(member, now + 1000), now + 1000), nil, "an unchanged aura sends nothing")
ChaosTemplar.auraState = {[18] = {reduction = 0.06, regenPct = 0, source = 31, untilMs = now + 2500}}
local ad = B.diff(sentA, B.collect(member, now + 1000), now + 1000)
ok(ad and ad.add and ad.add[1].k == "templar_aura" and ad.add[1].s == 6, "a different aura is sent")
ChaosTemplar.auraState = {}
ad = B.diff(sentA, B.collect(member, now + 2000), now + 2000)
ok(ad and ad.del and ad.del[1] == "templar_aura", "leaving the aura removes it")
Player = nil

-- ------------------------------------------------------------------ order and cap
local many = mockPlayer(17)
for _, def in ipairs(B.entries) do
	if def.cond then
		cond(many, _G[def.cond.type], _G[def.cond.ids[1]], def.cond.sub, 5000)
	end
end
list = B.collect(many, now)
eq(#list, B.cfg.maxEntries, "the bar is capped")
local lastKind = "buff"
for _, it in ipairs(list) do
	ok(not (lastKind == "debuff" and it.kind == "buff"), "buffs before debuffs: " .. it.key)
	lastKind = it.kind
end

-- ------------------------------------------------------------------ the wire
local wire = B.wire({key = "haste", name = "Haste", desc = "You move faster.", icon = "spell:utani hur", kind = "buff", leftMs = 12000.4, stacks = 3})
eq(wire.k, "haste", "wire key"); eq(wire.t, 0, "buff = 0"); eq(wire.l, 12000, "whole ms"); eq(wire.s, 3, "stacks")
eq(B.wire({key = "x", name = "X", desc = "", icon = "buff:x", kind = "debuff"}).t, 1, "debuff = 1")
eq(B.wire({key = "x", name = "X", desc = "", icon = "buff:x", kind = "debuff"}).l, nil, "no timer = no l")
eq(#B.wire({key = "x", name = string.rep("n", 99), desc = string.rep("d", 999), icon = "buff:x", kind = "buff"}).n, B.cfg.maxName, "name is cut")
eq(#B.wire({key = "x", name = "n", desc = string.rep("d", 999), icon = "buff:x", kind = "buff"}).d, B.cfg.maxDesc, "description is cut")

-- ------------------------------------------------------------------ the diff
local items = {{key = "haste", name = "Haste", desc = "d", icon = "i", kind = "buff", leftMs = 10000, prio = 1},
	{key = "poison", name = "Poisoned", desc = "d", icon = "i", kind = "debuff", leftMs = 6000, prio = 1}}
local sent = {}
local full = B.full(sent, items, now)
eq(#full.list, 2, "full has both")
eq(B.diff(sent, items, now), nil, "nothing changed: nothing sent")
-- time passes: the same buff 1 s later is no change
local later = {{key = "haste", name = "Haste", desc = "d", icon = "i", kind = "buff", leftMs = 9000, prio = 1},
	{key = "poison", name = "Poisoned", desc = "d", icon = "i", kind = "debuff", leftMs = 5000, prio = 1}}
eq(B.diff(sent, later, now + 1000), nil, "a countdown is not a change")
-- a recast moves the end by more than the tolerance
local recast = {{key = "haste", name = "Haste", desc = "d", icon = "i", kind = "buff", leftMs = 12000, prio = 1},
	{key = "poison", name = "Poisoned", desc = "d", icon = "i", kind = "debuff", leftMs = 4000, prio = 1}}
local d = B.diff(sent, recast, now + 2000)
ok(d ~= nil and d.upd ~= nil and #d.upd == 1 and d.upd[1].k == "haste" and d.upd[1].l == 12000, "a recast is an update")
eq(d.add, nil, "no add"); eq(d.del, nil, "no del")
eq(B.diff(sent, recast, now + 2000), nil, "and then it is the new normal")
-- stacks
recast[1].stacks = 2
d = B.diff(sent, recast, now + 2000)
ok(d and d.upd and d.upd[1].s == 2, "stacks change is an update")
-- new, gone
recast[3] = {key = "burning", name = "Burning", desc = "d", icon = "i", kind = "debuff", leftMs = 3000, prio = 1}
table.remove(recast, 2)
d = B.diff(sent, recast, now + 2000)
ok(d and d.add and #d.add == 1 and d.add[1].k == "burning" and d.add[1].t == 1, "a new debuff is an add")
ok(d.del and #d.del == 1 and d.del[1] == "poison", "a gone one is a del")
-- a timer that appears or disappears (a permanent buff getting an end) is an add (the entry is replaced)
recast[1].leftMs = nil
d = B.diff(sent, recast, now + 2000)
ok(d and d.add and d.add[1].k == "haste" and d.add[1].l == nil, "timer gone: replaced")
-- a text change replaces the entry
recast[1].desc = "changed"
d = B.diff(sent, recast, now + 2000)
ok(d and d.add and d.add[1].d == "changed", "text change replaces")
-- everything gone
d = B.diff(sent, {}, now + 3000)
ok(d and #d.del == 2 and d.add == nil and d.upd == nil, "all gone: only dels")
eq(next(sent), nil, "sent is empty again")

-- ------------------------------------------------------------------ cache and brief
local calls = 0
local cp = mockPlayer(20)
local origCollect = B.collect
B.collect = function(player, t) calls = calls + 1 return origCollect(player, t) end
B.get(cp, now, 900); B.get(cp, now + 500, 900); B.get(cp, now + 950, 900)
eq(calls, 2, "collect runs at most once per ttl")
B.collect = origCollect
B.forget(20)
local brief = B.brief({{kind = "buff", icon = "a", leftMs = 5000}, {kind = "debuff", icon = "b", leftMs = nil}, {kind = "buff", icon = "c"},
	{kind = "buff", icon = "d"}, {kind = "buff", icon = "e"}, {kind = "buff", icon = "f"}}, 3)
eq(B.brief({{kind = "buff", icon = "buff:templar_aura", name = "Brann's Aura"}})[1].n, "Brann's Aura", "brief carries the name")
eq(#brief, 3, "brief is capped"); eq(brief[1].i, "b", "debuffs first in the brief"); eq(brief[1].t, 1, "brief kind"); eq(brief[2].l, 5000, "brief time")

if fails > 0 then
	print(fails .. " of " .. checks .. " checks FAILED")
	os.exit(1)
end
print("buffs tests OK (" .. checks .. " checks)")
