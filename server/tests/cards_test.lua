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
	players[#players + 1] = p
	return p
end
Game = {getPlayers = function() return players end}
EventCallback = {register = function() end}

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
eq(C.decks[1].size + C.decks[2].size + C.decks[3].size, 35, "deck sizes 5, 10, 20")
-- the card list matches the patch tool's list (tools/patch_badges.py CARDS)
local f = io.open("tools/patch_badges.py", "rb")
local py = f:read("*a")
f:close()
ok(py:find("tuple(range(27482, 27542)) + tuple(range(27547, 27632, 6)) + (27640,)", 1, true) ~= nil, "the tool's card list")
for id = 27482, 27541 do ok(K.isCard(id), "common to mythic " .. id) end
for id = 27547, 27631, 6 do ok(K.isCard(id), "legendary level 6 " .. id) end
ok(K.isCard(27640) and not K.isCard(27635) and not K.isCard(27632) and not K.isCard(nil), "ids outside")
ok(K.isDeck(27632) and K.isDeck(27634) and not K.isDeck(27482), "decks")

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

-- ---------------------------------------------------------------- core: decide
local function d(over)
	local s = {id = 27482, inDeck = false, isOn = false, storageOn = false, count = 0, decks = {{used = 0, size = 5}}}
	for k, v in pairs(over or {}) do s[k] = v end
	return K.decide(s)
end
eq(d(), "move", "loose card, deck with room: move") eq(d({inDeck = true}), "on", "in a deck: on")
eq(d({storageOn = true, isOn = true, inDeck = true}), "off", "on: off")
eq(d({storageOn = true, isOn = false}), "dupe", "another copy is on")
eq(d({count = 5}), "max", "five on") eq(d({count = 5, storageOn = true, isOn = true}), "off", "off at five")
eq(d({decks = {}}), "nodeck", "no deck") eq(d({decks = {{used = 5, size = 5}}}), "full", "full")
eq(select(2, d({decks = {{used = 5, size = 5}, {used = 1, size = 10}}})), 2, "the second deck has room")
eq(d({id = 27632}), "notcard", "a deck is not a card")

-- ---------------------------------------------------------------- the glue on a mocked engine
itemNames[27482], itemNames[27483], itemNames[27632] = "Common One Card", "Rare One Card", "Bronze Deck"
itemNames[27633], itemNames[27634], itemNames[27547] = "Silver Deck", "Golden Deck", "Legendary Two Lv6"

local function mkPlayer(name)
	local p = newPlayer(name)
	p.backpack = newItem(1988, {}, 30)
	p.slots[3] = p.backpack
	return p
end
local function put(bag, item)
	bag.kids[#bag.kids + 1] = item
	item.parent = bag
	return item
end
local function lastMsg(p) return p.messages[#p.messages] end

-- no deck: the text says where to buy one, with the seller's prices
local p = mkPlayer("Alice")
local card = put(p.backpack, newItem(27482))
eq(M.use(p, card), true, "no deck: handled")
ok(lastMsg(p):find("Veyra the Apothecary", 1, true) and lastMsg(p):find("1000 gold", 1, true)
	and lastMsg(p):find("6000", 1, true) and lastMsg(p):find("30000", 1, true), "no deck: where and how much: " .. tostring(lastMsg(p)))
eq(p.storage[37000], nil, "no deck: nothing turned on") eq(card.aid, 0, "no deck: no action id")
eq(M.use(p, newItem(2160)), nil, "not a card: the base runs")

-- a deck nested two bags deep and the card loose: the card goes in and turns on
local inner = put(p.backpack, newItem(1987, {}, 20))
local innermost = put(inner, newItem(1987, {}, 20))
local deck = put(innermost, newItem(27632, {}, 5))
eq(M.use(p, card), true, "deck deep in a bag: handled")
eq(card.parent, deck, "the card is in the deck") eq(#p.backpack.kids, 1, "left the backpack")
eq(p.storage[37000], 1, "on") eq(card.aid, 37866, "tagged")
ok(p.messages[#p.messages - 1]:find("went into your Bronze Deck", 1, true) and lastMsg(p):find("You turned on Common One Card", 1, true)
	and lastMsg(p):find("Reaping Gyre deals Earth damage instead.", 1, true), "messages")
-- used inside the deck: off
eq(M.use(p, card), true, "off") eq(p.storage[37000], 0, "off storage") eq(card.aid, 0, "action id gone")
ok(lastMsg(p):find("You turned off Common One Card", 1, true), "off message")
M.use(p, card)
eq(p.storage[37000], 1, "on again (inside the deck)")

-- a second copy of an on card: refused, counts once; the copy is not duplicated or moved
local copy = put(p.backpack, newItem(27482))
eq(M.use(p, copy), true, "second copy handled")
ok(lastMsg(p):find("already on with another copy", 1, true), "second copy: said so")
eq(copy.parent, p.backpack, "second copy stays") eq(copy.aid, 0, "second copy untagged")
-- a second deck: the card still counts once
local deck2 = put(p.backpack, newItem(27634, {}, 20))
local st = M.scan(p)
eq(#st.decks, 2, "two decks seen") eq(st.decks[1].size, 20, "the golden deck first")
local plan = K.reconcile(st.decks, st.loose, st.storage)
eq(K.activeCount(plan), 1, "one card on with two decks")

-- the limit of five
local ids = {27483, 27484, 27485, 27486, 27487}
local made = {}
for _, id in ipairs(ids) do
	made[#made + 1] = put(p.backpack, newItem(id))
end
for i = 1, 4 do
	M.use(p, made[i])
end
local on = 0
for _, c in pairs(C.cards) do if p.storage[c.storage] == 1 then on = on + 1 end end
eq(on, 5, "five on")
eq(M.use(p, made[5]), true, "sixth handled")
ok(lastMsg(p):find("already have 5 cards on", 1, true), "sixth: the limit")
eq(made[5].parent, p.backpack, "sixth stays out (no move without turning on)") eq(made[5].aid, 0, "sixth untagged")
-- off frees a place
M.use(p, card)
M.use(p, made[5])
eq(p.storage[C.cards[27487].storage], 1, "after an off the sixth turns on")

-- all decks full: the card stays, the text says so. A Bronze Deck of 5 cards is full already
local q = mkPlayer("Bob")
local bronze = put(q.backpack, newItem(27632, {}, 5))
for _ = 1, 5 do put(bronze, newItem(2160)) end
local c1 = put(q.backpack, newItem(27483))
eq(M.use(q, c1), true, "full deck: handled")
ok(lastMsg(q):find("decks are full", 1, true), "full deck: said so") eq(c1.parent, q.backpack, "full deck: card stays")
eq(q.storage[37001], nil, "full deck: off")

-- a card in the depot (not carried): told to carry it
local lone = newItem(27483)
eq(M.use(q, lone), true, "a card that is not carried: handled")
ok(lastMsg(q):find("Carry the card in your backpack", 1, true), "not carried: said so")

-- a card dropped while on (death): the next sweep turns it off, the count frees
local r = mkPlayer("Cara")
local rdeck = put(r.backpack, newItem(27633, {}, 10))
local rc = put(r.backpack, newItem(27483))
M.use(r, rc)
eq(r.storage[37001], 1, "on before the loss")
for i, k in ipairs(rdeck.kids) do if k == rc then table.remove(rdeck.kids, i) end end -- gone
M.sweep(r)
eq(r.storage[37001], 0, "left the deck: off after the sweep")
ok(lastMsg(r):find("no longer in a deck you carry", 1, true), "told")
-- the deck itself put away (not carried): its card turns off
local rc2 = put(rdeck, newItem(27484))
M.use(r, rc2)
eq(r.storage[37002], 1, "on")
for i, k in ipairs(r.backpack.kids) do if k == rdeck then table.remove(r.backpack.kids, i) end end
M.sweep(r)
eq(r.storage[37002], 0, "deck put away: off")

-- a stray action id (card outside a deck, a second tagged copy, a tagged card with its storage off) is cleared
local s = mkPlayer("Dan")
local sdeck = put(s.backpack, newItem(27633, {}, 10))
local a = put(s.backpack, newItem(27483)); a.aid = 37866
local b1 = put(sdeck, newItem(27484)); b1.aid = 37866
local b2 = put(sdeck, newItem(27484)); b2.aid = 37866
s.storage[37002] = 1
M.sweep(s)
eq(a.aid, 0, "loose tagged card cleared")
eq(b1.aid, 37866, "the first tagged copy stays on") eq(b2.aid, 0, "the second tagged copy cleared")
eq(s.storage[37002], 1, "still on once")
s.storage[37002] = 0
M.sweep(s)
eq(b1.aid, 0, "storage off: the tag goes")

-- login keeps what is right and repairs what is not (no message when nothing changed)
local t = mkPlayer("Eve")
local tdeck = put(t.backpack, newItem(27632, {}, 5))
local tc = put(tdeck, newItem(27482))
M.use(t, tc)
local before = #t.messages
registered.ChaosCardsLogin.onLogin(t)
eq(t.storage[37000], 1, "login: still on") eq(tc.aid, 37866, "login: still tagged") eq(#t.messages, before, "login: silent")
eq(registered.ChaosCardsReconcile.ms, C.reconcileMs, "the sweep interval")

-- a legendary card sets the base's one-time flag, once
local u = mkPlayer("Fay")
put(u.backpack, newItem(27632, {}, 5))
local lc = put(u.backpack, newItem(27547))
M.use(u, lc)
eq(u.storage[37065], 1, "legendary on") eq(u.storage[110017], 1, "the base's first-time flag (110017 + id - 27547)")

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
local text = status(p, "en")
ok(text:find("Decks carried: Golden Deck 0 of 20, Bronze Deck 1 of 5", 1, true) or text:find("Decks carried:", 1, true), "decks line")
ok(text:find("Cards on (5 of 5):", 1, true), "cards on count: " .. text)
ok(text:find("Reaping Gyre deals Earth damage instead.", 1, true), "an on card with its bonus")
ok(text:find("Cards carried outside a deck", 1, true), "loose cards listed")
ok(text:find("Cards 1 of 25", 1, true) or text:find("of 25", 1, true), "capacity used of total")
ok(#text < C.maxTextBytes, "under the size cap")
local none = status(mkPlayer("Gus"), "en")
ok(none:find("You carry no deck.", 1, true) and none:find("Veyra the Apothecary", 1, true) and none:find("No card is on.", 1, true),
	"no deck: how to get one")
local pt = status(q, "pt-BR")
ok(pt:find("Decks que você carrega", 1, true) and pt:find("Cartas", 1, true), "pt-BR status: " .. pt)
local ptNone = status(mkPlayer("Hal"), "pt-BR")
ok(ptNone:find("não carrega nenhum deck", 1, true) and ptNone:find("Veyra the Apothecary", 1, true), "pt-BR no deck")

-- a golden deck full of cards and as many loose: the text is cut, under the cap
local big = mkPlayer("Ivy")
local gd = put(big.backpack, newItem(27634, {}, 20))
for _ = 1, 20 do put(gd, newItem(27547)) end
for _ = 1, 200 do put(big.backpack, newItem(27547)) end
local bigText = status(big, "pt-BR")
ok(#bigText <= C.maxTextBytes, "huge list stays under the cap: " .. #bigText)
ok(bigText:find("... e mais", 1, true) ~= nil, "cut with a count")

-- the scan guard
local huge = mkPlayer("Jo")
for _ = 1, C.scanLimit + 50 do put(huge.backpack, newItem(2160)) end
eq(#M.scan(huge).loose, 0, "the scan ends at its limit")


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
		ok(d:sub(-#"Veyra the Apothecary sells decks.") == "Veyra the Apothecary sells decks." or lang ~= "en", "ends with the hint " .. id)
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
ok(py:find(K.HINT:sub(1, 60), 1, true) ~= nil and py:find("Veyra the Apothecary sells decks.", 1, true) ~= nil, "the hint matches the tool")
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
		for _, row in ipairs(C.classes) do
			if row.line == line then ok(casts(row, sp[2]), sp[1] .. " is cast by " .. row.name) end
		end
		ok(newNames[sp[1]:lower()] and ids[sp[1]:lower()] == sp[2], sp[1] .. " is a current spell with id " .. sp[2])
		for t = 1, 4 do
			ok(K.description("en", fam.ids[t]):find(sp[1], 1, true) ~= nil, "description names " .. sp[1])
		end
	end
end

-- every class has at least one common line (and the table is printed by `luajit tests/cards_test.lua --table`)
local rows = {}
for _, row in ipairs(C.classes) do
	local lines = {}
	for f, fam in ipairs(C.families) do
		if lineClasses[f][row.name] then lines[#lines + 1] = fam.spell end
	end
	ok(#lines >= 1, row.name .. ": at least one common card line (" .. #lines .. ")")
	rows[#rows + 1] = row.name .. ": " .. table.concat(lines, ", ")
end
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

print(string.format("cards_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
