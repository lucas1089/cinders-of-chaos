-- Run from the server/ folder: luajit tests/potion_hint_test.lua (and lua5.3; CI runs both)
-- The Everfull upgrade hint (O465, server/README.md "Potions", "Upgrade hint (O465)"): potions_core.lua hintDue /
-- hintMessage on the real config (which tiers are due for a level and an owned set, never twice, never for a line the
-- character does not use, at most one message), the config block, the texts in both languages, and potions.lua on a
-- mocked engine: the level-up event, the login check, the switch. All data is synthetic.
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

SKILL_LEVEL = 8
MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 19, 22
RETURNVALUE_NOERROR = 0
CONST_SLOT_FIRST, CONST_SLOT_LAST = 1, 10
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/potions_core.lua")
local cfg = dofile("data/scripts/chaos/potions_config.lua")
local K = ChaosPotionsCore
local PT_STRINGS = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]

-- ---------------------------------------------------------------- config
local h = cfg.hint
check(type(h) == "table", "a hint block")
eq(h.enabled, true, "on")
eq(h.storageBase, 7102520, "its own block 7102520 - 7102529")
local targets = K.upgradeTargets(cfg)
eq(#targets, 10, "ten upgrades, ten hint marks")
check(h.storageBase + #targets - 1 <= 7102529, "the marks fit the block")
local used = {}
for i, e in ipairs(targets) do
	local key = K.hintStorage(cfg, e.id)
	eq(key, h.storageBase + i - 1, e.name .. ": the mark is at its place")
	check(not used[key], e.name .. ": one key each")
	used[key] = true
	check(key ~= K.upgradeStorage(cfg, e.id), e.name .. ": not the upgrade flag")
end
for k, v in pairs(cfg.storage) do
	check(not used[v] and not (v >= 7102520 and v <= 7102529), "the potion storage " .. k .. " is outside the hint block")
end
eq(K.hintStorage(cfg, 32085), nil, "a tier 1 flask has no mark")
eq(K.hintStorage(cfg, 1), nil, "an unknown id has no mark")
check(h.minTierLevel >= 1 and h.delayMs > 0, "a minimum tier level and a login delay")
-- the storage block is claimed once in the whole config
local seen = 0
for _, e in ipairs(targets) do
	if K.hintStorage(cfg, e.id) == K.upgradeStorage(cfg, e.id) then seen = seen + 1 end
end
eq(seen, 0, "no hint mark is an upgrade flag")

-- ---------------------------------------------------------------- the core
local HEALTH2, MANA2, SPIRIT2 = 32261, 32262, 32263
local HEALTH3, MANA3, SPIRIT3 = 32264, 32265, 32266
local HEALTH4, MANA4, SPIRIT4 = 32267, 32269, 32270
local SPIRIT1 = 32268
local function ids(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.id end
	return table.concat(out, ",")
end
local function due(level, earned, hinted)
	local e, hd = {}, {}
	for _, id in ipairs(earned or {}) do e[id] = true end
	for _, id in ipairs(hinted or {}) do hd[id] = true end
	return K.hintDue(cfg, {level = level, earned = e, hinted = hd})
end

eq(ids(due(1)), "", "level 1: nothing")
eq(ids(due(79)), "", "level 79: below the first tier")
eq(ids(due(80)), HEALTH2 .. "," .. MANA2, "level 80: the great health and mana tiers, one message's worth")
-- a line the character does not use: the spirit line needs the spirit flask, so a health-flask character hears nothing of it
check(not ids(due(500)):find(tostring(SPIRIT2)), "no great spirit hint for a character on the health line")
check(not ids(due(500)):find(tostring(SPIRIT1)), "the first spirit potion needs no level: never hinted (minTierLevel)")
-- only what can be done now: great before ultimate, even at level 500
eq(ids(due(500)), HEALTH2 .. "," .. MANA2, "level 500 with the first flasks: the next step only")
eq(ids(due(130)), HEALTH2 .. "," .. MANA2, "level 130: ultimate waits for great")
-- never twice
eq(ids(due(80, {}, {HEALTH2})), tostring(MANA2), "the health tier was told: only mana")
eq(ids(due(80, {}, {HEALTH2, MANA2})), "", "both told: nothing")
eq(ids(due(500, {}, {HEALTH2, MANA2})), "", "told once, never again at a higher level (the next tier is not doable yet)")
-- the next tier is told when it can be taken: great earned, ultimate due at its level
eq(ids(due(129, {HEALTH2}, {HEALTH2})), tostring(MANA2), "great health earned and told, level 129: only the mana tier is left to tell")
eq(ids(due(129, {HEALTH2}, {HEALTH2, MANA2})), "", "level 129: the ultimate tier needs 130")
eq(ids(due(130, {HEALTH2}, {HEALTH2, MANA2})), tostring(HEALTH3), "level 130: ultimate health is due now")
eq(ids(due(130, {HEALTH2}, {HEALTH2, MANA2, HEALTH3})), "", "and only once")
-- an earned tier is never hinted
eq(ids(due(80, {HEALTH2, MANA2})), "", "both earned at level 80: nothing")
-- a long way: the highest doable tier of each line, one per line
eq(ids(due(200, {HEALTH2, HEALTH3}, {HEALTH2, MANA2, HEALTH3})), tostring(HEALTH4), "supreme health at 200")
eq(ids(due(200, {HEALTH2, MANA2, HEALTH3, MANA3}, {HEALTH2, MANA2, HEALTH3, MANA3})), HEALTH4 .. "," .. MANA4,
	"supreme health and mana, one entry per line, in config order")
eq(ids(due(1000, {HEALTH2, MANA2, HEALTH3, MANA3, HEALTH4, MANA4}, {})), "", "everything earned: nothing")
-- the spirit line: the character took the spirit flask (flag of the tier 1 spirit potion)
eq(ids(due(80, {SPIRIT1})), MANA2 .. "," .. SPIRIT2, "spirit flask: great spirit and great mana, not great health (that flask is gone)")
check(not ids(due(300, {SPIRIT1})):find(tostring(HEALTH2)), "a character on the spirit line never hears of the health line")
eq(ids(due(300, {SPIRIT1, SPIRIT2}, {SPIRIT2})), MANA2 .. "," .. SPIRIT3, "great spirit earned: ultimate spirit due, mana great still due")
eq(ids(due(200, {SPIRIT1, SPIRIT2, SPIRIT3}, {SPIRIT2, SPIRIT3})), MANA2 .. "," .. SPIRIT4, "ultimate spirit earned: supreme spirit due")
-- a character that skipped the first mana tier but took health: mana is its own line
eq(ids(due(130, {HEALTH2, HEALTH3}, {HEALTH2, HEALTH3})), tostring(MANA2), "mana waits on its own flask")
-- at most one tier per line, always a doable one
for _, level in ipairs({80, 130, 200, 600}) do
	local list = due(level, {SPIRIT1}, {})
	local lines = {}
	for _, e in ipairs(list) do
		check(not lines[e.line], "one tier per line at level " .. level)
		lines[e.line] = true
	end
end
-- the switch
do
	local off = {hint = {enabled = false, minTierLevel = 1, storageBase = 7102520}, everfull = cfg.everfull, storage = cfg.storage}
	eq(#K.hintDue(off, {level = 500, earned = {}, hinted = {}}), 0, "off: nothing due")
	eq(#K.hintDue({everfull = cfg.everfull, storage = cfg.storage}, {level = 500}), 0, "no hint block: nothing due")
end
-- a nil level and nil sets do not break it
eq(#K.hintDue(cfg, {}), 0, "empty input")

-- ---------------------------------------------------------------- the texts
check(K.hintName(targets[1]) == "Everfull Great Health Potion", "the name as the game writes it: " .. K.hintName(targets[1]))
local plain = function(key, ...) return select("#", ...) > 0 and string.format(key, ...) or key end
local title, text = K.hintMessage(cfg, due(80), "Veyra the Apothecary", plain)
eq(title, "Potion upgrade", "title")
check(text:find("Everfull Great Health Potion, Everfull Great Mana Potion", 1, true) ~= nil, "both flasks in one text: " .. text)
check(text:find("Veyra the Apothecary", 1, true) ~= nil, "names the Apothecary")
check(text:find("store", 1, true) ~= nil, "names the store")
check(text:find("How it works", 1, true) ~= nil, "names How it works")
local apo = dofile("data/scripts/chaos/apothecary_config.lua")
eq(apo.npc, "Veyra the Apothecary", "the NPC is the one of the config")
local keyKeys = {"Potion upgrade", "Your Everfull potion can be upgraded: %s. Ask %s in the hub, or buy the swap in the store. How it works explains it: open Help Search (Alt+F) and type \"potion\"."}
for _, k in ipairs(keyKeys) do
	check(PT_STRINGS[k] ~= nil, "pt-BR text for: " .. k)
end
local _, texten = K.hintMessage(cfg, due(80), apo.npc, function(key, ...) return ChaosI18n.text("en", key, ...) end)
local ptTitle, ptText = K.hintMessage(cfg, due(80), apo.npc, function(key, ...) return ChaosI18n.text("pt-BR", key, ...) end)
eq(ptTitle, "Melhoria de poção", "pt-BR title")
check(ptText:find("Everfull Great Health Potion, Everfull Great Mana Potion", 1, true) ~= nil, "pt-BR: the item names stay English")
check(ptText:find("Veyra the Apothecary", 1, true) ~= nil, "pt-BR: the NPC name")
check(ptText:find("Como funciona", 1, true) ~= nil and ptText:find("Buscar Ajuda", 1, true) ~= nil, "pt-BR: Como funciona, Buscar Ajuda")
check(ptText ~= texten, "pt-BR differs from English")
-- the same number of % places in both languages
local function places(s)
	local n = 0
	for _ in s:gmatch("%%s") do n = n + 1 end
	return n
end
for _, k in ipairs(keyKeys) do
	eq(places(k), places(PT_STRINGS[k]), "same places in both languages: " .. k:sub(1, 20))
end
-- the toast fits the toast window: a short sentence, one message
check(#text <= 300, "short enough for a toast: " .. #text)

-- ---------------------------------------------------------------- potions.lua on a mocked engine
local registered, scheduled = {}, {}
local function event(name)
	local e = {name = name}
	function e:register() registered[name or "action"] = self end
	function e:type() end
	function e:id() end
	return e
end
CreatureEvent, GlobalEvent = event, event
Action = function() return event(nil) end
ItemType = function(id) return {getId = function() return id end} end
Game = {getTowns = function() return {} end}
configKeys = {EX_ACTIONS_DELAY_INTERVAL = 1}
configManager = {getNumber = function() return 1000 end}
function addEvent(fn, ms) scheduled[#scheduled + 1] = {fn = fn, ms = ms} end
local toasts = {}
ChaosNotify = {send = function(player, t, x, kind) toasts[#toasts + 1] = {player = player, title = t, text = x, kind = kind} return true end}

local players = {}
local function mkPlayer(id, level, pt)
	local p = {id = id, st = {}, msgs = {}, level = level}
	if pt then p.st[ChaosI18n.STORAGE] = 1 end
	p.st[cfg.storage.granted] = 1 -- the Everfull potions were given
	function p:getId() return self.id end
	function p:getName() return "P" .. self.id end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:getLevel() return self.level end
	function p:getLastLoginSaved() return 1700000000 end
	function p:registerEvent(name) self.events = self.events or {} self.events[name] = true end
	function p:getSlotItem() return nil end
	function p:getInbox() return nil end
	function p:getDepotChest() return nil end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	players[id] = p
	return p
end
Player = function(cid) return players[cid] end

dofile("data/scripts/chaos/potions.lua")
local PT = ChaosPotions
check(registered.ChaosPotionsAdvance ~= nil and registered.ChaosPotionsAdvance.onAdvance ~= nil, "the level-up event is registered")
check(registered.ChaosPotionsLogin ~= nil, "the login event is still registered")

-- a level-up to 80: one toast and one chat line, both flasks in it
local ann = mkPlayer(1, 80)
registered.ChaosPotionsAdvance.onAdvance(ann, SKILL_LEVEL, 79, 80)
eq(#toasts, 1, "one toast") eq(#ann.msgs, 1, "one chat line")
eq(toasts[1].kind, "milestone", "the level toast kind: the hint fires when the level of a tier is reached")
eq(toasts[1].title, "Potion upgrade", "its title")
check(toasts[1].text:find("Everfull Great Health Potion, Everfull Great Mana Potion", 1, true) ~= nil, "both lines in the one toast")
eq(ann.msgs[1], toasts[1].title .. ": " .. toasts[1].text, "the chat line is the toast")
eq(ann.st[K.hintStorage(cfg, HEALTH2)], 1, "the health mark is set") eq(ann.st[K.hintStorage(cfg, MANA2)], 1, "the mana mark is set")
eq(ann.st[K.hintStorage(cfg, SPIRIT2)], nil, "no mark for a line it does not use")
-- never twice: the next level, a relog
registered.ChaosPotionsAdvance.onAdvance(ann, SKILL_LEVEL, 80, 81)
eq(#toasts, 1, "the next level says nothing")
registered.ChaosPotionsLogin.onLogin(ann)
eq(#scheduled, 1, "login schedules the check")
eq(scheduled[1].ms, cfg.hint.delayMs, "after the configured delay")
scheduled[1].fn()
eq(#toasts, 1, "the login check finds nothing left to say") scheduled = {}
check(ann.events and ann.events.ChaosPotionsAdvance, "the login registers the level-up event on the player")
-- the other events do not hint: a skill, a level lost, no change
local bob = mkPlayer(2, 90)
registered.ChaosPotionsAdvance.onAdvance(bob, 1, 79, 90)
registered.ChaosPotionsAdvance.onAdvance(bob, SKILL_LEVEL, 90, 80)
registered.ChaosPotionsAdvance.onAdvance(bob, SKILL_LEVEL, 90, 90)
eq(#toasts, 1, "a skill advance, a level lost and no change say nothing")
-- a character already past the tiers: the login check says it once, in one message
local cy = mkPlayer(3, 200, true)
registered.ChaosPotionsLogin.onLogin(cy)
eq(#toasts, 1, "nothing at once at login (the toast waits for the delay)")
eq(#scheduled, 1, "one check queued")
scheduled[1].fn() scheduled = {}
eq(#toasts, 2, "a toast after the delay")
eq(toasts[2].title, "Melhoria de poção", "in the player's language (pt-BR)")
check(toasts[2].text:find("Everfull Great Health Potion, Everfull Great Mana Potion", 1, true) ~= nil, "level 200: the next step of each line")
eq(#cy.msgs, 1, "one chat line")
registered.ChaosPotionsLogin.onLogin(cy)
scheduled[1].fn() scheduled = {}
eq(#toasts, 2, "never twice at the next login")
-- a level-up and a login together: still one message
local dee = mkPlayer(4, 130)
registered.ChaosPotionsLogin.onLogin(dee)
registered.ChaosPotionsAdvance.onAdvance(dee, SKILL_LEVEL, 129, 130)
scheduled[1].fn() scheduled = {}
eq(#toasts, 3, "a level-up and a login check in one go: one message in all")
-- after the swap the next tier is hinted at its level, once
dee.st[K.upgradeStorage(cfg, HEALTH2)] = 1
dee.st[K.upgradeStorage(cfg, MANA2)] = 1
registered.ChaosPotionsAdvance.onAdvance(dee, SKILL_LEVEL, 130, 131)
eq(#toasts, 4, "great earned: the ultimate tiers are told at 131")
check(toasts[4].text:find("Everfull Ultimate Health Potion, Everfull Ultimate Mana Potion", 1, true) ~= nil, "ultimate health and mana")
registered.ChaosPotionsAdvance.onAdvance(dee, SKILL_LEVEL, 131, 132)
eq(#toasts, 4, "once")
-- the switch
ChaosPotionsConfig.hint.enabled = false -- potions.lua loaded its own copy of the config
local eve = mkPlayer(5, 500)
registered.ChaosPotionsAdvance.onAdvance(eve, SKILL_LEVEL, 499, 500)
registered.ChaosPotionsLogin.onLogin(eve)
eq(#toasts, 4, "off: no toast") eq(#scheduled, 0, "off: nothing scheduled")
ChaosPotionsConfig.hint.enabled = true
-- a tier missing from items.otb is not hinted
local oldItemType = ItemType
ItemType = function() return {getId = function() return 0 end} end
local fay = mkPlayer(6, 500)
registered.ChaosPotionsAdvance.onAdvance(fay, SKILL_LEVEL, 499, 500)
eq(#toasts, 4, "items not installed: no hint")
eq(fay.st[K.hintStorage(cfg, HEALTH2)], nil, "and no mark, so it comes when the items are installed")
ItemType = oldItemType
-- a failure in the toast never breaks the level-up
ChaosNotify = {send = function() error("boom") end}
local gus = mkPlayer(7, 500)
local okAdv = pcall(registered.ChaosPotionsAdvance.onAdvance, gus, SKILL_LEVEL, 499, 500)
eq(okAdv, true, "an error in the toast is caught")
ChaosNotify = nil
-- no ChaosNotify at all: the chat line still goes out
local hal = mkPlayer(8, 500)
registered.ChaosPotionsAdvance.onAdvance(hal, SKILL_LEVEL, 499, 500)
eq(#hal.msgs, 1, "without the notify module the chat line is still sent")
eq(#PT.hintDue(hal), 0, "and the mark is set")

print(count .. " checks, " .. failures .. " failures")
if failures > 0 then os.exit(1) end
