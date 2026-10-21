-- Run from the server/ folder: luajit tests/gentledeath_test.lua (CI runs it with luajit and lua5.3)
-- Gentle deaths and blessings (gentledeath_core.lua, gentledeath_config.lua, gentledeath.lua; server/README.md "Gentle
-- deaths and blessings"): the level curve, the first death of the day, the eased loss, who keeps the items (everyone but
-- a red / black skull or Hardcore), the engine side on a mocked player (storages, messages in both languages, Hardcore
-- untouched), the death keep hook, the !bless price and command (combat, money, nothing missing), the Eternal Blessing
-- store service (check, apply, login after a death) and its store offer.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "check") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/gentledeath_core.lua")
local G = ChaosGentleDeathCore
local cfg = dofile("data/scripts/chaos/gentledeath_config.lua")

-- ---------------------------------------------------------------- config
check(cfg.storage.base >= 7102740 and cfg.storage.base + cfg.storage.firstDeathDay <= cfg.storage.last, "storage in block")
check(cfg.storage.last <= 7102744, "block end")
local last = 0
for _, p in ipairs(cfg.xpLoss) do
	check(p.level >= last, "curve sorted"); last = p.level
	check(p.mult >= 0 and p.mult <= 1, "curve factor 0..1")
end
eq(cfg.xpLoss[#cfg.xpLoss].mult, 1, "the full loss at the end of the curve")

-- ---------------------------------------------------------------- curve
eq(G.curve(cfg.xpLoss, 1), 0, "level 1"); eq(G.curve(cfg.xpLoss, 30), 0, "level 30")
eq(G.curve(cfg.xpLoss, 100), 0.5, "level 100"); eq(G.curve(cfg.xpLoss, 175), 0.75, "level 175 between")
eq(G.curve(cfg.xpLoss, 2000), 1, "flat after"); eq(G.curve({}, 50), 1, "no curve: full")
eq(G.curve({{level = 10, mult = 0.2}}, 1), 0.2, "flat before")

-- ---------------------------------------------------------------- mult and ease
eq(G.mult(cfg, 400, false), 1, "full loss"); eq(G.mult(cfg, 400, true), 0.5, "first of the day")
eq(G.mult(cfg, 10, true), 0, "new character")
eq(G.mult({xpLoss = {{level = 1, mult = 2}}}, 1, false), 1, "clamped to 1")
eq(G.ease(1000, 0.5), 500, "half"); eq(G.ease(1001, 0.5), 501, "rounded"); eq(G.ease(0, 0.5), 0, "nothing")
eq(G.ease(1000, 1), 1000, "never more"); eq(G.percent(0.75), 75, "percent")
eq(G.day(os.time({year = 2026, month = 10, day = 15, hour = 5}), 6), 20261014, "before the reset hour: yesterday")
eq(G.day(os.time({year = 2026, month = 10, day = 15, hour = 7}), 6), 20261015, "after the reset hour")

-- ---------------------------------------------------------------- items
check(G.keepItems(cfg, 10, false, false), "level 10 keeps")
check(G.keepItems(cfg, 2000, false, false), "level 2000 keeps too")
check(not G.keepItems(cfg, 10, true, false), "red skull drops")
check(not G.keepItems(cfg, 10, false, true), "Hardcore drops")
check(not G.keepItems({keepItems = false}, 1, false, false), "off")

-- ---------------------------------------------------------------- blessing prices
local b = cfg.bless
eq(G.blessCost(b, 1), 2000, "level 1"); eq(G.blessCost(b, 30), 2000, "level 30"); eq(G.blessCost(b, 31), 2200, "level 31")
eq(G.blessCost(b, 120), 20000, "level 120: the base cap"); eq(G.blessCost(b, 121), 20100, "after 120 +100")
eq(G.blessCost(b, 500), 58000, "level 500"); eq(G.blessCost(b, 920), 100000, "level 920 the cap")
eq(G.blessCost(b, 3000), 100000, "capped")
eq(#G.missing({1, 2, 3}, function(id) return id == 2 end), 2, "missing")
eq(G.blessProblem({inCombat = true, missing = 5, gold = 1, money = 9}):sub(1, 10), "Blessings:", "combat")
eq(G.blessProblem({missing = 0, gold = 0, money = 0}), "You already have all blessings.", "nothing missing")
check(G.blessProblem({missing = 2, gold = 10, money = 9}):find("need", 1, true) ~= nil, "money")
eq(G.blessProblem({missing = 2, gold = 10, money = 10}), nil, "can buy")

-- ---------------------------------------------------------------- engine side
MESSAGE_EVENT_ADVANCE, SKULL_RED, SKULL_BLACK = 19, 4, 5
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local registry = {}
local function ev(name)
	return {name = name, type = function() end, register = function(self) registry[name or self.words or "?"] = self end}
end
CreatureEvent, GlobalEvent = ev, ev
TalkAction = function(words) local o = ev(words); o.words = words; return o end
dofile("data/scripts/chaos/gentledeath.lua")
local GD = ChaosGentleDeath
local function mk(id, level, lang)
	local p = {id = id, level = level, st = {}, said = {}, skull = 0}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:getSkull() return self.skull end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendTextMessage(t, m) self.said[#self.said + 1] = m end
	if lang then Chaos.setLang(p, lang) end
	return p
end
local low = mk(1, 10)
eq(GD.onLoseExperience(low, 5000), 0, "level 10 loses nothing")
check(low.said[1]:find("no experience", 1, true) ~= nil, "told")
check(low.said[2]:find("keep all your items", 1, true) ~= nil, "items told")
check(GD.keepAll(low), "keeps items")
low.skull = SKULL_RED
check(not GD.keepAll(low), "not with a red skull")
local high = mk(2, 400, "pt-BR")
check(GD.keepAll(high), "level 400 keeps items too")
eq(GD.onLoseExperience(high, 1000), 500, "first death of the day")
check(high.said[1]:find("primeira morte", 1, true) ~= nil, "pt-BR text: " .. tostring(high.said[1]))
eq(GD.onLoseExperience(high, 1000), 1000, "second death: full")
eq(#high.said, 3, "a full loss tells only that the items stay")
local mid = mk(3, 175)
GD.onLoseExperience(mid, 1000)
eq(GD.onLoseExperience(mid, 1000), 750, "level 175 second death")
ChaosSeason = {modesOf = function() return {hc = true} end}
local hc = mk(4, 10)
eq(GD.onLoseExperience(hc, 1000), 1000, "Hardcore untouched")
check(not GD.keepAll(hc), "Hardcore drops items")
ChaosSeason = nil
eq(GD.onLoseExperience(mk(5, 10), "x"), "x", "bad input passed through")
local alive = mk(8, 10)
function alive:getHealth() return 150 end
eq(GD.onLoseExperience(alive, 150), 150, "a script's removeExperience (alive, the tutorial reset) is not a death")
eq(#alive.said, 0, "and says nothing")
local dead = mk(9, 10)
function dead:getHealth() return 0 end
eq(GD.onLoseExperience(dead, 150), 0, "a death (health 0) is eased")
ChaosGentleDeathConfig.enabled = false
eq(GD.onLoseExperience(mk(6, 10), 1000), 1000, "off")
check(not GD.keepAll(mk(7, 10)), "off: items drop")
ChaosGentleDeathConfig.enabled = true

-- the death keep hook asks keepAll first
CreatureEvent = function() return {type = function() end, register = function() end} end
GlobalEvent, TalkAction = CreatureEvent, CreatureEvent
dofile("data/scripts/chaos/death_keep.lua")
local item = {getId = function() return 2400 end}
check(ChaosDeathKeep.beforeDrop(mk(8, 10), item, nil) == true, "death keep: a new character keeps the item")

-- ---------------------------------------------------------------- blessings
CONST_ME_HOLYAREA, CONDITION_INFIGHT = 49, 8
local function blessable(id, level, money, bank)
	local p = mk(id, level)
	p.bless, p.money, p.bankGold, p.cancels, p.pz = {}, money or 0, bank or 0, {}, false
	function p:hasBlessing(i) return self.bless[i] == true end
	function p:addBlessing(i) self.bless[i] = true end
	function p:isPzLocked() return self.pz end
	function p:hasCondition() return false end
	function p:getMoney() return self.money end
	function p:getBankBalance() return self.bankGold end
	function p:setBankBalance(v) self.bankGold = v return true end
	function p:removeMoney(g) if self.money < g then return false end self.money = self.money - g return true end
	function p:removeTotalMoney(g)
		if self.money + self.bankGold < g then return false end
		local hand = math.min(self.money, g)
		self.money, self.bankGold = self.money - hand, self.bankGold - (g - hand)
		return true
	end
	function p:sendCancelMessage(m) self.cancels[#self.cancels + 1] = m end
	function p:getPosition() return {sendMagicEffect = function() end} end
	return p
end
local talk = registry[cfg.bless.words]
check(talk ~= nil and talk.onSay ~= nil, "!bless registered")
local pb = blessable(20, 200, 1000, 200000)
pb.bless[1] = true
eq(talk.onSay(pb, "!bless", ""), false, "the words are not said")
eq(pb.money + pb.bankGold, 201000 - 4 * G.blessCost(cfg.bless, 200), "paid four blessings")
for i = 1, 5 do check(pb.bless[i], "blessing " .. i) end
check(pb.said[#pb.said]:find("4 blessing", 1, true) ~= nil, "told: " .. tostring(pb.said[#pb.said]))
Chaos.limited = function() return false end
talk.onSay(pb, "!bless", "")
eq(pb.cancels[#pb.cancels], "You already have all blessings.", "nothing missing")
local poor = blessable(21, 200, 10, 0)
talk.onSay(poor, "!bless", "")
check(poor.cancels[1]:find("you need", 1, true) ~= nil, "no money"); check(not poor.bless[1], "nothing given")
local fighter = blessable(22, 50, 1e9, 0)
fighter.pz = true
talk.onSay(fighter, "!bless", "")
check(fighter.cancels[1]:find("leave combat", 1, true) ~= nil, "in combat"); check(not fighter.bless[1], "nothing in combat")
Chaos.limited = function() return true end
local limited = blessable(23, 50, 1e9, 0)
talk.onSay(limited, "!bless", "")
check(not limited.bless[1] and #limited.cancels == 0, "rate limited: silent")
Chaos.limited = nil

-- the Eternal Blessing: the store service, the login after a death, the offer
ChaosShopServices = {services = {}}
registry.ChaosGentleDeathStartup.onStartup()
local svc = ChaosShopServices.services[cfg.eternal.service]
check(svc == GD.eternalService, "service registered at startup")
local et = blessable(24, 300)
eq(svc.check(et), nil, "can buy")
check(svc.apply(et), "applied")
check(GD.hasEternal(et), "owned"); for i = 1, 5 do check(et.bless[i], "eternal blessing " .. i) end
eq(svc.check(et), "You already have the Eternal Blessing.", "once per character")
et.bless = {} -- a death took them
registry.ChaosGentleDeathLogin.onLogin(et)
for i = 1, 5 do check(et.bless[i], "back at login " .. i) end
local plain = blessable(25, 300)
registry.ChaosGentleDeathLogin.onLogin(plain)
check(not plain.bless[1], "no Eternal Blessing: nothing at login")
local found
for _, cat in ipairs(dofile("data/scripts/chaos/shop_config.lua").categories or {}) do
	for _, o in ipairs(cat.offers or {}) do
		if o.service == cfg.eternal.service then found = o end
	end
end
check(found ~= nil, "store offer"); check(found and found.seasonBlocked == true, "not for season characters")
check(found and found.cost > 0, "a price")

-- ---------------------------------------------------------------- pt-BR keys
local strings = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local fh = io.open("data/scripts/chaos/gentledeath.lua", "r")
local src = fh:read("*a")
fh:close()
local n = 0
for _, pat in ipairs({'tell%(player, "([^"]+)"', 'Chaos%.t%(player, "([^"]+)"'}) do
	for key in src:gmatch(pat) do
		n = n + 1
		check(strings[key] ~= nil, "pt-BR for: " .. key)
	end
end
local core = io.open("data/scripts/chaos/gentledeath_core.lua"):read("*a")
for key in core:gmatch('return "([^"]+)"') do
	n = n + 1
	check(strings[key] ~= nil, "pt-BR for core: " .. key)
end
check(n >= 4, "texts found")

print(string.format("gentledeath_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
