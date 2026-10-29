-- Run from the server/ folder: luajit tests/combat_stats_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Covers the combat stat rows of the Skills window (combat_stats_core.lua, combat_stats.lua): armour sum and percent, the
-- engine's defence formula, mitigation, the weapon hit with the tree factor and the display scale, the message of a mocked
-- player (weapon, shield, armour, tree, gear modifiers) and when it is sent (login, equip, advance, tree, `get`).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local fails, checks = 0, 0
local function ok(cond, what) checks = checks + 1; if not cond then fails = fails + 1; print("FAIL " .. what) end end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, what) ok(a and math.abs(a - b) < 1e-6, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.combatStats, 119, "opcode 119")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 126, 127, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(ChaosOpcodes.combatStats ~= v, "not an opcode of the reference server or client: " .. v)
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end
local others = 0
for _, cmd in ipairs({"ls data/scripts/chaos/*.lua", "ls ../client/overlay/modules/*/*.lua"}) do
	local ph = io.popen(cmd .. " 2>/dev/null")
	for file in ph:lines() do
		local s = readFile(file)
		local own = file:find("combat_stats", 1, true) or file:find("game_skillstats", 1, true) or file:find("chaos_constants", 1, true)
		if s and not own and not file:find("_test.lua", 1, true)
				and (s:find("[Oo]pcode[%w_]*%s*=%s*119%f[%D]") or s:find("xtended[%w]*Opcode%(%s*119%f[%D]")) then
			others = others + 1
			print("opcode 119 in " .. file)
		end
	end
	ph:close()
end
eq(others, 0, "no other script or module on 119")

-- ------------------------------------------------------------------ the pure rules
dofile("data/scripts/chaos/weapon_dps_core.lua")
dofile("data/scripts/chaos/combat_stats_core.lua")
local C = ChaosCombatStats
local cfg = dofile("data/scripts/chaos/combat_stats_config.lua")

eq(C.armour({10, 20, "5", -3, 7}), 42, "armour sum, negative counts 0")
eq(C.armour(nil), 0, "no armour list")
near(C.armourShare(250, 250, 80), 0.5, "armour 250 with K 250 is 50%")
near(C.armourShare(100, 250, 80), 100 / 350, "armour 100: 28.6%")
near(C.armourShare(5000, 250, 80), 0.8, "the cap holds")
eq(C.armourShare(0, 250, 80), 0, "no armour no share")
eq(C.armourShare(-5, 250, 80), 0, "negative armour no share")

-- engine Player::getDefense: (skill / 4 + 2.23) * defence * 0.15
eq(C.defence({shield = {defense = 40}, shielding = 100, bare = 7, fist = 10}), math.floor((100 / 4 + 2.23) * 40 * 0.15), "shield defence")
eq(C.defence({weapon = {defense = 20, extra = 3, skill = 80}, bare = 7}), math.floor((80 / 4 + 2.23) * 23 * 0.15), "weapon defence and extra")
eq(C.defence({weapon = {defense = 20, extra = 3, skill = 80}, shield = {defense = 30}, shielding = 60}),
	math.floor((60 / 4 + 2.23) * 33 * 0.15), "the shield wins, the weapon's extra counts")
eq(C.defence({bare = 7, fist = 50}), math.floor((50 / 4 + 2.23) * 7 * 0.15), "bare hands")
eq(C.defence({bare = 7, fist = 0}), 1, "skill 0: 1, as the engine")
eq(C.defence({shield = {defense = 40}, shielding = 100, factor = 0.5}), math.floor((100 / 4 + 2.23) * 40 * 0.15 * 0.5), "stance factor")

near(C.mitigation(0, 0, 0), 0, "nothing: 0")
near(C.mitigation(0.5, 0, 0), 0.5, "armour only")
near(C.mitigation(0.5, 20, 10), 1 - 0.5 * 0.8 * 0.9, "armour, absorb and gear one after the other")
near(C.mitigation(2, 200, 500), 1, "parts clamp at all")
near(C.mitigation(-1, -5, nil), 0, "negative parts count 0")

