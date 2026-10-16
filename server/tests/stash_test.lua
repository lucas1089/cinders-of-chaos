-- Run from the server/ folder: luajit tests/stash_test.lua (and lua5.3; CI runs both)
-- The stash (server/README.md "Stash"):
--   * stash_core.lua with the real stash_config.lua and pact_config.lua: config sanity, item classes (weapons, armour,
--     jewellery, supplies, materials, creature products, orbs, gems, keys, collectibles), tab ownership (free, Chaos
--     Pact, bought, achievements, bought depot tabs), routing (affinity first, spilling into general tabs, full,
--     withdraw-only), the layout (old entries, a newly bought affinity tab, the Old depot tab), plans that fill as they
--     go, the tab bar, the Stow Everything rules and report, the withdraw place
--   * the journal: a deposit and a withdrawal crashed after every single step and recovered from the saved state,
--     failed saves, a failed write after a failed save: never an item lost, never one doubled
--   * item_codec.lua: the blob round trip (every attribute back), the key-list fallback, plain stacks
--   * stash.lua against a mocked engine with an in-memory database: a weapon and gold deposited (one row, one merged
--     stack), withdraw refused outside a protection zone and the exact item back inside one, Stow Everything through
--     nested bags with every skip reason and a tab that fills mid-way, the depot migration (boxes, bags, overflow into
--     the Old depot tab, kept items), rows of the offline tool described and merged, the login recovery, the
--     never-stash list, forged requests (another character's row, a bad count, no item)
--   * the SQL of the store: every number formatted as an integer, every text escaped

local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end
local function has(text, part, label)
	check(type(text) == "string" and text:find(part, 1, true) ~= nil, label .. " (" .. tostring(text) .. ")")
end

-- engine constants (the security test's trick: any other upper-case global is a fresh number)
local n = 1000
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
CONST_SLOT_BACKPACK = 3
WEAPON_AMMO = 7
ITEM_TYPE_KEY = 5
RETURNVALUE_NOERROR = 0
MESSAGE_INFO_DESCR = 22

dofile("data/scripts/chaos/stash_core.lua")
local K = ChaosStashCore
local cfg = dofile("data/scripts/chaos/stash_config.lua")
local pc = dofile("data/scripts/chaos/pact_config.lua")

-- ====================================================================== config
local tabs, keys = {}, {}
for _, a in ipairs(cfg.affinities) do
	check(not tabs[a.tab], "affinity tab id once: " .. a.tab)
	check(not keys[a.key], "affinity key once: " .. a.key)
	tabs[a.tab], keys[a.key] = true, true
	check(a.tab > cfg.maxGeneralTabs and a.tab < cfg.oldDepot.tab, "affinity tab id between the general tabs and Old depot: " .. a.key)
	check(a.size > 0 and type(a.name) == "string" and a.icon, "affinity tab size, name, icon: " .. a.key)
	check(a.free or a.pact or a.extra or a.achievements, "affinity tab has an owner source: " .. a.key)
	if a.extra then
		check(pc.extras[a.extra] ~= nil, "affinity extra is a Pact extra: " .. a.extra)
	end
end
for _, k in ipairs({"orbs", "gems", "keys"}) do
	check(K.affinity(cfg, k) ~= nil, "the old special tab " .. k .. " is an affinity tab")
end
eq(K.affinity(cfg, "orbs").tab, 101, "Orbs keeps tab id 101 (rows of before)")
eq(K.affinity(cfg, "gems").tab, 102, "Gems keeps tab id 102")
eq(K.affinity(cfg, "keys").tab, 103, "Keys keeps tab id 103")
check(pc.limits.stashTabs.free * cfg.tabSize + K.affinity(cfg, "supplies").size >= 496,
	"the free room is at least the old free stash + depot (2 x 48 + 4 x 100)")
eq(K.affinity(cfg, "supplies").free, true, "Supplies is free")
eq(cfg.storage.seq, 7100011, "journal serial storage")
eq(cfg.storage.migrated, 7100012, "migration storage")

-- ====================================================================== classes
local function f(t)
	t.id = t.id or 1
	t.name = t.name or "thing"
	return t
end
local function classes(t)
	return table.concat(K.classify(cfg, f(t)), ",")
end
eq(classes({gear = "weapon", name = "fire sword"}), "weapons", "a sword")
eq(classes({gear = "quiver"}), "weapons", "a quiver")
eq(classes({gear = "armor"}), "armor", "a body armour")
eq(classes({gear = "shield"}), "armor", "a shield")
eq(classes({gear = "boots"}), "armor", "boots")
eq(classes({gear = "jewel", name = "ring of healing"}), "jewels", "a ring")
eq(classes({rune = true, name = "sudden death rune"}), "supplies", "a rune")
eq(classes({fluid = true, name = "great mana potion"}), "supplies", "a potion")
eq(classes({ammo = true, name = "arrow"}), "supplies", "ammunition")
eq(classes({name = "ham"}), "supplies", "food by name")
eq(classes({name = "ham", food = false}), "", "food named but told otherwise")
eq(classes({kind = "orbs", name = "orb of chaos", material = true}), "orbs,materials", "an orb: Orbs first, then Materials")
eq(classes({kind = "gems", name = "flawed ruby"}), "gems", "a gem")
eq(classes({kind = "keys", name = "omen fragment"}), "keys", "an omen fragment")
eq(classes({riftKey = true, name = "shadow orb"}), "keys", "a rift key")
eq(classes({key = true, name = "golden key"}), "keys", "a key")
eq(classes({name = "treasure map"}), "keys", "a map by name")
eq(classes({material = true, name = "bitterroot"}), "materials", "a profession material")
eq(classes({name = "iron ore"}), "materials", "ore by name")
eq(classes({product = true, name = "goblin tooth"}), "products", "a pack product")
eq(classes({price = 40, name = "minotaur leather"}), "products", "sellable loot that is nothing else")
eq(classes({price = 40, gear = "helmet", name = "steel helmet"}), "armor", "a sellable helmet is armour")
eq(classes({price = 40, rune = true, name = "rune"}), "supplies", "a sellable rune is a supply")
eq(classes({price = 0, name = "strange thing"}), "", "unclassified: general tabs")
eq(classes({name = "teddy bear doll"}), "cosmetics", "a doll")
eq(classes({gear = "weapon", name = "trophy sword"}), "weapons", "words never move gear")
eq(classes({container = true, price = 10, name = "bag"}), "", "a bag is no product")
eq(K.entryKey({id = 2148, plain = true, stackable = true}), "s2148", "a plain stack merges by type")
eq(K.entryKey({id = 2148, plain = false, stackable = true}), nil, "a stack with attributes is a row")
eq(K.entryKey({id = 2400, plain = true, stackable = false}), nil, "a weapon is a row")
eq(table.concat(K.unpackClasses(cfg, "weapons,bogus,armor,"), ","), "weapons,armor", "stored classes, unknown keys dropped")

-- ====================================================================== ownership and room
local L = pc.limits.stashTabs
local v0 = K.view(cfg, {stashTabs = L.free})
eq(v0.general, 4, "4 free general tabs")
eq(v0.owned.supplies, "free", "Supplies owned by everybody")
eq(v0.owned.orbs, nil, "Orbs not owned")
eq(v0.owned.products, nil, "Products not owned without the Pact")
local vP = K.view(cfg, {stashTabs = L.free + L.pact, pact = true})
eq(vP.general, 6, "the Pact adds 2 general tabs")
eq(vP.owned.products, "pact", "the Pact lends the Products tab")
local vB = K.view(cfg, {stashTabs = L.free, extras = {stashOrbs = 1, stashWeapons = 1}})
eq(vB.owned.orbs, "bought", "Orbs bought")
eq(vB.owned.weapons, "bought", "Weapons bought")
local vA = K.view(cfg, {stashTabs = L.free, achievements = {depot_tab_relics = true, depot_tab_vault = true, unique_50 = true}})
eq(vA.general, 6, "two achievements: two more general tabs")
eq(vA.owned.cosmetics, "achievement", "Collectibles earned by an achievement")
eq(K.view(cfg, {stashTabs = L.free, depotTabs = 3}).general, 7, "bought depot tabs count as general tabs")
eq(K.view(cfg, {stashTabs = 99, depotTabs = 99}).general, cfg.maxGeneralTabs, "capped at maxGeneralTabs")
eq(K.view(cfg, {stashTabs = -5}).general, 0, "never negative")

eq(K.writable(cfg, v0, 4), true, "general tab 4 writable")
eq(K.writable(cfg, v0, 5), false, "general tab 5 withdraw-only")
eq(K.writable(cfg, v0, 104), true, "Supplies writable")
eq(K.writable(cfg, v0, 101), false, "Orbs not owned: withdraw-only")
eq(K.writable(cfg, v0, cfg.oldDepot.tab), false, "Old depot never takes items")
eq(K.sizeOf(cfg, 1), cfg.tabSize, "general tab size")
eq(K.sizeOf(cfg, 101), 100, "Orbs tab size")
eq(K.sizeOf(cfg, cfg.oldDepot.tab), math.huge, "Old depot never full")

-- ====================================================================== routing
local function entries(n, firstKey, tab, cls)
	local out = {}
	for i = 1, n do
		out[i] = {key = firstKey .. i, tab = tab or 0, classes = cls or {}}
	end
	return out
end
local function concat(...)
	local out = {}
	for _, list in ipairs({...}) do
		for _, e in ipairs(list) do out[#out + 1] = e end
	end
	return out
end
local function tabCount(list, tab)
	local c = 0
	for _, e in ipairs(list) do
		if e.tab == tab then c = c + 1 end
	end
	return c
end
local used = {}
eq(K.route(cfg, v0, used, nil, {"supplies"}), 104, "a potion goes to the free Supplies tab")
eq(K.route(cfg, v0, used, nil, {"orbs", "materials"}), 1, "an orb without an Orbs tab: a general tab")
eq(K.route(cfg, vB, used, nil, {"orbs", "materials"}), 101, "with the Orbs tab: there")
eq(K.route(cfg, vB, {[101] = 100}, nil, {"orbs", "materials"}), 1, "Orbs tab full: spills into a general tab")
eq(K.route(cfg, v0, {[1] = 100}, nil, {}), 2, "tab 1 full: tab 2")
local full = {[1] = 100, [2] = 100, [3] = 100, [4] = 100}
local t, why = K.route(cfg, v0, full, nil, {})
check(t == nil and why == "full", "every general tab full: full")
full[5] = 3
t, why = K.route(cfg, v0, full, nil, {})
check(t == nil and why == "locked", "full, and entries wait in a withdraw-only tab: locked")
eq(K.route(cfg, v0, full, {key = "s1", tab = 2}, {}), 2, "a merged stack in a writable tab needs no room")
eq(K.route(cfg, v0, {[1] = 99}, {key = "s1", tab = 5}, {}), 1, "a merged stack in a withdraw-only tab moves where there is room")

-- the layout: the stash of before (tab 0) placed by key, nothing deleted
local old = entries(450, "s", 0)
local moves = K.layout(cfg, v0, old)
eq(#moves, 450, "every old entry placed")
eq(tabCount(old, 1) + tabCount(old, 2) + tabCount(old, 3) + tabCount(old, 4), 400, "the 4 free tabs filled")
eq(tabCount(old, 5), 50, "the rest waits in tab 5, withdraw-only")
eq(#K.layout(cfg, v0, old), 0, "the layout is stable")
-- a newly bought Orbs tab: the orbs of the general tabs move in
local mixed = concat(entries(3, "a", 1), entries(2, "o", 1, {"orbs", "materials"}))
moves = K.layout(cfg, vB, mixed)
eq(#moves, 2, "orbs move into the bought Orbs tab")
eq(tabCount(mixed, 101), 2, "two orbs in tab 101")
-- a lost affinity tab keeps its entries
local lost = entries(2, "g", 102, {"gems"})
eq(#K.layout(cfg, v0, lost), 0, "entries of a lost Gems tab stay, withdraw-only")
-- an unknown tab id is placed again; the depot migration's entries prefer the Old depot tab over a locked tab
local unknown = {{key = "x", tab = 150, classes = {}}}
K.layout(cfg, v0, unknown)
eq(unknown[1].tab, 1, "an unknown tab id is placed again")
local crowd = entries(400, "c", 0)
K.layout(cfg, v0, crowd)
local depotNew = {{key = "d1", tab = 0, classes = {}, overflow = cfg.oldDepot.tab}, {key = "d2", tab = 0, classes = {"supplies"},
	overflow = cfg.oldDepot.tab}}
K.layout(cfg, v0, concat(crowd, depotNew))
eq(depotNew[1].tab, cfg.oldDepot.tab, "a migrated item that fits no tab: Old depot")
eq(depotNew[2].tab, 104, "a migrated potion still finds Supplies")

-- plans fill as they go
local items = {{ref = 1, key = "s2148", classes = {}, count = 100}, {ref = 2, key = "s2148", classes = {}, count = 50}}
for i = 3, 7 do items[#items + 1] = {ref = i, classes = {}, count = 1} end
items[#items + 1] = {ref = 8, classes = {}, count = 1, skip = "locked"}
local nearly = entries(398, "n", 0)
K.layout(cfg, v0, nearly)
local plan, skipped = K.plan(cfg, v0, nearly, items, {counts = {}})
eq(#plan, 3, "room for 2 entries: the gold (both stacks in one entry) and one row")
eq(plan[2] and plan[2].key, "s2148", "the second gold stack joins the first")
eq(plan[3] and plan[3].ref, 3, "then the first row")
eq(#skipped, 5, "4 rows without room and the skipped one")
local reasons = {}
for _, s in ipairs(skipped) do reasons[s.reason] = (reasons[s.reason] or 0) + 1 end
eq(reasons.locked, 1, "the skip reason is kept")
eq(reasons.full, 4, "no room for the rest")
plan, skipped = K.plan(cfg, v0, {}, {{ref = 1, key = "s1", classes = {}, count = 10}}, {counts = {s1 = cfg.maxStackPerEntry - 5}})
eq(skipped[1] and skipped[1].reason, "limit", "the most of one stack type")
plan = K.plan(cfg, v0, crowd, {{ref = 1, classes = {}, count = 1}}, {overflow = cfg.oldDepot.tab})
eq(plan[1] and plan[1].tab, cfg.oldDepot.tab, "the migration's overflow")
local locked5 = {{key = "s9", tab = 5, classes = {}}}
plan = K.plan(cfg, v0, concat(crowd, locked5), {{ref = 1, key = "s9", classes = {}, count = 3}}, {overflow = cfg.oldDepot.tab})
eq(plan[1] and plan[1].tab, 5, "a migrated stack joins its withdraw-only entry (one entry per type)")

-- the tab bar
local view = K.tabsView(cfg, v0, old)
eq(view[1].id, 1, "first tab")
eq(view[5].locked, true, "tab 5 shown withdraw-only")
local sup
for _, tb in ipairs(view) do
	if tb.affinity == "supplies" then sup = tb end
end
check(sup ~= nil and sup.locked == false and sup.icon ~= nil and sup.source == "free", "Supplies shown, writable, with its icon")
view = K.tabsView(cfg, v0, concat(lost, {{key = "z", tab = cfg.oldDepot.tab}}))
local gemsShown, oldShown = false, false
for _, tb in ipairs(view) do
	gemsShown = gemsShown or (tb.affinity == "gems" and tb.locked)
	oldShown = oldShown or (tb.old and tb.locked and tb.used == 1)
end
check(gemsShown, "a lost tab with items is shown withdraw-only")
check(oldShown, "the Old depot tab shows while it holds items")

-- ====================================================================== rules
eq(K.depositRefusal(cfg, f({pickupable = false})), "cannot", "fixed item")
eq(K.depositRefusal(cfg, f({container = true, contents = 2})), "container", "a bag with items")
eq(K.depositRefusal(cfg, f({container = true, contents = 0})), nil, "an empty bag")
eq(K.depositRefusal(cfg, f({uniqueId = 5})), "cannot", "a unique id")
eq(K.depositRefusal(cfg, f({blocked = true})), "blocked", "never-stash list")
eq(K.depositRefusal(cfg, f({actionId = 47401})), nil, "a dragged rift key may go in")
eq(K.depositRefusal(cfg, f({bound = true})), nil, "a dragged store-bound item may go in (the stash is the character's)")
eq(K.stowSkip(cfg, f({container = true})), "container", "stow: bags stay")
eq(K.stowSkip(cfg, f({movable = false})), "fixed", "stow: fixed")
eq(K.stowSkip(cfg, f({bound = true})), "bound", "stow: store-bound")
eq(K.stowSkip(cfg, f({locked = true})), "locked", "stow: locked")
eq(K.stowSkip(cfg, f({actionId = 1234})), "quest", "stow: action id")
eq(K.stowSkip(cfg, f({uniqueId = 1})), "quest", "stow: unique id")
eq(K.stowSkip(cfg, f({actionId = 47401})), nil, "stow: a rift key goes")
eq(K.stowSkip(cfg, f({blocked = true})), "blocked", "stow: never-stash list")
eq(K.stowSkip(cfg, f({})), nil, "stow: a plain item goes")
local rep = K.report(cfg, {{name = "gold coin", count = 100}, {name = "sword", count = 1}},
	{{name = "bag", reason = "container"}, {name = "bag", reason = "container"}, {name = "x", reason = "full"}})
eq(rep.stowed, 101, "report: units stowed")
eq(rep.kept, 3, "report: kept")
eq(rep.reasons[1].reason, "container", "report: the biggest reason first")
eq(#rep.reasons[1].names, 1, "report: a name once")
eq(K.reasonLine(rep), "containers 2, no room 1", "report line")
eq(K.canWithdraw(cfg, {pz = true}), true, "withdraw in a protection zone")
eq(K.canWithdraw(cfg, {pz = false}), false, "no withdraw outside")
eq(K.canWithdraw(cfg, {hideout = true}), true, "withdraw inside a hideout")

-- ====================================================================== the journal, crashed at every step
eq(K.recoverAction(9, 5, 5), "activate", "depositing, saved")
eq(K.recoverAction(9, 6, 5), "drop", "depositing, not saved")
eq(K.recoverAction(8, 5, 5), "done", "taking, saved")
eq(K.recoverAction(8, 6, 5), "restore", "taking, not saved")
eq(K.recoverAction(8, 1, -1), "restore", "taking, no serial saved yet")
eq(K.recoverAction(0, 9, 0), "keep", "an active row")

local function copy(t)
	local o = {}
	for k, v in pairs(t) do o[k] = v end
	return o
end
-- the world: the character (memory and its saved copy) and the database (durable at once)
local function newWorld(inv)
	local w = {inv = copy(inv), seq = 0, rows = {}, nextId = 0}
	w.saved = {inv = copy(inv), seq = 0}
	return w
end
local function addRow(w, item, state, seq)
	w.nextId = w.nextId + 1
	w.rows[w.nextId] = {id = w.nextId, item = item, state = state, seq = seq}
	return w.nextId
end
local function envOf(w, opts)
	opts = opts or {}
	local step = 0
	local function tick(name)
		step = step + 1
		if opts.crashAt == step then
			error("crash", 0)
		end
		if opts.fail and opts.fail[name] then
			opts.fail[name] = opts.fail[name] - 1
			if opts.fail[name] >= 0 then
				return false
			end
		end
		return true
	end
	local env = {}
	function env.getSeq() return w.seq end
	function env.setSeq(v) tick("setSeq"); w.seq = v end
	function env.pending()
		local out = {}
		for _, r in pairs(w.rows) do
			if r.state == 8 or r.state == 9 then out[#out + 1] = copy(r) end
		end
		table.sort(out, function(a, b) return a.id < b.id end)
		return out
	end
	function env.insert(rec, seq)
		if not tick("insert") then return nil end
		return addRow(w, rec.item, 9, seq)
	end
	function env.remove(rec)
		if not tick("remove") or (w.inv[rec.item] or 0) < 1 then return false end
		w.inv[rec.item] = w.inv[rec.item] - 1
		return true
	end
	function env.restore(rec) tick("restore"); w.inv[rec.item] = (w.inv[rec.item] or 0) + 1 end
	function env.activate(seq)
		if not tick("activate") then return false end
		for _, r in pairs(w.rows) do
			if r.seq == seq and r.state == 9 then r.state = 0 end
		end
		return true
	end
	function env.drop(row)
		if not tick("drop") then return false end
		local r = w.rows[row.id]
		if r and r.state == 9 then w.rows[row.id] = nil end
		return true
	end
	function env.take(rec, seq)
		if not tick("take") then return false end
		local r = w.rows[rec.id]
		if not r or r.state ~= 0 then return false end
		r.state, r.seq = 8, seq
		return true
	end
	function env.give(rec)
		if not tick("give") then return false end
		w.inv[rec.item] = (w.inv[rec.item] or 0) + 1
		return true
	end
	function env.ungive(rec) tick("ungive"); w.inv[rec.item] = w.inv[rec.item] - 1 end
	function env.untake(rec)
		if not tick("untake") then return false end
		local r = w.rows[rec.id]
		if r and r.state == 8 then r.state = 0 end
		return true
	end
	function env.finish(rec)
		if not tick("finish") then return false end
		local r = w.rows[rec.id]
		if r and r.state == 8 then w.rows[rec.id] = nil end
		return true
	end
	function env.save()
		if not tick("save") then return false end
		w.saved = {inv = copy(w.inv), seq = w.seq}
		return true
	end
	return env
end
local function crash(w)
	w.inv, w.seq = copy(w.saved.inv), w.saved.seq
end
-- the copies of an item: on the character plus active stash rows; and journal rows left
local function total(w, item)
	local c = w.inv[item] or 0
	for _, r in pairs(w.rows) do
		if r.item == item and r.state == 0 then c = c + 1 end
	end
	return c
end
local function open(w)
	local c = 0
	for _, r in pairs(w.rows) do
		if r.state ~= 0 then c = c + 1 end
	end
	return c
end
local function login(w)
	local env = envOf(w)
	return K.recover(env, env.pending(), w.seq)
end

-- a deposit of two items, crashed after each step
local steps = 0
for crashAt = 1, 30 do
	local w = newWorld({sword = 1, ring = 1})
	local ok = pcall(K.deposit, envOf(w, {crashAt = crashAt}), {{item = "sword"}, {item = "ring"}})
	if ok then
		steps = crashAt - 1
		eq(w.inv.sword, 0, "deposit done: the sword left")
		eq(total(w, "sword") .. "/" .. total(w, "ring"), "1/1", "deposit done: one copy each")
		break
	end
	crash(w)
	check(login(w), "deposit crash " .. crashAt .. ": recovered")
	eq(total(w, "sword") .. "/" .. total(w, "ring"), "1/1", "deposit crashed at step " .. crashAt .. ": one copy each")
	eq(open(w), 0, "deposit crashed at step " .. crashAt .. ": no journal row left")
end
check(steps >= 7, "the deposit was crashed at each of its steps (" .. steps .. ")")

-- a withdrawal, crashed after each step
steps = 0
for crashAt = 1, 30 do
	local w = newWorld({})
	local id = addRow(w, "axe", 0, 0)
	local ok = pcall(K.withdraw, envOf(w, {crashAt = crashAt}), {id = id, item = "axe"})
	if ok then
		steps = crashAt - 1
		eq(w.inv.axe, 1, "withdraw done: on the character")
		eq(total(w, "axe"), 1, "withdraw done: one copy")
		break
	end
	crash(w)
	check(login(w), "withdraw crash " .. crashAt .. ": recovered")
	eq(total(w, "axe"), 1, "withdraw crashed at step " .. crashAt .. ": one copy")
	eq(open(w), 0, "withdraw crashed at step " .. crashAt .. ": no journal row left")
end
check(steps >= 5, "the withdrawal was crashed at each of its steps (" .. steps .. ")")

-- a failed save: everything back, nothing credited
local w = newWorld({sword = 1})
local done, failed = K.deposit(envOf(w, {fail = {save = 1}}), {{item = "sword"}})
eq(#done .. "/" .. #failed, "0/1", "failed save: nothing deposited")
eq(failed[1].reason, "busy", "failed save: busy")
eq(w.inv.sword, 1, "failed save: the sword is back")
eq(total(w, "sword"), 1, "failed save: one copy")
w = newWorld({})
local id = addRow(w, "axe", 0, 0)
local okW, whyW = K.withdraw(envOf(w, {fail = {save = 1}}), {id = id, item = "axe"})
check(not okW and whyW == "busy", "failed save on a withdrawal: busy")
eq(total(w, "axe"), 1, "failed save on a withdrawal: one copy, in the stash")
eq(w.rows[id].state, 0, "and its row active again")
-- no room
w = newWorld({})
id = addRow(w, "axe", 0, 0)
okW, whyW = K.withdraw(envOf(w, {fail = {give = 1}}), {id = id, item = "axe"})
check(not okW and whyW == "room", "no room: refused")
eq(w.rows[id].state, 0, "no room: the row active again")
-- a failed save AND a failed write after it: the next operation settles the row first (the serial in memory is the
-- saved one between operations)
w = newWorld({sword = 1, ring = 1})
K.deposit(envOf(w, {fail = {save = 1, drop = 1}}), {{item = "sword"}})
eq(open(w), 1, "double fault: a depositing row is left")
eq(total(w, "sword"), 1, "double fault: still one sword")
done = K.deposit(envOf(w), {{item = "ring"}})
eq(#done, 1, "the next deposit works")
eq(open(w), 0, "and settled the row left before")
eq(total(w, "sword") .. "/" .. total(w, "ring"), "1/1", "nothing doubled")
crash(w)
login(w)
eq(total(w, "sword") .. "/" .. total(w, "ring"), "1/1", "nothing doubled after a crash either")
w = newWorld({})
id = addRow(w, "axe", 0, 0)
K.withdraw(envOf(w, {fail = {save = 1, untake = 1}}), {id = id, item = "axe"})
eq(w.rows[id].state, 8, "double fault on a withdrawal: a taking row is left")
local id2 = addRow(w, "bow", 0, 0)
check(K.withdraw(envOf(w), {id = id2, item = "bow"}), "the next withdrawal works")
eq(total(w, "axe") .. "/" .. total(w, "bow"), "1/1", "the axe is back in the stash, the bow on the character")
-- settle refuses a new operation while a row cannot be fixed
w = newWorld({sword = 1})
addRow(w, "ghost", 9, 99)
done, failed = K.deposit(envOf(w, {fail = {drop = 1}}), {{item = "sword"}})
eq(#done .. "/" .. (failed[1] and failed[1].reason), "0/busy", "an unsettled row: no new deposit")

-- ====================================================================== the codec
-- items as the market test makes them: the engine form of every attribute, a plain stack as the engine writes it
local types = {
	[2148] = {name = "gold coin", stackable = true, price = 0},
	[2152] = {name = "platinum coin", stackable = true},
	[2400] = {name = "magic sword", gear = "weapon"},
	[2472] = {name = "magic plate armor", gear = "armor"},
	[2171] = {name = "platinum amulet", gear = "jewel"},
	[7618] = {name = "health potion", stackable = true, fluid = false},
	[2268] = {name = "sudden death rune", stackable = true, rune = true},
	[2544] = {name = "arrow", stackable = true, weapon = 7},
	[29856] = {name = "orb of chaos", stackable = true},
	[10155] = {name = "shadow orb"},
	[1987] = {name = "bag", container = true},
	[1988] = {name = "backpack", container = true},
	[3000] = {name = "statue", movable = false},
	[32081] = {name = "loot bag", container = true},
	[5880] = {name = "iron ore", stackable = true},
	[2594] = {name = "depot chest", container = true},
	[25453] = {name = "depot tab 1", container = true},
	[25454] = {name = "depot tab 2", container = true},
	[4000] = {name = "strange relic"}
}
local ITEM_ATTRIBUTE_NAME_ = 1
ITEM_ATTRIBUTE_NAME = ITEM_ATTRIBUTE_NAME_
ITEM_ATTRIBUTE_ACTIONID = 2
ITEM_ATTRIBUTE_UNIQUEID = 3
ITEM_ATTRIBUTE_DESCRIPTION = 4
ITEM_ATTRIBUTE_TEXT = 5
ITEM_ATTRIBUTE_CHARGES = 6

local Items = {}
local itemMeta = {__index = Items}
local function newItem(id, cnt, extra)
	local it = setmetatable({id = id, count = cnt or 1, custom = {}, std = {}}, itemMeta)
	if types[id] and types[id].container then
		it.children = {}
	end
	for k, v in pairs(extra or {}) do it[k] = v end
	return it
end
local function typeOf(id)
	local t = types[id] or {name = "item " .. id}
	return {
		getId = function() return id end, getName = function() return t.name end,
		isStackable = function() return t.stackable == true end, isContainer = function() return t.container == true end,
		isPickupable = function() return true end, isMovable = function() return t.movable ~= false end,
		isRune = function() return t.rune == true end, isFluidContainer = function() return t.fluid == true end,
		getWeaponType = function() return t.weapon or 0 end, getAmmoType = function() return 0 end,
		getType = function() return t.key and ITEM_TYPE_KEY or 0 end, getClientId = function() return id + 100000 end,
		getWeight = function(_, c) return 0 end, gear = t.gear
	}
end
ItemType = typeOf
ChaosItemMods = {kindOfType = function(it) return it.gear end}
function Items.getId(self) return self.id end
function Items.getCount(self) return self.count end
function Items.getName(self) return self.std[ITEM_ATTRIBUTE_NAME] or (types[self.id] or {}).name or "thing" end
function Items.getType(self) return typeOf(self.id) end
function Items.getDescription(self) return "You see " .. self:getName() .. "." end
function Items.getCustomAttribute(self, k) return self.custom[k:lower()] end
function Items.setCustomAttribute(self, k, v) self.custom[k:lower()] = v end
function Items.removeCustomAttribute(self, k) self.custom[k:lower()] = nil end
function Items.hasAttribute(self, a) return self.std[a] ~= nil end
function Items.getAttribute(self, a) return self.std[a] end
function Items.setAttribute(self, a, v) self.std[a] = v end
function Items.getActionId(self) return self.std[ITEM_ATTRIBUTE_ACTIONID] or 0 end
function Items.isStoreItem(self) return self.store == true end
function Items.isContainer(self) return self.children ~= nil end
function Items.isStackable(self) return types[self.id] ~= nil and types[self.id].stackable == true end
function Items.getSize(self) return self.children and #self.children or 0 end
function Items.getItem(self, i) return self.children and self.children[i + 1] end
function Items.getItems(self, recursive)
	local out = {}
	for _, c in ipairs(self.children or {}) do
		out[#out + 1] = c
		if recursive and c.children then
			for _, x in ipairs(c:getItems(true)) do out[#out + 1] = x end
		end
	end
	return out
end
function Items.getParent(self) return self.parent end
local function detach(item)
	local p = item.parent
	if p and p.children then
		for i, c in ipairs(p.children) do
			if c == item then table.remove(p.children, i) break end
		end
	elseif p and p.slots then
		for s, c in pairs(p.slots) do
			if c == item then p.slots[s] = nil end
		end
	end
	item.parent = nil
end
function Items.remove(self, cnt)
	if self.noRemove then return false end
	if cnt and cnt < self.count then
		self.count = self.count - cnt
		return true
	end
	detach(self)
	self.removed = true
	return true
end
local function ser(item)
	if next(item.custom) == nil and next(item.std) == nil and Items.isStackable(item) then
		return string.char(15, math.min(item.count, 255)) -- the engine's ATTR_COUNT: a plain stack
	end
	local parts = {}
	local ks = {}
	for k in pairs(item.custom) do ks[#ks + 1] = k end
	table.sort(ks)
	for _, k in ipairs(ks) do
		local v = item.custom[k]
		parts[#parts + 1] = "c|" .. k .. "|" .. type(v) .. "|" .. tostring(v)
	end
	local ss = {}
	for k in pairs(item.std) do ss[#ss + 1] = k end
	table.sort(ss)
	for _, k in ipairs(ss) do
		parts[#parts + 1] = "s|" .. k .. "|" .. type(item.std[k]) .. "|" .. tostring(item.std[k])
	end
	return table.concat(parts, "\n") .. "\0\255"
end
local function blobMethods(on)
	if on then
		Items.serializeAttributes = function(self) return ser(self) end
		Items.unserializeAttributes = function(self, raw)
			if raw:byte(1) == 15 and #raw == 2 then return true end
			if raw:sub(-2) ~= "\0\255" then return false end
			for line in raw:sub(1, -3):gmatch("[^\n]+") do
				local kind, k, ty, val = line:match("^(%a)|([^|]*)|(%a+)|(.*)$")
				local value = ty == "number" and tonumber(val) or (ty == "boolean" and val == "true") or val
				if kind == "c" then self.custom[k] = value elseif kind == "s" then self.std[tonumber(k)] = value end
			end
			return true
		end
	else
		Items.serializeAttributes, Items.unserializeAttributes = nil, nil
	end
	Item = {serializeAttributes = Items.serializeAttributes, unserializeAttributes = Items.unserializeAttributes}
end
blobMethods(true)
local created = {}
Game = {
	createItem = function(id, cnt)
		local it = newItem(id, cnt)
		created[#created + 1] = it
		return it
	end,
	getTowns = function() return {{getId = function() return 1 end}, {getId = function() return 2 end}} end
}

dofile("data/scripts/chaos/item_codec.lua")
local IC = ChaosItemCodec
local function rolled()
	local s = newItem(2400)
	for k, v in pairs({rarity = 5, combatpowerlevel = 150, rarity_firedamage = 12, rarity_firedamage_t = 3, chaos_sockets = 2,
		chaos_gem1 = 40001, chaos_quality = 18, chaos_iid = 777, chaos_ext = "pw:deathblast"}) do s.custom[k] = v end
	s.std[ITEM_ATTRIBUTE_NAME] = "Doombringer"
	s.std[ITEM_ATTRIBUTE_CHARGES] = 3
	return s
end
local sw = rolled()
local codec, data = IC.encode(sw)
eq(codec, "blob", "blob codec with engine patch 0017")
local back = IC.decode(2400, 1, codec, data)
local want = rolled()
want.custom.chaos_iid = nil
eq(ser(back), ser(want), "blob round trip: every attribute back, a new per-item id")
check(back.custom.chaos_ext == "pw:deathblast", "a custom key no list knows survives the blob")
eq(IC.isPlain(newItem(2148, 50)), true, "a plain stack")
local named = newItem(2148, 50)
named.custom.chaos_locked = 1
eq(IC.isPlain(named), false, "a locked stack is not plain")
eq(select(1, IC.decode(2148, 40, "plain", "")).count, 40, "plain decode: the count")
local bad = IC.decode(2400, 1, "blob", "zz")
eq(bad, nil, "a broken blob is not delivered")
blobMethods(false)
codec, data = IC.encode(rolled(), false)
eq(codec, "attrs", "key-list codec without the patch")
local copyKL = IC.decode(2400, 1, codec, data, false)
eq(copyKL.custom.rarity, 5, "key list: rarity back")
eq(copyKL.std[ITEM_ATTRIBUTE_NAME], "Doombringer", "key list: the name back")
eq(IC.isPlain(newItem(2148, 50), false), true, "plain without the patch: no attribute")
eq(IC.isPlain(named, false), false, "a locked stack without the patch")
local _, whyBlob = IC.decode(2400, 1, "blob", "00", false)
has(whyBlob, "0017", "a blob row without the patch says why")
blobMethods(true)

-- ====================================================================== stash.lua against a mocked engine
dofile("data/scripts/chaos/chaos_constants.lua")
local sent = {}
Chaos.decode = function(b) return type(b) == "table" and b or nil end
function Chaos.send(player, opcode, action, d) sent[#sent + 1] = {player = player, opcode = opcode, action = action, data = d}; return true end
local events = {}
function CreatureEvent(name) local o = {}; function o:type() end; function o:register() events[name] = o end; return o end
local queries = {}
db = {
	query = function(q) queries[#queries + 1] = q; return true end, asyncQuery = function(q) queries[#queries + 1] = q end,
	storeQuery = function() return nil end, escapeString = function(s) return "'" .. tostring(s):gsub("'", "\\'") .. "'" end,
	lastInsertId = function() return 0 end
}
Chaos.select = function() return {} end
json = json or {encode = function() return "{}" end}

local pz = {}
local function key3(p) return p.x .. "," .. p.y .. "," .. p.z end
function Tile(p)
	return {hasFlag = function(_, flag) return flag == TILESTATE_PROTECTIONZONE and pz[key3(p)] == true end,
		getHouse = function() return nil end, getThing = function() return nil end}
end
function Position(x, y, z) return {x = x, y = y, z = z} end

local function container(id, kids)
	local c = newItem(id)
	for _, k in ipairs(kids or {}) do
		c.children[#c.children + 1] = k
		k.parent = c
	end
	return c
end
local function newPlayer(guid)
	local p = {guid = guid, storage = {}, slots = {}, cancels = {}, texts = {}, saveOk = true, pos = Position(100, 100, 7), chests = {}}
	function p:getGuid() return self.guid end
	function p:getId() return self.guid end
	function p:getAccountId() return self.guid * 10 end
	function p:getName() return "P" .. self.guid end
	function p:getPosition() return self.pos end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:setStorageValue(k, v) self.storage[k] = v end
	function p:getSlotItem(s) return self.slots[s] end
	function p:getContainerById(cid) return cid == 0 and self.slots[CONST_SLOT_BACKPACK] or nil end
	function p:sendCancelMessage(t) self.cancels[#self.cancels + 1] = tostring(t) end
	function p:sendTextMessage(_, t) self.texts[#self.texts + 1] = tostring(t) end
	function p:registerEvent() end
	function p:save()
		if not self.saveOk then return false end
		self.saves = (self.saves or 0) + 1
		return true
	end
	function p:getFreeCapacity() return 100000 end
	function p:getDepotChest(town) return self.chests[town] end
	local function bp() return p.slots[CONST_SLOT_BACKPACK] end
	p.bp = bp
	function p:addItemEx(item)
		if self.full then return 1 end
		local b = bp()
		b.children[#b.children + 1] = item
		item.parent = b
		return RETURNVALUE_NOERROR
	end
	function p:addItem(id, cnt)
		if self.full then return nil end
		local b = bp()
		for _, c in ipairs(b.children) do
			if c.id == id and Items.isStackable(c) and next(c.custom) == nil then
				c.count = c.count + cnt
				return c
			end
		end
		return self:addItemEx(newItem(id, cnt)) == RETURNVALUE_NOERROR
	end
	function p:getItemCount(id)
		local c = 0
		for _, it in ipairs(bp():getItems(true)) do
			if it.id == id then c = c + it.count end
		end
		return c
	end
	function p:removeItem(id, cnt)
		for _, it in ipairs(bp():getItems(true)) do
			if it.id == id then it:remove(cnt) return true end
		end
		return false
	end
	local backpack = container(1988)
	p.slots[CONST_SLOT_BACKPACK] = backpack
	backpack.parent = {slots = p.slots}
	return p
end

dofile("data/scripts/chaos/stash.lua")
local S = ChaosStash
local store = S.store
check(events.ChaosStashExtended ~= nil and events.ChaosStashLogin ~= nil, "events registered")
check(ChaosCommands == nil or ChaosCommands.handlers == nil or ChaosCommands.handlers.stash == nil,
	"no player command: Stow Everything is a button of the window (owner rule)")

-- the in-memory database behind the store (the same rules as the SQL)
local DB
local function resetDB() DB = {plain = {}, rows = {}, nextId = 0, blocked = {}, ach = {}, logs = {}} end
resetDB()
local function plainKey(g, i) return g .. ":" .. i end
function store.plainRows(g)
	local out = {}
	for _, r in pairs(DB.plain) do
		if r.player == g and r.count > 0 then out[#out + 1] = {item_id = r.item, count = r.count, tab = r.tab} end
	end
	table.sort(out, function(a, b) return a.item_id < b.item_id end)
	return out
end
function store.itemRows(g)
	local out = {}
	for _, r in pairs(DB.rows) do
		if r.player == g and (r.state == 0 or r.state == 9) and r.codec ~= "plain" then
			out[#out + 1] = {id = r.id, item_id = r.item, count = r.count, tab = r.tab, classes = r.classes, name = r.name,
				info = r.info, rarity = r.rarity, source = r.source}
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end
function store.itemRow(g, id)
	local r = DB.rows[id]
	if r and r.player == g and r.state == 0 then
		return {id = r.id, item_id = r.item, count = r.count, codec = r.codec, data = r.data, tab = r.tab, name = r.name}
	end
	return nil
end
function store.plainCount(g, i)
	local r = DB.plain[plainKey(g, i)]
	return r and r.count or 0, r and r.tab or 0
end
function store.pending(g)
	local out = {}
	for _, r in pairs(DB.rows) do
		if r.player == g and (r.state == 8 or r.state == 9) then
			out[#out + 1] = {id = r.id, state = r.state, seq = r.seq, item_id = r.item, count = r.count, codec = r.codec, tab = r.tab}
		end
	end
	return out
end
function store.setTab(g, e)
	if e.row then
		if DB.rows[e.row] and DB.rows[e.row].player == g then DB.rows[e.row].tab = e.tab end
	elseif DB.plain[plainKey(g, e.item)] then
		DB.plain[plainKey(g, e.item)].tab = e.tab
	end
	return true
end
function store.insert(g, rec, state, seq)
	if DB.failInsert then return nil end
	DB.nextId = DB.nextId + 1
	DB.rows[DB.nextId] = {id = DB.nextId, player = g, item = rec.itemId, count = rec.count, codec = rec.codec or "plain",
		data = rec.data or "", tab = rec.tab, classes = rec.classes or "", name = rec.name or "", info = rec.info or "",
		rarity = rec.rarity or 0, state = state, seq = seq, source = rec.source or "deposit"}
	return DB.nextId
end
local function addPlain(g, i, c, tab, moveTab)
	local k = plainKey(g, i)
	local r = DB.plain[k]
	if r then
		r.count = r.count + c
		if moveTab then r.tab = tab end
	else
		DB.plain[k] = {player = g, item = i, count = c, tab = tab}
	end
end
function store.activate(g, seq)
	for id, r in pairs(DB.rows) do
		if r.player == g and r.seq == seq and r.state == 9 then
			if r.codec == "plain" then
				addPlain(g, r.item, r.count, r.tab, true)
				DB.rows[id] = nil
			else
				r.state = 0
			end
		end
	end
	return true
end
function store.drop(g, id, state)
	local r = DB.rows[id]
	if r and r.player == g and r.state == state then DB.rows[id] = nil end
	return true
end
function store.take(g, rec, seq)
	if rec.plain then
		local have = store.plainCount(g, rec.itemId)
		if have < rec.count then return false end
		DB.plain[plainKey(g, rec.itemId)].count = have - rec.count
		if have - rec.count <= 0 then DB.plain[plainKey(g, rec.itemId)] = nil end
		rec.id = store.insert(g, rec, 8, seq)
		return rec.id ~= nil
	end
	local r = DB.rows[rec.id]
	if not r or r.player ~= g or r.state ~= 0 then return false end
	r.state, r.seq = 8, seq
	return true
end
function store.untake(g, rec)
	local r = DB.rows[rec.id]
	if rec.plain then
		addPlain(g, rec.itemId, rec.count, rec.tab)
		DB.rows[rec.id] = nil
		return true
	end
	if r and r.state == 8 then r.state = 0 end
	return true
end
function store.shrinkTake(g, rec, given)
	DB.rows[rec.id].count = given
	addPlain(g, rec.itemId, rec.count - given, rec.tab)
	return true
end
function store.blocked(g)
	local out = {}
	for k in pairs(DB.blocked) do
		local pg, id = k:match("^(%d+):(%d+)$")
		if tonumber(pg) == g then out[#out + 1] = tonumber(id) end
	end
	return out
end
function store.block(g, id, on) DB.blocked[plainKey(g, id)] = on or nil; return true end
function store.achievements(acc, ids)
	local out = {}
	for _, idA in ipairs(ids) do
		if DB.ach[idA] then out[#out + 1] = idA end
	end
	return out
end
function store.unclassified(g)
	local out = {}
	for _, r in pairs(DB.rows) do
		if r.player == g and r.state == 0 and r.source == "depot" and r.classes == "" and r.name == "" then
			out[#out + 1] = {id = r.id, item_id = r.item, count = r.count, codec = r.codec, data = r.data}
		end
	end
	return out
end
function store.mergeRow(g, row)
	addPlain(g, row.item_id, row.count, 0)
	DB.rows[row.id] = nil
	return true
end
function store.describe(g, id, cls, name, info, rarity, cnt)
	local r = DB.rows[id]
	r.classes, r.name, r.info, r.rarity, r.count = cls, name, info, rarity, cnt
	return true
end
function store.log(g, action, moved, overflow, kept, detail)
	DB.logs[#DB.logs + 1] = {g = g, action = action, moved = moved, overflow = overflow, kept = kept, detail = detail}
end
local function activeRows(g)
	local c = 0
	for _, r in pairs(DB.rows) do
		if r.player == g and r.state == 0 then c = c + 1 end
	end
	return c
end
local function openRows()
	local c = 0
	for _, r in pairs(DB.rows) do
		if r.state ~= 0 then c = c + 1 end
	end
	return c
end

local OP = ChaosOpcodes.stash
local ev = events.ChaosStashExtended
local function req(p, d)
	sent = {}
	ev.onExtendedOpcode(p, OP, {action = "Stash", data = d})
end
local function last(make)
	for i = #sent, 1, -1 do
		if sent[i].data and sent[i].data.make == make then return sent[i].data end
	end
	return nil
end
local function lastText(p) return p.texts[#p.texts] end
local function lastCancel(p) return p.cancels[#p.cancels] end
local function itemsList()
	local out = {}
	for _, s in ipairs(sent) do
		if s.data and s.data.make == "addItems" then
			for _, it in ipairs(s.data.items) do out[#out + 1] = it end
		end
	end
	return out
end

-- a deposit from the backpack: the weapon becomes one row with its attributes, the gold one merged stack
local hero = newPlayer(1)
local bp = hero.bp()
local blade = rolled()
local gold1, gold2 = newItem(2148, 100), newItem(2148, 30)
for _, it in ipairs({blade, gold1, gold2}) do
	bp.children[#bp.children + 1] = it
	it.parent = bp
end
local function slotOf(item)
	for i, c in ipairs(bp.children) do
		if c == item then return i - 1 end
	end
end
-- a free player outside town: no deposit (owner 2026-10-15: remote deposit is a paid unlock)
req(hero, {make = "Stash", Pos = {x = 65535, y = 64, z = slotOf(blade)}, UpdateList = true})
eq(blade.removed, nil, "free, outside a protection zone: the weapon stays")
has(lastCancel(hero), "Storage & Slots", "the refusal says where to unlock remote deposit")
eq(last("access") and last("access").canDeposit, false, "the client is told")
check(last("tabs") ~= nil and last("tabs").canDeposit == false and last("tabs").remote == nil, "tabs: deposit locked, no unlock")
req(hero, {make = "StashAllRequest"})
eq(last("StowReport"), nil, "free, outside: no Stow Everything either")
eq(activeRows(1), 0, "nothing stored")
-- in town it works for everybody
pz[key3(hero.pos)] = true
req(hero, {make = "Stash", Pos = {x = 65535, y = 64, z = slotOf(blade)}, UpdateList = true})
eq(blade.removed, true, "the weapon left the backpack")
eq(activeRows(1), 1, "one row for it")
local row = DB.rows[DB.nextId]
eq(row.codec, "blob", "stored with the blob")
eq(row.tab, 1, "no Weapons tab: general tab 1")
eq(row.name, "Doombringer", "its name kept for the list")
eq(hero.storage[cfg.storage.seq], 1, "the journal serial advanced")
eq(hero.saves, 1, "one save")
has(lastText(hero), "Stashed 1x Doombringer", "told")
local listed = itemsList()
eq(#listed, 1, "the list echo")
eq(listed[1] and listed[1].row, row.id, "the list carries the row id")
check(last("tabs") ~= nil and last("tabs").canWithdraw == true and last("tabs").depositWhy == "pz", "tabs: in town both work")
req(hero, {make = "Stash", Pos = {x = 65535, y = 64, z = slotOf(gold1)}})
req(hero, {make = "Stash", Pos = {x = 65535, y = 64, z = slotOf(gold2)}})
eq(DB.plain["1:2148"] and DB.plain["1:2148"].count, 130, "two gold stacks: one merged entry of 130")
eq(activeRows(1), 1, "and no row for them")
eq(openRows(), 0, "no journal row left")
-- the equipped backpack itself is never taken
req(hero, {make = "Stash", Pos = {x = 65535, y = CONST_SLOT_BACKPACK, z = 0}})
check(hero.slots[CONST_SLOT_BACKPACK] == bp, "the backpack stays equipped")

-- withdraw: refused outside a protection zone, the exact item back inside one
pz[key3(hero.pos)] = nil
req(hero, {make = "Redeem", row = row.id})
has(lastCancel(hero), "protection zone", "withdraw refused outside a protection zone")
eq(last("access") and last("access").canWithdraw, false, "the client is told")
eq(activeRows(1), 1, "still stored")
pz[key3(hero.pos)] = true
req(hero, {make = "Redeem", row = row.id})
eq(activeRows(1), 0, "the row is gone")
local backBlade = bp.children[#bp.children]
local expect = rolled()
expect.custom.chaos_iid = nil
eq(backBlade and ser(backBlade), ser(expect), "the same weapon came back: every attribute")
has(lastText(hero), "Retrieved 1x Doombringer", "told")
req(hero, {make = "Redeem", item = 2148, count = 50})
eq(DB.plain["1:2148"].count, 80, "50 gold out, 80 left")
eq(hero:getItemCount(2148), 50, "on the character")
eq(openRows(), 0, "no journal row left after withdrawals")
-- forged requests
local other = newPlayer(2)
pz[key3(other.pos)] = true
local before = activeRows(1)
DB.nextId = DB.nextId + 1
DB.rows[DB.nextId] = {id = DB.nextId, player = 1, item = 2400, count = 1, codec = "blob", data = IC.encode(rolled()), tab = 1,
	classes = "", name = "x", info = "", rarity = 0, state = 0, seq = 0, source = "deposit"}
req(other, {make = "Redeem", row = DB.nextId})
eq(#other.bp().children, 0, "another character's row gives nothing")
has(lastCancel(other), "do not have", "and says so")
req(other, {make = "Redeem", item = 2148, count = 50})
eq(#other.bp().children, 0, "another character's gold gives nothing")
for _, bad in ipairs({{item = 2148, count = -5}, {item = 2148, count = 0 / 0}, {item = "x"}, {row = -1}, {row = 1e300}}) do
	bad.make = "Redeem"
	req(hero, bad)
end
eq(DB.plain["1:2148"].count, 80, "bad counts and rows change nothing")
eq(activeRows(1), before + 1, "nothing else changed")
DB.rows[DB.nextId] = nil
-- no room: the item stays in the stash
hero.full = true
local stuck = rolled()
DB.nextId = DB.nextId + 1
local codecS, dataS = IC.encode(stuck)
DB.rows[DB.nextId] = {id = DB.nextId, player = 1, item = 2400, count = 1, codec = codecS, data = dataS, tab = 1, classes = "",
	name = "y", info = "", rarity = 0, state = 0, seq = 0, source = "deposit"}
req(hero, {make = "Redeem", row = DB.nextId})
eq(DB.rows[DB.nextId] and DB.rows[DB.nextId].state, 0, "no room: still stored, active")
hero.full = false
-- a failed save during a withdrawal: nothing changes
hero.saveOk = false
local nBefore = #bp.children
req(hero, {make = "Redeem", row = DB.nextId})
eq(#bp.children, nBefore, "failed save: the item was taken back")
eq(DB.rows[DB.nextId] and DB.rows[DB.nextId].state, 0, "failed save: the row active again")
has(lastCancel(hero), "busy", "failed save: busy")
hero.saveOk = true
DB.rows[DB.nextId] = nil

-- Stow Everything: nested bags, every skip reason, the Supplies tab, a tab that fills mid-way
resetDB()
local h2 = newPlayer(3)
pz[key3(h2.pos)] = true
local b2 = h2.bp()
local locked = newItem(2472)
locked.custom.chaos_locked = 1
local quest = newItem(4000)
quest.std[ITEM_ATTRIBUTE_ACTIONID] = 1234
local riftKey = newItem(10155)
riftKey.std[ITEM_ATTRIBUTE_ACTIONID] = 47401
riftKey.custom.rift_tier = 4
local storeItem = newItem(4000, 1, {store = true})
local fixed = newItem(3000)
local potions = newItem(7618, 20)
local blocked = newItem(2152, 5)
local inner = container(1987, {newItem(2171), newItem(2268, 10), newItem(5880, 7)})
for _, it in ipairs({newItem(2400), locked, quest, riftKey, storeItem, fixed, potions, blocked, inner, newItem(2148, 99)}) do
	b2.children[#b2.children + 1] = it
	it.parent = b2
end
DB.blocked["3:2152"] = true
req(h2, {make = "StashAllRequest"})
local report = last("StowReport")
check(report ~= nil, "a report")
local why = {}
for _, r in ipairs(report and report.reasons or {}) do why[r.reason] = r.count end
eq(why.locked, 1, "kept: locked")
eq(why.quest, 1, "kept: a quest item")
eq(why.bound, 1, "kept: a store item")
eq(why.fixed, 1, "kept: a fixed item")
eq(why.blocked, 1, "kept: never-stash list")
eq(why.container, 1, "kept: the bag")
local left = {}
for _, it in ipairs(b2:getItems(true)) do left[it.id] = true end
check(left[2472] and left[4000] and left[3000] and left[2152] and left[1987], "the kept items are still in the backpack")
check(not left[2400] and not left[10155] and not left[7618] and not left[2171] and not left[2268] and not left[5880]
	and not left[2148], "everything else left, through the nested bag")
eq(#inner.children, 0, "the bag is empty, and stays")
check(h2.slots[CONST_SLOT_BACKPACK] == b2, "the backpack stays equipped")
eq(report.stowed, 1 + 1 + 20 + 1 + 10 + 7 + 99, "units stowed")
eq(DB.plain["3:7618"] and DB.plain["3:7618"].tab, 104, "potions into the free Supplies tab")
eq(DB.plain["3:2268"] and DB.plain["3:2268"].tab, 104, "runes into Supplies")
local rkRow
for _, r in pairs(DB.rows) do
	if r.item == 10155 then rkRow = r end
end
check(rkRow ~= nil and rkRow.codec == "blob" and rkRow.classes:find("keys", 1, true) ~= nil, "the rift key stored whole, class keys")
eq(h2.saves, 1, "one save for the whole stow")
has(h2.texts[#h2.texts], "Kept 6 item(s)", "the chat line names what stayed")
-- the general tabs fill mid-way: what does not fit stays, nothing lost
resetDB()
local h3 = newPlayer(4)
local b3 = h3.bp()
for i = 1, 4 * cfg.tabSize - 2 do
	DB.nextId = DB.nextId + 1
	DB.rows[DB.nextId] = {id = DB.nextId, player = 4, item = 4000, count = 1, codec = "blob", data = "", tab = 1 + math.floor((i - 1) / cfg.tabSize),
		classes = "", name = "relic", info = "", rarity = 0, state = 0, seq = 0, source = "deposit"}
end
for i = 1, 5 do
	local it = newItem(4000)
	it.custom.n = i
	b3.children[#b3.children + 1] = it
	it.parent = b3
end
req(h3, {make = "StashAllRequest"})
report = last("StowReport")
eq(report.stowed, 2, "two fitted")
why = {}
for _, r in ipairs(report.reasons) do why[r.reason] = r.count end
eq(why.full, 3, "three had no room")
eq(#b3.children, 3, "and are still in the backpack")
eq(activeRows(4), 4 * cfg.tabSize, "the tabs are exactly full")
eq(openRows(), 0, "no journal row left")
-- a failed save during a stow: everything back
resetDB()
local h4 = newPlayer(5)
local b4 = h4.bp()
for _, it in ipairs({newItem(2400), newItem(2148, 10)}) do
	b4.children[#b4.children + 1] = it
	it.parent = b4
end
h4.saveOk = false
req(h4, {make = "StashAllRequest"})
eq(h4:getItemCount(2148), 10, "failed save: the gold is back")
local swordBack = false
for _, it in ipairs(b4.children) do swordBack = swordBack or it.id == 2400 end
check(swordBack, "failed save: the sword is back")
eq(activeRows(5) + (DB.plain["5:2148"] and 1 or 0), 0, "failed save: nothing stored")
eq(openRows(), 0, "failed save: journal rows dropped")

-- the login recovery: rows a crash left
resetDB()
local h5 = newPlayer(6)
h5.storage[cfg.storage.seq] = 7
DB.rows[1] = {id = 1, player = 6, item = 2400, count = 1, codec = "blob", data = "", tab = 1, classes = "", name = "a", info = "",
	rarity = 0, state = 9, seq = 7, source = "deposit"}
DB.rows[2] = {id = 2, player = 6, item = 2472, count = 1, codec = "blob", data = "", tab = 1, classes = "", name = "b", info = "",
	rarity = 0, state = 9, seq = 8, source = "deposit"}
DB.rows[3] = {id = 3, player = 6, item = 2148, count = 40, codec = "plain", data = "", tab = 1, classes = "", name = "c", info = "",
	rarity = 0, state = 9, seq = 7, source = "deposit"}
DB.rows[4] = {id = 4, player = 6, item = 2171, count = 1, codec = "blob", data = "", tab = 1, classes = "", name = "d", info = "",
	rarity = 0, state = 8, seq = 8, source = "deposit"}
DB.nextId = 4
events.ChaosStashLogin.onLogin(h5)
eq(DB.rows[1] and DB.rows[1].state, 0, "login: a saved deposit is activated")
eq(DB.rows[2], nil, "login: an unsaved deposit is dropped (the item is still on the character)")
eq(DB.plain["6:2148"] and DB.plain["6:2148"].count, 40, "login: a saved plain deposit is merged")
eq(DB.rows[4] and DB.rows[4].state, 0, "login: an unsaved withdrawal is restored")

-- the depot migration (at a depot locker opening): boxes, bags, overflow into the Old depot tab, kept items
resetDB()
local h6 = newPlayer(7)
local box1 = container(25453, {newItem(2400), newItem(2148, 100), newItem(2148, 100),
	container(1987, {newItem(2171), newItem(7618, 5)})})
local box2 = container(25454, {newItem(4000)})
local uniq = newItem(4000)
uniq.std[ITEM_ATTRIBUTE_UNIQUEID] = 5000
local box3bag = container(1987, {uniq, newItem(2472)})
local chest1 = container(2594, {box1, box2, box3bag})
h6.chests[1] = chest1
local chest2 = container(2594, {newItem(2268, 3)})
h6.chests[2] = chest2
Chaos.depotConfig = dofile("data/scripts/chaos/depot_config.lua")
dofile("data/scripts/chaos/depot_core.lua")
-- tabs nearly full: one general entry left
for i = 1, 4 * cfg.tabSize - 1 do
	DB.nextId = DB.nextId + 1
	DB.rows[DB.nextId] = {id = DB.nextId, player = 7, item = 4000, count = 1, codec = "blob", data = "", tab = 1 + math.floor((i - 1) / cfg.tabSize),
		classes = "", name = "relic", info = "", rarity = 0, state = 0, seq = 0, source = "deposit"}
end
local moved, overflow, kept, finished = S.migrateDepot(h6)
eq(#box1.children .. "/" .. #box2.children, "0/0", "the boxes are emptied (and stay)")
eq(#chest1.children, 3, "the boxes stay in the chest, the bag with a kept item stays")
eq(#box3bag.children, 1, "the unique-id item stays in its bag")
eq(#chest2.children, 0, "the second town's chest too")
eq(kept, 2, "kept: the unique-id item and its bag")
eq(DB.plain["7:2148"] and DB.plain["7:2148"].count, 200, "the gold merged")
eq(DB.plain["7:7618"] and DB.plain["7:7618"].tab, 104, "the potions into Supplies")
eq(DB.plain["7:2268"] and DB.plain["7:2268"].tab, 104, "the runes into Supplies")
local oldTab = 0
for _, r in pairs(DB.rows) do
	if r.player == 7 and r.tab == cfg.oldDepot.tab and r.state == 0 then oldTab = oldTab + 1 end
end
for _, r in pairs(DB.plain) do
	if r.player == 7 and r.tab == cfg.oldDepot.tab then oldTab = oldTab + 1 end
end
check(oldTab >= 2 and overflow >= oldTab, "what fitted no tab went to Old depot (" .. oldTab .. " entries, " .. overflow .. " items)")
eq(moved, 9, "moved: sword, 2 gold, ring, potions, bag, relic, the armour beside the unique item, runes")
eq(finished, true, "finished (the kept items wait in the depot, withdraw-only)")
eq(h6.storage[cfg.storage.migrated], cfg.depot.version, "the version is marked")
eq(DB.logs[#DB.logs] and DB.logs[#DB.logs].action, "migrate", "logged")
eq(DB.logs[#DB.logs] and DB.logs[#DB.logs].moved, 9, "logged with its counts")
eq(openRows(), 0, "no journal row left")
local m3 = S.migrateDepot(h6)
eq(m3, 0, "idempotent: a second opening moves nothing")
-- a new migration version (the unique item taken out by hand meanwhile): the rest moves
table.remove(box3bag.children, 1)
h6.storage[cfg.storage.migrated] = nil
local m2, _, k2, fin2 = S.migrateDepot(h6)
eq(fin2, true, "finished")
eq(k2, 0, "nothing kept")
eq(m2, 1, "the bag, empty now, moved")
eq(#chest1.children, 2, "only the two boxes are left in the chest")
-- a big depot moves in batches
resetDB()
local h10 = newPlayer(11)
local many = {}
for i = 1, cfg.migrationBatch + 5 do
	local it = newItem(4000)
	it.custom.n = i
	many[i] = it
end
h10.chests[1] = container(2594, {container(25453, many)})
local mb, _, _, finB = S.migrateDepot(h10)
eq(mb, cfg.migrationBatch, "one batch per opening")
eq(finB, false, "not finished yet")
has(h10.texts[#h10.texts], "next login", "told that more moves later")
local mb2, _, _, finB2 = S.migrateDepot(h10)
eq(mb2 .. "/" .. tostring(finB2), "5/true", "the rest at the next opening")
-- the Old depot tab is withdraw-only
local view7 = S.viewOf(h6)
eq(K.writable(cfg, view7, cfg.oldDepot.tab), false, "Old depot withdraw-only")
-- migration needs the blob
blobMethods(false)
h6.storage[cfg.storage.migrated] = nil
local _, _, _, fin4 = S.migrateDepot(h6)
eq(fin4, false, "no migration without engine patch 0017")
blobMethods(true)

-- rows of the offline tool (tools/migrate_depot_stash.py): described, plain stacks merged, then placed
resetDB()
local h7 = newPlayer(8)
local cB, dB = IC.encode(rolled())
DB.rows[1] = {id = 1, player = 8, item = 2400, count = 3, codec = cB, data = dB, tab = 0, classes = "", name = "", info = "",
	rarity = 0, state = 0, seq = 0, source = "depot"}
DB.rows[2] = {id = 2, player = 8, item = 2148, count = 77, codec = "blob", data = ChaosItemCodecCore.hex(string.char(15, 77)), tab = 0,
	classes = "", name = "", info = "", rarity = 0, state = 0, seq = 0, source = "depot"}
DB.nextId = 2
req(h7, {make = "SendItems"})
eq(DB.rows[1].name, "Doombringer", "tool row described")
eq(DB.rows[1].classes, "weapons,", "and classified")
eq(DB.rows[1].tab, 1, "and placed")
eq(DB.rows[1].count, 1, "a whole item that does not stack counts 1 (the engine's count column held its charges)")
eq(DB.rows[2], nil, "a plain stack row merged")
eq(DB.plain["8:2148"] and DB.plain["8:2148"].count, 77, "into chaos_stash")

-- the never-stash list
resetDB()
local h8 = newPlayer(9)
local coin = newItem(2152, 3)
h8.bp().children[1] = coin
coin.parent = h8.bp()
req(h8, {make = "ChangeStash", Pos = {x = 65535, y = 64, z = 0}})
eq(last("addBlockItem") and last("addBlockItem").status, true, "on the list")
req(h8, {make = "Stash", Pos = {x = 65535, y = 64, z = 0}})
has(lastCancel(h8), "never-stash", "a listed item is refused")
eq(coin.removed, nil, "and stays")
req(h8, {make = "ChangeStash", RemoveUI = true, itemId = 2152})
eq(last("addBlockItem") and last("addBlockItem").status, false, "off the list")
req(h8, {make = "Stash", Pos = {x = 65535, y = 64, z = 0}})
eq(coin.removed, true, "then it goes in")

-- affinity ownership through the Pact and achievements in the engine
resetDB()
ChaosPact = {limit = function() return 4 end, state = function() return {extras = {stashWeapons = 1}} end,
	active = function() return true end}
local h9 = newPlayer(10)
local wpn = newItem(2400)
h9.bp().children[1] = wpn
wpn.parent = h9.bp()
req(h9, {make = "Stash", Pos = {x = 65535, y = 64, z = 0}})
local wrow = DB.rows[DB.nextId]
eq(wrow and wrow.tab, 105, "a weapon goes to the bought Weapons tab")
has(lastText(h9), "(Weapons tab)", "the line names the tab")
DB.ach.unique_50 = true
local v9 = S.viewOf(h9, true)
eq(v9.owned.cosmetics, "achievement", "Collectibles earned by an achievement")
eq(v9.owned.products, "pact", "Products lent by the Pact")

-- remote deposit (owner 2026-10-15): bought or lent by the Pact; withdraw stays in town for everybody
local extras, pactOn = {}, true
ChaosPact = {limit = function() return 4 end, state = function() return {extras = extras} end,
	active = function() return pactOn end}
pz[key3(h9.pos)] = nil
local function depositOutside(label, expectOk)
	local it = newItem(2472)
	it.custom.n = label
	h9.bp().children[#h9.bp().children + 1] = it
	it.parent = h9.bp()
	req(h9, {make = "Stash", Pos = {x = 65535, y = 64, z = #h9.bp().children - 1}})
	eq(it.removed == true, expectOk, label)
	return it
end
depositOutside("the Pact active, outside town: remote deposit works", true)
eq(S.viewOf(h9).remote, "pact", "lent by the Pact")
pactOn = false
depositOutside("the Pact ended: remote deposit stops", false)
has(lastCancel(h9), "protection zone", "and says why")
check(activeRows(10) >= 2, "nothing stored before is lost when the Pact ends")
extras.stashRemote = 1
depositOutside("bought unlock, outside town: remote deposit works", true)
eq(S.viewOf(h9).remote, "bought", "bought once")
req(h9, {make = "StashAllRequest"})
check(last("StowReport") ~= nil, "bought unlock: Stow Everything from anywhere")
local stored
for _, r in pairs(DB.rows) do
	if r.player == 10 and r.state == 0 then stored = r end
end
req(h9, {make = "Redeem", row = stored.id})
has(lastCancel(h9), "protection zone", "withdraw outside town refused even with the unlock")
eq(DB.rows[stored.id] and DB.rows[stored.id].state, 0, "still stored")
req(h9, {make = "SendItems"})
eq(tostring(last("tabs").canDeposit) .. "/" .. tostring(last("tabs").depositWhy) .. "/" .. tostring(last("tabs").canWithdraw), "true/remote/false",
	"tabs: remote deposit, no withdraw")
eq(K.canDeposit(cfg, {remote = nil}, {pz = false}), false, "core: free outside")
eq(select(2, K.canDeposit(cfg, {remote = nil}, {hideout = true})), "hideout", "core: a hideout counts as town")
eq(select(2, K.canDeposit(cfg, {remote = "bought"}, {pz = true})), "pz", "core: in town the zone is the reason")
eq(K.view(cfg, {extras = {stashRemote = 1}}).remote, "bought", "core: bought")
eq(K.view(cfg, {pact = true}).remote, "pact", "core: the Pact")
eq(K.view(cfg, {pact = false}).remote, nil, "core: the Pact ended")
ChaosPact = nil

-- ====================================================================== staff (admin panel economy.stash_*)
do
resetDB()
local st = newPlayer(20)
local function openCount() return openRows() end
local okG, textG = S.staffGive(st, 2148, 500, 0)
check(okG, "staff give: a plain stack (" .. tostring(textG) .. ")")
eq(DB.plain["20:2148"] and DB.plain["20:2148"].count, 500, "staff give: one merged entry of 500")
eq(openCount(), 0, "staff give: no journal row left open")
check((st.saves or 0) >= 1 and (st.storage[cfg.storage.seq] or 0) >= 1, "staff give: the serial saved with the character")
okG = S.staffGive(st, 2400, 2, 0)
eq(okG and activeRows(20), 2, "staff give: an item that does not stack is one row each")
okG = S.staffGive(st, 2472, 1, 2)
local armorRow
for _, r in pairs(DB.rows) do
	if r.player == 20 and r.item == 2472 then armorRow = r end
end
eq(okG and armorRow and armorRow.tab, 2, "staff give into a named tab")
eq(armorRow and armorRow.source, "staff", "the row says who made it")
eq(select(1, S.staffGive(st, 2400, 1, cfg.oldDepot.tab)), false, "never into the Old depot tab")
eq(select(1, S.staffGive(st, 2400, 101, 0)), false, "at most 100 whole items at once")
eq(select(1, S.staffGive(st, 2148, 0, 0)), false, "a count of 0 is refused")
st.saveOk = false
local rowsBefore = activeRows(20)
eq(select(1, S.staffGive(st, 2400, 1, 0)), false, "a failed save: not stored")
eq(activeRows(20) .. "/" .. openCount(), rowsBefore .. "/0", "and nothing left behind")
st.saveOk = true
local tabsS, entriesS, itemsS = S.staffSummary(20)
eq(entriesS .. "/" .. itemsS, "4/503", "summary: entries and items")
check(#tabsS >= 2 and tabsS[1].tab <= tabsS[#tabsS].tab, "summary: per tab, sorted")
local plainF, rowsF = S.staffFind(20, 2400)
eq(plainF.count .. "/" .. #rowsF, "0/2", "find: the two swords as rows")
eq(select(1, S.staffRemove(st, {item = 2148, count = 200})), true, "staff remove from the stack")
eq(DB.plain["20:2148"].count, 300, "300 left")
eq(select(1, S.staffRemove(st, {row = rowsF[1].id})), true, "staff remove one row")
eq(DB.rows[rowsF[1].id], nil, "the row is gone")
eq(select(1, S.staffRemove(st, {item = 2148, count = 999999})), true, "a count over the stack is clamped")
eq(DB.plain["20:2148"], nil, "the stack is gone")
eq(select(1, S.staffRemove(st, {row = 999})), false, "an unknown row is refused")
eq(openCount(), 0, "staff remove: no journal row left open")
eq(#st.bp().children, 0, "staff give and remove never touch the backpack")
end

-- ====================================================================== the SQL
-- the real store, against a recording database: integers formatted as integers, texts escaped
dofile("data/scripts/chaos/stash.lua")
local real = ChaosStash.store
queries = {}
local evil = "x'); DROP TABLE players; --"
real.insert(1, {itemId = 2400.7, count = 1, codec = evil, data = evil, tab = 3, classes = evil, name = evil, info = evil,
	rarity = 999, source = evil}, 9, 4)
real.describe(1, 5, evil, evil, evil, -3)
real.achievements(1, {evil})
real.block(1, 2152.9, true)
real.log(1, evil, 1, 0, 0, evil)
real.drop(1, "5 OR 1=1", 9)
for _, q in ipairs(queries) do
	check(not q:find("x'); DROP", 1, true), "no raw client text in: " .. q:sub(1, 60))
	check(not q:find("%d%.%d"), "no fraction in: " .. q:sub(1, 60))
	check(not q:find("OR 1=1", 1, true), "no injected id in: " .. q:sub(1, 60))
end
check(#queries >= 5, "the store wrote its queries (" .. #queries .. ")")

print(string.format("stash_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
