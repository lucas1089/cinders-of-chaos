-- Run from the server/ folder: luajit tests/badges_test.lua (and lua5.3; CI runs both)
-- Badge slot (server/README.md "Badge slot"): the ids of badges_core.lua against the base's upgrade table (nine lines,
-- 40 badges, 31 catalysts, each catalyst one tier up) and the retired items (decks, ships, belts and gloves), the texts
-- in English and pt-BR, the move rule (slots 12, 14, 15 and 16 refuse everything, slot 13 takes a badge and refuses a
-- retired item), the login moves, the ship storages, and the glue badges.lua on a mocked engine (the move refusal, the
-- deck a card is looked for in, a carried ship, the login move into the backpack or the inbox, once).
-- The base data side (slot types, descriptions, the Fury typo, hooks) is tools/patch_badges_test.py.

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
MESSAGE_EVENT_ADVANCE = 19
RETURNVALUE_NOTPOSSIBLE = 4
CONST_SLOT_BACKPACK, CONST_SLOT_DECK = 3, 12
FLAG_NOLIMIT, FLAG_IGNOREAUTOSTACK = 1, 32
local registered = {}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:register() registered[self.name] = self end
	return ev
end
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/badges_core.lua")
local K = ChaosBadgesCore

-- ---------------------------------------------------------------- ids
local nb, nc, nr = 0, 0, 0
for _ in pairs(K.badges) do nb = nb + 1 end
for _ in pairs(K.catalysts) do nc = nc + 1 end
for _ in pairs(K.retired) do nr = nr + 1 end
eq(nb, 40, "40 badges") eq(nc, 31, "31 catalysts") eq(#K.LINES, 9, "nine lines")
eq(nr, 3 + 7 + 24, "3 decks, 7 ships, 24 belts and gloves")
for id = K.FIRST_BADGE, K.LAST_BADGE do ok(K.isBadge(id) and not K.isCatalyst(id) and not K.retiredKind(id), "badge " .. id) end
for id = K.FIRST_CATALYST, K.LAST_CATALYST do ok(K.isCatalyst(id) and not K.isBadge(id), "catalyst " .. id) end
ok(not K.isBadge(27802) and not K.isCatalyst(27874) and not K.isBadge(nil) and not K.isBadge("x"), "outside the ranges")
eq(K.retiredKind(27632), "deck", "Bronze Deck") eq(K.retiredKind(27799), "ship", "the first ship")
eq(K.retiredKind(29919), "beltgloves", "gloves") eq(K.retiredKind(27635), nil, "the legendary card is a card")
eq(K.retiredKind(27849), nil, "a catalyst is not retired")
-- the base's upgrade table (badges_upgrade.lua): a few rows of it
local function cat(id) local c = K.catalysts[id] return c.from .. ">" .. c.to .. "@" .. c.tier end
eq(cat(27843), "27803>27804@2", "Exiled [1]") eq(cat(27845), "27805>27806@4", "Exiled [3]")
eq(cat(27848), "27809>27810@4", "Fury [3]") eq(cat(27849), "27811>27812@2", "Moon [1]")
eq(cat(27852), "27814>27815@5", "Moon [4]") eq(cat(27856), "27819>27820@5", "Night Seeker [4]")
eq(cat(27863), "27828>27829@5", "Reborn [4]") eq(cat(27866), "27832>27833@4", "Chaosfiend [3]")
eq(cat(27869), "27836>27837@4", "Veins [3]") eq(cat(27873), "27841>27842@5", "Daybreak [4]")
eq(K.badges[27811].line, "moon", "Raging Moon Badge") eq(K.badges[K.CONTAINER_BADGE].tier, 5, "Eternal Moon Badge")
for id, c in pairs(K.catalysts) do
	ok(K.isBadge(c.from) and K.isBadge(c.to) and c.to == c.from + 1 and K.badges[c.to].tier == c.tier, "catalyst " .. id)
end

-- ---------------------------------------------------------------- texts
local pt = ChaosI18n.strings["pt-BR"]
for _, key in ipairs({K.TEXT_EQUIP, K.TEXT_RETIRED, K.TEXT_MOVED}) do
	ok(pt[key] ~= nil, "pt-BR for " .. key)
	ok(not key:find("\226\128\148", 1, true) and not (pt[key] or ""):find("\226\128\148", 1, true), "no em dash: " .. key)
end
eq(K.equipText(nil, 27632), K.TEXT_RETIRED, "a deck: it can't be worn")
eq(K.equipText(nil, 2160), K.TEXT_EQUIP, "anything else: the slot is retired")
ok(K.movedText("pt-BR", "x"):find("Movidos: x", 1, true) ~= nil, "pt-BR moved text")

-- ---------------------------------------------------------------- moves
local function inv(slot) return {x = 0xFFFF, y = slot, z = 0} end
ok(not K.refusesMove(27811, inv(13)), "a badge into the badge slot")
ok(not K.refusesMove(27815, inv(13)), "the container badge into the badge slot")
for _, slot in ipairs({12, 14, 15, 16}) do
	ok(K.refusesMove(27811, inv(slot)), "a badge into slot " .. slot)
	ok(K.refusesMove(2160, inv(slot)), "anything into slot " .. slot)
end
ok(K.refusesMove(27632, inv(12)), "a deck into the deck slot")
ok(K.refusesMove(27632, inv(13)), "a deck into the badge slot")
ok(K.refusesMove(27799, inv(14)), "a ship into the ship slot")
ok(K.refusesMove(29577, inv(16)), "gloves into the gloves slot")
ok(K.refusesMove(29577, inv(13)), "gloves into the badge slot")
ok(not K.refusesMove(27632, inv(3)), "a deck onto the backpack slot")
ok(not K.refusesMove(27632, {x = 0xFFFF, y = 0x40, z = 2}), "a deck into a container")
ok(not K.refusesMove(27632, {x = 100, y = 12, z = 7}), "a deck on the map")
ok(not K.refusesMove(2160, inv(9)), "a ring slot is not this rule's")
ok(not K.refusesMove(27811, nil), "no position")

-- ---------------------------------------------------------------- login moves and ship storages
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end
ok(same(K.loginMoves({}), {}), "nothing worn: nothing to move")
ok(same(K.loginMoves({[13] = 27811}), {}), "a badge in slot 13 stays")
ok(same(K.loginMoves({[13] = 27632, [12] = 27633, [14] = 27799, [16] = 29577}), {12, 13, 14, 16}), "the rest moves")
ok(same(K.loginMoves({[15] = 2160}), {15}), "anything in a retired slot moves")
local s = K.shipStorages({[27799] = true}, {[110013] = -1, [110010] = 1})
eq(s[37123], 1, "the carried ship's storage") eq(s[37120], 0, "another ship's storage is cleared")
eq(s[110013], 1, "its trainer portal opens") eq(s[110010], nil, "another portal is never cleared")
eq(s[K.SAILING_STORAGE], 1, "sailing flag")
s = K.shipStorages({}, {[110013] = 1})
eq(s[37123], 0, "no ship: storage 0") eq(s[K.SAILING_STORAGE], 0, "no ship: not sailing") eq(s[110013], nil, "portal kept")
eq(K.shipStorages({[27799] = true}, {[110013] = 1})[110013], nil, "an open portal is not written again")

-- ---------------------------------------------------------------- glue (badges.lua)
local sent = {}
local function newItem(id, props)
	local it = {id = id, items = {}}
	for k, v in pairs(props or {}) do it[k] = v end
	function it:getId() return self.id end
	function it:getName() return "item " .. self.id end
	function it:isContainer() return self.container == true end
	function it:moveTo(to, flags)
		if to.full then return false end
		to.items[#to.items + 1] = self
		self.parent, self.flags = to, flags
		if self.owner then self.owner.slots[self.slot] = nil end
		return true
	end
	return it
end
local nextId = 0
local function newPlayer(lang)
	nextId = nextId + 1
	local p = {id = nextId, slots = {}, storage = {}, carried = {}, saves = 0, inbox = newItem(14404, {container = true}),
		store = newItem(14405, {container = true})}
	function p:getId() return self.id end
	function p:getName() return "Ann" end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(t, text) sent[#sent + 1] = {type = t, text = text} end
	function p:getSlotItem(slot) return self.slots[slot] end
	function p:wear(slot, item) self.slots[slot] = item item.owner, item.slot = self, slot return item end
	function p:getItemById(id) return self.carried[id] end
	function p:getItemCount(id) return self.carried[id] and 1 or 0 end
	function p:getInbox() return self.inbox end
	function p:getStoreInbox() return self.store end
	Chaos.setLang(p, lang or "en")
	return p
end
Chaos.saveCharacter = function(p) p.saves = p.saves + 1 return true end
dofile("data/scripts/chaos/badges.lua")
local B = ChaosBadges
ok(registered.ChaosBadgesLogin ~= nil, "the login event is registered")

local ann = newPlayer()
local badge, deck = newItem(27811), newItem(27632, {container = true})
local n = #sent
eq(B.onMoveItem(ann, deck, inv(13)), RETURNVALUE_NOTPOSSIBLE, "a deck into the badge slot is refused")
eq(#sent, n + 1, "with a message") eq(sent[#sent].text, K.TEXT_RETIRED, "it can't be worn")
eq(B.onMoveItem(ann, badge, inv(12)), RETURNVALUE_NOTPOSSIBLE, "a badge into the deck slot is refused")
eq(sent[#sent].text, K.TEXT_EQUIP, "the slot is retired")
eq(B.onMoveItem(ann, badge, inv(13)), nil, "a badge into the badge slot: the engine decides")
eq(B.onMoveItem(ann, deck, {x = 0xFFFF, y = 0x41, z = 0}), nil, "a deck into a bag: nothing to say")
eq(#sent, n + 2, "no other message")

-- the deck the cards are looked for in
eq(B.deckOf(ann), nil, "no deck")
local silver, golden = newItem(27633, {container = true}), newItem(27634, {container = true})
ann.carried[27633] = silver
eq(B.deckOf(ann), silver, "a carried deck")
ann.carried[27634] = golden
eq(B.deckOf(ann), golden, "the largest carried deck")
local worn = ann:wear(12, newItem(27632, {container = true}))
eq(B.deckOf(ann), worn, "a deck still worn in slot 12 comes first")
ann.slots[12] = nil

-- a carried ship
eq(B.boardShip(ann), false, "no ship: not aboard")
eq(ann.storage[37123], 0, "the ship storage is 0") eq(ann.storage[K.SAILING_STORAGE], 0, "not sailing")
ann.carried[27799] = newItem(27799)
eq(B.boardShip(ann), true, "a carried ship: aboard")
eq(ann.storage[37123], 1, "its storage") eq(ann.storage[110013], 1, "its trainer portal")
eq(ann.storage[K.SAILING_STORAGE], 1, "sailing")

-- the login move
local bia = newPlayer("pt-BR")
local bp = bia:wear(CONST_SLOT_BACKPACK, newItem(1988, {container = true}))
local wornBadge = bia:wear(13, newItem(27811))
local wornDeck = bia:wear(12, newItem(27633, {container = true}))
local wornShip = bia:wear(14, newItem(27797))
local wornGloves = bia:wear(16, newItem(29577))
eq(B.checkSlots(bia), 3, "three items move")
eq(bia.slots[13], wornBadge, "the badge stays worn")
ok(bia.slots[12] == nil and bia.slots[14] == nil and bia.slots[16] == nil, "the retired slots are empty")
eq(wornDeck.parent, bia.store, "into the store inbox (the Purse)") eq(wornGloves.parent, bia.store, "the gloves too")
eq(wornShip.parent, bia.store, "the ship too") eq(#bp.items, 0, "nothing into the backpack")
eq(bia.saves, 1, "saved at once")
ok(sent[#sent].text:find("Movidos:", 1, true) ~= nil and sent[#sent].type == MESSAGE_EVENT_ADVANCE, "told in pt-BR")
eq(B.checkSlots(bia), 0, "a second login moves nothing") eq(bia.saves, 1, "and saves nothing")
local cid = newPlayer()
cid.store.full = true
local lost = cid:wear(15, newItem(29578))
eq(B.checkSlots(cid), 1, "the store inbox refuses: one move") eq(lost.parent, cid.inbox, "into the depot inbox")
-- nowhere to go: the item stays worn (never deleted), nothing saved, tried again at the next login
local dan = newPlayer()
dan.store.full, dan.inbox.full = true, true
local stuck = dan:wear(14, newItem(27797))
eq(B.checkSlots(dan), 0, "nothing moved") eq(dan.slots[14], stuck, "the ship stays where it was") eq(dan.saves, 0, "no save")
dan.store.full = false
eq(B.checkSlots(dan), 1, "the next login moves it") eq(stuck.parent, dan.store, "into the store inbox")

-- the base's one-badge storage
ok(not K.staleBadgeStorage(-1, nil) and not K.staleBadgeStorage(nil, 27811), "unset: nothing to clear")
ok(not K.staleBadgeStorage(27811, 27811), "the badge worn: kept")
ok(K.staleBadgeStorage(27811, nil) and K.staleBadgeStorage(27811, 27812), "no badge or another one worn: cleared")
local eve = newPlayer()
eve.storage[K.BASE_BADGE_STORAGE] = 27822
B.checkSlots(eve)
eq(eve.storage[K.BASE_BADGE_STORAGE], -1, "a stale storage is cleared at login")
local fay = newPlayer()
fay:wear(13, newItem(27822))
fay.storage[K.BASE_BADGE_STORAGE] = 27822
B.checkSlots(fay)
eq(fay.storage[K.BASE_BADGE_STORAGE], 27822, "the storage of the worn badge stays")

print(string.format("badges_test: %d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
