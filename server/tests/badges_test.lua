-- Run from the server/ folder: luajit tests/badges_test.lua (and lua5.3; CI runs both)
-- Retired badges (server/README.md "Retired badges"): the ids of badges_core.lua against the base's upgrade table
-- (nine lines, 40 badges, 31 catalysts, each catalyst one tier up), the texts in English and pt-BR, the move rule
-- (slots 12 and 13 refuse a badge, every other place takes it), and the glue badges.lua on a mocked engine: a catalyst
-- use explains, names the Loot Buyer's price and keeps both items; a badge move into slot 13 is refused with the text.
-- The base data side (drops, rewards, prizes, hooks, descriptions) is tools/patch_badges_test.py.

local checks, failures = 0, 0
local function ok(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	ok(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

-- ---------------------------------------------------------------- mocked engine
MESSAGE_INFO_DESCR = 22
CONST_ME_POFF = 3
RETURNVALUE_NOTPOSSIBLE = 4
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/badges_core.lua")
local K = ChaosBadgesCore

-- ---------------------------------------------------------------- ids
local nb, nc = 0, 0
for _ in pairs(K.badges) do nb = nb + 1 end
for _ in pairs(K.catalysts) do nc = nc + 1 end
eq(nb, 40, "40 badges") eq(nc, 31, "31 catalysts") eq(#K.LINES, 9, "nine lines")
eq(#K.ids(), 71, "71 retired ids")
for id = K.FIRST_BADGE, K.LAST_BADGE do ok(K.isBadge(id) and not K.isCatalyst(id), "badge " .. id) end
for id = K.FIRST_CATALYST, K.LAST_CATALYST do ok(K.isCatalyst(id) and not K.isBadge(id), "catalyst " .. id) end
ok(not K.isBadge(27802) and not K.isCatalyst(27874) and not K.isBadge(nil) and not K.isBadge("x"), "outside the ranges")
-- the base's upgrade table (badges_upgrade.lua): a few rows of it
local function cat(id) local c = K.catalysts[id] return c.from .. ">" .. c.to .. "@" .. c.tier end
eq(cat(27843), "27803>27804@2", "Exiled [1]") eq(cat(27845), "27805>27806@4", "Exiled [3]")
eq(cat(27848), "27809>27810@4", "Fury [3]") eq(cat(27849), "27811>27812@2", "Moon [1]")
eq(cat(27852), "27814>27815@5", "Moon [4]") eq(cat(27856), "27819>27820@5", "Night Seeker [4]")
eq(cat(27863), "27828>27829@5", "Reborn [4]") eq(cat(27866), "27832>27833@4", "Chaosfiend [3]")
eq(cat(27869), "27836>27837@4", "Veins [3]") eq(cat(27873), "27841>27842@5", "Daybreak [4]")
eq(K.badges[27811].line, "moon", "Raging Moon Badge") eq(K.badges[27815].tier, 5, "Eternal Moon Badge")
for id, c in pairs(K.catalysts) do
	ok(K.isBadge(c.from) and K.isBadge(c.to) and c.to == c.from + 1 and K.badges[c.to].tier == c.tier, "catalyst " .. id)
end

-- ---------------------------------------------------------------- texts
local pt = ChaosI18n.strings["pt-BR"]
for _, key in ipairs({K.TEXT_CATALYST, K.TEXT_PRICE, K.TEXT_EQUIP}) do
	ok(pt[key] ~= nil, "pt-BR for " .. key)
end
eq(K.catalystText(16000), K.TEXT_CATALYST .. " The Loot Buyer pays 16000 gold for it.", "English with a price")
eq(K.catalystText(0), K.TEXT_CATALYST, "no price: not named")
ok(K.catalystText(16000, "pt-BR"):find("O Loot Buyer paga 16000 de ouro", 1, true) ~= nil, "pt-BR with a price")
ok(K.equipText("pt-BR"):find("aposentados", 1, true) ~= nil, "pt-BR equip text")
for _, s in ipairs({K.TEXT_CATALYST, K.TEXT_PRICE, K.TEXT_EQUIP, pt[K.TEXT_CATALYST], pt[K.TEXT_EQUIP]}) do
	ok(not s:find("\226\128\148", 1, true), "no em dash: " .. s)
end

-- ---------------------------------------------------------------- moves
ok(K.refusesMove(27811, {x = 0xFFFF, y = 13, z = 0}), "a badge into the badge slot")
ok(K.refusesMove(27811, {x = 0xFFFF, y = 12, z = 0}), "a badge into the deck slot")
ok(not K.refusesMove(27811, {x = 0xFFFF, y = 3, z = 0}), "a badge onto the backpack slot")
ok(not K.refusesMove(27811, {x = 0xFFFF, y = 0x40, z = 2}), "a badge into a container")
ok(not K.refusesMove(27811, {x = 100, y = 13, z = 7}), "a badge on the map")
ok(not K.refusesMove(27632, {x = 0xFFFF, y = 12, z = 0}), "a deck is not a badge")
ok(not K.refusesMove(27849, {x = 0xFFFF, y = 13, z = 0}), "a catalyst is not a badge (no slot takes it anyway)")
ok(not K.refusesMove(27811, nil), "no position")

-- ---------------------------------------------------------------- glue (badges.lua)
local sent, effects = {}, 0
local function newPlayer(id, lang)
	local p = {id = id}
	function p:getId() return self.id end
	function p:getStorageValue() return -1 end
	function p:setStorageValue() end
	function p:sendTextMessage(t, text) sent[#sent + 1] = {type = t, text = text} end
	function p:getPosition() return {sendMagicEffect = function() effects = effects + 1 end} end
	Chaos.setLang(p, lang or "en")
	return p
end
local function newItem(id, count)
	local it = {id = id, count = count or 1, removed = 0}
	function it:getId() return self.id end
	function it:remove(n) self.removed = self.removed + (n or 1) end
	function it:transform(to) self.id = to end
	return it
end
ChaosItemPrices = {sellPrice = function(item) return item:getId() == 27849 and 16000 or 0 end}
dofile("data/scripts/chaos/badges.lua")
local B = ChaosBadges
local ann, bia = newPlayer(1), newPlayer(2, "pt-BR")
local catalyst, badge = newItem(27849), newItem(27811)
eq(B.onCatalystUse(ann, catalyst, badge), true, "the catalyst use is handled")
eq(catalyst.removed, 0, "the catalyst is kept") eq(badge:getId(), 27811, "the badge is not upgraded")
eq(sent[#sent].type, MESSAGE_INFO_DESCR, "an info message")
eq(sent[#sent].text, K.TEXT_CATALYST .. " The Loot Buyer pays 16000 gold for it.", "the text with the price")
eq(effects, 1, "a puff")
B.onCatalystUse(bia, catalyst, badge)
ok(sent[#sent].text:find("Loot Buyer paga 16000", 1, true) ~= nil, "pt-BR reader")
eq(B.onCatalystUse(ann, newItem(2160), badge), false, "not a catalyst: the base action goes on")
local n = #sent
eq(B.onMoveItem(ann, badge, {x = 0xFFFF, y = 13, z = 0}), RETURNVALUE_NOTPOSSIBLE, "badge slot refused")
eq(#sent, n + 1, "with a message") eq(sent[#sent].text, K.TEXT_EQUIP, "the equip text")
eq(B.onMoveItem(ann, badge, {x = 0xFFFF, y = 0x41, z = 0}), nil, "into a bag: nothing to say")
eq(B.onMoveItem(ann, newItem(2160), {x = 0xFFFF, y = 13, z = 0}), nil, "another item: the base decides")
eq(#sent, n + 1, "no other message")

print(string.format("badges_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
