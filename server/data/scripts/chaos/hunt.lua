-- Hunt tracker (client game_hunt, extended opcode ChaosOpcodes.hunt)
--
-- Counts a hunting session on the server and pushes it to the client window: session time (pause / resume / reset),
-- experience and exp/h, time to the next level, kills per monster, loot (items and gold value, NPC sell prices of
-- sell_prices.lua, coins at face value), supplies used (potions, runes, ammunition; NPC buy prices of
-- hunt_supplies.lua), profit and profit/h, damage dealt and healing received, and the Chaos drops (orbs, uniques,
-- items with a rarity). The pure logic is hunt_core.lua (tests: server/tests/hunt_test.lua); settings hunt_config.lua.
--
-- Where the numbers come from:
--   experience  EventCallback onGainExperience at index cfg.expIndex (after every bonus): what the character really gets
--   kills       CreatureEvent kill (the engine runs it for the last hit and the most damage), monsters without a master
--   loot        EventCallback onDropLoot, the corpses the character owns: read before (cfg.lootBeforeIndex) and after
--               (cfg.lootAfterIndex) the index-2 callbacks, the larger count per item kept (auto seller, paragon gold)
--   supplies    the potions / runes / ammunition in the inventory are counted every cfg.thinkMs; fewer than the last
--               count = used (not counted in a protection zone, so the depot and NPCs do not count as used)
--   damage      healthchange on what the character attacks (registered from onTargetCombat), capped at the target's
--               health; summons count for their master
--   healing     healthchange on the character itself, healing capped at the missing health
-- Sessions live in memory, by character, and survive a relog within cfg.keepOfflineMinutes (not a server restart).
--
-- Protocol (JSON {action, data}):
--   client -> server  open | close | get | pause | resume | reset
--   server -> client  state {open = 1 (show the window) | nil, t, p, xp, xph, lvl, left, ttl, lv, lvh, sv, svh, pf,
--                     pfh, dmg, dps, heal, hps, kc, k = [[name, n]], l = [[clientId, n, gold, name, rarity, unique,
--                     orb]], s = [[clientId, n, gold, name]], x = [[clientId, n, name, rarity, unique, orb]]}
--   (see hunt_core.lua H.state). While the window is open the server sends a state every cfg.thinkMs.
-- Lua 5.1 / LuaJIT compatible.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/hunt_core.lua")

Chaos.huntConfig = dofile("data/scripts/chaos/hunt_config.lua")
local cfg = Chaos.huntConfig
local H = ChaosHunt
local OPCODE = ChaosOpcodes.hunt or 241
local PRICES = (ChaosAutoSell and ChaosAutoSell.prices) or dofile("data/scripts/chaos/sell_prices.lua")
local SUPPLIES = dofile("data/scripts/chaos/hunt_supplies.lua")

H.sessions = H.sessions or {} -- guid -> session (kept over /reload)
H.watch = H.watch or {} -- player id -> true while the window is open

local ORBS = {}
for _, id in ipairs(cfg.orbIds or {}) do
	ORBS[id] = true
end

local function unit(id)
	return H.unitValue(id, PRICES, cfg.coins, cfg.extraValues)
end

local function sessionOf(player)
	local s = H.sessions[player:getGuid()]
	if s and s.online then
		return s
	end
	return nil
end

local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and v or nil
end

-- ---------------------------------------------------------------- state push
local function send(player, open)
	local s = H.sessions[player:getGuid()]
	if not s then
		s = H.new(os.time())
		H.sessions[player:getGuid()] = s
	end
	local st = H.state(s, os.time(), {exp = player:getExperience(), level = player:getLevel(),
		minRateSeconds = cfg.minRateSeconds, maxKills = cfg.maxKills, maxLoot = cfg.maxLoot,
		maxSupplies = cfg.maxSupplies, maxSpecials = cfg.maxSpecials})
	if open then
		st.open = 1
	end
	if ChaosDisplayScale and ChaosDisplayScale.apply then -- the viewer's display scale: damage, DPS, healing
		st = ChaosDisplayScale.apply("huntState", player, st)
	end
	Chaos.send(player, OPCODE, "state", st)
end
H.send = send

-- ---------------------------------------------------------------- experience
local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	local s = sessionOf(player)
	if s then
		H.addExp(s, exp)
	end
	return exp
end
xp:register(cfg.expIndex)

