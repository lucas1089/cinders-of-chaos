-- Run from the server/ folder: luajit tests/lootline_test.lua (and lua5.3; mock engine API, CI runs it)
-- One loot line per kill (data/scripts/chaos/lootline_core.lua, lootline.lua): playtest 2026-10-16, a kill printed
-- "Loot of ...", "Chaos bonus loot of ..." and "Looted: ...". The rules of the merged line, then the onDropLoot chain on
-- a mocked engine: the stock line is held back, the bonus items and the pouch part join it, one line is sent (the
-- owner's with the pouch part, the party's without it), other messages pass, and without a record nothing changes.
local checks, failures = 0, 0
local function check(v, m)
	checks = checks + 1
	if not v then
		failures = failures + 1
		print("FAIL " .. tostring(m))
	end
end
local function eq(a, b, m) check(a == b, tostring(m) .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

local K = dofile("data/scripts/chaos/lootline_core.lua")

-- ---------------------------------------------------------------- the rules
check(K.isStockLine("Loot of a dragon: 120 gold coins"), "a stock line")
check(not K.isStockLine("Looted: 120 gold coins."), "the pouch line is not")
check(not K.isStockLine("Loot of nothing"), "no item list")
local m, items = K.split("Loot of an abyssal gazer: a gold coin, a meat")
eq(m, "an abyssal gazer", "the monster")
eq(items, "a gold coin, a meat", "the items")

eq(K.compose({stock = "Loot of a dragon: 120 gold coins, a dragon ham", bonus = {"2 ember shards", "{Ashbringer}"},
	pouch = "Looted: 120 gold coins, {Ashbringer} (2 to your backpack)."}),
	"Loot of a dragon: 120 gold coins, a dragon ham, 2 ember shards, {Ashbringer}. Looted: 120 gold coins, " ..
	"{Ashbringer} (2 to your backpack).", "one line: stock, bonus, pouch")
eq(K.compose({stock = "Loot of a dragon: 120 gold coins", bonus = {"{Ashbringer}"},
	pouch = "Looted: {Ashbringer} (Loot Bag is full)."}, false),
	"Loot of a dragon: 120 gold coins, {Ashbringer}.", "a party member: without the owner's pouch part")
eq(K.compose({stock = "Loot of a rat: nothing", bonus = {"an ember shard"}}), "Loot of a rat: an ember shard.",
	"an empty corpse: the bonus replaces nothing")
eq(K.compose({stock = "Loot of a rat: nothing (due to low stamina)", bonus = {}}),
	"Loot of a rat: nothing (due to low stamina).", "low stamina, no bonus")
eq(K.compose({stock = "Loot of a rat: a meat"}), "Loot of a rat: a meat.", "the stock line alone")
eq(K.compose({monster = "a rat", bonus = {"{Ashbringer}"}}), "Loot of a rat: {Ashbringer}.", "no stock line")
eq(K.compose({pouch = "Looted: nothing (Loot Bag is full)."}), "Looted: nothing (Loot Bag is full).", "only the pouch")
eq(K.compose({bonus = {}}), nil, "nothing to say")

-- ---------------------------------------------------------------- the engine side
local byName
MESSAGE_LOOT, MESSAGE_INFO_DESCR = 22, 20
local sent = {} -- {who, mode, text}
local players = {}
local Pmeta = {}
Player = setmetatable({}, {__call = function(_, id) return players[id] end})
Pmeta.__index = Player
function Player.sendTextMessage(self, mode, text)
	sent[#sent + 1] = {self.name, mode, text}
	return true
end
function Player.getId(self) return self.id end
function Player.getParty(self) return self.party end
Party = {}
local PartyMeta = {__index = Party}
function Party.broadcastPartyLoot(self, text)
	for _, p in ipairs({self.leader, unpack and unpack(self.members) or table.unpack(self.members)}) do
		Player.sendTextMessage(p, MESSAGE_LOOT, text)
	end
end
function Party.getLeader(self) return self.leader end
function Party.getMembers(self) return self.members end
local function mkPlayer(id, name)
	local p = setmetatable({id = id, name = name}, Pmeta)
	players[id] = p
	return p
end
local cara = mkPlayer(1, "Cara")
local bo = mkPlayer(2, "Bo")
Chaos = {monsterNameDescription = function(mon) return mon.desc end}

local callbacks, pending = {}, nil
EventCallback = setmetatable({}, {
	__index = function(_, k)
		if k == "register" then
			return function(_, index) callbacks[#callbacks + 1] = {fn = pending, index = index or 0} end
		end
	end,
	__newindex = function(_, _, v) pending = v end
})

dofile("data/scripts/chaos/lootline.lua")
local X = ChaosLootLine
eq(#callbacks, 2, "two callbacks")
check(callbacks[1].index < 0 and callbacks[2].index >= 99, "before the stock callback (0), after the empty corpse check (99)")

-- a kill's chain: stock (0), the Chaos layer (1), the pouches (2.7)
local function kill(monster, corpse, owner, steps)
	local chain = {{index = callbacks[1].index, fn = callbacks[1].fn}, {index = callbacks[2].index, fn = callbacks[2].fn}}
	for _, s in ipairs(steps) do
		chain[#chain + 1] = s
	end
	table.sort(chain, function(a, b) return a.index < b.index end)
	for _, c in ipairs(chain) do
		c.fn(monster, corpse)
	end
end
local function stock(text)
	return {index = 0, fn = function(_, corpse)
		local owner = Player(corpse.owner)
		if owner:getParty() then
			owner:getParty():broadcastPartyLoot(text)
		else
			owner:sendTextMessage(MESSAGE_LOOT, text)
		end
	end}
end
local function layer(items)
	return {index = 1, fn = function(mon) check(X.addBonus(mon, items), "the bonus joins the line") end}
end
local function pouch(text)
	return {index = 2.7, fn = function(mon)
		check(X.addPouch(mon, text), "the pouch part joins the line")
		Player(1):sendTextMessage(MESSAGE_INFO_DESCR, "Auto seller: kept a locked item.") -- other messages pass
	end}
end

local Cmeta = {__index = {getCorpseOwner = function(self) return self.owner end}}
local function corpseOf(owner) return setmetatable({owner = owner}, Cmeta) end

local dragon = {id = 900, desc = "a dragon"}
kill(dragon, corpseOf(1), cara, {stock("Loot of a dragon: 120 gold coins"), layer({"{Ashbringer}"}),
	pouch("Looted: 120 gold coins (2 to your backpack).")})
eq(#sent, 2, "one loot line and the other message")
eq(sent[1][3], "Auto seller: kept a locked item.", "the other message is not held")
eq(sent[2][2], MESSAGE_LOOT, "a loot message")
eq(sent[2][3], "Loot of a dragon: 120 gold coins, {Ashbringer}. Looted: 120 gold coins (2 to your backpack).",
	"the one line")
eq(X.current, nil, "the record is closed")

-- a party: the stock line was broadcast; the owner gets the pouch part, the others not
sent = {}
local party = setmetatable({leader = bo, members = {cara}}, PartyMeta)
cara.party, bo.party = party, party
kill({id = 901, desc = "a rat"}, corpseOf(1), cara, {stock("Loot of a rat: a meat"), layer({"an ember shard"}),
	pouch("Looted: an ember shard.")})
eq(#sent, 3, "one line per member, and the other message")
byName = {}
for _, s in ipairs(sent) do
	if s[2] == MESSAGE_LOOT then
		check(byName[s[1]] == nil, "one loot line for " .. s[1])
		byName[s[1]] = s[3]
	end
end
eq(byName.Bo, "Loot of a rat: a meat, an ember shard.", "the other member: no pouch part")
eq(byName.Cara, "Loot of a rat: a meat, an ember shard. Looted: an ember shard.", "the owner: with it")
cara.party, bo.party = nil, nil

-- no owner (no record): nothing held; outside a kill every message passes
sent = {}
kill({id = 902, desc = "a wolf"}, corpseOf(99), nil, {})
eq(#sent, 0, "no owner: nothing")
cara:sendTextMessage(MESSAGE_LOOT, "Loot of a wolf: a meat")
eq(#sent, 1, "no open record: the stock line passes")
check(not X.addBonus({id = 903}, {"x"}), "no record: the caller sends its own line")
check(not X.addPouch({id = 903}, "Looted: x."), "no record: the pouch sends its own line")

-- a record a failed chain left open is sent when the next kill opens one
sent = {}
callbacks[1].fn({id = 904, desc = "a bat"}, corpseOf(1))
cara:sendTextMessage(MESSAGE_LOOT, "Loot of a bat: a meat")
eq(#sent, 0, "held")
kill({id = 905, desc = "a bear"}, corpseOf(1), cara, {stock("Loot of a bear: nothing")})
eq(#sent, 2, "the stale line, then the new one")
eq(sent[1][3], "Loot of a bat: a meat.", "the stale line is not lost")
eq(sent[2][3], "Loot of a bear: nothing.", "the new kill")

-- ---------------------------------------------------------------- the player's language (coordinator follow-up)
-- the fixed parts ("Loot of", "Looted:", the pouch notes, "nothing") come from i18n_strings.lua; item names stay
local strings = dofile("data/scripts/chaos/i18n_strings.lua")
local ptS = strings["pt-BR"]
local function T(lang)
	return function(key, ...)
		local pat = lang == "pt-BR" and ptS[key] or key
		if select("#", ...) == 0 then return pat end
		return string.format(pat, ...)
	end
end
for _, key in ipairs({"Loot of %s: %s", "nothing", "nothing (due to low stamina)", "a creature", "Looted: %s",
		"%s is full", "%d to your %s", "%d to your backpack", "%d left in the corpse, no room", " and %d more"}) do
	check(ptS[key] ~= nil, "pt-BR: " .. key)
end
eq(K.compose({stock = "Loot of a dragon: 120 gold coins", bonus = {"{Ashbringer}"}, pouch = "Coletado: {Ashbringer}."},
	true, T("pt-BR")), "Loot de a dragon: 120 gold coins, {Ashbringer}. Coletado: {Ashbringer}.",
	"pt-BR: the prefix translated, the names as the engine gives them")
eq(K.compose({stock = "Loot of a rat: nothing (due to low stamina)"}, true, T("pt-BR")), "Loot de a rat: nada (stamina baixa).",
	"pt-BR: the stock nothing")
eq(K.compose({stock = "Loot of a rat: a meat"}, true, T("en")), "Loot of a rat: a meat.", "English unchanged")

-- the pouch part in the owner's language (pouches_core.lua summary)
local PC = dofile("data/scripts/chaos/pouches_core.lua")
local pcfg = dofile("data/scripts/chaos/pouches_config.lua")
local looted = {{id = 3031, name = "gold coin", plural = "gold coins", count = 120, rarity = 0}}
eq(PC.summary(pcfg, looted, 2, 1, {loot = true}, 3, T("pt-BR")),
	"Coletado: 120 gold coins (Loot Bag está cheio; 3 para seu Loot Bag; 2 para sua mochila; 1 ficou no corpo, sem espaço).",
	"pt-BR: Looted and the notes")
eq(PC.summary(pcfg, {}, 2, 0, {}, 0, T("pt-BR")), "Coletado: nada (2 para sua mochila).", "pt-BR: nothing looted")
eq(PC.summary(pcfg, looted, 2, 0, {}, 0), "Looted: 120 gold coins (2 to your backpack).", "English by default")

-- the engine side: each party member reads the line in their own language
cara.lang, bo.lang = "pt-BR", "en"
Chaos.t = function(player, key, ...) return T(player.lang)(key, ...) end
sent = {}
local party2 = setmetatable({leader = bo, members = {cara}}, PartyMeta)
cara.party, bo.party = party2, party2
kill({id = 906, desc = "a rat"}, corpseOf(1), cara, {stock("Loot of a rat: nothing"), layer({"an ember shard"}),
	{index = 2.7, fn = function(mon) X.addPouch(mon, "Coletado: an ember shard.") end}})
byName = {}
for _, s in ipairs(sent) do byName[s[1]] = s[3] end
eq(byName.Cara, "Loot de a rat: an ember shard. Coletado: an ember shard.", "the owner in pt-BR, with the pouch part")
eq(byName.Bo, "Loot of a rat: an ember shard.", "the other member in English, without it")
cara.party, bo.party = nil, nil
sent = {}
kill({id = 907, desc = "a bat"}, corpseOf(1), cara, {stock("Loot of a bat: nothing")})
eq(sent[1][3], "Loot de a bat: nada.", "solo pt-BR: the stock nothing translated")

-- ---------------------------------------------------------------- rarity of stock items (rolled after the stock line)
-- the stock line names the rarity the stock callback rolled; loot.lua raises it afterwards. Every stock entry shows
-- its final rarity, in {} from Rare (3) on.
eq(K.compose({stock = "Loot of a dragon: 120 gold coins, [Rare] fire sword, [Uncommon] plate armor"}),
	"Loot of a dragon: 120 gold coins, {[Rare] fire sword}, [Uncommon] plate armor.", "stock Rare: {}; Uncommon: none")
eq(K.compose({stock = "Loot of a dragon: 120 gold coins, [Common] fire sword, plate armor",
	upgrades = {{name = "fire sword", from = "Common", to = "Epic"}, {name = "plate armor", to = "Uncommon"}}}),
	"Loot of a dragon: 120 gold coins, {[Epic] fire sword}, [Uncommon] plate armor.",
	"raised after the stock line: the entry shows the final rarity, no duplicate")
eq(K.compose({stock = "Loot of a dragon: [Rare] fire sword, [Rare] fire sword",
	upgrades = {{name = "fire sword", from = "Rare", to = "Mythic"}}}),
	"Loot of a dragon: {[Mythic] fire sword}, {[Rare] fire sword}.", "two of a kind: one raise, one entry")
eq(K.compose({stock = "Loot of a dragon: a meat", upgrades = {{name = "fire sword", from = "Rare", to = "Legendary"}},
	bonus = {"{Ashbringer}"}}),
	"Loot of a dragon: a meat, {[Legendary] fire sword}, {Ashbringer}.", "no matching entry: a bonus item")
eq(K.compose({stock = "Loot of a rat: nothing", upgrades = {{name = "fire sword", to = "Rare"}}}),
	"Loot of a rat: {[Rare] fire sword}.", "an empty stock line: the raise replaces nothing")
eq(K.compose({monster = "a rat", upgrades = {{name = "fire sword", to = "Epic"}}}),
	"Loot of a rat: {[Epic] fire sword}.", "no stock line")
eq(K.compose({stock = "Loot of a dragon: 2x [Rare] arrows, {Ashbringer}"}),
	"Loot of a dragon: {2x [Rare] arrows}, {Ashbringer}.", "a count kept inside, an entry in {} left as is")
eq(K.compose({stock = "Loot of a dragon: [Rare] fire sword", flag = 5}), "Loot of a dragon: [Rare] fire sword.",
	"the flag from the config")
eq(K.compose({stock = "Loot of a dragon: [Strange] fire sword"}), "Loot of a dragon: [Strange] fire sword.",
	"an unknown rarity name: no {}")
eq(K.compose({stock = "Loot of a dragon: [Rare] fire sword"}, true, T("pt-BR")),
	"Loot de a dragon: {[Rare] fire sword}.", "pt-BR: the same marks")
local cfgNames = dofile("data/scripts/chaos/loot_config.lua")
cfgNames = ChaosLootConfig and ChaosLootConfig.gear.names or (cfgNames and cfgNames.gear and cfgNames.gear.names)
for i, n in ipairs(K.RARITY_NAMES) do
	eq(cfgNames and cfgNames[i], n, "the default rarity names are loot_config.lua's: " .. n)
end

-- the engine side: loot.lua's raise reaches the line through addUpgrade
sent = {}
kill({id = 908, desc = "a dragon"}, corpseOf(1), cara, {stock("Loot of a dragon: 120 gold coins, [Common] fire sword"),
	{index = 1, fn = function(mon)
		check(X.addUpgrade(mon, {name = "fire sword", from = "Common", to = "Rare"}), "the raise joins the line")
	end}})
eq(sent[1] and sent[1][3], "Loot de a dragon: 120 gold coins, {[Rare] fire sword}.", "the merged line shows the raise")
check(not X.addUpgrade({id = 909}, {name = "x", to = "Rare"}), "no record: loot.lua lists the raise itself")
local lootSrc = io.open("data/scripts/chaos/loot.lua"):read("*a")
check(lootSrc:find("ChaosLootLine.addUpgrade(monster, up)", 1, true) ~= nil, "loot.lua hands its raises to the line")

print(string.format("lootline_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
