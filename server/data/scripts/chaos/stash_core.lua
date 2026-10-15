-- The stash: the rules, without engine calls (stash.lua; server/tests/stash_test.lua). Config: stash_config.lua.
--
-- Items. An item is described by its facts (stash.lua factsOf builds them from the item and its type):
--   {id, name (lower case), count, stackable, plain (nothing but id and count), container, contents (items inside),
--    pickupable, movable, kind ("orbs" | "gems" | "keys" | nil), gear (chaos_item_mods.lua kind or nil),
--    rune, fluid, ammo, food, key, riftKey, material, product, cosmetic (flags), price (what an NPC pays, plain copy),
--    actionId, uniqueId, bound (store-bound or a store item), locked (the item lock), blocked (never-stash list)}
--   K.flagsOf(cfg, f)                   the flags of f, with "product" for sellable loot that is nothing else
--   K.classify(cfg, f)                  the affinity keys f matches, in routing order
--   K.entryKey(f)                       "s<id>" for a plain stack (merged by type), nil for a whole item (a row each)
--
-- Tabs. General tabs 1..n (n = K.view general) take anything; affinity tabs (cfg.affinities, ids 101..) take their
-- class; the Old depot tab (cfg.oldDepot.tab) holds what the depot migration could not place: withdraw-only, never full.
-- A tab beyond the general count, an affinity tab no longer owned and the Old depot tab are withdraw-only. Nothing is
-- ever deleted when a limit shrinks.
--   K.view(cfg, ctx)                    {general = n, owned = {key = source}}; ctx = {stashTabs (pact limit), extras =
--                                       {key = n}, pact = bool, achievements = {id = true}}
--   K.writable(cfg, view, tab), K.sizeOf(cfg, tab), K.counts(entries)
--   K.layout(cfg, view, entries)        places entries of tab 0 / an unknown tab (writable tabs first, then e.overflow
--                                       or a withdraw-only general tab), moves entries of a general tab into their owned
--                                       affinity tab while it has room; returns {{key, tab}} moves
--   K.route(cfg, view, used, own, classes)   the tab of one more entry (own = the merged entry already stored, or nil)
--   K.plan(cfg, view, entries, items, opts)  tabs for a list of items (stow, migration): plan {{ref, tab, key}},
--                                       skipped {{ref, reason}}; the room is counted as it fills
--   K.tabsView(cfg, view, entries)      the tab bar {{id, name, used, size, locked, affinity, icon, old}}
--
-- Rules.
--   K.depositRefusal(cfg, f)            why one dragged item cannot go in (a message key of cfg.messages), or nil
--   K.stowSkip(cfg, f)                  why Stow Everything leaves an item (a key of cfg.reasons), or nil
--   K.report(cfg, stowed, skipped)      the Stow Everything report {stowed, kept, reasons = {{reason, label, count, names}}}
--   K.canWithdraw(cfg, place)           place = {pz = bool, hideout = bool}
--
-- The journal (no item lost or doubled by a crash or a failed save; server/README.md "Stash", "Write order"):
-- every deposit and withdrawal is first a row of chaos_stash_items in a journal state with a serial `seq`; the
-- character's storage cfg.storage.seq is set to that serial in memory and saved with the items in ONE transaction
-- (player:save()). So whatever a crash leaves behind, the saved serial says which side is true:
--   depositing (9) seq <= saved: the item left the character in the saved state -> the row becomes active ("activate")
--                  seq >  saved: the item is still in the saved character             -> the row is dropped ("drop")
--   taking (8)     seq <= saved: the item reached the character in the saved state  -> the row is dropped ("done")
--                  seq >  saved: the item never reached it                          -> the row is active again ("restore")
--   K.recoverAction(state, seq, saved)
--   K.recover(env, rows, saved)         applies those actions; false when a row could not be fixed (no new operation
--                                       starts then)
--   K.deposit(env, recs)                a batch of deposits (one save): done, failed {{rec, reason}}
--   K.withdraw(env, rec)                one withdrawal: true | false, reason
-- env (stash.lua: the engine and the database; the test: a simulated world with crashes):
--   getSeq() / setSeq(n)                the serial storage (in memory)
--   pending() -> rows                   journal rows not settled yet ({id, state, seq, ...})
--   insert(rec, seq) -> id              a depositing row (database, at once)
--   remove(rec) -> bool                 the item leaves the character (in memory)
--   restore(rec)                        a removed item comes back (in memory)
--   activate(seq, recs) -> bool         the depositing rows of seq become stash entries (plain stacks merge)
--   drop(row) -> bool                   a depositing row is deleted
--   take(rec, seq) -> bool              an entry becomes a taking row (a plain stack: the amount leaves its entry)
--   give(rec) -> bool                   the item is created on the character (in memory)
--   ungive(rec)                         the created item goes away again (in memory)
--   untake(rec) -> bool                 a taking row becomes an entry again
--   finish(rec) -> bool                 a taking row is deleted
--   save() -> bool                      player:save()
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosStashCore = ChaosStashCore or {}
local K = ChaosStashCore

