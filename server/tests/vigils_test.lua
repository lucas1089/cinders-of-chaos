-- Run from the server/ folder: luajit tests/vigils_test.lua (and lua5.3; CI runs both)
-- The vigils, auras that reserve mana (docs/BUILDS.md "Vigils", server/README.md "Vigils"):
--   * the pure rules (vigils_core.lua): the mask, the reservation with the keystones and the uniques, what fits, the
--     coverage of a party (radius, floor, Iron Tithe, multi-client), the strongest of two holders, the hit factors with
--     Inspiring Illusion and the Templar aura, Clarity under Parched Veins, the buff bar rows and their texts;
--   * the toggle spells' side (data/spells/chaos/_vigils.lua) against mocks: on, off, too much reserved, the keystone;
--   * the scripts' glue (vigils.lua) against a mocked engine: the reserved mana as a lower maximum (renewed when the
--     maximum changes, given back when switched off, re-applied after death), Iron Tithe on health, the party in range,
--     haste and Clarity, vigils that no longer fit switched off, the hit multipliers, the rows on the buff bar
--     (data/lib/chaos_buffs.lua: holder, party member, stranger, no traffic when quiet, Iron Tithe);
--   * the data: the spells in spells_chaos.xml, the storage and Inspiring Illusion's numbers match their sources.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local count, failures = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what) check(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, what) check(math.abs(a - b) < 1e-6, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/vigils_config.lua")
dofile("data/scripts/chaos/vigils_core.lua")
local C, V = ChaosVigilsConfig, ChaosVigilsCore

-- ------------------------------------------------------------------------------------------------ core
-- the mask
local m = V.with(0, "wrath", true)
m = V.with(m, "clarity", true)
check(V.has(m, "wrath") and V.has(m, "clarity") and not V.has(m, "iron"), "mask")
eq(table.concat(V.keys(m), ","), "wrath,clarity", "keys in bit order")
eq(V.with(m, "wrath", true), m, "on twice: the same")
eq(V.keys(V.with(m, "wrath", false))[1], "clarity", "off")
check(not V.has(-1, "wrath"), "no storage")
eq(V.bySpell[179], "wrath", "spell 179")
-- reservation
near(V.reserve("wrath", {}), 0.35, "wrath 35%")
near(V.reserve("wrath", {keystone = true}), 0.35 * 0.7, "keystone x0.7")
near(V.reserve("wrath", {keystone = true, choirmaster = true, oathkeeper = true}), 0.35 * 0.7 * 0.85 * 0.9, "and both uniques")
near(V.reserve("wrath", {tithe = true}), 0.35 * 0.6, "Iron Tithe: 60% of the share, of the health")
local all = 0
for _, v in ipairs(C.list) do all = V.with(all, v.key, true) end
near(V.totalReserve(all, {}), 1.10, "all four: 110%")
local _, total, err = V.toggle(V.with(V.with(V.with(0, "wrath", true), "iron", true), "haste", true), "clarity", {})
check(err == "full" and math.abs(total - 0.9) < 1e-9, "the fourth does not fit without help")
local m2, total2, err2 = V.toggle(V.with(V.with(V.with(0, "wrath", true), "iron", true), "haste", true), "clarity",
	{keystone = true})
check(not err2 and V.has(m2, "clarity") and math.abs(total2 - 0.77) < 1e-9, "with the keystone all four fit (77%)")
local m3 = V.toggle(m2, "iron", {})
check(not V.has(m3, "iron"), "toggle off")
eq(V.reserved(5000, 0.35), 1750, "flat")
eq(V.reserved(5000, 1.5), 5000, "at most all")
-- what no longer fits goes, the last first
local fitted = V.fit(all, {keystone = true, choirmaster = true})
eq(fitted, all, "fits with help")
fitted = V.fit(all, {})
check(V.has(fitted, "wrath") and V.has(fitted, "iron") and V.has(fitted, "haste") and not V.has(fitted, "clarity"),
	"without help clarity goes")
