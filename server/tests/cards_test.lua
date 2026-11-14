-- Run from the server/ folder: luajit tests/cards_test.lua (and lua5.3; CI runs both)
-- Cards and decks (server/README.md "Cards and decks"): cards_config.lua (60 + 16 cards, the base storages, the three
-- decks), cards_core.lua (reconcile, decide, the bonus and status texts in English and pt-BR) and the glue cards.lua on a
-- mocked engine: a card used loose goes into a deck with room and turns on, used again turns off; no deck says how to get
-- one; a deck found in a closed bag at any depth; a second copy or a second deck never counts twice; the limit of five;
-- a card that left the decks is turned off; nothing is duplicated or lost by the moves; login keeps the state.

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
local registered = {}
function CreatureEvent(name)
	local ev = {name = name}
	function ev:type() end
	function ev:register() registered[name] = self end
	return ev
end
function GlobalEvent(name)
	local ev = {name = name}
	function ev:interval(ms) self.ms = ms end
	function ev:register() registered[name] = self end
	return ev
end
local itemNames = {}
function ItemType(id)
	return {getName = function() return itemNames[id] or ("item " .. id) end}
end

local nextUid = 0
local Item = {}
Item.__index = Item
local function newItem(id, children, capacity)
	nextUid = nextUid + 1
	local it = setmetatable({id = id, aid = 0, uid = nextUid, kids = children, cap = capacity}, Item)
	for _, k in ipairs(children or {}) do
		k.parent = it
	end
	return it
end
function Item:getId() return self.id end
function Item:getActionId() return self.aid end
function Item:setActionId(a) self.aid = a end
function Item:isContainer() return self.kids ~= nil end
function Item:getSize() return #self.kids end
function Item:getItem(i) return self.kids[i + 1] end
function Item:getName() return itemNames[self.id] or ("item " .. self.id) end
function Item:getItems() return self.kids end
function Item:getCount() return 1 end
function Item:remove()
	local from = self.parent
	for i, k in ipairs(from and from.kids or {}) do
		if k == self then
			table.remove(from.kids, i)
			break
		end
	end
	self.parent = nil
	return true
