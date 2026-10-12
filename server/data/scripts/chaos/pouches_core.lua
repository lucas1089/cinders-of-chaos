-- Store pouches: pure rules (no engine calls), shared by pouches.lua and server/tests/pouches_test.lua.
--   ChaosPouchesCore.kindOfId(cfg, id)              "loot" | "orbs" | "keys" for a pouch item id, else nil
--   ChaosPouchesCore.defaults(cfg)                  the Loot Pouch rules of a character that never set them
--   ChaosPouchesCore.packRules(r) / unpackRules(cfg, v)   rules <-> one int32 storage value (unset = defaults)
--   ChaosPouchesCore.sanitizeRules(cfg, t)          rules from client input (booleans, minRarity 1..15)
--   ChaosPouchesCore.sets(cfg, extraOrbIds)         {orbs = set, omens = set, coins = set} of item ids
--   ChaosPouchesCore.wants(kind, info, rules, sets, cfg)   true when that pouch collects the corpse item
--   ChaosPouchesCore.specialistOf(info, sets, cfg)  the first specialist pouch (cfg.priority: orbs, keys) whose kind it is
--   ChaosPouchesCore.plan(info, rules, sets, cfg, carried)   the carried pouches to try, in order, and the overflow kind
--   ChaosPouchesCore.route(info, rules, sets, cfg)  plan() with every pouch carried: the kinds, in order
--   ChaosPouchesCore.moveRefusal(m)                 nil (allowed) or the reason a pouch move is refused
--   ChaosPouchesCore.summary(cfg, taken, backpack, left)   the per-kill chat line, or nil
-- info = {id, actionId, count, category = "equipment"|"currency"|"supplies"|"other", rarity = 0..15, unique = bool,
--         gem = bool, container = bool, pouch = bool (a pouch itself), onList = bool (on the base autoloot list)}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosPouchesCore = ChaosPouchesCore or {}
local P = ChaosPouchesCore

P.MAX_RARITY = 15
P.FLAGS = {list = 1, gold = 2, uniques = 4, gear = 8, supplies = 16, gems = 32, other = 64, overflow = 128}
P.FLAG_ORDER = {"list", "gold", "uniques", "gear", "supplies", "gems", "other", "overflow"}
-- stored inverted (bit set = off), so rules saved before the overflow rule existed read it as on (its default)
local INVERTED = {overflow = true}
local SET_MARK = 32768 -- a stored value always has it (0 = everything off is a valid choice)
local RARITY_UNIT = 256

local function hasBit(v, b)
	return math.floor(v / b) % 2 == 1
end

function P.kindOfId(cfg, id)
	for kind, k in pairs(cfg.kinds) do
		if k.id == id then
			return kind
		end
	end
	return nil
end

function P.defaults(cfg)
	local d = cfg.lootDefaults or {}
	local r = {minRarity = tonumber(d.minRarity) or 5}
	for _, k in ipairs(P.FLAG_ORDER) do
		r[k] = d[k] and true or false
	end
	return r
end

function P.packRules(r)
	local v = SET_MARK
	for _, k in ipairs(P.FLAG_ORDER) do
		if (r[k] and true or false) ~= (INVERTED[k] or false) then
			v = v + P.FLAGS[k]
		end
	end
	local m = math.max(1, math.min(P.MAX_RARITY, math.floor(tonumber(r.minRarity) or 1)))
	return v + m * RARITY_UNIT
end

function P.unpackRules(cfg, v)
	v = tonumber(v) or -1
	if v < SET_MARK then
		return P.defaults(cfg)
	end
	local r = {}
	for _, k in ipairs(P.FLAG_ORDER) do
		r[k] = hasBit(v, P.FLAGS[k]) ~= (INVERTED[k] or false)
	end
	r.minRarity = math.floor(v / RARITY_UNIT) % 16
	if r.minRarity < 1 then
		r.minRarity = 1
	end
	return r
end

function P.sanitizeRules(cfg, t)
	local d = P.defaults(cfg)
	if type(t) ~= "table" then
		return d
	end
	local r = {}
	for _, k in ipairs(P.FLAG_ORDER) do
		if t[k] == nil then
			r[k] = d[k]
		else
			r[k] = t[k] == true or t[k] == 1
		end
	end
	local m = math.floor(tonumber(t.minRarity) or d.minRarity)
	r.minRarity = math.max(1, math.min(P.MAX_RARITY, m))
	return r
end

local function toSet(list, set)
	set = set or {}
	for _, id in ipairs(list or {}) do
		set[id] = true
	end
	return set
end

function P.sets(cfg, extraOrbIds)
	return {orbs = toSet(extraOrbIds, toSet(cfg.orbIds)), omens = toSet(cfg.omenIds), coins = toSet(cfg.coinIds)}
end

function P.isRiftKey(info, cfg)
	return info.id == cfg.riftKey.itemId and info.actionId == cfg.riftKey.actionId
end