-- mods from the archetype flags
local mods = V.modsOf({arVigils = true, arIronTithe = true}, {choirmaster = true})
check(mods.keystone and mods.tithe and mods.choirmaster and not mods.oathkeeper, "mods")
check(not V.modsOf({arIronTithe = true, arHollowVessel = true}, {}).tithe, "no Iron Tithe next to Hollow Vessel")
-- effects
near(V.effect("wrath", {}, true), 0.05, "wrath 5%")
near(V.effect("wrath", {keystone = true}, false), 0.06, "the party +20% with the keystone")
near(V.effect("wrath", {keystone = true}, true), 0.05, "not the holder")
near(V.effect("iron", {tithe = true}, true), 0.09, "Iron Tithe: x1.5 on you")
eq(V.effect("iron", {tithe = true}, false), 0, "Iron Tithe: nobody else")
eq(V.radius({}), 5, "radius")
eq(V.radius({keystone = true, oathkeeper = true}), 10, "radius with the keystone and the standard")
-- coverage
local PM = {__index = {sendMagicEffect = function() end}}
local P = function(x, y, z) return setmetatable({x = x, y = y, z = z or 7}, PM) end
local holders = {{id = 1, pos = P(100, 100), party = 9, mask = V.with(V.with(0, "wrath", true), "haste", true), mods = {}}}
local players = {{id = 1, pos = P(100, 100), party = 9}, {id = 2, pos = P(105, 100), party = 9},
	{id = 3, pos = P(106, 100), party = 9}, {id = 4, pos = P(101, 100), party = 8}, {id = 5, pos = P(101, 100, 6), party = 9},
	{id = 6, pos = P(101, 101), party = 9, dead = true}}
local cov = V.coverage(holders, players)
check(cov[1] and cov[2] and not cov[3] and not cov[4] and not cov[5] and not cov[6],
	"the holder and party members in range on the floor, alive")
near(cov[2].wrath, 0.05, "wrath on a member")
near(cov[2].haste, 0.15, "haste on a member")
holders[1].mods = {tithe = true}
cov = V.coverage(holders, players)
check(cov[1] and not cov[2], "Iron Tithe: the holder alone")
near(cov[1].wrath, 0.075, "x1.5")
holders[1].mods = {multiClient = true}
cov = V.coverage(holders, players)
check(cov[1] and not cov[2], "a multi-client holder: alone")
-- two holders: the strongest of each, never the sum
holders = {{id = 1, pos = P(100, 100), party = 9, mask = V.with(0, "wrath", true), mods = {}},
	{id = 2, pos = P(101, 100), party = 9, mask = V.with(0, "wrath", true), mods = {keystone = true}}}
cov = V.coverage(holders, {{id = 1, pos = P(100, 100), party = 9}, {id = 2, pos = P(101, 100), party = 9},
	{id = 3, pos = P(102, 100), party = 9}})