-- the weapon hit: the same estimate as the tooltip's DPS at a 1 s interval, times the tree factor and the display scale
local sword = {kind = "sword", attack = 40, twoHanded = false}
local base = ChaosWeaponDps.estimate({level = 100, skill = 80, attack = 40, interval = 1000, weaponType = "sword", twoHanded = false})
eq(C.hit(sword, {level = 100, skill = 80}, 1, 1), math.floor(base + 0.5), "hit = estimate at 1 s")
eq(C.hit(sword, {level = 100, skill = 80}, 1.5, 3), math.floor(base * 1.5 * 3 + 0.5), "tree factor and display scale")
eq(C.hit({kind = "wand", attack = 0}, {level = 100, skill = 80}, 1, 1), nil, "a wand has no attack hit")
eq(C.hit({kind = "sword", attack = 0}, {level = 100, skill = 80}, 1, 1), nil, "attack 0: no hit")
ok(C.hit({kind = "distance", attack = 50, launcher = "bow", hitChance = 90}, {level = 100, skill = 80}, 1, 1) ~= nil, "a bow hits")
eq(C.hit(nil, {level = 1}, 1, 1), nil, "no weapon")

-- build
local d = C.build({level = 100, weapon = {kind = "sword", attack = 40, defense = 20, extra = 0}, shield = {defense = 30},
	armourList = {50, 50}, skills = {melee = 80, distance = 10, shielding = 60, fist = 5}, k = 250, cap = 80, absorb = 0,
	monster = 0, mult = 1, scale = 1}, cfg)
eq(d.attack, 40, "attack = the weapon's attack")
eq(d.armor, 100, "armor = the sum")
near(d.mitigation, math.floor(100 / 350 * 10000 + 0.5) / 10000, "mitigation = the armour share")
eq(d.defense, C.defence({weapon = {defense = 20, extra = 0, skill = 80}, shield = {defense = 30}, shielding = 60}), "defence with weapon and shield")
ok(d.damage and d.damage > 0, "damage for a sword")
d = C.build({level = 100, weapon = {kind = "wand", attack = 0, defense = 0, extra = 0}, armourList = {},
	skills = {melee = 80, shielding = 60, fist = 5}, k = 250, cap = 80}, cfg)
eq(d.attack, nil, "no attack with a wand"); eq(d.damage, nil, "no damage with a wand"); eq(d.armor, 0, "no armour")
eq(d.mitigation, 0, "no mitigation"); ok(type(d.defense) == "number", "a defence value anyway")
d = C.build({level = 1, armourList = {100}, skills = {fist = 0}, k = nil, cap = 80, absorb = 10, monster = 5}, cfg)
near(d.mitigation, 1 - 0.9 * 0.95, "percent armour off: absorb and gear only")
eq(d.defense, 1, "no weapon, fist 0: defence 1"); eq(d.attack, nil, "bare hands: no attack")
eq(C.signature({damage = nil, attack = 1, defense = 2, armor = 3, mitigation = 0.5}),
	C.signature({damage = nil, attack = 1, defense = 2, armor = 3, mitigation = 0.5}), "signature is stable")
ok(C.signature({attack = 1, defense = 2, armor = 3, mitigation = 0.5}) ~= C.signature({attack = 2, defense = 2, armor = 3, mitigation = 0.5}), "signature differs")
local gs = {}
ok(C.dueGet(gs, 1000, 2000), "first get answered"); ok(not C.dueGet(gs, 2500, 2000), "second within 2 s dropped")
ok(C.dueGet(gs, 3100, 2000), "after the gap answered again")

-- ------------------------------------------------------------------ the glue (mocks)
local events, callbacks = {}, {}
local function obj(name)
	local o = {}
	function o:register() if name then events[name] = o end end
	function o:type() end
	return o
