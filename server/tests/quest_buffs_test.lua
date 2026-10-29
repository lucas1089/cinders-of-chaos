-- Run from the server/ folder: luajit tests/quest_buffs_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- The seven level 800 buffs of the line spell quests (server/README.md "Line spell quests"): Ironbound Oath, Unblinking Gaze,
-- Veil of Whispers, Shroud of Knives, Dirge of the Legion, Lotus Stance, Mantle of Dawn. Config and rules
-- (quest_buffs_config.lua, quest_buffs_core.lua), the casts on a mocked player, the spell entries, the ids of the pool, the buff
-- bar rows, the hooks of the combat scripts (evasion, chi, minions, damage taken, holy strike).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails = 0
local function ok(c, m) if not c then fails = fails + 1; print("FAIL " .. m) end end
local function eq(a, b, m) ok(a == b, m .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, m) ok(math.abs(a - b) < 1e-9, m .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

dofile("data/scripts/chaos/quest_buffs_config.lua")
dofile("data/scripts/chaos/quest_buffs_core.lua")
local C, Q = ChaosQuestBuffsConfig, ChaosQuestBuffs

-- ------------------------------------------------------------------ the seven buffs: id, key, folder, script, class, vocations, mana, duration ms
local BUFFS = {
	{id = 143, key = "oath", name = "Ironbound Oath", file = "knight/ironbound_oath.lua", vocs = "Warrior,Juggernaut,Berserker", ms = 20000},
	{id = 150, key = "gaze", name = "Unblinking Gaze", file = "paladin/unblinking_gaze.lua", vocs = "Ranger,Deadeye,Beastmaster", ms = 20000},
	{id = 153, key = "veil", name = "Veil of Whispers", file = "sorcerer/veil_of_whispers.lua", vocs = "Mystic,Elementalist,Illusionist", ms = 20000},
	{id = 156, key = "knives", name = "Shroud of Knives", file = "thief/shroud_of_knives.lua", vocs = "Thief,Ninja,Samurai", ms = 15000},
	{id = 159, key = "dirge", name = "Dirge of the Legion", file = "necromancer/dirge_of_the_legion.lua", vocs = "Necromancer,Lich,Bone Lord", ms = 20000},
	{id = 173, key = "lotus", name = "Lotus Stance", file = "monk/lotus_stance.lua", vocs = "Monk,Shadowfist,Iron Sage", ms = 15000},
	{id = 178, key = "mantle", name = "Mantle of Dawn", file = "templar/mantle_of_dawn.lua", vocs = "Templar,Inquisitor,Sentinel", ms = 20000},
}

-- ------------------------------------------------------------------ config
eq(C.cooldownMs, 90000, "cooldown 90 s")
local seenSub = {}
for _, b in ipairs(BUFFS) do
	local sub = C.subId[b.key]
	ok(sub and sub >= 71075 and sub <= 71081 and not seenSub[sub], b.key .. ": its own sub id in 71075-71081")
	seenSub[sub] = true
	eq(C[b.key].durationMs, b.ms, b.name .. ": duration")
	ok(C[b.key].durationMs >= 15000 and C[b.key].durationMs <= 20000, b.name .. ": 15 to 20 s (spec)")
end
eq(C.oath.melee, 120, "Oath +20% melee"); eq(C.oath.shield, 125, "Oath +25% shielding")
eq(C.gaze.distance, 125, "Gaze +25% distance"); eq(C.gaze.crit, 10, "Gaze +10 crit")
eq(C.veil.magic, 115, "Veil +15% magic level")
eq(C.knives.melee, 120, "Knives +20% melee"); eq(C.knives.distance, 120, "Knives +20% distance"); near(C.knives.evade, 0.10, "Knives +10 evasion")
near(C.dirge.minion, 0.25, "Dirge +25% minions"); near(C.dirge.death, 0.10, "Dirge +10% death spells")
eq(C.lotus.chi, 1, "Lotus +1 chi"); near(C.lotus.evade, 0.10, "Lotus +10 evasion")
near(C.mantle.taken, 0.15, "Mantle -15% damage taken"); near(C.mantle.holy, 0.20, "Mantle +20% holy strike")
-- no sub id of another system (grep of the sub id blocks the README lists)
for _, f in ipairs({"data/spells/chaos/_common.lua", "data/scripts/chaos/necro_config.lua", "data/scripts/chaos/monk_chi_core.lua",
		"data/scripts/chaos/templar_aura_core.lua", "data/scripts/chaos/chaos_constants.lua"}) do
	local text = read(f)
	for sub in pairs(seenSub) do
		local count = 0
		for _ in text:gmatch(tostring(sub)) do count = count + 1 end
		ok(count <= 1, f .. ": sub id " .. sub .. " used " .. count .. " times")
	end
end

-- ------------------------------------------------------------------ the rules (pure)
local function playerWith(...)
	local subs = {}
	for _, key in ipairs({...}) do subs[C.subId[key]] = true end
	return {getCondition = function(_, ctype, cid, sub) return subs[sub] and {} or nil end}
end
eq(Q.has(playerWith("knives"), "knives"), true, "has: the condition is there")
eq(Q.has(playerWith("knives"), "lotus"), false, "has: another buff is not")
eq(Q.has(nil, "knives"), false, "has: nobody")
eq(Q.has({}, "knives"), false, "has: no condition API")
near(Q.evadeBonus(playerWith()), 0, "no buff, no evasion")
near(Q.evadeBonus(playerWith("knives")), 0.10, "Shroud of Knives: +10 points")
near(Q.evadeBonus(playerWith("lotus")), 0.10, "Lotus Stance: +10 points")
near(Q.evadeBonus(playerWith("knives", "lotus")), 0.20, "both (they never share a line: sum)")
eq(Q.chiPerHit(1, false), 1, "chi per hit as before"); eq(Q.chiPerHit(1, true), 2, "Lotus Stance: one more chi")
near(Q.minionBonus(false), 0, "no Dirge, no minion bonus"); near(Q.minionBonus(true), 0.25, "Dirge: minions +25%")
near(Q.deathFactor(true, 5, 5, 9, 9, false), 1.1, "Dirge: a death spell +10%")
near(Q.deathFactor(false, 5, 5, 9, 9, false), 1, "no Dirge")
near(Q.deathFactor(true, 4, 5, 9, 9, false), 1, "another damage type")
near(Q.deathFactor(true, 5, 5, 8, 9, false), 1, "a weapon hit")
near(Q.deathFactor(true, 5, 5, 9, 9, true), 1, "a minion hit or a proc")
near(Q.takenFactor(true), 0.85, "Mantle: -15% taken"); near(Q.takenFactor(false), 1, "no Mantle")
near(Q.holyFactor(true), 1.2, "Mantle: holy strike +20%"); near(Q.holyFactor(false), 1, "no Mantle: as before")
eq(Q.manaTick(10000), 100, "Veil: 1% of 10000 mana"); eq(Q.manaTick(100), 5, "Veil: at least 5"); eq(Q.manaTick(nil), 5, "Veil: no mana known")

-- the hooks' pure ends
dofile("data/scripts/chaos/templar_aura_core.lua")
local T = ChaosTemplar
eq(T.radiantDamage(23, 1000, false), 150, "Radiant Strike as before")
eq(T.radiantDamage(23, 1000, false, nil, Q.holyFactor(true)), 180, "Radiant Strike under Mantle of Dawn: 15% x 1.2")
eq(T.radiantDamage(23, 1000, true, nil, Q.holyFactor(true)), 360, "against players from the unhalved hit")
near(T.damageTakenFactor(nil, false, nil, Q.takenFactor(true)), 0.85, "Mantle alone")
near(T.damageTakenFactor({reduction = 0.12}, true, 1, Q.takenFactor(true)), 0.88 * 0.6 * 0.85, "aura, Aegis and Mantle multiply")
near(T.damageTakenFactor({reduction = 0.12}, false), 0.88, "as before without the argument")
dofile("data/scripts/chaos/monk_chi_core.lua")
local M = ChaosMonk
near(M.dodgeChance(17), 0.06, "Monk evasion as before"); near(M.dodgeChance(17, Q.evadeBonus(playerWith("lotus"))), 0.16, "Lotus Stance: 6 + 10")
eq(M.dodges(17, true, 0.15, false, 0.10), true, "a roll of 0.15 dodges with the buff")
eq(M.dodges(17, true, 0.15, false), false, "and does not without it")
eq(M.dodges(17, true, 0.01, true, 0.10), false, "Scarred Discipline still takes the evasion away")
eq(M.dodges(17, false, 0.01, false, 0.10), false, "a spell cannot be dodged")
dofile("data/scripts/chaos/classes.lua")
near(ChaosClasses.dodgeChance(12, Q.evadeBonus(playerWith("knives"))), 0.22, "Shroud of Knives on the Ninja: 12 + 10")
near(ChaosClasses.dodgeChance(11, Q.evadeBonus(playerWith("knives")), 0.5), 0.09, "the Blackblood Creed halves the sum")

-- ------------------------------------------------------------------ the casts on a mocked player
local common = read("data/spells/chaos/_common.lua")
local block = common:match("ChaosSpell%.SUBID = %b{}")
local realDofile = dofile
local Cond = {}
Cond.__index = Cond
function Condition(ctype, cid) return setmetatable({type = ctype, id = cid, params = {}}, Cond) end
function Cond:setParameter(k, v) self.params[k] = v end
local vfxCalls = {}
ChaosSpell = {vfxOr = function(pos, v, name, fb) vfxCalls[#vfxCalls + 1] = {v, name, fb} end}
dofile = function(path)
	if path == "data/spells/scripts/chaos/_common.lua" then return end -- ChaosSpell is the stub above
	if path == "data/spells/scripts/chaos/_questbuffs.lua" then return realDofile("data/spells/chaos/_questbuffs.lua") end
	return realDofile(path)
end
local function cast(file)
	local added = {}
	local pos = {}
	local player = {}
	function player:getPlayer() return self end
	function player:addCondition(c) added[#added + 1] = c; return true end
	function player:getPosition() return pos end
	function player:getMaxMana() return 8000 end
	onCastSpell = nil
	vfxCalls = {}
	realDofile("data/spells/chaos/" .. file)
	eq(onCastSpell(player, nil, false), true, file .. ": the cast succeeds")
	eq(#vfxCalls, 1, file .. ": one effect")
	eq(onCastSpell({getPlayer = function() return nil end}, nil, false), false, file .. ": no player, no cast")
	for _, x in ipairs(added) do
		ok(x.type ~= CONDITION_PACIFIED and x.type ~= CONDITION_PARALYZE and x.type ~= CONDITION_SPELLGROUPCOOLDOWN, file .. ": no lock, no slow")
		ok(x.params[CONDITION_PARAM_DISABLE_DEFENSE] == nil, file .. ": defence untouched")
	end
	return added
end
local P = {}
for _, b in ipairs(BUFFS) do
	local added = cast(b.file)
	P[b.key] = added
	local main = added[1] or {params = {}}
	eq(main.type, CONDITION_ATTRIBUTES, b.name .. ": an attribute condition")
	eq(main.id, CONDITIONID_COMBAT, b.name .. ": the combat id (the combat scripts look there)")
	eq(main.params[CONDITION_PARAM_SUBID], C.subId[b.key], b.name .. ": its own sub id")
	eq(main.params[CONDITION_PARAM_TICKS], b.ms, b.name .. ": duration")
end
local function params(key) return P[key][1].params end
eq(#P.oath, 1, "Oath: one condition"); eq(params("oath")[CONDITION_PARAM_SKILL_MELEEPERCENT], 120, "Oath: +20% melee")
eq(params("oath")[CONDITION_PARAM_SKILL_SHIELDPERCENT], 125, "Oath: +25% shielding"); eq(params("oath")[CONDITION_PARAM_BUFF_SPELL], true, "Oath: a buff spell")
eq(params("gaze")[CONDITION_PARAM_SKILL_DISTANCEPERCENT], 125, "Gaze: +25% distance")
eq(params("gaze")[CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE], 10, "Gaze: +10 crit")
eq(params("veil")[CONDITION_PARAM_STAT_MAGICPOINTSPERCENT], 115, "Veil: +15% magic level")
eq(#P.veil, 2, "Veil: the buff and a regeneration")
local regen = P.veil[2]
eq(regen.type, CONDITION_REGENERATION, "Veil: a regeneration condition")
eq(regen.params[CONDITION_PARAM_SUBID], C.subId.veil + C.regenOffset, "Veil: the regeneration's sub id")
eq(regen.params[CONDITION_PARAM_MANAGAIN], 80, "Veil: 1% of 8000 mana"); eq(regen.params[CONDITION_PARAM_MANATICKS], 1000, "Veil: every second")
eq(regen.params[CONDITION_PARAM_TICKS], 20000, "Veil: as long as the buff"); eq(regen.params[CONDITION_PARAM_HEALTHGAIN], nil, "Veil: no health")
eq(params("knives")[CONDITION_PARAM_SKILL_MELEEPERCENT], 120, "Knives: +20% melee")
eq(params("knives")[CONDITION_PARAM_SKILL_DISTANCEPERCENT], 120, "Knives: +20% distance")
for _, key in ipairs({"dirge", "lotus", "mantle"}) do
	eq(#P[key], 1, key .. ": one condition"); eq(next((function() local t = {}; for k, v in pairs(params(key)) do if k ~= CONDITION_PARAM_SUBID and k ~= CONDITION_PARAM_TICKS then t[k] = v end end; return t end)()), nil, key .. ": a timer only, the combat scripts do the rest")
end
dofile = realDofile

-- ------------------------------------------------------------------ the spell entries
local xml = read("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
local pool = dofile("data/scripts/chaos/spell_id_pool_config.lua")
local inPool = {}
for _, id in ipairs(pool.ids) do inPool[id] = true end
local quest = dofile("data/scripts/chaos/spellquest_config.lua")
for i, b in ipairs(BUFFS) do
	local head, body = xml:match('<instant ([^>]*name="' .. b.name .. '"[^>]*)>(.-)</instant>')
	ok(head ~= nil, b.name .. " is in spells_chaos.xml")
	head, body = head or "", body or ""
	ok(head:find('spellid="' .. b.id .. '"', 1, true), b.name .. ": id " .. b.id)
	ok(inPool[b.id], b.name .. ": id " .. b.id .. " is in the pool")
	ok(head:find('group="support"', 1, true) and not head:find("secondarygroup", 1, true), b.name .. ": support group only")
	ok(head:find('level="800"', 1, true), b.name .. ": level 800")
	ok(head:find('needlearn="1"', 1, true), b.name .. ": needlearn (taught by the quest)")
	ok(head:find('cooldown="90000"', 1, true) and head:find('groupcooldown="2000"', 1, true), b.name .. ": 90 s, group 2 s")
	ok(head:find('selftarget="1"', 1, true) and head:find('aggressive="0"', 1, true), b.name .. ": a self buff")
	ok(head:find('script="chaos/' .. b.file .. '"', 1, true), b.name .. ": its script")
	local f = io.open("data/spells/chaos/" .. b.file, "r")
	ok(f ~= nil, b.name .. ": script file exists"); if f then f:close() end
	local got = {}
	for v in body:gmatch('<vocation name="([^"]+)"') do got[#got + 1] = v end
	eq(table.concat(got, ","), b.vocs, b.name .. ": the three classes of the line")
	local count = 0
	for _ in xml:gmatch('spellid="' .. b.id .. '"') do count = count + 1 end
	eq(count, 1, b.name .. ": one spell with the id")
	eq(quest.lines[i].spells[2], b.name, b.name .. ": quest 2 of line " .. i .. " in spellquest_config.lua")
end

-- ------------------------------------------------------------------ the buff bar, the support kinds, the sub ids
dofile("data/lib/chaos_buffs.lua")
local rows = {ironbound_oath = "oath", unblinking_gaze = "gaze", veil_of_whispers = "veil", shroud_of_knives = "knives",
	dirge_of_the_legion = "dirge", lotus_stance = "lotus", mantle_of_dawn = "mantle"}
for key, short in pairs(rows) do
	local def = ChaosBuffs.byKey[key]
	ok(def ~= nil, key .. ": a buff bar row")
	if def then
		eq(def.cond.sub, C.subId[short], key .. ": the row's sub id"); eq(def.icon, "buff:" .. key, key .. ": its icon")
		eq(def.cond.type, "CONDITION_ATTRIBUTES", key .. ": type")
		ok(common:find(key .. " = " .. C.subId[short], 1, true) ~= nil, key .. ": in ChaosSpell.SUBID")
		local f = io.open("../client/overlay/data/images/game/buffs/" .. key .. ".png", "rb")
		ok(f ~= nil, key .. ": the icon file"); if f then f:close() end
	end
end
local supports = read("data/lib/chaos_supports_config.lua")
for _, b in ipairs(BUFFS) do
	ok(supports:find("[" .. b.id .. '] = "buff"', 1, true), b.name .. ": kindOverride buff")
end

-- ------------------------------------------------------------------ the hooks are in the combat scripts
local function has(file, text) ok(read(file):find(text, 1, true) ~= nil, file .. ": " .. text) end
has("data/scripts/chaos/thief_combat.lua", "QB.evadeBonus(player)")
has("data/scripts/chaos/monk_combat.lua", "QB.evadeBonus(player)")
has("data/scripts/chaos/monk_combat.lua", "QB.chiPerHit(")
has("data/scripts/chaos/necro_minions.lua", "L.hitBonus(owner, aura)")
has("data/scripts/chaos/necro_lib.lua", "ChaosQuestBuffs.minionBonus(")
has("data/scripts/chaos/templar_combat.lua", "QB.holyFactor(")
has("data/scripts/chaos/templar_combat.lua", "QB.takenFactor(")
has("data/scripts/chaos/passivetree_effects.lua", "ChaosQuestBuffs.deathFactor(")

-- ------------------------------------------------------------------ the translated texts of the buff bar
local i18n = read("data/scripts/chaos/i18n_strings.lua")
for key in pairs(rows) do
	local desc = ChaosBuffs.byKey[key].desc
	ok(i18n:find('["' .. desc .. '"]', 1, true), key .. ": pt-BR text for '" .. desc .. "'")
end

if fails > 0 then error("quest_buffs_test: " .. fails .. " failure(s)") end
print("quest_buffs_test: OK")