K.STATE_ACTIVE = 0
K.STATE_TAKING = 8
K.STATE_DEPOSITING = 9

local function int(v)
	v = tonumber(v) or 0
	if v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.floor(v)
end

local function set(list)
	local s = {}
	for _, v in ipairs(list or {}) do
		s[v] = true
	end
	return s
end

-- ---------------------------------------------------------------- affinities
local cache = setmetatable({}, {__mode = "k"})
local function index(cfg)
	local c = cache[cfg]
	if not c then
		c = {byKey = {}, byTab = {}}
		for _, a in ipairs(cfg.affinities or {}) do
			c.byKey[a.key] = a
			c.byTab[a.tab] = a
		end
		cache[cfg] = c
	end
	return c
end

function K.affinity(cfg, key)
	return index(cfg).byKey[key]
end

function K.affinityByTab(cfg, tab)
	return index(cfg).byTab[int(tab)]
end

local function isOld(cfg, tab)
	return cfg.oldDepot ~= nil and int(tab) == int(cfg.oldDepot.tab)
end

-- ---------------------------------------------------------------- classes
local function hasWord(name, words)
	if type(name) ~= "string" or name == "" then
		return false
	end
	for _, w in ipairs(words or {}) do
		if name:find("%f[%a]" .. w .. "%f[%A]") then
			return true
		end
	end
	return false
end
K.hasWord = hasWord

function K.flagsOf(cfg, f)
	local flags = {}
	for _, k in ipairs({"rune", "fluid", "ammo", "food", "key", "riftKey", "material", "product", "cosmetic"}) do
		if f[k] then
			flags[k] = true
		end
	end
	if not flags.food and f.food == nil and not f.gear and hasWord(f.name, cfg.foodWords) then
		flags.food = true
	end
	-- sellable loot that is nothing else: a creature product
	if not flags.product and int(f.price) > 0 and not f.gear and not f.kind and not f.container then
		local other = false
		for k in pairs(flags) do
			other = other or k ~= "product"
		end
		if not other then
			flags.product = true
		end
	end
	return flags
end

local function matches(a, f, flags)
	local m = a.match or {}
	for _, k in ipairs(m.kinds or {}) do
		if f.kind == k then
			return true
		end
	end
	for _, g in ipairs(m.gear or {}) do
		if f.gear == g then
			return true
		end
	end
	for _, fl in ipairs(m.flags or {}) do
		if flags[fl] then
			return true
		end
	end
	for _, id in ipairs(m.ids or {}) do
		if int(f.id) == int(id) then
			return true
		end
	end
	if m.words and not f.gear and hasWord(f.name, m.words) then
		return true
	end
	return false
end