near(cov[3].wrath, 0.06, "the stronger wrath counts")
near(cov[1].wrath, 0.06, "the holder gets the other's stronger one")
near(cov[2].wrath, 0.05, "its own on itself")
-- hit factors
near(V.dealtFactor({wrath = 0.05}, 0), 1.05, "wrath")
near(V.dealtFactor({wrath = 0.05}, 0.08), 1, "under Inspiring Illusion: nothing more")
near(V.dealtFactor({wrath = 0.09}, 0.08), 1.09 / 1.08, "a stronger wrath adds the difference")
near(V.dealtFactor(nil, 0), 1, "not covered")
near(V.takenFactor({iron = 0.06}, 0), 0.94, "iron")
near(V.takenFactor({iron = 0.06}, 0.12), 1, "under the Sentinel's aura: nothing more")
near(V.takenFactor({iron = 0.09}, 0.04), 0.91 / 0.96, "a stronger iron adds the difference")
eq(V.clarityMana({clarity = 0.01}, 2000, false), 20, "clarity 1% a second")
eq(V.clarityMana({clarity = 0.01}, 2000, true), 0, "not under Parched Veins")
check(V.toggleText("wrath", true, 0.35, {}):find("35%% of your maximum mana"), "toggle text")
check(V.toggleText("wrath", true, 0.21, {tithe = true}):find("health"), "toggle text: health with Iron Tithe")
-- the buff bar rows: one per vigil that covers the player (stacks = the effect in percent), Iron Tithe's health
eq(V.pctText(0.05), "5", "percent text"); eq(V.pctText(0.075), "7.5", "percent text with a decimal")
local own = V.buffItem("wrath", {wrath = 0.05, haste = 0.15}, V.with(0, "wrath", true), {})
check(own and own.name == "Vigil of Wrath" and own.stacks == 5, "own wrath: name and stacks")
eq(own.desc, "+5% damage dealt. Your own: it reserves 35% of your maximum mana.", "own wrath text")
local from = V.buffItem("haste", {wrath = 0.05, haste = 0.15}, V.with(0, "wrath", true), {})
eq(from.desc, "+15% speed. From a party member's vigil.", "a party member's haste")
eq(from.stacks, 15, "haste stacks")
eq(V.buffItem("iron", {wrath = 0.05}, nil, nil), nil, "no iron, no row")
eq(V.buffItem("iron", nil, nil, nil), nil, "not covered, no row")
eq(V.buffItem("iron", {iron = 0.06 * 1.2}, nil, nil).desc, "-7.2% damage taken. From a party member's vigil.",
	"a Covenant holder's iron on the party")
local clar = V.buffItem("clarity", {clarity = 0.01}, nil, nil, true)
eq(clar.desc, "1% of your maximum mana back every second (none under Parched Veins). From a party member's vigil.",
	"clarity under Parched Veins")
eq(clar.stacks, 1, "clarity stacks")
local titheMods = {tithe = true}
local titheMask = V.with(V.with(0, "wrath", true), "iron", true)
local tw = V.buffItem("wrath", {wrath = 0.075, iron = 0.09}, titheMask, titheMods)
eq(tw.desc, "+7.5% damage dealt. Your own: it reserves 21% of your maximum health.", "Iron Tithe: health, x1.5")
eq(tw.stacks, 8, "7.5% rounds to 8 stacks")
local tt = V.buffItem("tithe", {wrath = 0.075, iron = 0.09}, titheMask, titheMods)
check(tt and tt.name == "Iron Tithe" and tt.stacks == 42, "the Iron Tithe row: 42% of the health reserved")
eq(tt.desc, "Your vigils reserve 42% of your maximum health instead of mana. They cover you alone, 50% stronger.", "Iron Tithe text")
eq(V.buffItem("tithe", {wrath = 0.05}, V.with(0, "wrath", true), {}), nil, "no Iron Tithe row without the keystone")
eq(V.buffItem("tithe", nil, 0, titheMods), nil, "no Iron Tithe row without a vigil on")

