-- Run from the server/ folder: luajit tests/exclusives_test.lua (and lua5.3; CI runs both)
-- Exclusives (exclusives_core.lua, exclusives_config.lua, exclusives.lua, the boss hooks): the shipped config against the
-- store, the generated store list, the achievements, the other catalogues (cosmetics, transmog sets, pets, portal
-- styles, frames) and the other reward sources; every visual kind has options that are never sold; the boss drop roll
-- (personal, owned ones skipped, rare); the kill keys of every boss; the achievement sync; the wardrobe rows; then
-- exclusives.lua on a mocked engine (account-wide grants applied to every character, the drop at a kill, the staff
-- command) and the guarded hook line in each boss script.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/exclusives_core.lua")
dofile("data/scripts/chaos/shop_core.lua")
dofile("data/scripts/chaos/nameplate_core.lua")
local K = ChaosExclusivesCore
local cfg = dofile("data/scripts/chaos/exclusives_config.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")
local achievements = dofile("data/scripts/chaos/achievements_data.lua")
local cosmetics = dofile("data/scripts/chaos/cosmetics_config.lua")
local transmog = dofile("data/scripts/chaos/transmog_config.lua")
local pets = dofile("data/scripts/chaos/pets_config.lua")
local portal = dofile("data/scripts/chaos/townportal_config.lua")
local storeList = dofile("data/scripts/chaos/shop_cosmetics.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- ---------------------------------------------------------------- the shipped config
local storeLooks = {looks = {}, mounts = {}}
for _, e in ipairs(storeList.outfits) do
	storeLooks.looks[e.looktype], storeLooks.looks[e.lookfemale] = true, true
end
for _, e in ipairs(storeList.addons) do
	storeLooks.looks[e.looktype], storeLooks.looks[e.lookfemale] = true, true
end
for _, e in ipairs(storeList.mounts) do
	storeLooks.mounts[e.id] = true
end
local opts = {achievements = achievements, shop = shop, storeLooks = storeLooks, cosmetics = cosmetics, transmog = transmog,
	pets = pets, portal = portal, frames = ChaosNameplate.FRAMES}
local problems = K.validate(cfg, opts)
eq(#problems, 0, "the shipped config validates: " .. table.concat(problems, "; "))
eq(cfg.table, Chaos.tables.exclusives, "table name in chaos_constants.lua")
eq(readFile("sql/chaos_exclusives.sql"):find("CREATE TABLE IF NOT EXISTS `chaos_exclusives`", 1, true) ~= nil, true, "sql file")

-- the validator refuses what must not be
local function broken(change)
	local copy = {}
	for k, v in pairs(cfg) do
		copy[k] = v
	end
	copy.exclusives, copy.bosses = {}, {}
	for i, e in ipairs(cfg.exclusives) do
		local c = {}
		for k, v in pairs(e) do
			c[k] = v
		end
		copy.exclusives[i] = c
	end
	for i, g in ipairs(cfg.bosses) do
		local c = {}
		for k, v in pairs(g) do
			c[k] = v
		end
		copy.bosses[i] = c
	end
	change(copy)
	return table.concat(K.validate(copy, opts), "\n")
end
local function find(copy, key)
	for _, e in ipairs(copy.exclusives) do
		if e.key == key then
			return e
		end
	end
end
eq(broken(function(c) find(c, "mount_tuskhide").price = 500 end):find("never sold", 1, true) ~= nil, true, "no price")
eq(broken(function(c) find(c, "mount_tuskhide").id = 141 end):find("is sold in the store", 1, true) ~= nil, true,
	"a store mount is refused")
eq(broken(function(c) find(c, "wings_cinderplumes").id = 7 end):find("is sold in the store", 1, true) ~= nil, true,
	"store wings are refused")
eq(broken(function(c) find(c, "frame_laurel").frame = "violet" end):find("is sold in the store", 1, true) ~= nil, true,
	"a store frame is refused")
eq(broken(function(c) find(c, "outfit_wingbound").male = 909 end):find("is sold in the store", 1, true) ~= nil, true,
	"a store outfit look is refused")
eq(broken(function(c) find(c, "mount_duskcrest").id = 146 end):find("given by", 1, true) ~= nil, true, "one mount once")
eq(broken(function(c) c.bosses[1].chance = 0.5 end):find("chance", 1, true) ~= nil, true, "a boss drop stays rare")
eq(broken(function(c) c.bosses[1].rewards = {"mount_tuskhide"} end):find("not a boss exclusive", 1, true) ~= nil, true,
	"an achievement exclusive is no boss drop")
eq(broken(function(c) table.remove(c.bosses, 1) end):find("tm_hellforged: a boss exclusive needs a boss group", 1, true) ~= nil,
	true, "a boss exclusive nobody drops")
eq(broken(function(c) c.bosses[2].kills = {"wb_kaelgor"} end):find("rolled by group", 1, true) ~= nil, true,
	"a kill rolls one group")
eq(broken(function(c) find(c, "foot_rime").name = "Frost" end):find("name must be the cosmetic's", 1, true) ~= nil, true,
	"the cosmetic's own name")
eq(broken(function(c) find(c, "tm_eldritch").set = "falconer" end):find("must exist with source boss", 1, true) ~= nil, true,
	"a store transmog set is no boss drop")
eq(broken(function(c) find(c, "pet_rotling").species = "lantern_wisp" end):find("source.boss", 1, true) ~= nil, true,
	"a store pet is no boss drop")
eq(broken(function(c) find(c, "portal_seraph").style = "abyssal" end):find("route boss", 1, true) ~= nil, true,
	"an achievement portal style is no boss drop")
eq(broken(function(c) find(c, "frame_infernal").frame = "nope" end):find("no picture", 1, true) ~= nil, true,
	"a frame the client does not have")
do -- an achievement exclusive named by no achievement
	local data = {list = {}}
	for _, a in ipairs(achievements.list) do
		data.list[#data.list + 1] = a.reward and a.reward.exclusives and {id = a.id, name = a.name} or a
	end
	local p = table.concat(K.validate(cfg, {achievements = data}), "\n")
	eq(p:find("mount_tuskhide: needs exactly one achievement", 1, true) ~= nil, true, "achievement link needed")
end

-- ---------------------------------------------------------------- every visual kind has never-sold options
-- kinds of the store and where their exclusives live (this file, or the kind's own catalogue)
local ach, boss = {}, {}
for _, e in ipairs(cfg.exclusives) do
	local kind = e.kind
	if kind == "cosmetic" then
		for _, c in ipairs(cosmetics.cosmetics) do
			if c.key == e.cosmetic then
				kind = c.kind
			end
		end
	end
	if e.source == "achievement" then ach[kind] = (ach[kind] or 0) + 1 else boss[kind] = (boss[kind] or 0) + 1 end
end
for _, c in ipairs(cosmetics.cosmetics) do
	if c.source == "achievement" then
		ach[c.kind] = (ach[c.kind] or 0) + 1
	end
end
for _, s in ipairs(transmog.sets) do
	if s.source == "achievement" then ach.transmog = (ach.transmog or 0) + 1 end
end
for _, s in ipairs(pets.species) do
	if s.source.achievement then ach.pet = (ach.pet or 0) + 1 end
end
for _, s in ipairs(portal.styles) do
	if s.route == "achievement" then ach.portal = (ach.portal or 0) + 1 end
end
for _, a in ipairs(achievements.list) do
	local r = a.reward or {}
	if r.outfit then ach.outfit = (ach.outfit or 0) + 1 end
	if r.mount then ach.mount = (ach.mount or 0) + 1 end
end
for _, kind in ipairs({"outfit", "addons", "mount", "wings", "aura", "shader", "frame", "portal", "transmog", "pet",
	"footprint", "outline"}) do
	eq((ach[kind] or 0) > 0, true, kind .. ": an achievement exclusive")
	eq((boss[kind] or 0) > 0, true, kind .. ": a boss exclusive")
end
-- wings: one look in the pair that no XML line had (1486), a boss drop; three achievement wings of things_custom17
-- (donor-library looks 2140..2142, picks.csv family "exclusive"), ids after the store's 1..15
eq(boss.wings, 1, "wings: a boss exclusive") eq(ach.wings, 3, "wings: three achievement exclusives")
local picks = readFile("../client/tools/sprites/monster_looks/picks.csv")
for _, e in ipairs(cfg.exclusives) do
	if e.kind == "wings" then
		eq(e.id > 15, true, e.key .. ": not a store wings id")
		if e.source == "achievement" then
			eq(picks:find("\n" .. e.key .. "," .. e.look .. ",I,%d+,,exclusive,wings,wings " .. e.id .. " " .. e.name) ~= nil, true,
				e.key .. ": its look is the picks.csv row of the pair")
		end
	end
end

-- the looks are no other source's reward and no store look
local others = ChaosShopCore.exclusions({classLooks = nil, achievements = achievements,
	season = dofile("data/scripts/chaos/season_config.lua"), seasonpass = dofile("data/scripts/chaos/seasonpass_config.lua")})
for _, e in ipairs(cfg.exclusives) do
	if e.kind == "outfit" then
		eq(others.looks[e.male] or others.looks[e.female], nil, e.key .. ": no other reward's look")
	elseif e.kind == "mount" then
		eq(others.mounts[e.id], nil, e.key .. ": no other reward's mount")
	elseif e.kind == "wings" or e.kind == "aura" or e.kind == "shader" then
		eq((others[e.kind] or {})[e.id], nil, e.key .. ": no other reward's " .. e.kind)
	end
end
-- the faction auras (25..28) and the store auras (1..24) stay theirs; the exclusive auras' manifest matches
local csv = readFile("data/XML/chaos_auras_exclusive.csv")
for _, e in ipairs(cfg.exclusives) do
	if e.kind == "aura" then
		eq(e.id > 28, true, e.key .. ": not a store or faction aura")
		eq(csv:find("\n" .. e.id .. "," .. e.look .. "," .. e.name .. "\n", 1, true) ~= nil, true, e.key .. " in chaos_auras_exclusive.csv")
	end
end
-- the store sees them as exclusives (shop.lua refuses to sell them)
local withEx = ChaosShopCore.exclusions({exclusives = cfg})
eq(ChaosShopCore.excluded({kind = "mount", id = 146}, withEx) ~= nil, true, "shop.lua: mount 146 is excluded")
eq(ChaosShopCore.excluded({kind = "wings", id = 16}, withEx) ~= nil, true, "shop.lua: wings 16 are excluded")
for id = 17, 19 do
	eq(ChaosShopCore.excluded({kind = "wings", id = id}, withEx) ~= nil, true, "shop.lua: wings " .. id .. " are excluded")
end
eq(ChaosShopCore.excluded({kind = "frame", frame = "laurel"}, withEx) ~= nil, true, "shop.lua: the laurel frame is excluded")
eq(ChaosShopCore.excluded({kind = "outfit", looktype = 1455, lookfemale = 1456}, withEx) ~= nil, true,
	"shop.lua: the Wingbound outfit is excluded")
eq(readFile("tools/gen_shop_cosmetics.py"):find("exclusives_config.lua", 1, true) ~= nil, true,
	"the generated store list leaves them out too")

-- ---------------------------------------------------------------- the kills of every boss roll a group
for _, b in ipairs(Chaos.worldBoss.bosses) do
	local kill = K.worldBossKill(cfg, b.name)
	eq(kill ~= nil and K.groupForKill(cfg, kill) ~= nil, true, "world boss " .. b.name .. " has a drop group")
end
eq(K.worldBossKill(cfg, "Vhalkareth"), nil, "an unknown boss rolls nothing")
local raid = dofile("data/scripts/chaos/raid_config.lua")
for _, b in ipairs(raid.bosses) do
	eq(K.groupForKill(cfg, "raid_" .. b.key) ~= nil, true, "raid boss " .. b.key .. " has a drop group")
end
local uber = dofile("data/scripts/chaos/uber_config.lua")
for _, def in ipairs(uber.kinds) do
	local kill = def.final and "cinder" or ("ascended_" .. def.key)
	eq(K.groupForKill(cfg, kill) ~= nil, true, "Ascended / Cinderheart " .. def.key .. " has a drop group")
end
local gb = dofile("data/scripts/chaos/guildboss_config.lua")
eq(K.groupForKill(cfg, "guild_" .. gb.boss.key) ~= nil, true, "the guild boss has a drop group")
eq(K.groupForKill(cfg, "raid_nobody"), nil, "an unknown kill rolls nothing")
-- the hook line in every boss script (guarded: the boss works without exclusives.lua)
for path, call in pairs({["data/scripts/chaos/worldboss.lua"] = "ChaosExclusives.worldBossKill, player, boss.name",
	["data/scripts/chaos/raid.lua"] = 'ChaosExclusives.bossKill, p, "raid_" .. b.key',
	["data/scripts/chaos/uber.lua"] = 'def.final and "cinder" or ("ascended_" .. def.key)',
	["data/scripts/chaos/guildboss.lua"] = 'ChaosExclusives.bossKill, p, "guild_" .. cfg.boss.key'}) do
	local text = readFile(path)
	eq(text:find(call, 1, true) ~= nil, true, path .. " rolls the drop")
	eq(text:find("if ChaosExclusives and ChaosExclusives.", 1, true) ~= nil, true, path .. ": guarded")
end

-- ---------------------------------------------------------------- the roll
local function seq(...)
	local v, i = {...}, 0
	return function()
		i = i + 1
		return v[i]
	end
end
local g = K.groupForKill(cfg, "cinder")
eq(#g.rewards, 4, "the Cinderheart has four rewards")
local key, why = K.roll(g, {}, seq(0.9))
eq(key, nil, "a miss") eq(why, "miss", "why: miss")
key = K.roll(g, {}, seq(0.01, 0))
eq(key, g.rewards[1], "a hit: the first reward")
key = K.roll(g, {}, seq(0.01, 0.99))
eq(key, g.rewards[4], "a hit: the last reward")
key = K.roll(g, {[g.rewards[1]] = true, [g.rewards[2]] = true}, seq(0.01, 0))
eq(key, g.rewards[3], "owned rewards are skipped")
key, why = K.roll(g, {[g.rewards[1]] = true, [g.rewards[2]] = true, [g.rewards[3]] = true, [g.rewards[4]] = true}, seq(0.01, 0))
eq(key, nil, "nothing left") eq(why, "owned", "why: owned")
eq(K.roll(g, {}, seq(g.chance, 0)), nil, "the chance is a strict bound")
eq(select(2, K.roll(nil, {}, seq(0))), "none", "no group")
-- rare: about chance x kills over many rolls (a fixed pseudo-random sequence, the same on LuaJIT and Lua 5.3)
local state = 12345
local function lcg()
	state = (state * 1103515245 + 12345) % 2147483648
	return state / 2147483648
end
for _, grp in ipairs(cfg.bosses) do
	local hits = 0
	for _ = 1, 20000 do
		if K.roll(grp, {}, lcg) then
			hits = hits + 1
		end
	end
	local rate = hits / 20000
	eq(math.abs(rate - grp.chance) < grp.chance * 0.35 + 0.002, true, grp.key .. ": drop rate " .. rate .. " near " .. grp.chance)
	eq(grp.chance <= 0.05, true, grp.key .. ": rare")
end

-- ---------------------------------------------------------------- achievements and the window
local function has(ids)
	return function(id)
		return ids[id] == true
	end
end
local syncs = K.syncs(cfg, achievements, has({ambush_250 = true, witching_hour = true}), {})
eq(#syncs, 2, "two earned") eq(syncs[1], "mount_tuskhide", "Tuskhide Boar") eq(syncs[2], "aura_murmuration", "the crows")
eq(#K.syncs(cfg, achievements, has({ambush_250 = true}), {mount_tuskhide = true}), 0, "owned: not again")
eq(#K.syncs(cfg, achievements, has({cinder_1 = true, raid_sovereign = true, wb_50 = true}), {}), 0,
	"a boss exclusive is never synced from achievements")
local wings = K.syncs(cfg, achievements, has({wb_all = true, raid_flawless = true, rift_100 = true}), {})
eq(table.concat(wings, " "), "wings_bloodthorn wings_gravecrow wings_riftglass",
	"the achievement wings: Colossus Hunter, Nobody Kneels, Lord of Thresholds")
eq(K.achievementOf(achievements, "frame_laurel").id, "mentor_15", "the laurel frame from Keeper of the Flame")
dofile("data/scripts/chaos/achievements_core.lua")
local AK = ChaosAchievementsCore
eq(#AK.build(achievements).problems, 0, "achievements_data.lua still validates")
eq(AK.rewardText(AK.build(achievements).byId.ambush_250.reward), "mount Tuskhide Boar", "the achievements window names it")
eq(AK.rewardText(AK.build(achievements).byId.bestiary_done_50.reward, function() return "Orb" end),
	"2 Orb, outfit addons Mage", "next to the other rewards")
local rows = K.rows(cfg, {wings_cinderplumes = true}, achievements, {clientItem = function(id) return id + 1 end, female = true})
eq(#rows, #cfg.exclusives, "a row per exclusive")
local byKey = {}
for _, r in ipairs(rows) do
	byKey[r.key] = r
end
eq(byKey.wings_cinderplumes.owned, true, "owned") eq(byKey.mount_tuskhide.owned, nil, "not owned")
eq(byKey.wings_cinderplumes.how, "Boss: Ysgrath the Cinderheart, rare drop", "boss line")
eq(byKey.mount_tuskhide.how, "Achievement: Nothing Surprises Me (Kill 250 ambushing monsters.)", "achievement line")
eq(byKey.aura_murmuration.how, "Achievement: ??? (a secret)", "a hidden achievement stays a secret")
eq(byKey.outfit_wingbound.look, 1456, "the female look for a female character")
eq(byKey.mount_tuskhide.look, 1323, "the mount's look") eq(byKey.wings_cinderplumes.with, "wings", "shown on the character")
eq(byKey.shader_cinderspark.shader, "ember_pixent", "the shader's name for the preview")
eq(byKey.frame_laurel.use:find("Plate frame", 1, true) ~= nil, true, "where it is chosen")
eq(byKey.mount_tuskhide.item, 2402, "the icon's client id")
-- the whole Collection fits a chunked message easily
local size = 0
for _, r in ipairs(rows) do
	for k, v in pairs(r) do
		size = size + #tostring(k) + #tostring(v) + 6
	end
end
eq(size < 16000, true, "the collection rows are small (" .. size .. " bytes)")
-- SQL
eq(K.sqlInsert(cfg, 7, "x';drop", "bo;ss", 1):find("'xdrop', 'boss'", 1, true) ~= nil, true, "keys sanitised")
eq(K.sqlSelect(cfg, "3 or 1"), "SELECT `exclusive` FROM `chaos_exclusives` WHERE `account_id` = 0", "account id numeric")

-- ---------------------------------------------------------------- exclusives.lua on a mocked engine
PLAYERSEX_FEMALE, PLAYERSEX_MALE = 0, 1
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 19, 22
CONST_ME_FIREWORK_RED = 28
local registered = {}
local function event(kind)
	return function(name)
		local e = {name = name, kind = kind}
		function e:register() registered[self.name] = self end
		function e:separator() end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = event("creature"), event("global"), event("talk")
ItemType = function(id) return {getClientId = function() return id + 1 end} end
local sent, effects, players = {}, {}, {}
local function newPlayer(id, name, account, sex, group)
	local p = {id = id, name = name, account = account, outfits = {}, mounts = {}, wings = {}, auras = {}, shaders = {},
		storage = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.id end
	function p:getName() return self.name end
	function p:getAccountId() return self.account end
	function p:getSex() return sex or PLAYERSEX_MALE end
	function p:getGroup() return {getId = function() return group or 1 end, getAccess = function() return (group or 1) >= 4 end} end
	function p:sendCancelMessage(text) self.cancel = text end
	function p:hasOutfit(look, addons) return self.outfits[look] == 3 end
	function p:addOutfitAddon(look, addons) self.outfits[look] = addons end
	function p:hasMount(id) return self.mounts[id] == true end
	function p:addMount(id) self.mounts[id] = true end
	function p:addWings(id) self.wings[id] = true end
	function p:addAura(id) self.auras[id] = true end
	function p:addShader(id) self.shaders[id] = true end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(_, text) sent[#sent + 1] = {to = self.name, text = text} end
	function p:getPosition() return {sendMagicEffect = function(_, id) effects[#effects + 1] = id end} end
	players[id] = p
	return p
end
Player = function(name)
	for _, p in pairs(players) do
		if p.name == name then
			return p
		end
	end
end
Game = {getPlayers = function()
	local out = {}
	for _, p in pairs(players) do
		out[#out + 1] = p
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end}
local rowsDb = {} -- account -> {keys}
db = {query = function(q)
	local acc, k = q:match("VALUES %((%d+), '([%w_]+)'")
	if acc then
		rowsDb[tonumber(acc)] = rowsDb[tonumber(acc)] or {}
		table.insert(rowsDb[tonumber(acc)], k)
	end
	local dacc, dk = q:match("DELETE FROM `chaos_exclusives` WHERE `account_id` = (%d+) AND `exclusive` = '([%w_]+)'")
	if dacc then
		for i, x in ipairs(rowsDb[tonumber(dacc)] or {}) do
			if x == dk then
				table.remove(rowsDb[tonumber(dacc)], i)
			end
		end
	end
	return true
end, storeQuery = function(q)
	local acc = tonumber(q:match("`account_id` = (%d+)"))
	if acc and rowsDb[acc] and #rowsDb[acc] > 0 then
		return {acc = acc, i = 1}
	end
	if q:find("FROM `players`", 1, true) then
		local name = q:match("`name` = '([^']+)'")
		local p = Player(name)
		return p and {account = p.account} or false
	end
	return false
end, escapeString = function(s) return "'" .. s .. "'" end}
result = {
	getString = function(r) return rowsDb[r.acc][r.i] end,
	getNumber = function(r) return r.account end,
	next = function(r) r.i = r.i + 1; return r.i <= #rowsDb[r.acc] end,
	free = function() end
}
-- the other systems exclusives.lua hands kinds to
local granted = {transmog = {}, pets = {}, cosmetics = {}}
ChaosTransmog = {grantSet = function(acc, set, src) granted.transmog[#granted.transmog + 1] = {acc, set, src}; return true end}
ChaosPets = {owns = function(p, key) return granted.pets[p.name .. ":" .. key] ~= nil end,
	grant = function(p, key, src) granted.pets[p.name .. ":" .. key] = src; return true end}
ChaosCosmetics = {owns = function(acc, key) return granted.cosmetics[acc .. ":" .. key] ~= nil end,
	grant = function(acc, key, src) granted.cosmetics[acc .. ":" .. key] = src; return true end}
local notified = {}
ChaosNotify = {send = function(p, title, text) notified[#notified + 1] = {p.name, title, text} end}
local achieved = {}
ChaosAchievements = {data = achievements, has = function(p, id) return achieved[id] == true end,
	syncTrack = function() end}

dofile("data/scripts/chaos/exclusives.lua")
local M = ChaosExclusives
-- two characters of account 10 online, one of account 20
local ann = newPlayer(1, "Ann", 10, PLAYERSEX_FEMALE)
local alt = newPlayer(2, "Alt", 10)
local bob = newPlayer(3, "Bob", 20)
registered.ChaosExclusivesStartup.onStartup()

-- a boss drop: personal, account-wide, applied at once to the account's characters online
M.rng = seq(0.01, 0) -- hit, first reward left
eq(M.bossKill(ann, "cinder"), "wings_cinderplumes", "Ann rolls the Cinder Plumes")
eq(ann.wings[16] and alt.wings[16], true, "both characters of the account have the wings")
eq(bob.wings[16], nil, "another account has nothing")
eq(M.owns(10, "wings_cinderplumes"), true, "owned by the account")
eq(notified[#notified][2], "Rare drop!", "a toast") eq(notified[#notified][1], "Ann", "to the roller")
eq(sent[#sent].text:find("Ysgrath the Cinderheart", 1, true) ~= nil, true, "the message names the boss")
M.rng = seq(0.01, 0)
eq(M.bossKill(ann, "cinder"), "tm_eldritch", "the next roll skips the owned wings")
eq(granted.transmog[1][2], "eldritch", "the set through ChaosTransmog.grantSet") eq(granted.transmog[1][3], "boss", "source")
M.rng = seq(0.01, 0)
eq(M.bossKill(ann, "cinder"), "frame_infernal", "the frame")
local slot = ChaosShopCore.frameIndex("infernal")
eq(ann.storage[ChaosShopCore.frameStorage(Chaos.storage, slot)], 1, "frame owned (storage slot)")
eq(ann.storage[Chaos.storage.shopFrameActive], slot, "and shown for the one who rolled it")
eq(alt.storage[Chaos.storage.shopFrameActive], nil, "the other character keeps its own choice")
M.rng = seq(0.5)
eq(M.bossKill(bob, "cinder"), nil, "a miss gives nothing")
M.rng = seq(0.01, 0)
eq(M.bossKill(bob, "nobody"), nil, "an unknown kill gives nothing")
M.rng = seq(0.01, 0.5)
eq(M.worldBossKill(bob, "The Rotmother"), "pet_rotling", "a world boss by name")
eq(granted.pets["Bob:rotling"], "boss", "the pet through ChaosPets.grant")
M.rng = seq(0.01, 0)
eq(M.worldBossKill(bob, "Skaldra the Rime Queen"), "mount_rimebone", "a mount")
eq(bob.mounts[148], true, "mount 148 added")
M.rng = seq(0.01, 0.4)
eq(M.worldBossKill(bob, "Skaldra the Rime Queen"), "foot_rime", "a footprint")
eq(granted.cosmetics["20:foot_rime"], "boss", "through ChaosCosmetics.grant")
M.rng = seq(0.01, 0.99)
eq(M.bossKill(bob, "guild_gorvath"), "addons_knight", "Knight addons")
eq(bob.outfits[131], 3, "male look with both addons") eq(bob.outfits[139], 3, "female look too")

-- achievements: granted for the account once any character has the achievement (only adds)
achieved.ambush_250 = true
local names = M.sync(alt)
eq(#names, 1, "one achievement exclusive") eq(names[1], "mount Tuskhide Boar", "its name")
eq(ann.mounts[146] and alt.mounts[146], true, "both characters get the mount")
eq(#M.sync(alt), 0, "a second sync changes nothing")
-- the wrapped syncTrack of achievements.lua carries the sync
achieved.witching_hour = true
ChaosAchievements.syncTrack(ann)
eq(ann.auras[29], true, "after an unlock: the crows aura")

-- a character of the account that logs in later gets everything
players[2] = nil
local late = newPlayer(4, "Late", 10)
registered.ChaosExclusivesLogin.onLogin(late)
eq(late.wings[16], true, "wings at login") eq(late.mounts[146], true, "the achievement mount at login")
eq(late.storage[ChaosShopCore.frameStorage(Chaos.storage, slot)], 1, "the frame at login")
eq(late.storage[Chaos.storage.shopFrameActive], nil, "but not switched on")
eq(late.auras[29], true, "the aura at login")

-- the rows of the window
local wrows = M.rows(ann)
local w = {}
for _, r in ipairs(wrows) do
	w[r.key] = r
end
eq(w.wings_cinderplumes.owned, true, "the window shows it owned") eq(w.mount_bloodwing.owned, nil, "not this one")
eq(w.outfit_wingbound.look, 1456, "Ann sees the female look")

-- staff: a grant or a roll needs an administrator (group 5; docs/GM_HANDBOOK.md: staff never give value), a revoke not
local gm = newPlayer(9, "Gm", 99, PLAYERSEX_MALE, 4)
local admin = newPlayer(8, "Admin", 98, PLAYERSEX_MALE, 5)
registered["/exclusive"].onSay(gm, "/exclusive", "Bob, mount_duskcrest")
eq(bob.mounts[147], nil, "a gamemaster cannot grant")
eq(gm.cancel ~= nil, true, "the gamemaster is told why")
registered["/exclusive"].onSay(admin, "/exclusive", "Bob, mount_duskcrest")
eq(bob.mounts[147], true, "an administrator's grant reaches the character")
registered["/exclusive"].onSay(gm, "/exclusive", "Bob, mount_duskcrest, revoke")
eq(M.owns(20, "mount_duskcrest"), false, "a gamemaster may revoke")
M.rng = seq(0.01, 0)
local beforeRoll = #sent
registered["/exclusive"].onSay(gm, "/exclusive", "Bob, roll, raid_sovereign")
eq(#sent, beforeRoll, "a gamemaster cannot roll")
registered["/exclusive"].onSay(admin, "/exclusive", "Bob, roll, raid_sovereign")
eq(sent[#sent].text, "Rolled outfit_ashseraph.", "an administrator's roll for tests")
local before = #sent
registered["/exclusive"].onSay(bob, "/exclusive", "Bob, all")
eq(#sent, before, "players cannot use it")

print("exclusives_test: " .. n .. " checks OK")