function K.classify(cfg, f)
	local flags = K.flagsOf(cfg, f)
	local out = {}
	for _, a in ipairs(cfg.affinities or {}) do
		if matches(a, f, flags) then
			out[#out + 1] = a.key
		end
	end
	return out
end

function K.entryKey(f)
	if f.plain and f.stackable then
		return "s" .. int(f.id)
	end
	return nil
end

-- "weapons,armor" <-> {"weapons", "armor"} (the classes stored with a whole item)
function K.packClasses(list)
	return table.concat(list or {}, ",")
end

function K.unpackClasses(cfg, text)
	local out = {}
	for k in tostring(text or ""):gmatch("[%w_]+") do
		if K.affinity(cfg, k) then
			out[#out + 1] = k
		end
	end
	return out
end

-- ---------------------------------------------------------------- tabs
function K.view(cfg, ctx)
	ctx = ctx or {}
	local extras = ctx.extras or {}
	local achieved = ctx.achievements or {}
	local general = int(ctx.stashTabs)
	for _, id in ipairs(cfg.generalAchievements or {}) do
		if achieved[id] then
			general = general + 1
		end
	end
	if cfg.depotTabsCount then
		general = general + math.max(0, int(ctx.depotTabs))
	end
	general = math.max(0, math.min(general, int(cfg.maxGeneralTabs)))
	local owned = {}
	for _, a in ipairs(cfg.affinities or {}) do
		local source
		if a.free then
			source = "free"
		elseif a.extra and int(extras[a.extra]) > 0 then
			source = "bought"
		elseif a.pact and ctx.pact then
			source = "pact"
		else
			for _, id in ipairs(a.achievements or {}) do
				if achieved[id] then
					source = "achievement"
				end
			end
		end
		owned[a.key] = source
	end
	return {general = general, owned = owned}
end

function K.sizeOf(cfg, tab)
	if isOld(cfg, tab) then
		return math.huge
	end
	local a = K.affinityByTab(cfg, tab)
	return a and int(a.size) or int(cfg.tabSize)
end

function K.writable(cfg, view, tab)
	tab = int(tab)
	if isOld(cfg, tab) then
		return false
	end
	local a = K.affinityByTab(cfg, tab)
	if a then
		return view.owned[a.key] ~= nil
	end
	return tab >= 1 and tab <= int(view.general)
end

-- a tab id that may hold entries: a general tab (1 .. maxGeneralTabs), an affinity tab or the Old depot tab
local function known(cfg, tab)
	tab = int(tab)
	return (tab >= 1 and tab <= int(cfg.maxGeneralTabs)) or K.affinityByTab(cfg, tab) ~= nil or isOld(cfg, tab)
end

function K.counts(entries)
	local used = {}
	for _, e in ipairs(entries or {}) do
		local t = int(e.tab)
		if t > 0 then
			used[t] = (used[t] or 0) + 1
		end
	end
	return used
end

local function room(cfg, used, tab)
	return (used[tab] or 0) < K.sizeOf(cfg, tab)
end

local function affinityTab(cfg, view, used, classes)
	for _, key in ipairs(classes or {}) do
		local a = K.affinity(cfg, key)
		if a and view.owned[key] and room(cfg, used, a.tab) then
			return a.tab
		end
	end
	return nil
end

-- a general tab with room: a writable one, else (allowLocked) the first tab above the count with room
local function generalTab(cfg, view, used, allowLocked)
	local max = int(cfg.maxGeneralTabs)
	for t = 1, max do
		local writable = t <= int(view.general)
		if not writable and not allowLocked then
			return nil
		end
		if room(cfg, used, t) then
			return t
		end
	end
	return nil
end

function K.route(cfg, view, used, own, classes)
	if own and int(own.tab) > 0 and K.writable(cfg, view, own.tab) then
		return int(own.tab) -- a merged stack stays where it is: no new entry
	end
	local target = affinityTab(cfg, view, used, classes) or generalTab(cfg, view, used, false)
	if target then
		return target
	end
	for t in pairs(used) do
		if not K.writable(cfg, view, t) and not isOld(cfg, t) then
			return nil, "locked"
		end
	end
	return nil, "full"
end

function K.layout(cfg, view, entries)
	local used = K.counts(entries)
	for _, e in ipairs(entries) do
		local t = int(e.tab)
		if t ~= 0 and not known(cfg, t) then
			used[t] = (used[t] or 1) - 1
			e.tab = 0
		end
	end
	local order = {}
	for i, e in ipairs(entries) do
		order[i] = e
	end
	table.sort(order, function(a, b) return tostring(a.key) < tostring(b.key) end)
	local moves = {}
	for _, e in ipairs(order) do
		local t = int(e.tab)
		local target
		if t <= 0 then
			-- an entry with e.overflow (the depot migration) goes there rather than into a withdraw-only general tab
			target = affinityTab(cfg, view, used, e.classes) or generalTab(cfg, view, used, e.overflow == nil) or e.overflow
				or (cfg.oldDepot and cfg.oldDepot.tab)
		elseif not K.affinityByTab(cfg, t) and not isOld(cfg, t) then
			target = affinityTab(cfg, view, used, e.classes) -- an orb in a general tab moves to the owned Orbs tab
		end
		if target and target ~= t then
			if t > 0 then
				used[t] = (used[t] or 1) - 1
			end
			used[target] = (used[target] or 0) + 1
			e.tab = target
			moves[#moves + 1] = {key = e.key, tab = target}
		end
	end
	return moves
end

-- items = {{ref, key (K.entryKey), classes, count, skip}}; opts = {overflow = tab (the migration: what fits nowhere),
-- counts = {key = count stored} (plain stacks), maxStack}
function K.plan(cfg, view, entries, items, opts)
	opts = opts or {}
	local used = K.counts(entries)
	local byKey = {}
	for _, e in ipairs(entries) do
		if e.key then
			byKey[e.key] = e
		end
	end
	local counts = {}
	for k, n in pairs(opts.counts or {}) do
		counts[k] = int(n)
	end
	local maxStack = int(opts.maxStack or cfg.maxStackPerEntry)
	local plan, skipped = {}, {}
	for _, it in ipairs(items) do
		if it.skip then
			skipped[#skipped + 1] = {ref = it.ref, reason = it.skip}
		else
			local own = it.key and byKey[it.key] or nil
			local tab, why
			if it.key and (counts[it.key] or 0) + int(it.count) > maxStack then
				why = "limit"
			else
				tab, why = K.route(cfg, view, used, own, it.classes)
				if tab then
					if own and int(own.tab) ~= tab then
						-- a merged stack in a withdraw-only tab moves with the deposit into the writable tab
						used[int(own.tab)] = (used[int(own.tab)] or 1) - 1
						used[tab] = (used[tab] or 0) + 1
						own.tab = tab
					elseif not own then
						used[tab] = (used[tab] or 0) + 1
					end
				elseif opts.overflow then
					if own then
						tab = int(own.tab) -- the migration joins the stack's withdraw-only entry (one entry per type)
					else
						tab = int(opts.overflow)
						used[tab] = (used[tab] or 0) + 1
					end
				end
				if tab and it.key and not own then
					byKey[it.key] = {key = it.key, tab = tab}
				end
			end
			if tab then
				if it.key then
					counts[it.key] = (counts[it.key] or 0) + int(it.count)
				end
				plan[#plan + 1] = {ref = it.ref, tab = tab, key = it.key}
			else
				skipped[#skipped + 1] = {ref = it.ref, reason = why == "limit" and "limit" or "full"}
			end
		end
	end
	return plan, skipped
end

function K.tabsView(cfg, view, entries)
	local used = K.counts(entries)
	local out = {}
	local highest = int(view.general)
	for t in pairs(used) do
		if t <= int(cfg.maxGeneralTabs) and t > highest then
			highest = t
		end
	end
	for t = 1, highest do
		out[#out + 1] = {id = t, name = tostring(t), used = used[t] or 0, size = K.sizeOf(cfg, t),
			locked = not K.writable(cfg, view, t)}
	end
	for _, a in ipairs(cfg.affinities or {}) do
		if view.owned[a.key] or (used[a.tab] or 0) > 0 then
			out[#out + 1] = {id = a.tab, name = a.name, used = used[a.tab] or 0, size = int(a.size),
				locked = not K.writable(cfg, view, a.tab), affinity = a.key, icon = a.icon, source = view.owned[a.key]}
		end
	end
	local old = cfg.oldDepot
	if old and (used[old.tab] or 0) > 0 then
		out[#out + 1] = {id = old.tab, name = old.name, used = used[old.tab], size = 0, locked = true, old = true,
			icon = old.icon}
	end
	return out
end

-- ---------------------------------------------------------------- rules
function K.depositRefusal(cfg, f)
	if not f or not f.id then
		return "taken"
	end
	if f.pickupable == false or f.movable == false then
		return "cannot"
	end
	if f.container and int(f.contents) > 0 then
		return "container"
	end
	if int(f.uniqueId) > 0 then
		return "cannot"
	end
	if f.blocked then
		return "blocked"
	end
	return nil
end

function K.stowSkip(cfg, f)
	if f.container then
		return "container"
	end
	if f.pickupable == false or f.movable == false then
		return "fixed"
	end
	if f.bound then
		return "bound"
	end
	if f.locked then
		return "locked"
	end
	if int(f.uniqueId) > 0 or (int(f.actionId) > 0 and not (cfg.stowActionIds or {})[int(f.actionId)]) then
		return "quest"
	end
	if f.blocked then
		return "blocked"
	end
	return nil
end

-- stowed = {{name, count}}; skipped = {{name, reason}} (reason: a key of cfg.reasons)
function K.report(cfg, stowed, skipped)
	local out = {stowed = 0, kept = 0, reasons = {}}
	for _, s in ipairs(stowed or {}) do
		out.stowed = out.stowed + math.max(1, int(s.count))
	end
	local byReason = {}
	for _, s in ipairs(skipped or {}) do
		local r = byReason[s.reason]
		if not r then
			r = {reason = s.reason, label = (cfg.reasons or {})[s.reason] or s.reason, count = 0, names = {}}
			byReason[s.reason] = r
			out.reasons[#out.reasons + 1] = r
		end
		r.count = r.count + 1
		out.kept = out.kept + 1
		if #r.names < int(cfg.reportNames) then
			local seen = false
			for _, n in ipairs(r.names) do
				seen = seen or n == s.name
			end
			if not seen and type(s.name) == "string" then
				r.names[#r.names + 1] = s.name
			end
		end
	end
	table.sort(out.reasons, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.reason < b.reason
	end)
	return out
end

-- "containers 3, no room 2" (the reasons of a report, for the chat line)
function K.reasonLine(rep)
	local parts = {}
	for _, r in ipairs(rep.reasons or {}) do
		parts[#parts + 1] = string.format("%s %d", r.label, r.count)
	end
	return table.concat(parts, ", ")
end

function K.canWithdraw(cfg, place)
	place = place or {}
	return place.pz == true or (cfg.withdrawInHideout == true and place.hideout == true)
end

-- ---------------------------------------------------------------- the journal
function K.recoverAction(state, seq, saved)
	seq, saved = int(seq), math.max(0, int(saved))
	if int(state) == K.STATE_DEPOSITING then
		return seq <= saved and "activate" or "drop"
	elseif int(state) == K.STATE_TAKING then
		return seq <= saved and "done" or "restore"
	end
	return "keep"
end

function K.recover(env, rows, saved)
	local ok = true
	local activate = {}
	for _, r in ipairs(rows or {}) do
		local action = K.recoverAction(r.state, r.seq, saved)
		local done = true
		if action == "activate" then
			activate[int(r.seq)] = activate[int(r.seq)] or {}
			table.insert(activate[int(r.seq)], r)
		elseif action == "drop" then
			done = env.drop(r)
		elseif action == "done" then
			done = env.finish(r)
		elseif action == "restore" then
			done = env.untake(r)
		end
		ok = ok and done ~= false
	end
	for seq, list in pairs(activate) do
		ok = env.activate(seq, list) ~= false and ok
	end
	return ok
end

-- settles what an earlier operation left (only valid while the serial in memory is the saved one: outside an operation)
local function settle(env)
	local rows = env.pending()
	if rows and #rows > 0 then
		return K.recover(env, rows, env.getSeq())
	end
	return true
end
K.settle = settle

function K.deposit(env, recs)
	local failed = {}
	if not settle(env) then
		for _, r in ipairs(recs) do
			failed[#failed + 1] = {rec = r, reason = "busy"}
		end
		return {}, failed
	end
	local seq = math.max(0, int(env.getSeq())) + 1
	local inserted = {}
	for _, r in ipairs(recs) do
		local id = env.insert(r, seq)
		if id then
			r.id = id
			inserted[#inserted + 1] = r
		else
			failed[#failed + 1] = {rec = r, reason = "busy"}
		end
	end
	local removed = {}
	for _, r in ipairs(inserted) do
		if env.remove(r) then
			removed[#removed + 1] = r
		else
			env.drop({id = r.id, state = K.STATE_DEPOSITING, seq = seq, rec = r})
			failed[#failed + 1] = {rec = r, reason = "taken"}
		end
	end
	if #removed == 0 then
		return {}, failed
	end
	local old = env.getSeq()
	env.setSeq(seq)
	if not env.save() then
		env.setSeq(old)
		for _, r in ipairs(removed) do
			env.restore(r)
			env.drop({id = r.id, state = K.STATE_DEPOSITING, seq = seq, rec = r}) -- a failure: dropped by the next settle
			failed[#failed + 1] = {rec = r, reason = "busy"}
		end
		return {}, failed
	end
	env.activate(seq, removed) -- a failure leaves them depositing: activated by the next settle or login
	return removed, failed
end

function K.withdraw(env, rec)
	if not settle(env) then
		return false, "busy"
	end
	local seq = math.max(0, int(env.getSeq())) + 1
	if not env.take(rec, seq) then
		return false, "busy"
	end
	rec.seq = seq
	if not env.give(rec) then
		env.untake(rec)
		return false, "room"
	end
	local old = env.getSeq()
	env.setSeq(seq)
	if not env.save() then
		env.setSeq(old)
		env.ungive(rec)
		env.untake(rec) -- a failure leaves it taking: restored by the next settle or login
		return false, "busy"
	end
	env.finish(rec) -- a failure leaves it taking: dropped by the next settle or login
	return true
end

return K
