-- Veiled modifiers, the engine side (the rules are data/lib/chaos_veiled.lua, the numbers chaos_veiled_config.lua;
-- server/README.md "Veiled modifiers"):
--   * drops: loot.lua hands every corpse to ChaosVeiled.onCorpse (rare and better gear of a kill in high content may roll
--     a veiled slot; the Orb of Unveiling may drop); rift.lua (chest), raid.lua (boss rewards) and uber.lua (Ascended
--     spoils) hand their gear to ChaosVeiled.rollReward. The source comes from the killer's runs (ChaosVeiled.contextOf).
--   * the Unveil window: the Orb of Unveiling used on a veiled item (use-with, or the crafting bench) does not apply at
--     once: crafting.lua calls orb.dialog, which rolls (once, then kept on the item) and sends the three choices; the
--     choice comes back here and runs through the bench's craft() (orb taken, crafting log, community goal).
-- Protocol (extended opcode ChaosOpcodes.veiled = 196, JSON {action, data}):
--   server -> client  open {path, id, clientId, name, rarity, rarityName, level, sig, orbs, offers = [{i, key, name, text,
--                     tier, tn, lo, hi, value, hook}]} | result {ok, text, veil = {s, n, t, tr, tn, lo, hi, h}}
--   client -> server  choose {path, id, sig, choice} | close
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua") -- loads chaos_veiled.lua
end

local V, C, M = ChaosVeiled, ChaosCrafting, ChaosItemMods
local OPCODE = ChaosOpcodes.veiled or 196

-- ---------------------------------------------------------------- sources
-- the content a player is in: {riftTier, omen, raid, ascended, descentDepth} (ChaosVeiled.sourceOf picks the source)
function V.contextOf(player)
	local ctx = {}
	if not player then
		return ctx
	end
	local pid = player:getId()
	local run = ChaosRift and ChaosRift.runOf and ChaosRift.runOf[pid]
	if run and run.key then
		ctx.riftTier = tonumber(run.key.tier) or 0
		ctx.omen = run.omen ~= nil
	end
	if ChaosRaid and ChaosRaid.runOf and ChaosRaid.runOf[pid] then
		ctx.raid = true
	end
	if ChaosAscended and ChaosAscended.runOf and ChaosAscended.runOf[pid] then
		ctx.ascended = true
	end
	local d = ChaosDescent and ChaosDescent.runOf and ChaosDescent.runOf[pid]
	if d then
		ctx.descentDepth = tonumber(d.depth or d.idx) or 0
	end
	return ctx
end

-- a gear reward made by a script (rift chest, raid boss, Ascended spoils): maybe a veiled slot. ctx as V.sourceOf.
function V.rollReward(item, ctx)
	if item and V.rollItem(item, ctx) then
		C.rewriteDescription(item)
		return true
	end
	return false
end

-- a kill's corpse (loot.lua, after the gear is forged): veiled slots on the rare and better gear, and the orb. Returns
-- the texts for the bonus loot line.
function V.onCorpse(corpse, monster, owner, tier)
	local ctx = V.contextOf(owner)
	if not V.sourceOf(ctx) then
		return {}
	end
	local out = {}
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item and item:isItem() and V.rollItem(item, ctx) then
			C.rewriteDescription(item)
			out[#out + 1] = "Veiled " .. C.itemName(item)
		end
	end
	local t = tier or "normal"
	local mt = monster and monster:getType()
	local okB, boss = pcall(function() return mt and mt:isBoss() end)
	if okB and boss then
		t = "boss"
	end
	if V.orbId and V.rollOrb(ctx, t) and corpse:addItem(V.orbId, 1) then
		out[#out + 1] = C.orbByKey[V.config.orbKey].name
	end
	return out
end

-- ---------------------------------------------------------------- the Unveil window
local function result(player, ok, text, item)
	local veil = ok and item and V.tooltip(item) or nil
	if veil then
		veil.st = nil
	end
	Chaos.send(player, OPCODE, "result", {ok = ok and true or false, text = text, veil = veil})
end

-- orb.dialog (crafting.lua craft): roll or read the three choices and open the window. Returns ok, text, item.
local function openDialog(player, item)
	local list = V.offers(item)
	if not list then
		return false, C.reasons.notVeiled
	end
	local bench = ChaosCraftingBench
	local path = bench and bench.pathOf(player, item)
	if not path then
		return false, "Put the item in your backpack first (equipped items cannot be crafted)."
	end
	local it = ItemType(item:getId())
	local rarity = C.rarityOf(item)
	Chaos.send(player, OPCODE, "open", {path = path, id = item:getId(), clientId = it and it:getClientId() or 0,
		name = C.itemName(item), rarity = rarity, rarityName = rarity > 0 and C.rarityName(rarity) or nil,
		level = M.itemLevelOf(item), sig = V.signature(item), orbs = player:getItemCount(V.orbId),
		offers = V.offerView(list)})
	return true, "Choose one of the three veiled modifiers in the Unveil window.", item
end
local orb = C.orbByKey[V.config.orbKey]
if orb then
	orb.dialog = openDialog
end

local function choose(player, data)
	local bench = ChaosCraftingBench
	if not bench or not bench.craft then
		return result(player, false, "The crafting bench is not available.")
	end
	local item = type(data.path) == "string" and #data.path <= 32 and bench.itemAt(player, data.path) or nil
	local id = Chaos.toInt(data.id, 1, 65535)
	if not item or item:getId() ~= id or type(data.sig) ~= "string" or data.sig ~= V.signature(item) then
		return result(player, false, "The item moved or changed. Use the orb on it again.")
	end
	local n = Chaos.toInt(data.choice, 1, V.config.offers)
	if not n then
		return result(player, false, C.reasons.badChoice)
	end
	local ok, text = bench.craft(player, V.config.orbKey, item, nil, {choice = n})
	result(player, ok, text, ok and item or nil)
	if ok then
		bench.sendState(player, false) -- an open bench shows the new counts and the item's new state
	end
end

local ext = CreatureEvent("ChaosVeiledExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or (ChaosRateLimit and not ChaosRateLimit.allow(player, "veiled", 300)) then
		return
	end
	if msg.action == "choose" then
		choose(player, type(msg.data) == "table" and msg.data or {})
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosVeiledLogin")
function login.onLogin(player)
	player:registerEvent("ChaosVeiledExtended")
	return true
end
login:type("login")
login:register()