end
function CreatureEvent(name) return obj(name) end
EventCallback = {register = function(self, prio) callbacks.prio = prio end}
local queue = {}
function addEvent(fn, ms, ...) queue[#queue + 1] = {fn = fn, ms = ms, args = {...}} end
local function flush()
	local q = queue
	queue = {}
	for _, e in ipairs(q) do e.fn(table.unpack and table.unpack(e.args) or unpack(e.args)) end
end
local sent = {}
Chaos.send = function(player, opcode, action, data) sent[#sent + 1] = {op = opcode, action = action, data = data}; return true end
Chaos.decode = function(s) return s end
os.mtime = nil

local types = {}
function ItemType(id) return types[id] end
local function itemType(t)
	local it = {}
	function it:getWeaponType() return t.wt or 0 end
	function it:getAttack() return t.attack or 0 end
	function it:getDefense() return t.defense or 0 end
	function it:getExtraDefense() return t.extra or 0 end
	function it:getArmor() return t.armor or 0 end
	function it:getHitChance() return t.hit or 0 end
	function it:getSlotPosition() return t.slotpos or 0 end
	function it:getAbilities() return {absorbPercent = t.absorb or {}} end
	return it
end
local function item(id, attrs)
	local i = {}
	function i:getId() return id end
	function i:hasAttribute(a) return attrs and attrs[a] ~= nil end
	function i:getAttribute(a) return attrs[a] end
	return i
end
types[1] = itemType({wt = WEAPON_SWORD, attack = 30, defense = 10})
types[2] = itemType({wt = WEAPON_SHIELD, defense = 35})
types[3] = itemType({armor = 20, absorb = {10}})
types[4] = itemType({armor = 15})
types[5] = itemType({wt = WEAPON_WAND, attack = 0})

local inv = {}
local storage = {}
local player = {id = 77, level = 150, skills = {}}
function player:getId() return self.id end
function player:getLevel() return self.level end
function player:getSlotItem(slot) return inv[slot] end
function player:getEffectiveSkillLevel(s) return self.skills[s] or 0 end
function player:getStorageValue(k) return storage[k] or -1 end
function player:registerEvent() end
function Player(id) return id == 77 and player or nil end
player.skills[SKILL_SWORD] = 90; player.skills[SKILL_CLUB] = 60; player.skills[SKILL_AXE] = 70
player.skills[SKILL_SHIELD] = 100; player.skills[SKILL_FIST] = 12; player.skills[SKILL_DISTANCE] = 20
configManager = {getBoolean = function() return true end, getNumber = function(k) return k == configKeys.ARMOR_PERCENT_MAX and 80 or 250 end}
configKeys = {ARMOR_PERCENT = 1, ARMOR_PERCENT_CONSTANT = 2, ARMOR_PERCENT_MAX = 3}

local okMods = pcall(dofile, "data/lib/chaos_item_mods.lua")
ok(okMods and ChaosItemMods and ChaosItemMods.effectiveAbsorb, "the real effectiveAbsorb loads")
dofile("data/scripts/chaos/combat_stats.lua")
local S = ChaosCombatStats

inv[CONST_SLOT_LEFT] = item(1, {[ITEM_ATTRIBUTE_ATTACK] = 55}) -- a rarity roll raised the attack
inv[CONST_SLOT_RIGHT] = item(2)
inv[CONST_SLOT_ARMOR] = item(3, {[ITEM_ATTRIBUTE_ARMOR] = 60})
inv[CONST_SLOT_HEAD] = item(4)
storage[977563] = 10 -- the passive tree's physical resist
local data = S.compute(player)
eq(data.attack, 55, "attack = the item attribute, not the type")
eq(data.armor, 75, "armor = 60 (rolled) + 15 (type)")
eq(data.defense, math.floor((100 / 4 + 2.23) * (35 + 0) * 0.15), "defence = shield, shielding 100")
ok(data.damage and data.damage > 0, "damage for a sword")
local share = 75 / (75 + 250)
local absorb = 100 - (1 - 0.10) * (1 - 0.10) * 100 -- item 10% then the storage 10% (no gear storage)
ok(data.mitigation > share and data.mitigation < 1, "mitigation counts armour and absorb")
-- the same result as the pure rules on the same inputs
local snap = S.gather(player)
eq(snap.skills.melee, 90, "best melee skill"); eq(snap.k, 250, "K from the config"); eq(snap.cap, 80, "cap from the config")
eq(#snap.armourList, 2, "two pieces"); eq(snap.mult, 1, "no tree: factor 1")
near(snap.absorb, absorb, "absorb: item type then the tree storage")

-- the passive tree factor reaches the hit
ChaosPassiveCache = {[77] = {}}
function ChaosPassiveDamagePercent() return 50 end
function ChaosPassiveStatMultiplier() return 1.1 end
function ChaosParagonDamageMultiplier() return 1 end
local boosted = S.compute(player)
ok(boosted.damage > data.damage, "tree damage raises the hit")
near(S.gather(player).mult, 1.5 * 1.1, "tree factor = percent x stats")
ChaosPassiveCache = nil

-- a wand: no attack, no damage; shield still defends
inv[CONST_SLOT_LEFT] = item(5)
data = S.compute(player)
eq(data.attack, nil, "wand: no attack"); eq(data.damage, nil, "wand: no damage")
-- bare hands: the fist skill defends
inv[CONST_SLOT_LEFT], inv[CONST_SLOT_RIGHT] = nil, nil
data = S.compute(player)
eq(data.defense, math.floor((12 / 4 + 2.23) * 7 * 0.15), "bare hands defence")
-- nothing worn
for k in pairs(inv) do inv[k] = nil end
data = S.compute(player)
eq(data.armor, 0, "naked: armor 0")
near(data.mitigation, 1 - (1 - 0.10), "naked: only the tree resist")

-- sending: login, equip, advance and tree changes make one message and only when something changed
sent = {}
local login = events.ChaosCombatStatsLogin
ok(login ~= nil, "login event registered")
login.onLogin(player)
eq(#sent, 0, "nothing before the delay")
eq(queue[1] and queue[1].ms, cfg.loginDelayMs, "login message after the delay")
flush()
eq(#sent, 1, "one message at login"); eq(sent[1].op, 119, "on opcode 119"); eq(sent[1].action, "stats", "action stats")
eq(sent[1].data.armor, 0, "its numbers")
S.schedule(player); S.schedule(player); S.schedule(player)
eq(#queue, 1, "a burst is one scheduled message")
flush()
eq(#sent, 1, "unchanged numbers are not sent again")
inv[CONST_SLOT_ARMOR] = item(3, {[ITEM_ATTRIBUTE_ARMOR] = 60})
callbacks.fn = EventCallback.onItemMoved
local from = {x = 100, y = 100, z = 7}
local to = {x = 0xFFFF, y = 4, z = 0} -- inventory slot 4
EventCallback.onItemMoved(player, item(3), 1, from, to)
eq(#queue, 1, "an equip schedules a message")
flush()
eq(#sent, 2, "an equip changes the numbers: sent"); eq(sent[2].data.armor, 60, "armor after the equip")
-- a move between two containers is not an equip
EventCallback.onItemMoved(player, item(3), 1, from, {x = 0xFFFF, y = 64 + 3, z = 0})
eq(#queue, 0, "a move between containers does nothing")
-- level up
player.level = 400
events.ChaosCombatStatsAdvance.onAdvance(player, SKILL_LEVEL, 150, 400)
eq(#queue, 1, "an advance schedules a message"); flush()
-- tree change: through the listener
ok(#ChaosPassiveTree.listeners >= 1, "a passive tree listener is registered")
inv[CONST_SLOT_LEFT] = item(1)
ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners](player, {})
eq(#queue, 1, "a tree change schedules a message"); flush()
local before = #sent
ok(before >= 3, "the weapon change was sent")
eq(sent[#sent].data.attack, 30, "the new weapon's type attack")
-- get: answered at once, forced, throttled
events.ChaosCombatStatsExtended.onExtendedOpcode(player, 119, {action = "get"})
eq(#sent, before + 1, "get is answered even with the same numbers")
events.ChaosCombatStatsExtended.onExtendedOpcode(player, 119, {action = "get"})
eq(#sent, before + 1, "a second get within the gap is dropped")
events.ChaosCombatStatsExtended.onExtendedOpcode(player, 120, {action = "get"})
events.ChaosCombatStatsExtended.onExtendedOpcode(player, 119, {action = "nope"})
eq(#sent, before + 1, "another opcode or action is ignored")
events.ChaosCombatStatsLogout.onLogout(player)
eq(S.last[77], nil, "logout forgets the player")

print(string.format("combat_stats_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
