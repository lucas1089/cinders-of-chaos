-- Store pouches: pure rules (no engine calls), shared by pouches.lua and server/tests/pouches_test.lua.
--   ChaosPouchesCore.kindOfId(cfg, id)              "loot" | "orbs" | "keys" | "gems" for a pouch item id, else nil
--   ChaosPouchesCore.defaults(cfg)                  the Loot Bag rules of a character that never set them
--   ChaosPouchesCore.packRules(r) / unpackRules(cfg, v)   rules <-> one int32 storage value (unset = defaults)
--   ChaosPouchesCore.sanitizeRules(cfg, t)          rules from client input (booleans, minRarity 1..15)
--   ChaosPouchesCore.sets(cfg, extraOrbIds)         {orbs = set, omens = set, coins = set} of item ids
--   ChaosPouchesCore.wants(kind, info, rules, sets, cfg)   true when that pouch collects the corpse item
--   ChaosPouchesCore.specialistOf(info, sets, cfg)  the first specialist pouch (cfg.priority: gems, orbs, keys) whose kind it is
--   ChaosPouchesCore.plan(info, rules, sets, cfg, carried)   the carried pouches to try, in order, and the overflow kind
--   ChaosPouchesCore.route(info, rules, sets, cfg)  plan() with every pouch carried: the kinds, in order
--   ChaosPouchesCore.rank(rarity, unique)           the sort rank of an item of the Loot Bag (uniques above every rarity)
--   ChaosPouchesCore.sortPlan(ranks, limit)         which items of a bag to move to the front, in order, to sort it by rarity
--   ChaosPouchesCore.moveRefusal(m)                 nil (allowed) or the reason a pouch move is refused
--   ChaosPouchesCore.lootBagInRefusal(m)            nil (allowed) or the reason an item may not go INTO a Loot Bag (one-way bag)
--   ChaosPouchesCore.summary(cfg, looted, backpack, left, full, overflow, t)   the per-kill loot line, or nil
--   ChaosPouchesCore.lootList(looted, opts, t)   "10 gold coins, {[Rare] wyrmscale helmet} and 2 more"
--   ChaosPouchesCore.bindLock(cfg) / needsRebind(cfg, value)   the chaos_locked value of a pouch; must it change to it?
--   (t(pattern, ...): the player's language, e.g. Chaos.t bound to the owner; default English, P.english)
-- info = {id, actionId, count, category = "equipment"|"currency"|"supplies"|"other", rarity = 0..15, unique = bool,
--         gem = bool, container = bool, pouch = bool (a pouch itself), onList = bool (on the base autoloot list)}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

ChaosPouchesCore = ChaosPouchesCore or {}
local P = ChaosPouchesCore

P.MAX_RARITY = 15 -- the highest id a saved rule can hold (4 bits); minRarity is a stored id of ChaosRarity (1, 2, 3, 4, 5, 10)

-- a minRarity as a stored id, at least 1 (an old rule saved with one of the 15 ids means the rarity it became)
local function minId(v)
	local c = ChaosRarity.canon(v)
	return (c == 0 or c == ChaosRarity.UNIQUE) and 1 or c
end
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
	return v + minId(r.minRarity) * RARITY_UNIT
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
	r.minRarity = minId(math.floor(v / RARITY_UNIT) % 16)
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
	r.minRarity = minId(math.floor(tonumber(t.minRarity) or d.minRarity))
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
	elseif kind == "gems" then
		return info.gem == true
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
			-- minRarity 1 (the lowest) = every piece of gear, plain ones too (the Loot Bag takes all the loot)
			return rules.gear and (rules.minRarity <= 1 or (tonumber(info.rarity) or 0) >= rules.minRarity)
		elseif cat == "supplies" then
			return rules.supplies
		end
		-- "other" and anything the loot filter has no category for: the Loot Bag takes everything else too
		return rules.other
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
-- specialist kind when the Loot Bag is in the list only as its overflow (else nil).
--   1. An item of a specialist kind (gems / orbs, rune shards, gems / Rift Keys, omen items) goes to the first CARRIED
--      pouch of cfg.priority that wants it, always, whatever the Loot Bag rules say (its "gems" rule, the autoloot
--      list). A gem is wanted by both the Gem Pouch and the Orbs Pouch, and the Gem Pouch comes first: with one
--      carried, the Orbs Pouch never gets a gem (they do not mix); without one the Orbs Pouch takes gems as before.
--   2. That pouch full: the Loot Bag takes it only with its "overflow" rule (default on); else the caller passes it
--      to the backpack, then leaves it in the corpse. A full Gem Pouch does not pass gems to the Orbs Pouch.
--   3. No specialist pouch carried for it: the Loot Bag rules decide as for any item (gems rule, autoloot list).
function P.plan(info, rules, sets, cfg, carried)
	carried = carried or {}
	rules = rules or P.defaults(cfg)
	local out = {}
	local spec
	for _, kind in ipairs(cfg.priority) do
		if carried[kind] and P.wants(kind, info, nil, sets, cfg) then
			spec = kind
			break
		end
	end
	if spec then
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

-- ---------------------------------------------------------------- Loot Bag order (rarest first)
-- rank of one item: uniques above everything, then the rarity (0 = plain). Higher = nearer the front.
function P.rank(rarity, unique)
	return (unique and 100 or 0) + ChaosRarity.rank(rarity)
end

-- The engine adds an item at the FRONT of a container, so a bag is sorted by moving items to the front, last of the
-- wanted order first. ranks = the rank of every item in the bag's current order (index 1 = the front). Ties keep the
-- current order (stable), so a new plain item in front of plain items does not move. The items that already sit in
-- the wanted order at the back are left alone: only the items ahead of that tail move. Returns the indices (into
-- `ranks`) to move to the front, in the order to move them; at most `limit` of them (the rest at the next call, the
-- bag then is sorted in part and every call only gets closer). An empty list = already sorted. Pure, O(n log n).
function P.sortPlan(ranks, limit)
	local n = #ranks
	local want = {}
	for i = 1, n do
		want[i] = i
	end
	table.sort(want, function(a, b)
		local ra, rb = tonumber(ranks[a]) or 0, tonumber(ranks[b]) or 0
		if ra ~= rb then
			return ra > rb
		end
		return a < b
	end)
	local keep = 0 -- the length of the tail of `want` that is also in current order
	if n > 0 then
		keep = 1
		while keep < n and want[n - keep] < want[n - keep + 1] do
			keep = keep + 1
		end
	end
	local moves = {}
	local max = tonumber(limit) or n
	for k = n - keep, 1, -1 do
		if #moves >= max then
			break
		end
		moves[#moves + 1] = want[k]
	end
	return moves
end

P.LOOT_BAG_STAYS = "The Loot Bag stays in your purse: it cannot be moved out, dropped, traded or mailed."

-- m = {holdsPouch = bool (the moved item is a pouch or holds one),
--      lootBag = bool (the moved item is the Loot Bag), inPurse = bool (it lies in the purse now),
--      toGround = bool (a map tile: the ground, a mailbox, a trash holder), chain = the destination and its parents,
--      innermost first: "self" (the mover), "player" (another one), "depot", "pouch", "item", "tile"}
function P.moveRefusal(m)
	if not m.holdsPouch then
		return nil
	end
	-- the Loot Bag lives in the purse (owner 2026-10-17): from there it goes nowhere but back into the purse
	if m.lootBag and m.inPurse then
		local toPurse = false
		for _, c in ipairs(m.chain or {}) do
			if c == "purse" then
				toPurse = true
				break
			end
		end
		if m.toGround or not toPurse then
			return P.LOOT_BAG_STAYS
		end
		return nil
	end
	if m.toGround then
		return "Store items stay with you: they cannot be dropped, mailed or thrown away."
	end
	for _, c in ipairs(m.chain or {}) do
		if c == "pouch" then
			return "A pouch cannot go into another pouch."
		elseif c == "self" or c == "depot" or c == "purse" then
			return nil
		elseif c == "player" or c == "tile" then
			break
		end
	end
	return "Store items stay with you: keep them in your backpack or your depot."
end

-- The Loot Bag only gives items back (owner 2026-10-29: "nao aceite itens de fora, nao aceite colocar itens, so tirar").
-- Autoloot fills it from script (pouches.lua), never through a player's move. m = {intoLootBag = bool (the destination is a
-- Loot Bag or lies anywhere inside one), sameBag = bool (the moved item already lies in that very Loot Bag)}.
-- A move within the same Loot Bag (to another slot or into a bag inside it) stays allowed: nothing enters from outside.
P.LOOT_BAG_ONE_WAY = "The Loot Bag only gives items back: autoloot fills it."
function P.lootBagInRefusal(m)
	if m and m.intoLootBag and not m.sameBag then
		return P.LOOT_BAG_ONE_WAY
	end
	return nil