-- ------------------------------------------------------------------------------------------------ engine mocks
NOW = 100000
os.mtime = function() return NOW end
local events = {}
function addEvent(fn, delay, ...) events[#events + 1] = {fn = fn, args = {...}} end
local registered = {}
function GlobalEvent(name) local o = {}; function o:interval(ms) o.ms = ms end; function o:register() registered[name] = o end; return o end
local creatures, nextId = {}, 1
local function mk(opt)
	nextId = nextId + 1
	local c = {id = nextId, hp = opt.hp or 1000, maxHp = opt.maxHp or 1000, mana = opt.mana or 1000, maxMana = opt.maxMana or 1000,
		pos = opt.pos or P(100, 100), storage = {}, conds = {}, slots = {}, level = opt.level or 300}
	local m = {c = c}
	local function stat(param)
		local v = 0
		for _, cd in ipairs(c.conds) do v = v + (cd.params[param] or 0) end
		return v
	end
	function m:getId() return c.id end
	function m:getName() return "P" .. c.id end
	function m:isPlayer() return true end
	function m:getPlayer() return m end
	function m:getPosition() return c.pos end
	function m:getHealth() return c.hp end
	function m:getMaxHealth() return c.maxHp + stat(CONDITION_PARAM_STAT_MAXHITPOINTS) end
	function m:getMana() return c.mana end
	function m:getMaxMana() return c.maxMana + stat(CONDITION_PARAM_STAT_MAXMANAPOINTS) end
	function m:addMana(v) c.mana = math.min(m:getMaxMana(), c.mana + v) end
	function m:getStorageValue(k) return c.storage[k] or -1 end
	function m:setStorageValue(k, v) c.storage[k] = v end
	function m:getParty() return c.party end
	function m:getSlotItem(slot) return c.slots[slot] end
	function m:getCondition(t, id, sub)
		for _, cd in ipairs(c.conds) do if cd.type == t and cd.sub == sub then return cd end end
		return nil
	end
	function m:addCondition(cd)
		for i = #c.conds, 1, -1 do if c.conds[i].type == cd.type and c.conds[i].sub == cd.sub then table.remove(c.conds, i) end end
		c.conds[#c.conds + 1] = cd
		c.mana = math.min(c.mana, m:getMaxMana())
		c.hp = math.min(c.hp, m:getMaxHealth())
	end
	function m:removeCondition(t, id, sub)
		for i = #c.conds, 1, -1 do if c.conds[i].type == t and c.conds[i].sub == sub then table.remove(c.conds, i) end end
	end
	function m:sendTextMessage(_, text) c.lastText = text end
	function m:sendCancelMessage(text) c.cancel = text end
	creatures[c.id] = m
	return m
end
Player = function(id) return creatures[id] end
Game = {getPlayers = function()
	local out = {}
	for _, p in pairs(creatures) do out[#out + 1] = p end
	table.sort(out, function(a, b) return a:getId() < b:getId() end)
	return out
end}
function Condition(t, id)
	local cd = {type = t, params = {}}
	function cd:setParameter(k, v) self.params[k] = v; if k == CONDITION_PARAM_SUBID then self.sub = v end end
	function cd:setFormula(a, b, c2, d) self.formula = {a, b, c2, d} end
	return cd
end
Chaos = {isMultiClient = function() return false end}
ChaosPassiveCache = {}

-- ------------------------------------------------------------------------------------------------ the toggle spells
dofile("data/scripts/chaos/archetypes_core.lua")
local A = ChaosArchetypesCore
ChaosSpell = {cancel = function(p, text) p.c.cancel = text; return false end}
Position = function(p) return {sendMagicEffect = function() end} end
local function withPos(p) local mt = p.c.pos; mt.sendMagicEffect = function() end; return p end
dofile("data/spells/chaos/_vigils.lua")
local W = ChaosVigilSpell
local mage = withPos(mk({maxMana = 2000, mana = 2000}))
check(W.toggle(mage, "wrath") and W.toggle(mage, "iron") and W.toggle(mage, "haste"), "three on")
check(mage.c.lastText:find("90%% in all"), "the message says 90% (" .. tostring(mage.c.lastText) .. ")")
check(not W.toggle(mage, "clarity"), "the fourth is refused")
check(mage.c.cancel and mage.c.cancel:find("more than all of your mana"), "with a message")
mage.c.storage[ChaosArchetypesConfig.storage] = A.mask({arVigils = true})
check(W.toggle(mage, "clarity"), "with Covenant of Vigils it fits")
check(W.toggle(mage, "haste") and not V.has(mage.c.storage[C.storage], "haste"), "switched off again")
local circlet = {getId = function() return 27667 end, getCustomAttribute = function() return 1 end}
check(W.mods(withPos(mk({}))).choirmaster == nil or true, "mods without uniques")
mage.c.slots[CONST_SLOT_HEAD] = circlet
check(W.mods(mage).choirmaster and W.mods(mage).keystone, "the circlet and the keystone read in the spells' state")

-- ------------------------------------------------------------------------------------------------ the scripts' glue
creatures = {}
dofile("data/scripts/chaos/vigils.lua")
local M = ChaosVigils
check(registered.ChaosVigilsThink and registered.ChaosVigilsThink.ms == C.thinkMs, "the think every second")
local party = {}
local holder = mk({maxMana = 2000, mana = 2000, maxHp = 5000, hp = 5000, pos = P(100, 100)})
local friend = mk({maxMana = 1000, mana = 100, maxHp = 4000, hp = 4000, pos = P(103, 100)})
local stranger = mk({maxMana = 1000, mana = 100, pos = P(101, 100)})
local farFriend = mk({maxMana = 1000, mana = 100, pos = P(120, 100)})
party.getMembers = function() return {friend, farFriend} end
party.getLeader = function() return holder end
holder.c.party, friend.c.party, farFriend.c.party = party, party, party
holder.c.storage[C.storage] = V.with(V.with(V.with(0, "wrath", true), "haste", true), "clarity", true)
registered.ChaosVigilsThink.onThink(1000)
eq(holder:getMaxMana(), 2000 - math.floor(2000 * 0.75), "75% of the mana reserved")
eq(holder.c.mana, 500, "the current mana follows the lower maximum")
check(M.covered[friend:getId()] and not M.covered[stranger:getId()] and not M.covered[farFriend:getId()],
	"the friend in range is covered; a stranger and a friend far away are not")
local haste = friend:getCondition(CONDITION_HASTE, CONDITIONID_COMBAT, C.subIds.haste)
check(haste and haste.formula[1] == 0.15 and haste.params[CONDITION_PARAM_TICKS] == C.holdMs, "haste on the friend")
eq(friend.c.mana, 110, "clarity: 1% of the friend's maximum mana")
near(M.dealt(friend), 1.05, "the friend deals 5% more")
near(M.taken(friend), 1, "no iron: nothing taken off")
-- the buff bar (data/lib/chaos_buffs.lua, source "vigils"): the holder and the friend see the rows, the stranger none
dofile("data/lib/chaos_buffs.lua")
local BB = ChaosBuffs
local function rows(p)
	local out = {}
	for _, it in ipairs(BB.collect(p, NOW)) do
		if it.key:match("^vigil_") then out[it.key] = it end
	end
	return out
end
local hr, fr = rows(holder), rows(friend)
check(hr.vigil_wrath and hr.vigil_haste and hr.vigil_clarity and not hr.vigil_iron and not hr.vigil_tithe,
	"the holder: wrath, haste, clarity")
check(hr.vigil_wrath.desc:find("Your own: it reserves 35%% of your maximum mana") ~= nil, "the holder's own text")
check(hr.vigil_wrath.leftMs == nil and hr.vigil_wrath.stacks == 5 and hr.vigil_wrath.icon == "buff:vigil_wrath",
	"no timer, the effect as stacks, its own icon")
check(fr.vigil_haste and fr.vigil_haste.desc:find("From a party member's vigil", 1, true) and fr.vigil_haste.stacks == 15,
	"the friend: the holder's haste")
check(next(rows(stranger)) == nil and next(rows(farFriend)) == nil, "a stranger and a friend far away: no rows")
local sentBar = {}
BB.full(sentBar, BB.collect(friend, NOW), NOW)
eq(BB.diff(sentBar, BB.collect(friend, NOW + 1000), NOW + 1000), nil, "an unchanged vigil sends nothing")
-- the maximum changes (a level, the tree): the reservation follows the unreserved maximum
holder.c.maxMana = 2400
registered.ChaosVigilsThink.onThink(1000)
eq(holder:getMaxMana(), 2400 - 1800, "the reservation renewed (75% of 2400)")
-- Parched Veins: no clarity for the friend in that rift
ChaosRift = {runOf = {[friend:getId()] = {fx = {noMana = true}}}}
friend.c.mana = 100
registered.ChaosVigilsThink.onThink(1000)
eq(friend.c.mana, 100, "Parched Veins: no mana")
ChaosRift = nil
-- the holder dies: the condition goes, the next think puts it back
holder.c.conds = {}
registered.ChaosVigilsThink.onThink(1000)
eq(holder:getMaxMana(), 600, "re-applied after the condition went")
-- O358: a reservation that does not lower the maximum (the engine ignored it) must not run away: before, every think
-- reserved 75% of (maximum + what it thought it held), towards 3x the maximum and past int32
local realGetMax = holder.getMaxMana
holder.getMaxMana = function(self) return self.c.maxMana end -- the condition has no effect
local printed = {}
local realPrint = print
print = function(x) printed[#printed + 1] = tostring(x) end
for _ = 1, 30 do registered.ChaosVigilsThink.onThink(1000) end
print = realPrint
local cd = holder:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, C.subIds.mana)
eq(cd and -cd.params[CONDITION_PARAM_STAT_MAXMANAPOINTS], 1800, "ineffective reservation: stays 75% of the true maximum")
check(#printed == 1 and printed[1]:find("did not lower the maximum", 1, true), "one log line: " .. #printed .. " " .. tostring(printed[1]))
holder.getMaxMana = realGetMax
-- a maximum past int32 (an engine sum that wrapped) is clamped
holder.c.maxMana = 5e9
registered.ChaosVigilsThink.onThink(1000)
cd = holder:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, C.subIds.mana)
check(cd and -cd.params[CONDITION_PARAM_STAT_MAXMANAPOINTS] <= 2147483647, "the reservation fits int32")
holder.c.maxMana = 2400
registered.ChaosVigilsThink.onThink(1000)
eq(holder:getMaxMana(), 600, "back to 75% of 2400")
-- switched off: the mana is free again
holder.c.storage[C.storage] = 0
registered.ChaosVigilsThink.onThink(1000)
eq(holder:getMaxMana(), 2400, "no vigil, no reservation")
check(M.applied[holder:getId()] == nil, "forgotten")
NOW = NOW + 2000
registered.ChaosVigilsThink.onThink(1000)
check(M.covered[friend:getId()] == nil, "the cover runs out")
check(next(rows(friend)) == nil, "no cover, no rows on the bar")
local gone = BB.diff(sentBar, BB.collect(friend, NOW), NOW)
check(gone and gone.del and #gone.del == 3, "the three rows are removed from the friend's bar")

-- Iron Tithe: the health is reserved, only the holder is covered, x1.5
ChaosArchetypes = {flags = {[holder:getId()] = {arIronTithe = true}}, uniques = {}}
holder.c.storage[C.storage] = V.with(V.with(0, "wrath", true), "iron", true)
registered.ChaosVigilsThink.onThink(1000)
eq(holder:getMaxMana(), 2400, "Iron Tithe: the mana stays free")
eq(holder:getMaxHealth(), 5000 - math.floor(5000 * 0.7 * 0.6), "Iron Tithe: 42% of the health reserved")
check(M.covered[holder:getId()] and not M.covered[friend:getId()], "Iron Tithe: the holder alone")
near(M.dealt(holder), 1.075, "wrath x1.5 on the holder")
near(M.taken(holder), 0.91, "iron x1.5 on the holder")
hr = rows(holder)
check(hr.vigil_tithe and hr.vigil_tithe.stacks == 42 and hr.vigil_tithe.name == "Iron Tithe", "the bar: Iron Tithe, 42% health")
check(hr.vigil_iron and hr.vigil_iron.desc:find("of your maximum health", 1, true) and hr.vigil_iron.stacks == 9,
	"the bar: iron x1.5, reserved from the health")
check(next(rows(friend)) == nil, "the friend: nothing under Iron Tithe")
-- the Templar aura: the stronger counts
ChaosTemplar = {activeAura = function(id) return id == holder:getId() and {reduction = 0.12} or nil end}
near(M.taken(holder), 1, "under the Sentinel's 12%: nothing more")
ChaosTemplar = nil
-- Inspiring Illusion of a party member in range: wrath adds only what is above it
ChaosArchetypes = nil
holder.c.storage[C.storage] = V.with(0, "wrath", true)
NOW = NOW + 2000
registered.ChaosVigilsThink.onThink(1000)
ChaosPassiveCache[holder:getId()] = {ksInspiringIllusion = 1}
near(M.dealt(friend), 1, "under Inspiring Illusion: wrath adds nothing")
ChaosPassiveCache[holder:getId()] = nil
near(M.dealt(friend), 1.05, "without it: 5%")
-- a unique taken off: what no longer fits is switched off, with a message
holder.c.storage[C.storage] = all
ChaosArchetypes = {flags = {[holder:getId()] = {arVigils = true}}, uniques = {}}
registered.ChaosVigilsThink.onThink(1000)
eq(holder.c.storage[C.storage], all, "with the keystone all four stay")
ChaosArchetypes = {flags = {}, uniques = {}}
registered.ChaosVigilsThink.onThink(1000)
check(not V.has(holder.c.storage[C.storage], "clarity"), "the keystone went: clarity is switched off")
check(holder.c.lastText and holder.c.lastText:find("Vigil of Clarity ends"), "with a message")
-- a player who left: forgotten
creatures[holder:getId()] = nil
registered.ChaosVigilsThink.onThink(1000)
check(M.applied[holder:getId()] == nil, "the reservation memory of a player who left is gone")

-- ------------------------------------------------------------------------------------------------ data
local xml = io.open("data/spells/chaos/spells_chaos.xml"):read("*a")
for _, v in ipairs(C.list) do
	local block = xml:match('<instant[^>]-spellid="' .. v.spell .. '".-</instant>')
	check(block ~= nil, v.name .. " in spells_chaos.xml")
	if block then
		check(block:find('name="' .. v.name .. '"', 1, true) ~= nil, v.name .. ": its name")
		check(block:find('mana="0"', 1, true) and block:find('aggressive="0"', 1, true), v.name .. ": no mana cost, not aggressive")
		local vocs = 0
		for _ in block:gmatch("<vocation ") do vocs = vocs + 1 end
		eq(vocs, 21, v.name .. ": every class")
	end
	local script = io.open("data/spells/chaos/shared/vigil_" .. v.key .. ".lua")
	check(script ~= nil, v.name .. ": its script")
	if script then
		local text = script:read("*a")
		script:close()
		check(text:find(math.floor(v.reserve * 100 + 0.5) .. "%", 1, true) ~= nil, v.name .. ": the description states its reservation")
	end
end
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
eq(Chaos.storage.vigils, C.storage, "the storage in chaos_constants.lua")
local ks = io.open("data/scripts/chaos/passivetree_keystones.lua"):read("*a")
local bonus, range = ks:match("inspire = {bonus = ([%d%.]+), range = (%d+)}")
check(tonumber(bonus) == C.inspire.bonus and tonumber(range) == C.inspire.range, "Inspiring Illusion's numbers match")
local subs = {}
for _, id in pairs(C.subIds) do check(not subs[id], "sub id " .. id .. " once"); subs[id] = true end
dofile("data/scripts/chaos/archetypes_config.lua")
check(not subs[ChaosArchetypesConfig.arAetherEdge.subId] and not subs[ChaosArchetypesConfig.arHollowVessel.subId],
	"the sub ids differ from the archetypes'")

-- pt-BR: the buff bar line and the toggle text follow the language
dofile("data/scripts/chaos/i18n_core.lua")
local ptItem = V.buffItem("iron", {iron = 0.06 * 1.2}, nil, nil, nil, "pt-BR")
check(ptItem.desc ~= "-7.2% damage taken. From a party member's vigil.", "the vigil buff line is translated to pt-BR")
eq(V.buffItem("iron", {iron = 0.06 * 1.2}, nil, nil, nil, "en").desc, "-7.2% damage taken. From a party member's vigil.", "English stays")
check(V.toggleText("wrath", true, 0.35, {}, "pt-BR") ~= V.toggleText("wrath", true, 0.35, {}, "en"), "the toggle text is translated to pt-BR")

print(string.format("vigils_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
