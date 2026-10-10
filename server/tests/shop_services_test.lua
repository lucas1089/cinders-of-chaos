-- Run from the server/ folder: luajit tests/shop_services_test.lua (mock engine API; CI runs it)
-- Covers the store services: name validation, world buff stacking and effects, the vocation mapping, stat
-- recomputation, the sell-price lookup, the unlock/service checks (and the store pouch service), the auto seller.
local n = 0
setmetatable(_G, {__index = function(t, k)
  if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

-- ------------------------------------------------------------------ engine mocks
local registry, talk, callbacks = {}, {}, {}
local function obj(store, name)
  local o = {}
  function o:register() if store and name then store[name] = o end end
  function o:separator() end
  function o:type() end
  function o:interval() end
  function o:aid(id) self.aidValue = id end
  return o
end
function CreatureEvent(name) return obj(registry, name) end
function GlobalEvent(name) return obj(registry, name) end
function TalkAction(words) return obj(talk, words) end
function Action() return obj(registry, "action") end
local pendingCb
EventCallback = setmetatable({}, {
  __index = function(_, k)
    if k == "register" then
      return function(_, index) callbacks[#callbacks + 1] = {name = pendingCb[1], fn = pendingCb[2], index = index or 0} end
    end
  end,
  __newindex = function(_, k, v) pendingCb = {k, v} end
})
local function callback(name, index)
  for _, c in ipairs(callbacks) do
    if c.name == name and c.index == index then return c.fn end
  end
end
local global, queries = {}, {}
Game = {
  getStorageValue = function(k) return global[k] end,
  setStorageValue = function(k, v) global[k] = v end,
  getPlayers = function() return {} end,
  broadcastMessage = function(text) Game.lastBroadcast = text end
}
db = {
  query = function(q) queries[#queries + 1] = q; return true end,
  storeQuery = function() return nil end,
  escapeString = function(s) return "'" .. tostring(s) .. "'" end
}
json = {encode = function() return "" end, decode = function() return {} end}

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/autosell.lua")
dofile("data/scripts/chaos/shop_services.lua")
local S = ChaosShopServices

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ------------------------------------------------------------------ name validation
eq(S.validateName("lord of chaos"), "Lord Of Chaos", "capitalised")
eq(S.validateName("  Kael  "), "Kael", "trimmed")
eq(S.validateName("vAlEn"), "Valen", "rest lower case")
eq(S.validateName("Ab"), nil, "too short")
eq(S.validateName("Abcdefghij Klmnopqrst"), nil, "21 characters")
eq(S.validateName("Bob1"), nil, "digits")
eq(S.validateName("Bob's"), nil, "punctuation")
eq(S.validateName("Bob  Smith"), nil, "double space")
eq(S.validateName("GM Bob"), nil, "staff prefix GM")
eq(S.validateName("Tutor Ann"), nil, "staff prefix Tutor")
eq(S.validateName("Bob God"), nil, "staff word anywhere")
eq(S.validateName("Superadmin"), nil, "forbidden substring")
eq(S.validateName("Aaaron"), nil, "triple letter")
eq(S.validateName("A Bcd"), nil, "one-letter word")
eq(S.validateName("Ab Cd Ef Gh"), nil, "four words")
eq(S.validateName("Godric"), "Godric", "staff word only refused as a whole word")
local _, why = S.validateName("GM Bob")
assert(why and why:find("staff"), "reason given")

-- ------------------------------------------------------------------ world buff stacking
local H = 3600
eq(S.stackBuff(1000, 0, H, 3 * H), 1000 + H, "fresh buff")
eq(S.stackBuff(1000, 500, H, 3 * H), 1000 + H, "expired buff starts fresh")
eq(S.stackBuff(1000, 1000 + H, H, 3 * H), 1000 + 2 * H, "extends")
eq(S.stackBuff(1000, 1000 + 2 * H, H, 3 * H), 1000 + 3 * H, "up to the cap exactly")
local none, left = S.stackBuff(1000, 1000 + 2 * H + 1, H, 3 * H)
eq(none, nil, "past the cap refused")
eq(left, 2 * H + 1, "seconds left reported")

-- ------------------------------------------------------------------ vocations
-- every base class has two ascended classes (docs/CLASSES.md): Warrior 4 -> Juggernaut 8 | Berserker 14,
-- Ranger 3 -> Deadeye 7 | Beastmaster 15, Mystic 1 -> Elementalist 5 | Illusionist 10, Thief 11 -> Ninja 12 | Samurai 13
eq(S.vocationFor("juggernaut", 7), 8, "deadeye -> juggernaut")
eq(S.vocationFor("Berserker", 7), 14, "deadeye -> berserker")
eq(S.vocationFor("warrior", 3), 4, "ranger -> warrior")
eq(S.vocationFor("berserker", 3), 4, "an unascended character becomes the base class, whatever it names")
eq(S.vocationFor("illusionist", 5), 10, "elementalist -> illusionist")
eq(S.vocationFor("elementalist", 10), 5, "illusionist -> elementalist")
eq(S.vocationFor("beastmaster", 7), 15, "deadeye -> beastmaster")
eq(S.vocationFor("deadeye", 15), 7, "beastmaster -> deadeye")
eq(S.vocationFor("mystic", 4), 1, "warrior -> mystic")
eq(S.vocationFor("juggernaut", 8), nil, "same vocation refused")
eq(S.vocationFor("warrior", 4), nil, "same (unascended) vocation refused")
local wv, wmsg = S.vocationFor("warrior", 7)
eq(wv, nil, "an ascended character must name the ascended class"); eq(wmsg:find("juggernaut or berserker") ~= nil, true, wmsg)
eq(S.vocationFor("mystic", 10), nil, "an illusionist naming mystic is asked to choose")
-- the Thief line
eq(S.vocationFor("thief", 4), 11, "warrior -> thief")
eq(S.vocationFor("ninja", 4), 11, "an unascended character becomes a thief, whatever it names")
eq(S.vocationFor("ninja", 8), 12, "juggernaut -> ninja")
eq(S.vocationFor("samurai", 7), 13, "deadeye -> samurai")
eq(S.vocationFor("samurai", 12), 13, "ninja -> samurai")
eq(S.vocationFor("ninja", 13), 12, "samurai -> ninja")
eq(S.vocationFor("juggernaut", 12), 8, "ninja -> juggernaut")
eq(S.vocationFor("berserker", 13), 14, "samurai -> berserker")
eq(S.vocationFor("mystic", 11), 1, "thief -> mystic")
local tv, tmsg = S.vocationFor("thief", 8)
eq(tv, nil, "an ascended character must name ninja or samurai"); eq(tmsg:find("ninja or samurai") ~= nil, true, tmsg)
eq(S.vocationFor("thief", 12), nil, "a ninja naming thief is asked to choose")
eq(S.vocationFor("ninja", 12), nil, "same ascended class refused")
eq(S.vocationFor("thief", 11), nil, "same base refused")
for _, id in ipairs({5, 7, 8, 10, 12, 13, 14, 15}) do eq(S.isPromoted(id), true, id .. " is ascended") end
for _, id in ipairs({1, 3, 4, 11}) do eq(S.isPromoted(id), false, id .. " is a base class") end
local nv, msg = S.vocationFor("knight", 4)
eq(nv, nil, "the old words are gone")
assert(msg:find("beastmaster"), "lists the choices")
eq(Chaos.shopServices.vocationWords:find("berserker") ~= nil, true, "the word list names the new classes")

local st = S.recomputeStats(562, 8, 1054000, {hp = 10, mana = 15, cap = 2000}, {hp = 15, mana = 5, cap = 2500})
eq(st.health, 185 + 554 * 15, "knight health")
eq(st.mana, 90 + 554 * 5, "knight mana")
eq(st.cap, 1054000 + 554 * 500, "capacity keeps extras")
eq(S.recomputeStats(5, 8, 47000, {hp = 15, mana = 5, cap = 2500}, {hp = 5, mana = 30, cap = 1000}).health, 185, "below level 8")
eq(S.recomputeStats(1000, 8, 50000, {hp = 15, mana = 5, cap = 2500}, {hp = 5, mana = 30, cap = 1000}).cap, 47000, "cap floor")

-- ------------------------------------------------------------------ sell prices
local prices = {[100] = 25, [200] = 0}
eq(S.sellPrice(100, 4, prices), 100, "4 x 25")
eq(S.sellPrice(100, nil, prices), 25, "count defaults to 1")
eq(S.sellPrice(200, 1, prices), 0, "zero price")
eq(S.sellPrice(300, 1, prices), 0, "no NPC buys it")
eq(S.sellBlocked({rarity = 0}, false), nil, "plain item sells")
eq(S.sellBlocked({rarity = 3}, false), "rarity", "rarity kept")
eq(S.sellBlocked({attributes = true}, false), "rarity", "modifiers kept")
eq(S.sellBlocked({rarity = 3}, true), nil, "rarity sold after opt-in")
eq(S.sellBlocked({unique = true, rarity = 9}, true), "unique", "uniques never sold")
eq(S.sellBlocked({locked = true, rarity = 3}, true), "locked", "locked items never sold (salvage.lua lock)")
eq(S.sellBlocked({locked = true, rarity = 0}, false), "locked", "a locked plain item is kept too")
local generated = dofile("data/scripts/chaos/sell_prices.lua")
local count = 0
for id, gold in pairs(generated) do
  assert(type(id) == "number" and type(gold) == "number" and gold > 0, "generated table shape")
  count = count + 1
end
assert(count > 100, "generated price table is filled")
eq(S.formatDuration(2 * H + 5 * 60), "2h 05m", "duration")
eq(S.formatDuration(90), "1m 30s", "short duration")

-- ------------------------------------------------------------------ mock player
local function newPlayer(o)
  o = o or {}
  local p = {storage = {}, stamina = o.stamina or 1000, bank = 0, msgs = {}, guid = o.guid or 7, premium = true}
  function p:getStorageValue(k) return self.storage[k] or -1 end
  function p:setStorageValue(k, v) self.storage[k] = v end
  function p:getStamina() return self.stamina end
  function p:setStamina(v) self.stamina = v end
  function p:getPosition() return {sendMagicEffect = function() end} end
  function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
  function p:sendCancelMessage(t) self.msgs[#self.msgs + 1] = t end
  function p:getName() return "Tester" end
  function p:getGuid() return self.guid end
  function p:getBankBalance() return self.bank end
  function p:setBankBalance(v) self.bank = v end
  function p:isPremium() return self.premium end
  return p
end

-- unlocks: refused when owned, delivered as a storage flag
local pl = newPlayer()
local sellerOffer = {kind = "unlock", unlock = "autoSeller"}
eq(S.check(pl, sellerOffer), nil, "auto seller can be bought")
eq(S.deliver(pl, sellerOffer), true, "auto seller delivered")
eq(pl.storage[Chaos.storage.shopAutoSeller], 1, "auto seller flag")
assert(S.check(pl, sellerOffer):find("already own"), "auto seller owned")
-- the retired Bottomless Loot Pouch unlock is no longer sold (pouches.lua gives its owners a Loot Pouch item)
assert(S.check(pl, {kind = "unlock", unlock = "lootPouch"}), "the old loot pouch unlock is gone")
-- the store pouches are a service handled by pouches.lua (pouches_test.lua covers the rules)
assert(S.check(pl, {kind = "service", service = "pouch", pouch = "loot"}), "pouch offer refused without pouches.lua")
do
	local asked
	ChaosPouches = {storeCheck = function(_, kind) asked = kind; return nil end,
		storeGive = function(_, kind) return kind == "orbs" end}
	eq(S.check(pl, {kind = "service", service = "pouch", pouch = "orbs"}), nil, "pouch offer checked by pouches.lua")
	eq(asked, "orbs", "the offer's pouch kind is passed on")
	eq(S.deliver(pl, {kind = "service", service = "pouch", pouch = "orbs"}), true, "pouch delivered by pouches.lua")
	ChaosPouches = nil
end
assert(S.check(pl, {kind = "unlock", unlock = "nope"}), "unknown unlock refused")
assert(S.check(pl, {kind = "service", service = "nope"}), "unknown service refused")

-- a class unlock (class_unlocks.lua, per account): the store asks ChaosClassUnlocks.storeUnlock for the entry
do
	local owned, granted = false, 0
	ChaosClassUnlocks = {storeUnlock = function(name)
		if name ~= "unlockTemplar" then
			return nil
		end
		return {name = "the Templar class", done = "",
			owned = function() return owned end,
			grant = function() granted = granted + 1; owned = true; return true end}
	end}
	local classOffer = {kind = "unlock", unlock = "unlockTemplar"}
	eq(S.check(pl, classOffer), nil, "class unlock can be bought")
	eq(S.deliver(pl, classOffer), true, "class unlock delivered")
	eq(granted, 1, "granted through class_unlocks.lua")
	assert(S.check(pl, classOffer):find("already own"), "class unlock owned")
	assert(S.check(pl, {kind = "unlock", unlock = "unlockNope"}), "unknown class unlock refused")
	ChaosClassUnlocks = {storeUnlock = function() return {name = "x", done = "", owned = function() return false end,
		grant = function() return false, "db down" end} end}
	eq(S.deliver(pl, classOffer), "db down", "a failed grant is an error (shop.lua refunds)")
	ChaosClassUnlocks = nil
end

-- stamina: refused when full
eq(S.check(pl, {kind = "service", service = "stamina"}), nil, "stamina not full")
eq(S.deliver(pl, {kind = "service", service = "stamina"}), true, "stamina delivered")
eq(pl.stamina, Chaos.shopServices.maxStamina, "stamina full")
assert(S.check(pl, {kind = "service", service = "stamina"}), "full stamina refused")

-- tokens: one unused token at a time
local tok = {kind = "service", service = "nameToken"}
eq(S.check(pl, tok), nil, "name token")
S.deliver(pl, tok)
eq(pl.storage[Chaos.storage.nameChangeTokens], 1, "token stored")
assert(S.check(pl, tok), "second token refused while unused")

-- world buffs: purchase, stacking cap, effects
local realTime = os.time
local now = 1800000000
os.time = function(t) if t then return realTime(t) end return now end
local xpOffer = {kind = "service", service = "worldBuff", buff = "xp"}
eq(S.buffMult("xp"), 1, "no buff yet")
eq(S.check(pl, xpOffer), nil, "buff can start")
eq(S.deliver(pl, xpOffer), true, "buff started")
assert(Game.lastBroadcast:find("Tester activated the World Experience"), "broadcast with buyer name")
eq(S.buffLeft("xp"), H, "one hour")
eq(S.buffMult("xp"), 1.25, "+25%")
assert(queries[#queries]:find("server_config") and queries[#queries]:find("chaos_worldbuff_xp"), "persisted to server_config")
S.deliver(pl, xpOffer)
S.deliver(pl, xpOffer)
eq(S.buffLeft("xp"), 3 * H, "three hours")
assert(Game.lastBroadcast:find("extended"), "extension broadcast")
assert(S.check(pl, xpOffer):find("at most"), "cap reached: refused before taking coins")
eq(S.buffMult("loot"), 1, "other buffs independent")
local monster = {isMonster = function() return true end}
eq(callback("onGainExperience", 5)(nil, monster, 1000, 1000), 1250, "xp callback")
eq(callback("onGainExperience", 5)(nil, {isMonster = function() return false end}, 1000, 1000), 1000, "only monster xp")
-- season characters: no World Experience, and the base double experience potion (storage 6000) is undone
ChaosSeason = {realmOf = function(p) return p.realm or 0 end}
local seasonal = {realm = 1, st = {}, getStorageValue = function(self, k) return self.st[k] or -1 end}
eq(callback("onGainExperience", 5)(seasonal, monster, 1000, 1000), 1000, "season: no world experience")
seasonal.st[6000] = os.time() + 3600
eq(callback("onGainExperience", 5)(seasonal, monster, 2000, 1000), 1000, "season: the potion's doubling undone")
eq(callback("onGainExperience", 5)({realm = 0}, monster, 1000, 1000), 1250, "standard character keeps the buff")
ChaosSeason = nil
now = now + 3 * H + 1
eq(S.buffMult("xp"), 1, "buff expired")
eq(callback("onGainExperience", 5)(nil, monster, 1000, 1000), 1000, "expired: no bonus")
S.deliver(pl, {kind = "service", service = "worldBuff", buff = "skill"})
local tries = callback("onGainSkillTries", 5)(nil, 1, 100)
eq(tries, 125, "skill tries +25%")
local sum = 0
for _ = 1, 4000 do sum = sum + callback("onGainSkillTries", 5)(nil, 1, 1) end
assert(sum > 4600 and sum < 5400, "fractional tries kept as a chance: " .. sum)
-- reload after a restart: memory empty, value read back from server_config
global = {}
db.storeQuery = function() return 1 end
result = {getString = function() return tostring(now + 600) end, next = function() return false end, free = function() end}
S.loadBuffs()
eq(S.buffLeft("skill"), 600, "restored from server_config")
db.storeQuery = function() return nil end
os.time = realTime

-- ------------------------------------------------------------------ auto seller (onDropLoot index 2)
local function newItem(id, count, o)
  o = o or {}
  local it = {id = id, count = count or 1, removed = false, custom = o.custom or {}, attrs = o.attrs or {}}
  function it:getId() return self.id end
  function it:getCount() return self.count end
  function it:getType() return {getName = function() return "item" .. id end, isContainer = function() return false end,
    isStackable = function() return true end} end
  function it:remove() self.removed = true; return true end
  function it:getCustomAttribute(k) return self.custom[k] end
  function it:hasAttribute(a) return self.attrs[a] == true end
  function it:moveTo(target) if target and target.accepts then self.movedTo = target; self.removed = true; return true end return false end
  return it
end
local function corpseOf(owner, items)
  return {getType = function() return {isContainer = function() return true end} end,
    getCorpseOwner = function() return owner end, getItems = function() return items end}
end
local seller = newPlayer({guid = 9})
Player = function(id) if id == "seller" then return seller end end
ChaosAutoSell.prices[100] = 30
local first = 100
seller.storage[Chaos.storage.shopAutoSeller] = 1
seller.storage[Chaos.storage.autosellBase + 1] = first
local plain, rare, unique, other = newItem(100, 3), newItem(100, 1, {custom = {rarity = 4}}),
  newItem(100, 1, {custom = {chaos_unique = 1}}), newItem(555, 1)
callback("onDropLoot", 2)(nil, corpseOf("seller", {plain, rare, unique, other}))
eq(seller.bank, 90, "3 x 30 gold into the bank")
eq(plain.removed, true, "plain item sold")
eq(rare.removed, false, "rarity item kept")
eq(unique.removed, false, "unique kept")
eq(other.removed, false, "item not on the list untouched")
seller.storage[Chaos.storage.autosellRarity] = 1
callback("onDropLoot", 2)(nil, corpseOf("seller", {rare, unique}))
eq(seller.bank, 120, "rarity item sold after opt-in")
eq(unique.removed, false, "unique still kept")
local locked = newItem(100, 1, {custom = {rarity = 2, chaos_locked = 1}})
callback("onDropLoot", 2)(nil, corpseOf("seller", {locked}))
eq(locked.removed, false, "a locked item is never sold, even after the opt-in (salvage.lua lock)")
eq(seller.bank, 120, "nothing paid for the locked item")
seller.storage[Chaos.storage.autosellPaused] = 1
local again = newItem(100, 1)
callback("onDropLoot", 2)(nil, corpseOf("seller", {again}))
eq(again.removed, false, "paused: nothing sold")
seller.storage[Chaos.storage.autosellPaused] = 0
seller.storage[Chaos.storage.shopAutoSeller] = -1
callback("onDropLoot", 2)(nil, corpseOf("seller", {again}))
eq(again.removed, false, "not unlocked: nothing sold")

-- ------------------------------------------------------------------ never sold: what the store pouches collect
ChaosPouches = {neverSell = function(id) return id == 100 end}
seller.storage[Chaos.storage.shopAutoSeller] = 1
local orb = newItem(100, 2)
callback("onDropLoot", 2)(nil, corpseOf("seller", {orb}))
eq(orb.removed, false, "an orb on the auto-sell list is never sold (ChaosPouches.neverSell)")
ChaosPouches = nil
assert(callback("onDropLoot", 4) == nil, "no loot pouch callback at index 4 any more")

print("shop_services_test: ok")
