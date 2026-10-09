-- Run from the server/ folder: luajit tests/gems_test.lua (and lua5.3; CI runs both)
-- Gems and sockets: data/lib/chaos_gems.lua (ids, effects per slot group, socket counts by kind and rarity, socketing,
-- totals and caps, the description section, combining, drop and reward rolls), the Orb of Sockets and the other orbs
-- through data/lib/chaos_crafting.lua, the weapon's attack interval (chaos_item_mods.lua), and
-- data/scripts/chaos/gems.lua against a mocked engine (use-with socketing and combining, taking gems out for gold or
-- shattering them, the condition with max health / mana / critical / leech, element damage dealt and taken).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
ITEM_ATTRIBUTE_DESCRIPTION, ITEM_ATTRIBUTE_NAME, ITEM_ATTRIBUTE_ATTACK_SPEED = 1, 2, 3
INDEX_WHEREEVER, FLAG_NOLIMIT, RETURNVALUE_NOERROR = -1, 1, 0
SLOTP_HEAD, SLOTP_NECKLACE, SLOTP_ARMOR, SLOTP_LEGS, SLOTP_FEET, SLOTP_RING, SLOTP_TWO_HAND = 1, 2, 8, 64, 128, 256, 2048
WEAPON_SHIELD, WEAPON_AMMO = 4, 7

local TYPES = {
	[2400] = {name = "magic sword", weaponType = 1, attack = 48, slot = 48},
	[7390] = {name = "the justice seeker", weaponType = 1, attack = 47, slot = 48, attackSpeed = 1500},
	[2431] = {name = "stonecutter axe", weaponType = 3, attack = 50, slot = 48 + SLOTP_TWO_HAND},
	[2466] = {name = "golden armor", armor = 14, slot = SLOTP_ARMOR, description = "It shines."},
	[2195] = {name = "boots of haste", armor = 1, slot = SLOTP_FEET},
	[2171] = {name = "platinum amulet", armor = 2, slot = SLOTP_NECKLACE},
	[2471] = {name = "golden helmet", armor = 12, slot = SLOTP_HEAD},
	[2514] = {name = "mastermind shield", weaponType = WEAPON_SHIELD, defense = 37, slot = 48},
	[2160] = {name = "crystal coin", stackable = true}
}

function ItemType(id)
	local t = TYPES[id] or {}
	return {
		getId = function() return id end,
		getName = function() return t.name or "" end,
		getDescription = function() return t.description or "" end,
		isContainer = function() return false end,
		isStackable = function() return t.stackable == true or (id >= 32001 and id <= 32035) end,
		getWeaponType = function() return t.weaponType or 0 end,
		getSlotPosition = function() return t.slot or 0 end,
		getArmor = function() return t.armor or 0 end,
		getAttack = function() return t.attack or 0 end,
		getDefense = function() return t.defense or 0 end,
		getHitChance = function() return 0 end,
		getElementDamage = function() return 0 end,
		getAttackSpeed = function() return t.attackSpeed or 0 end,
		getAbilities = function() return {} end,
		getClientId = function() return id end
	}
end

local Item = {}
Item.__index = Item
local function newItem(id, count)
	return setmetatable({id = id, count = count or 1, attrs = {}, custom = {}}, Item)
end
function Item:getId() return self.id end
function Item:getType() return ItemType(self.id) end
function Item:getCount() return self.count end
function Item:isItem() return true end
function Item:getName() return self.attrs[ITEM_ATTRIBUTE_NAME] or ItemType(self.id):getName() end
function Item:getCustomAttribute(k) return self.custom[k:lower()] end
function Item:setCustomAttribute(k, v) self.custom[k:lower()] = v end
function Item:removeCustomAttribute(k) self.custom[k:lower()] = nil return true end
function Item:getAttribute(k) return self.attrs[k] or (k == ITEM_ATTRIBUTE_DESCRIPTION and "" or nil) end
function Item:setAttribute(k, v) self.attrs[k] = v end
function Item:removeAttribute(k) self.attrs[k] = nil end
function Item:getActionId() return 0 end
function Item:getParent() return self.parent end
function Item:getTopParent() return self.holder end
function Item:remove(n)
	n = n or self.count
	self.count = self.count - n
	if self.count <= 0 and self.parent and self.parent.items then
		for i, it in ipairs(self.parent.items) do
			if it == self then table.remove(self.parent.items, i) break end
		end
	end
	return true