-- ---------------------------------------------------------------- kills
local kill = CreatureEvent("ChaosHuntKill")
function kill.onKill(player, target)
	if not player:isPlayer() or not target or not target:isMonster() or target:getMaster() then
		return true
	end
	local s = sessionOf(player)
	if s then
		H.addKill(s, target:getName()) -- the name the player saw (a rift monster's rift name)
	end
	return true
end
kill:register()

-- ---------------------------------------------------------------- loot
local function readCorpse(corpse, out, depth)
	for _, item in ipairs(corpse:getItems() or {}) do
		local itemType = item:getType()
		if item:isContainer() and depth < 2 then
			readCorpse(item, out, depth + 1)
		end
		local id = item:getId()
		local rarity = ChaosRarity.canon(customAttr(item, "rarity")) -- a stored id; an old 6 .. 15 is the rarity it became
		if rarity == ChaosRarity.UNIQUE then
			rarity = 0
		end
		local unique = customAttr(item, "chaos_unique") ~= nil
		local name = item:getName()
		local lname = (name or ""):lower()
		local orb = ORBS[id] or (not unique and rarity == 0 and itemType:isStackable()
			and (lname:find("%f[%a]orb$") or lname:find("^orb of ")) and true) or false
		local key = H.itemKey(id, rarity, unique)
		local e = out[key]
		if e then
			e.n = e.n + item:getCount()
		else
			out[key] = {id = id, cid = itemType:getClientId(), name = name, n = item:getCount(), r = rarity, u = unique,
				o = orb}
		end
	end
	return out
end

local first -- {monster id, corpse read} of the corpse being dropped (the callbacks of one corpse run back to back)

local function ownerSession(corpse)
	if not corpse or not corpse:getType():isContainer() then
		return nil
	end
	local owner = Player(corpse:getCorpseOwner())
	return owner and sessionOf(owner), owner
end

local before = EventCallback
before.onDropLoot = function(monster, corpse)
	first = nil
	local ok, err = pcall(function()
		if ownerSession(corpse) then
			first = {mid = monster:getId(), items = readCorpse(corpse, {}, 0)}
		end
	end)
	if not ok then
		print("[Chaos hunt] loot (before) failed: " .. tostring(err))
	end
end
before:register(cfg.lootBeforeIndex)

local after = EventCallback
after.onDropLoot = function(monster, corpse)
	local ok, err = pcall(function()
		local s = ownerSession(corpse)
		if not s then
			return
		end
		local items = readCorpse(corpse, {}, 0)
		if first and first.mid == monster:getId() then
			items = H.mergeMax(first.items, items)
		end
		H.addLoot(s, items, unit)
	end)
	first = nil
	if not ok then
		print("[Chaos hunt] loot (after) failed: " .. tostring(err))
	end
end
after:register(cfg.lootAfterIndex)

-- ---------------------------------------------------------------- supplies
local typeInfo = {} -- id -> {stack, charges, cid, name}
local function supplyType(id)
	local t = typeInfo[id]
	if not t then
		local it = ItemType(id)
		t = {stack = it:isStackable(), charges = it:getCharges() or 0, cid = it:getClientId(), name = it:getName()}
		typeInfo[id] = t
	end
	return t
end

local function units(item, t)
	if t.stack then
		return item:getCount()
	end
	if t.charges > 0 then
		return math.max(0, item:getCharges())
	end
	return 1
end

local function countInto(item, out, depth)
	local id = item:getId()
	if SUPPLIES[id] then
		out[id] = (out[id] or 0) + units(item, supplyType(id))
	end
	if depth < 8 and item:isContainer() then
		for _, child in ipairs(item:getItems() or {}) do
			countInto(child, out, depth + 1)
		end
	end
end

local function countSupplies(player)
	local out = {}
	for slot = CONST_SLOT_HEAD, CONST_SLOT_AMMO do
		local item = player:getSlotItem(slot)
		if item then
			countInto(item, out, 0)
		end
	end
	return out
end

local function checkSupplies(player, s)
	local tile = not cfg.countSuppliesInPz and Tile(player:getPosition())
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		s.inv = nil
		return
	end
	local cur = countSupplies(player)
	for id, n in pairs(H.supplyUsed(s.inv, cur)) do
		local t = supplyType(id)
		local price = SUPPLIES[id]
		if not t.stack and t.charges > 1 then
			price = price / t.charges -- runes sold with their charges: the price of one charge
		end
		H.addSupply(s, id, n, price, t.cid, t.name)
	end
	s.inv = cur
end

-- ---------------------------------------------------------------- damage and healing
local function huntOwner(attacker)
	if not attacker then
		return nil
	end
	if attacker:isPlayer() then
		return attacker
	end
	local master = attacker:getMaster()
	return master and master:isPlayer() and master or nil
end

local dmg = CreatureEvent("ChaosHuntDamage")
function dmg.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING then
		local player = huntOwner(attacker)
		local s = player and sessionOf(player)
		if s then
			local total = math.abs(primaryDamage or 0) + math.abs(secondaryDamage or 0)
			H.addDamage(s, math.min(total, creature:getHealth()))
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dmg:register()

local heal = CreatureEvent("ChaosHuntHeal")
function heal.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING and creature:isPlayer() then
		local s = sessionOf(creature)
		if s then
			H.addHealing(s, math.min(math.abs(primaryDamage or 0), creature:getMaxHealth() - creature:getHealth()))
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
heal:register()

-- Chaos.registerOnce / eventKnown (chaos_constants.lua): register on a monster once, not at every hit
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local function eventKnown(creature, name)
	local f = Chaos and Chaos.eventKnown
	return f ~= nil and f(creature, name)
end
local target = EventCallback
target.onTargetCombat = function(creature, victim)
	if creature and victim and victim:isMonster() and not eventKnown(victim, "ChaosHuntDamage") and huntOwner(creature) then
		registerOnce(victim, "ChaosHuntDamage")
	end
	return RETURNVALUE_NOERROR
end
target:register(cfg.targetIndex)

-- ---------------------------------------------------------------- tick: supplies, window refresh, cleanup
-- every character is looked at once per thinkMs, spread over SLICES shorter ticks by creature id: the supply count walks
-- the whole inventory, and every online character has a session (autoStart), so one pass over all of them in one tick
-- made a lag spike under load
local SLICES = 4
local slice = 0
local think = GlobalEvent("ChaosHuntThink")
function think.onThink(interval)
	local now = os.time()
	slice = (slice + 1) % SLICES
	for _, player in ipairs(Game.getPlayers()) do
		local id = player:getId()
		if id % SLICES == slice then
			local s = sessionOf(player)
			if s and H.running(s) then
				local ok, err = pcall(checkSupplies, player, s)
				if not ok then
					print("[Chaos hunt] supplies failed: " .. tostring(err))
				end
			end
			if H.watch[id] then
				send(player, false)
			end
		end
	end
	if slice == 0 then
		H.sweep(H.sessions, now, (cfg.keepOfflineMinutes or 30) * 60)
	end
	return true
end
think:interval(math.max(100, math.floor((cfg.thinkMs or 2000) / SLICES)))
think:register()

-- ---------------------------------------------------------------- login / logout / opcode
local login = CreatureEvent("ChaosHuntLogin")
function login.onLogin(player)
	player:registerEvent("ChaosHuntExtended")
	player:registerEvent("ChaosHuntLogout")
	player:registerEvent("ChaosHuntKill")
	player:registerEvent("ChaosHuntHeal")
	local guid, now = player:getGuid(), os.time()
	local s = H.sessions[guid]
	if s then
		H.setOnline(s, true, now)
	elseif cfg.autoStart then
		H.sessions[guid] = H.new(now)
	else
		s = H.new(now)
		H.pause(s, now)
		H.sessions[guid] = s
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosHuntLogout")
function logout.onLogout(player)
	local s = H.sessions[player:getGuid()]
	if s then
		H.setOnline(s, false, os.time())
	end
	H.watch[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local function act(player, action)
	local s = H.sessions[player:getGuid()]
	local now = os.time()
	if not s then
		s = H.new(now)
		H.sessions[player:getGuid()] = s
	end
	if action == "pause" then
		H.pause(s, now)
	elseif action == "resume" then
		H.resume(s, now)
	elseif action == "reset" then
		H.reset(s, now)
		-- the DPS meter's session follows the hunt session (combatlog.lua)
		if ChaosCombatLog and ChaosCombatLog.onHuntReset then
			pcall(ChaosCombatLog.onHuntReset, player)
		end
	end
end

local ext = CreatureEvent("ChaosHuntExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	-- per action (ratelimit.lua): requests that hit the database cannot be flooded
	if Chaos.limited and Chaos.limited(player, "hunt." .. tostring(msg.action), 300) then
		return
	end
	local action = msg.action
	if action == "open" then
		H.watch[player:getId()] = true
		send(player, true)
	elseif action == "close" then
		H.watch[player:getId()] = nil
	elseif action == "get" then
		send(player, false)
	elseif action == "pause" or action == "resume" or action == "reset" then
		act(player, action)
		send(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