end
function Item:moveTo(dest)
	if #dest.kids >= dest.cap then
		return false
	end
	local from = self.parent
	for i, k in ipairs(from.kids) do
		if k == self then
			table.remove(from.kids, i)
			break
		end
	end
	dest.kids[#dest.kids + 1] = self
	self.parent = dest
	return true
end

local players = {}
local function newPlayer(name)
	local p = {name = name, id = #players + 1, slots = {}, storage = {}, messages = {}}
	function p:getId() return self.id end
	function p:getName() return self.name end
	function p:registerEvent(name) self.events = self.events or {}; self.events[name] = true end
	function p:getSlotItem(s) return self.slots[s] end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:sendTextMessage(_, text) self.messages[#self.messages + 1] = text end
	p.ext = {}
	function p:sendExtendedOpcode(op, buf) self.ext[#self.ext + 1] = {op = op, buf = buf} return true end
	players[#players + 1] = p
	return p
end
Game = {getPlayers = function() return players end}
EventCallback = {register = function() end}

-- the JSON of the card state message is kept as a table so the test reads it back
json = {encode = function(t) return t end, decode = function(t) if t == "@msg" then return TEST_MSG end return {action = t} end}
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/cards.lua")
local K, C, M = ChaosCardsCore, ChaosCardsCore.config, ChaosCards

-- ---------------------------------------------------------------- the data
local n, legendary = 0, 0
local seen = {}
for id, c in pairs(C.cards) do
	n = n + 1
	ok(not seen[c.storage], "storage once: " .. c.storage)
	seen[c.storage] = true
	if c.legendary then
		legendary = legendary + 1
	end
end
eq(n, 76, "76 cards") eq(legendary, 16, "16 legendary cards")
eq(C.cards[27482].storage, 37000, "first card storage") eq(C.cards[27541].storage, 37059, "last common card storage")
eq(C.cards[27547].storage, 37065, "first legendary storage") eq(C.cards[27640].storage, 37076, "the Paladin 5% card is 27640")
eq(C.cards[27631].storage, 37080, "last legendary storage")
eq(C.cards[27482].element, "Earth", "first card element") eq(C.cards[27485].element, "Energy", "mythic of the first line")
eq(C.cards[27526].kind, "heal", "heal line") eq(C.cards[27534].kind, "widen", "Taunt of Iron line")
eq(C.cards[27514].spell, "Bloodlust", "melee buff line") eq(C.cards[27538].spell, "Tautstring", "bow buff line")
eq(C.maxActive, 5, "five at once") eq(C.activeActionId, 37866, "the base's action id")
-- the card list matches the patch tool's list (tools/patch_badges.py CARDS)
local f = io.open("tools/patch_badges.py", "rb")
local py = f:read("*a")
f:close()
ok(py:find("tuple(range(27482, 27542)) + tuple(range(27547, 27632, 6)) + (27640,)", 1, true) ~= nil, "the tool's card list")
for id = 27482, 27541 do ok(K.isCard(id), "common to mythic " .. id) end
for id = 27547, 27631, 6 do ok(K.isCard(id), "legendary level 6 " .. id) end
ok(K.isCard(27640) and not K.isCard(27635) and not K.isCard(27632) and not K.isCard(nil), "ids outside")

-- every card has a bonus text in both languages, none empty, no stray format
for id in pairs(C.cards) do
	for _, lang in ipairs({"en", "pt-BR"}) do
		local t = K.bonusText(lang, id)
		ok(type(t) == "string" and #t > 10 and not t:find("%%[sd]"), "bonus text " .. id .. " " .. lang)
	end
end
eq(K.bonusText("en", 27482), "While on, Reaping Gyre deals Earth damage instead. With several cards of this spell on, the highest one counts.", "convert text")
eq(K.bonusText("pt-BR", 27482), "Ativa, Reaping Gyre causa dano de Terra no lugar. Com várias cartas desta magia ativas, vale a mais alta.", "convert text pt-BR")
eq(K.bonusText("en", 27526), "While on, Grand Mending heals 10% more. With several cards of this spell on, the highest one counts.", "heal text")
eq(K.bonusText("en", 27547),
	"Needs a wand or a rod in your left hand. While on, a hit of 50 damage or more has a 7% chance to summon a monster that fights with you and gives you 3 more magic level for 25 seconds. Only one summon at a time.",
	"legendary text")
ok(K.bonusText("pt-BR", 27547):find("nível mágico", 1, true) ~= nil, "legendary text pt-BR")
eq(K.bonusText("en", 1), "", "not a card")

-- ---------------------------------------------------------------- core: decide, reconcile, quest, payloads
local D = ChaosCardDeck
local Deck = ChaosCardDeck
local DK = C.deck
local function d(over)
	local s = {id = 27482, owned = 1, isOn = false, count = 0, unlocked = true}
	for k, v in pairs(over or {}) do s[k] = v end
	return K.decide(s)
end
eq(d(), "on", "owned, unlocked: on") eq(d({unlocked = false}), "locked", "locked Deck")
eq(d({owned = 0}), "none", "no copy") eq(d({isOn = true}), "off", "on: off")
eq(d({count = 5}), "max", "five on") eq(d({count = 5, isOn = true}), "off", "off at five")
eq(d({id = 27632}), "notcard", "a deck is not a card") eq(d({unlocked = false, isOn = true}), "locked", "locked wins")
ok(K.isRetiredDeck(27632) and K.isRetiredDeck(27634) and not K.isRetiredDeck(27482), "the retired decks")
ok(C.decks == nil, "no deck table any more")
eq(DK.name, "Deck of Cards", "the name") eq(C.maxActive, 5, "the slot rule is kept: five on")

-- the storage keys: inside the block, once each, apart from the card storages
do
	local seenKeys = {}
	for _, id in ipairs(K.cardIds()) do
		local ck, fk = K.countKey(id), K.freshKey(id)
		ok(ck >= DK.storage.base and fk <= DK.storage.last and ck < fk, "keys of " .. id .. " inside the block")
		ok(not seenKeys[ck] and not seenKeys[fk], "keys of " .. id .. " are new")
		seenKeys[ck], seenKeys[fk] = true, true
	end
	eq(DK.storage.base, 7104400, "the block") eq(K.countKey(27482), 7104400, "first count") eq(K.freshKey(27482), 7104500, "first mark")
	ok(DK.storage.base + DK.storage.decksFound <= DK.storage.last, "the notes fit")
end
eq(K.addCopies(nil, 1), 1, "copies from nothing") eq(K.addCopies(-1, 2), 2, "unset is -1") eq(K.addCopies(DK.maxCopies, 5), DK.maxCopies, "capped")

-- reconcile
do
	local owned = {[27482] = 1, [27483] = 0}
	local on = {[27482] = 1, [27483] = 1, [27484] = 1}
	local plan = K.reconcile(function(id) return owned[id] or 0 end, function(id) return on[id] or 0 end, true)
	eq(table.concat(plan.off, ","), "27483,27484", "cards with no copy go off") eq(K.activeCount(plan), 1, "one stays")
	plan = K.reconcile(function(id) return owned[id] or 0 end, function(id) return on[id] or 0 end, false)
	eq(#plan.off, 3, "locked: every card goes off") eq(plan.lockedOff, true, "and says why") eq(K.activeCount(plan), 0, "none on")
	local seven = {}
	for id = 27482, 27488 do seven[id] = 1 end
	plan = K.reconcile(function() return 3 end, function(id) return seven[id] or 0 end, true)
	eq(K.activeCount(plan), 5, "never more than five") eq(table.concat(plan.off, ","), "27487,27488", "the highest ids go first")
end

-- payloads
do
	local cards = K.cardsPayload("en", function(id) return "Card " .. id end, function(id) return id + 1000 end)
	eq(#cards.cards, 76, "the list holds every card") eq(cards.max, 5, "the slot rule travels")
	local row
	for _, r in ipairs(cards.cards) do if r.i == 27482 then row = r end end
	eq(row.c, 28482, "client id") eq(row.n, "Card 27482", "name") eq(row.t, 1, "tier") eq(row.r, "Common", "rarity") eq(row.e, "Earth", "element")
	eq(row.l, "Reaping Gyre", "line") eq(row.k, "convert", "kind") eq(row.s, "Earth", "the set element")
	ok(#row.x > 20, "text") ok(row.cl and #row.cl >= 3, "classes of a convert line")
	local leg
	for _, r in ipairs(cards.cards) do if r.i == 27547 then leg = r end end
	eq(leg.r, "Legendary", "legendary rarity") eq(leg.t, 5, "legendary tier") eq(leg.l, "Sorcerer", "legendary class")
	ok(leg.cl and #leg.cl >= 1, "legendary classes by weapon")
	for _, r in ipairs(cards.cards) do
		ok(r.r ~= nil and r.t >= 1 and r.t <= 5, "rarity " .. r.i)
	end
end

-- ---------------------------------------------------------------- the glue on a mocked engine
itemNames[27482], itemNames[27483], itemNames[27632] = "Common One Card", "Rare One Card", "Bronze Deck"
itemNames[27633], itemNames[27634], itemNames[27547] = "Silver Deck", "Golden Deck", "Legendary Two Lv6"

local function mkPlayer(name)
	local p = newPlayer(name)
	p.backpack = newItem(1988, {}, 30)
	p.slots[3] = p.backpack
	p.level, p.gold = 50, 100000
	function p:getLevel() return self.level end
	function p:getMoney() return self.gold end
	function p:removeMoney(n) if self.gold < n then return false end self.gold = self.gold - n return true end
	return p
end
local function put(bag, item)
	bag.kids[#bag.kids + 1] = item
	item.parent = bag
	return item
end
local function lastMsg(p) return p.messages[#p.messages] end
local function anyMsg(p, text)
	for _, m in ipairs(p.messages) do if m:find(text, 1, true) then return true end end
	return false
end
local function lastExt(p) return p.ext[#p.ext] end

-- the toasts of ChaosNotify.send (kind newcard)
local toasts = {}
ChaosNotify = {send = function(player, title, text, kind) toasts[#toasts + 1] = {who = player:getId(), title = title, text = text, kind = kind} return true end}

-- a card looted: loose in the backpack. The absorb takes it in, a new card is marked and toasted; Deck is locked
local p = mkPlayer("Alice")
local card = put(p.backpack, newItem(27482))
eq(M.use(p, card), true, "a used card is handled") eq(M.use(p, newItem(2160)), nil, "not a card: the base runs")
eq(D.owned(p, 27482), 1, "one copy in the Deck") eq(#p.backpack.kids, 0, "the item is gone: no inventory item")
eq(D.isFresh(p, 27482), true, "marked new") eq(D.freshCount(p), 1, "one new card")
eq(#toasts, 1, "a toast for a new card") eq(toasts[1].kind, "newcard", "kind newcard") eq(toasts[1].text, "Common One Card", "names the card")
eq(toasts[1].title, "New card", "title")
ok(lastMsg(p):find("went into your Deck of Cards", 1, true) and lastMsg(p):find("locked", 1, true) and lastMsg(p):find("main quest step", 1, true),
	"locked: kept, and where to go: " .. tostring(lastMsg(p)))
eq(p.storage[37000], nil, "nothing turned on") eq(D.unlocked(p), false, "locked")
-- a second copy: counts, no new toast
put(p.backpack, newItem(27482))
M.sweep(p)
eq(D.owned(p, 27482), 2, "the second copy counts") eq(#toasts, 1, "no toast for a copy") eq(D.freshCount(p), 1, "still one new card")
-- locked: a toggle is refused, nothing is lost
eq(M.toggle(p, 27482), false, "locked: refused") ok(lastMsg(p):find("locked", 1, true), "said so") eq(p.storage[37000], nil, "still off")
-- cards looted before the quest are never lost: many, in nested bags
local nest = put(p.backpack, newItem(1987, {}, 20))
local nest2 = put(nest, newItem(1987, {}, 20))
put(nest2, newItem(27483)) put(nest2, newItem(27484)) put(nest, newItem(27485))
M.sweep(p)
eq(D.owned(p, 27483) + D.owned(p, 27484) + D.owned(p, 27485), 3, "cards in nested bags were taken in")
eq(select(1, D.totals(p)), 4, "four different cards") eq(#nest.kids, 1, "only the bag is left")
-- the toast count is capped, the rest in one line
for _, id in ipairs({27486, 27487, 27488, 27489, 27490}) do put(p.backpack, newItem(id)) end
local before = #toasts
M.sweep(p)
eq(#toasts - before, DK.toastMax, "at most toastMax toasts in one sweep")
ok(lastMsg(p):find("5 new cards went into your Deck of Cards", 1, true), "one line for several")
-- the inbox is swept too
local inbox = newItem(2594, {}, 50)
p.getInbox = function() return inbox end
put(inbox, newItem(27491))
M.sweep(p)
eq(D.owned(p, 27491), 1, "a card in the inbox is taken in")

-- the unlock: the main quest step "deck" opens the Deck (data/lib/chaos_mqgate.lua); a stored mark opens it for a character that held a deck
do
	local MQ = dofile("data/scripts/chaos/mainquest_config.lua")
	local mqState, mqStep = MQ.storage.base + MQ.storage.state, MQ.storage.base + MQ.storage.step
	local idx
	for i, st in ipairs(MQ.steps) do if st.key == DK.unlock.step then idx = i end end
	ok(idx ~= nil, "the main quest has the step " .. DK.unlock.step)
	local st = MQ.steps[idx]
	eq(st.conds[1].c, "flag", "the step is done by a flag") eq(st.conds[1].key, "deck", "the flag deck")
	local inFlags, inAcks = false, false
	for _, f in ipairs(MQ.flags) do if f == "deck" then inFlags = true end end
	for _, f in ipairs(MQ.acks) do if f == "deck" then inAcks = true end end
	ok(inFlags and inAcks, "the flag deck is one the quest knows and the Go button marks")
	eq(st.where.m, "game_carddeck", "the step opens the window")
	eq(ChaosMQGate.title("deck", "en"), "Open the Deck of Cards", "the step title") eq(ChaosMQGate.title("deck", "pt-BR"), "Abra o Deck of Cards", "in pt-BR")
	local g = mkPlayer("Gate")
	eq(D.unlocked(g), false, "a character the quest has not seen: locked")
	g.storage[mqState], g.storage[mqStep] = 0, idx
	eq(D.unlocked(g), false, "on the step: locked")
	g.storage[mqStep] = idx + 1
	eq(D.unlocked(g), true, "past the step: open, with nothing stored")
	eq(g.storage[7104400 + 201], nil, "no mark is needed")
	g.storage[mqState] = MQ.states.skipped
	eq(D.unlocked(g), true, "a skipped quest: open") g.storage[mqState] = MQ.states.quiet eq(D.unlocked(g), true, "a quiet character: open")
	g.storage[mqState] = MQ.states.done g.storage[mqStep] = 0
	eq(D.unlocked(g), true, "a finished quest: open")
	local h = mkPlayer("Mark")
	Deck.unlock(h)
	eq(D.unlocked(h), true, "the stored mark opens it")
	-- opening the window emits the flag of the step (the quest's own hook) and sends the state again
	local emitted = {}
	ChaosMainQuest = {emit = function(pl, flag) emitted[#emitted + 1] = flag return true end}
	local before = #h.ext
	TEST_MSG = nil
	registered.ChaosCardsExtended.onExtendedOpcode(h, 173, "open")
	eq(emitted[1], "deck", "the window opened: flag deck") eq(emitted[2], nil, "once")
	ChaosMainQuest = nil
	registered.ChaosCardsExtended.onExtendedOpcode(h, 173, "open")
end

-- turn on and off (unlocked): the rules of five, copies, storage and the legendary flag
local u = mkPlayer("Fay")
Deck.unlock(u)
for _, id in ipairs({27482, 27483, 27484, 27485, 27486, 27487}) do D.add(u, id, 1) end
D.add(u, 27547, 1)
eq(M.toggle(u, 27482), true, "on") eq(u.storage[37000], 1, "storage on")
ok(lastMsg(u):find("You turned on Common One Card", 1, true) and lastMsg(u):find("Reaping Gyre deals Earth damage instead.", 1, true), "on message")
eq(M.toggle(u, 27482), true, "off") eq(u.storage[37000], 0, "storage off") ok(lastMsg(u):find("You turned off Common One Card", 1, true), "off message")
for _, id in ipairs({27482, 27483, 27484, 27485, 27486}) do M.toggle(u, id) end
eq(M.toggle(u, 27487), false, "the sixth is refused") ok(lastMsg(u):find("already have 5 cards on", 1, true), "the limit")
eq(u.storage[37005], nil, "the sixth stays off")
M.toggle(u, 27482)
eq(M.toggle(u, 27487), true, "after an off the sixth turns on") eq(u.storage[37005], 1, "on")
eq(M.toggle(u, 27541), false, "no copy: refused") ok(lastMsg(u):find("no copy of", 1, true), "none text")
eq(M.toggle(u, 2160), false, "not a card")
M.toggle(u, 27483)
eq(M.toggle(u, 27547), true, "a legendary card on") eq(u.storage[37065], 1, "legendary on") eq(u.storage[110017], 1, "the base's first-time flag (110017 + id - 27547)")
-- two copies count once
D.add(u, 27484, 4)
local act = 0
for _, c in pairs(C.cards) do if u.storage[c.storage] == 1 then act = act + 1 end end
eq(act, 5, "five on however many copies")

-- the sweep keeps the storages true: a card with no copy, a locked Deck, six on
local v = mkPlayer("Gus")
Deck.unlock(v)
D.add(v, 27482, 1)
v.storage[37000], v.storage[37001] = 1, 1
M.sweep(v)
eq(v.storage[37000], 1, "owned: stays on") eq(v.storage[37001], 0, "no copy: off") ok(lastMsg(v):find("no longer in your Deck of Cards", 1, true), "told")
v.storage[7104400 + 201] = 0
M.sweep(v)
eq(v.storage[37000], 0, "locked: every card off") ok(lastMsg(v):find("Deck of Cards is locked", 1, true), "told why")

-- migration at login: decks (carried, nested, in the depot), loose cards, the marker, grandfather
local m = mkPlayer("Hal")
local mdeck = put(m.backpack, newItem(27633, {}, 10))
local c1 = put(mdeck, newItem(27482)); c1.aid = 37866
local c2 = put(mdeck, newItem(27547))
local junk = put(mdeck, newItem(2160))
local c1b = put(m.backpack, newItem(27482))
local chest = newItem(2594, {}, 100)
local depotDeck = put(chest, newItem(27632, {}, 5))
put(depotDeck, newItem(27541))
put(chest, newItem(27541))
m.depot = {[1] = chest}
m.getDepotChest = function(self, id) return self.depot[id] end
m.storage[37000] = 1 -- the card was on in the deck
registered.ChaosCardsLogin.onLogin(m)
eq(D.owned(m, 27482), 2, "the deck's card and the loose copy") eq(D.owned(m, 27547), 1, "a legendary card") eq(D.owned(m, 27541), 2, "depot: the deck's card and the loose one")
eq(#mdeck.kids, 0, "the deck is emptied") eq(junk.parent, m.backpack, "a non-card item of a deck goes to the bag")
eq(#m.backpack.kids, 1, "the deck item is removed, the junk stays") eq(#chest.kids, 0, "the depot is empty of decks and cards")
eq(D.unlocked(m), true, "a character that held a deck has the Deck open") eq(m.storage[37000], 1, "its card stays on")
eq(m.storage[7104400 + 203], 2, "two decks found") eq(m.storage[7104400 + 200], DK.migrationVersion, "the marker")
ok(anyMsg(m, "Your decks are gone. 5 cards went into your Deck of Cards, which is open for you"), "told: " .. tostring(m.messages[1]))
-- a second login changes nothing
local copies = select(2, D.totals(m))
local nmsg = #m.messages
put(chest, newItem(27541))
registered.ChaosCardsLogin.onLogin(m)
eq(select(2, D.totals(m)), copies + 0, "the migration runs once: a card put in the depot later is not walked at login")
eq(#chest.kids, 1, "and stays in the depot") eq(#m.messages, nmsg, "no message")
-- no deck: not unlocked
local n = mkPlayer("Ina")
put(n.backpack, newItem(27483))
registered.ChaosCardsLogin.onLogin(n)
eq(D.owned(n, 27483), 1, "loose cards move in at login") eq(D.unlocked(n), false, "no deck held: the quest is still to do")
ok(anyMsg(n, "Your decks are gone. 1 cards went into your Deck of Cards."), "migration text without the open note")
-- a deck found later (picked up from a house floor) is taken in by the sweep, once
local lateDeck = put(n.backpack, newItem(27634, {}, 20))
put(lateDeck, newItem(27484))
M.sweep(n)
eq(D.owned(n, 27484), 1, "a deck picked up later is emptied") eq(#n.backpack.kids, 0, "and removed") eq(D.unlocked(n), true, "and it opens the Deck")
-- a deck item that cannot be emptied stays (no card or item is lost)
local stuck = mkPlayer("Jo")
local sdeck = put(stuck.backpack, newItem(27632, {}, 5))
local sjunk = put(sdeck, newItem(2160))
sjunk.moveTo = function() return false end
M.sweep(stuck)
eq(#stuck.backpack.kids, 1, "a deck whose items cannot move out is kept") eq(sdeck.kids[1], sjunk, "with its item")

-- the window talks: sync sends the list and the state, toggle, seen
local w = mkPlayer("Wim")
Deck.unlock(w)
D.add(w, 27482, 2) D.add(w, 27483, 1)
local ask = registered.ChaosCardsExtended
local function send(pl, msg) TEST_MSG = msg ask.onExtendedOpcode(pl, 173, type(msg) == "table" and "@msg" or msg) end
ChaosOpcodes.cardDeck = ChaosOpcodes.cardDeck
eq(ChaosOpcodes.cardDeck, 173, "the Deck of Cards opcode")
for name, v in pairs(ChaosOpcodes) do ok(name == "cardDeck" or (v ~= 172 and v ~= 173), "opcodes 172 (retired) and 173 are not used by " .. name) end
eq(#w.ext, 0, "nothing sent before")
send(w, "sync")
eq(#w.ext, 2, "sync: the list and the state") eq(w.ext[1].buf.action, "cards", "the list first") eq(#w.ext[1].buf.data.cards, 76, "76 cards")
local st = lastExt(w).buf.data
eq(lastExt(w).op, 173, "opcode") eq(lastExt(w).buf.action, "state", "state") eq(st.unlocked, true, "unlocked") eq(st.distinct, 2, "two different cards")
eq(st.copies, 3, "three copies") eq(#st.new, 2, "both are new") eq(#st.own, 2, "two rows") eq(st.own[1][1], 27482, "first row") eq(st.own[1][2], 2, "two copies")
eq(st.max, 5, "slot rule") eq(#st.on, 0, "none on")
-- toggle through the opcode
send(w, {action = "toggle", id = 27482})
eq(w.storage[37000], 1, "toggle turned it on") eq(table.concat(lastExt(w).buf.data.on, ","), "27482", "the state follows")
local sent = #w.ext
w.limitedNow = true
send(w, {action = "seen", ids = {27482}})
st = lastExt(w).buf.data
eq(#st.new, 1, "one mark cleared") eq(st.new[1], 27483, "the other stays") eq(D.isFresh(w, 27482), false, "seen")
send(w, {action = "seen", all = true})
eq(#lastExt(w).buf.data.new, 0, "all seen") eq(D.freshCount(w), 0, "the badge count is zero")
sent = #w.ext
send(w, {action = "seen", all = true})
eq(#w.ext, sent, "nothing changed: nothing sent")
send(w, {action = "toggle", id = 1})
send(w, {action = "bogus"})
ask.onExtendedOpcode(w, 172, "sync")
eq(#w.ext, sent, "another opcode, action or card is ignored")
-- the periodic sweep sends nothing when nothing changed
M.sweep(w)
registered.ChaosCardsReconcile.onThink(1)
registered.ChaosCardsAbsorb.onThink(1)
eq(#w.ext, sent, "an unchanged state is not sent again")
eq(registered.ChaosCardsReconcile.ms, C.reconcileMs, "the sweep interval") eq(registered.ChaosCardsAbsorb.ms, DK.absorbMs, "the absorb interval")
-- logout forgets the last state
registered.ChaosCardsLogout.onLogout(w)
registered.ChaosCardsLogin.onLogin(w)
eq(#w.ext, sent + 1, "login after logout sends the state")
-- a locked Deck says so in the state
local lk = mkPlayer("Lock")
send(lk, "sync")
eq(lastExt(lk).buf.data.unlocked, false, "locked state") ok(lastExt(lk).buf.data.quest:find("main quest step", 1, true), "with the hint")
-- the card list is in the player's language
Chaos.setLang(lk, "pt-BR")
send(lk, "sync")
local ptList
for _, e in ipairs(lk.ext) do if e.buf.action == "cards" then ptList = e.buf.data end end
ok(ptList.cards[1].x:find("Ativa,", 1, true) ~= nil, "pt-BR card text in the list")
-- a card item that moves into a bag is taken in at once (EventCallback onItemMoved)
do
	local moved = EventCallback.onItemMoved
	ok(type(moved) == "function", "the move callback")
	local mv = mkPlayer("Mov")
	mv.isPlayer = function() return true end
	local it = put(mv.backpack, newItem(27483))
	moved(mv, it, 1, {x = 1, y = 1, z = 7}, {x = 65535, y = 64, z = 0})
	eq(D.owned(mv, 27483), 1, "the moved card is in the Deck") eq(#mv.backpack.kids, 0, "and gone from the bag")
	local gold2 = put(mv.backpack, newItem(2160))
	moved(mv, gold2, 1, {x = 1, y = 1, z = 7}, {x = 65535, y = 64, z = 0})
	eq(#mv.backpack.kids, 1, "other items are left alone")
end
-- the carried scan stops at its limit
local huge = mkPlayer("Huge")
for _ = 1, DK.carriedLimit + 50 do put(huge.backpack, newItem(2160)) end
local _, _, looked = M.collect({huge.backpack}, DK.carriedLimit)
eq(looked, DK.carriedLimit, "the walk ends at its limit")

-- a legendary on card sets the flag once (above); login keeps the state and is silent when nothing changed
do
	local t = mkPlayer("Eve")
	Deck.unlock(t)
	D.add(t, 27482, 1)
	M.toggle(t, 27482)
	registered.ChaosCardsLogin.onLogin(t)
	local nmsgs = #t.messages
	registered.ChaosCardsLogin.onLogin(t)
	eq(t.storage[37000], 1, "login: still on") eq(#t.messages, nmsgs, "login: silent")
end

-- ---------------------------------------------------------------- Character Info
local function status(player, lang)
	if lang then Chaos.setLang(player, lang) end
	local captured
	local saved = player.sendTextMessage
	player.sendTextMessage = function(_, _, text) captured = text end
	ChaosCommands.handlers.deck(player, "")
	player.sendTextMessage = saved
	return captured
end
local text = status(u, "en")
ok(text:find("Deck of Cards: 8 of 76 cards", 1, true) or text:find("Deck of Cards: 7 of 76 cards", 1, true), "deck line: " .. text)
ok(text:find("Cards on (5 of 5):", 1, true), "cards on count: " .. text)
ok(text:find("Reaping Gyre", 1, true) ~= nil, "an on card with its bonus")
ok(#text < C.maxTextBytes, "under the size cap")
local lockedText = status(mkPlayer("Gus2"), "en")
ok(lockedText:find("Deck of Cards is locked", 1, true) and lockedText:find("main quest step", 1, true) and lockedText:find("No card is on.", 1, true),
	"locked: how to open it")
local ptText = status(u, "pt-BR")
ok(ptText:find("Cartas ativas", 1, true) or ptText:find("ativas", 1, true), "pt-BR status: " .. ptText)
local ptLocked = status(mkPlayer("Hal2"), "pt-BR")
ok(ptLocked:find("trancado", 1, true) and ptLocked:find("quest principal", 1, true), "pt-BR locked")


-- ---------------------------------------------------------------- the spells the cards name are current spells
-- (owner 2026-10-23: the cards still named the old stock spells). Sources: spell_names.csv (stock old name, Chaos name,
-- stock words), spells_chaos.xml (the Chaos spells), stock_spells.csv (id, name) and the CAP table of patch_spell_cap.py.
local function slurp(path)
	local fh = assert(io.open(path, "rb"))
	local data = fh:read("*a")
	fh:close()
	return data
end
local oldNames, newNames, oldWords, ids = {}, {}, {}, {}
local first = true
for line in slurp("data/spells/spell_names.csv"):gmatch("[^\r\n]+") do
	if first then
		first = false
	else
		local old, new, words = line:match("^([^,]*),([^,]*),([^,]*)")
		if old and new then
			oldNames[#oldNames + 1] = old
			newNames[new:lower()] = true
			oldWords[#oldWords + 1] = words
		end
	end
end
for spellid, name in slurp("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", ""):gmatch('spellid="(%d+)" name="([^"]+)"') do
	newNames[name:lower()] = true
	ids[name:lower()] = tonumber(spellid)
end
first = true
for line in slurp("data/spells/stock_spells.csv"):gmatch("[^\r\n]+") do
	if first then
		first = false
	else
		local id, name = line:match("^(%d+),([^,]*)")
		if id then
			ids[name:lower()] = tonumber(id)
		end
	end
end
for id, name in slurp("tools/patch_spell_cap.py"):gmatch("%((%d+), '([^']+)', %(") do
	ids[name:lower()] = tonumber(id)
end
local function hasPhrase(text, phrase)
	text, phrase = (" " .. text .. " "):lower():gsub("[%p]", " "), phrase:lower():gsub("[%p]", " ")
	return text:find("%f[%w]" .. phrase:gsub("%s+", "%%s+") .. "%f[%W]") ~= nil
end
ok(#oldNames > 100, "spell_names.csv read")
for _, lang in ipairs({"en", "pt-BR"}) do
	for id, c in pairs(C.cards) do
		local d = K.description(lang, id)
		ok(d:sub(-#"Open the Deck from the menu to turn it on.") == "Open the Deck from the menu to turn it on." or lang ~= "en", "ends with the hint " .. id)
		for _, old in ipairs(oldNames) do
			-- an old stock name is fine only when it is a current name too
			if not newNames[old:lower()] then
				ok(not hasPhrase(d, old), "card " .. id .. " " .. lang .. " names the old spell " .. old)
			end
		end
		for _, w in ipairs(oldWords) do
			if w ~= "" and w:find(" ") then
				ok(not hasPhrase(d, w), "card " .. id .. " " .. lang .. " has the stock words " .. w)
			end
		end
		for _, w in ipairs({"exori", "exevo", "exura", "utito", "exeta", "adori", "avalanche", "sharpshooter"}) do
			ok(not hasPhrase(d, w), "card " .. id .. " " .. lang .. " has the stock word " .. w)
		end
	end
end
for f, fam in ipairs(C.families) do
	ok(newNames[fam.spell:lower()], "line " .. f .. ": " .. fam.spell .. " is a current spell")
	if fam.spell ~= "Frostfall Rune" then
		eq(ids[fam.spell:lower()], fam.id, "line " .. f .. ": the spell id of " .. fam.spell)
	end
	for t = 1, 4 do
		ok(K.description("en", fam.ids[t]):find(fam.spell, 1, true) ~= nil, "description names " .. fam.spell)
	end
end
-- the hint is the install tool's hint (tools/patch_badges.py CARD_HINT)
ok(py:find(K.HINT:sub(1, 60), 1, true) ~= nil and py:find("Open the Deck from the menu to turn it on.", 1, true) ~= nil, "the hint matches the tool")
-- the screenshot of 2026-10-23: the line that named the old spell now names its replacement
ok(not K.description("en", 27482):find("Exori", 1, true), "no stock words")
eq(K.description("en", 27482):find("Reaping Gyre deals Earth damage instead", 1, true) ~= nil, true, "Reaping Gyre line")
-- every retired stock line has a current replacement of the same role, and no line is dead
local hits, live, bow = 0, 0, 0
for _, fam in ipairs(C.families) do
	if fam.how == "hit" then hits = hits + 1 elseif fam.how == "live" then live = live + 1 else bow = bow + 1 end
	ok(fam.how == "hit" or fam.how == "live" or fam.how == "bow", "line kind")
end
eq(hits + live + bow, 15, "15 lines") eq(bow, 1, "one buff line read by Tautstring") eq(hits, 8, "eight lines acted on by cards.lua")

-- ---------------------------------------------------------------- the hit event
COMBAT_PHYSICALDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_FIREDAMAGE = 1, 2, 4, 8
COMBAT_HEALING, COMBAT_ICEDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_DEATHDAMAGE = 256, 512, 1024, 2048
ORIGIN_CONDITION = 1
dofile("data/lib/chaos_supports.lua")
ok(ChaosSupports and ChaosSupports.convert, "supports lib loaded")
local ctxKey = ChaosSupports.config.storageContext
local caster = mkPlayer("Caster")
local mon = {isMonster = function() return true end, getName = function() return "Rat" end,
	getType = function() return {getElementList = function() return {[COMBAT_EARTHDAMAGE] = 0} end} end}
local function setCtx(spell) caster.storage[ctxKey] = 5 * 1000 + spell end
local function turn(id) caster.storage[C.cards[id].storage] = 1 end
-- no card on: untouched
setCtx(220)
local a, b, c2, d = M.applyHit(caster, mon, 220, -100, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(a, -100, "no card on: same hit") eq(b, COMBAT_PHYSICALDAMAGE, "no card on: same type")
-- Reaping Gyre, Minor Earth card on
turn(27482)
a, b, c2, d = M.applyHit(caster, mon, 220, -100, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(a, 0, "the whole hit moved") eq(c2, -100, "into the second part") eq(d, COMBAT_EARTHDAMAGE, "as Earth")
-- the highest tier decides (Powerful: Energy)
turn(27485)
a, b, c2, d = M.applyHit(caster, mon, 220, -100, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(d, COMBAT_ENERGYDAMAGE, "the highest card counts")
-- another spell: untouched; a live line (Tempest Fan) is the base script's business
a, b, c2, d = M.applyHit(caster, mon, 221, -100, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(a, -100, "another spell untouched")
turn(27490)
a = M.applyHit(caster, mon, 13, -100, COMBAT_PHYSICALDAMAGE, 0, 0)
eq(a, -100, "a spell with its stock script is not touched here")
-- Grand Mending: 10% more per the top tier (Intense 30%)
turn(27526) turn(27527) turn(27528)
a, b = M.applyHit(caster, mon, 3, 200, COMBAT_HEALING, 0, 0)
eq(a, 260, "Grand Mending heals 30% more") eq(b, COMBAT_HEALING, "still a heal")
a = M.applyHit(caster, mon, 3, -200, COMBAT_FIREDAMAGE, 0, 0)
eq(a, -200, "damage of a heal spell untouched")
-- the event: needs the cast context, a player attacker, not a condition tick
local ev = registered.ChaosCardsHit
ok(ev and ev.onHealthChange, "the hit event is registered")
local atk = caster
atk.isPlayer = function() return true end
setCtx(220)
a, b, c2, d = ev.onHealthChange(mon, atk, -100, COMBAT_PHYSICALDAMAGE, 0, 0, 2)
eq(d, COMBAT_ENERGYDAMAGE, "the event converts the hit")
a, b, c2, d = ev.onHealthChange(mon, atk, -100, COMBAT_PHYSICALDAMAGE, 0, 0, ORIGIN_CONDITION)
eq(a, -100, "condition ticks untouched")
caster.storage[ctxKey] = -1
a = ev.onHealthChange(mon, atk, -100, COMBAT_PHYSICALDAMAGE, 0, 0, 2)
eq(a, -100, "no cast context: untouched")
a = ev.onHealthChange(mon, nil, -100, COMBAT_PHYSICALDAMAGE, 0, 0, 2)
eq(a, -100, "no attacker: untouched")

-- Tautstring: the line that is on adds seconds and percentage points (the spell script calls buffBonus)
local st = {}
local function sv(key) return st[key] or -1 end
local s0, p0 = C.buffBonus(135, sv)
eq(s0, 0, "no card: no seconds") eq(p0, 0, "no card: no points")
st[C.cards[27540].storage] = 1
local s1, p1 = C.buffBonus(135, sv)
eq(s1, 6, "Intense: 6 seconds") eq(p1, 6, "Intense: 6 points")
st[C.cards[27541].storage] = 1
s1, p1 = C.buffBonus(135, sv)
eq(s1, 8, "Powerful: 8 seconds") eq(p1, 8, "Powerful: 8 points")
eq(C.buffBonus(220, sv), 0, "another spell has no buff bonus")


-- ---------------------------------------------------------------- every card x every class (beta 2026-10-23)
-- "A card I put in my deck does not work at all" (a Ninja): the Thief, Monk, Templar and Necromancer lines had no common
-- card line at all, and the legendary cards asked for a left-hand item id out of four lists of stock ids. This walks the
-- 21 classes (docs/CLASSES.md; cards_config.lua C.classes) against all 76 cards and proves that each card meant for a
-- class can trigger for it.
eq(#C.classes, 21, "21 classes")
do
	local ids21 = Chaos.classes.ids
	local seenVoc = {}
	for _, row in ipairs(C.classes) do
		seenVoc[row.id] = row.name
		ok(Chaos.classes.baseOf[row.id] ~= nil, row.name .. ": a Chaos class id")
		local key = row.name:lower():gsub(" ", "")
		eq(ids21[key], row.id, row.name .. ": the vocation id of Chaos.classes.ids")
		eq(Chaos.classes.baseOf[row.id] == row.id, row.line == row.name, row.name .. ": base class flag")
	end
	local n = 0
	for _ in pairs(seenVoc) do n = n + 1 end
	eq(n, 21, "21 distinct vocation ids")
end

-- which classes cast a spell: the CAP table of patch_spell_cap.py (non-empty = the vocations it keeps), else the Chaos
-- spell file, else stock_spells.csv. The Frostfall Rune is a rune item every class may use.
local vocOf = {}
do
	local xml = slurp("data/spells/chaos/spells_chaos.xml"):gsub("<!%-%-.-%-%->", "")
	for block in xml:gmatch("<instant(.-)</instant>") do
		local id = tonumber(block:match('spellid="(%d+)"'))
		if id then
			local set = {}
			for v in block:gmatch('<vocation name="([^"]+)"') do set[v] = true end
			vocOf[id] = set
		end
	end
	local firstLine = true
	for line in slurp("data/spells/stock_spells.csv"):gmatch("[^\r\n]+") do
		if firstLine then
			firstLine = false
		else
			local id, voc = line:match("^(%d+),.*,([^,]*)$")
			if id and not vocOf[tonumber(id)] then
				local set = {}
				for v in voc:gmatch("[^;]+") do set[v] = true end
				vocOf[tonumber(id)] = set
			end
		end
	end
	for id, _, tuple in slurp("tools/patch_spell_cap.py"):gmatch("%((%d+), '([^']+)', (%b())") do
		local set, any = {}, false
		for v in tuple:gmatch("'([^']+)'") do set[v] = true any = true end
		if any then vocOf[tonumber(id)] = set end
	end
end
local function casts(class, spellId)
	if spellId == 115 then return true end
	local set = vocOf[spellId]
	return set ~= nil and set[class.name] == true
end

-- every line has a spell some class can cast; a spell a line adds belongs to a whole class line (all three ascensions)
local lineClasses = {}
for f, fam in ipairs(C.families) do
	local classes = {}
	for _, row in ipairs(C.classes) do
		for _, sp in ipairs(fam.spells) do
			if casts(row, sp[2]) then classes[row.name] = true end
		end
	end
	lineClasses[f] = classes
	ok(next(classes) ~= nil, "line " .. f .. " (" .. fam.spell .. "): some class casts it")
	for _, sp in ipairs(fam.also or {}) do
		local line
		for _, row in ipairs(C.classes) do
			if casts(row, sp[2]) then
				line = line or row.line
				eq(row.line, line, sp[1] .. ": one class line only")
			end
		end
		ok(line ~= nil, sp[1] .. ": cast by a class")
		-- the whole class line casts it, except a spell of the Mystic line that only some ascensions have (O149)
		for _, row in ipairs(C.classes) do
			if row.line == line and not (line == "Mystic" and sp[2] == 228) then
				ok(casts(row, sp[2]), sp[1] .. " is cast by " .. row.name)
			end
		end
		ok(newNames[sp[1]:lower()] and ids[sp[1]:lower()] == sp[2], sp[1] .. " is a current spell with id " .. sp[2])
		for t = 1, 4 do
			ok(K.description("en", fam.ids[t]):find(sp[1], 1, true) ~= nil, "description names " .. sp[1])
		end
	end
end

-- every class has at least one common line (and the table is printed by `luajit tests/cards_test.lua --table`)
local rows, counts = {}, {}
local MIN_LINES = 3 -- the median class had 3 lines before O149; no class stays below it
for _, row in ipairs(C.classes) do
	local lines = {}
	for f, fam in ipairs(C.families) do
		if lineClasses[f][row.name] then lines[#lines + 1] = fam.spell end
	end
	ok(#lines >= 1, row.name .. ": at least one common card line (" .. #lines .. ")")
	counts[#counts + 1] = #lines
	ok(#lines >= MIN_LINES, row.name .. ": at least " .. MIN_LINES .. " usable common lines, the median (" .. #lines .. ")")
	if row.line == "Necromancer" then ok(#lines >= 4, row.name .. ": 4 lines like the martial lines (" .. #lines .. ")") end
	rows[#rows + 1] = row.name .. ": " .. table.concat(lines, ", ")
end
table.sort(counts)
ok(counts[11] >= MIN_LINES, "the median class has at least " .. MIN_LINES .. " lines (" .. counts[11] .. ")")
if arg and arg[1] == "--table" then print(table.concat(rows, "\n")) end

-- every common card triggers: a hit line moves a physical hit to the card's element (or heals more) for every spell of
-- the line; a line with its stock script reads the card's storage (the storage is the base's, 37000 + id - 27482);
-- the bow line is read by buffBonus. Run through the real hit function with the cast context of that spell.
do
	local tester = mkPlayer("Matrix")
	local mon2 = {isMonster = function() return true end, getName = function() return "Rat" end,
		getType = function() return {getElementList = function() return {} end} end}
	local elementConst = {Fire = COMBAT_FIREDAMAGE, Earth = COMBAT_EARTHDAMAGE, Ice = COMBAT_ICEDAMAGE, Holy = COMBAT_HOLYDAMAGE,
		Death = COMBAT_DEATHDAMAGE, Energy = COMBAT_ENERGYDAMAGE}
	elementConst.Drown = rawget(_G, "COMBAT_DROWNDAMAGE")
	COMBAT_DROWNDAMAGE = COMBAT_DROWNDAMAGE or 4096
	elementConst.Drown = COMBAT_DROWNDAMAGE
	local fired, total = 0, 0
	for id, c in pairs(C.cards) do
		if not c.legendary then
			total = total + 1
			eq(c.storage, 37000 + (id - 27482), "card " .. id .. " keeps the base storage")
			for k in pairs(tester.storage) do tester.storage[k] = nil end
			tester.storage[c.storage] = 1
			if c.how == "hit" then
				for _, sp in ipairs(c.spells) do
					local pd, pt, sd, st
					if c.kind == "heal" then
						pd, pt, sd, st = M.applyHit(tester, mon2, sp[2], 200, COMBAT_HEALING, 0, 0)
						ok(pd > 200 and pt == COMBAT_HEALING, "card " .. id .. " heals more on " .. sp[1])
					else
						pd, pt, sd, st = M.applyHit(tester, mon2, sp[2], -100, COMBAT_PHYSICALDAMAGE, 0, 0)
						ok(elementConst[c.element] ~= nil and (st == elementConst[c.element] or pt == elementConst[c.element]),
							"card " .. id .. " (" .. c.element .. ") converts the hit of " .. sp[1])
					end
					fired = fired + 1
				end
			elseif c.how == "bow" then
				local secs = C.buffBonus(c.spellId, function(key) return tester.storage[key] or -1 end)
				ok(secs > 0, "card " .. id .. " lengthens " .. c.spell)
				fired = fired + 1
			else
				ok(c.how == "live", "card " .. id .. " is a stock-script line")
				ok(vocOf[c.spellId] ~= nil or c.spellId == 115, "card " .. id .. ": the stock spell " .. c.spell .. " has vocations")
				fired = fired + 1
			end
		end
	end
	eq(total, 60, "60 common cards walked") ok(fired >= 60, "every common card fired")
end

-- legendary cards: the weapon. A mocked engine with weapon types; real fist weapon ids from data/lib.
WEAPON_NONE, WEAPON_SWORD, WEAPON_CLUB, WEAPON_AXE, WEAPON_SHIELD, WEAPON_DISTANCE, WEAPON_WAND, WEAPON_AMMO =
	0, 1, 2, 3, 4, 5, 6, 7
CONST_SLOT_RIGHT, CONST_SLOT_LEFT = 5, 6
dofile("data/lib/chaos_fist_weapons.lua")
local wtypes = {[2379] = WEAPON_SWORD, [40100] = WEAPON_SWORD, [40101] = WEAPON_CLUB, [40102] = WEAPON_AXE,
	[40103] = WEAPON_DISTANCE, [40104] = WEAPON_WAND, [40105] = WEAPON_SHIELD, [40106] = WEAPON_AMMO,
	[2408] = WEAPON_SWORD, [27197] = WEAPON_WAND}
for fid in pairs(ChaosFistWeapons.items) do wtypes[fid] = WEAPON_SHIELD end
local plainItemType = ItemType
function ItemType(id)
	local t = plainItemType(id)
	t.getWeaponType = function() return wtypes[id] or WEAPON_NONE end
	return t
end
local function weaponItem(id) local it = newItem(id) it.itemid = id return it end
local sample = {sword = 40100, club = 40101, axe = 40102, distance = 40103, wand = 40104}
local function fistId() for fid in pairs(ChaosFistWeapons.items) do return fid end end
local function equip(p, weapon)
	p.slots[CONST_SLOT_LEFT], p.slots[CONST_SLOT_RIGHT] = nil, nil
	local left
	if weapon == "fist" then
		p.slots[CONST_SLOT_RIGHT] = weaponItem(fistId())
	elseif weapon ~= "none" then
		left = weaponItem(sample[weapon])
		p.slots[CONST_SLOT_LEFT] = left
	end
	return left
end
local legendaryClasses = {"Sorcerer", "Druid", "Paladin", "Knight"}
local covered = {}
for _, row in ipairs(C.classes) do
	local p = mkPlayer("L" .. row.name)
	p.getVocation = function() return {getId = function() return row.id end} end
	local firesAny = false
	for _, weapon in ipairs(row.weapons) do
		local left = equip(p, weapon)
		local expect = K.legendaryFor(row, weapon)
		ok(#expect > 0, row.name .. " with " .. weapon .. ": a legendary card fires")
		for id, c in pairs(C.cards) do
			if c.legendary then
				local want = false
				for _, e in ipairs(expect) do if e == id then want = true end end
				eq(M.holds(p, c.class, left, nil), want, row.name .. "/" .. weapon .. ": card " .. id .. " (" .. c.class .. ")")
				if want then covered[id] = true firesAny = true end
			end
		end
	end
	ok(firesAny, row.name .. ": some legendary card can fire")
end
for id, c in pairs(C.cards) do
	if c.legendary then ok(covered[id], "legendary card " .. id .. " (" .. c.class .. ") can fire for some class") end
end
-- the classes the cards are for (by weapon): melee for the Knight cards, bow for the Paladin cards, wand or rod for both mage cards
do
	local melee = {Warrior = 1, Juggernaut = 1, Berserker = 1, Thief = 1, Ninja = 1, Samurai = 1, Monk = 1, Shadowfist = 1,
		["Iron Sage"] = 1, Templar = 1, Inquisitor = 1, Sentinel = 1}
	local p = mkPlayer("Spare")
	p.getVocation = function() return {getId = function() return 4 end} end
	for _, row in ipairs(C.classes) do
		local knight = false
		for _, w in ipairs(row.weapons) do
			for _, id in ipairs(K.legendaryFor(row, w)) do if C.cards[id].class == "Knight" then knight = true end end
		end
		eq(knight, melee[row.name] == 1, row.name .. ": the Knight cards fire exactly for the melee classes")
	end
end
-- a Chaos weapon (an id the base lists never had), a Ninja's dagger, a stock id with an unknown type, a shield, ammunition
do
	local p = mkPlayer("Ninja")
	p.getVocation = function() return {getId = function() return 12 end} end
	local dagger = equip(p, "sword")
	ok(M.holds(p, "Knight", dagger, nil), "a Chaos dagger (not in the base lists) fires the Knight card")
	ok(not M.holds(p, "Paladin", dagger, nil) and not M.holds(p, "Sorcerer", dagger, nil), "a dagger is not a bow or a wand")
	local stock = weaponItem(7777)
	ok(M.holds(p, "Knight", stock, {1, 7777}), "a stock id of the base list still fires")
	ok(not M.holds(p, "Knight", stock, {1}), "an unknown item does not")
	ok(not M.holds(p, "Knight", weaponItem(40105), nil), "a shield in the left hand does not")
	ok(not M.holds(p, "Knight", weaponItem(40106), nil), "ammunition does not")
	ok(not M.holds(p, "Knight", nil, {1}), "empty hands do not (not the Monk line)")
	local monk = mkPlayer("Monk")
	monk.getVocation = function() return {getId = function() return 18 end} end
	ok(M.holds(monk, "Knight", nil, {1}), "empty hands fire the Knight card for the Monk line")
	ok(not M.holds(monk, "Paladin", nil, {1}), "but never the bow card")
	local rod = weaponItem(27197)
	ok(M.holds(p, "Druid", rod, nil) and M.holds(p, "Sorcerer", rod, nil), "a rod or a wand fires either mage card")
end

-- the summon lock the base never released: a summon that died leaves no lock
do
	DeckSystem = {Legendary = {CanCreateSummon = 37090}}
	local p = mkPlayer("Summoner")
	p.summons = {}
	p.getSummons = function(self) return self.summons end
	p.storage[37090] = 1
	p.summons = {{}}
	eq(M.releaseSummon(p), false, "a living summon keeps the lock") eq(p.storage[37090], 1, "still locked")
	p.summons = {}
	eq(M.releaseSummon(p), true, "no summon: released") eq(p.storage[37090], 0, "unlocked")
	eq(M.releaseSummon(p), false, "nothing to release the second time")
	p.storage[37090] = 1
	registered.ChaosCardsLogin.onLogin(p)
	eq(p.storage[37090], 0, "login clears the lock")
	ok(registered.ChaosCardsSummonRelease and registered.ChaosCardsSummonRelease.onThink, "the release think event")
	eq(registered.ChaosCardsSummonRelease.ms, C.summonReleaseMs, "every few seconds")
	DeckSystem = nil
end

-- the text of a line that acts on several spells
eq(K.bonusText("en", 27502), "While on, Doomtide and Blade Flurry deal Fire damage instead. With several cards of these spells on, the highest one counts.", "two spells")
eq(K.bonusText("pt-BR", 27502), "Ativa, Doomtide e Blade Flurry causam dano de Fogo no lugar. Com várias cartas destas magias ativas, vale a mais alta.", "two spells pt-BR")

-- ---------------------------------------------------------------- card sets (O453)
-- Three cards of one element, one per convert line the class casts, give a small bonus. The rules are cards_core.lua's pure
-- functions (set element of a card, the effective cards of a class, the state, the numbers); the hit is cards.lua's glue.
do
	local S = C.sets
	local names = {Fire = 1, Earth = 1, Death = 1, Holy = 1, Energy = 1}
	-- the config: five sets, one tier, one set at a time with five slots, the damage parts at most 6%
	eq(S.need, 3, "3 cards make a set") eq(S.maxSets, 1, "five slots allow one set of 3")
	ok(S.maxSets * S.need <= C.maxActive, "the sets fit the slots")
	for name in pairs(S.by) do ok(names[name], "a set for " .. name .. " is one of the five") end
	for name in pairs(names) do ok(S.by[name] ~= nil, name .. " has its bonus") end
	ok(S.by.Ice == nil and S.by.Drown == nil, "Ice (no class has three lines) and Drown (one line) have no set")
	eq(#S.order, 5, "five sets in order")
	local kinds = {}
	for _, name in ipairs(S.order) do
		local b = S.by[name]
		ok(b ~= nil, name .. " is in the order")
		ok(not kinds[b.kind], name .. ": each set has its own kind of effect (" .. b.kind .. ")")
		kinds[b.kind] = true
		if b.kind == "damage" or b.kind == "poison" then
			ok(b.pct > 0 and b.pct <= S.damagePartMax, name .. ": the damage part is at most " .. S.damagePartMax .. "%")
		end
	end
	eq(S.damagePartMax, 4, "the cap of a damage part is 4% (O473: the cap of the card set entry of the damage pool)")
	do
		local pc = dofile("data/scripts/chaos/damage_pool_config.lua")
		eq(pc.sources.cardSets.cap, S.damagePartMax, "the pool cap of a card set is the damage part cap")
	end
	-- smaller than the snare of the same element (snares_config.lua)
	local sn = dofile("data/scripts/chaos/snares_config.lua").effects
	ok(S.by.Fire.pct < sn.burnShare * 100, "Fire: smaller than the burn of the snare")
	ok(S.by.Energy.percent < sn.slowPercent * 100 and S.by.Energy.ms < sn.slowMs, "Energy slow: weaker and shorter than the snare's")
	ok(S.by.Earth.pct < sn.poisonShare * 100 and S.by.Earth.ticks <= sn.poisonTicks, "Earth: less poison than the snare")
	ok(S.by.Death.pct < sn.deathLeech * 100, "Death: less leech than the snare")
	ok(S.by.Holy.pct < sn.holyHeal * 100, "Holy: less heal than the snare, and only the owner")
	eq(S.pvpScale, 1 / 3, "PvP: a third, like the unique passives")
	eq(dofile("data/scripts/chaos/unique_passives_config.lua").pvpScale, S.pvpScale, "the same PvP scale as the unique passives")
	local oldMax = C.maxActive
	C.maxActive = 6
	eq(math.floor(C.maxActive / S.need), 2, "with six slots two sets would fit")
	C.maxActive = oldMax

	-- the set element of every card: derived from the convert element, one pure function
	local withEl, noEl, perEl = 0, 0, {}
	for id, c in pairs(C.cards) do
		local el = K.setElement(id)
		if c.kind == "convert" and c.element and S.by[c.element] then
			eq(el, c.element, "card " .. id .. " counts for " .. tostring(c.element))
			withEl = withEl + 1
			perEl[el] = (perEl[el] or 0) + 1
		else
			eq(el, nil, "card " .. id .. " (" .. c.kind .. ", " .. tostring(c.element) .. ") belongs to no set")
			noEl = noEl + 1
		end
		eq(K.setElement(id), K.setElement(tostring(id)), "the id as text gives the same answer")
	end
	eq(withEl + noEl, 76, "every card is told") eq(K.setElement(1), nil, "not a card") eq(K.setElement(nil), nil, "no card")
	-- 44 convert cards: 6 Ice and 1 Drown have no set
	eq(withEl, 44 - 6 - 1, "37 cards have a set element")
	eq(perEl.Fire, 7, "7 Fire cards") eq(perEl.Earth, 6, "6 Earth cards") eq(perEl.Death, 11, "11 Death cards")
	eq(perEl.Holy, 6, "6 Holy cards") eq(perEl.Energy, 7, "7 Energy cards")

	-- the class table of the lines equals what the spell data says
	for f, fam in ipairs(C.families) do
		if fam.kind == "convert" then
			local cfg = {}
			for _, n in ipairs(C.lineClasses[fam.spell] or {}) do cfg[n] = true end
			for n in pairs(lineClasses[f]) do ok(cfg[n], fam.spell .. ": " .. n .. " casts it, the table lists it") end
			for n in pairs(cfg) do ok(lineClasses[f][n], fam.spell .. ": the table lists " .. n .. ", who casts it") end
		else
			ok(C.lineClasses[fam.spell] == nil, fam.spell .. ": no line table for a card with no element")
		end
	end

	local function card(line, tier) return C.families[line].ids[tier] end
	local function elementCard(line, el)
		for t = 1, 4 do if C.families[line].elements[t] == el then return C.families[line].ids[t] end end
	end
	local function lineOf(spell)
		for f, fam in ipairs(C.families) do if fam.spell == spell then return f end end
	end
	local function on(...)
		local set = {}
		for _, id in ipairs({...}) do set[id] = true end
		return function(id) return set[id] == true end
	end
	local gyre, rime = lineOf("Reaping Gyre"), lineOf("Rime Bloom")
	local frost, earthb = lineOf("Frostfall Rune"), lineOf("Earthbreaker")
	local sanct, crypt, doom = lineOf("Sanctum Burst"), lineOf("Frozen Crypt"), lineOf("Doomtide")
	local tempest, pyre = lineOf("Tempest Fan"), lineOf("Pyre Torrent")

	-- reachability: per class and element the lines that carry it (printed by `luajit tests/cards_test.lua --sets`)
	local reach, rows2 = {}, {}
	for _, row in ipairs(C.classes) do
		local list, lines = {}, 0
		for _, el in ipairs(S.order) do
			local n = 0
			for f, fam in ipairs(C.families) do
				if fam.kind == "convert" and K.castsLine(row.name, fam) and elementCard(f, el) then n = n + 1 end
			end
			if n >= S.need then list[#list + 1] = el end
			reach[row.name .. el] = n
		end
		for _, fam in ipairs(C.families) do
			if fam.kind == "convert" and K.castsLine(row.name, fam) then lines = lines + 1 end
		end
		ok(#list >= 1, row.name .. ": a set is reachable")
		ok(K.classNameOf(row.id) == row.name, row.name .. ": the name of the vocation id")
		ok(reach[row.name .. "Death"] >= S.need, row.name .. ": the Death set is reachable")
		eq(lines, row.name == "Elementalist" and 6 or 3, row.name .. ": convert lines")
		rows2[#rows2 + 1] = row.name .. " (" .. lines .. " lines): " .. table.concat(list, ", ")
		eq(reach[row.name .. "Holy"] >= S.need, row.name == "Elementalist", row.name .. ": Holy set only for the Elementalist")
	end
	if arg and arg[1] == "--sets" then print(table.concat(rows2, "\n")) end
	eq(K.classNameOf(99), nil, "no class") eq(K.classNameOf(nil), nil, "no vocation")
	-- the facts the design rests on
	eq(reach.WarriorEarth, 3, "Warrior line: Earth set") eq(reach.WarriorFire, 2, "Warrior line: no Fire set")
	eq(reach.RangerFire, 3, "Ranger line: Fire set") eq(reach.MysticEnergy, 3, "Mystic: Energy set")
	eq(reach.ElementalistHoly, 5, "Elementalist: Holy set") eq(reach.MysticHoly, 2, "the Mystic has two Holy lines")

	-- detection: Warrior (Reaping Gyre, Frostfall Rune, Earthbreaker), Death at tier 3, 4, 4
	local d3, d4, d5 = card(gyre, 3), card(frost, 4), card(earthb, 4)
	eq(C.cards[d3].element, "Death", "Gyre tier 3 is Death") eq(C.cards[d4].element, "Death", "Frostfall tier 4 is Death")
	eq(C.cards[d5].element, "Death", "Earthbreaker tier 4 is Death")
	local st3 = K.setState(on(d3, d4, d5), "Warrior")
	eq(st3.element, "Death", "3 Death cards: the Death set is on") eq(st3.count, 3, "with 3 cards") eq(#st3.active, 1, "one set")
	local st2 = K.setState(on(d3, d4), "Warrior")
	eq(st2.element, nil, "2 cards: no set") eq(#st2.active, 0, "no active set") eq(st2.best.element, "Death", "progress: Death")
	eq(st2.best.count, 2, "2 of 3")
	eq(K.setState(on(), "Warrior").best, nil, "no card: no progress")
	eq(K.setState(on(d3, d4, d5), nil).element, nil, "no class: no set")
	eq(K.setState(on(d3, d4, d5), "Nobody").element, nil, "a name that is no class: no set")
	-- 4 and 5 cards: one tier only (Elementalist, 6 lines)
	local e1, e2, e3, e4, e5 = elementCard(rime, "Death"), elementCard(tempest, "Death"), elementCard(frost, "Death"),
		elementCard(doom, "Death"), elementCard(pyre, "Death")
	local s4 = K.setState(on(e1, e2, e3, e4), "Elementalist")
	local s5 = K.setState(on(e1, e2, e3, e4, e5), "Elementalist")
	eq(s4.element, "Death", "4 cards: on") eq(s5.element, "Death", "5 cards: on") eq(s4.count, 4, "count 4") eq(s5.count, 5, "count 5")
	eq(K.setBonus(s4.element), K.setBonus(s5.element), "the same bonus with 4 and 5 cards: one tier only")
	-- a card of a line the class does not cast does not count (Rime Bloom is not a Warrior spell)
	local rimeDeath = elementCard(rime, "Death")
	eq(K.setState(on(d3, d4, rimeDeath), "Warrior").element, nil, "a card of a spell the class cannot cast counts for nothing")
	eq(K.setState(on(d3, d4, rimeDeath), "Warrior").best.count, 2, "only the two castable cards count")
	-- a card with no element (heal, melee, widen, bow, legendary) counts for no set
	eq(K.setState(on(d3, d4, 27526, 27514, 27538, 27547), "Warrior").element, nil, "cards with no element make no set")
	-- the same line twice: the highest card decides, the lower one counts for nothing ("the element changed by another card")
	local lowEarth = card(frost, 2)
	eq(C.cards[lowEarth].element, "Earth", "Frostfall tier 2 is Earth")
	local stTwice = K.setState(on(d3, d4, d5, lowEarth), "Warrior")
	eq(stTwice.count, 3, "a lower card of Frostfall does not add a card") eq(stTwice.counts.Earth, nil, "and its Earth counts for nothing")
	local stOver = K.setState(on(card(gyre, 1), card(frost, 4), card(frost, 2), d5), "Warrior")
	eq(stOver.counts.Death, 2, "Gyre tier 1 is Earth: Frostfall and Earthbreaker are the two Death cards")
	eq(stOver.counts.Earth, 1, "the Frostfall Earth card is overridden by its tier 4")
	-- a higher card of another element takes the line out of the set
	local gyreEnergy = card(gyre, 4)
	local stHigh = K.setState(on(gyreEnergy, d3, d4, d5), "Warrior")
	eq(stHigh.counts.Death, 2, "Gyre tier 3 and 4 on: tier 4 (Energy) wins, the Death count is 2")
	eq(stHigh.element, nil, "and no set is on")
	-- the Drown card of Tempest Fan has no element: the line counts for nothing
	local drown = card(tempest, 3)
	eq(C.cards[drown].element, "Drown", "Tempest Fan tier 3 is Drown")
	eq(K.setState(on(drown, e1, e3), "Elementalist").counts.Drown, nil, "Drown is no set element")
	-- two sets at once only if the slots allow 6 cards: five slots, one set; with room for two, both
	local fire1, fire2, fire3 = elementCard(rime, "Fire"), elementCard(frost, "Fire"), elementCard(doom, "Fire")
	local both = on(fire1, fire2, fire3, e2, e5, elementCard(crypt, "Death"))
	eq(#K.setState(both, "Elementalist").active, 1, "six cards in two sets: only one set is on (five slots)")
	S.maxSets = 2
	local sBoth2 = K.setState(both, "Elementalist")
	eq(#sBoth2.active, 2, "with room for two sets both are on")
	ok(sBoth2.active[1].element ~= sBoth2.active[2].element, "two elements")
	S.maxSets = 1
	-- the most cards first, then the order
	local sTie = K.setState(on(fire1, fire2, fire3, e2, e5, elementCard(crypt, "Death"), e1), "Elementalist")
	eq(sTie.active[1].element, "Death", "the set with the most cards first")

	-- the keys: a change of the set is news, a plain progress of one card is not
	eq(K.setKey(nil), "", "no state") eq(K.setKey(st3), "on:Death", "a set on") eq(K.setKey(st2), "progress:Death2", "2 cards")
	eq(K.setKey(K.setState(on(d3), "Warrior")), "", "one card is not news")
	-- the texts, every set, both languages
	for _, name in ipairs(S.order) do
		for _, lang in ipairs({"en", "pt-BR"}) do
			local t = K.setBonusText(lang, name)
			ok(#t > 20 and not t:find("%%[sd]"), "set text " .. name .. " " .. lang .. ": " .. t)
		end
	end
	eq(K.setBonusText("en", "Fire"), "Your Fire damage: +3.5% increased damage (a card set adds at most 4 to the one damage pool).", "Fire text")
	eq(K.setBonusText("en", "Energy"), "Your Energy hits slow the target by 15% for 1.5 seconds.", "Energy text")
	eq(K.setBonusText("en", "Earth"), "Your Earth hits poison the target for 4% of the hit over 4 seconds.", "Earth text")
	eq(K.setBonusText("en", "Death"), "Your Death hits heal you for 1.5% of the damage, at most 1% of your maximum health a hit.", "Death text")
	eq(K.setBonusText("en", "Holy"), "Your Holy hits heal you for 0.5% of your maximum health, at most once every 3 seconds.", "Holy text")
	eq(K.setBonusText("pt-BR", "Fire"), "Seu dano de Fogo: +3.5% de dano aumentado (um conjunto de cartas soma no máximo 4 ao conjunto de dano).", "Fire text pt-BR")
	eq(K.setBonusText("en", "Ice"), "", "Ice has no set text")
	eq(K.setLine("en", st3), "Card set Death is on with 3 cards: Your Death hits heal you for 1.5% of the damage, at most 1% of your maximum health a hit.",
		"the line of a set that is on")
	ok(K.setLine("en", st2):find("Card set Death: 2 of 3 cards.", 1, true) ~= nil, "the progress line")
	ok(K.setLine("pt-BR", st2):find("Conjunto de cartas Morte: 2 de 3 cartas.", 1, true) ~= nil, "the progress line in pt-BR: " .. K.setLine("pt-BR", st2))
	ok(K.setLine("en", K.setState(on(), "Warrior")):find("No card set yet.", 1, true) ~= nil, "no card: how to get a set")
	eq(K.setMessage("en", nil, nil), nil, "nothing changed")
	eq(K.setMessage("en", st2, st2), nil, "the same progress")
	ok(K.setMessage("en", st2, st3):find("is on with 3 cards", 1, true) ~= nil, "a set turned on is told")
	eq(K.setMessage("en", st3, st2), "Card set Death is off.", "a set turned off is told")
	ok(K.setMessage("pt-BR", st3, st2):find("desativado", 1, true) ~= nil, "off in pt-BR")
	-- the card texts name the set; the cards with no set element do not
	ok(K.description("en", d3):find("It counts for the Death card set. With 3 cards of one element, one for each spell you cast, you get a bonus.", 1, true) ~= nil,
		"a Death card names its set")
	ok(K.description("en", drown):find("card set", 1, true) == nil, "the Drown card names no set")
	ok(K.description("en", card(sanct, 2)):find("card set", 1, true) == nil, "an Ice card names no set")
	ok(K.description("en", 27526):find("card set", 1, true) == nil, "the heal card names no set")
	ok(K.description("en", 27547):find("card set", 1, true) == nil, "a legendary card names no set")
	ok(K.description("pt-BR", d3):find("conjunto de cartas Morte", 1, true) ~= nil, "pt-BR card text names the set")
	for id in pairs(C.cards) do ok(K.description("en", id):sub(-#K.HINT) == K.HINT, "description ends with the hint " .. id) end

	-- the numbers, pure
	eq(K.setExtra("Fire", "damage", -100, false), -3, "Fire: 3.5% more of a hit of 100 (3, rounded toward zero)") eq(K.setExtra("Fire", "damage", -1000, false), -35, "of 1000")
	eq(K.setExtra("Fire", "damage", 100, false), 3, "the sign is kept") eq(K.setExtra("Fire", "damage", 0, false), 0, "no hit")
	eq(K.setExtra("Fire", "damage", -100, true), -1, "PvP: a third of the bonus")
	eq(K.setExtra("Fire", "damage", -1000, true), -11, "PvP: 11 of 1000 (3.5% / 3, rounded toward zero)")
	eq(K.setExtra("Earth", "damage", -100, false), 0, "another kind has no damage part")
	eq(K.setExtra("Earth", "poison", -100, false), -4, "Earth: poison 4% of the hit") eq(K.setExtra("Death", "damage", -100, false), 0, "Death: no damage part")
	eq(K.setExtra("Ice", "damage", -100, false), 0, "Ice: nothing") eq(K.setExtra("Fire", "poison", -100, false), 0, "Fire has no poison part")
	for _, name in ipairs({"Death", "Holy", "Energy"}) do
		eq(K.setExtra(name, "damage", -100, false) + K.setExtra(name, "poison", -100, false), 0, name .. ": no damage part")
	end
	eq(K.setLeech("Death", 1000, 100000), 15, "Death: 1.5% of 1000") eq(K.setLeech("Death", 1000, 1000), 10, "at most 1% of the maximum health")
	eq(K.setLeech("Death", -5, 1000), 0, "no damage no leech") eq(K.setLeech("Fire", 1000, 100000), 0, "Fire does not leech")
	eq(K.setHeal("Holy", 20000), 100, "Holy: 0.5% of 20000") eq(K.setHeal("Death", 20000), 0, "Death does not heal this way")
	local pct, ms = K.setSlow("Energy", false)
	eq(pct, 0.15, "Energy: 15% slow") eq(ms, 1500, "for 1.5 s") eq(K.setSlow("Energy", true), nil, "no slow on a player")
	eq(K.setSlow("Fire", false), nil, "Fire does not slow")
	eq(K.setScale(true), 1 / 3, "PvP scale") eq(K.setScale(false), 1, "PvE scale")
end

-- the glue: the set follows the cards that are on, the hit event applies it, the player is told (mocked engine)
do
	local S = C.sets
	local function lineOf(spell)
		for f, fam in ipairs(C.families) do if fam.spell == spell then return f end end
	end
	local function elementCard(spell, el)
		local fam = C.families[lineOf(spell)]
		for t = 1, 4 do if fam.elements[t] == el then return fam.ids[t] end end
	end
	-- a player of a class with the Deck of Cards open and holding `ids`, none on yet; the 2nd result is only kept for the old call shape
	local function setPlayer(name, vocId, ids)
		local p = mkPlayer(name)
		p.getVocation = function() return {getId = function() return vocId end} end
		p.isPlayer = function() return true end
		p.health, p.maxHealth = 1000, 20000
		p.getHealth = function(self) return self.health end
		p.getMaxHealth = function(self) return self.maxHealth end
		p.addHealth = function(self, n) self.healed = (self.healed or 0) + n self.health = self.health + n end
		Deck.unlock(p)
		for _, id in ipairs(ids) do D.add(p, id, 1) end
		return p, nil, ids
	end
	local function target(isPlayer)
		local t = {id = 1000 + #players, conditions = {}}
		t.getId = function(self) return self.id end
		t.isPlayer = function() return isPlayer == true end
		t.isMonster = function() return not isPlayer end
		t.addCondition = function(self, c) self.conditions[#self.conditions + 1] = c end
		return t
	end
	local hitEvent = registered.ChaosCardsHit
	-- O473: the hit event keeps the set's effects; the damage part of the Fire set is an entry of the additive damage pool
	-- (M.poolRaw, provider "cardSets"), so hitOf adds it the way ChaosPassiveDealt does: 1 + soft(raw) / 100 on a damage part
	local function hitOf(p, t, pd, pt, sd, st, origin)
		pd, pt, sd, st = hitEvent.onHealthChange(t, p, pd, pt, sd, st or 0, origin or 2)
		local function part(d, ty)
			if not d or d >= 0 or not ty then
				return d
			end
			local raw = M.poolRaw(p, t, ty, origin or 2)
			if raw <= 0 then
				return d
			end
			local _, sum = ChaosDamagePool.combine({cardSets = raw}, 0, ty)
			return -math.floor(-d * ChaosDamagePool.factor(sum) + 1e-6)
		end
		return part(pd, pt), pt, part(sd, st), st
	end

	-- Ranger line (vocation 3): the Fire set is Sanctum Burst, Frostfall Rune and Dawnpiercer at tier 1
	local f1, f2, f3 = elementCard("Sanctum Burst", "Fire"), elementCard("Frostfall Rune", "Fire"), elementCard("Dawnpiercer", "Fire")
	local ranger, deck, it = setPlayer("Rae", 3, {f1, f2, f3})
	local mon = target(false)
	local a, b = hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0)
	eq(a, -100, "no card on: a Fire hit is untouched")
	M.toggle(ranger, it[1])
	ok(lastMsg(ranger):find("You turned on", 1, true) ~= nil, "one card: no set message, only the card's own")
	M.toggle(ranger, it[2])
	ok(lastMsg(ranger):find("Card set Fire: 2 of 3 cards.", 1, true) ~= nil, "two cards: the progress is told: " .. lastMsg(ranger))
	a = hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0)
	eq(a, -100, "2 cards: no bonus")
	M.toggle(ranger, it[3])
	ok(lastMsg(ranger):find("Card set Fire is on with 3 cards: Your Fire damage: +3.5% increased damage", 1, true) ~= nil, "three cards: the set is on: " .. lastMsg(ranger))
	eq(M.sets[ranger:getId()].element, "Fire", "the cache says Fire")
	-- the hit: the primary part, the secondary part, never another element
	a, b = hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0)
	eq(a, -103, "Fire: 3.5% more (primary)") eq(b, COMBAT_FIREDAMAGE, "the type is kept")
	local c, d
	a, b, c, d = hitOf(ranger, mon, 0, COMBAT_PHYSICALDAMAGE, -200, COMBAT_FIREDAMAGE)
	eq(c, -207, "Fire: 3.5% more (secondary part)") eq(a, 0, "the primary part stays")
	a, b, c, d = hitOf(ranger, mon, -100, COMBAT_PHYSICALDAMAGE, -100, COMBAT_FIREDAMAGE)
	eq(a, -100, "the physical part is untouched") eq(c, -103, "only the Fire part grows")
	for name, ctype in pairs({Earth = COMBAT_EARTHDAMAGE, Ice = COMBAT_ICEDAMAGE, Holy = COMBAT_HOLYDAMAGE, Death = COMBAT_DEATHDAMAGE,
			Energy = COMBAT_ENERGYDAMAGE, Physical = COMBAT_PHYSICALDAMAGE}) do
		eq((hitOf(ranger, mon, -100, ctype, 0, 0)), -100, name .. " damage is never changed by the Fire set")
	end
	eq((hitOf(ranger, mon, 100, COMBAT_FIREDAMAGE, 0, 0)), 100, "a positive amount (a heal) is untouched")
	eq((hitOf(ranger, mon, -100, COMBAT_HEALING, 0, 0)), -100, "a healing type is untouched")
	eq((hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0, ORIGIN_CONDITION)), -100, "a damage over time tick is untouched")
	eq((hitOf(ranger, target(true), -1000, COMBAT_FIREDAMAGE, 0, 0)), -1011, "PvP: a third of the bonus (11 of 1000)")
	eq((ranger.getId and hitEvent.onHealthChange(ranger, ranger, -100, COMBAT_FIREDAMAGE, 0, 0, 2)), -100, "a hit on yourself is untouched")
	eq((hitEvent.onHealthChange(mon, nil, -100, COMBAT_FIREDAMAGE, 0, 0, 2)), -100, "no attacker: untouched")
	-- another player has no set
	local other = setPlayer("Oz", 3, {f1})
	eq((hitOf(other, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "a player with no set: untouched")
	-- the convert card and the set together: Dawnpiercer turns a physical hit into Fire (the secondary part), then +4%
	ranger.storage[ctxKey] = 5 * 1000 + 214
	a, b, c, d = hitOf(ranger, mon, -100, COMBAT_PHYSICALDAMAGE, 0, 0)
	eq(a, 0, "Dawnpiercer: the hit moved") eq(c, -103, "to Fire, and 3.5% more") eq(d, COMBAT_FIREDAMAGE, "as Fire")
	ranger.storage[ctxKey] = -1

	-- swapping a card: off turns the set off at once and says so; on again turns it on
	M.toggle(ranger, it[3])
	ok(lastMsg(ranger):find("Card set Fire: 2 of 3 cards.", 1, true) ~= nil or lastMsg(ranger):find("Card set Fire is off.", 1, true) ~= nil,
		"a card off: the set is off: " .. lastMsg(ranger))
	eq(M.sets[ranger:getId()].element, nil, "no set after the card went off")
	eq((hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "the bonus is gone with the card")
	M.toggle(ranger, it[3])
	eq((hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -103, "the bonus is back with the card")
	-- the same card twice: a second copy goes into the Deck and counts once, the count of cards stays 3
	local copy = put(ranger.backpack, newItem(f1))
	M.use(ranger, copy)
	eq(D.owned(ranger, f1), 2, "a second copy is in the Deck")
	eq(M.sets[ranger:getId()].count, 3, "a second copy of a card does not make a fourth card")
	-- a card of the line with a higher tier of another element replaces it ("the element changed by another card")
	local ice = elementCard("Sanctum Burst", "Ice")
	D.add(ranger, ice, 1)
	M.toggle(ranger, ice)
	eq(M.sets[ranger:getId()].counts.Fire, 2, "Sanctum Burst Ice (tier 2) replaces its Fire card: 2 Fire cards")
	eq((hitOf(ranger, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "no bonus when another card changed the element")
	M.toggle(ranger, ice)
	eq(M.sets[ranger:getId()].counts.Fire, 3, "the Ice card off: Fire is back")
	-- cards in the Deck but off, or loose: no set
	local q, _, qit = setPlayer("Quin", 3, {f1, f2, f3})
	M.toggle(q, qit[1]) M.toggle(q, qit[2])
	eq(M.sets[q:getId()].count, nil, "two cards on: no set")
	eq((hitOf(q, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "the third card is in the Deck, off: no bonus")
	local looseCard = put(q.backpack, newItem(f3))
	M.sweep(q)
	eq((hitOf(q, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "a loose card went into the Deck, off: no bonus")
	-- a card that lost its last copy: the sweep turns it off and the bonus goes
	M.toggle(q, qit[3])
	eq((hitOf(q, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -103, "three cards on: the bonus")
	D.setOwned(q, qit[3], 0)
	M.sweep(q)
	eq(M.sets[q:getId()].element, nil, "no copy left: the set is off after the sweep")
	eq((hitOf(q, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "no bonus without the card")
	-- the Character Info line
	local info = status(ranger, "en")
	ok(info:find("Card set Fire is on with 3 cards:", 1, true) ~= nil, "Character Info names the set: " .. info)
	ok(status(q, "en"):find("Card set Fire: 2 of 3 cards.", 1, true) ~= nil, "Character Info shows the progress")
	ok(status(mkPlayer("Nod"), "en"):find("No card set", 1, true) == nil, "a player with no class gets no set line")
	ok(status(ranger, "pt-BR"):find("Conjunto de cartas Fogo ativo com 3 cartas:", 1, true) ~= nil, "pt-BR Character Info")
	-- logout forgets the cache
	registered.ChaosCardsLogout.onLogout(ranger)
	eq(M.sets[ranger:getId()], nil, "logout clears the set")
	-- login computes it again
	registered.ChaosCardsLogin.onLogin(ranger)
	eq(M.sets[ranger:getId()].element, "Fire", "login: the set is back")

	-- Death leech (Warrior line, vocation 4): Gyre tier 3, Frostfall tier 4, Earthbreaker tier 4
	local w, _, wit = setPlayer("Wil", 4, {elementCard("Reaping Gyre", "Death"), elementCard("Frostfall Rune", "Death"),
		elementCard("Earthbreaker", "Death")})
	for _, item in ipairs(wit) do M.toggle(w, item) end
	eq(M.sets[w:getId()].element, "Death", "the Warrior's Death set")
	w.healed = nil
	local pd = hitOf(w, mon, -1000, COMBAT_DEATHDAMAGE, 0, 0)
	eq(pd, -1000, "Death: the hit itself is not changed") eq(w.healed, 15, "Death: 1.5% of the damage dealt healed")
	w.healed = nil
	hitOf(w, mon, -1000, COMBAT_FIREDAMAGE, 0, 0)
	eq(w.healed, nil, "a Fire hit does not leech")
	w.maxHealth = 1000
	hitOf(w, mon, -100000, COMBAT_DEATHDAMAGE, 0, 0)
	eq(w.healed, 10, "the leech stops at 1% of the maximum health")
	w.health = 0
	w.healed = nil
	hitOf(w, mon, -1000, COMBAT_DEATHDAMAGE, 0, 0)
	eq(w.healed, nil, "a dead player is not healed")

	-- Earth poison (Warrior line): Gyre tier 1, Frostfall tier 2, Earthbreaker tier 2
	local ep, _, epit = setPlayer("Eve", 4, {elementCard("Reaping Gyre", "Earth"), elementCard("Frostfall Rune", "Earth"),
		elementCard("Earthbreaker", "Earth")})
	for _, item in ipairs(epit) do M.toggle(ep, item) end
	eq(M.sets[ep:getId()].element, "Earth", "the Warrior's Earth set")
	local conds = {}
	Condition = function(kind)
		local cnd = {kind = kind, params = {}}
		function cnd:setParameter(k, v) self.params[k] = v end
		function cnd:addDamage(n, every, per) self.ticks, self.every, self.per = n, every, per end
		conds[#conds + 1] = cnd
		return cnd
	end
	CONDITION_POISON, CONDITION_PARAM_OWNER, CONDITION_PARAM_DELAYED = 3, 1, 2
	local pm = target(false)
	eq((hitOf(ep, pm, -1000, COMBAT_EARTHDAMAGE, 0, 0)), -1000, "Earth: the hit itself is not changed")
	eq(#pm.conditions, 1, "Earth: one poison on the target") eq(conds[1].ticks, 4, "over 4 seconds") eq(conds[1].every, 1000, "a tick a second")
	eq(conds[1].per, -10, "4% of 1000 over 4 ticks: 10 a tick") eq(conds[1].params[1], ep:getId(), "owned by the player")
	hitOf(ep, pm, -1000, COMBAT_FIREDAMAGE, 0, 0)
	eq(#pm.conditions, 1, "a Fire hit does not poison")
	hitOf(ep, pm, -1000, COMBAT_EARTHDAMAGE, 0, 0, ORIGIN_CONDITION)
	eq(#pm.conditions, 1, "a poison tick does not poison again")
	local pp = target(true)
	hitOf(ep, pp, -1000, COMBAT_EARTHDAMAGE, 0, 0)
	eq(conds[#conds].per, -3, "PvP: a third of the poison (3 a tick, rounded down)")
	Condition = nil

	-- Energy slow (Mystic, vocation 1): Rime Bloom tier 4, Frostfall Rune tier 3, Frozen Crypt tier 4
	local sl = {}
	ChaosSpell = {slow = function(t, ms, pct) sl[#sl + 1] = {t = t, ms = ms, pct = pct} end}
	local my, _, myit = setPlayer("Mia", 1, {elementCard("Rime Bloom", "Energy"), elementCard("Frostfall Rune", "Energy"),
		elementCard("Frozen Crypt", "Energy")})
	for _, item in ipairs(myit) do M.toggle(my, item) end
	eq(M.sets[my:getId()].element, "Energy", "the Mystic's Energy set")
	eq((hitOf(my, mon, -1000, COMBAT_ENERGYDAMAGE, 0, 0)), -1000, "Energy: the hit itself is not changed")
	eq(#sl, 1, "Energy: the target is slowed") eq(sl[1].ms, 1500, "for 1.5 s") eq(sl[1].pct, 0.15, "by 15%")
	hitOf(my, mon, -1000, COMBAT_FIREDAMAGE, 0, 0)
	eq(#sl, 1, "a Fire hit does not slow")
	hitOf(my, target(true), -1000, COMBAT_ENERGYDAMAGE, 0, 0)
	eq(#sl, 1, "no slow on a player")
	ChaosSpell = nil

	-- Holy heal (Elementalist, vocation 5): Rime Bloom, Tempest Fan, Doomtide at their Holy tier
	local el, _, elit = setPlayer("Eli", 5, {elementCard("Rime Bloom", "Holy"), elementCard("Tempest Fan", "Holy"),
		elementCard("Doomtide", "Holy")})
	for _, item in ipairs(elit) do M.toggle(el, item) end
	eq(M.sets[el:getId()].element, "Holy", "the Elementalist's Holy set")
	local clock = 100000
	local realMtime = os.mtime
	os.mtime = function() return clock end
	hitOf(el, mon, -1000, COMBAT_HOLYDAMAGE, 0, 0)
	eq(el.healed, 100, "Holy: 0.5% of the maximum health")
	hitOf(el, mon, -1000, COMBAT_HOLYDAMAGE, 0, 0)
	eq(el.healed, 100, "once every 3 seconds: the second hit heals nothing")
	clock = clock + 3000
	hitOf(el, mon, -1000, COMBAT_HOLYDAMAGE, 0, 0)
	eq(el.healed, 200, "3 seconds later: it heals again")
	os.mtime = realMtime

	-- the set cache of a class with no vocation id (a test player): no set, no error
	local nv = mkPlayer("Nvi")
	nv.isPlayer = function() return true end
	Deck.unlock(nv)
	D.add(nv, f1, 1)
	M.toggle(nv, f1)
	eq(M.sets[nv:getId()], nil, "no vocation: no set state")
	eq((hitOf(nv, mon, -100, COMBAT_FIREDAMAGE, 0, 0)), -100, "no vocation: no bonus")
	-- the event stays registered once, on the monsters a player attacks (the set needs no other event)
	ok(registered.ChaosCardsHit and registered.ChaosCardsHit.onHealthChange, "the one hit event carries the set")
end

print(string.format("cards_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
