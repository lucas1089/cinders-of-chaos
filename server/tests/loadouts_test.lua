-- Run from the server/ folder: luajit tests/loadouts_test.lua (or lua5.3; CI runs both)
-- Loadouts / Armory: the pure rules (loadouts_core.lua: slots, names, tree validation against changed tree data,
-- Paragon, keystones, the switching gate, the anti-dodge plans with a randomized check, crash recovery, runes, gear)
-- and the engine part (loadouts.lua) against a mocked engine: save, switch in and out of a protection zone, the
-- channel, cooldown, runes moving between loadouts, gear by reference, free refunds, crash rollback.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, 1000 + n); return 1000 + n end
end})

local failures, count = 0, 0
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

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/loadouts_config.lua")
dofile("data/scripts/chaos/loadouts_core.lua")
dofile("data/scripts/chaos/class_tree.lua")
local C, cfg = ChaosLoadoutsCore, ChaosLoadoutsConfig
local tree = dofile("data/scripts/chaos/passivetree_data.lua")

-- ================================================================== constants and config
eq(ChaosOpcodes.loadouts, 206, "opcode 206")
local seen = {}
for key, op in pairs(ChaosOpcodes) do
	check(not seen[op] or seen[op] == key, "opcode " .. op .. " used twice: " .. tostring(seen[op]) .. " / " .. key)
	seen[op] = key