function P.wants(kind, info, rules, sets, cfg)
	if info.pouch or info.container then
		return false -- a pouch never collects a container (or another pouch)
	end
	if kind == "keys" then
		return P.isRiftKey(info, cfg) or sets.omens[info.id] == true
	elseif kind == "orbs" then
		return sets.orbs[info.id] == true or (cfg.orbGems and info.gem == true) or false
	elseif kind == "loot" then
		rules = rules or P.defaults(cfg)
		if rules.list and info.onList then
			return true
		end
		if P.isRiftKey(info, cfg) or sets.omens[info.id] or sets.orbs[info.id] then
			return false -- the other pouches' items come here only from the autoloot list
		end
		if sets.coins[info.id] then
			return rules.gold
		end
		if info.unique then
			return rules.uniques
		end
		if info.gem then
			return rules.gems
		end
		local cat = info.category
		if cat == "equipment" then
			return rules.gear and (tonumber(info.rarity) or 0) >= rules.minRarity
		elseif cat == "supplies" then
			return rules.supplies
		elseif cat == "other" then
			return rules.other
		end
		return false
	end
	return false
end

-- the specialist pouch (Orbs Pouch, Rift Key Pouch: cfg.priority, in that order) whose kind the item is, else nil
function P.specialistOf(info, sets, cfg)
	for _, kind in ipairs(cfg.priority) do
		if P.wants(kind, info, nil, sets, cfg) then
			return kind
		end
	end
	return nil
end

-- carried = {[kind] = truthy} for the pouches the character carries. Returns the kinds to try, in order, and the
-- specialist kind when the Loot Pouch is in the list only as its overflow (else nil).
--   1. An item of a specialist kind (orbs, rune shards, gems / Rift Keys, omen items) goes to that pouch first, always,
--      whatever the Loot Pouch rules say (its "gems" rule, the autoloot list).
--   2. That pouch full: the Loot Pouch takes it only with its "overflow" rule (default on); else the caller passes it
--      to the backpack, then leaves it in the corpse.
--   3. No specialist pouch carried for it: the Loot Pouch rules decide as for any item (gems rule, autoloot list).
function P.plan(info, rules, sets, cfg, carried)
	carried = carried or {}
	rules = rules or P.defaults(cfg)
	local out = {}
	local spec = P.specialistOf(info, sets, cfg)
	if spec and carried[spec] then
		out[1] = spec
		if rules.overflow and carried.loot then
			out[2] = "loot"
			return out, spec
		end
		return out, nil
	end
	if carried.loot and P.wants("loot", info, rules, sets, cfg) then
		out[1] = "loot"
	end
	return out, nil
end

function P.route(info, rules, sets, cfg)
	local all = {}
	for kind in pairs(cfg.kinds) do
		all[kind] = true
	end
	return (P.plan(info, rules, sets, cfg, all))
end

-- m = {holdsPouch = bool (the moved item is a pouch or holds one),
--      toGround = bool (a map tile: the ground, a mailbox, a trash holder), chain = the destination and its parents,
--      innermost first: "self" (the mover), "player" (another one), "depot", "pouch", "item", "tile"}
function P.moveRefusal(m)
	if not m.holdsPouch then
		return nil
	end
	if m.toGround then
		return "Store pouches stay with you: they cannot be dropped, mailed or thrown away."
	end
	for _, c in ipairs(m.chain or {}) do
		if c == "pouch" then
			return "A pouch cannot go into another pouch."
		elseif c == "self" or c == "depot" then
			return nil
		elseif c == "player" or c == "tile" then
			break
		end
	end
	return "Store pouches stay with you: keep them in your backpack or your depot."
end

-- taken = {[kind] = n}, backpack = n (wanted by a pouch, went to the backpack), left = n (no room anywhere),
-- full = {[kind] = true} (say the pouch is full), overflow = n (of the Loot Pouch's count: items a full specialist
-- pouch passed to it)
function P.summary(cfg, taken, backpack, left, full, overflow)
	local parts = {}
	for _, kind in ipairs(cfg.order) do
		local n = taken[kind] or 0
		if n > 0 then
			parts[#parts + 1] = string.format("%s +%d", cfg.kinds[kind].title, n)
		end
	end
	local notes = {}
	for _, kind in ipairs(cfg.order) do
		if full and full[kind] then
			notes[#notes + 1] = cfg.kinds[kind].title .. " is full"
		end
	end
	if (overflow or 0) > 0 then
		notes[#notes + 1] = overflow .. " to your " .. cfg.kinds.loot.title
	end
	if backpack > 0 then
		notes[#notes + 1] = backpack .. " to your backpack"
	end
	if left > 0 then
		notes[#notes + 1] = left .. " left in the corpse, no room"
	end
	if #parts == 0 and #notes == 0 then
		return nil
	end
	local text = "Pouches: " .. (#parts > 0 and table.concat(parts, ", ") or "nothing")
	if #notes > 0 then
		text = text .. " (" .. table.concat(notes, "; ") .. ")"
	end
	return text .. "."
end

return P