end

-- the loot line's item list. looted = the items taken this kill, in corpse order: {id, name, plural, count, rarity,
-- rarityName, unique}. Same item (id, rarity, unique) grouped and counted; uniques and rarity gear first (highest first),
-- then the rest in corpse order; at most opts.maxEntries (5), then "and N more". Returns the text or nil.
-- English text of a pattern (the default translator of lootList / summary)
function P.english(pattern, ...)
	if select("#", ...) == 0 then
		return pattern
	end
	return string.format(pattern, ...)
end

function P.lootList(looted, opts, t)
	opts = opts or {}
	local maxEntries, flag = opts.maxEntries or 5, opts.flagRarity or 3
	local groups, byKey = {}, {}
	for i, e in ipairs(looted or {}) do
		local rarity = ChaosRarity.rank(e.rarity) -- the place in the order (an old id counts as the rarity it became)
		local key = tostring(e.id) .. ":" .. rarity .. ":" .. (e.unique and 1 or 0)
		local g = byKey[key]
		if not g then
			g = {e = e, rarity = rarity, count = 0, order = i}
			byKey[key] = g
			groups[#groups + 1] = g
		end
		g.count = g.count + math.max(1, tonumber(e.count) or 1)
	end
	if #groups == 0 then
		return nil
	end
	local function rank(g)
		return g.e.unique and 1000 or g.rarity
	end
	table.sort(groups, function(a, b)
		if rank(a) ~= rank(b) then
			return rank(a) > rank(b)
		end
		return a.order < b.order
	end)
	local parts = {}
	for i = 1, math.min(#groups, maxEntries) do
		local g = groups[i]
		local e = g.e
		local name = tostring(e.name or ("item " .. tostring(e.id)))
		if g.count > 1 then
			local plural = e.plural ~= nil and e.plural ~= "" and e.plural or name
			name = g.count .. " " .. plural
		end
		if g.rarity > 0 and e.rarityName then
			name = "[" .. e.rarityName .. "] " .. name
		end
		if e.unique or g.rarity >= ChaosRarity.rank(flag) then
			name = "{" .. name .. "}"
		end
		parts[#parts + 1] = name
	end
	local text = table.concat(parts, ", ")
	if #groups > maxEntries then
		text = text .. (t or P.english)(" and %d more", #groups - maxEntries)
	end
	return text
end

-- the per-kill line: "Looted: <P.lootList> (<notes>)." looted = the items the pouch step took (into a pouch or the
-- backpack), backpack = n (wanted by a pouch, went to the backpack), left = n (no room anywhere), full = {[kind] =
-- true} (say the pouch is full), overflow = n (items a full specialist pouch passed to the Loot Bag). The pouch names
-- stay out of the list; they appear only in the short notes. nil when nothing happened.
function P.summary(cfg, looted, backpack, left, full, overflow, t)
	t = t or P.english
	local list = P.lootList(looted, cfg.lootLine, t)
	local notes = {}
	for _, kind in ipairs(cfg.order) do
		if full and full[kind] then
			notes[#notes + 1] = t("%s is full", cfg.kinds[kind].title)
		end
	end
	if (overflow or 0) > 0 then
		notes[#notes + 1] = t("%d to your %s", overflow, cfg.kinds.loot.title)
	end
	if backpack > 0 then
		notes[#notes + 1] = t("%d to your backpack", backpack)
	end
	if left > 0 then
		notes[#notes + 1] = t("%d left in the corpse, no room", left)
	end
	if not list and #notes == 0 then
		return nil
	end
	local text = t("Looted: %s", list or t("nothing"))
	if #notes > 0 then
		text = text .. " (" .. table.concat(notes, "; ") .. ")"
	end
	return text .. "."
end

-- the chaos_locked value a pouch carries (cfg.bindLock: locked, drawn in its colours), and whether an item's current
-- value must change to it (a pouch given before 2026-10-22 carries 1, the grey player lock)
function P.bindLock(cfg)
	return cfg.bindLock or 1
end

function P.needsRebind(cfg, value)
	return tonumber(value) ~= P.bindLock(cfg)
end

return P