end
-- the reference server's own opcodes (README "Opcode collision check")
for _, op in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(ChaosOpcodes.loadouts ~= op, "no collision with the reference server's " .. op)
end
eq(Chaos.storage.loadouts, cfg.storage.active, "storage base")
check(cfg.storage.active >= 7100570 and cfg.storage.lastSwitch <= 7100579, "storages in 7100570 - 7100579")
eq(Chaos.tables.loadouts, "chaos_loadouts", "table name")
eq(cfg.maxSlots, cfg.baseSlots + #cfg.earned + cfg.pactSlots, "max slots = base + earned + the Chaos Pact's")
check(cfg.maxSlots <= cfg.runeMirrorSlots, "the rune mirror has room for every slot")

-- ================================================================== slots
eq(C.slotLimit(8), 3, "3 free slots")
eq(C.slotLimit(199), 3, "3 below 200")
eq(C.slotLimit(200), 4, "4 at level 200")
eq(C.slotLimit(500), 5, "5 at level 500")
eq(C.slotLimit(5000), 5, "5 without the Chaos Pact")
eq(C.slotLimit(5000, nil, true), 6, "6 with the Chaos Pact (VIP)")
eq(C.slotLimit(8, nil, true), 4, "the Pact adds one at any level")
eq(C.slotLimit(5000, nil, 9), 6, "never more than maxSlots")
eq(C.slotLimit(300, nil, 0), 4, "no bonus")
eq(C.nextUnlock(100), 200, "next at 200")
eq(C.nextUnlock(300), 500, "next at 500")
eq(C.nextUnlock(600), nil, "none left")
eq(C.slotState(1, 3), "ok", "slot 1")
eq(C.slotState(4, 3), "locked", "slot 4 locked at 3")
eq(C.slotState(7, 5), "invalid", "slot 7 invalid")
eq(C.slotState(6, 5), "locked", "slot 6 locked without the Pact")
eq(C.slotState(0, 3), "invalid", "slot 0 invalid (the state row)")
eq(C.slotState(1.5, 3), "invalid", "fraction")
has(C.lockedText(300), "level 500", "locked text names the level")

-- ================================================================== names, icons, node lists
eq(C.cleanName("  Boss   run  ", 2), "Boss run", "trimmed")
eq(C.cleanName("", 2), "Loadout 2", "default name")
eq(C.cleanName("<script>x</script>", 1), "scriptxscript", "markup stripped")
eq(#C.cleanName(string.rep("a", 50), 1), cfg.nameMax, "name length")
eq(C.cleanIcon("pvp"), "pvp", "known icon")
eq(C.cleanIcon("../../x"), cfg.icons[1], "unknown icon -> first")
eq(table.concat(C.parseNodes("9,2,2,x,0,3"), ","), "9,2,3", "parse: unique positive ids")
eq(C.formatNodes({9, 2, 3}), "2,3,9", "format sorted")
check(C.sameSet({1, 2}, {2, 1}) and not C.sameSet({1}, {1, 2}), "sameSet")

-- ================================================================== tree validation
-- a connected allocation: breadth-first from the root, shared nodes only
local function bfsPath(count)
	local out, seenN, queue, head = {}, {[tree.root] = true}, {tree.root}, 1
	while head <= #queue and #out < count do
		local cur = queue[head]
		head = head + 1
		for _, nb in ipairs(tree.nodes[cur].n) do
			local node = tree.nodes[nb]
			if not seenN[nb] and node and not node.c and #out < count then
				seenN[nb] = true
				out[#out + 1] = nb
				queue[#queue + 1] = nb
			end
		end
	end
	return out
end
local function connected(t, ids)
	local set = {}
	for _, id in ipairs(ids) do set[id] = true end
	local reached, queue, head, c = {[t.root] = true}, {t.root}, 1, 0
	while head <= #queue do
		local cur = queue[head]
		head = head + 1
		for _, nb in ipairs(t.nodes[cur].n or {}) do
			if set[nb] and not reached[nb] then reached[nb] = true; c = c + 1; queue[#queue + 1] = nb end
		end
	end
	return c == #ids
end
local path = bfsPath(30)
eq(#path, 30, "test path")
local kept, removed = C.validateTree(tree, path, {points = 100})
eq(#kept, 30, "valid tree kept")
eq(#removed, 0, "nothing removed")
kept, removed = C.validateTree(tree, path, {points = 20})
eq(#kept, 20, "over budget: trimmed to the points")
eq(C.countWhy(removed).budget, 10, "10 over the budget")
check(connected(tree, kept), "trimming the deepest nodes keeps the rest connected")
for budget = 0, 30, 3 do
	local k = C.validateTree(tree, path, {points = budget})
	check(#k == math.min(budget, 30) and connected(tree, k), "trim to " .. budget .. " stays connected")
end
local withUnknown = {path[1], path[2], 999999}
kept, removed = C.validateTree(tree, withUnknown, {points = 100})
eq(#kept, 2, "unknown node dropped")
eq(C.countWhy(removed).unknown, 1, "unknown counted")
-- a class node: the class tree's own rule decides
local classNode, classOf
for id, node in pairs(tree.nodes) do
	if node.c and not classNode then
		classNode = id
		classOf = next(node.c)
	end
end
check(classNode ~= nil, "the tree has class nodes")
kept, removed = C.validateTree(tree, {classNode}, {classKey = "nobody", points = 10, allowed = ChaosClassTree.allowed})
eq(C.countWhy(removed).class, 1, "another class's node is refunded")
kept = C.validateTree(tree, {classNode}, {classKey = classOf, points = 10, allowed = ChaosClassTree.allowed})
check(#kept <= 1, "own class node is not refused for the class")
-- a balance pass moves a node: the nodes behind it no longer connect and are refunded
local small = {root = 1, nodes = {[1] = {n = {2}}, [2] = {n = {1, 3}}, [3] = {n = {2, 4}}, [4] = {n = {3}}}}
kept, removed = C.validateTree(small, {2, 3, 4}, {points = 10})
eq(#kept, 3, "small tree valid")
local moved = {root = 1, nodes = {[1] = {n = {2}}, [2] = {n = {1}}, [3] = {n = {4}}, [4] = {n = {3}}}}
kept, removed = C.validateTree(moved, {2, 3, 4}, {points = 10})
eq(table.concat(kept, ","), "2", "after the move only node 2 connects")
eq(C.countWhy(removed).disconnected, 2, "two disconnected")
local gone = {root = 1, nodes = {[1] = {n = {2}}, [2] = {n = {1}}}}
kept, removed = C.validateTree(gone, {2, 3, 4}, {points = 10})
eq(C.countWhy(removed).unknown, 2, "removed nodes counted as left the tree")
has(C.refundText(removed), "2 nodes that left the tree", "refund text")
has(C.refundText({{id = 1, why = "budget"}}, 3), "3 Paragon points", "refund text Paragon")
eq(C.refundText({}, 0), nil, "no text without refunds")

-- ================================================================== Paragon
local defs = {damage = {maxPoints = 40}, health = {maxPoints = 40}}
eq(C.encodeParagon({health = 4, damage = 3, junk = 0}), "damage=3,health=4", "encode sorted, zero dropped")
local dec = C.decodeParagon("damage=3,health=4")
eq(dec.damage, 3, "decode damage"); eq(dec.health, 4, "decode health")
local par, gone2, all = C.validateParagon({damage = 50, health = 5, nope = 2}, defs, 100)
eq(par.damage, 40, "capped at maxPoints"); eq(par.nope, nil, "unknown stat dropped"); eq(gone2, 12, "10 + 2 refunded")
eq(all, false, "kept within the budget")
par, gone2, all = C.validateParagon({damage = 30, health = 30}, defs, 50)
eq(next(par), nil, "over the budget: all refunded (as at login)"); eq(all, true, "all flag"); eq(gone2, 60, "60 points back")

-- ================================================================== keystones
eq(C.keystoneName("ksArcaneEcho"), "Arcane Echo", "keystone name")
eq(C.keystoneName("ksHundredHands"), "Hundred Hands", "keystone name 2")
local ksNode, ksVariant
for id, node in pairs(tree.nodes) do
	for key, stats in pairs(node.v or {}) do
		for stat in pairs(stats) do
			if stat:match("^ks") and not ksNode then ksNode, ksVariant = id, key end
		end
	end
end
check(ksNode ~= nil, "a keystone variant exists")
local names = C.keystones(tree, {ksNode, path[1]}, ksVariant)
eq(#names, 1, "one keystone among the nodes")
check(names[1] and not names[1]:match("^ks"), "keystone name without the prefix")

-- ================================================================== switching gate
eq(C.switchGate({level = 100, inPz = true}), "instant", "protection zone: at once")
eq(C.switchGate({level = 100, inPz = false}), "cast", "elsewhere: a channel")
local mode, why = C.switchGate({level = 100, inCombat = true, inPz = true})
eq(mode, nil, "combat refused"); has(why, "combat", "combat text")
mode, why = C.switchGate({level = 100, inPz = true, cooldownLeft = 12})
has(why, "12 seconds", "cooldown text")
mode, why = C.switchGate({level = 100, inPz = true, busy = "a rift"})
has(why, "a rift", "instance refused")
mode, why = C.switchGate({level = 3, inPz = true})
has(why, "level " .. cfg.minLevel, "low level")
mode, why = C.switchGate({level = 100, inPz = true, casting = true})
has(why, "already", "one channel at a time")
eq(C.cooldownLeft(1000, 1030), cfg.cooldownSeconds - 30, "cooldown left")
eq(C.cooldownLeft(1000, 1000 + cfg.cooldownSeconds), 0, "cooldown over")
eq(C.cooldownLeft(-1, 5), 0, "never switched")
local cast = {pos = {x = 1, y = 1, z = 7}, endMs = 3000}
eq(C.castStep(cast, 100, {x = 1, y = 1, z = 7}, false), "wait", "wait")
eq(C.castStep(cast, 100, {x = 2, y = 1, z = 7}, false), "moved", "moved")
eq(C.castStep(cast, 100, {x = 1, y = 1, z = 7}, true), "hit", "combat")
eq(C.castStep(cast, 3000, {x = 1, y = 1, z = 7}, false), "done", "done")

-- ================================================================== the anti-dodge plans
local arm = {active = 0, limit = 3, slots = {}, live = {nodes = 10, paragon = 0, runes = 0}}
local plan
plan, why = C.planLoad(arm, 1)
has(why, "empty", "load an empty slot")
plan = C.planSave(arm, 1)
eq(plan.activate, true, "first save activates"); eq(plan.copy, false, "first save is not a copy")
arm.active, arm.slots[1] = 1, {runes = 2}
plan = C.planSave(arm, 2)
eq(plan.copy, true, "save into another slot = a copy"); eq(plan.activate, false, "the active loadout stays")
arm.slots[2] = {runes = 0}
plan = C.planLoad(arm, 2)
eq(plan.park, 1, "the live build goes into the active loadout"); eq(plan.load, 2, "target"); eq(plan.cost, 0, "free")
plan, why = C.planLoad(arm, 1)
has(why, "already active", "the active one")
plan, why = C.planLoad(arm, 4)
eq(why, "locked", "slot 4 locked at level < 200")
plan, why = C.planLoad(arm, 9)
has(why, "does not exist", "slot 9")
plan, why = C.planDelete(arm, 1)
eq(plan.deactivate, true, "deleting the active loadout keeps the live build")
arm.active = 2
plan, why = C.planDelete(arm, 1)
has(why, "2 support runes", "an inactive loadout holding runes cannot be deleted")
plan = C.planDelete(arm, 2)
eq(plan.deactivate, true, "active deleted")
plan, why = C.planSave({active = 0, limit = 3, slots = {[1] = {runes = 2}}, live = {nodes = 1}}, 1)
has(why, "2 support runes of its own", "saving over a parked loadout with runes while none is active is refused")
plan = C.planSave({active = 0, limit = 3, slots = {[1] = {runes = 2}}, live = {nodes = 1}}, 2)
eq(plan.activate, true, "another slot is fine")
-- without an active loadout the live build would be lost: refused while it holds anything
local loose = {active = 0, limit = 3, slots = {[2] = {runes = 0}}, live = {nodes = 5, paragon = 0, runes = 0}}
plan, why = C.planLoad(loose, 2)
has(why, "Save your current build", "save first")
loose.live = {nodes = 0, paragon = 3, runes = 0}
plan, why = C.planLoad(loose, 2)
has(why, "Save your current build", "Paragon points count")
loose.live = {nodes = 0, paragon = 0, runes = 1}
plan, why = C.planLoad(loose, 2)
has(why, "Save your current build", "runes count")
loose.live = {nodes = 0, paragon = 0, runes = 0}
plan = C.planLoad(loose, 2)
eq(plan.park, nil, "an empty live build may be replaced")

-- randomized: save / load / delete never create a tree shape that was not made by a (priced) edit, never lose the live
-- build, and never create or destroy a rune. Edits: add a node (free) or take one back (priced, counted).
do
	local seed = 12345
	local function rnd(k)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % k + 1
	end
	local function key(set)
		local ids = {}
		for id in pairs(set) do ids[#ids + 1] = id end
		table.sort(ids)
		return table.concat(ids, ",")
	end
	local function copy(set)
		local out = {}
		for id in pairs(set) do out[id] = true end
		return out
	end
	for run = 1, 40 do
		local live = {tree = {}, runes = 0}
		local slots = {}
		local active = 0
		local made = {[""] = true} -- shapes produced by edits (and the empty start)
		local paid = 0
		local inventory = 6 -- runes carried
		local totalRunes = inventory
		for step = 1, 200 do
			local op = rnd(7)
			local s = rnd(3)
			local armNow = {active = active, limit = 3, slots = {}, live = {nodes = 0, paragon = 0, runes = live.runes}}
			for id in pairs(live.tree) do armNow.live.nodes = armNow.live.nodes + 1 end
			for slot, row in pairs(slots) do armNow.slots[slot] = {runes = row.runes} end
			if op == 1 then -- edit: add a node (free)
				live.tree[rnd(20)] = true
				made[key(live.tree)] = true
			elseif op == 2 then -- edit: take a node back (priced)
				local ids = {}
				for id in pairs(live.tree) do ids[#ids + 1] = id end
				if #ids > 0 then
					table.sort(ids)
					live.tree[ids[rnd(#ids)]] = nil
					paid = paid + 1
					made[key(live.tree)] = true
				end
			elseif op == 3 then -- socket a carried rune (free) / take one out (priced)
				if inventory > 0 and rnd(2) == 1 then
					inventory, live.runes = inventory - 1, live.runes + 1
				elseif live.runes > 0 then
					inventory, live.runes, paid = inventory + 1, live.runes - 1, paid + 1
				end
			elseif op == 4 or op == 5 then -- save
				local p = C.planSave(armNow, s)
				if p then
					local old = slots[s]
					slots[s] = {tree = copy(live.tree), runes = p.copy and (old and old.runes or 0) or 0}
					if p.activate then active = s end
				end
			elseif op == 6 then -- load
				local p = C.planLoad(armNow, s)
				if p then
					if p.park then
						slots[p.park].tree = copy(live.tree)
						slots[p.park].runes = live.runes
					end
					live.tree = copy(slots[s].tree)
					live.runes = slots[s].runes
					slots[s].runes = 0
					active = s
					eq(p.cost, 0, "switch is free")
				end
			else -- delete
				local p = C.planDelete(armNow, s)
				if p then
					check(s == active or (slots[s].runes or 0) == 0, "deleted slot held no parked runes")
					slots[s] = nil
					if p.deactivate then active = 0 end
				end
			end
			-- invariants
			check(made[key(live.tree)], "live shape was made by an edit (run " .. run .. ")")
			for slot, row in pairs(slots) do
				check(made[key(row.tree)], "slot shape was made by an edit (run " .. run .. ", slot " .. slot .. ")")
			end
			local runes = inventory + live.runes
			for _, row in pairs(slots) do runes = runes + (row.runes or 0) end
			eq(runes, totalRunes, "runes conserved")
		end
	end
end

-- ================================================================== crash recovery
eq(C.recoverAction(4, 4), "ok", "in step")
eq(C.recoverAction(4, 5), "rollback", "database one ahead: undo")
eq(C.recoverAction(-1, 1), "rollback", "first switch never saved")
eq(C.recoverAction(5, 3), "adopt", "older database (backup)")
eq(C.recoverAction(-1, 0), "ok", "nothing yet")

-- ================================================================== runes
local layout = {[10] = {32101, 0, 32150}, [20] = {0, 0, 0}, [499] = {32200, 0, 0}}
eq(C.runeCount(layout), 3, "rune count")
local enc = C.encodeRunes(layout)
eq(enc, "10:32101/0/32150;499:32200/0/0", "encode runes (empty spells dropped)")
local back = C.decodeRunes(enc)
eq(back[10][3], 32150, "decode runes"); eq(back[499][1], 32200, "decode runes 499")
local keep, giveBack, dropped = C.planRestore({[10] = {32101, 0, 0}, [11] = {32102, 0, 0}, [12] = {5, 0, 0}},
	function(id) return id ~= 11 end, function(id) return id >= 32101 and id <= 32200 end)
eq(keep[10][1], 32101, "kept"); eq(#giveBack, 1, "spell gone: rune given back"); eq(#dropped, 1, "rune type gone: dropped")
eq(C.mirrorSpan(499), 2000, "mirror span")
eq(C.mirrorKey(1, 0, 1, cfg, 499), 7112001, "first mirror key")
local last = C.mirrorKey(cfg.runeMirrorSlots, 499, 3, cfg, 499)
check(last <= 7127999, "mirror keys stay in 7112000 - 7127999 (" .. last .. ")")
check(C.mirrorKey(2, 0, 1, cfg, 499) > C.mirrorKey(1, 499, 3, cfg, 499), "slot ranges do not overlap")
check(C.mirrorKey(1, 0, 0, cfg, 499) > 7111999, "above the live support sockets (7110000 - 7111999)")

-- ================================================================== gear
local sword = {id = 3264, iid = "1790000000001", name = "sword"}
local plainRing = {id = 3051, iid = "", name = "energy ring"}
check(C.matches(sword, {id = 9999, iid = "1790000000001"}), "per-item id matches whatever the type")
check(not C.matches(sword, {id = 3264, iid = "1790000000002"}), "another item of the same type does not")
check(C.matches(plainRing, {id = 3051, iid = ""}), "plain item by type")
check(not C.matches(plainRing, {id = 3051, iid = "55"}), "a plain reference never takes an item with an id")
check(not C.matches({empty = true}, {id = 1}), "empty never matches")
eq(C.iidString(1790000000001), "1790000000001", "iid as a decimal string")
eq(C.iidString(0), "", "no iid")
local slots = cfg.gearSlots
local set = {[6] = sword, [9] = plainRing, [5] = {empty = true}, [1] = {id = 3351, iid = "", name = "steel helmet"}}
local curSword = {id = 3264, iid = "1790000000001", name = "sword", where = "backpack"}
local curShield = {id = 3425, iid = "", name = "shield", where = "slot", slot = 5}
local curRing = {id = 3051, iid = "", name = "energy ring", where = "slot", slot = 9}
local steps = C.planGear(set, {[5] = curShield, [9] = curRing}, {curSword, {id = 3264, iid = "1790000000001", name = "dup"}}, slots)
local bySlot = {}
for _, s in ipairs(steps) do bySlot[s.slot] = s end
eq(bySlot[9].action, "keep", "ring already on")
eq(bySlot[5].action, "clear", "shield hand must be empty")
eq(bySlot[6].action, "equip", "sword from the backpack"); check(bySlot[6].item == curSword, "first match used")
eq(bySlot[1].action, "missing", "helmet missing")
eq(bySlot[2], nil, "a slot outside the set is not touched")
local sum = C.gearSummary(steps)
eq(sum.total, 3, "three items in the set"); eq(sum.ready, 2, "two ready"); eq(sum.missing[1].name, "steel helmet", "missing named")
-- an item equipped in another slot is moved, and never used twice
local axe = {id = 3274, iid = "77", name = "axe", where = "slot", slot = 6}
steps = C.planGear({[5] = {id = 3274, iid = "77", name = "axe"}, [6] = {id = 3274, iid = "77", name = "axe"}}, {[6] = axe}, {}, slots)
bySlot = {}
for _, s in ipairs(steps) do bySlot[s.slot] = s end
eq(bySlot[6].action, "keep", "kept where it is")
eq(bySlot[5].action, "missing", "the same item is not used twice")
steps = C.planGear({[5] = {id = 3274, iid = "77", name = "axe"}}, {[6] = axe}, {}, slots)
eq(steps[1].action, "equip", "taken from the other hand"); check(steps[1].item == axe, "same item")
local genc = C.encodeGear({[6] = sword, [9] = plainRing, [5] = {empty = true}, [1] = {id = 3351, iid = "", name = "a|b=c:d"}}, slots)
local gdec = C.decodeGear(genc)
eq(gdec[6].iid, "1790000000001", "gear iid round trip"); eq(gdec[5].empty, true, "empty round trip")
eq(gdec[9].id, 3051, "plain id round trip"); eq(gdec[1].name, "abcd", "separators stripped from names")
eq(next(C.decodeGear("junk|7=0::x")), nil, "malformed gear ignored")
-- a set saved with a quiver in slot 10 (before engine patch 0023): the quiver is the set's off-hand item; slot 10 is
-- left out of every set (it takes nothing since 0058; a ring saved there while it was the second ring slot is dropped)
local isQ = function(id) return id == 29566 end
local legacy = C.decodeGear("6=8849::Gallowsbolt Crossbow|5=empty|10=29566:55:Haloed Quiver", isQ)
eq(legacy[5] and legacy[5].id, 29566, "legacy loadout: the quiver goes to the off-hand")
eq(legacy[5] and legacy[5].iid, "55", "the same quiver (its per-item id)")
eq(legacy[10], nil, "slot 10 is no longer part of that set")
local shielded = C.decodeGear("6=2400::sword|5=2520::shield|10=29566::quiver", isQ)
eq(shielded[5].id, 2520, "a set with a shield keeps it; its old quiver is dropped from the set")
eq(shielded[10], nil, "and slot 10 is left alone")
local ringSet = C.decodeGear("9=2357::ring|10=2165::stealth ring", isQ)
eq(ringSet[10], nil, "a ring saved in slot 10 (the second ring slot until engine patch 0058) is dropped from the set")
eq(ringSet[9] and ringSet[9].id, 2357, "the ring slot's ring stays")
eq(C.decodeGear("10=29566::quiver")[10], nil, "without a quiver test (no archery loaded) slot 10 is dropped too")
eq(C.decodeGear("13=27811::Raging Moon Badge")[13].id, 27811, "a badge in slot 13 is part of a set")

-- ================================================================== engine (loadouts.lua) against a mocked engine
local fakeNow = 1000000
os.mtime = function() return fakeNow end
CONST_SLOT_BACKPACK = 3
CONST_SLOT_RIGHT = 5
CONST_SLOT_LEFT = 6
local RV_OK = RETURNVALUE_NOERROR

-- json: a registry (the engine only encodes tables to send or store and decodes what it stored)
local registry = {}
json = {
	encode = function(t) registry[#registry + 1] = t; return "J" .. #registry end,
	decode = function(s) return registry[tonumber(tostring(s):match("^J(%d+)$") or -1)] end
}

-- database: chaos_loadouts rows, escaped strings are tokens
local DB, strings = {}, {}
db = {
	escapeString = function(s) strings[#strings + 1] = tostring(s); return "@" .. #strings .. "@" end,
	query = function(sql)
		local function val(tok)
			local i = tok:match("^@(%d+)@$")
			if i then return strings[tonumber(i)] end
			return tonumber(tok)
		end
		if sql:match("^INSERT INTO `chaos_loadouts`") then
			local list = sql:match("VALUES %((.-)%) ON DUPLICATE")
			local v = {}
			for tok in list:gmatch("[^,%s]+") do v[#v + 1] = val(tok) end
			DB[v[1]] = DB[v[1]] or {}
			DB[v[1]][v[2]] = {slot = v[2], name = v[3], icon = v[4], voc = v[5], tree = v[6], paragon = v[7], supports = v[8],
				gear = v[9], serial = v[10], undo = v[11], updated = v[12]}
		elseif sql:match("^DELETE FROM `chaos_loadouts`") then
			local g, s = sql:match("`player_id` = (%d+) AND `slot` = (%d+)")
			if DB[tonumber(g)] then DB[tonumber(g)][tonumber(s)] = nil end
		end
		return true
	end
}
Chaos.select = function(query, cols)
	local out = {}
	local g = tonumber(query:match("`player_id` = (%d+)"))
	for _, r in pairs(DB[g] or {}) do
		local copy = {}
		for k, v in pairs(r) do copy[k] = v end
		out[#out + 1] = copy
	end
	return out
end

-- engine objects
local events, pending = {}, {}
local function obj(name) local o = {}; function o:register() events[name] = o end; function o:type() end; return o end
function CreatureEvent(name) return obj(name) end
function GlobalEvent(name) return obj(name) end
function addEvent(fn, ms, ...) pending[#pending + 1] = {fn = fn, args = {...}} end
local function runPending()
	local list = pending
	pending = {}
	for _, e in ipairs(list) do e.fn((table.unpack or unpack)(e.args)) end
end
local pzFlag = true
function Tile() return {hasFlag = function() return pzFlag end} end
function Vocation(id) return {getName = function() return ({[4] = "Warrior", [11] = "Juggernaut"})[id] or "None" end} end
local deEquip = {[3088] = 3051} -- an equipped energy ring is another item id
function ItemType(id) return {getTransformDeEquipId = function() return deEquip[id] or 0 end, getClientId = function() return id end} end
Game = {getTowns = function() return {{getId = function() return 1 end, getName = function() return "Emberfall" end}} end,
	getReturnMessage = function() return "you cannot dress this object there" end}
ChaosClasses = {classKey = function() return "warrior" end}

-- items and containers
local Item = {}
Item.__index = Item
local function newItem(id, name, iid, items)
	return setmetatable({id = id, name = name, iid = iid, items = items}, Item)
end
function Item:getId() return self.id end
function Item:getName() return self.name end
function Item:getCustomAttribute(k) if k == "chaos_iid" then return self.iid end end
function Item:isContainer() return self.items ~= nil end
function Item:hasAttribute() return false end
function Item:clone() local c = newItem(self.id, self.name, self.iid); c.twoHanded = self.twoHanded; return c end
local function detach(item)
	local p = item.parent
	if p and p.items then
		for i, it in ipairs(p.items) do if it == item then table.remove(p.items, i) break end end
	elseif p and p.player then
		p.player.equip[p.slot] = nil
	end
	item.parent = nil
end
function Item:remove() detach(self); self.removed = true; return true end
function Item:moveTo(c, flags)
	if #c.items >= (c.cap or 20) then return false end
	detach(self)
	c.items[#c.items + 1] = self
	self.parent = c
	return true
end
function Item:getItems(recursive)
	local out = {}
	for _, it in ipairs(self.items or {}) do
		out[#out + 1] = it
		if recursive and it.items then
			for _, sub in ipairs(it:getItems(true)) do out[#out + 1] = sub end
		end
	end
	return out
end
local function put(c, item) c.items[#c.items + 1] = item; item.parent = c; return item end

local storages = {}
local sent = {}
local player = {guid = 7, id = 100007, level = 300, voc = 4, points = 60, pos = {x = 100, y = 100, z = 7}, equip = {},
	combat = false, saved = 0, texts = {}}
local backpack = newItem(2854, "backpack", nil, {})
backpack.cap = 20
local inbox = newItem(1, "inbox", nil, {})
local depot = newItem(2, "depot chest", nil, {})
player.equip[3] = backpack
backpack.parent = {player = player, slot = 3}
function player:getGuid() return self.guid end
function player:getId() return self.id end
function player:getName() return "Tester" end
function player:getLevel() return self.level end
function player:getVocation() local v = self.voc; return {getId = function() return v end} end
function player:getStorageValue(k) return storages[k] or -1 end
function player:setStorageValue(k, v) if v == -1 then storages[k] = nil else storages[k] = v end end
function player:getPosition()
	local p = {x = self.pos.x, y = self.pos.y, z = self.pos.z}
	p.sendMagicEffect = function() end
	return p
end
function player:getSlotItem(slot) return self.equip[slot] end
function player:getInbox() return inbox end
function player:getDepotChest() return depot end
function player:addItemEx(item, drop, slot)
	if self.equip[slot] then return RETURNVALUE_NOTPOSSIBLE end
	-- a two-handed weapon (slot 6) needs the other hand free, and blocks it
	local other = slot == 5 and 6 or (slot == 6 and 5 or nil)
	local o = other and self.equip[other]
	if o and (item.twoHanded or o.twoHanded) then return RETURNVALUE_BOTHHANDSNEEDTOBEFREE end
	if item.minLevel and self.level < item.minLevel then return RETURNVALUE_NOTPOSSIBLE end
	self.equip[slot] = item
	item.parent = {player = self, slot = slot}
	return RV_OK
end
function player:addItem(id, count) put(backpack, newItem(id, "rune " .. id, nil)) end
function player:isPzLocked() return false end
function player:hasCondition() return self.combat end
function player:sendTextMessage(_, text) self.texts[#self.texts + 1] = text end
function player:sendCancelMessage(text) self.texts[#self.texts + 1] = text end
function player:sendExtendedOpcode(op, buffer) sent[#sent + 1] = {op = op, msg = json.decode(buffer)} end
function player:save() self.saved = self.saved + 1; return true end
function player:registerEvent() end
function Player(id) if id == player.id then return player end end

-- the passive tree, Paragon and supports (their own files are tested elsewhere)
local presets = {}
local applied = 0
ChaosPassiveTree = {
	internal = {
		getTree = function() return tree end,
		loadPresets = function(guid)
			if not presets[guid] then return {} end
			local ids = {}
			for i, id in ipairs(presets[guid]) do ids[i] = id end
			return {{preset = 1, name = "Preset 1", nodes = ids}}
		end,
		savePreset = function(guid, preset, name, ids)
			local copy = {}
			for i, id in ipairs(ids) do copy[i] = id end
			table.sort(copy)
			presets[guid] = copy
		end,
		sendNodes = function() end, sendPoints = function() end,
		totalPoints = function(p) return p.points end
	},
	apply = function() applied = applied + 1 end,
	classKey = function() return "warrior" end,
	vocationKey = function() return nil end
}
local paragonDb = {}
ChaosParagon = {defs = {damage = {maxPoints = 40}, health = {maxPoints = 40}}, cache = {},
	totalPoints = function(level) return math.max(0, level - 1000) end,
	allocation = function(p) return ChaosParagon.cache[p:getId()] or {} end,
	save = function(guid, alloc) paragonDb[guid] = alloc end,
	sendState = function() end}
ChaosSupports = {config = {maxSpellId = 499}, names = {[10] = "Fire Wave", [20] = "Ice Strike"}}
local SP = ChaosSupports
function SP.storageKey(spellId, slot) return 7110000 + spellId * 4 + (slot or 0) end
function SP.isRune(id) return type(id) == "number" and id >= 32101 and id <= 32200 end
function SP.read(p, spellId)
	local out = {opened = false, runes = {}}
	for i = 1, 3 do
		local v = p:getStorageValue(SP.storageKey(spellId, i))
		out.runes[i] = SP.isRune(v) and v or 0
	end
	return out
end
function SP.setRune(p, spellId, slot, id) p:setStorageValue(SP.storageKey(spellId, slot), (id and id > 0) and id or -1) end
function SP.spellInfo(id) return SP.names[id] and {id = id, name = SP.names[id]} or nil end
function SP.runeName(id) return "Rune " .. id end
function SP.refreshActive() end
function SP.sendBar() end

dofile("data/scripts/chaos/loadouts.lua")
local LO = ChaosLoadouts
check(events.ChaosLoadoutsExtended and events.ChaosLoadoutsLogin and events.ChaosLoadoutsStartup, "events registered")

local function lastOf(action)
	for i = #sent, 1, -1 do
		if sent[i].op == 206 and sent[i].msg and sent[i].msg.action == action then return sent[i].msg.data end
	end
end
local function request(action, data)
	events.ChaosLoadoutsExtended.onExtendedOpcode(player, 206, (json.encode({action = action, data = data})))
end
local function countIid(iid)
	local c = 0
	for _, it in pairs(player.equip) do if it.iid == iid then c = c + 1 end end
	for _, it in ipairs(backpack:getItems(true)) do if it.iid == iid then c = c + 1 end end
	for _, it in ipairs(inbox:getItems(true)) do if it.iid == iid then c = c + 1 end end
	for _, it in ipairs(depot:getItems(true)) do if it.iid == iid then c = c + 1 end end
	return c
end
local function liveRunes()
	local c = 0
	for k, v in pairs(storages) do if k >= 7110000 and k <= 7111999 and v > 0 then c = c + 1 end end
	return c
end
local function mirrorRunes()
	local c = 0
	for k, v in pairs(storages) do if k >= 7112000 and k <= 7127999 and v > 0 then c = c + 1 end end
	return c
end

-- the live build: 12 nodes, two runes on Fire Wave, a sword (with an id), a ring and a helmet
local build = bfsPath(12)
ChaosPassiveTree.internal.savePreset(7, 1, "Preset 1", build)
SP.setRune(player, 10, 1, 32101)
SP.setRune(player, 10, 2, 32110)
local swordItem = newItem(3264, "fire sword", "1790000000001")
player:addItemEx(swordItem, false, 6)
player:addItemEx(newItem(3088, "energy ring", ""), false, 9)
player:addItemEx(newItem(3351, "steel helmet", ""), false, 1)

events.ChaosLoadoutsLogin.onLogin(player)
request("open")
local st = lastOf("state")
eq(st.limit, 4, "level 300: 4 slots"); eq(#st.slots, 6, "6 slot rows (the Pact's slot shown locked)"); eq(st.slots[5].locked, true, "slot 5 locked")
eq(st.active, 0, "nothing active"); check(st.slots[1].empty, "slot 1 empty")

request("load", {slot = 1})
has(lastOf("result").text, "empty", "load an empty slot refused")
request("save", {slot = 5, name = "x"})
has(lastOf("result").text, "level 500", "save into a locked slot refused")

request("save", {slot = 1, name = "Hunting", icon = "pvp"})
local res = lastOf("result")
eq(res.ok, true, "saved"); has(res.text, "12 passive nodes", "save text"); has(res.text, "3 items", "three items")
eq(storages[7100570], 1, "first save activates slot 1")
eq(DB[7][1].tree, C.formatNodes(build), "slot 1 holds the live tree")
eq(DB[7][1].supports, "10:32101/32110/0", "slot 1 lists the live runes")
local g = C.decodeGear(DB[7][1].gear)
eq(g[6].iid, "1790000000001", "sword by its id"); eq(g[9].id, 3051, "ring stored de-equipped"); eq(g[5].empty, true, "empty hand")

request("save", {slot = 2, name = "Bossing"})
res = lastOf("result")
eq(res.ok, true, "copy saved"); has(res.lines[1] or "", "stay with the loadout", "runes are not copied")
eq(DB[7][2].supports, "", "the copy holds no runes")
eq(storages[7100570], 1, "slot 1 stays active")

-- slot 2 is the boss build: take the sword off (the boss set uses no weapon), then go back to slot 1's tree edits
-- edit the live tree (as the passive tree window would): two more nodes, live belongs to slot 1
local more = bfsPath(14)
ChaosPassiveTree.internal.savePreset(7, 1, "Preset 1", more)

-- switch to slot 2 in a protection zone: instant and free
pzFlag = true
request("load", {slot = 2})
res = lastOf("result")
eq(res.ok, true, "switched"); has(res.text, "Bossing is active", "switch text")
eq(table.concat(presets[7], ","), C.formatNodes(build), "live tree = slot 2's")
eq(DB[7][1].tree, C.formatNodes(more), "the edited live tree parked into slot 1")
eq(storages[7100570], 2, "slot 2 active")
eq(liveRunes(), 0, "slot 2 has no runes")
eq(mirrorRunes(), 2, "the two runes are parked with slot 1")
eq(player.saved, 1, "player saved at once")
eq(storages[7100571], 1, "serial 1"); eq(DB[7][0].serial, 1, "database serial 1")
check(applied > 0, "bonuses applied")

-- cooldown
request("load", {slot = 1})
has(lastOf("result").text, "seconds", "cooldown")
storages[7100572] = os.time() - cfg.cooldownSeconds - 1

-- combat
player.combat = true
request("load", {slot = 1})
has(lastOf("result").text, "combat", "combat refused")
player.combat = false

-- out of a protection zone: a channel; moving interrupts it
pzFlag = false
request("load", {slot = 1})
eq(lastOf("cast").ms, cfg.castMs, "channel started")
check(LO.casts[player.id] ~= nil, "casting")
request("load", {slot = 1})
has(lastOf("result").text, "already", "second request while casting refused")
player.pos.x = 101
runPending()
check(LO.casts[player.id] == nil, "moved: interrupted")
eq(storages[7100570], 2, "nothing switched")
player.pos.x = 100
-- the gear of slot 1: put the sword into the backpack and wear something else meanwhile
swordItem:moveTo(backpack)
player:addItemEx(newItem(3300, "club", ""), false, 6)
request("load", {slot = 1})
fakeNow = fakeNow + 1000
runPending()
check(LO.casts[player.id] ~= nil, "still casting")
fakeNow = fakeNow + cfg.castMs
runPending()
check(LO.casts[player.id] == nil, "channel done")
res = lastOf("result")
eq(res.ok, true, "switched after the channel")
eq(table.concat(presets[7], ","), C.formatNodes(more), "slot 1's edited tree is live again (nothing lost)")
eq(liveRunes(), 2, "runes back in the sockets"); eq(mirrorRunes(), 0, "no rune left parked")
eq(player.equip[6] and player.equip[6].iid, "1790000000001", "the sword is equipped again")
eq(countIid("1790000000001"), 1, "one sword: moved, never copied")
local clubs = 0
for _, it in ipairs(backpack:getItems(true)) do if it.name == "club" then clubs = clubs + 1 end end
eq(clubs, 1, "the club went into the backpack")
eq(storages[7100571], 2, "serial 2")

-- deleting slot 2 (no runes) is fine; slot 1 is active
storages[7100572] = os.time() - cfg.cooldownSeconds - 1
pzFlag = true
-- park the runes into slot 1 by switching to slot 2, then try deleting slot 1 (inactive, holds runes)
request("load", {slot = 2})
eq(lastOf("result").ok, true, "to slot 2 again")
eq(mirrorRunes(), 2, "runes parked with slot 1")
request("delete", {slot = 1})
has(lastOf("result").text, "2 support runes", "an inactive loadout with runes cannot be deleted")
check(DB[7][1] ~= nil, "slot 1 kept")

-- missing gear and an item in the depot: slot 1 wants the sword; put it into the depot
storages[7100572] = os.time() - cfg.cooldownSeconds - 1
local s1 = player.equip[6]
if s1 then s1:moveTo(depot) else
	for _, it in ipairs(backpack:getItems(true)) do if it.iid == "1790000000001" then it:moveTo(depot) end end
end
request("open")
st = lastOf("state")
local m = st.slots[1].gear.missing[1]
check(m and m.where:find("depot") ~= nil, "the window names the depot")
request("load", {slot = 1})
res = lastOf("result")
eq(res.ok, true, "switch with a missing item still switches the build")
local joined = table.concat(res.lines, " ")
has(joined, "in your depot (Emberfall)", "missing item reported with its place")
eq(countIid("1790000000001"), 1, "still one sword (left in the depot)")
-- O316: the stash is the storage; a sword that lies there is named "in your stash" (the depot is empty by then)
do
	local keepDepot = depot.items
	depot.items = {}
	ChaosStash = {staffFind = function() return {count = 0, tab = 0}, {{id = 1, tab = 1}} end}
	request("open")
	stM = lastOf("state").slots[1].gear.missing[1]
	eq(stM and stM.where, "in your stash", "a missing item that lies in the stash is named")
	ChaosStash = nil
	depot.items = keepDepot
end

-- validation against changed tree data: slot 2's tree gets a node that left the tree and too many nodes
storages[7100572] = os.time() - cfg.cooldownSeconds - 1
DB[7][2].tree = C.formatNodes(bfsPath(80)) .. ",999999"
request("open")
st = lastOf("state")
has(table.concat(st.slots[2].warnings, " "), "Refunded for free", "the window warns before loading")
request("load", {slot = 2})
res = lastOf("result")
joined = table.concat(res.lines, " ")
has(joined, "1 node that left the tree", "unknown node refunded")
has(joined, "20 nodes over your passive points", "over the budget trimmed")
eq(#presets[7], player.points, "live tree = the points owned")
check(connected(tree, presets[7]), "trimmed live tree connected")

-- crash: the database part of a switch is written, the player save is lost
storages[7100572] = os.time() - cfg.cooldownSeconds - 1
local before = {}
for k, v in pairs(storages) do before[k] = v end
local liveBefore = table.concat(presets[7], ",")
local slot2Before = DB[7][2].tree
request("load", {slot = 1})
eq(lastOf("result").ok, true, "switch before the crash")
check(table.concat(presets[7], ",") ~= liveBefore, "live changed")
storages = before -- the storages (and items) go back to the last player save
events.ChaosLoadoutsLogin.onLogin(player)
eq(table.concat(presets[7], ","), liveBefore, "rollback: live tree as before the switch")
eq(DB[7][2].tree, slot2Before, "rollback: the parked slot as before")
eq(DB[7][0].serial, storages[7100571], "serials agree again")
has(player.texts[#player.texts], "undone", "player told")

-- rename, delete the active loadout, save-first rule
request("rename", {slot = 2, name = "Raid Night", icon = "dungeons"})
eq(DB[7][2].name, "Raid Night", "renamed"); eq(DB[7][2].icon, "dungeons", "icon")
request("delete", {slot = 2})
eq(lastOf("result").ok, true, "active loadout deleted")
eq(storages[7100570], 0, "no active loadout")
storages[7100572] = os.time() - cfg.cooldownSeconds - 1
request("load", {slot = 1})
has(lastOf("result").text, "Save your current build", "the live build is not saved anywhere: refused")

-- a two-handed weapon the set does not want blocks the shield hand: it is put away when the set's own weapon is missing
player.guid, storages, player.equip = 8, {}, {[3] = backpack}
backpack.items, depot.items, inbox.items = {}, {}, {}
ChaosPassiveTree.internal.savePreset(8, 1, "Preset 1", build)
local shield = newItem(2525, "dwarven shield", "")
local oneHand = newItem(2376, "sword", "S1")
player:addItemEx(shield, false, 5)
player:addItemEx(oneHand, false, 6)
request("save", {slot = 1, name = "Sword and board"})
request("save", {slot = 2, name = "Two hands"})
storages[7100572] = nil
request("load", {slot = 2})
eq(lastOf("result").ok, true, "to slot 2")
shield:moveTo(backpack)
oneHand:moveTo(depot)
local giant = newItem(2393, "giant sword", "G1")
giant.twoHanded = true
player:addItemEx(giant, false, 6)
request("save", {slot = 2})
storages[7100572] = os.time() - cfg.cooldownSeconds - 1
request("load", {slot = 1})
res = lastOf("result")
eq(res.ok, true, "to slot 1 with its sword in the depot")
eq(player.equip[5] and player.equip[5].name, "dwarven shield", "the shield is worn")
eq(player.equip[6], nil, "the unwanted two-handed weapon was put away")
eq(countIid("G1"), 1, "one giant sword (in the backpack)")
has(table.concat(res.lines, " "), "sword: in your depot", "the missing sword named")

-- reworked nodes (passivetree.lua refundReworked): every saved loadout loses them, and what only hung on them
dofile("data/scripts/chaos/passivetree_core.lua")
local g = player:getGuid()
local path = {2, 9, 11, 13, 61} -- a chain from the root
local savedRows = DB[g]
DB[g] = {}
DB[g][3] = {slot = 3, name = "Old", icon = "", voc = 4, tree = table.concat(path, ","), paragon = "", supports = "",
	gear = "", serial = 0, undo = "", updated = 0}
DB[g][4] = {slot = 4, name = "Untouched", icon = "", voc = 4, tree = "3,32", paragon = "", supports = "", gear = "", serial = 0,
	undo = "", updated = 0}
eq(LO.dropNodes(player, {[61] = true}), 1, "the end of the chain goes")
eq(DB[g][3].tree, "2,9,11,13", "slot 3 keeps the rest")
eq(LO.dropNodes(player, {[9] = true}), 3, "node 9 and the two behind it")
eq(DB[g][3].tree, "2", "slot 3 keeps the first")
eq(DB[g][4].tree, "3,32", "a loadout without them is not touched")
eq(LO.dropNodes(player, {}), 0, "nothing to drop")
DB[g] = savedRows

-- unknown actions and bad slots are ignored or refused
request("load", {slot = "x"})
has(lastOf("result").text, "does not exist", "bad slot")
request("nope", {})

print(string.format("loadouts_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