end

local bag = {items = {}}
function bag:addItemEx(item)
	self.items[#self.items + 1] = item
	item.parent = self
	return RETURNVALUE_NOERROR
end
local function put(item)
	bag:addItemEx(item)
	return item
end

Game = {
	createItem = function(id, count) return newItem(id, count) end,
	createItemWithRarity = function(id, count, rarity)
		local it = newItem(id, count)
		it:setCustomAttribute("rarity", rarity)
		it:setCustomAttribute("combatPowerLevel", rarity * 10 - 3)
		it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Level: " .. (rarity * 10 - 3))
		return it
	end
}

dofile("data/lib/chaos_crafting.lua")
local C, M, G = ChaosCrafting, ChaosItemMods, ChaosGems
local cfg = G.config
M.random = function(a, b) return b end -- no Chaos modifiers on recreated items
local dice = {}
local function roll(a, b)
	local v = table.remove(dice, 1)
	if v == nil then
		return a
	end
	assert(v >= a and v <= b, "dice value " .. v .. " outside " .. a .. ".." .. b)
	return v
end
C.random, G.random = roll, roll

local function gear(id, rarity)
	local it = put(newItem(id))
	if rarity and rarity > 0 then
		it:setCustomAttribute("rarity", rarity)
		it:setCustomAttribute("combatPowerLevel", 42)
		it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Level: 42")
	end
	return it
end

-- ---------------------------------------------------------------- ids
eq(G.TYPES, 7, "seven gem types")
eq(G.TIERS, 5, "five tiers")
eq(G.gemId(1, 1), 32001, "chipped ruby")
eq(G.gemId(7, 5), 32035, "perfect onyx")
eq(G.lastId, 32035, "last id")
local seen = {}
for t = 1, 7 do
	for q = 1, 5 do
		local id = G.gemId(t, q)
		assert(not seen[id], "duplicate id")
		seen[id] = true
		local g = G.gemOf(id)
		eq(g.type.index, t, "type of " .. id)
		eq(g.tier, q, "tier of " .. id)
	end
end
eq(G.gemOf(32000), nil, "below the range")
eq(G.gemOf(32036), nil, "above the range")
eq(G.isGem(2147), false, "a stock small ruby is no socket gem")
eq(G.gemName(32004), "Flawless Ruby", "name")
eq(G.itemName(4, 2, true), "flawed amethysts", "items.xml plural")
eq(G.clientIdOf(1, 3), 3030, "small ruby sprite up to Polished")
eq(G.clientIdOf(1, 4), 676, "enchanted ruby sprite from Flawless")
eq(G.clientIdOf(5, 5), 9057, "topaz has no high sprite")

-- ---------------------------------------------------------------- effects
local e = G.effectOf(32004, "weapon")
eq(e.key, "dmg_fire", "ruby in a weapon"); eq(e.value, 9, "flawless value")
eq(G.effectOf(32004, "armour").value, 130, "ruby in armour: max health")
eq(G.effectOf(32004, "jewel").key, "res_fire", "ruby in jewellery")
local crit = G.effectOf(G.gemId(4, 3), "weapon")
eq(crit.key, "crit", "amethyst in a weapon"); eq(crit.value, 3, "crit chance"); eq(crit.value2, 15, "crit damage")
eq(G.effectText("crit", 3, 15), "Critical Chance +3%, Critical Hit +15%", "pair text")
eq(G.effectText("maxhealth", 80), "Max Health +80", "flat text")
eq(G.gemText(32004, "weapon"), "Flawless Ruby (Fire Damage +9%)", "gem text")
eq(G.gemSummary(32001), "weapon: Fire Damage +2%; armour: Max Health +20; jewellery: Fire Resistance +2%", "summary")
-- every type has every group and one value per tier, every effect is known
for _, t in ipairs(cfg.types) do
	for _, group in ipairs({"weapon", "armour", "jewel"}) do
		assert(cfg.effects[t[group].effect], t.key .. " " .. group)
		eq(#t[group].values, 5, t.key .. " " .. group .. " values")
		for q = 2, 5 do
			assert(t[group].values[q] >= t[group].values[q - 1], t.key .. " values rise")
		end
	end
end

-- ---------------------------------------------------------------- socket counts
eq(G.groupOf(gear(2400)), "weapon", "sword group")
eq(G.groupOf(gear(2514)), "armour", "shields are armour")
eq(G.groupOf(gear(2171)), "jewel", "amulet")
eq(G.maxSockets(gear(2400)), 1, "a normal sword: 1")
eq(G.maxSockets(gear(2400, 4)), 2, "an Epic sword: 2")
eq(G.maxSockets(gear(2400, 13)), 2, "one-handed weapons: 2 at most")
eq(G.maxSockets(gear(2431, 13)), 3, "two-handed: 3")
eq(G.maxSockets(gear(2466, 7)), 2, "a Mythic armour: 2 (rarity)")
eq(G.maxSockets(gear(2466, 10)), 3, "a Divine armour: 3")
eq(G.maxSockets(gear(2195, 15)), 1, "boots: 1")
eq(G.maxSockets(gear(2171, 15)), 1, "jewellery: 1")
eq(G.maxSockets(put(newItem(2160, 5))), 0, "not gear")
local uniq = gear(2400)
uniq:setCustomAttribute("chaos_unique", 1)
eq(G.maxSockets(uniq), cfg.uniqueSockets, "unique: fixed")
eq(G.count(uniq), 1, "a unique has its socket without the attribute")

-- ---------------------------------------------------------------- inserting and taking
local sword = gear(2400, 6)
G.setCount(sword, 2)
eq(G.count(sword), 2, "two sockets")
eq(G.insert(sword, 32004), 1, "first socket")
eq(G.insert(sword, 2147), nil, "a stock gem does not go in")
eq(G.insert(sword, G.gemId(4, 3)), 2, "second socket")
eq(G.insert(sword, 32001), nil, "full")
eq(G.read(sword).filled, 2, "two gems")
eq(G.take(sword, 1), 32004, "taken out")
eq(G.gemAt(sword, 1), 0, "socket 1 empty")
eq(G.firstFree(sword), 1, "first free")
eq(G.take(sword, 1), nil, "nothing to take")
eq(G.take(sword, 3), nil, "no socket 3")
G.insert(sword, 32004)
-- fewer sockets: the gems move to the front, the ones past the end come back
local s2 = gear(2466, 10)
G.setCount(s2, 3)
s2:setCustomAttribute("chaos_gem3", 32010)
local dropped = G.setCount(s2, 1)
eq(G.gemAt(s2, 1), 32010, "packed to the front")
eq(#dropped, 0, "nothing dropped")
G.setCount(s2, 3); G.insert(s2, 32001); dropped = G.setCount(s2, 1)
eq(#dropped, 1, "one gem past the end"); eq(dropped[1], 32001, "the second gem")
-- unique: socketing writes the count
eq(G.insert(uniq, 32020), 1, "a unique takes a gem")
eq(uniq:getCustomAttribute("chaos_sockets"), 1, "count written")

-- ---------------------------------------------------------------- totals and caps
local armour = gear(2466, 10); G.setCount(armour, 3)
G.insert(armour, 32005); G.insert(armour, 32005); G.insert(armour, G.gemId(6, 5)) -- 2 perfect rubies, perfect diamond
local amulet = gear(2171, 10); G.setCount(amulet, 1); G.insert(amulet, 32005) -- fire resistance 8
local t = G.totals({sword, armour, amulet})
eq(t.dmg_fire, 9, "flawless ruby in the sword")
eq(t.crit, 3, "amethyst crit chance"); eq(t.crit2, 15, "amethyst crit damage")
eq(t.maxhealth, 400, "two perfect rubies in armour")
eq(t.res_fire, 8 + 4, "amulet ruby + diamond's all resistances")
eq(t.res_ice, 4, "diamond spreads"); eq(t.res_physical, 0, "but not to physical")
eq(t.attackspeed, nil, "attack speed is no character total")
-- caps
local many = {}
for i = 1, 6 do
	local w = gear(2431, 15); G.setCount(w, 3)
	for _ = 1, 3 do G.insert(w, 32005) end
	many[i] = w
end
eq(G.totals(many).dmg_fire, cfg.effects.dmg_fire.cap, "fire damage capped")
local leech = {}
for i = 1, 4 do
	local w = gear(2431, 15); G.setCount(w, 3)
	for _ = 1, 3 do G.insert(w, 32035) end
	leech[i] = w
end
local lt = G.totals(leech)
eq(lt.leech, cfg.effects.leech.cap, "leech chance capped"); eq(lt.leech2, cfg.effects.leech.cap2, "leech amount capped")
eq(G.totals({}).maxmana, 0, "nothing equipped")
eq(G.scale(-100, 10), -110, "damage +10%"); eq(G.scale(-100, -8), -92, "damage -8%")

-- attack speed: the weapon's own interval, modifier + topaz under the gem cap
local blade = gear(7390, 10); G.setCount(blade, 2)
G.insert(blade, G.gemId(5, 5)) -- perfect topaz: 5%
M.syncAttackSpeed(blade)
eq(blade.attrs[ITEM_ATTRIBUTE_ATTACK_SPEED], 1425, "1500 ms -5%")
M.set(blade, "attackspeed", 10)
eq(blade.attrs[ITEM_ATTRIBUTE_ATTACK_SPEED], 1275, "mod 10% + gem 5%")
G.insert(blade, G.gemId(5, 5)); M.syncAttackSpeed(blade)
eq(blade.attrs[ITEM_ATTRIBUTE_ATTACK_SPEED], 1200, "mod 10 + gems 10 = cap 20")
eq(G.attackSpeedOf(gear(2466)), 0, "no topaz")

-- ---------------------------------------------------------------- description
eq(G.sectionText(sword), "Sockets (2/2): Flawless Ruby (Fire Damage +9%), Polished Amethyst (Critical Chance +3%, Critical Hit +15%).", "section")
eq(G.summary(sword), "Sockets 2/2: Flawless Ruby (Fire Damage +9%), Polished Amethyst (Critical Chance +3%, Critical Hit +15%)", "summary line")
eq(G.strip("Level: 5, Fire +1% Sockets (0/1): empty."), "Level: 5, Fire +1%", "strip")
eq(G.strip("Level: 5 Sockets (1/2): Flawless Ruby (Fire Damage +9%), empty. [Attack+2]"), "Level: 5 [Attack+2]", "strip keeps what follows")
-- rarity items: through rewriteDescription, upgrade slots kept, section last, written once
sword:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "Level: 42 [Attack+1]")
sword:setCustomAttribute("rarity_swordSkill", 1)
G.writeDescription(sword)
eq(sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Level: 42, Sword +1 [Attack+1]. Sockets (2/2): Flawless Ruby (Fire Damage +9%), Polished Amethyst (Critical Chance +3%, Critical Hit +15%).", "rarity description")
C.rewriteDescription(sword)
local _, n = sword:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):gsub("Sockets", "")
eq(n, 1, "one section after a second rewrite")
-- normal items: the items.xml description is kept in front
local plain = gear(2466); G.setCount(plain, 1)
G.writeDescription(plain)
eq(plain:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "It shines. Sockets (0/1): empty.", "normal item")
G.insert(plain, 32006); G.writeDescription(plain)
eq(plain:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "It shines. Sockets (1/1): Chipped Sapphire (Max Mana +15).", "armour group")

-- ---------------------------------------------------------------- the Orb of Sockets and the other orbs
local orb = C.orbByKey.sockets
eq(orb.id, cfg.socketOrb.id, "eighth orb"); eq(#C.config.orbs, 8, "eight orbs")
eq(C.orbById[24692].key, "sockets", "by id")
local axe = gear(2431, 13)
eq(C.check("sockets", axe), true, "a fresh two-hander")
eq(C.preview("sockets", axe), "0 -> 1-3 sockets", "preview")
dice = {100} -- weights 50/35/15: 100 = the third
local ok, res = C.apply("sockets", axe)
eq(ok, true, "applied"); eq(G.count(axe), 3, "three sockets")
eq(res.text, "stonecutter axe now has 3 sockets (had 0).", "text")
assert(axe:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Sockets %(0/3%): empty, empty, empty%."), "description")
G.insert(axe, 32001); G.insert(axe, 32002)
eq(C.preview("sockets", axe), "3 -> 2-3 sockets", "never below the gems")
dice = {1}
C.apply("sockets", axe)
eq(G.count(axe), 2, "rerolled to 2"); eq(G.read(axe).filled, 2, "gems kept")
eq(select(2, C.check("sockets", uniq)), "unique", "uniques keep their socket")
eq(select(2, C.check("sockets", put(newItem(2160, 3)))), "notGear", "not gear")
local boots = gear(2195, 3); G.setCount(boots, 1)
eq(select(2, C.check("sockets", boots)), G.reasons.same, "boots already at their one socket")
eq(C.check("sockets", gear(2195, 3)), true, "boots without a socket")
-- sockets and gems survive the orbs that remake an item, and are part of the bench signature
local before = C.signature(axe)
G.take(axe, 1)
assert(C.signature(axe) ~= before, "signature follows the gems")
local okChaos, r2 = C.apply("chaos", axe)
eq(okChaos, true, "chaos orb")
eq(G.count(r2.item), 2, "sockets survive the Chaos Orb"); eq(G.gemAt(r2.item, 2), 32002, "and the gem, in its socket")
assert(r2.item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Sockets %(1/2%)"), "copy has the section")
local okScour, r3 = C.apply("scouring", r2.item)
eq(okScour, true, "scouring"); eq(G.count(r3.item), 2, "sockets survive scouring")
eq(r3.item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION), "Sockets (1/2): empty, Flawed Ruby (Fire Damage +4%).", "a normal copy keeps only the section")
local view = C.describe(r3.item)
eq(view.sockets.count, 2, "bench view"); eq(view.sockets.list[2].name, "Flawed Ruby", "bench gem")
eq(view.sockets.list[2].cost, cfg.removeCost[2], "removal cost"); eq(view.sockets.list[1].id, 0, "empty socket")
eq(view.orbs.sockets, "", "orb usable")

-- ---------------------------------------------------------------- combining
eq(G.combineResult(32001), 32002, "three chipped -> one flawed")
eq(G.combineResult(32004), 32005, "flawless -> perfect")
eq(select(2, G.combineResult(32005)), "perfect", "perfect stays")
eq(select(2, G.combineResult(2147)), "notGem", "not a gem")
eq(G.removeCost(32003), cfg.removeCost[3], "cost by tier")

-- ---------------------------------------------------------------- drops and rewards
eq(G.rarityIndex(0), 1, "no rarity"); eq(G.rarityIndex(3), 2, "Rare"); eq(G.rarityIndex(15), 6, "Transcendent")
dice = {100} -- Common-Rare weights 80/18/2/0: 100 = 2 sockets
eq(G.rollDropCount(2), 2, "drop count")
dice = {100}
local drop = gear(2195, 2)
eq(G.rollDropSockets(drop), 1, "boots: capped at 1")
eq(G.rollDropSockets(drop), 0, "only once")
eq(G.rollDropSockets(gear(2400)), 0, "no rarity: no sockets")
dice = {1}
eq(#G.rollDrop("normal", 10, 1), 1, "lowest roll drops")
dice = {cfg.drop.chance.normal * 100 + 1}
eq(#G.rollDrop("normal", 10, 1), 0, "just above the chance")
dice = {cfg.drop.chance.normal * 200}
eq(#G.rollDrop("normal", 10, 2), 1, "the rate doubles it")
dice = {1, 100, 3, 1} -- drops; level 1000 weights {5,25,40,24,6}: 100 = Perfect; type 3 (emerald); tier up (boss)
local d = G.rollDrop("boss", 1000, 1)
eq(d[1], G.gemId(3, 5), "perfect stays perfect")
dice = {1, 1, 2, 1}
eq(G.rollDrop("legendary", 10, 1)[1], G.gemId(2, 2), "tier up for a legendary")
eq(#G.rollDrop("normal", 10, 0), 0, "scale 0")
-- level weights
eq(G.levelWeights(1)[1], 85, "low level"); eq(G.levelWeights(400)[5], 2, "level 400")
-- rewards
dice = {30, 1, 1}
local b = G.rewardGems("bounty", {type = "hunt", band = 1})
eq(#b, 1, "bounty hunt at 30%"); eq(b[1].id, 32001, "band 1: chipped ruby")
dice = {31}
eq(#G.rewardGems("bounty", {type = "hunt", band = 1}), 0, "above the chance")
dice = {100, 1, 1}
eq(#G.rewardGems("bounty", {type = "boss", band = 6}), 1, "boss contracts always")
dice = {1, 1, 1, 1}
local w = G.rewardGems("bountyWeekly", {band = 2})
eq(#w, 1, "two of the same merge"); eq(w[1].count, 2, "merged count")
dice = {1}
eq(G.rewardGems("rift", {tier = 1})[1].count, 2, "rift tier 1: 1 + a 20% chance of one more (rolled 1)")
dice = {2001}
eq(G.rewardGems("rift", {tier = 1})[1].count, 1, "rift tier 1: the 20% missed")
dice = {}
local rt = G.rewardGems("rift", {tier = 5})
eq(rt[1].count, 2, "tier 5: 1 + 1.0 = 2")
dice = {1}
local wb = G.rewardGems("worldboss", {share = 0.5})
local total = 0
for _, x in ipairs(wb) do total = total + x.count end
eq(total, 4, "world boss: 2 + 4 x 0.5")
eq(G.listText({{id = 32001, count = 2}, {id = 32034, count = 1}}), "2 Chipped Rubies, Flawless Onyx", "list text")

-- ---------------------------------------------------------------- runtime (data/scripts/chaos/gems.lua)
CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, CONDITION_PARAM_SUBID = 1, 0, 100
CONDITION_PARAM_STAT_MAXHITPOINTS, CONDITION_PARAM_STAT_MAXMANAPOINTS = 101, 102
CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE, CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT = 103, 104
CONDITION_PARAM_SPECIALSKILL_LIFELEECHCHANCE, CONDITION_PARAM_SPECIALSKILL_LIFELEECHAMOUNT = 105, 106
COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_EARTHDAMAGE = 1, 8, 16, 2
COMBAT_ENERGYDAMAGE, COMBAT_DEATHDAMAGE, COMBAT_HOLYDAMAGE, COMBAT_HEALING, COMBAT_NONE = 4, 32, 64, 128, 0
MESSAGE_INFO_DESCR = 1
CONST_ME_MAGIC_BLUE, CONST_ME_MAGIC_GREEN, CONST_ME_BLOCKHIT = 1, 2, 3
Chaos = {giveItem = nil}
local events, actions = {}, {}
function CreatureEvent(name)
	local o = {name = name}
	o.register = function(self) events[name] = self return true end
	return o
end
EventCallback = setmetatable({}, {__index = function() return nil end})
EventCallback.register = function() return true end
function Action()
	local a = {}
	a.id = function(self, id) actions[id] = self end
	a.allowFarUse = function() end
	a.register = function() return true end
	return a
end
function Condition(kind, id)
	local c = {params = {}}
	c.setTicks = function() end
	c.setParameter = function(self, k, v) self.params[k] = v end
	return c
end

local Player = {}
Player.__index = Player
local function newPlayer()
	return setmetatable({id = 7, inv = {}, conds = {}, bank = 0, money = 0, msgs = {}, cancels = {}}, Player)
end
function Player:getId() return self.id end
function Player:isPlayer() return true end
function Player:getMaster() return nil end
function Player:getItemCount(id) return self.inv[id] or 0 end
function Player:removeItem(id, n)
	if (self.inv[id] or 0) < n then return false end
	self.inv[id] = self.inv[id] - n
	return true
end
function Player:addItem(id, n) self.inv[id] = (self.inv[id] or 0) + n end
function Player:getInbox() return nil end
function Player:getBankBalance() return self.bank end
function Player:setBankBalance(v) self.bank = v end
function Player:removeMoney(n)
	if self.money < n then return false end
	self.money = self.money - n
	return true
end
function Player:addCondition(c) self.conds[c.params[CONDITION_PARAM_SUBID]] = c end
function Player:removeCondition(kind, id, sub) self.conds[sub] = nil end
function Player:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
function Player:sendCancelMessage(text) self.cancels[#self.cancels + 1] = text end
function Player:getPosition() return {sendMagicEffect = function() end} end
function Chaos.giveItem(player, id, count) player:addItem(id, count) return count end

dofile("data/scripts/chaos/gems.lua")
local p = newPlayer()
-- conditions
G.applyTotals(p, {maxhealth = 400, maxmana = 0, crit = 3, crit2 = 15, leech = 0, leech2 = 0})
local cond = p.conds[7240]
eq(cond.params[CONDITION_PARAM_STAT_MAXHITPOINTS], 400, "max health condition")
eq(cond.params[CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT], 15, "critical damage")
eq(cond.params[CONDITION_PARAM_STAT_MAXMANAPOINTS], nil, "no mana")
G.applyTotals(p, G.totals({}))
eq(p.conds[7240], nil, "removed when nothing is equipped")
-- damage dealt and taken
G.applyTotals(p, {dmg_fire = 10, res_ice = 20})
local monster = {isPlayer = function() return false end, getMaster = function() return nil end}
local a, _, b2 = events.ChaosGemsDealt.onHealthChange(monster, p, -100, COMBAT_FIREDAMAGE, -50, COMBAT_ICEDAMAGE, 0)
eq(a, -110, "fire hit +10%"); eq(b2, -50, "ice part unchanged")
local summon = {isPlayer = function() return false end, getMaster = function() return p end}
eq((events.ChaosGemsDealt.onHealthChange(monster, summon, -100, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0)), -110, "summons too")
eq((events.ChaosGemsDealt.onHealthChange(monster, p, 100, COMBAT_HEALING, 0, COMBAT_NONE, 0)), 100, "heals untouched")
eq((events.ChaosGemsTaken.onHealthChange(p, monster, -100, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, 0)), -80, "ice taken -20%")
eq((events.ChaosGemsTaken.onHealthChange(p, monster, -100, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, 0)), -100, "fire taken unchanged")
G.forget(p)
eq((events.ChaosGemsTaken.onHealthChange(p, monster, -100, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, 0)), -100, "forgotten at logout")

-- use-with: socket a gem into gear the player carries
local onUse = actions[32004].onUse
local helm = gear(2471, 10); helm.holder = p; G.setCount(helm, 1)
local stack = put(newItem(32004, 2)); stack.holder = p
onUse(p, stack, nil, helm)
eq(G.gemAt(helm, 1), 32004, "socketed by use-with"); eq(stack.count, 1, "one gem used")
assert(p.msgs[#p.msgs]:find("Flawless Ruby socketed into golden helmet %(socket 1%): Max Health %+130%."), p.msgs[#p.msgs])
assert(helm:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION):find("Sockets %(1/1%)"), "description updated")
onUse(p, stack, nil, helm)
eq(p.cancels[#p.cancels], G.reasons.full, "full"); eq(stack.count, 1, "nothing used")
local foreign = gear(2471, 10); G.setCount(foreign, 1)
onUse(p, stack, nil, foreign)
eq(G.gemAt(foreign, 1), 0, "not someone else's item")
local bare = gear(2466, 5); bare.holder = p
onUse(p, stack, nil, bare)
assert(p.cancels[#p.cancels]:find("Orb of Sockets"), "no sockets: the orb is named")
-- combining
p.inv[32001] = 4
local chipped = put(newItem(32001, 4)); chipped.holder = p
actions[32001].onUse(p, chipped, nil, chipped)
eq(p.inv[32001], 1, "three used"); eq(p.inv[32002], 1, "one flawed")
assert(p.msgs[#p.msgs]:find("Three Chipped Rubies became a Flawed Ruby"), p.msgs[#p.msgs])
actions[32001].onUse(p, chipped, nil, chipped)
eq(p.cancels[#p.cancels], G.reasons.needThree, "needs three"); eq(p.inv[32001], 1, "nothing used")
p.inv[32005] = 3
actions[32005].onUse(p, chipped, nil, chipped) -- the target is what matters: same id as the used gem
local perfect = put(newItem(32005, 3)); perfect.holder = p
actions[32005].onUse(p, perfect, nil, perfect)
eq(p.cancels[#p.cancels], G.reasons.perfect, "perfect does not combine"); eq(p.inv[32005], 3, "kept")
actions[32001].onUse(p, chipped, nil, nil)
assert(p.msgs[#p.msgs]:find("Use it with a piece of gear"), "plain use explains")
-- taking a gem out: for gold (bank first, then the backpack) or shattered
local cost = G.removeCost(32004)
local okR, why = G.unsocket(p, helm, 1, true)
eq(okR, false, "no gold"); assert(why:find(tostring(cost)), why)
p.money = cost
okR = G.unsocket(p, helm, 1, true)
eq(okR, true, "paid from the backpack"); eq(p.money, 0, "money taken"); eq(p.inv[32004], 1, "gem back")
G.insert(helm, 32004); p.bank = cost + 5
G.unsocket(p, helm, 1, true)
eq(p.bank, 5, "bank first"); eq(p.inv[32004], 2, "second gem back")
G.insert(helm, 32004)
okR = G.unsocket(p, helm, 1, false)
eq(okR, true, "shattered"); eq(p.inv[32004], 2, "nothing back"); eq(G.gemAt(helm, 1), 0, "socket empty")
eq((G.unsocket(p, helm, 1, false)), false, "empty socket")
eq((G.unsocket(p, helm, "x", false)), false, "bad index")

print("gems_test: " .. checks .. " checks OK")
